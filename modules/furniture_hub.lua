--// Pulls care furniture near the player and keeps it following (no player TP)

local FurnitureHub = {}

local RunService = game:GetService("RunService")

local STATION_CONFIG = {
    food = {
        find = "FindFood",
        partName = "UseBlock",
        offset = CFrame.new(-4, 0.5, -4),
    },
    drink = {
        find = "FindDrink",
        partName = "UseBlock",
        offset = CFrame.new(4, 0.5, -4),
    },
    toilet = {
        find = "FindToilet",
        partName = "Seat1",
        offset = CFrame.new(-4, 0, 4),
    },
    shower = {
        find = "FindShower",
        partName = "UseBlock",
        offset = CFrame.new(4, 0, 4),
    },
    bed = {
        find = "FindBed",
        partName = "Seat1",
        offset = CFrame.new(0, 0.5, -5),
        module = "sleep",
    },
}

local stations = {}
local followConn = nil

local function getFurnitureModel(fromInst)
    if not fromInst then
        return nil
    end
    local model = fromInst
    while model and not model:IsA("Model") do
        model = model.Parent
    end
    if model and model:IsA("Model") then
        return model
    end
    return fromInst
end

local function getActivatePart(model, partName)
    if not model then
        return nil
    end
    local named = model:FindFirstChild(partName, true)
    if named and named:IsA("BasePart") then
        return named
    end
    if model:IsA("BasePart") then
        return model
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function prepModel(model)
    if not model then
        return
    end
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored = false
            desc.CanCollide = false
        end
    end
    local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if primary and not model.PrimaryPart then
        pcall(function()
            model.PrimaryPart = primary
        end)
    end
end

local function placeStation(station, hrp)
    if not station or not station.model or not hrp then
        return
    end
    prepModel(station.model)
    local targetCF = hrp.CFrame * station.offset
    pcall(function()
        if station.model:IsA("Model") and station.model.PrimaryPart then
            station.model:SetPrimaryPartCFrame(targetCF)
        else
            local part = station.activatePart
            if part then
                part.CFrame = targetCF
            end
        end
    end)
    station.activatePart = getActivatePart(station.model, station.partName) or station.activatePart
end

local function updateFollow(player)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end
    for _, station in pairs(stations) do
        placeStation(station, hrp)
    end
end

function FurnitureHub.cacheAll(Care, Sleep)
    stations = {}
    local findBed = Sleep and Sleep.FindBed

    for key, cfg in pairs(STATION_CONFIG) do
        local finder = cfg.module == "sleep" and findBed or (Care and Care[cfg.find])
        if finder then
            local id, target = finder()
            if id and target then
                local model = getFurnitureModel(target)
                stations[key] = {
                    id = id,
                    model = model,
                    activatePart = getActivatePart(model, cfg.partName) or target,
                    partName = cfg.partName,
                    offset = cfg.offset,
                }
            end
        end
    end
    return stations
end

function FurnitureHub.startFollow(player)
    if followConn then
        return
    end
    followConn = RunService.Heartbeat:Connect(function()
        updateFollow(player)
    end)
end

function FurnitureHub.stopFollow()
    if followConn then
        followConn:Disconnect()
        followConn = nil
    end
end

function FurnitureHub.refresh(player)
    updateFollow(player)
end

function FurnitureHub.use(needType, player, pet, ActivateFurniture, Care, Sleep)
    if not pet or not ActivateFurniture then
        return false
    end

    local station = stations[needType]
    if not station then
        FurnitureHub.cacheAll(Care, Sleep)
        station = stations[needType]
    end
    if not station or not station.activatePart then
        return false
    end

    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        placeStation(station, hrp)
    end

    local cf = station.activatePart.CFrame
    return pcall(function()
        ActivateFurniture:InvokeServer(
            player,
            station.id,
            station.partName,
            {cframe = cf},
            pet
        )
    end)
end

return FurnitureHub
