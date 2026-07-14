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

-- UE4SS.log is TRUNCATED on every launch, which blinded diagnosis for days.
-- Mirror every journal line into a persistent append-only log next to the journal.
local JLOG_PATH = "ue4ss/Mods/RSDWBlankMenu/journal.log"
local function jlog(msg)
    print(msg)
    pcall(function()
        local fh = io.open(JLOG_PATH, "a")
        if fh then
            fh:write(os.date("%Y-%m-%d %H:%M:%S "), tostring(msg), string.char(10))
            fh:close()
        end
    end)
end

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
        jlog(TAG .. " cannot write journal: " .. tostring(err))
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

function M.snapshot(reason, min_expected)
    -- HARD GATE: only write in a world whose restore pass has completed. The main
    -- menu, load screens and the pre-restore window must never touch the journal.
    if restore_completed_world ~= world_gen then return end
    local live = scan_live_pieces()
    -- Post-restore floor: a restore pass that just processed N journal entries must
    -- never immediately write FEWER than N (observed once after failed conversions
    -- — the shrunken write is a wipe, not a truth; keep the journal and retry next
    -- load instead).
    if min_expected and #live < min_expected then
        jlog(string.format("%s snapshot (%s) SKIPPED: live=%d < expected=%d — journal preserved",
            TAG, tostring(reason), #live, min_expected))
        return
    end
    -- Writing ZERO pieces is only trustworthy while the building world is intact
    -- (subsystem map readable AND some building exists). During teardown/menu the
    -- map is gone or empty — a 0-write there is a wipe, not a truth.
    if #live == 0 then
        local total = 0
        local swept = foreach_building_actor(function() total = total + 1 end)
        if not swept or total == 0 then return end
    end
    local slot = detect_slot()
    local entries = {}
    local dedup = {}
    local function entry_key(id, x, y, z)
        return string.format("%s:%d:%d:%d", id,
            math.floor(x / 10), math.floor(y / 10), math.floor(z / 10))
    end
    for _, e in ipairs(live) do
        if math.abs(e.pitch) + math.abs(e.roll) > 1.0 then
            jlog(string.format("%s warn: %s has non-yaw rotation (pitch=%.1f roll=%.1f) — journal stores yaw only",
                TAG, e.piece.id, e.pitch, e.roll))
        end
        -- Co-located STACKED actors (an earlier double-spawn bug created these)
        -- collapse to ONE journal entry: the journal records intent, not debris.
        local key = entry_key(e.piece.id, e.x, e.y, e.z)
        if dedup[key] then goto continue end
        dedup[key] = true
        entries[#entries + 1] = {
            id = e.piece.id,
            pid = e.piece.persistence_id or "",
            x = e.x, y = e.y, z = e.z, yaw = e.yaw,
        }
        ::continue::
    end
    -- MERGE, don't replace (2026-07-14): pieces can vanish WITHOUT the player
    -- demolishing them (observed: stability collapse of respawned walls ~30 s after
    -- restore) — an honest scan then wipes the journal and the pieces are lost
    -- forever. Journal entries may only be REMOVED by the demolish-hook snapshot;
    -- every other snapshot keeps unmatched old entries so the next load resurrects
    -- whatever vanished.
    if reason ~= "demolish" then
        local old = read_journal(slot) or {}
        local kept = 0
        for _, o in ipairs(old) do
            if o.id and o.x and not dedup[entry_key(o.id, o.x, o.y or 0, o.z or 0)] then
                dedup[entry_key(o.id, o.x, o.y or 0, o.z or 0)] = true
                entries[#entries + 1] = o
                kept = kept + 1
            end
        end
        if kept > 0 then
            jlog(string.format("%s snapshot (%s): keeping %d journal entr%s not currently live",
                TAG, tostring(reason), kept, kept == 1 and "y" or "ies"))
        end
    end
    if write_journal(slot, entries) then
        jlog(string.format("%s snapshot (%s): %d piece(s) -> journal_%s", TAG, tostring(reason), #entries, slot))
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
    if not ok then jlog(TAG .. " restore error: " .. tostring(err)) end
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
    -- THE persistence carrier (2026-07-14): the save records a piece's identity from
    -- the ACTOR's own saved properties, not from BuildingPieceData at save time —
    -- without re-stamping the runtime index, converted pieces save as vanilla again
    -- and re-convert on every load. Our index is the GAME-assigned one (native
    -- AssetRegistry registration), so this is a genuine piece index, not the fake
    -- deferred slots the legacy mod warned about.
    local idx = nil
    pcall(function() idx = da.BuildingPieceDataIndex end)
    if type(idx) == "number" and idx >= 0 then
        pcall(function() actor.BuildingPieceDataIndex = idx end)
    end
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

local function is_ours_native(actor)
    local bfn = full_name(actor)
    for cls in pairs(piece_by_class()) do
        if bfn:find(cls, 1, true) == 1 then return true end
    end
    return false
end

local function get_pc()
    local pc = nil
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and ue and ue.GetPlayerController then
        pcall(function() pc = ue.GetPlayerController() end)
        if not is_valid(pc) then pcall(function() pc = ue:GetPlayerController() end) end
    end
    return pc
end

local VOID_DEPTH = 50000.0 -- uu below the original spot; far outside any playspace

local function kill_attempt(actor, pc)
    -- DO NOT use ApplyDamage here: with domSetCanDamageBuildings it half-works —
    -- it destroys the wall's SECTIONS (collision, structure) but leaves the actor
    -- alive as a walk-through husk (observed 2026-07-14). Instead: TELEPORT the
    -- substitute into the void. SetActorLocation is a plain safe AActor call and
    -- cannot half-fail; a buried wall has no supports, so the game's stability
    -- system disposes of it natively — and even if it lingers, it is invisible,
    -- intangible and harmless. Plain destroy attempted as a bonus.
    pcall(function()
        local loc = actor:K2_GetActorLocation()
        actor:K2_SetActorLocation(
            { X = loc.X, Y = loc.Y, Z = (loc.Z or 0) - VOID_DEPTH },
            false, {}, true)
    end)
    pcall(function() actor:K2_DestroyActor() end)
end

-- A kill is successful if the actor is gone OR no longer anywhere near its spot.
local function kill_succeeded(actor, x, y, z)
    if not is_valid(actor) or full_name(actor) == "" then return true end
    local loc = nil
    pcall(function() loc = actor:K2_GetActorLocation() end)
    if not loc then return true end
    return dist2(x, y, z, loc.X or 0, loc.Y or 0, loc.Z or 0) > (VOID_DEPTH * 0.5) ^ 2
end

local function restore_missing(reason)
    local slot = detect_slot()
    local journal = read_journal(slot)

    local by_id = {}
    for _, p in ipairs(pieces_mod.all()) do by_id[p.id] = p end

    local live = scan_live_pieces()

    -- ALWAYS narrate: silent passes have hidden every bug in this system so far.
    jlog(string.format("%s restore pass (%s): slot=%s journal=%d live=%d",
        TAG, tostring(reason), slot, journal and #journal or 0, #live))
    for _, e in ipairs(live) do
        jlog(string.format("%s   live: %s [%s]%s at (%.0f, %.0f, %.0f)",
            TAG, e.piece.id, full_name(e.actor):match("^(%S+)") or "?",
            e.substitute and " SUBSTITUTE" or "", e.x, e.y, e.z))
    end

    -- NATIVE REPLACEMENT (2026-07-14): in-place conversion (stamping BuildingPieceData
    -- + index + mesh) looks right but does NOT persist — the save derives a piece's
    -- identity from the actor's CLASS, so converted substitutes save as vanilla and
    -- re-convert on every load. Seamless = kill the substitute through a legitimate
    -- channel and respawn a REAL piece via Server_SpawnBuilding (native spawns are
    -- proven to persist). Two phases: kill attempts now, verify + spawn ~2.5 s later.
    if not journal or #journal == 0 then
        jlog(TAG .. " restore pass: journal empty — nothing to do")
        return 0, 0
    end

    -- ONE-TO-ONE matching against NATIVE actors only (substitute-flagged actors are
    -- replace candidates, not proof of life).
    local used = {}
    local function native_match(entry)
        for i, e in ipairs(live) do
            if not used[i] and not e.substitute and e.piece.id == entry.id
                and dist2(entry.x, entry.y, entry.z, e.x, e.y, e.z) <= MATCH_DIST * MATCH_DIST then
                used[i] = true
                return true
            end
        end
        return false
    end

    local missing = {}
    for _, entry in ipairs(journal) do
        if by_id[entry.id] and not native_match(entry) then missing[#missing + 1] = entry end
    end
    if #missing == 0 then
        jlog(TAG .. " restore pass: all journaled pieces are native — nothing to do")
        return 0, 0
    end

    jlog(string.format("%s restore (%s): %d journaled piece(s) not native — replacing", TAG, tostring(reason), #missing))

    -- Phase A: attempt to remove each blocking substitute (engine damage via the
    -- game's own building-damage cheat, then actor destroy). All pcall'd;
    -- effectiveness is verified in phase B, never assumed.
    local pc = get_pc()
    local kills = {} -- entry -> actor ref, for direct liveness verification in phase B
    for _, entry in ipairs(missing) do
        local blocker = find_actor_near(entry.x, entry.y, entry.z, BLOCKER_DIST)
        if is_valid(blocker) and not is_ours_native(blocker) then
            jlog(string.format("%s   %s: killing substitute [%s] at (%.0f, %.0f, %.0f)",
                TAG, entry.id, full_name(blocker):match("^(%S+)") or "?", entry.x, entry.y, entry.z))
            kills[entry] = blocker
            kill_attempt(blocker, pc)
        end
    end

    -- Phase B: verify the kills, then spawn REAL pieces where the ground is clear.
    -- Where a substitute survived every channel, fall back to in-place conversion
    -- (correct for this session; re-converts next load — degraded but functional).
    local entries = missing
    if LoopAsync then
        LoopAsync(2500, function()
            run_gt(function()
                local spawned, fallback = 0, 0
                local bmc = get_bmc()
                with_build_cheats(function()
                    for _, entry in ipairs(entries) do
                        local piece = by_id[entry.id]
                        -- Kill success = actor gone OR teleported far from its spot;
                        -- then a fresh positional sweep for anything else standing.
                        local blocker = kills[entry]
                        if blocker ~= nil and kill_succeeded(blocker, entry.x, entry.y, entry.z) then
                            blocker = nil
                        end
                        if blocker == nil then
                            blocker = find_actor_near(entry.x, entry.y, entry.z, BLOCKER_DIST)
                        end
                        if is_valid(blocker) and not is_ours_native(blocker) then
                            fallback = fallback + 1
                            jlog(string.format("%s   %s: substitute SURVIVED all kill channels [%s] — converting in place",
                                TAG, entry.id, full_name(blocker):match("^(%S+)") or "?"))
                            convert_substitute(blocker, piece)
                        else
                            local idx = piece_runtime_index(piece)
                            if not idx then
                                jlog(string.format("%s   %s: DA has no runtime index — skipped", TAG, entry.id))
                            elseif is_valid(bmc) and bmc.Server_SpawnBuilding then
                                local xform = make_transform(entry.x, entry.y, entry.z, entry.yaw)
                                local ok = pcall(function() bmc:Server_SpawnBuilding(idx, xform, false, {}) end)
                                if ok then
                                    spawned = spawned + 1
                                    jlog(string.format("%s   %s: NATIVE respawn at (%.0f, %.0f, %.0f) yaw=%.0f idx=%d",
                                        TAG, entry.id, entry.x, entry.y, entry.z, entry.yaw, idx))
                                else
                                    jlog(string.format("%s   %s: Server_SpawnBuilding FAILED at (%.0f, %.0f, %.0f)",
                                        TAG, entry.id, entry.x, entry.y, entry.z))
                                end
                            end
                        end
                    end
                end)
                jlog(string.format("%s replace complete: %d native respawn(s), %d conversion fallback(s)",
                    TAG, spawned, fallback))
                M.snapshot("post-restore", #entries)
                -- Anti-collapse (2026-07-14): transform-spawned walls can fail the
                -- stability evaluation and get demolished by the game ~30 s later
                -- (observed: 2 natives gone between two snapshots). Stamp full
                -- stability on each respawned piece (legacy-proven property).
                if spawned > 0 and LoopAsync then
                    LoopAsync(1500, function()
                        run_gt(function()
                            local stamped = 0
                            for _, le in ipairs(scan_live_pieces()) do
                                if not le.substitute then
                                    if pcall(function() le.actor.StabilityValue = 1.0 end) then
                                        stamped = stamped + 1
                                    end
                                end
                            end
                            jlog(string.format("%s stability stamped on %d piece(s)", TAG, stamped))
                        end)
                        return true
                    end)
                end
            end)
            return true -- one-shot
        end)
    end
    return #missing, #missing
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
                    jlog(string.format("%s restore: waiting for world stream-in (buildings %d -> %d)",
                        TAG, last_building_count, count))
                end
                last_building_count = count
                return
            end
            -- World + registration + player + streamed buildings all ready: run.
            restore_done_for_gen = gen
            local spawned, missing = restore_missing(reason)
            restore_completed_world = world_gen -- journaling may begin for this world
            -- (phase B of the replace flow owns the post-restore snapshot)
            -- Twin sweep EVERY load: substitute records are immortal (teleport moves
            -- the actor, not the record — it respawns at its original transform each
            -- load), and when our pieces are healthy the replace flow never fires.
            -- Sweep any vanilla actor overlapping a native piece into the void.
            pcall(function() M.cleanup_twins() end)
            done = true
        end)
        if not done and polls >= RESTORE_MAX_POLLS then
            -- World never became ready: journaling stays blocked this session (the
            -- safe direction — a stale journal loses nothing; a wiped one does).
            jlog(TAG .. " restore never became ready — journaling disabled this world")
            return true
        end
        return done
    end)
end

local snapshot_loop_installed = false

function M.install()
    -- Map-transition hook: ONLY bumps world_gen. It must NOT snapshot: on quit-to-
    -- menu the world's actors are torn down BEFORE this hook fires, so an exit
    -- snapshot reads 0 live pieces and wipes the journal (the final wipe path found
    -- 2026-07-14). Journal writes are event-driven (placement/demolish/save) +
    -- periodic; save-hooks keep journal ≡ save, which is the only sync that matters.
    if RegisterLoadMapPreHook then
        RegisterLoadMapPreHook(function()
            run_gt(function()
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
                jlog(TAG .. " hook OK (" .. reason .. "): " .. path)
            else
                jlog(TAG .. " hook unavailable (" .. reason .. "): " .. path)
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
        -- Twin PATROL (2026-07-14): substitute records live in STREAMED world cells —
        -- they materialize only when the player approaches, long after the one-shot
        -- load-time sweep ran. Patrol continuously; a twin dies within ~15 s of its
        -- cell streaming in. Gated to post-restore worlds by cleanup's own scan.
        LoopAsync(15000, function()
            if restore_completed_world == world_gen then
                run_gt(function() M.cleanup_twins(true) end)
            end
            return false -- run forever
        end)
    end
    jlog(TAG .. " installed (snapshot every " .. math.floor(SNAPSHOT_PERIOD_MS / 1000) .. "s + on map change)")
end

-- Console diagnostics: journal vs mod-matched actors, PLUS a raw dump of EVERY
-- placed building actor in the world (class + pid + position) — ground truth for
-- diagnosing degradation behavior without guessing.
function M.diag()
    local slot = detect_slot()
    local journal = read_journal(slot) or {}
    local live = scan_live_pieces()
    jlog(string.format("%s slot=%s journal=%d live=%d gen=%d armed=%d completed=%d",
        TAG, slot, #journal, #live, world_gen, restore_armed_world, restore_completed_world))
    for _, e in ipairs(journal) do
        jlog(string.format("%s   journal: %s at (%.0f, %.0f, %.0f) yaw=%.0f", TAG, e.id, e.x, e.y, e.z, e.yaw))
    end
    for _, e in ipairs(live) do
        jlog(string.format("%s   live:    %s [%s]%s at (%.0f, %.0f, %.0f)",
            TAG, e.piece.id, full_name(e.actor):match("^(%S+)") or "?",
            e.substitute and " SUBSTITUTE" or "", e.x, e.y, e.z))
    end
    local n = 0
    local swept = foreach_building_actor(function(actor)
        n = n + 1
        local idx, da_name = nil, ""
        pcall(function() idx = actor.BuildingPieceDataIndex end)
        pcall(function()
            local pd = actor.BuildingPieceData
            if is_valid(pd) then da_name = pd:GetFullName():match("([^%.]+)$") or "" end
        end)
        local loc = nil
        pcall(function() loc = actor:K2_GetActorLocation() end)
        jlog(string.format("%s   world[%d]: [%s] idx=%s da=%s at (%.0f, %.0f, %.0f)",
            TAG, n, full_name(actor):match("^(%S+)") or "?", tostring(idx), da_name,
            loc and loc.X or 0, loc and loc.Y or 0, loc and loc.Z or 0))
    end)
    if not swept then
        jlog(TAG .. "   (BuildingSubsystem actor map unavailable — no world dump)")
    end
end

-- One-shot cleanup: kill every non-mod building actor standing right on top of a
-- NATIVE custom piece — the vanilla "twins" left behind by earlier replace cycles.
function M.cleanup_twins(quiet)
    local live = scan_live_pieces()
    local pc = get_pc()
    local targets = {}
    for _, e in ipairs(live) do
        if not e.substitute then
            local blocker = find_actor_near(e.x, e.y, e.z, BLOCKER_DIST)
            if is_valid(blocker) and not is_ours_native(blocker) then
                targets[#targets + 1] = { e = e, actor = blocker }
            end
        end
    end
    if #targets == 0 then
        if not quiet then
            jlog(TAG .. " cleanup: no vanilla twins found next to native pieces")
        end
        return
    end
    for _, t in ipairs(targets) do
        jlog(string.format("%s cleanup: killing twin [%s] at (%.0f, %.0f, %.0f)",
            TAG, full_name(t.actor):match("^(%S+)") or "?", t.e.x, t.e.y, t.e.z))
        kill_attempt(t.actor, pc)
    end
    if LoopAsync then
        LoopAsync(2500, function()
            run_gt(function()
                local dead, alive = 0, 0
                for _, t in ipairs(targets) do
                    if kill_succeeded(t.actor, t.e.x, t.e.y, t.e.z) then dead = dead + 1
                    else alive = alive + 1 end
                end
                jlog(string.format("%s cleanup verdict: %d twin(s) removed, %d SURVIVED", TAG, dead, alive))
            end)
            return true
        end)
    end
end

-- Runtime reflection dump: list every UFunction on the building-related classes.
-- Purpose: find the game's REAL demolish/deconstruct entry point instead of
-- guessing names from binary strings (destroy/damage/teleport all fail to remove
-- the persistent building RECORD — only the game's own demolish flow can).
function M.dump_funcs()
    local subjects = {}
    local bmc = get_bmc()
    if is_valid(bmc) then subjects["BuildModeComponent"] = bmc end
    if FindFirstOf then
        for _, cls in ipairs({ "BuildingSubsystem", "BuildingPieceSubsystem", "PersistenceSubsystem" }) do
            local ok, obj = pcall(FindFirstOf, cls)
            if ok and is_valid(obj) then subjects[cls] = obj end
        end
    end
    foreach_building_actor(function(actor)
        if not subjects["<building actor>"] then subjects["<building actor>"] = actor end
    end)
    for label, obj in pairs(subjects) do
        local cls = nil
        pcall(function() cls = obj:GetClass() end)
        if is_valid(cls) then
            jlog(string.format("%s === functions of %s [%s] ===", TAG, label, full_name(cls):match("^(%S+ %S+)") or "?"))
            local count = 0
            local ok = pcall(function()
                local c = cls
                while is_valid(c) do
                    c:ForEachFunction(function(fn)
                        local name = nil
                        pcall(function() name = fn:GetFName():ToString() end)
                        if name then
                            count = count + 1
                            jlog(TAG .. "   fn: " .. name)
                        end
                        return false
                    end)
                    local parent = nil
                    pcall(function() parent = c:GetSuperStruct() end)
                    if not is_valid(parent) or full_name(parent) == full_name(c) then break end
                    local pname = full_name(parent)
                    -- stop at engine base classes; game code is what we want
                    if pname:find("/Script/Engine.") or pname:find("/Script/CoreUObject.") then break end
                    c = parent
                end
            end)
            if not ok or count == 0 then
                jlog(TAG .. "   (ForEachFunction unavailable or no functions enumerated)")
            end
        end
    end
    jlog(TAG .. " dump complete -> journal.log")
end

function M.force_restore()
    restore_done_for_gen = -1
    local spawned, missing = restore_missing("console")
    restore_completed_world = world_gen
    jlog(string.format("%s manual restore: %d/%d respawned", TAG, spawned, missing))
    if spawned > 0 then M.snapshot("post-restore") end
end

return M
