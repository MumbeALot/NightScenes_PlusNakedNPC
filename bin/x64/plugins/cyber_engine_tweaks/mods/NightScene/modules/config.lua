-- NightScene Framework - Configuration Module
-- ==============================================
-- Handles loading/saving configuration to a JSON file,
-- and syncing config values with the Redscript framework.
--
-- Config is persisted to:
--   bin/x64/plugins/cyber_engine_tweaks/mods/NightScene/config.json

local Config = {}

-- Default configuration values (mirrors NightSceneConfig.reds)
Config.defaults = {
    enabled = true,
    debugMode = false,           -- For at least trace log functions
    defaultCameraMode = 0,       -- 0=FirstPerson, 1=ThirdPerson, 2=Cinematic, 3=Free
    keepHairInFP = false,        -- true = keep the clone's hair visible in first person
    defeatEnabled = true,
    defeatHealthThreshold = 0.15, -- 15% health triggers defeat (leaves margin so burst damage can't slip past the 0.2s poll before reaching 0 HP)
    npcInteractionEnabled = true,
    npcInteractionRange = 5.0,   -- meters
    autoAdvanceStages = true,
    defaultSpeed = 1.0,
    stripEquipment = true,
    npcGenderFilter = 0,         -- 0=Any, 1=Male, 2=Female
    playerPosition = 0,          -- 0=Dom, 1=Sub (only affects same-gender ff scenes)

    -- Defeat extras
    defeatGracePeriod = 12.0,    -- Seconds before enemies re-aggro after defeat scene (gives a real escape window combined with the 20m teleport)
    defeatCooldown = 30.0,       -- Seconds before defeat can trigger again
    defeatMoneyLoss = 0.0,       -- Money lost on defeat (0 = disabled)
    defeatMoneyLossIsPercent = false, -- true = percentage, false = flat eddies
    defeatFatalMode = false,     -- true = V actually flatlines when a defeat scene ends

    -- Hotkeys (CET key codes)
    -- hotkeyInteract = "U",        -- Start interaction with looked-at NPC
    -- hotkeyCancel = "End",        -- Cancel current scene
    -- hotkeyNextStage = "PageDown", -- Advance to next stage
    -- hotkeyPrevStage = "PageUp",  -- Go back to previous stage
    -- hotkeySpeedUp = "Multiply",  -- Increase speed (numpad *)
    -- hotkeySpeedDown = "Divide",  -- Decrease speed (numpad /)
    -- hotkeyCameraMode = "Numpad0", -- Cycle camera mode
    -- hotkeyCameraPreset = "Numpad1", -- Cycle camera preset (cinematic)
}

-- Active configuration (loaded from file or defaults)
Config.current = {}

-- Path to the config file.
--
-- CET's working directory for a mod is the MOD'S OWN FOLDER, not bin/x64 as
-- the old comment here claimed. The previous value --
--   "plugins/cyber_engine_tweaks/mods/NightScene/config.json"
-- -- therefore resolved to
--   mods/NightScene/plugins/cyber_engine_tweaks/mods/NightScene/config.json
-- and io.open(path, "w") does NOT create missing directories, so on any install
-- where that nested tree didn't already exist the save silently failed with
-- "Could not save config file" and settings never persisted. This is why
-- saving appeared broken for most users.
Config.filePath = "config.json"

-- Where saves used to land. Read once on load so existing settings survive the
-- move; never written to again.
Config.legacyFilePath = "plugins/cyber_engine_tweaks/mods/NightScene/config.json"

--- Load configuration from file, or create defaults if file doesn't exist.
function Config.Load()
    local file = io.open(Config.filePath, "r")

    -- Fall back to the old nested location so anyone who did manage to save
    -- there keeps their settings. The next save writes to the new path.
    local migrated = false
    if not file then
        file = io.open(Config.legacyFilePath, "r")
        migrated = (file ~= nil)
    end

    if file then
        local content = file:read("*all")
        file:close()

        local success, data = pcall(json.decode, content)
        if success and type(data) == "table" then
            -- Merge loaded values with defaults (so new config keys get default values)
            Config.current = Config.MergeWithDefaults(data)
            if migrated then
                NightScene.Print("[NightScene] Configuration migrated from the old nested path")
                Config.Save()
            else
                NightScene.Print("[NightScene] Configuration loaded from file")
            end
        else
            NightScene.Print("[NightScene] WARN: Config file corrupted, using defaults")
            Config.current = Config.DeepCopy(Config.defaults)
        end
    else
        NightScene.Print("[NightScene] No config file found, creating defaults")
        Config.current = Config.DeepCopy(Config.defaults)
        Config.Save()
    end

    -- Push config to Redscript framework
    Config.SyncToRedscript()
end

--- Save current configuration to file.
function Config.Save()
    local content = NightScene.EncodeSorted(Config.current)
    -- NightScene.DebugTrace("[NightScene] Save sorted: ", content)

    if content then
        -- io.open returns the reason as its second result. The previous version
        -- re-opened the file to print it, which leaked a handle and printed the
        -- file object or nil -- never the actual error.
        local file, err = io.open(Config.filePath, "w")
        if file then
            file:write(content)
            file:close()
            NightScene.Print("[NightScene] Configuration saved")
        else
            NightScene.Print("[NightScene] ERROR: Could not save config file: " .. tostring(err))
        end
    else
        NightScene.Print("[NightScene] ERROR: Could not encode the config file")
    end

    -- Push updated config to Redscript framework
    Config.SyncToRedscript()
end

--- Push the current Lua config values into Redscript via individual setter calls.
function Config.SyncToRedscript()
    local success, err = pcall(function()
        Game['NightSceneAPI::SetEnabled;Bool'](Config.current.enabled)
        Game['NightSceneAPI::SetDebugMode;Bool'](Config.current.debugMode)
        Game['NightSceneAPI::SetDefeatEnabled;Bool'](Config.current.defeatEnabled)
        Game['NightSceneAPI::SetDefeatHealthThreshold;Float'](Config.current.defeatHealthThreshold)
        Game['NightSceneAPI::SetNpcInteractionEnabled;Bool'](Config.current.npcInteractionEnabled)
        Game['NightSceneAPI::SetDefaultSpeed;Float'](Config.current.defaultSpeed)
        Game['NightSceneAPI::SetStripEquipment;Bool'](Config.current.stripEquipment)
        Game['NightSceneAPI::SetAutoAdvanceStages;Bool'](Config.current.autoAdvanceStages)
        Game['NightSceneAPI::SetDefeatGracePeriod;Float'](Config.current.defeatGracePeriod)
        Game['NightSceneAPI::SetDefeatCooldown;Float'](Config.current.defeatCooldown)
        Game['NightSceneAPI::SetDefeatMoneyLoss;Float'](Config.current.defeatMoneyLoss)
        Game['NightSceneAPI::SetDefeatMoneyLossIsPercent;Bool'](Config.current.defeatMoneyLossIsPercent)
        Game['NightSceneAPI::SetDefeatFatalMode;Bool'](Config.current.defeatFatalMode or false)
        Game['NightSceneAPI::SetPlayerPosition;NightScenePlayerPosition'](Config.current.playerPosition)
        Game['NightSceneAPI::SetDefaultCameraMode;NightSceneCameraMode'](Config.current.defaultCameraMode)
        -- These two were missing, which is why the gender filter and
        -- interaction range sliders in the settings menu did nothing.
        Game['NightSceneAPI::SetNpcGenderFilter;NightSceneGender'](Config.current.npcGenderFilter)
        Game['NightSceneAPI::SetNpcInteractionRange;Float'](Config.current.npcInteractionRange)
        -- Commented out: SyncToRedscript now runs every frame the settings menu
        -- is open (so changes apply live), which spammed the log dozens of
        -- times per second.
        -- NightScene.Print("[NightScene] Config synced to Redscript")
    end)

    if not success then
        NightScene.Print("[NightScene] WARN: Could not sync config to Redscript: " .. tostring(err))
    end
end

--- Merge loaded config with defaults (adds any new keys from defaults).
function Config.MergeWithDefaults(loaded)
    local merged = Config.DeepCopy(Config.defaults)
    for key, value in pairs(loaded) do
        if merged[key] ~= nil then
            merged[key] = value
        end
    end
    return merged
end

--- Deep copy a table.
function Config.DeepCopy(orig)
    local copy = {}
    for key, value in pairs(orig) do
        if type(value) == "table" then
            copy[key] = Config.DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

--- Reset config to defaults.
function Config.Reset()
    Config.current = Config.DeepCopy(Config.defaults)
    Config.Save()
    NightScene.Print("[NightScene] Configuration reset to defaults")
end

--- Get a config value by key.
function Config.Get(key)
    return Config.current[key]
end

--- Set a config value by key and save.
function Config.Set(key, value)
    if Config.current[key] ~= nil then
        Config.current[key] = value
        Config.Save()
    end
end

return Config
