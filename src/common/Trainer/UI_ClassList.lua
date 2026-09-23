local _, ns = ...
local Trainer = ns.Trainer

Trainer:AddBuilder(function()
    local classFrame = Trainer.ClassFrame
    local searchBox = CreateFrame("EditBox", "TurboFaceTrainerSearchBox", classFrame, "SearchBoxTemplate")
    Trainer.SearchBox = searchBox
    searchBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", -60, -6)
    searchBox:SetPoint("TOPRIGHT", classFrame, "TOPRIGHT", -10, -6)
    searchBox:SetHeight(20)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        Trainer.SearchText = self:GetText() or ""
        if Trainer.RefreshActiveSpellbookList then
            Trainer.RefreshActiveSpellbookList()
        else
            Trainer.RefreshList()
        end
    end)

    local scrollBox = CreateFrame("Frame", "TurboFaceTrainerScrollBox", classFrame, "WowScrollBoxList")
    Trainer.ClassScrollBox = scrollBox
    scrollBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 6, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -24, 13)
    local listBg = classFrame:CreateTexture("TurboFaceTrainerFrameBackground", "BACKGROUND")
    Trainer.ClassListBackground = listBg
    local nativeInsetBg = Trainer:CreateNativeInsetBackground(classFrame, "TurboFaceTrainerNativeInsetBackground")
    nativeInsetBg:Hide()
    Trainer.ClassNativeInsetBackground = nativeInsetBg
    local scrollBar = CreateFrame("EventFrame", "TurboFaceTrainerScrollBar", classFrame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)
    local scrollView = CreateScrollBoxListLinearView()
    local spellbookSizeBump = Trainer.SpellbookListSizeBump or 0
    local nativeTrainerCards = ns.TrainerProviderUsesSpellbookGrid
        and ns.TrainerProviderUsesSpellbookGrid()
    Trainer.SpellbookColumnCount = Trainer.SpellbookColumnCount or 2
    local spellbookRowSpacing = nativeTrainerCards and 0
        or (Trainer.RowSpacing + (spellbookSizeBump > 0 and 1 or 0))
    scrollView:SetElementExtentCalculator(function(index, elementData)
        local headerHeight = Trainer.HeaderHeight + spellbookSizeBump
        local isHeader = elementData.isHeaderRow or elementData.isHeader
        if isHeader then return index > 1 and (headerHeight + Trainer.HeaderExtraGap) or headerHeight end
        if nativeTrainerCards then return 47 end
        return Trainer.RowHeight + spellbookSizeBump
    end)

    scrollView:SetPadding(6, 0, 0, 0, spellbookRowSpacing)
    if nativeTrainerCards then
        local CARD_GAP = 2
        local MAX_COLUMNS = 4

        local function EnsureGridCells(rowFrame)
            if rowFrame._tfSpellbookCells then return rowFrame._tfSpellbookCells end
            local cells = {}
            for index = 1, MAX_COLUMNS do
                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetFrameLevel((rowFrame:GetFrameLevel() or 0) + 1)
                cell:Hide()
                cells[index] = cell
            end
            rowFrame._tfSpellbookCells = cells
            return cells
        end

        local function LayoutGridRow(rowFrame, elementData)
            local cells = EnsureGridCells(rowFrame)
            local entries = elementData.cells or {}
            local columns = elementData.isHeaderRow and 1
                or math.max(2, math.min(MAX_COLUMNS, elementData.columnCount or 2))
            local rowWidth = rowFrame:GetWidth() or 0
            local cellWidth = math.max(1, (rowWidth - ((columns - 1) * CARD_GAP)) / columns)

            for index, cell in ipairs(cells) do
                cell:Hide()
                cell:ClearAllPoints()
                local entry = entries[index]
                if entry then
                    cell:SetWidth(elementData.isHeaderRow and rowWidth or cellWidth)
                    if index == 1 then
                        cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, 0)
                        cell:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, 0)
                    else
                        cell:SetPoint("TOPLEFT", cells[index - 1], "TOPRIGHT", CARD_GAP, 0)
                        cell:SetPoint("BOTTOMLEFT", cells[index - 1], "BOTTOMRIGHT", CARD_GAP, 0)
                    end
                    cell:Show()
                    Trainer:InitScrollRow(cell, entry, true)
                end
            end
        end

        scrollView:SetElementInitializer("Frame", function(rowFrame, elementData)
            LayoutGridRow(rowFrame, elementData)
        end)

        function Trainer:BuildSpellbookGridItems(items)
            local columns = math.max(2, math.min(MAX_COLUMNS, Trainer.SpellbookColumnCount or 2))
            local rows, pending = {}, {}
            local function FlushCards()
                if #pending == 0 then return end
                rows[#rows + 1] = {cells = pending, columnCount = columns}
                pending = {}
            end
            for _, item in ipairs(items or {}) do
                if item.isHeader then
                    FlushCards()
                    rows[#rows + 1] = {cells = {item}, columnCount = 1, isHeaderRow = true}
                else
                    pending[#pending + 1] = item
                    if #pending == columns then FlushCards() end
                end
            end
            FlushCards()
            return rows
        end

        function Trainer:SetSpellbookColumnCount(columns, refresh)
            columns = columns >= 4 and 4 or 2
            if Trainer.SpellbookColumnCount == columns then return false end
            Trainer.SpellbookColumnCount = columns
            if refresh and classFrame:IsShown() and Trainer.RefreshActiveSpellbookList then
                Trainer.RefreshActiveSpellbookList()
            end
            return true
        end
    else
        scrollView:SetElementInitializer("Frame", function(rowFrame, elementData)
            Trainer:InitScrollRow(rowFrame, elementData, true)
        end)
    end
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, scrollView)

    function Trainer.RefreshList()
        local searchText = (Trainer.SearchText or ""):lower()
        local selectedLevel = UnitLevel("player") or 1
        local selectedClass = select(2, UnitClass("player"))
        -- Defense in depth: the Class Trainer view must never render general
        -- skills even if an old SavedVariables snapshot or a failed trainer
        -- tooltip resolution contaminated the class database.
        if selectedClass and Trainer.ScrubGeneralSkillsFromClassData then
            Trainer:ScrubGeneralSkillsFromClassData(selectedClass)
        end
        local classData = selectedClass and TurboFaceTrainerDB.data and TurboFaceTrainerDB.data[selectedClass]
        local items = {}
        if classData then
            local groups = Trainer:ClassifyEntries(classData, searchText, selectedLevel, false, nil, "class", selectedClass)
            Trainer:AppendGroupItems(items, groups, "")
        end

        if selectedClass == "WARLOCK" then Trainer:AppendPetAbilities(items, searchText, selectedLevel) end
        if selectedClass == "HUNTER" then Trainer:AppendPetTrainerAbilities(items, searchText, selectedLevel, selectedClass) end
        if #items == 0 then
            if not classData then
                Trainer:AddHeaderItem(items, "No data collected for " .. tostring(selectedClass) .. " yet. Visit a trainer.", "|cffff5555")
            else
                Trainer:AddHeaderItem(items, "Nothing to show.", "|cffaaaaaa")
            end
        end

        local displayItems = Trainer.BuildSpellbookGridItems and Trainer:BuildSpellbookGridItems(items) or items
        scrollBox:SetDataProvider(CreateDataProvider(displayItems), ScrollBoxConstants.RetainScrollPosition)
    end

    function Trainer.RefreshActiveSpellbookList()
        if Trainer.SpellbookViewMode == "skills" and Trainer.RefreshSkillsList then
            Trainer.RefreshSkillsList()
        else
            Trainer.RefreshList()
        end
    end

    classFrame:SetScript("OnShow", function(self)
        if not Trainer.tooltipActive then self:Hide(); return end
        if Trainer.SpellbookViewMode ~= "skills" then Trainer:SyncKnownPetSpellsForActivePet() end
        Trainer._classListDirty = false
        Trainer.RefreshActiveSpellbookList()
    end)

    function Trainer:SetClassListEvents(active)
        classFrame:UnregisterEvent("PLAYER_LEVEL_UP")
        classFrame:UnregisterEvent("SPELLS_CHANGED")
        classFrame:UnregisterEvent("SKILL_LINES_CHANGED")
        if active then
            classFrame:RegisterEvent("PLAYER_LEVEL_UP")
            classFrame:RegisterEvent("SPELLS_CHANGED")
            classFrame:RegisterEvent("SKILL_LINES_CHANGED")
        end
    end

    local function HandleClassListEvent(self, event)
        if not Trainer.tooltipActive then return end

        -- Skills.lua can be display-disabled, in which case its own event frame
        -- is dormant. Trainer still consumes its scanner, so keep the shared
        -- cache invalidation even while our panel is hidden; invalidation is
        -- cheap and does not rebuild the Trainer list.
        if event == "SKILL_LINES_CHANGED" and ns.Skills and ns.Skills.Invalidate then
            ns.Skills:Invalidate()
        end

        -- PLAYER_LEVEL_UP used to rebuild the entire captured class/skills data
        -- set and replace the ScrollBox data provider even when the Spellbook
        -- panel was closed. That creates large transient tables/row-provider
        -- garbage exactly on the level-up frame. Hidden panels have no consumer
        -- for that work: OnShow already rebuilds from current level/spell/skill
        -- state, so mark it dirty and remain dormant until actually visible.
        if not self:IsShown() then
            Trainer._classListDirty = true
            return
        end

        Trainer._classListDirty = false
        Trainer.RefreshActiveSpellbookList()
    end

    classFrame:HookScript("OnEvent", function(self, event)
        if event ~= "PLAYER_LEVEL_UP" and event ~= "SPELLS_CHANGED" and event ~= "SKILL_LINES_CHANGED" then return end
        HandleClassListEvent(self, event)
    end)
end)
