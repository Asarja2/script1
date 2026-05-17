--// Pet Controller - Minimized (500 Lines)
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local UI = {}

function UI.Init(Pets, Sleep, Care, Remotes)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local API = ReplicatedStorage:WaitForChild("API")
    
    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local ReplicatePerformanceModifiers = Remotes.ReplicatePerformanceModifiers
    local DataChanged = Remotes.DataChanged
    local handleDataChanged, handleDataChangedGuard = nil, false

    --// STATE
    local PetAilmentCache = {}
    local PetState = setmetatable({}, {__mode = "k"})
    local selectedPet, selectedPetName = nil, nil
    local petOptions, PetDropdown = {}, nil
    local autofarmEnabled = false
    local autoThrottle = {}
    
    local AILMENT_MAPPINGS = {
        hungry = {"hungry", "feed", "needsfood", "needs_food", "hunger", "starving"},
        thirsty = {"thirsty", "needsdrink", "drink", "thirst", "needs_drink"},
        dirty = {"dirty", "stinky", "stink", "needsbath", "needs_bath", "bath"},
        toilet = {"toilet", "pee", "poop", "restroom"},
        sleepy = {"sleepy", "tired", "needsleep", "needs_sleep", "sleep"},
        school = {"school"},
        pet_me = {"pet_me", "petme", "pet"},
    }

    --// HELPERS
    local function resolvePetId(pet)
        return pet and pet:IsA("Model") and tostring(pet:GetAttribute("unique") or pet:GetAttribute("id") or pet.Name) or nil
    end

    local function addAilmentKey(norm, key)
        if key then norm[tostring(key):lower()] = true end
    end

    local function collectAilments(ailData, norm)
        if type(ailData) ~= "table" then return end
        addAilmentKey(norm, ailData.ailment_key)
        addAilmentKey(norm, ailData.kind)
        addAilmentKey(norm, ailData.ailment_name)
        if type(ailData.components) == "table" then
            for name, data in pairs(ailData.components) do
                addAilmentKey(norm, name)
                collectAilments(data, norm)
            end
        end
    end

    local function markPet(pet, ailment, value)
        if not pet or not pet:IsA("Model") then return end
        local petId = resolvePetId(pet)
        if petId then
            local cache = PetAilmentCache[petId] or {}
            cache[ailment] = value and true or nil
            PetAilmentCache[petId] = cache
        end
    end

    local function hasAilment(pet, ailName)
        local petId = resolvePetId(pet)
        return petId and PetAilmentCache[petId] and PetAilmentCache[petId][tostring(ailName):lower()] ~= nil or false
    end

    local function checkAnyAilment(pet, ailments)
        for _, a in ipairs(ailments) do if hasAilment(pet, a) then return true end end
        return false
    end

    local function checkMappedNeed(pet, needName)
        local keys = AILMENT_MAPPINGS[needName]
        return keys and checkAnyAilment(pet, keys) or false
    end

    local function getActiveCacheKeys(pet)
        local petId = resolvePetId(pet)
        if not petId or not PetAilmentCache[petId] then return {} end
        local keys = {}
        for key in pairs(PetAilmentCache[petId]) do
            table.insert(keys, tostring(key))
        end
        table.sort(keys)
        return keys
    end

    local function debugPetNeeds(pet, source)
        if not pet then return end
        local cacheKeys = table.concat(getActiveCacheKeys(pet), ", ")
        print(
            "[PET NEEDS DEBUG]",
            source or "?",
            "pet=" .. pet.Name,
            "id=" .. tostring(resolvePetId(pet)),
            "| cache:", cacheKeys == "" and "(empty)" or cacheKeys,
            "| sleepy=" .. tostring(checkMappedNeed(pet, "sleepy")),
            "dirty=" .. tostring(checkMappedNeed(pet, "dirty")),
            "hungry=" .. tostring(checkMappedNeed(pet, "hungry")),
            "thirsty=" .. tostring(checkMappedNeed(pet, "thirsty")),
            "toilet=" .. tostring(checkMappedNeed(pet, "toilet")),
            "school=" .. tostring(checkMappedNeed(pet, "school")),
            "pet_me=" .. tostring(checkMappedNeed(pet, "pet_me"))
        )
    end

    local function syncAilmentsFromData(data)
        if type(data) ~= "table" or type(data.ailments) ~= "table" then
            return
        end
        for petId, ailmentTable in pairs(data.ailments) do
            if type(ailmentTable) == "table" then
                local normalized = {}
                for ailmentName, ailmentData in pairs(ailmentTable) do
                    local key = tostring(ailmentName):lower()
                    normalized[key] = true
                    print("PET:", petId, "AILMENT:", ailmentName)
                    collectAilments(ailmentData, normalized)
                end
                PetAilmentCache[tostring(petId)] = normalized
            end
        end
    end

    --// DETECTION (ailments_manager cache + key aliases)
    local function isDirty(pet) return checkMappedNeed(pet, "dirty") end
    local function isSleepy(pet) return checkMappedNeed(pet, "sleepy") end
    local function isHungry(pet) return checkMappedNeed(pet, "hungry") end
    local function isThirsty(pet) return checkMappedNeed(pet, "thirsty") end
    local function isToilet(pet) return checkMappedNeed(pet, "toilet") end
    local function isSleeping(pet)
        local state = PetState[pet]
        if not state then return false end
        for key in pairs(state) do
            if tostring(key):lower():match("sleep|asleep|focus") then return state[key] end
        end
        return false
    end

    --// UI
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
        if not pet then PetStatusLabel:Set("Pet Status: no pet selected") return end
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
        if selectedPet and selectedPet.Parent and selectedPet:IsDescendantOf(workspace) then return selectedPet end
        if selectedPetName then selectedPet = Pets.FindPetByName(selectedPetName) return selectedPet end
        return nil
    end

    --// HOOKS
    pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if getnamecallmethod() == "FireServer" and (self == ReplicatePerformanceModifiers or tostring(self) == "PetAPI/ReplicatePerformanceModifiers") then
                local args = {...}
                local pet, data = args[1], args[2]
                if type(data) == "table" then
                    local dirty = data.TransitionDirty or data.DirtyAilmentReaction
                    local sleepy = false
                    if type(data.effects) == "table" then
                        for _, e in ipairs(data.effects) do
                            if tostring(e):lower() == "stinky" then dirty = true end
                            if tostring(e):lower() == "sleep" then sleepy = true end
                        end
                    end
                    markPet(pet, "dirty", dirty)
                    markPet(pet, "sleepy", sleepy)
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)

    --// DATA CHANGED (ailments_manager — same method as AilmentViewer example)
    if DataChanged and DataChanged:IsA("RemoteEvent") then
        handleDataChanged = function(playerName, dataType, data, timestamp)
            if dataType ~= "ailments_manager" or type(data) ~= "table" then
                return
            end
            if handleDataChangedGuard then
                return
            end
            handleDataChangedGuard = true
            syncAilmentsFromData(data)
            local pet = resolveSelectedPet()
            if pet then
                local petId = resolvePetId(pet)
                if petId and data.ailments and data.ailments[petId] == nil then
                    for id, _ in pairs(data.ailments) do
                        if tostring(id) == tostring(petId) then
                            petId = id
                            break
                        end
                    end
                end
                debugPetNeeds(pet, "ailments_manager")
                updatePetStatus(pet)
                if autofarmEnabled then
                    task.spawn(function() pcall(runAutofarmOnce) end)
                end
            end
            handleDataChangedGuard = false
        end
        DataChanged.OnClientEvent:Connect(function(...)
            if handleDataChanged then
                pcall(handleDataChanged, ...)
            end
        end)
        print("Ailment detection: listening to DataAPI/DataChanged (ailments_manager)")
    else
        warn("Ailment detection: DataAPI/DataChanged not found")
    end

    --// FURNITURE
    local function activateFurniture(id, target, partName, label)
        if not id or not target then return false, "No furniture" end
        local cframe = target:IsA("BasePart") and target.CFrame or (target.PrimaryPart and target.PrimaryPart.CFrame) or nil
        if not cframe then
            local part = target:FindFirstChild(partName) or target:FindFirstChildOfClass("BasePart")
            cframe = part and part.CFrame or nil
        end
        if not cframe then return false, "Invalid position" end
        
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = cframe * CFrame.new(0, 0, -5) end
        
        local ok = pcall(function() ActivateFurniture:InvokeServer(player, id, partName, {cframe = cframe}, selectedPet) end)
        return ok, ok and "Success" or "Failed"
    end

    --// AUTOFARM
    local function runAutofarmOnce()
        if not selectedPet then return false end
        debugPetNeeds(selectedPet, "autofarm")
        if isSleeping(selectedPet) then return true end
        
        if isHungry(selectedPet) then
            updateStatus("Feeding...")
            activateFurniture(Care.FindFood(), Care.FindFood(), "UseBlock", "food")
            return true
        end
        if isThirsty(selectedPet) then
            updateStatus("Drinking...")
            activateFurniture(Care.FindDrink(), Care.FindDrink(), "UseBlock", "drink")
            return true
        end
        if isToilet(selectedPet) then
            updateStatus("Toilet...")
            activateFurniture(Care.FindToilet(), Care.FindToilet(), "Seat1", "toilet")
            return true
        end
        if isDirty(selectedPet) then
            updateStatus("Shower...")
            activateFurniture(Care.FindShower(), Care.FindShower(), "UseBlock", "shower")
            return true
        end
        if isSleepy(selectedPet) then
            updateStatus("Sleep...")
            activateFurniture(Sleep.FindBed(), Sleep.FindBed(), "Seat1", "bed")
            return true
        end
        return true
    end

    local autofarmLoop
    local function setAutofarm(enabled)
        autofarmEnabled = enabled
        if enabled then
            updateStatus("Autofarm enabled")
            if not autofarmLoop then
                autofarmLoop = task.spawn(function()
                    while autofarmEnabled do
                        if selectedPet then pcall(runAutofarmOnce) else updateStatus("No pet selected") end
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

    --// BUTTONS
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
        selectedPet = nil updateStatus("Cleared")
    end})

    Tab:CreateButton({Name = "🍼 Hold", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        pcall(function() HoldBaby:FireServer(selectedPet) end)
        updateStatus("Holding " .. selectedPet.Name)
    end})

    Tab:CreateButton({Name = "⬇️ Drop", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        pcall(function() EjectBaby:FireServer(selectedPet) end)
        updateStatus("Dropped " .. selectedPet.Name)
    end})

    Tab:CreateButton({Name = "🛏️ Sleep", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        local id, obj = Sleep.FindBed()
        if id then activateFurniture(id, obj, "Seat1", "sleep") end
        updateStatus(id and "Sleeping" or "No bed")
    end})

    Tab:CreateButton({Name = "🍎 Feed", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        local id, obj = Care.FindFood()
        if id then activateFurniture(id, obj, "UseBlock", "food") end
        updateStatus(id and "Eating" or "No food")
    end})

    Tab:CreateButton({Name = "🥤 Drink", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        local id, obj = Care.FindDrink()
        if id then activateFurniture(id, obj, "UseBlock", "drink") end
        updateStatus(id and "Drinking" or "No drink")
    end})

    Tab:CreateButton({Name = "🚿 Shower", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        local id, obj = Care.FindShower()
        if id then activateFurniture(id, obj, "UseBlock", "shower") end
        updateStatus(id and "Showering" or "No shower")
    end})

    Tab:CreateButton({Name = "🚽 Toilet", Callback = function()
        if not selectedPet then updateStatus("No pet") return end
        local id, obj = Care.FindToilet()
        if id then activateFurniture(id, obj, "Seat1", "toilet") end
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
    print("Ailment UI loaded.")
end

return UI