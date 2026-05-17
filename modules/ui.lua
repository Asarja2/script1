--// Pet Controller UI — needs from PetStates only (ailments_manager.kind)

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local UI = {}

function UI.Init(Pets, Sleep, Care, Remotes, PetState)
    if not PetState then
        warn("Pet Controller: PetStates module missing — load Core/PetStates before ui")
        return
    end

    local player = game:GetService("Players").LocalPlayer
    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local DataChanged = Remotes.DataChanged

    local selectedPetName = nil
    local petOptions = {}
    local PetDropdown = nil
    local autofarmEnabled = false
    local autofarmLoop = nil

    local function resolveSelectedPet()
        if not selectedPetName then
            return nil
        end
        local pet = Pets.FindPetByName(selectedPetName)
        if pet and pet.Parent and pet:IsDescendantOf(workspace) then
            return pet
        end
        return nil
    end

    local function activateFurniture(id, target, partName, label, pet)
        pet = pet or resolveSelectedPet()
        if not pet then
            return false, "No pet selected"
        end
        if not id or not target then
            return false, "No furniture"
        end

        local cframe = target:IsA("BasePart") and target.CFrame or (target.PrimaryPart and target.PrimaryPart.CFrame)
        if not cframe then
            local part = target:FindFirstChild(partName) or target:FindFirstChildOfClass("BasePart")
            cframe = part and part.CFrame
        end
        if not cframe then
            return false, "Invalid position"
        end

        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = cframe * CFrame.new(0, 0, -5)
        end

        print("DEBUG ACTION", label, "pet=", pet.Name, "furnitureId=", id)
        local ok, err = pcall(function()
            ActivateFurniture:InvokeServer(player, id, partName, {cframe = cframe}, pet)
        end)
        if not ok then
            warn("FURNITURE ERROR", label, err)
        end
        return ok, ok and "Success" or err
    end

    local Window = Rayfield:CreateWindow({
        Name = "Pet Controller",
        Icon = 0,
        LoadingTitle = "Pet Controller",
        LoadingSubtitle = "Loading...",
        Theme = "Default",
        ToggleUIKeybind = Enum.KeyCode.F2,
        ConfigurationSaving = {Enabled = true, FolderName = "PetController", FileName = "config"},
    })

    local Tab = Window:CreateTab("Controls", 0)
    Tab:CreateSection("Status")
    local StatusLabel = Tab:CreateLabel("Status: Ready")
    local PetStatusLabel = Tab:CreateLabel("Pet Status: unknown")
    Tab:CreateSection("Pet Selection")
    Tab:CreateSection("Actions")

    local function updateStatus(text)
        StatusLabel:Set("Status: " .. text)
    end

    local function updatePetStatusLabel()
        local pet = resolveSelectedPet()
        if not pet then
            PetStatusLabel:Set("Pet Status: no pet selected")
            return
        end
        local parts = {}
        if PetState.isDirty(pet) then table.insert(parts, "Dirty") end
        if PetState.isSleepy(pet) then table.insert(parts, "Sleepy") end
        if PetState.isHungry(pet) then table.insert(parts, "Hungry") end
        if PetState.isThirsty(pet) then table.insert(parts, "Thirsty") end
        if PetState.isToilet(pet) then table.insert(parts, "Needs toilet") end
        if PetState.isSchool(pet) then table.insert(parts, "School") end
        if PetState.isPetMe(pet) then table.insert(parts, "Wants attention") end
        PetStatusLabel:Set(
            #parts == 0 and "Pet Status: no needs detected" or ("Pet Status: " .. table.concat(parts, ", "))
        )
    end

    local runAutofarmOnce

    runAutofarmOnce = function()
        local pet = resolveSelectedPet()
        if not pet then
            return false
        end
        PetState.debugPetNeeds(pet, "autofarm")

        if PetState.isHungry(pet) then
            updateStatus("Feeding...")
            local id, obj = Care.FindFood()
            if id and obj then activateFurniture(id, obj, "UseBlock", "food", pet) end
            return true
        end
        if PetState.isThirsty(pet) then
            updateStatus("Drinking...")
            local id, obj = Care.FindDrink()
            if id and obj then activateFurniture(id, obj, "UseBlock", "drink", pet) end
            return true
        end
        if PetState.isToilet(pet) then
            updateStatus("Toilet...")
            local id, obj = Care.FindToilet()
            if id and obj then activateFurniture(id, obj, "Seat1", "toilet", pet) end
            return true
        end
        if PetState.isDirty(pet) then
            updateStatus("Shower...")
            local id, obj = Care.FindShower()
            if id and obj then activateFurniture(id, obj, "UseBlock", "shower", pet) end
            return true
        end
        if PetState.isSleepy(pet) then
            updateStatus("Sleep...")
            local id, obj = Sleep.FindBed()
            if id and obj then activateFurniture(id, obj, "Seat1", "bed", pet) end
            return true
        end
        return true
    end

    local function setAutofarm(enabled)
        autofarmEnabled = enabled
        if enabled then
            updateStatus("Autofarm enabled")
            if not autofarmLoop then
                autofarmLoop = task.spawn(function()
                    while autofarmEnabled do
                        if resolveSelectedPet() then
                            pcall(runAutofarmOnce)
                        else
                            updateStatus("No pet selected")
                        end
                        task.wait(4)
                    end
                    autofarmLoop = nil
                end)
            end
        else
            updateStatus("Autofarm disabled")
        end
        updatePetStatusLabel()
    end

    local function onAilmentsUpdated()
        local pet = resolveSelectedPet()
        if pet then
            PetState.debugPetNeeds(pet, "ailments_manager")
            updatePetStatusLabel()
            if autofarmEnabled then
                task.spawn(function()
                    pcall(runAutofarmOnce)
                end)
            end
        end
    end

    PetState.subscribe(onAilmentsUpdated)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(_, dataType, data)
            if dataType ~= "ailments_manager" then
                return
            end
            PetState.parseAilmentsManager(data)
        end)
        print("Pet Controller: ailments_manager → PetState (kind)")
    else
        warn("Pet Controller: DataAPI/DataChanged missing")
    end

    PetDropdown = Tab:CreateDropdown({
        Name = "Select Pet",
        Options = {"No pets available"},
        CurrentOption = {"No pets available"},
        MultipleOptions = false,
        Flag = "PetDropdown",
        Callback = function(opts)
            if opts[1] == "No pets available" then
                selectedPetName = nil
                updateStatus("No pet")
                updatePetStatusLabel()
                return
            end
            selectedPetName = opts[1]
            local pet = resolveSelectedPet()
            if pet then
                updateStatus("Selected: " .. pet.Name)
                PetState.debugPetNeeds(pet, "select")
            else
                updateStatus("Pet not found")
            end
            updatePetStatusLabel()
        end,
    })

    Tab:CreateButton({Name = "🔄 Refresh", Callback = function()
        petOptions = {}
        for _, p in ipairs(Pets.GetPets()) do
            table.insert(petOptions, p.Name)
        end
        if #petOptions > 0 then
            PetDropdown:Refresh(petOptions)
            PetDropdown:Set({petOptions[1]})
            selectedPetName = petOptions[1]
            updateStatus("Found " .. #petOptions .. " pets")
            updatePetStatusLabel()
        else
            PetDropdown:Refresh({"No pets available"})
            updateStatus("No pets found")
        end
    end})

    Tab:CreateButton({Name = "❌ Clear", Callback = function()
        selectedPetName = nil
        updateStatus("Cleared")
        updatePetStatusLabel()
    end})

    Tab:CreateButton({Name = "🍼 Hold", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        pcall(function() HoldBaby:FireServer(pet) end)
        updateStatus("Holding " .. pet.Name)
    end})

    Tab:CreateButton({Name = "⬇️ Drop", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        pcall(function() EjectBaby:FireServer(pet) end)
        updateStatus("Dropped " .. pet.Name)
    end})

    Tab:CreateButton({Name = "🛏️ Sleep", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Sleep.FindBed()
        if id and obj then activateFurniture(id, obj, "Seat1", "sleep", pet) end
        updateStatus(id and "Sleeping" or "No bed")
    end})

    Tab:CreateButton({Name = "🍎 Feed", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindFood()
        if id and obj then activateFurniture(id, obj, "UseBlock", "food", pet) end
        updateStatus(id and "Eating" or "No food")
    end})

    Tab:CreateButton({Name = "🥤 Drink", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindDrink()
        if id and obj then activateFurniture(id, obj, "UseBlock", "drink", pet) end
        updateStatus(id and "Drinking" or "No drink")
    end})

    Tab:CreateButton({Name = "🚿 Shower", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindShower()
        if id and obj then activateFurniture(id, obj, "UseBlock", "shower", pet) end
        updateStatus(id and "Showering" or "No shower")
    end})

    Tab:CreateButton({Name = "🚽 Toilet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindToilet()
        if id and obj then activateFurniture(id, obj, "Seat1", "toilet", pet) end
        updateStatus(id and "Toilet" or "No toilet")
    end})

    Tab:CreateToggle({Name = "🤖 Autofarm", CurrentValue = false, Flag = "Autofarm", Callback = function(v)
        setAutofarm(v)
    end})

    Tab:CreateButton({Name = "🔍 Debug Pet Needs", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet selected") return end
        PetState.debugPetNeeds(pet, "manual")
        updatePetStatusLabel()
        updateStatus("Printed needs to console (F9)")
    end})

    local pets = Pets.GetPets()
    if #pets > 0 then
        for _, p in ipairs(pets) do
            table.insert(petOptions, p.Name)
        end
        PetDropdown:Refresh(petOptions)
        selectedPetName = petOptions[1]
        updatePetStatusLabel()
    end

    Rayfield:LoadConfiguration()
end

return UI
