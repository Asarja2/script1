--// Ailment Detection Module
--// Detects pet ailments and states

local Detection = {}

function Detection.Init(PetAilmentCache, PetState)
    local function getPetState(pet)
        if not pet then
            return nil
        end
        return PetState[pet]
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

        if not petId then
            if pet:IsA("Model") then
                petId = tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
            else
                return false
            end
        end

        local cache = PetAilmentCache[petId]
        if type(cache) ~= "table" then
            return false
        end

        return cache[tostring(ailmentName):lower()] ~= nil
    end

    local function isDirty(pet)
        local petId = pet:IsA("Model") and tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name) or nil
        if petHasAilment(pet, "dirty", petId) or petHasAilment(pet, "stinky", petId) or petHasAilment(pet, "stink", petId) or petHasAilment(pet, "needsbath", petId) or petHasAilment(pet, "bath", petId) then
            return true
        end
        local state = getPetState(pet)
        if not state then
            return false
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
        local petId = pet:IsA("Model") and tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name) or nil
        if petHasAilment(pet, "sleepy", petId) or petHasAilment(pet, "tired", petId) or petHasAilment(pet, "needsleep", petId) or petHasAilment(pet, "sleep", petId) then
            return true
        end
        local state = getPetState(pet)
        if not state then
            return false
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
        if not pet or not pet:IsA("Model") then
            return false
        end

         local petId = tostring(
         pet:GetAttribute("unique")
         or pet:GetAttribute("id")
         or pet.Name
    )

    return petHasAilment(pet, "hungry", petId)
end

    local function isSleeping(pet)
        if stateHasAny(pet, {"sleeping", "Sleeping", "Asleep", "asleep", "Sleep", "FallAsleep", "FocusPet", "SleepLoop"}) then
            return true
        end
        return false
    end

    local function isToilet(pet)
        local petId = pet:IsA("Model") and tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name) or nil
        if petHasAilment(pet, "toilet", petId) or petHasAilment(pet, "pee", petId) or petHasAilment(pet, "poop", petId) or petHasAilment(pet, "restroom", petId) then
            return true
        end
        local state = getPetState(pet)
        if not state then
            return false
        end
        if stateHasAny(pet, {"Toilet", "Pee", "Poop", "Restroom"}) then
            return true
        end
        if stateHasEffect(pet, {"toilet", "pee", "poop"}) then
            return true
        end
        return false
    end

    local function isThirsty(pet)
        if not pet or not pet:IsA("Model") then
            return false
        end

        local petId = tostring(
            pet:GetAttribute("unique")
            or pet:GetAttribute("id")
            or pet.Name
        )

        return petHasAilment(pet, "thirsty", petId)
    end

    return {
        isDirty = isDirty,
        isSleepy = isSleepy,
        isHungry = isHungry,
        isThirsty = isThirsty,
        isToilet = isToilet,
        isSleeping = isSleeping,
        petHasAilment = petHasAilment,
        stateHasAny = stateHasAny,
        stateHasEffect = stateHasEffect,
        getPetState = getPetState,
    }
end

return Detection
