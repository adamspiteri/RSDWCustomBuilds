-- RSDW custom building pieces — vanilla menu only (persistence + catalogue runtime bind).
local TAG = "[RSDWBuilds]"
local pieces = require("pieces")

local function run_gt(fn)
    if ExecuteInGameThread then
        ExecuteInGameThread(function()
            local ok, e = pcall(fn)
            if not ok then print(TAG .. " error: " .. tostring(e)) end
        end)
    else
        pcall(fn)
    end
end

run_gt(function()
    -- Journal FIRST: its LoadMapPre hook (world-exit snapshot) must run before
    -- persistence's LoadMapPre re-arms the restore gate that blocks snapshots.
    require("journal").install()
    local persistence = require("persistence")
    persistence.install_boot_hooks()

    if LoadAsset then
        for _, piece in ipairs(pieces.all()) do
            if piece.pak_first and piece.da_path then
                local pkg = piece.da_path:match("^(.-)%.[^%.]+$") or piece.da_path
                pcall(function() LoadAsset(pkg) end)
            end
        end
    end

    persistence.register_all("startup")
end)

if RegisterConsoleCommandHandler then
    RegisterConsoleCommandHandler("rsdw_builds_diag", function()
        run_gt(function()
            local catalogue = require("catalogue")
            local assets = require("assets")
            catalogue.diag(pieces.all(), assets.load)
        end)
        return true
    end)
    -- Legacy alias
    RegisterConsoleCommandHandler("blank_menu_diag", function()
        run_gt(function()
            local catalogue = require("catalogue")
            local assets = require("assets")
            catalogue.diag(pieces.all(), assets.load)
        end)
        return true
    end)
    -- Piece journal: status + manual resurrection trigger.
    RegisterConsoleCommandHandler("rsdw_journal", function()
        run_gt(function() require("journal").diag() end)
        return true
    end)
    RegisterConsoleCommandHandler("rsdw_restore", function()
        run_gt(function() require("journal").force_restore() end)
        return true
    end)
    -- Kill vanilla "twin" walls standing on top of native custom pieces.
    RegisterConsoleCommandHandler("rsdw_cleanup", function()
        run_gt(function() require("journal").cleanup_twins() end)
        return true
    end)
    -- Dump all UFunctions of the building classes (find the real demolish call).
    RegisterConsoleCommandHandler("rsdw_funcs", function()
        run_gt(function() require("journal").dump_funcs() end)
        return true
    end)
end

print(TAG .. " ready — vanilla build menu only; " .. #pieces.all() .. " piece(s)")
