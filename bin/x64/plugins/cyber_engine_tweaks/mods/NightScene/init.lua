-- NightScene Framework - CET Entry Point
-- =========================================
-- This is the main Cyber Engine Tweaks mod entry point.
-- CET loads this file when the game starts.
--
-- Responsibilities:
--   1. Load configuration from disk
--   2. Register hotkey bindings
--   3. Set up ImGui draw callbacks for the UI
--   4. Bridge between CET Lua and Redscript framework
--
-- INSTALLATION:
--   Place this folder at:
--   <game_dir>/bin/x64/plugins/cyber_engine_tweaks/mods/NightScene/

-- Load modules safely (a failing module must not block event registration)
local ok, Config = pcall(require, "modules/config")
if not ok then
    print("[NightScene] ERROR loading config module: " .. tostring(Config))
    Config = { Load = function() end, Save = function() end, SyncToRedscript = function() end, current = { enabled = true } }
end

local ok2, UI = pcall(require, "modules/ui")
if not ok2 then
    print("[NightScene] ERROR loading UI module: " .. tostring(UI))
    UI = { Init = function() end, OnDraw = function() end, ToggleConfigMenu = function() end, ToggleAnimBrowser = function() end, SetSceneControlsVisible = function() end, showSceneControls = false }
end

local ok3, AMMLoader = pcall(require, "modules/amm_loader")
if not ok3 then
    print("[NightScene] ERROR loading AMM loader module: " .. tostring(AMMLoader))
    AMMLoader = { LoadAll = function() print("[NightScene] AMM Loader not available") end }
end

local ok4, Spawner = pcall(require, "modules/workspot_spawner")
if not ok4 then
    print("[NightScene] ERROR loading workspot spawner module: " .. tostring(Spawner))
    Spawner = { SpawnAndPlay = function() end, Cleanup = function() end }
end

local ok5, AnimToggles = pcall(require, "modules/anim_toggles")
if not ok5 then
    print("[NightScene] ERROR loading anim toggles module: " .. tostring(AnimToggles))
    AnimToggles = { Load = function() end, Save = function() end, ApplyToRedscript = function() end, SetEnabled = function() end, IsEnabled = function() return true end, disabled = {} }
end

local ok6, ExplicitMatcher = pcall(require, "modules/explicit_matcher")
if not ok6 then
    print("[NightScene] ERROR loading explicit matcher module: " .. tostring(ExplicitMatcher))
    ExplicitMatcher = { FindForNPC = function() return nil, { reason = "matcher failed to load" } end, DebugLookAt = function() end }
end

-- Temporary: NPC hiding experiments for the explicit-entity swap.
local ok7, HideTest = pcall(require, "modules/hide_test")
if not ok7 then
    print("[NightScene] ERROR loading hide test module: " .. tostring(HideTest))
    HideTest = { Hide = function() end, Show = function() end, Components = function() end }
end

-- Module-level state
local isInitialized = false
local isInGame = false

-- ============================================================
--  CET LIFECYCLE CALLBACKS
-- ============================================================

--- Called when CET initializes the mod.
registerForEvent("onInit", function()
    print("[NightScene] ========================================")
    print("[NightScene]  NightScene Framework v0.1.0 (CET)")
    print("[NightScene] ========================================")

    -- Load configuration
    Config.Load()
    AnimToggles.Load()

    -- Initialize UI with config + anim toggle references
    UI.Init(Config, AnimToggles)

    isInitialized = true
    print("[NightScene] CET module initialized")
end)

--- Called when CET shuts down.
registerForEvent("onShutdown", function()
    -- Save config on exit
    if isInitialized then
        Config.Save()
    end
    print("[NightScene] CET module shut down")
end)

--- Called every frame to render ImGui.
registerForEvent("onDraw", function()
    if not isInitialized or not isInGame then
        return
    end

    UI.OnDraw()
end)

--- Called when a game overlay (like CET console) opens.
registerForEvent("onOverlayOpen", function()
    -- Show the config menu when CET overlay is opened
    -- (This is the CET "home" key overlay)
end)

--- Called when the game overlay closes.
registerForEvent("onOverlayClose", function()
    -- Optionally hide menus when overlay closes
end)

-- Detect when player is in-game and load animations.
-- Re-loads if the ScriptableSystem resets (e.g. after loading a save).
local playerDetectedTime = nil
local lastLoadedCount = 0
local waitingToLoad = false

registerForEvent("onUpdate", function(deltaTime)
    -- Are we in-game? This has to come FIRST. These callbacks also run at the
    -- main menu and through save loading, where there's no game session for
    -- NightSceneAPI to query -- the pending-spawn poll below was firing during
    -- load and reporting "Scene started, spawning workspot... / No entity path"
    -- over and over before the player even existed.
    local okPlayer, player = pcall(Game.GetPlayer)
    if not okPlayer or not player then
        -- Not in game - reset state so we reload on next session
        playerDetectedTime = nil
        waitingToLoad = false
        isInGame = false
        return
    end

    isInGame = true

    -- Poll for workspot entity spawn
    pcall(Spawner.OnUpdate)

    -- Check for a pending workspot spawn. Set by EVERY scene start (defeat,
    -- NPC defeat, and normal hotkey interaction).
    pcall(function()
        local hasPending = Game['NightSceneAPI::HasPendingWorkspotSpawn;']()
        if hasPending then
            Game['NightSceneAPI::ClearPendingWorkspotSpawn;']()
            print("[NightScene] Scene started, spawning workspot...")
            Spawner.SpawnAndPlay()
        end
    end)

    -- Animation or stage changed mid-scene: re-point the actors already in the
    -- workspot at the new clips instead of rebuilding the scene.
    pcall(function()
        if Game['NightSceneAPI::ConsumePendingWorkspotUpdate;']() then
            Spawner.SwitchAnimations()
        end
    end)

    -- Auto-cleanup: detect when Redscript scene ends (auto-advance timer expired)
    -- and trigger Lua cleanup if spawner still has active entities
    pcall(function()
        if Spawner.workspotEntity or Spawner.vClone then
            local isActive = Game['NightSceneAPI::IsSceneActive;']()
            if not isActive then
                print("[NightScene] Scene ended (auto-advance), triggering Lua cleanup...")
                Spawner.Cleanup()
            end
        end
    end)

    -- Check if animations need loading (first time or after system reset)
    local countOk, currentCount = pcall(Game['NightSceneAPI::GetAnimationCount;'])
    if countOk and currentCount and currentCount > 0 then
        -- Already loaded, nothing to do
        lastLoadedCount = currentCount
        waitingToLoad = false
        return
    end

    -- Count is 0 - need to load (or reload after save)
    if not waitingToLoad then
        playerDetectedTime = os.clock()
        waitingToLoad = true
        print("[NightScene] Animations need loading, waiting 3s for framework init...")
        return
    end

    -- Wait 3 seconds for ScriptableSystem to fully attach
    if os.clock() - playerDetectedTime < 3.0 then
        return
    end

    waitingToLoad = false
    print("[NightScene] Loading animation packs...")

    local loadSuccess, loadErr = pcall(function()
        AMMLoader.LoadAll()
    end)
    if not loadSuccess then
        print("[NightScene] AMM Loader error: " .. tostring(loadErr))
    end

    local postOk, postCount = pcall(Game['NightSceneAPI::GetAnimationCount;'])
    print("[NightScene] Registered animations: " .. tostring(postCount))
    lastLoadedCount = postCount or 0

    -- Now that ScriptableSystem is confirmed ready, sync config from Lua to Redscript
    pcall(function()
        Config.SyncToRedscript()
        print("[NightScene] Config synced to Redscript (post-load)")
    end)

    -- Apply saved animation enable/disable toggles now that animations are registered
    pcall(function()
        AnimToggles.ApplyToRedscript()
    end)
end)

-- ============================================================
--  HOTKEY BINDINGS
-- ============================================================

--- Register all hotkeys.
-- CET uses registerHotkey(id, label, callback) for key bindings.
-- Users can rebind these in the CET overlay.

-- Debounce for toggle-style hotkeys (open/close menus). Some key input paths
-- fire registerHotkey callbacks more than once for what feels like a single
-- press (OS/game key-repeat), which flips an open/close toggle back and
-- forth so fast the window only ever flashes on screen. A short cooldown
-- collapses those into a single effective toggle.
local lastToggleTime = {}
local TOGGLE_DEBOUNCE_SECONDS = 0.3

local function debouncedToggle(key, fn)
    local now = os.clock()
    if lastToggleTime[key] and (now - lastToggleTime[key]) < TOGGLE_DEBOUNCE_SECONDS then
        return
    end
    lastToggleTime[key] = now
    fn()
end

-- Toggle config menu
registerHotkey("ns_toggle_config", "NightScene: Toggle Settings", function()
    debouncedToggle("config", UI.ToggleConfigMenu)
end)

-- Toggle animation browser
registerHotkey("ns_toggle_browser", "NightScene: Toggle Anim Browser", function()
    debouncedToggle("browser", UI.ToggleAnimBrowser)
end)

-- Interact with NPC (start scene)
-- Routes through NightSceneInteractionHandler.OnInteractionHotkey, which
-- handles eligibility, defeated-NPC routing, and animation selection itself.
-- It doesn't report success back directly -- like the defeat scenes, it signals
-- Lua via the pending-spawn flag, picked up by the onUpdate poller below.
registerHotkey("ns_interact", "NightScene: Interact with NPC", function()
    if not isInGame then return end
    if not Config.current.enabled then return end

    local success, err = pcall(function()
        Game['NightSceneAPI::TriggerInteractionHotkey;']()
    end)

    if not success then
        print("[NightScene] Interaction error: " .. tostring(err))
    end
end)

-- Cancel current scene
registerHotkey("ns_cancel_scene", "NightScene: Cancel Scene", function()
    if not isInGame then return end

    pcall(function()
        local isActive = Game['NightSceneAPI::IsSceneActive;']()
        if isActive then
            Spawner.Cleanup()
            Game['NightSceneAPI::StopScene;']()
            UI.SetSceneControlsVisible(false)
            print("[NightScene] Scene stopped")
        end
    end)
end)

-- Switch to the next/previous compatible animation WITHOUT restarting the
-- scene. Only animations sharing the current workspot entity and pairing
-- family are offered, so the actors can stay where they are.
local function cycleAnimation(direction)
    if not isInGame then return end

    pcall(function()
        if not Game['NightSceneAPI::IsSceneActive;']() then return end

        local switched = Game['NightSceneAPI::CycleAnimation;Int32'](direction)
        if not switched then
            print("[NightScene] No other compatible animation to switch to")
        end
    end)
end

registerHotkey("ns_next_anim", "NightScene: Next Animation", function()
    cycleAnimation(1)
end)

registerHotkey("ns_prev_anim", "NightScene: Previous Animation", function()
    cycleAnimation(-1)
end)

-- Next stage
registerHotkey("ns_next_stage", "NightScene: Next Stage", function()
    if not isInGame then return end

    pcall(function()
        NightSceneAPI.NextStage()
    end)
end)

-- Previous stage
registerHotkey("ns_prev_stage", "NightScene: Previous Stage", function()
    if not isInGame then return end

    pcall(function()
        NightSceneAPI.PreviousStage()
    end)
end)

-- Speed up
registerHotkey("ns_speed_up", "NightScene: Speed Up", function()
    if not isInGame then return end

    pcall(function()
        if NightSceneAPI.IsSceneActive() then
            -- Speed control via API
            NightSceneAPI.SetSpeed(1.25) -- TODO: track current speed in Lua
            print("[NightScene] Speed up")
        end
    end)
end)

-- Speed down
registerHotkey("ns_speed_down", "NightScene: Speed Down", function()
    if not isInGame then return end

    pcall(function()
        if NightSceneAPI.IsSceneActive() then
            NightSceneAPI.SetSpeed(0.75) -- TODO: track current speed in Lua
            print("[NightScene] Speed down")
        end
    end)
end)

-- Cycle camera mode
registerHotkey("ns_camera_mode", "NightScene: Cycle Camera Mode", function()
    if not isInGame then return end

    pcall(function()
        NightSceneAPI.NextCameraPreset()
        print("[NightScene] Camera preset cycled")
    end)
end)

-- Cycle camera preset (for cinematic mode)
registerHotkey("ns_camera_preset", "NightScene: Next Camera Angle", function()
    if not isInGame then return end

    pcall(function()
        NightSceneAPI.NextCameraPreset()
    end)
end)

-- Toggle scene controls overlay
registerHotkey("ns_scene_controls", "NightScene: Toggle Scene Controls", function()
    if not isInGame then return end
    debouncedToggle("sceneControls", function()
        UI.SetSceneControlsVisible(not UI.showSceneControls)
    end)
end)

-- ============================================================
--  UTILITY FUNCTIONS
-- ============================================================

-- NightSceneAPI is accessed as a global from CET (abstract class with static methods).

print("[NightScene] CET init.lua loaded")

-- Public table, reachable from the CET console and other mods via
-- GetMod("NightScene"). Mod globals are sandboxed per mod, so this is the only
-- way the console can reach NightScene's functions.
return {
    --- Aim at an NPC and print which explicit entity/appearance it would use.
    ---     GetMod("NightScene").DebugExplicitMatch()
    DebugExplicitMatch = function() return ExplicitMatcher.DebugLookAt() end,

    --- NPC hiding experiments (temporary -- see modules/hide_test.lua).
    ---     GetMod("NightScene").DebugComponents()
    ---     GetMod("NightScene").DebugHide("components")
    ---     GetMod("NightScene").DebugShow()
    DebugComponents = function() return HideTest.Components() end,
    DebugHide = function(mode) return HideTest.Hide(mode) end,
    DebugShow = function() return HideTest.Show() end,
}
