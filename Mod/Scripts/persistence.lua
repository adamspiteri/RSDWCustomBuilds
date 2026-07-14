-- Register mod piece persistence IDs before save hydration (BuildingsUnlocked).
local M = {}

local TAG = "[RSDWBuilds]"
local BOOT_OK_KEY = "RSDW_BUILDS_PERSIST_BOOT_OK"
local BOOT_LOGGED_KEY = "RSDW_BUILDS_PERSIST_BOOT_LOGGED"

local assets = require("assets")
local subsystem = require("subsystem")

local DONOR_DA = {
    foundation_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/DA_T1_Foundation_Large.DA_T1_Foundation_Large",
    wall_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Walls/DA_T1_Wall_Large.DA_T1_Wall_Large",
}

-- Saves written during earlier mod builds may reference these ids in BuildingsUnlocked.
local LEGACY_PERSIST_ALIASES = {
    MyFoundation_Mod_v1 = "Stonewall",
    RSDWBuilds_Stonewall_v1 = "Stonewall",
    Build_Stonewall_Tier1 = "Stonewall",
}

local function is_valid(obj)
    return assets.is_valid(obj)
end

local function load_object(path)
    return assets.load(path)
end

local function read_manifest()
    local ok, data = pcall(require, "pieces_data")
    if ok and type(data) == "table" then return data end
    return nil
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

local function tmap_replace(map, key, val)
    if not map then return false end
    pcall(function() map:Remove(key) end)
    return tmap_add(map, key, val)
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

local function clear_piece_requirements(da)
    if not da then return end
    pcall(function()
        local req = da.Requirements
        if req and req.Clear then req:Clear() end
    end)
end

local function resolve_donor_da(entry)
    local donor = entry and entry.donor or "foundation_large"
    local path = DONOR_DA[donor] or DONOR_DA.foundation_large
    return load_object(path)
end

local function resolve_piece_da(entry)
    if not entry or not entry.da_path then return nil, "missing da_path" end
    if LoadAsset then
        pcall(function() LoadAsset(entry.da_path:match("^(.-)%.[^%.]+$") or entry.da_path) end)
    end
    local da = load_object(entry.da_path)
    if is_valid(da) then
        clear_piece_requirements(da)
        return da, nil
    end
    local stub = resolve_donor_da(entry)
    if is_valid(stub) then
        clear_piece_requirements(stub)
        return stub, "hydration_stub"
    end
    return nil, "DA not mounted: " .. tostring(entry.da_path)
end

local function register_entry_on_subsystem(live, entry, da)
    local pid = entry.persistence_id
    if type(pid) ~= "string" or pid == "" then return false, "missing persistence_id" end

    local parent = live.PersistenceIDToDataMap
    if not parent then return false, "PersistenceIDToDataMap missing" end

    local wrote = false
    if tmap_find(parent, pid) == nil then
        local ok = tmap_add(parent, pid, da)
        if not ok then return false, "PersistenceIDToDataMap Add failed for " .. pid end
        wrote = true
    end

    local pid_map = live.PersistenceIDToBuildingPieceDataMap
    if pid_map and tmap_find(pid_map, pid) == nil then
        tmap_add(pid_map, pid, da)
    end

    local idx = tonumber(entry.catalogue_index)
    if idx and idx >= 0 then
        local idx_map = live.BuildingPieceDataIndexToBuildingPieceData
        if idx_map then
            local at = tmap_find(idx_map, idx)
            if at == nil then
                tmap_add(idx_map, idx, da)
            elseif not is_valid(at) then
                tmap_replace(idx_map, idx, da)
            end
            bump_num_building_piece_datas(live, idx)
        end
    end

    return true, wrote and ("registered " .. pid) or ("already had " .. pid)
end

local function register_legacy_aliases(live, pieces_by_id)
    for legacy_id, piece_id in pairs(LEGACY_PERSIST_ALIASES) do
        local entry = pieces_by_id[piece_id]
        if entry then
            local da, _note = resolve_piece_da(entry)
            if is_valid(da) then
                local fake = {
                    persistence_id = legacy_id,
                    catalogue_index = entry.catalogue_index,
                }
                register_entry_on_subsystem(live, fake, da)
            end
        end
    end
end

function M.register_all(reason)
    local m = read_manifest()
    if not m or type(m.pieces) ~= "table" or #m.pieces == 0 then
        return false, "no manifest pieces"
    end

    local sub = subsystem.find()
    if not sub then return false, "BuildingPieceSubsystem not ready" end

    local any = false
    local details = {}
    local pieces_by_id = {}
    for _, entry in ipairs(m.pieces) do
        if entry.id then pieces_by_id[entry.id] = entry end
    end
    for _, entry in ipairs(m.pieces) do
        local da, note = resolve_piece_da(entry)
        if not is_valid(da) then
            details[#details + 1] = (entry.id or "?") .. ": " .. tostring(note)
        else
            for _, live in ipairs(subsystem.collect_all(sub)) do
                local ok, detail = register_entry_on_subsystem(live, entry, da)
                if ok then
                    any = true
                    if note == "hydration_stub" then
                        detail = detail .. " (stub until pak DA mounts)"
                    end
                    details[#details + 1] = (entry.id or "?") .. ": " .. detail
                else
                    details[#details + 1] = (entry.id or "?") .. ": FAIL " .. tostring(detail)
                end
            end
        end
    end
    if any then
        for _, live in ipairs(subsystem.collect_all(sub)) do
            register_legacy_aliases(live, pieces_by_id)
        end
    end

    if any then
        rawset(_G, BOOT_OK_KEY, true)
        if not rawget(_G, BOOT_LOGGED_KEY) or reason == "LoadPlayerState" or reason == "LoadMapPre" then
            rawset(_G, BOOT_LOGGED_KEY, true)
            print(TAG .. " persistence boot (" .. tostring(reason or "?") .. "): " .. table.concat(details, "; "))
        end
        return true, table.concat(details, "; ")
    end
    return false, table.concat(details, "; ")
end

function M.is_ready()
    return rawget(_G, BOOT_OK_KEY) == true
end

local function attempt(reason)
    subsystem.invalidate()
    local ok = M.register_all(reason)
    return ok
end

function M.install_boot_hooks()
    if rawget(_G, "RSDW_BUILDS_PERSIST_HOOKS") then return end
    rawset(_G, "RSDW_BUILDS_PERSIST_HOOKS", true)

    if RegisterLoadMapPreHook then
        RegisterLoadMapPreHook(function()
            rawset(_G, BOOT_OK_KEY, false)
            attempt("LoadMapPre")
        end)
    end

    local function hook_persist(reason, path)
        pcall(function()
            RegisterHook(path, function()
                attempt(reason)
            end)
        end)
    end

    if RegisterHook then
        -- Must run before save hydrates BuildingsUnlocked (see RSDWCustomBuilding building.lua).
        hook_persist("LoadPlayerState", "/Script/Dominion.PersistenceSubsystem:LoadPlayerState")
        hook_persist("ProcessPlayerStateLoad", "/Script/Dominion.PersistenceSubsystem:ProcessPlayerStateLoad")
        hook_persist("InitGameState", "/Script/Engine.GameModeBase:InitGameState")
        hook_persist("ClientRestart", "/Script/Engine.PlayerController:ClientRestart")
    end

    print(TAG .. " persistence hooks installed (fixes BuildingsUnlocked save load)")
end

return M
