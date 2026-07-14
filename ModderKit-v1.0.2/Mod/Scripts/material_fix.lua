local M = {}

local TAG = "[RSDWBuilds]"
local MESH_NEEDLE = "/Game/RSDWBuilds/Stonewall/SM_Stonewall"
local MATERIAL_PATH = "/Game/RSDWBuilds/Stonewall/MI_Stonewall_Walls.MI_Stonewall_Walls"
local MATERIAL_PACKAGE = "/Game/RSDWBuilds/Stonewall/MI_Stonewall_Walls"
local logged_missing_material = false

local function is_valid(obj)
    if type(obj) ~= "userdata" or not obj.IsValid then return false end
    local ok, value = pcall(function() return obj:IsValid() end)
    return ok and value == true
end

local function full_name(obj)
    if not is_valid(obj) then return "none" end
    local value = tostring(obj)
    pcall(function()
        if obj.GetFullName then value = obj:GetFullName() end
    end)
    return value
end

local function load_material()
    if LoadAsset then
        local ok1, mat1 = pcall(function() return LoadAsset(MATERIAL_PATH) end)
        if ok1 and is_valid(mat1) then return mat1 end
        local ok2, mat2 = pcall(function() return LoadAsset(MATERIAL_PACKAGE) end)
        if ok2 and is_valid(mat2) then return mat2 end
    end
    if StaticFindObject then
        local ok, mat = pcall(StaticFindObject, MATERIAL_PATH)
        if ok and is_valid(mat) then return mat end
        local ok_pkg, pkg_mat = pcall(StaticFindObject, MATERIAL_PACKAGE)
        if ok_pkg and is_valid(pkg_mat) then return pkg_mat end
    end
    return nil
end

local function component_mesh(comp)
    local mesh = nil
    pcall(function() mesh = comp.StaticMesh end)
    if not is_valid(mesh) and comp.GetStaticMesh then
        pcall(function() mesh = comp:GetStaticMesh() end)
    end
    return mesh
end

local function component_material(comp)
    local mat = nil
    if comp.GetMaterial then
        pcall(function() mat = comp:GetMaterial(0) end)
    end
    return mat
end

local function is_stonewall_component(comp)
    if not is_valid(comp) then return false end
    local mesh = component_mesh(comp)
    return full_name(mesh):find(MESH_NEEDLE, 1, true) ~= nil
end

function M.apply(verbose)
    if verbose == nil then verbose = true end
    local material = load_material()
    if not is_valid(material) then
        if verbose or not logged_missing_material then
            print(TAG .. " matfix: material missing " .. MATERIAL_PATH)
            logged_missing_material = true
        end
        return false, "material missing"
    end
    if not FindAllOf then
        return false, "FindAllOf missing"
    end

    local list = FindAllOf("StaticMeshComponent")
    if type(list) ~= "table" then
        return false, "StaticMeshComponent list missing"
    end

    local seen = 0
    local changed = 0
    for _, comp in pairs(list) do
        if is_stonewall_component(comp) then
            seen = seen + 1
            local before = full_name(component_material(comp))
            local ok = false
            if comp.SetMaterial then
                ok = pcall(function() comp:SetMaterial(0, material) end)
            end
            pcall(function()
                if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end
            end)
            local after = full_name(component_material(comp))
            if ok then changed = changed + 1 end
            if verbose or before ~= after then
                print(string.format("%s matfix comp%d: %s -> %s", TAG, seen, before, after))
            end
        end
    end

    return true, string.format("matfix seen=%d set=%d material=%s", seen, changed, full_name(material))
end

function M.install_auto()
    if rawget(_G, "RSDWBUILDS_MATFIX_AUTO") or not LoopAsync then return end
    rawset(_G, "RSDWBUILDS_MATFIX_AUTO", true)
    local last_seen = -1
    LoopAsync(1500, function()
        local ok, detail = M.apply(false)
        local seen = 0
        if type(detail) == "string" then
            seen = tonumber(detail:match("seen=(%d+)")) or 0
        end
        if ok and seen > 0 and seen ~= last_seen then
            print(TAG .. " " .. tostring(detail))
            last_seen = seen
        end
        return false
    end)
    print(TAG .. " matfix auto installed")
end

return M

