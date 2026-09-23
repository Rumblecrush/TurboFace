local _, ns = ...
local Trainer = ns.Trainer
local GetSpellInfo = ns.API.GetSpellInfo
local function ResolveTalentSpellIDByName(name)
    if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo or not GetTalentLink then return nil end
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local talentName = GetTalentInfo(tab, i)
            if talentName == name then
                local link = GetTalentLink(tab, i)
                if link then
                    local scanTooltip = Trainer:GetScanTooltip()
                    scanTooltip:ClearLines()
                    scanTooltip:SetHyperlink(link)
                    local _, spellID = scanTooltip:GetSpell()
                    if Trainer:IsSaneSpellID(spellID) then return spellID end
                end
                return nil
            end
        end
    end
end

local function ResolveRequirementSpellID(name)
    local _, _, _, _, _, _, spellID = GetSpellInfo(name)
    if Trainer:IsSaneSpellID(spellID) then return spellID end
    spellID = ResolveTalentSpellIDByName(name)
    if Trainer:IsSaneSpellID(spellID) then return spellID end
    local baseName = name:match("^(.-)%s*%b()$")
    if baseName then
        _, _, _, _, _, _, spellID = GetSpellInfo(baseName)
        if Trainer:IsSaneSpellID(spellID) then return spellID end
        spellID = ResolveTalentSpellIDByName(baseName)
        if Trainer:IsSaneSpellID(spellID) then return spellID end
    end
end

local function ParseRequirementText(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local colonPos = text:find(":")
    local reqText = colonPos and text:sub(colonPos + 1) or text
    local spellIDs = {}
    for part in reqText:gmatch("[^,]+") do
        part = part:match("^%s*(.-)%s*$")
        if part ~= "" then
            local spellID = ResolveRequirementSpellID(part)
            if spellID then table.insert(spellIDs, spellID) end
        end
    end

    if #spellIDs == 0 then return nil end
    return spellIDs
end

local function CaptureTrainerInner()
    -- Trainer events can expose persisted data immediately after load/reload.
    -- Keep capture robust even if an older SavedVariables schema omitted one
    -- of the newer containers such as skillData.
    Trainer:InitSavedVariables()
    Trainer.currentTrainerHasGeneralSkills = false
    local _, classToken = UnitClass("player")
    local isTradeskill = IsTradeskillTrainer and IsTradeskillTrainer()
    local professionKey = isTradeskill and Trainer:DetectTrainerProfession() or nil
    if not classToken then
        ns:Chat("Trainer", "UnitClass(\"player\") returned no class token.")
        return
    end

    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then
        ns:Chat("Trainer", "Trainer service APIs are unavailable on this client; run /tf debug trainer while the trainer is open.")
        return
    end

    Trainer:ExpandAllTrainerHeaders()
    local numServices = GetNumTrainerServices()
    local rankFound = false
    for i = 1, numServices do
        local _, _, sType = Trainer:GetTrainerServiceInfoCompat(i)
        if sType == "available" or sType == "unavailable" or sType == "used" then
            rankFound = true
            break
        end
    end

    if not rankFound then return end
    for i = 1, numServices do
        local name, rankText, sType = Trainer:GetTrainerServiceInfoCompat(i)
        local rank = rankText and tonumber(rankText:match("%d+"))
        local levelReq = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
        if (rank ~= nil or levelReq ~= nil) and (sType == "available" or sType == "unavailable" or sType == "used") then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            local skillLine = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(i)
            local spellID = Trainer:GetSpellIDForService(i)
            local isPetTraining = spellID and Trainer:IsPetTrainerSkillLine(skillLine)
            local generalSkillID = not isPetTraining and Trainer:ResolveGeneralSkillSpellID(spellID, name, rankText) or nil
            if generalSkillID then spellID = generalSkillID end
            local isGeneralSkill = generalSkillID ~= nil
            if isGeneralSkill then Trainer.currentTrainerHasGeneralSkills = true end

            if name and professionKey then
                local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i)
                local skillReq = Trainer:GetSkillReqForService(i)
                local bucket = Trainer:EnsureProfessionPath(professionKey, skillReq)
                local existing = bucket[name]
                local entry = {
                    spellID = spellID or (existing and existing.spellID),
                    icon = icon or (existing and existing.icon),
                    cost = cost,
                    rank = rank,
                    -- Preserve the raw rank label (for example "Journeyman") so
                    -- SkillData can match proficiency upgrades even when the
                    -- trainer service and learned spell use different IDs.
                    rankText = rankText,
                    status = sType,
                    levelReq = (levelReq and levelReq > 0) and levelReq or nil,
                    -- Preserve the profession gate as entry metadata as well
                    -- as the outer bucket. Native trainer cards must not
                    -- reinterpret that bucket as a character-level requirement.
                    skillReq = skillReq,
                    skillName = Trainer:GetProfessionDisplayName(professionKey)
                        or skillLine or professionKey,
                    requires = existing and existing.requires,
                    source = "Trainer capture",
                }
                bucket[name] = entry

            else
                if spellID then
                    -- Weapon masters used to fall through to the class catalog,
                    -- which is how skills such as Daggers appeared under
                    -- Classtrainer. Remove any stale class copy whenever a
                    -- recognized general skill is seen again.
                    if isPetTraining or isGeneralSkill then
                        local classLevels = TurboFaceTrainerDB.data[classToken]
                        if classLevels then
                            for _, oldBucket in pairs(classLevels) do
                                if type(oldBucket) == "table" then oldBucket[spellID] = nil end
                            end
                        end
                    end

                    if isGeneralSkill then
                        local skillLevels = TurboFaceTrainerDB.skillData[classToken]
                        if skillLevels then
                            for _, oldSkillBucket in pairs(skillLevels) do
                                if type(oldSkillBucket) == "table" then oldSkillBucket[spellID] = nil end
                            end
                        end
                        local bucket = Trainer:EnsureSkillPath(classToken, levelReq or 0)
                        local existing = bucket[spellID]
                        bucket[spellID] = {
                            icon = (GetTrainerServiceIcon and GetTrainerServiceIcon(i)) or (existing and existing.icon),
                            cost = (cost and cost > 0 and cost) or (existing and existing.cost),
                            rank = rank,
                            levelReq = (levelReq and levelReq > 0) and levelReq or nil,
                            source = (Trainer:IsProfessionStarterSpell(spellID) or Trainer:IsProfessionRankSpell(spellID)) and "Profession Trainer" or "Weapon Master",
                            requires = existing and existing.requires,
                            faction = existing and existing.faction,
                            race = existing and existing.race
                            -- Deliberately no status=sType. skillData is shared
                            -- account metadata; known state must be evaluated
                            -- from the current character's spellbook.
                        }
                    else
                        local bucket = isPetTraining and Trainer:EnsurePetTrainerPath(classToken, levelReq or 0) or Trainer:EnsurePath(classToken, levelReq or 0)
                        local existing = bucket[spellID]
                        bucket[spellID] = {
                            cost = cost,
                            rank = rank,
                            status = sType,
                            requires = existing and existing.requires,
                            faction = existing and existing.faction,
                            race = existing and existing.race
                        }
                    end
                end
            end
        end
    end

end

function Trainer:CaptureTrainer()
    local ok, err = pcall(CaptureTrainerInner)
    if not ok then ns:Chat("Trainer", "|cffff5555Capture error:|r " .. tostring(err)) end
end

local function OnTrainerServiceSelectedInner(id)
    Trainer:InitSavedVariables()
    local _, classToken = UnitClass("player")
    if not classToken or not id then return end
    local fs = _G["ClassTrainerSkillRequirements"]
    local text = fs and fs:GetText()
    local requires = text and ParseRequirementText(text)
    if not requires then return end
    local isTradeskill = IsTradeskillTrainer and IsTradeskillTrainer()
    local professionKey
    if isTradeskill then professionKey = Trainer:DetectTrainerProfession() end
    local bucket, key
    if professionKey then
        local name = Trainer:GetTrainerServiceInfoCompat(id)
        local skillReq = Trainer:GetSkillReqForService(id)
        local profession = TurboFaceTrainerDB.professionData[professionKey]
        bucket = profession and profession[skillReq]
        key = name
    else
        local serviceName, serviceRank = Trainer:GetTrainerServiceInfoCompat(id)
        local spellID = Trainer:GetSpellIDForService(id)
        local skillLine = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(id)
        local levelReq = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(id) or 0
        local isPetTraining = spellID and Trainer:IsPetTrainerSkillLine(skillLine)
        local generalSkillID = not isPetTraining and Trainer:ResolveGeneralSkillSpellID(spellID, serviceName, serviceRank) or nil
        if generalSkillID then spellID = generalSkillID end
        if not spellID then return end
        local isGeneralSkill = generalSkillID ~= nil
        local levels
        if isPetTraining then
            levels = TurboFaceTrainerDB.petTrainerData[classToken]
        elseif isGeneralSkill then
            levels = TurboFaceTrainerDB.skillData[classToken]
        else
            levels = TurboFaceTrainerDB.data[classToken]
        end
        bucket = levels and levels[levelReq]
        key = spellID
    end

    if bucket and key and bucket[key] then
        bucket[key].requires = requires
        if Trainer.RefreshActiveSpellbookList then
            Trainer.RefreshActiveSpellbookList()
        elseif Trainer.RefreshList then
            Trainer.RefreshList()
        end
        if Trainer.ProfessionRefresh then Trainer.ProfessionRefresh() end
    end
end

local function OnTrainerServiceButtonClicked(self)
    if not Trainer.tooltipActive then return end
    local id = self:GetID()
    local ok, err = pcall(OnTrainerServiceSelectedInner, id)
    if not ok then ns:Chat("Trainer", "|cffff5555Capture error:|r " .. tostring(err)) end
end

local hookedTrainerButtons = {}
function Trainer:CaptureTrainerRequirements()
    local i = 1
    while _G["ClassTrainerSkill" .. i] do
        local button = _G["ClassTrainerSkill" .. i]
        if not hookedTrainerButtons[button] then
            hookedTrainerButtons[button] = true
            button:HookScript("OnClick", OnTrainerServiceButtonClicked)
        end

        i = i + 1
    end
end