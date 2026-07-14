-- Build-piece catalogue helpers (separate chunk -- Lua 200-local limit per file).
local M = {}
local subsystem = require("subsystem")

local TAG, DA_PATH, DA_PKG, PERSIST_ID
local CATALOGUE_PATH, CATALOGUE_PKG, CATALOGUE_OBJ, CATALOGUE_INDEX
local MOD_CATALOGUE_PKG, MOD_CATALOGUE_OBJ
local CATALOGUE_INDEX_KEY, CATALOGUE_PATCH_LOGGED, CATALOGUE_MISS_LOGGED
local is_valid, load_object, string_from_fstring, uobject_same
local get_persist_id, clear_da_index, map_slot_matches_da
local tmap_find, tmap_add, bump_num_building_piece_datas
local ensure_da_stability_profile, preload_mod_assets, make_transform
local set_shared_deferred_index, allocate_deferred_index
local load_asset_blocking

function M.bind(deps)
    TAG = deps.TAG
    DA_PATH = deps.DA_PATH
    DA_PKG = deps.DA_PKG
    PERSIST_ID = deps.PERSIST_ID
    CATALOGUE_PATH = deps.CATALOGUE_PATH
    CATALOGUE_PKG = deps.CATALOGUE_PKG
    CATALOGUE_OBJ = deps.CATALOGUE_OBJ
    MOD_CATALOGUE_PKG = deps.MOD_CATALOGUE_PKG
    MOD_CATALOGUE_OBJ = deps.MOD_CATALOGUE_OBJ
    CATALOGUE_INDEX = deps.CATALOGUE_INDEX
    CATALOGUE_INDEX_KEY = deps.CATALOGUE_INDEX_KEY
    CATALOGUE_PATCH_LOGGED = deps.CATALOGUE_PATCH_LOGGED
    CATALOGUE_MISS_LOGGED = deps.CATALOGUE_MISS_LOGGED
    is_valid = deps.is_valid
    load_object = deps.load_object
    string_from_fstring = deps.string_from_fstring
    uobject_same = deps.uobject_same
    get_persist_id = deps.get_persist_id
    clear_da_index = deps.clear_da_index
    map_slot_matches_da = deps.map_slot_matches_da
    tmap_find = deps.tmap_find
    tmap_add = deps.tmap_add
    bump_num_building_piece_datas = deps.bump_num_building_piece_datas
    ensure_da_stability_profile = deps.ensure_da_stability_profile
    preload_mod_assets = deps.preload_mod_assets
    make_transform = deps.make_transform
    set_shared_deferred_index = deps.set_shared_deferred_index
    allocate_deferred_index = deps.allocate_deferred_index
    load_asset_blocking = deps.load_asset_blocking
end

function M.reset_catalogue_probe_flags()
    rawset(_G, CATALOGUE_MISS_LOGGED, nil)
    rawset(_G, CATALOGUE_PATCH_LOGGED, nil)
end

local function tarray_len(arr)
    if type(arr) ~= "userdata" and type(arr) ~= "table" then return 0 end
    local n = 0
    pcall(function() n = #arr end)
    if n == 0 then
        pcall(function()
            if arr.Num then n = arr:Num() end
        end)
    end
    return tonumber(n) or 0
end

local function tarray_get(arr, i)
    local v = nil
    pcall(function() v = arr[i] end)
    return v
end

local function soft_path_of(entry, safe)
    if entry == nil then return nil end
    local p = nil
    local ok, raw = pcall(function() return entry.AssetPathName end)
    if ok and type(raw) == "string" and raw ~= "" then
        p = raw
    elseif type(raw) == "userdata" and raw and raw.ToString then
        local ok2, s = pcall(function() return raw:ToString() end)
        if ok2 and type(s) == "string" and s ~= "" then p = s end
    end
    if not p then
        pcall(function()
            local ap = entry.AssetPath
            if not ap then return end
            local pkg = ap.PackageName
            if type(pkg) == "string" and pkg ~= "" then
                p = pkg
            elseif type(pkg) == "userdata" and pkg and pkg.ToString then
                local ok3, s = pcall(function() return pkg:ToString() end)
                if ok3 and type(s) == "string" and s ~= "" then p = s end
            end
            if type(p) == "string" and p ~= "" and ap.AssetName then
                local an = ap.AssetName
                if type(an) == "string" and an ~= "" and not p:find("%." .. an .. "$", 1) then
                    p = p .. "." .. an
                elseif type(an) == "userdata" and an and an.ToString then
                    local ok4, asn = pcall(function() return an:ToString() end)
                    if ok4 and type(asn) == "string" and asn ~= "" and not p:find("%." .. asn .. "$", 1) then
                        p = p .. "." .. asn
                    end
                end
            end
        end)
    end
    if type(p) == "string" and p ~= "" then return p end
    if safe then return nil end
    if entry.Get then
        local ok3, obj = pcall(function() return entry:Get() end)
        if ok3 and is_valid(obj) then
            pcall(function()
                local fn = obj:GetFullName()
                if fn then p = fn end
            end)
            if type(p) == "string" then return p end
        end
    end
    return nil
end

local function path_looks_like_ours(path)
    if type(path) ~= "string" or path == "" then return false end
    if path == DA_PATH or path == DA_PKG then return true end
    if path:find("/Game/RSDWBuilds/", 1, true) then return true end
    local leaf = DA_PATH and DA_PATH:match("([^/]+)%.[^%.]+$")
    if leaf and path:find(leaf, 1, true) then return true end
    return false
end

-- Pak-built clone catalogue: serialized offline, array soft refs are valid even when
-- UE4SS reflection cannot read TSoftObjectPtr entries (slot651 reads as nil).
local function is_mod_clone_catalogue(cat)
    if not is_valid(cat) then return false end
    local fn
    pcall(function() fn = cat:GetFullName() end)
    return type(fn) == "string"
        and fn:find("DA_BuildPieceCatalogue", 1, true) ~= nil
end

local function piece_looks_like_ours(piece)
    if not is_valid(piece) then return false end
    if get_persist_id(piece) == PERSIST_ID then return true end
    local fn
    pcall(function() fn = piece:GetFullName() end)
    if type(fn) ~= "string" then return false end
    if fn:find("/Game/RSDWBuilds/", 1, true) then return true end
    local leaf = DA_PATH and DA_PATH:match("([^/]+)%.[^%.]+$")
    return leaf ~= nil and fn:find(leaf, 1, true) ~= nil
end

local function sync_subsystem_catalogue(sub, cat)
    if not is_valid(sub) or not is_valid(cat) then return end
    pcall(function() sub.BuildPieceCatalogue = cat end)
    pcall(function()
        local ref = sub.BuildPieceCatalogueRef
        if ref and ref.Set then ref:Set(cat) end
    end)
end

function M.catalogue_slot_path_at(cat, idx)
    if not is_valid(cat) or not cat.BuildingPieceArray or type(idx) ~= "number" or idx < 0 then
        return nil
    end
    return soft_path_of(tarray_get(cat.BuildingPieceArray, idx + 1), true)
end

local function try_find_catalogue_index(cat, da)
    if not is_valid(cat) or not da or not cat.FindIndexForPieceData then return nil end
    local ok, idx = pcall(function() return cat:FindIndexForPieceData(da) end)
    if ok and type(idx) == "number" and idx >= 0 then return idx end
    return nil
end

local function catalogue_piece_at_index(cat, idx)
    if not is_valid(cat) or type(idx) ~= "number" or not cat.FindPieceDataForIndex then
        return nil
    end
    -- Broken IoStore soft refs at patched indices hard-crash FindPieceDataForIndex (pcall cannot catch).
    local persist = M.catalogue_persistence_id_at(cat, idx)
    local slot = M.catalogue_slot_path_at(cat, idx)
    if persist == PERSIST_ID or path_looks_like_ours(slot) then
        return nil
    end
    if idx == CATALOGUE_INDEX and is_mod_clone_catalogue(cat) then
        return nil
    end
    if not slot or slot == "" or slot:lower() == "none" then
        return nil
    end
    local piece
    pcall(function() piece = cat:FindPieceDataForIndex(idx) end)
    if is_valid(piece) then return piece end
    return nil
end

-- Array slot / persistence must resolve for native build preview (OnPieceSelected).
local function catalogue_array_slot_resolves(cat, idx, da)
    if not is_valid(cat) or type(idx) ~= "number" or idx < 0 then return false end
    if M.catalogue_persistence_id_at(cat, idx) == PERSIST_ID then return true end
    local slot = M.catalogue_slot_path_at(cat, idx)
    if path_looks_like_ours(slot) then return true end
    -- FindIndexForPieceData alone is not enough: main pak ships a clone catalogue object but
    -- pakchunk651 must be mounted for slot 651 to spawn (reflection may still show slot=nil).
    -- Never trust index-only: IoStore soft refs at unverified slots hard-crash native probes.
    if da and get_persist_id(da) == PERSIST_ID and idx ~= CATALOGUE_INDEX then
        return false
    end
    if not slot or slot == "" or slot:lower() == "none" then return false end
    local piece = catalogue_piece_at_index(cat, idx)
    if piece_looks_like_ours(piece) then return true end
    if da and is_valid(piece) and uobject_same(piece, da) then return true end
    return false
end

-- Cooked IoStore catalogues cannot accept runtime TArray patches safely (crashes on resolve).
local function try_patch_catalogue_slot(_cat, _idx, _da)
    return false
end

-- FindIndexForPieceData can succeed when BuildingPieceArray soft ref is broken (IoStore).
local function catalogue_spawn_resolves(cat, idx, da)
    return catalogue_array_slot_resolves(cat, idx, da)
end

function M.catalogue_chunk651_mounted(cat, _da)
    if not is_valid(cat) then return false end
    if M.catalogue_persistence_id_at(cat, CATALOGUE_INDEX) == PERSIST_ID then return true end
    local slot = M.catalogue_slot_path_at(cat, CATALOGUE_INDEX)
    return path_looks_like_ours(slot)
end

function M.catalogue_persistence_id_at(cat, idx)
    if not is_valid(cat) or type(idx) ~= "number" or idx < 0 then return nil end
    local set = cat.BuildingPiecePersistenceIDSet
    if not set then return nil end
    if set.Find then
        for _, key in ipairs({ idx, tostring(idx) }) do
            local ok, v = pcall(function() return set:Find(key) end)
            if ok and v ~= nil then
                local s = string_from_fstring(v)
                if s and s ~= "" then return s end
            end
        end
    end
    local n = tarray_len(set)
    if n > idx then
        local s = string_from_fstring(tarray_get(set, idx + 1))
        if s and s ~= "" then return s end
    end
    return nil
end

local function scan_persistence_values(cat)
    local values = {}
    local seen = {}
    local function add_val(v)
        local s = string_from_fstring(v)
        if s and s ~= "" and not seen[s] then
            seen[s] = true
            values[#values + 1] = s
        end
    end
    local set = cat and cat.BuildingPiecePersistenceIDSet
    if not is_valid(set) then return values end
    local set_len = tonumber(tarray_len(set)) or 0
    if set_len > 0 then
        for i = 1, set_len do
            add_val(tarray_get(set, i))
        end
    end
    local arr_len = 0
    if cat.BuildingPieceArray then
        arr_len = tonumber(tarray_len(cat.BuildingPieceArray)) or 0
    end
    local cat_idx = tonumber(CATALOGUE_INDEX) or 651
    local scan_max = math.max(arr_len, cat_idx + 1)
    if set.Find and scan_max >= 0 then
        for idx = 0, scan_max do
            for _, key in ipairs({ idx, tostring(idx) }) do
                local ok, v = pcall(function() return set:Find(key) end)
                if ok and v ~= nil then add_val(v) end
            end
        end
    end
    return values
end

local function load_mod_catalogue_object()
    if not MOD_CATALOGUE_OBJ or not MOD_CATALOGUE_PKG then return nil end
    if LoadAsset then
        pcall(function() LoadAsset(MOD_CATALOGUE_PKG) end)
        pcall(function() LoadAsset(MOD_CATALOGUE_OBJ) end)
    end
    if StaticFindObject then
        local cat = nil
        pcall(function() cat = StaticFindObject(MOD_CATALOGUE_OBJ) end)
        if is_valid(cat) then return cat end
    end
    return load_object(MOD_CATALOGUE_OBJ)
end

local function mod_catalogue_slot_ok(cat, da)
    if not is_valid(cat) then return false end
    if M.catalogue_persistence_id_at(cat, CATALOGUE_INDEX) == PERSIST_ID then return true end
    local slot = M.catalogue_slot_path_at(cat, CATALOGUE_INDEX)
    if path_looks_like_ours(slot) then return true end
    if da and try_find_catalogue_index(cat, da) == CATALOGUE_INDEX then
        return catalogue_array_slot_resolves(cat, CATALOGUE_INDEX, da)
            or M.catalogue_persistence_id_at(cat, CATALOGUE_INDEX) == PERSIST_ID
    end
    return false
end

local function find_all_catalogue_candidates()
    local out = {}
    local seen = {}
    local function add(cat)
        if not is_valid(cat) then return end
        local fn
        pcall(function() fn = cat:GetFullName() end)
        fn = fn or tostring(cat)
        if seen[fn] then return end
        seen[fn] = true
        out[#out + 1] = cat
    end
    add(load_mod_catalogue_object())
    -- Never LoadAsset_Blocking on IoStore catalogue (hard-crashes); soft LoadAsset only.
    if LoadAsset then
        pcall(function() LoadAsset(CATALOGUE_PKG) end)
        pcall(function() LoadAsset(CATALOGUE_OBJ) end)
    end
    if StaticFindObject then
        pcall(function() add(StaticFindObject(CATALOGUE_OBJ)) end)
    end
    pcall(function()
        local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if not is_valid(arh) then return end
        local ok_ue, ue = pcall(require, "UEHelpers")
        if not ok_ue or not ue or not ue.FindOrAddFName then return end
        local ok_ad, ad = pcall(function()
            return {
                PackageName = ue.FindOrAddFName(CATALOGUE_PKG),
                AssetName = ue.FindOrAddFName("DA_BuildPieceCatalogue_Default"),
            }
        end)
        if ok_ad and ad and arh.GetAsset then
            local ok_g, asset = pcall(function() return arh:GetAsset(ad) end)
            if ok_g then add(asset) end
        end
    end)
    if FindAllOf then
        pcall(function()
            local list = FindAllOf("BuildPieceCatalogue")
            if type(list) == "table" then
                for _, cat in pairs(list) do add(cat) end
            end
        end)
    end
    local sub = subsystem.find()
    if sub then
        pcall(function() add(sub.BuildPieceCatalogue) end)
        pcall(function()
            local ref = sub.BuildPieceCatalogueRef
            if ref and ref.Get then add(ref:Get()) end
        end)
    end
    add(load_object(CATALOGUE_OBJ))
    return out
end

local function clear_stale_clone_index(da)
    if not da or get_persist_id(da) ~= PERSIST_ID then return end
    local idx
    pcall(function() idx = da.BuildingPieceDataIndex end)
    if type(idx) ~= "number" or idx < 0 then return end
    local cat = M.find_build_piece_catalogue()
    -- Keep index only when the live catalogue array slot resolves (not find_index-only).
    if is_valid(cat) and catalogue_array_slot_resolves(cat, idx, da) then return end
    clear_da_index(da)
end

function M.prepare_da_for_native_build(da, force_stability)
    if not da then return end
    clear_stale_clone_index(da)
    ensure_da_stability_profile(da, force_stability == true)
end

function M.find_build_piece_catalogue()
    local mod_cat = load_mod_catalogue_object()
    if is_valid(mod_cat) then return mod_cat end
    local sub = subsystem.find()
    if is_valid(sub) then
        local cat
        pcall(function() cat = sub.BuildPieceCatalogue end)
        if is_valid(cat) then return cat end
        pcall(function()
            local ref = sub.BuildPieceCatalogueRef
            if ref and ref.Get then cat = ref:Get() end
        end)
        if is_valid(cat) then return cat end
    end
    if LoadAsset then
        pcall(function() LoadAsset(CATALOGUE_PKG) end)
        pcall(function() LoadAsset(CATALOGUE_OBJ) end)
    end
    return load_object(CATALOGUE_OBJ) or load_object(CATALOGUE_PATH)
end

function M.catalogue_pak_active(cat, da)
    if not is_valid(cat) then return false end
    return catalogue_spawn_resolves(cat, CATALOGUE_INDEX, da)
end

function M.catalogue_native_preview_ready(cat, da)
    if not is_valid(cat) then return false end
    return catalogue_array_slot_resolves(cat, CATALOGUE_INDEX, da)
end

-- Native Server_SpawnBuilding indexes the live catalogue array, not subsystem deferred map slots.
function M.index_is_catalogue_backed(cat, da, idx)
    if not is_valid(cat) or type(idx) ~= "number" or idx < 0 then return false end
    return catalogue_array_slot_resolves(cat, idx, da)
end

function M.force_reload_catalogue_assets()
    preload_mod_assets()
    if LoadAsset then
        if MOD_CATALOGUE_PKG then pcall(function() LoadAsset(MOD_CATALOGUE_PKG) end) end
        if MOD_CATALOGUE_OBJ then pcall(function() LoadAsset(MOD_CATALOGUE_OBJ) end) end
        pcall(function() LoadAsset(CATALOGUE_PKG) end)
        pcall(function() LoadAsset(CATALOGUE_OBJ) end)
        pcall(function() LoadAsset(DA_PKG) end)
    end
end

function M.force_load_mounted_catalogue()
    M.force_reload_catalogue_assets()
end

local function catalogue_has_mod_patch(cat, da)
    if not is_valid(cat) then return false, "missing" end
    local ok_scan, scanned = pcall(scan_persistence_values, cat)
    if ok_scan and type(scanned) == "table" then
        for _, s in ipairs(scanned) do
            if s == PERSIST_ID then return true, "persist_id" end
            if s:find("rsdw_pad_", 1, true) then return true, "pad" end
        end
    end
    if M.catalogue_persistence_id_at(cat, CATALOGUE_INDEX) == PERSIST_ID then
        return true, "persist651"
    end
    if da then
        local find_idx = try_find_catalogue_index(cat, da)
        if find_idx == CATALOGUE_INDEX then
            return true, "find_index"
        end
    end
    local piece = catalogue_piece_at_index(cat, CATALOGUE_INDEX)
    if piece_looks_like_ours(piece) then return true, "piece651" end
    local path = M.catalogue_slot_path_at(cat, CATALOGUE_INDEX)
    if path_looks_like_ours(path) then return true, "slot651" end
    return false, "vanilla"
end

local function usable_catalogue_index(cat, da)
    if not is_valid(cat) then return nil end
    if catalogue_spawn_resolves(cat, CATALOGUE_INDEX, da) then
        return CATALOGUE_INDEX
    end
    if da then
        local idx = try_find_catalogue_index(cat, da)
        if type(idx) == "number" and idx >= 0 and catalogue_spawn_resolves(cat, idx, da) then
            return idx
        end
    end
    return nil
end

function M.resolve_live_catalogue(da)
    M.force_load_mounted_catalogue()
    local best, best_reason = nil, nil
    local sub = subsystem.find()

    for _, cat in ipairs(find_all_catalogue_candidates()) do
        local has, reason = catalogue_has_mod_patch(cat, da)
        if is_valid(cat) and mod_catalogue_slot_ok(cat, da) then
            best, best_reason = cat, "mod_catalogue651"
        elseif has and (not best_reason or reason == "persist651" or reason == "slot651" or reason == "piece651") then
            best, best_reason = cat, reason
        elseif has and not best then
            best, best_reason = cat, reason
        elseif not best then
            best = cat
        end
    end

    if best and best_reason then
        local mounted = M.catalogue_chunk651_mounted(best, da)
        if sub and mounted then sync_subsystem_catalogue(sub, best) end
        if not rawget(_G, CATALOGUE_PATCH_LOGGED) then
            rawset(_G, CATALOGUE_PATCH_LOGGED, true)
            local slot = M.catalogue_slot_path_at(best, CATALOGUE_INDEX)
            local persist = M.catalogue_persistence_id_at(best, CATALOGUE_INDEX)
            print(string.format(
                "%s catalogue %s (%s) index=%d slot651=%s persist651=%s",
                TAG, mounted and "pak: OK" or "clone only (no pakchunk651)",
                best_reason, CATALOGUE_INDEX, tostring(slot), tostring(persist)
            ))
        end
    elseif not rawget(_G, CATALOGUE_MISS_LOGGED) then
        rawset(_G, CATALOGUE_MISS_LOGGED, true)
        local arr_len = best and best.BuildingPieceArray and tarray_len(best.BuildingPieceArray) or 0
        local slot = best and M.catalogue_slot_path_at(best, CATALOGUE_INDEX) or nil
        local persist = best and M.catalogue_persistence_id_at(best, CATALOGUE_INDEX) or nil
        print(string.format(
            "%s catalogue miss: arr_len=%d slot651=%s persist651=%s (runtime still vanilla -- full restart after redeploy pak trio)",
            TAG, arr_len, tostring(slot), tostring(persist)
        ))
    end
    return best, best_reason
end

function M.sync_catalogue_for_world(da)
    M.reset_catalogue_probe_flags()
    return M.resolve_live_catalogue(da)
end

local function resolve_catalogue_index(sub, da)
    local cat = select(1, M.resolve_live_catalogue(da))
    if not is_valid(cat) then return nil, nil end
    local idx = usable_catalogue_index(cat, da)
    if idx == nil then return nil, cat end

    rawset(_G, CATALOGUE_INDEX_KEY, idx)
    set_shared_deferred_index(nil)
    return idx, cat
end

local function repair_catalogue_index(sub, da, idx, cat)
    if not sub or not da or type(idx) ~= "number" or idx < 0 then return false end
    cat = cat or select(1, M.resolve_live_catalogue(da))
    if not catalogue_spawn_resolves(cat, idx, da) then
        if is_valid(cat) and da and try_find_catalogue_index(cat, da) == idx then
            try_patch_catalogue_slot(cat, idx, da)
        end
    end
    if not catalogue_spawn_resolves(cat, idx, da) then
        return false
    end
    local array_ok = catalogue_array_slot_resolves(cat, idx, da)
    if not array_ok and is_valid(cat) and try_find_catalogue_index(cat, da) == idx then
        array_ok = try_patch_catalogue_slot(cat, idx, da)
    end
    local idx_map = sub.BuildingPieceDataIndexToBuildingPieceData
    if idx_map and array_ok then
        local at = tmap_find(idx_map, idx)
        if at == nil then
            tmap_add(idx_map, idx, da)
        elseif not map_slot_matches_da(at, da) then
            print(TAG .. " warn: catalogue index " .. idx .. " occupied; spawn may fail")
            return false
        end
    end
    if array_ok then
        -- Never assign BuildingPieceDataIndex on mod DAs (IoStore slot probe hard-crash in shipping).
        clear_da_index(da)
        pcall(function() bump_num_building_piece_datas(sub, idx) end)
        rawset(_G, CATALOGUE_INDEX_KEY, idx)
    else
        clear_da_index(da)
        rawset(_G, CATALOGUE_INDEX_KEY, nil)
    end
    return array_ok
end

function M.resolve_spawn_index(sub, da)
    sub = sub or subsystem.find()
    local cat_idx, cat = resolve_catalogue_index(sub, da)
    if cat_idx ~= nil and not catalogue_array_slot_resolves(cat, cat_idx, da) then
        try_patch_catalogue_slot(cat, cat_idx, da)
    end
    if cat_idx ~= nil and catalogue_array_slot_resolves(cat, cat_idx, da) then
        repair_catalogue_index(sub, da, cat_idx, cat)
        return cat_idx, "catalogue"
    end
    if cat_idx ~= nil then
        clear_da_index(da)
        rawset(_G, CATALOGUE_INDEX_KEY, nil)
        set_shared_deferred_index(nil)
    end
    if not rawget(_G, CATALOGUE_PATCH_LOGGED) and not rawget(_G, CATALOGUE_MISS_LOGGED) then
        rawset(_G, CATALOGUE_MISS_LOGGED, true)
        print(TAG .. " warn: catalogue pak missing -- rebuild with Build-And-Pack-Full-Phase2.ps1 -IncludeCatalogue")
    end
    local deferred = allocate_deferred_index(sub, da)
    if deferred ~= nil then return deferred, "deferred" end
    return nil, nil
end

function M.prepare_da_for_build(sub, da)
    sub = sub or subsystem.find()
    local cat_idx, cat = resolve_catalogue_index(sub, da)
    if cat_idx ~= nil and not catalogue_array_slot_resolves(cat, cat_idx, da) then
        try_patch_catalogue_slot(cat, cat_idx, da)
    end
    if cat_idx ~= nil and catalogue_array_slot_resolves(cat, cat_idx, da) then
        repair_catalogue_index(sub, da, cat_idx, cat)
        return cat_idx, "catalogue"
    end
    if cat_idx ~= nil then
        clear_da_index(da)
        return cat_idx, "find_index"
    end
    clear_da_index(da)
    return nil, "deferred"
end

function M.spawn_via_server_building(bmc, idx, loc, rot)
    if not is_valid(bmc) or type(idx) ~= "number" or not loc then
        return false, "missing bmc/idx/loc"
    end
    if not bmc.Server_SpawnBuilding then
        return false, "Server_SpawnBuilding missing"
    end
    local xform = make_transform(loc.X, loc.Y, loc.Z, (rot and rot.Yaw) or 0)
    local ok, err = pcall(function()
        bmc:Server_SpawnBuilding(idx, xform, false, {})
    end)
    if not ok then return false, tostring(err) end
    return true, "ok"
end

local function catalogue_index_reserved_for_other(cat, idx, da)
    if type(idx) == "number" and idx == CATALOGUE_INDEX then
        if M.catalogue_persistence_id_at(cat, idx) == PERSIST_ID then return false end
        local slot = M.catalogue_slot_path_at(cat, idx)
        if path_looks_like_ours(slot) then return false end
    end
    local piece = catalogue_piece_at_index(cat, idx)
    if not is_valid(piece) then return false end
    return not map_slot_matches_da(piece, da)
end

function M.deferred_map_slot_usable(sub, cat, idx, da)
    if not sub or type(idx) ~= "number" or idx < 0 then return false end
    if catalogue_index_reserved_for_other(cat, idx, da) then return false end
    local idx_map = sub.BuildingPieceDataIndexToBuildingPieceData
    if not idx_map then return false end
    local at = tmap_find(idx_map, idx)
    return at == nil or map_slot_matches_da(at, da)
end

-- Re-probe after mod IoStore mounts (boot may have cached vanilla catalogue too early).
function M.try_resync_mounted_catalogue(da)
    M.reset_catalogue_probe_flags()
    return M.resolve_live_catalogue(da)
end

return M


