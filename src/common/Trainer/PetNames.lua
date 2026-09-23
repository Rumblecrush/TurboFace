local _, ns = ...
local Trainer = ns.Trainer
local impId = 688
local voidwalkerId = 697
local succubusId = 712
local incubusId = 101822
local felhunterId = 691
local felguardId = 30146
local PET_SUMMON_SPELL_IDS = {impId, voidwalkerId, succubusId, incubusId, felhunterId, felguardId}
local function CommonAffixLength(a, b, fromEnd)
    local maxLen = math.min(#a, #b)
    local len = 0
    while len < maxLen do
        local posA = fromEnd and (#a - len) or (len + 1)
        local posB = fromEnd and (#b - len) or (len + 1)
        if a:sub(posA, posA) ~= b:sub(posB, posB) then break end
        len = len + 1
    end
    return len
end

local function GetMapLength(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function StripCommonAffixes(names)
    if GetMapLength(names) < 2 then return names end
    local prefixLen, suffixLen = nil, nil
    local firstElement = nil
    for i, v in pairs(names) do
        if firstElement == nil then
            firstElement = v
            prefixLen, suffixLen = #v, #v
        else
            prefixLen = math.min(prefixLen, CommonAffixLength(firstElement, v, false))
            suffixLen = math.min(suffixLen, CommonAffixLength(firstElement, v, true))
        end
    end

    local result = {}
    for i, name in pairs(names) do
        local suffixStart = math.max(prefixLen, #name - suffixLen)
        result[i] = name:sub(prefixLen + 1, suffixStart)
    end
    return result
end

local rawPetSummonNames = {}
for _, spellID in ipairs(PET_SUMMON_SPELL_IDS) do
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if spellInfo and spellInfo.name then rawPetSummonNames[spellID] = spellInfo.name end
end

local PET_NAMES = StripCommonAffixes(rawPetSummonNames)
Trainer.PetNames = PET_NAMES
function Trainer:GetPetNameById(id)
    return PET_NAMES[id]
end
