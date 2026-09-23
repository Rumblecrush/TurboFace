local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings

Trainer:AddBuilder(function()
    local scrollBox = Trainer.ClassScrollBox

    local function PullUnavailablePrimaryProfessions(groups)
        local unavailable = {}

        local function Filter(list)
            local kept = {}
            for _, entry in ipairs(list or {}) do
                if Trainer:IsProfessionStarterUnavailable(entry.spellID) then
                    entry.trainingQueueEligible = false
                    if entry.trainingQueueKey and Trainer:IsEntryQueued(entry) then
                        Trainer:RemoveEntryFromTrainingQueue(entry)
                    end
                    unavailable[#unavailable + 1] = entry
                else
                    kept[#kept + 1] = entry
                end
            end
            return kept
        end

        -- The two-primary-profession cap outranks every other display state.
        -- Once the cap is reached, unlearned primary starters are not queueable
        -- and are shown together under Unavailable.
        groups.queued = Filter(groups.queued)
        groups.available = Filter(groups.available)
        groups.soon = Filter(groups.soon)
        groups.higher = Filter(groups.higher)
        groups.missingTalents = Filter(groups.missingTalents)
        groups.ignored = Filter(groups.ignored)
        Trainer:SortEntries(unavailable)
        return unavailable
    end

    local function BuildNotYetAvailable(groups)
        local notYet = {}
        for _, entry in ipairs(groups.soon or {}) do
            notYet[#notYet + 1] = entry
        end
        for _, entry in ipairs(groups.higher or {}) do
            notYet[#notYet + 1] = entry
        end
        Trainer:SortEntries(notYet)
        return notYet
    end

    local function AppendSkillsGroups(items, groups, unavailable, notYet)
        local Colors = Trainer.UIColors

        if groups.queued and #groups.queued > 0 then
            Trainer:AddHeaderItem(items, L.LID_TRAININGQUEUE, Colors.QUEUED, Trainer:SumCost(groups.queued), "spellbookskills_queued")
            if not Trainer:IsGroupCollapsed("spellbookskills_queued") then
                Trainer:AddEntryItems(items, groups.queued, Colors.QUEUED, false, true, false, nil, "levelSkill")
            end
        end

        if #groups.available > 0 then
            Trainer:AddHeaderItem(items, "Available", Colors.AVAILABLE, Trainer:SumCost(groups.available), "spellbookskills_available")
            if not Trainer:IsGroupCollapsed("spellbookskills_available") then
                Trainer:AddEntryItems(items, groups.available, Colors.AVAILABLE, false, true, false, nil, "levelSkill")
            end
        end

        if notYet and #notYet > 0 then
            Trainer:AddHeaderItem(items, L.LID_NOTYETAVAILABLE, Colors.NOTYET, Trainer:SumCost(notYet), "spellbookskills_notyet")
            if not Trainer:IsGroupCollapsed("spellbookskills_notyet") then
                Trainer:AddEntryItems(items, notYet, Colors.NOTYET, false, true, false, nil, "levelSkill")
            end
        end

        if #groups.known > 0 then
            Trainer:AddHeaderItem(items, L.LID_ALREADYKNOWN, Colors.KNOWN, Trainer:SumCost(groups.known), "spellbookskills_known")
            if not Trainer:IsGroupCollapsed("spellbookskills_known") then
                Trainer:AddEntryItems(items, groups.known, Colors.KNOWN, false, true, true, nil, "levelSkill")
            end
        end

        if unavailable and #unavailable > 0 then
            Trainer:AddHeaderItem(items, "Unavailable", Colors.NOTYET, Trainer:SumCost(unavailable), "spellbookskills_unavailable")
            if not Trainer:IsGroupCollapsed("spellbookskills_unavailable") then
                Trainer:AddEntryItems(items, unavailable, Colors.NOTYET, false, true, true, nil, "levelSkill")
            end
        end

        -- Preserve the existing ignore feature without splitting the Skills
        -- catalog by weapon/profession type. Ignored rows remain a status group.
        if #groups.ignored > 0 then
            Trainer:AddHeaderItem(items, L.LID_IGNORED, Colors.IGNORED, nil, "spellbookskills_ignored")
            if not Trainer:IsGroupCollapsed("spellbookskills_ignored") then
                Trainer:AddEntryItems(items, groups.ignored, Colors.IGNORED, false, true, true, nil, "levelSkill")
            end
        end
    end

    function Trainer.RefreshSkillsList()
        if not scrollBox then return end
        local searchText = (Trainer.SearchText or ""):lower()
        local knownProfessions = Trainer:GetKnownProfessionStarterNames()
        local _, classToken = UnitClass("player")
        local items = {}

        -- Skills are a single catalog. Gathering/Fishing rank-ups retain their
        -- real level buckets, while ClassifyEntries also checks their live
        -- profession-skill requirement through ns.Skills. Unlike the class-spell
        -- view, Skills merges `soon` and `higher` into one Not Yet Available
        -- section so players can see future ranks together with their exact
        -- Level / Skill requirements.
        local playerLevel = UnitLevel("player") or 1
        local groups = Trainer:ClassifyEntries(
            Trainer:BuildSpellbookSkillsData(), searchText, playerLevel, true,
            nil, "skills", classToken, knownProfessions
        )
        local unavailable = PullUnavailablePrimaryProfessions(groups)
        local notYet = BuildNotYetAvailable(groups)
        AppendSkillsGroups(items, groups, unavailable, notYet)

        if #items == 0 then Trainer:AddHeaderItem(items, "Nothing to show.", "|cffaaaaaa") end
        local displayItems = Trainer.BuildSpellbookGridItems and Trainer:BuildSpellbookGridItems(items) or items
        scrollBox:SetDataProvider(CreateDataProvider(displayItems), ScrollBoxConstants.RetainScrollPosition)
    end
end)
