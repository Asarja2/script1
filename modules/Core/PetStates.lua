--// Pet States Module
--// Manages pet state caching and updates

local PetStates = {}

local TRACKED_AILMENTS = {
    "sleepy",
    "dirty",
    "hungry",
    "thirsty",
    "toilet",
    "school",
    "pet_me",
}

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

    local function ingestAilmentEntry(normalized, ailmentName, ailmentData)
        addAilmentKey(normalized, ailmentName)
        if type(ailmentData) ~= "table" then
            return
        end
        addAilmentKey(normalized, ailmentData.kind)
        addAilmentKey(normalized, ailmentData.ailment_key)
        addAilmentKey(normalized, ailmentData.ailment_name)
        if type(ailmentData.components) == "table" then
            for subName, subData in pairs(ailmentData.components) do
                addAilmentKey(normalized, subName)
                if type(subData) == "table" then
                    addAilmentKey(normalized, subData.kind)
                    addAilmentKey(normalized, subData.ailment_key)
                end
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
            ingestAilmentEntry(normalized, ailmentName, ailmentData)
            if type(ailmentData) == "table" and ailmentData.kind then
                print("PET:", petId, "AILMENT kind=", ailmentData.kind)
            else
                print("PET:", petId, "AILMENT:", ailmentName)
            end
        end
        PetAilmentCache[tostring(petId)] = normalized
        return normalized
    end

    local function syncFromAilmentsManager(data)
        if type(data) ~= "table" or type(data.ailments) ~= "table" then
            return
        end
        for petId, ailmentTable in pairs(data.ailments) do
            updateAilmentCache(petId, ailmentTable)
        end
    end

    return {
        PetAilmentCache = PetAilmentCache,
        PetState = PetState,
        dirtyPetState = dirtyPetState,
        sleepyPetState = sleepyPetState,
        TRACKED_AILMENTS = TRACKED_AILMENTS,
        updatePetState = updatePetState,
        addAilmentKey = addAilmentKey,
        ingestAilmentEntry = ingestAilmentEntry,
        markPetDirty = markPetDirty,
        markPetSleepy = markPetSleepy,
        markPetToilet = markPetToilet,
        updateAilmentCache = updateAilmentCache,
        syncFromAilmentsManager = syncFromAilmentsManager,
    }
end

return PetStates
