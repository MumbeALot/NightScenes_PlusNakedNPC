-- NightScene Framework - Animation Toggle Persistence
-- =======================================================
-- Tracks which registered animations are enabled/disabled for random
-- selection. Default: everything enabled. Persisted as a list of DISABLED
-- animation IDs only (compact, since most animations stay enabled).
--
-- Config is persisted to:
--   bin/x64/plugins/cyber_engine_tweaks/mods/NightScene/anim_toggles.json

local AnimToggles = {}

AnimToggles.filePath = "plugins/cyber_engine_tweaks/mods/NightScene/anim_toggles.json"

-- Set of disabled animation IDs: animId -> true
AnimToggles.disabled = {}

--- Load the disabled-animation set from disk (does not touch Redscript --
--- call ApplyToRedscript once animations are registered).
function AnimToggles.Load()
    local file = io.open(AnimToggles.filePath, "r")
    if not file then
        AnimToggles.disabled = {}
        print("[NightScene] No anim_toggles.json found, all animations enabled by default")
        return
    end

    local content = file:read("*all")
    file:close()

    local success, data = pcall(json.decode, content)
    if success and type(data) == "table" then
        local disabled = {}
        for _, id in ipairs(data) do
            disabled[id] = true
        end
        AnimToggles.disabled = disabled
        print("[NightScene] Loaded animation toggles: " .. tostring(#data) .. " disabled")
    else
        print("[NightScene] WARN: anim_toggles.json corrupted, all animations enabled")
        AnimToggles.disabled = {}
    end
end

--- Save the current disabled-animation set to disk.
function AnimToggles.Save()
    local list = {}
    for id, _ in pairs(AnimToggles.disabled) do
        table.insert(list, id)
    end

    local content = json.encode(list)
    local file = io.open(AnimToggles.filePath, "w")
    if file then
        file:write(content)
        file:close()
        print("[NightScene] Saved animation toggles: " .. tostring(#list) .. " disabled")
    else
        print("[NightScene] ERROR: Could not save anim_toggles.json")
    end
end

--- Push the loaded disabled set into the Redscript registry. Call this after
--- animations have been registered (AMMLoader.LoadAll), since it looks each
--- ID up by exact match.
function AnimToggles.ApplyToRedscript()
    local count = 0
    for id, _ in pairs(AnimToggles.disabled) do
        local ok, result = pcall(function()
            return Game['NightSceneAPI::SetAnimationEnabled;StringBool'](id, false)
        end)
        if ok and result then
            count = count + 1
        end
    end
    print("[NightScene] Applied animation toggles to Redscript: " .. count .. " disabled")
end

--- Set an animation's enabled state. Updates Redscript immediately (live
--- effect) and the local disabled set (persisted on the next Save()).
function AnimToggles.SetEnabled(id, enabled)
    if enabled then
        AnimToggles.disabled[id] = nil
    else
        AnimToggles.disabled[id] = true
    end

    pcall(function()
        Game['NightSceneAPI::SetAnimationEnabled;StringBool'](id, enabled)
    end)
end

function AnimToggles.IsEnabled(id)
    return not AnimToggles.disabled[id]
end

return AnimToggles
