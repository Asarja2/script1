--// Toys by name (unique id from equip_manager / backpack / nil instances)

local Toys = {}

Toys.TOY_NAME_PATTERNS = {
    "squeaky",
    "squeaky_bone",
    "squeaky_bone_default",
    "SqueakyToyTool",
}

local cachedUniqueId = nil
local equipToys = {}

local THROW_COUNT = 3
local THROW_COOLDOWN = 5

local function lower(s)
    return tostring(s or ""):lower()
end

local function nameMatches(str)
    local text = lower(str)
    for _, pattern in ipairs(Toys.TOY_NAME_PATTERNS) do
        if text:find(lower(pattern), 1, true) then
            return true
        end
    end
    return false
end

local function toyEntryMatches(entry)
    if type(entry) ~= "table" then
        return false
    end
    if nameMatches(entry.kind) or nameMatches(entry.id) then
        return true
    end
    if entry.properties and nameMatches(entry.properties.kind) then
        return true
    end
    return false
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
    equipToys = {}
    if type(data) ~= "table" or type(data.toys) ~= "table" then
        return
    end
    for _, toy in pairs(data.toys) do
        if type(toy) == "table" and toy.unique then
            table.insert(equipToys, toy)
            if toyEntryMatches(toy) then
                cachedUniqueId = tostring(toy.unique)
            end
        end
    end
end

local function uidFromTool(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end
    if not nameMatches(tool.Name) then
        return nil
    end
    local uid = tool:GetAttribute("unique")
        or tool:GetAttribute("UniqueId")
        or tool:GetAttribute("item_unique")
    if uid then
        return tostring(uid)
    end
    return nil
end

local function scanContainers(player)
    if not player then
        return nil
    end
    local list = {}
    if player:FindFirstChildOfClass("Backpack") then
        table.insert(list, player.Backpack)
    end
    if player.Character then
        table.insert(list, player.Character)
    end
    for _, container in ipairs(list) do
        for _, child in ipairs(container:GetChildren()) do
            local uid = uidFromTool(child)
            if uid then
                cachedUniqueId = uid
                return uid
            end
        end
    end
    local nilFn = getNilInstances()
    if nilFn then
        for _, inst in ipairs(nilFn()) do
            local uid = uidFromTool(inst)
            if uid then
                cachedUniqueId = uid
                return uid
            end
        end
    end
    return nil
end

function Toys.findToyByName(player)
    if cachedUniqueId then
        return cachedUniqueId
    end
    for _, toy in ipairs(equipToys) do
        if toyEntryMatches(toy) and toy.unique then
            cachedUniqueId = tostring(toy.unique)
            return cachedUniqueId
        end
    end
    return scanContainers(player)
end

function Toys.getToyId(player)
    return Toys.findToyByName(player) or ""
end

function Toys.getToyDisplayName()
    return Toys.TOY_NAME_PATTERNS[1] or "squeaky"
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

function Toys.throwOnce(Remotes, uniqueId)
    Toys.equip(Remotes, uniqueId)
    task.wait(0.35)
    Toys.throwToy(Remotes, uniqueId)
    task.wait(0.4)
    Toys.unequip(Remotes, uniqueId, true)
end

function Toys.throwThreeTimes(Remotes, uniqueId, stillNeedsFn)
    for i = 1, THROW_COUNT do
        if stillNeedsFn and not stillNeedsFn() then
            break
        end
        pcall(function()
            Toys.throwOnce(Remotes, uniqueId)
        end)
        if i < THROW_COUNT then
            task.wait(THROW_COOLDOWN)
        end
    end
    return true
end

function Toys.playUntilDone(Remotes, uniqueId, stillNeedsFn)
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

local WALK_KEYS = {
    Enum.KeyCode.W,
    Enum.KeyCode.A,
    Enum.KeyCode.S,
    Enum.KeyCode.D,
}

local KEY_HOLD = 0.16
local KEY_GAP = 0.03
local BURST_COUNT = 8

local function pressKey(keyCode, down)
    pcall(function()
        game:GetService("VirtualInputManager"):SendKeyEvent(down, keyCode, false, game)
    end)
end

local function releaseAllKeys()
    for _, key in ipairs(WALK_KEYS) do
        pressKey(key, false)
    end
end

local function tapKey(keyCode)
    pressKey(keyCode, true)
    task.wait(KEY_HOLD)
    pressKey(keyCode, false)
    task.wait(KEY_GAP)
end

local function nextWalkKey()
    local roll = math.random(1, 10)
    if roll <= 5 then
        return Enum.KeyCode.W
    elseif roll <= 7 then
        return math.random(1, 2) == 1 and Enum.KeyCode.A or Enum.KeyCode.D
    elseif roll == 8 then
        return Enum.KeyCode.S
    end
    return WALK_KEYS[math.random(1, #WALK_KEYS)]
end

local function walkBurst()
    releaseAllKeys()
    for _ = 1, BURST_COUNT do
        tapKey(nextWalkKey())
    end
    releaseAllKeys()
end

function Toys.walkWithPet(player, HoldBaby, pet, stillNeedsFn)
    if not pet then
        return false
    end
    pcall(function()
        HoldBaby:FireServer(pet)
    end)
    task.wait(0.35)

    local char = player.Character
    if not char or not char:FindFirstChildOfClass("Humanoid") then
        return false
    end

    local timeout = os.clock() + 70
    while stillNeedsFn() and os.clock() < timeout do
        walkBurst()
        pcall(function()
            HoldBaby:FireServer(pet)
        end)
        task.wait(0.12)
    end

    releaseAllKeys()
    return true
end

return Toys
