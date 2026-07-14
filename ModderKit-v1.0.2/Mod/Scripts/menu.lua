-- Custom build menu overlay (canvas-only UMG, same pattern as RSDWTools toast).

local building = require("building")

local game_thread = require("game_thread")



local M = {}



local TAG = "[RSDWBuilds]"

local ICON_PATH = "/Game/RSDWBuilds/Stonewall/T_Icon_Stonewall.T_Icon_Stonewall"

local POLL_MS = 50



local VIS_HIDDEN = 2

local VIS_HIT = 4



local root_widget = nil

local root_canvas = nil

local root_panel = nil

local click_border = nil

local icon_widget = nil

local hint_widget = nil

local menu_open = false

local poll_active = false

local mouse_was_down = false

local pending_click = false

local place_key_registered = false

local _fkey_cache = {}



local set_menu_visible



local function is_valid(obj)

    if type(obj) ~= "userdata" then return false end

    if not obj.IsValid then return false end

    local ok, v = pcall(function() return obj:IsValid() end)

    return ok and v == true

end



local function FLinearColor(r, g, b, a)

    return { R = r, G = g, B = b, A = a }

end



local function FSlateColor(r, g, b, a)

    return { SpecifiedColor = FLinearColor(r, g, b, a), ColorUseRule = 0 }

end



local function fkey(name)

    local cached = _fkey_cache[name]

    if cached then return cached end

    if not FName then return nil end

    local ok, fn = pcall(function() return FName(name) end)

    if not ok or not fn then return nil end

    local k = { KeyName = fn }

    _fkey_cache[name] = k

    return k

end



local function get_pc()

    local ok_req, ue = pcall(require, "UEHelpers")

    if ok_req and ue and ue.GetPlayerController then

        local ok_pc, pc = pcall(function() return ue.GetPlayerController() end)

        if ok_pc and is_valid(pc) then return pc end

    end

    if FindAllOf then

        local ok, list = pcall(FindAllOf, "PlayerController")

        if ok and list then

            for _, pc in pairs(list) do

                if is_valid(pc) then

                    local mine = false

                    pcall(function()

                        if pc.IsLocalPlayerController then mine = pc:IsLocalPlayerController() end

                    end)

                    if mine then return pc end

                end

            end

        end

    end

    return nil

end



local function load_icon()

    if LoadAsset then pcall(function() LoadAsset("/Game/RSDWBuilds/Stonewall/T_Icon_Stonewall") end) end

    if StaticFindObject then

        local ok, tex = pcall(StaticFindObject, ICON_PATH)

        if ok and is_valid(tex) then return tex end

    end

    return nil

end



local function refresh_icon()

    if not is_valid(icon_widget) then return end

    local tex = load_icon()

    if tex then

        pcall(function() icon_widget:SetBrushFromTexture(tex, true) end)

    end

end



local function set_widget_visibility(widget, show)

    if not is_valid(widget) or not widget.SetVisibility then return end

    pcall(function()

        widget:SetVisibility(show and VIS_HIT or VIS_HIDDEN)

    end)

end



local function refresh_menu_hint()

    if not is_valid(hint_widget) or not hint_widget.SetText then return end

    local blocked = building.pak_blocked_short()

    if blocked then

        pcall(function()

            hint_widget:SetText(FText("PAK NOT LOADED -- G disabled until repack"))

            hint_widget:SetColorAndOpacity(FSlateColor(1.0, 0.45, 0.35, 1.0))

        end)

    else

        pcall(function()

            hint_widget:SetText(FText("F7 close | G build | E or click place"))

            hint_widget:SetColorAndOpacity(FSlateColor(0.7, 0.7, 0.7, 1.0))

        end)

    end

end



local function on_foundation_chosen()

    if not menu_open then return end

    local blocked = building.pak_blocked_short()

    if blocked then

        building.show_status("[RSDWBuilds] " .. blocked, 10)

        refresh_menu_hint()

        return

    end

    set_menu_visible(false)

    game_thread.run(function()

        local ok, detail = building.build_from_menu()

        if ok then

            print(TAG .. " menu -> " .. tostring(detail))

        else

            building.show_status("[RSDWBuilds] Build failed: " .. tostring(detail), 8)

            print(TAG .. " menu build failed: " .. tostring(detail))

        end

    end)

end



local function register_place_keybind()

    if place_key_registered or not RegisterKeyBind then return end

    local g_key = Key and Key.G or fkey("G")

    if not g_key then return end

    RegisterKeyBind(g_key, function()

        if not menu_open then return end

        on_foundation_chosen()

    end)

    place_key_registered = true

end



local function click_triggered_on_game_thread()

    local pc = get_pc()

    if not pc then return false end

    if not is_valid(click_border) or not click_border.IsHovered then return false end

    local hovered = false

    pcall(function() hovered = click_border:IsHovered() end)

    if not hovered then return false end



    local lmb = fkey("LeftMouseButton")

    if not lmb or not pc.IsInputKeyDown then return false end

    local down = false

    pcall(function() down = pc:IsInputKeyDown(lmb) end)

    if down and not mouse_was_down then

        mouse_was_down = true

        return true

    end

    mouse_was_down = down

    return false

end



function M.start_click_poll()

    if poll_active or not LoopAsync then return end

    poll_active = true

    pending_click = false

    LoopAsync(POLL_MS, function()

        if not menu_open then

            mouse_was_down = false

            pending_click = false

            poll_active = false

            return true

        end

        if pending_click then

            pending_click = false

            on_foundation_chosen()

            poll_active = false

            return true

        end

        local check = function()

            if click_triggered_on_game_thread() then

                pending_click = true

            end

        end

        if ExecuteInGameThread then

            ExecuteInGameThread(check)

        else

            check()

        end

        return false

    end)

end



set_menu_visible = function(show)

    menu_open = show == true

    set_widget_visibility(root_canvas, menu_open)

    set_widget_visibility(root_panel, menu_open)

    if menu_open then

        mouse_was_down = false

        refresh_icon()

        refresh_menu_hint()

        register_place_keybind()

        M.start_click_poll()

    else

        mouse_was_down = false

        building.cancel_aim_place()

    end

end



function M.is_open()

    return menu_open

end



function M.toggle()

    local ok_world, detail = building.is_playable_world()

    if not ok_world then

        return false, detail or "load into your world first (not main menu)"

    end

    if not is_valid(root_canvas) then

        if not M.ensure_widget() then return false, "menu widget failed (see log above)" end

    end

    set_menu_visible(not menu_open)

    return true, menu_open and "menu open (F7 close; G build; E to place)" or "menu closed"

end



function M.close()

    set_menu_visible(false)

end



function M.ensure_widget()

    if is_valid(root_canvas) then return true end



    local ok_all, err = pcall(function()

        local UEHelpers

        do

            local ok, mod = pcall(require, "UEHelpers")

            if ok and type(mod) == "table" then UEHelpers = mod end

        end

        if not UEHelpers or not UEHelpers.GetGameInstance then

            error("UEHelpers.GetGameInstance unavailable")

        end



        local game_instance

        pcall(function() game_instance = UEHelpers.GetGameInstance() end)

        if not is_valid(game_instance) then

            error("GameInstance not ready")

        end



        local user_widget_cls = StaticFindObject and StaticFindObject("/Script/UMG.UserWidget") or nil

        local widget_tree_cls = StaticFindObject and StaticFindObject("/Script/UMG.WidgetTree") or nil

        local canvas_panel_cls = StaticFindObject and StaticFindObject("/Script/UMG.CanvasPanel") or nil

        local border_cls = StaticFindObject and StaticFindObject("/Script/UMG.Border") or nil

        local text_block_cls = StaticFindObject and StaticFindObject("/Script/UMG.TextBlock") or nil

        local image_cls = StaticFindObject and StaticFindObject("/Script/UMG.Image") or nil

        if not (user_widget_cls and widget_tree_cls and canvas_panel_cls and border_cls and text_block_cls and image_cls) then

            error("required UMG classes not found")

        end



        local hud = StaticConstructObject(user_widget_cls, game_instance, FName("RCBMenuHUD"))

        hud.WidgetTree = StaticConstructObject(widget_tree_cls, hud, FName("RCBMenuTree"))



        local canvas = StaticConstructObject(canvas_panel_cls, hud.WidgetTree, FName("RCBMenuCanvas"))

        hud.WidgetTree.RootWidget = canvas



        local panel = StaticConstructObject(border_cls, canvas, FName("RCBMenuPanel"))

        panel:SetBrushColor(FLinearColor(0.05, 0.06, 0.08, 0.92))

        panel:SetPadding({ Left = 16, Top = 14, Right = 16, Bottom = 14 })



        local panel_slot = canvas:AddChildToCanvas(panel)

        panel_slot:SetAnchors({ Minimum = { X = 1.0, Y = 1.0 }, Maximum = { X = 1.0, Y = 1.0 } })

        panel_slot:SetAlignment({ X = 1.0, Y = 1.0 })

        panel_slot:SetPosition({ X = -24, Y = -120 })

        panel_slot:SetAutoSize(true)



        local panel_canvas = StaticConstructObject(canvas_panel_cls, panel, FName("RCBMenuPanelCanvas"))

        panel:SetContent(panel_canvas)



        local title = StaticConstructObject(text_block_cls, panel_canvas, FName("RCBMenuTitle"))

        title:SetText(FText("Custom Building"))

        pcall(function() title.Font.Size = 20 end)

        title:SetColorAndOpacity(FSlateColor(0.95, 0.88, 0.55, 1.0))

        local title_slot = panel_canvas:AddChildToCanvas(title)

        title_slot:SetAutoSize(true)

        title_slot:SetPosition({ X = 0, Y = 0 })



        click_border = StaticConstructObject(border_cls, panel_canvas, FName("RCBMenuClick"))

        click_border:SetBrushColor(FLinearColor(0.15, 0.17, 0.22, 1.0))

        click_border:SetPadding({ Left = 8, Top = 8, Right = 8, Bottom = 8 })

        local click_slot = panel_canvas:AddChildToCanvas(click_border)

        click_slot:SetAutoSize(true)

        click_slot:SetPosition({ X = 0, Y = 34 })



        icon_widget = StaticConstructObject(image_cls, click_border, FName("RCBMenuIcon"))

        icon_widget:SetDesiredSizeOverride({ X = 72, Y = 72 })

        click_border:SetContent(icon_widget)



        local label = StaticConstructObject(text_block_cls, panel_canvas, FName("RCBMenuLabel"))

        label:SetText(FText("Stonewall"))

        pcall(function() label.Font.Size = 16 end)

        label:SetColorAndOpacity(FSlateColor(1.0, 1.0, 1.0, 1.0))

        local label_slot = panel_canvas:AddChildToCanvas(label)

        label_slot:SetAutoSize(true)

        label_slot:SetPosition({ X = 0, Y = 118 })



        hint_widget = StaticConstructObject(text_block_cls, panel_canvas, FName("RCBMenuHint"))

        hint_widget:SetText(FText("F7 close | G build | E or click place"))

        pcall(function() hint_widget.Font.Size = 12 end)

        hint_widget:SetColorAndOpacity(FSlateColor(0.7, 0.7, 0.7, 1.0))

        local hint_slot = panel_canvas:AddChildToCanvas(hint_widget)

        hint_slot:SetAutoSize(true)

        hint_slot:SetPosition({ X = 0, Y = 142 })



        canvas:SetVisibility(VIS_HIDDEN)

        panel:SetVisibility(VIS_HIDDEN)

        panel_canvas:SetVisibility(VIS_HIT)



        hud:AddToViewport(9999)



        root_widget = hud

        root_canvas = canvas

        root_panel = panel

    end)



    if not ok_all then

        print(TAG .. " menu widget error: " .. tostring(err))

        root_widget = nil

        root_canvas = nil

        root_panel = nil

        click_border = nil

        icon_widget = nil

        hint_widget = nil

        return false

    end



    refresh_icon()

    register_place_keybind()

    print(TAG .. " custom build menu widget created")

    return is_valid(root_canvas)

end



function M.on_world_ready()

end



return M




