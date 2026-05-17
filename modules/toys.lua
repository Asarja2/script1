--// Toy inventory (equip_manager) + equip / play / throw / walk

local Toys = {}

local toyList = {}

local PLAY_KINDS = {
    squeaky_bone_default = true,
    play = true,
}

local function kindOf(entry)
    if type(entry) ~= "table" then
        return ""
    end
    return tostring(entry.kind or entry.id or ""):lower()
end

local function getFiresignal()
    if typeof(firesignal) == "function" then
        return firesignal
    end
    local g = getgenv and getgenv() or _G
    if g and typeof(g.firesignal) == "function" then
        return g.firesignal
    end
    if syn and typeof(syn.fire_signal) == "function" then
        return syn.fire_signal
    end
    return nil
end

local function getNilInstances()
    if typeof(getnilinstances) == "function" then
        return getnilinstances
    end
    local g = getgenv and getgenv() or _G
    if g and typeof(g.getnilinstances) == "function" then
        return g.getnilinstances
    end
    return nil
end

function Toys.parseEquipManager(data)
    toyList = {}
    if type(data) ~= "table" or type(data.toys) ~= "table" then
        return
    end
    for _, toy in pairs(data.toys) do
        if type(toy) == "table" and toy.unique then
            table.insert(toyList, toy)
        end
    end
end

function Toys.getToys()
    return toyList
end

-- Backpack / nil tools when equip_manager has not synced yet
function Toys.scanInventory(player)
    local found = {}
    local seen = {}
    local function add(entry)
        local uid = entry and entry.unique
        if uid and not seen[uid] then
            seen[uid] = true
            table.insert(found, entry)
        end
    end

    local function scanContainer(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                local uid = child:GetAttribute("unique")
                    or child:GetAttribute("UniqueId")
                    or child:GetAttribute("item_unique")
                if uid then
                    local name = child.Name:lower()
                    add({
                        unique = tostring(uid),
                        kind = name,
                        id = name,
                        category = "toys",
                    })
                end
            end
        end
    end

    if player then
        scanContainer(player:FindFirstChildOfClass("Backpack"))
        if player.Character then
            scanContainer(player.Character)
        end
    end

    local nilFn = getNilInstances()
    if nilFn then
        for _, inst in ipairs(nilFn()) do
            if inst:IsA("Tool") then
                local uid = inst:GetAttribute("unique") or inst:GetAttribute("UniqueId")
                if uid then
                    local name = inst.Name:lower()
                    add({
                        unique = tostring(uid),
                        kind = name,
                        id = name,
                        category = "toys",
                    })
                end
            end
        end
    end

    if #found > 0 then
        toyList = found
    end
    return found
end

function Toys.ensureInventory(player)
    if #toyList > 0 then
        return true
    end
    Toys.scanInventory(player)
    return #toyList > 0
end

function Toys.findToyByKind(wantedKind)
    wantedKind = tostring(wantedKind or ""):lower()
    if wantedKind == "" then
        return nil, nil
    end
    for _, toy in ipairs(toyList) do
        if kindOf(toy) == wantedKind then
            return tostring(toy.unique), toy
        end
    end
    return nil, nil
end

function Toys.findPlayToy()
    for _, toy in ipairs(toyList) do
        local k = kindOf(toy)
        if PLAY_KINDS[k] then
            return tostring(toy.unique), toy
        end
    end
    for _, toy in ipairs(toyList) do
        local k = kindOf(toy)
        if k:find("squeaky", 1, true) then
            return tostring(toy.unique), toy
        end
    end
    for _, toy in ipairs(toyList) do
        local k = kindOf(toy)
        if k:find("bone", 1, true) or k:find("toy", 1, true) then
            return tostring(toy.unique), toy
        end
    end
    return nil, nil
end

function Toys.findThrowableToy()
    for _, toy in ipairs(toyList) do
        local k = kindOf(toy)
        if k:find("ball", 1, true)
            or k:find("frisbee", 1, true)
            or k:find("throw", 1, true)
            or k:find("bone", 1, true)
            or k:find("squeaky", 1, true)
            or k:find("toy", 1, true) then
            return tostring(toy.unique), toy
        end
    end
    if #toyList > 0 then
        return tostring(toyList[1].unique), toyList[1]
    end
    return nil, nil
end

function Toys.equip(Remotes, uniqueId)
    return pcall(function()
        Remotes.ToolEquip:InvokeServer(uniqueId, {
            use_sound_delay = true,
            equip_as_last = false,
        })
    end)
end

function Toys.unequip(Remotes, uniqueId, fromThrow)
    return pcall(function()
        if fromThrow then
            Remotes.ToolUnequip:InvokeServer(uniqueId, {from_throw_toy = true})
        else
            Remotes.ToolUnequip:InvokeServer(uniqueId, nil)
        end
    end)
end

function Toys.useStart(Remotes, uniqueId)
    return pcall(function()
        Remotes.ServerUseTool:InvokeServer(uniqueId, "START")
    end)
end

function Toys.useEnd(Remotes, uniqueId)
    return pcall(function()
        Remotes.ServerUseTool:InvokeServer(uniqueId, "END", nil)
    end)
end

function Toys.throwToy(Remotes, uniqueId)
    return pcall(function()
        Remotes.CreatePetObject:InvokeServer("__Enum_PetObjectCreatorType_1", {
            reaction_name = "ThrowToyReaction",
            unique_id = uniqueId,
        })
    end)
end

-- Cobalt play flow: equip → START → hold until need clears → END → unequip
function Toys.playUntilDone(Remotes, uniqueId, stillNeedsFn)
    if not uniqueId then
        return false, "no toy"
    end
    Toys.equip(Remotes, uniqueId)
    task.wait(0.35)
    Toys.useStart(Remotes, uniqueId)
    local timeout = os.clock() + 50
    while stillNeedsFn() and os.clock() < timeout do
        task.wait(0.45)
    end
    Toys.useEnd(Remotes, uniqueId)
    task.wait(0.2)
    Toys.unequip(Remotes, uniqueId, false)
    return true
end

-- Cobalt throw flow: equip → START → throw reaction → unequip (throw) → unequip
function Toys.throwOnce(Remotes, uniqueId)
    Toys.equip(Remotes, uniqueId)
    task.wait(0.3)
    Toys.useStart(Remotes, uniqueId)
    task.wait(0.15)
    Toys.throwToy(Remotes, uniqueId)
    task.wait(0.8)
    Toys.useEnd(Remotes, uniqueId)
    task.wait(0.2)
    Toys.unequip(Remotes, uniqueId, true)
    task.wait(0.15)
    Toys.unequip(Remotes, uniqueId, nil)
end

function Toys.throwUntilDone(Remotes, uniqueId, stillNeedsFn)
    if not uniqueId then
        return false, "no toy"
    end
    local timeout = os.clock() + 60
    while stillNeedsFn() and os.clock() < timeout do
        pcall(function()
            Toys.throwOnce(Remotes, uniqueId)
        end)
        task.wait(1.1)
    end
    return true
end

local function pressKey(keyCode, down)
    local ok = pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendKeyEvent(down, keyCode, false, game)
    end)
    return ok
end

local function walkStep(hum, root, seconds)
    if hum and root then
        local offset = Vector3.new(math.random(-18, 18), 0, math.random(-18, 18))
        pcall(function()
            hum:MoveTo(root.Position + offset)
        end)
    end
    local keys = {
        Enum.KeyCode.W,
        Enum.KeyCode.A,
        Enum.KeyCode.S,
        Enum.KeyCode.D,
    }
    local key = keys[math.random(1, #keys)]
    pressKey(key, true)
    task.wait(seconds or 1.8)
    pressKey(key, false)
end

-- Hold pet and walk (MoveTo + WASD fallback) until walk ailment clears
function Toys.walkWithPet(player, HoldBaby, pet, stillNeedsFn)
    if not pet then
        return false
    end
    pcall(function()
        HoldBaby:FireServer(pet)
    end)
    task.wait(0.45)

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then
        return false
    end

    local timeout = os.clock() + 70
    while stillNeedsFn() and os.clock() < timeout do
        walkStep(hum, root, 2)
        pcall(function()
            HoldBaby:FireServer(pet)
        end)
        task.wait(0.35)
    end
    return true
end

return Toys
