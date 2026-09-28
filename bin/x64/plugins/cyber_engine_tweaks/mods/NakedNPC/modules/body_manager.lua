-- NakedNPC - Body Manager Module
-- ================================
-- Manages universal nude body mesh paths per body type.
-- Users can override paths via config or body_meshes.json.
--
-- Genital handling uses a single mesh with chunkMask to control state:
--   chunkMask = 0ULL  → hidden (soft/default)
--   chunkMask = 1ULL  → submesh_00 (soft variant, if available)
--   chunkMask = 2ULL  → submesh_01 (cut)
--   chunkMask = 4ULL  → submesh_02 (laid back uncut)
--   chunkMask = 8ULL  → submesh_03 (laid back cut / erect)

local BodyManager = {}

local meshDataPath = "data/body_meshes.json"

-- Default mesh paths
-- body    = full nude torso mesh (swapped onto t0_ during OnRequestComponents)
-- genitals = genital mesh path (repurposed onto an i1_ component during OnRequestComponents)
--
-- Male body: no path set — vanilla stub mesh is used with chunkMask = ALL.
-- Install a male body mod (e.g. Adonis, Gymfiend) and set the body path
-- to get a seamless result. Without a body mod, seams will be visible.
--
-- Genital chunkMasks (Bag of Dicks mesh submeshes):
--   softMask  = 0ULL  (hidden — no soft submesh available yet)
--   erectMask = 8ULL  (submesh_03 = laid back cut / erect)
local defaultMeshes = {
    female_average = {
        body = "base\\characters\\common\\base_bodies\\woman_average\\t0_000_wa_base__full.mesh",
        -- genitals = nil  (female genitals not currently supported)
    },
    male_average = {
        -- body = nil  (no male body mod installed — vanilla stub used)
        -- To enable: set this to your male body mod's full body mesh path
        -- e.g. body = "base\\adonis\\meshes\\t0_000_ma_base__full.mesh"
        genitals  = "dp77\\x_dicks\\meshes\\i1_penis_regular_pma.mesh",
        body = "base\\characters\\common\\base_bodies\\man_average\\t0_000_ma_base__full.mesh",
        softMask  = 0ULL,   -- hidden (no soft submesh yet)
        erectMask = 8ULL    -- submesh_03
    },
    male_big = {
        -- body = nil  (no male body mod installed — vanilla stub used)
        genitals  = "dp77\\x_dicks\\meshes\\i1_penis_regular_pma.mesh",
        softMask  = 0ULL,
        erectMask = 8ULL
    }
}

local meshData = {}

-- -------------------------------------------------------
--  INIT
-- -------------------------------------------------------

function BodyManager.Init()
    -- Try to load from JSON file
    -- local file = io.open(meshDataPath, "r")
    -- if file then
    --     local content = file:read("*a")
    --     file:close()
    --     local ok, loaded = pcall(json.decode, content)
    --     if ok and type(loaded) == "table" then
    --         meshData = loaded
    --         print("[NakedNPC] Body mesh data loaded from " .. meshDataPath)
    --         return
    --     end
    -- end

    meshData = defaultMeshes
    print("[NakedNPC] Using default body mesh paths")
end

-- -------------------------------------------------------
--  QUERIES
-- -------------------------------------------------------

--- Map NakedNPCBodyType enum int to our key string.
--- @param bodyTypeInt integer - 1=Female, 2=Male, 3=MaleBig
--- @return string
local function bodyTypeToKey(bodyTypeInt)
    if bodyTypeInt == 1 then return "female_average" end
    if bodyTypeInt == 2 then return "male_average" end
    if bodyTypeInt == 3 then return "male_big" end
    return "female_average"
end

--- Get a mesh depot path for a body type and part.
--- @param bodyTypeInt integer - 1=Female, 2=Male, 3=MaleBig
--- @param part string - "body" or "genitals"
--- @return string|nil
function BodyManager.GetMeshPath(bodyTypeInt, part)
    local key = bodyTypeToKey(bodyTypeInt)
    part = part or "body"

    if meshData[key] and meshData[key][part] then
        return meshData[key][part]
    end

    if defaultMeshes[key] and defaultMeshes[key][part] then
        return defaultMeshes[key][part]
    end

    return nil
end

--- Get the chunkMask for a genital state.
--- @param bodyTypeInt integer
--- @param genitalState string - "erect" or anything else = soft/hidden
--- @return userdata - ULL chunkMask value
function BodyManager.GetGenitalMask(bodyTypeInt, genitalState)
    local key = bodyTypeToKey(bodyTypeInt)
    local data = meshData[key] or defaultMeshes[key] or {}

    if genitalState == "erect" then
        return data.erectMask or 8ULL
    else
        return data.softMask or 0ULL
    end
end

--- Get all mesh paths for a body type.
--- @param bodyTypeInt integer
--- @return table
function BodyManager.GetAllMeshPaths(bodyTypeInt)
    local key = bodyTypeToKey(bodyTypeInt)
    return meshData[key] or defaultMeshes[key] or {}
end

--- Get the body type key names (for UI iteration).
function BodyManager.GetBodyTypes()
    return { "female_average", "male_average", "male_big" }
end

--- Get human-readable display name for a body type key.
function BodyManager.GetDisplayName(key)
    local names = {
        female_average = "Female (Average)",
        male_average   = "Male (Average)",
        male_big       = "Male (Big)"
    }
    return names[key] or key
end

--- Override a mesh path (from config or UI).
function BodyManager.SetMeshPath(bodyTypeKey, part, path)
    if not meshData[bodyTypeKey] then
        meshData[bodyTypeKey] = {}
    end
    meshData[bodyTypeKey][part] = path
end

--- Save current mesh data to JSON file.
function BodyManager.Save()
    local ok, encoded = pcall(json.encode, meshData)
    if ok then
        local file = io.open(meshDataPath, "w")
        if file then
            file:write(encoded)
            file:close()
            print("[NakedNPC] Body mesh data saved")
        end
    end
end

--- Get the mesh appearance name for a body type.
--- @param bodyTypeInt integer
--- @return string|nil
function BodyManager.GetBodyAppearance(bodyTypeInt)
    local key = bodyTypeToKey(bodyTypeInt)
    if meshData[key] and meshData[key].bodyAppearance then
        return meshData[key].bodyAppearance
    end
    if defaultMeshes[key] and defaultMeshes[key].bodyAppearance then
        return defaultMeshes[key].bodyAppearance
    end
    return nil
end

return BodyManager