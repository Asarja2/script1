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

local COLOR_INACTIVE = Color3.fromRGB(120, 125, 138)
local COLOR_ACTIVE = Color3.fromRGB(96, 165, 250)
local COLOR_HEADER = Color3.fromRGB(210, 214, 222)
local COLOR_DIM = Color3.fromRGB(155, 160, 172)
local COLOR_WARN = Color3.fromRGB(230, 175, 90)

local AILMENT_DISPLAY = {
    sleepy = "Sleepy",
    dirty = "Bath",
    hungry = "Hunger",
    thirsty = "Thirst",
    toilet = "Toilet",
    school = "School",
    pet_me = "Pet Me",
    play = "Play",
    walk = "Walk",
}

local function setLabel(label, text, color)
    if not label then
        return
    end
    pcall(function()
        label:Set(text, 0, color or COLOR_DIM, false)
    end)
end

local function formatNeed(name, active)
    local title = AILMENT_DISPLAY[name] or name
    if active then
        return "●  " .. title .. "  ·  active"
    end
    return "○  " .. title .. "  ·  clear"
end

function UI.Init(Pets, Sleep, Care, Remotes, PetState, Toys, FurnitureHub)
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
        getToyId = function()
            return ""
        end,
        parseEquipManager = function() end,
        playUntilDone = function() end,
        throwThreeTimes = function() end,
        walkWithPet = function() end,
    }

    FurnitureHub = FurnitureHub or {
        cacheAll = function() end,
        use = function()
            return false
        end,
        startFollow = function() end,
        stopFollow = function() end,
        refresh = function() end,
    }

    print("[ui] Init v8 — mobile stations, toy by name")

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

    local function useNeed(needType, pet)
        pet = pet or getPet()
        if not pet then
            return false
        end
        FurnitureHub.refresh(player)
        return FurnitureHub.use(needType, player, pet, ActivateFurniture, Care, Sleep)
    end

    local function getToyId()
        if Toys.getToyId then
            return Toys.getToyId(player) or ""
        end
        return ""
    end

    local function refreshToyLabel()
        local uid = getToyId()
        local name = (Toys.getToyDisplayName and Toys.getToyDisplayName()) or "squeaky"
        if uid ~= "" then
            setLabel(ToyIdLabel, "Toy: " .. name .. "  (resolved)", COLOR_DIM)
        else
            setLabel(ToyIdLabel, "Toy: " .. name .. "  (open toy backpack)", COLOR_WARN)
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
        LoadingSubtitle = "v8",
        Theme = "Default",
        ToggleUIKeybind = Enum.KeyCode.F2,
        ConfigurationSaving = {Enabled = true, FolderName = "PetController", FileName = "config"},
    })

    local ControlsTab = Window:CreateTab("Controls", 0)
    local NeedsTab = Window:CreateTab("Pet Needs", 0)

    ControlsTab:CreateSection("Status")
    local StatusLabel = ControlsTab:CreateLabel("Status: Ready")
    local ToyIdLabel = ControlsTab:CreateLabel("Toy: squeaky")

    local function setStatus(t)
        setLabel(StatusLabel, "Status: " .. t, COLOR_DIM)
    end

    refreshToyLabel()

    NeedsTab:CreateSection("Pet Status")
    local PetIdLabel = NeedsTab:CreateLabel("Selected: —")
    local AutofarmLabel = NeedsTab:CreateLabel("Queue: —")
    local ailLabels = {}
    for _, n in ipairs(track) do
        ailLabels[n] = NeedsTab:CreateLabel(formatNeed(n, false))
    end
    local RawLabel = NeedsTab:CreateLabel("Signals: waiting")

    local function refreshAilments()
        local pet = getPet()
        if not pet then
            setLabel(PetIdLabel, "Selected: none", COLOR_DIM)
            for _, n in ipairs(track) do
                setLabel(ailLabels[n], formatNeed(n, false), COLOR_INACTIVE)
            end
            setLabel(RawLabel, "Signals: —", COLOR_DIM)
            setLabel(AutofarmLabel, "Queue: —", COLOR_DIM)
            return
        end
        setLabel(
            PetIdLabel,
            "Selected: " .. pet.Name .. "  |  " .. tostring(PetState.findStateId(pet) or "?"),
            COLOR_HEADER
        )
        local list = {}
        for _, n in ipairs(track) do
            local on = PetState.hasNeed(pet, n)
            setLabel(ailLabels[n], formatNeed(n, on), on and COLOR_ACTIVE or COLOR_INACTIVE)
            if on then
                table.insert(list, AILMENT_DISPLAY[n] or n)
            end
        end
        local act = PetState.getActive(pet)
        if act then
            local k = {}
            for key in pairs(act) do
                table.insert(k, key)
            end
            table.sort(k)
            setLabel(RawLabel, "Signals: " .. table.concat(k, ", "), COLOR_DIM)
        else
            setLabel(RawLabel, "Signals: awaiting ailments_manager", COLOR_DIM)
        end
        setLabel(
            AutofarmLabel,
            "Queue: " .. (#list > 0 and table.concat(list, " → ") or "all clear"),
            #list > 0 and COLOR_WARN or COLOR_HEADER
        )
    end

    PetState.subscribe(refreshAilments)

    if DataChanged and DataChanged:IsA("RemoteEvent") then
        DataChanged.OnClientEvent:Connect(function(_, dtype, data)
            if dtype == "ailments_manager" then
                PetState.parseAilmentsManager(data)
            elseif dtype == "equip_manager" then
                if Toys.parseEquipManager then
                    Toys.parseEquipManager(data)
                end
                refreshToyLabel()
            end
        end)
    end

    local function doPlay(pet)
        local uid = getToyId()
        if uid == "" then
            setStatus("Toy not found — open toy backpack")
            return
        end
        if not stillPlay(pet) then
            setStatus("No play need detected")
            return
        end
        setStatus("Playing squeaky toy")
        Toys.playUntilDone(Remotes, uid, function()
            return stillPlay(pet)
        end)
        setStatus("Play finished")
    end

    local function doThrow(pet)
        local uid = getToyId()
        if uid == "" then
            setStatus("Toy not found — open toy backpack")
            return
        end
        if not stillPlay(pet) then
            setStatus("No play need detected")
            return
        end
        setStatus("Throwing toy (3x, 5s apart)")
        Toys.throwThreeTimes(Remotes, uid, function()
            return stillPlay(pet)
        end)
        setStatus("Throw finished")
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
            setStatus("Feeding (near you)")
            useNeed("food", pet)
            return
        end
        if PetState.isThirsty(pet) then
            setStatus("Drinking (near you)")
            useNeed("drink", pet)
            return
        end
        if PetState.isToilet(pet) then
            setStatus("Toilet (near you)")
            useNeed("toilet", pet)
            return
        end
        if PetState.isDirty(pet) then
            setStatus("Shower (near you)")
            useNeed("shower", pet)
            return
        end
        if PetState.isSleepy(pet) then
            setStatus("Sleep (near you)")
            useNeed("bed", pet)
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
                doThrow(pet)
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
            useNeed("food", p)
        end,
    })
    ControlsTab:CreateButton({
        Name = "Drink",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            useNeed("drink", p)
        end,
    })
    ControlsTab:CreateButton({
        Name = "Shower",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            useNeed("shower", p)
        end,
    })
    ControlsTab:CreateButton({
        Name = "Toilet",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            useNeed("toilet", p)
        end,
    })
    ControlsTab:CreateButton({
        Name = "Sleep",
        Callback = function()
            local p = getPet()
            if not p then
                return
            end
            useNeed("bed", p)
        end,
    })

    ControlsTab:CreateSection("Toys")
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
    ControlsTab:CreateSection("Autofarm")
    ControlsTab:CreateToggle({
        Name = "Autofarm",
        CurrentValue = false,
        Flag = "Autofarm",
        Callback = function(on)
            autofarmEnabled = on
            if on then
                FurnitureHub.cacheAll(Care, Sleep)
                FurnitureHub.startFollow(player)
                if not autofarmLoop then
                    autofarmLoop = task.spawn(function()
                        while autofarmEnabled do
                            pcall(autofarm)
                            task.wait(actionBusy and 2 or 4)
                        end
                        autofarmLoop = nil
                    end)
                end
                setStatus("Autofarm ON — stations follow you")
            else
                FurnitureHub.stopFollow()
                setStatus("Autofarm OFF")
            end
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

    FurnitureHub.cacheAll(Care, Sleep)
    refreshToyLabel()
    refreshAilments()
    Rayfield:LoadConfiguration()
    pcall(function()
        Rayfield:Notify({
            Title = "Loaded v8",
            Content = "Care items follow you on autofarm. Toy found by squeaky name.",
            Duration = 5,
        })
    end)
end

return UI
