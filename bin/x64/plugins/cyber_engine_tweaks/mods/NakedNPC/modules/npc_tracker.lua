-- NakedNPC - NPC Tracker Module
-- ===============================
-- Tracks stripped NPCs on the Lua side for UI display and cleanup.
-- The authoritative state is in the Redscript NakedNPCSystem;
-- this module mirrors it for CET-side access.

local NPCTracker = {}

-- Tracked NPCs: keyed by EntityID hash string
-- Value: { entityRef, appearance, timestamp, bodyType, componentCount }
local trackedNPCs = {}
local stats = {
    totalStripped = 0,
    totalRestored = 0,
    totalCleanups = 0
}

-- -------------------------------------------------------
--  INIT
-- -------------------------------------------------------

function NPCTracker.Init()
    trackedNPCs = {}
    stats = { totalStripped = 0, totalRestored = 0, totalCleanups = 0 }
    print("[NakedNPC] NPC Tracker initialized")
end

-- -------------------------------------------------------
--  TRACKING
-- -------------------------------------------------------

--- Convert EntityID to a string key for our table.
local function entityIDToKey(entityID)
    return tostring(entityID.hash)
end

--- Track a newly stripped NPC.
--- @param entity - game entity reference
--- @param appearanceName string - the _naked appearance that was requested
--- @param savedComponents table|nil - saved component states for restore (optional)
function NPCTracker.Track(entity, appearanceName, savedComponents)
    if not entity then return end
    local key = entityIDToKey(entity:GetEntityID())
    trackedNPCs[key] = {
        entityRef = entity,
        entityID = entity:GetEntityID(),
        appearance = appearanceName or "unknown",
        originalAppearance = appearanceName,  -- use passed value, not GetCurrentAppearanceName()
        timestamp = os.clock(),
        bodyType = "detecting...",
        componentCount = 0,
        savedComponents = savedComponents
    }
    stats.totalStripped = stats.totalStripped + 1
end

--- Get saved components for an entity (for restore fallback).
function NPCTracker.GetSavedComponents(entityID)
    local key = entityIDToKey(entityID)
    if trackedNPCs[key] then
        return trackedNPCs[key].savedComponents
    end
    return nil
end


--- Get the original appearance name saved at strip time.
--- Used by RestoreEntity to reload the correct appearance.
--- @param entityID - EntityID object
--- @return string|nil
function NPCTracker.GetOriginalAppearance(entityID)
    local key = entityIDToKey(entityID)
    if trackedNPCs[key] then
        return trackedNPCs[key].originalAppearance
    end
    return nil
end

--- Get the name of the repurposed genital component for an entity.
--- Used by SwitchGenitalState to find the component by name instead of guessing.
--- @param entityID - EntityID object
--- @return string|nil
function NPCTracker.GetGenitalComponentName(entityID)
    local key = entityIDToKey(entityID)
    if not trackedNPCs[key] then return nil end
    local saved = trackedNPCs[key].savedComponents
    if not saved then return nil end
    for _, entry in ipairs(saved) do
        if entry.isGenital then
            return entry.name
        end
    end
    return nil
end


--- Remove tracking for an entity (after restore).
--- @param entityID - EntityID object
function NPCTracker.Untrack(entityID)
    local key = entityIDToKey(entityID)
    if trackedNPCs[key] then
        trackedNPCs[key] = nil
        stats.totalRestored = stats.totalRestored + 1
    end
end

--- Check if an entity is tracked (by entity reference).
function NPCTracker.IsTracked(entity)
    if not entity then return false end
    local key = entityIDToKey(entity:GetEntityID())
    return trackedNPCs[key] ~= nil
end

--- Check if an entity is tracked (by EntityID).
function NPCTracker.IsTrackedByID(entityID)
    local key = entityIDToKey(entityID)
    return trackedNPCs[key] ~= nil
end

-- -------------------------------------------------------
--  QUERIES
-- -------------------------------------------------------

--- Get count of currently tracked (stripped) NPCs.
function NPCTracker.GetCount()
    local count = 0
    for _ in pairs(trackedNPCs) do
        count = count + 1
    end
    return count
end

--- Get all tracked NPCs (for UI display).
--- @return table - array of { key, data } pairs
function NPCTracker.GetAll()
    local result = {}
    for key, data in pairs(trackedNPCs) do
        table.insert(result, { key = key, data = data })
    end
    table.sort(result, function(a, b) return a.data.timestamp > b.data.timestamp end)
    return result
end

--- Get stats table.
function NPCTracker.GetStats()
    return {
        currentlyStripped = NPCTracker.GetCount(),
        totalStripped = stats.totalStripped,
        totalRestored = stats.totalRestored,
        totalCleanups = stats.totalCleanups
    }
end

-- -------------------------------------------------------
--  CLEANUP
-- -------------------------------------------------------

--- Remove entries for despawned entities.
--- Called periodically from init.lua onUpdate.
function NPCTracker.Cleanup()
    local toRemove = {}

    for key, data in pairs(trackedNPCs) do
        local entity = data.entityRef
        if not entity or not Game.FindEntityByID(data.entityID) then
            table.insert(toRemove, key)
        end
    end

    for _, key in ipairs(toRemove) do
        trackedNPCs[key] = nil
        stats.totalCleanups = stats.totalCleanups + 1
    end
end

return NPCTracker