local _, ns = ...
local Trainer = ns.Trainer
local GetSpellInfo = ns.API.GetSpellInfo
function Trainer.ToggleIgnoreSpell(spellID)
    spellID = tonumber(spellID)
    local _, classToken = UnitClass("player")
    if not classToken or not spellID then return end
    TurboFaceTrainerCharDB.ignored[classToken] = TurboFaceTrainerCharDB.ignored[classToken] or {}
    local ignored = TurboFaceTrainerCharDB.ignored[classToken]
    if ignored[spellID] then
        ignored[spellID] = nil
    else
        ignored[spellID] = true
    end
end

function Trainer.ToggleIgnoreName(name)
    local _, classToken = UnitClass("player")
    if not classToken or not name then return end
    TurboFaceTrainerCharDB.ignoredNames[classToken] = TurboFaceTrainerCharDB.ignoredNames[classToken] or {}
    local ignored = TurboFaceTrainerCharDB.ignoredNames[classToken]
    if ignored[name] then
        ignored[name] = nil
        local ignoredSpells = TurboFaceTrainerCharDB.ignored[classToken]
        if ignoredSpells then
            for spellID in pairs(ignoredSpells) do
                if GetSpellInfo(spellID) == name then ignoredSpells[spellID] = nil end
            end
        end
    else
        ignored[name] = true
    end
end

function Trainer.IsSpellIgnored(spellID)
    spellID = tonumber(spellID)
    local _, classToken = UnitClass("player")
    if not classToken or not spellID then return false end
    return TurboFaceTrainerCharDB.ignored[classToken] and TurboFaceTrainerCharDB.ignored[classToken][spellID] or false
end

function Trainer.IsNameIgnored(name)
    local _, classToken = UnitClass("player")
    if not classToken or not name then return false end
    return TurboFaceTrainerCharDB.ignoredNames[classToken] and TurboFaceTrainerCharDB.ignoredNames[classToken][name] or false
end

function Trainer.IsIgnored(spellID, name)
    return Trainer.IsSpellIgnored(spellID) or Trainer.IsNameIgnored(name)
end

function Trainer.IsProfessionSpellIgnored(spellID, professionKey)
    spellID = tonumber(spellID)
    local _, classToken = UnitClass("player")
    if not classToken or not spellID then return false end
    professionKey = professionKey or Trainer:DetectTrainerProfession()
    if not professionKey then return false end
    TurboFaceTrainerCharDB.ignoredProfessions[professionKey] = TurboFaceTrainerCharDB.ignoredProfessions[professionKey] or {}
    local ignored = TurboFaceTrainerCharDB.ignoredProfessions[professionKey]
    return ignored[spellID] or false
end

function Trainer.ToggleIgnoreProfessionSpell(spellID, professionKey)
    spellID = tonumber(spellID)
    local _, classToken = UnitClass("player")
    if not classToken or not spellID then return end
    professionKey = professionKey or Trainer:DetectTrainerProfession()
    if not professionKey then return end
    TurboFaceTrainerCharDB.ignoredProfessions[professionKey] = TurboFaceTrainerCharDB.ignoredProfessions[professionKey] or {}
    local ignored = TurboFaceTrainerCharDB.ignoredProfessions[professionKey]
    if ignored[spellID] then
        ignored[spellID] = nil
    else
        ignored[spellID] = true
    end

    if Trainer.ProfessionRefresh then Trainer.ProfessionRefresh() end
end

function Trainer:MigrateLegacyProfessionIgnores()
    if TurboFaceTrainerDB.data.migratedProfessionIgnoresV1 then return end
    TurboFaceTrainerDB.data.migratedProfessionIgnoresV1 = true
    local _, classToken = UnitClass("player")
    if not classToken then return end
    local ignoredSpells = TurboFaceTrainerCharDB.ignored[classToken]
    local ignoredNames = TurboFaceTrainerCharDB.ignoredNames[classToken]
    if not ignoredSpells and not ignoredNames then return end
    for _, dataStore in ipairs({TurboFaceTrainerDB.professionData, TurboFaceTrainerDB.recipeData}) do
        for professionKey, byLevel in pairs(dataStore or {}) do
            for _, spells in pairs(byLevel) do
                for key, data in pairs(spells) do
                    local spellID = (type(key) == "number" and key) or (type(data) == "table" and data.spellID)
                    if spellID then
                        local name = GetSpellInfo(spellID)
                        local nameIgnored = ignoredNames and name and ignoredNames[name]
                        if (ignoredSpells and ignoredSpells[spellID]) or nameIgnored then
                            TurboFaceTrainerCharDB.ignoredProfessions[professionKey] = TurboFaceTrainerCharDB.ignoredProfessions[professionKey] or {}
                            TurboFaceTrainerCharDB.ignoredProfessions[professionKey][spellID] = true
                            if ignoredSpells then ignoredSpells[spellID] = nil end
                            if nameIgnored then ignoredNames[name] = nil end
                        end
                    end
                end
            end
        end
    end
end
