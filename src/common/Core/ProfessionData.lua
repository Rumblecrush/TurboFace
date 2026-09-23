local _, ns = ...

-- Shared Classic Era profession metadata. Trainer and the skill tracker are
-- sibling consumers; neither subsystem owns the profession identity map.
-- Build lazily so disabling both consumers costs no profession spell lookups.
local PD = {}
ns.ProfessionData = PD

-- These IDs are useful stable metadata/icon sources, but some are higher-rank
-- profession spells. Keep the Apprentice/base IDs as a second source so the
-- identity map never depends on which rank name a client returns for the first
-- table.
local PROFESSION_SPELLS = {
    Alchemy = 3101,
    Blacksmithing = 9785,
    Cooking = 18260,
    Enchanting = 7413,
    Engineering = 4036,
    ["First Aid"] = 7924,
    Fishing = 7620,
    Herbalism = 13614,
    Leatherworking = 10662,
    Mining = 2575,
    Skinning = 10768,
    Tailoring = 3910,
}

local PROFESSION_STARTER_SPELLS = {
    Alchemy = 2259,
    Blacksmithing = 2018,
    Cooking = 2550,
    Enchanting = 7411,
    Engineering = 4036,
    ["First Aid"] = 3273,
    Fishing = 7620,
    Herbalism = 2366,
    Leatherworking = 2108,
    Mining = 2575,
    Skinning = 8613,
    Tailoring = 3908,
}

local SECONDARY_KEYS = { Cooking = true, ["First Aid"] = true, Fishing = true }
local nameToKey, lowerNameToKey, keyToName, keyToIcon, skillLines = {}, {}, {}, {}, {}
local built = false

local function AddAlias(key, name)
    if type(name) ~= "string" or name == "" then return end
    nameToKey[name] = key
    lowerNameToKey[name:lower()] = key
    skillLines[name] = true
end

local function EnsureBuilt()
    if built then return end
    built = true

    local getInfo = C_Spell and C_Spell.GetSpellInfo
    for key, spellID in pairs(PROFESSION_SPELLS) do
        -- English-key fallback is intentional. Localized clients use the spell
        -- aliases below; enUS remains correct even if one spell lookup is late
        -- or a particular rank returns an unexpected name.
        AddAlias(key, key)

        local info = getInfo and getInfo(spellID) or nil
        local starterID = PROFESSION_STARTER_SPELLS[key]
        local starterInfo = getInfo and starterID and getInfo(starterID) or nil

        if info and info.name then AddAlias(key, info.name) end
        if starterInfo and starterInfo.name then AddAlias(key, starterInfo.name) end

        -- Prefer the base/Apprentice spell for the user-facing profession name.
        keyToName[key] = (starterInfo and starterInfo.name) or (info and info.name) or key
        keyToIcon[key] = (starterInfo and (starterInfo.iconID or starterInfo.originalIconID))
            or (info and (info.iconID or info.originalIconID))
    end
end

function PD:GetKey(name)
    EnsureBuilt()
    if type(name) ~= "string" or name == "" then return nil end
    return nameToKey[name] or lowerNameToKey[name:lower()]
end
function PD:GetDisplayName(key) EnsureBuilt(); return key and keyToName[key] or nil end
function PD:GetKeyMap() EnsureBuilt(); return keyToName end
function PD:GetIcon(key) EnsureBuilt(); return key and keyToIcon[key] or nil end
function PD:IsSecondary(key) return key ~= nil and SECONDARY_KEYS[key] == true end
function PD:IsProfessionSkillLine(name) EnsureBuilt(); return name ~= nil and (skillLines[name] == true or lowerNameToKey[type(name) == "string" and name:lower() or ""] ~= nil) end
