-- Preview/placed mesh + stability fixes (ported from RSDWCustomBuilding).

local M = {}



local TAG = "[RSDWBuilds]"

local assets = require("assets")



local STABILITY_DT = "/Game/Gameplay/BaseBuilding_New/DT_StabilityProfile.DT_StabilityProfile"



local DONOR_VANILLA_DA = {

    foundation_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/DA_T1_Foundation_Large.DA_T1_Foundation_Large",

    foundation_med = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/DA_T1_Foundation_Med.DA_T1_Foundation_Med",

    wall_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Walls/DA_T1_Wall_Large.DA_T1_Wall_Large",

    floor_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Floors/DA_T1_Floor_Large.DA_T1_Floor_Large",

}



local DONOR_STABILITY_ROW = {

    foundation_large = "Tier1_Foundation",

    foundation_med = "Tier1_Foundation",

    wall_large = "Tier1_Base",

    floor_large = "Tier1_Floor",

}



-- The proven mod points BuildableActor at the VANILLA blueprint (valid stability/collision/snap
-- baked in) and shows the custom mesh via ProxyMesh + runtime mesh swap. Custom BPs lose their
-- stability wiring during the retoc/UAssetGUI clone, so LoadStabilityProfile fails on spawn.

local DONOR_VANILLA_BP = {

    foundation_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/BP_T1_Foundation_Large.BP_T1_Foundation_Large_C",

    foundation_med = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/BP_T1_Foundation_Med.BP_T1_Foundation_Med_C",

    wall_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Walls/BP_T1_Wall_Large.BP_T1_Wall_Large_C",

    floor_large = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Floors/BP_T1_Floor_Large.BP_T1_Floor_Large_C",

}



local _sm_cls = nil



local function is_valid(obj)

    return assets.is_valid(obj)

end



local function load_object(path)

    return assets.load(path)

end



local function weak_get(wptr)

    if not wptr then return nil end

    if type(wptr) == "userdata" and is_valid(wptr) then return wptr end

    local ok, v = pcall(function() return wptr:Get() end)

    if ok and is_valid(v) then return v end

    ok, v = pcall(function() return wptr:get() end)

    if ok and is_valid(v) then return v end

    return nil

end



local function tarray_len(arr)

    if type(arr) ~= "userdata" and type(arr) ~= "table" then return 0 end

    local n = 0

    pcall(function() n = #arr end)

    if n == 0 then

        pcall(function() if arr.Num then n = arr:Num() end end)

    end

    return n or 0

end



local function tarray_get(arr, i)

    local v = nil

    pcall(function() v = arr[i] end)

    return v

end



local function static_mesh_component_class()

    if _sm_cls and is_valid(_sm_cls) then return _sm_cls end

    if StaticFindObject then

        local ok, cls = pcall(StaticFindObject, "/Script/Engine.StaticMeshComponent")

        if ok and is_valid(cls) then

            _sm_cls = cls

            return _sm_cls

        end

    end

    return nil

end



local function foreach_static_mesh_component(actor, fn)

    if not is_valid(actor) or type(fn) ~= "function" then return 0 end

    local seen, n = {}, 0

    local function visit(comp)

        if not is_valid(comp) or not comp.SetStaticMesh then return end

        local key = tostring(comp)

        if seen[key] then return end

        seen[key] = true

        if fn(comp) then n = n + 1 end

    end

    local cls = static_mesh_component_class()

    if cls then

        local arr

        if actor.GetComponentsByClass then

            pcall(function() arr = actor:GetComponentsByClass(cls) end)

        end

        if not arr and actor.K2_GetComponentsByClass then

            pcall(function() arr = actor:K2_GetComponentsByClass(cls) end)

        end

        if arr then

            for i = 1, tarray_len(arr) do visit(tarray_get(arr, i)) end

        end

    end

    pcall(function()

        local cached = actor.CachedMeshes

        if cached then

            for i = 1, tarray_len(cached) do visit(tarray_get(cached, i)) end

        end

    end)

    local getters = {

        function() return actor.StaticMesh end,

        function() return actor:GetStaticMeshComponent() end,

        function() return actor.StaticMeshComponent end,

        function() return actor.Mesh end,

    }

    for _, g in ipairs(getters) do

        local okc, comp = pcall(g)

        if okc then visit(comp) end

    end

    return n

end



local function set_comp_static_mesh(comp, mesh)

    if not is_valid(comp) or not mesh or not comp.SetStaticMesh then return false end

    local ok = pcall(function() comp:SetStaticMesh(mesh) end)

    if ok then

        pcall(function() if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end end)

    end

    return ok

end



local function fname_label(v)

    if type(v) == "string" and v ~= "" and v ~= "None" then return v end

    if type(v) == "userdata" and v.ToString then

        local ok, s = pcall(function() return v:ToString() end)

        if ok and type(s) == "string" and s ~= "" and s ~= "None" then return s end

    end

    return nil

end



local function stability_row_handle_valid(da)

    if not da then return false end

    local ok, valid = pcall(function()

        local h = da.BuildingStabilityProfileRowHandle

        if not h or not fname_label(h.RowName) then return false end

        local dt = h.DataTable

        return dt ~= nil and (type(dt) == "userdata" and is_valid(dt))

    end)

    return ok and valid == true

end



local function stability_row_native_resolves(da)

    if not da then return false end

    local ok, resolved = pcall(function()

        local h = da.BuildingStabilityProfileRowHandle

        if not h then return false end

        local dt = h.DataTable

        if not is_valid(dt) then return false end

        local row_name = fname_label(h.RowName)

        if not row_name then return false end

        if dt.FindRow then

            if dt:FindRow(row_name) ~= nil then return true end

            if FName then

                local ok_fn, fn = pcall(function() return FName(row_name) end)

                if ok_fn and fn and dt:FindRow(fn) ~= nil then return true end

            end

        end

        return false

    end)

    return ok and resolved == true

end



local function make_stability_handle(row_name)

    local dt = load_object(STABILITY_DT)

    if not is_valid(dt) then return nil end

    local row = row_name

    local ok_ue, ue = pcall(require, "UEHelpers")

    if ok_ue and ue and ue.FindOrAddFName then

        pcall(function() row = ue.FindOrAddFName(row_name) end)

    elseif FName then

        pcall(function() row = FName(row_name) end)

    end

    return { DataTable = dt, RowName = row }

end



local function assign_stability_row_handle(da, handle)

    if not da or not handle then return false end

    if pcall(function() da.BuildingStabilityProfileRowHandle = handle end)

        and stability_row_handle_valid(da) then

        return true

    end

    pcall(function()

        local h = da.BuildingStabilityProfileRowHandle

        if h then

            h.DataTable = handle.DataTable

            h.RowName = handle.RowName

        end

    end)

    return stability_row_handle_valid(da)

end



local function copy_stability_from_donor(da, entry)

    local donor = (entry and entry.donor) or "foundation_large"

    local vanilla_path = DONOR_VANILLA_DA[donor] or DONOR_VANILLA_DA.foundation_large

    local vanilla = load_object(vanilla_path)

    if is_valid(vanilla) then

        pcall(function() da.BuildingStabilityProfileRowHandle = vanilla.BuildingStabilityProfileRowHandle end)

        if stability_row_native_resolves(da) or stability_row_handle_valid(da) then

            return true

        end

        pcall(function()

            local vh = vanilla.BuildingStabilityProfileRowHandle

            if vh then

                assign_stability_row_handle(da, {

                    DataTable = vh.DataTable,

                    RowName = vh.RowName,

                })

            end

        end)

        if stability_row_native_resolves(da) or stability_row_handle_valid(da) then

            return true

        end

    end

    local row = DONOR_STABILITY_ROW[donor] or DONOR_STABILITY_ROW.foundation_large

    local handle = make_stability_handle(row)

    if handle and assign_stability_row_handle(da, handle) then

        return stability_row_native_resolves(da) or stability_row_handle_valid(da)

    end

    return false

end



local function ensure_da_stability_profile(da, entry, force)

    if not da then return false end

    if not force and stability_row_native_resolves(da) then return true end

    if LoadAsset then pcall(function() LoadAsset(STABILITY_DT) end) end

    copy_stability_from_donor(da, entry)

    return stability_row_native_resolves(da) or stability_row_handle_valid(da)

end



-- Read the current BuildableActor as a printable path (for diagnostics).
function M.buildable_label(da)

    if not da then return "nil-da" end

    local label = "?"

    pcall(function()

        local v = da.BuildableActor

        if v == nil then label = "nil" return end

        if type(v) == "userdata" then

            if v.GetFullName then label = v:GetFullName() return end

            if v.ToString then label = v:ToString() return end

            if v.AssetPath and v.AssetPath.AssetName then label = tostring(v.AssetPath.AssetName) return end

        end

        label = tostring(v)

    end)

    return label

end



-- Point BuildableActor at the vanilla donor BP class so the game spawns a fully-wired actor
-- (valid stability profile, collision, snapping). Returns true if it appears to have stuck.
function M.retarget_buildable_to_vanilla(da, entry)

    if not da then return false end

    local donor = (entry and entry.donor) or "foundation_large"

    local bp_obj_path = DONOR_VANILLA_BP[donor] or DONOR_VANILLA_BP.foundation_large

    if LoadAsset then

        local pkg = bp_obj_path:match("^(.-)%.[^%.]+$") or bp_obj_path

        pcall(function() LoadAsset(pkg) end)

    end

    local bp_cls = load_object(bp_obj_path)

    if not is_valid(bp_cls) then

        print(TAG .. " retarget: vanilla BP class not loaded (" .. tostring(bp_obj_path) .. ")")

        return false

    end

    local before = M.buildable_label(da)

    local applied = false

    -- TSoftClassPtr: assigning the UClass userdata directly is the usual UE4SS path.

    pcall(function() da.BuildableActor = bp_cls applied = true end)

    if not applied then

        pcall(function()

            local v = da.BuildableActor

            if v and v.SetAsset then v:SetAsset(bp_cls) applied = true end

        end)

    end

    local after = M.buildable_label(da)

    print(TAG .. " retarget BuildableActor: '" .. tostring(before) .. "' -> '" .. tostring(after) .. "'")

    return applied

end



function M.prepare_da(da, entry, mesh)

    if not da then return false end

    ensure_da_stability_profile(da, entry, true)

    -- NOTE: do NOT assign da.BuildableActor or da.BuildingPieceProxyData.ProxyMesh at runtime —
    -- writing those soft-object/soft-class properties in-memory hard-crashes the game.
    -- BuildableActor (vanilla BP) and ProxyMesh (SM_Stonewall) are already baked into the .uasset.
    -- The placed actor's visible mesh is swapped post-spawn via SetStaticMesh (safe), not here.

    return true

end



local function patch_actor_mesh(actor, mesh)

    if not is_valid(actor) or not is_valid(mesh) then return false end

    local changed = false

    foreach_static_mesh_component(actor, function(comp)

        if set_comp_static_mesh(comp, mesh) then

            changed = true

            return true

        end

        return false

    end)

    return changed

end



local function patch_preview_actor(bmc, da, mesh)

    if not is_valid(bmc) or not is_valid(mesh) then return false end

    local preview = weak_get(bmc.PreviewPiece)

    if not is_valid(preview) then return false end

    local changed = false

    if da then

        ensure_da_stability_profile(da, nil, true)

        pcall(function()

            preview.BuildingPieceData = da

            changed = true

        end)

        pcall(function() preview.StabilityValue = 1.0 end)

    end

    if patch_actor_mesh(preview, mesh) then changed = true end

    return changed

end



function M.apply_preview_patch(bmc, da, mesh)

    if not is_valid(bmc) or not is_valid(mesh) then return 0 end

    if patch_preview_actor(bmc, da, mesh) then

        print(TAG .. " preview mesh patched")

        return 1

    end

    return 0

end



function M.schedule_preview_retries(bmc, da, mesh, max_ticks)

    if not LoopAsync then return end

    max_ticks = max_ticks or 10

    local ticks = 0

    LoopAsync(200, function()

        ticks = ticks + 1

        local run = function()

            if is_valid(bmc) and is_valid(mesh) then

                M.apply_preview_patch(bmc, da, mesh)

            end

        end

        if ExecuteInGameThread then ExecuteInGameThread(run) else run() end

        return ticks >= max_ticks

    end)

end



-- Short class-name(s) of the vanilla BP the piece spawns as (used to locate the placed actor).
function M.donor_bp_class_names(entry)

    local donor = (entry and entry.donor) or "foundation_large"

    local path = DONOR_VANILLA_BP[donor] or DONOR_VANILLA_BP.foundation_large

    local short = path:match("%.([%w_]+)$") or path

    return { short }

end



function M.patch_actor_mesh(actor, mesh)

    return patch_actor_mesh(actor, mesh)

end



-- Find recently-spawned building actors near `loc` and swap their mesh to ours.
-- Tracks which actors we've already patched so repeated polls don't re-patch.
local placed_seen = {}

function M.patch_recent_placed(loc, mesh, class_names)

    if not is_valid(mesh) then return 0 end

    class_names = class_names or {}

    local patched = 0

    for _, cn in ipairs(class_names) do

        if FindAllOf then

            local ok, list = pcall(FindAllOf, cn)

            if ok and list then

                for i = 1, tarray_len(list) do

                    local a = tarray_get(list, i)

                    if is_valid(a) then

                        local key = tostring(a)

                        local near = true

                        if loc then

                            local al

                            pcall(function() al = a:K2_GetActorLocation() end)

                            if al and type(al.X) == "number" then

                                local dx = (al.X - (loc.X or 0))

                                local dy = (al.Y - (loc.Y or 0))

                                local dz = (al.Z - (loc.Z or 0))

                                near = (dx * dx + dy * dy + dz * dz) < (2500 * 2500)

                            end

                        end

                        if near then
                            -- Native placement can leave the spawned BP as a construction ghost.
                            -- Clear those flags every retry; only count/log each actor once.
                            pcall(function() a.bIsPreview = false end)
                            pcall(function() a.bIsGhosted = false end)
                            pcall(function() a.bHidden = false end)
                            pcall(function() a.StabilityValue = 1.0 end)
                            pcall(function() if a.SetActorHiddenInGame then a:SetActorHiddenInGame(false) end end)
                            pcall(function() if a.SetActorEnableCollision then a:SetActorEnableCollision(true) end end)
                            pcall(function() if a.K2_SetActorEnableCollision then a:K2_SetActorEnableCollision(true) end end)
                            patch_actor_mesh(a, mesh)
                            if not placed_seen[key] then
                                placed_seen[key] = true
                                patched = patched + 1
                            end
                        end

                    end

                end

            end

        end

    end

    if patched > 0 then

        print(TAG .. " placed actor finalized (" .. patched .. ")")

    end

    return patched

end



-- The placed actor appears a frame or two after Server_SpawnBuilding; poll briefly to catch it.
function M.schedule_placed_patch(loc, mesh, class_names, ticks)

    if not LoopAsync or not is_valid(mesh) then return end

    ticks = ticks or 10

    local n = 0

    LoopAsync(150, function()

        n = n + 1

        local run = function() M.patch_recent_placed(loc, mesh, class_names) end

        if ExecuteInGameThread then ExecuteInGameThread(run) else run() end

        return n >= ticks

    end)

end



return M

