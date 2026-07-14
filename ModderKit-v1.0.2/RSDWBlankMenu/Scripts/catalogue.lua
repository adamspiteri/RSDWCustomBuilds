-- Runtime catalogue binding for pak-first custom pieces.
--
-- HARD RULE: data reads only. NEVER call catalogue UFunctions from Lua
-- (FindIndexForPieceData / FindPieceDataForIndex hard-crash with a native access
-- violation — documented pitfall, re-confirmed 2026-07-04).
--
-- Why this module exists: the pak catalogue override loads fine (AllPiecesInCatalogue
-- grows, the vanilla menu shows the piece), but the game's own registration pass only
-- assigns BuildingPieceDataIndex to DAs discovered via the AssetRegistry — which does
-- not include pak-only DAs. Index -1 → default stability profile → permanently
-- "Unstable". So at world load we verify our persistence ID is really in the loaded
-- catalogue and, only then, stamp the DA index + subsystem index map ourselves.
local M = {}
local TAG = "[BlankMenu/catalogue]"

local subsystem = require("subsystem")
local assets = require("assets")
local pieces_mod = require("pieces")

local CAT_PKG = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/DA_BuildPieceCatalogue_Default"
local CAT_OBJ = CAT_PKG .. ".DA_BuildPieceCatalogue_Default"

local bind_gen = 0

local function is_valid(obj)
    if obj == nil then return false end
    if obj.IsValid then
        local ok, v = pcall(function() return obj:IsValid() end)
        return ok and v == true
    end
    return type(obj) == "userdata"
end

local function load_object(path)
    return assets.load(path)
end

local function unwrap_remote(v)
    if v == nil then return nil end
    if type(v) == "userdata" then
        local ok, got = pcall(function() return v:get() end)
        if ok and got ~= nil then return got end
        ok, got = pcall(function() return v:Get() end)
        if ok and got ~= nil then return got end
    end
    return v
end

local function as_string(v)
    v = unwrap_remote(v)
    if type(v) == "string" and v ~= "" then return v end
    if v ~= nil and type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    return nil
end

local function tmap_find(map, key)
    if not map or not map.Find then return nil end
    local val = nil
    pcall(function() val = map:Find(key) end)
    val = unwrap_remote(val)
    if val ~= nil and is_valid(val) then return val end
    if type(val) == "userdata" then return val end
    return nil
end

local function tmap_add(map, key, val)
    if not map then return false end
    return pcall(function() map:Add(key, val) end)
end

local function bump_num_building_piece_datas(sub, idx)
    if not sub or type(idx) ~= "number" or idx < 0 then return end
    pcall(function()
        local num = sub.NumBuildingPieceDatas or 0
        if type(num) ~= "number" or num <= idx then
            sub.NumBuildingPieceDatas = idx + 1
        end
    end)
end

local function load_catalogue()
    if LoadAsset then
        pcall(function() LoadAsset(CAT_PKG) end)
        pcall(function() LoadAsset(CAT_OBJ) end)
    end
    if StaticFindObject then
        local ok, cat = pcall(StaticFindObject, CAT_OBJ)
        if ok and is_valid(cat) then return cat end
    end
    return load_object(CAT_OBJ)
end

local function tarray_len(arr)
    if type(arr) ~= "userdata" and type(arr) ~= "table" then return 0 end
    local n = 0
    pcall(function() n = #arr end)
    if n == 0 then pcall(function() if arr.Num then n = arr:Num() end end) end
    return n or 0
end

local function tarray_get(arr, i)
    local v = nil
    pcall(function() v = arr[i] end)
    return v
end

-- Total entries our own build wrote into the catalogue (max piece index + 1). Pieces are
-- always appended at the end, so a loaded catalogue with exactly this many entries can
-- only be OUR override (vanilla has fewer; a game update forces a rebuild anyway).
local function expected_total()
    local max_idx = nil
    for _, p in ipairs(pieces_mod.all()) do
        local i = tonumber(p.catalogue_index)
        if i and (not max_idx or i > max_idx) then max_idx = i end
    end
    if max_idx then return max_idx + 1 end
    return nil
end

-- Canonical UE4SS container iteration (indexing TArray<FString> elements directly has
-- proven unreliable — returns nil). ForEach hands each element as a wrapped param.
local function scan_all_pieces(all, pid)
    local found = nil
    pcall(function()
        all:ForEach(function(i, elem)
            if found ~= nil then return end
            local v = elem
            pcall(function() v = elem:get() end)
            if as_string(v) == pid then found = i - 1 end
        end)
    end)
    return found
end

-- Find the runtime index of a persistence ID in AllPiecesInCatalogue (pure data reads).
-- Three strategies, strongest first; "how" says which one succeeded.
local function find_pid_index(cat, pid, hint_idx)
    if not is_valid(cat) or type(pid) ~= "string" or pid == "" then return nil, nil, nil end
    local all = nil
    pcall(function() all = cat.AllPiecesInCatalogue end)
    if not all then return nil, nil, nil end
    local n = tarray_len(all)
    if n == 0 then return nil, 0, nil end

    -- 1) ForEach scan: authoritative, self-heals a stale manifest index.
    local idx = scan_all_pieces(all, pid)
    if idx ~= nil then return idx, n, "scan" end

    -- 2) Direct indexed read at the hint (1-based, then 0-based).
    if type(hint_idx) == "number" and hint_idx >= 0 and hint_idx < n then
        for _, lua_i in ipairs({ hint_idx + 1, hint_idx }) do
            if as_string(tarray_get(all, lua_i)) == pid then
                return hint_idx, n, "hint"
            end
        end
    end

    -- 3) Length match: elements unreadable from Lua, but the array size equals exactly
    -- what OUR build wrote (vanilla is smaller) → the loaded catalogue is ours and the
    -- build-time index is correct by construction.
    local expect = expected_total()
    if expect and n == expect and type(hint_idx) == "number" and hint_idx >= 0 and hint_idx < n then
        return hint_idx, n, "length"
    end

    return nil, n, nil
end

-- One-shot state snapshot: everything needed to decide native vs fallback. Reads only.
function M.inspect(piece, da)
    local manifest_idx = tonumber(piece and piece.catalogue_index)
    local cat = load_catalogue()
    local runtime_idx, all_len, how = nil, nil, nil
    if is_valid(cat) and piece and piece.persistence_id then
        runtime_idx, all_len, how = find_pid_index(cat, piece.persistence_id, manifest_idx)
    end
    local da_idx = nil
    if is_valid(da) then
        pcall(function() da_idx = da.BuildingPieceDataIndex end)
    end
    return {
        cat_loaded = is_valid(cat),
        all_len = all_len,
        manifest_idx = manifest_idx,
        runtime_idx = runtime_idx,
        how = how,
        da_idx = da_idx,
        -- Verified = our persistence ID is really in the LOADED catalogue → the mod
        -- override is active and runtime_idx is authoritative.
        verified = runtime_idx ~= nil,
    }, cat
end

-- The game's runtime BuildingPieceDataIndex space is assigned in REGISTRATION order and
-- does NOT match AllPiecesInCatalogue positions. Empirically: stamping our catalogue
-- position (755) mislabeled the piece as the vanilla piece already at runtime slot 755
-- ("Armadyl Banner 02" name/cost/XP, failed spawn). A new native piece must therefore be
-- appended to the END of the runtime index space. Server_SpawnBuilding spawns BY index,
-- so the index must resolve on UBuildingPieceSubsystem (SDK: NumBuildingPieceDatas,
-- BuildingPieceDataIndexToBuildingPieceData, PersistenceIDToBuildingPieceDataMap).
local MIN_SANE = 200 -- some structure must show this many vanilla pieces before we allocate

-- Per-instance snapshot of every runtime structure that could hold the index registry.
-- Live 0.12 truth (from bind[] dumps): NumBuildingPieceDatas does NOT exist (SDK stale),
-- the index map is empty, and NetIdToData holds all ~772 registered piece DAs —
-- BuildingPieceDataIndex == position in NetIdToData (vanilla banner sits at 755).
local function subsystem_stats(live)
    local s = { name = "?", num = nil, map_count = nil, map_max = nil, netids = nil }
    pcall(function() s.name = live:GetFullName() end)
    pcall(function()
        local v = live.NumBuildingPieceDatas
        if type(v) == "number" then s.num = v end
    end)
    local m = nil
    pcall(function() m = live.BuildingPieceDataIndexToBuildingPieceData end)
    if m and m.ForEach then
        local count, maxk = 0, -1
        pcall(function()
            m:ForEach(function(k, _v)
                local kk = k
                pcall(function() kk = k:get() end)
                kk = tonumber(kk)
                if kk then
                    count = count + 1
                    if kk > maxk then maxk = kk end
                end
            end)
        end)
        s.map_count = count
        s.map_max = maxk
    end
    local arr = nil
    pcall(function() arr = live.NetIdToData end)
    if arr then s.netids = tarray_len(arr) end
    return s
end

function M.dump_subsystems(prefix)
    local lives = subsystem.collect_all(subsystem.find())
    if #lives == 0 then
        print(TAG .. " " .. tostring(prefix) .. ": no live BuildingPieceSubsystem found")
        return
    end
    for _, live in ipairs(lives) do
        local s = subsystem_stats(live)
        print(string.format("%s %s: %s Num=%s idxMapCount=%s idxMapMax=%s NetIdToData=%s",
            TAG, tostring(prefix), tostring(s.name), tostring(s.num),
            tostring(s.map_count), tostring(s.map_max), tostring(s.netids)))
    end
end

local warned_append_failed = false

-- UE4SS wrapper equality (`a == b`) is unreliable between separately-obtained
-- references to the same UObject; compare by full name instead.
local function same_object(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    local fa, fb = nil, nil
    pcall(function() fa = a:GetFullName() end)
    pcall(function() fb = b:GetFullName() end)
    return type(fa) == "string" and fa ~= "" and fa == fb
end

-- Verified-only writes: allocate a fresh runtime index for the DA and register it in the
-- subsystem index map so stability/cost/name lookups resolve to OUR data (never a vanilla
-- slot). Called at world load (bind pass) and before F7 native select.
function M.prepare_for_build(piece, da, quiet)
    if not piece or not is_valid(da) then return false end
    local snap = M.inspect(piece, da)
    local ready = false

    if snap.verified then
        -- Pick the live BuildingPieceSubsystem whose NetIdToData is populated (the real
        -- runtime registry: BuildingPieceDataIndex == position in this array, 0-based).
        local lives = subsystem.collect_all(subsystem.find())
        local primary, arr, n = nil, nil, 0
        for _, live in ipairs(lives) do
            local a = nil
            pcall(function() a = live.NetIdToData end)
            local len = a and tarray_len(a) or 0
            if len > n then primary, arr, n = live, a, len end
        end

        if primary and n >= MIN_SANE then
            local found_idx = nil
            -- Game-NATIVE registration first (premade AssetRegistry shipped with the
            -- mod): the game's own AssetManager scan registers our DA like a vanilla
            -- piece and stamps BuildingPieceDataIndex ANYWHERE in the array (observed:
            -- 577/578 of 774), not at the tail. Trust but verify NetIdToData[idx] is
            -- really our DA — appending again would register the piece twice.
            local stamped = nil
            pcall(function() stamped = da.BuildingPieceDataIndex end)
            if type(stamped) == "number" and stamped >= 0 and stamped < n then
                local at = unwrap_remote(tarray_get(arr, stamped + 1))
                if same_object(at, da) then
                    found_idx = stamped
                end
            end
            -- Otherwise: appended by US earlier this session? Wrapper equality is
            -- unreliable, so scan the array tail by full name (our appends can only
            -- live at the very end).
            if found_idx == nil then
                for i = n, math.max(1, n - 15), -1 do
                    local at = unwrap_remote(tarray_get(arr, i))
                    if same_object(at, da) then
                        found_idx = i - 1 -- 0-based
                        break
                    end
                end
            end
            if found_idx ~= nil then
                if type(snap.da_idx) ~= "number" or snap.da_idx ~= found_idx then
                    pcall(function() da.BuildingPieceDataIndex = found_idx end)
                    pcall(function() snap.da_idx = da.BuildingPieceDataIndex end)
                end
                ready = type(snap.da_idx) == "number" and snap.da_idx >= 0
            end

            if not ready then
                -- Append at the end: NetIdToData[n] (0-based) = our DA.
                local appended = false
                pcall(function()
                    arr[n + 1] = da -- UE4SS arrays are 1-based; n+1 = one past the end
                end)
                local back = unwrap_remote(tarray_get(arr, n + 1))
                if tarray_len(arr) == n + 1 and same_object(back, da) then
                    appended = true
                end

                if appended then
                    local idx = n -- 0-based runtime index
                    pcall(function() da.BuildingPieceDataIndex = idx end)
                    -- Reverse map (data -> netid), used by the game for replication/lookups.
                    pcall(function()
                        local dm = primary.DataToNetIdMap
                        if dm and dm.Add then dm:Add(da, { NetId = idx }) end
                    end)
                    -- Best-effort on legacy-named maps (harmless if absent in live build).
                    pcall(function()
                        local m = primary.BuildingPieceDataIndexToBuildingPieceData
                        if m and m.Add then m:Add(idx, da) end
                    end)
                    pcall(function()
                        local pm = primary.PersistenceIDToBuildingPieceDataMap
                        if pm and pm.Add and piece.persistence_id then pm:Add(piece.persistence_id, da) end
                    end)
                    bump_num_building_piece_datas(primary, idx)
                    pcall(function() snap.da_idx = da.BuildingPieceDataIndex end)
                    ready = type(snap.da_idx) == "number" and snap.da_idx >= 0
                    if ready then
                        print(TAG .. " registered " .. tostring(piece.id) .. " at NetId slot " .. tostring(idx)
                            .. " (NetIdToData " .. tostring(n) .. " -> " .. tostring(tarray_len(arr))
                            .. "; catalogue pos " .. tostring(snap.runtime_idx) .. " is persistence-only)")
                    end
                elseif not warned_append_failed then
                    warned_append_failed = true
                    print(TAG .. " warn: NetIdToData append failed (len=" .. tostring(tarray_len(arr))
                        .. ") — UE4SS array append unsupported? Native placement unavailable this session.")
                end
            end
        elseif not quiet then
            print(TAG .. " not ready: no live subsystem shows a populated NetIdToData ("
                .. tostring(n) .. " < " .. MIN_SANE .. ")")
        end
    end

    if not quiet then
        print(string.format(
            "%s prepare %s catalogue_pos=%s (via %s) da_idx=%s all_len=%s verified=%s ready=%s",
            TAG, tostring(piece.id), tostring(snap.runtime_idx), tostring(snap.how),
            tostring(snap.da_idx), tostring(snap.all_len), tostring(snap.verified), tostring(ready)))
        if not snap.verified and snap.all_len then
            print(TAG .. " warn: persistence ID not in loaded catalogue (" .. tostring(snap.all_len)
                .. " entries) — rebuild Build-Piece.bat against current game + full restart")
        end
    end

    return ready
end

-- Strict gate for the native OnPieceSelected(custom DA) path.
function M.catalogue_resolves(piece, da)
    if not piece or not is_valid(da) then return false end
    return M.prepare_for_build(piece, da) == true
end

-- The vanilla build menu only lists UNLOCKED pieces; a fresh mod piece has never been
-- "learned" by the save, so unlock it explicitly once it is bound.
local function unlock_piece(da)
    local pc = nil
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and ue and ue.GetPlayerController then
        pcall(function() pc = ue.GetPlayerController() end)
        if not is_valid(pc) then
            pcall(function() pc = ue:GetPlayerController() end)
        end
    end
    if not is_valid(pc) then return false end
    local prog = nil
    pcall(function() prog = pc.ProgressComponent end)
    if is_valid(prog) and prog.UnlockBuildings then
        local ok = pcall(function() prog:UnlockBuildings({ da }) end)
        return ok
    end
    return false
end

local function bind_pass(pieces_list, load_da)
    local pending = 0
    for _, piece in ipairs(pieces_list) do
        if piece.native_placement and piece.persistence_id then
            local da = load_da(piece.da_path)
            if is_valid(da) then
                local was_idx = nil
                pcall(function() was_idx = da.BuildingPieceDataIndex end)
                local already = type(was_idx) == "number" and was_idx >= 0
                if M.prepare_for_build(piece, da, true) then
                    unlock_piece(da)
                    if not already then
                        local now_idx = nil
                        pcall(function() now_idx = da.BuildingPieceDataIndex end)
                        print(TAG .. " bound " .. piece.id .. ": runtime slot " .. tostring(now_idx)
                            .. " (vanilla menu placement + stability active, unlocked)")
                    end
                else
                    pending = pending + 1
                end
            else
                pending = pending + 1
            end
        end
    end
    return pending
end

-- World-load binding: retries a few times because the live subsystem and pak assets
-- come up at different points during load. Cheap no-op once everything is bound.
function M.schedule_bind(pieces_list, load_da, reason)
    bind_gen = bind_gen + 1
    local gen = bind_gen

    local function run_pass()
        return bind_pass(pieces_list, load_da)
    end

    if ExecuteInGameThread then
        ExecuteInGameThread(function()
            pcall(function() M.dump_subsystems("bind[" .. tostring(reason) .. "]") end)
            pcall(run_pass)
        end)
    else
        pcall(function() M.dump_subsystems("bind[" .. tostring(reason) .. "]") end)
        pcall(run_pass)
    end

    if not LoopAsync then return end
    local pass = 0
    LoopAsync(2500, function()
        if gen ~= bind_gen then return true end
        pass = pass + 1
        local done = false
        local body = function()
            local ok, pending = pcall(run_pass)
            if ok and pending == 0 then done = true end
        end
        if ExecuteInGameThread then ExecuteInGameThread(body) else body() end
        return done or pass >= 8
    end)
end

-- Console diagnostic (rsdw_builds_diag / blank_menu_diag): binding state per piece.
function M.diag(pieces_list, load_da)
    M.dump_subsystems("diag")
    for _, piece in ipairs(pieces_list) do
        local da = load_da and load_da(piece.da_path) or load_object(piece.da_path)
        local snap = M.inspect(piece, is_valid(da) and da or nil)
        print(string.format(
            "%s diag %s: cat_loaded=%s all_len=%s manifest_idx=%s runtime_idx=%s (via %s) da_idx=%s da_loaded=%s verified=%s",
            TAG, tostring(piece.id), tostring(snap.cat_loaded), tostring(snap.all_len),
            tostring(snap.manifest_idx), tostring(snap.runtime_idx), tostring(snap.how), tostring(snap.da_idx),
            tostring(is_valid(da)), tostring(snap.verified)))
        if snap.verified then
            print(TAG .. "   -> mod catalogue LOADED; piece at runtime index " .. tostring(snap.runtime_idx))
        elseif snap.all_len ~= nil then
            print(TAG .. "   -> persistence ID not found in loaded catalogue (" .. tostring(snap.all_len)
                .. " entries) — pak override not active? Rebuild + full restart.")
        end
    end
end

return M
