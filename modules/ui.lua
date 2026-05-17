--// Pet Controller
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local UI = {}

local TRACKED_AILMENTS = {
    "sleepy",
    "dirty",
    "hungry",
    "thirsty",
    "toilet",
    "school",
    "pet_me",
}

function UI.Init(Pets, Sleep, Care, Remotes)
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local ReplicatePerformanceModifiers = Remotes.ReplicatePerformanceModifiers
    local DataChanged = Remotes.DataChanged

    local PetAilmentCache = {}
    local PetState = setmetatable({}, {__mode = "k"})
    local selectedPet, selectedPetName = nil, nil
    local petOptions, PetDropdown = {}, nil
    local autofarmEnabled = false
    local autofarmLoop = nil

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
                return PetAilmentCache[candidate]
            end
        end
        for cacheId, cache in pairs(PetAilmentCache) do
            for _, candidate in ipairs(candidates) do
                if tostring(cacheId) == candidate then
                    return cache
                end
            end
        end
        local count, onlyCache = 0, nil
        for _, cache in pairs(PetAilmentCache) do
            count = count + 1
            onlyCache = cache
        end
        if count == 1 then
            return onlyCache
        end
        return nil
    end

    local function addAilmentKey(norm, key)
        if key then
            norm[tostring(key):lower()] = true
        end
    end

    local function ingestAilmentEntry(norm, ailmentName, ailmentData)
        addAilmentKey(norm, ailmentName)
        if type(ailmentData) ~= "table" then
            return
        end
        addAilmentKey(norm, ailmentData.kind)
        addAilmentKey(norm, ailmentData.ailment_key)
    end

    local function syncAilmentsFromData(data)
        if type(data) ~= "table" or type(data.ailments) ~= "table" then
            return
        end
        for petId, ailmentTable in pairs(data.ailments) do
            if type(ailmentTable) == "table" then
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
            end
        end
    end

    local function hasNeed(pet, needName)
        local cache = getCacheForPet(pet)
        return cache and cache[tostring(needName):lower()] == true or false
    end

    local function isDirty(pet) return hasNeed(pet, "dirty") end
    local function isSleepy(pet) return hasNeed(pet, "sleepy") end
    local function isHungry(pet) return hasNeed(pet, "hungry") end
    local function isThirsty(pet) return hasNeed(pet, "thirsty") end
    local function isToilet(pet) return hasNeed(pet, "toilet") end

    local function isSleeping(pet)
        local state = PetState[pet]
        if not state then return false end
        for key, value in pairs(state) do
            if value and tostring(key):lower():match("sleep|asleep|focus") then
                return true
            end
        end
        return false
    end

    local function debugPetNeeds(pet, source)
        if not pet then return end
        local cache = getCacheForPet(pet) or {}
        local keys = {}
        for k in pairs(cache) do table.insert(keys, k) end
        table.sort(keys)
        local parts = {}
        for _, name in ipairs(TRACKED_AILMENTS) do
            table.insert(parts, name .. "=" .. tostring(hasNeed(pet, name)))
        end
        print(
            "[PET NEEDS DEBUG]", source or "?",
            "pet=" .. pet.Name, "id=" .. tostring(resolvePetId(pet)),
            "| keys:", #keys == 0 and "(empty)" or table.concat(keys, ", "),
            "| " .. table.concat(parts, " ")
        )
    end

    local Window = Rayfield:CreateWindow({
        Name = "Pet Controller", Icon = 0, LoadingTitle = "Pet Controller",
        LoadingSubtitle = "Loading...", Theme = "Default", ToggleUIKeybind = Enum.KeyCode.F2,
        ConfigurationSaving = {Enabled = true, FolderName = "PetController", FileName = "config"}
    })

    local Tab = Window:CreateTab("Controls", 0)
    Tab:CreateSection("Status")
    local StatusLabel = Tab:CreateLabel("Status: Ready")
    local PetStatusLabel = Tab:CreateLabel("Pet Status: unknown")
    Tab:CreateSection("Pet Selection")
    Tab:CreateSection("Actions")

    local function updateStatus(text) StatusLabel:Set("Status: " .. text) end

    local function updatePetStatus(pet)
        if not pet then
            PetStatusLabel:Set("Pet Status: no pet selected")
            return
        end
        local s = {}
        if isSleeping(pet) then table.insert(s, "Sleeping") end
        if isDirty(pet) then table.insert(s, "Dirty") end
        if isSleepy(pet) then table.insert(s, "Sleepy") end
        if isHungry(pet) then table.insert(s, "Hungry") end
        if isThirsty(pet) then table.insert(s, "Thirsty") end
        if isToilet(pet) then table.insert(s, "Needs toilet") end
        PetStatusLabel:Set(#s == 0 and "Pet Status: no needs detected" or "Pet Status: " .. table.concat(s, ", "))
    end

    local function resolveSelectedPet()
        if selectedPet and selectedPet.Parent and selectedPet:IsDescendantOf(workspace) then
            return selectedPet
        end
        if selectedPetName then
            selectedPet = Pets.FindPetByName(selectedPetName)
            return selectedPet
        end
        return nil
    end

    local function activateFurniture(id, target, partName, label, pet)
        pet = pet or resolveSelectedPet()
        if not pet then return false, "No pet selected" end
        if not id or not target then return false, "No furniture" end

        local cframe = target:IsA("BasePart") and target.CFrame or (target.PrimaryPart and target.PrimaryPart.CFrame)
        if not cframe then
            local part = target:FindFirstChild(partName) or target:FindFirstChildOfClass("BasePart")
            cframe = part and part.CFrame
        end
        if not cframe then return false, "Invalid position" end

        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = cframe * CFrame.new(0, 0, -5) end

        print("DEBUG ACTION", label, "furnitureId=", id, "pet=", pet.Name)
        local ok, err = pcall(function()
            ActivateFurniture:InvokeServer(player, id, partName, {cframe = cframe}, pet)
        end)
        if not ok then
            warn("FURNITURE ERROR", label, err)
        end
        return ok, ok and "Success" or err
    end

    local runAutofarmOnce

    pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "FireServer" and (self == ReplicatePerformanceModifiers or tostring(self) == "PetAPI/ReplicatePerformanceModifiers") then
                local pet, data = ...
                if type(data) == "table" and pet then
                    PetState[pet] = PetState[pet] or {}
                    for k, v in pairs(data) do PetState[pet][k] = v end
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(playerName, dataType, data, timestamp)
            if dataType ~= "ailments_manager" then return end
            syncAilmentsFromData(data)
            local pet = resolveSelectedPet()
            if pet then
                debugPetNeeds(pet, "ailments_manager")
                updatePetStatus(pet)
                if autofarmEnabled and runAutofarmOnce then
                    task.spawn(function() pcall(runAutofarmOnce) end)
                end
            end
        end)
        print("Ailment detection: DataAPI/DataChanged (kind field)")
    end

    runAutofarmOnce = function()
        local pet = resolveSelectedPet()
        if not pet then return false end
        debugPetNeeds(pet, "autofarm")
        if isSleeping(pet) then return true end

        if isHungry(pet) then
            updateStatus("Feeding...")
            local id, obj = Care.FindFood()
            if id and obj then activateFurniture(id, obj, "UseBlock", "food", pet) end
            return true
        end
        if isThirsty(pet) then
            updateStatus("Drinking...")
            local id, obj = Care.FindDrink()
            if id and obj then activateFurniture(id, obj, "UseBlock", "drink", pet) end
            return true
        end
        if isToilet(pet) then
            updateStatus("Toilet...")
            local id, obj = Care.FindToilet()
            if id and obj then activateFurniture(id, obj, "Seat1", "toilet", pet) end
            return true
        end
        if isDirty(pet) then
            updateStatus("Shower...")
            local id, obj = Care.FindShower()
            if id and obj then activateFurniture(id, obj, "UseBlock", "shower", pet) end
            return true
        end
        if isSleepy(pet) then
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
                        if resolveSelectedPet() then pcall(runAutofarmOnce)
                        else updateStatus("No pet selected") end
                        task.wait(4)
                    end
                    autofarmLoop = nil
                end)
            end
        else
            updateStatus("Autofarm disabled")
        end
        updatePetStatus(resolveSelectedPet())
    end

    PetDropdown = Tab:CreateDropdown({
        Name = "Select Pet", Options = {"No pets available"}, CurrentOption = {"No pets available"},
        MultipleOptions = false, Flag = "PetDropdown",
        Callback = function(opts)
            if opts[1] == "No pets available" then selectedPet, selectedPetName = nil, nil updateStatus("No pet") return end
            selectedPetName = opts[1]
            selectedPet = Pets.FindPetByName(opts[1])
            if selectedPet then updateStatus("Selected: " .. selectedPet.Name) updatePetStatus(selectedPet)
            else updateStatus("Pet not found") end
        end
    })

    Tab:CreateButton({Name = "🔄 Refresh", Callback = function()
        petOptions = {}
        for _, p in ipairs(Pets.GetPets()) do table.insert(petOptions, p.Name) end
        if #petOptions > 0 then
            PetDropdown:Refresh(petOptions)
            PetDropdown:Set({petOptions[1]})
            selectedPet = Pets.GetPets()[1]
            selectedPetName = petOptions[1]
            updateStatus("Found " .. #petOptions .. " pets")
            updatePetStatus(selectedPet)
        else
            PetDropdown:Refresh({"No pets available"})
            updateStatus("No pets found")
        end
    end})

    Tab:CreateButton({Name = "❌ Clear", Callback = function()
        selectedPet, selectedPetName = nil, nil
        updateStatus("Cleared")
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

    Tab:CreateToggle({Name = "🤖 Autofarm", CurrentValue = false, Flag = "Autofarm",
        Callback = function(v) setAutofarm(v) end
    })

    Tab:CreateButton({Name = "🔍 Debug Pet Needs", Callback = function()
        local pet = resolveSelectedPet()
        if not pet then updateStatus("No pet selected") return end
        debugPetNeeds(pet, "manual")
        updatePetStatus(pet)
        updateStatus("Printed needs to console (F9)")
    end})

    local pets = Pets.GetPets()
    if #pets > 0 then
        for _, p in ipairs(pets) do table.insert(petOptions, p.Name) end
        PetDropdown:Refresh(petOptions)
        selectedPet = pets[1]
        selectedPetName = petOptions[1]
        updatePetStatus(selectedPet)
    end

    Rayfield:LoadConfiguration()
end

return UI
