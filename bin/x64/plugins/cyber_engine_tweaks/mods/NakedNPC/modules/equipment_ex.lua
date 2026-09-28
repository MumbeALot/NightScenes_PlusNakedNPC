-- NakedNPC - Equipment-EX Bridge
-- ================================
-- Equipment-EX (https://github.com/psiberx/cp2077-equipment-ex) takes over the
-- player's outfit system. While its outfit mode is active, the vanilla
-- TransactionSystem unequip path NakedNPCSystem uses has no visible effect --
-- which is why Clone V kept its underwear on for users who had it installed.
--
-- This module routes player stripping through Equipment-EX's own console
-- commands when it's present, and reports "not available" otherwise so the
-- caller can fall back to the vanilla path.
--
-- PLAYER ONLY. Equipment-EX manages the player's outfit; it has no concept of
-- NPC equipment, so NPCs must keep using the normal ComponentStripper path.

local EquipmentEx = {}

-- nil = not probed yet, true/false = probe result (cached per session)
EquipmentEx.available = nil

-- Index into the candidate invocation list that actually worked, cached so we
-- only pay for the probe once.
EquipmentEx.callForm = nil

-- Reserved outfit name used to stash the player's pre-scene outfit so it can be
-- restored afterwards. Deleted again on restore.
EquipmentEx.backupOutfit = "__NakedNPC_Backup__"

EquipmentEx.hasBackup = false

-- Names of the user-saved Equipment-EX outfit to strip into. Equipment-EX users
-- are REQUIRED to have saved an outfit under one of these names.
--
-- Listed in DESCENDING priority order -- first match wins. We resolve these
-- against the real saved-outfit list (see FindOutfitName), matched
-- case-insensitively, so an outfit saved as "NUDE" or "Nude" is found too.
EquipmentEx.outfitNames = { "naked", "nude" }

-- One-time hint so a user who hasn't made the outfit yet finds out why V is
-- still dressed, without spamming it on every scene.
EquipmentEx.hintShown = false

-- ------------------------------------------------------------
--  INVOCATION
-- ------------------------------------------------------------
-- Equipment-EX's commands live on `public abstract class EquipmentEx` in
-- scripts/Facade.reds, so CET addresses them as "EquipmentEx::Method" (double
-- colon -- same as our own NightSceneAPI statics), NOT "EquipmentEx.Method".
--
-- Every one of them takes `game: GameInstance` as its FIRST parameter, and the
-- name parameters are typed per-function -- LoadOutfit/DeleteOutfit want a
-- CName while SaveOutfit wants a String. Passing a plain Lua string to
-- LoadOutfit silently does nothing.

-- argType: nil = no argument beyond GameInstance
-- (Version is the one exception -- it takes no GameInstance at all -- but the
-- candidate list below covers that shape anyway.)
local COMMANDS = {
    Version      = { argType = nil },
    Activate     = { argType = nil },
    Reactivate   = { argType = nil },
    Deactivate   = { argType = nil },
    UnequipAll   = { argType = nil },
    PrintOutfits = { argType = nil },
    LoadOutfit   = { argType = "CName" },
    DeleteOutfit = { argType = "CName" },
    SaveOutfit   = { argType = "String" },
}

--- CET may or may not need the GameInstance passed explicitly.
local function gameInstance()
    local ok, gi = pcall(function() return GetGameInstance() end)
    if ok and gi ~= nil then return gi end
    ok, gi = pcall(function() return Game.GetGameInstance() end)
    if ok then return gi end
    return nil
end

local function buildCandidates(funcName, arg)
    local spec = COMMANDS[funcName] or { argType = nil }

    -- Convert the Lua value to the type the Redscript signature declares.
    -- Guarded: this runs outside the pcall loop below, so an unavailable
    -- CName constructor must not throw out of Call() and abort the scene.
    local typedArg = nil
    if spec.argType == "CName" then
        local ok, converted = pcall(function() return CName.new(arg) end)
        typedArg = ok and converted or arg
    elseif spec.argType == "String" then
        typedArg = tostring(arg)
    end

    local base = "EquipmentEx::" .. funcName
    local withGI = base .. ";GameInstance" .. (spec.argType or "")
    local withoutGI = base .. ";" .. (spec.argType or "")
    local gi = gameInstance()

    return {
        -- GameInstance declared in the signature AND passed explicitly
        function()
            if typedArg ~= nil then return Game[withGI](gi, typedArg) end
            return Game[withGI](gi)
        end,
        -- GameInstance declared but auto-injected by CET
        function()
            if typedArg ~= nil then return Game[withGI](typedArg) end
            return Game[withGI]()
        end,
        -- GameInstance omitted from the signature, auto-injected
        function()
            if typedArg ~= nil then return Game[withoutGI](typedArg) end
            return Game[withoutGI]()
        end,
        -- No signature suffix at all
        function()
            if typedArg ~= nil then return Game[base](typedArg) end
            return Game[base]()
        end,
    }
end

--- Invoke an Equipment-EX command. Returns true if the call went through.
--- NOTE: a `true` here only means the function existed and didn't error -- it
--- does NOT confirm the command had the intended effect (e.g. LoadOutfit with a
--- name that doesn't exist is a silent no-op).
function EquipmentEx.Call(funcName, arg)
    local candidates = buildCandidates(funcName, arg)

    -- Already know which form works: try it first, but fall through to a full
    -- re-probe if it fails, since arities differ between commands.
    if EquipmentEx.callForm and pcall(candidates[EquipmentEx.callForm]) then
        return true
    end

    for i, fn in ipairs(candidates) do
        local ok = pcall(fn)
        if ok then
            if EquipmentEx.callForm ~= i then
                EquipmentEx.callForm = i
                print("[NakedNPC] Equipment-EX: using call form " .. i .. " for " .. funcName)
            end
            return true
        end
    end

    return false
end

-- The EquipmentEx facade's LoadOutfit returns nothing, so it can't tell us
-- whether the outfit actually existed. The underlying OutfitSystem
-- ScriptableSystem exposes far better primitives:
--     GetOutfits() -> array<CName>
--     HasOutfit(name: CName) -> Bool
--     LoadOutfit(name: CName) -> Bool     <- real success signal
-- Declared here (above IsAvailable) because Lua locals are only in scope from
-- their declaration onward.
local function getOutfitSystem()
    local ok, sys = pcall(function()
        return Game.GetScriptableSystemsContainer():Get(CName.new("EquipmentEx.OutfitSystem"))
    end)
    if ok and sys then return sys end
    return nil
end

--- Is Equipment-EX present and callable? Probes once with a harmless command.
function EquipmentEx.IsAvailable()
    if EquipmentEx.available ~= nil then
        return EquipmentEx.available
    end

    -- Prefer the ScriptableSystem: if it resolves, Equipment-EX is installed.
    -- This replaced a PrintOutfits probe, which worked but made Equipment-EX
    -- dump the player's entire saved-outfit list to the console every session.
    if getOutfitSystem() ~= nil then
        EquipmentEx.available = true
        print("[NakedNPC] Equipment-EX detected")
        return true
    end

    -- Fallback probe: Version() is the only facade call with no side effects
    -- and no console output.
    EquipmentEx.available = EquipmentEx.Call("Version")

    if not EquipmentEx.available then
        print("[NakedNPC] Equipment-EX not detected, using vanilla unequip path")
    end
    return EquipmentEx.available
end

-- ------------------------------------------------------------
--  OUTFIT SYSTEM (direct access)
-- ------------------------------------------------------------

--- Resolve one of EquipmentEx.outfitNames against the player's actual saved
--- outfits, matched case-insensitively. Returns (CName, displayString) or nil.
--- CName is a hash of the exact string, so "nude" and "NUDE" are NOT the same
--- name -- this is why loading a hardcoded lowercase "nude" silently did
--- nothing for an outfit actually saved as "NUDE".
function EquipmentEx.FindOutfitName()
    local sys = getOutfitSystem()
    if not sys then return nil end

    local ok, outfits = pcall(function() return sys:GetOutfits() end)
    if not ok or not outfits then return nil end

    for _, wanted in ipairs(EquipmentEx.outfitNames) do
        for _, entry in ipairs(outfits) do
            local okName, asString = pcall(function() return Game.NameToString(entry) end)
            if okName and asString and asString:lower() == wanted:lower() then
                return entry, asString
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------
--  STRIP / RESTORE (player only)
-- ------------------------------------------------------------

--- Strip the player via Equipment-EX, backing up the current outfit first.
function EquipmentEx.StripPlayer()
    if not EquipmentEx.IsAvailable() then return false end

    -- Make sure outfit mode is on, otherwise the outfit commands have nothing
    -- to act on. Activate() clones the current equipment, so this is safe to
    -- call even when it's already active.
    EquipmentEx.Call("Activate")

    -- Back up the current outfit so RestorePlayer can put it back. Clear any
    -- stale backup first, since SaveOutfit won't overwrite an existing name.
    EquipmentEx.Call("DeleteOutfit", EquipmentEx.backupOutfit)
    EquipmentEx.hasBackup = EquipmentEx.Call("SaveOutfit", EquipmentEx.backupOutfit)

    -- Preferred path: resolve the real saved-outfit name (case-insensitively)
    -- and load it through OutfitSystem, which reports actual success.
    local sys = getOutfitSystem()
    local cname, displayName = EquipmentEx.FindOutfitName()

    if sys and cname then
        local ok, loaded = pcall(function() return sys:LoadOutfit(cname) end)
        if ok and loaded then
            print("[NakedNPC] Equipment-EX: loaded outfit '" .. displayName .. "'")
            return true
        end
        print("[NakedNPC] Equipment-EX: LoadOutfit('" .. displayName .. "') failed")
    elseif sys then
        -- We could read the outfit list and none of our names were in it.
        print("[NakedNPC] Equipment-EX: no saved outfit named "
            .. table.concat(EquipmentEx.outfitNames, " or ")
            .. " -- create one in Equipment-EX (it's required).")
        return false
    end

    -- Fallback: facade call, for when OutfitSystem isn't reachable. No success
    -- signal here, so we can't verify or fall back any further.
    local called = false
    for _, name in ipairs(EquipmentEx.outfitNames) do
        if EquipmentEx.Call("LoadOutfit", name) then
            called = true
        end
    end

    if called and not EquipmentEx.hintShown then
        EquipmentEx.hintShown = true
        print("[NakedNPC] Equipment-EX: requested outfit via facade (unverified). "
            .. "If V is still clothed, check the outfit name.")
    end
    return called
end

--- Restore the player's pre-scene outfit.
function EquipmentEx.RestorePlayer()
    if not EquipmentEx.IsAvailable() then return false end

    if not EquipmentEx.hasBackup then
        -- Nothing stashed -- fall back to Equipment-EX's own last-used outfit.
        return EquipmentEx.Call("Reactivate")
    end

    local ok = EquipmentEx.Call("LoadOutfit", EquipmentEx.backupOutfit)
    EquipmentEx.Call("DeleteOutfit", EquipmentEx.backupOutfit)
    EquipmentEx.hasBackup = false

    if ok then
        print("[NakedNPC] Equipment-EX: restored player outfit")
    end
    return ok
end

return EquipmentEx
