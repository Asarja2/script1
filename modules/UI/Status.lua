--// Status Module
--// Handles status display and updates

local Status = {}

function Status.Init(Detection)
    local StatusLabel = nil
    local PetStatusLabel = nil

    local function updateStatus(text)
        if StatusLabel then
            StatusLabel:Set("Status: " .. text)
        end
    end

    local function getPetStatusText(pet)
        if not pet then
            return "Pet Status: no pet selected"
        end

        local statuses = {}
        if Detection.isSleeping(pet) then
            table.insert(statuses, "Sleeping")
        end
        if Detection.isDirty(pet) then
            table.insert(statuses, "Dirty")
        end
        if Detection.isSleepy(pet) then
            table.insert(statuses, "Sleepy")
        end
        if Detection.isHungry(pet) then
            table.insert(statuses, "Hungry")
        end
        if Detection.isThirsty(pet) then
            table.insert(statuses, "Thirsty")
        end
        if Detection.isToilet(pet) then
            table.insert(statuses, "Needs toilet")
        end

        if #statuses == 0 then
            return "Pet Status: no needs detected"
        end

        return "Pet Status: " .. table.concat(statuses, ", ")
    end

    local function refreshSelectedPetStatus(pet)
        if PetStatusLabel then
            PetStatusLabel:Set(getPetStatusText(pet))
        end
    end

    local function setStatusLabels(status, petStatus)
        StatusLabel = status
        PetStatusLabel = petStatus
    end

    return {
        updateStatus = updateStatus,
        getPetStatusText = getPetStatusText,
        refreshSelectedPetStatus = refreshSelectedPetStatus,
        setStatusLabels = setStatusLabels,
    }
end

return Status
