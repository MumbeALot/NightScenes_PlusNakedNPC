-- NakedNPC - Configuration Module
-- =================================
-- Handles loading/saving persistent settings from a JSON file.

local Config = {}

local configPath = "data/config.json"
local defaults = {
    enabled = true,
    debugMode = false,
    showUI = true,
    meshSwapEnabled = true,
    stripHeadwear = true,
    stripAccessories = true,
    cleanupIntervalSeconds = 5.0,
    -- Body mesh path overrides (empty = use defaults from Redscript)
    bodyMeshOverrides = {
        female_average = "",
        male_average = "",
        male_big = ""
    }
}

local current = {}

-- Deep copy a table
local function deepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Merge loaded config with defaults (fills missing keys)
local function mergeWithDefaults(loaded)
    local result = deepCopy(defaults)
    if loaded then
        for k, v in pairs(loaded) do
            if type(v) == "table" and type(result[k]) == "table" then
                for k2, v2 in pairs(v) do
                    result[k][k2] = v2
                end
            else
                result[k] = v
            end
        end
    end
    return result
end

function Config.Load()
    local file = io.open(configPath, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local ok, loaded = pcall(json.decode, content)
        if ok and type(loaded) == "table" then
            current = mergeWithDefaults(loaded)
            print("[NakedNPC] Config loaded from " .. configPath)
        else
            print("[NakedNPC] Config parse error, using defaults")
            current = deepCopy(defaults)
        end
    else
        print("[NakedNPC] No config file found, using defaults")
        current = deepCopy(defaults)
    end
    return current
end

function Config.Save()
    local ok, encoded = pcall(json.encode, current)
    if ok then
        -- Ensure data directory exists
        -- CET doesn't support os.execute; directory must exist already
        local file = io.open(configPath, "w")
        if file then
            file:write(encoded)
            file:close()
            print("[NakedNPC] Config saved to " .. configPath)
        else
            print("[NakedNPC] ERROR: Could not write config file")
        end
    end
end

function Config.Get(key)
    if key then
        return current[key]
    end
    return current
end

function Config.Set(key, value)
    current[key] = value
end

function Config.GetBodyMeshOverride(bodyType)
    if current.bodyMeshOverrides and current.bodyMeshOverrides[bodyType] then
        local override = current.bodyMeshOverrides[bodyType]
        if override ~= "" then
            return override
        end
    end
    return nil
end

function Config.SetBodyMeshOverride(bodyType, path)
    if not current.bodyMeshOverrides then
        current.bodyMeshOverrides = {}
    end
    current.bodyMeshOverrides[bodyType] = path or ""
end

function Config.Reset()
    current = deepCopy(defaults)
    Config.Save()
end

return Config
