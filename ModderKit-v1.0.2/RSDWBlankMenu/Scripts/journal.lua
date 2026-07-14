-- Piece journal + resurrection ("disappear -> reappear when the mod is re-enabled").
--
-- Problem: a session played WITHOUT the mod degrades placed custom pieces to vanilla
-- substitutes and the next save strips their persistence IDs permanently. Nothing can
-- prevent that (our code is not running); instead we RECOVER: while the mod is on we
-- keep a per-save sidecar journal of every placed custom piece (id + transform); at
-- world load we re-spawn any journaled piece that is missing, through the game's own
-- placement RPC (Server_SpawnBuilding by the GAME-stamped runtime index).
--
-- Rules honored (AI_HANDOFF): UObject access on the game thread only; GetFullName()
-- comparisons (wrapper == lies); no LoadAsset in hot paths; data reads on catalogue.
local M = {}
local TAG = "[RSDWBuilds/journal]"

local pieces_mod = require("pieces")
local subsystem = require("subsystem")
local assets = require("assets")

local SNAPSHOT_PERIOD_MS = 45000
local RESTORE_POLL_MS = 3000
local RESTORE_MAX_POLLS = 25      -- ~75 s budget for the world to become ready
local MATCH_DIST = 50.0           -- uu: journal entry <-> live actor same-piece radius
local BLOCKER_DIST = 25.0         -- uu: vanilla substitute detection radius (exact spot)

local restore_gen = 0
local restore_done_for_gen = -1

-- Snapshot gating — THE invariant (learned across three journal-wipe incidents):
-- the journal may only be WRITTEN in a world whose restore pass has already
-- COMPLETED. Everything earlier (main menu — which HAS a player pawn, so pawn
-- checks are useless —, mid-load, pre-restore) must never overwrite the journal:
-- it is exactly the data the restore pass is about to need.
local world_gen = 0
local restore_armed_world = -1
local restore_completed_world = -1

-- Restore runs ONCE per actual MAP LOAD, never re-armed mid-session. persistence's
-- attempt() fires on several hooks (LoadPlayerState etc.) that can also fire during
-- gameplay (autosaves); re-running restore then resurrects pieces the player just
-- demolished. world_gen bumps only in our LoadMapPre hook.

-- ---------------------------------------------------------------- helpers

local function is_valid(obj)
    if obj == nil then return false end
    if obj.IsValid then
        local ok, v = pcall(function() return obj:IsValid() end)
        return ok and v == true
    end
    return type(obj) == "userdata"
end

local function full_name(obj)
    local fn = nil
    pcall(function() fn = obj:GetFullName() end)
    return type(fn) == "string" and fn or ""
end

local function run_gt(fn)
    if ExecuteInGameThread then
        ExecuteInGameThread(function() pcall(fn) end)
    else
        pcall(fn)
    end
end

local function dist2(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx * dx + dy * dy + dz * dz
end

-- Piece lookup tables from the manifest: class token "BP_<Id>_C" -> piece.
local function class_token(piece)
    local bp = piece.bp_path or ""
    local cls = bp:match("([^%.]+)$") -- BP_<Id>_C
    if cls and cls ~= "" then return cls end
    return "BP_" .. tostring(piece.id) .. "_C"
end

local function piece_by_class()
    local map = {}
    for _, p in ipairs(pieces_mod.all()) do
        map[class_token(p)] = p
    end
    return map
end

-- ---------------------------------------------------------------- save slot

-- Best-effort save-slot key so multi-world users get separate journals.
-- Probes live persistence-ish subsystems for a slot/world name property.
local SLOT_CLASSES = { "PersistenceSubsystem", "SpudSubsystem", "DominionPersistenceSubsystem" }
local SLOT_PROPS = { "SaveSlotName", "SlotName", "CurrentSlotName", "ActiveSlotName",
    "CurrentWorldName", "WorldName", "SaveName" }

local function detect_slot()
    if not FindFirstOf then return "default" end
    for _, cls in ipairs(SLOT_CLASSES) do
        local ok, sub = pcall(FindFirstOf, cls)
        if ok and is_valid(sub) then
            for _, prop in ipairs(SLOT_PROPS) do
                local val = nil
                pcall(function()
                    local raw = sub[prop]
                    if raw ~= nil then
                        if type(raw) == "string" then
                            val = raw
                        else
                            pcall(function() val = raw:ToString() end)
                        end
                    end
                end)
                if type(val) == "string" and val ~= "" and val ~= "None" then
                    return (val:gsub("[^%w_%-]", "_"))
                end
            end
        end
    end
    return "default"
end

-- ---------------------------------------------------------------- journal file

-- CWD for UE4SS Lua is <game>\Binaries\Win64; keep journals inside the mod folder.
local function journal_path(slot)
    return "ue4ss/Mods/RSDWBlankMenu/journal_" .. tostring(slot) .. ".lua"
end

local function serialize_entries(slot, entries)
    local out = {}
    out[#out + 1] = "-- RSDWBuilds piece journal (auto-generated; delete to forget). slot=" .. slot
    out[#out + 1] = "return {"
    for _, e in ipairs(entries) do
        out[#out + 1] = string.format(
            "  { id=%q, pid=%q, x=%.2f, y=%.2f, z=%.2f, yaw=%.3f },",
            e.id, e.pid, e.x, e.y, e.z, e.yaw)
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

local function write_journal(slot, entries)
    local path = journal_path(slot)
    local fh, err = io.open(path, "w")
    if not fh then
        print(TAG .. " cannot write journal: " .. tostring(err))
        return false
    end
    fh:write(serialize_entries(slot, entries))
    fh:close()
    return true
end

local function read_journal(slot)
    local path = journal_path(slot)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    if type(src) ~= "string" or src == "" then return nil end
    local chunk = load(src, "journal", "t", {})
    if not chunk then return nil end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

-- ---------------------------------------------------------------- world scan

local foreach_building_actor -- defined below (subsystem map enumeration)

-- Enumerate live custom-piece actors -> { {piece, x, y, z, yaw, actor}, ... }
-- Primary: FindAllOf per exact BP class (guaranteed hit). The BaseBuildingActor
-- sweep is only used for blocker detection, where derived-inclusion is best-effort.
local function scan_live_pieces()
    local out = {}
    if not FindAllOf then return out end
    local seen = {}
    local function consider(actor, piece, is_substitute)
        if not is_valid(actor) then return end
        local fn = full_name(actor)
        if fn == "" or seen[fn] then return end
        if fn:find("Default__", 1, true) then return end
        seen[fn] = true
        -- Skip the build-mode ghost (first test journaled one at the origin).
        local preview = false
        pcall(function() preview = actor.bIsPreview end)
        if preview == true then return end
        local loc, rot = nil, nil
        pcall(function() loc = actor:K2_GetActorLocation() end)
        pcall(function() rot = actor:K2_GetActorRotation() end)
        if not loc then return end
        -- Near-origin actors are templates/uninitialized, never placed pieces.
        if math.abs(loc.X or 0) + math.abs(loc.Y or 0) + math.abs(loc.Z or 0) < 10.0 then return end
        out[#out + 1] = {
            piece = piece,
            actor = actor,
            substitute = is_substitute or false,
            x = loc.X or 0, y = loc.Y or 0, z = loc.Z or 0,
            yaw = (rot and rot.Yaw) or 0,
            pitch = (rot and rot.Pitch) or 0,
            roll = (rot and rot.Roll) or 0,
        }
    end
    local classes = piece_by_class()
    for cls, piece in pairs(classes) do
        local ok, list = pcall(FindAllOf, cls)
        if ok and type(list) == "table" then
            for _, actor in pairs(list) do consider(actor, piece, false) end
        end
    end
    -- DA sweep over ALL building actors: catches substitutes we converted this
    -- session (vanilla class until next reload, but BuildingPieceData -> our DA).
    -- NOTE (diag dump 2026-07-13): actor.PersistenceID reads EMPTY on every actor,
    -- even genuine custom pieces — identity must be read via BuildingPieceData.
    if foreach_building_actor then
        local pieces = pieces_mod.all()
        foreach_building_actor(function(actor)
            local da_name = nil
            pcall(function()
                local pd = actor.BuildingPieceData
                if is_valid(pd) then da_name = pd:GetFullName() end
            end)
            if type(da_name) == "string" and da_name ~= "" then
                for _, piece in ipairs(pieces) do
                    if da_name:find("%.DA_" .. piece.id .. "$") then
                        local fn = full_name(actor)
                        local is_ours = fn:find(class_token(piece), 1, true) == 1
                        consider(actor, piece, not is_ours)
                        break
                    end
                end
            end
        end)
    end
    return out
end

-- Enumerate EVERY placed building actor (vanilla included) via the world
-- BuildingSubsystem's PieceIDToBuildingPieceActor map (legacy-proven). FindAllOf
-- cannot do this: given a base class name it does NOT return derived-BP instances,
-- which is why the first convert-in-place test never found any substitute.
foreach_building_actor = function(fn)
    local sub = nil
    if FindFirstOf then pcall(function() sub = FindFirstOf("BuildingSubsystem") end) end
    if not is_valid(sub) then return false end
    local map = nil
    pcall(function() map = sub.PieceIDToBuildingPieceActor end)
    if not map or not map.ForEach then return false end
    return pcall(function()
        map:ForEach(function(_k, v)
            local actor = v
            pcall(function() actor = v:get() end)
            if is_valid(actor) then fn(actor) end
        end)
    end) == true
end

-- Any live building actor (vanilla included) near a point — blocker detection.
local function find_actor_near(x, y, z, radius)
    local best, best_d2 = nil, radius * radius
    local function consider(actor)
        local loc = nil
        pcall(function() loc = actor:K2_GetActorLocation() end)
        if loc then
            local d2 = dist2(x, y, z, loc.X or 0, loc.Y or 0, loc.Z or 0)
            if d2 <= best_d2 then best, best_d2 = actor, d2 end
        end
    end
    if not foreach_building_actor(consider) and FindAllOf then
        -- Fallback sweep (known to miss derived classes; better than nothing).
        local ok, list = pcall(FindAllOf, "BaseBuildingActor")
        if ok and type(list) == "table" then
            for _, actor in pairs(list) do
                if is_valid(actor) then consider(actor) end
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------- snapshot

local function get_player_pawn()
    local pc = nil
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and ue and ue.GetPlayerController then
        pcall(function() pc = ue.GetPlayerController() end)
        if not is_valid(pc) then pcall(function() pc = ue:GetPlayerController() end) end
    end
    if not is_valid(pc) then return nil end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not is_valid(pawn) then pcall(function() pawn = pc.AcknowledgedPawn end) end
    if not is_valid(pawn) then return nil end
    return pawn
end

function M.snapshot(reason)
    -- HARD GATE: only write in a world whose restore pass has completed. The main
    -- menu, load screens and the pre-restore window must never touch the journal.
    if restore_completed_world ~= world_gen then return end
    local live = scan_live_pieces()
    local slot = detect_slot()
    local entries = {}
    local dedup = {}
    for _, e in ipairs(live) do
        if math.abs(e.pitch) + math.abs(e.roll) > 1.0 then
            print(string.format("%s warn: %s has non-yaw rotation (pitch=%.1f roll=%.1f) — journal stores yaw only",
                TAG, e.piece.id, e.pitch, e.roll))
        end
        -- Co-located STACKED actors (an earlier double-spawn bug created these)
        -- collapse to ONE journal entry: the journal records intent, not debris.
        local key = string.format("%s:%d:%d:%d", e.piece.id,
            math.floor(e.x / 10), math.floor(e.y / 10), math.floor(e.z / 10))
        if dedup[key] then goto continue end
        dedup[key] = true
        entries[#entries + 1] = {
            id = e.piece.id,
            pid = e.piece.persistence_id or "",
            x = e.x, y = e.y, z = e.z, yaw = e.yaw,
        }
        ::continue::
    end
    if write_journal(slot, entries) then
        print(string.format("%s snapshot (%s): %d piece(s) -> journal_%s", TAG, tostring(reason), #entries, slot))
    end
end

-- ---------------------------------------------------------------- restore

local function make_transform(x, y, z, yaw_deg)
    local half = ((yaw_deg or 0) * math.pi / 180.0) * 0.5
    return {
        Rotation = { X = 0, Y = 0, Z = math.sin(half), W = math.cos(half) },
        Translation = { X = x, Y = y, Z = z },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
end

local function get_bmc()
    local pc = nil
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and ue and ue.GetPlayerController then
        pcall(function() pc = ue.GetPlayerController() end)
        if not is_valid(pc) then pcall(function() pc = ue:GetPlayerController() end) end
    end
    if not is_valid(pc) then return nil end
    local bmc = nil
    pcall(function() bmc = pc.BuildModeComponent end)
    if not is_valid(bmc) then return nil end
    return bmc
end

local function with_build_cheats(fn)
    local bsub = nil
    if FindFirstOf then pcall(function() bsub = FindFirstOf("BuildingSubsystem") end) end
    local prev = nil
    if is_valid(bsub) then
        pcall(function() prev = bsub.bCheatAlwaysAllowBuilding end)
        pcall(function() bsub.bCheatAlwaysAllowBuilding = true end)
    end
    local ok, err = pcall(fn)
    if is_valid(bsub) and prev ~= nil then
        pcall(function() bsub.bCheatAlwaysAllowBuilding = prev end)
    end
    if not ok then print(TAG .. " restore error: " .. tostring(err)) end
end

-- Runtime index of a piece's DA (game-stamped by native registration, or the Lua
-- fallback's appended slot). -1/nil = piece not registered -> cannot spawn.
local function piece_runtime_index(piece)
    local da = assets.load(piece.da_path)
    if not is_valid(da) then return nil end
    local idx = nil
    pcall(function() idx = da.BuildingPieceDataIndex end)
    if type(idx) == "number" and idx >= 0 then return idx end
    return nil
end

-- Swap the static mesh on every SM component of an actor (legacy-proven calls).
local function swap_actor_mesh(actor, mesh)
    if not is_valid(actor) or not is_valid(mesh) then return false end
    local changed = false
    local arr = nil
    pcall(function()
        local cls = StaticFindObject and StaticFindObject("/Script/Engine.StaticMeshComponent") or nil
        if cls and actor.K2_GetComponentsByClass then
            arr = actor:K2_GetComponentsByClass(cls)
        elseif cls and actor.GetComponentsByClass then
            arr = actor:GetComponentsByClass(cls)
        end
    end)
    if not arr then
        -- Fallback: many building actors expose the root mesh as .Mesh
        local comp = nil
        pcall(function() comp = actor.Mesh end)
        if is_valid(comp) and comp.SetStaticMesh then
            if pcall(function() comp:SetStaticMesh(mesh) end) then
                pcall(function() if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end end)
                changed = true
            end
        end
        return changed
    end
    local n = 0
    pcall(function() n = #arr end)
    for i = 1, n do
        local comp = nil
        pcall(function() comp = arr[i] end)
        pcall(function() comp = comp:get() end)
        if is_valid(comp) and comp.SetStaticMesh then
            if pcall(function() comp:SetStaticMesh(mesh) end) then
                pcall(function() if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end end)
                changed = true
            end
        end
    end
    return changed
end

-- Convert a standing vanilla substitute back into OUR piece, in place: stamp the
-- identity the save reads (BuildingPieceData + PersistenceID) and swap the visible
-- mesh. The building actor keeps its position/snapping/stability; the NEXT save
-- writes our pid, so the following load spawns it fully natively. Property names
-- proven by the legacy mod (configure_placed_actor). Mesh goes FIRST: a native
-- refresh on BuildingPieceData can reset visuals (legacy-documented).
local function convert_substitute(actor, piece)
    if not is_valid(actor) then return false end
    local da = assets.load(piece.da_path)
    if not is_valid(da) then return false end
    local mesh = piece.mesh_path and assets.load(piece.mesh_path) or nil
    if is_valid(mesh) then swap_actor_mesh(actor, mesh) end
    local da_set = false
    pcall(function()
        actor.BuildingPieceData = da
        da_set = true
    end)
    pcall(function() actor.PersistenceID = piece.persistence_id end)
    pcall(function() actor.StabilityValue = 1.0 end)
    if is_valid(mesh) then swap_actor_mesh(actor, mesh) end
    -- Verify the identity actually took (wrapper == lies; compare full names).
    local now = nil
    pcall(function()
        local pd = actor.BuildingPieceData
        if is_valid(pd) then now = pd:GetFullName() end
    end)
    local want = nil
    pcall(function() want = da:GetFullName() end)
    return da_set and now ~= nil and now == want
end

local function restore_missing(reason)
    local slot = detect_slot()
    local journal = read_journal(slot)

    local by_id = {}
    for _, p in ipairs(pieces_mod.all()) do by_id[p.id] = p end

    local live = scan_live_pieces()

    -- ALWAYS narrate: silent passes have hidden every bug in this system so far.
    print(string.format("%s restore pass (%s): slot=%s journal=%d live=%d",
        TAG, tostring(reason), slot, journal and #journal or 0, #live))
    for _, e in ipairs(live) do
        print(string.format("%s   live: %s [%s]%s at (%.0f, %.0f, %.0f)",
            TAG, e.piece.id, full_name(e.actor):match("^(%S+)") or "?",
            e.substitute and " SUBSTITUTE" or "", e.x, e.y, e.z))
    end

    -- FIRST: convert any degraded substitute detected by pid+wrong-class, journal
    -- or not. These count as "live" for missing-detection (prevents double-spawn)
    -- but still LOOK vanilla — hand them their identity + mesh back in place.
    local converted_in_place = 0
    for _, e in ipairs(live) do
        if e.substitute then
            local cls = full_name(e.actor):match("^(%S+)") or "?"
            if convert_substitute(e.actor, e.piece) then
                converted_in_place = converted_in_place + 1
                print(string.format("%s   %s: converted pid-carrying substitute [%s] at (%.0f, %.0f, %.0f)",
                    TAG, e.piece.id, cls, e.x, e.y, e.z))
            else
                print(string.format("%s   %s: pid-carrying substitute [%s] refused conversion at (%.0f, %.0f, %.0f)",
                    TAG, e.piece.id, cls, e.x, e.y, e.z))
            end
        end
    end

    if not journal or #journal == 0 then return converted_in_place, converted_in_place end
    -- ONE-TO-ONE matching: each live actor satisfies at most one journal entry,
    -- or N co-located duplicate entries would all match a single stacked actor
    -- (and vice versa) and mask each other.
    local used = {}
    local function live_match(entry)
        for i, e in ipairs(live) do
            if not used[i] and e.piece.id == entry.id
                and dist2(entry.x, entry.y, entry.z, e.x, e.y, e.z) <= MATCH_DIST * MATCH_DIST then
                used[i] = true
                return true
            end
        end
        return false
    end

    local missing = {}
    for _, entry in ipairs(journal) do
        if by_id[entry.id] and not live_match(entry) then missing[#missing + 1] = entry end
    end
    if #missing == 0 then
        print(string.format("%s restore pass: nothing missing (converted %d substitute(s))",
            TAG, converted_in_place))
        return converted_in_place, converted_in_place
    end

    local bmc = get_bmc()
    if not is_valid(bmc) or not bmc.Server_SpawnBuilding then
        print(TAG .. " restore: BuildModeComponent not ready — retry later")
        return 0, #missing
    end

    print(string.format("%s restore (%s): %d journaled piece(s) missing — resurrecting", TAG, tostring(reason), #missing))
    local spawned = 0
    with_build_cheats(function()
        for _, entry in ipairs(missing) do
            local piece = by_id[entry.id]
            -- PREFERRED: a vanilla piece standing at the EXACT journaled spot is the
            -- degraded substitute of OUR piece (a legit wall could never have
            -- coexisted there). Convert it back IN PLACE — identity + mesh — instead
            -- of destroy+respawn: the actor keeps its snapping/stability, and the
            -- next save writes our pid so the following load is fully native.
            local converted = false
            local blocker = find_actor_near(entry.x, entry.y, entry.z, BLOCKER_DIST)
            if is_valid(blocker) then
                local bfn = full_name(blocker)
                local ours = false
                for cls in pairs(piece_by_class()) do
                    if bfn:find(cls, 1, true) == 1 then ours = true break end
                end
                if not ours then
                    if convert_substitute(blocker, piece) then
                        converted = true
                        spawned = spawned + 1
                        print(string.format("%s   %s: converted substitute [%s] in place at (%.0f, %.0f, %.0f)",
                            TAG, entry.id, bfn:match("^(%S+)") or "?", entry.x, entry.y, entry.z))
                    else
                        print(string.format("%s   %s: substitute [%s] refused conversion — falling back to respawn",
                            TAG, entry.id, bfn:match("^(%S+)") or "?"))
                        pcall(function() blocker:K2_DestroyActor() end)
                        local recheck = find_actor_near(entry.x, entry.y, entry.z, BLOCKER_DIST)
                        if is_valid(recheck) then
                            print(TAG .. "   destroy also refused — hiding the substitute")
                            pcall(function() recheck:SetActorEnableCollision(false) end)
                            pcall(function() recheck:SetActorHiddenInGame(true) end)
                        end
                    end
                end
            end
            if not converted then
                local idx = piece_runtime_index(piece)
                if not idx then
                    print(string.format("%s   %s: DA has no runtime index — skipped", TAG, entry.id))
                else
                    local xform = make_transform(entry.x, entry.y, entry.z, entry.yaw)
                    local ok = pcall(function() bmc:Server_SpawnBuilding(idx, xform, false, {}) end)
                    if ok then
                        spawned = spawned + 1
                        print(string.format("%s   %s respawned at (%.0f, %.0f, %.0f) yaw=%.0f idx=%d",
                            TAG, entry.id, entry.x, entry.y, entry.z, entry.yaw, idx))
                    else
                        print(string.format("%s   %s: Server_SpawnBuilding FAILED at (%.0f, %.0f, %.0f)",
                            TAG, entry.id, entry.x, entry.y, entry.z))
                    end
                end
            end
        end
    end)
    return spawned + converted_in_place, #missing + converted_in_place
end

-- ---------------------------------------------------------------- scheduling

-- One restore pass per world load, once the world/pieces are actually ready:
-- subsystem populated + our DAs indexed + BuildModeComponent present.
function M.schedule_restore(reason)
    -- Once per map load: the first persistence hook after LoadMapPre arms the pass;
    -- every later hook in the same world (autosaves, player-state loads) is a no-op.
    if restore_armed_world == world_gen then return end
    restore_armed_world = world_gen
    restore_gen = restore_gen + 1
    local gen = restore_gen
    if not LoopAsync then return end
    local polls = 0
    local last_building_count = -1
    LoopAsync(RESTORE_POLL_MS, function()
        if gen ~= restore_gen then return true end
        if restore_done_for_gen == gen then return true end
        polls = polls + 1
        local done = false
        run_gt(function()
            local sub = subsystem.find()
            if not is_valid(sub) then return end
            local n = 0
            pcall(function()
                local arr = sub.NetIdToData
                if arr then n = #arr end
            end)
            if n < 200 then return end
            local any_ready = false
            for _, p in ipairs(pieces_mod.all()) do
                if piece_runtime_index(p) then any_ready = true break end
            end
            if not any_ready then return end
            if not get_player_pawn() then return end
            if not get_bmc() then return end
            -- CRITICAL (diag 2026-07-13): pawn/bmc/registration are all ready BEFORE
            -- the persistence system finishes streaming in SAVED buildings — running
            -- then sees live=0, respawns everything, and the save's own actors stream
            -- in afterwards = stacked duplicates each cycle. Wait until the placed-
            -- building count is STABLE across two consecutive polls.
            local count = 0
            foreach_building_actor(function() count = count + 1 end)
            if count ~= last_building_count then
                if last_building_count >= 0 then
                    print(string.format("%s restore: waiting for world stream-in (buildings %d -> %d)",
                        TAG, last_building_count, count))
                end
                last_building_count = count
                return
            end
            -- World + registration + player + streamed buildings all ready: run.
            restore_done_for_gen = gen
            local spawned, missing = restore_missing(reason)
            restore_completed_world = world_gen -- journaling may begin for this world
            if spawned > 0 then
                M.snapshot("post-restore")
            end
            done = true
        end)
        if not done and polls >= RESTORE_MAX_POLLS then
            -- World never became ready: journaling stays blocked this session (the
            -- safe direction — a stale journal loses nothing; a wiped one does).
            print(TAG .. " restore never became ready — journaling disabled this world")
            return true
        end
        return done
    end)
end

local snapshot_loop_installed = false

function M.install()
    -- Snapshot the OUTGOING world before a map switch (actors still alive in pre-hook),
    -- THEN bump world_gen so the next persistence hook re-arms the restore pass.
    if RegisterLoadMapPreHook then
        RegisterLoadMapPreHook(function()
            run_gt(function()
                M.snapshot("LoadMapPre")
                world_gen = world_gen + 1
            end)
        end)
    end
    -- Event-driven snapshots. Every registration logs success AND failure — the
    -- first SaveWorldState attempt failed silently for days because the path was
    -- wrong and pcall swallowed it; never again.
    local function hook_snapshot(paths, reason, delay_ms)
        if not RegisterHook then return end
        for _, path in ipairs(paths) do
            local ok, err = pcall(function()
                RegisterHook(path, function()
                    if delay_ms and LoopAsync then
                        LoopAsync(delay_ms, function()
                            run_gt(function() M.snapshot(reason) end)
                            return true -- one-shot
                        end)
                    else
                        run_gt(function() M.snapshot(reason) end)
                    end
                end)
            end)
            if ok then
                print(TAG .. " hook OK (" .. reason .. "): " .. path)
            else
                print(TAG .. " hook unavailable (" .. reason .. "): " .. path)
            end
        end
    end
    -- Save sync: journal ≡ save, so demolished pieces can never resurrect.
    hook_snapshot({
        "/Script/Dominion.PersistenceSubsystem:SaveWorldState",
        "/Script/Dominion.PersistenceSubsystem:ModifyAndSaveWorldState",
        "/Script/Dominion.PersistenceSubsystem:SavePlayerState",
        "/Script/SPUD.SpudSubsystem:SaveGame",
    }, "save", nil)
    -- Placement: journal a new piece the moment it is placed (post-RPC, actor exists).
    hook_snapshot({
        "/Script/Dominion.BuildModeComponent:Server_SpawnBuilding",
    }, "placement", 1500)
    -- Demolish: re-journal shortly AFTER the actor is gone.
    hook_snapshot({
        "/Script/Dominion.BaseBuildingActor:NotifyBuildingDeconstructed",
        "/Script/Dominion.BaseBuildingActor:BP_OnBuildingDeconstructed",
    }, "demolish", 1500)
    -- Periodic in-world snapshot (game-thread body; cheap when no pieces placed).
    if LoopAsync and not snapshot_loop_installed then
        snapshot_loop_installed = true
        LoopAsync(SNAPSHOT_PERIOD_MS, function()
            run_gt(function() M.snapshot("periodic") end)
            return false -- run forever
        end)
    end
    print(TAG .. " installed (snapshot every " .. math.floor(SNAPSHOT_PERIOD_MS / 1000) .. "s + on map change)")
end

-- Console diagnostics: journal vs mod-matched actors, PLUS a raw dump of EVERY
-- placed building actor in the world (class + pid + position) — ground truth for
-- diagnosing degradation behavior without guessing.
function M.diag()
    local slot = detect_slot()
    local journal = read_journal(slot) or {}
    local live = scan_live_pieces()
    print(string.format("%s slot=%s journal=%d live=%d gen=%d armed=%d completed=%d",
        TAG, slot, #journal, #live, world_gen, restore_armed_world, restore_completed_world))
    for _, e in ipairs(journal) do
        print(string.format("%s   journal: %s at (%.0f, %.0f, %.0f) yaw=%.0f", TAG, e.id, e.x, e.y, e.z, e.yaw))
    end
    for _, e in ipairs(live) do
        print(string.format("%s   live:    %s [%s]%s at (%.0f, %.0f, %.0f)",
            TAG, e.piece.id, full_name(e.actor):match("^(%S+)") or "?",
            e.substitute and " SUBSTITUTE" or "", e.x, e.y, e.z))
    end
    local n = 0
    local swept = foreach_building_actor(function(actor)
        n = n + 1
        local pid = ""
        pcall(function()
            local raw = actor.PersistenceID
            if type(raw) == "string" then pid = raw
            else pcall(function() pid = raw:ToString() end) end
        end)
        local loc = nil
        pcall(function() loc = actor:K2_GetActorLocation() end)
        print(string.format("%s   world[%d]: [%s] pid=%q at (%.0f, %.0f, %.0f)",
            TAG, n, full_name(actor):match("^(%S+)") or "?", tostring(pid),
            loc and loc.X or 0, loc and loc.Y or 0, loc and loc.Z or 0))
    end)
    if not swept then
        print(TAG .. "   (BuildingSubsystem actor map unavailable — no world dump)")
    end
end

function M.force_restore()
    restore_done_for_gen = -1
    local spawned, missing = restore_missing("console")
    restore_completed_world = world_gen
    print(string.format("%s manual restore: %d/%d respawned", TAG, spawned, missing))
    if spawned > 0 then M.snapshot("post-restore") end
end

return M
