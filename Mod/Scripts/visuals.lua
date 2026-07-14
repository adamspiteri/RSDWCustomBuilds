-- Runtime Stonewall visuals: swap mesh + brick textures for DA_T1_Wall_Large placements.
local M = {}

local assets = require("assets")
local subsystem = require("subsystem")
local TAG = "[RSDWBuilds/visuals]"

local K = {
    MESH = "/Game/RSDWBuilds/Stonewall/SM_Stonewall.SM_Stonewall",
    DA = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Walls/DA_T1_Wall_Large.DA_T1_Wall_Large",
    PERSIST = "ra70cEh9cDOb_leFJwQE2Q",
    MID = "RSDW_StonewallMat",
    WALL_MARK = "Wall_Large",
    WALL_BP = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Walls/BP_T1_Wall_Large.BP_T1_Wall_Large_C",
    MASTERS = {
        "/Game/Materials/Environment/M_Standard_Env_MR.M_Standard_Env_MR",
        "/Game/Art/Env/Architecture/DowdunReach/Materials/MT_DR_BrickWall_04.MT_DR_BrickWall_04",
    },
    BASE = "/Game/RSDWBuilds/Stonewall/T_Walls.T_Walls",
    NORM = "/Game/RSDWBuilds/Stonewall/T_Walls_N.T_Walls_N",
    BASECOLOR = { "BaseColor", "Base Color", "Diffuse", "Albedo", "Color", "Texture" },
    NORMAL = { "Normal", "NormalMap", "Normal Map", "Bump", "BumpMap" },
    SCALAR = {
        { "Metallic", 0.0 }, { "Metallic Intensity", 0.0 }, { "MetallicIntensity", 0.0 }, { "Metal", 0.0 },
        { "Roughness", 1.0 }, { "Roughness Intensity", 1.0 }, { "RoughnessIntensity", 1.0 },
        { "Specular", 0.0 }, { "Specular Intensity", 0.0 }, { "SpecularIntensity", 0.0 },
        { "Reflectance", 0.0 }, { "Env Reflections", 0.0 },
    },
}

local cache = { mesh = nil, da = nil, da_idx = nil, master = nil, base = nil, norm = nil }
local finished = {}
local _sm_cls = nil
local tracked_preview = nil
local last_preview_loc = nil
local stonewall_session = false
local last_session_was_stonewall = false
local piece_ids_snapshot = nil
local placement_window = 0
local had_preview_last_tick = false

local function is_valid(obj)
    return assets.is_valid(obj)
end

local function fname(s)
    return (FName and FName(s)) or s
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
    if n == 0 then pcall(function() if arr.Num then n = arr:Num() end end) end
    return n or 0
end

local function tarray_get(arr, i)
    local v = nil
    pcall(function() v = arr[i] end)
    return v
end

local function full_name(obj)
    if not is_valid(obj) then return "" end
    local n = ""
    pcall(function() if obj.GetFullName then n = obj:GetFullName() end end)
    return n or tostring(obj)
end

local function as_string(v)
    if type(v) == "string" then return v end
    if v == nil then return "" end
    return tostring(v)
end

local function uobject_same(a, b)
    if not is_valid(a) or not is_valid(b) then return false end
    if a == b then return true end
    return full_name(a) == full_name(b)
end

local function actor_class_name(actor)
    if not is_valid(actor) then return "" end
    local cn = full_name(actor)
    pcall(function()
        local cls = actor:GetClass()
        if is_valid(cls) then cn = full_name(cls) end
    end)
    return cn
end

local function actor_is_wall_large(actor)
    return actor_class_name(actor):find(K.WALL_MARK, 1, true) ~= nil
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
    if not is_valid(actor) or type(fn) ~= "function" then return end
    local seen = {}
    local function visit(comp)
        if not is_valid(comp) or not comp.SetStaticMesh then return end
        local key = tostring(comp)
        if seen[key] then return end
        seen[key] = true
        fn(comp)
    end
    local cls = static_mesh_component_class()
    if cls then
        local arr
        if actor.GetComponentsByClass then pcall(function() arr = actor:GetComponentsByClass(cls) end) end
        if not arr and actor.K2_GetComponentsByClass then pcall(function() arr = actor:K2_GetComponentsByClass(cls) end) end
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
    for _, g in ipairs({
        function() return actor.Mesh end,
        function() return actor:GetStaticMeshComponent() end,
        function() return actor.StaticMeshComponent end,
        function() return actor.StaticMesh end,
        function() return actor.StaticMeshComponent0 end,
    }) do
        local okc, comp = pcall(g)
        if okc then visit(comp) end
    end
end

local function comp_mesh(comp)
    local mesh = nil
    pcall(function() mesh = comp.StaticMesh end)
    if not is_valid(mesh) and comp.GetStaticMesh then
        pcall(function() mesh = comp:GetStaticMesh() end)
    end
    return mesh
end

local function comp_is_stonewall(comp)
    return full_name(comp_mesh(comp)):find("SM_Stonewall", 1, true) ~= nil
end

local function comp_has_stone_mat(comp)
    if not comp.GetMaterial then return false end
    local mat = nil
    pcall(function() mat = comp:GetMaterial(0) end)
    return full_name(mat):find(K.MID, 1, true) ~= nil
end

local function refresh_da_index()
    if not is_valid(cache.da) then return end
    pcall(function() cache.da_idx = cache.da.BuildingPieceDataIndex end)
end

local function ensure_assets()
    if not is_valid(cache.mesh) then cache.mesh = assets.load(K.MESH) end
    if not is_valid(cache.da) then cache.da = assets.load(K.DA) end
    if is_valid(cache.da) and cache.da_idx == nil then refresh_da_index() end
    if not is_valid(cache.master) then
        for _, p in ipairs(K.MASTERS) do
            cache.master = assets.load(p)
            if is_valid(cache.master) then break end
        end
    end
    if not is_valid(cache.base) then cache.base = assets.load(K.BASE) end
    if not is_valid(cache.norm) then cache.norm = assets.load(K.NORM) end
    return is_valid(cache.mesh)
end

local function piece_data_is_stonewall(pd)
    if not is_valid(pd) then return false end
    if is_valid(cache.da) and uobject_same(pd, cache.da) then return true end
    if full_name(pd):find("DA_T1_Wall_Large", 1, true) then return true end
    local pid = nil
    pcall(function() pid = pd.PersistenceID end)
    if as_string(pid) == K.PERSIST then return true end
    if pd.GetPersistenceID then
        local ok, got = pcall(function() return pd:GetPersistenceID() end)
        if ok and as_string(got) == K.PERSIST then return true end
    end
    return false
end

local function actor_is_stonewall_piece(actor)
    if not is_valid(actor) then return false end
    local pd = nil
    pcall(function() pd = actor.BuildingPieceData end)
    if piece_data_is_stonewall(pd) then return true end
    local pid = nil
    pcall(function() pid = actor.PersistenceID end)
    if as_string(pid) == K.PERSIST then return true end
    if type(cache.da_idx) == "number" then
        local idx = nil
        pcall(function() idx = actor.BuildingPieceDataIndex end)
        if type(idx) == "number" and idx == cache.da_idx then return true end
    end
    return false
end

local function actor_fully_patched(actor)
    local key = tostring(actor)
    if finished[key] then return true end
    if not is_valid(actor) or not is_valid(cache.mesh) then return false end
    local ok_mesh, ok_mat, any = true, true, false
    foreach_static_mesh_component(actor, function(comp)
        any = true
        if not comp_is_stonewall(comp) then ok_mesh = false end
        if not comp_has_stone_mat(comp) then ok_mat = false end
    end)
    if any and ok_mesh and ok_mat then
        finished[key] = true
        return true
    end
    return false
end

local function apply_material_to_comp(comp)
    if not is_valid(comp) or not comp.CreateDynamicMaterialInstance then return false end
    if not comp_is_stonewall(comp) or comp_has_stone_mat(comp) then return false end
    if not is_valid(cache.master) then return false end
    local slots = 1
    pcall(function() if comp.GetNumMaterials then slots = comp:GetNumMaterials() end end)
    if type(slots) ~= "number" or slots < 1 then slots = 1 end
    local applied = false
    for s = 0, slots - 1 do
        local mid = nil
        local ok = pcall(function()
            mid = comp:CreateDynamicMaterialInstance(s, cache.master, fname(K.MID))
        end)
        if ok and is_valid(mid) then
            if is_valid(cache.base) then
                for _, p in ipairs(K.BASECOLOR) do
                    pcall(function() mid:SetTextureParameterValue(fname(p), cache.base) end)
                end
            end
            if is_valid(cache.norm) then
                for _, p in ipairs(K.NORMAL) do
                    pcall(function() mid:SetTextureParameterValue(fname(p), cache.norm) end)
                end
            end
            for _, sv in ipairs(K.SCALAR) do
                pcall(function() mid:SetScalarParameterValue(fname(sv[1]), sv[2]) end)
            end
            applied = true
        end
    end
    if applied then
        pcall(function() if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end end)
    end
    return applied
end

local function set_comp_mesh(comp, mesh)
    if not is_valid(comp) or not is_valid(mesh) then return false end
    local cur = comp_mesh(comp)
    if is_valid(cur) and cur == mesh then return false end
    local ok = pcall(function() comp:SetStaticMesh(mesh) end)
    if ok then
        pcall(function() if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end end)
    end
    return ok
end

local function patch_actor_meshes(actor)
    if not is_valid(actor) or not ensure_assets() then return false end
    if actor_fully_patched(actor) then return false end
    local changed = false
    foreach_static_mesh_component(actor, function(comp)
        if set_comp_mesh(comp, cache.mesh) then changed = true end
        if apply_material_to_comp(comp) then changed = true end
    end)
    if actor_fully_patched(actor) then
        finished[tostring(actor)] = true
    end
    return changed
end

function M.patch_actor(actor)
    if not is_valid(actor) then return false end
    if not actor_is_stonewall_piece(actor) and not actor_is_wall_large(actor) then return false end
    if not actor_is_stonewall_piece(actor) and not stonewall_session and place_burst <= 0 then
        return false
    end
    return patch_actor_meshes(actor)
end

local function find_building_subsystem()
    if FindFirstOf then
        local ok, sub = pcall(FindFirstOf, "BuildingSubsystem")
        if ok and is_valid(sub) then return sub end
    end
    return nil
end

local function unwrap_map_actor(v)
    if type(v) ~= "userdata" then return v end
    local got
    pcall(function() got = v:get() end)
    if not is_valid(got) then pcall(function() got = v:Get() end) end
    return is_valid(got) and got or v
end

local function foreach_subsystem_actor(fn)
    local sub = find_building_subsystem()
    if not is_valid(sub) then return 0 end
    local map = nil
    pcall(function() map = sub.PieceIDToBuildingPieceActor end)
    if not map or not map.ForEach then return 0 end
    local n = 0
    pcall(function()
        map:ForEach(function(_k, v)
            local actor = unwrap_map_actor(v)
            if is_valid(actor) then
                n = n + 1
                fn(actor)
            end
        end)
    end)
    return n
end

local function get_player_controller()
    if FindFirstOf then
        local ok, pc = pcall(FindFirstOf, "PlayerController")
        if ok and is_valid(pc) then return pc end
    end
    return nil
end

local function get_build_mode_component()
    local pc = get_player_controller()
    if not is_valid(pc) then return nil end
    local bmc = nil
    pcall(function() bmc = pc.BuildModeComponent end)
    if not is_valid(bmc) and pc.GetBuildModeComponent then
        pcall(function() bmc = pc:GetBuildModeComponent() end)
    end
    return is_valid(bmc) and bmc or nil
end

local function placing_stonewall(bmc)
    if not is_valid(bmc) or not ensure_assets() then return false end
    local cur = weak_get(bmc.CurrentlyPlacingPieceData)
    if piece_data_is_stonewall(cur) then return true end
    local preview = weak_get(bmc.PreviewPiece)
    if is_valid(preview) then
        local pd = nil
        pcall(function() pd = preview.BuildingPieceData end)
        if piece_data_is_stonewall(pd) then return true end
        if actor_is_wall_large(preview) then return true end
    end
    return false
end

local function actor_location(actor)
    if not is_valid(actor) then return nil end
    local loc = nil
    pcall(function() loc = actor:K2_GetActorLocation() end)
    return loc
end

local function near_loc(a, b, r)
    if not a or not b or type(a.X) ~= "number" or type(b.X) ~= "number" then return false end
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return (dx * dx + dy * dy + dz * dz) <= (r * r)
end

local function is_preview_actor(actor, bmc)
    if not is_valid(actor) then return false end
    local is_preview = false
    pcall(function() is_preview = actor.bIsPreview == true end)
    if is_preview then return true end
    if is_valid(bmc) then
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) and preview == actor then return true end
    end
    return false
end

local function snapshot_piece_ids()
    local ids = {}
    foreach_subsystem_actor(function(a)
        local id = nil
        pcall(function() id = a.BuildingPieceID end)
        if type(id) == "number" then ids[id] = true end
    end)
    return ids
end

local function find_new_subsystem_actor(before_ids, ref, radius)
    if not before_ids or not ref then return nil end
    radius = radius or 900
    local best, best_d2
    local max_d2 = radius * radius
    foreach_subsystem_actor(function(a)
        local id = nil
        pcall(function() id = a.BuildingPieceID end)
        if type(id) == "number" and before_ids[id] then return end
        if is_preview_actor(a, nil) then return end
        if not actor_is_wall_large(a) then return end
        local aloc = actor_location(a)
        if not aloc then return end
        local dx, dy, dz = aloc.X - ref.X, aloc.Y - ref.Y, aloc.Z - ref.Z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 <= max_d2 and (not best_d2 or d2 < best_d2) then
            best, best_d2 = a, d2
        end
    end)
    return best
end

local function run_on_game_thread(fn)
    if ExecuteInGameThread then ExecuteInGameThread(fn) else fn() end
end

local function finalize_placement(bmc)
    if not ensure_assets() then return end
    placement_window = 30

    if is_valid(tracked_preview) then
        pcall(function() tracked_preview.bIsPreview = false end)
        pcall(function() tracked_preview.bIsGhosted = false end)
        patch_actor_meshes(tracked_preview)
    end

    local placed = find_new_subsystem_actor(piece_ids_snapshot, last_preview_loc, 900)
    if is_valid(placed) then patch_actor_meshes(placed) end

    if last_preview_loc then
        M.patch_near_placed(last_preview_loc, 900)
    end
    M.patch_tracked_actor(bmc)
end

local function schedule_fast_retry(bmc, loc)
    if not LoopAsync or not loc then return end
    local ticks = 0
    LoopAsync(50, function()
        ticks = ticks + 1
        run_on_game_thread(function()
            M.patch_near_placed(loc, 900)
            M.patch_tracked_actor(bmc)
            local placed = find_new_subsystem_actor(piece_ids_snapshot, loc, 900)
            if is_valid(placed) then patch_actor_meshes(placed) end
        end)
        return ticks >= 12
    end)
end

function M.patch_preview(bmc)
    if not is_valid(bmc) or not placing_stonewall(bmc) or not ensure_assets() then return false end
    local preview = weak_get(bmc.PreviewPiece)
    if not is_valid(preview) or not actor_is_wall_large(preview) then return false end
    return patch_actor_meshes(preview)
end

function M.patch_near_placed(ref, radius)
    if not ensure_assets() or not ref then return 0 end
    radius = radius or 900
    local patched = 0
    foreach_subsystem_actor(function(a)
        if is_preview_actor(a, nil) then return end
        if not near_loc(actor_location(a), ref, radius) then return end
        if actor_is_stonewall_piece(a) or (stonewall_session and actor_is_wall_large(a)) then
            if patch_actor_meshes(a) then patched = patched + 1 end
        end
    end)
    if patched == 0 and FindAllOf then
        local ok, list = pcall(FindAllOf, "BP_T1_Wall_Large_C")
        if ok and list then
            for i = 1, tarray_len(list) do
                local a = tarray_get(list, i)
                if is_valid(a) and not is_preview_actor(a, nil)
                    and near_loc(actor_location(a), ref, radius)
                    and (actor_is_stonewall_piece(a) or stonewall_session) then
                    if patch_actor_meshes(a) then patched = patched + 1 end
                end
            end
        end
    end
    return patched
end

function M.patch_tracked_actor(bmc)
    if not ensure_assets() then return false end
    if is_valid(tracked_preview) then
        if patch_actor_meshes(tracked_preview) then return true end
    end
    return false
end

function M.patch_save_walls_once()
    if not ensure_assets() then return 0 end
    local patched = 0
    foreach_subsystem_actor(function(a)
        if is_preview_actor(a, nil) then return end
        if actor_is_stonewall_piece(a) and patch_actor_meshes(a) then
            patched = patched + 1
        end
    end)
    return patched
end

local function install_spawn_notify()
    if not NotifyOnNewObject then return end
    pcall(function()
        NotifyOnNewObject(K.WALL_BP, function(obj)
            if placement_window <= 0 then return end
            run_on_game_thread(function()
                if is_valid(obj) and actor_is_wall_large(obj) then
                    patch_actor_meshes(obj)
                end
            end)
        end)
    end)
end

local function install_spawn_hook()
    if not RegisterHook then return end
    local paths = {
        "/Script/Dominion.BuildModeComponent:Server_SpawnBuilding",
        "/Script/Dominion.DominionBuildModeComponent:Server_SpawnBuilding",
    }
    for _, path in ipairs(paths) do
        pcall(function()
            RegisterHook(path, function(bmc)
                if placement_window <= 0 and not last_session_was_stonewall then return end
                run_on_game_thread(function()
                    if is_valid(bmc) and not placing_stonewall(bmc) and placement_window <= 0 then return end
                    placement_window = 30
                    if last_preview_loc then
                        finalize_placement(bmc)
                        schedule_fast_retry(bmc, last_preview_loc)
                    end
                end)
            end)
        end)
    end
end

function M.install()
    if rawget(_G, "RSDW_BUILDS_VISUALS") or not LoopAsync then return end
    rawset(_G, "RSDW_BUILDS_VISUALS", true)

    pcall(function()
        ensure_assets()
        if LoadAsset then
            pcall(function() LoadAsset(K.MESH) end)
            pcall(function() LoadAsset(K.DA) end)
        end
    end)

    install_spawn_notify()
    install_spawn_hook()

    -- 100ms: preview mesh + instant finalize when click places (preview clears).
    LoopAsync(100, function()
        run_on_game_thread(function()
            ensure_assets()
            if placement_window > 0 then placement_window = placement_window - 1 end

            local bmc = get_build_mode_component()
            stonewall_session = is_valid(bmc) and placing_stonewall(bmc)
            local preview = is_valid(bmc) and weak_get(bmc.PreviewPiece) or nil

            if is_valid(preview) then
                if stonewall_session then
                    placement_window = 60
                    piece_ids_snapshot = snapshot_piece_ids()
                    M.patch_preview(bmc)
                    tracked_preview = preview
                    last_preview_loc = actor_location(preview)
                    last_session_was_stonewall = true
                    had_preview_last_tick = true
                else
                    last_session_was_stonewall = false
                    had_preview_last_tick = false
                end
            elseif had_preview_last_tick and last_session_was_stonewall and last_preview_loc then
                had_preview_last_tick = false
                finalize_placement(bmc)
                schedule_fast_retry(bmc, last_preview_loc)
            end
        end)
        return false
    end)

    local boot_pass = 0
    LoopAsync(2500, function()
        boot_pass = boot_pass + 1
        run_on_game_thread(function()
            local n = M.patch_save_walls_once()
            if n > 0 then
                print(TAG .. " save-load patched " .. n .. " stonewall(s)")
            end
        end)
        return boot_pass >= 6
    end)

    print(TAG .. " installed (instant place patch + stonewall-only)")
end

return M
