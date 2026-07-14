-- RSDW Custom Builds — save-fix + override pak (no F7 menu, no catalogue probing).
-- Registers legacy mod persistence IDs before LoadPlayerState so old saves still load.
-- Runtime visuals swap vanilla wall mesh/texture to SM_Stonewall + brick textures.

local TAG = "[RSDWBuilds]"
print(TAG .. " loading (override pak, persistence + stonewall visuals)...")

local persistence = require("persistence")
persistence.install_boot_hooks()

pcall(function()
    persistence.register_all("startup")
end)

local visuals = require("visuals")
pcall(function()
    visuals.install()
end)

print(TAG .. " ready — vanilla build menu Stonewall; mesh/textures patched at runtime")
