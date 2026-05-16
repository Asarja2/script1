local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local UI = {}

function UI.Init(Pets, Sleep, Care, Remotes)

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    --// API
    local API = ReplicatedStorage:WaitForChild("API")

    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local ReplicatePerformanceModifiers = Remotes.ReplicatePerformanceModifiers
    local ReplicateActivePerformances = Remotes.ReplicateActivePerformances
    local ReplicateActiveReactions = Remotes.ReplicateActiveReactions
    local DataChanged = Remotes.DataChanged

    local dirtyPetState = setmetatable({}, {__mode = "k"})
    local sleepyPetState = setmetatable({}, {__mode = "k"})
    local PetAilmentCache = {}
    -- mapping of logical states to possible ailment keys received from DataChanged
    local AILMENT_MAPPINGS = {
        hungry = {"hungry", "feed", "needsfood", "needs_food", "hunger", "starving", "needs_food"},
        thirsty = {"thirsty", "needsdrink", "drink", "thirst", "needs_drink"},
        dirty = {"dirty", "stinky", "stink", "needsbath", "needs_bath", "bath"},
        toilet = {"toilet", "pee", "poop", "restroom"},
        sleepy = {"sleepy", "tired", "needsleep", "needs_sleep", "sleep"}
    }
    local dataChangedAutofarmThrottle = setmetatable({}, {__mode = "k"})

    local function markPetDirty(pet, value)
        if pet and pet:IsA("Model") then
            dirtyPetState[pet] = value
            local petId = resolvePetId(pet)
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
            local petId = resolvePetId(pet)
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
            local petId = resolvePetId(pet)
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

    local currentAutofarmTask = nil
    local autofarmTaskQueue = {}

    local function queueAutofarmTask(taskType, pet)
        table.insert(autofarmTaskQueue, {type = taskType, pet = pet})
        if not currentAutofarmTask then
            executeNextAutofarmTask()
        end
    end

    local function executeNextAutofarmTask()
        if #autofarmTaskQueue == 0 then
            currentAutofarmTask = nil
            return
        end
        local task = table.remove(autofarmTaskQueue, 1)
        currentAutofarmTask = task
        if task.type == "shower" then
            performAutoShower(task.pet)
        elseif task.type == "sleep" then
            performAutoSleep(task.pet)
        elseif task.type == "toilet" then
            performAutoToilet(task.pet)
        end
    end

    local successHook, hookErr = pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall

        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and (self == ReplicatePerformanceModifiers or tostring(self) == "PetAPI/ReplicatePerformanceModifiers") then
                local args = {...}
                local pet = args[1]
                local data = args[2]

                if type(data) == "table" then
                    local isDirtyNow = false
                    local isSleepyNow = false

                    if data.TransitionDirty or data.DirtyAilmentReaction then
                        isDirtyNow = true
                    end

                    if type(data.effects) == "table" then
                        for _, effect in ipairs(data.effects) do
                            local effectLower = tostring(effect):lower()
                            if effectLower == "stinky" then
                                isDirtyNow = true
                            end
                            if effectLower == "sleep" then
                                isSleepyNow = true
                            end
                        end
                    end

                    if isDirtyNow then
                        markPetDirty(pet, true)
                        if autofarmEnabled and selectedPet == pet then
                            queueAutofarmTask("shower", pet)
                        end
                    else
                        markPetDirty(pet, false)
                    end

                    if isSleepyNow then
                        markPetSleepy(pet, true)
                        if autofarmEnabled and selectedPet == pet then
                            queueAutofarmTask("sleep", pet)
                        end
                    else
                        markPetSleepy(pet, false)
                    end
                end
            end

            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)

    if not successHook then
        warn("Dirty detection hook failed:", hookErr)
    end

    --// Create Rayfield Window
    local Window = Rayfield:CreateWindow({
        Name = "Pet Controller",
        Icon = 0,
        LoadingTitle = "Pet Controller",
        LoadingSubtitle = "Loading your pets...",
        Theme = "Default",
        ToggleUIKeybind = Enum.KeyCode.F2,
        DisableRayfieldPrompts = false,
        DisableBuildWarnings = false,
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "PetController",
            FileName = "config"
        }
    })

    --// Create Tab
    local Tab = Window:CreateTab("Controls", 0)

    --// Status Section
    local StatusCategory = Tab:CreateSection("Status")
    local StatusLabel = Tab:CreateLabel("Status: Ready")
    local PetStatusLabel = Tab:CreateLabel("Pet Status: unknown")

    --// Create Sections
    local PetSection = Tab:CreateSection("Pet Selection")
    local ActionSection = Tab:CreateSection("Actions")
    local CareSection = Tab:CreateSection("Care")

    --// Variables
    local selectedPet = nil
    local selectedPetName = nil
    local petOptions = {}
    local PetDropdown = nil
    local PetState = setmetatable({}, {__mode = "k"})

    local autofarmEnabled = false
    local autofarmToggle = nil
    local autofarmLoop = nil

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

    local function updateStatus(text)
        StatusLabel:Set("Status: " .. text)
    end

    local function tableContains(tbl, value)
        if type(tbl) ~= "table" then
            return false
        end
        for _, v in ipairs(tbl) do
            if v == value then
                return true
            end
        end
        return false
    end

    local function resolveSelectedPet()
        if selectedPet and selectedPet.Parent and selectedPet:IsDescendantOf(workspace) then
            return selectedPet
        end

        if not selectedPetName then
            return nil
        end

        local pet = Pets.FindPetByName(selectedPetName)
        if pet then
            selectedPet = pet
            return pet
        end

        selectedPet = nil
        return nil
    end

    local function resolvePetId(pet)
        if not pet or not pet:IsA("Model") then
            return nil
        end
        return tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name)
    end

    local function petHasAilment(pet, ailmentName)
        if not pet or type(ailmentName) ~= "string" then
            return false
        end

        local petId = resolvePetId(pet)
        if not petId then
            return false
        end

        local cache = PetAilmentCache[petId]
        if type(cache) ~= "table" then
            return false
        end

        return cache[tostring(ailmentName):lower()] ~= nil
    end

    local function getPetStatusText(pet)
        if not pet then
            return "Pet Status: no pet selected"
        end

        local statuses = {}
        if isSleeping(pet) then
            table.insert(statuses, "Sleeping")
        end
        if isDirty(pet) then
            table.insert(statuses, "Dirty")
        end
        if isSleepy(pet) then
            table.insert(statuses, "Sleepy")
        end
        if isHungry(pet) then
            table.insert(statuses, "Hungry")
        end
        if isThirsty(pet) then
            table.insert(statuses, "Thirsty")
        end
        if petHasAilment(pet, "toilet") then
            table.insert(statuses, "Needs toilet")
        end

        if #statuses == 0 then
            return "Pet Status: no needs detected"
        end

        return "Pet Status: " .. table.concat(statuses, ", ")
    end

    local function refreshSelectedPetStatus()
        local pet = resolveSelectedPet()
        if PetStatusLabel then
            PetStatusLabel:Set(getPetStatusText(pet))
        end
    end

    --// Debug Remote Listeners
    if ReplicatePerformanceModifiers and ReplicatePerformanceModifiers:IsA("RemoteEvent") then
        ReplicatePerformanceModifiers.OnClientEvent:Connect(function(pet, data)
            print("DEBUG REMOTE: ReplicatePerformanceModifiers fired", pet and pet.Name, data)
            if pet then
                updatePetState(pet, data)
            end
            if selectedPet == pet then
                updateStatus("Remote says modifiers updated")
                attemptAutoShower(pet, "ReplicatePerformanceModifiers")
                attemptAutoSleep(pet, "ReplicatePerformanceModifiers")
            end
        end)
    end

    if ReplicateActivePerformances and ReplicateActivePerformances:IsA("RemoteEvent") then
        ReplicateActivePerformances.OnClientEvent:Connect(function(pet, data)
            print("DEBUG REMOTE: ReplicateActivePerformances fired", pet and pet.Name, data)
            if pet then
                updatePetState(pet, data)
            end
            if selectedPet and pet and selectedPet == pet then
                if type(data) == "table" and (data.Dirty or data.Transform or data.FocusPet) then
                    updateStatus("Remote says pet has active dirty/transform state")
                end
                attemptAutoShower(pet, "ReplicateActivePerformances")
                attemptAutoSleep(pet, "ReplicateActivePerformances")
            end
        end)
    end

    if ReplicateActiveReactions and ReplicateActiveReactions:IsA("RemoteEvent") then
        ReplicateActiveReactions.OnClientEvent:Connect(function(pet, data)
            print("DEBUG REMOTE: ReplicateActiveReactions fired", pet and pet.Name, data)
            if pet then
                updatePetState(pet, data)
            end
            if selectedPet and pet and selectedPet == pet then
                if type(data) == "table" and (data.Dirty or data.Transform or data.FocusPet) then
                    updateStatus("Remote says pet has active reaction dirty/transform state")
                end
                attemptAutoShower(pet, "ReplicateActiveReactions")
                attemptAutoSleep(pet, "ReplicateActiveReactions")
            end
        end)
    end

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(playerName, dataType, data, timestamp)
            if dataType ~= "ailments_manager" then
                return
            end
            if type(data) ~= "table" then
                return
            end

            local ailments = data.ailments
            if type(ailments) ~= "table" then
                return
            end

            for petId, ailmentTable in pairs(ailments) do
                if type(ailmentTable) == "table" then
                    local normalized = {}
                    for ailmentName, ailmentData in pairs(ailmentTable) do
                        local lower = tostring(ailmentName):lower()
                        normalized[lower] = ailmentData
                        print("AILMENT UPDATE", petId, lower)
                    end
                    PetAilmentCache[tostring(petId)] = normalized

                    -- try to resolve the pet model from the petId
                    local petModel = nil
                    for _, p in ipairs(Pets.GetPets()) do
                        local id = resolvePetId(p)
                        if id and tostring(id) == tostring(petId) then
                            petModel = p
                            break
                        end
                    end

                    -- mark ailments on the pet model so other detection logic stays in sync
                    if petModel then
                        local hasDirty = normalized["dirty"] or normalized["stinky"] or normalized["stink"]
                        local hasSleepy = normalized["sleepy"]
                        local hasToilet = normalized["toilet"]

                        markPetDirty(petModel, hasDirty and true or false)
                        markPetSleepy(petModel, hasSleepy and true or false)
                        markPetToilet(petModel, hasToilet and true or false)

                        -- derive mapped logical states (hungry/thirsty/etc) from arbitrary ailment keys
                        local mappedState = {}
                        for logicalName, keys in pairs(AILMENT_MAPPINGS) do
                            for _, k in ipairs(keys) do
                                if normalized[tostring(k):lower()] then
                                    mappedState[logicalName] = true
                                    break
                                end
                            end
                        end

                        -- update PetState so existing checks like isHungry/isThirsty work
                        if next(mappedState) then
                            updatePetState(petModel, mappedState)
                        end

                        -- if this is the selected pet, refresh status and possibly queue autofarm
                        local selected = resolveSelectedPet()
                        if selected and selected == petModel then
                            refreshSelectedPetStatus()
                            if autofarmEnabled then
                                if mappedState["toilet"] or hasToilet then
                                    queueAutofarmTask("toilet", petModel)
                                end
                                if mappedState["dirty"] or hasDirty then
                                    queueAutofarmTask("shower", petModel)
                                end
                                if mappedState["sleepy"] or hasSleepy then
                                    queueAutofarmTask("sleep", petModel)
                                end
                                -- also throttle a full autofarm run to avoid rapid repeats
                                local last = dataChangedAutofarmThrottle[selected]
                                if not last or (time() - last) > 2 then
                                    dataChangedAutofarmThrottle[selected] = time()
                                    task.spawn(function()
                                        local ok, err = pcall(runAutofarmOnce)
                                        if not ok then
                                            warn("AUTOFARM DATACHANGE ERROR", err)
                                        end
                                    end)
                                end
                            end
                        end
                    else
                        -- fallback: if selected pet matches id, still refresh label
                        local selected = resolveSelectedPet()
                        if selected then
                            local currentId = resolvePetId(selected)
                            if tostring(currentId) == tostring(petId) then
                                refreshSelectedPetStatus()
                                if autofarmEnabled then
                                    local last = dataChangedAutofarmThrottle[selected]
                                    if not last or (time() - last) > 2 then
                                        dataChangedAutofarmThrottle[selected] = time()
                                        task.spawn(function()
                                            local ok, err = pcall(runAutofarmOnce)
                                            if not ok then
                                                warn("AUTOFARM DATACHANGE ERROR", err)
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    --// Pet Dropdown
    PetDropdown = Tab:CreateDropdown({
        Name = "Select Pet",
        Options = {"No pets available"},
        CurrentOption = {"No pets available"},
        MultipleOptions = false,
        Flag = "PetDropdown",
        Callback = function(Options)
            local selectedName = Options[1]
            if selectedName == "No pets available" then
                selectedPet = nil
                selectedPetName = nil
                updateStatus("No pet selected")
                return
            end
            selectedPetName = selectedName
            selectedPet = Pets.FindPetByName(selectedName)
            if selectedPet then
                print("DEBUG: pet selected", selectedPet.Name, selectedPet:GetFullName())
                updateStatus("Selected: " .. selectedPet.Name)
                refreshSelectedPetStatus()
            else
                warn("DEBUG: selected pet by name not found", selectedName)
                updateStatus("Selected pet not found live")
                refreshSelectedPetStatus()
            end
        end
    })

    --// Refresh Pets
    local function refreshPets()
        selectedPet = nil
        petOptions = {}

        local pets = Pets.GetPets()
        
        for i, pet in ipairs(pets) do
            table.insert(petOptions, pet.Name)
            print("DEBUG: pet found", pet.Name, pet:GetFullName())
        end

        if #petOptions > 0 then
            updateStatus("Found " .. #petOptions .. " pets")
            if PetDropdown then
                PetDropdown:Refresh(petOptions)
                if selectedPetName and tableContains(petOptions, selectedPetName) then
                    PetDropdown:Set({selectedPetName})
                    selectedPet = Pets.FindPetByName(selectedPetName)
                    updateStatus("Re-selected: " .. selectedPetName)
                else
                    PetDropdown:Set({petOptions[1]})
                    selectedPetName = petOptions[1]
                    selectedPet = pets[1]
                    updateStatus("Auto-selected: " .. pets[1].Name)
                end
                refreshSelectedPetStatus()
            else
                warn("PetDropdown is nil in refreshPets")
            end
        else
            updateStatus("No pets found")
            if PetDropdown then
                PetDropdown:Refresh({"No pets available"})
                PetDropdown:Set({"No pets available"})
            else
                warn("PetDropdown is nil in refreshPets")
            end
        end
    end

    local function resolveCFrame(target, expectedName)
        if not target then
            return nil
        end

        if target:IsA("BasePart") then
            return target.CFrame
        end

        if target:IsA("Model") and target.PrimaryPart then
            return target.PrimaryPart.CFrame
        end

        local childPart = target:FindFirstChild(expectedName)
        if childPart and childPart:IsA("BasePart") then
            return childPart.CFrame
        end

        local anyPart = target:FindFirstChildOfClass("BasePart")
        if anyPart then
            return anyPart.CFrame
        end

        return nil
    end

    local function childStateEnabled(pet, name)
        local targetName = name:lower()
        local child = pet:FindFirstChild(name)

        if not child then
            for _, v in ipairs(pet:GetChildren()) do
                if v.Name:lower() == targetName then
                    child = v
                    break
                end
            end
        end

        if not child then
            return false
        end

        if child:IsA("BoolValue") then
            return child.Value == true
        end

        if child:IsA("IntValue") or child:IsA("NumberValue") then
            return child.Value ~= 0
        end

        if child:IsA("StringValue") then
            local lowerValue = tostring(child.Value):lower()
            return lowerValue ~= "" and lowerValue == targetName
        end

        if child:IsA("ObjectValue") then
            local lowerValue = tostring(child.Value):lower()
            return lowerValue == targetName
        end

        return true
    end

    local function descendantStateEnabled(pet, name)
        local targetName = name:lower()
        for _, descendant in ipairs(pet:GetDescendants()) do
            if descendant.Name:lower() == targetName then
                if descendant:IsA("BoolValue") then
                    return descendant.Value == true
                end
                if descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
                    return descendant.Value ~= 0
                end
                if descendant:IsA("StringValue") then
                    local lowerValue = tostring(descendant.Value):lower()
                    return lowerValue ~= "" and lowerValue == targetName
                end
                if descendant:IsA("ObjectValue") then
                    local lowerValue = tostring(descendant.Value):lower()
                    return lowerValue == targetName
                end
                return true
            end
        end
        return false
    end

    local function activePerformanceEnabled(pet, name)
        local active = pet:FindFirstChild("ActivePerformances")
        if not active then
            return false
        end

        local lowerName = name:lower()
        for _, perf in ipairs(active:GetChildren()) do
            local perfName = perf.Name:lower()
            local value
            if perf:IsA("BoolValue") or perf:IsA("IntValue") or perf:IsA("NumberValue") then
                value = perf.Value
            elseif perf:IsA("StringValue") then
                value = perf.Value
            elseif perf:IsA("ObjectValue") then
                value = perf.Value and perf.Value.Name or nil
            end

            if perfName == lowerName or perfName:find(lowerName, 1, true) then
                if value == nil or value == true or tostring(value):lower() == lowerName then
                    return true
                end
                if type(value) == "string" and value:lower() ~= "false" and value:lower() ~= "" then
                    return true
                end
            end
        end

        return false
    end

    local function hasEffect(pet, name)
        local lowerName = name:lower()
        local effects = pet:FindFirstChild("effects") or pet:FindFirstChild("Effects")

        if effects then
            for _, child in ipairs(effects:GetChildren()) do
                local childName = child.Name and child.Name:lower() or ""
                if childName == lowerName then
                    return true
                end

                if child:IsA("StringValue") or child:IsA("ObjectValue") or child:IsA("BoolValue") or child:IsA("IntValue") or child:IsA("NumberValue") then
                    local valueString = tostring(child.Value):lower()
                    if valueString == lowerName then
                        return true
                    end
                end
            end
        end

        local attr = pet:GetAttribute("effects") or pet:GetAttribute("Effects")
        if attr then
            if type(attr) == "string" then
                if attr:lower() == lowerName then
                    return true
                end
            elseif type(attr) == "table" then
                for _, item in ipairs(attr) do
                    if tostring(item):lower() == lowerName then
                        return true
                    end
                end
            end
        end

        return false
    end

    local function petHasState(pet, name)
        if not pet then
            return false
        end

        local attr = pet:GetAttribute(name)
        if attr == true or attr == 1 or tostring(attr):lower() == "true" then
            return true
        end
        if type(attr) == "string" and attr:lower() == name:lower() then
            return true
        end
        if type(attr) == "table" then
            for _, item in ipairs(attr) do
                if tostring(item):lower() == name:lower() then
                    return true
                end
            end
        end

        if childStateEnabled(pet, name) then
            return true
        end

        if descendantStateEnabled(pet, name) then
            return true
        end

        if activePerformanceEnabled(pet, name) then
            return true
        end

        if hasEffect(pet, name) then
            return true
        end

        return false
    end

    local function petHasAnyState(pet, names)
        for _, name in ipairs(names) do
            if petHasState(pet, name) then
                return true
            end
        end
        return false
    end

    local function isDirty(pet)
        return petHasAilment(pet, "dirty")
    end

    local function isSleepy(pet)
        return petHasAilment(pet, "sleepy")
    end

    local function isHungry(pet)
        local state = getPetState(pet)
        if not state then
            return false
        end

        if stateHasAny(pet, {"Hungry", "Starving", "NeedsFood", "Feed"}) then
            return true
        end
        if stateHasEffect(pet, {"hungry", "starving", "feed"}) then
            return true
        end
        return false
    end

    local function getNeedsState(pet)
        return {
            dirty = isDirty(pet),
            sleepy = isSleepy(pet),
            hungry = isHungry(pet),
            toilet = petHasAilment(pet, "toilet")
        }
    end

    local function isSleeping(pet)
        if stateHasAny(pet, {"sleeping", "Sleeping", "Asleep", "asleep", "Sleep", "FallAsleep", "FocusPet", "SleepLoop"}) then
            return true
        end
        return false
    end

    local function isThirsty(pet)
        if stateHasAny(pet, {"Thirsty", "Parched", "NeedsDrink", "Drink", "Thirst"}) then
            return true
        end
        if stateHasEffect(pet, {"thirsty"}) then
            return true
        end
        return false
    end

    local function debugPetState(pet)
        if not pet then
            return
        end

        print("DEBUG PET STATE for", pet.Name)
        local state = getPetState(pet)
        if state then
            print("DEBUG CACHED STATE:")
            for key, value in pairs(state) do
                print("DEBUG STATE", key, value)
            end
        else
            print("DEBUG CACHED STATE: none")
        end

        local names = {"sleepy", "Sleepy", "Tired", "NeedsSleep", "Sleep", "FallAsleep", "FocusPet", "Sleeping", "Asleep", "Dirty", "dirty", "Stinky", "stinky", "NeedsBath", "Bath", "Transform"}
        for _, name in ipairs(names) do
            local attr = pet:GetAttribute(name)
            if attr ~= nil then
                print("DEBUG ATTR", name, "=", attr)
            end
        end

        local ailmentsFolder = pet:FindFirstChild("ailments") or pet:FindFirstChild("Ailments")
        if ailmentsFolder then
            for _, child in ipairs(ailmentsFolder:GetDescendants()) do
                if child:IsA("BoolValue") or child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") or child:IsA("ObjectValue") then
                    print("DEBUG AILMENT", child:GetFullName(), child.ClassName, child.Value)
                end
            end
        end

        local active = pet:FindFirstChild("ActivePerformances")
        if active then
            for _, perf in ipairs(active:GetDescendants()) do
                if perf:IsA("BoolValue") or perf:IsA("IntValue") or perf:IsA("NumberValue") or perf:IsA("StringValue") or perf:IsA("ObjectValue") then
                    print("DEBUG PERF", perf:GetFullName(), perf.ClassName, perf.Value)
                end
            end
        end

        local effects = pet:FindFirstChild("effects") or pet:FindFirstChild("Effects")
        if effects then
            for _, child in ipairs(effects:GetDescendants()) do
                if child:IsA("BoolValue") or child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") or child:IsA("ObjectValue") then
                    print("DEBUG EFFECT", child:GetFullName(), child.ClassName, child.Value)
                end
            end
        end

        local state = getPetState(pet)
        if state then
            for key, value in pairs(state) do
                print("DEBUG CACHE", key, value)
            end
        end
    end

    local function teleportToTarget(cframe)
        if not cframe then
            return
        end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = cframe * CFrame.new(0, 0, -5)
        end
    end

    local function performFurnitureActivation(furnitureId, target, partName, actionLabel)
        if not furnitureId or not target then
            return false, "No furniture found"
        end

        local targetCFrame = resolveCFrame(target, partName)
        if not targetCFrame then
            return false, "Invalid furniture position"
        end

        print("DEBUG ACTION", actionLabel, "furnitureId=", furnitureId, "target=", target:GetFullName())
        teleportToTarget(targetCFrame)
        updateStatus("Using " .. actionLabel .. "...")

        local args = {
            player,
            furnitureId,
            partName,
            {
                cframe = targetCFrame
            },
            selectedPet
        }

        local ok, err = pcall(function()
            ActivateFurniture:InvokeServer(unpack(args))
        end)

        if not ok then
            return false, err
        end

        return true
    end

    local autoShowerThrottle = {}
    local autoShowerDisabled = false

    local function canAutoShowerForPet(pet)
        if not pet then
            return false
        end
        if not autofarmEnabled then
            return false
        end
        if autoShowerDisabled then
            return false
        end
        local last = autoShowerThrottle[pet]
        if last and (time() - last) < 5 then
            return false
        end
        return true
    end

    local function markAutoShower(pet)
        if pet then
            autoShowerThrottle[pet] = time()
        end
    end

    local function attemptAutoShower(pet, source)
        local currentPet = resolveSelectedPet()
        if not currentPet or currentPet ~= pet then
            return
        end
        if not autofarmEnabled then
            return
        end
        if isSleeping(pet) then
            return
        end
        if not isDirty(pet) then
            return
        end
        queueAutofarmTask("shower", pet)
    end

    local function performAutoShower(pet)
        local furnitureId, obj = Care.FindShower()
        if not furnitureId or not obj then
            updateStatus("Auto-shower: no shower found")
            warn("AUTO SHOWER: no shower found")
            executeNextAutofarmTask()
            return
        end

        updateStatus("Auto-shower triggered")
        print("DEBUG AUTO-SHOWER", pet.Name)
        markPetDirty(pet, false)
        refreshSelectedPetStatus()

        task.spawn(function()
            local success, err = performFurnitureActivation(furnitureId, obj, "UseBlock", "shower")
            if not success then
                warn("AUTO SHOWER ERROR", err)
                updateStatus("Auto shower failed")
            else
                updateStatus(pet.Name .. " is showering")
            end
            executeNextAutofarmTask()
        end)
    end

    local autoSleepThrottle = {}

    local function canAutoSleepForPet(pet)
        if not pet then
            return false
        end
        if not autofarmEnabled then
            return false
        end
        local last = autoSleepThrottle[pet]
        if last and (time() - last) < 5 then
            return false
        end
        return true
    end

    local function markAutoSleep(pet)
        if pet then
            autoSleepThrottle[pet] = time()
        end
    end

    local function attemptAutoSleep(pet, source)
        local currentPet = resolveSelectedPet()
        if not currentPet or currentPet ~= pet then
            return
        end
        if not canAutoSleepForPet(pet) then
            return
        end
        if isSleeping(pet) then
            return
        end
        if not isSleepy(pet) then
            return
        end
        queueAutofarmTask("sleep", pet)
    end

    local autoToiletThrottle = {}

    local function canAutoToiletForPet(pet)
        if not pet then
            return false
        end
        if not autofarmEnabled then
            return false
        end
        local last = autoToiletThrottle[pet]
        if last and (time() - last) < 5 then
            return false
        end
        return true
    end

    local function markAutoToilet(pet)
        if pet then
            autoToiletThrottle[pet] = time()
        end
    end

    local function attemptAutoToilet(pet, source)
        local currentPet = resolveSelectedPet()
        if not currentPet or currentPet ~= pet then
            return
        end
        if not canAutoToiletForPet(pet) then
            return
        end
        if not petHasAilment(pet, "toilet") then
            return
        end
        queueAutofarmTask("toilet", pet)
    end

    local function performAutoSleep(pet)
        local furnitureId, seat = Sleep.FindBed()
        if not furnitureId or not seat then
            updateStatus("Auto-sleep: no bed found")
            warn("AUTO SLEEP: no bed found")
            executeNextAutofarmTask()
            return
        end

        updateStatus("Auto-sleep triggered")
        print("DEBUG AUTO-SLEEP", pet.Name)
        markAutoSleep(pet)
        markPetSleepy(pet, false)
        refreshSelectedPetStatus()

        task.spawn(function()
            local success, err = performFurnitureActivation(furnitureId, seat, "Seat1", "bed")
            if not success then
                warn("AUTO SLEEP ERROR", err)
                updateStatus("Auto sleep failed")
            else
                updateStatus(pet.Name .. " is sleeping")
            end
            executeNextAutofarmTask()
        end)
    end

    local function performAutoToilet(pet)
        local furnitureId, seat = Care.FindToilet()
        if not furnitureId or not seat then
            updateStatus("Auto-toilet: no toilet found")
            warn("AUTO TOILET: no toilet found")
            executeNextAutofarmTask()
            return
        end

        updateStatus("Auto-toilet triggered")
        print("DEBUG AUTO-TOILET", pet.Name)
        markAutoToilet(pet)

        task.spawn(function()
            local success, err = performFurnitureActivation(furnitureId, seat, "Seat1", "toilet")
            if not success then
                warn("AUTO TOILET ERROR", err)
                updateStatus("Auto toilet failed")
            else
                updateStatus(pet.Name .. " is using the toilet")
            end
            executeNextAutofarmTask()
        end)
    end

    --// Refresh Pets Button
    Tab:CreateButton({
        Name = "🔄 Refresh Pets",
        Callback = function()
            refreshPets()
            updateStatus("Pets refreshed")
        end
    })

    --// Clear Selection Button
    Tab:CreateButton({
        Name = "❌ Clear Selection",
        Callback = function()
            selectedPet = nil
            if PetDropdown then
                PetDropdown:Set({"No pets available"})
            end
            updateStatus("Selection cleared")
        end
    })

    --// Hold Pet
    Tab:CreateButton({
        Name = "🍼 Hold Pet",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            updateStatus("Sending hold request...")
            print("DEBUG: hold pet", selectedPet.Name, selectedPet:GetFullName())
            local args = {selectedPet}
            local ok, err = pcall(function()
                HoldBaby:FireServer(unpack(args))
            end)
            if not ok then
                updateStatus("Hold request failed")
                warn("HOLD REQUEST ERROR", err)
                return
            end
            updateStatus("Holding " .. selectedPet.Name)
        end
    })

    --// Eject Pet
    Tab:CreateButton({
        Name = "⬇️ Drop Pet",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            updateStatus("Sending drop request...")
            local args = {selectedPet}
            local ok, err = pcall(function()
                EjectBaby:FireServer(unpack(args))
            end)
            if not ok then
                updateStatus("Drop request failed")
                warn("DROP REQUEST ERROR", err)
                return
            end
            updateStatus("Dropped " .. selectedPet.Name)
        end
    })

    --// Sleep
    Tab:CreateButton({
        Name = "🛏️ Put Pet To Sleep",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            print("DEBUG: action sleep", selectedPet.Name, selectedPet:GetFullName())
            updateStatus("Searching for bed...")
            local furnitureId, seat = Sleep.FindBed()
            print("DEBUG: Sleep.FindBed returned", furnitureId, seat and seat:GetFullName() or nil)
            if not furnitureId or not seat then
                updateStatus("No valid bed found")
                warn("BED NOT FOUND")
                return
            end
            local sleepCFrame = resolveCFrame(seat, "Seat1")
            print("DEBUG: resolved sleep CFrame", sleepCFrame)
            if not sleepCFrame then
                updateStatus("Invalid bed position")
                warn("BED CFRAME MISSING")
                return
            end
            updateStatus("Using bed...")
            print("USING BED:", furnitureId, seat:GetFullName())
            local args = {
                player,
                furnitureId,
                "Seat1",
                {
                    cframe = sleepCFrame
                },
                selectedPet
            }
            print("SENDING SLEEP REQUEST", furnitureId, seat:GetFullName())
            local ok, err = pcall(function()
                ActivateFurniture:InvokeServer(unpack(args))
            end)
            if not ok then
                updateStatus("Sleep request failed")
                warn("SLEEP REQUEST ERROR", err)
                return
            end
            updateStatus(selectedPet.Name .. " is sleeping")
        end
    })

    --// Feed Pet
    Tab:CreateButton({
        Name = "🍎 Feed Pet",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            print("DEBUG: action eat", selectedPet.Name, selectedPet:GetFullName())
            updateStatus("Searching for food...")
            local furnitureId, obj = Care.FindFood()
            print("DEBUG: Care.FindFood returned", furnitureId, obj and obj:GetFullName() or nil)
            if not furnitureId or not obj then
                updateStatus("No food found")
                warn("FOOD NOT FOUND")
                return
            end
            local foodCFrame = resolveCFrame(obj, "UseBlock")
            print("DEBUG: resolved food CFrame", foodCFrame)
            if not foodCFrame then
                updateStatus("Invalid food position")
                warn("FOOD CFRAME MISSING")
                return
            end
            updateStatus("Using food...")
            print("USING FOOD:", furnitureId, obj:GetFullName())
            local args = {
                player,
                furnitureId,
                "UseBlock",
                {
                    cframe = foodCFrame
                },
                selectedPet
            }
            print("SENDING EAT REQUEST", furnitureId, obj:GetFullName())
            local ok, err = pcall(function()
                ActivateFurniture:InvokeServer(unpack(args))
            end)
            if not ok then
                updateStatus("Feed request failed")
                warn("FEED REQUEST ERROR", err)
                return
            end
            updateStatus(selectedPet.Name .. " is eating")
        end
    })

    --// Drink Pet
    Tab:CreateButton({
        Name = "🥤 Give Pet Drink",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            print("DEBUG: action drink", selectedPet.Name, selectedPet:GetFullName())
            updateStatus("Searching for drink...")
            local furnitureId, obj = Care.FindDrink()
            print("DEBUG: Care.FindDrink returned", furnitureId, obj and obj:GetFullName() or nil)
            if not furnitureId or not obj then
                updateStatus("No drink found")
                warn("DRINK NOT FOUND")
                return
            end
            local drinkCFrame = resolveCFrame(obj, "UseBlock")
            print("DEBUG: resolved drink CFrame", drinkCFrame)
            if not drinkCFrame then
                updateStatus("Invalid drink position")
                warn("DRINK CFRAME MISSING")
                return
            end
            updateStatus("Using drink...")
            print("USING DRINK:", furnitureId, obj:GetFullName())
            local args = {
                player,
                furnitureId,
                "UseBlock",
                {
                    cframe = drinkCFrame
                },
                selectedPet
            }
            print("SENDING DRINK REQUEST", furnitureId, obj:GetFullName())
            local ok, err = pcall(function()
                ActivateFurniture:InvokeServer(unpack(args))
            end)
            if not ok then
                updateStatus("Drink request failed")
                warn("DRINK REQUEST ERROR", err)
                return
            end
            updateStatus(selectedPet.Name .. " is drinking")
        end
    })

    --// Shower Pet
    Tab:CreateButton({
        Name = "🚿 Shower Pet",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            print("DEBUG: action shower", selectedPet.Name, selectedPet:GetFullName())
            updateStatus("Searching for shower...")
            local furnitureId, obj = Care.FindShower()
            print("DEBUG: Care.FindShower returned", furnitureId, obj and obj:GetFullName() or nil)
            if not furnitureId or not obj then
                updateStatus("No shower found")
                warn("SHOWER NOT FOUND")
                return
            end
            local showerCFrame = resolveCFrame(obj, "UseBlock")
            print("DEBUG: resolved shower CFrame", showerCFrame)
            if not showerCFrame then
                updateStatus("Invalid shower position")
                warn("SHOWER CFRAME MISSING")
                return
            end
            updateStatus("Using shower...")
            print("USING SHOWER:", furnitureId, obj:GetFullName())
            local args = {
                player,
                furnitureId,
                "UseBlock",
                {
                    cframe = showerCFrame
                },
                selectedPet
            }
            print("SENDING SHOWER REQUEST", furnitureId, obj:GetFullName())
            local ok, err = pcall(function()
                ActivateFurniture:InvokeServer(unpack(args))
            end)
            if not ok then
                updateStatus("Shower request failed")
                warn("SHOWER REQUEST ERROR", err)
                return
            end
            updateStatus(selectedPet.Name .. " is showering")
        end
    })

    --// Toilet Pet
    Tab:CreateButton({
        Name = "🚽 Use Toilet",
        Callback = function()
            if not selectedPet then
                updateStatus("No pet selected")
                return
            end
            print("DEBUG: action toilet", selectedPet.Name, selectedPet:GetFullName())
            updateStatus("Searching for toilet...")
            local furnitureId, obj = Care.FindToilet()
            print("DEBUG: Care.FindToilet returned", furnitureId, obj and obj:GetFullName() or nil)
            if not furnitureId or not obj then
                updateStatus("No toilet found")
                warn("TOILET NOT FOUND")
                return
            end
            local toiletCFrame = resolveCFrame(obj, "Seat1")
            print("DEBUG: resolved toilet CFrame", toiletCFrame)
            if not toiletCFrame then
                updateStatus("Invalid toilet position")
                warn("TOILET CFRAME MISSING")
                return
            end
            updateStatus("Using toilet...")
            print("USING TOILET:", furnitureId, obj:GetFullName())
            local args = {
                player,
                furnitureId,
                "Seat1",
                {
                    cframe = toiletCFrame
                },
                selectedPet
            }
            print("SENDING TOILET REQUEST", furnitureId, obj:GetFullName())
            local ok, err = pcall(function()
                ActivateFurniture:InvokeServer(unpack(args))
            end)
            if not ok then
                updateStatus("Toilet request failed")
                warn("TOILET REQUEST ERROR", err)
                return
            end
            updateStatus(selectedPet.Name .. " is using toilet")
        end
    })

    local function runAutofarmOnce()
        local pet = resolveSelectedPet()
        if not pet then
            return false, "No pet selected or pet instance stale"
        end

        selectedPet = pet
        updateStatus("Checking pet needs...")
        local needs = getNeedsState(selectedPet)
        print("AUTOFARM STATE:", selectedPet.Name,
            "hungry=" .. tostring(needs.hungry),
            "thirsty=" .. tostring(isThirsty(selectedPet)),
            "dirty=" .. tostring(needs.dirty),
            "sleepy=" .. tostring(needs.sleepy),
            "sleeping=" .. tostring(isSleeping(selectedPet)))

        local active = selectedPet:FindFirstChild("ActivePerformances")
        if active then
            for _, perf in ipairs(active:GetChildren()) do
                print("AUTOFARM PERF:", perf.Name, perf.ClassName, perf.Value)
            end
        end
        local effects = selectedPet:FindFirstChild("effects") or selectedPet:FindFirstChild("Effects")
        if effects then
            for _, child in ipairs(effects:GetChildren()) do
                print("AUTOFARM EFFECT:", child.Name, child.ClassName, child.Value)
            end
        end

        debugPetState(selectedPet)

        if isSleeping(selectedPet) then
            updateStatus(selectedPet.Name .. " is already sleeping")
            return true
        end

        if isHungry(selectedPet) then
            updateStatus("Pet is hungry, teleporting to food...")
            local furnitureId, obj = Care.FindFood()
            local success, err = performFurnitureActivation(furnitureId, obj, "UseBlock", "food")
            if not success then
                return false, err
            end
            updateStatus(selectedPet.Name .. " is eating")
            return true
        end

        if isThirsty(selectedPet) then
            updateStatus("Pet is thirsty, teleporting to drink...")
            local furnitureId, obj = Care.FindDrink()
            local success, err = performFurnitureActivation(furnitureId, obj, "UseBlock", "drink")
            if not success then
                return false, err
            end
            updateStatus(selectedPet.Name .. " is drinking")
            return true
        end

        if needs.toilet then
            updateStatus("Pet needs toilet, teleporting to restroom...")
            local furnitureId, obj = Care.FindToilet()
            print("DEBUG AUTOFARM: Care.FindToilet returned", furnitureId, obj and obj:GetFullName() or nil)
            local success, err = performFurnitureActivation(furnitureId, obj, "Seat1", "toilet")
            if not success then
                warn("AUTOFARM TOILET ERROR", err)
                return false, err
            end
            markPetToilet(selectedPet, false)
            refreshSelectedPetStatus()
            updateStatus(selectedPet.Name .. " is using the toilet")
            return true
        end

        if isDirty(selectedPet) then
            print("DEBUG AUTOFARM: dirty state detected for", selectedPet.Name)
            updateStatus("Pet is dirty, teleporting to shower...")
            local furnitureId, obj = Care.FindShower()
            print("DEBUG AUTOFARM: Care.FindShower returned", furnitureId, obj and obj:GetFullName() or nil)
            local success, err = performFurnitureActivation(furnitureId, obj, "UseBlock", "shower")
            if not success then
                warn("AUTOFARM SHOWER ERROR", err)
                return false, err
            end
            updateStatus(selectedPet.Name .. " is showering")
            return true
        end

        if isSleepy(selectedPet) then
            updateStatus("Pet is sleepy, teleporting to bed...")
            local furnitureId, seat = Sleep.FindBed()
            local success, err = performFurnitureActivation(furnitureId, seat, "Seat1", "bed")
            if not success then
                return false, err
            end
            updateStatus(selectedPet.Name .. " is sleeping")
            return true
        end

        updateStatus("Pet doesn't need anything")
        return true
    end

    local function autofarmLoopFunction()
        while autofarmEnabled do
            if selectedPet then
                local ok, err = pcall(runAutofarmOnce)
                if not ok then
                    warn("AUTOFARM ERROR", err)
                    updateStatus("Autofarm error")
                end
            else
                updateStatus("Autofarm enabled but no pet selected")
            end
            task.wait(4)
        end
        autofarmLoop = nil
    end

    local function setAutofarmEnabled(enabled)
        autofarmEnabled = enabled
        if autofarmEnabled then
            updateStatus("Autofarm enabled")
            if not autofarmLoop then
                autofarmLoop = task.spawn(autofarmLoopFunction)
            end
        else
            updateStatus("Autofarm disabled")
        end
        refreshSelectedPetStatus()
    end

    --// Autofarm Toggle
    autofarmToggle = Tab:CreateToggle({
        Name = "🤖 Autofarm Enabled",
        CurrentValue = false,
        Flag = "AutoFarmToggle",
        Callback = function(value)
            setAutofarmEnabled(value)
        end
    })

    --// Initial Refresh
    refreshPets()
    refreshSelectedPetStatus()

    --// Remote Debug Logger
    print("=== PET APIS ===")
    local APIDebug = game:GetService("ReplicatedStorage"):WaitForChild("API")
    for _,v in pairs(APIDebug:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            print(v:GetFullName())
        end
    end

    Rayfield:LoadConfiguration()
end

return UI