--// Pet Controller UI — MUST work via loadstring (no require, no script.Parent)

local UI = {}

local Rayfield = nil
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if ok then
        Rayfield = lib
    else
        warn("[ui] Rayfield load failed:", lib)
    end
end

local COLOR_OFF = Color3.fromRGB(255, 80, 80)
local COLOR_ON = Color3.fromRGB(80, 255, 120)
local COLOR_MUTED = Color3.fromRGB(180, 180, 190)

local function setLabel(label, text, color)
    if not label then return end
    pcall(function() label:Set(text, 0, color or COLOR_MUTED, false) end)
    pcall(function() label:Set(text) end)
end

function UI.Init(Pets, Sleep, Care, Remotes, PetState)
    if not Rayfield then
        warn("[ui] No Rayfield")
        return
    end
    if not PetState then
        warn("[ui] No PetState — loader must load PetStates.lua first")
        return
    end
    if not Pets or not Sleep or not Care or not Remotes then
        warn("[ui] Missing Pets/Sleep/Care/Remotes module")
        return
    end

    print("[ui] Init v4 — ailments on Controls tab")

    local player = game:GetService("Players").LocalPlayer
    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local DataChanged = Remotes.DataChanged

    local selectedPetName = nil
    local PetDropdown = nil
    local autofarmEnabled = false
    local autofarmLoop = nil
    local track = PetState.TRACKED_AILMENTS

    local function getPet()
        if not selectedPetName then return nil end
        local p = Pets.FindPetByName(selectedPetName)
        if p and p.Parent and p:IsDescendantOf(workspace) then return p end
        return nil
    end

    local function useFurniture(id, target, part, pet)
        pet = pet or getPet()
        if not pet or not id or not target then return false end
        local cf = target:IsA("BasePart") and target.CFrame or target.PrimaryPart and target.PrimaryPart.CFrame
        if not cf then
            local p = target:FindFirstChild(part) or target:FindFirstChildOfClass("BasePart")
            cf = p and p.CFrame
        end
        if not cf then return false end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = cf * CFrame.new(0, 0, -5) end
        return pcall(function()
            ActivateFurniture:InvokeServer(player, id, part, {cframe = cf}, pet)
        end)
    end

    local Window = Rayfield:CreateWindow({
        Name = "Pet Controller",
        Icon = 0,
        LoadingTitle = "Pet Controller",
        LoadingSubtitle = "v4",
        Theme = "Default",
        ToggleUIKeybind = Enum.KeyCode.F2,
        ConfigurationSaving = {Enabled = true, FolderName = "PetController", FileName = "config"},
    })

    local Tab = Window:CreateTab("Controls", 0)

    Tab:CreateSection("Status")
    local StatusLabel = Tab:CreateLabel("Status: Ready")
    local AutofarmLabel = Tab:CreateLabel("Needs: —")

    Tab:CreateSection("Pet Ailments (live)")
    local PetIdLabel = Tab:CreateLabel("Pet ID: —")
    local ailLabels = {}
    for _, n in ipairs(track) do
        ailLabels[n] = Tab:CreateLabel(n .. ": false")
    end
    local RawLabel = Tab:CreateLabel("Raw keys: waiting")

    local function refreshAilments()
        local pet = getPet()
        if not pet then
            setLabel(PetIdLabel, "Pet ID: none", COLOR_MUTED)
            for _, n in ipairs(track) do setLabel(ailLabels[n], n .. ": false", COLOR_OFF) end
            setLabel(RawLabel, "Raw keys: —", COLOR_MUTED)
            setLabel(AutofarmLabel, "Needs: —", COLOR_MUTED)
            return
        end
        setLabel(PetIdLabel, "Pet: " .. pet.Name .. " | " .. tostring(PetState.findStateId(pet) or "?"), COLOR_MUTED)
        local list = {}
        for _, n in ipairs(track) do
            local on = PetState.hasNeed(pet, n)
            setLabel(ailLabels[n], n .. ": " .. tostring(on), on and COLOR_ON or COLOR_OFF)
            if on then table.insert(list, n) end
        end
        local act = PetState.getActive(pet)
        if act then
            local k = {}
            for key in pairs(act) do table.insert(k, key) end
            table.sort(k)
            setLabel(RawLabel, "Raw keys: " .. table.concat(k, ", "), COLOR_MUTED)
        else
            setLabel(RawLabel, "Raw keys: no ailments_manager data yet", COLOR_MUTED)
        end
        setLabel(AutofarmLabel, "Needs: " .. (#list > 0 and table.concat(list, ", ") or "none"), COLOR_MUTED)
    end

    local function setStatus(t)
        setLabel(StatusLabel, "Status: " .. t, COLOR_MUTED)
    end

    PetState.subscribe(refreshAilments)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(_, dtype, data)
            if dtype == "ailments_manager" then
                PetState.parseAilmentsManager(data)
            end
        end)
    end

    local function autofarm()
        local pet = getPet()
        if not pet then return end
        refreshAilments()
        if PetState.isHungry(pet) then
            setStatus("Feeding")
            local a, b = Care.FindFood()
            if a and b then useFurniture(a, b, "UseBlock", pet) end
            return
        end
        if PetState.isThirsty(pet) then
            setStatus("Drinking")
            local a, b = Care.FindDrink()
            if a and b then useFurniture(a, b, "UseBlock", pet) end
            return
        end
        if PetState.isToilet(pet) then
            setStatus("Toilet")
            local a, b = Care.FindToilet()
            if a and b then useFurniture(a, b, "Seat1", pet) end
            return
        end
        if PetState.isDirty(pet) then
            setStatus("Shower")
            local a, b = Care.FindShower()
            if a and b then useFurniture(a, b, "UseBlock", pet) end
            return
        end
        if PetState.isSleepy(pet) then
            setStatus("Sleep")
            local a, b = Sleep.FindBed()
            if a and b then useFurniture(a, b, "Seat1", pet) end
            return
        end
        setStatus("Nothing needed")
    end

    Tab:CreateSection("Pet Selection")
    PetDropdown = Tab:CreateDropdown({
        Name = "Select Pet",
        Options = {"No pets available"},
        CurrentOption = {"No pets available"},
        MultipleOptions = false,
        Flag = "PetDropdown",
        Callback = function(o)
            selectedPetName = (o[1] ~= "No pets available") and o[1] or nil
            refreshAilments()
        end,
    })

    Tab:CreateButton({Name = "Refresh Pets", Callback = function()
        local o = {}
        for _, p in ipairs(Pets.GetPets()) do table.insert(o, p.Name) end
        if #o > 0 then
            PetDropdown:Refresh(o)
            PetDropdown:Set({o[1]})
            selectedPetName = o[1]
        end
        refreshAilments()
    end})

    Tab:CreateButton({Name = "Refresh Ailments", Callback = function()
        refreshAilments()
        local p = getPet()
        if p then PetState.debugPetNeeds(p, "manual") end
    end})

    Tab:CreateSection("Care")
    Tab:CreateButton({Name = "Hold", Callback = function() local p = getPet() if p then pcall(function() HoldBaby:FireServer(p) end) end end})
    Tab:CreateButton({Name = "Drop", Callback = function() local p = getPet() if p then pcall(function() EjectBaby:FireServer(p) end) end end})
    Tab:CreateButton({Name = "Feed", Callback = function() local p = getPet() if not p then return end local a,b=Care.FindFood() if a and b then useFurniture(a,b,"UseBlock",p) end end})
    Tab:CreateButton({Name = "Drink", Callback = function() local p = getPet() if not p then return end local a,b=Care.FindDrink() if a and b then useFurniture(a,b,"UseBlock",p) end end})
    Tab:CreateButton({Name = "Shower", Callback = function() local p = getPet() if not p then return end local a,b=Care.FindShower() if a and b then useFurniture(a,b,"UseBlock",p) end end})
    Tab:CreateButton({Name = "Toilet", Callback = function() local p = getPet() if not p then return end local a,b=Care.FindToilet() if a and b then useFurniture(a,b,"Seat1",p) end end})
    Tab:CreateButton({Name = "Sleep", Callback = function() local p = getPet() if not p then return end local a,b=Sleep.FindBed() if a and b then useFurniture(a,b,"Seat1",p) end end})

    Tab:CreateSection("Autofarm")
    Tab:CreateToggle({
        Name = "Autofarm",
        CurrentValue = false,
        Flag = "Autofarm",
        Callback = function(on)
            autofarmEnabled = on
            if on and not autofarmLoop then
                autofarmLoop = task.spawn(function()
                    while autofarmEnabled do
                        pcall(autofarm)
                        task.wait(4)
                    end
                    autofarmLoop = nil
                end)
            end
            setStatus(on and "Autofarm ON" or "OFF")
        end,
    })

    local pets = Pets.GetPets()
    if #pets > 0 then
        local o = {}
        for _, p in ipairs(pets) do table.insert(o, p.Name) end
        PetDropdown:Refresh(o)
        selectedPetName = o[1]
        PetDropdown:Set({o[1]})
    end

    refreshAilments()
    Rayfield:LoadConfiguration()
    pcall(function()
        Rayfield:Notify({Title = "Loaded v4", Content = "Scroll to Pet Ailments section", Duration = 5})
    end)
end

return UI
