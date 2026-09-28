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
    defaultCameraMode = 0,       -- 0=FirstPerson, 1=ThirdPerson, 2=Cinematic, 3=Free
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

-- Path to the config file (relative to the mod directory)
-- CET's working directory is bin/x64/, so we use the full relative path to the mod folder
Config.filePath = "plugins/cyber_engine_tweaks/mods/NightScene/config.json"

--- Load configuration from file, or create defaults if file doesn't exist.
function Config.Load()
    local file = io.open(Config.filePath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local success, data = pcall(json.decode, content)
        if success and type(data) == "table" then
            -- Merge loaded values with defaults (so new config keys get default values)
            Config.current = Config.MergeWithDefaults(data)
            print("[NightScene] Configuration loaded from file")
        else
            print("[NightScene] WARN: Config file corrupted, using defaults")
            Config.current = Config.DeepCopy(Config.defaults)
        end
    else
        print("[NightScene] No config file found, creating defaults")
        Config.current = Config.DeepCopy(Config.defaults)
        Config.Save()
    end

    -- Push config to Redscript framework
    Config.SyncToRedscript()
end

--- Save current configuration to file.
function Config.Save()
    local content = json.encode(Config.current)
    local file = io.open(Config.filePath, "w")
    if file then
        file:write(content)
        file:close()
        print("[NightScene] Configuration saved")
    else
        print("[NightScene] ERROR: Could not save config file")
    end

    -- Push updated config to Redscript framework
    Config.SyncToRedscript()
end

--- Push the current Lua config values into Redscript via individual setter calls.
function Config.SyncToRedscript()
    local success, err = pcall(function()
        Game['NightSceneAPI::SetEnabled;Bool'](Config.current.enabled)
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
        Game['NightSceneAPI::SetPlayerPosition;NightScenePlayerPosition'](Config.current.playerPosition)
        -- Commented out: SyncToRedscript now runs every frame the settings menu
        -- is open (so changes apply live), which spammed the log dozens of
        -- times per second.
        -- print("[NightScene] Config synced to Redscript")
    end)

    if not success then
        print("[NightScene] WARN: Could not sync config to Redscript: " .. tostring(err))
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
    print("[NightScene] Configuration reset to defaults")
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
