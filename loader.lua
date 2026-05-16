local BASE = "https://raw.githubusercontent.com/AsarjaStuff/Script/main/modules/"

local function load(name)
    print("loading", name)

    local src = game:HttpGet(BASE..name..".lua")
    local fn = loadstring(src)

    if not fn then
        warn("loadstring failed:", name)
        return nil
    end

    local ok, result = pcall(fn)

    if not ok then
        warn("module crash:", name, result)
        return nil
    end

    return result
end

local Remotes = load("remote")
local Pets = load("pets")
local Sleep = load("sleep")
local Care = load("care")
local UI = load("ui")

print("INIT UI")

if UI and UI.Init then
    UI.Init(Pets, Sleep, Care, Remotes)
else
    warn("UI missing Init")
end