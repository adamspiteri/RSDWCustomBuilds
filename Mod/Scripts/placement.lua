-- Forward placement offset helpers (separate chunk -- Lua 200-local limit in building.lua).
local M = {}

local TAG, PLACE_FORWARD_DIST, PLACE_LARGE_MESH_EXTRA
local is_valid, copy_vector, dist_sq, dist_sq_xy
local get_local_pawn, get_local_player_controller, trace_ground_z
local weak_get, capture_deferred_preview_loc

function M.bind(deps)
    TAG = deps.TAG
    PLACE_FORWARD_DIST = deps.PLACE_FORWARD_DIST
    PLACE_LARGE_MESH_EXTRA = deps.PLACE_LARGE_MESH_EXTRA
    is_valid = deps.is_valid
    copy_vector = deps.copy_vector
    dist_sq = deps.dist_sq
    dist_sq_xy = deps.dist_sq_xy
    get_local_pawn = deps.get_local_pawn
    get_local_player_controller = deps.get_local_player_controller
    trace_ground_z = deps.trace_ground_z
    weak_get = deps.weak_get
    capture_deferred_preview_loc = deps.capture_deferred_preview_loc
end

local function get_facing_yaw()
    local yaw = 0
    local pc = get_local_player_controller()
    if is_valid(pc) and pc.GetControlRotation then
        pcall(function()
            local rot = pc:GetControlRotation()
            if rot then yaw = rot.Yaw or 0 end
        end)
        return yaw
    end
    local pawn = get_local_pawn()
    if is_valid(pawn) then
        pcall(function()
            local rot = pawn:K2_GetActorRotation()
            if rot then yaw = rot.Yaw or 0 end
        end)
    end
    return yaw
end

local function push_location_forward(loc, yaw, extra)
    if not loc or not extra or extra <= 0 then return loc end
    local rad = (yaw or 0) * math.pi / 180.0
    return {
        X = (loc.X or 0) + math.cos(rad) * extra,
        Y = (loc.Y or 0) + math.sin(rad) * extra,
        Z = loc.Z or 0,
    }
end

function M.pawn_front_location(dist)
    local pawn = get_local_pawn()
    if not is_valid(pawn) then return nil end
    local loc
    pcall(function() loc = pawn:K2_GetActorLocation() end)
    if not loc then return nil end
    local yaw = get_facing_yaw()
    local rad = yaw * math.pi / 180.0
    local target = {
        X = (loc.X or 0) + math.cos(rad) * (dist or PLACE_FORWARD_DIST),
        Y = (loc.Y or 0) + math.sin(rad) * (dist or PLACE_FORWARD_DIST),
        Z = loc.Z or 0,
    }
    local ground_z, snapped = trace_ground_z(target.X, target.Y, target.Z, pawn)
    target.Z = ground_z
    if not snapped then
        print(TAG .. " spawn: ground trace missed; using pawn Z (may float)")
    end
    return target, yaw
end

function M.ensure_forward_placement(loc, rot)
    if not loc then return loc, rot end
    rot = rot or { Pitch = 0, Yaw = 0, Roll = 0 }
    local yaw = rot.Yaw or get_facing_yaw()
    rot.Yaw = yaw

    local pawn = get_local_pawn()
    if is_valid(pawn) then
        local ploc
        pcall(function() ploc = copy_vector(pawn:K2_GetActorLocation()) end)
        if ploc then
            local min_d = PLACE_FORWARD_DIST
            local min_d2 = min_d * min_d
            if dist_sq_xy(ploc, loc) < min_d2 then
                local pushed, pyaw = M.pawn_front_location(min_d)
                if pushed then
                    loc = pushed
                    yaw = pyaw or yaw
                    rot.Yaw = yaw
                end
            end
        end
    end

    loc = push_location_forward(loc, yaw, PLACE_LARGE_MESH_EXTRA)
    if is_valid(pawn) then
        local ground_z = select(1, trace_ground_z(loc.X, loc.Y, loc.Z, pawn))
        if ground_z then loc.Z = ground_z end
    end
    return loc, rot
end

function M.nudge_preview_forward(bmc)
    if not is_valid(bmc) then return false end
    local preview = weak_get(bmc.PreviewPiece)
    if not is_valid(preview) then return false end
    local loc
    pcall(function() loc = copy_vector(preview:K2_GetActorLocation()) end)
    if not loc then return false end
    local rot
    pcall(function()
        local r = preview:K2_GetActorRotation()
        if r then rot = { Pitch = r.Pitch or 0, Yaw = r.Yaw or 0, Roll = r.Roll or 0 } end
    end)
    local new_loc, new_rot = M.ensure_forward_placement(loc, rot)
    if not new_loc then return false end
    if dist_sq(loc, new_loc) <= 4 then return false end
    local ok = false
    pcall(function()
        ok = preview:K2_SetActorLocation(new_loc, false, {}, false)
    end)
    if ok then
        pcall(function()
            if new_rot and preview.K2_SetActorRotation then
                preview:K2_SetActorRotation(new_rot, false)
            end
        end)
        capture_deferred_preview_loc(bmc)
    end
    return ok
end

return M


