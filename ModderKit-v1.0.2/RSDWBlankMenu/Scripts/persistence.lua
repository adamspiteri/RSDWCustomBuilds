-- Register mod persistence IDs only. Never write BuildingPieceDataIndex (game assigns from AllPiecesInCatalogue).
local M = {}
local TAG = "[BlankMenu/persist]"
local BOOT_OK = "RSDW_BLANKMENU_PERSIST_OK"

local subsystem = require("subsystem")
local pieces = require("pieces")
local donors = require("donors")
local assets = require("assets")
local catalogue = require("catalogue")

-- Old experimental persistence IDs still present in old saves. NEVER alias a vanilla
-- piece's real PersistenceID here (ra70cEh9cDOb_leFJwQE2Q is the vanilla T1 wall).
local LEGACY_ALIASES = {
    MyFoundation_Mod_v1 = "Stonewall",
    Build_Stonewall_Tier1 = "Stonewall",
}

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

local function clear_piece_requirements(da)
    if not is_valid(da) then return end
    pcall(function()
        if da.Requirements and da.Requirements.Clear then
            da.Requirements:Clear()
        end
    end)
end

local function da_build_index(da)
    if not is_valid(da) then return nil end
    local idx = nil
    pcall(function() idx = da.BuildingPieceDataIndex end)
    if type(idx) == "number" then return idx end
    return nil
end

local function resolve_donor_da(piece)
    local d = donors[piece.donor or ""]
    if not d then return nil end
    return load_object(d.da_path)
end

local function resolve_piece_da(piece)
    if piece.da_path then
        local da = load_object(piece.da_path)
        if is_valid(da) then
            clear_piece_requirements(da)
            return da
        end
        print(TAG .. " warning: custom DA not loaded for " .. tostring(piece.id) .. " — " .. piece.da_path)
    end
    return resolve_donor_da(piece)
end

local function register_pid(live, pid, da)
    if not pid or pid == "" or not is_valid(da) then return false end
    local parent = live.PersistenceIDToDataMap
    if not parent then return false end
    if tmap_find(parent, pid) == nil then
        if not tmap_add(parent, pid, da) then return false end
    end
    local pid_map = live.PersistenceIDToBuildingPieceDataMap
    if pid_map and tmap_find(pid_map, pid) == nil then
        tmap_add(pid_map, pid, da)
    end
    return true
end

local function register_piece(live, piece, da)
    local pid = piece.persistence_id
    if type(pid) ~= "string" or pid == "" or not is_valid(da) then return false end
    return register_pid(live, pid, da)
end

function M.register_all(reason)
    local list = pieces.all()
    if #list == 0 then return false end
    local sub = subsystem.find()
    if not sub then return false end

    local any = false
    local details = {}
    local by_id = {}
    for _, p in ipairs(list) do by_id[p.id] = p end

    for _, piece in ipairs(list) do
        local pid = piece.persistence_id
        if type(pid) ~= "string" or pid == "" then goto continue end
        local da = resolve_piece_da(piece)
        if not is_valid(da) then
            details[#details + 1] = piece.id .. ": DA missing"
            goto continue
        end
        for _, live in ipairs(subsystem.collect_all(sub)) do
            if register_piece(live, piece, da) then
                any = true
                local idx = da_build_index(da)
                local idx_note = (type(idx) == "number") and (" idx=" .. idx) or ""
                details[#details + 1] = piece.id .. "=" .. pid .. idx_note
            end
        end
        ::continue::
    end

    for legacy_pid, piece_id in pairs(LEGACY_ALIASES) do
        local piece = by_id[piece_id]
        if piece then
            local da = resolve_piece_da(piece)
            if is_valid(da) then
                for _, live in ipairs(subsystem.collect_all(sub)) do
                    local fake = { persistence_id = legacy_pid }
                    register_piece(live, fake, da)
                end
            end
        end
    end

    if any then
        rawset(_G, BOOT_OK, true)
        print(TAG .. " registered (" .. tostring(reason or "?") .. "): " .. table.concat(details, "; "))
    end
    return any
end

local function attempt(reason)
    subsystem.invalidate()
    M.register_all(reason)
    -- Bind native pieces so vanilla menu placement gets stability + correct DA index.
    pcall(function() catalogue.schedule_bind(pieces.all(), assets.load, reason) end)
    -- Resurrection pass: re-spawn journaled pieces lost to a mod-off session
    -- (runs once per world load, only after the world/pieces are actually ready).
    pcall(function() require("journal").schedule_restore(reason) end)
end

function M.install_boot_hooks()
    if rawget(_G, "RSDW_BLANKMENU_PERSIST_HOOKS") then return end
    rawset(_G, "RSDW_BLANKMENU_PERSIST_HOOKS", true)

    if RegisterLoadMapPreHook then
        RegisterLoadMapPreHook(function()
            rawset(_G, BOOT_OK, false)
            attempt("LoadMapPre")
        end)
    end

    local paths = {
        "/Script/Dominion.PersistenceSubsystem:LoadPlayerState",
        "/Script/Dominion.PersistenceSubsystem:ProcessPlayerStateLoad",
        "/Script/Engine.GameModeBase:InitGameState",
        "/Script/Engine.PlayerController:ClientRestart",
    }
    for _, path in ipairs(paths) do
        pcall(function()
            RegisterHook(path, function()
                attempt(path:match("([^:]+)$") or "hook")
            end)
        end)
    end

    print(TAG .. " boot hooks installed (persistence ID only)")
end

return M
