--// Pet States Module
--// Manages pet state caching and updates

local PetStates = {}

function PetStates.Init()
    local PetAilmentCache = {}
    local PetState = setmetatable({}, {__mode = "k"})
    local dirtyPetState = setmetatable({}, {__mode = "k"})
    local sleepyPetState = setmetatable({}, {__mode = "k"})

    local function updatePetState(pet, data)
        if not pet or type(data) ~= "table" then
            return
        end
        local state = PetState[pet]
        if not state then
            state = {}
            PetState[pet] = state
        end
        for key, value in pairs(data) do
            state[key] = value
        end
    end

    local function addAilmentKey(normalized, key)
        if not key then
            return
        end
        local lower = tostring(key):lower()
        if lower ~= "" then
            normalized[lower] = true
        end
    end

    local function collectAilmentKeys(ailmentData, normalized)
        if type(ailmentData) ~= "table" then
            return
        end
        if ailmentData.ailment_key then
            addAilmentKey(normalized, ailmentData.ailment_key)
        end
        if ailmentData.kind then
            addAilmentKey(normalized, ailmentData.kind)
        end
        if ailmentData.ailment_name then
            addAilmentKey(normalized, ailmentData.ailment_name)
        end
        if type(ailmentData.components) == "table" then
            for subName, subData in pairs(ailmentData.components) do
                addAilmentKey(normalized, subName)
                collectAilmentKeys(subData, normalized)
            end
        end
    end

    local function markPetDirty(pet, value)
        if pet and pet:IsA("Model") then
            dirtyPetState[pet] = value
            local petId = tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
            if petId then
                local cache = PetAilmentCache[petId]
                if value then
                    cache = cache or {}
                    cache.dirty = true
                    PetAilmentCache[petId] = cache
                elseif cache then
                    cache.dirty = nil
                end
            end
        end
    end

    local function markPetSleepy(pet, value)
        if pet and pet:IsA("Model") then
            sleepyPetState[pet] = value
            local petId = tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
            if petId then
                local cache = PetAilmentCache[petId]
                if value then
                    cache = cache or {}
                    cache.sleepy = true
                    PetAilmentCache[petId] = cache
                elseif cache then
                    cache.sleepy = nil
                end
            end
        end
    end

    local function markPetToilet(pet, value)
        if pet and pet:IsA("Model") then
            local petId = tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
            if petId then
                local cache = PetAilmentCache[petId]
                if value then
                    cache = cache or {}
                    cache.toilet = true
                    PetAilmentCache[petId] = cache
                elseif cache then
                    cache.toilet = nil
                end
            end
        end
    end

    local function updateAilmentCache(petId, ailmentTable)
        if type(ailmentTable) ~= "table" then
            return {}
        end
        local normalized = {}
        for ailmentName, ailmentData in pairs(ailmentTable) do
            local lower = tostring(ailmentName):lower()
            normalized[lower] = ailmentData
            addAilmentKey(normalized, lower)
            collectAilmentKeys(ailmentData, normalized)
        end
        PetAilmentCache[tostring(petId)] = normalized
        return normalized
    end

    return {
        PetAilmentCache = PetAilmentCache,
        PetState = PetState,
        dirtyPetState = dirtyPetState,
        sleepyPetState = sleepyPetState,
        updatePetState = updatePetState,
        addAilmentKey = addAilmentKey,
        collectAilmentKeys = collectAilmentKeys,
        markPetDirty = markPetDirty,
        markPetSleepy = markPetSleepy,
        markPetToilet = markPetToilet,
        updateAilmentCache = updateAilmentCache,
    }
end

return PetStates
