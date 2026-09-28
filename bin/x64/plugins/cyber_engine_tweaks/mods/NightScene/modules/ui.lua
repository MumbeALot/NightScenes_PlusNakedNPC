-- NightScene Framework - UI Module
-- ==================================
-- ImGui-based configuration menu and animation browser.
-- Rendered through CET's ImGui integration.
--
-- The UI has two main panels:
--   1. Config Menu - Settings, hotkeys, toggles
--   2. Animation Browser - Browse and select registered animations

local UI = {}

-- Reference to the config module (set during init)
UI.config = nil

-- Reference to the animation toggle module (set during init)
UI.animToggles = nil

-- Whether any animation toggle has changed since the last save
UI.animTogglesDirty = false

-- UI state
UI.showConfigMenu = false
UI.showAnimBrowser = false
UI.showSceneControls = false

-- Set when a window is toggled open, to clear a stale collapsed state that CET
-- may have persisted in layout.ini (see DrawConfigMenu)
UI.forceExpandConfig = false
UI.forceExpandBrowser = false

-- Animation browser state
UI.animBrowserFilter = ""
UI.animBrowserPack = "All"
UI.selectedAnimIndex = -1

-- Scene control state
UI.sceneSpeed = 1.0

-- Camera mode names for display
UI.cameraModeNames = { "First Person", "Third Person", "Cinematic", "Free Camera" }
UI.genderFilterNames = { "Any", "Male", "Female" }
UI.playerPositionNames = { "Dom", "Sub" }

UI.hotkeySlots = {
    { label = "Interact with NPC",  slug = "ns_interact"       },
    { label = "Cancel Scene",       slug = "ns_cancel_scene"   },
    { label = "Next Stage",         slug = "ns_next_stage"     },
    { label = "Prev Stage",         slug = "ns_prev_stage"     },
    { label = "Speed Up",           slug = "ns_speed_up"       },
    { label = "Speed Down",         slug = "ns_speed_down"     },
    { label = "Cycle Camera",       slug = "ns_camera_mode"    },
    { label = "Next Camera Angle",  slug = "ns_camera_preset"  },
    { label = "Scene Controls HUD", slug = "ns_scene_controls" },
    { label = "Open Settings",      slug = "ns_toggle_config"  },
    { label = "Anim Browser",       slug = "ns_toggle_browser" },
}

--- Initialize the UI module.
function UI.Init(configModule, animTogglesModule)
    UI.config = configModule
    UI.animToggles = animTogglesModule
    print("[NightScene] UI module initialized")
end

--- Main render function called every frame by CET.
function UI.OnDraw()
    if UI.showConfigMenu then
        UI.DrawConfigMenu()
    end

    if UI.showAnimBrowser then
        UI.DrawAnimBrowser()
    end

    if UI.showSceneControls then
        UI.DrawSceneControls()
    end
end

-- ============================================================
--  CONFIG MENU
-- ============================================================

function UI.DrawConfigMenu()
    -- NoCollapse removes the title-bar collapse ("drop down") arrow. Clicking it
    -- put the window into a collapsed state that CET persists in layout.ini;
    -- from then on ImGui.Begin reports the window as not-visible every frame, we
    -- early-return, and the window appears to flash and vanish -- permanently,
    -- across restarts, until layout.ini is deleted. DrawSceneControls already
    -- used NoCollapse, which is why it was never affected.
    local windowFlags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoCollapse

    -- Self-heal for anyone whose layout.ini already has this window stored as
    -- collapsed: force it expanded the frame it's toggled open, so they don't
    -- have to delete the file by hand.
    if UI.forceExpandConfig then
        UI.forceExpandConfig = false
        pcall(function() ImGui.SetNextWindowCollapsed(false, ImGuiCond.Always) end)
    end

    local shouldDraw, isOpen = ImGui.Begin("NightScene - Settings", UI.showConfigMenu, windowFlags)

    -- Only treat this as "closed" when it's actually false. Assigning it blindly
    -- let a nil/collapsed result silently close the window.
    if isOpen == false then
        UI.showConfigMenu = false
    end

    if not shouldDraw then
        ImGui.End()
        return
    end

    local cfg = UI.config.current

    -- Master enable
    ImGui.Separator()
    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "=== General ===")
    ImGui.Separator()

    -- Player position preference
    ImGui.Text("Player Position:")
    for i, name in ipairs(UI.playerPositionNames) do
        if ImGui.RadioButton(name .. "##playerpos", cfg.playerPosition == (i - 1)) then
            cfg.playerPosition = i - 1
        end
        if i < #UI.playerPositionNames then
            ImGui.SameLine()
        end
    end
    ImGui.TextWrapped("Only applies to same-gender scenes -- mixed-gender scenes are always locked to the correct body slot automatically.")

    cfg.enabled, _ = ImGui.Checkbox("Enable NightScene Framework", cfg.enabled)

    -- Default camera mode
    ImGui.Text("Default Camera Mode:")
    for i, name in ipairs(UI.cameraModeNames) do
        if ImGui.RadioButton(name, cfg.defaultCameraMode == (i - 1)) then
            cfg.defaultCameraMode = i - 1
        end
        if i < #UI.cameraModeNames then
            ImGui.SameLine()
        end
    end

    -- Speed
    cfg.defaultSpeed, _ = ImGui.SliderFloat("Default Speed", cfg.defaultSpeed, 0.1, 3.0, "%.1f")

    -- Equipment
    cfg.stripEquipment, _ = ImGui.Checkbox("Strip Equipment During Scenes", cfg.stripEquipment)

    -- Auto-advance
    cfg.autoAdvanceStages, _ = ImGui.Checkbox("Auto-Advance Stages", cfg.autoAdvanceStages)

    -- Defeat system
    ImGui.Separator()
    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "=== Defeat System ===")
    ImGui.Separator()

    cfg.defeatEnabled, _ = ImGui.Checkbox("Enable Defeat Scenes", cfg.defeatEnabled)

    if cfg.defeatEnabled then
        -- Display as percentage (1% to 50%) but store as fraction (0.01 to 0.5)
        local displayPct = cfg.defeatHealthThreshold * 100.0
        displayPct, _ = ImGui.SliderFloat(
            "Health Threshold",
            displayPct,
            1.0, 100.0,
            "%.0f%%"
        )
        cfg.defeatHealthThreshold = displayPct / 100.0
        ImGui.TextWrapped("Defeat triggers when health drops below this percentage.")

        -- Grace Period
        cfg.defeatGracePeriod, _ = ImGui.SliderFloat(
            "Grace Period (s)",
            cfg.defeatGracePeriod,
            0.0, 30.0,
            "%.0f"
        )
        ImGui.TextWrapped("Seconds before enemies become hostile again after defeat scene.")

        -- Cooldown
        cfg.defeatCooldown, _ = ImGui.SliderFloat(
            "Defeat Cooldown (s)",
            cfg.defeatCooldown,
            5.0, 120.0,
            "%.0f"
        )
        ImGui.TextWrapped("Seconds before defeat can trigger again.")

        -- Money Loss
        cfg.defeatMoneyLossIsPercent, _ = ImGui.Checkbox("Money Loss is Percentage", cfg.defeatMoneyLossIsPercent)
        if cfg.defeatMoneyLossIsPercent then
            cfg.defeatMoneyLoss, _ = ImGui.SliderFloat(
                "Money Loss (%)",
                cfg.defeatMoneyLoss,
                0.0, 100.0,
                "%.0f%%"
            )
        else
            cfg.defeatMoneyLoss, _ = ImGui.SliderFloat(
                "Money Loss (eddies)",
                cfg.defeatMoneyLoss,
                0.0, 10000.0,
                "%.0f"
            )
        end
        ImGui.TextWrapped("Money deducted on defeat. Set to 0 to disable.")
    end

    -- NPC Interaction
    ImGui.Separator()
    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "=== NPC Interaction ===")
    ImGui.Separator()

    cfg.npcInteractionEnabled, _ = ImGui.Checkbox("Enable NPC Interactions", cfg.npcInteractionEnabled)

    if cfg.npcInteractionEnabled then
        cfg.npcInteractionRange, _ = ImGui.SliderFloat(
            "Interaction Range (m)",
            cfg.npcInteractionRange,
            1.0, 20.0,
            "%.1f"
        )

        -- Gender filter
        ImGui.Text("NPC Gender Filter:")
        for i, name in ipairs(UI.genderFilterNames) do
            if ImGui.RadioButton(name .. "##gender", cfg.npcGenderFilter == (i - 1)) then
                cfg.npcGenderFilter = i - 1
            end
            if i < #UI.genderFilterNames then
                ImGui.SameLine()
            end
        end
    end

    -- Hotkeys
    ImGui.Separator()
    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, "=== Hotkeys ===")
    ImGui.Separator()

    for _, slot in ipairs(UI.hotkeySlots) do
        local isBound = pcall(IsBound, slot.slug) and IsBound(slot.slug)
        local bindStr = "[UNBOUND]"
        if isBound then
            local ok, result = pcall(GetBind, slot.slug)
            bindStr = (ok and result and result ~= "") and result or "[UNBOUND]"
            isBound = bindStr ~= "[UNBOUND]"
        end

        ImGui.Text(string.format("%-22s", slot.label .. ":"))
        ImGui.SameLine()
        if isBound then
            ImGui.TextColored(0.4, 1.0, 0.4, 1.0, bindStr)
        else
            ImGui.TextColored(1.0, 0.45, 0.45, 1.0, bindStr)
        end
    end

    ImGui.TextWrapped("Rebind keys in the CET overlay > Bindings tab.")

    -- Push any changes made this frame to Redscript immediately, so settings
    -- take effect live instead of silently doing nothing until a manual save.
    UI.config.SyncToRedscript()

    -- Save / Reset buttons
    ImGui.Separator()
    if ImGui.Button("Save Settings") then
        UI.config.Save()
    end
    ImGui.SameLine()
    if ImGui.Button("Reset to Defaults") then
        UI.config.Reset()
    end

    -- Info
    ImGui.Separator()
    ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "NightScene Framework v0.1.0")

    -- Show animation count
    local animCount = 0
    pcall(function()
        animCount = Game["NightSceneAPI::GetAnimationCount;"]()
    end)
    ImGui.Text("Registered Animations: " .. tostring(animCount))

    ImGui.End()
end

-- ============================================================
--  ANIMATION BROWSER
-- ============================================================

--- Whether an animation passes the current filter/pack selection.
local function animMatchesFilter(anim)
    if UI.animBrowserFilter ~= "" then
        local filterLower = string.lower(UI.animBrowserFilter)
        local idLower = string.lower(anim.id or "")
        local nameLower = string.lower(anim.displayName or "")
        if not string.find(idLower, filterLower) and not string.find(nameLower, filterLower) then
            return false
        end
    end

    if UI.animBrowserPack ~= "All" and anim.packName ~= UI.animBrowserPack then
        return false
    end

    return true
end

--- Enable or disable every animation currently passing the filter/pack selection.
local function setAllFiltered(anims, enabled)
    if not UI.animToggles then return end
    for _, anim in ipairs(anims) do
        if animMatchesFilter(anim) and anim.id then
            UI.animToggles.SetEnabled(anim.id, enabled)
        end
    end
    UI.animTogglesDirty = true
end

function UI.DrawAnimBrowser()
    -- NoCollapse + force-expand: same collapsed-state trap as the settings
    -- window (see DrawConfigMenu). This window had the collapse arrow too, so
    -- the "pops up for a microsecond then goes away" reports likely came from
    -- here as well.
    local windowFlags = ImGuiWindowFlags.NoCollapse

    if UI.forceExpandBrowser then
        UI.forceExpandBrowser = false
        pcall(function() ImGui.SetNextWindowCollapsed(false, ImGuiCond.Always) end)
    end

    local shouldDraw, isOpen = ImGui.Begin("NightScene - Animation Browser", UI.showAnimBrowser, windowFlags)

    if isOpen == false then
        UI.showAnimBrowser = false
    end

    if not shouldDraw then
        ImGui.End()
        return
    end

    -- Filter bar
    ImGui.Text("Filter:")
    ImGui.SameLine()
    UI.animBrowserFilter, _ = ImGui.InputText("##filter", UI.animBrowserFilter, 256)

    -- Pack filter
    ImGui.SameLine()
    ImGui.Text("Pack:")
    ImGui.SameLine()
    if ImGui.BeginCombo("##packFilter", UI.animBrowserPack) then
        if ImGui.Selectable("All", UI.animBrowserPack == "All") then
            UI.animBrowserPack = "All"
        end

        -- Get pack names from registry
        local packs = {}
        pcall(function()
            packs = Game["NightSceneAPI::GetPackNames;"]()
        end)

        for _, pack in ipairs(packs) do
            if ImGui.Selectable(pack, UI.animBrowserPack == pack) then
                UI.animBrowserPack = pack
            end
        end

        ImGui.EndCombo()
    end

    ImGui.Separator()

    -- Animation list
    local anims = {}
    pcall(function()
        local emptyTags = {}
        anims = Game["NightSceneAPI::QueryAnimations;array<String>Int32"](emptyTags, 0)
    end)

    -- Bulk enable/disable -- applies to whatever the current filter/pack
    -- selection shows, so "All" + no filter affects everything.
    if ImGui.Button("Enable All") then
        setAllFiltered(anims, true)
    end
    ImGui.SameLine()
    if ImGui.Button("Disable All") then
        setAllFiltered(anims, false)
    end
    if UI.animBrowserFilter ~= "" or UI.animBrowserPack ~= "All" then
        ImGui.SameLine()
        ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "(applies to filtered results only)")
    end

    -- Table header
    if ImGui.BeginTable("AnimTable", 6, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn("On", ImGuiTableColumnFlags.None, 30)
        ImGui.TableSetupColumn("ID", ImGuiTableColumnFlags.None, 200)
        ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.None, 200)
        ImGui.TableSetupColumn("Pack", ImGuiTableColumnFlags.None, 120)
        ImGui.TableSetupColumn("Actors", ImGuiTableColumnFlags.None, 50)
        ImGui.TableSetupColumn("Stages", ImGuiTableColumnFlags.None, 50)
        ImGui.TableHeadersRow()

        for i, anim in ipairs(anims) do
            if animMatchesFilter(anim) then
                ImGui.TableNextRow()
                ImGui.TableNextColumn()

                -- Enabled checkbox -- default to true if the field is missing
                -- (older/uninitialized defs), matching the "enabled by default" design.
                local isEnabled = anim.enabled
                if isEnabled == nil then isEnabled = true end
                local newEnabled, toggled = ImGui.Checkbox("##enabled" .. tostring(i), isEnabled)
                if toggled and UI.animToggles and anim.id then
                    UI.animToggles.SetEnabled(anim.id, newEnabled)
                    UI.animTogglesDirty = true
                end

                ImGui.TableNextColumn()

                -- Selectable row
                local isSelected = (UI.selectedAnimIndex == i)
                if ImGui.Selectable(anim.id or "???", isSelected, ImGuiSelectableFlags.SpanAllColumns) then
                    UI.selectedAnimIndex = i
                end

                ImGui.TableNextColumn()
                ImGui.Text(anim.displayName or "")
                ImGui.TableNextColumn()
                ImGui.Text(anim.packName or "")
                ImGui.TableNextColumn()
                ImGui.Text(tostring(anim.actorCount or 0))
                ImGui.TableNextColumn()
                ImGui.Text(tostring(#(anim.stages or {})))
            end
        end

        ImGui.EndTable()
    end

    -- Action buttons
    ImGui.Separator()
    if UI.selectedAnimIndex > 0 and UI.selectedAnimIndex <= #anims then
        local selectedAnim = anims[UI.selectedAnimIndex]
        ImGui.Text("Selected: " .. (selectedAnim.displayName or selectedAnim.id))

        if ImGui.Button("Play With Nearest NPC") then
            pcall(function()
                Game["NightSceneAPI::TriggerInteractionHotkey;"]()
            end)
        end

        ImGui.SameLine()
        if ImGui.Button("Play By ID") then
            pcall(function()
                if selectedAnim and selectedAnim.id then
                    -- TODO: Full implementation needs a proper "start this exact
                    -- animation" API (StartScene by ID goes through the general
                    -- ff/mf/mbf/defeat selection, not a specific def) plus NPC
                    -- selection UI. For now this behaves the same as the button above.
                    Game["NightSceneAPI::TriggerInteractionHotkey;"]()
                end
            end)
        end
    else
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Select an animation from the list above")
    end

    -- Animation toggle save
    ImGui.Separator()
    if ImGui.Button("Save Enabled Animations") then
        if UI.animToggles then
            UI.animToggles.Save()
            UI.animTogglesDirty = false
        end
    end
    if UI.animTogglesDirty then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.8, 0.3, 1.0, "Unsaved changes")
    end

    -- Stats
    ImGui.Separator()
    ImGui.Text("Total animations: " .. tostring(#anims))

    ImGui.End()
end

-- ============================================================
--  SCENE CONTROLS (shown during active scene)
-- ============================================================

function UI.DrawSceneControls()
    -- Small floating control panel during active scenes
    local windowFlags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoCollapse

    local shouldDraw, isOpen = ImGui.Begin("Scene Controls", UI.showSceneControls, windowFlags)
    UI.showSceneControls = isOpen

    if not shouldDraw then
        ImGui.End()
        return
    end

    -- Stage navigation
    if ImGui.Button("<< Prev Stage") then
        pcall(function() Game["NightSceneAPI::PreviousStage;"]() end)
    end
    ImGui.SameLine()
    if ImGui.Button("Next Stage >>") then
        pcall(function() Game["NightSceneAPI::NextStage;"]() end)
    end

    -- Speed control
    ImGui.Separator()
    UI.sceneSpeed, _ = ImGui.SliderFloat("Speed", UI.sceneSpeed, 0.1, 3.0, "%.1f")
    if ImGui.IsItemDeactivatedAfterEdit() then
        pcall(function() Game["NightSceneAPI::SetSpeed;Float"](UI.sceneSpeed) end)
    end

    -- Camera controls
    ImGui.Separator()
    ImGui.Text("Camera:")
    for i, name in ipairs(UI.cameraModeNames) do
        if ImGui.Button(name .. "##cam") then
            pcall(function() Game["NightSceneAPI::SetCameraMode;NightSceneCameraMode"](i - 1) end)
        end
        if i < #UI.cameraModeNames then
            ImGui.SameLine()
        end
    end

    if ImGui.Button("Next Camera Angle") then
        pcall(function() Game["NightSceneAPI::NextCameraPreset;"]() end)
    end

    -- Stop button
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.2, 0.2, 1.0)
    if ImGui.Button("Stop Scene", 280, 30) then
        pcall(function() Game["NightSceneAPI::StopScene;"]() end)
    end
    ImGui.PopStyleColor(1)

    ImGui.End()
end

--- Toggle the config menu visibility.
function UI.ToggleConfigMenu()
    UI.showConfigMenu = not UI.showConfigMenu
    if UI.showConfigMenu then
        -- Clear any stale collapsed state persisted in layout.ini so the window
        -- always comes back expanded when the hotkey opens it.
        UI.forceExpandConfig = true
    end
end

--- Toggle the animation browser visibility.
function UI.ToggleAnimBrowser()
    UI.showAnimBrowser = not UI.showAnimBrowser
    if UI.showAnimBrowser then
        UI.forceExpandBrowser = true
    end
end

--- Show/hide scene controls (called when scene starts/stops).
function UI.SetSceneControlsVisible(visible)
    UI.showSceneControls = visible
end

return UI
