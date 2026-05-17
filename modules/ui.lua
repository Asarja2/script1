--// Pet Controller — Rayfield UI + live ailment panel (AilmentViewer logic)

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local UI = {}

local COLOR_OFF = Color3.fromRGB(255, 80, 80)
local COLOR_ON = Color3.fromRGB(80, 255, 120)
local COLOR_MUTED = Color3.fromRGB(160, 160, 170)

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
    local ailmentsPanelRefresh = nil

    local ailmentsToTrack = PetState.TRACKED_AILMENTS

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
        LoadingSubtitle = "Adopt Me pet care",
        ShowText = "Pet Controller",
        Theme = "Ocean",
        ToggleUIKeybind = Enum.KeyCode.F2,
        DisableRayfieldPrompts = false,
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "PetController",
            FileName = "config",
        },
    })

    local ControlsTab = Window:CreateTab("Controls", "gamepad-2")
    local NeedsTab = Window:CreateTab("Pet Needs", "heart-pulse")

    ControlsTab:CreateSection("Status")
    local StatusLabel = ControlsTab:CreateLabel("Status: Ready", 0, COLOR_MUTED, false)
    ControlsTab:CreateSection("Pet Selection")

    NeedsTab:CreateSection("Live ailments (selected pet)")
    NeedsTab:CreateParagraph({
        Title = "How this works",
        Content = "Updates from DataAPI/DataChanged (ailments_manager). Green = active need. Check Raw keys if thirsty shows false but you expect thirst.",
    })

    local PetIdLabel = NeedsTab:CreateLabel("Pet ID: —", 0, COLOR_MUTED, false)
    NeedsTab:CreateDivider()

    local ailmentLabels = {}
    for _, name in ipairs(ailmentsToTrack) do
        ailmentLabels[name] = NeedsTab:CreateLabel(name .. ": false", 0, COLOR_OFF, false)
    end

    NeedsTab:CreateDivider()
    local RawKeysLabel = NeedsTab:CreateLabel("Raw keys: (waiting)", 0, COLOR_MUTED, false)

    local function setAilmentLabel(name, isActive)
        local label = ailmentLabels[name]
        if not label then
            return
        end
        if isActive then
            label:Set(name .. ": true", 0, COLOR_ON, false)
        else
            label:Set(name .. ": false", 0, COLOR_OFF, false)
        end
    end

    local function refreshAilmentPanel()
        local pet = resolveSelectedPet()
        if not pet then
            PetIdLabel:Set("Pet ID: no pet selected", 0, COLOR_MUTED, false)
            for _, name in ipairs(ailmentsToTrack) do
                setAilmentLabel(name, false)
            end
            RawKeysLabel:Set("Raw keys: —", 0, COLOR_MUTED, false)
            return
        end

        local stateId = PetState.findStateId(pet)
        local resolveId = PetState.resolvePetId(pet)
        PetIdLabel:Set(
            "Pet ID: " .. tostring(stateId or resolveId or "?"),
            0,
            COLOR_MUTED,
            false
        )

        for _, name in ipairs(ailmentsToTrack) do
            setAilmentLabel(name, PetState.hasNeed(pet, name))
        end

        local active = PetState.getActive(pet)
        if active then
            local keys = {}
            for key in pairs(active) do
                table.insert(keys, key)
            end
            table.sort(keys)
            RawKeysLabel:Set(
                #keys > 0 and ("Raw keys: " .. table.concat(keys, ", ")) or "Raw keys: (none)",
                0,
                COLOR_MUTED,
                false
            )
        else
            RawKeysLabel:Set("Raw keys: no data yet — wait for ailments_manager", 0, COLOR_MUTED, false)
        end
    end

    ailmentsPanelRefresh = refreshAilmentPanel

    local function updateStatus(text)
        StatusLabel:Set("Status: " .. text, 0, COLOR_MUTED, false)
    end

    local function refreshAllUI()
        refreshAilmentPanel()
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
            Rayfield:Notify({
                Title = "Autofarm",
                Content = "Watching pet needs from ailments_manager",
                Duration = 4,
                Image = "bot",
            })
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
        refreshAllUI()
    end

    PetState.subscribe(function()
        refreshAllUI()
        local pet = resolveSelectedPet()
        if pet and autofarmEnabled then
            task.spawn(function()
                pcall(runAutofarmOnce)
            end)
        end
    end)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(_, dataType, data)
            if dataType ~= "ailments_manager" then
                return
            end
            PetState.parseAilmentsManager(data)
        end)
    else
        warn("DataAPI/DataChanged missing")
    end

    ControlsTab:CreateSection("Actions")

    PetDropdown = ControlsTab:CreateDropdown({
        Name = "Select Pet",
        Options = {"No pets available"},
        CurrentOption = {"No pets available"},
        MultipleOptions = false,
        Flag = "PetDropdown",
        Callback = function(opts)
            if opts[1] == "No pets available" then
                selectedPetName = nil
                updateStatus("No pet")
                refreshAllUI()
                return
            end
            selectedPetName = opts[1]
            local pet = resolveSelectedPet()
            updateStatus(pet and ("Selected: " .. pet.Name) or "Pet not found")
            if pet then
                PetState.debugPetNeeds(pet, "select")
            end
            refreshAllUI()
        end,
    })

    ControlsTab:CreateButton({Name = "Refresh Pets", Callback = function()
        petOptions = {}
        for _, p in ipairs(Pets.GetPets()) do
            table.insert(petOptions, p.Name)
        end
        if #petOptions > 0 then
            PetDropdown:Refresh(petOptions)
            PetDropdown:Set({petOptions[1]})
            selectedPetName = petOptions[1]
            updateStatus("Found " .. #petOptions .. " pets")
        else
            PetDropdown:Refresh({"No pets available"})
            updateStatus("No pets found")
        end
        refreshAllUI()
    end})

    ControlsTab:CreateButton({Name = "Clear Selection", Callback = function()
        selectedPetName = nil
        updateStatus("Cleared")
        refreshAllUI()
    end})

    ControlsTab:CreateDivider()
    ControlsTab:CreateSection("Care")

    ControlsTab:CreateButton({Name = "Hold Pet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        pcall(function() HoldBaby:FireServer(pet) end)
        updateStatus("Holding " .. pet.Name)
    end})

    ControlsTab:CreateButton({Name = "Drop Pet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        pcall(function() EjectBaby:FireServer(pet) end)
        updateStatus("Dropped " .. pet.Name)
    end})

    ControlsTab:CreateButton({Name = "Put To Sleep", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Sleep.FindBed()
        if id and obj then activateFurniture(id, obj, "Seat1", "sleep", pet) end
        updateStatus(id and "Sleeping" or "No bed")
    end})

    ControlsTab:CreateButton({Name = "Feed Pet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindFood()
        if id and obj then activateFurniture(id, obj, "UseBlock", "food", pet) end
        updateStatus(id and "Eating" or "No food")
    end})

    ControlsTab:CreateButton({Name = "Give Drink", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindDrink()
        if id and obj then activateFurniture(id, obj, "UseBlock", "drink", pet) end
        updateStatus(id and "Drinking" or "No drink")
    end})

    ControlsTab:CreateButton({Name = "Shower Pet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindShower()
        if id and obj then activateFurniture(id, obj, "UseBlock", "shower", pet) end
        updateStatus(id and "Showering" or "No shower")
    end})

    ControlsTab:CreateButton({Name = "Toilet", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet") return end
        local id, obj = Care.FindToilet()
        if id and obj then activateFurniture(id, obj, "Seat1", "toilet", pet) end
        updateStatus(id and "Toilet" or "No toilet")
    end})

    ControlsTab:CreateDivider()
    ControlsTab:CreateSection("Automation")

    ControlsTab:CreateToggle({Name = "Autofarm", CurrentValue = false, Flag = "Autofarm", Callback = function(v)
        setAutofarm(v)
    end})

    NeedsTab:CreateButton({Name = "Refresh Needs Display", Callback = function()
        local pet = resolveSelectedPet()
        if pet then
            PetState.debugPetNeeds(pet, "manual")
        end
        refreshAilmentPanel()
        Rayfield:Notify({
            Title = "Needs refreshed",
            Content = pet and ("Checked " .. pet.Name) or "No pet selected",
            Duration = 3,
            Image = "refresh-cw",
        })
    end})

    local pets = Pets.GetPets()
    if #pets > 0 then
        for _, p in ipairs(pets) do
            table.insert(petOptions, p.Name)
        end
        PetDropdown:Refresh(petOptions)
        selectedPetName = petOptions[1]
    end

    refreshAllUI()
    Rayfield:LoadConfiguration()

    Rayfield:Notify({
        Title = "Pet Controller loaded",
        Content = "Open the Pet Needs tab to see live ailments",
        Duration = 5,
        Image = "check",
    })

    print("Pet Controller loaded — Pet Needs tab shows ailments_manager data")
end

return UI
