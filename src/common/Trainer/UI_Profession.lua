local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings
local GetItemIcon = ns.API and ns.API.GetItemIcon
local GetItemInfoInstant = ns.API and ns.API.GetItemInfoInstant
local GetSpellInfo = ns.API and ns.API.GetSpellInfo
local FOREVER_NATIVE_PROFESSIONS = ns.TrainerProviderOwnsDetachedProfessionHost
    and ns.TrainerProviderOwnsDetachedProfessionHost() or false

local function TradeSkillRecipeSpellID(index)
    if not GetTradeSkillRecipeLink then return nil end
    local link = GetTradeSkillRecipeLink(index)
    local spellID = type(link) == "string" and link:match("spell:(%d+)") or nil
    return tonumber(spellID)
end

-- Classic SkillLine ids used by LibProfessionDB. Keep this bridge local to the
-- profession UI: Core/ProfessionData owns profession identity, while this map
-- describes one third-party catalog's key format.
local PROFESSION_SKILL_LINE_IDS = {
    Alchemy = 171,
    Blacksmithing = 164,
    Cooking = 185,
    Enchanting = 333,
    Engineering = 202,
    ["First Aid"] = 129,
    Fishing = 356,
    Leatherworking = 165,
    Mining = 186,
    Tailoring = 197,
}

local PROFESSION_KEY_BY_SKILL_LINE = {}
for key, skillLineID in pairs(PROFESSION_SKILL_LINE_IDS) do
    PROFESSION_KEY_BY_SKILL_LINE[skillLineID] = key
end

local PROFESSIONS_WITHOUT_TRAINING_RECIPES = {
    Fishing = true,
    Herbalism = true,
    Skinning = true,
}

local SOURCE_ORDER = {
    { key = "vendor", label = "Vendor" },
    { key = "quest", label = "Quest" },
    { key = "container", label = "Container" },
    { key = "drop", label = "Drop" },
}

local function HasExternalRecipeSource(sourceKinds)
    return sourceKinds and (sourceKinds.vendor or sourceKinds.quest
        or sourceKinds.container or sourceKinds.drop) or false
end

local function GetKnownTradeSkillRecipeState()
    local state = { ids = {}, names = {}, icons = {} }

    -- Forever's Retail-derived profession window does not publish the legacy
    -- GetNumTradeSkills/GetTradeSkillInfo list.  Its recipe records are the
    -- authority instead: `learned` is per-character and changes as soon as the
    -- player learns a recipe.  Recipes owns the complete catalog, so scan the
    -- complete native ID list here.
    if FOREVER_NATIVE_PROFESSIONS and C_TradeSkillUI
        and type(C_TradeSkillUI.GetAllRecipeIDs) == "function"
        and type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local okIDs, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if okIDs and type(recipeIDs) == "table" then
            for _, recipeID in ipairs(recipeIDs) do
                local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                if okInfo and type(info) == "table" then
                    if info.icon then state.icons[recipeID] = info.icon end
                    if info.learned == true then
                        state.ids[recipeID] = true
                        if type(info.name) == "string" and info.name ~= "" then
                            state.names[info.name] = true
                        end
                    end
                end
            end
            return state
        end
    end

    if not GetNumTradeSkills or not GetTradeSkillInfo then return state end
    for i = 1, GetNumTradeSkills() do
        local name, skillType = GetTradeSkillInfo(i)
        if type(name) == "string" and name ~= ""
            and skillType ~= "header" and skillType ~= "subheader" then
            local spellID = TradeSkillRecipeSpellID(i)
            state.names[name] = true
            if spellID then state.ids[spellID] = true end
            if GetTradeSkillIcon then state.icons[spellID or name] = GetTradeSkillIcon(i) end
        end
    end
    return state
end

-- Training needs knowledge only for the comparatively small trainer catalog,
-- not every recipe exposed by the profession book.  Querying just its spell
-- IDs keeps search/collapse refreshes cheap while retaining Blizzard's live
-- per-character `learned` flag as the source of truth.
function Trainer:GetKnownProfessionTrainingState(dataTable)
    local known = {}
    if FOREVER_NATIVE_PROFESSIONS and C_TradeSkillUI
        and type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local seen = {}
        for _, bucket in pairs(dataTable or {}) do
            if type(bucket) == "table" then
                for key, data in pairs(bucket) do
                    local recipeID = type(data) == "table" and tonumber(data.spellID)
                        or (type(key) == "number" and key or nil)
                    if recipeID and not seen[recipeID] then
                        seen[recipeID] = true
                        local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                        if okInfo and type(info) == "table" and info.learned == true then
                            known[recipeID] = true
                            if type(info.name) == "string" and info.name ~= "" then
                                known[info.name] = true
                            end
                        end
                    end
                end
            end
        end
        return known
    end

    if not GetNumTradeSkills or not GetTradeSkillInfo then return known end
    for i = 1, GetNumTradeSkills() do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" and skillType ~= "subheader" then
            known[skillName] = true
            local recipeID = TradeSkillRecipeSpellID(i)
            if recipeID then known[recipeID] = true end
        end
    end
    return known
end

local function GetObservedTrainerRecipeState(professionKey)
    local state = { ids = {}, names = {} }
    local professionData = TurboFaceTrainerDB and TurboFaceTrainerDB.professionData
        and TurboFaceTrainerDB.professionData[professionKey]
    if type(professionData) ~= "table" then return state end

    for _, bucket in pairs(professionData) do
        if type(bucket) == "table" then
            for key, data in pairs(bucket) do
                if type(key) == "string" then state.names[key] = true end
                if type(key) == "number" then state.ids[key] = true end
                if type(data) == "table" then
                    if type(data.spellID) == "number" then state.ids[data.spellID] = true end
                    if type(data.name) == "string" then state.names[data.name] = true end
                end
            end
        end
    end
    return state
end

local function GetCraftedItemIcon(itemID)
    if not itemID then return nil end
    local icon = GetItemIcon and GetItemIcon(itemID)
    if icon then return icon end
    if GetItemInfoInstant then return select(5, GetItemInfoInstant(itemID)) end
end

local function FormatRecipeSource(database, spellID)
    if database.IsAutoTaughtRecipe and database:IsAutoTaughtRecipe(spellID) then
        return "Learned with profession"
    end

    local sources = database.GetRecipeSources and database:GetRecipeSources(spellID)
    if not sources then return "Unknown" end

    local parts = {}
    for i = 1, #SOURCE_ORDER do
        local sourceInfo = SOURCE_ORDER[i]
        local list = sources[sourceInfo.key]
        if list then
            local names = {}
            for j = 1, math.min(#list, 2) do
                if list[j].name then names[#names + 1] = list[j].name end
            end
            local total = tonumber(list.total) or #list
            local detail = #names > 0 and (": " .. table.concat(names, ", ")) or ""
            if total > #names then detail = detail .. (" +%d more"):format(total - #names) end
            parts[#parts + 1] = sourceInfo.label .. detail
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or "Unknown"
end

-- Live-book fallback used if the embedded static database cannot initialize.
-- Native header order is retained; only empty search groups are discarded.
function Trainer:BuildKnownTradeSkillRecipeGroups(searchText, professionName)
    local groups = {}
    if not GetNumTradeSkills or not GetTradeSkillInfo then return groups end

    searchText = type(searchText) == "string" and searchText:lower() or ""
    local current
    local function EnsureGroup(name, index)
        current = {
            name = (type(name) == "string" and name ~= "") and name or L.LID_RECIPES,
            index = index,
            entries = {},
        }
        groups[#groups + 1] = current
    end

    for i = 1, GetNumTradeSkills() do
        local name, skillType = GetTradeSkillInfo(i)
        if skillType == "header" or skillType == "subheader" then
            EnsureGroup(name, i)
        elseif type(name) == "string" and name ~= "" then
            local spellID = TradeSkillRecipeSpellID(i)
            local searchable = name:lower()
            if spellID and GetSpellInfo then
                local spellName, rankText = GetSpellInfo(spellID)
                if spellName then searchable = searchable .. " " .. spellName:lower() end
                if rankText then searchable = searchable .. " " .. rankText:lower() end
            end
            if searchText == "" or searchable:find(searchText, 1, true) then
                if not current then EnsureGroup(professionName, 0) end
                current.entries[#current.entries + 1] = {
                    name = name,
                    spellID = spellID,
                    icon = (GetTradeSkillIcon and GetTradeSkillIcon(i))
                        or "Interface\\Icons\\INV_Misc_QuestionMark",
                    source = professionName and ("Learned " .. professionName .. " recipe")
                        or "Learned profession recipe",
                }
            end
        end
    end

    local nonempty = {}
    for i = 1, #groups do
        if #groups[i].entries > 0 then nonempty[#nonempty + 1] = groups[i] end
    end
    return nonempty
end

-- Build the external-acquisition catalog from LibProfessionDB, then overlay the
-- currently open trade-skill book to distinguish learned from missing recipes.
-- The persistent trainer snapshot participates only as a negative duplicate
-- filter; its rows and metadata remain owned and rendered by Training.
function Trainer:BuildProfessionRecipeGroups(searchText, professionKey, professionName)
    local skillLineID = professionKey and PROFESSION_SKILL_LINE_IDS[professionKey]
    local database = ns.EnsureProfessionRecipeDatabase and ns:EnsureProfessionRecipeDatabase() or nil
    local recipes = database and skillLineID and database:GetRecipes(skillLineID) or nil
    if not recipes then return nil end

    local knownState = GetKnownTradeSkillRecipeState()
    local observedTrainerState = GetObservedTrainerRecipeState(professionKey)
    local groups = { known = {}, missing = {}, ignored = {} }
    searchText = type(searchText) == "string" and searchText:lower() or ""

    for spellID, recipe in pairs(recipes) do
        local sourceKinds = database.GetRecipeSourceKinds
            and database:GetRecipeSourceKinds(spellID) or nil
        -- Community trainer flags are known to be over-inclusive in the Era
        -- source data, so a confirmed external path is positive evidence even
        -- when a questionable trainer flag is also present. Actual trainer
        -- duplicates are removed against TurboFace's own observed Training
        -- catalog below.
        local hasExternalSource = HasExternalRecipeSource(sourceKinds)
        local isRankBook = false
        if database.GetRecipeItem then
            local _, rankBook = database:GetRecipeItem(spellID)
            isRankBook = rankBook
        end
        -- Do not route this through `GetSpellInfo and GetSpellInfo(...)`.
        -- Lua logical expressions collapse multiple returns, which preserves
        -- the name but discards GetSpellInfo's third return (the icon).
        local spellName, spellIcon
        if GetSpellInfo then
            local resolvedName, _, resolvedIcon = GetSpellInfo(spellID)
            spellName, spellIcon = resolvedName, resolvedIcon
        end
        local name = spellName or recipe.name or ("SpellID " .. tostring(spellID))
        local isObservedTrainerRecipe = observedTrainerState.ids[spellID]
            or observedTrainerState.names[name]
        if hasExternalSource and not isObservedTrainerRecipe and not isRankBook
            and not (database.IsHiddenRecipe and database:IsHiddenRecipe(spellID)) then
            local source = FormatRecipeSource(database, spellID)
            local searchable = (name .. " " .. (recipe.effect or "") .. " " .. source):lower()
            if searchText == "" or searchable:find(searchText, 1, true) then
                local requiredSkill = tonumber(recipe.requiredSkill)
                local sortSkill = requiredSkill
                    or (recipe.difficulty and tonumber(recipe.difficulty[1])) or 0
                local entry = {
                    level = sortSkill,
                    key = spellID,
                    spellID = spellID,
                    name = name,
                    -- Crafted recipes represent their output item. Enchants and
                    -- other no-item effects have no craftedItemId and therefore
                    -- fall back to the live recipe/spell texture.
                    icon = GetCraftedItemIcon(recipe.craftedItemId)
                        or knownState.icons[spellID] or spellIcon
                        or "Interface\\Icons\\INV_Misc_QuestionMark",
                    source = source,
                    skillReq = requiredSkill,
                    skillName = professionName,
                }

                if Trainer.IsProfessionSpellIgnored
                    and Trainer.IsProfessionSpellIgnored(spellID, professionKey) then
                    groups.ignored[#groups.ignored + 1] = entry
                elseif knownState.ids[spellID] or knownState.names[name] then
                    groups.known[#groups.known + 1] = entry
                else
                    groups.missing[#groups.missing + 1] = entry
                end
            end
        end
    end

    local function SortRecipes(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.spellID < b.spellID
    end
    table.sort(groups.known, SortRecipes)
    table.sort(groups.missing, SortRecipes)
    table.sort(groups.ignored, SortRecipes)
    return groups
end

-- LibProfessionDB supplies the durable baseline for profession Training. Keep
-- its trainer-only rows separate from Recipes, then overlay TurboFace's live
-- observations so Blizzard remains authoritative for transient cost/status and
-- trainer-specific requirements. Mixed trainer/external source rows stay in
-- Recipes because the Era community trainer flags are known to over-report.
function Trainer:BuildProfessionTrainingData(professionKey, professionName)
    local skillLineID = professionKey and PROFESSION_SKILL_LINE_IDS[professionKey]
    local database = ns.EnsureProfessionRecipeDatabase and ns:EnsureProfessionRecipeDatabase() or nil
    local recipes = database and skillLineID and database:GetRecipes(skillLineID) or nil
    local merged = {}
    local baselineBySpellID = {}

    if recipes then
        for spellID, recipe in pairs(recipes) do
            local sourceKinds = database.GetRecipeSourceKinds
                and database:GetRecipeSourceKinds(spellID) or nil
            local isTrainerOnly = sourceKinds and sourceKinds.trainer
                and not HasExternalRecipeSource(sourceKinds)
            local isAutoTaught = database.IsAutoTaughtRecipe
                and database:IsAutoTaughtRecipe(spellID)
            local isRankBook = false
            if database.GetRecipeItem then
                local _, rankBook = database:GetRecipeItem(spellID)
                isRankBook = rankBook
            end

            if isTrainerOnly and not isAutoTaught and not isRankBook
                and not (database.IsHiddenRecipe and database:IsHiddenRecipe(spellID)) then
                local spellName, spellIcon
                if GetSpellInfo then
                    local resolvedName, _, resolvedIcon = GetSpellInfo(spellID)
                    spellName, spellIcon = resolvedName, resolvedIcon
                end
                local name = spellName or recipe.name or ("SpellID " .. tostring(spellID))
                local requiredSkill = tonumber(recipe.requiredSkill)
                -- requiredSkill is specifically the level needed to learn the
                -- recipe. Do not substitute the orange crafting threshold:
                -- those values differ for many Vanilla trainer recipes.
                local bucketKey = requiredSkill or 0
                merged[bucketKey] = merged[bucketKey] or {}
                local entry = {
                    spellID = spellID,
                    icon = GetCraftedItemIcon(recipe.craftedItemId) or spellIcon,
                    skillReq = requiredSkill,
                    skillRequirementUnknown = requiredSkill == nil,
                    skillName = professionName,
                    source = "Trainer",
                }
                merged[bucketKey][name] = entry
                baselineBySpellID[spellID] = { bucket = merged[bucketKey], name = name }
            end
        end
    end

    -- Forever adds recipes that are absent from the Classic Era database.
    -- Admit only live trainer-verified rows here; the 512-recipe crafting
    -- snapshot alone proves existence/reagents but not acquisition method or
    -- learn skill. A subsequent live observation removes/replaces this seed by
    -- spell ID below, retaining Blizzard authority for cost and requirements.
    local foreverRows = FOREVER_NATIVE_PROFESSIONS
        and Trainer.ForeverProfessionTrainingData
        and Trainer.ForeverProfessionTrainingData[professionKey]
    for _, seeded in ipairs(foreverRows or {}) do
        local spellName, spellIcon
        if GetSpellInfo then
            local resolvedName, _, resolvedIcon = GetSpellInfo(seeded.spellID)
            spellName, spellIcon = resolvedName, resolvedIcon
        end
        local name = spellName or seeded.name or ("SpellID " .. tostring(seeded.spellID))
        local skillReq = tonumber(seeded.skillReq)
        local bucketKey = skillReq or 0
        merged[bucketKey] = merged[bucketKey] or {}
        merged[bucketKey][name] = {
            spellID = seeded.spellID,
            icon = seeded.icon or spellIcon,
            cost = seeded.cost,
            skillReq = skillReq,
            skillRequirementUnknown = skillReq == nil,
            skillName = professionName,
            source = "Trainer",
        }
        baselineBySpellID[seeded.spellID] = {
            bucket = merged[bucketKey], name = name,
        }
    end

    -- Remove a baseline row by spell id before inserting its observed form. In
    -- practice names match, but spell identity also handles locale/name changes
    -- without rendering a duplicate in two skill buckets.
    local observed = TurboFaceTrainerDB and TurboFaceTrainerDB.professionData
        and TurboFaceTrainerDB.professionData[professionKey]
    if type(observed) == "table" then
        for skillReq, bucket in pairs(observed) do
            if type(bucket) == "table" then
                for name, data in pairs(bucket) do
                    local observedSpellID = type(data) == "table" and data.spellID or nil
                    if observedSpellID then
                        local baseline = baselineBySpellID[observedSpellID]
                        if baseline then baseline.bucket[baseline.name] = nil end
                    end
                    merged[skillReq] = merged[skillReq] or {}
                    if type(data) == "table" then
                        -- Older live snapshots stored the requirement only in
                        -- the outer skill bucket. Normalize a shallow view so
                        -- those records render as profession skill gates rather
                        -- than generic character levels, without rewriting the
                        -- user's persisted capture table.
                        local normalized = {}
                        for key, value in pairs(data) do normalized[key] = value end
                        normalized.skillReq = tonumber(data.skillReq) or tonumber(skillReq)
                        normalized.skillName = data.skillName or professionName or professionKey
                        merged[skillReq][name] = normalized
                    else
                        merged[skillReq][name] = data
                    end
                end
            end
        end
    end

    return merged
end

Trainer:AddBuilder(function()
    local classFrame = Trainer.ClassFrame
    -- Returns current rank and max rank. The max is what identifies which
    -- profession ranks the player has already trained: a Journeyman
    -- leatherworker reads 150 regardless of current skill, and rank-up services
    -- capped at or below that are already learned. See GetProfessionRankCap.
    --
    -- Delegates to ns.Skills rather than scanning here. The local loop this
    -- replaced read only VISIBLE skill lines, so collapsing the Professions
    -- header in Blizzard's skill panel returned 0/0 and silently disabled the
    -- rank check. The engine expands, reads, and restores collapse state.
    local function GetCurrentProfessionSkill(professionName)
        if not professionName then return 0, 0 end
        if FOREVER_NATIVE_PROFESSIONS and C_TradeSkillUI
            and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
            local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if ok and type(info) == "table" and (tonumber(info.professionID) or 0) > 0
                and (info.professionName == professionName
                    or Trainer:GetProfessionKey(info.professionName) == Trainer:GetProfessionKey(professionName)) then
                return tonumber(info.skillLevel) or 0, tonumber(info.maxSkillLevel) or 0
            end
        end
        if ns.Skills and ns.Skills.Get then
            local rank, maxRank = ns.Skills:Get(professionName)
            if rank then return rank, maxRank or 0 end
            return 0, 0
        end

        -- Fallback if the engine is unavailable.
        if not GetNumSkillLines or not GetSkillLineInfo then return 0, 0 end
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
            if not isHeader and skillName == professionName then
                return skillRank or 0, skillMaxRank or 0
            end
        end
        return 0, 0
    end

    local professionFrame = CreateFrame("Frame", "TurboFaceTrainerProfessionFrame", UIParent)
    professionFrame:SetSize(420, 480)
    professionFrame:SetFrameStrata("HIGH")
    professionFrame:SetFrameLevel(500)
    professionFrame:EnableMouse(true)
    professionFrame:Hide()
    local professionSearchBox = CreateFrame("EditBox", "TurboFaceTrainerProfessionSearchBox", professionFrame, "SearchBoxTemplate")
    professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 8, -24)
    professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -8, -24)
    professionSearchBox:SetHeight(20)
    professionSearchBox:SetAutoFocus(false)
    professionSearchBox:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        Trainer.ProfessionSearchText = self:GetText() or ""
        Trainer.ProfessionRefresh()
    end)

    local professionScrollBox = CreateFrame("Frame", "TurboFaceTrainerProfessionScrollBox", professionFrame, "WowScrollBoxList")
    professionScrollBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 8, -4)
    professionScrollBox:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -26, 12)
    local professionListBg = professionFrame:CreateTexture("TurboFaceTrainerProfessionBackground", "BACKGROUND")
    local professionNativeInsetBg = Trainer:CreateNativeInsetBackground(professionFrame, "TurboFaceTrainerProfessionNativeInsetBackground")
    professionNativeInsetBg:Hide()
    local professionScrollBar = CreateFrame("EventFrame", "TurboFaceTrainerProfessionScrollBar", professionFrame, "MinimalScrollBar")
    professionScrollBar:SetPoint("TOPLEFT", professionScrollBox, "TOPRIGHT", 4, -2)
    professionScrollBar:SetPoint("BOTTOMLEFT", professionScrollBox, "BOTTOMRIGHT", 4, 2)
    local professionScrollView = CreateScrollBoxListLinearView()
    local function BuildForeverProfessionGrid(items)
        local rows, pending = {}, {}
        local function Flush()
            if #pending == 0 then return end
            rows[#rows + 1] = {cells = pending, columnCount = 2}
            pending = {}
        end
        for _, item in ipairs(items or {}) do
            if item.isHeader then
                Flush()
                rows[#rows + 1] = {cells = {item}, columnCount = 1, isHeaderRow = true}
            else
                pending[#pending + 1] = item
                if #pending == 2 then Flush() end
            end
        end
        Flush()
        return rows
    end
    if FOREVER_NATIVE_PROFESSIONS then
        professionScrollView:SetElementExtentCalculator(function(index, elementData)
            local headerHeight = Trainer.HeaderHeight + (Trainer.SpellbookListSizeBump or 0)
            if elementData.isHeaderRow then
                return index > 1 and (headerHeight + Trainer.HeaderExtraGap) or headerHeight
            end
            return 47
        end)
        professionScrollView:SetPadding(6, 0, 0, 0, 0)
        professionScrollView:SetElementInitializer("Frame", function(rowFrame, elementData)
            if not rowFrame._tfProfessionCells then
                rowFrame._tfProfessionCells = {}
                for index = 1, 2 do
                    local cell = CreateFrame("Frame", nil, rowFrame)
                    cell:SetFrameLevel((rowFrame:GetFrameLevel() or 0) + 1)
                    cell:Hide()
                    rowFrame._tfProfessionCells[index] = cell
                end
            end
            local cells, entries = rowFrame._tfProfessionCells, elementData.cells or {}
            local columns = elementData.isHeaderRow and 1 or 2
            local gap = 2
            local width = rowFrame:GetWidth() or 0
            local cellWidth = math.max(1, (width - ((columns - 1) * gap)) / columns)
            for index, cell in ipairs(cells) do
                cell:Hide()
                cell:ClearAllPoints()
                local entry = entries[index]
                if entry then
                    cell:SetWidth(elementData.isHeaderRow and width or cellWidth)
                    if index == 1 then
                        cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, 0)
                        cell:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, 0)
                    else
                        cell:SetPoint("TOPLEFT", cells[index - 1], "TOPRIGHT", gap, 0)
                        cell:SetPoint("BOTTOMLEFT", cells[index - 1], "BOTTOMRIGHT", gap, 0)
                    end
                    cell:Show()
                    Trainer:InitScrollRow(cell, entry, true)
                end
            end
        end)
    else
        professionScrollView:SetElementExtentCalculator(function(index, elementData)
            if elementData.isHeader then return index > 1 and (Trainer.HeaderHeight + Trainer.HeaderExtraGap) or Trainer.HeaderHeight end
            return Trainer.RowHeight
        end)
        professionScrollView:SetPadding(6, 0, 0, 0, Trainer.RowSpacing)
        professionScrollView:SetElementInitializer("Frame", function(rowFrame, elementData) Trainer:InitScrollRow(rowFrame, elementData) end)
    end
    ScrollUtil.InitScrollBoxListWithScrollBar(professionScrollBox, professionScrollBar, professionScrollView)

    if FOREVER_NATIVE_PROFESSIONS then
        professionListBg:SetTexture(404984)
        professionListBg:SetTexCoord(0.00195313, 0.58593750, 0.00195313, 0.65429688)
        if professionNativeInsetBg.Bg then professionNativeInsetBg.Bg:Hide() end
    end

    -- GetTradeSkillLine() is only meaningful while the tradeskill window is
    -- open. With it closed the API returns the literal string "UNKNOWN", which
    -- the old code passed through as if it were a profession name: the key
    -- lookup failed, the skill-line scan matched nothing, and max skill came
    -- back 0 -- which silently disabled the profession rank-known check.
    --
    -- So: reject the sentinel, fall back to the trainer's own skill line when
    -- standing at one, and always resolve the display name from the key rather
    -- than trusting whatever the window happened to report.
    local function IsUsableSkillLineName(name)
        if type(name) ~= "string" or name == "" then return false end
        if name == "UNKNOWN" then return false end
        if UNKNOWN and name == UNKNOWN then return false end
        return true
    end

    local function GetOpenProfession()
        if FOREVER_NATIVE_PROFESSIONS and C_TradeSkillUI
            and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
            local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if ok and type(info) == "table" then
                local professionID = tonumber(info.professionID)
                local professionName = info.professionName
                local professionKey = Trainer:GetProfessionKey(professionName)
                    or PROFESSION_KEY_BY_SKILL_LINE[professionID]
                if professionKey and professionID and professionID > 0 then
                    return professionKey,
                        Trainer:GetProfessionDisplayName(professionKey) or professionName or professionKey
                end
            end
        end
        local skillLineName = GetTradeSkillLine and GetTradeSkillLine() or nil
        local professionKey = IsUsableSkillLineName(skillLineName)
            and Trainer:GetProfessionKey(skillLineName) or nil

        -- Standing at a profession trainer with no tradeskill window open.
        if not professionKey and Trainer.DetectTrainerProfession then
            local key = Trainer:DetectTrainerProfession()
            if key then professionKey = key end
        end

        if not professionKey then return nil, nil end

        -- Canonical localized name for the key; only fall back to the window's
        -- report if the map has no entry.
        local displayName = Trainer:GetProfessionDisplayName(professionKey)
        if not displayName and IsUsableSkillLineName(skillLineName) then
            displayName = skillLineName
        end

        return professionKey, displayName
    end

    local PROFESSION_VIEW_TRAINING = "training"
    local PROFESSION_VIEW_RECIPES = "recipes"
    local professionViewMode = PROFESSION_VIEW_TRAINING

    -- Profession proficiency upgrades now have a single presentation owner:
    -- Spellbook > Skills, where Level and Skill requirements can be shown
    -- together. Keep the profession-specific Training panel focused on ordinary
    -- trainer-taught profession abilities/recipes by removing only rank rows.
    -- A shallow filtered view is enough; the captured data itself remains
    -- untouched and continues to feed live requirement/cost overrides.
    local function WithoutProfessionRanks(data, professionName)
        if type(data) ~= "table" or not professionName then return data end
        local filtered = {}
        for skillReq, bucket in pairs(data) do
            if type(bucket) == "table" then
                local kept
                for key, entryData in pairs(bucket) do
                    local spellID = type(entryData) == "table" and entryData.spellID
                        or (type(key) == "number" and key or nil)
                    if not Trainer:GetProfessionRankCap(key, professionName, spellID) then
                        kept = kept or {}
                        kept[key] = entryData
                    end
                end
                if kept then filtered[skillReq] = kept end
            end
        end
        return filtered
    end
    function Trainer:IsProfessionRecipeViewActive()
        return professionViewMode == PROFESSION_VIEW_RECIPES
    end

    function Trainer.ProfessionRefresh()
        local searchText = (Trainer.ProfessionSearchText or ""):lower()
        local professionKey, skillLineName = GetOpenProfession()
        local items = {}
        if professionViewMode == PROFESSION_VIEW_RECIPES then
            local recipeGroups = Trainer:BuildProfessionRecipeGroups(searchText, professionKey, skillLineName)
            if recipeGroups then
                local prefix = "tradeskillrecipe_" .. tostring(professionKey or "unknown") .. "_"
                if #recipeGroups.missing > 0 then
                    Trainer:AddHeaderItem(items, L.LID_NOTLEARNEDYET, Trainer.UIColors.NOTYET, nil, prefix .. "missing")
                    if not Trainer:IsGroupCollapsed(prefix .. "missing") then
                        Trainer:AddEntryItems(items, recipeGroups.missing, Trainer.UIColors.NOTYET, false, false, false, nil, "levelSkill")
                    end
                end
                if #recipeGroups.ignored > 0 then
                    Trainer:AddHeaderItem(items, L.LID_IGNORED, Trainer.UIColors.IGNORED, nil, prefix .. "ignored")
                    if not Trainer:IsGroupCollapsed(prefix .. "ignored") then
                        Trainer:AddEntryItems(items, recipeGroups.ignored, Trainer.UIColors.IGNORED, false, false, true, nil, "levelSkill")
                    end
                end
                if #recipeGroups.known > 0 then
                    Trainer:AddHeaderItem(items, L.LID_ALREADYKNOWN, Trainer.UIColors.KNOWN, nil, prefix .. "known")
                    if not Trainer:IsGroupCollapsed(prefix .. "known") then
                        Trainer:AddEntryItems(items, recipeGroups.known, Trainer.UIColors.KNOWN, false, false, true, nil, "levelSkill")
                    end
                end
            else
                -- A bad or incomplete embedded-library load should degrade to
                -- the live learned book rather than blanking the Recipes tab.
                local fallbackGroups = Trainer:BuildKnownTradeSkillRecipeGroups(searchText, skillLineName)
                for i = 1, #fallbackGroups do
                    local group = fallbackGroups[i]
                    local groupKey = ("tradeskillrecipe_fallback_%s_%d"):format(tostring(professionKey or "unknown"), group.index or i)
                    Trainer:AddHeaderItem(items, group.name, Trainer.UIColors.KNOWN, nil, groupKey)
                    if not Trainer:IsGroupCollapsed(groupKey) then
                        Trainer:AddEntryItems(items, group.entries, Trainer.UIColors.KNOWN, false, false, false)
                    end
                end
            end

            if #items == 0 then Trainer:AddHeaderItem(items, skillLineName and ("No recipes found for " .. skillLineName .. ".") or "No profession detected.", "|cffaaaaaa") end
        else
            local data = professionKey
                and Trainer:BuildProfessionTrainingData(professionKey, skillLineName) or nil
            if data and next(data) then
                local currentSkill, maxSkill = GetCurrentProfessionSkill(skillLineName)
                local displayData = WithoutProfessionRanks(data, skillLineName)
                local knownRecipes = Trainer:GetKnownProfessionTrainingState(displayData)
                local groups = Trainer:ClassifyEntries(displayData, searchText, currentSkill, true, professionKey, "profession", professionKey, knownRecipes, skillLineName, maxSkill)
                local prefix = "tradeskillprofession_" .. tostring(professionKey) .. "_"
                Trainer:AppendGroupItems(items, groups, prefix, nil, L.LID_SKILL)
            end

            if #items == 0 then
                local message
                if professionKey and PROFESSIONS_WITHOUT_TRAINING_RECIPES[professionKey] then
                    message = "No trainer-taught recipes for " .. skillLineName .. ". Profession ranks are shown in Skills."
                elseif skillLineName then
                    message = "No Training entries found for " .. skillLineName .. "."
                else
                    message = "No profession detected."
                end
                Trainer:AddHeaderItem(items, message, "|cffaaaaaa")
            end
        end

        local displayItems = FOREVER_NATIVE_PROFESSIONS and BuildForeverProfessionGrid(items) or items
        professionScrollBox:SetDataProvider(CreateDataProvider(displayItems), ScrollBoxConstants.RetainScrollPosition)
    end

    local function PositionProfessionFrame()
        professionFrame:ClearAllPoints()
        if TradeSkillFrame and TradeSkillFrame:IsShown() then
            if Trainer:IsDragonflightUIEnabled() and DragonflightUIProfessionFrame and DragonflightUIProfessionFrame:IsShown() then
                professionFrame:SetScale(DragonflightUIProfessionFrame:GetScale())
                professionFrame:SetPoint("TOPLEFT", DragonflightUIProfessionFrame, "TOPLEFT", -4, -24)
                professionFrame:SetPoint("BOTTOMRIGHT", DragonflightUIProfessionFrame, "BOTTOMRIGHT", -4, 4)
            elseif Trainer:IsLeatrixWideProfessionEnabled() then
                professionFrame:SetScale(TradeSkillFrame:GetScale())
                professionFrame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 14, -70)
                professionFrame:SetPoint("BOTTOMRIGHT", TradeSkillFrame, "BOTTOMRIGHT", -36, 70)
            else
                professionFrame:SetScale(TradeSkillFrame:GetScale())
                professionFrame:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 14, -70)
                professionFrame:SetPoint("BOTTOMRIGHT", TradeSkillFrame, "BOTTOMRIGHT", -36, 70)
            end
        else
            professionFrame:SetScale(1)
            professionFrame:SetPoint("CENTER")
        end

        professionSearchBox:ClearAllPoints()
        professionScrollBox:ClearAllPoints()
        if Trainer:IsDragonflightUIEnabled() and DragonflightUIProfessionFrame and DragonflightUIProfessionFrame:IsShown() then
            professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 80, 0)
            professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -10, 0)
            professionScrollBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 8, -64)
            professionScrollBox:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -26, 12)
        elseif Trainer:IsLeatrixWideProfessionEnabled() then
            local titleText = TradeSkillFrame and _G["TradeSkillFrameTitleText"]
            if titleText and professionFrame:GetTop() and titleText:GetBottom() then
                local topOffset = titleText:GetBottom() - professionFrame:GetTop() - 4
                professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 66, topOffset)
                professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -4, topOffset)
            else
                professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 10, -6)
                professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -30, -10)
            end

            professionScrollBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 0, -4)
            professionScrollBox:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -26, -12)
        else
            local titleText = TradeSkillFrame and _G["TradeSkillFrameTitleText"]
            if titleText and professionFrame:GetTop() and titleText:GetBottom() then
                local topOffset = titleText:GetBottom() - professionFrame:GetTop() - 4
                professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 66, topOffset)
                professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -4, topOffset)
            else
                professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 10, -6)
                professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -30, -6)
            end

            professionScrollBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 8, -4)
            professionScrollBox:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -26, 12)
        end
    end

    if FOREVER_NATIVE_PROFESSIONS then
        local professionUI
        local loader = CreateFrame("Frame", "TurboFaceTrainerProfessionLoader", UIParent)

        local function CurrentProfessionInfo()
            if not (C_TradeSkillUI and type(C_TradeSkillUI.GetBaseProfessionInfo) == "function") then
                return nil
            end
            local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            if not ok or type(info) ~= "table" or (tonumber(info.professionID) or 0) <= 0 then
                return nil
            end
            return info
        end

        local function InitializeForeverProfessions()
            if professionUI then return professionUI end
            local professionsFrame = rawget(_G, "ProfessionsFrame")
            local craftingPage = professionsFrame and professionsFrame.CraftingPage
            if not (professionsFrame and craftingPage) then return nil end

            local customOpen = false
            local nativeCraftingWasShown
            local refreshQueued = false

            local bookButton = CreateFrame("Button", "TurboFaceTrainerProfessionBookTab", UIParent)
            bookButton:SetSize(55, 55)
            bookButton:SetFrameStrata("HIGH")
            bookButton:SetFrameLevel(510)
            bookButton:EnableMouse(true)
            bookButton:Hide()

            local background = bookButton:CreateTexture(nil, "BACKGROUND")
            background:SetPoint("CENTER", bookButton, "CENTER", 0, 0)
            background:SetAtlas("common-sidetab", true)
            local icon = bookButton:CreateTexture(nil, "ARTWORK")
            icon:SetSize(40, 40)
            icon:SetPoint("CENTER", bookButton, "CENTER", -4, 0)
            icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local mask = bookButton:CreateMaskTexture(nil, "ARTWORK")
            mask:SetPoint("CENTER", bookButton, "CENTER", 0, 0)
            mask:SetAtlas("common-sidetab-mask", true)
            icon:AddMaskTexture(mask)
            local selected = bookButton:CreateTexture(nil, "OVERLAY", nil, 0)
            selected:SetPoint("CENTER", bookButton, "CENTER", 0, 0)
            selected:SetAtlas("common-sidetab-selected", true)
            selected:Hide()
            local highlight = bookButton:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetPoint("CENTER", bookButton, "CENTER", 0, 0)
            highlight:SetAtlas("common-sidetab-hover", true)

            local function PositionLauncher()
                local anchor = professionsFrame.ProfessionsOverviewTab
                for index = 1, 7 do
                    local candidate = professionsFrame["Professions" .. index .. "Tab"]
                    if candidate and candidate:IsShown() then anchor = candidate end
                end
                bookButton:ClearAllPoints()
                if anchor then
                    bookButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
                else
                    bookButton:SetPoint("TOPLEFT", professionsFrame, "TOPRIGHT", 0, -60)
                end
            end

            local function PositionContent()
                professionFrame:SetParent(UIParent)
                professionFrame:SetScale(1)
                professionFrame:SetFrameStrata("HIGH")
                professionFrame:SetFrameLevel(500)
                professionFrame:ClearAllPoints()
                professionFrame:SetPoint("TOPLEFT", professionsFrame, "TOPLEFT", 8, -60)
                professionFrame:SetPoint("BOTTOMRIGHT", professionsFrame, "BOTTOMRIGHT", -8, 8)

                professionListBg:ClearAllPoints()
                professionListBg:SetAllPoints(professionFrame)
                professionListBg:Show()
                professionNativeInsetBg:ClearAllPoints()
                professionNativeInsetBg:SetAllPoints(professionFrame)
                professionNativeInsetBg:Show()
                if professionNativeInsetBg.Bg then professionNativeInsetBg.Bg:Hide() end

                professionSearchBox:ClearAllPoints()
                professionSearchBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 12, -10)
                professionSearchBox:SetPoint("TOPRIGHT", professionFrame, "TOPRIGHT", -12, -10)
                professionScrollBox:ClearAllPoints()
                professionScrollBox:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 8, -38)
                professionScrollBox:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -24, 13)
            end

            local function SetSelected(value)
                selected:SetShown(value == true)
            end

            local function ClearNativeSnapshot()
                nativeCraftingWasShown = nil
            end

            local function CloseCustomPage(restoreNative)
                if not customOpen then return end
                customOpen = false
                professionFrame:Hide()
                SetSelected(false)
                if restoreNative and nativeCraftingWasShown ~= nil then
                    craftingPage:SetShown(nativeCraftingWasShown)
                end
                ClearNativeSnapshot()
            end

            local function OpenCustomPage()
                if InCombatLockdown and InCombatLockdown() then
                    if ns.Chat then ns:Chat("Training", "Cannot change Profession pages during combat.") end
                    return
                end
                if not Trainer.tooltipActive or not CurrentProfessionInfo() then return end
                if not customOpen then
                    nativeCraftingWasShown = craftingPage:IsShown()
                    customOpen = true
                end
                craftingPage:Hide()
                professionViewMode = PROFESSION_VIEW_TRAINING
                PositionContent()
                SetSelected(true)
                professionFrame:Show()
                Trainer.ProfessionRefresh()
            end

            local function UpdateLauncher()
                local shown = Trainer.tooltipActive == true and professionsFrame:IsShown()
                    and CurrentProfessionInfo() ~= nil
                PositionLauncher()
                bookButton:SetShown(shown)
                if not shown and customOpen then CloseCustomPage(false) end
            end

            local function RefreshAfterNativeChange()
                refreshQueued = false
                if not Trainer.tooltipActive or not professionsFrame:IsShown() then
                    bookButton:Hide()
                    CloseCustomPage(false)
                    return
                end
                local info = CurrentProfessionInfo()
                if not info then
                    bookButton:Hide()
                    -- Blizzard has navigated to its Overview page. Preserve the
                    -- newly selected native page rather than restoring the old
                    -- CraftingPage snapshot over it.
                    CloseCustomPage(false)
                    return
                end
                UpdateLauncher()
                if customOpen then
                    craftingPage:Hide()
                    PositionContent()
                    Trainer.ProfessionRefresh()
                end
            end

            local function QueueRefreshAfterNativeChange()
                if refreshQueued then return end
                refreshQueued = true
                C_Timer.After(0, RefreshAfterNativeChange)
            end

            bookButton:SetScript("OnClick", function()
                if ns.PlayUISound then ns:PlayUISound("pageTurn") end
                if customOpen then CloseCustomPage(true) else OpenCustomPage() end
            end)
            bookButton:SetScript("OnEnter", function(self)
                local info = CurrentProfessionInfo()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText((info and info.professionName and (info.professionName .. " Training")) or L.LID_TRAINING)
                GameTooltip:Show()
            end)
            bookButton:SetScript("OnLeave", GameTooltip_Hide)
            bookButton:SetScript("OnHide", GameTooltip_Hide)

            professionsFrame:HookScript("OnShow", QueueRefreshAfterNativeChange)
            professionsFrame:HookScript("OnHide", function()
                C_Timer.After(0, function()
                    bookButton:Hide()
                    CloseCustomPage(true)
                end)
            end)
            if professionsFrame.SetScale then
                hooksecurefunc(professionsFrame, "SetScale", function()
                    C_Timer.After(0, function()
                        if professionsFrame:IsShown() then
                            PositionLauncher()
                            if customOpen then PositionContent() end
                        end
                    end)
                end)
            end

            local controller = {}
            function controller:SetActive(active)
                if not active then
                    bookButton:Hide()
                    CloseCustomPage(true)
                    return
                end
                UpdateLauncher()
            end
            function controller:NativeDataChanged()
                QueueRefreshAfterNativeChange()
            end

            Trainer.ForeverProfessionFrame = professionsFrame
            Trainer.ForeverProfessionBookTab = bookButton
            Trainer.ForeverProfessionDetached = true
            professionUI = controller
            return controller
        end

        local function TryInitializeForeverProfessions()
            if not Trainer.tooltipActive then return end
            local controller = InitializeForeverProfessions()
            if controller then
                loader:UnregisterEvent("ADDON_LOADED")
                controller:SetActive(true)
            end
        end

        loader:SetScript("OnEvent", function(_, event, addonName)
            if event == "ADDON_LOADED" and addonName == "Blizzard_Professions" then
                TryInitializeForeverProfessions()
            end
        end)

        local tradeSkillWatcher = CreateFrame("Frame")
        local function RegisterTradeSkillEvent(event)
            if ns.API and ns.API.RegisterEvent then
                return ns.API.RegisterEvent(tradeSkillWatcher, event)
            end
            return pcall(tradeSkillWatcher.RegisterEvent, tradeSkillWatcher, event)
        end

        function Trainer:SetProfessionEvents(active)
            tradeSkillWatcher:UnregisterAllEvents()
            if not active then return end
            RegisterTradeSkillEvent("TRADE_SKILL_SHOW")
            RegisterTradeSkillEvent("TRADE_SKILL_UPDATE")
            RegisterTradeSkillEvent("TRADE_SKILL_LIST_UPDATE")
            RegisterTradeSkillEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
            RegisterTradeSkillEvent("TRADE_SKILL_DETAILS_UPDATE")
            RegisterTradeSkillEvent("TRADE_SKILL_NAME_UPDATE")
        end

        tradeSkillWatcher:SetScript("OnEvent", function()
            TryInitializeForeverProfessions()
            if professionUI then professionUI:NativeDataChanged() end
        end)

        function Trainer:RefreshProfessionUI(active)
            if active then
                if professionUI then
                    professionUI:SetActive(true)
                else
                    loader:RegisterEvent("ADDON_LOADED")
                    TryInitializeForeverProfessions()
                end
            else
                loader:UnregisterEvent("ADDON_LOADED")
                if professionUI then professionUI:SetActive(false) end
                professionFrame:Hide()
            end
        end

        Trainer:RefreshProfessionUI(Trainer.tooltipActive == true)
        return
    end

    if TradeSkillFrame then hooksecurefunc(TradeSkillFrame, "SetScale", function() if Trainer.tooltipActive and classFrame:IsShown() then PositionProfessionFrame() end end) end
    local function CreateTradeSkillTab(name, icon)
        local tab = CreateFrame("Button", name, UIParent)
        tab:SetSize(32, 32)
        tab:SetNormalTexture(icon)
        tab:SetHighlightTexture(130718, "ADD")
        tab:SetFrameStrata("HIGH")
        tab:SetFrameLevel(500)
        tab:Hide()
        local border = tab:CreateTexture(name .. "Border", "BACKGROUND")
        border:SetSize(64, 64)
        border:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
        border:SetTexture(136831)
        local glow = tab:CreateTexture(nil, "OVERLAY")
        glow:SetSize(32, 32)
        glow:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        glow:SetTexture(130724)
        glow:SetBlendMode("ADD")
        glow:Hide()
        return tab, glow
    end

    local nativeTab, nativeTabGlow = CreateTradeSkillTab("TurboFaceTrainerTradeSkillNativeTab", "Interface\\Icons\\ability_kick")
    local professionTab, professionTabGlow = CreateTradeSkillTab("TurboFaceTrainerTradeSkillProfessionTab", "Interface\\Icons\\INV_Misc_Book_09")
    local recipeTab, recipeTabGlow = CreateTradeSkillTab("TurboFaceTrainerTradeSkillRecipeTab", "Interface\\Icons\\INV_Scroll_03")
    local function PositionTradeSkillTabs()
        C_Timer.After(Trainer:IsDragonflightUIEnabled() and 0.1 or 0, function()
            if not Trainer.tooltipActive then return end
            if Trainer:IsDragonflightUIEnabled() and DragonflightUIProfessionFrame and DragonflightUIProfessionFrame:IsShown() then
                local scale = DragonflightUIProfessionFrame:GetScale()
                nativeTab:SetScale(scale)
                professionTab:SetScale(scale)
                recipeTab:SetScale(scale)
                nativeTab:ClearAllPoints()
                nativeTab:SetPoint("TOPLEFT", DragonflightUIProfessionFrame, "TOPRIGHT", 0, -60)
                professionTab:ClearAllPoints()
                professionTab:SetPoint("TOPLEFT", nativeTab, "BOTTOMLEFT", 0, -16)
                recipeTab:ClearAllPoints()
                recipeTab:SetPoint("TOPLEFT", professionTab, "BOTTOMLEFT", 0, -16)
            else
                if TradeSkillFrame then
                    local scale = TradeSkillFrame:GetScale()
                    nativeTab:SetScale(scale)
                    professionTab:SetScale(scale)
                    recipeTab:SetScale(scale)
                    nativeTab:ClearAllPoints()
                    nativeTab:SetPoint("TOPLEFT", TradeSkillFrame, "TOPRIGHT", -33, -60)
                    professionTab:ClearAllPoints()
                    professionTab:SetPoint("TOPLEFT", nativeTab, "BOTTOMLEFT", 0, -16)
                    recipeTab:ClearAllPoints()
                    recipeTab:SetPoint("TOPLEFT", professionTab, "BOTTOMLEFT", 0, -16)
                end
            end
        end)
    end

    local NATIVE_TRADESKILL_WIDGETS = {"TradeSkillSubClassDropdown", "TradeSkillInvSlotDropdown", "TradeSkillRankFrame", "TradeSkillRankFrameBorder"}
    local function HideNativeTradeSkillWidgets()
        for _, name in ipairs(NATIVE_TRADESKILL_WIDGETS) do
            local widget = _G[name]
            if widget then widget:Hide() end
        end
    end

    local function ShowNativeTradeSkillWidgets()
        for _, name in ipairs(NATIVE_TRADESKILL_WIDGETS) do
            local widget = _G[name]
            if widget then widget:Show() end
        end
    end

    local function SetTradeSkillView(mode)
        if mode == PROFESSION_VIEW_TRAINING or mode == PROFESSION_VIEW_RECIPES then
            professionViewMode = mode
            C_Timer.After(Trainer:IsDragonflightUIEnabled() and 0.1 or 0, function()
                if not Trainer.tooltipActive then return end
                if Trainer:IsDragonflightUIEnabled() and DragonflightUIProfessionFrame and DragonflightUIProfessionFrame:IsShown() then
                    professionNativeInsetBg:Hide()
                    professionListBg:Show()
                    professionListBg:ClearAllPoints()
                    professionListBg:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 4, -32)
                    professionListBg:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", 4, -2)
                    professionListBg:SetColorTexture(0, 0, 0, 1)
                    if DragonflightUIProfessionRankFrame then DragonflightUIProfessionRankFrame:Hide() end
                elseif Trainer:IsLeatrixWideProfessionEnabled() then
                    professionNativeInsetBg:Hide()
                    professionListBg:Show()
                    professionListBg:ClearAllPoints()
                    professionListBg:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 0, -2)
                    professionListBg:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -2, -16)
                    professionListBg:SetColorTexture(0, 0, 0, 1)
                else
                    professionListBg:Hide()
                    professionNativeInsetBg:ClearAllPoints()
                    professionNativeInsetBg:SetPoint("TOPLEFT", professionFrame, "TOPLEFT", 4, -2)
                    professionNativeInsetBg:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -2, 0)
                    professionNativeInsetBg:Show()
                    if TradeSkillFrameAvailableFilterCheckButton then TradeSkillFrameAvailableFilterCheckButton:Hide() end
                    if TradeSearchInputBox then TradeSearchInputBox:Hide() end
                end

                PositionProfessionFrame()
                professionFrame:Show()
                nativeTabGlow:Hide()
                if mode == PROFESSION_VIEW_RECIPES then
                    recipeTabGlow:Show()
                    professionTabGlow:Hide()
                else
                    professionTabGlow:Show()
                    recipeTabGlow:Hide()
                end

                HideNativeTradeSkillWidgets()
                Trainer.ProfessionRefresh()
            end)
        else
            professionFrame:Hide()
            professionTabGlow:Hide()
            recipeTabGlow:Hide()
            nativeTabGlow:Show()
            ShowNativeTradeSkillWidgets()
        end
    end

    -- Sound sits on the three handlers rather than inside SetTradeSkillView,
    -- which is also called programmatically on TRADE_SKILL_SHOW and when the
    -- window closes -- those must not click. Matches the spellbook tab.
    nativeTab:SetScript("OnClick", function()
        ns:PlayUISound("pageTurn")
        SetTradeSkillView("native")
    end)
    nativeTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((GetTradeSkillLine and GetTradeSkillLine()) or L.LID_PROFESSIONS)
        GameTooltip:Show()
    end)

    nativeTab:SetScript("OnLeave", GameTooltip_Hide)
    professionTab:SetScript("OnClick", function()
        ns:PlayUISound("pageTurn")
        SetTradeSkillView(PROFESSION_VIEW_TRAINING)
    end)
    professionTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.LID_TRAINING)
        GameTooltip:Show()
    end)

    professionTab:SetScript("OnLeave", GameTooltip_Hide)
    recipeTab:SetScript("OnClick", function()
        ns:PlayUISound("pageTurn")
        SetTradeSkillView(PROFESSION_VIEW_RECIPES)
    end)
    recipeTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.LID_RECIPES)
        GameTooltip:Show()
    end)

    recipeTab:SetScript("OnLeave", GameTooltip_Hide)

    function Trainer:RefreshProfessionUI(active)
        if not active then
            professionFrame:Hide()
            nativeTabGlow:Hide()
            professionTabGlow:Hide()
            recipeTabGlow:Hide()
            nativeTab:Hide()
            professionTab:Hide()
            recipeTab:Hide()
            ShowNativeTradeSkillWidgets()
            return
        end
        if TradeSkillFrame and TradeSkillFrame:IsShown() then
            PositionTradeSkillTabs()
            nativeTab:Show()
            professionTab:Show()
            recipeTab:Show()
        end
    end

    local tradeSkillHooksInstalled = false
    local function EnsureTradeSkillHooksInstalled()
        if tradeSkillHooksInstalled then return end
        if not TradeSkillFrame then return end
        tradeSkillHooksInstalled = true
        TradeSkillFrame:HookScript("OnShow", function()
            if not Trainer.tooltipActive then
                professionFrame:Hide()
                nativeTab:Hide()
                professionTab:Hide()
                recipeTab:Hide()
                ShowNativeTradeSkillWidgets()
                return
            end
            PositionTradeSkillTabs()
            nativeTab:Show()
            professionTab:Show()
            recipeTab:Show()
            SetTradeSkillView("native")
        end)

        TradeSkillFrame:HookScript("OnHide", function()
            professionFrame:Hide()
            professionTabGlow:Hide()
            recipeTabGlow:Hide()
            nativeTabGlow:Hide()
            nativeTab:Hide()
            professionTab:Hide()
            recipeTab:Hide()
            ShowNativeTradeSkillWidgets()
        end)

        hooksecurefunc(TradeSkillFrame, "SetScale", function()
            if not Trainer.tooltipActive then return end
            PositionTradeSkillTabs()
            if professionFrame:IsShown() then PositionProfessionFrame() end
        end)

        if Trainer.tooltipActive and TradeSkillFrame:IsShown() then
            PositionTradeSkillTabs()
            nativeTab:Show()
            professionTab:Show()
            recipeTab:Show()
            SetTradeSkillView("native")
        end

        C_Timer.After(4, function()
            for i = 1, 4 do
                local t = _G["DragonflightUIProfessionFrameTabButton" .. i]
                if t then t:HookScript("OnClick", function()
                    if Trainer.tooltipActive then SetTradeSkillView("native") end
                end) end
            end

            if DragonflightUIProfessionFrame then hooksecurefunc(DragonflightUIProfessionFrame, "SetScale", function() if Trainer.tooltipActive and professionFrame:IsShown() then PositionProfessionFrame() end end) end
        end)
    end

    local tradeSkillWatcher = CreateFrame("Frame")
    local function RegisterTradeSkillEvent(event)
        if ns.API and ns.API.RegisterEvent then
            return ns.API.RegisterEvent(tradeSkillWatcher, event)
        end
        return pcall(tradeSkillWatcher.RegisterEvent, tradeSkillWatcher, event)
    end

    function Trainer:SetProfessionEvents(active)
        tradeSkillWatcher:UnregisterAllEvents()
        if not active then return end

        -- Event names differ between Era and Forever/modern clients.  Register
        -- every useful candidate through the compatibility wrapper so an event
        -- removed by Blizzard can never abort Trainer initialization.
        RegisterTradeSkillEvent("TRADE_SKILL_SHOW")
        RegisterTradeSkillEvent("TRADE_SKILL_UPDATE")          -- Era / legacy
        RegisterTradeSkillEvent("TRADE_SKILL_LIST_UPDATE")     -- modern recipe list
        RegisterTradeSkillEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
        RegisterTradeSkillEvent("TRADE_SKILL_DETAILS_UPDATE")
        RegisterTradeSkillEvent("TRADE_SKILL_NAME_UPDATE")
    end

    tradeSkillWatcher:SetScript("OnEvent", function(_, event)
        if not Trainer.tooltipActive then return end
        EnsureTradeSkillHooksInstalled()

        local isRefreshEvent = event == "TRADE_SKILL_UPDATE"
            or event == "TRADE_SKILL_LIST_UPDATE"
            or event == "TRADE_SKILL_DATA_SOURCE_CHANGED"
            or event == "TRADE_SKILL_DETAILS_UPDATE"
            or event == "TRADE_SKILL_NAME_UPDATE"

        if isRefreshEvent and professionFrame:IsShown() then
            Trainer.ProfessionRefresh()
            HideNativeTradeSkillWidgets()
        end
    end)
end)
