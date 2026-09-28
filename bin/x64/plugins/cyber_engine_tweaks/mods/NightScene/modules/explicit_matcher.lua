-- NightScene Framework - Explicit Entity Matcher
-- =================================================
-- Maps an in-world NPC to a BONeill "O'Neill's Explicit Content" entity and the
-- nude appearance to spawn it in. The entity list comes from
-- anims/explicit_manifest.lua (regenerate with tools/generate_explicit_manifest.ps1).
--
-- The explicit mod uses two different naming schemes, so matching runs in tiers:
--
--   A. Appearance match -- faction files (Maelstrom, Tyger Claws, Valentinos,
--      Voodoo Boys, Mox, Us Cracks) and a few named characters (Hasan, Paco,
--      Mama Welles) reuse in-world appearance names with "_nude" appended. An
--      in-world "gang__maelstrom_wa_fast__lvl3_02" ends with the entity's
--      "fast__lvl3_02", so we suffix-match against the real appearance list.
--      Suffix matching copes with every prefix shape at once, including the
--      leading-underscore names like "_sq011__patricia".
--
--   B. Variant fallback -- same archetype and level, different variant number
--      ("fast__lvl3_01" -> "fast__lvl3_02"). Same archetype in a different
--      outfit, which stops mattering once the character is nude.
--
--   B2. Archetype fallback -- same role, nearest level bracket
--      ("biker__lvl3_05" -> "biker__lvl2_03"). The explicit mod doesn't cover
--      every level of every faction. Only runs once the faction is pinned
--      down by a shared token, since "biker" alone spans every gang.
--
--   C. Identity match -- most named characters only have "default" / "nude",
--      unrelated to their in-world appearance names. Match tokens from the
--      NPC's RECORD ID ("Character.mr_hands" -> "hands") against the entity's
--      file name, display name and path. Path alone isn't enough: Mr. Hands'
--      entity lives under "wade_bleecker", but his file is "Hands_Explicit".
--      Appearance-name tokens are deliberately excluded here -- they're full
--      of descriptor words, and would let a random citizen whose outfit
--      contains "young" match Rogue Young.
--
--   D. Faction fallback -- a gang member whose role the mod doesn't cover at
--      all (Maelstrom has no netrunner) borrows another nude body from their
--      OWN faction, chosen by a stable hash so it doesn't change between
--      scenes and isn't the same model for every unmatched grunt.
--
-- Anything unmatched returns nil so the caller can fall back to NakedNPC's strip.

local ExplicitMatcher = {}

-- Record ID -> manifest file name, checked before any automatic matching. Use
-- this for NPCs the matcher gets wrong or can't disambiguate (it refuses ties
-- rather than guessing -- e.g. Rogue Old vs Rogue Young both tokenize to "rogue").
ExplicitMatcher.overrides = {
    -- ["Character.rogue"] = "Rogue_Young_Explicit",
}

-- NightSceneGender enum values, as returned by NightSceneAPI.DetectEntityGender
local GENDER_MALE, GENDER_FEMALE, GENDER_MALE_BIG = 1, 2, 3
local GENDER_NAMES = { [GENDER_MALE] = "Male", [GENDER_FEMALE] = "Female", [GENDER_MALE_BIG] = "Male Big" }

-- Tokens that say nothing about identity: framework words, NPC categories and
-- gender words. Gender words especially must not count, or "Maelstrom Women"
-- would score an identity match against every female NPC.
-- Descriptor words (young/old/lady) are excluded too: on their own they'd
-- match Rogue Young / Rogue Old / Soulkiller Lady against unrelated NPCs.
local STOPWORDS = {
    explicit = true, amm = true, ent = true, boneill = true, photomode = true,
    character = true, default = true, service = true, fixer = true, gang = true,
    citizen = true, male = true, female = true, men = true, women = true,
    big = true, new = true, appearances = true, the = true,
    young = true, old = true, lady = true,
}

local manifest = nil

-- ------------------------------------------------------------
--  HELPERS
-- ------------------------------------------------------------

local function startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

--- Add identity tokens from `str` into the `into` set.
local function tokenize(str, into)
    into = into or {}
    for tok in string.gmatch(string.lower(str or ""), "[a-z0-9]+") do
        if #tok >= 3 and not STOPWORDS[tok]
            and not tok:match("^%d+$") and not tok:match("^lvl%d") then
            into[tok] = true
        end
    end
    return into
end

local function overlap(a, b)
    local n = 0
    for tok in pairs(a) do
        if b[tok] then n = n + 1 end
    end
    return n
end

--- Does `str` end with `suffix`, starting on a name boundary? Stops "lvl1_01"
--- from matching inside an unrelated longer name.
local function endsWithOnBoundary(str, suffix)
    if #suffix == 0 or #suffix > #str or str:sub(-#suffix) ~= suffix then
        return false
    end
    if #suffix == #str or startsWith(suffix, "_") then
        return true
    end
    return str:sub(#str - #suffix, #str - #suffix) == "_"
end

--- "fast__lvl3_01" -> "fast__lvl3"
local function stripVariant(name)
    return (name:gsub("_%d+$", ""))
end

--- "biker__lvl3_05" -> "biker" (archetype, any level)
local function stripFamily(name)
    return (name:gsub("__lvl%d+_%d+$", ""))
end

--- The level number in an appearance name, or nil.
local function lvlOf(name)
    return tonumber(name:match("__lvl(%d+)"))
end

local function hasAccessories(name)
    -- The mod spells it both ways: "accessoires" and (Imogen) "accessories".
    return name:find("accessoir", 1, true) ~= nil or name:find("accessori", 1, true) ~= nil
end

-- ------------------------------------------------------------
--  MANIFEST
-- ------------------------------------------------------------

local function loadManifest()
    if manifest then return manifest end
    manifest = {}

    local paths = {
        "anims/explicit_manifest.lua",
        "plugins/cyber_engine_tweaks/mods/NightScene/anims/explicit_manifest.lua",
    }

    for _, path in ipairs(paths) do
        local ok, data = pcall(dofile, path)
        if ok and type(data) == "table" then
            for _, entity in ipairs(data) do
                -- Base appearances are the non-nude ones -- what an in-world
                -- appearance name gets matched against.
                entity.bases = {}
                for _, app in ipairs(entity.appearances or {}) do
                    if not app:find("nude", 1, true) and not app:find("naked", 1, true) then
                        table.insert(entity.bases, app)
                    end
                end

                entity.tokens = tokenize(entity.file)
                tokenize(entity.name, entity.tokens)
                tokenize(entity.path, entity.tokens)

                table.insert(manifest, entity)
            end
            print("[NightScene] Explicit: loaded " .. #manifest .. " entities from " .. path)
            return manifest
        end
    end

    print("[NightScene] Explicit: explicit_manifest.lua not found -- explicit swaps disabled")
    return manifest
end

--- Pick the nude appearance to spawn. `base` is the matched in-world appearance
--- base, or nil to use the entity's generic nude ("nude", "default_nude", ...).
--- This has to be a ranked search rather than a fixed suffix: Valentinos Big
--- uses "_nude_bod_regular", Roxanne uses "default_nude_no_doll", etc.
--- Prefixes the nude variants of `base` can live under, most likely first.
--- Usually "<base>_nude", but the character-style files pair "<name>__default"
--- with a SIBLING "<name>__nude" instead of "<name>__default_nude" -- Us Cracks
--- ships "blue_moon__default" and "blue_moon__nude", so Blue Moon matched her
--- base appearance and then found no nude under it.
local function nudePrefixes(base)
    if not base then return { "nude", "default_nude" } end
    local prefixes = { base .. "_nude" }
    local stem = base:match("^(.-)default$")
    if stem then table.insert(prefixes, stem .. "nude") end
    return prefixes
end

local function pickNude(entity, base, isMale)
    for _, prefix in ipairs(nudePrefixes(base)) do
        local pool = {}
        for _, app in ipairs(entity.appearances) do
            if startsWith(app, prefix) then table.insert(pool, app) end
        end

        if #pool > 0 then
            local function find(pred)
                for _, app in ipairs(pool) do
                    if pred(app) then return app end
                end
            end

            local hit
            if isMale then
                -- Bag of Dicks "regular" size by default
                hit = find(function(a) return a == prefix .. "_regular" end)
                    or find(function(a) return a:find("regular", 1, true) ~= nil end)
                    or find(function(a) return a == prefix end)
                    or pool[1]
            else
                hit = find(function(a) return a == prefix end)
                    or find(function(a) return not hasAccessories(a) end)
                    or pool[1]
            end
            if hit then return hit end
        end
    end
    return nil
end

local function entityByFile(file)
    for _, entity in ipairs(loadManifest()) do
        if entity.file == file then return entity end
    end
end

-- ------------------------------------------------------------
--  MATCHING
-- ------------------------------------------------------------

local function describeNPC(npc)
    local info = { record = "", appearance = "", genderInt = 0 }

    pcall(function() info.record = TDBID.ToStringDEBUG(npc:GetRecordID()) end)
    pcall(function() info.appearance = Game.NameToString(npc:GetCurrentAppearanceName()) end)
    pcall(function() info.genderInt = Game['NightSceneAPI::DetectEntityGender;GameObject'](npc) end)

    info.isMale = (info.genderInt == GENDER_MALE or info.genderInt == GENDER_MALE_BIG)
    info.isBig = (info.genderInt == GENDER_MALE_BIG)

    -- recordTokens identify WHO the NPC is (identity matching).
    -- tokens add the appearance name too, which carries the faction
    -- ("gang__maelstrom_...") used to break ties in appearance matching.
    info.recordTokens = tokenize(info.record)
    info.appTokens = tokenize(info.appearance)
    info.tokens = tokenize(info.record)
    tokenize(info.appearance, info.tokens)
    return info
end

--- Entities whose gender matches the NPC. `requireSize` also matches Big vs
--- average build -- used for appearance matching, where a faction's Big entity
--- is a genuinely different body. Identity matching skips it, since named
--- characters only ship one entity each.
local function compatibleEntities(info, requireSize)
    local out = {}
    for _, entity in ipairs(loadManifest()) do
        local genderOk = (entity.gender == "male") == info.isMale
        local sizeOk = (not requireSize) or (entity.big == info.isBig)
        if genderOk and sizeOk then
            table.insert(out, entity)
        end
    end
    return out
end

--- Restrict `entities` to those sharing an identity token with the NPC's
--- appearance name -- the faction ("gang__maelstrom_..." -> Maelstrom) or band
--- ("us_cracks_..." -> Us Cracks). Without it, an archetype name matches
--- whichever faction happens to ship that exact variant: a Maelstrom
--- handgunner wearing "grunt__lvl2_04" resolved to VOODOO BOYS, because
--- Maelstrom Men stop at grunt__lvl2_03 and only Voodoo Boys had an _04.
--- Returns the original list (and false) when nothing shares a token, so
--- non-faction NPCs are unaffected.
local function narrowByFaction(entities, info)
    local out = {}
    for _, entity in ipairs(entities) do
        if overlap(info.appTokens, entity.tokens) > 0 then
            table.insert(out, entity)
        end
    end
    if #out > 0 then return out, true end
    return entities, false
end

--- mode: "exact" | "variant" (same archetype+level) | "family" (same archetype)
local REDUCE = { exact = function(s) return s end, variant = stripVariant, family = stripFamily }

local function appearanceCandidates(entities, info, mode)
    local reduce = REDUCE[mode]
    local subject = reduce(info.appearance)
    local wantLvl = lvlOf(info.appearance)
    local out = {}

    for _, entity in ipairs(entities) do
        for _, base in ipairs(entity.bases) do
            local key = reduce(base)
            -- Reduced matching only applies to bases the reduction actually
            -- shortened, and a bare "default" is too generic to suffix-match.
            if (mode == "exact" or key ~= base) and key ~= "default" and #key >= 3
                and endsWithOnBoundary(subject, key) then
                local nude = pickNude(entity, base, info.isMale)
                if nude then
                    -- Prefer the nearest level when falling back across levels.
                    local baseLvl = lvlOf(base)
                    local delta = (wantLvl and baseLvl) and math.abs(wantLvl - baseLvl) or 0
                    table.insert(out, {
                        entity = entity,
                        base = base,
                        key = key,
                        appearance = nude,
                        lvlDelta = math.min(delta, 9),
                        overlap = overlap(info.tokens, entity.tokens),
                    })
                end
            end
        end
    end
    return out
end

local function chooseAppearanceCandidate(candidates)
    -- Prefer candidates that also share an identity token (e.g. "maelstrom"),
    -- then the most specific (longest) base.
    local best, bestScore = nil, -1
    for _, c in ipairs(candidates) do
        if c.overlap > 0 then
            local score = c.overlap * 10000 + #c.key * 100 - c.lvlDelta
            if score > bestScore then
                best, bestScore = c, score
            end
        end
    end
    if best then return best end

    -- No shared token at all: only trust a faction-style ("__") base, and only
    -- when exactly one entity claims it. "grunt__lvl1_01" alone exists in half
    -- a dozen factions and can't tell them apart.
    local entities, pick, count = {}, nil, 0
    for _, c in ipairs(candidates) do
        if c.key:find("__", 1, true) then
            if not entities[c.entity] then
                entities[c.entity] = true
                count = count + 1
            end
            if not pick or #c.key > #pick.key then
                pick = c
            end
        end
    end
    return (count == 1) and pick or nil
end

--- Stable hash, so the same in-world appearance always draws the same body.
local function hashOf(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 2147483647
    end
    return h
end

--- Last resort for a gang NPC whose exact role the explicit mod doesn't cover
--- at all: any nude body from that same faction. Maelstrom has no netrunner
--- (only Voodoo Boys do), and borrowing across factions is what produced the
--- Voodoo Boys mismatch, so we stay inside the faction and pick a body by a
--- stable hash of the appearance name -- deterministic per NPC type, but not
--- the same model for every unmatched grunt in the gang.
local function factionFallback(entities, info)
    -- Only when one faction clearly owns this NPC.
    local entity, bestScore, tied = nil, 0, false
    for _, candidate in ipairs(entities) do
        local score = overlap(info.appTokens, candidate.tokens)
        if score > bestScore then
            entity, bestScore, tied = candidate, score, false
        elseif score == bestScore and score > 0 then
            tied = true
        end
    end
    if not entity or tied then return nil end

    -- Faction entities only -- a named character's single "default" body isn't
    -- a stand-in for anyone else.
    local pool = {}
    for _, base in ipairs(entity.bases) do
        if base:find("__lvl", 1, true) then
            local nude = pickNude(entity, base, info.isMale)
            if nude then table.insert(pool, nude) end
        end
    end
    if #pool == 0 then return nil end

    table.sort(pool)
    return { entity = entity, appearance = pool[(hashOf(info.appearance) % #pool) + 1] }
end

local function identityMatch(entities, info)
    local best, bestScore, tied = nil, 0, false

    for _, entity in ipairs(entities) do
        -- Record ID tokens only -- see the Tier C note at the top of the file.
        local score = overlap(info.recordTokens, entity.tokens)
        if score > 0 then
            -- Faction entities have no generic nude, so they drop out here.
            local nude = pickNude(entity, nil, info.isMale)
            if nude then
                if score > bestScore then
                    best, bestScore, tied = { entity = entity, appearance = nude }, score, false
                elseif score == bestScore then
                    tied = true
                end
            end
        end
    end

    if tied then
        return nil, "ambiguous identity match -- add an override"
    end
    return best
end

--- Find the explicit entity and nude appearance for an NPC.
--- Returns (match, info). `match` is nil when the NPC isn't covered.
function ExplicitMatcher.FindForNPC(npc)
    local info = describeNPC(npc)

    if #loadManifest() == 0 then
        info.reason = "no manifest"
        return nil, info
    end

    local overrideFile = ExplicitMatcher.overrides[info.record]
    if overrideFile then
        local entity = entityByFile(overrideFile)
        local nude = entity and pickNude(entity, nil, info.isMale)
        if nude then
            return { entity = entity, appearance = nude, method = "override" }, info
        end
        print("[NightScene] Explicit: override " .. info.record .. " -> " .. overrideFile
            .. " has no usable nude appearance, ignoring")
    end

    local sized, narrowed = narrowByFaction(compatibleEntities(info, true), info)

    local match = chooseAppearanceCandidate(appearanceCandidates(sized, info, "exact"))
    if match then
        match.method = "appearance"
        return match, info
    end

    if stripVariant(info.appearance) ~= info.appearance then
        match = chooseAppearanceCandidate(appearanceCandidates(sized, info, "variant"))
        if match then
            match.method = "variant"
            return match, info
        end
    end

    -- Archetype fallback: same role in a different level bracket, e.g. a Tyger
    -- Claw "biker__lvl3_05" borrowing "biker__lvl2_03". Only safe once the
    -- faction is pinned down -- "biker" and "grunt" mean nothing on their own.
    if narrowed then
        match = chooseAppearanceCandidate(appearanceCandidates(sized, info, "family"))
        if match then
            match.method = "archetype"
            return match, info
        end
    end

    local reason
    match, reason = identityMatch(compatibleEntities(info, false), info)
    if match then
        match.method = "identity"
        return match, info
    end

    if narrowed then
        match = factionFallback(sized, info)
        if match then
            match.method = "faction"
            return match, info
        end
    end

    info.reason = reason or "not covered by the explicit mod"
    return nil, info
end

--- Console helper: aim at an NPC and print what the matcher would pick.
---     GetMod("NightScene").DebugExplicitMatch()
function ExplicitMatcher.DebugLookAt()
    local ok, npc = pcall(function()
        local ts, player = Game.GetTargetingSystem(), Game.GetPlayer()
        return ts:GetLookAtObject(player, true, false) or ts:GetLookAtObject(player, false, false)
    end)
    if not ok or not npc then
        print("[NightScene] Explicit: no look-at target -- aim directly at an NPC")
        return nil
    end

    local match, info = ExplicitMatcher.FindForNPC(npc)
    print("[NightScene] Explicit: record=" .. info.record
        .. "  appearance=" .. info.appearance
        .. "  gender=" .. (GENDER_NAMES[info.genderInt] or "Unknown"))

    if match then
        print("[NightScene] Explicit: MATCH via " .. match.method
            .. " -> " .. match.entity.name .. " as '" .. match.appearance .. "'")
    else
        print("[NightScene] Explicit: no match (" .. info.reason .. ") -- would fall back to NakedNPC strip")
    end
    return match
end

return ExplicitMatcher
