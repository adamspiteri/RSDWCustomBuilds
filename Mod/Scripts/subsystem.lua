-- Live BuildingPieceSubsystem lookup (separate chunk to stay under Lua's 200-local limit).
local M = {}

local cached_live_subsystem = nil

local function is_valid(obj)
    if type(obj) ~= "userdata" then return false end
    if not obj.IsValid then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

local function subsystem_full_name(sub)
    if not is_valid(sub) then return nil end
    local fn = nil
    pcall(function() fn = sub:GetFullName() end)
    return type(fn) == "string" and fn or nil
end

local function is_live_subsystem(sub)
    if not is_valid(sub) then return false end
    local fn = subsystem_full_name(sub)
    if not fn then return true end
    if fn:find("Default__", 1, true) then return false end
    return true
end

function M.invalidate()
    cached_live_subsystem = nil
end

local function get_game_instance_live()
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and type(ue) == "table" and ue.GetGameInstance then
        local gi = nil
        pcall(function() gi = ue.GetGameInstance() end)
        if is_valid(gi) then return gi end
    end
    if not FindAllOf then return nil end
    for _, class_name in ipairs({ "DominionGameInstance", "GameInstance" }) do
        local ok, list = pcall(FindAllOf, class_name)
        if ok and list then
            local n = 0
            pcall(function() n = #list end)
            for i = 1, n do
                local eok, entry = pcall(function() return list[i] end)
                if eok and is_valid(entry) then
                    local fn = subsystem_full_name(entry)
                    if fn and not fn:find("Default__", 1, true) then
                        return entry
                    end
                end
            end
        end
    end
    return nil
end

local function find_all_live(class_name)
    local out = {}
    if not FindAllOf then return out end
    local ok, list = pcall(FindAllOf, class_name)
    if not ok or not list then return out end
    local n = 0
    pcall(function() n = #list end)
    if n == 0 then
        local ok_num, num_val = pcall(function() return list:Num() end)
        if ok_num and type(num_val) == "number" then n = num_val end
    end
    for i = 1, n do
        local eok, entry = pcall(function() return list[i] end)
        if eok and is_live_subsystem(entry) then
            out[#out + 1] = entry
        end
    end
    return out
end

function M.collect_all(primary)
    local out = {}
    local seen = {}
    local function add(s)
        if not s then return end
        local key = s
        pcall(function()
            local fn = s:GetFullName()
            if type(fn) == "string" and fn ~= "" then key = fn end
        end)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = s
    end
    add(primary)
    if not primary then add(M.find()) end
    for _, s in ipairs(find_all_live("BuildingPieceSubsystem")) do add(s) end
    return out
end

function M.all()
    return find_all_live("BuildingPieceSubsystem")
end

-- Must return the live GameInstance subsystem, not Default__BuildingPieceSubsystem.
function M.find()
    if is_valid(cached_live_subsystem) and is_live_subsystem(cached_live_subsystem) then
        return cached_live_subsystem
    end
    cached_live_subsystem = nil

    local live = find_all_live("BuildingPieceSubsystem")
    if live[1] then
        cached_live_subsystem = live[1]
        return live[1]
    end

    local gi = get_game_instance_live()
    if is_valid(gi) and StaticFindObject and gi.GetSubsystem then
        local cls = StaticFindObject("/Script/Dominion.BuildingPieceSubsystem")
        if cls then
            local ok, sub = pcall(function() return gi:GetSubsystem(cls) end)
            if ok and is_live_subsystem(sub) then
                cached_live_subsystem = sub
                return sub
            end
        end
    end

    if FindFirstOf then
        local ok, sub = pcall(FindFirstOf, "BuildingPieceSubsystem")
        if ok and is_live_subsystem(sub) then
            cached_live_subsystem = sub
            return sub
        end
    end
    return nil
end

return M


