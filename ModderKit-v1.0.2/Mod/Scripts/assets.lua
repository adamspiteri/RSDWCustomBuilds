-- Shared asset loading (IoStore pak + legacy uasset/uexp).
local M = {}

function M.is_valid(obj)
    if type(obj) ~= "userdata" then return false end
    if not obj.IsValid then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

function M.load(path)
    if not path or path == "" or path:lower() == "none" then return nil end
    if not path:find("/", 1, true) then return nil end

    local package_path = path:match("^(.-)%.[^%.]+$") or path
    local export = path:match("%.([^%.]+)$")

    if StaticFindObject then
        local ok, found = pcall(StaticFindObject, path)
        if ok and M.is_valid(found) then return found end
    end

    if LoadAsset then
        pcall(function() LoadAsset(package_path) end)
        pcall(function() LoadAsset(path) end)
        if StaticFindObject then
            local ok2, found2 = pcall(StaticFindObject, path)
            if ok2 and M.is_valid(found2) then return found2 end
        end
    end

    if StaticFindObject and export and package_path then
        local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if M.is_valid(arh) then
            local ok_ue, ue = pcall(require, "UEHelpers")
            if ok_ue and ue and ue.FindOrAddFName then
                local ok_ad, ad = pcall(function()
                    return {
                        PackageName = ue.FindOrAddFName(package_path),
                        AssetName = ue.FindOrAddFName(export),
                    }
                end)
                if ok_ad and ad and arh.GetAsset then
                    local ok_g, asset = pcall(function() return arh:GetAsset(ad) end)
                    if ok_g and M.is_valid(asset) then return asset end
                end
            end
        end
    end

    return nil
end

return M
