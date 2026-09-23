local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellSubtext = ns.API.GetSpellSubtext

Trainer:AddBuilder(function()
    local classFrame = CreateFrame("Frame", "TurboFaceTrainerFrame", UIParent)
    classFrame:SetSize(420, 480)
    classFrame:SetPoint("CENTER")
    classFrame:SetFrameStrata("HIGH")
    classFrame:SetFrameLevel(500)
    -- The Class Trainer and Skills views replace the spellbook page while
    -- open. The frame must own mouse input so gaps between rows cannot click
    -- Blizzard spell buttons hidden underneath the opaque custom panel.
    classFrame:EnableMouse(true)
    classFrame:Hide()
    Trainer.ClassFrame = classFrame

    -- Match the former inset's structure with Blizzard's reusable Classic Era
    -- inset: a tiled UI-Background-Marble interior and its native NineSlice
    -- border. The artwork stays in the game client and is not redistributed.
    function Trainer:CreateNativeInsetBackground(parent, name)
        local background = CreateFrame("Frame", name, parent, "InsetFrameTemplate")
        background:SetFrameLevel(parent:GetFrameLevel())
        background:EnableMouse(false)
        return background
    end

    Trainer.RowSpacing = 0.5
    Trainer.HeaderExtraGap = 12
    Trainer.SpellbookListSizeBump = ns.TrainerProviderSpellbookListSizeBump
        and ns.TrainerProviderSpellbookListSizeBump() or 0
    local MAX_ICON_SIZE = 32
    Trainer.HeaderHeight = 16
    local trainerFontPath, trainerBaseFontSize, trainerFontFlags = GameFontHighlightSmall:GetFont()
    local trainerRowFontSize = trainerBaseFontSize + 2
    local trainerRankFontSize = math.max(1, trainerRowFontSize - 2)
    local trainerHeaderFontSize = trainerBaseFontSize + 4
    Trainer.RowHeight = 20
    Trainer.UIColors = {
        QUEUED = "|cffffd100",
        AVAILABLE = "|cff30d030",
        SOON = "|cff4db8ff",
        NOTYET = "|cffff4444",
        TALENT = "|cffff9933",
        KNOWN = "|cff888888",
        IGNORED = "|cff666666",
        PET_HEADER = "|cffcc66ff",
        SKILL_HEADER = "|cff66ccff",
        SPELL_NAME = "|cffffffff",
        DIM_NAME = "|cff999999",
        RANK = "|cffaaaaaa",
        REQUIREMENT_MET = "|cffffd100",
        REQUIREMENT_UNMET = "|cffff4444",
        COLLAPSE_EXPANDED = "|cffffffff-|r ",
        COLLAPSE_COLLAPSED = "|cffffffff+|r ",
    }

    Trainer.PetGroups = {
        {
            label = Trainer:GetPetNameById(688),
            keys = {"Imp"}
        },
        {
            label = Trainer:GetPetNameById(697),
            keys = {"Voidwalker"}
        },
        {
            label = Trainer:GetPetNameById(712),
            keys = {"Succubus", "Incubus"}
        },
        {
            label = Trainer:GetPetNameById(691),
            keys = {"Felhunter"}
        },
        {
            label = Trainer:GetPetNameById(30146),
            keys = {"Felguard"}
        },
    }

    function Trainer:IsDragonflightUIEnabled()
        return Trainer:IsAddonLoaded("DragonflightUI")
    end

    function Trainer:IsLeatrixWideProfessionEnabled()
        return Trainer:IsAddonLoaded("Leatrix_Plus") and LeaPlusDB and LeaPlusDB["EnhanceProfessions"] == "On"
    end

    function Trainer:IsGroupCollapsed(groupKey)
        return groupKey and TurboFaceTrainerCharDB.character and TurboFaceTrainerCharDB.character.collapsedGroups[groupKey] or false
    end

    local function ToggleGroup(groupKey)
        if not groupKey or not TurboFaceTrainerCharDB.character then return end
        TurboFaceTrainerCharDB.character.collapsedGroups[groupKey] = not TurboFaceTrainerCharDB.character.collapsedGroups[groupKey] or nil
    end

    local function GetLevelDiffColorCode(level)
        if GetQuestDifficultyColor then
            local r, g, b = GetQuestDifficultyColor(level)
            if type(r) == "table" then r, g, b = r.r, r.g, r.b end
            if r then return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end
        end
        return Trainer.UIColors.RANK
    end

    function Trainer:GetTalentNameSet()
        local names, learned = {}, {}
        if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
            for tab = 1, GetNumTalentTabs() do
                for i = 1, GetNumTalents(tab) do
                    local talentName, _, _, _, rank = GetTalentInfo(tab, i)
                    if talentName then
                        names[talentName] = true
                        if (rank or 0) > 0 then learned[talentName] = true end
                    end
                end
            end
        end
        return names, learned
    end

    function Trainer:GetPlayerFaction()
        return UnitFactionGroup and UnitFactionGroup("player")
    end

    function Trainer:GetPlayerRace()
        if not UnitRace then return nil end
        local _, englishRace = UnitRace("player")
        return englishRace
    end

    local function IsReqSpellKnown(spellID)
        if not IsPlayerSpell or type(spellID) ~= "number" then return false end
        local ok, known = pcall(IsPlayerSpell, spellID)
        return ok and known or false
    end

    function Trainer:RequiresUnknownTalent(entry, talentNames, learnedTalents)
        if type(entry.requires) ~= "table" then return false end
        for _, reqSpellID in ipairs(entry.requires) do
            local reqName = GetSpellInfo(reqSpellID)
            if reqName and talentNames[reqName] and not learnedTalents[reqName] and not IsReqSpellKnown(reqSpellID) then return true end
        end
        return false
    end

    local function FormatCost(copper)
        if not copper or copper == 0 then return L.LID_FREE end
        return ns.API.FormatMoney(copper)
    end

    local function FormatOwnedMoney()
        return ns.API.FormatMoney(GetMoney() or 0)
    end

    local function GetLocalizedRankText(spellID)
        local subtext = GetSpellSubtext and spellID and GetSpellSubtext(spellID)
        return (subtext and subtext ~= "") and subtext or nil
    end

    function Trainer:EntryMatchesSearch(entry, search)
        if not search or search == "" then return true end
        if entry.name and entry.name:lower():find(search, 1, true) then return true end
        if entry.level and tostring(entry.level):find(search, 1, true) then return true end
        if entry.levelReq and tostring(entry.levelReq):find(search, 1, true) then return true end
        return false
    end

    function Trainer:SortEntries(list)
        table.sort(list, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.key < b.key
        end)
    end

    local ignoreMenuFrame = CreateFrame("Frame", "TurboFaceTrainerIgnoreMenu", UIParent, "UIDropDownMenuTemplate")
    local ignoreMenuEntry
    local function IgnoreMenu_Initialize(sel, level)
        local entry = ignoreMenuEntry
        if not entry then return end
        local isProfessionSpell = false
        local professionKey
        if entry.trainingQueueScope == "profession" and entry.trainingQueueOwner then
            professionKey = entry.trainingQueueOwner
            isProfessionSpell = true
        elseif entry.spellID and GetTradeSkillLine then
            local skillLine = GetTradeSkillLine()
            if skillLine then
                professionKey = Trainer:GetProfessionKey(skillLine)
                if professionKey then isProfessionSpell = true end
            end
        end

        local rankSubtext = GetLocalizedRankText(entry.spellID)
        local rankText = rankSubtext and (" " .. rankSubtext) or ""
        local info = UIDropDownMenu_CreateInfo()
        info.text = (entry.displayName or entry.name) .. rankText
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        if entry.trainingQueueKey and entry.trainingQueueEligible then
            local queued = Trainer:IsEntryQueued(entry)
            info = UIDropDownMenu_CreateInfo()
            info.text = queued and L.LID_REMOVEAUTOTRAIN or L.LID_QUEUEAUTOTRAIN
            info.notCheckable = true
            info.func = function() Trainer:ToggleTrainingQueue(entry) end
            UIDropDownMenu_AddButton(info, level)

            if queued then
                info = UIDropDownMenu_CreateInfo()
                info.text = L.LID_MOVEQUEUEUP
                info.notCheckable = true
                info.disabled = not Trainer:CanMoveTrainingQueueEntry(entry, -1)
                info.func = function() Trainer:MoveTrainingQueueEntry(entry, -1) end
                UIDropDownMenu_AddButton(info, level)

                info = UIDropDownMenu_CreateInfo()
                info.text = L.LID_MOVEQUEUEDOWN
                info.notCheckable = true
                info.disabled = not Trainer:CanMoveTrainingQueueEntry(entry, 1)
                info.func = function() Trainer:MoveTrainingQueueEntry(entry, 1) end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        if isProfessionSpell then
            local spellIgnored = Trainer.IsProfessionSpellIgnored and Trainer.IsProfessionSpellIgnored(entry.spellID, professionKey)
            info = UIDropDownMenu_CreateInfo()
            local isRecipeView = Trainer.IsProfessionRecipeViewActive and Trainer:IsProfessionRecipeViewActive()
            if isRecipeView then
                info.text = spellIgnored and L.LID_STOPIGNORINGTHISRECIPE or L.LID_IGNORINGTHISRECIPE
            else
                info.text = spellIgnored and L.LID_STOPIGNORINGTHISSKILL or L.LID_IGNORINGTHISSKILL
            end

            info.notCheckable = true
            info.func = function()
                Trainer.ToggleIgnoreProfessionSpell(entry.spellID, professionKey)
                Trainer.ProfessionRefresh()
            end

            UIDropDownMenu_AddButton(info, level)
        else
            local spellIgnored = Trainer.IsSpellIgnored and Trainer.IsSpellIgnored(entry.spellID)
            local nameIgnored = Trainer.IsNameIgnored and Trainer.IsNameIgnored(entry.name)
            info = UIDropDownMenu_CreateInfo()
            info.text = spellIgnored and L.LID_STOPIGNORINGTHISRANK or L.LID_IGNORINGTHISRANK
            info.notCheckable = true
            info.func = function()
                Trainer.ToggleIgnoreSpell(entry.spellID)
                if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() else Trainer.RefreshList() end
            end

            UIDropDownMenu_AddButton(info, level)
            info = UIDropDownMenu_CreateInfo()
            info.text = nameIgnored and L.LID_STOPIGNOREINGALLRANKS or L.LID_IGNOREALLRANKS
            info.notCheckable = true
            info.func = function()
                Trainer.ToggleIgnoreName(entry.name)
                if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() else Trainer.RefreshList() end
            end

            UIDropDownMenu_AddButton(info, level)
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = L.LID_CANCEL
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(ignoreMenuFrame, IgnoreMenu_Initialize, "MENU")
    function Trainer:ShowIgnoreMenu(anchor, entry)
        ignoreMenuEntry = entry
        ToggleDropDownMenu(1, nil, ignoreMenuFrame, "cursor", 0, 0)
        if DropDownList1 then
            DropDownList1:SetFrameStrata("TOOLTIP")
            DropDownList1:SetFrameLevel(600)
        end
    end

    local pendingSpellTooltipExtra
    local function OnTrainerSpellTooltip(tooltip, tooltipData)
        if tooltip ~= GameTooltip or not Trainer.tooltipActive then return end
        local extra = pendingSpellTooltipExtra
        if not extra then return end

        local spellID = tooltipData and tooltipData.id
        if ns.API.CanAccessValue and not ns.API.CanAccessValue(spellID) then spellID = nil end
        if spellID == nil and tooltip.GetSpell then
            local ok, _, fallbackID = pcall(tooltip.GetSpell, tooltip)
            if ok then spellID = fallbackID end
        end
        if spellID ~= extra.spellID then return end

        if extra.showCost then
            local canAfford = not extra.cost or extra.cost == 0 or (GetMoney() or 0) >= extra.cost
            local costColor = canAfford and "|cffffffff" or "|cffff3333"
            tooltip:AddLine(L.LID_COSTS .. ": " .. costColor .. FormatCost(extra.cost) .. "|r", 1, 1, 1)
            tooltip:AddLine(L.LID_OWNGOLD .. ": " .. FormatOwnedMoney(), 1, 1, 1)
        end

        if extra.source then tooltip:AddLine(L.LID_SOURCE .. ": " .. extra.source, 0.9, 0.9, 0.9, true) end
        tooltip:Show()
    end

    -- OnTooltipSetSpell/OnTooltipSetItem are Classic-only widget scripts on the
    -- modern tooltip system used by Forever. Prefer TooltipDataProcessor there;
    -- retain the native Classic hook as a fallback for Era.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnTrainerSpellTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetSpell", OnTrainerSpellTooltip)
    end

    function Trainer:InitScrollRow(rowFrame, elementData, useSpellbookSizing)
        local Colors = Trainer.UIColors
        local sizeBump = useSpellbookSizing and Trainer.SpellbookListSizeBump or 0
        local nativeTrainerCard = useSpellbookSizing
            and ns.TrainerProviderUsesNativeTrainerCards
            and ns.TrainerProviderUsesNativeTrainerCards()
        if not rowFrame.icon then
            if nativeTrainerCard then
                -- Forever's live ClassTrainerServiceButton probe (build 69913):
                -- texture 404984, 301x47. GetTexCoord returns transformed
                -- corners, so these legacy bounds are derived as
                -- left=ulX, right=urX, top=ulY, bottom=llY. The rounded border
                -- is baked into each sprite and stretches with the card.
                local normal = rowFrame:CreateTexture(nil, "ARTWORK", nil, 0)
                normal:SetAllPoints(rowFrame)
                normal:SetTexture(404984)
                normal:SetTexCoord(0.0020, 0.5742, 0.6582, 0.7500)
                rowFrame.nativeTrainerNormal = normal

                local selected = rowFrame:CreateTexture(nil, "OVERLAY", nil, 1)
                selected:SetAllPoints(rowFrame)
                selected:SetTexture(404984)
                selected:SetTexCoord(0.0020, 0.5742, 0.8496, 0.9414)
                selected:SetBlendMode("ADD")
                selected:Hide()
                rowFrame.nativeTrainerSelected = selected

                local highlight = rowFrame:CreateTexture(nil, "HIGHLIGHT", nil, 0)
                highlight:SetAllPoints(rowFrame)
                highlight:SetTexture(404984)
                highlight:SetTexCoord(0.0020, 0.5742, 0.7539, 0.8457)
                highlight:SetBlendMode("ADD")
                highlight:Hide()
                rowFrame.nativeTrainerHighlight = highlight
            end
            local icon = rowFrame:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("LEFT", rowFrame, "LEFT", 4, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rowFrame.icon = icon
            local nameFS = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            rowFrame.nameFS = nameFS
            local rankFS = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rankFS:SetJustifyH("LEFT")
            rankFS:SetWordWrap(false)
            rowFrame.rankFS = rankFS
            local levelFS = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            levelFS:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
            levelFS:SetJustifyH("RIGHT")
            rowFrame.levelFS = levelFS
            if nativeTrainerCard then
                local costFS = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                costFS:SetJustifyH("RIGHT")
                costFS:SetWordWrap(false)
                rowFrame.costFS = costFS
            end
        end

        local icon, nameFS, rankFS, levelFS = rowFrame.icon, rowFrame.nameFS, rowFrame.rankFS, rowFrame.levelFS
        local iconSize = nativeTrainerCard and 36
            or math.max(8, math.min(MAX_ICON_SIZE + sizeBump, (rowFrame:GetHeight() or Trainer.RowHeight) - 4))
        icon:SetSize(iconSize, iconSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", rowFrame, "LEFT", nativeTrainerCard and 6 or 4, 0)
        rowFrame:EnableMouse(false)
        rowFrame:SetScript("OnEnter", nil)
        rowFrame:SetScript("OnLeave", nil)
        rowFrame:SetScript("OnMouseUp", nil)
        icon:Show()
        icon:SetTexture(nil)
        -- ScrollBox rows are pooled and can be rebound to a different group.
        -- Never inherit a gray/tinted icon presentation from an earlier entry
        -- (or from template/native code touching the texture between binds).
        -- Availability is communicated by the card group and requirement text;
        -- an Available Now icon must always render at its authored color.
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
        nameFS:ClearAllPoints()
        nameFS:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetText("")
        nameFS:Show()
        rankFS:ClearAllPoints()
        rankFS:SetText("")
        rankFS:Hide()
        levelFS:ClearAllPoints()
        levelFS:SetPoint("RIGHT", rowFrame, "RIGHT", -4, 0)
        levelFS:SetJustifyH("RIGHT")
        levelFS:SetText("")
        levelFS:Show()
        if rowFrame.costFS then rowFrame.costFS:SetText(""); rowFrame.costFS:Hide() end
        if rowFrame.nativeTrainerNormal then rowFrame.nativeTrainerNormal:Hide() end
        if rowFrame.nativeTrainerSelected then rowFrame.nativeTrainerSelected:Hide() end
        if rowFrame.nativeTrainerHighlight then rowFrame.nativeTrainerHighlight:Hide() end
        if elementData.isHeader then
            nameFS:SetFont(trainerFontPath, trainerHeaderFontSize + sizeBump, trainerFontFlags)
            icon:Hide()
            nameFS:ClearAllPoints()
            nameFS:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 4, 5)
            nameFS:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -4, 5)
            nameFS:SetJustifyH("CENTER")
            local collapseIcon = elementData.groupKey and (elementData.collapsed and Colors.COLLAPSE_COLLAPSED or Colors.COLLAPSE_EXPANDED) or ""
            local prefix = elementData.prefixText and (Colors.PET_HEADER .. "[" .. elementData.prefixText .. "] |r") or ""
            nameFS:SetText(collapseIcon .. prefix .. elementData.color .. elementData.text .. "|r")
            if elementData.totalCost or elementData.groupKey then
                rowFrame:EnableMouse(true)
                rowFrame:SetScript("OnEnter", function(sel)
                    if not elementData.totalCost then return end
                    GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(elementData.text)
                    local canAfford = elementData.totalCost == 0 or (GetMoney() or 0) >= elementData.totalCost
                    local costColor = canAfford and "|cffffffff" or "|cffff3333"
                    GameTooltip:AddLine(L.LID_TOTALCOST .. ": " .. costColor .. FormatCost(elementData.totalCost) .. "|r", 1, 1, 1)
                    GameTooltip:AddLine(L.LID_OWNGOLD .. ": " .. FormatOwnedMoney(), 1, 1, 1)
                    GameTooltip:Show()
                end)

                rowFrame:SetScript("OnLeave", GameTooltip_Hide)
                rowFrame:SetScript("OnMouseUp", function(sel, button)
                    if button == "LeftButton" and elementData.groupKey then
                        ToggleGroup(elementData.groupKey)
                        if Trainer.RefreshActiveSpellbookList then
                            Trainer.RefreshActiveSpellbookList()
                        elseif Trainer.RefreshList then
                            Trainer.RefreshList()
                        end
                        if Trainer.ProfessionRefresh then Trainer.ProfessionRefresh() end
                    end
                end)
            end
        else
            nameFS:SetFont(trainerFontPath, nativeTrainerCard and 12 or (trainerRowFontSize + sizeBump), trainerFontFlags)
            rankFS:SetFont(trainerFontPath, nativeTrainerCard and 10 or (trainerRankFontSize + sizeBump), trainerFontFlags)
            levelFS:SetFont(trainerFontPath, nativeTrainerCard and 10 or (trainerRowFontSize + sizeBump), trainerFontFlags)
            local entry = elementData.entry
            icon:SetTexture(entry.icon)
            if icon.SetDesaturated then icon:SetDesaturated(false) end
            if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
            local rankSubtext = GetLocalizedRankText(entry.spellID)
            local nameColor
            if nativeTrainerCard then
                nameColor = elementData.dimName and Colors.DIM_NAME or "|cffffd100"
                rowFrame.nativeTrainerNormal:Show()
                rowFrame.nativeTrainerSelected:SetShown(entry.trainingQueueKey ~= nil
                    and Trainer:IsEntryQueued(entry))
            else
                nameColor = elementData.dimName and Colors.DIM_NAME or Colors.SPELL_NAME
            end
            nameFS:SetText(nameColor .. (entry.displayName or entry.name) .. "|r")
            if rankSubtext then
                rankFS:SetText(" " .. Colors.RANK .. "(" .. rankSubtext .. ")|r")
                rankFS:Show()
            end
            if nativeTrainerCard then
                local requirements = {}
                local isWeaponSkill = Trainer.IsWeaponSkillSpell
                    and Trainer:IsWeaponSkillSpell(entry.spellID)
                local playerLevel = UnitLevel("player") or 1
                local skillReq = tonumber(entry.skillReq)
                -- `entry.level` is the outer grouping bucket. For profession
                -- lists that bucket is a skill value (levelLabel="Skill"), not
                -- a character level. Only class-style rows may use it as the
                -- legacy fallback when no explicit requirement exists.
                local levelReq = tonumber(entry.levelReq)
                if not levelReq and not skillReq and elementData.showLevel
                    and not elementData.levelLabel then
                    levelReq = tonumber(entry.level)
                end
                if levelReq and levelReq > 1 then
                    local color = playerLevel >= levelReq and "|cffffffff" or Colors.REQUIREMENT_UNMET
                    requirements[#requirements + 1] = "Level " .. color .. levelReq .. "|r"
                end
                if skillReq and skillReq > 0 then
                    local skillMet = Trainer:IsSkillRequirementMet(entry)
                    local color = skillMet and "|cffffffff" or Colors.REQUIREMENT_UNMET
                    local skillLabel = entry.skillName or L.LID_SKILL
                    requirements[#requirements + 1] = color .. skillLabel
                        .. " (" .. skillReq .. ")|r"
                end
                local requiredSpells = type(entry.requires) == "table" and entry.requires or {}
                for _, requiredSpellID in ipairs(requiredSpells) do
                    local requiredName = GetSpellInfo(requiredSpellID)
                    if requiredName then
                        local requiredRank = GetLocalizedRankText(requiredSpellID)
                        local known = ns.API.IsKnownSpellID and ns.API.IsKnownSpellID(requiredSpellID)
                        local color = known and "|cffffffff" or Colors.REQUIREMENT_UNMET
                        requirements[#requirements + 1] = color .. requiredName
                            .. (requiredRank and (" (" .. requiredRank .. ")") or "") .. "|r"
                    end
                end
                if isWeaponSkill and entry.source then
                    levelFS:SetText("|cffffffff" .. L.LID_SOURCE .. ":|r " .. entry.source)
                elseif #requirements > 0 then
                    levelFS:SetText("|cffffffffRequires:|r " .. table.concat(requirements, "|cffffffff, |r"))
                end
            elseif elementData.requirementMode == "levelSkill" then
                local requirements = {}
                local levelReq = tonumber(entry.levelReq)
                local skillReq = tonumber(entry.skillReq)
                if levelReq and levelReq > 1 then
                    local levelMet = (UnitLevel("player") or 1) >= levelReq
                    local color = levelMet and Colors.REQUIREMENT_MET or Colors.REQUIREMENT_UNMET
                    requirements[#requirements + 1] = color .. "Level " .. levelReq .. "|r"
                end
                if skillReq and skillReq > 0 then
                    local skillMet = Trainer:IsSkillRequirementMet(entry)
                    local color = skillMet and Colors.REQUIREMENT_MET or Colors.REQUIREMENT_UNMET
                    requirements[#requirements + 1] = color
                        .. (entry.skillName or L.LID_SKILL) .. " (" .. skillReq .. ")|r"
                end
                if #requirements > 0 then
                    levelFS:SetText(table.concat(requirements, " |cffaaaaaa/|r "))
                end
            elseif elementData.showLevel then
                if elementData.levelLabel then
                    local levelPrefix = entry.levelReq and (L.LID_LVL .. " " .. entry.levelReq .. " ") or ""
                    local levelValue = entry.skillRequirementUnknown and "?" or entry.level
                    levelFS:SetText(Colors.RANK .. levelPrefix .. elementData.levelLabel .. " " .. levelValue .. "|r")
                else
                    levelFS:SetText(GetLevelDiffColorCode(entry.level) .. "Level " .. entry.level .. "|r")
                end
            end

            if nativeTrainerCard then
                local costFS = rowFrame.costFS
                if elementData.showCostTooltip and entry.cost ~= nil then
                    local canAfford = entry.cost == 0 or (GetMoney() or 0) >= entry.cost
                    costFS:SetText((canAfford and "|cffffffff" or "|cffff3333")
                        .. FormatCost(entry.cost) .. "|r")
                    costFS:ClearAllPoints()
                    costFS:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -6, -7)
                    costFS:Show()
                end
                local priceWidth = costFS:IsShown() and (costFS:GetStringWidth() or 0) or 0
                local rankWidth = rankFS:IsShown() and (rankFS:GetStringWidth() or 0) or 0
                local rowWidth = rowFrame:GetWidth() or 0
                local maxNameWidth = math.max(0, rowWidth - 54 - priceWidth - rankWidth - 18)
                nameFS:ClearAllPoints()
                nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
                nameFS:SetWidth(math.min((nameFS:GetStringWidth() or 0) + 1, maxNameWidth))
                if rankFS:IsShown() then
                    rankFS:SetWidth(rankWidth + 1)
                    rankFS:SetPoint("BOTTOMLEFT", nameFS, "BOTTOMRIGHT", 5, -1)
                end
                levelFS:ClearAllPoints()
                levelFS:SetPoint("LEFT", nameFS, "LEFT", 0, -19)
                levelFS:SetPoint("RIGHT", rowFrame, "RIGHT", -6, 0)
                levelFS:SetJustifyH("LEFT")
            else
                -- Keep the smaller rank immediately beside the spell name while reserving
                -- room for the right-aligned level/skill requirement text.
                local levelWidth = levelFS:GetStringWidth() or 0
                local rankWidth = rankFS:IsShown() and (rankFS:GetStringWidth() or 0) or 0
                local rowWidth = rowFrame:GetWidth() or 0
                local leftInset = 4 + iconSize + 6
                local rightInset = 4 + levelWidth + (levelWidth > 0 and 4 or 0)
                local maxNameWidth = math.max(0, rowWidth - leftInset - rightInset - rankWidth)
                local nameWidth = math.min((nameFS:GetStringWidth() or 0) + 1, maxNameWidth)
                nameFS:SetWidth(nameWidth)
                if rankFS:IsShown() then
                    rankFS:SetWidth(rankWidth + 1)
                    rankFS:SetPoint("LEFT", nameFS, "RIGHT", 0, 0)
                end
            end

            rowFrame:EnableMouse(true)
            rowFrame:SetScript("OnEnter", function(sel)
                if sel.nativeTrainerHighlight then sel.nativeTrainerHighlight:Show() end
                GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
                local showCost = elementData.showCostTooltip and entry.cost ~= nil
                if entry.spellID then
                    pendingSpellTooltipExtra = {
                        spellID = entry.spellID,
                        showCost = showCost,
                        cost = entry.cost,
                        source = entry.source,
                    }

                    GameTooltip:SetSpellByID(entry.spellID)
                else
                    pendingSpellTooltipExtra = nil
                    GameTooltip:SetText(entry.name)
                    if showCost then
                        local canAfford = not entry.cost or entry.cost == 0 or (GetMoney() or 0) >= entry.cost
                        local costColor = canAfford and "|cffffffff" or "|cffff3333"
                        GameTooltip:AddLine(L.LID_COSTS .. ": " .. costColor .. FormatCost(entry.cost) .. "|r", 1, 1, 1)
                        GameTooltip:AddLine(L.LID_OWNGOLD .. ": " .. FormatOwnedMoney(), 1, 1, 1)
                    end

                    if entry.source then GameTooltip:AddLine(L.LID_SOURCE .. ": " .. entry.source, 0.9, 0.9, 0.9, true) end
                end

                GameTooltip:Show()
            end)

            rowFrame:SetScript("OnLeave", function(sel)
                if sel.nativeTrainerHighlight then sel.nativeTrainerHighlight:Hide() end
                pendingSpellTooltipExtra = nil
                GameTooltip_Hide(sel)
            end)

            rowFrame:SetScript("OnMouseUp", function(sel, button)
                if button == "LeftButton" and entry.trainingQueueKey and entry.trainingQueueEligible then
                    Trainer:ToggleTrainingQueue(entry)
                elseif button == "RightButton" then
                    Trainer:ShowIgnoreMenu(sel, entry)
                end
            end)
        end
    end
end)
