--// Single source of truth for pet needs (ailments_manager → kind)

local PetStates = {}

local CARE_NEEDS = {
    "sleepy",
    "dirty",
    "hungry",
    "thirsty",
    "toilet",
}

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
    local PetStateById = {}
    local listeners = {}

    local function emptyNeeds()
        local needs = {}
        for _, name in ipairs(TRACKED_AILMENTS) do
            needs[name] = false
        end
        return needs
    end

    local function notifyListeners()
        for _, callback in ipairs(listeners) do
            task.spawn(callback)
        end
    end

    local function resolvePetId(pet)
        if not pet or not pet:IsA("Model") then
            return nil
        end
        return tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
    end

    local function petIdCandidates(pet)
        local candidates = {}
        local seen = {}
        local function add(value)
            if value == nil then
                return
            end
            local key = tostring(value)
            if key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(candidates, key)
            end
        end
        add(pet:GetAttribute("unique"))
        add(pet:GetAttribute("id"))
        add(pet.Name)
        return candidates
    end

    local function findStateId(pet)
        if not pet then
            return nil
        end
        for _, candidate in ipairs(petIdCandidates(pet)) do
            if PetStateById[candidate] then
                return candidate
            end
        end
        for stateId in pairs(PetStateById) do
            local stateKey = tostring(stateId)
            for _, candidate in ipairs(petIdCandidates(pet)) do
                if stateKey == candidate then
                    return stateKey
                end
            end
        end
        return nil
    end

    local function getState(pet)
        local stateId = findStateId(pet)
        if not stateId then
            return nil, nil
        end
        return PetStateById[stateId], stateId
    end

    local function hasNeed(pet, needName)
        local state = getState(pet)
        if not state or not state.needs then
            return false
        end
        return state.needs[tostring(needName):lower()] == true
    end

    local function parseAilmentsManager(data)
        if type(data) ~= "table" or type(data.ailments) ~= "table" then
            return
        end

        for key in pairs(PetStateById) do
            PetStateById[key] = nil
        end

        for petId, ailmentTable in pairs(data.ailments) do
            if type(ailmentTable) == "table" then
                local needs = emptyNeeds()
                local rawKinds = {}

                for _, ailment in pairs(ailmentTable) do
                    if type(ailment) == "table" and ailment.kind then
                        local kind = tostring(ailment.kind):lower()
                        rawKinds[kind] = true
                        if needs[kind] ~= nil then
                            needs[kind] = true
                        end
                        print("PET:", petId, "kind=", kind)
                    end
                end

                PetStateById[tostring(petId)] = {
                    needs = needs,
                    rawKinds = rawKinds,
                    updatedAt = os.clock(),
                }
            end
        end

        notifyListeners()
    end

    local function subscribe(callback)
        if type(callback) == "function" then
            table.insert(listeners, callback)
        end
    end

    local function getNeeds(pet)
        local state = getState(pet)
        return state and state.needs or nil
    end

    local function getRawKinds(pet)
        local state = getState(pet)
        return state and state.rawKinds or nil
    end

    local function debugPetNeeds(pet, source)
        if not pet then
            print("[PET NEEDS DEBUG]", source or "?", "no pet")
            return
        end
        local state, stateId = getState(pet)
        if not state then
            print(
                "[PET NEEDS DEBUG]",
                source or "?",
                "pet=" .. pet.Name,
                "resolveId=" .. tostring(resolvePetId(pet)),
                "stateId=nil (no ailments_manager data yet)"
            )
            return
        end
        local rawParts = {}
        for kind in pairs(state.rawKinds or {}) do
            table.insert(rawParts, kind)
        end
        table.sort(rawParts)
        local needParts = {}
        for _, name in ipairs(TRACKED_AILMENTS) do
            table.insert(needParts, name .. "=" .. tostring(state.needs[name]))
        end
        print(
            "[PET NEEDS DEBUG]",
            source or "?",
            "pet=" .. pet.Name,
            "resolveId=" .. tostring(resolvePetId(pet)),
            "stateId=" .. tostring(stateId),
            "| raw kinds:", #rawParts == 0 and "(none)" or table.concat(rawParts, ", "),
            "| " .. table.concat(needParts, " ")
        )
    end

    local api = {
        CARE_NEEDS = CARE_NEEDS,
        TRACKED_AILMENTS = TRACKED_AILMENTS,
        PetStateById = PetStateById,
        parseAilmentsManager = parseAilmentsManager,
        subscribe = subscribe,
        getState = getState,
        getNeeds = getNeeds,
        getRawKinds = getRawKinds,
        hasNeed = hasNeed,
        resolvePetId = resolvePetId,
        findStateId = findStateId,
        debugPetNeeds = debugPetNeeds,
        isDirty = function(pet) return hasNeed(pet, "dirty") end,
        isSleepy = function(pet) return hasNeed(pet, "sleepy") end,
        isHungry = function(pet) return hasNeed(pet, "hungry") end,
        isThirsty = function(pet) return hasNeed(pet, "thirsty") end,
        isToilet = function(pet) return hasNeed(pet, "toilet") end,
        isSchool = function(pet) return hasNeed(pet, "school") end,
        isPetMe = function(pet) return hasNeed(pet, "pet_me") end,
        isSleeping = function()
            return false
        end,
    }

    return api
end

return PetStates
