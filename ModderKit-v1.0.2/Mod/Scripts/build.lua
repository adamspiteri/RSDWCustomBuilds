-- Manifest-driven build mode — native pak path only (no runtime mesh patching).

local M = {}



local TAG = "[RSDWBuilds]"

local registry = require("registry")

local assets = require("assets")

local preview = require("preview")

local placement = require("placement")

local catalogue = require("catalogue")



local VANILLA_CATALOGUE_OBJ = "/Game/Gameplay/BaseBuilding_New/BuildingPieces/DA_BuildPieceCatalogue_Default.DA_BuildPieceCatalogue_Default"



local NON_PLAYABLE_MAPS = {

    l_frontend = true,

    frontend = true,

    untitled = true,

    mainmenu = true,

    l_mainmenu = true,

}



local function is_valid(obj)

    return assets.is_valid(obj)

end



local function load_object(path)

    return assets.load(path)

end



local function read_manifest()

    local ok, data = pcall(require, "pieces_data")

    if ok and type(data) == "table" then return data end

    return nil

end



local function get_piece(id)

    local m = read_manifest()

    if not m or type(m.pieces) ~= "table" then return nil end

    for _, entry in ipairs(m.pieces) do

        if entry.id == id then return entry end

    end

    return m.pieces[1]

end



local function current_map_name()

    local name = "?"

    pcall(function()

        local ok_ue, ue = pcall(require, "UEHelpers")

        if ok_ue and ue and ue.GetWorld then

            local w = ue:GetWorld()

            if is_valid(w) and w.GetName then name = w:GetName() or name end

        end

    end)

    return name

end



function M.is_playable_world()

    local map = (current_map_name() or "?"):lower()

    if NON_PLAYABLE_MAPS[map] then

        return false, "load into your world first (not " .. map .. ")"

    end

    return true, map

end



local function get_pc()

    local ok_ue, ue = pcall(require, "UEHelpers")

    if ok_ue and ue and ue.GetPlayerController then

        local ok, pc = pcall(function() return ue:GetPlayerController() end)

        if ok and is_valid(pc) then return pc end

    end

    if FindAllOf then

        local ok, list = pcall(FindAllOf, "PlayerController")

        if ok and list then

            for _, pc in pairs(list) do

                if is_valid(pc) then return pc end

            end

        end

    end

    return nil

end



local function get_bmc()

    local pc = get_pc()

    if not is_valid(pc) then return nil, nil, "PlayerController not ready" end

    local bmc = nil

    pcall(function() bmc = pc.BuildModeComponent end)

    if not is_valid(bmc) then return pc, nil, "BuildModeComponent not ready" end

    return pc, bmc, nil

end



local function weak_get(wptr)
    if not wptr then return nil end
    if type(wptr) == "userdata" and is_valid(wptr) then return wptr end
    local ok, v = pcall(function() return wptr:Get() end)
    if ok and is_valid(v) then return v end
    return nil
end



local function object_key(obj)
    if not is_valid(obj) then return nil end
    local fn
    pcall(function() fn = obj:GetFullName() end)
    if type(fn) == "string" and fn ~= "" then return fn end
    return tostring(obj)
end



local finalized_actors = {}

local function is_current_preview(actor, bmc)
    if not is_valid(actor) or not is_valid(bmc) then return false end
    local preview_actor
    pcall(function() preview_actor = weak_get(bmc.PreviewPiece) end)
    if not is_valid(preview_actor) then return false end
    return object_key(actor) == object_key(preview_actor)
end



local function iter_found(class_name, fn)
    if not FindAllOf or type(fn) ~= "function" then return 0 end
    local ok, list = pcall(FindAllOf, class_name)
    if not ok or not list then return 0 end
    local seen, count = {}, 0
    local function visit(v)
        if not is_valid(v) then return end
        local k = object_key(v) or tostring(v)
        if seen[k] then return end
        seen[k] = true
        count = count + 1
        fn(v)
    end
    if type(list) == "table" then
        for _, v in pairs(list) do visit(v) end
    end
    local n = 0
    pcall(function() n = #list end)
    if n == 0 then pcall(function() if list.Num then n = list:Num() end end) end
    for i = 1, tonumber(n or 0) do
        local v
        pcall(function() v = list[i] end)
        visit(v)
    end
    return count
end



local function bp_class_name(entry)
    local path = entry and entry.bp_path
    if type(path) == "string" and path ~= "" then
        return path:match("%.([%w_]+)$") or ("BP_" .. tostring(entry.id) .. "_C")
    end
    return "BP_" .. tostring(entry and entry.id or "Stonewall") .. "_C"
end



local function finalize_actor(actor, da)
    if not is_valid(actor) then return false end
    local changed = false
    if is_valid(da) then
        pcall(function() actor.BuildingPieceData = da changed = true end)
        pcall(function() actor.PersistenceID = da.PersistenceID end)
    end
    pcall(function() actor.bIsPreview = false changed = true end)
    pcall(function() actor.bIsGhosted = false changed = true end)
    pcall(function() actor.bHidden = false end)
    pcall(function() actor.StabilityValue = 1.0 end)
    pcall(function() if actor.SetActorHiddenInGame then actor:SetActorHiddenInGame(false) end end)
    pcall(function() if actor.SetActorEnableCollision then actor:SetActorEnableCollision(true) end end)
    pcall(function() if actor.K2_SetActorEnableCollision then actor:K2_SetActorEnableCollision(true) end end)
    return changed
end



local function finalize_placed_actors(entry, da, bmc)
    local class_name = bp_class_name(entry)
    local patched = 0
    iter_found(class_name, function(actor)
        if is_current_preview(actor, bmc) then return end
        local k = object_key(actor) or tostring(actor)
        if finalize_actor(actor, da) then
            if not finalized_actors[k] then
                finalized_actors[k] = true
                patched = patched + 1
            end
        end
    end)
    if patched > 0 then
        print(TAG .. " finalized placed actor(s): " .. tostring(patched))
    end
    return patched
end



local function schedule_placed_finalizer(entry, da, bmc)
    local function run_once()
        finalize_placed_actors(entry, da, bmc)
    end
    if not LoopAsync then
        run_once()
        return
    end
    local ticks = 0
    LoopAsync(200, function()
        ticks = ticks + 1
        if ExecuteInGameThread then ExecuteInGameThread(run_once) else run_once() end
        -- Keep the finalizer alive long enough for several placements, but it is not permanent.
        return ticks >= 150
    end)
end



local function clear_requirements(da)

    if not da then return end

    pcall(function()

        if da.Requirements and da.Requirements.Clear then

            da.Requirements:Clear()

        end

    end)

end



local function enable_build_cheats()
    if not FindFirstOf then return end
    local ok, sub = pcall(FindFirstOf, "BuildingSubsystem")
    if ok and is_valid(sub) then
        pcall(function() sub.bCheatAlwaysAllowBuilding = true end)
    end
end



local function leave_build_mode_safe(bmc)
    if not is_valid(bmc) then return false end
    pcall(function() bmc.CurrentBuildMode = 0 end)
    if bmc.ExitAnyMode then
        pcall(function() bmc:ExitAnyMode() end)
    end
    return true
end



function M.cancel_build()
    local _pc, bmc = get_bmc()
    placement.cancel()
    if leave_build_mode_safe(bmc) then
        print(TAG .. " build mode cancelled")
        return true, "build mode cancelled"
    end
    return false, "no BuildModeComponent"
end



function M.is_build_active()
    local _pc, bmc = get_bmc()
    if not is_valid(bmc) then return false end
    local mode
    pcall(function()
        if bmc.GetCurrentBuildMode then mode = bmc:GetCurrentBuildMode()
        else mode = bmc.CurrentBuildMode end
    end)
    if type(mode) == "number" and mode ~= 0 then return true end
    local preview_actor
    pcall(function()
        local p = bmc.PreviewPiece
        if p and p.Get then preview_actor = p:Get() else preview_actor = p end
    end)
    return is_valid(preview_actor)
end



local function infer_bp_path(entry)

    if entry and type(entry.bp_path) == "string" and entry.bp_path ~= "" then

        return entry.bp_path

    end

    if not entry or not entry.id then return nil end

    return string.format("/Game/RSDWBuilds/%s/BP_%s.BP_%s_C", entry.id, entry.id, entry.id)

end



local function native_bp_ready(entry)

    local bp_path = infer_bp_path(entry)

    if not bp_path then return false end

    if LoadAsset then

        local pkg = bp_path:match("^(.-)%.[^%.]+$") or bp_path

        pcall(function() LoadAsset(pkg) end)

    end

    return is_valid(load_object(bp_path))

end



local function load_vanilla_catalogue()

    if LoadAsset then

        pcall(function() LoadAsset("/Game/Gameplay/BaseBuilding_New/BuildingPieces/DA_BuildPieceCatalogue_Default") end)

    end

    return load_object(VANILLA_CATALOGUE_OBJ)

end



local function catalogue_slot_ready(cat, entry)

    if not is_valid(cat) or not entry then return false end

    local idx = tonumber(entry.catalogue_index) or 651

    if cat.BuildingPiecePersistenceIDSet and cat.BuildingPiecePersistenceIDSet.Find then

        local ok, v = pcall(function() return cat.BuildingPiecePersistenceIDSet:Find(idx) end)

        if ok and v and tostring(v):find(entry.persistence_id or "", 1, true) then

            return true

        end

    end

    if cat.FindIndexForPieceData then

        local da = load_object(entry.da_path)

        if is_valid(da) then

            local ok, found = pcall(function() return cat:FindIndexForPieceData(da) end)

            if ok and type(found) == "number" and found == idx then

                return true

            end

        end

    end

    return false

end



function M.list_pieces()

    local m = read_manifest()

    if not m or type(m.pieces) ~= "table" then return {} end

    return m.pieces

end



function M.piece_mounted(entry)

    if not entry or not entry.da_path then return false end

    return is_valid(load_object(entry.da_path))

end

function M.readiness(entry)
    if not entry then return false, "no piece selected" end
    if not M.piece_mounted(entry) then
        return false, "DA not in pak — run Tools\\Build-Piece.bat " .. (entry.id or "?")
    end
    if not native_bp_ready(entry) then
        return false, "BP_" .. entry.id .. " not in pak — rerun Tools\\Build-Piece.bat " .. entry.id
    end
    local cat = load_vanilla_catalogue()
    if not catalogue_slot_ready(cat, entry) then
        return false, "catalogue slot " .. tostring(entry.catalogue_index or 651)
            .. " not in pak — rerun Build-Piece.bat " .. entry.id
    end
    return true, "ready"
end

function M.start_build(piece_id)

    local ok_world, wreason = M.is_playable_world()

    if not ok_world then return false, wreason end



    local entry = get_piece(piece_id)

    if not entry then return false, "no piece in manifest" end



    registry.unlock_all()



    local da = load_object(entry.da_path)

    if not is_valid(da) then

        return false, "DA not mounted: " .. tostring(entry.da_path) .. " (rebuild pak)"

    end



    local mesh = entry.mesh_path and load_object(entry.mesh_path) or nil



    if not native_bp_ready(entry) then

        return false, "BP missing in pak — rerun Tools\\Build-Piece.bat " .. entry.id

    end



    local cat = load_vanilla_catalogue()

    if not catalogue_slot_ready(cat, entry) then

        return false, "catalogue slot "

            .. tostring(entry.catalogue_index or 651)

            .. " not ready — run Tools\\Build-Piece.bat "

            .. entry.id .. " (needs vanilla catalogue in pak)"

    end



    preview.prepare_da(da, entry, nil)



    local _pc, bmc, berr = get_bmc()

    if not bmc then return false, berr end



    clear_requirements(da)
    enable_build_cheats()



    if bmc.ForceEnterBuildMode then

        pcall(function() bmc:ForceEnterBuildMode() end)

    end



    if not bmc.OnPieceSelected then

        return false, "OnPieceSelected missing"

    end



    local ok, err = pcall(function() bmc:OnPieceSelected(da) end)

    if not ok then

        return false, "OnPieceSelected failed: " .. tostring(err)

    end



    -- Swap the live subsystem catalogue to our baked clone so Server_SpawnBuilding(idx) resolves
    -- against a real entry (never the vanilla slot, which hard-crashes on spawn).

    local cok, cidx, creason = catalogue.prepare(entry, da)

    print(TAG .. " catalogue prepare -> ok=" .. tostring(cok)
        .. " idx=" .. tostring(cidx) .. " (" .. tostring(creason) .. ")")



    -- Do not use the game's native confirm path here: it leaves placed pieces as construction
    -- ghosts and keeps the player in continuous build mode. Use the working mod's direct-spawn
    -- style instead: preview for aiming, E/click Server_SpawnBuilding once, then exit build mode.
    if cok then
        schedule_placed_finalizer(entry, da, bmc)
    end
    placement.begin(bmc, da, registry.notify, tonumber(entry.catalogue_index) or 651,
        mesh, { bp_class_name(entry) })

    local detail = "build mode: " .. (entry.display_name or entry.id)
        .. " — aim and press E or click to place once"

    print(TAG .. " " .. detail)

    return true, detail

end



function M.diag(piece_id)

    local entry = get_piece(piece_id)

    if not entry then

        local m = read_manifest()

        if m and m.pieces and m.pieces[1] then entry = m.pieces[1] end

    end

    if not entry then return false, "no manifest entry" end

    local da = load_object(entry.da_path)

    local mesh = entry.mesh_path and load_object(entry.mesh_path) or nil

    local cat = load_vanilla_catalogue()

    local lines = {

        "piece=" .. entry.id,

        "da=" .. (is_valid(da) and "OK" or ("MISSING " .. entry.da_path)),

        "mesh=" .. (is_valid(mesh) and "OK" or ("MISSING " .. tostring(entry.mesh_path))),

        "bp=" .. (native_bp_ready(entry) and "OK" or ("MISSING " .. tostring(infer_bp_path(entry)))),

        "catalogue651=" .. tostring(catalogue_slot_ready(cat, entry)),

    }

    local msg = table.concat(lines, " | ")

    print(TAG .. " diag: " .. msg)

    return is_valid(da) and native_bp_ready(entry) and catalogue_slot_ready(cat, entry), msg

end



-- Live test: gather everything, log it, then directly attempt the spawn (no pak rebuild, no E/click).
function M.test(piece_id)
    local entry = get_piece(piece_id)
    if not entry then return false, "no manifest entry" end

    registry.unlock_all()

    local da = load_object(entry.da_path)
    print(TAG .. " TEST: da_path=" .. tostring(entry.da_path)
        .. " valid=" .. tostring(is_valid(da)))

    local bp_path = infer_bp_path(entry)
    print(TAG .. " TEST: bp_path=" .. tostring(bp_path)
        .. " valid=" .. tostring(native_bp_ready(entry)))

    local cat = load_vanilla_catalogue()
    print(TAG .. " TEST: catalogue valid=" .. tostring(is_valid(cat)))
    if is_valid(cat) and cat.FindIndexForPieceData and is_valid(da) then
        local found = nil
        pcall(function() found = cat:FindIndexForPieceData(da) end)
        print(TAG .. " TEST: FindIndexForPieceData(da)=" .. tostring(found)
            .. " (expected " .. tostring(entry.catalogue_index or 651) .. ")")
    end

    if not is_valid(da) then return false, "DA not mounted" end

    local mesh = entry.mesh_path and load_object(entry.mesh_path) or nil
    print(TAG .. " TEST: mesh_path=" .. tostring(entry.mesh_path)
        .. " valid=" .. tostring(is_valid(mesh)))

    preview.prepare_da(da, entry, mesh)
    clear_requirements(da)
    print(TAG .. " TEST: BuildableActor now=" .. tostring(preview.buildable_label(da)))

    local _pc, bmc, berr = get_bmc()
    if not bmc then
        print(TAG .. " TEST: " .. tostring(berr))
        return false, berr
    end

    local cok, cidx, creason = catalogue.prepare(entry, da)
    print(TAG .. " TEST: catalogue prepare -> ok=" .. tostring(cok)
        .. " idx=" .. tostring(cidx) .. " (" .. tostring(creason) .. ")")

    local ok, label = placement.test_spawn(bmc, da, entry.id, tonumber(entry.catalogue_index) or 651)
    return ok, "test spawn: " .. tostring(label)
end



return M


