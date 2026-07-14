-- Load pak assets (DA, mesh) for persistence and catalogue binding.
local M = {}
local TAG = "[RSDWBuilds/assets]"
local pieces = require("pieces")

local cache = {}

local function is_valid(obj)
    if obj == nil then return false end
    if obj.IsValid then
        local ok, v = pcall(function() return obj:IsValid() end)
        return ok and v == true
    end
    return type(obj) == "userdata"
end

local function load_obj(path)
    if not path or path == "" then return nil end
    local pkg = path:match("^(.-)%.[^%.]+$") or path
    local export = path:match("%.([^%.]+)$")

    if StaticFindObject then
        local ok, obj = pcall(StaticFindObject, path)
        if ok and is_valid(obj) then return obj end
    end

    if LoadAsset then
        pcall(function() LoadAsset(pkg) end)
        pcall(function() LoadAsset(path) end)
        if StaticFindObject then
            local ok, obj = pcall(StaticFindObject, path)
            if ok and is_valid(obj) then return obj end
            ok, obj = pcall(StaticFindObject, pkg)
            if ok and is_valid(obj) then return obj end
        end
    end

    if StaticFindObject and export and pkg then
        local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if is_valid(arh) and arh.GetAsset then
            local ok_ue, ue = pcall(require, "UEHelpers")
            if ok_ue and ue and ue.FindOrAddFName then
                local ok_ad, ad = pcall(function()
                    return {
                        PackageName = ue.FindOrAddFName(pkg),
                        AssetName = ue.FindOrAddFName(export),
                    }
                end)
                if ok_ad and ad then
                    local ok_g, asset = pcall(function() return arh:GetAsset(ad) end)
                    if ok_g and is_valid(asset) then return asset end
                end
            end
        end
    end

    return nil
end

function M.load(path)
    return load_obj(path)
end

local function load_piece_assets(piece)
    if not piece or not piece.id then return false end
    cache[piece.id] = cache[piece.id] or {}

    if not is_valid(cache[piece.id].mesh) and piece.mesh_path then
        cache[piece.id].mesh = load_obj(piece.mesh_path)
    end

    if piece.runtime_material then
        if piece.base_tex and not is_valid(cache[piece.id].base) then
            cache[piece.id].base = load_obj(piece.base_tex)
        end
        if piece.norm_tex and not is_valid(cache[piece.id].norm) then
            cache[piece.id].norm = load_obj(piece.norm_tex)
        end
    end

    return is_valid(cache[piece.id].mesh)
end

function M.preload_all()
    local list = pieces.all()
    local n_mesh, n_tex = 0, 0
    for _, p in ipairs(list) do
        if load_piece_assets(p) then n_mesh = n_mesh + 1 end
        if p.runtime_material and is_valid(cache[p.id] and cache[p.id].base) then
            n_tex = n_tex + 1
        end
    end
    print(TAG .. string.format(" preloaded %d piece mesh(es), %d texture(s)", n_mesh, n_tex))
    return n_mesh
end

function M.ensure_piece(piece)
    if not piece then return false end
    local ok = load_piece_assets(piece)
    if not ok then
        print(TAG .. " mesh missing: " .. tostring(piece.mesh_path))
    end
    return ok
end

function M.mesh(piece_id)
    local c = cache[piece_id]
    return c and c.mesh or nil
end

function M.base_tex(piece_id)
    local c = cache[piece_id]
    return c and c.base or nil
end

function M.norm_tex(piece_id)
    local c = cache[piece_id]
    return c and c.norm or nil
end

function M.master()
    if is_valid(cache._master) then return cache._master end
    cache._master = load_obj("/Game/Materials/Environment/M_Standard_Env_MR.M_Standard_Env_MR")
    return cache._master
end

return M
