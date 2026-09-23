local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings

-- Forever's Player Spells book is a native, pooled, secret-cooldown consumer.
-- TurboFace must never register with its CategoryTabSystem, participate in its
-- layout, or alter a pooled native tab. The Forever adapter below follows the
-- safe What's Training pattern: addon-owned launchers are ordinary children of
-- the TabSystem but never enter its tabs/pool/layout; addon content remains
-- detached on UIParent. Classic/Era keeps the existing integration below.
local ownsEmbeddedSpellbookHost = ns.TrainerProviderOwnsEmbeddedSpellbookHost
    and ns.TrainerProviderOwnsEmbeddedSpellbookHost() or false
local FOREVER_NATIVE_SPELLBOOK = not ownsEmbeddedSpellbookHost

Trainer:AddBuilder(function()
    local classFrame = Trainer.ClassFrame
    local scrollBox = Trainer.ClassScrollBox
    local listBg = Trainer.ClassListBackground
    local nativeInsetBg = Trainer.ClassNativeInsetBackground
    local searchBox = Trainer.SearchBox
    local spellbookUI

    if FOREVER_NATIVE_SPELLBOOK then
        local loader = CreateFrame("Frame", "TurboFaceTrainerSpellbookLoader", UIParent)
        Trainer.SpellbookLoader = loader

        -- TrainerTextures' large top sprite is the parchment underneath the
        -- translucent service-row sprites. UI-Background-Marble (374154) is
        -- the generic dark inset and cannot provide the native card interior.
        local trainerPageLeft = listBg
        local trainerPageRight
        if classFrame.CreateTexture then
            trainerPageRight = classFrame:CreateTexture(
                "TurboFaceTrainerRightPageBackground", "BACKGROUND", nil, -6)
        end
        local function StyleTrainerPage(texture)
            if not (texture and texture.SetTexture) then return end
            texture:SetTexture(404984)
            texture:SetTexCoord(0.00195313, 0.58593750, 0.00195313, 0.65429688)
            if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, 1) end
            if texture.SetBlendMode then texture:SetBlendMode("BLEND") end
        end
        StyleTrainerPage(trainerPageLeft)
        StyleTrainerPage(trainerPageRight)
        if nativeInsetBg.Bg then nativeInsetBg.Bg:Hide() end
        Trainer.ClassNativeTrainerBackground = trainerPageLeft
        Trainer.ClassNativeTrainerRightBackground = trainerPageRight

        local function InitializeForeverDetached()
            local spellBookFrame = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
            if not (spellBookFrame and spellBookFrame.CategoryTabSystem) then return nil end

            local tabSystem = spellBookFrame.CategoryTabSystem
            local nativeWidgets = {}
            local nativeWidgetState = {}
            local customOpen = false
            local closingQueued = false

            local function AddNativeWidget(widget)
                if widget then nativeWidgets[#nativeWidgets + 1] = widget end
            end
            AddNativeWidget(spellBookFrame.PagedSpellsFrame)
            AddNativeWidget(spellBookFrame.SearchBox)
            AddNativeWidget(spellBookFrame.SearchPreviewContainer)
            AddNativeWidget(spellBookFrame.SettingsDropdown)
            AddNativeWidget(spellBookFrame.AssistedCombatRotationSpellFrame)
            AddNativeWidget(spellBookFrame.BookCornerFlipbook)
            AddNativeWidget(spellBookFrame.Bookmark)

            local function PositionFrame()
                local columns = spellBookFrame.isMinimized and 2 or 4
                if Trainer.SetSpellbookColumnCount then
                    Trainer:SetSpellbookColumnCount(columns, false)
                end
                classFrame:SetParent(UIParent)
                classFrame:SetScale(1)
                classFrame:SetFrameStrata("HIGH")
                classFrame:SetFrameLevel(500)
                classFrame:ClearAllPoints()
                local contentBounds = spellBookFrame.PagedSpellsFrame or spellBookFrame
                classFrame:SetPoint("TOPLEFT", contentBounds, "TOPLEFT", 0, -7)
                classFrame:SetPoint("BOTTOMRIGHT", contentBounds, "BOTTOMRIGHT", 0, 0)

                trainerPageLeft:ClearAllPoints()
                if columns == 4 and trainerPageRight then
                    trainerPageLeft:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 0, 0)
                    trainerPageLeft:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOM", -1, 0)
                    trainerPageRight:ClearAllPoints()
                    trainerPageRight:SetPoint("TOPLEFT", classFrame, "TOP", 1, 0)
                    trainerPageRight:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", 0, 0)
                    trainerPageRight:Show()
                else
                    trainerPageLeft:SetAllPoints(classFrame)
                    if trainerPageRight then trainerPageRight:Hide() end
                end
                trainerPageLeft:Show()
                nativeInsetBg:ClearAllPoints()
                nativeInsetBg:SetAllPoints(classFrame)
                nativeInsetBg:Show()

                searchBox:ClearAllPoints()
                searchBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 12, -10)
                searchBox:SetPoint("TOPRIGHT", classFrame, "TOPRIGHT", -12, -10)
                scrollBox:ClearAllPoints()
                scrollBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 8, -38)
                scrollBox:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -24, 13)
            end

            local classIcon = GetFileIDFromPath and GetFileIDFromPath("Interface\\Icons\\INV_Misc_Book_09")
                or "Interface\\Icons\\INV_Misc_Book_09"
            local skillsIcon = GetFileIDFromPath and GetFileIDFromPath("Interface\\Icons\\INV_Sword_04")
                or "Interface\\Icons\\INV_Sword_04"

            local function CreateDetachedTab(name, icon, tooltipText)
                -- SpellBookCategoryTabTemplate:Init() calls through its parent
                -- TabSystem while calculating square-mode width, so it must use
                -- the real TabSystem as its parent. Like What's Training, the
                -- button remains unregistered: it never enters tabs/pool/layout.
                local button = CreateFrame("Button", name, tabSystem, "SpellBookCategoryTabTemplate")
                if button.Init then button:Init(0, nil, icon) end
                button:SetFrameStrata("HIGH")
                button:SetFrameLevel(510)
                button:Hide()
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(tooltipText)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", GameTooltip_Hide)
                button:SetScript("OnHide", GameTooltip_Hide)
                return button
            end

            local classTab = CreateDetachedTab(
                "TurboFaceTrainerSpellbookTab", classIcon, L.LID_CLASSTRAINER)
            local skillsTab = CreateDetachedTab(
                "TurboFaceTrainerSkillsSpellbookTab", skillsIcon, L.LID_SKILLS)
            classTab:SetPoint("LEFT", tabSystem, "RIGHT", 8, 0)
            skillsTab:SetPoint("LEFT", classTab, "RIGHT", 2, 0)

            local function SetDetachedSelection(mode)
                if classTab.SetTabSelected then classTab:SetTabSelected(mode == "class") end
                if skillsTab.SetTabSelected then skillsTab:SetTabSelected(mode == "skills") end
            end

            local function HideNativeContent(captureState)
                for _, widget in ipairs(nativeWidgets) do
                    if captureState then nativeWidgetState[widget] = widget:IsShown() end
                    widget:Hide()
                end
            end

            local function RestoreNativeContent()
                for widget, wasShown in pairs(nativeWidgetState) do
                    widget:SetShown(wasShown)
                    nativeWidgetState[widget] = nil
                end
            end

            local function CloseCustomPage()
                closingQueued = false
                if not customOpen then return end
                customOpen = false
                classFrame:Hide()
                SetDetachedSelection(nil)
                RestoreNativeContent()
            end

            local function QueueCloseCustomPage()
                if not customOpen or closingQueued then return end
                closingQueued = true
                C_Timer.After(0, CloseCustomPage)
            end

            local function OpenCustomPage(mode)
                if InCombatLockdown and InCombatLockdown() then
                    if ns.Chat then ns:Chat("Training", "Cannot change Spellbook pages during combat.") end
                    return
                end
                if not Trainer.tooltipActive then return end
                if not customOpen then
                    customOpen = true
                    HideNativeContent(true)
                else
                    HideNativeContent(false)
                end
                Trainer.SpellbookViewMode = mode
                PositionFrame()
                SetDetachedSelection(mode)
                classFrame:Show()
                if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() end
            end

            classTab:SetScript("OnClick", function()
                if ns.PlayUISound then ns:PlayUISound("pageTurn") end
                OpenCustomPage("class")
            end)
            skillsTab:SetScript("OnClick", function()
                if ns.PlayUISound then ns:PlayUISound("pageTurn") end
                OpenCustomPage("skills")
            end)

            -- Secure post-hooks observe only navigation. The actual restore is
            -- deferred out of Blizzard's tab call stack, and never writes to a
            -- native tab or its selection fields.
            if tabSystem.SetTab then hooksecurefunc(tabSystem, "SetTab", QueueCloseCustomPage) end
            if spellBookFrame.SetTab then hooksecurefunc(spellBookFrame, "SetTab", QueueCloseCustomPage) end
            if spellBookFrame.SetMinimized then
                hooksecurefunc(spellBookFrame, "SetMinimized", function()
                    C_Timer.After(0, function()
                        if not customOpen then return end
                        PositionFrame()
                        if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() end
                    end)
                end)
            end
            spellBookFrame:HookScript("OnShow", function()
                C_Timer.After(0, function()
                    local shown = Trainer.tooltipActive == true and spellBookFrame:IsShown()
                    classTab:SetShown(shown)
                    skillsTab:SetShown(shown)
                    if customOpen then PositionFrame() end
                end)
            end)
            spellBookFrame:HookScript("OnHide", function()
                C_Timer.After(0, function()
                    CloseCustomPage()
                    classTab:Hide()
                    skillsTab:Hide()
                end)
            end)

            local controller = {}
            function controller:SetActive(active)
                local shown = active and spellBookFrame:IsShown()
                classTab:SetShown(shown)
                skillsTab:SetShown(shown)
                if not active then CloseCustomPage() end
            end

            Trainer.ForeverSpellbookFrame = spellBookFrame
            Trainer.ForeverSpellbookTrainingTab = classTab
            Trainer.ForeverSpellbookSkillsTab = skillsTab
            Trainer.ForeverSpellbookDetached = true
            return controller
        end

        local function TryInitializeSpellbook()
            if spellbookUI or not Trainer.tooltipActive then return end
            spellbookUI = InitializeForeverDetached()
            if spellbookUI then
                loader:UnregisterEvent("ADDON_LOADED")
                spellbookUI:SetActive(true)
            end
        end

        loader:SetScript("OnEvent", function(_, event, addonName)
            if event == "ADDON_LOADED" and addonName == "Blizzard_PlayerSpells" then
                TryInitializeSpellbook()
            end
        end)

        function Trainer:RefreshSpellbookUI(active)
            if active then
                if spellbookUI then
                    spellbookUI:SetActive(true)
                else
                    loader:RegisterEvent("ADDON_LOADED")
                    TryInitializeSpellbook()
                end
            else
                loader:UnregisterEvent("ADDON_LOADED")
                if spellbookUI then spellbookUI:SetActive(false) end
                classFrame:Hide()
            end
        end

        Trainer:RefreshSpellbookUI(Trainer.tooltipActive == true)
        return
    end

    -- Forever inherits the modern load-on-demand PlayerSpells hierarchy. Era
    -- exposes the book directly as SpellBookFrame, so keep that path intact.
    local function ResolveSpellBookFrame()
        if PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame then
            return PlayerSpellsFrame.SpellBookFrame, true
        end
        if SpellBookFrame then
            local foreverLayout = SpellBookFrame.CategoryTabSystem ~= nil or SpellBookFrame.SearchBox ~= nil
            return SpellBookFrame, foreverLayout
        end
        return nil, false
    end

    local function PositionLegacyFrame(spellBookFrame)
        classFrame:SetParent(UIParent)
        classFrame:SetFrameStrata("HIGH")
        classFrame:SetFrameLevel(500)
        classFrame:ClearAllPoints()

        if Trainer:IsDragonflightUIEnabled() and DragonflightUISpellBookBG and DragonflightUISpellBookBG:IsShown() then
            nativeInsetBg:Hide()
            listBg:Show()
            listBg:SetPoint("CENTER", classFrame, "CENTER", 0, 0)
            if DragonflightUISpellBookInsetBg then
                local shortHeight = 30
                listBg:ClearAllPoints()
                listBg:SetPoint("TOPLEFT", DragonflightUISpellBookInsetBg, "TOPLEFT", 0, -shortHeight)
                listBg:SetPoint("BOTTOMRIGHT", DragonflightUISpellBookInsetBg, "BOTTOMRIGHT", 0, 0)
                listBg:SetTexture(DragonflightUISpellBookInsetBg:GetTexture())
                local fullHeight = DragonflightUISpellBookInsetBg:GetHeight()
                local cropTop = shortHeight / fullHeight
                listBg:SetTexCoord(0, 1, cropTop, 1)
                listBg:SetVertexColor(0, 0, 0)
            else
                listBg:ClearAllPoints()
                listBg:SetAllPoints(classFrame)
                listBg:SetColorTexture(0, 0, 0, 1)
            end
        else
            listBg:Hide()
            nativeInsetBg:ClearAllPoints()
            nativeInsetBg:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 4, -2)
            nativeInsetBg:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -2, 0)
            nativeInsetBg:Show()
        end

        if spellBookFrame:IsShown() then
            classFrame:SetScale(spellBookFrame:GetScale())
            if Trainer:IsDragonflightUIEnabled() and DragonflightUISpellBookBG and DragonflightUISpellBookBG:IsShown() then
                classFrame:SetPoint("TOPLEFT", spellBookFrame, "TOPLEFT", 4, -50)
                classFrame:SetPoint("BOTTOMRIGHT", spellBookFrame, "BOTTOMRIGHT", -4, 4)
            else
                classFrame:SetPoint("TOPLEFT", spellBookFrame, "TOPLEFT", 14, -70)
                classFrame:SetPoint("BOTTOMRIGHT", spellBookFrame, "BOTTOMRIGHT", -36, 70)
            end
        else
            classFrame:SetScale(1)
            classFrame:SetPoint("CENTER")
        end

        searchBox:ClearAllPoints()
        local titleText = _G["SpellBookTitleText"]
        if titleText and classFrame:GetTop() and titleText:GetBottom() then
            local topOffset = titleText:GetBottom() - classFrame:GetTop() - 4
            searchBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 66, topOffset)
            searchBox:SetPoint("TOPRIGHT", classFrame, "TOPRIGHT", -4, topOffset)
        else
            searchBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 10, -6)
            searchBox:SetPoint("TOPRIGHT", classFrame, "TOPRIGHT", -30, -6)
        end
    end

    local function PositionModernFrame(spellBookFrame)
        -- Parent the custom page to Blizzard's non-secure content frame so it
        -- naturally follows UI scale, maximize/minimize, and panel movement.
        classFrame:SetParent(spellBookFrame)
        classFrame:SetScale(1)
        classFrame:SetFrameStrata(spellBookFrame:GetFrameStrata())
        classFrame:SetFrameLevel((spellBookFrame:GetFrameLevel() or 0) + 25)
        classFrame:ClearAllPoints()
        -- PagedSpellsFrame owns the modern book's real content rectangle: its
        -- top begins below the category strip and its remaining edges reach the
        -- inner book border. Reuse those bounds instead of carrying parchment
        -- title/margin insets from the old embedded panel layout.
        local contentBounds = spellBookFrame.PagedSpellsFrame or spellBookFrame
        classFrame:SetPoint("TOPLEFT", contentBounds, "TOPLEFT", 0, -7)
        classFrame:SetPoint("BOTTOMRIGHT", contentBounds, "BOTTOMRIGHT", 0, 0)

        -- Keep the established list renderer, but fit its controls inside the
        -- modern parchment instead of relying on removed Era title/page globals.
        listBg:Hide()
        nativeInsetBg:ClearAllPoints()
        nativeInsetBg:SetAllPoints(classFrame)
        nativeInsetBg:Show()

        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 12, -10)
        searchBox:SetPoint("TOPRIGHT", classFrame, "TOPRIGHT", -12, -10)

        scrollBox:ClearAllPoints()
        scrollBox:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 8, -38)
        scrollBox:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -24, 13)
    end

    local function OpenFrame(mode, positionFunc, hideNativeFunc, setSelectionFunc)
        if not Trainer.tooltipActive then return end
        Trainer.SpellbookViewMode = mode or "class"
        positionFunc()
        hideNativeFunc()
        if setSelectionFunc then setSelectionFunc(Trainer.SpellbookViewMode) end
        classFrame:Show()
        if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() end
    end

    local function InitializeModern(spellBookFrame)
        if not (spellBookFrame.CategoryTabSystem and spellBookFrame.AddNamedTab
            and spellBookFrame.SetTab and spellBookFrame.GetTab) then
            return false
        end

        local trainingTabID = spellBookFrame:AddNamedTab(L.LID_TRAINING)
        local skillsTabID = spellBookFrame:AddNamedTab(L.LID_SKILLS)
        local tabSystem = spellBookFrame.CategoryTabSystem

        local function GetMaterializedTab(tabID)
            if tabSystem.GetTabButton then
                local ok, button = pcall(tabSystem.GetTabButton, tabSystem, tabID)
                if ok and button then return button end
            end
            return tabSystem.tabs and tabSystem.tabs[tabID] or nil
        end

        -- Forever's transitional TabSystem can return an ID from AddNamedTab
        -- without materializing a matching CategoryTabSystem button. Calling
        -- SetTabShown with that orphan ID is an immediate FrameXML error. Fall
        -- back to our horizontal icon buttons instead.
        if not GetMaterializedTab(trainingTabID) or not GetMaterializedTab(skillsTabID) then
            return false
        end

        local nativeWidgetState = {}
        local nativeWidgets = {}
        local function AddNativeWidget(widget)
            if widget then nativeWidgets[#nativeWidgets + 1] = widget end
        end
        AddNativeWidget(spellBookFrame.PagedSpellsFrame)
        AddNativeWidget(spellBookFrame.SearchBox)
        AddNativeWidget(spellBookFrame.SearchPreviewContainer)
        AddNativeWidget(spellBookFrame.SettingsDropdown)
        AddNativeWidget(spellBookFrame.AssistedCombatRotationSpellFrame)
        AddNativeWidget(spellBookFrame.BookCornerFlipbook)
        AddNativeWidget(spellBookFrame.Bookmark)
        local customOpen = false

        local function SetTabShown(tabID, shown)
            local button = GetMaterializedTab(tabID)
            if not button then return false end
            if tabSystem.SetTabShown then
                tabSystem:SetTabShown(tabID, shown)
                return true
            end
            button:SetShown(shown)
            return true
        end

        local function SetCustomTabsShown(shown)
            SetTabShown(trainingTabID, shown)
            SetTabShown(skillsTabID, shown)
        end

        local function HideNativeContent(captureState)
            for _, widget in ipairs(nativeWidgets) do
                if widget then
                    if captureState then nativeWidgetState[widget] = widget:IsShown() end
                    widget:Hide()
                end
            end
        end

        local function RestoreNativeContent()
            for widget, wasShown in pairs(nativeWidgetState) do
                widget:SetShown(wasShown)
            end
            wipe(nativeWidgetState)
            if spellBookFrame.UpdateAttic then spellBookFrame:UpdateAttic() end
        end

        local function CloseCustomPage()
            if not customOpen then return end
            customOpen = false
            classFrame:Hide()
            RestoreNativeContent()
        end

        local function OpenModernPage(mode)
            if not customOpen then
                customOpen = true
                HideNativeContent(true)
            else
                HideNativeContent(false)
            end
            OpenFrame(
                mode,
                function() PositionModernFrame(spellBookFrame) end,
                function() HideNativeContent(false) end
            )
        end

        local function SyncSelectedTab()
            if not Trainer.tooltipActive then
                CloseCustomPage()
                return
            end
            local tabID = spellBookFrame:GetTab()
            if tabID == trainingTabID then
                OpenModernPage("class")
            elseif tabID == skillsTabID then
                OpenModernPage("skills")
            else
                CloseCustomPage()
            end
        end

        -- Native category buttons route through SetTab. Let Blizzard update its
        -- own TabSystem first, then exchange only the page contents.
        hooksecurefunc(spellBookFrame, "SetTab", SyncSelectedTab)
        if spellBookFrame.UpdateAttic then
            hooksecurefunc(spellBookFrame, "UpdateAttic", function()
                if customOpen and Trainer.tooltipActive then HideNativeContent(false) end
            end)
        end

        spellBookFrame:HookScript("OnShow", function()
            SetCustomTabsShown(Trainer.tooltipActive == true)
            SyncSelectedTab()
        end)
        spellBookFrame:HookScript("OnHide", CloseCustomPage)

        local controller = {}
        function controller:SetActive(active)
            SetCustomTabsShown(active)
            if not active then
                local tabID = spellBookFrame:GetTab()
                if tabID == trainingTabID or tabID == skillsTabID then
                    if spellBookFrame.ResetToFirstAvailableTab then
                        spellBookFrame:ResetToFirstAvailableTab()
                    else
                        CloseCustomPage()
                    end
                else
                    CloseCustomPage()
                end
            elseif spellBookFrame:IsShown() then
                SyncSelectedTab()
            end
        end

        Trainer.ForeverSpellbookTrainingTabID = trainingTabID
        Trainer.ForeverSpellbookSkillsTabID = skillsTabID
        Trainer.ForeverSpellbookFrame = spellBookFrame
        SetCustomTabsShown(Trainer.tooltipActive == true)
        return controller
    end

    local function InitializeLegacy(spellBookFrame, modernLayout)
        local function PositionFrame()
            if modernLayout then PositionModernFrame(spellBookFrame)
            else PositionLegacyFrame(spellBookFrame) end
        end
        hooksecurefunc(spellBookFrame, "SetScale", function()
            if Trainer.tooltipActive and classFrame:IsShown() then PositionFrame() end
        end)

        local nativeExtraWidgets = {
            "SpellBookPageNavigationFrame",
            "SpellBookFrameShowAllSpellRanksCheckbox",
            "ShowAllSpellRanksCheckbox",
        }
        local spellButtonsHidden = false
        local hiddenPageRegions = {}
        local hiddenModernWidgets = {}

        local function HideNativeSpellButtons()
            if spellButtonsHidden then return end
            spellButtonsHidden = true
            for _, name in ipairs(nativeExtraWidgets) do
                local widget = _G[name]
                if widget then widget:Hide() end
            end
            if modernLayout then
                local function HideModernWidget(widget)
                    if widget then
                        hiddenModernWidgets[widget] = widget:IsShown()
                        widget:Hide()
                    end
                end
                HideModernWidget(spellBookFrame.SearchBox)
                HideModernWidget(spellBookFrame.SearchPreviewContainer)
                HideModernWidget(spellBookFrame.SettingsDropdown)
                HideModernWidget(_G.SpellBookFrameSearchBox)
                HideModernWidget(_G.SpellBookSearchBox)
            end
            wipe(hiddenPageRegions)
            for _, region in ipairs({spellBookFrame:GetRegions()}) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    if text and text:find("^Page ") then
                        region:Hide()
                        table.insert(hiddenPageRegions, region)
                    end
                end
            end
        end

        local function ShowNativeSpellButtons()
            if not spellButtonsHidden then return end
            spellButtonsHidden = false
            for _, name in ipairs(nativeExtraWidgets) do
                local widget = _G[name]
                if widget then widget:Show() end
            end
            for _, region in ipairs(hiddenPageRegions) do region:Show() end
            wipe(hiddenPageRegions)
            for widget, wasShown in pairs(hiddenModernWidgets) do widget:SetShown(wasShown) end
            wipe(hiddenModernWidgets)
            if SpellBookFrame_Update then SpellBookFrame_Update() end
        end

        local categoryTabSystem = spellBookFrame.CategoryTabSystem
        local classTab, skillsTab, classTabGlow, skillsTabGlow
        local function GetTabGlow(tabFrame)
            if not tabFrame then return nil end
            for _, region in ipairs({tabFrame:GetRegions()}) do
                if region.GetObjectType and region:GetObjectType() == "Texture"
                    and region.GetDrawLayer and region:GetDrawLayer() == "OVERLAY" then
                    return region
                end
            end
        end

        local function HideNativeSkillTabGlows()
            for i = 1, 8 do
                local glow = GetTabGlow(_G["SpellBookSkillLineTab" .. i])
                if glow then glow:Hide() end
            end
        end

        local function SetCustomGlow(mode)
            if modernLayout then
                local function SetModernSelected(tab, selected)
                    if not tab then return end
                    if tab.SetTabSelected then
                        local ok = pcall(tab.SetTabSelected, tab, selected)
                        if ok then return end
                    end
                    if tab._tfSelection then tab._tfSelection:SetShown(selected) end
                end
                SetModernSelected(classTab, mode == "class")
                SetModernSelected(skillsTab, mode == "skills")
            else
                if classTabGlow then classTabGlow:SetShown(mode == "class") end
                if skillsTabGlow then skillsTabGlow:SetShown(mode == "skills") end
            end
        end

        local function ClearNativeCategorySelection()
            if not (modernLayout and categoryTabSystem and type(categoryTabSystem.tabs) == "table") then return end
            for _, tab in ipairs(categoryTabSystem.tabs) do
                if tab and tab.SetTabSelected then
                    pcall(tab.SetTabSelected, tab, false)
                elseif tab and tab.SetEnabled then
                    tab:SetEnabled(true)
                end
            end
        end

        local function RestoreNativeCategorySelection()
            if not (modernLayout and categoryTabSystem) then return end
            local tabID = spellBookFrame.GetTab and spellBookFrame:GetTab() or nil
            if tabID and categoryTabSystem.SetTabVisuallySelected then
                pcall(categoryTabSystem.SetTabVisuallySelected, categoryTabSystem, tabID)
            elseif tabID and categoryTabSystem.tabs and categoryTabSystem.tabs[tabID]
                and categoryTabSystem.tabs[tabID].SetTabSelected then
                pcall(categoryTabSystem.tabs[tabID].SetTabSelected, categoryTabSystem.tabs[tabID], true)
            end
        end

        local function OpenLegacyPage(mode)
            OpenFrame(mode, PositionFrame, function()
                HideNativeSpellButtons()
                HideNativeSkillTabGlows()
            end, SetCustomGlow)
            -- The Blizzard category remains the TabSystem's selected ID while
            -- our detached page is open. Clear only its visual/disabled state
            -- so clicking that same category (for example General) is a real
            -- user action that can close the custom page.
            ClearNativeCategorySelection()
        end

        local function CreateTrainerTab(name, icon, anchor, tooltipText, mode, yOffset)
            local tabParent = modernLayout and categoryTabSystem or spellBookFrame
            local tabTemplate = modernLayout and categoryTabSystem and categoryTabSystem.tabTemplate or nil
            local tab = CreateFrame("Button", name, tabParent, tabTemplate)
            local glow

            if modernLayout then
                if tab.Init then pcall(tab.Init, tab, -1, "") end
                local nativeWidth = anchor._tfLayoutWidth
                    or (anchor.GetWidth and anchor:GetWidth()) or 48
                local nativeHeight = anchor._tfLayoutHeight
                    or (anchor.GetHeight and anchor:GetHeight()) or 32
                -- Keep the visible text-tab chrome independently sized while a
                -- native-height slot owns its horizontal position and baseline.
                local layoutWidth = anchor._tfLayoutWidth
                    or math.max(44, math.min(52, (nativeWidth or 48) - 2))
                local buttonWidth = 44
                local chromeHeight = 44
                local buttonHeight = chromeHeight
                local layoutHeight = math.max(32, math.min(48, nativeHeight or 32))
                tab._tfButtonWidth = buttonWidth
                tab._tfLayoutWidth = layoutWidth
                tab._tfLayoutHeight = layoutHeight
                tab:SetSize(buttonWidth, buttonHeight)

                -- TabSystemButtonTemplate's frame height does not resize its
                -- atlas-backed chrome: every rotated piece retains its native
                -- 32px height. Resize the actual background/active/highlight
                -- pieces so the top rises while the already-correct bottom edge
                -- stays on the category-row baseline.
                for _, texture in ipairs(tab.RotatedTextures or {}) do
                    if texture.SetHeight then texture:SetHeight(chromeHeight) end
                end
                -- The generic atlas caps are visually lighter than the native
                -- spellbook category border. Widen only the left/right pieces;
                -- the middle pieces continue to stretch between their anchors.
                local chromeCaps = {
                    tab.Left, tab.Right, tab.LeftActive, tab.RightActive,
                    tab.LeftHighlight, tab.RightHighlight,
                }
                for _, texture in ipairs(chromeCaps) do
                    if texture and texture.GetWidth and texture.SetWidth then
                        local capWidth = texture:GetWidth()
                        if capWidth and capWidth > 0 then texture:SetWidth(capWidth + 6) end
                    end
                end

                -- CategoryTabSystem inherits HorizontalLayoutFrame. Participating
                -- children must have a layoutIndex; a manually anchored child
                -- without one is repositioned unpredictably when Blizzard marks
                -- the row dirty (and can land over tab 2/3).
                local anchorLayout = anchor._tfLayoutSlot or anchor
                if anchorLayout.layoutIndex and categoryTabSystem.MarkDirty then
                    local layoutSlot = CreateFrame("Frame", name .. "LayoutSlot", categoryTabSystem)
                    layoutSlot:SetSize(layoutWidth, layoutHeight)
                    layoutSlot.layoutIndex = anchorLayout.layoutIndex + 1
                    layoutSlot:SetFrameLevel(anchor.GetFrameLevel and anchor:GetFrameLevel() or 0)
                    tab:SetParent(layoutSlot)
                    tab:ClearAllPoints()
                    tab:SetPoint("BOTTOM", layoutSlot, "BOTTOM", 0, 0)
                    tab._tfLayoutSlot = layoutSlot
                    tab:SetFrameLevel(layoutSlot:GetFrameLevel() + 10)
                    categoryTabSystem:MarkDirty()
                else
                    tab:SetFrameLevel((anchor.GetFrameLevel and anchor:GetFrameLevel() or 0) + 10)
                    tab:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", categoryTabSystem.spacing or 1, 0)
                end

                if tab.Text then tab.Text:SetText(""); tab.Text:Hide() end
                -- The template center is opaque, so icons must render above it.
                -- Keep them inset from the chrome edges so they do not obscure
                -- the thicker border treatment.
                local iconTexture = tab:CreateTexture(name .. "Icon", "ARTWORK")
                iconTexture:SetSize(32, 32)
                iconTexture:SetPoint("BOTTOM", tab, "BOTTOM", -0.5, 0.5)
                iconTexture:SetTexture(icon)
                iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                tab._tfIcon = iconTexture

                glow = tab:CreateTexture(nil, "OVERLAY")
                glow:SetAllPoints(tab)
                glow:SetTexture(130724)
                glow:SetBlendMode("ADD")
                glow:Hide()
                tab._tfSelection = glow

                if tab.SetTabSelected then pcall(tab.SetTabSelected, tab, false) end
            else
                tab:SetSize(32, 32)
                tab:SetNormalTexture(icon)
                tab:SetHighlightTexture(130718, "ADD")
                local border = tab:CreateTexture(name .. "Border", "BACKGROUND")
                border:SetSize(64, 64)
                border:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
                border:SetTexture(136831)
                glow = tab:CreateTexture(nil, "OVERLAY")
                glow:SetSize(32, 32)
                glow:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
                glow:SetTexture(130724)
                glow:SetBlendMode("ADD")
                glow:Hide()
                tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -34)
            end
            tab:Hide()
            if tab._tfLayoutSlot then tab._tfLayoutSlot:Hide() end
            tab:SetScript("OnClick", function()
                ns:PlayUISound("pageTurn")
                OpenLegacyPage(mode)
            end)
            tab:SetScript("OnEnter", function(sel)
                GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipText)
                GameTooltip:Show()
            end)
            tab:SetScript("OnLeave", GameTooltip_Hide)
            return tab, glow
        end

        local function SetTrainerTabShown(tab, shown)
            tab:SetShown(shown)
            if tab._tfLayoutSlot then tab._tfLayoutSlot:SetShown(shown) end
        end

        local lastNativeTab
        if modernLayout and categoryTabSystem and type(categoryTabSystem.tabs) == "table" then
            for _, candidate in ipairs(categoryTabSystem.tabs) do
                if candidate and (not candidate.IsShown or candidate:IsShown()) then lastNativeTab = candidate end
            end
        end
        if not lastNativeTab then
            for i = 1, 12 do
                local candidate = _G["SpellBookSkillLineTab" .. i]
                if candidate and (not candidate.IsShown or candidate:IsShown()) then lastNativeTab = candidate end
            end
        end
        lastNativeTab = lastNativeTab or _G["SpellBookSkillLineTab5"]
            or _G["SpellBookSkillLineTab4"] or _G["SpellBookSkillLineTab1"] or spellBookFrame
        classTab, classTabGlow = CreateTrainerTab(
            "TurboFaceTrainerSpellbookTab", "Interface\\Icons\\INV_Misc_Book_09",
            lastNativeTab, L.LID_CLASSTRAINER, "class"
        )
        skillsTab, skillsTabGlow = CreateTrainerTab(
            "TurboFaceTrainerSkillsSpellbookTab", "Interface\\Icons\\INV_Sword_04",
            classTab, L.LID_SKILLS, "skills", -16
        )

        spellBookFrame:HookScript("OnShow", function()
            SetTrainerTabShown(classTab, Trainer.tooltipActive == true)
            SetTrainerTabShown(skillsTab, Trainer.tooltipActive == true)
            if categoryTabSystem and categoryTabSystem.MarkDirty then categoryTabSystem:MarkDirty() end
            if Trainer.tooltipActive then classTab:Raise(); skillsTab:Raise() end
        end)
        spellBookFrame:HookScript("OnHide", function()
            SetTrainerTabShown(classTab, false)
            SetTrainerTabShown(skillsTab, false)
            if categoryTabSystem and categoryTabSystem.MarkDirty then categoryTabSystem:MarkDirty() end
            classFrame:Hide()
            ShowNativeSpellButtons()
            SetCustomGlow(nil)
            RestoreNativeCategorySelection()
        end)

        local function OnNativeTabClicked()
            if not Trainer.tooltipActive or not classFrame:IsShown() then return end
            classFrame:Hide()
            ShowNativeSpellButtons()
            SetCustomGlow(nil)
            RestoreNativeCategorySelection()
        end
        -- Forever's retail-derived categories are pooled TabSystem buttons, not
        -- the old SpellBookSkillLineTab globals. Cover both direct clicks and
        -- programmatic/native SetTab changes so a Blizzard category can never
        -- leave the Training or Skills page layered over it.
        if modernLayout and categoryTabSystem and type(categoryTabSystem.tabs) == "table" then
            for _, tab in ipairs(categoryTabSystem.tabs) do
                if tab and tab.HookScript then tab:HookScript("OnClick", OnNativeTabClicked) end
            end
        end
        if modernLayout and spellBookFrame.SetTab then
            hooksecurefunc(spellBookFrame, "SetTab", OnNativeTabClicked)
        end
        for i = 1, 12 do
            local tab = _G["SpellBookSkillLineTab" .. i]
            if tab then tab:HookScript("OnClick", OnNativeTabClicked) end
        end
        for i = 1, 3 do
            local tab = _G["SpellBookFrameTabButton" .. i]
            if tab then tab:HookScript("OnClick", OnNativeTabClicked) end
        end
        C_Timer.After(4, function()
            for i = 1, 4 do
                local tab = _G["DragonflightUISpellBookFrameTabButton" .. i]
                if tab then tab:HookScript("OnClick", OnNativeTabClicked) end
            end
        end)

        local controller = {}
        function controller:SetActive(active)
            if active and spellBookFrame:IsShown() then
                SetTrainerTabShown(classTab, true)
                SetTrainerTabShown(skillsTab, true)
            else
                SetTrainerTabShown(classTab, false)
                SetTrainerTabShown(skillsTab, false)
                classFrame:Hide()
                ShowNativeSpellButtons()
                SetCustomGlow(nil)
                RestoreNativeCategorySelection()
            end
            if categoryTabSystem and categoryTabSystem.MarkDirty then categoryTabSystem:MarkDirty() end
        end
        return controller
    end

    local loader = CreateFrame("Frame", "TurboFaceTrainerSpellbookLoader", UIParent)
    Trainer.SpellbookLoader = loader

    local function TryInitializeSpellbook()
        if spellbookUI or not Trainer.tooltipActive then return end
        local spellBookFrame, modern = ResolveSpellBookFrame()
        if not spellBookFrame then return end
        -- Build 69913's transitional AddNamedTab mutates an existing category
        -- label without adding a CategoryTabSystem.tabs entry. Use detached
        -- horizontal icon buttons on that exact build; keep the native route
        -- available for later retail-derived builds where it is well-formed.
        local brokenForeverTabSystem = ns.TrainerProviderOwnsEmbeddedSpellbookHost
            and not ns.TrainerProviderOwnsEmbeddedSpellbookHost()
        if modern and not brokenForeverTabSystem then spellbookUI = InitializeModern(spellBookFrame) end
        if not spellbookUI then spellbookUI = InitializeLegacy(spellBookFrame, modern) end
        if spellbookUI then
            loader:UnregisterEvent("ADDON_LOADED")
            spellbookUI:SetActive(true)
        end
    end

    loader:SetScript("OnEvent", function(_, event, addonName)
        if event ~= "ADDON_LOADED" then return end
        if addonName == "Blizzard_PlayerSpells" or addonName == "Blizzard_SpellBookUI"
            or addonName == "Blizzard_TalentUI" then
            TryInitializeSpellbook()
        end
    end)

    function Trainer:RefreshSpellbookUI(active)
        if active then
            if spellbookUI then
                spellbookUI:SetActive(true)
            else
                loader:RegisterEvent("ADDON_LOADED")
                TryInitializeSpellbook()
            end
        else
            loader:UnregisterEvent("ADDON_LOADED")
            if spellbookUI then spellbookUI:SetActive(false) end
            classFrame:Hide()
        end
    end

    Trainer:RefreshSpellbookUI(Trainer.tooltipActive == true)
end)
