local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings
local GetSpellInfo = ns.API.GetSpellInfo
local function BuildCachedSpellIDLookup()
    local _, classToken = UnitClass("player")
    local lookup = {}
    local classData = classToken and TurboFaceTrainerDB.data[classToken]
    if not classData then return lookup end
    for _, spells in pairs(classData) do
        for id, data in pairs(spells) do
            local name = GetSpellInfo(id)
            if name then
                lookup[name] = lookup[name] or {}
                local rankNum = type(data) == "table" and tonumber(data.rank) or 0
                lookup[name][rankNum or 0] = id
            end
        end
    end
    return lookup
end

local function BuildVisibleTrainerIndexList()
    local total = GetNumTrainerServices()
    if TurboFaceTrainerCharDB.character.showIgnoredInTrainer then
        local list = {}
        for i = 1, total do
            table.insert(list, i)
        end
        return list
    end

    local cachedSpellIDs = BuildCachedSpellIDLookup()
    local list = {}
    for i = 1, total do
        local name, subText, category = GetTrainerServiceInfo(i)
        local keep = true
        if category and category ~= "header" and name then
            local rankNum = subText and tonumber(subText:match("%d+")) or 0
            local spellID = cachedSpellIDs[name] and cachedSpellIDs[name][rankNum]
            if not spellID then spellID = Trainer:GetSpellIDForService(i) end
            if Trainer.IsIgnored(spellID, name) then keep = false end
        end

        if keep then table.insert(list, i) end
    end
    return list
end

-- Blizzard's own ClassTrainerFrame_Update, captured before this file replaces
-- the global. See EnsureTrainerUpdateOverrideInstalled below for why the
-- replacement exists and why it is a sanctioned exception to ARCHITECTURE 1.3.
local BlizzardClassTrainerFrame_Update

local function Trainer_ClassTrainerFrame_Update()
    -- PREDICATE GATE (ARCHITECTURE 7.5). Replacing a global cannot be undone,
    -- so a disabled Trainer module must hand the list straight back to Blizzard
    -- instead of continuing to render a filtered view the user turned off.
    -- tooltipActive is the module's existing "currently on" flag, maintained by
    -- both Init() and Refresh().
    if not Trainer.tooltipActive and BlizzardClassTrainerFrame_Update then
        return BlizzardClassTrainerFrame_Update()
    end

    SetPortraitTexture(ClassTrainerFramePortrait, "npc")
    ClassTrainerNameText:SetText(UnitName("npc"))
    ClassTrainerGreetingText:SetText(GetTrainerGreetingText())
    local visibleList = BuildVisibleTrainerIndexList()
    local numTrainerServices = #visibleList
    local skillOffset = FauxScrollFrame_GetOffset(ClassTrainerListScrollFrame)
    if numTrainerServices == 0 then
        ClassTrainerCollapseAllButton:Disable()
    else
        ClassTrainerCollapseAllButton:Enable()
    end

    if not ClassTrainerFrame.selectedService then ClassTrainer_HideSkillDetails() end
    if IsTradeskillTrainer() then
        ClassTrainer_SetToTradeSkillTrainer()
    else
        ClassTrainer_SetToClassTrainer()
    end

    FauxScrollFrame_Update(ClassTrainerListScrollFrame, numTrainerServices, CLASS_TRAINER_SKILLS_DISPLAYED, CLASS_TRAINER_SKILL_HEIGHT, nil, nil, nil, ClassTrainerSkillHighlightFrame, 293, 316)
    ClassTrainerMoneyFrame:Show()
    ClassTrainerSkillHighlightFrame:Hide()
    for i = 1, CLASS_TRAINER_SKILLS_DISPLAYED do
        local skillIndex = visibleList[i + skillOffset]
        local skillButton = _G["ClassTrainerSkill" .. i]
        local serviceName, serviceSubText, serviceType, isExpanded
        local moneyCost
        if skillIndex then
            serviceName, serviceSubText, serviceType, isExpanded = GetTrainerServiceInfo(skillIndex)
            if not serviceName then serviceName = UNKNOWN end
            if ClassTrainerListScrollFrame:IsVisible() then
                skillButton:SetWidth(293)
            else
                skillButton:SetWidth(323)
            end

            local skillSubText = _G["ClassTrainerSkill" .. i .. "SubText"]
            if serviceType == "header" then
                local skillText = _G["ClassTrainerSkill" .. i .. "Text"]
                skillText:SetText(serviceName)
                skillText:SetWidth(0)
                skillButton:SetNormalFontObject("GameFontNormal")
                skillSubText:Hide()
                if isExpanded then
                    skillButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                else
                    skillButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                end

                _G["ClassTrainerSkill" .. i .. "Highlight"]:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
            else
                skillButton:ClearNormalTexture()
                _G["ClassTrainerSkill" .. i .. "Highlight"]:SetTexture("")
                local skillText = _G["ClassTrainerSkill" .. i .. "Text"]
                skillText:SetText("  " .. serviceName)
                if serviceSubText and serviceSubText ~= "" then
                    skillSubText:SetText(format(PARENS_TEMPLATE, serviceSubText))
                    skillSubText:SetPoint("LEFT", "ClassTrainerSkill" .. i .. "Text", "RIGHT", 10, 0)
                    skillSubText:Show()
                    skillText:SetWidth(0)
                else
                    skillSubText:Hide()
                    skillText:SetWidth(SKILL_TEXT_WIDTH)
                end

                local _
                moneyCost, _ = GetTrainerServiceCost(skillIndex)
                if serviceType == "available" then
                    skillButton:SetNormalFontObject("GameFontNormalLeftGreen")
                    ClassTrainer_SetSubTextColor(skillButton, 0, 0.6, 0)
                elseif serviceType == "used" then
                    skillButton:SetNormalFontObject("GameFontDisable")
                    ClassTrainer_SetSubTextColor(skillButton, 0.5, 0.5, 0.5)
                else
                    skillButton:SetNormalFontObject("GameFontNormalLeftRed")
                    ClassTrainer_SetSubTextColor(skillButton, 0.6, 0, 0)
                end
            end

            skillButton:SetID(skillIndex)
            skillButton:Show()
            if ClassTrainerFrame.selectedService and GetTrainerSelectionIndex() == skillIndex then
                ClassTrainerSkillHighlightFrame:SetPoint("TOPLEFT", "ClassTrainerSkill" .. i, "TOPLEFT", 0, 0)
                ClassTrainerSkillHighlightFrame:Show()
                skillButton:LockHighlight()
                ClassTrainer_SetSubTextColor(skillButton, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                if moneyCost and moneyCost > 0 then ClassTrainerCostLabel:Show() end
            else
                skillButton:UnlockHighlight()
            end
        else
            skillButton:Hide()
        end
    end

    local numHeaders = 0
    local notExpanded = 0
    local showDetails = nil
    for i = 1, numTrainerServices do
        local realIndex = visibleList[i]
        local serviceName, _, serviceType, isExpanded = GetTrainerServiceInfo(realIndex)
        if serviceName and serviceType == "header" then
            numHeaders = numHeaders + 1
            if not isExpanded then notExpanded = notExpanded + 1 end
        end

        if ClassTrainerFrame.selectedService and GetTrainerSelectionIndex() == realIndex then showDetails = 1 end
    end

    if showDetails then
        ClassTrainer_ShowSkillDetails()
    else
        ClassTrainer_HideSkillDetails()
    end

    if notExpanded ~= numHeaders then
        ClassTrainerCollapseAllButton.collapsed = nil
        ClassTrainerCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        ClassTrainerCollapseAllButton.collapsed = 1
        ClassTrainerCollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
end

-- SANCTIONED EXCEPTION to ARCHITECTURE 1.3 ("never invoke a Blizzard FrameXML
-- function; hook it"). This replaces the global outright, and the replacement
-- body calls FrameXML directly (ClassTrainer_SetToClassTrainer,
-- FauxScrollFrame_Update, ClassTrainer_ShowSkillDetails, ...). This filtering
-- approach is retained from the MIT-licensed What's Training? lineage; see
-- Licenses/WhatsTraining-MIT.txt:
--
--   * A post-hook cannot do this job cheaply. Blizzard assigns button IDs from
--     the UNFILTERED service offset, so hiding ignored ranks means re-running
--     essentially the whole button loop after Blizzard's pass -- double work,
--     a visible relayout, and no reduction in FrameXML calls.
--   * The blast radius is genuinely small compared with the 12.2 ComboFrame
--     incident: ClassTrainerFrame belongs to the load-on-demand
--     Blizzard_TrainerUI, is not a SecureUnitButton, and trainer interaction is
--     out of combat by definition.
--
-- What would change this decision: any blocked-action or taint report naming
-- ClassTrainer*, or Blizzard giving the trainer list a real filter API. If that
-- happens, start with /console taintLog 2 at an open trainer -- do NOT assume
-- the fault is local to this file (see 12.2).
--
-- The original is captured so the replacement can hand control back when the
-- module is gated off; the global itself stays replaced for the session.
local function HasLegacyTrainerListSurface()
    -- A client may keep the legacy trainer-service API without exposing the
    -- complete Era ClassTrainerFrame XML surface. Data capture is API-driven,
    -- so fail closed unless every object/function required by the replacement
    -- renderer is actually present.
    local requiredObjects = {
        "ClassTrainerFrame", "ClassTrainerFramePortrait",
        "ClassTrainerNameText", "ClassTrainerGreetingText",
        "ClassTrainerListScrollFrame", "ClassTrainerCollapseAllButton",
        "ClassTrainerMoneyFrame", "ClassTrainerSkillHighlightFrame",
        "ClassTrainerCostLabel", "ClassTrainerSkill1",
    }
    for _, name in ipairs(requiredObjects) do
        if rawget(_G, name) == nil then return false end
    end

    local requiredFunctions = {
        "SetPortraitTexture", "FauxScrollFrame_GetOffset",
        "ClassTrainer_HideSkillDetails", "IsTradeskillTrainer",
        "ClassTrainer_SetToTradeSkillTrainer", "ClassTrainer_SetToClassTrainer",
        "FauxScrollFrame_Update", "ClassTrainer_SetSubTextColor",
        "GetTrainerSelectionIndex", "ClassTrainer_ShowSkillDetails",
    }
    for _, name in ipairs(requiredFunctions) do
        if type(rawget(_G, name)) ~= "function" then return false end
    end

    return type(CLASS_TRAINER_SKILLS_DISPLAYED) == "number"
        and type(CLASS_TRAINER_SKILL_HEIGHT) == "number"
        and type(SKILL_TEXT_WIDTH) == "number"
end

local trainerUpdateOverrideInstalled = false
function Trainer:EnsureTrainerUpdateOverrideInstalled()
    if trainerUpdateOverrideInstalled then return true end
    if type(ClassTrainerFrame_Update) ~= "function" then return false end
    if not Trainer.IsIgnored then return false end
    if not HasLegacyTrainerListSurface() then return false end
    trainerUpdateOverrideInstalled = true
    BlizzardClassTrainerFrame_Update = ClassTrainerFrame_Update
    ClassTrainerFrame_Update = Trainer_ClassTrainerFrame_Update
    ClassTrainerFrame_Update()
    return true
end

local trainerFilterHookInstalled = false
function Trainer:EnsureTrainerFilterHookInstalled()
    if trainerFilterHookInstalled then return end
    -- The extra "Ignored" checkbox only has an effect when TurboFace owns the
    -- legacy list renderer. Do not advertise it on a native trainer surface.
    if not trainerUpdateOverrideInstalled then return end
    if not ClassTrainerFrame or not ClassTrainerFrame.FilterDropdown then return end
    trainerFilterHookInstalled = true
    local function IsNativeFilterSelected(filter)
        return GetTrainerServiceTypeFilter(filter)
    end

    local function SetNativeFilterSelected(filter)
        ClassTrainerFrame.filterPending = true
        SetTrainerServiceTypeFilter(filter, not GetTrainerServiceTypeFilter(filter))
    end

    local function IsIgnoredFilterSelected()
        return TurboFaceTrainerCharDB.character.showIgnoredInTrainer
    end

    local function SetIgnoredFilterSelected()
        TurboFaceTrainerCharDB.character.showIgnoredInTrainer = not TurboFaceTrainerCharDB.character.showIgnoredInTrainer
        if ClassTrainerFrame_Update then ClassTrainerFrame_Update() end
    end

    local applyingOwnMenu = false
    local function ApplyOwnMenu()
        applyingOwnMenu = true
        ClassTrainerFrame.FilterDropdown:SetupMenu(function(dropdown, rootDescription)
            rootDescription:SetTag("MENU_TRAINER_FILTER")
            rootDescription:CreateCheckbox(GREEN_FONT_COLOR:WrapTextInColorCode(AVAILABLE), IsNativeFilterSelected, SetNativeFilterSelected, "available")
            rootDescription:CreateCheckbox(RED_FONT_COLOR:WrapTextInColorCode(UNAVAILABLE), IsNativeFilterSelected, SetNativeFilterSelected, "unavailable")
            rootDescription:CreateCheckbox(YELLOW_FONT_COLOR:WrapTextInColorCode(L.LID_IGNORED), IsIgnoredFilterSelected, SetIgnoredFilterSelected)
            rootDescription:CreateCheckbox(GRAY_FONT_COLOR:WrapTextInColorCode(USED), IsNativeFilterSelected, SetNativeFilterSelected, "used")
        end)

        applyingOwnMenu = false
    end

    hooksecurefunc(ClassTrainerFrame.FilterDropdown, "SetupMenu", function()
        if applyingOwnMenu or not Trainer.tooltipActive then return end
        ApplyOwnMenu()
    end)

    ApplyOwnMenu()
end
