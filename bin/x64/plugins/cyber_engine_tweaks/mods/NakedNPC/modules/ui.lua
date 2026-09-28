-- NakedNPC - ImGui UI Module
-- ============================
-- Debug and settings overlay accessible via CET overlay (default: ~ key).
-- Shows mod status, stripped NPC list, component inspector, and settings.

local UI = {}

local Config = nil
local NPCTracker = nil
local Stripper = nil
local BodyManager = nil
local modVersion = ""

-- UI state
local selectedNPCIndex = 0
local componentDump = {}
local showComponentInspector = false
local showBodyMeshEditor = false
local bodyMeshInputs = {}

-- -------------------------------------------------------
--  INIT
-- -------------------------------------------------------

function UI.Init(config, npcTracker, stripper, bodyManager, version)
    Config = config
    NPCTracker = npcTracker
    Stripper = stripper
    BodyManager = bodyManager
    modVersion = version

    -- Initialize body mesh input buffers
    for _, bodyType in ipairs(BodyManager.GetBodyTypes()) do
        bodyMeshInputs[bodyType] = {
            body = "",
            legs = "",
            feet = ""
        }
    end
end

-- -------------------------------------------------------
--  MAIN DRAW
-- -------------------------------------------------------

function UI.Draw(system)
    -- Main window
    ImGui.SetNextWindowSize(480, 600, ImGuiCond.FirstUseEver)
    local visible, opened = ImGui.Begin("NakedNPC v" .. modVersion, true)

    if not visible then
        ImGui.End()
        return
    end

    -- ---- STATUS BAR ----
    UI.DrawStatusBar(system)
    ImGui.Separator()

    -- ---- TABS ----
    if ImGui.BeginTabBar("NakedNPCTabs") then
        if ImGui.BeginTabItem("Status") then
            UI.DrawStatusTab(system)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("NPCs") then
            UI.DrawNPCsTab(system)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Debug") then
            UI.DrawDebugTab(system)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Settings") then
            UI.DrawSettingsTab(system)
            ImGui.EndTabItem()
        end

        ImGui.EndTabBar()
    end

    ImGui.End()
end

-- -------------------------------------------------------
--  STATUS BAR
-- -------------------------------------------------------

function UI.DrawStatusBar(system)
    local enabled = Config.Get("enabled")
    local statusColor = enabled and {0.0, 1.0, 0.0, 1.0} or {1.0, 0.3, 0.3, 1.0}
    local statusText = enabled and "ACTIVE" or "DISABLED"

    ImGui.TextColored(statusColor[1], statusColor[2], statusColor[3], statusColor[4], statusText)
    ImGui.SameLine()

    local stats = NPCTracker.GetStats()
    ImGui.Text(string.format("| Stripped: %d | Session: %d / %d restored",
        stats.currentlyStripped, stats.totalStripped, stats.totalRestored))

    -- Redscript system status
    if system then
        ImGui.SameLine()
        ImGui.TextColored(0.0, 0.8, 0.0, 1.0, "| RS: OK")
    else
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.5, 0.0, 1.0, "| RS: N/A")
    end
end

-- -------------------------------------------------------
--  STATUS TAB
-- -------------------------------------------------------

function UI.DrawStatusTab(system)
    ImGui.Spacing()

    -- Master toggle
    local enabled = Config.Get("enabled")
    local changed
    enabled, changed = ImGui.Checkbox("Mod Enabled", enabled)
    if changed then
        Config.Set("enabled", enabled)
        if system then system:SetEnabled(enabled) end
        Config.Save()
    end

    ImGui.Spacing()
    ImGui.Text("How it works:")
    ImGui.TextWrapped("NakedNPC hooks ScheduleAppearanceChange(). When a mod requests a '_naked' appearance that doesn't exist, NakedNPC intercepts the call and strips clothing components instead.")
    ImGui.Spacing()

    -- Quick stats
    local stats = NPCTracker.GetStats()
    ImGui.Text("Currently Stripped NPCs: " .. stats.currentlyStripped)
    ImGui.Text("Total Stripped (session): " .. stats.totalStripped)
    ImGui.Text("Total Restored (session): " .. stats.totalRestored)
    ImGui.Text("Cleanup removals: " .. stats.totalCleanups)

    if system then
        ImGui.Spacing()
        ImGui.Text("Redscript System Stats:")
        ImGui.Text("  RS Stripped: " .. system:GetCurrentStrippedCount())
        ImGui.Text("  RS Total Stripped: " .. system:GetTotalStripped())
        ImGui.Text("  RS Total Restored: " .. system:GetTotalRestored())
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Quick actions
    ImGui.Text("Quick Actions:")
    if ImGui.Button("Strip Look-At Target") then
        local target = Stripper.GetLookAtTarget()
        if target then
            -- Use the global NakedNPC.Strip() which routes through
            -- initiateNakedCycle() for proper mesh swap via OnRequestComponents
            local success = NakedNPC.Strip(target)
            if success then
                print("[NakedNPC] Stripped look-at target")
            else
                print("[NakedNPC] Failed to strip target")
            end
        else
            print("[NakedNPC] No NPC target found")
        end
    end

    ImGui.SameLine()

    if ImGui.Button("Restore Look-At Target") then
        local target = Stripper.GetLookAtTarget()
        if target then
            local success = Stripper.RestoreEntity(target)
            if success then
                print("[NakedNPC] Restored look-at target")
            else
                print("[NakedNPC] Failed to restore target")
            end
        else
            print("[NakedNPC] No NPC target found")
        end
    end

    ImGui.SameLine()

    if ImGui.Button("Inspect Look-At Target") then
        local target = Stripper.GetLookAtTarget()
        if target then
            componentDump = Stripper.GetComponentDump(target)
            showComponentInspector = true
            print("[NakedNPC] Inspecting target: " .. #componentDump .. " mesh components")
        else
            print("[NakedNPC] No NPC target found")
        end
    end
end

-- -------------------------------------------------------
--  NPCS TAB
-- -------------------------------------------------------

function UI.DrawNPCsTab(system)
    ImGui.Spacing()

    local trackedNPCs = NPCTracker.GetAll()

    if #trackedNPCs == 0 then
        ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "No NPCs currently stripped")
        return
    end

    ImGui.Text(string.format("%d NPCs currently stripped:", #trackedNPCs))
    ImGui.Spacing()

    -- NPC list
    for i, entry in ipairs(trackedNPCs) do
        local data = entry.data
        local label = string.format("[%s] %s (%.0fs ago)",
            entry.key,
            data.originalAppearance or "unknown",
            os.clock() - data.timestamp)

        if ImGui.Selectable(label, selectedNPCIndex == i) then
            selectedNPCIndex = i
            -- Dump components for selected NPC
            if data.entityRef then
                componentDump = Stripper.GetComponentDump(data.entityRef)
                showComponentInspector = true
            end
        end
    end

    -- Component inspector for selected NPC
    if showComponentInspector and #componentDump > 0 then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        UI.DrawComponentInspector()
    end
end

-- -------------------------------------------------------
--  COMPONENT INSPECTOR
-- -------------------------------------------------------

function UI.DrawComponentInspector()
    ImGui.Text(string.format("Mesh Components (%d):", #componentDump))

    ImGui.BeginChild("ComponentList", 0, 200, true)
    for _, comp in ipairs(componentDump) do
        local color
        if comp.isBody then
            color = comp.enabled and {0.0, 1.0, 0.0, 1.0} or {0.0, 0.5, 0.0, 1.0}
        elseif comp.isClothing then
            color = comp.enabled and {1.0, 0.3, 0.3, 1.0} or {0.5, 0.15, 0.15, 1.0}
        else
            color = comp.enabled and {0.8, 0.8, 0.8, 1.0} or {0.4, 0.4, 0.4, 1.0}
        end

        local prefix = comp.isBody and "[BODY]  " or (comp.isClothing and "[CLOTH] " or "[????]  ")
        local status = comp.enabled and " ON" or " OFF"

        ImGui.TextColored(color[1], color[2], color[3], color[4],
            prefix .. comp.name .. status)
    end
    ImGui.EndChild()

    ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "Green = Body (kept)")
    ImGui.SameLine()
    ImGui.TextColored(1.0, 0.3, 0.3, 1.0, " Red = Clothing (stripped)")
    ImGui.SameLine()
    ImGui.TextColored(0.8, 0.8, 0.8, 1.0, " Grey = Other")
end

-- -------------------------------------------------------
--  DEBUG TAB
-- -------------------------------------------------------

function UI.DrawDebugTab(system)
    ImGui.Spacing()

    local debugMode = Config.Get("debugMode")
    local changed
    debugMode, changed = ImGui.Checkbox("Debug Mode (verbose logging)", debugMode)
    if changed then
        Config.Set("debugMode", debugMode)
        if system then system:SetDebugMode(debugMode) end
        Config.Save()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.Text("Manual Component Inspection:")
    ImGui.TextWrapped("Look at an NPC and click 'Inspect' to see their mesh components.")

    if ImGui.Button("Inspect Crosshair Target") then
        local target = Stripper.GetLookAtTarget()
        if target then
            componentDump = Stripper.GetComponentDump(target)
            showComponentInspector = true
            print("[NakedNPC] Components found: " .. #componentDump)
        else
            print("[NakedNPC] No target")
        end
    end

    if showComponentInspector and #componentDump > 0 then
        ImGui.Spacing()
        UI.DrawComponentInspector()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Redscript system debug info
    if system then
        ImGui.Text("Redscript System Debug:")
        ImGui.Text("  Enabled: " .. tostring(system:IsEnabled()))
        ImGui.Text("  Debug: " .. tostring(system:IsDebugMode()))
        ImGui.Text("  MeshSwap: " .. tostring(system:IsMeshSwapEnabled()))
        ImGui.Text("  Tracked: " .. system:GetCurrentStrippedCount())
    else
        ImGui.TextColored(1.0, 0.5, 0.0, 1.0, "Redscript system not available")
        ImGui.TextWrapped("The NakedNPC Redscript component is not loaded. The ScheduleAppearanceChange hook will not work. You can still use the manual Strip/Restore buttons (Lua-only mode).")
    end
end

-- -------------------------------------------------------
--  SETTINGS TAB
-- -------------------------------------------------------

function UI.DrawSettingsTab(system)
    ImGui.Spacing()
    local changed

    -- General settings
    ImGui.Text("General:")
    ImGui.Spacing()

    local showUI = Config.Get("showUI")
    showUI, changed = ImGui.Checkbox("Show this UI window", showUI)
    if changed then Config.Set("showUI", showUI); Config.Save() end

    local meshSwap = Config.Get("meshSwapEnabled")
    meshSwap, changed = ImGui.Checkbox("Enable mesh swap fallback (experimental)", meshSwap)
    if changed then
        Config.Set("meshSwapEnabled", meshSwap)
        if system then system:SetMeshSwapEnabled(meshSwap) end
        Config.Save()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Stripping options
    ImGui.Text("Stripping Options:")
    ImGui.Spacing()

    local stripHead = Config.Get("stripHeadwear")
    stripHead, changed = ImGui.Checkbox("Strip headwear (hats, glasses)", stripHead)
    if changed then Config.Set("stripHeadwear", stripHead); Config.Save() end

    local stripAcc = Config.Get("stripAccessories")
    stripAcc, changed = ImGui.Checkbox("Strip accessories (chokers, jewelry)", stripAcc)
    if changed then Config.Set("stripAccessories", stripAcc); Config.Save() end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Body mesh paths
    ImGui.Text("Body Mesh Depot Paths:")
    ImGui.TextWrapped("Override the nude body mesh paths used for mesh swap fallback. Leave empty to use defaults. These are game depot paths (e.g. base\\characters\\...).")
    ImGui.Spacing()

    if ImGui.Button(showBodyMeshEditor and "Hide Mesh Editor" or "Show Mesh Editor") then
        showBodyMeshEditor = not showBodyMeshEditor
    end

    if showBodyMeshEditor then
        for _, bodyType in ipairs(BodyManager.GetBodyTypes()) do
            ImGui.Spacing()
            ImGui.Text(BodyManager.GetDisplayName(bodyType) .. ":")

            local paths = BodyManager.GetAllMeshPaths(bodyType == "female_average" and 1 or (bodyType == "male_average" and 2 or 3))
            for _, part in ipairs({"body", "legs", "feet"}) do
                local currentPath = paths[part] or ""
                ImGui.PushItemWidth(380)
                local newPath
                newPath, changed = ImGui.InputText(part .. "##" .. bodyType, currentPath, 256)
                ImGui.PopItemWidth()
                if changed and newPath ~= currentPath then
                    BodyManager.SetMeshPath(bodyType, part, newPath)
                end
            end
        end

        ImGui.Spacing()
        if ImGui.Button("Save Mesh Paths") then
            BodyManager.Save()
            print("[NakedNPC] Body mesh paths saved")
        end
        ImGui.SameLine()
        if ImGui.Button("Reset to Defaults") then
            BodyManager.Init()
            print("[NakedNPC] Body mesh paths reset to defaults")
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Reset all settings
    ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Danger Zone:")
    if ImGui.Button("Reset All Settings to Defaults") then
        Config.Reset()
        if system then
            system:SetEnabled(true)
            system:SetDebugMode(false)
            system:SetMeshSwapEnabled(true)
        end
        print("[NakedNPC] All settings reset to defaults")
    end
end

return UI
