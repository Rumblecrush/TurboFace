local _, ns = ...
local Trainer = ns.Trainer
local GetSpellInfo = ns.API.GetSpellInfo

-- =============================================================================
-- SPELLBOOK "SKILLS" DATA
--
-- This is deliberately Trainer-owned rather than Skills.lua-owned. The latter
-- tracks the player's CURRENT skill values; this file describes things a
-- trainer can teach before the player owns the skill at all.
--
-- The static catalog gives a fresh install useful data immediately. Live
-- general-skill scans are kept in TurboFaceTrainerDB.skillData while profession
-- trainer scans live in professionData; both can override seeded metadata for
-- the current Classic client when available.
-- =============================================================================

local WEAPON_SKILLS = {
    AXES             = { spellID = 196,   level = 1, cost = 1000 },
    TWO_HANDED_AXES  = { spellID = 197,   level = 1, cost = 1000 },
    MACES            = { spellID = 198,   level = 1, cost = 1000 },
    TWO_HANDED_MACES = { spellID = 199,   level = 1, cost = 1000 },
    POLEARMS          = { spellID = 200,   level = 1, cost = 10000 },
    SWORDS            = { spellID = 201,   level = 1, cost = 1000 },
    TWO_HANDED_SWORDS= { spellID = 202,   level = 1, cost = 1000 },
    STAVES            = { spellID = 227,   level = 1, cost = 1000 },
    BOWS              = { spellID = 264,   level = 1, cost = 1000 },
    GUNS              = { spellID = 266,   level = 1, cost = 1000 },
    DAGGERS           = { spellID = 1180,  level = 1, cost = 1000 },
    THROWN            = { spellID = 2567,  level = 1, cost = 1000 },
    CROSSBOWS         = { spellID = 5011,  level = 1, cost = 1000 },
    FIST_WEAPONS      = { spellID = 15590, level = 1, cost = 1000 },
}

-- Weapon-master sources adapted from What's Training?'s MIT-licensed
-- Classes/WeaponSkills.lua catalog. Declaration order is intentional: cards
-- use the first master who teaches the skill as their compact primary source.
-- Capital names come from C_Map when available so the city is localized.
local WEAPON_MASTER_SOURCES = {
    {
        faction = "Alliance", name = "Buliwyf Stonehand", zoneID = 1537, city = "Ironforge",
        teaches = {196, 197, 198, 199, 266, 15590},
    },
    {
        faction = "Alliance", name = "Bixi Wobblebonk", zoneID = 1537, city = "Ironforge",
        teaches = {1180, 2567, 5011},
    },
    {
        faction = "Alliance", name = "Woo Ping", zoneID = 1519, city = "Stormwind City",
        teaches = {200, 201, 202, 227, 1180, 5011},
    },
    {
        faction = "Alliance", name = "Ilyenia Moonfire", zoneID = 1657, city = "Darnassus",
        teaches = {227, 264, 1180, 2567, 15590},
    },
    {
        faction = "Horde", name = "Hanashi", zoneID = 1637, city = "Orgrimmar",
        teaches = {196, 197, 227, 264, 2567},
    },
    {
        faction = "Horde", name = "Sayoc", zoneID = 1637, city = "Orgrimmar",
        teaches = {196, 197, 227, 264, 1180, 2567, 15590},
    },
    {
        faction = "Horde", name = "Ansekhwa", zoneID = 1638, city = "Thunder Bluff",
        teaches = {198, 199, 227, 266},
    },
    {
        faction = "Horde", name = "Archibald", zoneID = 1497, city = "Undercity",
        teaches = {200, 201, 202, 1180, 5011},
    },
}

local weaponMasterSources = {Alliance = {}, Horde = {}}
for _, master in ipairs(WEAPON_MASTER_SOURCES) do
    local factionSources = weaponMasterSources[master.faction]
    for _, spellID in ipairs(master.teaches) do
        factionSources[spellID] = factionSources[spellID] or {}
        factionSources[spellID][#factionSources[spellID] + 1] = master
    end
end

-- What's Training exposes every valid master. The compact card has room for
-- one source, so preserve known canonical choices where catalog declaration
-- order is not the desired presentation.
local PRIMARY_WEAPON_MASTER = {
    Horde = {
        [227] = "Ansekhwa", -- Staves: Thunder Bluff
    },
}

local function GetWeaponMasterSource(spellID, faction)
    if not (ns.TrainerProviderUsesDetailedWeaponMasterSources
        and ns.TrainerProviderUsesDetailedWeaponMasterSources()) then
        return "Weapon Master"
    end
    local sources = weaponMasterSources[faction or ""]
    sources = sources and sources[tonumber(spellID)]
    local master = sources and sources[1]
    local preferredName = PRIMARY_WEAPON_MASTER[faction or ""]
        and PRIMARY_WEAPON_MASTER[faction or ""][tonumber(spellID)]
    if preferredName then
        for _, candidate in ipairs(sources or {}) do
            if candidate.name == preferredName then
                master = candidate
                break
            end
        end
    end
    if not master then return "Weapon Master" end
    local city = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(master.zoneID)
    return master.name .. " - " .. (city or master.city)
end

-- Class-appropriate proficiencies, not race starting proficiencies. Starting
-- weapon skills naturally land in Already Known through IsPlayerSpell. Shaman
-- two-hand axes/maces are intentionally absent because Classic grants them via
-- the talent rather than a weapon master.
local CLASS_WEAPONS = {
    WARRIOR = {
        "AXES", "TWO_HANDED_AXES", "MACES", "TWO_HANDED_MACES", "POLEARMS",
        "SWORDS", "TWO_HANDED_SWORDS", "STAVES", "BOWS", "GUNS", "DAGGERS",
        "THROWN", "CROSSBOWS", "FIST_WEAPONS",
    },
    PALADIN = {
        "AXES", "TWO_HANDED_AXES", "MACES", "TWO_HANDED_MACES", "POLEARMS",
        "SWORDS", "TWO_HANDED_SWORDS",
    },
    HUNTER = {
        "AXES", "TWO_HANDED_AXES", "POLEARMS", "SWORDS", "TWO_HANDED_SWORDS",
        "STAVES", "BOWS", "GUNS", "DAGGERS", "THROWN", "CROSSBOWS",
        "FIST_WEAPONS",
    },
    ROGUE = {
        "MACES", "SWORDS", "BOWS", "GUNS", "DAGGERS", "THROWN", "CROSSBOWS",
        "FIST_WEAPONS",
    },
    PRIEST = { "MACES", "STAVES", "DAGGERS" },
    SHAMAN = { "AXES", "MACES", "STAVES", "DAGGERS", "FIST_WEAPONS" },
    MAGE = { "SWORDS", "STAVES", "DAGGERS" },
    WARLOCK = { "SWORDS", "STAVES", "DAGGERS" },
    DRUID = { "MACES", "TWO_HANDED_MACES", "STAVES", "DAGGERS", "FIST_WEAPONS" },
}

local PROFESSION_STARTERS = {
    -- Starter behavior is intentionally unchanged by the rank consolidation.
    -- This pass moves Journeyman/Expert/Artisan ownership only.
    Alchemy        = { spellID = 2259, level = 1, cost = 10 },
    Blacksmithing  = { spellID = 2018, level = 1, cost = 10 },
    Enchanting     = { spellID = 7411, level = 1, cost = 10 },
    Engineering    = { spellID = 4036, level = 1, cost = 10 },
    Herbalism      = { spellID = 2366, level = 1, cost = 10 },
    Leatherworking = { spellID = 2108, level = 1, cost = 10 },
    Mining         = { spellID = 2575, level = 1, cost = 10 },
    Skinning       = { spellID = 8613, level = 1, cost = 10 },
    Tailoring      = { spellID = 3908, level = 1, cost = 10 },
    Cooking        = { spellID = 2550, level = 1, cost = 10 },
    ["First Aid"] = { spellID = 3273, level = 1, cost = 10 },
    Fishing        = { spellID = 7620, level = 5, cost = 10 },
}

-- Profession proficiency rank-ups shown in the Spellbook Skills view.
--
-- This is the SINGLE static catalog for Journeyman/Expert/Artisan, including
-- production, gathering, and secondary professions. The profession-specific
-- Training panel deliberately filters these rows out; it owns ordinary profession
-- trainer skills/recipes, while the Spellbook Skills panel owns proficiency
-- advancement because it can show BOTH character-level and profession-skill
-- requirements in one place.
--
-- Spell IDs are the LEARNED skill spells (matching PROFESSION_STARTERS, which
-- seeds 2575 for Mining rather than 2582, the trainer's teaching spell). Live
-- trainer capture may expose a different teaching spell ID/name; the general-
-- skill resolver normalizes that service back to these learned IDs.
--
-- `skill` is the profession skill required, `level` the character level.
-- `trainable = false` marks ranks obtained from a book/quest rather than a
-- trainer, so they remain visible here but cannot enter the auto-training queue.
-- Costs are seeds only; trainer capture overwrites trainer-taught costs.
local PROFESSION_RANKS = {
    -- Standard production professions: 50/10, 125/20, 200/35.
    Alchemy = {
        { rank = "Journeyman", spellID = 3101,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 3464,  skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 11611, skill = 200, level = 35, cost = 50000 },
    },
    Blacksmithing = {
        { rank = "Journeyman", spellID = 3100, skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 3538, skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 9785, skill = 200, level = 35, cost = 50000 },
    },
    Enchanting = {
        { rank = "Journeyman", spellID = 7412,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 7413,  skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 13920, skill = 200, level = 35, cost = 50000 },
    },
    Engineering = {
        { rank = "Journeyman", spellID = 4037,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 4038,  skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 12656, skill = 200, level = 35, cost = 50000 },
    },
    Leatherworking = {
        { rank = "Journeyman", spellID = 3104,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 3811,  skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 10662, skill = 200, level = 35, cost = 50000 },
    },
    Tailoring = {
        { rank = "Journeyman", spellID = 3909,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 3910,  skill = 125, level = 20, cost = 5000 },
        { rank = "Artisan",    spellID = 12180, skill = 200, level = 35, cost = 50000 },
    },

    -- Gathering ranks advance earlier than production professions.
    Mining = {
        { rank = "Journeyman", spellID = 2576,  skill = 50,  level = 1,  cost = 100 },
        { rank = "Expert",     spellID = 3564,  skill = 125, level = 10, cost = 500 },
        { rank = "Artisan",    spellID = 10248, skill = 200, level = 25, cost = 2000 },
    },
    Herbalism = {
        { rank = "Journeyman", spellID = 2368,  skill = 50,  level = 1,  cost = 100 },
        { rank = "Expert",     spellID = 3570,  skill = 125, level = 10, cost = 500 },
        { rank = "Artisan",    spellID = 11993, skill = 200, level = 25, cost = 2000 },
    },
    Skinning = {
        { rank = "Journeyman", spellID = 8617,  skill = 50,  level = 1,  cost = 100 },
        { rank = "Expert",     spellID = 8618,  skill = 125, level = 10, cost = 500 },
        { rank = "Artisan",    spellID = 10768, skill = 200, level = 25, cost = 2000 },
    },

    -- Secondary professions. Book/quest ranks remain visible but are never
    -- trainer-queueable.
    Cooking = {
        { rank = "Journeyman", spellID = 3102,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 3413,  skill = 125, level = 20, cost = 10000,
          trainable = false, source = "Book: Expert Cookbook" },
        { rank = "Artisan",    spellID = 18260, skill = 225, level = 35, cost = 0,
          trainable = false, source = "Quest: Clamlette Surprise" },
    },
    ["First Aid"] = {
        { rank = "Journeyman", spellID = 3274,  skill = 50,  level = 1,  cost = 500 },
        { rank = "Expert",     spellID = 7924,  skill = 125, level = 1,  cost = 10000,
          trainable = false, source = "Book: Expert First Aid - Under Wraps" },
        { rank = "Artisan",    spellID = 10846, skill = 225, level = 35, cost = 0,
          trainable = false, source = "Quest: Triage" },
    },
    Fishing = {
        { rank = "Journeyman", spellID = 7731,  skill = 50,  level = 10, cost = 500 },
        { rank = "Expert",     spellID = 7732,  skill = 125, level = 20, cost = 10000,
          trainable = false, source = "Book: Old Man Heming (Booty Bay)" },
        { rank = "Artisan",    spellID = 18248, skill = 225, level = 35, cost = 0,
          trainable = false, source = "Quest: Nat Pagle (Dustwallow Marsh)" },
    },
}

local professionRankBySpellID = {}
for key, ranks in pairs(PROFESSION_RANKS) do
    for _, r in ipairs(ranks) do
        professionRankBySpellID[r.spellID] = { professionKey = key, rank = r }
    end
end

local weaponSpellIDs = {}
local professionStarterBySpellID = {}
for _, data in pairs(WEAPON_SKILLS) do weaponSpellIDs[data.spellID] = true end
for key, data in pairs(PROFESSION_STARTERS) do professionStarterBySpellID[data.spellID] = key end

local generalSkillNameToSpellID
local function BuildGeneralSkillNameMap(self)
    if generalSkillNameToSpellID then return generalSkillNameToSpellID end
    generalSkillNameToSpellID = {}

    local function Add(name, spellID)
        if type(name) == "string" and name ~= "" then
            generalSkillNameToSpellID[name:lower()] = spellID
        end
    end

    for key, data in pairs(WEAPON_SKILLS) do
        local name = GetSpellInfo and GetSpellInfo(data.spellID) or nil
        Add(name, data.spellID)
        Add(key:gsub("_", " "), data.spellID)
    end

    for professionKey, data in pairs(PROFESSION_STARTERS) do
        local displayName = self:GetProfessionDisplayName(professionKey) or professionKey
        local spellName = GetSpellInfo and GetSpellInfo(data.spellID) or nil
        Add(spellName, data.spellID)
        Add(displayName, data.spellID)
        Add("Apprentice " .. displayName, data.spellID)
        Add(professionKey, data.spellID)
        Add("Apprentice " .. professionKey, data.spellID)

        for _, r in ipairs(PROFESSION_RANKS[professionKey] or {}) do
            Add(r.rank .. " " .. displayName, r.spellID)
            Add(r.rank .. " " .. professionKey, r.spellID)
        end
    end

    return generalSkillNameToSpellID
end

function Trainer:IsWeaponSkillSpell(spellID)
    return spellID and weaponSpellIDs[tonumber(spellID)] == true or false
end

function Trainer:IsProfessionStarterSpell(spellID)
    return spellID and professionStarterBySpellID[tonumber(spellID)] ~= nil or false
end

-- Rank-ups are NOT starters: they must not count toward the two-primary cap,
-- and they are never "unavailable" for that reason -- you already have the
-- profession if you can see them.
-- True when an entry's profession-skill requirement is satisfied.
--
-- Reads the live value from ns.Skills, the same tracker the Skills panel shows,
-- rather than assuming. Entries WITHOUT a skillReq are unaffected and always
-- return true, so class spells and weapon skills keep their existing behaviour.
--
-- A real skill gate fails CLOSED if its source cannot be resolved. Showing an
-- Expert/Artisan rank before the player meets the profession requirement is
-- incorrect and can also make it queueable. Skills:Get resolves profession
-- aliases through ProfessionData, so normal spell-name/skill-line-name
-- differences (for example Herb Gathering vs Herbalism) do not cause a false
-- negative here.
function Trainer:IsSkillRequirementMet(entry)
    local req = entry and tonumber(entry.skillReq)
    if not req or req <= 0 then return true end

    -- Forever removed the legacy skill-line enumeration used by Skills.lua.
    -- While a profession page is active, its modern base info is the most
    -- direct authority for the current character's rank.  Match profession
    -- identity before using it so one open profession can never satisfy a
    -- requirement belonging to another profession.
    if ns.TrainerProviderUsesOpenProfessionSkillFallback
        and ns.TrainerProviderUsesOpenProfessionSkillFallback()
        and C_TradeSkillUI
        and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and (tonumber(info.professionID) or 0) > 0 then
            local requiredKey = self.GetProfessionKey
                and self:GetProfessionKey(entry.skillName or entry.name) or nil
            local openKey = self.GetProfessionKey
                and self:GetProfessionKey(info.professionName) or nil
            if requiredKey and openKey and requiredKey == openKey then
                return (tonumber(info.skillLevel) or 0) >= req
            end
        end
    end

    if not (ns.Skills and ns.Skills.Get) then return false end
    local rank = ns.Skills:Get(entry.skillName or entry.name)
    if rank == nil then return false end
    return (tonumber(rank) or 0) >= req
end

function Trainer:IsProfessionRankSpell(spellID)
    return spellID and professionRankBySpellID[tonumber(spellID)] ~= nil or false
end

function Trainer:IsProfessionRankTrainable(spellID)
    local info = spellID and professionRankBySpellID[tonumber(spellID)]
    return info ~= nil and info.rank.trainable ~= false or false
end

-- A rank is "known" once the skill's ceiling has reached what that rank grants.
-- Checking the spellbook would not work: training Journeyman REPLACES the
-- Apprentice spell rather than adding to it, so IsSpellKnown on the lower rank
-- goes false and the entry would reappear.
local RANK_CEILING = { Journeyman = 150, Expert = 225, Artisan = 300 }

function Trainer:IsProfessionRankKnown(professionKey, r)
    if not r then return false end
    local ceiling = RANK_CEILING[r.rank]
    if not ceiling then return false end
    local displayName = self:GetProfessionDisplayName(professionKey) or professionKey
    if not (ns.Skills and ns.Skills.Get) then return false end
    local _, maxRank = ns.Skills:Get(displayName)
    return (tonumber(maxRank) or 0) >= ceiling
end

function Trainer:IsProfessionRankSpellKnown(spellID)
    local info = spellID and professionRankBySpellID[tonumber(spellID)]
    if not info then return false end
    return self:IsProfessionRankKnown(info.professionKey, info.rank)
end

function Trainer:GetProfessionStarterKey(spellID)
    return spellID and professionStarterBySpellID[tonumber(spellID)] or nil
end

-- Trainer tooltips do not always yield a spell ID for an unlearned general
-- skill. Resolve by localized service name as a fallback so a Weapon Master can
-- never fall through into the class-spell database merely because GetSpell()
-- returned nil.
function Trainer:ResolveGeneralSkillSpellID(spellID, serviceName, serviceRank)
    spellID = tonumber(spellID)
    if self:IsWeaponSkillSpell(spellID)
        or self:IsProfessionStarterSpell(spellID)
        or self:IsProfessionRankSpell(spellID) then
        return spellID
    end
    if type(serviceName) ~= "string" or serviceName == "" then return nil end

    local map = BuildGeneralSkillNameMap(self)

    -- Profession rank trainer rows may expose the profession as the service
    -- name and the proficiency ("Journeyman", "Expert", ...) separately as
    -- serviceRank. Try that compound identity FIRST: plain "Mining" is also the
    -- Apprentice starter key, so resolving the bare service name first would
    -- incorrectly collapse every later Mining rank back to Apprentice.
    if type(serviceRank) == "string" and serviceRank ~= "" then
        local combined = map[(serviceRank .. " " .. serviceName):lower()]
        if combined then return combined end
    end

    return map[serviceName:lower()]
end

function Trainer:ScrubGeneralSkillsFromClassData(classToken)
    local data = TurboFaceTrainerDB and TurboFaceTrainerDB.data
    if not data then return end

    local function ScrubClass(token, levels)
        if type(levels) ~= "table" then return end
        for level, spells in pairs(levels) do
            if type(spells) == "table" then
                for storedID, captured in pairs(spells) do
                    local spellID = tonumber(storedID)
                    if self:IsWeaponSkillSpell(spellID) or self:IsProfessionStarterSpell(spellID) or self:IsProfessionRankSpell(spellID) then
                        local bucket = self:EnsureSkillPath(token, level)
                        if bucket[spellID] == nil then bucket[spellID] = captured end
                        spells[storedID] = nil
                    end
                end
            end
        end
    end

    if classToken then
        ScrubClass(classToken, data[classToken])
    else
        for token, levels in pairs(data) do ScrubClass(token, levels) end
    end
end

function Trainer:IsPrimaryProfessionStarterSpell(spellID)
    local professionKey = self:GetProfessionStarterKey(spellID)
    return professionKey ~= nil and not self:IsSecondaryProfession(professionKey)
end

local function AddKnownProfessionName(self, known, name)
    local key = name and self:GetProfessionKey(name)
    if key and PROFESSION_STARTERS[key] then known[key] = true end
end

-- Current-character profession authority. Classic Era still exposes professions
-- through the legacy skill-line system, and TurboFace already has a scanner that
-- safely expands collapsed headers, reads them, then restores the UI state. Use
-- that scanner first; GetProfessions is retained only as an additive fallback.
-- This avoids the exact failure where a Druid with Skinning + Leatherworking was
-- counted as having zero primaries and therefore saw every other starter as
-- Available.
function Trainer:GetKnownProfessionKeySet()
    local known = {}

    if ns.Skills and ns.Skills.GetAll then
        local data = ns.Skills:GetAll()
        for _, category in ipairs({"profession", "secondary"}) do
            for _, entry in ipairs((data and data[category]) or {}) do
                if entry.key and PROFESSION_STARTERS[entry.key] then known[entry.key] = true end
                AddKnownProfessionName(self, known, entry.name)
            end
        end
    end

    if GetProfessions and GetProfessionInfo then
        local professionSlots = {GetProfessions()}
        for i = 1, 6 do
            local professionIndex = professionSlots[i]
            if professionIndex then
                AddKnownProfessionName(self, known, GetProfessionInfo(professionIndex))
            end
        end
    end

    return known
end

function Trainer:GetKnownPrimaryProfessionCount()
    local count = 0
    for key in pairs(self:GetKnownProfessionKeySet()) do
        if not self:IsSecondaryProfession(key) then count = count + 1 end
    end
    return count
end

function Trainer:IsProfessionStarterUnavailable(spellID)
    if not self:IsPrimaryProfessionStarterSpell(spellID) then return false end
    if self:IsProfessionStarterKnown(spellID) then return false end
    return self:GetKnownPrimaryProfessionCount() >= 2
end

function Trainer:IsProfessionStarterKnown(spellID)
    local professionKey = self:GetProfessionStarterKey(spellID)
    if not professionKey then return false end
    return self:GetKnownProfessionKeySet()[professionKey] == true
end

function Trainer:EnsureSkillPath(class, level)
    -- Keep this accessor safe on its own because migrations call it while
    -- repairing legacy class-trainer contamination. Never assume the persisted
    -- Skills container survived an upgrade in a valid shape.
    if type(TurboFaceTrainerDB) ~= "table" then TurboFaceTrainerDB = {} end
    if type(TurboFaceTrainerDB.skillData) ~= "table" then TurboFaceTrainerDB.skillData = {} end
    if type(TurboFaceTrainerDB.skillData[class]) ~= "table" then TurboFaceTrainerDB.skillData[class] = {} end
    if type(TurboFaceTrainerDB.skillData[class][level]) ~= "table" then TurboFaceTrainerDB.skillData[class][level] = {} end
    return TurboFaceTrainerDB.skillData[class][level]
end

local function CopyCapturedFields(target, captured)
    if type(captured) ~= "table" then return end
    if captured.cost and captured.cost > 0 then target.cost = captured.cost end
    if captured.levelReq and captured.levelReq > 0 then target.levelReq = captured.levelReq end
    if captured.icon then target.icon = captured.icon end
    if captured.source then target.source = captured.source end
    if type(captured.requires) == "table" then
        target.requires = captured.requires
    elseif type(captured.requires) == "string" then
        target.requirementText = captured.requires
    end
    if captured.faction then target.faction = captured.faction end
    if captured.race then target.race = captured.race end
end

local function FindCapturedSkill(classToken, spellID)
    local levels = TurboFaceTrainerDB.skillData and TurboFaceTrainerDB.skillData[classToken]
    if not levels then return nil, nil end
    for level, spells in pairs(levels) do
        local captured = spells[spellID]
        if captured then return captured, tonumber(level) end
    end
    return nil, nil
end

local function FindCapturedProfession(professionKey, spellID, displayName, rankName, professionName)
    local levels = TurboFaceTrainerDB.professionData and TurboFaceTrainerDB.professionData[professionKey]
    if not levels then return nil, nil end

    local wantedDisplay = type(displayName) == "string" and displayName:lower() or nil
    local wantedRank = type(rankName) == "string" and rankName:lower() or nil
    local wantedProfession = type(professionName) == "string" and professionName:lower() or nil
    local nameFallback, rankFallback

    for skillReq, spells in pairs(levels) do
        for name, data in pairs(spells) do
            if type(data) == "table" then
                if tonumber(data.spellID) == spellID then return data, tonumber(skillReq) end

                local lowerName = type(name) == "string" and name:lower() or nil
                if wantedDisplay and lowerName == wantedDisplay then
                    nameFallback, rankFallback = data, tonumber(skillReq)
                elseif wantedRank and wantedProfession and lowerName == wantedProfession then
                    local capturedRank = type(data.rankText) == "string" and data.rankText:lower() or nil
                    if capturedRank and capturedRank:find(wantedRank, 1, true) then
                        nameFallback, rankFallback = data, tonumber(skillReq)
                    end
                end
            end
        end
    end

    return nameFallback, rankFallback
end

local function AddEntry(dataTable, level, key, data)
    level = tonumber(level) or 1
    dataTable[level] = dataTable[level] or {}
    dataTable[level][key] = data
end

function Trainer:BuildSpellbookWeaponSkillData()
    local _, classToken = UnitClass("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local dataTable = {}
    for _, key in ipairs(CLASS_WEAPONS[classToken] or {}) do
        local seeded = WEAPON_SKILLS[key]
        local captured = FindCapturedSkill(classToken, seeded.spellID)
        local entry = {
            spellID = seeded.spellID,
            cost = seeded.cost,
            source = GetWeaponMasterSource(seeded.spellID, faction),
        }
        CopyCapturedFields(entry, captured)
        -- Static source metadata is more specific than the generic
        -- "Weapon Master" marker written by live trainer capture.
        entry.source = GetWeaponMasterSource(seeded.spellID, faction)
        -- Every entry in the Spellbook Skills view is available from level 1.
        -- Live trainer scans may improve price/source metadata, but they must
        -- never reintroduce a level gate into this catalog.
        entry.levelReq = nil
        local spellName = GetSpellInfo and GetSpellInfo(seeded.spellID) or nil
        AddEntry(dataTable, 1, spellName or key, entry)
    end
    return dataTable
end


function Trainer:GetKnownProfessionStarterNames()
    local known = {}
    for key in pairs(self:GetKnownProfessionKeySet()) do
        if PROFESSION_STARTERS[key] then
            local displayName = self:GetProfessionDisplayName(key) or key
            known["Apprentice " .. displayName] = true
        end
    end
    return known
end

function Trainer:BuildSpellbookProfessionStarterData(secondary)
    local _, classToken = UnitClass("player")
    local dataTable = {}
    local knownProfessionKeys = self:GetKnownProfessionKeySet()

    for professionKey, seeded in pairs(PROFESSION_STARTERS) do
        if Trainer:IsSecondaryProfession(professionKey) == secondary then
            local professionName = Trainer:GetProfessionDisplayName(professionKey) or professionKey
            local displayName = "Apprentice " .. professionName
            local captured = FindCapturedProfession(
                professionKey, seeded.spellID, displayName, "Apprentice", professionName
            )
            local entry = {
                spellID = seeded.spellID,
                cost = seeded.cost,
                source = "Profession Trainer",
                -- Keep the canonical rank-prefixed name for matching/queue keys,
                -- but present the profession name itself in the Skills book.
                -- The localized spell subtext already supplies "(Apprentice)".
                displayName = professionName,
            }
            CopyCapturedFields(entry, captured)
            local genericCaptured = FindCapturedSkill(classToken, seeded.spellID)
            CopyCapturedFields(entry, genericCaptured)

            -- Starter behavior is unchanged by the proficiency-rank move.
            -- Gathering/Fishing keep the requirements established by the
            -- earlier Skills pass; production starters remain on their prior
            -- Spellbook behavior. Live captured metadata can still override.
            local starterLevel = 1
            if professionKey == "Mining" or professionKey == "Herbalism"
                or professionKey == "Skinning" or professionKey == "Fishing" then
                starterLevel = tonumber(entry.levelReq) or tonumber(seeded.level) or 1
            end
            entry.levelReq = starterLevel > 1 and starterLevel or nil
            AddEntry(dataTable, starterLevel, displayName, entry)

            -- Rank-ups only exist in this view once the player owns that
            -- profession. Before that, the Apprentice row is the useful action.
            local ranks = PROFESSION_RANKS[professionKey]
            if ranks and knownProfessionKeys[professionKey] then
                for _, r in ipairs(ranks) do
                    -- A rank disappears after training. maxRank is the reliable
                    -- authority because rank spells replace one another.
                    if not Trainer:IsProfessionRankKnown(professionKey, r) then
                        local rankDisplayName = r.rank .. " " .. professionName
                        local capturedRank, capturedSkillReq = FindCapturedProfession(
                            professionKey, r.spellID, rankDisplayName, r.rank, professionName
                        )
                        local rankEntry = {
                            spellID = r.spellID,
                            cost = r.cost,
                            source = r.source or "Profession Trainer",
                            -- Keep static queue policy separate from the runtime
                            -- `trainingQueueEligible` state computed by the UI.
                            queueAllowed = Trainer:IsProfessionRankTrainable(r.spellID),
                            -- The tracker is keyed by the profession display name,
                            -- not by a row name such as "Expert Mining".
                            skillName = professionName,
                            -- Do not repeat the proficiency in the visible label:
                            -- "Herb Gathering (Journeyman)", not
                            -- "Journeyman Herb Gathering (Journeyman)".
                            -- `name` remains rank-prefixed for matching/queue logic.
                            displayName = professionName,
                        }
                        CopyCapturedFields(rankEntry, capturedRank)
                        CopyCapturedFields(rankEntry, FindCapturedSkill(classToken, r.spellID))

                        -- A live 1.15.9 trainer scan is authoritative when it
                        -- exposes a skill requirement. Otherwise use the static
                        -- Classic Era seed so the view works before trainer visit.
                        local skillReq = tonumber(capturedSkillReq)
                        if not skillReq or skillReq <= 0 then skillReq = tonumber(r.skill) or 0 end
                        rankEntry.skillReq = skillReq
                        if not rankEntry.requirementText and skillReq > 0 then
                            rankEntry.requirementText = ("%s %d"):format(professionName, skillReq)
                        end

                        -- CopyCapturedFields may have supplied the live trainer's
                        -- level requirement. Fall back to the static Era rule.
                        local levelReq = tonumber(rankEntry.levelReq)
                        if not levelReq or levelReq <= 0 then levelReq = tonumber(r.level) or 1 end
                        rankEntry.levelReq = levelReq > 1 and levelReq or nil
                        AddEntry(dataTable, levelReq, rankDisplayName, rankEntry)
                    end
                end
            end
        end
    end
    return dataTable
end

function Trainer:BuildSpellbookSkillsData()
    local merged = {}
    local function Merge(source)
        for level, spells in pairs(source or {}) do
            local bucketLevel = tonumber(level) or 1
            merged[bucketLevel] = merged[bucketLevel] or {}
            for key, data in pairs(spells) do merged[bucketLevel][key] = data end
        end
    end
    Merge(self:BuildSpellbookWeaponSkillData())
    Merge(self:BuildSpellbookProfessionStarterData(true))
    Merge(self:BuildSpellbookProfessionStarterData(false))
    return merged
end

-- Older builds treated every non-tradeskill trainer as a class trainer. Move
-- known weapon/profession starter captures out of the class catalog so entries
-- such as Daggers no longer appear under Classtrainer after upgrading.
function Trainer:MigrateLegacySkillCaptures()
    local db = TurboFaceTrainerDB
    -- This scrub is intentionally idempotent and runs on every initialization.
    -- The original migration marker could already be set before a later bad
    -- Weapon Master scan reintroduced Daggers into class data, leaving the bad
    -- row permanent. A cheap deterministic scrub is safer than another one-shot
    -- migration version and also handles numeric IDs serialized as strings.
    self:ScrubGeneralSkillsFromClassData()
    db.migratedSpellbookSkillsV1 = true

    -- General skills are queueable now. Older builds either misfiled these
    -- records under the class/profession scopes or (for the first Skills build)
    -- deliberately removed them. We cannot reconstruct entries that were
    -- already deleted, but any surviving legacy records are migrated into the
    -- dedicated Skills queue rather than discarded. This marker is character-
    -- local because TurboFaceTrainerCharDB is per-character.
    local character = TurboFaceTrainerCharDB and TurboFaceTrainerCharDB.character
    if character and not character.migratedSpellbookSkillQueueV2 then
        character.migratedSpellbookSkillQueueV2 = true
        local queue = character.trainingQueue
        local _, classToken = UnitClass("player")
        if type(queue) == "table" and classToken then
            local moves = {}
            for queueKey, record in pairs(queue) do
                local spellID = type(record) == "table" and tonumber(record.spellID)
                if self:IsWeaponSkillSpell(spellID) or self:IsProfessionStarterSpell(spellID) then
                    moves[#moves + 1] = { oldKey = queueKey, record = record }
                end
            end
            for _, move in ipairs(moves) do
                local record = move.record
                local entry = {
                    spellID = record.spellID,
                    name = record.name,
                    rankNum = record.rankNum,
                    level = record.level,
                }
                local newKey = self:GetTrainingQueueKey(entry, "skills", classToken)
                queue[move.oldKey] = nil
                if newKey then
                    record.scope = "skills"
                    record.owner = tostring(classToken)
                    if queue[newKey] == nil then queue[newKey] = record end
                end
            end
        end
    end

    -- Rank-ups used to belong to the profession Training panel/queue. They now
    -- have one UI owner: Spellbook Skills. Migrate surviving profession-scope
    -- rank records so a user's existing queue intent is preserved rather than
    -- becoming an invisible stale record after the presentation move.
    if character and not character.migratedProfessionRanksToSkillsV3 then
        character.migratedProfessionRanksToSkillsV3 = true
        local queue = character.trainingQueue
        local _, classToken = UnitClass("player")
        if type(queue) == "table" and classToken then
            local moves = {}
            for queueKey, record in pairs(queue) do
                if type(record) == "table" and record.scope == "profession" then
                    local professionKey = tostring(record.owner or "")
                    local ranks = PROFESSION_RANKS[professionKey]
                    if ranks then
                        local matched
                        local spellInfo = professionRankBySpellID[tonumber(record.spellID)]
                        if spellInfo and spellInfo.professionKey == professionKey then
                            matched = spellInfo.rank
                        elseif self.GetProfessionRankCap then
                            local professionName = self:GetProfessionDisplayName(professionKey) or professionKey
                            local cap = self:GetProfessionRankCap(record.name, professionName, record.spellID)
                            if cap then
                                for _, r in ipairs(ranks) do
                                    if RANK_CEILING[r.rank] == cap then
                                        matched = r
                                        break
                                    end
                                end
                            end
                        end
                        if matched then
                            moves[#moves + 1] = {
                                oldKey = queueKey,
                                record = record,
                                professionKey = professionKey,
                                rank = matched,
                            }
                        end
                    end
                end
            end

            for _, move in ipairs(moves) do
                local record, r = move.record, move.rank
                local professionName = self:GetProfessionDisplayName(move.professionKey) or move.professionKey
                local entry = {
                    spellID = r.spellID,
                    name = r.rank .. " " .. professionName,
                    level = r.level,
                }
                local newKey = self:GetTrainingQueueKey(entry, "skills", classToken)
                queue[move.oldKey] = nil
                if newKey then
                    record.scope = "skills"
                    record.owner = tostring(classToken)
                    record.spellID = r.spellID
                    record.name = entry.name
                    record.level = r.level
                    record.rankNum = nil
                    record.hasRealRank = false
                    if queue[newKey] == nil then queue[newKey] = record end
                end
            end
        end
    end
end
