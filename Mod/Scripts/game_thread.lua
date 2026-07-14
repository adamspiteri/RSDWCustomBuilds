local M = {}

local TAG = "[RSDWBuilds]"

function M.run(fn)
    if ExecuteInGameThread then
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then
                print(TAG .. " error: " .. tostring(err))
            end
        end)
    else
        pcall(fn)
    end
end

return M


