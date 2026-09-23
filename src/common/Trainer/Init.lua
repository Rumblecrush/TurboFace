local _, ns = ...
local Trainer = ns.Trainer
local GetSpellInfo = ns.API.GetSpellInfo
local BEAST_TRAINING_SPELL_ID = 5149
local PET_TRAINER_SKILL_LINE = GetSpellInfo(BEAST_TRAINING_SPELL_ID) or ""
local ProfessionData = ns.ProfessionData

-- Compatibility methods retained on Trainer for existing Trainer UI callers.
-- The underlying metadata is neutral shared data owned by ProfessionData.
function Trainer:GetProfessionIcon(key)
    return ProfessionData and ProfessionData:GetIcon(key) or nil
end

function Trainer:IsSecondaryProfession(key)
    return ProfessionData and ProfessionData:IsSecondary(key) or false
end

function Trainer:GetProfessionKeyMap()
    return ProfessionData and ProfessionData:GetKeyMap() or {}
end

function Trainer:GetProfessionKey(name)
    return ProfessionData and ProfessionData:GetKey(name) or nil
end

function Trainer:GetProfessionDisplayName(key)
    return ProfessionData and ProfessionData:GetDisplayName(key) or nil
end

function Trainer:DetectTrainerProfession()
    if not GetNumTrainerServices or not GetTrainerServiceSkillLine then return nil end
    for i = 1, GetNumTrainerServices() do
        local skillLine = GetTrainerServiceSkillLine(i)
        if skillLine and ProfessionData and ProfessionData:IsProfessionSkillLine(skillLine) then return ProfessionData:GetKey(skillLine) or skillLine, skillLine end
    end
    return nil
end

function Trainer:IsPetTrainerSkillLine(skillLine)
    return skillLine == PET_TRAINER_SKILL_LINE
end

-- Built on first use rather than at load, so a disabled module creates no
-- frames at all. Only the capture paths touch it.
function Trainer:GetScanTooltip()
    if not self.ScanTooltip then
        self.ScanTooltip = CreateFrame("GameTooltip", "TurboFaceTrainerScanTooltip", nil, "GameTooltipTemplate")
        self.ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return self.ScanTooltip
end
function Trainer:IsSaneSpellID(spellID)
    return type(spellID) == "number" and spellID > 0 and spellID < 2000000
end

local function TrainerRankNumber(rankText)
    if type(rankText) == "number" then return rankText end
    if type(rankText) ~= "string" then return nil end
    return tonumber(rankText:match("%d+"))
end

-- Trainer service information is one of the Forever port's live compatibility
-- boundaries. Era returns name, rank, category, expanded. Some retail-derived
-- trainer implementations expose the category in return #2 instead. Normalize
-- both layouts here so capture and auto-training do not silently classify every
-- row as unknown. Unknown layouts fail closed and are visible in /tf debug trainer.
local TRAINER_SERVICE_TYPES = {
    available = true,
    unavailable = true,
    used = true,
    header = true,
}

function Trainer:GetTrainerServiceInfoCompat(index)
    if type(GetTrainerServiceInfo) ~= "function" then
        return nil, nil, nil, nil, "missing"
    end

    local ok, a, b, c, d = pcall(GetTrainerServiceInfo, index)
    if not ok then
        return nil, nil, nil, nil, "error", a
    end

    -- Be liberal at the compatibility boundary if a future client changes this
    -- old global into a structured return. No current Forever build requires
    -- this path, but accepting obvious field names is safer than indexing blindly.
    if type(a) == "table" then
        local name = a.name or a.serviceName
        local rank = a.rank or a.subText or a.serviceSubText
        local category = a.category or a.serviceType or a.type
        local expanded = a.expanded
        if expanded == nil then expanded = a.isExpanded end
        if TRAINER_SERVICE_TYPES[category] then
            return name, rank, category, expanded, "table"
        end
        return name, rank, category, expanded, "table-unknown"
    end

    if TRAINER_SERVICE_TYPES[c] then
        return a, b, c, d, "category-third"
    end
    if TRAINER_SERVICE_TYPES[b] then
        -- Retail-derived two/three-return layout: name, category, expanded.
        return a, nil, b, c, "category-second"
    end

    return a, b, c, d, "unknown"
end

local requestedTrainerSpellData = {}
function Trainer:RequestSpellDataIfNeeded(spellID)
    if not self:IsSaneSpellID(spellID) then return false end
    if requestedTrainerSpellData[spellID] then return false end
    local spellAPI = C_Spell
    if type(spellAPI) ~= "table" or type(spellAPI.RequestLoadSpellData) ~= "function" then
        return false
    end

    if type(spellAPI.IsSpellDataCached) == "function" then
        local ok, cached = pcall(spellAPI.IsSpellDataCached, spellID)
        if ok and cached == true then return false end
    end

    local ok = pcall(spellAPI.RequestLoadSpellData, spellID)
    if ok then requestedTrainerSpellData[spellID] = true end
    return ok
end

-- Forever's modern spell API can resolve an unlearned spell by numeric ID, but
-- a localized spell NAME is only a reliable SpellIdentifier once that spell is
-- already in the player's spellbook. Trainer rows are the inverse case: the
-- important rows are usually still unlearned. Resolve those rows against the
-- seeded class catalog instead of depending on C_Spell name lookup.
--
-- Name is the hard identity boundary. Rank and level are disambiguators. If the
-- catalog still has an unresolved tie, return nil rather than risk buying the
-- wrong trainer service.
function Trainer:ResolveClassTrainerServiceSpellID(serviceName, serviceRank, serviceLevelReq)
    if type(serviceName) ~= "string" or serviceName == "" then return nil end

    local _, classToken = UnitClass("player")
    local classData = classToken and TurboFaceTrainerDB and TurboFaceTrainerDB.data
        and TurboFaceTrainerDB.data[classToken]
    if type(classData) ~= "table" then return nil end

    local wantedRank = TrainerRankNumber(serviceRank)
    local wantedLevel = tonumber(serviceLevelReq)
    if wantedLevel and wantedLevel <= 0 then wantedLevel = nil end

    local bestSpellID, bestScore, bestCount
    for level, spells in pairs(classData) do
        if type(spells) == "table" then
            for spellID, data in pairs(spells) do
                if self:IsSaneSpellID(spellID) then
                    local spellName = GetSpellInfo(spellID)
                    if not spellName then
                        -- Modern spell metadata is load-on-demand. Request it and
                        -- let SPELL_DATA_LOAD_RESULT drive another trainer pass.
                        self:RequestSpellDataIfNeeded(spellID)
                    end
                    if spellName == serviceName then
                        local dataRank = type(data) == "table" and TrainerRankNumber(data.rank) or nil
                        local rankConflicts = wantedRank and dataRank and wantedRank ~= dataRank
                        if not rankConflicts then
                            local score = 1 -- exact localized name
                            if wantedRank and dataRank == wantedRank then score = score + 8 end

                            local dataLevel = tonumber(level)
                            if type(data) == "table" and tonumber(data.levelReq) then
                                dataLevel = tonumber(data.levelReq)
                            end
                            if wantedLevel and dataLevel == wantedLevel then score = score + 4 end

                            if not bestScore or score > bestScore then
                                bestSpellID, bestScore, bestCount = spellID, score, 1
                            elseif score == bestScore and spellID ~= bestSpellID then
                                bestCount = (bestCount or 1) + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if bestCount == 1 then return bestSpellID end
    return nil
end

function Trainer:GetSpellIDForService(i)
    if not GetTrainerServiceInfo then return nil end

    local serviceName, serviceRank = self:GetTrainerServiceInfoCompat(i)
    local serviceLevelReq = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or nil
    local spellID

    -- Retail-derived clients expose structured trainer tooltip data. Its id is
    -- not assumed to be a spell ID: accept it only when numeric spell metadata
    -- resolves back to this exact trainer-service name.
    if C_TooltipInfo and type(C_TooltipInfo.GetTrainerService) == "function" then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
        local candidate = ok and type(data) == "table" and data.id or nil
        if self:IsSaneSpellID(candidate) then
            local candidateName = GetSpellInfo(candidate)
            if candidateName == serviceName then spellID = candidate end
        end
    end

    -- Era-compatible tooltip path. Keep this as a capability-gated fallback;
    -- Forever's retail-derived trainer tooltip does not reliably expose the
    -- unlearned service spell through GameTooltip:GetSpell().
    if not spellID then
        local scanTooltip = Trainer:GetScanTooltip()
        if scanTooltip and scanTooltip.SetTrainerService and scanTooltip.GetSpell then
            local ok, _, candidate = pcall(function()
                scanTooltip:ClearLines()
                scanTooltip:SetTrainerService(i)
                return scanTooltip:GetSpell()
            end)
            if ok and self:IsSaneSpellID(candidate) then spellID = candidate end
        end
    end

    -- Deterministic Forever fallback for class trainers. Thunder Clap Rank 1,
    -- for example, maps back to seeded spellID 6343 by name + rank/level even
    -- though the player has not learned it yet.
    if not spellID then
        spellID = self:ResolveClassTrainerServiceSpellID(serviceName, serviceRank, serviceLevelReq)
    end

    -- Last-resort compatibility for clients where name lookup still resolves
    -- trainer spells. Do not make this the primary modern path: C_Spell name
    -- identifiers are spellbook-dependent for unlearned spells.
    if not spellID and serviceName then
        local _, _, _, _, _, _, foundSpellID = GetSpellInfo(serviceName)
        if self:IsSaneSpellID(foundSpellID) then spellID = foundSpellID end
    end

    return self:IsSaneSpellID(spellID) and spellID or nil
end

function Trainer:GetSkillReqForService(i)
    if not GetTrainerServiceSkillReq then return 0 end
    local _, skillReq = GetTrainerServiceSkillReq(i)
    return skillReq or 0
end

function Trainer:ExpandAllTrainerHeaders()
    if not GetNumTrainerServices or not GetTrainerServiceInfo or not ExpandTrainerSkillLine then return end
    local i = 1
    while i <= GetNumTrainerServices() do
        local _, _, category, expanded = self:GetTrainerServiceInfoCompat(i)
        if category == "header" and not expanded then ExpandTrainerSkillLine(i) end
        i = i + 1
    end
end

function Trainer:EnsurePath(class, level)
    TurboFaceTrainerDB.data[class] = TurboFaceTrainerDB.data[class] or {}
    TurboFaceTrainerDB.data[class][level] = TurboFaceTrainerDB.data[class][level] or {}
    return TurboFaceTrainerDB.data[class][level]
end

function Trainer:EnsurePetTrainerPath(class, level)
    TurboFaceTrainerDB.petTrainerData[class] = TurboFaceTrainerDB.petTrainerData[class] or {}
    TurboFaceTrainerDB.petTrainerData[class][level] = TurboFaceTrainerDB.petTrainerData[class][level] or {}
    return TurboFaceTrainerDB.petTrainerData[class][level]
end

function Trainer:EnsureProfessionPath(profession, skillReq)
    TurboFaceTrainerDB.professionData[profession] = TurboFaceTrainerDB.professionData[profession] or {}
    TurboFaceTrainerDB.professionData[profession][skillReq] = TurboFaceTrainerDB.professionData[profession][skillReq] or {}
    return TurboFaceTrainerDB.professionData[profession][skillReq]
end

function Trainer:EnsureRecipePath(profession, skillReq)
    TurboFaceTrainerDB.recipeData[profession] = TurboFaceTrainerDB.recipeData[profession] or {}
    TurboFaceTrainerDB.recipeData[profession][skillReq] = TurboFaceTrainerDB.recipeData[profession][skillReq] or {}
    return TurboFaceTrainerDB.recipeData[profession][skillReq]
end

function Trainer:EnsurePetPath(pet, level)
    TurboFaceTrainerDB.petData[pet] = TurboFaceTrainerDB.petData[pet] or {}
    TurboFaceTrainerDB.petData[pet][level] = TurboFaceTrainerDB.petData[pet][level] or {}
    return TurboFaceTrainerDB.petData[pet][level]
end