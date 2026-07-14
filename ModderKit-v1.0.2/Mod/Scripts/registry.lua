-- RSDW Custom Builds — manifest-driven registry (no per-piece code)
local M = {}

local TAG = "[RSDWBuilds]"
local UNLOCKED_KEY = "RSDW_BUILDS_UNLOCKED"

local manifest = nil
local STATUS_FILE = nil
local assets = require("assets")
local persistence = require("persistence")

local function status_file_path()
    if STATUS_FILE then return STATUS_FILE end
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local dir = src:match("^(.+[\\/])") or ""
    dir = dir:gsub("/", "\\")
    STATUS_FILE = dir .. "..\\last_status.txt"
    return STATUS_FILE
end

local function write_status_file(text)
    local path = status_file_path()
    local f = io.open(path, "w")
    if not f then return end
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. "\r\n")
    f:write(tostring(text))
    f:write("\r\n\r\nOpen full log:\r\n")
    f:write("E:\\SteamLibrary\\steamapps\\common\\RSDragonwilds\\RSDragonwilds\\Binaries\\Win64\\ue4ss\\UE4SS.log\r\n")
    f:close()
end

local function is_valid(obj)
    return assets.is_valid(obj)
end

local function get_print_context()
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and type(ue) == "table" then
        if ue.GetPlayerController then
            local ok, pc = pcall(function() return ue:GetPlayerController() end)
            if ok and is_valid(pc) then return pc end
        end
        if ue.GetWorld then
            local ok, w = pcall(function() return ue:GetWorld() end)
            if ok and is_valid(w) then return w end
        end
    end
    return nil
end

local function notify(msg, duration)
    duration = duration or 8.0
    local line = TAG .. " " .. tostring(msg)
    print(line)
    write_status_file(line)
    local ksl = StaticFindObject and StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not is_valid(ksl) or not ksl.PrintString then return end
    local ctx = get_print_context()
    if not is_valid(ctx) then return end
    pcall(function()
        ksl:PrintString(
            ctx,
            TAG .. " " .. tostring(msg),
            true,
            false,
            { R = 1.0, G = 0.85, B = 0.2, A = 1.0 },
            duration,
            FName("RSDWBuildsNotify")
        )
    end)
end

local function log(msg)
    notify(msg)
end

local function load_object(path)
    return assets.load(path)
end

local function read_manifest()
    if manifest then return manifest end
    local ok, data = pcall(require, "pieces_data")
    if ok and type(data) == "table" then
        manifest = data
        return manifest
    end
    log("missing pieces_data.lua - run Build-Piece.bat first")
    return nil
end

local function get_progress_component()
    local ok_ue, ue = pcall(require, "UEHelpers")
    if not ok_ue or type(ue) ~= "table" then return nil end
    local pc
    if ue.GetPlayerController then
        pcall(function() pc = ue:GetPlayerController() end)
    end
    if not is_valid(pc) and ue.GetPlayer then
        local pawn
        pcall(function() pawn = ue:GetPlayer() end)
        if is_valid(pawn) then
            pcall(function() pc = pawn:GetController() end)
        end
    end
    if not is_valid(pc) then return nil end
    local prog
    pcall(function() prog = pc.ProgressComponent end)
    if is_valid(prog) then return prog end
    return nil
end

function M.unlock_all()
    if rawget(_G, UNLOCKED_KEY) then return true end
    local m = read_manifest()
    if not m or type(m.pieces) ~= "table" then return false end
    local prog = get_progress_component()
    if not is_valid(prog) or not prog.UnlockBuildings then
        log("ProgressComponent not ready - enter world first, then retry")
        return false
    end
    local das = {}
    local count = 0
    for _, entry in ipairs(m.pieces) do
        local da_path = entry.da_path
        if type(da_path) == "string" then
            local da = load_object(da_path)
            if is_valid(da) then
                das[#das + 1] = da
                count = count + 1
            else
                log("DA not mounted: " .. da_path)
            end
        end
    end
    if count == 0 then
        log("no DAs loaded - pak/DA not ready yet (mesh-only build is OK)")
        return false
    end
    persistence.register_all("unlock_all")
    pcall(function() prog:UnlockBuildings(das) end)
    rawset(_G, UNLOCKED_KEY, true)
    log("unlocked " .. count .. " piece(s)")
    return true
end

function M.list()
    local m = read_manifest()
    if not m or type(m.pieces) ~= "table" then
        notify("no pieces in manifest")
        return
    end
    notify("pieces in manifest: " .. #m.pieces .. " (see UE4SS.log for list)", 6.0)
    for _, entry in ipairs(m.pieces) do
        notify(string.format("%s - %s", entry.id or "?", entry.display_name or "?"), 5.0)
    end
end

function M.status()
    local m = read_manifest()
    local n = (m and m.pieces) and #m.pieces or 0
    local unlocked = rawget(_G, UNLOCKED_KEY) == true
    notify("manifest pieces: " .. n .. " | unlocked: " .. tostring(unlocked), 10.0)
end

function M.notify(msg, duration)
    notify(msg, duration)
end

return M
