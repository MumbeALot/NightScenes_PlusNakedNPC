-- NakedNPC - CET Main Entry Point
-- =================================
-- Universal Naked NPC Appearances Mod v0.3.0
--
-- ARCHITECTURE (two-step appearance reload cycle):
-- 1. Trigger: _naked ScheduleAppearanceChange OR UI Strip button
-- 2. Flag entity in pendingNaked table (step=0)
-- 3. Schedule "Cycle" appearance → forces component reload (step=1)
-- 4. OnRequestComponents fires for "Cycle" → schedule back to original (step=2)
-- 5. OnRequestComponents fires for original → DO MESH SWAPS + STRIP HERE
--
-- RESTORE ARCHITECTURE:
-- 1. Trigger: non-naked ScheduleAppearanceChange on a tracked entity
-- 2. Flag entity in pendingRestore table
-- 3. Schedule original appearance via deferred queue (0.15s delay)
-- 4. Hook sees pendingRestore flag → skips re-stripping
-- 5. Appearance reloads cleanly with all original components
--
-- Mesh swaps ONLY work during OnRequestComponents (component loading phase).
-- This two-step cycle is the same pattern CET NPC Body Tweaks and AMM use.

local modVersion = "0.4.1"
local modName = "NakedNPC"

local Config = require("modules/config")
local Stripper = require("modules/stripper")
local BodyManager = require("modules/body_manager")
local NPCTracker = require("modules/npc_tracker")
local UI = require("modules/ui")
local EquipmentEx = require("modules/equipment_ex")

local initialized = false
local drawWindow = false
local system = nil
local cleanupTimer = 0.0

-- Pending naked table: entities going through the two-step strip cycle
-- Key = entityID hash string (ULL stripped)
-- Value = { entityRef, originalAppearance, step, timestamp }
local pendingNaked = {}

-- Pending restore table: entities going through the restore cycle
-- Key = entityID hash string
-- Value = true (just a flag to prevent re-stripping during restore)
local pendingRestore = {}

-- Deferred schedule queue: appearance changes that need a time delay
-- Each entry: { entityRef, appName, afterTime }
local deferredSchedule = {}

-- Pending genital state: when StripForScene is called with a genitalState,
-- store it here so OnRequestComponents can pass it to StripDuringLoad
-- Key = entityID key, Value = "soft" or "erect"
local pendingGenitalState = {}

local function entityIDKey(entityID)
    return tostring(entityID.hash):gsub("ULL$", "")
end

-- -------------------------------------------------------
--  CORE: Initiate the naked reload cycle for an entity
-- -------------------------------------------------------
local function initiateNakedCycle(entity)
    if not entity then return false end
    if not entity:IsA(CName.new("ScriptedPuppet")) then return false end

    local eid = entity:GetEntityID()
    local key = entityIDKey(eid)

    -- Skip if already in cycle, already tracked, or being restored
    if pendingNaked[key] then return false end
    if pendingRestore[key] then return false end
    if NPCTracker.IsTrackedByID(eid) then return false end

    local currentApp = Game.NameToString(entity:GetCurrentAppearanceName())
    if currentApp == "" or currentApp == "None" then return false end

    pendingNaked[key] = {
        entityRef = entity,
        originalAppearance = currentApp,
        step = 0,
        timestamp = os.clock()
    }

    print("[NakedNPC] Initiating naked cycle for: " .. currentApp .. " (key=" .. key .. ")")

    pendingNaked[key].step = 1
    -- print("[NakedNPC] Deferred firing ScheduleAppearanceChange: " .. d.appName .. " for key=" .. (d.restoreKey or "?"))
    entity:PrefetchAppearanceChange(CName.new("Cycle"))
    entity:ScheduleAppearanceChange(CName.new("Cycle"))

    return true
end

-- -------------------------------------------------------
--  CORE: Initiate the restore cycle for an entity
-- -------------------------------------------------------
local function initiateRestoreCycle(entity)
    if not entity then return false end

    local eid = entity:GetEntityID()
    local key = entityIDKey(eid)

    local originalApp = NPCTracker.GetOriginalAppearance(eid)
    if not originalApp or originalApp == "" or originalApp == "None" then
        print("[NakedNPC] Restore: no saved appearance for " .. key)
        -- Fallback: just untrack, game will handle appearance naturally
        NPCTracker.Untrack(eid)
        return false
    end

    print("[NakedNPC] Initiating restore cycle for: " .. originalApp .. " (key=" .. key .. ")")

    -- Untrack BEFORE scheduling so the hook doesn't try to restore again
    NPCTracker.Untrack(eid)

    -- Flag as pending restore so OnRequestComponents skips re-stripping
    pendingRestore[key] = true

    -- Use deferred schedule (same 0.15s delay as strip cycle step 2)
    -- This gives the game time to process any in-flight appearance changes
    table.insert(deferredSchedule, {
        entityRef = entity,
        appName = originalApp,
        afterTime = os.clock() + 0.15,
        isRestore = true,
        restoreKey = key
    })

    return true
end

-- -------------------------------------------------------
--  PUBLIC API
-- -------------------------------------------------------

NakedNPC = {}

function NakedNPC.Strip(entity)
    if not initialized or not entity then return false end
    local cycleStarted = initiateNakedCycle(entity)
    if not cycleStarted then
        return Stripper.StripEntity(entity)
    end
    return true
end

function NakedNPC.Restore(entity)
    if not initialized or not entity then return false end
    return initiateRestoreCycle(entity)
end

function NakedNPC.IsStripped(entity)
    if not initialized or not entity then return false end
    return NPCTracker.IsTracked(entity)
end

--- Strip an NPC for a NightScene animation.
-- function NakedNPC.StripForScene(entity, genitalState)
--     if not initialized or not entity then return false end

--     if NPCTracker.IsTracked(entity) then
--         if genitalState then
--             Stripper.SwitchGenitalState(entity, genitalState)
--         end
--         return true
--     end

--     local eid = entity:GetEntityID()
--     local key = entityIDKey(eid)
--     if genitalState then
--         pendingGenitalState[key] = genitalState
--     end

--     local cycleStarted = initiateNakedCycle(entity)
--     if not cycleStarted then
--         return Stripper.StripEntity(entity, genitalState)
--     end
--     return true
-- end

function NakedNPC.StripForScene(entity, genitalState)
    if not initialized or not entity then return false end

    local eid = entity:GetEntityID()
    local key = entityIDKey(eid)

    -- Already stripped via full cycle — just switch genital state
    if NPCTracker.IsTracked(entity) then
        if genitalState then
            Stripper.SwitchGenitalState(entity, genitalState)
        end
        return true
    end

    -- Already mid-cycle — just update genital state
    if pendingNaked[key] then
        if genitalState then
            pendingGenitalState[key] = genitalState
        end
        print("[NakedNPC] StripForScene: cycle already in progress for " .. key)
        return true
    end

    -- Store genital state for OnRequestComponents step 2
    if genitalState then
        pendingGenitalState[key] = genitalState
    end

    -- Always try cycle first — DO NOT fall back to StripEntity for scene strips
    -- StripEntity tracks the NPC which would block the cycle from starting
    local cycleStarted = initiateNakedCycle(entity)
    if not cycleStarted then
        print("[NakedNPC] StripForScene: cycle failed to start for " .. key .. " (appearance empty or being restored?)")
        -- Only fall back to StripEntity if truly unable to cycle
        -- Don't track via NPCTracker here to avoid blocking future cycle attempts
        return false
    end
    return true
end

--- Strip Clone V's clothing directly, bypassing the appearance-cycle system.
-- Clone V (Character.TPP_Player_Cutscene_Male/Female) always reports an empty
-- GetCurrentAppearanceName(), so initiateNakedCycle (used by StripForScene)
-- can never succeed on it. StripEntity's immediate component-toggle mode
-- doesn't need an appearance name at all, and stripper.lua already has
-- dedicated Clone V handling (isCloneV/isCloneVBodyComponent) for it.
-- Unlike real NPCs, Clone V is a one-time throwaway entity despawned right
-- after the scene, so there's no future-cycle concern with using this path.
function NakedNPC.StripCloneV(entity, genitalState)
    if not initialized or not entity then return false end
    return Stripper.StripEntity(entity, genitalState)
end

--- Restore an NPC after a NightScene scene ends.
function NakedNPC.RestoreFromScene(entity)
    if not initialized or not entity then return false end

    local eid = entity:GetEntityID()
    local key = entityIDKey(eid)
    local originalApp = NPCTracker.GetOriginalAppearance(eid)

    NPCTracker.Untrack(eid)
    pendingNaked[key] = nil
    pendingRestore[key] = true
    pendingGenitalState[key] = nil

    if originalApp and originalApp ~= "" and originalApp ~= "None" then
        -- Schedule to a dummy appearance first to force OnRequestComponents
        -- then immediately back to original — same trick as the strip cycle
        entity:PrefetchAppearanceChange(CName.new("__NakedNPC_Restore__"))
        entity:ScheduleAppearanceChange(CName.new("__NakedNPC_Restore__"))

        -- Then schedule back to original after short delay
        table.insert(deferredSchedule, {
            entityRef = entity,
            appName = originalApp,
            afterTime = os.clock() + 0.15,
            isRestore = true,
            restoreKey = key
        })
        print("[NakedNPC] RestoreFromScene: two-step restore -> " .. originalApp)
    end

    return true
end

--- Switch genital state on an already-stripped male NPC.
function NakedNPC.SwitchGenitalState(entity, genitalState)
    if not initialized or not entity then return false end
    return Stripper.SwitchGenitalState(entity, genitalState)
end

--- Remove ALL equipment from all 10 slots on an entity.
function NakedNPC.StripAllSlots(entity)
    if not initialized or not entity then return false end
    if system then
        system:StripAllSlots(entity)
        return true
    end
    return false
end

--- Unequip all player clothing (for Clone V spawn).
--- PLAYER ONLY -- NPCs go through the ComponentStripper path instead.
function NakedNPC.UnequipPlayer()
    if not initialized then return false end

    -- Equipment-EX owns the player's outfit while its outfit mode is active,
    -- and the vanilla unequip below is a no-op in that state (this is why
    -- Clone V kept its underwear on with Equipment-EX installed). Route
    -- through Equipment-EX's own commands when it's present.
    if EquipmentEx.IsAvailable() and EquipmentEx.StripPlayer() then
        return true
    end

    if system then
        system:UnequipPlayerClothing()
        print("[NakedNPC] Player clothing unequipped for Clone V")
        return true
    end
    return false
end

--- Re-equip saved player clothing (after Clone V spawn or scene end).
function NakedNPC.ReequipPlayer()
    if not initialized then return false end

    -- Mirror whichever path UnequipPlayer took.
    if EquipmentEx.IsAvailable() and EquipmentEx.RestorePlayer() then
        return true
    end

    if system then
        system:ReequipPlayerClothing()
        print("[NakedNPC] Player clothing re-equipped")
        return true
    end
    return false
end

--- Expose the Equipment-EX bridge so other mods (NightScene) can query it.
function NakedNPC.HasEquipmentEx()
    if not initialized then return false end
    return EquipmentEx.IsAvailable()
end

function NakedNPC.GetVersion() return modVersion end
function NakedNPC.IsReady() return initialized and Config.Get("enabled") end

-- -------------------------------------------------------
--  LIFECYCLE
-- -------------------------------------------------------

registerForEvent("onInit", function()
    print("[NakedNPC] Initializing v" .. modVersion)

    Config.Load()
    BodyManager.Init()
    NPCTracker.Init()
    Stripper.Init(Config, BodyManager, NPCTracker)
    UI.Init(Config, NPCTracker, Stripper, BodyManager, modVersion)

    initialized = true
    print("[NakedNPC] CET module initialized")

    -- Sync config when game loads
    Observe("PlayerPuppet", "OnGameAttached", function(self)
        system = Game.GetScriptableSystemsContainer():Get(CName.new("NakedNPCSystem"))
        if system then
            system:SetEnabled(Config.Get("enabled"))
            system:SetDebugMode(Config.Get("debugMode"))
            system:SetMeshSwapEnabled(Config.Get("meshSwapEnabled"))
            Stripper.SetSystem(system)
            print("[NakedNPC] Synced config to Redscript system")
        else
            print("[NakedNPC] WARNING: NakedNPCSystem not found")
        end
    end)

    -- -------------------------------------------------------
    --  HOOK 1: ScheduleAppearanceChange — detect _naked requests
    -- -------------------------------------------------------
    ObserveBefore("Entity", "ScheduleAppearanceChange", function(self, newAppearanceName)
        if not Config.Get("enabled") then return end
        if not self:IsA(CName.new("ScriptedPuppet")) then return end

        local nameStr = Game.NameToString(newAppearanceName)
        local eid = self:GetEntityID()
        local key = entityIDKey(eid)

        if nameStr == "__NakedNPC_Restore__" then return end
        if nameStr == "__NakedNPC_Step2__" then return end

        -- SKIP: entity is mid-cycle (strip or restore) — don't interfere
        if pendingNaked[key] then return end
        if pendingRestore[key] then return end

        -- No log here: this hook fires for EVERY scripted puppet in the world
        -- whenever it changes appearance, so the whole crowd streaming past
        -- buries the lines that actually matter. The cases below still log.

        -- Case 1: _naked requested
        if string.match(nameStr, "_naked$") or string.match(nameStr, "_naked_ltd$") then
            if NPCTracker.IsTrackedByID(eid) then return end

            if system and system:CheckHasRealNakedAppearance(self) then
                if Config.Get("debugMode") then
                    print("[NakedNPC] PASS-THROUGH: Real _naked for " .. nameStr)
                end
                return
            end

            initiateNakedCycle(self)
            return
        end

        -- Case 2: Non-naked appearance on a stripped entity → trigger restore cycle
        if NPCTracker.IsTrackedByID(eid) then
            -- Don't restore if this is our own deferred firing the original appearance back
            local originalApp = NPCTracker.GetOriginalAppearance(eid)
            if originalApp and nameStr == originalApp then
                if Config.Get("debugMode") then
                    print("[NakedNPC] Skipping restore — deferred original appearance firing")
                end
                return
            end
            initiateRestoreCycle(self)
        end
    end)

    -- -------------------------------------------------------
    --  HOOK 2: OnRequestComponents — the REAL mesh swap point
    -- -------------------------------------------------------
    Observe("ScriptedPuppet", "OnRequestComponents", function(self)
        if not Config.Get("enabled") then return end

        local eid = self:GetEntityID()
        local key = entityIDKey(eid)

        -- SKIP: entity is being restored — do NOT re-strip
        if pendingRestore[key] then
            print("[NakedNPC] OnRequestComponents: skipping (restore in progress for " .. key .. ")")
            pendingRestore[key] = nil
            return
        end

        local pending = pendingNaked[key]
        if not pending then return end

        print("[NakedNPC] OnRequestComponents fired (key=" .. key .. " step=" .. pending.step .. ")")

        if pending.step == 1 then
            print("[NakedNPC] OnRequestComponents step 1: deferring schedule back to " .. pending.originalAppearance)
            pendingNaked[key].step = 2
            pendingNaked[key].timestamp = os.clock()

            table.insert(deferredSchedule, {
                entityRef = pending.entityRef,
                appName = "__NakedNPC_Step2__",
                afterTime = os.clock() + 0.15
            })
            return
        end

        if pending.step >= 2 then
            local genitalState = pendingGenitalState[key]
            pendingGenitalState[key] = nil
            pendingNaked[key] = nil

            -- Deliberately does NOT mention genitalState: at this point it's only
            -- a *requested* state, and it's ignored entirely for female bodies.
            -- StripDuringLoad logs what actually happened once it knows the body
            -- type. Printing "(genitals: erect)" here made it look like genitals
            -- were being applied to every NPC.
            print("[NakedNPC] OnRequestComponents step 2: applying mesh swaps for " .. pending.originalAppearance)
            local savedComponents = Stripper.StripDuringLoad(self, genitalState)
            print("[NakedNPC] About to track NPC, savedComponents count=" .. #savedComponents)
            NPCTracker.Track(self, pending.originalAppearance, savedComponents)
            
            print("[NakedNPC] OnRequestComponents: naked processing complete")
        end
    end)
end)

registerForEvent("onUpdate", function(delta)
    if not initialized then return end

    local now = os.clock()

    -- Process deferred appearance schedule queue
    for i = #deferredSchedule, 1, -1 do
        local d = deferredSchedule[i]
        if d and now >= d.afterTime then
            table.remove(deferredSchedule, i)

            -- Handle mid-cycle intermediate step
            if d.isMidCycle then
                if d.entityRef and d.entityRef:IsA(CName.new("ScriptedPuppet")) then
                    d.entityRef:PrefetchAppearanceChange(CName.new(d.appName))
                    d.entityRef:ScheduleAppearanceChange(CName.new(d.appName))
                    -- Schedule the real original appearance after short delay
                    table.insert(deferredSchedule, {
                        entityRef = d.entityRef,
                        appName = d.midCycleApp,
                        afterTime = now + 0.1
                    })
                end

            -- Handle clear restore flag
            elseif d.isClearRestore then
                if d.restoreKey then
                    pendingRestore[d.restoreKey] = nil
                    print("[NakedNPC] Restore flag cleared for key=" .. d.restoreKey)
                end

            -- Handle normal schedule
            elseif d.entityRef and d.entityRef:IsA(CName.new("ScriptedPuppet")) then
                print("[NakedNPC] Deferred schedule firing: " .. d.appName
                    .. (d.isRestore and " (RESTORE)" or ""))
                d.entityRef:PrefetchAppearanceChange(CName.new(d.appName))
                d.entityRef:ScheduleAppearanceChange(CName.new(d.appName))

                if d.isRestore and d.restoreKey then
                    local restoreKey = d.restoreKey
                    table.insert(deferredSchedule, {
                        entityRef = nil,
                        appName = "",
                        afterTime = now + 0.5,
                        isClearRestore = true,
                        restoreKey = restoreKey
                    })
                end
            else
                if d.isRestore and d.restoreKey then
                    pendingRestore[d.restoreKey] = nil
                end
                if d.appName and d.appName ~= "" then
                    print("[NakedNPC] Deferred schedule: entity no longer valid, skipping")
                end
            end
        end
    end

    cleanupTimer = cleanupTimer + delta
    local interval = Config.Get("cleanupIntervalSeconds") or 5.0
    if cleanupTimer >= interval then
        cleanupTimer = 0.0
        NPCTracker.Cleanup()

        if system and Game.GetPlayer() then
            system:CleanupDespawned()
        end

        -- Clean up stale pending entries (older than 10 seconds)
        for k, v in pairs(pendingNaked) do
            if now - v.timestamp > 60.0 then
                print("[NakedNPC] Cleaning stale pending naked entry: " .. k)
                pendingNaked[k] = nil
            end
        end

        -- Clean up stale restore flags (older than 5 seconds — safety net)
        -- These should already be cleared by the deferred clear above
        for k, v in pairs(pendingRestore) do
            -- pendingRestore values are just `true`, not timestamps
            -- so we rely on the deferred clear. This is just a safety net
            -- in case something went wrong. We can't time these without
            -- storing timestamps, so just leave them — the deferred clear handles it.
        end
    end
end)

-- -------------------------------------------------------
--  IMGUI
-- -------------------------------------------------------

registerForEvent("onOverlayOpen", function() drawWindow = true end)
registerForEvent("onOverlayClose", function() drawWindow = false end)

registerForEvent("onDraw", function()
    if not drawWindow or not initialized then return end
    if not Config.Get("showUI") then return end
    UI.Draw(system)
end)

registerForEvent("onShutdown", function()
    Config.Save()
    print("[NakedNPC] Shutdown complete")
end)

-- Return the public API table so other mods can access it via GetMod("NakedNPC")
return NakedNPC