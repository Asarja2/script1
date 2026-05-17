--// Ailment Detection Module
--// Detects pet ailments from ailments_manager cache + pet state fallbacks

local Detection = {}

local DEFAULT_MAPPINGS = {
    hungry = {"hungry", "feed", "needsfood", "needs_food", "hunger", "starving"},
    thirsty = {"thirsty", "needsdrink", "drink", "thirst", "needs_drink"},
    dirty = {"dirty", "stinky", "stink", "needsbath", "needs_bath", "bath"},
    toilet = {"toilet", "pee", "poop", "restroom"},
    sleepy = {"sleepy", "tired", "needsleep", "needs_sleep", "sleep"},
    school = {"school"},
    pet_me = {"pet_me", "petme", "pet"},
}

function Detection.Init(PetAilmentCache, PetState, ailmentMappings)
    local MAPPINGS = ailmentMappings or DEFAULT_MAPPINGS

    local function getPetState(pet)
        if not pet then
            return nil
        end
        return PetState[pet]
    end

    local function resolvePetId(pet)
        if not pet or not pet:IsA("Model") then
            return nil
        end
        return tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
    end

    local function stateHasAny(pet, keys)
        local state = getPetState(pet)
        if not state then
            return false
        end
        for _, key in ipairs(keys) do
            local normalizedKey = tostring(key):lower()
            for stateKey, stateValue in pairs(state) do
                if tostring(stateKey):lower() == normalizedKey and stateValue then
                    return true
                end
            end
        end
        return false
    end

    local function stateHasEffect(pet, effectNames)
        local state = getPetState(pet)
        if not state then
            return false
        end
        local effects = state.effects
        if type(effects) == "table" then
            for _, effect in ipairs(effects) do
                for _, name in ipairs(effectNames) do
                    if tostring(effect):lower() == tostring(name):lower() then
                        return true
                    end
                end
            end
        elseif type(effects) == "string" then
            for _, name in ipairs(effectNames) do
                if tostring(effects):lower() == tostring(name):lower() then
                    return true
                end
            end
        end
        return false
    end

    local function petHasAilment(pet, ailmentName, petId)
        if not pet or type(ailmentName) ~= "string" then
            return false
        end

        petId = petId or resolvePetId(pet)
        if not petId then
            return false
        end

        local cache = PetAilmentCache[petId]
        if type(cache) ~= "table" then
            return false
        end

        return cache[tostring(ailmentName):lower()] ~= nil
    end

    local function checkMapped(pet, category)
        local keys = MAPPINGS[category]
        if not keys then
            return false
        end
        for _, key in ipairs(keys) do
            if petHasAilment(pet, key) then
                return true
            end
        end
        return false
    end

    local function isDirty(pet)
        if checkMapped(pet, "dirty") then
            return true
        end
        if stateHasAny(pet, {"Dirty", "Stinky", "NeedsBath", "Bath"}) then
            return true
        end
        if stateHasEffect(pet, {"dirty", "stinky"}) then
            return true
        end
        return false
    end

    local function isSleepy(pet)
        if checkMapped(pet, "sleepy") then
            return true
        end
        if stateHasAny(pet, {"Sleepy", "Tired", "NeedsSleep", "Sleep"}) then
            return true
        end
        if stateHasEffect(pet, {"sleepy", "tired", "sleep"}) then
            return true
        end
        return false
    end

    local function isHungry(pet)
        return checkMapped(pet, "hungry")
    end

    local function isThirsty(pet)
        return checkMapped(pet, "thirsty")
    end

    local function isToilet(pet)
        if checkMapped(pet, "toilet") then
            return true
        end
        if stateHasAny(pet, {"Toilet", "Pee", "Poop", "Restroom"}) then
            return true
        end
        if stateHasEffect(pet, {"toilet", "pee", "poop"}) then
            return true
        end
        return false
    end

    local function isSleeping(pet)
        if stateHasAny(pet, {"sleeping", "Sleeping", "Asleep", "asleep", "Sleep", "FallAsleep", "FocusPet", "SleepLoop"}) then
            return true
        end
        return false
    end

    local function getActiveCacheKeys(pet)
        local petId = resolvePetId(pet)
        if not petId then
            return {}
        end
        local cache = PetAilmentCache[petId]
        if type(cache) ~= "table" then
            return {}
        end
        local keys = {}
        for key in pairs(cache) do
            table.insert(keys, tostring(key))
        end
        table.sort(keys)
        return keys
    end

    local function debugPetNeeds(pet, source)
        if not pet then
            print("[PET NEEDS DEBUG]", source or "?", "no pet")
            return
        end
        local petId = resolvePetId(pet)
        local cacheKeys = table.concat(getActiveCacheKeys(pet), ", ")
        print(
            "[PET NEEDS DEBUG]",
            source or "?",
            "pet=" .. pet.Name,
            "id=" .. tostring(petId),
            "| cache:", cacheKeys == "" and "(empty)" or cacheKeys,
            "| hungry=" .. tostring(isHungry(pet)),
            "thirsty=" .. tostring(isThirsty(pet)),
            "dirty=" .. tostring(isDirty(pet)),
            "sleepy=" .. tostring(isSleepy(pet)),
            "toilet=" .. tostring(isToilet(pet)),
            "sleeping=" .. tostring(isSleeping(pet))
        )
    end

    return {
        isDirty = isDirty,
        isSleepy = isSleepy,
        isHungry = isHungry,
        isThirsty = isThirsty,
        isToilet = isToilet,
        isSleeping = isSleeping,
        petHasAilment = petHasAilment,
        checkMapped = checkMapped,
        stateHasAny = stateHasAny,
        stateHasEffect = stateHasEffect,
        getPetState = getPetState,
        getActiveCacheKeys = getActiveCacheKeys,
        debugPetNeeds = debugPetNeeds,
    }
end

return Detection
