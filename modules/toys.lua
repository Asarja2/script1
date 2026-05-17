--// Fixed toy ID + equip / play / throw / walk

local Toys = {}

-- Your squeaky bone (change here if the unique id changes)
Toys.TOY_ID = "2_1a3aae15c72c4430bd9824c5e6def466"

local THROW_COUNT = 3
local THROW_COOLDOWN = 5

function Toys.getToyId()
    return Toys.TOY_ID
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

-- Cobalt throw: equip → ThrowToyReaction → unequip (from_throw_toy)
function Toys.throwOnce(Remotes, uniqueId)
    uniqueId = uniqueId or Toys.TOY_ID
    Toys.equip(Remotes, uniqueId)
    task.wait(0.35)
    Toys.throwToy(Remotes, uniqueId)
    task.wait(0.4)
    Toys.unequip(Remotes, uniqueId, true)
end

-- 3 throws, 5 seconds between each (when play need is active)
function Toys.throwThreeTimes(Remotes, uniqueId, stillNeedsFn)
    uniqueId = uniqueId or Toys.TOY_ID
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

-- Cobalt play: equip → START → hold until need clears → END → unequip
function Toys.playUntilDone(Remotes, uniqueId, stillNeedsFn)
    uniqueId = uniqueId or Toys.TOY_ID
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

-- Short taps so movement steers around walls instead of MoveTo into them
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
    -- Favor forward + strafe so we circle obstacles instead of ramming walls
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
