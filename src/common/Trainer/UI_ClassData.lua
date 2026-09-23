local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellSubtext = ns.API.GetSpellSubtext

Trainer:AddBuilder(function()
    function Trainer:AddHeaderItem(items, text, colorCode, totalCost, groupKey, prefixText)
        table.insert(items, {
            isHeader = true,
            text = text,
            color = colorCode,
            totalCost = totalCost,
            groupKey = groupKey,
            collapsed = Trainer:IsGroupCollapsed(groupKey),
            prefixText = prefixText
        })
    end

    function Trainer:AddEntryItems(items, list, colorCode, showLevel, showCostTooltip, dimName, levelLabel, requirementMode)
        for _, entry in ipairs(list) do
            table.insert(items, {
                isHeader = false,
                entry = entry,
                color = colorCode,
                showLevel = showLevel,
                showCostTooltip = showCostTooltip,
                dimName = dimName,
                levelLabel = levelLabel,
                requirementMode = requirementMode,
            })
        end
    end

    function Trainer:SumCost(list)
        local total = 0
        for _, entry in ipairs(list) do
            total = total + (entry.cost or 0)
        end
        return total
    end

    function Trainer:BuildEntriesFromData(dataTable)
        local allEntries = {}
        local knownMaxRank = {}
        local playerFaction = Trainer:GetPlayerFaction()
        local playerRace = Trainer:GetPlayerRace()
        for lvl, spells in pairs(dataTable) do
            for key, data in pairs(spells) do
                local cost, rank, status, requires, faction, race, spellID, icon, levelReq
                local source, skillReq, skillName, skillRequirementUnknown, queueAllowed, displayName
                local requirementText
                if type(data) == "table" then
                    cost, rank, status, requires, faction, race = data.cost, data.rank, data.status, data.requires, data.faction, data.race
                    spellID, icon, levelReq = data.spellID, data.icon, data.levelReq
                    source = data.source
                    -- Profession rank-ups gate on skill, not just level.
                    skillReq, skillName = data.skillReq, data.skillName
                    skillRequirementUnknown = data.skillRequirementUnknown
                    queueAllowed = data.queueAllowed
                    displayName = data.displayName
                    requirementText = data.requirementText
                else
                    cost = data
                end

                local raceMatches = true
                if race and playerRace then
                    if type(race) == "table" then
                        raceMatches = false
                        for _, r in ipairs(race) do
                            if r == playerRace then
                                raceMatches = true
                                break
                            end
                        end
                    else
                        raceMatches = race == playerRace
                    end
                end

                if (not faction or not playerFaction or faction == playerFaction) and raceMatches then
                    local name
                    if type(key) == "number" then
                        spellID = spellID or key
                        name, _, icon = GetSpellInfo(key)
                    else
                        name = key
                    end

                    name = name or ("SpellID " .. tostring(key))
                    if not icon and spellID then
                        local _, _, resolvedIcon = GetSpellInfo(spellID)
                        icon = resolvedIcon
                    end

                    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    local hasRealRank = (type(rank) == "number") or (type(rank) == "string" and rank:match("%d+") ~= nil)
                    local rankNum = (type(rank) == "number" and rank) or (type(rank) == "string" and tonumber(rank:match("%d+"))) or 1
                    local isLearnedPetSpell = spellID and Trainer:IsPetSpellKnown(spellID)
                    local isKnownPlayerSpell = spellID and ns.API and ns.API.IsKnownSpellID
                        and ns.API.IsKnownSpellID(spellID)
                    local directlyKnown = isKnownPlayerSpell or isLearnedPetSpell or status == "used"
                    local entry = {
                        level = lvl,
                        key = key,
                        spellID = spellID,
                        cost = cost,
                        name = name,
                        displayName = displayName,
                        icon = icon,
                        rankNum = rankNum,
                        hasRealRank = hasRealRank,
                        directlyKnown = directlyKnown,
                        -- `requires` is exclusively a list of prerequisite
                        -- spell IDs. Older Skills rows stored text here; filter
                        -- those values at the shared entry boundary.
                        requires = type(requires) == "table" and requires or nil,
                        requirementText = requirementText or (type(requires) == "string" and requires or nil),
                        levelReq = levelReq,
                        source = source,
                        skillReq = skillReq,
                        skillName = skillName,
                        skillRequirementUnknown = skillRequirementUnknown,
                        queueAllowed = queueAllowed,
                    }

                    table.insert(allEntries, entry)
                    if directlyKnown and hasRealRank then knownMaxRank[name] = math.max(knownMaxRank[name] or 0, rankNum) end
                end
            end
        end
        return allEntries, knownMaxRank
    end

    -- Profession rank-up services ("Journeyman Leatherworking", "Apprentice
    -- First Aid") cannot be detected with IsSpellKnown: learning the next rank
    -- replaces the previous one, so every rank reports as unknown and the list
    -- keeps offering ranks the player passed long ago. The authority is the
    -- profession's own max skill -- a Journeyman leatherworker maxes at 150, so
    -- any rank capped at or below that is already trained.
    local PROFESSION_RANK_CAPS = {
        apprentice = 75,
        journeyman = 150,
        expert     = 225,
        artisan    = 300,
    }

    -- Do two names share a leading stem of at least minLen characters?
    -- Rank-up spells are named for the practitioner, not the profession:
    -- Cooking/"Cook", Fishing/"Fisherman", Alchemy/"Alchemist", Mining/"Miner",
    -- Enchanting/"Enchanter", Leatherworking/"Leatherworker". Requiring the
    -- profession name verbatim rejected all of them -- First Aid was the only
    -- profession whose rank spells happen to spell it out, which is why it was
    -- the one that appeared to work.
    --
    -- Three is enough: "Miner"/"Mining" share only "min", and every other pair
    -- shares more. False positives are held off by the rank-word gate below,
    -- not by this length.
    local function SharesStem(a, b, minLen)
        if type(a) ~= "string" or type(b) ~= "string" then return false end
        local limit = math.min(#a, #b)
        if limit < minLen then return false end
        local common = 0
        for i = 1, limit do
            if a:sub(i, i) ~= b:sub(i, i) then break end
            common = common + 1
        end
        return common >= minLen
    end

    -- Returns the skill cap this entry grants, or nil if it is not a rank-up.
    --
    -- Recognised forms:
    --   "Journeyman Cook"      -- rank word + practitioner noun (the usual case)
    --   "Apprentice First Aid" -- rank word + the profession itself
    --   "Cooking"              -- base rank named for the profession, no rank word
    --   name carries no rank word but the spell's subtext does
    --
    -- Recipes are excluded by the rank-word gate: a recipe does not begin with
    -- "Apprentice "/"Journeyman "/"Expert "/"Artisan ". An item that does (say
    -- "Expert Goldminer's Helmet") is then rejected by the stem check, since its
    -- remainder shares no stem with the profession.
    --
    -- Rank words are English. On other locales this returns nil and behaviour
    -- falls back to the previous (imperfect) detection rather than misfiring.
    function Trainer:GetProfessionRankCap(entryName, professionName, spellID)
        if type(professionName) ~= "string" or professionName == "" then return nil end

        -- The stored key can differ from the spell's own name, so consider both.
        local candidates = {}
        if type(entryName) == "string" and entryName ~= "" then candidates[#candidates + 1] = entryName end
        if spellID and GetSpellInfo then
            local spellName = GetSpellInfo(spellID)
            if type(spellName) == "string" and spellName ~= "" and spellName ~= entryName then
                candidates[#candidates + 1] = spellName
            end
        end
        if #candidates == 0 then return nil end

        local lowerProf = professionName:lower()
        for _, candidate in ipairs(candidates) do
            local lowerName = candidate:lower()

            for word, cap in pairs(PROFESSION_RANK_CAPS) do
                local remainder = lowerName:match("^" .. word .. "%s+(.+)$")
                if remainder then
                    -- A rank word whose noun belongs to another profession is
                    -- not this profession's rank.
                    if SharesStem(remainder, lowerProf, 3) then return cap end
                end
            end

            if lowerName == lowerProf then return PROFESSION_RANK_CAPS.apprentice end
        end

        -- Last resort: the name carries no rank word but the spell's subtext may.
        if spellID and GetSpellSubtext then
            local subText = GetSpellSubtext(spellID)
            if type(subText) == "string" and subText ~= "" then
                local lowerSub = subText:lower()
                for word, cap in pairs(PROFESSION_RANK_CAPS) do
                    if lowerSub:find(word, 1, true) then return cap end
                end
            end
        end

        return nil
    end

    function Trainer:ClassifyEntries(dataTable, searchText, selectedLevel, skipTalentCheck, professionKey, queueScope, queueOwner, knownNames, professionName, professionMaxSkill)
        local allEntries, knownMaxRank = Trainer:BuildEntriesFromData(dataTable)
        local talentNames, learnedTalents
        if not skipTalentCheck then talentNames, learnedTalents = Trainer:GetTalentNameSet() end
        local queued, ignored, known, remaining = {}, {}, {}, {}
        for _, entry in ipairs(allEntries) do
            if queueScope and queueOwner then Trainer:PrepareTrainingQueueEntry(entry, queueScope, queueOwner) end
            local maxKnown = knownMaxRank[entry.name] or 0
            local isKnown = entry.directlyKnown
                or (knownNames and (knownNames[entry.spellID] or knownNames[entry.name]))
                or (entry.hasRealRank and entry.rankNum <= maxKnown)

            -- A rank-up the player has already passed. Checked after the normal
            -- paths so it can only ever add knowledge, never take it away.
            if not isKnown and professionName and professionMaxSkill then
                local rankCap = Trainer:GetProfessionRankCap(entry.name, professionName, entry.spellID)
                if rankCap and professionMaxSkill >= rankCap then isKnown = true end
            end
            entry.trainingQueueEligible = entry.queueAllowed ~= false and entry.trainingQueueKey ~= nil and not isKnown
            if entry.trainingQueueKey and Trainer:IsEntryQueued(entry) and (isKnown or entry.queueAllowed == false) then
                Trainer:RemoveEntryFromTrainingQueue(entry)
            end

            if Trainer:EntryMatchesSearch(entry, searchText) then
                local isProfessionIgnored = Trainer.IsProfessionSpellIgnored and Trainer.IsProfessionSpellIgnored(entry.spellID, professionKey)
                local isIgnored = (Trainer.IsIgnored and Trainer.IsIgnored(entry.spellID, entry.name)) or isProfessionIgnored
                if isKnown then
                    if isIgnored then
                        table.insert(ignored, entry)
                    else
                        table.insert(known, entry)
                    end
                elseif entry.trainingQueueKey and Trainer:IsEntryQueued(entry) then
                    table.insert(queued, entry)
                elseif isIgnored then
                    table.insert(ignored, entry)
                else
                    table.insert(remaining, entry)
                end
            end
        end

        local available, missingTalents, future = {}, {}, {}
        local higherSkill = {}
        for _, entry in ipairs(remaining) do
            local looksTalentGated = talentNames and ((talentNames[entry.name] and not learnedTalents[entry.name]) or Trainer:RequiresUnknownTalent(entry, talentNames, learnedTalents))
            if looksTalentGated then
                table.insert(missingTalents, entry)
            elseif entry.skillRequirementUnknown then
                -- The static catalog deliberately leaves some Vanilla trainer
                -- requirements absent instead of guessing from crafting-color
                -- thresholds. Keep those visible, but never claim they are
                -- currently trainable until a live trainer supplies the fact.
                table.insert(higherSkill, entry)
            elseif entry.level > selectedLevel then
                table.insert(future, entry)
            elseif not Trainer:IsSkillRequirementMet(entry) then
                -- Level is met but the profession skill is not. Straight into
                -- `higher` rather than `future`: the soon/higher split keys off
                -- entry.level to build the "Coming soon (Level N)" header, and
                -- these entries are already AT or BELOW the player's level, so
                -- routing them through that path would label them as arriving
                -- at a level already reached.
                table.insert(higherSkill, entry)
            else
                table.insert(available, entry)
            end
        end

        local nextLevel
        for _, entry in ipairs(future) do
            if not nextLevel or entry.level < nextLevel then nextLevel = entry.level end
        end

        local soon, higher = {}, {}
        for _, entry in ipairs(higherSkill) do table.insert(higher, entry) end
        for _, entry in ipairs(future) do
            if entry.level == nextLevel then
                table.insert(soon, entry)
            else
                table.insert(higher, entry)
            end
        end

        table.sort(queued, function(a, b)
            local aOrder = Trainer:GetTrainingQueueOrder(a) or math.huge
            local bOrder = Trainer:GetTrainingQueueOrder(b) or math.huge
            if aOrder ~= bOrder then return aOrder < bOrder end
            if a.level ~= b.level then return a.level < b.level end
            return a.key < b.key
        end)
        Trainer:SortEntries(available)
        Trainer:SortEntries(missingTalents)
        Trainer:SortEntries(ignored)
        Trainer:SortEntries(soon)
        Trainer:SortEntries(higher)
        Trainer:SortEntries(known)
        return {
            queued = queued,
            available = available,
            soon = soon,
            higher = higher,
            missingTalents = missingTalents,
            ignored = ignored,
            known = known,
            nextLevel = nextLevel,
        }
    end

    function Trainer:AppendGroupItems(items, groups, keyPrefix, labelPrefix, unitLabel, showCost)
        local Colors = Trainer.UIColors
        if showCost == nil then showCost = true end
        local entryLevelLabel = unitLabel and unitLabel ~= L.LID_LVL and unitLabel or nil
        unitLabel = unitLabel or L.LID_LVL
        if groups.queued and #groups.queued > 0 then
            Trainer:AddHeaderItem(items, L.LID_TRAININGQUEUE, Colors.QUEUED, showCost and Trainer:SumCost(groups.queued) or nil, keyPrefix .. "queued", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "queued") then Trainer:AddEntryItems(items, groups.queued, Colors.QUEUED, true, showCost, false, entryLevelLabel) end
        end

        if #groups.available > 0 then
            Trainer:AddHeaderItem(items, L.LID_AVAILABLENOW, Colors.AVAILABLE, showCost and Trainer:SumCost(groups.available) or nil, keyPrefix .. "available", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "available") then Trainer:AddEntryItems(items, groups.available, Colors.AVAILABLE, true, showCost, false, entryLevelLabel) end
        end

        if #groups.soon > 0 then
            Trainer:AddHeaderItem(items, ("%s (%s %d)"):format(L.LID_COMINGSOON, unitLabel, groups.nextLevel), Colors.SOON, showCost and Trainer:SumCost(groups.soon) or nil, keyPrefix .. "soon", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "soon") then Trainer:AddEntryItems(items, groups.soon, Colors.SOON, true, showCost, false, entryLevelLabel) end
        end

        if #groups.higher > 0 then
            Trainer:AddHeaderItem(items, L.LID_NOTYETAVAILABLE, Colors.NOTYET, showCost and Trainer:SumCost(groups.higher) or nil, keyPrefix .. "higher", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "higher") then Trainer:AddEntryItems(items, groups.higher, Colors.NOTYET, true, showCost, false, entryLevelLabel) end
        end

        if #groups.missingTalents > 0 then
            Trainer:AddHeaderItem(items, L.LID_MISSINGREQUIREDTALENTS, Colors.TALENT, showCost and Trainer:SumCost(groups.missingTalents) or nil, keyPrefix .. "missingTalents", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "missingTalents") then Trainer:AddEntryItems(items, groups.missingTalents, Colors.TALENT, true, showCost, false, entryLevelLabel) end
        end

        if #groups.ignored > 0 then
            Trainer:AddHeaderItem(items, L.LID_IGNORED, Colors.IGNORED, nil, keyPrefix .. "ignored", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "ignored") then Trainer:AddEntryItems(items, groups.ignored, Colors.IGNORED, true, showCost, true, entryLevelLabel) end
        end

        if #groups.known > 0 then
            Trainer:AddHeaderItem(items, L.LID_ALREADYKNOWN, Colors.KNOWN, showCost and Trainer:SumCost(groups.known) or nil, keyPrefix .. "known", labelPrefix)
            if not Trainer:IsGroupCollapsed(keyPrefix .. "known") then Trainer:AddEntryItems(items, groups.known, Colors.KNOWN, true, showCost, true, entryLevelLabel) end
        end
    end

    local function MergePetData(keys)
        local merged = {}
        for _, key in ipairs(keys) do
            local data = TurboFaceTrainerDB.petData and TurboFaceTrainerDB.petData[key]
            if data then
                for lvl, spells in pairs(data) do
                    merged[lvl] = merged[lvl] or {}
                    for spellID, entryData in pairs(spells) do
                        merged[lvl][spellID] = entryData
                    end
                end
            end
        end
        return merged
    end

    function Trainer:AppendPetAbilities(items, searchText, selectedLevel)
        local Colors = Trainer.UIColors
        local petItems = {}
        for _, petGroup in ipairs(Trainer.PetGroups) do
            local merged = MergePetData(petGroup.keys)
            if next(merged) then
                local groupKey = "pet_" .. table.concat(petGroup.keys, "_")
                local groups = Trainer:ClassifyEntries(merged, searchText, selectedLevel, true)
                local subItems = {}
                Trainer:AppendGroupItems(subItems, groups, groupKey .. "_", petGroup.label)
                if #subItems > 0 then
                    Trainer:AddHeaderItem(petItems, petGroup.label, Colors.PET_HEADER, nil, groupKey)
                    if not Trainer:IsGroupCollapsed(groupKey) then
                        for _, item in ipairs(subItems) do
                            table.insert(petItems, item)
                        end
                    end
                end
            end
        end

        if #petItems > 0 then
            Trainer:AddHeaderItem(items, L.LID_PETTRAINING, Colors.PET_HEADER, nil, "petAbilities")
            if not Trainer:IsGroupCollapsed("petAbilities") then
                for _, item in ipairs(petItems) do
                    table.insert(items, item)
                end
            end
        end
    end

    function Trainer:AppendPetTrainerAbilities(items, searchText, selectedLevel, classToken)
        local petTrainerData = TurboFaceTrainerDB.petTrainerData and TurboFaceTrainerDB.petTrainerData[classToken]
        if not petTrainerData or not next(petTrainerData) then return end
        local groups = Trainer:ClassifyEntries(petTrainerData, searchText, selectedLevel, true)
        local subItems = {}
        Trainer:AppendGroupItems(subItems, groups, "pettrainer_")
        if #subItems == 0 then return end
        Trainer:AddHeaderItem(items, L.LID_PETTRAINING, Trainer.UIColors.PET_HEADER, nil, "petTraining")
        if not Trainer:IsGroupCollapsed("petTraining") then
            for _, item in ipairs(subItems) do
                table.insert(items, item)
            end
        end
    end
end)
