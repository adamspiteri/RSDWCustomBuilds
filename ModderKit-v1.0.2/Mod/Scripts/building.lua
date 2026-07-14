-- RSDW Custom Builds -- DA_Stonewall with catalogue pak + F7 menu.
local M = {}
local subsystem = require("subsystem")
local placement = require("placement")

-- Single table keeps main-chunk locals under Lua's 200 limit (catalogue.lua uses the same pattern).
local K = {
    TAG = "[RSDWBuilds]",
    DA_PATH = "/Game/RSDWBuilds/Stonewall/DA_Stonewall.DA_Stonewall",
    DA_PKG = "/Game/RSDWBuilds/Stonewall/DA_Stonewall",
    PERSIST_ID = "RSDWBuilds_Stonewall_v1",
    MESH_PATH = "/Game/RSDWBuilds/Stonewall/SM_Stonewall.SM_Stonewall",
    ICON_PATH = "/Game/RSDWBuilds/Stonewall/T_Icon_Stonewall.T_Icon_Stonewall",
    MESH_PKG = "/Game/RSDWBuilds/Stonewall/SM_Stonewall",
    VANILLA_FOUNDATION_DA = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/Tier1_Brynmoor/Foundations/DA_T1_Foundation_Large.DA_T1_Foundation_Large",
    STABILITY_DT_PATH = "/Game/Gameplay/BaseBuilding_New/DT_StabilityProfile.DT_StabilityProfile",
    STABILITY_ROW_NAME = "Tier1_Foundation",
    CATALOGUE_PATH = "/Game/Gameplay/BaseBuilding_New/DA_BuildPieceCatalogue.DA_BuildPieceCatalogue",
    CATALOGUE_PKG = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/DA_BuildPieceCatalogue_Default",
    CATALOGUE_OBJ = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/DA_BuildPieceCatalogue_Default.DA_BuildPieceCatalogue_Default",
    -- Standalone mod pak catalogue (same slot 651 data; avoids IoStore override merge on vanilla path).
    MOD_CATALOGUE_PKG = "/Game/RSDWBuilds/DA_BuildPieceCatalogue",
    MOD_CATALOGUE_OBJ = "/Game/RSDWBuilds/DA_BuildPieceCatalogue.DA_BuildPieceCatalogue",
    CATALOGUE_INDEX = 651,
    CATALOGUE_INDEX_KEY = "RSDWBUILDS_CATALOGUE_INDEX",
    CATALOGUE_PATCH_LOGGED = "RSDWBUILDS_CATALOGUE_PATCH_LOGGED",
    CATALOGUE_MISS_LOGGED = "RSDWBUILDS_CATALOGUE_MISS_LOGGED",
    DEFERRED_KEY = "RSDWBUILDS_DEFERRED_INDEX",
    TOOLS_DEFERRED_KEY = "RSDWTOOLS_MOD_FOUNDATION_DEFERRED_INDEX",
    LUA_UNLOCKED_KEY = "RSDWBUILDS_MOD_FOUNDATION_LUA_UNLOCKED",
    -- EValiditySpawnState (Dominion); Valid is the only successful placement result.
    VALIDITY_SPAWN_STATE_VALID = 9,
    VALIDITY_SPAWN_STATE_NAMES = {
        [0] = "None", [1] = "Overlapping", [2] = "Floating", [3] = "NeedsFoundation",
        [4] = "NeedsSnapping", [5] = "Unstable", [6] = "MissingMaterials",
        [7] = "WrongPhysicalSurface", [8] = "InsideVault", [9] = "Valid",
        [10] = "InsideProtectedArea", [11] = "ReachedCountLimit", [12] = "ShelterCheckFailed",
    },
    BOOT_OK_KEY = "RSDWBUILDS_MOD_FOUNDATION_BOOT_OK",
    BOOT_FAIL_LOGGED_KEY = "RSDWBUILDS_BOOT_FAIL_LOGGED",
    HYDRATION_STUB_KEY = "RSDWBUILDS_HYDRATION_STUB",
    BOOT_SCHEDULED_KEY = "RSDWBUILDS_MOD_FOUNDATION_BOOT_SCHEDULED",
    PIECE_HOOKS_KEY = "RSDWBUILDS_PIECE_HOOKS_INSTALLED",
    MESH_PATCH_ACTIVE = "RSDWBUILDS_MESH_PATCH_ACTIVE",
    DEFERRED_BUILD_ACTIVE = "RSDWBUILDS_DEFERRED_BUILD_ACTIVE",
    DEFERRED_PREVIEW_LOC_KEY = "RSDWBUILDS_DEFERRED_PREVIEW_LOC",
    DEFERRED_PIECE_COUNT_KEY = "RSDWBUILDS_DEFERRED_PIECE_COUNT",
    DEFERRED_PIECE_IDS_KEY = "RSDWBUILDS_DEFERRED_PIECE_IDS",
    DEFERRED_PATCH_WARNED_KEY = "RSDWBUILDS_DEFERRED_PATCH_WARNED",
    DEFERRED_SELECT_GUARD_KEY = "RSDWBUILDS_DEFERRED_SELECT_GUARD",
    DEFERRED_PREVIEW_ACTOR_KEY = "RSDWBUILDS_DEFERRED_PREVIEW_ACTOR",
    DEFERRED_WATCH_KEY = "RSDWBUILDS_DEFERRED_WATCH_ACTIVE",
    DEFERRED_CLICK_WATCH_KEY = "RSDWBUILDS_DEFERRED_CLICK_WATCH",
    PREVIEW_WATCH_KEY = "RSDWBUILDS_PREVIEW_WATCH_ACTIVE",
    VANILLA_PROXY_BACKUP_KEY = "RSDWBUILDS_VANILLA_PROXY_BACKUP",
    AIM_PLACE_ACTIVE = "RSDWBUILDS_AIM_PLACE_ACTIVE",
    AIM_E_KEY_REGISTERED = "RSDWBUILDS_AIM_E_KEY_REGISTERED",
    AIM_POLL_ACTIVE = "RSDWBUILDS_AIM_POLL_ACTIVE",
    AIM_E_WAS_DOWN = "RSDWBUILDS_AIM_E_WAS_DOWN",
    PLACE_GUARD_KEY = "RSDWBUILDS_PLACE_IN_FLIGHT",
    NATIVE_CONFIRM_PENDING = "RSDWBUILDS_NATIVE_CONFIRM_PENDING",
    PLACE_FINISH_KEY = "RSDWBUILDS_PLACE_FINISH_DONE",
    CLEANUP_IN_PROGRESS = "RSDWBUILDS_CLEANUP_IN_PROGRESS",
    PLACE_PATCH_DONE = "RSDWBUILDS_PLACE_PATCH_DONE",
    -- Catalogue index the current build session is allowed to touch; nil = legacy retag mode.
    EXPECTED_IDX_KEY = "RSDWBUILDS_EXPECTED_PIECE_IDX",
    -- Large foundation mesh extends past its pivot; keep placement well clear of the player.
    PLACE_FORWARD_DIST = 850,
    PLACE_LARGE_MESH_EXTRA = 250,
}
local restore_vanilla_proxy_mesh
local patch_deferred_click_placement
local deferred_trigger_placed_patch
local finish_deferred_tryspawn_at
local find_registered_da
local resolve_vanilla_foundation_da
local find_placed_actor_after_spawn
local configure_placed_actor
local schedule_actor_mesh_patch
local patch_deferred_placed_actor
local leave_build_mode_safe
local cached_mod_mesh = nil
local warned_rsdwtools = false

local NON_PLAYABLE_MAPS = {
    l_frontend = true,
    frontend = true,
    untitled = true,
    mainmenu = true,
    l_mainmenu = true,
}

local function string_from_fstring(v)
    if type(v) == "string" then return v end
    if type(v) ~= "userdata" then return nil end
    local ok, s = pcall(function()
        if v.ToString then return v:ToString() end
        return tostring(v)
    end)
    if ok and type(s) == "string" and s ~= "" and not s:find("^FString:", 1, false) then
        return s
    end
    return nil
end

local function is_valid(obj)
    if type(obj) ~= "userdata" then return false end
    if not obj.IsValid then return false end
    local ok, v = pcall(function() return obj:IsValid() end)
    return ok and v == true
end

local function is_vector_like(v)
    if v == nil then return false end
    if type(v) == "table" and type(v.X) == "number" then return true end
    if type(v) ~= "userdata" then return false end
    local ok, x = pcall(function() return v.X end)
    return ok and type(x) == "number"
end

-- Never probe v.Get / v.get with dot access -- UE4SS Vector structs throw on __index.
local function unwrap_remote(v)
    if v == nil then return nil end
    if is_vector_like(v) then return v end
    if type(v) == "userdata" then
        local ok, got = pcall(function() return v:get() end)
        if ok and got ~= nil then return got end
        ok, got = pcall(function() return v:Get() end)
        if ok and got ~= nil then return got end
    end
    return v
end

local function unwrap_bool(v)
    v = unwrap_remote(v)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    return nil
end

local function load_object(path)
    if not path or path == "" or path:lower() == "none" then return nil end
    if not path:find("/", 1, true) then return nil end

    local package_path = path:match("^(.-)%.[^%.]+$") or path
    local export = path:match("%.([^%.]+)$")

    if StaticFindObject then
        local ok, found = pcall(StaticFindObject, path)
        if ok and is_valid(found) then return found end
    end

    if LoadAsset then
        pcall(function() LoadAsset(package_path) end)
        pcall(function() LoadAsset(path) end)
        if StaticFindObject then
            local ok, found = pcall(StaticFindObject, path)
            if ok and is_valid(found) then return found end
        end
    end

    if StaticFindObject and export and package_path then
        local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if is_valid(arh) then
            local ok_ue, ue = pcall(require, "UEHelpers")
            if ok_ue and ue and ue.FindOrAddFName then
                local ok_ad, ad = pcall(function()
                    return {
                        PackageName = ue.FindOrAddFName(package_path),
                        AssetName = ue.FindOrAddFName(export),
                    }
                end)
                if ok_ad and ad then
                    local ok_g, asset = pcall(function() return arh:GetAsset(ad) end)
                    if ok_g and is_valid(asset) then return asset end
                end
            end
        end
    end

    return nil
end


local function tarray_len(arr)
    if type(arr) ~= "userdata" and type(arr) ~= "table" then return 0 end
    local n = 0
    pcall(function() n = #arr end)
    if n == 0 then
        pcall(function()
            if arr.Num then n = arr:Num() end
        end)
    end
    return n or 0
end

local function tarray_get(arr, i)
    local v = nil
    pcall(function() v = arr[i] end)
    return v
end
local function uobject_same(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    if a == b then return true end
    local na, nb
    pcall(function() na = a:GetFullName() end)
    pcall(function() nb = b:GetFullName() end)
    return type(na) == "string" and na == nb
end

local function get_local_player_controller()
    local ok_req, ue = pcall(require, "UEHelpers")
    if ok_req and type(ue) == "table" and ue.GetPlayerController then
        local ok_pc, pc = pcall(function() return ue.GetPlayerController() end)
        if ok_pc and is_valid(pc) then return pc end
    end
    if FindAllOf then
        local ok, list = pcall(FindAllOf, "PlayerController")
        if ok and type(list) == "table" then
            for _, pc in pairs(list) do
                if is_valid(pc) then
                    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
                    if ok_pawn and is_valid(pawn) and pawn.IsPlayerControlled then
                        local ok_me, mine = pcall(function() return pawn:IsPlayerControlled() end)
                        if ok_me and mine then return pc end
                    end
                    local ok_local, local_pc = pcall(function()
                        if pc.IsLocalPlayerController then return pc:IsLocalPlayerController() end
                        return false
                    end)
                    if ok_local and local_pc then return pc end
                end
            end
        end
    end
    return nil
end

local function get_local_pawn()
    local ok_req, ue = pcall(require, "UEHelpers")
    if ok_req and type(ue) == "table" and ue.GetPlayer then
        local ok_pawn, pawn = pcall(function() return ue.GetPlayer() end)
        if ok_pawn and is_valid(pawn) then return pawn end
    end
    local pc = get_local_player_controller()
    if not is_valid(pc) then return nil end
    local ok_pawn, pawn = pcall(function() return pc.Pawn end)
    if ok_pawn and is_valid(pawn) then return pawn end
    if FindAllOf then
        local ok, list = pcall(FindAllOf, "Pawn")
        if ok and type(list) == "table" then
            for _, p in pairs(list) do
                if is_valid(p) and p.IsLocallyControlled then
                    local ok_me, mine = pcall(function() return p:IsLocallyControlled() end)
                    if ok_me and mine then return p end
                end
            end
        end
    end
    return nil
end

local function get_pc_and_bmc()
    local pc = get_local_player_controller()
    local pawn = get_local_pawn()
    if not is_valid(pawn) then return nil, nil, "no local pawn (enter world first)" end
    if not is_valid(pc) then
        pcall(function() pc = pawn:GetController() end)
    end
    if not is_valid(pc) then return nil, nil, "no player controller" end

    local bmc
    pcall(function() bmc = pc.BuildModeComponent end)
    if not is_valid(bmc) and pc.GetBuildModeComponent then
        pcall(function() bmc = pc:GetBuildModeComponent() end)
    end
    if not is_valid(bmc) then return pc, nil, "no BuildModeComponent" end
    return pc, bmc, nil
end

local function get_world_for_map_check()
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and type(ue) == "table" and ue.GetWorld then
        local ok, w = pcall(function() return ue.GetWorld() end)
        if ok and is_valid(w) then return w end
    end
    local pc = get_local_player_controller()
    if is_valid(pc) and pc.GetWorld then
        local ok, w = pcall(function() return pc:GetWorld() end)
        if ok and is_valid(w) then return w end
    end
    if FindFirstOf then
        local ok, w = pcall(FindFirstOf, "World")
        if ok and is_valid(w) then return w end
    end
    return nil
end

local function world_map_label(w)
    if not is_valid(w) then return nil end
    local ok, label = pcall(function()
        if w.GetMapName then
            local m = w:GetMapName()
            local s = string_from_fstring(m)
            if s and s ~= "" and s ~= "None" then return s end
        end
        local fn = w:GetFullName()
        if type(fn) == "string" and fn ~= "" then
            local short = fn:match("%.([^%.]+)$")
            if short and short ~= "" then return short end
            if fn:find("L_World", 1, true) then return "L_World" end
            return fn
        end
        return nil
    end)
    if ok and type(label) == "string" and label ~= "" then return label end
    return nil
end

local function current_map_name()
    return world_map_label(get_world_for_map_check()) or "unknown"
end

local function is_non_playable_map(map)
    local s = tostring(map or ""):lower()
    if s == "" or s == "unknown" then return false end
    if NON_PLAYABLE_MAPS[s] then return true end
    if s:find("frontend", 1, true) then return true end
    if s:find("mainmenu", 1, true) then return true end
    if s:find("untitled", 1, true) then return true end
    return false
end

local function is_playable_world_map(map)
    local s = tostring(map or ""):lower()
    if s:find("l_world", 1, true) then return true end
    if is_valid(get_local_pawn()) then return true end
    return false
end

local function require_playable_world()
    local map = current_map_name()
    if is_non_playable_map(map) then
        return false, "not in world (current map: " .. map .. ")"
    end
    if is_playable_world_map(map) then return true, map end
    if is_valid(get_local_pawn()) then
        return true, (map ~= "unknown" and map or "in_world")
    end
    return false, "load L_World first (current map: " .. map .. ", no local pawn yet)"
end

local function is_playable_world()
    return require_playable_world()
end

-- Build-mode path only: never touch catalogue assets (LoadAsset on IoStore catalogue has crashed).
local function preload_core_assets()
    local paths = {
        "/Game/RSDWBuilds",
        K.DA_PKG,
        K.DA_PATH,
        K.MESH_PKG,
        K.MESH_PATH,
        K.ICON_PATH,
        K.VANILLA_FOUNDATION_DA,
    }
    for _, p in ipairs(paths) do
        if LoadAsset then pcall(function() LoadAsset(p) end) end
    end
end

local function preload_mod_assets()
    preload_core_assets()
    -- Stability DT only; catalogue IoStore loads are deferred to playable-world sync.
    if LoadAsset then
        pcall(function() LoadAsset(K.STABILITY_DT_PATH) end)
    end
end

local function should_run_catalogue_sync()
    if rawget(_G, K.HYDRATION_STUB_KEY) == true then return false end
    local map = current_map_name()
    if is_non_playable_map(map) and not is_playable_world_map(map) then return false end
    return true
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

local function copy_vector(v)
    v = unwrap_remote(v)
    if not is_vector_like(v) then return nil end
    return { X = v.X or 0, Y = v.Y or 0, Z = v.Z or 0 }
end

local function unwrap_uint32(v)
    v = unwrap_remote(v)
    if type(v) == "number" then return v end
    if type(v) == "userdata" then
        local n
        pcall(function() n = v.Value end)
        if type(n) == "number" then return n end
        pcall(function() n = tonumber(tostring(v)) end)
        if type(n) == "number" then return n end
    end
    return nil
end

local function dist_sq(a, b)
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    local dz = (a.Z or 0) - (b.Z or 0)
    return dx * dx + dy * dy + dz * dz
end

local function dist_sq_xy(a, b)
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    return dx * dx + dy * dy
end

local _spawn_ksl = nil
local function get_spawn_kismet_lib()
    if _spawn_ksl and is_valid(_spawn_ksl) then return _spawn_ksl end
    if not StaticFindObject then return nil end
    local ok, obj = pcall(StaticFindObject, "/Script/Engine.Default__KismetSystemLibrary")
    if ok and is_valid(obj) then
        _spawn_ksl = obj
        return _spawn_ksl
    end
    return nil
end

local function trace_ground_z(x, y, ref_z, ignore_actor)
    local ksl = get_spawn_kismet_lib()
    if not ksl then return ref_z, false end
    local world = get_world_for_map_check()
    if not is_valid(world) then return ref_z, false end

    local z0 = ref_z or 0
    local start_v = { X = x, Y = y, Z = z0 + 3000.0 }
    local end_v = { X = x, Y = y, Z = z0 - 8000.0 }
    local ignore = {}
    if is_valid(ignore_actor) then ignore[#ignore + 1] = ignore_actor end
    local hit = {}
    local trace_color = { R = 0, G = 0, B = 0, A = 0 }
    local ok, hit_b = pcall(function()
        return ksl:LineTraceSingle(
            world, start_v, end_v,
            "TraceTypeQuery1", false, ignore,
            "EDrawDebugTrace::None", hit, true,
            trace_color, trace_color, 0.0)
    end)
    if ok and hit_b and hit.Location and type(hit.Location.Z) == "number" then
        return hit.Location.Z, true
    end
    return ref_z, false
end

local function actor_uses_our_da(actor, da)
    if not is_valid(actor) or not da then return false end
    local pd
    pcall(function() pd = actor.BuildingPieceData end)
    if pd and uobject_same(pd, da) then return true end
    local pid
    pcall(function() pid = actor.PersistenceID end)
    if type(pid) == "string" and pid == K.PERSIST_ID then return true end
    return false
end

local function actor_is_vanilla_foundation(actor, vanilla)
    if not is_valid(actor) or not vanilla then return false end
    local is_preview = false
    pcall(function() is_preview = actor.bIsPreview end)
    if is_preview then return false end
    local class_match = false
    pcall(function()
        local cls = actor:GetClass()
        if is_valid(cls) and cls.GetFullName then
            local cn = cls:GetFullName()
            if type(cn) == "string" and cn:find("Foundation_Large", 1, true) then
                class_match = true
            end
        end
    end)
    if class_match then return true end
    local pd
    pcall(function() pd = actor.BuildingPieceData end)
    if is_valid(pd) and uobject_same(pd, vanilla) then return true end
    if is_valid(pd) then
        local name
        pcall(function() name = pd:GetFullName() end)
        if type(name) == "string" and name:find("Foundation_Large", 1, true) then
            return true
        end
    end
    local idx
    pcall(function() idx = actor.BuildingPieceDataIndex end)
    local van_idx
    pcall(function() van_idx = vanilla.BuildingPieceDataIndex end)
    return type(idx) == "number" and type(van_idx) == "number" and idx == van_idx
end

local function is_build_preview_actor(actor, bmc)
    if not is_valid(actor) then return false end
    local is_preview = false
    pcall(function() is_preview = actor.bIsPreview end)
    if is_preview then return true end
    if is_valid(bmc) then
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) and uobject_same(preview, actor) then return true end
    end
    return false
end

local function actor_should_patch_for_deferred(actor, mod_da, ref_loc, bmc)
    if not is_valid(actor) then return false end
    if is_build_preview_actor(actor, bmc) then return false end
    if mod_da and actor_uses_our_da(actor, mod_da) then return true end
    local mesh = resolve_mod_mesh()
    if mesh and actor_has_mod_mesh(actor, mesh) then return false end
    local vanilla = resolve_vanilla_foundation_da(false)
    if vanilla and actor_is_vanilla_foundation(actor, vanilla) then return true end
    if not ref_loc then return false end
    local aloc
    pcall(function() aloc = actor:K2_GetActorLocation() end)
    if not aloc then return false end
    return dist_sq(ref_loc, aloc) <= 900 * 900
end

local function patch_actor_stability(actor, da)
    if not is_valid(actor) then return false end
    if da and not actor_uses_our_da(actor, da) then return false end
    local ok = pcall(function() actor.StabilityValue = 1.0 end)
    return ok
end

local _static_mesh_component_class = nil

local function static_mesh_component_class()
    if _static_mesh_component_class and is_valid(_static_mesh_component_class) then
        return _static_mesh_component_class
    end
    if StaticFindObject then
        local ok, cls = pcall(StaticFindObject, "/Script/Engine.StaticMeshComponent")
        if ok and is_valid(cls) then
            _static_mesh_component_class = cls
            return _static_mesh_component_class
        end
    end
    return nil
end

local function foreach_actor_static_mesh_component(actor, fn)
    if not is_valid(actor) or type(fn) ~= "function" then return 0 end
    local seen = {}
    local n = 0

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
            local count = tarray_len(arr)
            for i = 1, count do
                visit(tarray_get(arr, i))
            end
        end
    end

    pcall(function()
        local cached = actor.CachedMeshes
        if not cached then return end
        local count = tarray_len(cached)
        for i = 1, count do
            visit(tarray_get(cached, i))
        end
    end)

    local getters = {
        function() return actor.StaticMesh end,
        function() return actor:GetStaticMeshComponent() end,
        function() return actor.StaticMeshComponent end,
        function() return actor.Mesh end,
        function() return actor.StaticMeshComponent0 end,
        function() return actor.RootComponent end,
    }
    for _, g in ipairs(getters) do
        local okc, comp = pcall(g)
        if okc then visit(comp) end
    end

    return n
end

local function get_actor_static_mesh_component(actor)
    if not is_valid(actor) then return nil end
    local ok_mesh, mesh_comp = pcall(function() return actor.Mesh end)
    if ok_mesh and is_valid(mesh_comp) and mesh_comp.SetStaticMesh then return mesh_comp end
    local found
    foreach_actor_static_mesh_component(actor, function(comp)
        if not found then found = comp end
        return false
    end)
    return found
end

local function find_object_mounted(path)
    if not path or not StaticFindObject then return nil end
    local ok, found = pcall(StaticFindObject, path)
    if ok and is_valid(found) then return found end
    return nil
end

local function resolve_soft_object(obj)
    if not obj then return nil end
    if is_valid(obj) then return obj end
    if type(obj) == "userdata" then
        do
            local ok, loaded = pcall(function() return obj:Get() end)
            if ok and is_valid(loaded) then return loaded end
        end
        if obj.ToSoftObjectPath then
            local ok, path = pcall(function() return obj:ToSoftObjectPath() end)
            if ok and path and path.ToString then
                local ok2, s = pcall(function() return path:ToString() end)
                if ok2 and type(s) == "string" and s ~= "" and s:lower() ~= "none" then
                    return load_object(s)
                end
            end
        end
    end
    if type(obj) == "table" and obj.AssetPathName then
        local path = tostring(obj.AssetPathName)
        if path ~= "" and path:lower() ~= "none" then
            if not path:find("%.", 1, true) and obj.SubPathString and obj.SubPathString ~= "" then
                path = path .. "." .. obj.SubPathString
            elseif not path:find("%.", 1, true) then
                local export = path:match("/([^/]+)$")
                if export then path = path .. "." .. export end
            end
            return load_object(path)
        end
    end
    return nil
end

local function find_static_mesh_by_name(name)
    if not name or not FindAllOf then return nil end
    local ok, list = pcall(FindAllOf, "StaticMesh")
    if not ok or type(list) ~= "table" then return nil end
    local needle = tostring(name):lower()
    for _, mesh in pairs(list) do
        if is_valid(mesh) then
            local fn
            pcall(function() fn = mesh:GetFullName() end)
            if type(fn) == "string" and fn:lower():find(needle, 1, true) then
                return mesh
            end
        end
    end
    return nil
end

local function resolve_mesh_from_da(da)
    if not da then return nil end
    local mesh
    pcall(function()
        local proxy = da.BuildingPieceProxyData
        if proxy and proxy.ProxyMesh then
            mesh = resolve_soft_object(proxy.ProxyMesh)
        end
    end)
    return mesh
end

local try_upgrade_from_hydration_stub

local function find_mod_da_mounted()
    local da = find_object_mounted(K.DA_PATH)
    if is_valid(da) then return da end
    if LoadAsset then
        pcall(function() LoadAsset(K.DA_PKG) end)
    end
    da = find_object_mounted(K.DA_PATH)
    if is_valid(da) then return da end
    return load_object(K.DA_PATH)
end

local function mod_pak_ready()
    if is_valid(find_mod_da_mounted()) then
        if try_upgrade_from_hydration_stub then
            try_upgrade_from_hydration_stub("mod_pak_ready")
        end
        return true
    end
    if rawget(_G, K.HYDRATION_STUB_KEY) == true then return false end
    return false
end

local function mod_pak_blocked_reason()
    if mod_pak_ready() then return nil end
    if rawget(_G, K.HYDRATION_STUB_KEY) == true then
        return "RSDWBuilds pak not loaded (hydration stub; DA not mountable yet). Repack: tools\\Build-And-Pack-Full-Phase2.ps1 -IncludeCatalogue, full restart."
    end
    if not is_valid(find_object_mounted(K.DA_PATH)) then
        return "RSDWBuilds pak not loaded (SkipPackage on DA_Stonewall). Repack and full game restart."
    end
    return nil
end

local function get_print_context()
    local ok_req, ue = pcall(require, "UEHelpers")
    if ok_req and ue then
        if ue.GetPlayerController then
            local ok, pc = pcall(function() return ue.GetPlayerController() end)
            if ok and is_valid(pc) then return pc end
        end
        if ue.GetWorld then
            local ok, world = pcall(function() return ue.GetWorld() end)
            if ok and is_valid(world) then return world end
        end
    end
    return nil
end

function M.show_status(msg, duration)
    if not msg or msg == "" then return end
    print(K.TAG .. " " .. msg)
    local ksl = StaticFindObject and StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if not is_valid(ksl) or not ksl.PrintString then return end
    local ctx = get_print_context()
    if not is_valid(ctx) then return end
    duration = duration or 8.0
    pcall(function()
        ksl:PrintString(
            ctx,
            msg,
            true,
            false,
            { R = 1.0, G = 0.82, B = 0.25, A = 1.0 },
            duration,
            FName("RCBStatus")
        )
    end)
end

function M.pak_blocked_short()
    local reason = mod_pak_blocked_reason()
    if reason then
        if reason:find("hydration stub", 1, true) then
            return "Mod pak not ready -- waiting for DA_Stonewall (stonewall_diag)."
        end
        return "Mod pak not loaded -- repack + full restart (stonewall_diag)."
    end
    return nil
end

local function load_asset_blocking(path)
    if not path or path == "" then return nil end
    local pkg = path:match("^(.-)%.[^%.]+$") or path
    local ksl = StaticFindObject and StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if is_valid(ksl) and ksl.LoadAsset_Blocking then
        pcall(function() ksl:LoadAsset_Blocking(pkg) end)
        pcall(function() ksl:LoadAsset_Blocking(path) end)
        local ok, found = pcall(StaticFindObject, path)
        if ok and is_valid(found) then return found end
    end
    return nil
end

-- IoStore mod mesh is not in the persistence map -- must LoadAsset like RSDWTools preload_my_foundation_assets.
local function preload_mod_mesh()
    if cached_mod_mesh and is_valid(cached_mod_mesh) then return cached_mod_mesh end
    cached_mod_mesh = find_object_mounted(K.MESH_PATH)
    if is_valid(cached_mod_mesh) then return cached_mod_mesh end
    -- LoadAsset_Blocking on SkipPackage paths hard-crashes the game; only touch pak assets when mounted.
    if try_upgrade_from_hydration_stub then
        try_upgrade_from_hydration_stub("preload_mod_mesh")
    end
    if not is_valid(find_mod_da_mounted()) and not mod_pak_ready() then return nil end
    cached_mod_mesh = load_object(K.MESH_PATH)
    if is_valid(cached_mod_mesh) then return cached_mod_mesh end
    cached_mod_mesh = resolve_mesh_from_da(find_mod_da_mounted())
    if is_valid(cached_mod_mesh) then return cached_mod_mesh end
    cached_mod_mesh = find_static_mesh_by_name("SM_Stonewall")
    return cached_mod_mesh
end

local function resolve_mod_mesh(allow_load)
    if cached_mod_mesh and is_valid(cached_mod_mesh) then return cached_mod_mesh end
    cached_mod_mesh = find_object_mounted(K.MESH_PATH)
    if is_valid(cached_mod_mesh) then return cached_mod_mesh end
    if allow_load ~= false then
        return preload_mod_mesh()
    end
    return nil
end

local function try_cache_mod_mesh_from_mount()
    return preload_mod_mesh()
end

local function resolve_mod_da(sub)
    sub = sub or subsystem.find()
    local da = find_registered_da(sub)
    if da then return da end
    for _, live in ipairs(subsystem.all()) do
        da = find_registered_da(live)
        if da then return da end
    end
    da = rawget(_G, "RSDWBUILDS_REGISTERED_MOD_DA")
    if type(da) == "userdata" then return da end
    return nil
end

local function component_has_mesh(comp, mesh)
    if not is_valid(comp) or not mesh then return false end
    local current
    pcall(function() current = comp.StaticMesh end)
    if not is_valid(current) and comp.GetStaticMesh then
        pcall(function() current = comp:GetStaticMesh() end)
    end
    return is_valid(current) and uobject_same(current, mesh)
end

local function actor_has_mod_mesh(actor, mesh)
    if not is_valid(actor) or not mesh then return false end
    local total, matched = 0, 0
    foreach_actor_static_mesh_component(actor, function(comp)
        total = total + 1
        if component_has_mesh(comp, mesh) then matched = matched + 1 end
        return false
    end)
    return total > 0 and matched == total
end

local function set_comp_static_mesh(comp, mesh)
    if not is_valid(comp) or not mesh or not comp.SetStaticMesh then return false end
    local ok = pcall(function() comp:SetStaticMesh(mesh) end)
    if ok then
        pcall(function()
            if comp.MarkRenderStateDirty then comp:MarkRenderStateDirty() end
        end)
    end
    return ok
end

local function patch_actor_mesh(actor, mesh)
    if not is_valid(actor) then return false end
    mesh = mesh or resolve_mod_mesh()
    if not mesh then return false end
    if actor_has_mod_mesh(actor, mesh) then return false end
    local changed = false
    foreach_actor_static_mesh_component(actor, function(comp)
        if not component_has_mesh(comp, mesh) and set_comp_static_mesh(comp, mesh) then
            changed = true
        end
        return false
    end)
    return changed
end

local function patch_actor_stability_value(actor)
    if not is_valid(actor) then return false end
    return pcall(function() actor.StabilityValue = 1.0 end)
end

local function patch_piece_actor(actor, da, mesh)
    if not is_valid(actor) then return false end
    mesh = mesh or resolve_mod_mesh()
    local changed = false
    if patch_actor_stability_value(actor) then changed = true end
    if patch_actor_mesh(actor, mesh) then changed = true end
    if patch_actor_stability(actor, da) then changed = true end
    return changed
end

local function find_building_subsystem()
    if FindFirstOf then
        local ok, sub = pcall(FindFirstOf, "BuildingSubsystem")
        if ok and is_valid(sub) then return sub end
    end
    return nil
end

local function unwrap_tmap_actor(v)
    local actor = v
    if type(actor) ~= "userdata" and v then
        local got
        pcall(function() got = v:get() end)
        if type(got) ~= "userdata" then
            pcall(function() got = v:Get() end)
        end
        if type(got) == "userdata" then actor = got end
    end
    return actor
end

local function foreach_building_subsystem_actor(fn)
    local sub = find_building_subsystem()
    if not is_valid(sub) then return false end
    local map
    pcall(function() map = sub.PieceIDToBuildingPieceActor end)
    if not map or not map.ForEach then return false end
    return pcall(function()
        map:ForEach(function(_k, v)
            local actor = unwrap_tmap_actor(v)
            if is_valid(actor) then fn(actor) end
        end)
    end)
end

local function count_building_subsystem_pieces()
    local n = 0
    foreach_building_subsystem_actor(function(_a) n = n + 1 end)
    return n
end

local function foreach_registered_building_actor(fn)
    local n = 0
    foreach_building_subsystem_actor(function(a)
        n = n + 1
        fn(a)
    end)
    if n == 0 and FindAllOf then
        pcall(function()
            local list = FindAllOf("BaseBuildingActor")
            if type(list) == "table" then
                for _, a in pairs(list) do fn(a) end
            end
        end)
    end
end

local function snapshot_subsystem_piece_ids()
    local ids = {}
    foreach_registered_building_actor(function(a)
        local id
        pcall(function() id = a.BuildingPieceID end)
        if type(id) == "number" then ids[id] = true end
    end)
    return ids
end

local function capture_deferred_piece_snapshot()
    rawset(_G, K.DEFERRED_PIECE_IDS_KEY, snapshot_subsystem_piece_ids())
    rawset(_G, K.DEFERRED_PIECE_COUNT_KEY, count_building_subsystem_pieces())
end

local function find_new_subsystem_actor(before_ids, ref_loc, max_dist)
    if not before_ids then return nil end
    local best, best_d2
    local max_d2 = (max_dist or 8000) * (max_dist or 8000)
    local max_xy = (max_dist or 8000) * (max_dist or 8000)
    foreach_registered_building_actor(function(a)
        local id
        pcall(function() id = a.BuildingPieceID end)
        if type(id) ~= "number" or before_ids[id] then return end
        if is_build_preview_actor(a, nil) then return end
        if ref_loc then
            local aloc
            pcall(function() aloc = a:K2_GetActorLocation() end)
            aloc = copy_vector(aloc)
            if aloc then
                local d2 = dist_sq(ref_loc, aloc)
                local dxy = dist_sq_xy(ref_loc, aloc)
                if (d2 <= max_d2 or dxy <= max_xy) and (not best_d2 or d2 < best_d2) then
                    best, best_d2 = a, d2
                end
            elseif not best then
                best = a
            end
        else
            best = a
        end
    end)
    return best
end

local function find_subsystem_actor_by_data_index(data_idx, ref_loc, max_dist)
    if type(data_idx) ~= "number" then return nil end
    local best, best_d2
    local max_d2 = (max_dist or 8000) * (max_dist or 8000)
    local max_xy = (max_dist or 8000) * (max_dist or 8000)
    foreach_registered_building_actor(function(a)
        local idx
        pcall(function() idx = a.BuildingPieceDataIndex end)
        if idx ~= data_idx then return end
        if is_build_preview_actor(a, nil) then return end
        if ref_loc then
            local aloc
            pcall(function() aloc = a:K2_GetActorLocation() end)
            aloc = copy_vector(aloc)
            if aloc then
                local d2 = dist_sq(ref_loc, aloc)
                local dxy = dist_sq_xy(ref_loc, aloc)
                if (d2 <= max_d2 or dxy <= max_xy) and (not best_d2 or d2 < best_d2) then
                    best, best_d2 = a, d2
                end
            elseif not best then
                best = a
            end
        else
            best = a
        end
    end)
    return best
end

local function transform_to_location(transform)
    transform = unwrap_remote(transform)
    if not transform then return nil end
    if is_vector_like(transform) then return copy_vector(transform) end
    local loc
    pcall(function() loc = transform.Translation end)
    loc = unwrap_remote(loc)
    if is_vector_like(loc) then return copy_vector(loc) end
    pcall(function()
        if transform.GetLocation then loc = transform:GetLocation() end
    end)
    loc = unwrap_remote(loc)
    return is_vector_like(loc) and copy_vector(loc) or nil
end

local function find_spawned_piece_near(loc, da, max_dist)
    if not loc or not da then return nil end
    local best, best_d2
    local max_d2 = (max_dist or 800) * (max_dist or 800)
    foreach_building_subsystem_actor(function(a)
        if not actor_uses_our_da(a, da) then return end
        local aloc
        pcall(function() aloc = a:K2_GetActorLocation() end)
        if not aloc then return end
        local d2 = dist_sq(loc, aloc)
        if d2 <= max_d2 and (not best_d2 or d2 < best_d2) then
            best, best_d2 = a, d2
        end
    end)
    return best
end

local function find_vanilla_foundation_near(loc, vanilla, max_dist)
    if not loc or not vanilla then return nil end
    local best, best_d2
    local max_d2 = (max_dist or 1500) * (max_dist or 1500)
    foreach_building_subsystem_actor(function(a)
        if not actor_is_vanilla_foundation(a, vanilla) then return end
        local aloc
        pcall(function() aloc = a:K2_GetActorLocation() end)
        if not aloc then return end
        local d2 = dist_sq(loc, aloc)
        if d2 <= max_d2 and (not best_d2 or d2 < best_d2) then
            best, best_d2 = a, d2
        end
    end)
    return best
end

local function validity_spawn_state_label(state)
    if type(state) == "string" then return state end
    local n = tonumber(state)
    if n == nil then return tostring(state) end
    return K.VALIDITY_SPAWN_STATE_NAMES[n] or ("state_" .. tostring(n))
end

local function validity_spawn_state_is_success(state)
    if type(state) == "string" then
        return state:find("Valid", 1, true) ~= nil
    end
    return tonumber(state) == K.VALIDITY_SPAWN_STATE_VALID
end

local function spawn_failure_hint(label)
    if label == "Floating" or label == "NeedsFoundation" then
        return label .. " (try flatter ground or stonewall_build)"
    end
    if label == "None" then
        return label .. " (build mode or piece not ready)"
    end
    if label == "MissingMaterials" then
        return label .. " (requirements should be cleared; try stonewall_diag)"
    end
    return label
end

local function bump_num_building_piece_datas(sub, idx)
    if not sub or type(idx) ~= "number" or idx < 0 then return end
    pcall(function()
        local num = sub.NumBuildingPieceDatas or 0
        if type(num) ~= "number" or num <= idx then
            sub.NumBuildingPieceDatas = idx + 1
        end
    end)
end

local function describe_actor_mesh(actor)
    if not is_valid(actor) then return "preview=none" end
    local parts = {}
    foreach_actor_static_mesh_component(actor, function(comp)
        local name = "?"
        pcall(function()
            local sm = comp.StaticMesh
            if not is_valid(sm) and comp.GetStaticMesh then sm = comp:GetStaticMesh() end
            if is_valid(sm) and sm.GetFullName then
                name = sm:GetFullName()
            end
        end)
        parts[#parts + 1] = name
        return false
    end)
    if #parts == 0 then return "preview=ok comps=0" end
    return "preview mesh=[" .. table.concat(parts, ", ") .. "]"
end

local function proxy_mesh_soft_path()
    return { AssetPathName = K.MESH_PATH, SubPathString = "" }
end

local function describe_da_proxy_mesh(da)
    if not da then return "proxy=none" end
    local label = "unknown"
    pcall(function()
        local proxy = da.BuildingPieceProxyData
        if not proxy or not proxy.ProxyMesh then return end
        local pm = proxy.ProxyMesh
        if is_valid(pm) and pm.GetFullName then
            label = pm:GetFullName()
        elseif type(pm) == "table" and pm.AssetPathName then
            label = tostring(pm.AssetPathName)
        else
            label = tostring(pm)
        end
    end)
    return label
end

local function assign_da_proxy_mesh(da, mesh)
    if not da then return false end
    mesh = mesh or resolve_mod_mesh(false)
    if not mesh then return false end
    pcall(function()
        local proxy = da.BuildingPieceProxyData
        if proxy then
            proxy.ProxyMesh = mesh
        else
            da.BuildingPieceProxyData = { ProxyMesh = mesh }
        end
    end)
    return true
end

local function ensure_visuals(da)
    if not da or not is_playable_world() then return end
    local icon = load_object(K.ICON_PATH)
    if icon then pcall(function() da.DisplayIcon = icon end) end
end

-- Native preview + placed mesh come from vanilla DA ProxyMesh (SetStaticMesh on preview is not enough).
local function capture_vanilla_proxy_backup(vanilla)
    if not is_valid(vanilla) then return end
    if rawget(_G, K.VANILLA_PROXY_BACKUP_KEY) ~= nil then return end
    local backup
    pcall(function()
        local proxy = vanilla.BuildingPieceProxyData
        if proxy and proxy.ProxyMesh ~= nil then
            backup = proxy.ProxyMesh
        end
    end)
    rawset(_G, K.VANILLA_PROXY_BACKUP_KEY, backup)
end

restore_vanilla_proxy_mesh = function()
    local backup = rawget(_G, K.VANILLA_PROXY_BACKUP_KEY)
    if backup == nil then return end
    local vanilla = resolve_vanilla_foundation_da(false)
    if is_valid(vanilla) then
        pcall(function()
            local proxy = vanilla.BuildingPieceProxyData
            if proxy then
                proxy.ProxyMesh = backup
            end
        end)
    end
    rawset(_G, K.VANILLA_PROXY_BACKUP_KEY, nil)
end

local function apply_vanilla_proxy_mod_mesh(vanilla)
    vanilla = vanilla or resolve_vanilla_foundation_da()
    if not is_valid(vanilla) then return false end
    local mesh = resolve_mod_mesh(true)
    if not mesh then return false end
    capture_vanilla_proxy_backup(vanilla)
    if assign_da_proxy_mesh(vanilla, mesh) then
        print(K.TAG .. " vanilla DA ProxyMesh -> SM_Stonewall (session)")
        return true
    end
    return false
end

local function patch_vanilla_da_proxy_for_deferred(vanilla)
    return apply_vanilla_proxy_mod_mesh(vanilla)
end

local function placing_our_piece(bmc, da)
    if not is_valid(bmc) or not da then return false end
    local cur = weak_get(bmc.CurrentlyPlacingPieceData)
    if not cur then return false end
    if uobject_same(cur, da) then return true end
    local pid
    pcall(function() pid = cur.PersistenceID end)
    if type(pid) == "string" and pid == K.PERSIST_ID then return true end
    return false
end

local function patch_preview_mesh_only(da, mesh)
    if not da then return 0 end
    mesh = mesh or resolve_mod_mesh()
    if not mesh then return 0 end
    local _pc, bmc = get_pc_and_bmc()
    if not bmc or not placing_our_piece(bmc, da) then return 0 end
    local preview = weak_get(bmc.PreviewPiece)
    if is_valid(preview) and patch_piece_actor(preview, da, mesh) then
        return 1
    end
    return 0
end

-- Deferred spawn keeps vanilla DA in build mode; optionally patch preview mesh only (no BuildingPieceData swap).
local function patch_bmc_preview_mesh(bmc, da, mesh, mesh_only)
    if not is_valid(bmc) then return 0 end
    mesh = mesh or resolve_mod_mesh()
    if not mesh then return 0 end
    local preview = weak_get(bmc.PreviewPiece)
    if not is_valid(preview) then return 0 end
    if not mesh_only and da then
        pcall(function() preview.BuildingPieceData = da end)
    end
    local changed = patch_actor_mesh(preview, mesh)
    if not changed then
        local comp = get_actor_static_mesh_component(preview)
        if comp and set_comp_static_mesh(comp, mesh) then
            changed = true
        end
    end
    if changed then
        rawset(_G, K.DEFERRED_PREVIEW_ACTOR_KEY, preview)
        return 1
    end
    return 0
end

local function refresh_deferred_preview_patch(bmc, da, mesh_only, log_label)
    if not is_valid(bmc) or not da then return 0 end
    local mesh = resolve_mod_mesh(true)
    if not mesh then
        if log_label then
            print(K.TAG .. " " .. log_label .. " skipped: SM_Stonewall not mounted")
        end
        return 0
    end
    if mesh_only ~= true then
        pcall(function() patch_preview_stability(bmc, da, false) end)
    end
    local n = patch_bmc_preview_mesh(bmc, da, mesh, mesh_only ~= false)
    if n > 0 and log_label then
        local preview = weak_get(bmc.PreviewPiece)
        print(string.format("%s %s (%s)", K.TAG, log_label, describe_actor_mesh(preview)))
    end
    placement.nudge_preview_forward(bmc)
    return n
end

local function preview_needs_patch(bmc, mesh)
    if not is_valid(bmc) or not mesh then return false end
    local preview = weak_get(bmc.PreviewPiece)
    if is_valid(preview) and not actor_has_mod_mesh(preview, mesh) then
        return true
    end
    return false
end

local function schedule_preview_patch_retries(bmc, da, max_ticks)
    if not LoopAsync or rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then return end
    max_ticks = max_ticks or 8
    local ticks = 0
    LoopAsync(200, function()
        ticks = ticks + 1
        if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then return true end
        local run = function()
            if not is_valid(bmc) then return end
            local mesh = resolve_mod_mesh(false)
            if mesh and preview_needs_patch(bmc, mesh) then
                refresh_deferred_preview_patch(bmc, da, true, ticks == 1 and "preview retry" or nil)
            end
        end
        if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
        return ticks >= max_ticks
    end)
end

-- Game resets preview mesh from vanilla DA ProxyMesh; keep re-patching for whole build session.
local function start_deferred_preview_watch(bmc, da)
    if not LoopAsync or rawget(_G, K.PREVIEW_WATCH_KEY) then return end
    if not is_valid(bmc) or not da then return end
    rawset(_G, K.PREVIEW_WATCH_KEY, true)
    LoopAsync(150, function()
        if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then
            rawset(_G, K.PREVIEW_WATCH_KEY, false)
            return true
        end
        local run = function()
            if not is_valid(bmc) then return end
            local mesh = resolve_mod_mesh(false)
            if mesh and preview_needs_patch(bmc, mesh) then
                refresh_deferred_preview_patch(bmc, da, true, nil)
            end
        end
        if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
        return false
    end)
end

local function capture_deferred_preview_loc(bmc)
    if not is_valid(bmc) then return end
    local preview = weak_get(bmc.PreviewPiece)
    if not is_valid(preview) then return end
    rawset(_G, K.DEFERRED_PREVIEW_ACTOR_KEY, preview)
    pcall(function()
        local loc = copy_vector(preview:K2_GetActorLocation())
        if loc then rawset(_G, K.DEFERRED_PREVIEW_LOC_KEY, loc) end
    end)
end

placement.bind({
    TAG = K.TAG,
    PLACE_FORWARD_DIST = K.PLACE_FORWARD_DIST,
    PLACE_LARGE_MESH_EXTRA = K.PLACE_LARGE_MESH_EXTRA,
    is_valid = is_valid,
    copy_vector = copy_vector,
    dist_sq = dist_sq,
    dist_sq_xy = dist_sq_xy,
    get_local_pawn = get_local_pawn,
    get_local_player_controller = get_local_player_controller,
    trace_ground_z = trace_ground_z,
    weak_get = weak_get,
    capture_deferred_preview_loc = capture_deferred_preview_loc,
})

local function get_preview_placement_transform(bmc)
    if not is_valid(bmc) then return nil, nil end
    capture_deferred_preview_loc(bmc)
    local preview = weak_get(bmc.PreviewPiece)
    local loc, rot
    if is_valid(preview) then
        pcall(function() loc = copy_vector(preview:K2_GetActorLocation()) end)
        pcall(function()
            local r = preview:K2_GetActorRotation()
            if r then
                rot = { Pitch = r.Pitch or 0, Yaw = r.Yaw or 0, Roll = r.Roll or 0 }
            end
        end)
    end
    if not loc then
        loc = copy_vector(rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY))
    end
    if not loc then return nil, nil end
    rot = rot or { Pitch = 0, Yaw = 0, Roll = 0 }
    -- Preview ghost is nudged in refresh_deferred_preview_patch; avoid stacking offset twice on E.
    if not is_valid(preview) then
        loc, rot = placement.ensure_forward_placement(loc, rot)
    end
    return loc, rot
end

local function deferred_build_mode_ready(bmc)
    if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true or not is_valid(bmc) then return false end
    local loc = select(1, get_preview_placement_transform(bmc))
    return loc ~= nil
end

local function get_current_build_mode(bmc)
    if not is_valid(bmc) then return 0 end
    local mode = nil
    pcall(function()
        if bmc.GetCurrentBuildMode then
            mode = bmc:GetCurrentBuildMode()
        else
            mode = bmc.CurrentBuildMode
        end
    end)
    if type(mode) == "number" then return mode end
    return 0
end

local function resolve_vanilla_catalogue_index()
    local vanilla = resolve_vanilla_foundation_da(false)
    if not is_valid(vanilla) then return nil, nil end
    local idx
    pcall(function() idx = vanilla.BuildingPieceDataIndex end)
    if type(idx) == "number" and idx >= 0 then return idx, vanilla end
    local cat = load_object(K.CATALOGUE_PATH)
        or load_object(K.CATALOGUE_OBJ)
        or load_object(K.MOD_CATALOGUE_OBJ)
    if is_valid(cat) and cat.FindIndexForPieceData then
        pcall(function() idx = cat:FindIndexForPieceData(vanilla) end)
        if type(idx) == "number" and idx >= 0 then return idx, vanilla end
    end
    return nil, vanilla
end

local function unhide_placed_actor(actor)
    if not is_valid(actor) then return end
    pcall(function()
        if actor.SetActorHiddenInGame then actor:SetActorHiddenInGame(false) end
    end)
    pcall(function() actor.bHidden = false end)
    pcall(function() actor.bIsGhosted = false end)
end

local function patch_preview_and_placed(da, mesh, mesh_only)
    local n = patch_preview_mesh_only(da, mesh)
    local _pc, bmc = get_pc_and_bmc()
    if is_valid(bmc) then
        n = n + patch_bmc_preview_mesh(bmc, da, mesh, mesh_only)
    end
    return n
end

local function patch_placed_actors(da, mesh)
    if not da then return 0 end
    mesh = mesh or resolve_mod_mesh()
    if not mesh then return 0 end
    local patched = 0
    foreach_building_subsystem_actor(function(actor)
        if actor_uses_our_da(actor, da) and patch_piece_actor(actor, da, mesh) then
            patched = patched + 1
        end
    end)
    return patched
end

local function schedule_post_spawn_stability(loc, da, mesh_only)
    if not da then return end
    local mesh = resolve_mod_mesh()

    local function run_once()
        local placed = loc and find_placed_actor_after_spawn(loc, da, nil, 1200) or nil
        if is_valid(placed) then
            configure_placed_actor(placed, da, nil, mesh_only)
        end
    end

    if not LoopAsync then
        run_once()
        return
    end

    local ticks = 0
    LoopAsync(200, function()
        ticks = ticks + 1
        if ExecuteInGameThread then
            ExecuteInGameThread(run_once)
        else
            run_once()
        end
        return ticks >= 3
    end)
end

local function stop_mesh_patch_loop_only()
    rawset(_G, K.MESH_PATCH_ACTIVE, false)
end

local function clear_deferred_build_session()
    rawset(_G, K.DEFERRED_BUILD_ACTIVE, false)
    rawset(_G, K.EXPECTED_IDX_KEY, nil)
    rawset(_G, K.DEFERRED_PREVIEW_LOC_KEY, nil)
    rawset(_G, K.DEFERRED_PREVIEW_ACTOR_KEY, nil)
    rawset(_G, K.DEFERRED_PIECE_IDS_KEY, nil)
    rawset(_G, K.DEFERRED_PATCH_WARNED_KEY, nil)
    rawset(_G, K.DEFERRED_SELECT_GUARD_KEY, nil)
    rawset(_G, K.DEFERRED_WATCH_KEY, false)
    rawset(_G, K.DEFERRED_CLICK_WATCH_KEY, false)
    rawset(_G, K.PREVIEW_WATCH_KEY, false)
    if restore_vanilla_proxy_mesh then restore_vanilla_proxy_mesh() end
end

local function finish_deferred_placement_session(bmc)
    if rawget(_G, K.CLEANUP_IN_PROGRESS) == true then return end
    if rawget(_G, K.PLACE_FINISH_KEY) == true then return end
    rawset(_G, K.CLEANUP_IN_PROGRESS, true)
    rawset(_G, K.PLACE_FINISH_KEY, true)
    rawset(_G, K.NATIVE_CONFIRM_PENDING, nil)
    rawset(_G, K.PLACE_PATCH_DONE, true)
    leave_build_mode_safe(bmc)
    clear_deferred_build_session()
    rawset(_G, K.AIM_PLACE_ACTIVE, false)
    rawset(_G, K.AIM_POLL_ACTIVE, false)
    rawset(_G, K.AIM_E_WAS_DOWN, false)
    rawset(_G, K.CLEANUP_IN_PROGRESS, nil)
    if LoopAsync then
        LoopAsync(250, function()
            rawset(_G, K.PLACE_FINISH_KEY, nil)
            rawset(_G, K.PLACE_PATCH_DONE, nil)
            return true
        end)
    end
end

local function set_deferred_build_session(active)
    rawset(_G, K.DEFERRED_BUILD_ACTIVE, active and true or false)
    if not active then
        rawset(_G, K.DEFERRED_PIECE_COUNT_KEY, nil)
        rawset(_G, K.DEFERRED_PIECE_IDS_KEY, nil)
        rawset(_G, K.DEFERRED_PATCH_WARNED_KEY, nil)
    else
        rawset(_G, K.DEFERRED_PATCH_WARNED_KEY, nil)
    end
end

local function stop_mesh_patch_loop(da, mesh)
    stop_mesh_patch_loop_only()
    if da then
        patch_placed_actors(da, mesh or resolve_mod_mesh())
    end
end

local function try_deferred_placed_patch_from_loop(bmc, da, mesh)
    if rawget(_G, K.PLACE_FINISH_KEY) == true or rawget(_G, K.PLACE_PATCH_DONE) == true then
        return false
    end
    if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true or not da then return false end
    mesh = mesh or resolve_mod_mesh()
    if not mesh then return false end

    local vanilla = resolve_vanilla_foundation_da()

    local ref_loc = rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY)
    local tracked = rawget(_G, K.DEFERRED_PREVIEW_ACTOR_KEY)

    if is_valid(bmc) then
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) then
            rawset(_G, K.DEFERRED_PREVIEW_ACTOR_KEY, preview)
            tracked = preview
            pcall(function()
                local loc = copy_vector(preview:K2_GetActorLocation())
                if loc then
                    ref_loc = loc
                    rawset(_G, K.DEFERRED_PREVIEW_LOC_KEY, loc)
                end
            end)
        end
    end

    if is_valid(tracked) and not actor_has_mod_mesh(tracked, mesh) then
        if is_build_preview_actor(tracked, bmc) then
            refresh_deferred_preview_patch(bmc, da, true, nil)
            return false
        end
        if patch_deferred_placed_actor(tracked, da, bmc, true, false) then
            print(K.TAG .. " loop: patched tracked placement actor")
            return true
        end
    end

    if is_valid(bmc) then
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) and not is_build_preview_actor(preview, bmc)
            and patch_deferred_placed_actor(preview, da, bmc, true, false) then
            print(K.TAG .. " loop: patched ex-preview placed actor")
            return true
        end
    end

    local prev = rawget(_G, K.DEFERRED_PIECE_COUNT_KEY)
    if type(prev) == "number" then
        local cur = count_building_subsystem_pieces()
        if cur > prev then
            rawset(_G, K.DEFERRED_PIECE_COUNT_KEY, cur)
            print(K.TAG .. " building registry grew -- patching placed mesh")
            if patch_deferred_click_placement(bmc, da, ref_loc) then return true end
        end
    end

    if ref_loc and vanilla then
        local placed = find_vanilla_foundation_near(ref_loc, vanilla, 500)
        if is_valid(placed) and not actor_has_mod_mesh(placed, mesh) then
            if patch_deferred_placed_actor(placed, da, bmc, true, true) then
                print(K.TAG .. " loop: patched vanilla foundation at preview loc")
                return true
            end
        end
    end

    return false
end

local function start_mesh_patch_loop(_da)
    -- Disabled: polling loops caused lag/crashes. Mesh is patched on hooks only.
end

local function start_deferred_placement_watch(bmc, da)
    if not LoopAsync or rawget(_G, K.DEFERRED_WATCH_KEY) then return end
    if not is_valid(bmc) or not da then return end
    rawset(_G, K.DEFERRED_WATCH_KEY, true)
    local ticks = 0
    LoopAsync(250, function()
        if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then
            rawset(_G, K.DEFERRED_WATCH_KEY, false)
            return true
        end
        if try_deferred_placed_patch_from_loop(bmc, da) then
            rawset(_G, K.DEFERRED_WATCH_KEY, false)
            return true
        end
        ticks = ticks + 1
        return ticks >= 120
    end)
end

-- When native click places, preview clears before hooks run -- finalize at last preview loc.
local function start_deferred_click_watch(bmc, da)
    if not LoopAsync or rawget(_G, K.DEFERRED_CLICK_WATCH_KEY) then return end
    if not is_valid(bmc) or not da then return end
    rawset(_G, K.DEFERRED_CLICK_WATCH_KEY, true)
    local had_preview = false
    LoopAsync(100, function()
        if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then
            rawset(_G, K.DEFERRED_CLICK_WATCH_KEY, false)
            return true
        end
        if not is_valid(bmc) then return false end
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) then
            had_preview = true
            capture_deferred_preview_loc(bmc)
        elseif had_preview then
            had_preview = false
            if rawget(_G, K.PLACE_FINISH_KEY) == true or rawget(_G, K.NATIVE_CONFIRM_PENDING) == true then
                return false
            end
            local loc = rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY)
            print(K.TAG .. " click watch: preview cleared -- finalizing placed piece")
            deferred_trigger_placed_patch(bmc, loc, "click_watch", nil)
        end
        return false
    end)
end

local function start_deferred_build_watches(bmc, da)
    start_deferred_placement_watch(bmc, da)
    start_deferred_click_watch(bmc, da)
end

local function schedule_post_spawn_mesh_patch(loc, da, mesh_only)
    if not is_playable_world() then return end
    local mesh = resolve_mod_mesh()
    if not mesh then return end
    local vanilla = resolve_vanilla_foundation_da()

    local run_once = function()
        local placed = loc and find_placed_actor_after_spawn(loc, da, vanilla, 1500) or nil
        if is_valid(placed) then
            if configure_placed_actor(placed, da, nil, mesh_only) then
                print(string.format("%s patched placed actor -> SM_Stonewall", K.TAG))
            end
            schedule_actor_mesh_patch(placed, da, mesh_only, 20)
            return
        end
        local n = patch_placed_actors(da, mesh)
        if n > 0 then
            print(string.format("%s patched %d placed actor(s) -> SM_Stonewall", K.TAG, n))
        end
    end

    if not LoopAsync then
        run_once()
        return
    end

    local ticks = 0
    LoopAsync(250, function()
        ticks = ticks + 1
        if ExecuteInGameThread then
            ExecuteInGameThread(run_once)
        else
            run_once()
        end
        return ticks >= 4
    end)
end

-- One retry only; aggressive re-patch loops raced native finalize and crashed on E place.
schedule_actor_mesh_patch = function(actor, mod_da, mesh_only, max_ticks)
    if not is_valid(actor) or not mod_da then return end
    if mesh_only then
        local function run_once()
            if is_valid(actor) then patch_placed_mesh_minimal(actor) end
        end
        if LoopAsync and (max_ticks or 0) > 1 then
            LoopAsync(350, run_once)
        end
        return
    end
    max_ticks = max_ticks or 2
    local run_once = function()
        if not is_valid(actor) then return end
        configure_placed_actor(actor, mod_da, nil, false)
    end
    if not LoopAsync then
        run_once()
        return
    end
    local ticks = 0
    LoopAsync(250, function()
        ticks = ticks + 1
        if ExecuteInGameThread then ExecuteInGameThread(run_once) else run_once() end
        return ticks >= max_ticks
    end)
end

local function tmap_find(map, key)
    if not map or not map.Find then return nil end
    local val = nil
    pcall(function() val = map:Find(key) end)
    val = unwrap_remote(val)
    if val ~= nil and is_valid(val) then return val end
    if type(val) == "userdata" then return val end
    return nil
end

local function tmap_add(map, key, val)
    if not map then return false end
    return pcall(function() map:Add(key, val) end)
end

local function get_persist_id(da)
    if da.GetPersistenceID then
        local ok, pid = pcall(function() return da:GetPersistenceID() end)
        if ok and type(pid) == "string" and pid ~= "" then return pid end
        if ok and pid and pid.ToString then
            local ok2, s = pcall(function() return pid:ToString() end)
            if ok2 and s and s ~= "" then return s end
        end
    end
    local field
    pcall(function() field = da.PersistenceID end)
    if type(field) == "string" and field ~= "" then return field end
    return K.PERSIST_ID
end

local function ensure_persist_id(da)
    pcall(function() da.PersistenceID = K.PERSIST_ID end)
    if da.SetPersistenceID then pcall(function() da:SetPersistenceID(K.PERSIST_ID) end) end
end

local function map_slot_matches_da(at, da)
    if at == nil then return true end
    if uobject_same(at, da) then return true end
    return get_persist_id(at) == get_persist_id(da)
end

local function clear_da_index(da)
    pcall(function() da.BuildingPieceDataIndex = -1 end)
end

-- Never probe the live catalogue here (FindPieceDataForIndex / slot resolve can hard-crash without pak override).
local function force_clear_mod_da_index(da)
    if not da or get_persist_id(da) ~= K.PERSIST_ID then return end
    clear_da_index(da)
end

local function clear_piece_requirements(da)
    if not da then return end
    pcall(function()
        local req = da.Requirements
        if req and req.Clear then req:Clear() end
    end)
end

local function fname_label(v)
    if type(v) == "string" and v ~= "" and v ~= "None" then return v end
    if v and v.ToString then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" and s ~= "" and s ~= "None" then return s end
    end
    return nil
end

local function stability_row_handle_valid(da)
    if not da then return false end
    local ok, valid = pcall(function()
        local h = da.BuildingStabilityProfileRowHandle
        if not h then return false end
        if not fname_label(h.RowName) then return false end
        local dt = h.DataTable
        if dt == nil then return false end
        if type(dt) == "userdata" and is_valid(dt) then return true end
        return false
    end)
    return ok and valid == true
end

local function describe_stability_row_handle(da)
    if not da then return "da=nil" end
    local parts = {}
    pcall(function()
        local h = da.BuildingStabilityProfileRowHandle
        if not h then
            parts[#parts + 1] = "handle=nil"
            return
        end
        parts[#parts + 1] = "row=" .. tostring(fname_label(h.RowName) or "?")
        local dt = h.DataTable
        if is_valid(dt) and dt.GetFullName then
            parts[#parts + 1] = "dt=" .. tostring(dt:GetFullName())
        else
            parts[#parts + 1] = "dt=" .. tostring(dt)
        end
    end)
    return table.concat(parts, " ")
end

local function make_stability_row_handle(dt, row_name)
    local row = row_name
    if FName then
        pcall(function() row = FName(row_name) end)
    end
    local ok_ue, ue = pcall(require, "UEHelpers")
    if ok_ue and ue and ue.FindOrAddFName then
        pcall(function() row = ue.FindOrAddFName(row_name) end)
    end
    return { DataTable = dt, RowName = row }
end

local function assign_stability_row_handle(da, handle)
    if not da or not handle then return false end
    local ok = pcall(function() da.BuildingStabilityProfileRowHandle = handle end)
    if ok and stability_row_handle_valid(da) then return true end
    pcall(function()
        local h = da.BuildingStabilityProfileRowHandle
        if h then
            h.DataTable = handle.DataTable
            h.RowName = handle.RowName
        end
    end)
    return stability_row_handle_valid(da)
end

local function resolve_stability_datatable()
    if StaticFindObject then
        local ok, dt = pcall(StaticFindObject, K.STABILITY_DT_PATH)
        if ok and is_valid(dt) then return dt end
    end
    return load_object(K.STABILITY_DT_PATH)
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
            local row = dt:FindRow(row_name)
            if row ~= nil then return true end
            if FName then
                local ok_fn, fn = pcall(function() return FName(row_name) end)
                if ok_fn and fn then
                    row = dt:FindRow(fn)
                    if row ~= nil then return true end
                end
            end
        end
        return false
    end)
    return ok and resolved == true
end

local function copy_stability_from_vanilla_da(da)
    local vanilla = load_object(K.VANILLA_FOUNDATION_DA)
    if not vanilla then return false end
    local copied = false
    pcall(function()
        da.BuildingStabilityProfileRowHandle = vanilla.BuildingStabilityProfileRowHandle
        copied = true
    end)
    if stability_row_native_resolves(da) then return true end
    if copied and stability_row_handle_valid(da) then return true end
    pcall(function()
        local vh = vanilla.BuildingStabilityProfileRowHandle
        if vh then
            assign_stability_row_handle(da, {
                DataTable = vh.DataTable,
                RowName = vh.RowName,
            })
        end
    end)
    return stability_row_native_resolves(da) or stability_row_handle_valid(da)
end

local function ensure_da_stability_profile(da, force)
    if not da then return end
    if not force and stability_row_native_resolves(da) then return end

    preload_mod_assets()
    if copy_stability_from_vanilla_da(da) and stability_row_native_resolves(da) then
        return
    end

    local dt = resolve_stability_datatable()
    if dt and assign_stability_row_handle(da, make_stability_row_handle(dt, K.STABILITY_ROW_NAME)) then
        if stability_row_native_resolves(da) then return end
    end

    copy_stability_from_vanilla_da(da)
    if not stability_row_native_resolves(da) and not stability_row_handle_valid(da) then
        print(K.TAG .. " warn: stability row handle still invalid (" .. describe_stability_row_handle(da) .. ")")
    end
end

local allocate_deferred_index
local get_shared_deferred_index
local set_shared_deferred_index
local make_transform

local catalogue = require("catalogue")
catalogue.bind({
    TAG = K.TAG,
    DA_PATH = K.DA_PATH,
    DA_PKG = K.DA_PKG,
    PERSIST_ID = K.PERSIST_ID,
    CATALOGUE_PATH = K.CATALOGUE_PATH,
    CATALOGUE_PKG = K.CATALOGUE_PKG,
    CATALOGUE_OBJ = K.CATALOGUE_OBJ,
    MOD_CATALOGUE_PKG = K.MOD_CATALOGUE_PKG,
    MOD_CATALOGUE_OBJ = K.MOD_CATALOGUE_OBJ,
    CATALOGUE_INDEX = K.CATALOGUE_INDEX,
    CATALOGUE_INDEX_KEY = K.CATALOGUE_INDEX_KEY,
    CATALOGUE_PATCH_LOGGED = K.CATALOGUE_PATCH_LOGGED,
    CATALOGUE_MISS_LOGGED = K.CATALOGUE_MISS_LOGGED,
    is_valid = is_valid,
    load_object = load_object,
    string_from_fstring = string_from_fstring,
    uobject_same = uobject_same,
    get_persist_id = get_persist_id,
    clear_da_index = clear_da_index,
    map_slot_matches_da = map_slot_matches_da,
    tmap_find = tmap_find,
    tmap_add = tmap_add,
    bump_num_building_piece_datas = bump_num_building_piece_datas,
    ensure_da_stability_profile = ensure_da_stability_profile,
    preload_mod_assets = preload_mod_assets,
    make_transform = function(x, y, z, yaw) return make_transform(x, y, z, yaw) end,
    set_shared_deferred_index = function(idx) return set_shared_deferred_index(idx) end,
    allocate_deferred_index = function(sub, da) return allocate_deferred_index(sub, da) end,
    load_asset_blocking = load_asset_blocking,
})

local function patch_preview_stability(bmc, da, mesh_only)
    if not is_valid(bmc) then return false end
    local preview = weak_get(bmc.PreviewPiece)
    if not is_valid(preview) then return false end
    local changed = false
    if not mesh_only and da then
        catalogue.prepare_da_for_native_build(da, true)
        pcall(function()
            if not actor_uses_our_da(preview, da) then
                preview.BuildingPieceData = da
                changed = true
            end
        end)
        if patch_actor_stability(preview, da) then changed = true end
    end
    if patch_actor_stability_value(preview) then changed = true end
    return changed
end

leave_build_mode_safe = function(bmc)
    if not is_valid(bmc) then return end
    -- Do not assign nil to weak object properties (PreviewPiece, CurrentlyPlacingPieceData):
    -- UE4SS 3.x throws [push_weakobjectproperty] Operation::Set is not supported.
    pcall(function() bmc.CurrentBuildMode = 0 end)
    if bmc.ExitAnyMode then
        pcall(function() bmc:ExitAnyMode() end)
    end
end

make_transform = function(x, y, z, yaw_deg)
    local yaw_rad = (yaw_deg or 0) * math.pi / 180.0
    local half = yaw_rad * 0.5
    return {
        Rotation = { X = 0, Y = 0, Z = math.sin(half), W = math.cos(half) },
        Translation = { X = x or 0, Y = y or 0, Z = z or 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
end

local function find_world_building_subsystem()
    if FindFirstOf then
        local ok, sub = pcall(FindFirstOf, "BuildingSubsystem")
        if ok and is_valid(sub) then return sub end
    end
    return nil
end

local function enable_build_cheats()
    local sub = find_world_building_subsystem()
    if not is_valid(sub) then return end
    pcall(function() sub.bCheatAlwaysAllowBuilding = true end)
end

local function get_building_ui_api()
    if FindFirstOf then
        local ok, hud = pcall(FindFirstOf, "HUDUISubsystem")
        if ok and is_valid(hud) then
            local api
            pcall(function() api = hud.BuildingAPI end)
            if is_valid(api) then return api end
        end
    end
    return nil
end

local function notify_building_ui_unlock(da)
    if not da then return end
    local api = get_building_ui_api()
    if not api then return end
    pcall(function() api:OnBuildingsUnlocked({ da }, false) end)
    if api.CallOnBuildingItemSelected then
        pcall(function() api:CallOnBuildingItemSelected(da) end)
    end
end

local function spawn_diagnostics(bmc, da, idx, source)
    local mode = "?"
    pcall(function()
        if bmc.GetCurrentBuildMode then
            mode = tostring(bmc:GetCurrentBuildMode())
        end
    end)
    local placing = "no"
    pcall(function()
        local cur = weak_get(bmc.CurrentlyPlacingPieceData)
        if is_valid(cur) then
            placing = uobject_same(cur, da) and "ours" or "other"
        end
    end)
    local preview = "none"
    pcall(function()
        local p = weak_get(bmc.PreviewPiece)
        if is_valid(p) then preview = "ok" end
    end)
    print(string.format(
        "%s spawn diag: index=%s source=%s buildMode=%s placing=%s preview=%s daIdx=%s stability=%s nativeStability=%s",
        K.TAG, tostring(idx), tostring(source or "?"), mode, placing, preview,
        (function()
            local di
            pcall(function() di = da and da.BuildingPieceDataIndex end)
            return tostring(di)
        end)(),
        describe_stability_row_handle(da),
        stability_row_native_resolves(da) and "ok" or "fail"
    ))
end

local function find_nearest_building_actor_near(loc, max_dist)
    if not loc then return nil end
    local best, best_d2
    local max_d2 = (max_dist or 900) * (max_dist or 900)
    local max_xy = (max_dist or 900) * (max_dist or 900)
    local function consider(a)
        if not is_valid(a) or is_build_preview_actor(a, nil) then return end
        local aloc
        pcall(function() aloc = a:K2_GetActorLocation() end)
        aloc = copy_vector(aloc)
        if not aloc then return end
        local d2 = dist_sq(loc, aloc)
        local dxy = dist_sq_xy(loc, aloc)
        if (d2 <= max_d2 or dxy <= max_xy) and (not best_d2 or d2 < best_d2) then
            best, best_d2 = a, d2
        end
    end
    foreach_building_subsystem_actor(consider)
    if not is_valid(best) and FindAllOf then
        pcall(function()
            local list = FindAllOf("BaseBuildingActor")
            if type(list) == "table" then
                for _, a in pairs(list) do consider(a) end
            end
        end)
    end
    return best
end

find_placed_actor_after_spawn = function(loc, da, alt_da, max_dist)
    local placed = find_spawned_piece_near(loc, da, max_dist)
    if is_valid(placed) then return placed end
    if alt_da and not uobject_same(alt_da, da) then
        placed = find_spawned_piece_near(loc, alt_da, max_dist)
        if is_valid(placed) then return placed end
        placed = find_vanilla_foundation_near(loc, alt_da, max_dist)
        if is_valid(placed) then return placed end
    end
    return find_nearest_building_actor_near(loc, max_dist)
end

-- RSDWTools-style: SetStaticMesh on all StaticMeshComponents (BP foundation uses actor.Mesh).
local function patch_placed_mesh_minimal(actor)
    if not is_valid(actor) then return false end
    local mesh = resolve_mod_mesh(true)
    if not mesh then return false end
    if actor_has_mod_mesh(actor, mesh) then return false end
    if patch_actor_mesh(actor, mesh) then return true end
    local comp = get_actor_static_mesh_component(actor)
    if comp and set_comp_static_mesh(comp, mesh) then return true end
    return false
end

configure_placed_actor = function(actor, da, _idx, mesh_only)
    if not is_valid(actor) or not da then return false end
    local mesh = resolve_mod_mesh(true)
    if mesh_only then
        local ok = patch_placed_mesh_minimal(actor)
        unhide_placed_actor(actor)
        return ok
    end
    ensure_persist_id(da)
    -- Apply mesh before DA swap; native refresh on BuildingPieceData can clear materials/mesh.
    if mesh then patch_placed_mesh_minimal(actor) end
    local da_set = false
    pcall(function()
        actor.BuildingPieceData = da
        da_set = true
    end)
    pcall(function() actor.PersistenceID = K.PERSIST_ID end)
    -- Never write deferred subsystem map slots onto actor.BuildingPieceDataIndex:
    -- native stability/telemetry indexes the live catalogue array (crash at ~648).
    pcall(function() actor.bIsPreview = false end)
    pcall(function() actor.bIsGhosted = false end)
    unhide_placed_actor(actor)
    patch_actor_stability_value(actor)
    local changed = da_set
    if mesh and patch_actor_mesh(actor, mesh) then changed = true end
    if patch_piece_actor(actor, da, mesh) then changed = true end
    if da_set and actor_uses_our_da(actor, da) then changed = true end
    if mesh and not actor_has_mod_mesh(actor, mesh) then
        if patch_placed_mesh_minimal(actor) then changed = true end
    end
    unhide_placed_actor(actor)
    local da_name, mesh_ok = "?", false
    pcall(function()
        local pd = actor.BuildingPieceData
        if is_valid(pd) and pd.GetFullName then da_name = pd:GetFullName() end
    end)
    if mesh then mesh_ok = actor_has_mod_mesh(actor, mesh) end
    print(string.format(
        "%s configure_placed: da=%s mesh_ok=%s changed=%s",
        K.TAG, da_name, tostring(mesh_ok), tostring(changed)
    ))
    return changed
end

local function get_progress_component()
    local pc = get_local_player_controller()
    if not is_valid(pc) then return nil, "no player controller" end
    local prog
    pcall(function() prog = pc.ProgressComponent end)
    if not is_valid(prog) then return nil, "no ProgressComponent" end
    return prog, nil
end

local function ensure_piece_unlocked(da, prefer_vanilla)
    if not da then return false end
    rawset(_G, K.LUA_UNLOCKED_KEY, true)
    local unlock_da = da
    if prefer_vanilla then
        if LoadAsset then
            pcall(function() LoadAsset(K.VANILLA_FOUNDATION_DA) end)
        end
        unlock_da = load_object(K.VANILLA_FOUNDATION_DA) or da
    end
    local prog = select(1, get_progress_component())
    if not is_valid(prog) or not prog.UnlockBuildings then return true end
    pcall(function() prog:UnlockBuildings({ unlock_da }) end)
    return true
end

local function ensure_da_mod_visuals(da)
    if not da then return false end
    ensure_visuals(da)
    local mesh = resolve_mod_mesh(true)
    if mesh and assign_da_proxy_mesh(da, mesh) then
        return true
    end
    return mesh ~= nil
end

local function select_mod_piece_for_build(bmc, da)
    if not is_valid(da) then
        return nil, "DA_Stonewall not loaded"
    end
    ensure_da_mod_visuals(da)
    catalogue.prepare_da_for_native_build(da, true)
    clear_piece_requirements(da)
    if not is_valid(bmc) or not bmc.OnPieceSelected then
        return nil, "OnPieceSelected missing on BuildModeComponent"
    end
    local ok, err = pcall(function() bmc:OnPieceSelected(da) end)
    if not ok then
        return nil, "OnPieceSelected(DA_Stonewall) failed: " .. tostring(err)
    end
    return da, nil
end

local function finalize_placed_building_actor(actor, da)
    if not is_valid(actor) or not da then return false end
    return configure_placed_actor(actor, da, nil, false)
end

local function prepare_build_mode_spawn(bmc, da)
    if not is_valid(da) then return false, "DA missing" end
    if is_valid(bmc) and bmc.ForceEnterBuildMode then
        pcall(function() bmc:ForceEnterBuildMode() end)
    end
    local selected, err = select_mod_piece_for_build(bmc, da)
    if not selected then return false, err end
    patch_preview_stability(bmc, da)
    return true, nil
end

local _cached_vanilla_foundation_da = nil

resolve_vanilla_foundation_da = function(allow_load)
    if is_valid(_cached_vanilla_foundation_da) then
        return _cached_vanilla_foundation_da
    end
    _cached_vanilla_foundation_da = find_object_mounted(K.VANILLA_FOUNDATION_DA)
    if is_valid(_cached_vanilla_foundation_da) then return _cached_vanilla_foundation_da end
    if allow_load == false then return nil end
    if LoadAsset then
        pcall(function() LoadAsset(K.VANILLA_FOUNDATION_DA) end)
    end
    _cached_vanilla_foundation_da = find_object_mounted(K.VANILLA_FOUNDATION_DA)
        or load_object(K.VANILLA_FOUNDATION_DA)
    return _cached_vanilla_foundation_da
end

local function select_vanilla_piece_for_deferred(bmc, _mod_da)
    local vanilla = resolve_vanilla_foundation_da(true)
    if not is_valid(vanilla) then
        return nil, "vanilla foundation DA not found (enter world first)"
    end
    clear_piece_requirements(vanilla)
    if not is_valid(bmc) or not bmc.OnPieceSelected then
        return nil, "OnPieceSelected missing on BuildModeComponent"
    end
    -- Do not call ForceEnterBuildMode here -- with find_index-only catalogue it hard-crashes before select.
    -- ProxyMesh swap drives native preview + LMB-placed mesh (SetStaticMesh on preview actor alone is not enough).
    pcall(function() apply_vanilla_proxy_mod_mesh(vanilla) end)
    print(K.TAG .. " deferred select: OnPieceSelected(vanilla foundation)...")
    rawset(_G, K.DEFERRED_SELECT_GUARD_KEY, true)
    local ok, err = pcall(function() bmc:OnPieceSelected(vanilla) end)
    rawset(_G, K.DEFERRED_SELECT_GUARD_KEY, nil)
    if not ok then
        return nil, "OnPieceSelected(vanilla) failed: " .. tostring(err)
    end
    return vanilla, nil
end

local function begin_native_build_mode(bmc, mod_da, log_label)
    if not is_valid(mod_da) then
        return false, "DA_Stonewall not loaded"
    end
    ensure_da_mod_visuals(mod_da)
    catalogue.prepare_da_for_native_build(mod_da, true)
    clear_piece_requirements(mod_da)

    local selected, err = select_mod_piece_for_build(bmc, mod_da)
    if not selected then
        return false, err
    end

    refresh_deferred_preview_patch(bmc, mod_da, true, log_label or "build preview")
    schedule_preview_patch_retries(bmc, mod_da, 12)
    capture_deferred_preview_loc(bmc)
    capture_deferred_piece_snapshot()
    start_deferred_build_watches(bmc, mod_da)
    return true, nil
end

-- Legacy fallback only when native OnPieceSelected(DA_Stonewall) fails without catalogue.
local function begin_deferred_build_mode(bmc, mod_da, log_label)
    if not is_valid(mod_da) then
        return false, "DA_Stonewall not loaded"
    end
    -- Vanilla OnPieceSelected + ProxyMesh swap -- never prepare mod DA for native build here
    -- (prepare_da_for_native_build can probe catalogue slot 651 and hard-crash when slot651=nil).
    force_clear_mod_da_index(mod_da)
    clear_piece_requirements(mod_da)

    local selected, err = select_vanilla_piece_for_deferred(bmc, mod_da)
    if not selected then
        return false, err
    end

    set_deferred_build_session(true)
    refresh_deferred_preview_patch(bmc, mod_da, true, log_label or "build preview")
    start_deferred_preview_watch(bmc, mod_da)
    capture_deferred_preview_loc(bmc)
    capture_deferred_piece_snapshot()
    start_deferred_build_watches(bmc, mod_da)
    return true, nil
end

-- Foreign = a piece from a different catalogue slot (vanilla build) -- never retag/re-mesh it.
-- Only enforced when the session declared an expected index (native651 path).
function M.actor_is_foreign_piece(actor)
    local expected = rawget(_G, K.EXPECTED_IDX_KEY)
    if type(expected) ~= "number" or not is_valid(actor) then return false end
    local idx
    pcall(function() idx = actor.BuildingPieceDataIndex end)
    if type(idx) == "number" and idx > 0 and idx ~= expected then return true end
    local pd
    pcall(function() pd = actor.BuildingPieceData end)
    if is_valid(pd) then
        local da = find_registered_da()
        if da and not uobject_same(pd, da) then return true end
    end
    return false
end

patch_deferred_placed_actor = function(actor, mod_da, bmc, finalize, force)
    if not is_valid(actor) or not mod_da then return false end
    if M.actor_is_foreign_piece(actor) then return false end
    if not force and is_build_preview_actor(actor, bmc) then return false end
    local ref_loc = rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY)
    if not force and not actor_should_patch_for_deferred(actor, mod_da, ref_loc, bmc) then
        return false
    end
    local mesh = resolve_mod_mesh(true)
    if not mesh then
        print(K.TAG .. " warn: SM_Stonewall not mounted (stonewall_diag)")
        return false
    end
    if actor_uses_our_da(actor, mod_da) and actor_has_mod_mesh(actor, mesh) then
        if finalize then finish_deferred_placement_session(bmc) end
        return true
    end

    configure_placed_actor(actor, mod_da, nil, false)
    if not actor_has_mod_mesh(actor, mesh) then
        patch_placed_mesh_minimal(actor)
    end
    unhide_placed_actor(actor)
    if not actor_has_mod_mesh(actor, mesh) then
        print(K.TAG .. " placed: mesh patch failed (actor still vanilla mesh)")
        return false
    end
    print(K.TAG .. " placed: DA_Stonewall building piece finalized")

    if finalize then
        finish_deferred_placement_session(bmc)
        stop_mesh_patch_loop_only()
    end
    return true
end

-- After click-to-place with vanilla build-mode DA, retag actor -> DA_Stonewall + mod mesh.
local function find_deferred_placed_candidate(ref_loc, mod_da, vanilla, bmc, radius)
    if not ref_loc then return nil end
    radius = radius or 2000
    local mesh = resolve_mod_mesh(true)
    local best, best_d2
    local max_d2 = radius * radius

    local function consider(a)
        if not is_valid(a) or is_build_preview_actor(a, bmc) then return end
        if mesh and actor_has_mod_mesh(a, mesh) and actor_uses_our_da(a, mod_da) then return end
        if vanilla and actor_is_vanilla_foundation(a, vanilla) then
            -- always candidate
        elseif not actor_should_patch_for_deferred(a, mod_da, ref_loc, bmc) then
            return
        end
        local aloc
        pcall(function() aloc = a:K2_GetActorLocation() end)
        aloc = copy_vector(aloc)
        if not aloc then return end
        local d2 = dist_sq(ref_loc, aloc)
        local dxy = dist_sq_xy(ref_loc, aloc)
        if (d2 <= max_d2 or dxy <= max_d2) and (not best_d2 or d2 < best_d2) then
            best, best_d2 = a, d2
        end
    end

    foreach_building_subsystem_actor(consider)
    if not is_valid(best) and FindAllOf then
        pcall(function()
            local list = FindAllOf("BaseBuildingActor")
            if type(list) == "table" then
                for _, a in pairs(list) do consider(a) end
            end
        end)
    end
    return best
end

patch_deferred_click_placement = function(bmc, mod_da, override_loc, data_idx)
    if not mod_da then mod_da = find_registered_da() end
    if not mod_da then return false end
    local vanilla = resolve_vanilla_foundation_da()
    if not vanilla then return false end
    if not resolve_mod_mesh(true) then return false end

    local ref_loc = copy_vector(override_loc) or rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY)
    if not ref_loc and is_valid(bmc) then
        local preview = weak_get(bmc.PreviewPiece)
        if is_valid(preview) then
            pcall(function() ref_loc = copy_vector(preview:K2_GetActorLocation()) end)
        end
    end

    local tracked = rawget(_G, K.DEFERRED_PREVIEW_ACTOR_KEY)
    local best
    local before_ids = rawget(_G, K.DEFERRED_PIECE_IDS_KEY)

    -- Telemetry idx (e.g. 526) is the placed vanilla piece -- prefer over ex-preview ghost.
    if type(data_idx) == "number" then
        best = find_subsystem_actor_by_data_index(data_idx, ref_loc, 8000)
        if is_valid(best) and patch_deferred_placed_actor(best, mod_da, bmc, true, true) then
            return true
        end
    end

    best = find_new_subsystem_actor(before_ids, ref_loc, 8000)
    if not is_valid(best) and vanilla then
        local van_idx
        pcall(function() van_idx = vanilla.BuildingPieceDataIndex end)
        if type(van_idx) == "number" then
            best = find_subsystem_actor_by_data_index(van_idx, ref_loc, 8000)
        end
    end
    if not is_valid(best) and ref_loc then
        best = find_deferred_placed_candidate(ref_loc, mod_da, vanilla, bmc, 8000)
    end
    if not is_valid(best) and ref_loc then
        best = find_vanilla_foundation_near(ref_loc, vanilla, 8000)
    end
    if not is_valid(best) and ref_loc then
        best = find_nearest_building_actor_near(ref_loc, 8000)
    end
    if not is_valid(best) and is_valid(tracked) and not is_build_preview_actor(tracked, bmc) then
        best = tracked
    end
    if not is_valid(best) then
        return false
    end
    if patch_deferred_placed_actor(best, mod_da, bmc, true, true) then
        return true
    end
    return false
end

local function deferred_patch_actor_from_hook(actor, _label, finalize)
    if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then return end
    actor = unwrap_remote(actor)
    if not is_valid(actor) then return end
    local da = find_registered_da()
    if not da then return end
    local function run()
        patch_deferred_placed_actor(actor, da, nil, finalize ~= false, true)
    end
    if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
end

deferred_trigger_placed_patch = function(bmc, loc, label, data_idx)
    if rawget(_G, K.DEFERRED_BUILD_ACTIVE) ~= true then return end
    if rawget(_G, K.PLACE_FINISH_KEY) == true or rawget(_G, K.PLACE_PATCH_DONE) == true then
        return
    end
    bmc = unwrap_remote(bmc)
    local da = find_registered_da()
    if not da then return end
    loc = copy_vector(loc) or rawget(_G, K.DEFERRED_PREVIEW_LOC_KEY)
    data_idx = unwrap_uint32(data_idx)
    local function run()
        if rawget(_G, K.PLACE_FINISH_KEY) == true then return true end
        if patch_deferred_click_placement(bmc, da, loc, data_idx) then
            print(string.format("%s placed: finalized -> DA_Stonewall (%s)", K.TAG, label or "place event"))
            return true
        end
        if not rawget(_G, K.DEFERRED_PATCH_WARNED_KEY) then
            rawset(_G, K.DEFERRED_PATCH_WARNED_KEY, true)
            local loc_s = loc and string.format("(%.0f, %.0f, %.0f)", loc.X or 0, loc.Y or 0, loc.Z or 0) or "nil"
            print(string.format(
                "%s warn: placed actor not found for mesh patch (%s; loc=%s idx=%s)",
                K.TAG, label or "place", loc_s, tostring(data_idx)))
        end
        return false
    end
    local function attempt_once()
        -- The whole patch+finish must run inside one game-thread closure:
        -- ExecuteInGameThread is async, so finishing out here would set
        -- PLACE_FINISH_KEY before run() executes and run() would no-op
        -- (placed piece stayed vanilla until the next save/load scan).
        local fn = function()
            local patched = run()
            -- native651: placement itself is fully native, the patch is cosmetic only.
            -- Always end the session so later vanilla builds are never touched.
            if patched or rawget(_G, K.EXPECTED_IDX_KEY) == K.CATALOGUE_INDEX then
                finish_deferred_placement_session(bmc)
            end
        end
        if ExecuteInGameThread then ExecuteInGameThread(fn) else fn() end
    end
    if LoopAsync then
        LoopAsync(200, function()
            attempt_once()
            return true
        end)
    else
        attempt_once()
    end
end

local function try_spawn_piece_at_location(bmc, da, loc, rot)
    if not is_valid(bmc) or not da or not loc then
        return false, "missing bmc/da/loc", nil
    end
    if not bmc.TrySpawnPieceAtLocation then
        return false, "TrySpawnPieceAtLocation missing", nil
    end
    local rotator = {
        Pitch = (rot and rot.Pitch) or 0,
        Yaw = (rot and rot.Yaw) or 0,
        Roll = (rot and rot.Roll) or 0,
    }
    local state
    local ok, err = pcall(function()
        state = bmc:TrySpawnPieceAtLocation(da, loc, rotator)
    end)
    if not ok then return false, tostring(err), nil end
    local label = validity_spawn_state_label(state)
    return validity_spawn_state_is_success(state), label, state
end

local function describe_spawn_da(da)
    if not is_valid(da) then return "nil" end
    local fn
    pcall(function() fn = da:GetFullName() end)
    if type(fn) == "string" and fn:find("DA_Stonewall", 1, true) then
        return "DA_Stonewall"
    end
    return fn or "?"
end

local function resolve_active_spawn_da(bmc, preferred)
    if is_valid(bmc) then
        local cur = weak_get(bmc.CurrentlyPlacingPieceData)
        if is_valid(cur) then return cur end
    end
    return preferred
end

local function try_spawn_with_retries(bmc, spawn_da, loc, rot, attempts, mod_da)
    attempts = attempts or 3
    local last_label = "None"
    local last_spawn_da = spawn_da
    for i = 1, attempts do
        last_spawn_da = resolve_active_spawn_da(bmc, last_spawn_da)
        if not is_valid(last_spawn_da) then last_spawn_da = spawn_da end
        local tok, tlabel = try_spawn_piece_at_location(bmc, last_spawn_da, loc, rot)
        last_label = tlabel
        if tok then return true, tlabel, last_spawn_da end
        if tlabel ~= "None" then break end
    end
    return false, last_label, last_spawn_da
end

-- Catalogue miss path: TrySpawn with mod DA directly (same approach as RSDWTools mod.foundation.spawn).
local function try_spawn_deferred_at(bmc, sub, mod_da, loc, rot)
    if not is_valid(bmc) or not mod_da or not loc then
        return false, "missing bmc/da/loc", mod_da
    end
    sub = sub or subsystem.find()
    local idx = get_shared_deferred_index()
    if idx == nil and sub then
        idx = allocate_deferred_index(sub, mod_da)
    end
    if idx == nil then
        return false, "no_deferred_map_slot", mod_da
    end

    ensure_piece_unlocked(mod_da, true)
    ensure_da_stability_profile(mod_da, true)
    clear_piece_requirements(mod_da)
    enable_build_cheats()

    if bmc.ForceEnterBuildMode then
        pcall(function() bmc:ForceEnterBuildMode() end)
    end
    if bmc.OnPieceSelected then
        pcall(function() bmc:OnPieceSelected(mod_da) end)
    end
    local cur = weak_get(bmc.CurrentlyPlacingPieceData)
    if not is_valid(cur) then
        return false, "OnPieceSelected(DA_Stonewall) did not set placing piece", mod_da
    end

    spawn_diagnostics(bmc, mod_da, idx, "mod_da")
    print(string.format(
        "%s TrySpawnPieceAtLocation(DA_Stonewall) map_slot=%d",
        K.TAG, idx
    ))

    local tok, tlabel = try_spawn_with_retries(bmc, mod_da, loc, rot, 3, mod_da)
    return tok, tlabel, mod_da
end

local function warn_if_rsdwtools_loaded()
    if warned_rsdwtools then return end
    if rawget(_G, "RSDWTOOLS_MOD_FOUNDATION_BOOT_SCHEDULED")
        or rawget(_G, "RSDWTOOLS_MOD_FOUNDATION_BOOT_OK") then
        warned_rsdwtools = true
        print(K.TAG .. " WARNING: RSDWTools is also loaded and touches DA_Stonewall.")
        print(K.TAG .. " Disable RSDWTools in mods.txt AND remove RSDWTools/enabled.txt for standalone use.")
    end
end

find_registered_da = function(sub)
    local function pick_from(s)
        if not s then return nil end
        local parent = s.PersistenceIDToDataMap
        if parent then
            local da = tmap_find(parent, K.PERSIST_ID)
            if da ~= nil then return da end
        end
        local pid_map = s.PersistenceIDToBuildingPieceDataMap
        if pid_map then
            local da = tmap_find(pid_map, K.PERSIST_ID)
            if da ~= nil then return da end
        end
        return nil
    end

    if sub then
        local da = pick_from(sub)
        if da then return da end
    end

    for _, live in ipairs(subsystem.all()) do
        local da = pick_from(live)
        if da then return da end
    end

    local cached = rawget(_G, "RSDWBUILDS_REGISTERED_MOD_DA")
    if type(cached) == "userdata" then return cached end
    return nil
end

local function sync_spawn_da(sub, da, idx)
    da = find_registered_da(sub) or da
    if sub and idx ~= nil then
        local idx_map = sub.BuildingPieceDataIndexToBuildingPieceData
        local from_idx = idx_map and tmap_find(idx_map, idx) or nil
        if is_valid(from_idx) then da = from_idx end
    end
    return da
end

get_shared_deferred_index = function()
    local idx = rawget(_G, K.DEFERRED_KEY)
    if type(idx) == "number" and idx >= 0 then return idx end
    idx = rawget(_G, K.TOOLS_DEFERRED_KEY)
    if type(idx) == "number" and idx >= 0 then return idx end
    return nil
end

set_shared_deferred_index = function(idx)
    if type(idx) == "number" and idx >= 0 then
        rawset(_G, K.DEFERRED_KEY, idx)
    else
        rawset(_G, K.DEFERRED_KEY, nil)
    end
end

local function register_da_persistence(sub, da)
    if not da then return false, "DA not loaded" end
    local subs = subsystem.collect_all(sub)
    if #subs == 0 then return false, "BuildingPieceSubsystem not ready (load into world first)" end

    warn_if_rsdwtools_loaded()
    local registered = find_registered_da(sub)
    if registered and not uobject_same(registered, da) then
        da = registered
    end

    local hydration_stub = rawget(_G, K.HYDRATION_STUB_KEY) == true
    if hydration_stub then
        clear_piece_requirements(da)
    else
        rawset(_G, K.HYDRATION_STUB_KEY, nil)
        ensure_persist_id(da)
        clear_piece_requirements(da)
        force_clear_mod_da_index(da)
    end

    -- Save hydration keys BuildingsUnlocked by persistence id string, not the DA field.
    local pid = hydration_stub and K.PERSIST_ID or get_persist_id(da)
    local wrote = false
    for _, live in ipairs(subs) do
        local parent = live.PersistenceIDToDataMap
        if not parent then
            return false, "PersistenceIDToDataMap missing"
        end
        if tmap_find(parent, pid) == nil then
            local ok, err = tmap_add(parent, pid, da)
            if not ok then return false, "PersistenceIDToDataMap Add failed: " .. tostring(err) end
            wrote = true
        end
        local pid_map = live.PersistenceIDToBuildingPieceDataMap
        if pid_map and tmap_find(pid_map, pid) == nil then
            tmap_add(pid_map, pid, da)
        end
        pcall(function()
            local internal = live.InternalNameToDataMap
            if internal then
                for _, name in ipairs({ K.DA_PKG, K.DA_PATH }) do
                    if tmap_find(internal, name) == nil then
                        tmap_add(internal, name, da)
                    end
                end
            end
        end)
    end

    rawset(_G, "RSDWBUILDS_REGISTERED_MOD_DA", da)
    if not find_registered_da(sub) and not find_registered_da() then
        return false, "registered but PersistenceIDToDataMap lookup failed"
    end
    local suffix = hydration_stub and " (hydration stub; pak DA missing)" or ""
    return true, (wrote and "registered " or "already had ") .. pid .. suffix
end

local function register_da_index_maps(sub, da)
    if not sub or not da then return end
    ensure_da_stability_profile(da, true)
    -- Subsystem index map only at runtime (F8/build). Never probe IoStore catalogue during load.
    if type(K.CATALOGUE_INDEX) ~= "number" then return end
    pcall(function()
        local idx_map = sub.BuildingPieceDataIndexToBuildingPieceData
        if not idx_map then return end
        local at = tmap_find(idx_map, K.CATALOGUE_INDEX)
        if at == nil then
            tmap_add(idx_map, K.CATALOGUE_INDEX, da)
        elseif is_valid(at) and not uobject_same(at, da) then
            tmap_replace(idx_map, K.CATALOGUE_INDEX, da)
        end
        bump_num_building_piece_datas(sub, K.CATALOGUE_INDEX)
    end)
end

local function tmap_replace(map, key, val)
    if not map then return false end
    pcall(function() map:Remove(key) end)
    return tmap_add(map, key, val)
end

try_upgrade_from_hydration_stub = function(reason)
    if rawget(_G, K.HYDRATION_STUB_KEY) ~= true then return false end
    local mod_da = find_mod_da_mounted()
    if not is_valid(mod_da) then return false end

    rawset(_G, K.HYDRATION_STUB_KEY, nil)
    cached_mod_mesh = nil
    rawset(_G, "RSDWBUILDS_REGISTERED_MOD_DA", mod_da)
    ensure_persist_id(mod_da)
    clear_piece_requirements(mod_da)
    force_clear_mod_da_index(mod_da)

    local sub = subsystem.find()
    if sub then
        for _, live in ipairs(subsystem.collect_all(sub)) do
            tmap_replace(live.PersistenceIDToDataMap, K.PERSIST_ID, mod_da)
            tmap_replace(live.PersistenceIDToBuildingPieceDataMap, K.PERSIST_ID, mod_da)
            pcall(function()
                local internal = live.InternalNameToDataMap
                if internal then
                    for _, name in ipairs({ K.DA_PKG, K.DA_PATH }) do
                        tmap_replace(internal, name, mod_da)
                    end
                end
            end)
        end
        pcall(function() register_da_index_maps(sub, mod_da) end)
    end

    if not rawget(_G, "RSDWBUILDS_STUB_UPGRADE_LOGGED") then
        rawset(_G, "RSDWBUILDS_STUB_UPGRADE_LOGGED", true)
        print(K.TAG .. " upgraded hydration stub -> DA_Stonewall (" .. tostring(reason or "?") .. ")")
    end
    try_cache_mod_mesh_from_mount()
    return true
end

local function register_da(da, sub)
    local ok, detail = register_da_persistence(sub, da)
    if not ok then return false, detail end
    sub = sub or subsystem.find()
    da = find_registered_da(sub) or da
    register_da_index_maps(sub, da)
    return true, detail
end

local function load_da_for_boot()
    warn_if_rsdwtools_loaded()
    rawset(_G, K.HYDRATION_STUB_KEY, nil)
    local registered = find_registered_da()
    if registered then
        ensure_persist_id(registered)
        clear_piece_requirements(registered)
        force_clear_mod_da_index(registered)
        return registered, nil
    end
    local da = find_object_mounted(K.DA_PATH)
    if da then
        ensure_persist_id(da)
        clear_piece_requirements(da)
        force_clear_mod_da_index(da)
        return da, nil
    end
    if LoadAsset then
        pcall(function() LoadAsset(K.DA_PKG) end)
        pcall(function() LoadAsset(K.DA_PATH) end)
    end
    da = load_object(K.DA_PATH)
    if da then
        ensure_persist_id(da)
        clear_piece_requirements(da)
        force_clear_mod_da_index(da)
        return da, nil
    end
    -- Pak DA missing (SkipPackage): map RSDWBuilds_Stonewall_v1 -> vanilla foundation for save hydration.
    local vanilla = resolve_vanilla_foundation_da()
    if is_valid(vanilla) then
        rawset(_G, K.HYDRATION_STUB_KEY, true)
        clear_piece_requirements(vanilla)
        return vanilla, "hydration_stub"
    end
    return nil, "could not load " .. K.DA_PATH .. " (pak missing) and vanilla foundation unavailable"
end

local function load_da()
    warn_if_rsdwtools_loaded()
    preload_mod_assets()

    local registered = find_registered_da()
    if registered then
        ensure_persist_id(registered)
        clear_piece_requirements(registered)
        catalogue.prepare_da_for_native_build(registered, true)
        return registered, nil
    end

    local da = load_object(K.DA_PATH)
    if not da then return nil, "could not load " .. K.DA_PATH .. " (is mod pak mounted?)" end
    ensure_persist_id(da)
    clear_piece_requirements(da)
    catalogue.prepare_da_for_native_build(da, true)
    return da, nil
end

local function is_persistence_registered(sub)
    return find_registered_da(sub) ~= nil
end

local function ensure_boot_register(reason, persistence_only)
    local sub = subsystem.find()
    if not sub then
        return false, "BuildingPieceSubsystem not ready"
    end

    if is_persistence_registered(sub) then
        rawset(_G, K.BOOT_OK_KEY, true)
        if not persistence_only then
            local map = current_map_name()
            if not is_non_playable_map(map) or is_playable_world_map(map) then
                local da = find_registered_da(sub)
                if da then pcall(function() register_da_index_maps(sub, da) end) end
            end
        end
        return true, "persistence map already had " .. K.PERSIST_ID
    end

    if rawget(_G, K.BOOT_OK_KEY) then
        rawset(_G, K.BOOT_OK_KEY, false)
    end

    local da, err = load_da_for_boot()
    if not da then
        if reason == "LoadPlayerState" or reason == "LoadMapPre" or reason == "InitGameState" then
            print(string.format("%s boot register: BLOCKED (%s) %s", K.TAG, tostring(reason), tostring(err)))
        elseif reason == "poll" then
            if not rawget(_G, K.BOOT_FAIL_LOGGED_KEY) then
                rawset(_G, K.BOOT_FAIL_LOGGED_KEY, true)
                print(string.format("%s boot register: waiting (%s) %s", K.TAG, tostring(reason), tostring(err)))
            end
        elseif reason then
            print(string.format("%s boot register: waiting (%s) %s", K.TAG, tostring(reason), tostring(err)))
        end
        return false, err
    end
    rawset(_G, K.BOOT_FAIL_LOGGED_KEY, nil)

    local ok, detail
    ok, detail = register_da_persistence(sub, da)
    if ok then
        local first_ok = rawget(_G, K.BOOT_OK_KEY) ~= true
        rawset(_G, K.BOOT_OK_KEY, true)
        if err == "hydration_stub" and not rawget(_G, "RSDWBUILDS_HYDRATION_STUB_LOGGED") then
            rawset(_G, "RSDWBUILDS_HYDRATION_STUB_LOGGED", true)
            print(K.TAG .. " boot: pak DA missing -- registered " .. K.PERSIST_ID
                .. " via vanilla foundation (Continue/load should work; rebuild pak for real piece)")
        end
        try_cache_mod_mesh_from_mount()
        local mesh = cached_mod_mesh
        if is_valid(mesh) and mesh.GetFullName then
            print(string.format("%s boot: SM_Stonewall OK (%s)", K.TAG, mesh:GetFullName()))
        elseif err ~= "hydration_stub" then
            print(K.TAG .. " warn: SM_Stonewall not loaded at boot (will retry on build/diag)")
        end
        if first_ok or reason == "menu_place" or reason == "LoadMapPre" or reason == "LoadPlayerState"
            or reason == "ClientRestart" then
            print(string.format("%s boot register: OK (%s) %s", K.TAG, tostring(reason or "?"), detail))
        end
        if not persistence_only then
            local map = current_map_name()
            if not is_non_playable_map(map) or is_playable_world_map(map) then
                pcall(function() register_da_index_maps(sub, da) end)
            else
                detail = detail .. " (index repair deferred until L_World)"
            end
        end
    elseif reason then
        print(string.format("%s boot register: waiting (%s) %s", K.TAG, tostring(reason), tostring(detail)))
    end
    return ok, detail
end

-- Diagnostic only (v3.0.0): count hydrated mod pieces (idx 651 / DA_Stonewall).
-- Visuals come natively from the cooked BP_Stonewall -- no runtime fixes needed.
function M.scan_restored_pieces(tag)
    local found, custom = 0, 0
    local da = find_registered_da()
    local mesh = resolve_mod_mesh(true)
    pcall(function()
        if not FindAllOf then return end
        local list = FindAllOf("BaseBuildingActor")
        if type(list) ~= "table" then return end
        for _, a in pairs(list) do
            if is_valid(a) then
                local idx, pd, preview
                pcall(function() idx = a.BuildingPieceDataIndex end)
                pcall(function() pd = a.BuildingPieceData end)
                pcall(function() preview = a.bIsPreview end)
                local ours = (type(idx) == "number" and idx == K.CATALOGUE_INDEX)
                    or (is_valid(pd) and da and uobject_same(pd, da))
                if ours and preview ~= true then
                    found = found + 1
                    if mesh and actor_has_mod_mesh(a, mesh) then
                        custom = custom + 1
                    end
                end
            end
        end
    end)
    print(string.format("%s restored-piece scan (%s): found=%d with-custom-mesh=%d",
        K.TAG, tostring(tag), found, custom))
    return found
end

function M.schedule_boot_register()
    -- Intentionally empty in safe mode (registration happens on F7/build only).
end

local function allocate_deferred_index_impl(sub, da)
    if not sub or not da then return nil end
    local idx_map = sub.BuildingPieceDataIndexToBuildingPieceData
    if not idx_map then return nil end
    local cat = catalogue.find_build_piece_catalogue()

    local cached = get_shared_deferred_index()
    if cached ~= nil then
        if catalogue.deferred_map_slot_usable(sub, cat, cached, da) then
            local at = tmap_find(idx_map, cached)
            if at == nil then tmap_add(idx_map, cached, da) end
            bump_num_building_piece_datas(sub, cached)
            clear_da_index(da)
            return cached
        end
        set_shared_deferred_index(nil)
        print(string.format(
            "%s deferred: cached slot=%d conflicts with catalogue; reassigning",
            K.TAG, cached
        ))
    end

    local start = sub.NumBuildingPieceDatas
    if type(start) ~= "number" or start < 0 then start = 0 end
    if is_valid(cat) and cat.GetNumPieces then
        local cat_n = 0
        pcall(function() cat_n = cat:GetNumPieces() end)
        if type(cat_n) == "number" and cat_n > start then start = cat_n end
    end

    local idx = start
    while not catalogue.deferred_map_slot_usable(sub, cat, idx, da) do
        idx = idx + 1
        if idx > start + 256 then return nil end
    end

    if not tmap_add(idx_map, idx, da) then return nil end
    bump_num_building_piece_datas(sub, idx)
    clear_da_index(da)
    set_shared_deferred_index(idx)
    print(string.format("%s deferred map slot=%d (DA index stays -1)", K.TAG, idx))
    return idx
end
allocate_deferred_index = allocate_deferred_index_impl

-- One-shot place: DA_Stonewall via TrySpawnPieceAtLocation (no OnPieceSelected mod DA).
local function spawn_mod_foundation_at(bmc, sub, da, loc, rot)
    return finish_deferred_tryspawn_at(bmc, sub, da, loc, rot)
end

-- One-shot place via catalogue index (Server_SpawnBuilding -- no OnPieceSelected).
local function finish_catalogue_place_at(bmc, sub, da, loc, rot, idx)
    if not is_valid(bmc) or not da or not loc or type(idx) ~= "number" then
        return false, "missing bmc/da/loc/idx"
    end
    sub = sub or subsystem.find()
    enable_build_cheats()
    clear_piece_requirements(da)
    spawn_diagnostics(bmc, da, idx, "catalogue")
    local sok, serr = catalogue.spawn_via_server_building(bmc, idx, loc, rot)
    leave_build_mode_safe(bmc)
    clear_deferred_build_session()
    if not sok then
        return false, serr .. " index=" .. tostring(idx)
            .. " at (" .. string.format("%.0f, %.0f, %.0f", loc.X, loc.Y, loc.Z) .. ")"
    end
    schedule_post_spawn_stability(loc, da)
    schedule_post_spawn_mesh_patch(loc, da)
    local placed = find_spawned_piece_near(loc, da, 900)
        or find_nearest_building_actor_near(loc, 900)
    if is_valid(placed) then
        finalize_placed_building_actor(placed, da)
        print(string.format("%s finalized placed building piece", K.TAG))
    end
    print(string.format(
        "%s spawned Server_SpawnBuilding index=%d at (%.0f, %.0f, %.0f)%s",
        K.TAG, idx, loc.X, loc.Y, loc.Z,
        is_valid(placed) and " actor_ok" or " NO_ACTOR"
    ))
    if not is_valid(placed) then
        return false, "Server_SpawnBuilding reported ok but no actor found near spawn point"
    end
    return true, string.format("spawned (Server_SpawnBuilding index=%d)", idx)
end

-- Place at the live build preview via direct spawn (never native confirm -- that always places vanilla idx 526).
local function place_deferred_preview_native(bmc, sub, da)
    if not is_valid(bmc) or not da then return false, "missing bmc/da" end
    local loc, rot = get_preview_placement_transform(bmc)
    if not loc then return false, "no build preview (press G first)" end

    capture_deferred_preview_loc(bmc)
    capture_deferred_piece_snapshot()

    print(string.format(
        "%s place: direct spawn at preview (%.0f, %.0f, %.0f)",
        K.TAG, loc.X, loc.Y, loc.Z
    ))

    -- Keep build mode active for TrySpawn; finalize_spawn exits after a successful place.
    rawset(_G, K.NATIVE_CONFIRM_PENDING, true)

    local ok, detail = finish_deferred_tryspawn_at(bmc, sub, da, loc, rot)
    if ok then
        M.cancel_aim_place()
    end
    return ok, detail
end

-- One-shot TrySpawn + mesh patch (no build-mode session, no poll loops).
finish_deferred_tryspawn_at = function(bmc, sub, da, loc, rot)
    if not is_valid(bmc) or not da or not loc then
        return false, "missing bmc/da/loc"
    end
    sub = sub or subsystem.find()
    ensure_piece_unlocked(da, true)
    clear_piece_requirements(da)
    ensure_da_stability_profile(da, true)

    -- Pak clone catalogue: resolve_spawn_index registers slot 651 on the subsystem index map too.
    local cat_idx, source = catalogue.resolve_spawn_index(sub, da)
    if source == "catalogue" and cat_idx ~= nil then
        return finish_catalogue_place_at(bmc, sub, da, loc, rot, cat_idx)
    end

    local cat = catalogue.find_build_piece_catalogue()

    -- find_index-only catalogue entries and deferred map slots are NOT catalogue-backed.
    local idx = get_shared_deferred_index()
    if idx == nil and sub then
        idx = allocate_deferred_index(sub, da)
    end
    idx = idx or -1

    enable_build_cheats()
    clear_piece_requirements(da)

    local function finalize_spawn(source_label)
        leave_build_mode_safe(bmc)
        clear_deferred_build_session()
        schedule_post_spawn_stability(loc, da, true)
        local vanilla = resolve_vanilla_foundation_da(false)
        local placed = find_placed_actor_after_spawn(loc, da, vanilla, 900)
        if is_valid(placed) and finalize_placed_building_actor(placed, da) then
            print(string.format("%s finalized placed building piece -> DA_Stonewall", K.TAG))
        end
        print(string.format(
            "%s spawned %s map_slot=%d at (%.0f, %.0f, %.0f)%s",
            K.TAG, source_label, idx, loc.X, loc.Y, loc.Z,
            is_valid(placed) and " actor_ok" or " NO_ACTOR"
        ))
        if not is_valid(placed) then
            return false, source_label .. " reported ok but no actor found near spawn point"
        end
        return true, string.format("spawned foundation at (%.0f, %.0f, %.0f)", loc.X, loc.Y, loc.Z)
    end

    if type(idx) == "number" and idx >= 0 and is_valid(cat)
        and catalogue.index_is_catalogue_backed(cat, da, idx) then
        spawn_diagnostics(bmc, da, idx, "deferred_server")
        local sok, serr = catalogue.spawn_via_server_building(bmc, idx, loc, rot)
        if sok then
            return finalize_spawn("Server_SpawnBuilding")
        end
        print(string.format(
            "%s Server_SpawnBuilding(%d) failed: %s -- TrySpawn fallback",
            K.TAG, idx, tostring(serr)
        ))
    elseif type(idx) == "number" and idx >= 0 then
        print(string.format(
            "%s skip Server_SpawnBuilding(%d): not catalogue-backed (slot651=nil) -- TrySpawn",
            K.TAG, idx
        ))
    end

    local tok, tlabel, _used_da = try_spawn_deferred_at(bmc, sub, da, loc, rot)
    if not tok then
        return false, "placement failed: " .. spawn_failure_hint(tlabel)
            .. " at (" .. string.format("%.0f, %.0f, %.0f", loc.X, loc.Y, loc.Z) .. ")"
    end

    return finalize_spawn("TrySpawn=" .. tostring(tlabel))
end

local function resolve_da()
    local da, err = load_da()
    if not da then return nil, err end
    ensure_visuals(da)
    return da, nil
end

local function aim_place_e_key()
    if Key and Key.E then return Key.E end
    if not FName then return nil end
    local ok, fn = pcall(function() return FName("E") end)
    if ok and fn then return { KeyName = fn } end
    return nil
end

local function try_begin_place_guard()
    if rawget(_G, K.PLACE_GUARD_KEY) == true then return false end
    rawset(_G, K.PLACE_GUARD_KEY, true)
    if LoopAsync then
        LoopAsync(400, function()
            rawset(_G, K.PLACE_GUARD_KEY, nil)
            return true
        end)
    end
    return true
end

local function run_aim_place_from_input(label)
    if not try_begin_place_guard() then return end
    print(K.TAG .. " aim-place: " .. tostring(label or "E"))
    local ok, detail = M.place_at_aim()
    if ok then
        M.show_status("Placed DA_Stonewall", 6)
        print(K.TAG .. " " .. tostring(detail))
    else
        M.show_status("Place failed: " .. tostring(detail), 8)
        print(K.TAG .. " place failed: " .. tostring(detail))
    end
end

local function ensure_aim_place_keybind()
    if rawget(_G, K.AIM_E_KEY_REGISTERED) or not RegisterKeyBind then return end
    local function on_place_input(label)
        if rawget(_G, K.AIM_PLACE_ACTIVE) ~= true then return end
        local run = function() run_aim_place_from_input(label) end
        if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
    end
    local e_key = aim_place_e_key()
    if e_key then
        RegisterKeyBind(e_key, function() on_place_input("E keybind") end)
    end
    rawset(_G, K.AIM_E_KEY_REGISTERED, true)
end

local function stop_aim_place_poll()
    rawset(_G, K.AIM_POLL_ACTIVE, false)
    rawset(_G, K.AIM_E_WAS_DOWN, false)
end

-- Poll E during build mode -- RegisterKeyBind is often swallowed by native Enhanced Input.
local function start_aim_place_poll()
    if rawget(_G, K.AIM_POLL_ACTIVE) or not LoopAsync then return end
    rawset(_G, K.AIM_POLL_ACTIVE, true)
    rawset(_G, K.AIM_E_WAS_DOWN, false)
    local ignore_until = (os.clock() or 0) + 0.35
    local e_key = aim_place_e_key()
    LoopAsync(50, function()
        if rawget(_G, K.AIM_PLACE_ACTIVE) ~= true then
            stop_aim_place_poll()
            return true
        end
        if not e_key then return false end
        local pc = get_local_player_controller()
        if not is_valid(pc) or not pc.IsInputKeyDown then return false end
        local down = false
        pcall(function() down = pc:IsInputKeyDown(e_key) end)
        local was = rawget(_G, K.AIM_E_WAS_DOWN) == true
        rawset(_G, K.AIM_E_WAS_DOWN, down)
        if down and not was and (os.clock() or 0) >= ignore_until then
            local run = function() run_aim_place_from_input("E poll") end
            if ExecuteInGameThread then ExecuteInGameThread(run) else run() end
        end
        return false
    end)
end

function M.cancel_aim_place()
    rawset(_G, K.AIM_PLACE_ACTIVE, false)
    stop_aim_place_poll()
    leave_build_mode_safe(select(2, get_pc_and_bmc()))
    restore_vanilla_proxy_mesh()
end

local function begin_aim_place_mode()
    rawset(_G, K.AIM_PLACE_ACTIVE, true)
    ensure_aim_place_keybind()
    start_aim_place_poll()
    print(K.TAG .. " aim-place: E direct-spawns DA_Stonewall at preview (console: stonewall_place)")
end

function M.place_at_aim()
    local ok_world, wreason = require_playable_world()
    if not ok_world then return false, wreason end
    local blocked = mod_pak_blocked_reason()
    if blocked then return false, blocked end
    local da = resolve_mod_da()
    if not da then return false, "DA_Stonewall not registered" end
    if not preload_mod_mesh() then
        return false, "SM_Stonewall not loaded (stonewall_diag)"
    end
    local _pc, bmc, berr = get_pc_and_bmc()
    if not bmc then return false, berr end
    local sub = subsystem.find()
    register_da(da, sub)
    ensure_piece_unlocked(da, true)
    clear_piece_requirements(da)
    enable_build_cheats()
    catalogue.prepare_da_for_build(sub, da)

    if rawget(_G, K.DEFERRED_BUILD_ACTIVE) == true then
        local ok, detail = place_deferred_preview_native(bmc, sub, da)
        if ok then return ok, detail end
        print(K.TAG .. " preview place failed: " .. tostring(detail) .. " -- TrySpawn fallback")
    end

    local loc, yaw = placement.pawn_front_location()
    if not loc then return false, "could not get placement location" end
    local rot = { Pitch = 0, Yaw = yaw or 0, Roll = 0 }
    loc, rot = placement.ensure_forward_placement(loc, rot)
    print(string.format(
        "%s place: TrySpawn fallback at (%.0f, %.0f, %.0f)",
        K.TAG, loc.X, loc.Y, loc.Z
    ))
    return finish_deferred_tryspawn_at(bmc, sub, da, loc, rot)
end

function M.diagnose()
    print(K.TAG .. " diag: running...")
    try_upgrade_from_hydration_stub("diagnose")
    local playable, preason = require_playable_world()
    local pawn = get_local_pawn()
    local map = current_map_name()
    print(string.format(
        "%s diag world: map=%s playable=%s pawn=%s",
        K.TAG, map, tostring(playable), is_valid(pawn) and "OK" or "MISSING"
    ))

    local lines = {}
    local mesh_ok = false
    pcall(function()
        local mesh = preload_mod_mesh()
        mesh_ok = is_valid(mesh)
        if mesh_ok then
            lines[#lines + 1] = "mesh=OK"
            if mesh.GetFullName then
                lines[#lines + 1] = "meshName=" .. mesh:GetFullName()
            end
        else
            lines[#lines + 1] = "mesh=MISSING " .. K.MESH_PATH
            lines[#lines + 1] = "pakHint=if LoadAsset says 'Asset loaded' but mesh still MISSING, repack with UnrealReZen (retoc to-zen breaks SM ScriptObjects); run tools\\Build-And-Pack-DA-SM.ps1"
        end
    end)

    lines[#lines + 1] = "pak=" .. (mod_pak_ready() and "OK" or "BLOCKED")
    if not mod_pak_ready() then
        lines[#lines + 1] = "pakReason=" .. (mod_pak_blocked_reason() or "?")
    end
    lines[#lines + 1] = "hydrationStub=" .. tostring(rawget(_G, K.HYDRATION_STUB_KEY) == true)
    lines[#lines + 1] = "modDaMounted=" .. (is_valid(find_mod_da_mounted()) and "OK" or "MISSING")

    if not playable then
        local detail = table.concat(lines, " | ")
        if detail ~= "" then
            print(K.TAG .. " diag: " .. detail)
        end
        return mesh_ok, preason or "not in playable world"
    end

    local da = nil
    pcall(function()
        da = find_registered_da() or select(1, load_da_for_boot())
        lines[#lines + 1] = "da=" .. (da and "OK" or "MISSING")
    end)

    if da then
        lines[#lines + 1] = "modProxy=" .. describe_da_proxy_mesh(da)
        pcall(function()
            local vanilla = resolve_vanilla_foundation_da()
            if is_valid(vanilla) then
                lines[#lines + 1] = "vanillaProxy=" .. describe_da_proxy_mesh(vanilla)
            end
        end)
        pcall(function()
            local _pc, bmc = get_pc_and_bmc()
            if is_valid(bmc) then
                local preview = weak_get(bmc.PreviewPiece)
                lines[#lines + 1] = describe_actor_mesh(preview)
                if rawget(_G, K.DEFERRED_BUILD_ACTIVE) == true then
                    lines[#lines + 1] = "deferredBuild=active"
                end
            end
        end)

        pcall(function()
            local req_count = "unknown"
            pcall(function()
                local req = da.Requirements
                if req and req.Num then
                    req_count = tostring(req:Num())
                elseif req == nil then
                    req_count = "0"
                else
                    req_count = "0"
                end
            end)
            lines[#lines + 1] = "requirements=" .. req_count .. " (free build)"
        end)

        pcall(function()
            local stab = describe_stability_row_handle(da)
            local native_ok = false
            pcall(function() native_ok = stability_row_native_resolves(da) end)
            lines[#lines + 1] = "stability=" .. stab .. " native=" .. (native_ok and "ok" or "fail")
        end)

        pcall(function()
            local da_idx = "?"
            pcall(function() da_idx = tostring(da.BuildingPieceDataIndex) end)
            lines[#lines + 1] = "daIndex=" .. da_idx
        end)

        pcall(function()
            local cat, creason = catalogue.sync_catalogue_for_world(da)
            local spawn_ok = catalogue.catalogue_pak_active(cat, da)
            local preview_ok = catalogue.catalogue_native_preview_ready(cat, da)
            if spawn_ok then
                lines[#lines + 1] = string.format(
                    "catalogue=OK index=%d reason=%s preview=%s",
                    K.CATALOGUE_INDEX, tostring(creason), preview_ok and "OK" or "MISSING"
                )
            else
                local arr_len = cat and cat.BuildingPieceArray and tarray_len(cat.BuildingPieceArray) or 0
                local slot = cat and catalogue.catalogue_slot_path_at(cat, K.CATALOGUE_INDEX) or nil
                local persist = cat and catalogue.catalogue_persistence_id_at(cat, K.CATALOGUE_INDEX) or nil
                lines[#lines + 1] = string.format(
                    "catalogue=MISSING arr=%d slot651=%s persist651=%s (run stonewall_catalogue; full restart after redeploy)",
                    arr_len, tostring(slot), tostring(persist)
                )
            end
        end)

        pcall(function()
            local sub = subsystem.find()
            local _idx, source = catalogue.resolve_spawn_index(sub, da)
            local cat_idx = rawget(_G, K.CATALOGUE_INDEX_KEY)
            local def_idx = get_shared_deferred_index()
            local persist_ok = sub and is_persistence_registered(sub)
            local sidx = cat_idx or def_idx
            local ssource = source or (cat_idx and "catalogue" or (def_idx and "deferred" or "unassigned"))
            lines[#lines + 1] = string.format(
                "persist=%s spawn_index=%s source=%s",
                persist_ok and "OK" or "no", tostring(sidx or "?"), ssource
            )
        end)
    end

    local detail = table.concat(lines, " | ")
    print(K.TAG .. " diag: " .. detail)
    return mesh_ok and da ~= nil, detail
end

function M.is_catalogue_active()
    local da = find_registered_da()
    if not da then
        da = select(1, load_da())
    end
    if not da then return false end
    catalogue.force_reload_catalogue_assets()
    local cat, _reason = catalogue.resolve_live_catalogue(da)
    return catalogue.catalogue_pak_active(cat, da)
end

function M.build()
    local ok_world, wreason = require_playable_world()
    if not ok_world then return false, wreason end

    local blocked = mod_pak_blocked_reason()
    if blocked then
        M.show_status("[RSDWBuilds] Build blocked -- mod pak not loaded.", 10)
        print(K.TAG .. " build: blocked -- " .. blocked)
        return false, blocked
    end

    print(K.TAG .. " build: begin")

    pcall(function() ensure_boot_register("build", false) end)

    local da = resolve_mod_da()
    if not da then return false, "DA_Stonewall not registered (boot failed?)" end

    if not preload_mod_mesh() then
        print(K.TAG .. " build: SM_Stonewall not loaded -- check RSDWBuilds pak (stonewall_diag)")
        return false, "SM_Stonewall not loaded"
    end

    local _pc, bmc, berr = get_pc_and_bmc()
    if not bmc then return false, berr end

    clear_piece_requirements(da)
    ensure_piece_unlocked(da, true)
    enable_build_cheats()

    local sub = subsystem.find()
    register_da(da, sub)
    catalogue.prepare_da_for_build(sub, da)
    local cat, _creason = catalogue.sync_catalogue_for_world(da)
    local chunk651 = catalogue.catalogue_chunk651_mounted(cat, da)
    local preview_ok = chunk651 and catalogue.catalogue_native_preview_ready(cat, da)

    if preview_ok then
        M.cancel_aim_place()
        -- Fully native path (v3.0.0): the pak DA's BuildableActor points at the cooked
        -- BP_Stonewall clone (custom mesh baked in), so preview, placement and
        -- save/load are handled by the game with zero runtime patching. No sessions,
        -- no watches, no mesh patch loops.
        clear_deferred_build_session()
        print(K.TAG .. " build: native651 step1 ForceEnterBuildMode")
        if bmc.ForceEnterBuildMode then
            pcall(function() bmc:ForceEnterBuildMode() end)
        end
        if not bmc.OnPieceSelected then
            return false, "OnPieceSelected missing on BuildModeComponent"
        end
        print(K.TAG .. " build: native651 step2 OnPieceSelected(DA_Stonewall)")
        local ok, serr = pcall(function() bmc:OnPieceSelected(da) end)
        print(K.TAG .. " build: native651 step3 OnPieceSelected returned ok=" .. tostring(ok))
        if not ok then
            return false, "OnPieceSelected(DA_Stonewall) failed: " .. tostring(serr)
        end
        local preview = is_valid(bmc) and weak_get(bmc.PreviewPiece) or nil
        print(string.format("%s build mode active (%s)", K.TAG, describe_actor_mesh(preview)))
        return true, "build mode active -- native catalogue piece 651, place with normal build controls"
    end

    -- Foundation donor path (works without pakchunk651/652 -- borrows vanilla floor for preview, E spawns Stonewall).
    M.cancel_aim_place()
    force_clear_mod_da_index(da)
    if sub then
        pcall(function() allocate_deferred_index(sub, da) end)
    end
    print(K.TAG .. " build: foundation donor preview + E (no catalogue pak required)")
    set_deferred_build_session(true)
    rawset(_G, K.EXPECTED_IDX_KEY, nil)
    local d_ok, d_err = begin_deferred_build_mode(bmc, da, "foundation donor")
    if d_ok then
        print(K.TAG .. " build: preview active -- vanilla floor selected, stonewall mesh swapped")
    else
        print(K.TAG .. " build: preview failed: " .. tostring(d_err))
        clear_deferred_build_session()
    end
    begin_aim_place_mode()
    M.show_status("Aim preview and press E to place Stonewall", 10)
    return true, d_ok and "donor preview -- press E" or tostring(d_err)
end

function M.resync_catalogue()
    local da = resolve_mod_da() or find_registered_da()
    if not da then return false, "DA_Stonewall not registered" end
    local cat, reason = catalogue.sync_catalogue_for_world(da)
    local ok = catalogue.catalogue_pak_active(cat, da)
    local slot = cat and catalogue.catalogue_slot_path_at(cat, K.CATALOGUE_INDEX) or nil
    local persist = cat and catalogue.catalogue_persistence_id_at(cat, K.CATALOGUE_INDEX) or nil
    local detail = string.format(
        "catalogue=%s index=%d slot651=%s persist651=%s reason=%s",
        ok and "OK" or "MISSING", K.CATALOGUE_INDEX, tostring(slot), tostring(persist), tostring(reason)
    )
    print(K.TAG .. " " .. detail)
    if ok and da then
        local sub = subsystem.find()
        if sub then register_da_index_maps(sub, da) end
    end
    return ok, detail
end

function M.spawn()
    print(K.TAG .. " spawn: begin")
    local ok_world, wreason = require_playable_world()
    if not ok_world then return false, wreason end
    local blocked = mod_pak_blocked_reason()
    if blocked then
        print(K.TAG .. " spawn: blocked -- " .. blocked)
        return false, blocked
    end
    preload_mod_assets()
    if not resolve_mod_mesh() then
        return false, "SM_Stonewall not loaded (is mod pak mounted? run stonewall_diag)"
    end
    local da, derr = resolve_da()
    if not da then return false, derr end

    local sub = subsystem.find()
    local rok, rdetail = register_da(da, sub)
    if not rok then return false, rdetail end
    ensure_piece_unlocked(da)
    clear_piece_requirements(da)
    catalogue.prepare_da_for_native_build(da, true)
    local idx, source = catalogue.resolve_spawn_index(sub, da)
    if idx == nil then return false, "no spawn index (catalogue or deferred registration failed)" end
    if source ~= "catalogue" then
        clear_da_index(da)
        da = sync_spawn_da(sub, da, idx)
    end

    enable_build_cheats()

    local _pc, bmc, berr = get_pc_and_bmc()
    if not bmc then return false, berr end

    local loc, yaw = placement.pawn_front_location()
    if not loc then return false, "could not get spawn location" end
    local rot = { Pitch = 0, Yaw = yaw or 0, Roll = 0 }
    loc, rot = placement.ensure_forward_placement(loc, rot)

    if source == "catalogue" then
        return finish_catalogue_place_at(bmc, sub, da, loc, rot, idx)
    end

    -- No catalogue pak: TrySpawn with DA_Stonewall (subsystem map slot, not vanilla piece).
    return spawn_mod_foundation_at(bmc, sub, da, loc, rot)
end

function M.menu_place()
    local blocked = mod_pak_blocked_reason()
    if blocked then
        M.show_status("[RSDWBuilds] G blocked -- mod pak not loaded (see stonewall_diag).", 10)
        print(K.TAG .. " menu place: blocked -- " .. blocked)
        return false, blocked
    end
    print(K.TAG .. " menu place: build from menu")
    return M.build()
end

function M.build_from_menu()
    return M.menu_place()
end

function M.place_from_menu()
    return M.spawn()
end

function M.install_piece_hooks()
    -- No TrySpawn RegisterHook (hard-crash). Deferred donor uses proxy swap + click/E watches.
    rawset(_G, "RSDWBUILDS_PIECE_HOOKS_VERSION", "3.0.3")
    clear_deferred_build_session()
    rawset(_G, K.PIECE_HOOKS_KEY, true)
    print(K.TAG .. " deferred donor mode -- no TrySpawn hook; F7 G build E/LMB place")
end

function M.is_playable_world()
    return require_playable_world()
end

function M.world_status()
    local playable, detail = require_playable_world()
    return playable, detail, current_map_name(), is_valid(get_local_pawn())
end

-- aim-place keybind registers on first build (not at require time)

return M


