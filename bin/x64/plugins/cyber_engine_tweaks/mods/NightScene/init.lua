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

NightScene = {}

function NightScene.Print(...)
	print(...)
	spdlog.info(...)
end

-- Load modules safely (a failing module must not block event registration)
local ok, Config = pcall(require, "modules/config")
if not ok then
    NightScene.Print("[NightScene] ERROR loading config module: " .. tostring(Config))
    Config = { Load = function() end, Save = function() end, SyncToRedscript = function() end, current = { enabled = true } }
end

local ok2, UI = pcall(require, "modules/ui")
if not ok2 then
    NightScene.Print("[NightScene] ERROR loading UI module: " .. tostring(UI))
    UI = { Init = function() end, OnDraw = function() end, ToggleConfigMenu = function() end, ToggleAnimBrowser = function() end, SetSceneControlsVisible = function() end, showSceneControls = false }
end

local ok3, AMMLoader = pcall(require, "modules/amm_loader")
if not ok3 then
    NightScene.Print("[NightScene] ERROR loading AMM loader module: " .. tostring(AMMLoader))
    AMMLoader = { LoadAll = function() NightScene.Print("[NightScene] AMM Loader not available") end }
end

local ok4, Spawner = pcall(require, "modules/workspot_spawner")
if not ok4 then
    NightScene.Print("[NightScene] ERROR loading workspot spawner module: " .. tostring(Spawner))
    Spawner = { SpawnAndPlay = function() end, Cleanup = function() end }
end

local ok5, AnimToggles = pcall(require, "modules/anim_toggles")
if not ok5 then
    NightScene.Print("[NightScene] ERROR loading anim toggles module: " .. tostring(AnimToggles))
    AnimToggles = { Load = function() end, Save = function() end, ApplyToRedscript = function() end, SetEnabled = function() end, IsEnabled = function() return true end, disabled = {} }
end

local ok6, ExplicitMatcher = pcall(require, "modules/explicit_matcher")
if not ok6 then
    NightScene.Print("[NightScene] ERROR loading explicit matcher module: " .. tostring(ExplicitMatcher))
    ExplicitMatcher = { FindForNPC = function() return nil, { reason = "matcher failed to load" } end, DebugLookAt = function() end }
end

-- Scene camera: a dedicated camera entity driven every frame while a scene
-- runs. Four modes -- first person on the clone's head bone, third-person
-- orbit, cinematic presets, and free cam.
local okCam, FPCamera = pcall(require, "modules/fp_camera")
if not okCam then
    NightScene.Print("[NightScene] ERROR loading camera module: " .. tostring(FPCamera))
    FPCamera = {
        Spawn = function() end, OnUpdate = function() end, HandleInput = function() end,
        CycleMode = function() end, NextPreset = function() end, SetMode = function() end,
        Deactivate = function() end, Despawn = function() end,
        active = false, mode = 0, entityID = nil,
    }
end

-- Mod version. Single source of truth: the UI is handed this rather than
-- carrying its own copy, which is how the startup banner and the settings
-- window both drifted to a stale "0.1.0".
local modVersion = "0.2.9.1L"

-- Module-level state
local isInitialized = false
local isInGame = false

-- Clone head visibility tracking for the first-person camera (see onUpdate).
local lastCloneHeadEntityID = nil
local lastCloneHeadVisible = nil
local cloneHeadHideWarmup = nil
local headCheckTick = 0

-- Frames elapsed in the current scene, used to re-apply hiding periodically.
local sceneTick = 0

function NightScene.Enabled()   return Config.Get("enabled")   end
function NightScene.DebugMode() return Config.Get("debugMode") end

--------------------------------------------------------------------
-- A library of sorts of useful functions . Where should it all go ?
--------------------------------------------------------------------

function NightScene.DebugPrint(...)
	if debug and debug.print then
		debug.print(...)
		if debug.log then
			debug.log(...)
		end
	end
end

function NightScene.DebugLog(...)
	if debug and debug.log then
		debug.log(...)
	end
end

function NightScene.DebugTrace(...)
	if debug and debug.log and NightScene.DebugMode() then
		debug.log(...)
    -- else
	--	debug.log("debugMode off: " .. ...)
	end
end

function NightScene.Log(...)
	spdlog.info(...)
end

function NightScene.Trace(...)
	if NightScene.DebugMode() then
		spdlog.info(...)
	end
end

function NightScene.TableSize(table)
	local result = 0
	if table then
		if type(table) == 'table' then
	        for _, value in pairs(table) do
	            result = result + 1
	        end
		else
        	NightScene.Print("[NightScene] TableSize type=" .. tostring(type(table)))
			result = -1
		end
	else
		result = 0
	end
	-- NightScene.Trace("[NightScene] TableSize=" .. tostring(result))
	return result
end

-- duplicated from anim_toggles.lua and adpted for tables with non numeric keys.
-- I don't know how to avoid duplication from NakedNPC also.

local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
        i = i + 1
        if a[i] == nil then return nil
        else return a[i], t[a[i]]
        end
    end
    return iter
end

-- Expect table contains only table, string and numbers as values...

function NightScene.TableSort(list)
    local i = 0
    local parts = {}
    for key, value in pairsByKeys(list) do
        i = i + 1
        if type(value) ~= 'table' then
            if type(value) == 'string' then
                parts[i] = '"' .. tostring(key) .. '": "' .. tostring(value) .. '"'
            else
                parts[i] = '"' .. tostring(key) .. '": ' .. tostring(value)
            end
        else
            local sub = {}
            sub = NightScene.TableSort(value)
            parts[i] = '"' .. tostring(key) .. '": {\n\t\t' .. table.concat(sub, ',\n\t\t') .. '\n\t}'
        end
        -- NightScene.Trace("[NightScene] TableSort parts[" .. tostring(i) .. "]='" .. tostring(parts[i]) .. "'")
    end
    return parts
end

function NightScene.EncodeSorted(list)
    if not list then return nil end
    -- NightScene.DebugTrace("[NightScene] EncodeSorted list ", list, " of size ", NightScene.TableSize(list))

    -- Written by hand rather than json.encode: that puts all ids on a single line,
    -- which is unreadable and undiffable if you ever want to
    -- edit the file directly. Sorted so entries stay put between saves.

    local parts = NightScene.TableSort(list)
    -- NightScene.DebugTrace("[NightScene] EncodeSorted parts ", parts)

    local content = "{\n\t" .. table.concat(parts, ",\n\t") .. "\n}\n"
    -- NightScene.DebugTrace("[NightScene] EncodeSorted content ", content)

    -- Do not write an empty config, it has to be an error
    if NightScene.TableSize(parts) == 0 then
        NightScene.Trace("[NightScene] EncodeSorted ERROR: Could not sort and encode the config file")
        content = nil 
    end
	return content
end

-- ============================================================
--  CET LIFECYCLE CALLBACKS
-- ============================================================

--- Called when CET initializes the mod.
registerForEvent("onInit", function()
    NightScene.Print("[NightScene] ========================================")
    NightScene.Print("[NightScene]  NightScene Framework v" .. modVersion .. " (CET)")
    NightScene.Print("[NightScene] ========================================")

    dofile("debug.lua")

    -- Load configuration
    Config.Load()
    AnimToggles.Load()

    -- Initialize UI with config + anim toggle references
    UI.Init(Config, AnimToggles, modVersion)

    -- Mouse look for the scene camera. Only consumed while the camera is
    -- active, so normal play is unaffected.
    Observe("PlayerPuppet", "OnAction", function(_self, action)
        if not FPCamera.active then return end
        pcall(function()
            local actionName = Game.NameToString(action:GetName(action))
            local actionType = action:GetType(action).value
            FPCamera.HandleInput(actionName, actionType, action)
        end)
    end)

    isInitialized = true
    NightScene.Print("[NightScene] CET module initialized")
    if NightScene.Enabled()   then NightScene.Print("[NightScene] enabled")  else NightScene.Print("[NightScene] disabled")  end
    if NightScene.DebugMode() then NightScene.Print("[NightScene] debug on") else NightScene.Print("[NightScene] debug off") end
end)

--- Called when CET shuts down.
registerForEvent("onShutdown", function()
    -- Save config on exit
    if isInitialized then
        Config.Save()
    end
    pcall(FPCamera.Despawn)
    NightScene.Print("[NightScene] CET module shut down")
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
    if Spawner then pcall(Spawner.OnUpdate) end	-- To avoid filling the log if the mod crashes

    -- Check for a pending workspot spawn. Set by EVERY scene start (defeat,
    -- NPC defeat, and normal hotkey interaction).
    pcall(function()
        local hasPending = Game['NightSceneAPI::HasPendingWorkspotSpawn;']()
        if hasPending then
            Game['NightSceneAPI::ClearPendingWorkspotSpawn;']()
            NightScene.Print("[NightScene] Scene started, spawning workspot...")
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

    -- Drive the scene camera. Spawns on first frame of a scene, then updates
    -- every frame; torn down by the cleanup block below when the scene ends.
    pcall(function()
        if not Game['NightSceneAPI::IsSceneActive;']() then return end

        local player = Game.GetPlayer()
        if not player then return end

        local mgr = Game['NightSceneServices::Get;']():SceneManager()
        local scene = mgr:GetActiveScene()
        if not scene then return end

        local originYaw = 0.0
        if scene.sceneOrientation then
            originYaw = scene.sceneOrientation:ToEulerAngles().yaw
        end

        -- In first person the camera sits inside the clone's head, so its head
        -- has to be hidden; every other mode shows it. Only touched when the
        -- mode or the clone actually changes -- this runs every frame.
        if Spawner.vClone then
            local headVisible = (FPCamera.mode ~= 0)
            if lastCloneHeadEntityID ~= Spawner.vCloneID or lastCloneHeadVisible ~= headVisible then
                lastCloneHeadEntityID = Spawner.vCloneID
                lastCloneHeadVisible = headVisible
                Spawner.SetCloneHeadVisible(Spawner.vClone, headVisible)
                -- Head meshes stream in over several frames, so re-apply for a
                -- short while or late arrivals show up inside the camera.
                if not headVisible then cloneHeadHideWarmup = 60 end
            elseif not headVisible then
                if cloneHeadHideWarmup and cloneHeadHideWarmup > 0 then
                    cloneHeadHideWarmup = cloneHeadHideWarmup - 1
                    Spawner.SetCloneHeadVisible(Spawner.vClone, false)
                elseif (headCheckTick % 30) == 0 then
                    -- Mesh swaps (NakedNPC, appearance changes) can restore
                    -- hidden components later; catch those periodically.
                    Spawner.SetCloneHeadVisible(Spawner.vClone, false)
                end
                headCheckTick = headCheckTick + 1
            end
        else
            lastCloneHeadEntityID = nil
            lastCloneHeadVisible = nil
            cloneHeadHideWarmup = nil
            headCheckTick = 0
        end

        -- Keep the real V hidden. Hiding once at scene start hasn't held: the
        -- outfit system, appearance changes and streaming all rebuild mesh
        -- components afterwards, and each rebuild brings V back. Rather than
        -- guess which one is responsible, re-apply periodically for as long as
        -- the scene runs. Quiet, or it would flood the log.
        sceneTick = sceneTick + 1
        if (sceneTick % 30) == 0 then
            pcall(Spawner.HidePlayer)
        end

        if not FPCamera.entityID then
            -- Start each scene in the configured mode. The Lua camera is what
            -- actually drives the view, so without this the setting only ever
            -- reached Redscript's scene.cameraMode and nothing acted on it --
            -- every scene opened in first person regardless.
            FPCamera.SetMode(Config.current.defaultCameraMode or 0)

            local yaw = player:GetWorldOrientation():ToEulerAngles().yaw
            FPCamera.Spawn(player:GetWorldPosition(), yaw)
        end

        FPCamera.OnUpdate(nil, nil, Spawner.vClone, scene.scenePosition, originYaw)
    end)

    -- Auto-cleanup: detect when Redscript scene ends (auto-advance timer expired)
    -- and trigger Lua cleanup if spawner still has active entities
    pcall(function()
        if Spawner.workspotEntity or Spawner.vClone then
            local isActive = Game['NightSceneAPI::IsSceneActive;']()
            if not isActive then
                NightScene.Print("[NightScene] Scene ended (auto-advance), triggering Lua cleanup...")
                sceneTick = 0
                pcall(FPCamera.Despawn)
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
        NightScene.Print("[NightScene] Animations have to load, waiting 3s for initialization of the framework...")
        return
    end

    -- Wait 3 seconds for ScriptableSystem to fully attach
    if os.clock() - playerDetectedTime < 3.0 then
        return
    end

    waitingToLoad = false
    NightScene.Print("[NightScene] Loading animation packs...")

    local loadSuccess, loadErr = pcall(function()
        AMMLoader.LoadAll()
    end)
    if not loadSuccess then
        NightScene.Print("[NightScene] AMM Loader error: " .. tostring(loadErr))
    end

    local postOk, postCount = pcall(Game['NightSceneAPI::GetAnimationCount;'])
    NightScene.Print("[NightScene] Registered animations: " .. tostring(postCount))
    lastLoadedCount = postCount or 0

    -- Now that ScriptableSystem is confirmed ready, sync config from Lua to Redscript
    pcall(function()
        Config.SyncToRedscript()
        NightScene.Print("[NightScene] Config synced to Redscript (post-load)")
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
        NightScene.Print("[NightScene] Interaction error: " .. tostring(err))
    end
end)

-- Cancel current scene
registerHotkey("ns_cancel_scene", "NightScene: Cancel Scene", function()
    if not isInGame then return end

    pcall(function()
        local isActive = Game['NightSceneAPI::IsSceneActive;']()
        if isActive then
            pcall(FPCamera.Despawn)
            Spawner.Cleanup()
            Game['NightSceneAPI::StopScene;']()
            UI.SetSceneControlsVisible(false)
            NightScene.Print("[NightScene] Scene stopped")
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
            NightScene.Print("[NightScene] No other compatible animation to switch to")
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
            NightScene.Print("[NightScene] Speed up")
        end
    end)
end)

-- Speed down
registerHotkey("ns_speed_down", "NightScene: Speed Down", function()
    if not isInGame then return end

    pcall(function()
        if NightSceneAPI.IsSceneActive() then
            NightSceneAPI.SetSpeed(0.75) -- TODO: track current speed in Lua
            NightScene.Print("[NightScene] Speed down")
        end
    end)
end)

-- Step through the interactive camera modes: first person -> third person ->
-- free cam. Cinematic is entered with the Next Camera Angle key below.
registerHotkey("ns_camera_mode", "NightScene: Cycle Camera Mode", function()
    if not isInGame then return end

    pcall(function()
        local mode = FPCamera.CycleMode()
        Game['NightSceneAPI::CycleCameraMode;']()
        NightScene.Print("[NightScene] Camera mode -> " .. tostring(mode))
    end)
end)

-- Enter cinematic mode, then step through the preset angles.
registerHotkey("ns_camera_preset", "NightScene: Next Camera Angle", function()
    if not isInGame then return end

    pcall(function()
        local preset = FPCamera.NextPreset()
        Game['NightSceneAPI::NextCameraPreset;']()
        NightScene.Print("[NightScene] Camera angle -> " .. tostring(preset))
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

NightScene.Log("")
NightScene.Print("[NightScene] CET init.lua loaded")

-- Public table, reachable from the CET console and other mods via
-- GetMod("NightScene"). Mod globals are sandboxed per mod, so this is the only
-- way the console can reach NightScene's functions.
return {
    --- Aim at an NPC and print which explicit entity/appearance it would use.
    ---     GetMod("NightScene").DebugExplicitMatch()
    DebugExplicitMatch = function() return ExplicitMatcher.DebugLookAt() end,

    --- Recover from a scene that left V stuck -- invulnerable, unable to move,
    --- phone or combat blocked. Clears every restriction the defeat system can
    --- apply, stops any active scene, and makes V visible again.
    ---     GetMod("NightScene").EmergencyUnlock()
    EmergencyUnlock = function()
        local ok, err = pcall(Game['NightSceneAPI::EmergencyUnlock;'])
        if ok then
            NightScene.Print("[NightScene] EmergencyUnlock: restrictions and invulnerability cleared")
        else
            NightScene.Print("[NightScene] EmergencyUnlock failed: " .. tostring(err))
        end
        -- The visual side lives in Lua, so undo it here too.
        pcall(Spawner.ShowPlayer)
        pcall(Spawner.Cleanup)
    end,

    --- Hide or restore the real V. Mostly an escape hatch: if a scene ever
    --- ends badly and leaves V invisible, DebugShowV() puts them back.
    ---     GetMod("NightScene").DebugHideV()
    ---     GetMod("NightScene").DebugShowV()
    DebugHideV = function()
        local added, total = Spawner.HidePlayer()
        NightScene.Print("[NightScene] Hid V: " .. tostring(added) .. " new, "
            .. tostring(total) .. " total components")
    end,
    DebugShowV = function()
        NightScene.Print("[NightScene] Restored V: " .. tostring(Spawner.ShowPlayer()) .. " components")
    end,

    --- Show or hide the V clone's head during a scene. It is hidden
    --- automatically in first person, where the camera sits inside it.
    ---     GetMod("NightScene").DebugCloneHead(true)
    DebugCloneHead = function(visible)
        if not Spawner.vClone then
            NightScene.Print("[NightScene] No V clone -- start a scene first")
            return
        end
        return Spawner.SetCloneHeadVisible(Spawner.vClone, visible ~= false)
    end,
}
