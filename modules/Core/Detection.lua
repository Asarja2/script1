--// Ailment Detection — reads ailments_manager cache (kind / ailment_key)

local Detection = {}

local TRACKED_AILMENTS = {
    "sleepy",
    "dirty",
    "hungry",
    "thirsty",
    "toilet",
    "school",
    "pet_me",
}

function Detection.Init(PetAilmentCache, PetState)
    local function resolvePetId(pet)
        if not pet or not pet:IsA("Model") then
            return nil
        end
        return tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
    end

    local function getCacheForPet(pet)
        if not pet then
            return nil
        end
        local candidates = {}
        local unique = pet:GetAttribute("unique")
        local id = pet:GetAttribute("id")
        if unique then table.insert(candidates, tostring(unique)) end
        if id then table.insert(candidates, tostring(id)) end
        table.insert(candidates, pet.Name)

        for _, candidate in ipairs(candidates) do
            if PetAilmentCache[candidate] then
                return PetAilmentCache[candidate], candidate
            end
        end

        for cacheId, cache in pairs(PetAilmentCache) do
            local cacheStr = tostring(cacheId)
            for _, candidate in ipairs(candidates) do
                if cacheStr == candidate then
                    return cache, cacheId
                end
            end
        end

        local cacheCount, onlyCache, onlyId = 0, nil, nil
        for cacheId, cache in pairs(PetAilmentCache) do
            cacheCount = cacheCount + 1
            onlyCache = cache
            onlyId = cacheId
        end
        if cacheCount == 1 then
            return onlyCache, onlyId
        end

        return nil, nil
    end

    local function cacheHas(cache, ailmentName)
        if type(cache) ~= "table" then
            return false
        end
        return cache[tostring(ailmentName):lower()] == true
    end

    local function petHasAilment(pet, ailmentName)
        local cache = getCacheForPet(pet)
        return cacheHas(cache, ailmentName)
    end

    local function isNeed(pet, needName)
        return petHasAilment(pet, needName)
    end

    local function getPetState(pet)
        if not pet then
            return nil
        end
        return PetState[pet]
    end

    local function isSleeping(pet)
        local state = getPetState(pet)
        if not state then
            return false
        end
        for key, value in pairs(state) do
            if value and tostring(key):lower():match("sleep|asleep|focus") then
                return true
            end
        end
        return false
    end

    local function getActiveCacheKeys(pet)
        local cache = getCacheForPet(pet)
        if not cache then
            return {}
        end
        local keys = {}
        for key in pairs(cache) do
            table.insert(keys, tostring(key))
        end
        table.sort(keys)
        return keys
    end

    local function getTrackedNeeds(pet)
        local out = {}
        for _, name in ipairs(TRACKED_AILMENTS) do
            out[name] = isNeed(pet, name)
        end
        return out
    end

    local function debugPetNeeds(pet, source)
        if not pet then
            print("[PET NEEDS DEBUG]", source or "?", "no pet")
            return
        end
        local cache, cacheId = getCacheForPet(pet)
        local keys = table.concat(getActiveCacheKeys(pet), ", ")
        local needs = getTrackedNeeds(pet)
        local parts = {}
        for _, name in ipairs(TRACKED_AILMENTS) do
            table.insert(parts, name .. "=" .. tostring(needs[name]))
        end
        print(
            "[PET NEEDS DEBUG]",
            source or "?",
            "pet=" .. pet.Name,
            "resolveId=" .. tostring(resolvePetId(pet)),
            "cacheId=" .. tostring(cacheId),
            "| keys:", keys == "" and "(empty)" or keys,
            "| " .. table.concat(parts, " ")
        )
    end

    return {
        TRACKED_AILMENTS = TRACKED_AILMENTS,
        isDirty = function(pet) return isNeed(pet, "dirty") end,
        isSleepy = function(pet) return isNeed(pet, "sleepy") end,
        isHungry = function(pet) return isNeed(pet, "hungry") end,
        isThirsty = function(pet) return isNeed(pet, "thirsty") end,
        isToilet = function(pet) return isNeed(pet, "toilet") end,
        isSleeping = isSleeping,
        petHasAilment = petHasAilment,
        getCacheForPet = getCacheForPet,
        getTrackedNeeds = getTrackedNeeds,
        getActiveCacheKeys = getActiveCacheKeys,
        debugPetNeeds = debugPetNeeds,
        getPetState = getPetState,
    }
end

return Detection
