-- NakedNPC - CET Main Entry Point
-- =================================
-- Universal Naked NPC Appearances Mod v0.3.0
--
-- ARCHITECTURE (three-step appearance reload cycle):
-- 1. Trigger: _naked ScheduleAppearanceChange OR UI Strip button
-- 2. Flag entity in pendingNaked table (step=0)
-- 3. Schedule "Cycle" appearance → forces component reload (step=1)
-- 4. OnRequestComponents fires → schedule "__NakedNPC_Step2__" (step=2)
-- 5. OnRequestComponents fires → schedule back to original (step=3)
-- 6. OnRequestComponents fires for original → DO MESH SWAPS + STRIP HERE
--
-- Step 4 exists because the game resolves "Cycle" back to the NPC's own
-- appearance, so going straight to the original from there is a no-op and no
-- reload arrives. An unknown name reliably moves the NPC OFF its appearance,
-- which is what makes scheduling the real one afterwards an actual change.
-- The strip must land on the ORIGINAL appearance: whatever the NPC is wearing
-- at step 6 is what it wears for the rest of the scene.
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

local modVersion = "0.2.9.1L"
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

-- Attempt to workaround the issue with Lizzie's Braindance and Hotscene not striping NPC (and probably all mod relying on the game to strip NPC).
-- Memorize wether or not the mod was enabled before calling its functionality (see EnableIfNeeded below)
-- To activate, set Enabled to false in Config.json
local changedEnabled = false

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

-- How many times to re-issue a restore that did not take before giving up.
-- Three attempts spans roughly 1.2s, which covers an NPC that is briefly busy
-- without leaving a despawning one retrying forever.
local MAX_RESTORE_ATTEMPTS = 3

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

    NakedNPC.Print("[NakedNPC] Initiating naked cycle for: " .. currentApp .. " (key=" .. key .. ")")

    pendingNaked[key].step = 1
    NakedNPC.Trace("[NakedNPC] Deferred firing ScheduleAppearanceChange: " .. d.appName .. " for key=" .. (d.restoreKey or "?"))
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
        NakedNPC.Print("[NakedNPC] Restore: no saved appearance for " .. key)
        -- Fallback: just untrack, game will handle appearance naturally
        NPCTracker.Untrack(eid)
        return false
    end

    NakedNPC.Print("[NakedNPC] Initiating restore cycle for: " .. originalApp .. " (key=" .. key .. ")")

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
        NakedNPC.Print("[NakedNPC] StripForScene: cycle already in progress for " .. key)
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
        NakedNPC.Print("[NakedNPC] StripForScene: cycle failed to start for " .. key .. " (appearance empty or being restored?)")
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
        NakedNPC.Print("[NakedNPC] RestoreFromScene: two-step restore -> " .. originalApp)
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
        NakedNPC.Print("[NakedNPC] Player clothing unequipped for Clone V")
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
        NakedNPC.Print("[NakedNPC] Player clothing re-equipped")
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
function NakedNPC.IsEnabled() return Config.Get("enabled") end
function NakedNPC.Enable() return Config.Set("enabled", true) end
function NakedNPC.Disable() return Config.Set("enabled", false) end

function NakedNPC.EnableIfNeeded()
    if not NakedNPC.IsEnabled() and not changedEnabled then
        NakedNPC.Enable()
        changedEnabled = true
        return true
    end 
    return false
end

function NakedNPC.DisableIfNeeded()
    if NakedNPC.IsEnabled() and changedEnabled then
        NakedNPC.Disable()
        changedEnabled = false
        return true
    end 
    return false
end

function NakedNPC.debugMode() return Config.Get("debugMode") end

--------------------------------------------------------------------
-- A library of sorts of useful functions . Where should it all go ?
--------------------------------------------------------------------

function NakedNPC.DebugPrint(...)
	if debug and debug.print then
		debug.print(...)
		if debug.log then
			debug.log(...)
		end
	end
end

function NakedNPC.DebugLog(...)
	if debug and debug.log then
		debug.log(...)
	end
end

function NakedNPC.DebugTrace(...)
	if debug and debug.log and NakedNPC.debugMode() then
		debug.log(...)
    -- else
	--	debug.log("debugMode off: " .. ...)
	end
end

function NakedNPC.Print(...)
	print(...)
	spdlog.info(...)
end

function NakedNPC.Log(...)
	spdlog.info(...)
end

function NakedNPC.Trace(...)
	if NakedNPC.debugMode() then
		spdlog.info(...)
	end
end

function NakedNPC.TableSize(table)
	local result = 0
	if table then
		if type(table) == 'table' then
	        for _, value in pairs(table) do
	            result = result + 1
	        end
		else
			result = -1
		end
	else
		result = 0
	end
	-- NakedNPC.DebugTrace("[NakedNPC] TableSize=" .. tostring(result))
	return result
end

-- duplicated from anim_toggles.lua and adpted for tables with non numeric keys.

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

function NakedNPC.TableSort(list)
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
            sub = NakedNPC.TableSort(value)
            parts[i] = '"' .. tostring(key) .. '": {\n\t\t' .. table.concat(sub, ',\n\t\t') .. '\n\t}'
        end
        -- NakedNPC.Trace("[NakedNPC] TableSort parts[" .. tostring(i) .. "]='" .. tostring(parts[i]) .. "'")
    end
    return parts
end

function NakedNPC.EncodeSorted(list)
    if not list then return nil end
    -- NakedNPC.DebugTrace("[NakedNPC] EncodeSorted list ", list, " of size ", NakedNPC.TableSize(list))

    -- Written by hand rather than json.encode: that puts all ids on a single line,
    -- which is unreadable and undiffable if you ever want to
    -- edit the file directly. Sorted so entries stay put between saves.

    local parts = NakedNPC.TableSort(list)
    -- NakedNPC.DebugTrace("[NakedNPC] EncodeSorted parts ", parts)

    local content = "{\n\t" .. table.concat(parts, ",\n\t") .. "\n}\n"
    -- NakedNPC.DebugTrace("[NakedNPC] EncodeSorted content ", content)

    -- Do not write an empty config, it has to be an error
    if NakedNPC.TableSize(parts) == 0 then
        -- NakedNPC.Trace("[NakedNPC] EncodeSorted ERROR: Could not sort and encode the config file")
        content = nil 
    end
	return content
end

-- -------------------------------------------------------
--  LIFECYCLE
-- -------------------------------------------------------

registerForEvent("onInit", function()
    NakedNPC.Log  ("")
    NakedNPC.Log  ("========================================")
    NakedNPC.Print("[NakedNPC] Initializing v" .. modVersion)
    NakedNPC.Log  ("========================================")

	dofile("debug.lua")
	
    Config.Load()
    BodyManager.Init()
    NPCTracker.Init()
    Stripper.Init(Config, BodyManager, NPCTracker)
    UI.Init(Config, NPCTracker, Stripper, BodyManager, modVersion)

    initialized = true
    NakedNPC.Print("[NakedNPC] CET module initialized")
    if Config.Get("enabled") then
        NakedNPC.Print("[NakedNPC] enabled")
    else
        NakedNPC.Print("[NakedNPC] disabled")
    end

    -- Sync config when game loads
    Observe("PlayerPuppet", "OnGameAttached", function(self)
        system = Game.GetScriptableSystemsContainer():Get(CName.new("NakedNPCSystem"))
        if system then
            system:SetEnabled(Config.Get("enabled"))
            system:SetDebugMode(Config.Get("debugMode"))
            system:SetMeshSwapEnabled(Config.Get("meshSwapEnabled"))
            Stripper.SetSystem(system)
            NakedNPC.Print("[NakedNPC] Synced config to Redscript system")
        else
            NakedNPC.Print("[NakedNPC] WARNING: NakedNPCSystem not found")
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
                NakedNPC.Trace("[NakedNPC] PASS-THROUGH: Real _naked for " .. nameStr)
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
                NakedNPC.Trace("[NakedNPC] Skipping restore — deferred original appearance firing")
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
            NakedNPC.Print("[NakedNPC] OnRequestComponents: skipping (restore in progress for " .. key .. ")")
            pendingRestore[key] = nil
            return
        end

        local pending = pendingNaked[key]
        if not pending then return end

        NakedNPC.Print("[NakedNPC] OnRequestComponents fired (key=" .. key .. " step=" .. pending.step .. ")")

        -- Three reloads, and only the last one matters. "Cycle" resolves back
        -- to the NPC's own appearance, so scheduling the original after it is
        -- a no-op and no reload arrives. The dummy is what reliably moves the
        -- NPC OFF its appearance, which is what makes scheduling the real one
        -- afterwards an actual change. Stripping on the dummy's reload -- which
        -- is what used to happen -- left the NPC in whatever other entry of its
        -- appearance list the game picked for that unknown name: an NPC in
        -- outfit 2 turning up in outfit 3 the moment the scene started.
        if pending.step == 1 then
            NakedNPC.Print("[NakedNPC] OnRequestComponents step 1: moving off " .. pending.originalAppearance)
            pendingNaked[key].step = 2
            pendingNaked[key].timestamp = os.clock()

            table.insert(deferredSchedule, {
                entityRef = pending.entityRef,
                appName = "__NakedNPC_Step2__",
                afterTime = os.clock() + 0.15
            })
            return
        end

        if pending.step == 2 then
            NakedNPC.Print("[NakedNPC] OnRequestComponents step 2: scheduling back to " .. pending.originalAppearance)
            pendingNaked[key].step = 3
            pendingNaked[key].timestamp = os.clock()

            -- The reload the strip runs on. Whatever appearance the NPC lands
            -- on here is what it wears for the rest of the scene.
            table.insert(deferredSchedule, {
                entityRef = pending.entityRef,
                appName = pending.originalAppearance,
                afterTime = os.clock() + 0.15
            })

            -- Only reachable if the dummy resolved to the original appearance
            -- after all, making the schedule above a no-op. Nothing can be done
            -- about it from here: forcing the dummy again would resolve to the
            -- same place. Drop the entry so the NPC is not left pending for
            -- ever, which would block every later attempt to strip it.
            table.insert(deferredSchedule, {
                entityRef = pending.entityRef,
                appName = "",
                afterTime = os.clock() + 0.65,
                isStep3Timeout = true,
                stepKey = key
            })
            return
        end

        if pending.step >= 3 then
            local genitalState = pendingGenitalState[key]
            pendingGenitalState[key] = nil
            pendingNaked[key] = nil

            -- Deliberately does NOT mention genitalState: at this point it's only
            -- a *requested* state, and it's ignored entirely for female bodies.
            -- StripDuringLoad logs what actually happened once it knows the body
            -- type. Printing "(genitals: erect)" here made it look like genitals
            -- were being applied to every NPC.
            -- Print what the NPC is actually wearing, not the name we saved.
            -- Printing the saved name here hid this whole bug: the line read
            -- "...for poor_01" while the NPC on screen was in poor_03.
            local okApp, wearing = pcall(function()
                return Game.NameToString(self:GetCurrentAppearanceName())
            end)
            if not okApp or wearing == "" then wearing = "<unknown>" end
            NakedNPC.Print("[NakedNPC] OnRequestComponents step 3: applying mesh swaps, wearing "
                .. wearing .. " (saved " .. pending.originalAppearance .. ")")
            local savedComponents = Stripper.StripDuringLoad(self, genitalState)
            NakedNPC.Print("[NakedNPC] About to track NPC, savedComponents count=" .. #savedComponents)
            NPCTracker.Track(self, pending.originalAppearance, savedComponents)
            
            NakedNPC.Print("[NakedNPC] OnRequestComponents: naked processing complete")
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

            -- The final reload never came, so the NPC is still dressed. Give up
            -- rather than leave it pending for ever and unstrippable later.
            elseif d.isStep3Timeout then
                local pending = d.stepKey and pendingNaked[d.stepKey]
                if pending and pending.step >= 3 then
                    NakedNPC.Print("[NakedNPC] WARN: reload back to " .. pending.originalAppearance
                        .. " never arrived for " .. d.stepKey .. " -- NPC left dressed")
                    pendingNaked[d.stepKey] = nil
                    pendingGenitalState[d.stepKey] = nil
                end

            -- Did the restore land on the appearance the NPC started in?
            elseif d.isVerifyRestore then
                local settled = true
                local valid = d.entityRef and d.entityRef:IsA(CName.new("ScriptedPuppet"))

                if valid then
                    -- Guarded: this runs every frame, and a stale handle here
                    -- would otherwise take the whole onUpdate down with it.
                    local ok, current = pcall(function()
                        return Game.NameToString(d.entityRef:GetCurrentAppearanceName())
                    end)
                    if not ok then current = "" end
                    -- An empty name means the entity has not finished streaming
                    -- rather than that it is wearing the wrong thing, but it is
                    -- still not the appearance we asked for, so retry either way.
                    if current ~= d.appName and d.attempt < MAX_RESTORE_ATTEMPTS then
                        settled = false
                        NakedNPC.Print(string.format(
                            "[NakedNPC] Restore did not take (is '%s', want '%s') -- retry %d/%d",
                            current, d.appName, d.attempt + 1, MAX_RESTORE_ATTEMPTS))
                        d.entityRef:PrefetchAppearanceChange(CName.new(d.appName))
                        d.entityRef:ScheduleAppearanceChange(CName.new(d.appName))
                        table.insert(deferredSchedule, {
                            entityRef = d.entityRef,
                            appName = d.appName,
                            afterTime = now + 0.4,
                            isVerifyRestore = true,
                            restoreKey = d.restoreKey,
                            attempt = d.attempt + 1
                        })
                    elseif current ~= d.appName then
                        NakedNPC.Print("[NakedNPC] WARN: gave up restoring " .. d.appName
                            .. " after " .. MAX_RESTORE_ATTEMPTS .. " attempts, NPC is wearing " .. current)
                    end
                end

                -- Hold the restore flag for as long as retries are outstanding,
                -- so nothing re-strips the NPC mid-restore. Always released in
                -- the end, or the NPC could never be stripped again.
                if settled and d.restoreKey then
                    pendingRestore[d.restoreKey] = nil
                end

            -- Handle normal schedule
            elseif d.entityRef and d.entityRef:IsA(CName.new("ScriptedPuppet")) then
                NakedNPC.Print("[NakedNPC] Deferred schedule firing: " .. d.appName
                    .. (d.isRestore and " (RESTORE)" or ""))
                d.entityRef:PrefetchAppearanceChange(CName.new(d.appName))
                d.entityRef:ScheduleAppearanceChange(CName.new(d.appName))

                if d.isRestore and d.restoreKey then
                    -- Check that it actually took. The restore goes through a
                    -- dummy appearance (__NakedNPC_Restore__) to force a
                    -- component reload, and the game resolves that name to some
                    -- other entry in the NPC's appearance list. If the schedule
                    -- back to the real appearance is dropped -- which happens
                    -- when the NPC is busy, mid-stream or out of range -- the
                    -- NPC is left wearing whatever the dummy resolved to, which
                    -- is why an NPC in outfit 2 sometimes came back in outfit 3.
                    table.insert(deferredSchedule, {
                        entityRef = d.entityRef,
                        appName = d.appName,
                        afterTime = now + 0.4,
                        isVerifyRestore = true,
                        restoreKey = d.restoreKey,
                        attempt = d.attempt or 1
                    })
                end
            else
                if d.isRestore and d.restoreKey then
                    pendingRestore[d.restoreKey] = nil
                end
                if d.appName and d.appName ~= "" then
                    NakedNPC.Print("[NakedNPC] Deferred schedule: entity no longer valid, skipping")
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
                NakedNPC.Print("[NakedNPC] Cleaning stale pending naked entry: " .. k)
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
    NakedNPC.Print("[NakedNPC] Shutdown complete")
end)

-- Return the public API table so other mods can access it via GetMod("NakedNPC")
return NakedNPC