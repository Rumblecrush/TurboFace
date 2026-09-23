local _, ns = ...

local LSM = LibStub("LibSharedMedia-3.0")

-- Shared banker artwork used by the nameplate Job Icon and Inventory's Bank
-- item-state overlay. Core/Client.lua owns the client-specific visual choice so
-- both consumers stay on one common path without hard-coding client branches.
ns.BANK_ICON_TEXTURE = ns.Client and ns.Client:GetAsset("bankIconTexture",
    "Interface\\AddOns\\TurboFace\\Textures\\BankIcon.tga")

-- Register TurboFace bundled textures with LSM
for _, texEntry in ipairs(ns.Textures) do
    LSM:Register("statusbar", texEntry.name, texEntry.path)
end

-- Register TurboFace border textures with LSM. LSM ships no default entries
-- for the "border" media type, so without this the list would be empty until
-- some other addon happened to register one.
for _, borderEntry in ipairs(ns.Borders) do
    LSM:Register("border", borderEntry.name, borderEntry.path)
end

-- Get list of all available borders from LSM (ours plus any other addon's)
function ns.GetLSMBorders()
    local list = LSM:List("border")
    local options = {}
    for i, name in ipairs(list) do
        options[i] = { name = name, value = name }
    end
    return options
end

-- Typography deliberately does not use LibSharedMedia. This module owns only
-- shareable statusbar/border media; font choices and resolution live in Config.

-- Get list of all available statusbar textures from LSM (ours plus any other
-- addon's registered media).
function ns.GetLSMTextures()
    local list = LSM:List("statusbar")
    local options = {}
    for i, name in ipairs(list) do
        options[i] = { name = name, value = name }
    end
    return options
end

function ns.GetTexture(name)
    if type(name) ~= "string" or name == "" then name = "Blizzard" end
    return LSM:Fetch("statusbar", name, true) or "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Retained public name used by unit-frame and Druid power-bar consumers.
ns.ResolveStatusBarTexture = ns.GetTexture

-- Store LSM reference for addon use
ns.LSM = LSM
