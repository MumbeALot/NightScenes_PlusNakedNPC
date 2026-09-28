-- NakedNPC - Stripper Module (Lua Side)
-- =======================================
-- Two stripping modes:
--   1. StripEntity() — immediate component toggle + chunkMask (for UI buttons, API calls)
--   2. StripDuringLoad() — full mesh swap + toggle (called during OnRequestComponents)
--
-- Runtime mesh swapping (comp.mesh = ...) does NOT work on already-rendered entities.
-- StripDuringLoad() is called during the component loading phase where swaps work.
--
-- RESTORE: Uses appearance reload cycle (ScheduleAppearanceChange back to original)
-- instead of manually restoring component states. This is more reliable because
-- mesh swaps cannot be reversed at runtime outside OnRequestComponents.

local Stripper = {}

local Config = nil
local BodyManager = nil
local NPCTracker = nil
local system = nil

-- Component prefix classification
local clothingPrefixes = {
    "t1_", "t2_",   -- torso clothing
    "l1_",           -- legs outer clothing (pants, skirts)
    "s1_",           -- shoes
    "h1_", "h2_",   -- headwear
    "i1_",           -- accessories
    "o1_",           -- outfit overlay
    "g1_"            -- gloves
}

-- Body type ints as returned by NakedNPCSystem:DetectBodyType. Genital handling
-- only applies to Male / Male Big; Female skips that phase entirely.
local bodyTypeNames = { [1] = "Female", [2] = "Male", [3] = "Male Big" }

local bodyPrefixes = {
    "t0_",           -- nude body (torso)
    "l0_",           -- legs body / underwear
    "s0_",           -- feet body
    "h0_", "hx_", "ht_", "he_", "hh_",  -- head/face/hair
    "a0_",           -- arm cyberware
    "i0_"            -- inner body
}

-- -------------------------------------------------------
--  INIT
-- -------------------------------------------------------

function Stripper.Init(config, bodyManager, npcTracker)
    Config = config
    BodyManager = bodyManager
    NPCTracker = npcTracker
    print("[NakedNPC] Stripper module initialized")
end

function Stripper.SetSystem(s)
    system = s
end

-- -------------------------------------------------------
--  PREFIX CHECKS
-- -------------------------------------------------------

local function startsWithAny(str, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string.sub(str, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function isClothingComponent(compName)
    return startsWithAny(compName, clothingPrefixes)
end

local function isBodyComponent(compName)
    return startsWithAny(compName, bodyPrefixes)
end

-- -------------------------------------------------------
--  CLONE V DETECTION
-- -------------------------------------------------------

--- Check if an entity is a Clone V (player cutscene puppet).
--- Clone V just needs clothing removed, no body mesh swaps.
local function isCloneV(entity)
    local puppet = entity
    if puppet and puppet.GetRecordID then
        local recordStr = tostring(puppet:GetRecordID())
        if recordStr and (string.find(recordStr, "Player_Cutscene") or string.find(recordStr, "TPP_Player")) then
            return true
        end
    end
    return false
end

--- Check if a component on Clone V is a body/body-mod part that should be KEPT.
local function isCloneVBodyComponent(compName)
    local lc = compName:lower()

    if isBodyComponent(compName) then return true end
    if string.find(lc, "_pwa_") or string.find(lc, "_pma_") then return true end
    if string.find(lc, "_pwa__") or string.find(lc, "_pma__") then return true end
    if string.find(lc, "body:") then return true end
    if string.find(lc, "morphtarget") then return true end
    if string.find(lc, "morphs") then return true end
    if string.find(lc, "_hyst_") or string.find(lc, "boobs") then return true end
    if string.find(lc, "jiggle") or string.find(lc, "physics") then return true end
    if string.find(lc, "seamfix") or string.find(lc, "_seamfix") then return true end
    if string.find(lc, "vtk_seamfix") then return true end
    if string.find(lc, "nim_head") then return true end
    if string.find(lc, "heb_") then return true end
    if string.find(lc, "kiasu") then return true end
    if string.find(lc, "replacer") then return true end
    if string.find(lc, "_base__full") then return true end
    if string.find(lc, "_base__hq") then return true end
    if string.find(lc, "personal_link") then return true end
    if string.find(lc, "cyberarm") or string.find(lc, "monowire") then return true end
    if string.find(lc, "mantisblade") or string.find(lc, "strongarm") then return true end
    if string.find(lc, "launcher") then return true end
    if string.find(lc, "tattoo") then return true end
    if string.find(lc, "freckle") or string.find(lc, "pimple") then return true end
    if string.find(lc, "makeup") then return true end
    if string.find(lc, "scar") then return true end
    if string.find(lc, "muscle") then return true end
    if string.find(lc, "eye") and not string.find(lc, "eyewear") then return true end

    return false
end

-- -------------------------------------------------------
--  STRIP ENTITY (immediate, no mesh swap)
-- -------------------------------------------------------
-- Used by UI buttons and direct API. Only does component toggling
-- and chunkMask changes. No mesh swaps (they don't work at runtime).

--- @param genitalState string|nil - "soft", "erect", or nil for default
function Stripper.StripEntity(entity, genitalState)
    if not entity then return false end
    if not Config or not Config.Get("enabled") then return false end
    if NPCTracker and NPCTracker.IsTracked(entity) then return true end

    local components = entity:GetComponents()
    if not components then return false end

    local cloneV = isCloneV(entity)
    if cloneV then
        print("[NakedNPC] Clone V detected — clothing strip only, no chunkMask changes on body")
    end

    local strippedCount = 0
    local savedComponents = {}
    local debugMode = Config.Get("debugMode")

    for i = 1, #components do
        local comp = components[i]
        if comp then
            local compName = Game.NameToString(comp:GetName())
            local className = Game.NameToString(comp:GetClassName())

            if string.find(className, "Mesh") then
                if cloneV then
                    if isCloneVBodyComponent(compName) then
                        table.insert(savedComponents, {
                            name = compName,
                            wasEnabled = comp:IsEnabled(),
                            originalChunkMask = comp.chunkMask,
                            isBodyMesh = true
                        })
                        if debugMode then
                            print("[NakedNPC]   Clone V body kept: " .. compName)
                        end
                    else
                        if comp:IsEnabled() then
                            table.insert(savedComponents, {
                                name = compName,
                                wasEnabled = true,
                                originalChunkMask = comp.chunkMask
                            })
                            comp.chunkMask = 0
                            comp:Toggle(false)
                            strippedCount = strippedCount + 1
                            if debugMode then
                                print("[NakedNPC]   Clone V stripped: " .. compName)
                            end
                        end
                    end
                else
                    -- REGULAR NPC: prefix-based classification
                    if isClothingComponent(compName) then
                        local shouldStrip = true
                        if (string.sub(compName, 1, 3) == "h1_" or string.sub(compName, 1, 3) == "h2_")
                            and not Config.Get("stripHeadwear") then
                            shouldStrip = false
                        end
                        if string.sub(compName, 1, 3) == "i1_" and not Config.Get("stripAccessories") then
                            shouldStrip = false
                        end

                        if shouldStrip then
                            table.insert(savedComponents, {
                                name = compName,
                                wasEnabled = comp:IsEnabled(),
                                originalChunkMask = comp.chunkMask
                            })
                            comp.chunkMask = 0
                            comp:Toggle(false)
                            strippedCount = strippedCount + 1
                            if debugMode then
                                print("[NakedNPC]   Stripped: " .. compName)
                            end
                        end

                    elseif isBodyComponent(compName) then
                        table.insert(savedComponents, {
                            name = compName,
                            wasEnabled = comp:IsEnabled(),
                            originalChunkMask = comp.chunkMask,
                            isBodyMesh = true
                        })
                        if debugMode then
                            print("[NakedNPC]   Body skipped (immediate mode): " .. compName)
                        end
                        -- local prefix = string.sub(compName, 1, 3)
                        -- -- l0_ legs stub: hide it, t0_ full body covers legs
                        -- if prefix == "l0_" then
                        --     table.insert(savedComponents, {
                        --         name = compName,
                        --         wasEnabled = comp:IsEnabled(),
                        --         originalChunkMask = comp.chunkMask,
                        --         isBodyMesh = true
                        --     })
                        --     comp.chunkMask = 0
                        --     comp:Toggle(false)
                        --     strippedCount = strippedCount + 1
                        --     if debugMode then
                        --         print("[NakedNPC]   l0_ hidden (covered by full body): " .. compName)
                        --     end
                        -- else
                        --     table.insert(savedComponents, {
                        --         name = compName,
                        --         wasEnabled = comp:IsEnabled(),
                        --         originalChunkMask = comp.chunkMask,
                        --         isBodyMesh = true
                        --     })
                        --     comp.chunkMask = 18446744073709551615ULL
                        --     if not comp:IsEnabled() then comp:Toggle(true) end
                        --     if debugMode then
                        --         print("[NakedNPC]   Body revealed: " .. compName .. " chunkMask -> ALL")
                        --     end
                        -- end
                    end
                end
            end
        end
    end

    if NPCTracker then
        NPCTracker.Track(entity, "lua_strip", savedComponents)
    end

    print(string.format("[NakedNPC] StripEntity: %d items stripped (toggle+chunkMask only)", strippedCount))
    return true
end

-- -------------------------------------------------------
--  STRIP DURING LOAD (with mesh swaps — called from OnRequestComponents)
-- -------------------------------------------------------
-- This is the PROPER stripping path. Called during the component loading
-- phase where mesh swaps (comp.mesh = ResRef.FromString) actually take effect.
-- Returns savedComponents table (used only for tracking, not for manual restore).

--- @param genitalState string|nil - "soft", "erect", or nil for default
function Stripper.StripDuringLoad(entity, genitalState)
    print("[NakedNPC] StripDuringLoad: starting")
    if not entity then return {} end

    local components = entity:GetComponents()
    if not components then return {} end

    local skipMeshSwaps = isCloneV(entity)
    if skipMeshSwaps then
        print("[NakedNPC] Clone V detected — clothing strip only, no mesh swaps")
    end

    local savedComponents = {}
    local strippedCount = 0
    local meshSwapCount = 0
    local debugMode = Config and Config.Get("debugMode")
    local detectedSkinTone = nil  -- captured from t0_ component, used for genital mesh appearance

    -- Hoisted out of the pcall below so the summary log can report it.
    local bodyTypeInt = 1

    local ok, err = pcall(function()

    -- Detect body type once up front
    bodyTypeInt = 1
    if system then
        bodyTypeInt = system:DetectBodyType(entity)
    elseif Game.GetScriptableSystemsContainer then
        local sys = Game.GetScriptableSystemsContainer():Get(CName.new("NakedNPCSystem"))
        if sys then
            bodyTypeInt = sys:DetectBodyType(entity)
            system = sys  -- cache it for future calls
        end
    end

    -- -------------------------------------------------------
    --  Phase 1: Clothing strip + body reveal + t0_ mesh swap
    -- -------------------------------------------------------
    for i = 1, #components do
        local comp = components[i]
        if comp then
            local compName = Game.NameToString(comp:GetName())
            local className = Game.NameToString(comp:GetClassName())

            if string.find(className, "Mesh") then
                -- CLOTHING: hide it
                if isClothingComponent(compName) then
                    table.insert(savedComponents, {
                        name = compName,
                        wasEnabled = comp:IsEnabled(),
                        originalChunkMask = comp.chunkMask
                    })
                    comp.chunkMask = 0
                    comp:Toggle(false)
                    strippedCount = strippedCount + 1
                    if debugMode then
                        print("[NakedNPC]   [LOAD] Stripped: " .. compName)
                    end

                -- BODY: handle per prefix
                elseif isBodyComponent(compName) then
                    local prefix = string.sub(compName, 1, 3)

                    -- t0_ torso: swap to full nude body mesh if path configured
                    if prefix == "t0_" and not skipMeshSwaps then
                        local bodyPath = BodyManager.GetMeshPath(bodyTypeInt, "body")
                        table.insert(savedComponents, {
                            name = compName,
                            wasEnabled = comp:IsEnabled(),
                            originalChunkMask = comp.chunkMask,
                            isBodyMesh = true,
                            isGenital = true
                        })
                        print("[NakedNPC] t0_ current meshAppearance=" .. Game.NameToString(comp.meshAppearance))
                        if bodyPath then
                            local currentApp = Game.NameToString(comp.meshAppearance)

                            -- Extract bare skin tone (strip _naked suffix if present)
                            -- e.g. "01_ca_pale_naked" -> "01_ca_pale"
                            --      "01_ca_pale"        -> "01_ca_pale"
                            local skinTone = currentApp:gsub("_naked$", "")
                            detectedSkinTone = skinTone
                            print("[NakedNPC] Detected skin tone: " .. skinTone)

                            local nakedApp = currentApp
                            if not string.find(currentApp, "_naked") then
                                nakedApp = currentApp .. "_naked"
                            end

                            comp.mesh = ResRef.FromString(bodyPath)
                            comp.meshAppearance = CName.new(nakedApp)
                            print("[NakedNPC] t0_ meshAppearance after set=" .. Game.NameToString(comp.meshAppearance))
                            meshSwapCount = meshSwapCount + 1
                            if debugMode then
                                print("[NakedNPC]   [LOAD] t0_ MESH SWAP: " .. compName .. " -> " .. bodyPath)
                            end
                        elseif debugMode then
                            print("[NakedNPC]   [LOAD] t0_ no body path configured, reveal only: " .. compName)
                        end
                        comp.chunkMask = 18446744073709551615ULL
                        if not comp:IsEnabled() then comp:Toggle(true) end

                    -- l0_ legs stub: hide it, t0_ full body covers legs geometry
                    elseif prefix == "l0_" then
                        table.insert(savedComponents, {
                            name = compName,
                            wasEnabled = comp:IsEnabled(),
                            originalChunkMask = comp.chunkMask,
                            isBodyMesh = true,
                            isGenital = true
                        })
                        comp.chunkMask = 0
                        comp:Toggle(false)
                        strippedCount = strippedCount + 1
                        if debugMode then
                            print("[NakedNPC]   [LOAD] l0_ hidden (covered by full body mesh): " .. compName)
                        end

                    -- All other body components: reveal all chunks
                    else
                        table.insert(savedComponents, {
                            name = compName,
                            wasEnabled = comp:IsEnabled(),
                            originalChunkMask = comp.chunkMask,
                            isBodyMesh = true,
                            isGenital = true
                        })
                        comp.chunkMask = 18446744073709551615ULL
                        if not comp:IsEnabled() then comp:Toggle(true) end
                        if debugMode then
                            print("[NakedNPC]   [LOAD] Body revealed: " .. compName)
                        end
                    end
                end
            end
        end
    end

    -- -------------------------------------------------------
    --  Phase 2: Male genital handling
    -- -------------------------------------------------------
    -- Looks for an existing i0_ component to repurpose as genitals.
    -- Falls back to repurposing a stripped i1_ accessory component.
    -- Uses a single mesh path with chunkMask to control soft/erect state.

    if not skipMeshSwaps and (bodyTypeInt == 2 or bodyTypeInt == 3) then
        local genitalPath = BodyManager.GetMeshPath(bodyTypeInt, "genitals")
        local genitalMask = BodyManager.GetGenitalMask(bodyTypeInt, genitalState)
        local foundGenital = false
        local foundI0 = false

        if genitalPath then
            -- First pass: look for existing i0_ or named genital component
            for i = 1, #components do
                local comp = components[i]
                if comp then
                    local compName = Game.NameToString(comp:GetName())
                    local className = Game.NameToString(comp:GetClassName())

                    if string.find(className, "Mesh") and string.sub(compName, 1, 3) == "i0_" then
                        foundI0 = true

                        if string.find(compName, "penis") or string.find(compName, "genital") then
                            -- Already a genital component — just set mask and enable
                            foundGenital = true
                            table.insert(savedComponents, {
                                name = compName,
                                wasEnabled = comp:IsEnabled(),
                                originalChunkMask = comp.chunkMask,
                                isBodyMesh = true
                            })
                            comp.chunkMask = genitalMask
                            if detectedSkinTone then
                                comp.meshAppearance = CName.new(detectedSkinTone)
                                print("[NakedNPC] Genital (existing) meshAppearance set to: " .. detectedSkinTone)
                            end
                            comp:Toggle(true)
                            if debugMode then
                                print("[NakedNPC]   [LOAD] Male genital ENABLED: " .. compName .. " mask=" .. tostring(genitalMask))
                            end
                        elseif not foundGenital then
                            -- Non-genital i0_ — swap its mesh to genital mesh
                            local originalMesh = comp.mesh
                            table.insert(savedComponents, {
                                name = compName,
                                wasEnabled = comp:IsEnabled(),
                                originalChunkMask = comp.chunkMask,
                                meshSwapped = true,
                                originalMesh = originalMesh,
                                isBodyMesh = true,
                                isGenital = true
                            })
                            comp.mesh = ResRef.FromString(genitalPath)
                            comp.chunkMask = genitalMask
                            if detectedSkinTone then
                                comp.meshAppearance = CName.new(detectedSkinTone)
                                print("[NakedNPC] Genital (i0_ swap) meshAppearance set to: " .. detectedSkinTone)
                            end
                            comp:Toggle(true)
                            meshSwapCount = meshSwapCount + 1
                            if debugMode then
                                print("[NakedNPC]   [LOAD] Male i0_ MESH SWAP to genitals: " .. compName .. " mask=" .. tostring(genitalMask))
                            end
                        end
                    end
                end
            end

            -- Second pass: fallback — repurpose a stripped i1_ accessory component
            if not foundGenital and not foundI0 then
                for i = 1, #components do
                    local comp = components[i]
                    if comp then
                        local compName = Game.NameToString(comp:GetName())
                        local className = Game.NameToString(comp:GetClassName())
                        local prefix = string.sub(compName, 1, 3)

                        if string.find(className, "Mesh") and (prefix == "i1_" or prefix == "l1_" or prefix == "t1_") then
                            local originalMesh = comp.mesh

                            -- Find and UPDATE the existing savedComponents entry
                            -- instead of adding a duplicate
                            local existingEntry = nil
                            for _, entry in ipairs(savedComponents) do
                                if entry.name == compName then
                                    existingEntry = entry
                                    break
                                end
                            end

                            if existingEntry then
                                existingEntry.meshSwapped = true
                                existingEntry.originalMesh = originalMesh
                                existingEntry.isGenital = true
                                -- wasEnabled and originalChunkMask already saved correctly
                            else
                                table.insert(savedComponents, {
                                    name = compName,
                                    wasEnabled = false,
                                    originalChunkMask = 0,
                                    meshSwapped = true,
                                    originalMesh = originalMesh,
                                    isBodyMesh = true,
                                    isGenital = true
                                })
                            end

                            comp.mesh = ResRef.FromString(genitalPath)
                            comp.chunkMask = genitalMask
                            if detectedSkinTone then
                                comp.meshAppearance = CName.new(detectedSkinTone)
                                print("[NakedNPC] Genital (fallback repurpose) meshAppearance set to: " .. detectedSkinTone)
                            end
                            comp:Toggle(true)
                            foundGenital = true
                            meshSwapCount = meshSwapCount + 1
                            if debugMode then
                                print("[NakedNPC]   [LOAD] Male REPURPOSED " .. compName .. " -> genitals mask=" .. tostring(genitalMask))
                            end
                            break
                        end
                    end
                end
            end
        end

        -- This whole phase only runs for Male / Male Big bodies, so anything
        -- logged here genuinely applies to genitals (the old unconditional
        -- "foundGenital=.. foundI0=.." line duplicated this, less readably).
        if foundGenital then
            print("[NakedNPC] Genitals applied (" .. (genitalState or "soft") .. ")")
        elseif foundI0 then
            print("[NakedNPC] Genitals skipped: i0_ found but no genital mesh path configured")
        else
            print("[NakedNPC] Genitals skipped: no suitable component found")
        end
    end
    end)
    if not ok then
        print("[NakedNPC] StripDuringLoad ERROR: " .. tostring(err))
        return {}
    end

    print(string.format("[NakedNPC] StripDuringLoad: %s body -- %d stripped, %d mesh swaps",
        bodyTypeNames[bodyTypeInt] or ("type " .. tostring(bodyTypeInt)),
        strippedCount, meshSwapCount))
    return savedComponents
end

-- -------------------------------------------------------
--  RESTORE
-- -------------------------------------------------------
-- Restores by scheduling the original appearance back.
-- This triggers a full component reload from scratch — far more reliable
-- than trying to manually reverse mesh swaps at runtime.

function Stripper.RestoreEntity(entity)
    if not entity then return false end

    local saved = NPCTracker and NPCTracker.GetSavedComponents(entity:GetEntityID())
    if saved and #saved > 0 then
        local restoredCount = 0
        for _, entry in ipairs(saved) do
            local comp = entity:FindComponentByName(CName.new(entry.name))
            if comp then
                -- Restore original mesh if this component was swapped
                print("[NakedNPC] Restoring: " .. entry.name .. " wasEnabled=" .. tostring(entry.wasEnabled) .. " chunkMask=" .. tostring(entry.originalChunkMask))
                if entry.meshSwapped and entry.originalMesh then
                    comp.mesh = entry.originalMesh
                end
                -- Restore chunkMask
                if entry.originalChunkMask then
                    comp.chunkMask = entry.originalChunkMask
                end
                -- Restore enabled state
                if entry.wasEnabled then
                    comp:Toggle(true)
                    print("[NakedNPC] Toggled " .. entry.name .. " -> isEnabled=" .. tostring(comp:IsEnabled()))
                else
                    comp:Toggle(false)
                end
                restoredCount = restoredCount + 1
            else
                print("[NakedNPC] NOT FOUND: " .. entry.name)
            end
        end
        print("[NakedNPC] RestoreEntity: " .. restoredCount .. " components restored")
    else
        print("[NakedNPC] RestoreEntity: no saved components found")
    end
    return true
end

-- -------------------------------------------------------
--  DEBUG UTILITIES
-- -------------------------------------------------------

function Stripper.GetComponentDump(entity)
    local result = {}
    if not entity then return result end
    local components = entity:GetComponents()
    if not components then return result end

    for i = 1, #components do
        local comp = components[i]
        if comp then
            local compName = Game.NameToString(comp:GetName())
            local className = Game.NameToString(comp:GetClassName())
            if string.find(className, "Mesh") then
                table.insert(result, {
                    name = compName,
                    className = className,
                    isBody = isBodyComponent(compName),
                    isClothing = isClothingComponent(compName),
                    enabled = comp:IsEnabled()
                })
            end
        end
    end
    return result
end

function Stripper.GetLookAtTarget()
    local player = Game.GetPlayer()
    if not player then return nil end
    local ts = Game.GetTargetingSystem()
    if not ts then return nil end
    return ts:GetLookAtObject(player, true, false) or ts:GetLookAtObject(player, false, false)
end

-- -------------------------------------------------------
--  SCENE SUPPORT: Switch genital state on already-stripped NPC
-- -------------------------------------------------------
-- Switches the chunkMask on the genital component to toggle soft/erect.
-- Works at runtime since it's just a chunkMask change, not a mesh swap.

function Stripper.SwitchGenitalState(entity, genitalState)
    if not entity then return false end

    local bodyTypeInt = 1
    if system then bodyTypeInt = system:DetectBodyType(entity) end
    if bodyTypeInt ~= 2 and bodyTypeInt ~= 3 then return false end

    local genitalMask = BodyManager.GetGenitalMask(bodyTypeInt, genitalState)

    -- First check if we have a tracked repurposed component
    local genitalCompName = NPCTracker and NPCTracker.GetGenitalComponentName(entity:GetEntityID())

    local components = entity:GetComponents()
    if not components then return false end

    for i = 1, #components do
        local comp = components[i]
        if comp then
            local compName = Game.NameToString(comp:GetName())
            local className = Game.NameToString(comp:GetClassName())
            if string.find(className, "Mesh") then
                -- Match by tracked name first, then fall back to name patterns
                local isGenital = (genitalCompName and compName == genitalCompName)
                    or string.find(compName, "penis")
                    or string.find(compName, "genital")
                    or string.sub(compName, 1, 3) == "i0_"
                if isGenital then
                    comp.chunkMask = genitalMask
                    comp:Toggle(genitalMask ~= 0ULL)
                    print("[NakedNPC] Genital state switched to " .. (genitalState or "soft") .. " on " .. compName)
                    return true
                end
            end
        end
    end

    print("[NakedNPC] No genital component found to switch state")
    return false
end

return Stripper