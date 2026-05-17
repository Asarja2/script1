--// Pet Controller UI — loadstring-safe (no require)

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
    if not label then
        return
    end
    pcall(function()
        label:Set(text, 0, color or COLOR_MUTED, false)
    end)
    pcall(function()
        label:Set(text)
    end)
end

function UI.Init(Pets, Sleep, Care, Remotes, PetState, Toys)
    if not Rayfield then
        warn("[ui] No Rayfield")
        return
    end
    if not PetState then
        warn("[ui] No PetState")
        return
    end
    if not Pets or not Sleep or not Care or not Remotes then
        warn("[ui] Missing modules")
        return
    end

    Toys = Toys or {
        parseEquipManager = function() end,
        ensureInventory = function() end,
        scanInventory = function() end,
        findPlayToy = function() end,
        findThrowableToy = function() end,
        findToyByKind = function() end,
        playUntilDone = function() end,
        throwUntilDone = function() end,
        walkWithPet = function() end,
        getToys = function()
            return {}
        end,
    }

    print("[ui] Init v6 — ailments on Pet Needs tab, kind-based toys")

    local player = game:GetService("Players").LocalPlayer
    local HoldBaby = Remotes.HoldBaby
    local EjectBaby = Remotes.EjectBaby
    local ActivateFurniture = Remotes.ActivateFurniture
    local DataChanged = Remotes.DataChanged

    local selectedPetName = nil
    local PetDropdown = nil
    local autofarmEnabled = false
    local autofarmLoop = nil
    local actionBusy = false
    local track = PetState.TRACKED_AILMENTS

    local function getPet()
        if not selectedPetName then
            return nil
        end
        local p = Pets.FindPetByName(selectedPetName)
        if p and p.Parent and p:IsDescendantOf(workspace) then
            return p
        end
        return nil
    end

    local function useFurniture(id, target, part, pet)
        pet = pet or getPet()
        if not pet or not id or not target then
            return false
        end
        local cf = target:IsA("BasePart") and target.CFrame or target.PrimaryPart and target.PrimaryPart.CFrame
        if not cf then
            local bp = target:FindFirstChild(part) or target:FindFirstChildOfClass("BasePart")
            cf = bp and bp.CFrame
        end
        if not cf then
            return false
        end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = cf * CFrame.new(0, 0, -5)
        end
        return pcall(function()
            ActivateFurniture:InvokeServer(player, id, part, {cframe = cf}, pet)
        end)
    end

    local function ensureToys()
        if Toys.ensureInventory then
            Toys.ensureInventory(player)
        end
    end

    local function stillPlay(pet)
        if PetState.needsPlayToy then
            local needs = PetState.needsPlayToy(pet)
            return needs == true
        end
        return PetState.isPlay(pet) or PetState.isPetMe(pet)
    end

    local function stillWalk(pet)
        return PetState.isWalk(pet)
    end

    local function stillThrow(pet)
        return stillPlay(pet) or PetState.isPetMe(pet)
    end

    local function runAction(fn)
        if actionBusy then
            return
        end
        actionBusy = true
        task.spawn(function()
            pcall(fn)
            actionBusy = false
        end)
    end

    local Window = Rayfield:CreateWindow({
        Name = "Pet Controller",
        Icon = 0,
        LoadingTitle = "Pet Controller",
        LoadingSubtitle = "v6",
        Theme = "Default",
        ToggleUIKeybind = Enum.KeyCode.F2,
        ConfigurationSaving = {Enabled = true, FolderName = "PetController", FileName = "config"},
    })

    local ControlsTab = Window:CreateTab("Controls", 0)
    local NeedsTab = Window:CreateTab("Pet Needs", 0)

    ControlsTab:CreateSection("Status")
    local StatusLabel = ControlsTab:CreateLabel("Status: Ready")
    local ToyCountLabel = ControlsTab:CreateLabel("Toys in inventory: 0")

    local function setStatus(t)
        setLabel(StatusLabel, "Status: " .. t, COLOR_MUTED)
    end

    local function refreshToyCount()
        local n = #(Toys.getToys and Toys.getToys() or {})
        setLabel(ToyCountLabel, "Toys in inventory: " .. n, COLOR_MUTED)
    end

    NeedsTab:CreateSection("Live ailments")
    local PetIdLabel = NeedsTab:CreateLabel("Pet ID: —")
    local AutofarmLabel = NeedsTab:CreateLabel("Active needs: —")
    local ailLabels = {}
    for _, n in ipairs(track) do
        ailLabels[n] = NeedsTab:CreateLabel(n .. ": false")
    end
    local RawLabel = NeedsTab:CreateLabel("Raw keys: waiting")

    local function refreshAilments()
        local pet = getPet()
        if not pet then
            setLabel(PetIdLabel, "Pet ID: none", COLOR_MUTED)
            for _, n in ipairs(track) do
                setLabel(ailLabels[n], n .. ": false", COLOR_OFF)
            end
            setLabel(RawLabel, "Raw keys: —", COLOR_MUTED)
            setLabel(AutofarmLabel, "Active needs: —", COLOR_MUTED)
            return
        end
        setLabel(
            PetIdLabel,
            "Pet: " .. pet.Name .. " | " .. tostring(PetState.findStateId(pet) or "?"),
            COLOR_MUTED
        )
        local list = {}
        for _, n in ipairs(track) do
            local on = PetState.hasNeed(pet, n)
            setLabel(ailLabels[n], n .. ": " .. tostring(on), on and COLOR_ON or COLOR_OFF)
            if on then
                table.insert(list, n)
            end
        end
        local act = PetState.getActive(pet)
        if act then
            local k = {}
            for key in pairs(act) do
                table.insert(k, key)
            end
            table.sort(k)
            setLabel(RawLabel, "Raw keys: " .. table.concat(k, ", "), COLOR_MUTED)
        else
            setLabel(RawLabel, "Raw keys: no ailments_manager yet", COLOR_MUTED)
        end
        setLabel(
            AutofarmLabel,
            "Active needs: " .. (#list > 0 and table.concat(list, ", ") or "none"),
            COLOR_MUTED
        )
    end

    PetState.subscribe(refreshAilments)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(_, dtype, data)
            if dtype == "ailments_manager" then
                PetState.parseAilmentsManager(data)
            elseif dtype == "equip_manager" then
                Toys.parseEquipManager(data)
                refreshToyCount()
            end
        end)
    end

    local function doPlay(pet)
        ensureToys()
        local uid, toy
        local _, playKind = false, nil
        if PetState.needsPlayToy then
            _, playKind = PetState.needsPlayToy(pet)
        end
        if playKind and Toys.findToyByKind then
            uid, toy = Toys.findToyByKind(playKind)
        end
        if not uid then
            uid, toy = Toys.findPlayToy()
        end
        if not uid then
            setStatus("No play toy — open toy backpack or wait for equip_manager")
            return
        end
        setStatus("Playing (" .. tostring(toy and (toy.kind or toy.id) or uid) .. ")")
        Toys.playUntilDone(Remotes, uid, function()
            return stillPlay(pet)
        end)
        setStatus("Play done")
    end

    local function doThrow(pet)
        ensureToys()
        local uid, toy = Toys.findThrowableToy()
        if not uid then
            setStatus("No throwable toy in inventory")
            return
        end
        setStatus("Throwing (" .. tostring(toy and (toy.kind or toy.id) or uid) .. ")")
        Toys.throwUntilDone(Remotes, uid, function()
            return stillThrow(pet)
        end)
        setStatus("Throw done")
    end

    local function doWalk(pet)
        setStatus("Walking pet")
        Toys.walkWithPet(player, HoldBaby, pet, function()
            return stillWalk(pet)
        end)
        setStatus("Walk done")
    end

    local function autofarm()
        if actionBusy then
            return
        end
        local pet = getPet()
        if not pet then
            return
        end
        refreshAilments()

        if PetState.isHungry(pet) then
            setStatus("Feeding")
            local a, b = Care.FindFood()
            if a and b then
                useFurniture(a, b, "UseBlock", pet)
            end
            return
        end
        if PetState.isThirsty(pet) then
            setStatus("Drinking")
            local a, b = Care.FindDrink()
            if a and b then
                useFurniture(a, b, "UseBlock", pet)
            end
            return
        end
        if PetState.isToilet(pet) then
            setStatus("Toilet")
            local a, b = Care.FindToilet()
            if a and b then
                useFurniture(a, b, "Seat1", pet)
            end
            return
        end
        if PetState.isDirty(pet) then
            setStatus("Shower")
            local a, b = Care.FindShower()
            if a and b then
                useFurniture(a, b, "UseBlock", pet)
            end
            return
        end
        if PetState.isSleepy(pet) then
            setStatus("Sleep")
            local a, b = Sleep.FindBed()
            if a and b then
                useFurniture(a, b, "Seat1", pet)
            end
            return
        end
        if stillWalk(pet) then
            runAction(function()
                doWalk(pet)
            end)
            return
        end
        if stillPlay(pet) then
            runAction(function()
                doPlay(pet)
            end)
            return
        end
        setStatus("Nothing needed")
    end

    ControlsTab:CreateSection("Pet Selection")
    PetDropdown = ControlsTab:CreateDropdown({
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

    ControlsTab:CreateButton({
        Name = "Refresh Pets",
        Callback = function()
            local o = {}
            for _, p in ipairs(Pets.GetPets()) do
                table.insert(o, p.Name)
            end
            if #o > 0 then
                PetDropdown:Refresh(o)
                PetDropdown:Set({o[1]})
                selectedPetName = o[1]
            end
            refreshAilments()
        end,
    })

    NeedsTab:CreateButton({
        Name = "Refresh Ailments",
        Callback = function()
            refreshAilments()
            local p = getPet()
            if p then
                PetState.debugPetNeeds(p, "manual")
            end
        end,
    })

    ControlsTab:CreateSection("Care")
    ControlsTab:CreateButton({
        Name = "Hold",
        Callback = function()
            local p = getPet()
            if p then
                pcall(function()
                    HoldBaby:FireServer(p)
                end)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Drop",
        Callback = function()
            local p = getPet()
            if p then
                pcall(function()
                    EjectBaby:FireServer(p)
                end)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Feed",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            local a, b = Care.FindFood()
            if a and b then
                useFurniture(a, b, "UseBlock", p)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Drink",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            local a, b = Care.FindDrink()
            if a and b then
                useFurniture(a, b, "UseBlock", p)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Shower",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            local a, b = Care.FindShower()
            if a and b then
                useFurniture(a, b, "UseBlock", p)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Toilet",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            local a, b = Care.FindToilet()
            if a and b then
                useFurniture(a, b, "Seat1", p)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Sleep",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            local a, b = Sleep.FindBed()
            if a and b then
                useFurniture(a, b, "Seat1", p)
            end
        end,
    })

    ControlsTab:CreateSection("Toys")
    ControlsTab:CreateButton({
        Name = "Sync Toys (scan backpack)",
        Callback = function()
            if Toys.scanInventory then
                Toys.scanInventory(player)
            end
            refreshToyCount()
            setStatus(#(Toys.getToys and Toys.getToys() or {}) > 0 and "Toys synced" or "No toys found")
        end,
    })
    ControlsTab:CreateButton({
        Name = "Play Toy",
        Callback = function()
            local p = getPet()
            if p then
                runAction(function()
                    doPlay(p)
                end)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Throw Toy",
        Callback = function()
            local p = getPet()
            if p then
                runAction(function()
                    doThrow(p)
                end)
            end
        end,
    })
    ControlsTab:CreateButton({
        Name = "Walk With Pet",
        Callback = function()
            local p = getPet()
            if p then
                runAction(function()
                    doWalk(p)
                end)
            end
        end,
    })

    ControlsTab:CreateSection("Autofarm")
    ControlsTab:CreateToggle({
        Name = "Autofarm",
        CurrentValue = false,
        Flag = "Autofarm",
        Callback = function(on)
            autofarmEnabled = on
            if on and not autofarmLoop then
                autofarmLoop = task.spawn(function()
                    while autofarmEnabled do
                        pcall(autofarm)
                        task.wait(actionBusy and 2 or 4)
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
        for _, p in ipairs(pets) do
            table.insert(o, p.Name)
        end
        PetDropdown:Refresh(o)
        selectedPetName = o[1]
        PetDropdown:Set({o[1]})
    end

    ensureToys()
    refreshAilments()
    refreshToyCount()
    Rayfield:LoadConfiguration()
    pcall(function()
        Rayfield:Notify({
            Title = "Loaded v6",
            Content = "Ailments: Pet Needs tab. Autofarm uses play/walk by kind. Throw Toy until need clears.",
            Duration = 5,
        })
    end)
end

return UI
