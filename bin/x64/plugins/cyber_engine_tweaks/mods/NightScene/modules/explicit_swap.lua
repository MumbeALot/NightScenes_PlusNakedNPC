-- NightScene Framework - Explicit Entity Swap
-- ==============================================
-- Replaces a real NPC with their nude counterpart from BONeill's "O'Neill's
-- Explicit Content" for the duration of a scene:
--
--   1. ExplicitMatcher picks the entity and nude appearance (nil = not covered,
--      caller falls back to NakedNPC's strip).
--   2. Spawn that entity at the NPC's exact position and orientation.
--   3. Hide the real NPC once the stand-in has actually arrived.
--   4. The scene plays on the stand-in instead of the real NPC.
--   5. Restore: despawn the stand-in, unhide the original.
--
-- The original is HIDDEN, never despawned -- quest NPCs have to survive this.
-- Hiding means TemporaryHide(true) on every visual component, which is the only
-- approach that actually worked in testing: SetInvisible() doesn't exist on NPC
-- objects, and teleporting them away is crude and risks them pathing back.
--
-- Components are enumerated through Codeware's Entity:GetComponents().

local ExplicitSwap = {}

local ok, ExplicitMatcher = pcall(require, "modules/explicit_matcher")
if not ok then
    print("[NightScene] Swap: ERROR loading matcher: " .. tostring(ExplicitMatcher))
    ExplicitMatcher = { FindForNPC = function() return nil, { reason = "matcher failed to load" } end }
end

-- One record per swapped actor. Keyed by nothing in particular -- the list is
-- short (scene actors) and always walked in full.
ExplicitSwap.records = {}

-- ------------------------------------------------------------
--  COMPONENT HIDING
-- ------------------------------------------------------------

local function getComponents(npc)
    local okc, comps = pcall(function() return npc:GetComponents() end)
    if okc and type(comps) == "table" and #comps > 0 then return comps end

    -- Dev-tool fallback; not something the mod ships a dependency on.
    if RedHotTools and RedHotTools.GetEntityComponents then
        local ok2, comps2 = pcall(RedHotTools.GetEntityComponents, npc)
        if ok2 and type(comps2) == "table" then return comps2 end
    end
    return nil
end

--- Mesh-bearing components -- the ones that actually draw the character.
local function isVisual(comp)
    local cls = ""
    pcall(function() cls = Game.NameToString(comp:GetClassName()) end)
    return cls:find("Mesh") ~= nil or cls:find("Cloth") ~= nil or cls:find("Garment") ~= nil
end

--- Hide every visual component, returning the list so it can be undone.
local function hideEntity(npc)
    local comps = getComponents(npc)
    if not comps then return nil end

    local hidden = {}
    for _, comp in ipairs(comps) do
        if isVisual(comp) then
            local okh = pcall(function() comp:TemporaryHide(true) end)
            if okh then table.insert(hidden, comp) end
        end
    end

    if #hidden == 0 then return nil end
    return hidden
end

local function unhideComponents(hidden)
    for _, comp in ipairs(hidden or {}) do
        pcall(function() comp:TemporaryHide(false) end)
    end
end

-- ------------------------------------------------------------
--  SWAP LIFECYCLE
-- ------------------------------------------------------------

--- Spawn a stand-in for `npc`, or return nil if the explicit mod doesn't cover
--- them. Returns the record; the stand-in resolves later in OnUpdate().
function ExplicitSwap.Begin(npc)
    if not npc then return nil end

    local match, info = ExplicitMatcher.FindForNPC(npc)
    if not match then
        print("[NightScene] Swap: " .. tostring(info and info.record or "?")
            .. " not covered (" .. tostring(info and info.reason or "?")
            .. ") -- using NakedNPC strip")
        return nil
    end

    -- Spawn AMM's TweakDB record for this entity, not the raw .ent template.
    -- AMM clones a real Character record for every Collab entity and points its
    -- entityTemplatePath at the .ent; spawning the template directly gives an
    -- entity with meshes but no puppet or animation rig, so the workspot system
    -- has nothing to drive and the body just stands there doing nothing.
    local recordID = match.entity.record
    if not recordID or recordID == "" then
        print("[NightScene] Swap: " .. match.entity.name
            .. " has no AMM record in the manifest (regenerate it) -- using NakedNPC strip")
        return nil
    end

    -- AMM registers these records at startup. If it hasn't (AMM missing, or the
    -- explicit mod's Collabs not installed), there's nothing to spawn.
    local hasRecord = false
    pcall(function() hasRecord = TweakDB:GetRecord(recordID) ~= nil end)
    if not hasRecord then
        print("[NightScene] Swap: AMM has not registered " .. recordID
            .. " -- using NakedNPC strip")
        return nil
    end

    -- Spawn where the NPC is standing. The stand-in gets put into the workspot
    -- straight after, which positions it properly anyway; this just avoids it
    -- appearing somewhere visible in the meantime.
    local spawnID
    local oks = pcall(function()
        local spec = DynamicEntitySpec.new()
        spec.recordID = TweakDBID.new(recordID)
        spec.appearanceName = CName.new(match.appearance)
        spec.persistState = false
        spec.persistSpawn = false
        spec.alwaysSpawned = true
        spec.spawnInView = true
        spec.position = npc:GetWorldPosition()
        spec.orientation = npc:GetWorldOrientation()

        spawnID = Game.GetDynamicEntitySystem():CreateEntity(spec)
    end)

    if not oks or not spawnID then
        print("[NightScene] Swap: failed to spawn " .. match.entity.name .. " -- using NakedNPC strip")
        return nil
    end

    local record = {
        original = npc,
        originalID = npc:GetEntityID(),
        entity = match.entity,
        appearance = match.appearance,
        method = match.method,
        spawnID = spawnID,
        standIn = nil,
        hidden = nil,
    }
    table.insert(ExplicitSwap.records, record)

    print("[NightScene] Swap: " .. tostring(info.record) .. " -> " .. match.entity.name
        .. " as '" .. match.appearance .. "' (via " .. match.method .. ")")
    return record
end

--- Resolve spawned stand-ins and hide their originals. Call every frame while
--- the spawner is polling -- entities aren't available the frame they're asked
--- for, the same as the V clone.
function ExplicitSwap.OnUpdate()
    for _, record in ipairs(ExplicitSwap.records) do
        if record.spawnID and not record.standIn then
            local ent = Game.FindEntityByID(record.spawnID)
            if ent then
                record.standIn = ent

                -- Hide the original only now, so there's never a moment with
                -- nobody standing there.
                record.hidden = hideEntity(record.original)
                if record.hidden then
                    print("[NightScene] Swap: " .. record.entity.name .. " ready, original hidden ("
                        .. #record.hidden .. " components)")
                else
                    print("[NightScene] Swap: " .. record.entity.name
                        .. " ready, but could not hide the original -- both will be visible")
                end
            end
        end
    end
end

--- True once every stand-in has spawned.
function ExplicitSwap.AllReady()
    for _, record in ipairs(ExplicitSwap.records) do
        if not record.standIn then return false end
    end
    return true
end

--- The stand-in standing in for this actor, if there is one.
function ExplicitSwap.GetStandIn(npc)
    if not npc then return nil end
    local record = ExplicitSwap.FindRecord(npc)
    return record and record.standIn or nil
end

function ExplicitSwap.FindRecord(npc)
    if not npc then return nil end

    local hash
    pcall(function() hash = tostring(npc:GetEntityID().hash) end)
    if not hash then return nil end

    for _, record in ipairs(ExplicitSwap.records) do
        local otherHash
        pcall(function() otherHash = tostring(record.originalID.hash) end)
        if otherHash == hash then return record end
    end
    return nil
end

function ExplicitSwap.IsActive()
    return #ExplicitSwap.records > 0
end

--- Every stand-in currently in play, for the caller to stop in the workspot.
function ExplicitSwap.StandIns()
    local out = {}
    for _, record in ipairs(ExplicitSwap.records) do
        if record.standIn then table.insert(out, record.standIn) end
    end
    return out
end

--- Despawn every stand-in and put the real NPCs back. Safe to call at any
--- point, including when a scene was cancelled before the stand-ins resolved.
function ExplicitSwap.RestoreAll()
    for _, record in ipairs(ExplicitSwap.records) do
        -- Unhide first: if the despawn throws, the real NPC is still visible
        -- rather than being left permanently invisible in the world.
        if record.hidden then
            unhideComponents(record.hidden)
            record.hidden = nil
        end

        -- DeleteEntity matches CreateEntity; the Despawn is the same belt-and-
        -- braces pair the V clone teardown uses, in case the first doesn't take.
        if record.spawnID then
            pcall(function() Game.GetDynamicEntitySystem():DeleteEntity(record.spawnID) end)
        end
        if record.standIn then
            pcall(function() exEntitySpawner.Despawn(record.standIn) end)
        end

        print("[NightScene] Swap: restored " .. tostring(record.entity and record.entity.name or "?"))
    end

    ExplicitSwap.records = {}
end

return ExplicitSwap
