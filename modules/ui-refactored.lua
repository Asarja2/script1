--// Pet Controller UI - Main Module
--// Refactored and modularized version

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Load modular components
local function loadModule(moduleName)
    local path = script.Parent:FindFirstChild(moduleName)
    if path then
        local fn = loadstring(path.Source)
        if fn then
            return pcall(fn)
        end
    end
    return nil
end

-- For local development, modules are already in folders
local Detection = require(script.Parent:FindFirstChild("Core"):FindFirstChild("Detection"))
local PetStates = require(script.Parent:FindFirstChild("Core"):FindFirstChild("PetStates"))
local TaskQueue = require(script.Parent:FindFirstChild("Core"):FindFirstChild("TaskQueue"))
local Helpers = require(script.Parent:FindFirstChild("Utils"):FindFirstChild("Helpers"))
local Furniture = require(script.Parent:FindFirstChild("Utils"):FindFirstChild("Furniture"))
local UIWindow = require(script.Parent:FindFirstChild("UI"):FindFirstChild("Window"))
local UIStatus = require(script.Parent:FindFirstChild("UI"):FindFirstChild("Status"))

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
    local handleDataChanged

    --// Initialize modules
    local petStates = PetStates.Init()
    local taskQueue = TaskQueue.Init()
    local detection = Detection.Init(petStates.PetAilmentCache, petStates.PetState)
    local furniture = Furniture.Init(player, ActivateFurniture, Helpers)
    local status = UIStatus.Init(detection)

    local dataChangedAutofarmThrottle = setmetatable({}, {__mode = "k"})

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
                        petStates.markPetDirty(pet, true)
                        if autofarmEnabled and selectedPet == pet then
                            taskQueue.queueAutofarmTask("shower", pet)
                        end
                    else
                        petStates.markPetDirty(pet, false)
                    end

                    if isSleepyNow then
                        petStates.markPetSleepy(pet, true)
                        if autofarmEnabled and selectedPet == pet then
                            taskQueue.queueAutofarmTask("sleep", pet)
                        end
                    else
                        petStates.markPetSleepy(pet, false)
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
    local window = UIWindow.createWindow(Rayfield)
    local tab = UIWindow.createTab(window, "Controls", 0)

    --// Status Section
    local StatusLabel = UIWindow.createLabel(tab, "Status: Ready")
    local PetStatusLabel = UIWindow.createLabel(tab, "Pet Status: unknown")
    status.setStatusLabels(StatusLabel, PetStatusLabel)

    --// Create Sections
    local PetSection = UIWindow.createSection(tab, "Pet Selection")
    local ActionSection = UIWindow.createSection(tab, "Actions")
    local CareSection = UIWindow.createSection(tab, "Care")

    --// Variables
    local selectedPet = nil
    local selectedPetName = nil
    local petOptions = {}
    local PetDropdown = nil
    local autofarmEnabled = false
    local autofarmToggle = nil
    local autofarmLoop = nil

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

    local function getNeedsState(pet)
        return {
            dirty = detection.isDirty(pet),
            sleepy = detection.isSleepy(pet),
            hungry = detection.isHungry(pet),
            thirsty = detection.isThirsty(pet),
            toilet = detection.isToilet(pet)
        }
    end

    local function refreshSelectedPetStatus()
        local pet = resolveSelectedPet()
        status.refreshSelectedPetStatus(pet)
    end

    local function activateForPet(furnitureId, target, partName, label, pet)
        pet = pet or resolveSelectedPet()
        return furniture.performFurnitureActivation(furnitureId, target, partName, label, pet)
    end

    --// Debug Remote Listeners
    if ReplicatePerformanceModifiers and ReplicatePerformanceModifiers:IsA("RemoteEvent") then
        ReplicatePerformanceModifiers.OnClientEvent:Connect(function(pet, data)
            print("DEBUG REMOTE: ReplicatePerformanceModifiers fired", pet and pet.Name, data)
            if pet then
                petStates.updatePetState(pet, data)
            end
            if selectedPet == pet then
                status.updateStatus("Remote says modifiers updated")
                attemptAutoShower(pet, "ReplicatePerformanceModifiers")
                attemptAutoSleep(pet, "ReplicatePerformanceModifiers")
            end
        end)
    end

    if ReplicateActivePerformances and ReplicateActivePerformances:IsA("RemoteEvent") then
        ReplicateActivePerformances.OnClientEvent:Connect(function(pet, data)
            print("DEBUG REMOTE: ReplicateActivePerformances fired", pet and pet.Name, data)
            if pet then
                petStates.updatePetState(pet, data)
            end
            if selectedPet and pet and selectedPet == pet then
                if type(data) == "table" and (data.Dirty or data.Transform or data.FocusPet) then
                    status.updateStatus("Remote says pet has active dirty/transform state")
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
                petStates.updatePetState(pet, data)
            end
            if selectedPet and pet and selectedPet == pet then
                if type(data) == "table" and (data.Dirty or data.Transform or data.FocusPet) then
                    status.updateStatus("Remote says pet has active reaction dirty/transform state")
                end
                attemptAutoShower(pet, "ReplicateActiveReactions")
                attemptAutoSleep(pet, "ReplicateActiveReactions")
            end
        end)
    end

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        handleDataChanged = function(playerName, dataType, data, timestamp)
            if dataType ~= "ailments_manager" or type(data) ~= "table" then
                return
            end
            petStates.syncFromAilmentsManager(data)
            local selected = resolveSelectedPet()
            if not selected then
                return
            end
            detection.debugPetNeeds(selected, "ailments_manager")
            refreshSelectedPetStatus()
            if autofarmEnabled then
                if detection.isToilet(selected) then
                    taskQueue.queueAutofarmTask("toilet", selected)
                end
                if detection.isDirty(selected) then
                    taskQueue.queueAutofarmTask("shower", selected)
                end
                if detection.isSleepy(selected) then
                    taskQueue.queueAutofarmTask("sleep", selected)
                end
                local last = dataChangedAutofarmThrottle[selected]
                if not last or (time() - last) > 2 then
                    dataChangedAutofarmThrottle[selected] = time()
                    task.spawn(function()
                        pcall(runAutofarmOnce)
                    end)
                end
            end
        end

        DataChanged.OnClientEvent:Connect(function(...)
            if handleDataChanged then
                pcall(handleDataChanged, ...)
            end
        end)
        print("Ailment detection: DataAPI/DataChanged (kind field)")
    end

    --// Pet Dropdown
    PetDropdown = tab:CreateDropdown({
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
                status.updateStatus("No pet selected")
                return
            end
            selectedPetName = selectedName
            selectedPet = Pets.FindPetByName(selectedName)
            if selectedPet then
                print("DEBUG: pet selected", selectedPet.Name, selectedPet:GetFullName())
                status.updateStatus("Selected: " .. selectedPet.Name)
                refreshSelectedPetStatus()
            else
                warn("DEBUG: selected pet by name not found", selectedName)
                status.updateStatus("Selected pet not found live")
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
            status.updateStatus("Found " .. #petOptions .. " pets")
            if PetDropdown then
                PetDropdown:Refresh(petOptions)
                if selectedPetName and Helpers.tableContains(petOptions, selectedPetName) then
                    PetDropdown:Set({selectedPetName})
                    selectedPet = Pets.FindPetByName(selectedPetName)
                    status.updateStatus("Re-selected: " .. selectedPetName)
                else
                    PetDropdown:Set({petOptions[1]})
                    selectedPetName = petOptions[1]
                    selectedPet = pets[1]
                    status.updateStatus("Auto-selected: " .. pets[1].Name)
                end
                refreshSelectedPetStatus()
            else
                warn("PetDropdown is nil in refreshPets")
            end
        else
            status.updateStatus("No pets found")
            if PetDropdown then
                PetDropdown:Refresh({"No pets available"})
                PetDropdown:Set({"No pets available"})
            else
                warn("PetDropdown is nil in refreshPets")
            end
        end
    end

    --// Autofarm Functions
    local autoShowerThrottle = {}
    local autoShowerDisabled = false
    local autoSleepThrottle = {}
    local autoToiletThrottle = {}

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
        if detection.isSleeping(pet) then
            return
        end
        if not detection.isDirty(pet) then
            return
        end
        taskQueue.queueAutofarmTask("shower", pet)
    end

    local function performAutoShower(pet)
        local furnitureId, obj = Care.FindShower()
        if not furnitureId or not obj then
            status.updateStatus("Auto-shower: no shower found")
            warn("AUTO SHOWER: no shower found")
            return
        end

        status.updateStatus("Auto-shower triggered")
        print("DEBUG AUTO-SHOWER", pet.Name)
        petStates.markPetDirty(pet, false)
        refreshSelectedPetStatus()

        task.spawn(function()
            local success, err = activateForPet(furnitureId, obj, "UseBlock", "shower", pet)
            if not success then
                warn("AUTO SHOWER ERROR", err)
                status.updateStatus("Auto shower failed")
            else
                status.updateStatus(pet.Name .. " is showering")
            end
        end)
    end

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
        if detection.isSleeping(pet) then
            return
        end
        if not detection.isSleepy(pet) then
            return
        end
        taskQueue.queueAutofarmTask("sleep", pet)
    end

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
        if not detection.isToilet(pet) then
            return
        end
        taskQueue.queueAutofarmTask("toilet", pet)
    end

    local function performAutoSleep(pet)
        local furnitureId, seat = Sleep.FindBed()
        if not furnitureId or not seat then
            status.updateStatus("Auto-sleep: no bed found")
            warn("AUTO SLEEP: no bed found")
            return
        end

        status.updateStatus("Auto-sleep triggered")
        print("DEBUG AUTO-SLEEP", pet.Name)
        markAutoSleep(pet)
        petStates.markPetSleepy(pet, false)
        refreshSelectedPetStatus()

        task.spawn(function()
            local success, err = activateForPet(furnitureId, seat, "Seat1", "bed", pet)
            if not success then
                warn("AUTO SLEEP ERROR", err)
                status.updateStatus("Auto sleep failed")
            else
                status.updateStatus(pet.Name .. " is sleeping")
            end
        end)
    end

    local function performAutoToilet(pet)
        local furnitureId, seat = Care.FindToilet()
        if not furnitureId or not seat then
            status.updateStatus("Auto-toilet: no toilet found")
            warn("AUTO TOILET: no toilet found")
            return
        end

        status.updateStatus("Auto-toilet triggered")
        print("DEBUG AUTO-TOILET", pet.Name)
        markAutoToilet(pet)

        task.spawn(function()
            local success, err = activateForPet(furnitureId, seat, "Seat1", "toilet", pet)
            if not success then
                warn("AUTO TOILET ERROR", err)
                status.updateStatus("Auto toilet failed")
            else
                status.updateStatus(pet.Name .. " is using the toilet")
            end
        end)
    end

    function runAutofarmOnce()
        local pet = resolveSelectedPet()
        if not pet then
            return false, "No pet selected"
        end

        status.updateStatus("Checking pet needs...")
        detection.debugPetNeeds(pet, "autofarm")

        if detection.isSleeping(pet) then
            status.updateStatus(pet.Name .. " is already sleeping")
            return true
        end

        if detection.isHungry(pet) then
            status.updateStatus("Pet is hungry, teleporting to food...")
            local furnitureId, obj = Care.FindFood()
            local success, err = activateForPet(furnitureId, obj, "UseBlock", "food", pet)
            if not success then
                return false, err
            end
            status.updateStatus(pet.Name .. " is eating")
            return true
        end

        if detection.isThirsty(pet) then
            status.updateStatus("Pet is thirsty, teleporting to drink...")
            local furnitureId, obj = Care.FindDrink()
            local success, err = activateForPet(furnitureId, obj, "UseBlock", "drink", pet)
            if not success then
                return false, err
            end
            status.updateStatus(pet.Name .. " is drinking")
            return true
        end

        if detection.isToilet(pet) then
            status.updateStatus("Pet needs toilet, teleporting to restroom...")
            local furnitureId, seat = Care.FindToilet()
            local success, err = activateForPet(furnitureId, seat, "Seat1", "toilet", pet)
            if not success then
                warn("AUTOFARM TOILET ERROR", err)
                return false, err
            end
            refreshSelectedPetStatus()
            status.updateStatus(pet.Name .. " is using the toilet")
            return true
        end

        if detection.isDirty(pet) then
            status.updateStatus("Pet is dirty, teleporting to shower...")
            local furnitureId, obj = Care.FindShower()
            local success, err = activateForPet(furnitureId, obj, "UseBlock", "shower", pet)
            if not success then
                warn("AUTOFARM SHOWER ERROR", err)
                return false, err
            end
            status.updateStatus(pet.Name .. " is showering")
            return true
        end

        if detection.isSleepy(pet) then
            status.updateStatus("Pet is sleepy, teleporting to bed...")
            local furnitureId, seat = Sleep.FindBed()
            local success, err = activateForPet(furnitureId, seat, "Seat1", "bed", pet)
            if not success then
                return false, err
            end
            status.updateStatus(pet.Name .. " is sleeping")
            return true
        end

        status.updateStatus("Pet doesn't need anything")
        return true
    end

    local function autofarmLoopFunction()
        while autofarmEnabled do
            if selectedPet then
                local ok, err = pcall(runAutofarmOnce)
                if not ok then
                    warn("AUTOFARM ERROR", err)
                    status.updateStatus("Autofarm error")
                end
            else
                status.updateStatus("Autofarm enabled but no pet selected")
            end
            task.wait(4)
        end
        autofarmLoop = nil
    end

    local function setAutofarmEnabled(enabled)
        autofarmEnabled = enabled
        if autofarmEnabled then
            status.updateStatus("Autofarm enabled")
            if not autofarmLoop then
                autofarmLoop = task.spawn(autofarmLoopFunction)
            end
        else
            status.updateStatus("Autofarm disabled")
        end
        refreshSelectedPetStatus()
    end

    --// Buttons
    tab:CreateButton({
        Name = "🔍 Debug Pet Needs",
        Callback = function()
            local pet = resolveSelectedPet()
            if not pet then
                status.updateStatus("No pet selected")
                return
            end
            detection.debugPetNeeds(pet, "manual")
            refreshSelectedPetStatus()
            status.updateStatus("Printed needs to console (F9)")
        end
    })

    tab:CreateButton({
        Name = "🔄 Refresh Pets",
        Callback = function()
            refreshPets()
            status.updateStatus("Pets refreshed")
        end
    })

    tab:CreateButton({
        Name = "❌ Clear Selection",
        Callback = function()
            selectedPet = nil
            if PetDropdown then
                PetDropdown:Set({"No pets available"})
            end
            status.updateStatus("Selection cleared")
        end
    })

    tab:CreateButton({
        Name = "🍼 Hold Pet",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Sending hold request...")
            local args = {selectedPet}
            local ok, err = pcall(function()
                HoldBaby:FireServer(unpack(args))
            end)
            if not ok then
                status.updateStatus("Hold request failed")
                warn("HOLD REQUEST ERROR", err)
                return
            end
            status.updateStatus("Holding " .. selectedPet.Name)
        end
    })

    tab:CreateButton({
        Name = "⬇️ Drop Pet",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Sending drop request...")
            local args = {selectedPet}
            local ok, err = pcall(function()
                EjectBaby:FireServer(unpack(args))
            end)
            if not ok then
                status.updateStatus("Drop request failed")
                warn("DROP REQUEST ERROR", err)
                return
            end
            status.updateStatus("Dropped " .. selectedPet.Name)
        end
    })

    --// Action Buttons
    tab:CreateButton({
        Name = "🛏️ Put Pet To Sleep",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Using bed...")
            local furnitureId, seat = Sleep.FindBed()
            if not furnitureId or not seat then
                status.updateStatus("No valid bed found")
                return
            end
            local pet = resolveSelectedPet()
            local ok, err = activateForPet(furnitureId, seat, "Seat1", "bed", pet)
            if not ok then
                status.updateStatus("Sleep request failed")
                warn("SLEEP REQUEST ERROR", err)
                return
            end
            status.updateStatus(selectedPet.Name .. " is sleeping")
        end
    })

    tab:CreateButton({
        Name = "🍎 Feed Pet",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Using food...")
            local furnitureId, obj = Care.FindFood()
            if not furnitureId or not obj then
                status.updateStatus("No food found")
                return
            end
            local pet = resolveSelectedPet()
            local ok, err = activateForPet(furnitureId, obj, "UseBlock", "food", pet)
            if not ok then
                status.updateStatus("Feed request failed")
                return
            end
            status.updateStatus(selectedPet.Name .. " is eating")
        end
    })

    tab:CreateButton({
        Name = "🥤 Give Pet Drink",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Using drink...")
            local furnitureId, obj = Care.FindDrink()
            if not furnitureId or not obj then
                status.updateStatus("No drink found")
                return
            end
            local pet = resolveSelectedPet()
            local ok, err = activateForPet(furnitureId, obj, "UseBlock", "drink", pet)
            if not ok then
                status.updateStatus("Drink request failed")
                return
            end
            status.updateStatus(selectedPet.Name .. " is drinking")
        end
    })

    tab:CreateButton({
        Name = "🚿 Shower Pet",
        Callback = function()
            if not selectedPet then
                status.updateStatus("No pet selected")
                return
            end
            status.updateStatus("Using shower...")
            local furnitureId, obj = Care.FindShower()
            if not furnitureId or not obj then
                status.updateStatus("No shower found")
                return
            end
            local pet = resolveSelectedPet()
            local ok, err = activateForPet(furnitureId, obj, "UseBlock", "shower", pet)
            if not ok then
                status.updateStatus("Shower request failed")
                return
            end
            status.updateStatus(selectedPet.Name .. " is showering")
        end
    })

    --// Autofarm Toggle
    autofarmToggle = tab:CreateToggle({
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

    Rayfield:LoadConfiguration()
end

return UI
