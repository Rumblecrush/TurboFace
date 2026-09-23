local _, ns = ...

-- =============================================================================
-- TurboFace skill engine + tracker
--
-- One scanner over the player's skill lines, shared by every consumer:
-- the HUD column here, Trainer/UI_Profession's rank checks, and /tf debug
-- trainer. Two ad-hoc scanners existed before this and both carried the same
-- latent bug (see COLLAPSED HEADERS below), which is the main reason the engine
-- is worth having rather than a third copy of the loop.
--
-- COLLAPSED HEADERS
-- GetNumSkillLines() enumerates only the lines currently VISIBLE in Blizzard's
-- skill panel. A collapsed header hides its children, so a naive scan silently
-- returns nothing for a profession the player has simply collapsed -- the
-- Trainer rank check read 0/0 and quietly stopped working. Scan() expands what
-- it must, reads, then restores the player's collapse state by name, because
-- indices shift as headers expand.
--
-- CATEGORISATION avoids localized header text entirely:
--   professions/secondary -> matched via the shared profession name map,
--                            which is built from C_Spell.GetSpellInfo and is
--                            therefore already in the client's locale
--   weapon/defense        -> maxRank == 5 * player level, which is exactly how
--                            Classic caps weapon skills. No name list, no
--                            locale dependency.
--   everything else       -> ignored (languages, class skills, armor
--                            proficiencies are out of scope)
-- =============================================================================

local SK = {}
ns.Skills = SK

local CreateFrame        = CreateFrame
local GetNumSkillLines   = GetNumSkillLines
local GetSkillLineInfo   = GetSkillLineInfo
local ExpandSkillHeader  = ExpandSkillHeader
local CollapseSkillHeader = CollapseSkillHeader
local UnitLevel          = UnitLevel
local GetInventoryItemLink = GetInventoryItemLink
local GetItemInfoInstant = ns.API.GetItemInfoInstant
local GetItemInfo        = ns.API.GetItemInfo

local CAT_PROFESSION = "profession"
local CAT_SECONDARY  = "secondary"
local CAT_WEAPON     = "weapon"

-- Weapon skill icons. Unlike professions there is no spell to read an icon
-- from, so this is a name map with a generic fallback -- on a non-English
-- client every weapon skill simply shows the fallback rather than breaking.
local WEAPON_ICONS = {
    ["defense"]      = "Interface\\Icons\\Ability_Defend",
    ["unarmed"]      = "Interface\\Icons\\Ability_GolemThunderClap",
    ["daggers"]      = "Interface\\Icons\\INV_Weapon_ShortBlade_05",
    ["swords"]       = "Interface\\Icons\\INV_Sword_04",
    ["two-handed swords"] = "Interface\\Icons\\INV_Sword_09",
    ["axes"]         = "Interface\\Icons\\INV_Axe_01",
    ["two-handed axes"]   = "Interface\\Icons\\INV_Axe_09",
    ["maces"]        = "Interface\\Icons\\INV_Mace_01",
    ["two-handed maces"]  = "Interface\\Icons\\INV_Hammer_16",
    ["polearms"]     = "Interface\\Icons\\INV_Spear_06",
    ["staves"]       = "Interface\\Icons\\INV_Staff_08",
    ["bows"]         = "Interface\\Icons\\INV_Weapon_Bow_07",
    ["crossbows"]    = "Interface\\Icons\\INV_Weapon_Crossbow_02",
    ["guns"]         = "Interface\\Icons\\INV_Weapon_Rifle_01",
    ["thrown"]       = "Interface\\Icons\\INV_ThrowingAxe_01",
    ["wands"]        = "Interface\\Icons\\INV_Wand_01",
    ["fist weapons"] = "Interface\\Icons\\INV_Gauntlets_04",
}
local WEAPON_ICON_FALLBACK = "Interface\\Icons\\Ability_MeleeDamage"

-- Item subclasses are client-stable numeric IDs, unlike localized item and
-- skill-line names. The tracker checks main hand, off hand, and ranged slots,
-- yielding at most three distinct equipped-weapon rows.
local WEAPON_SKILL_BY_SUBCLASS = {
    [0] = "axes", [1] = "two-handed axes", [2] = "bows", [3] = "guns",
    [4] = "maces", [5] = "two-handed maces", [6] = "polearms",
    [7] = "swords", [8] = "two-handed swords", [10] = "staves",
    [13] = "fist weapons", [15] = "daggers", [16] = "thrown",
    [18] = "crossbows", [19] = "wands",
}
local WEAPON_SKILL_BY_SUBTYPE = {
    ["one-handed axes"] = "axes", ["two-handed axes"] = "two-handed axes",
    ["bows"] = "bows", ["guns"] = "guns",
    ["one-handed maces"] = "maces", ["two-handed maces"] = "two-handed maces",
    ["polearms"] = "polearms", ["one-handed swords"] = "swords",
    ["two-handed swords"] = "two-handed swords", ["staves"] = "staves",
    ["fist weapons"] = "fist weapons", ["daggers"] = "daggers",
    ["thrown"] = "thrown", ["crossbows"] = "crossbows", ["wands"] = "wands",
}
local EQUIPPED_WEAPON_SLOTS = { 16, 17, 18 } -- main hand, off hand, ranged

local cache, cacheDirty = nil, true
local display, rows, eventFrame

local DB = ns.DB   -- shared root accessor (Config.lua)

local function Enabled()
    local on = DB().skillTrackerEnabled == true
    return ns.MoverDependentEnabled(on)
end

-- -----------------------------------------------------------------------------
-- Scanning
-- -----------------------------------------------------------------------------

-- Records which headers are collapsed, expands everything, and returns the list
-- of collapsed header names so Restore can put them back. Returns nil when
-- nothing needed expanding, which is the common case and costs one pass.
local function ExpandAllHeaders()
    if not GetNumSkillLines or not GetSkillLineInfo or not ExpandSkillHeader then return nil end

    local collapsed
    for i = 1, GetNumSkillLines() do
        local name, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and name then
            collapsed = collapsed or {}
            collapsed[#collapsed + 1] = name
        end
    end
    if not collapsed then return nil end

    -- Index 0 expands every header at once.
    ExpandSkillHeader(0)
    return collapsed
end

local function RestoreHeaders(collapsed)
    if not collapsed or not CollapseSkillHeader then return end
    -- Re-collapse by name: expanding shifted every index, so the values we
    -- recorded are no longer valid positions.
    local wanted = {}
    for i = 1, #collapsed do wanted[collapsed[i]] = true end

    for i = GetNumSkillLines(), 1, -1 do
        local name, isHeader = GetSkillLineInfo(i)
        if isHeader and name and wanted[name] then
            CollapseSkillHeader(i)
        end
    end
end

local function Categorize(name, maxRank)
    local P = ns.ProfessionData
    if P then
        local key = P:GetKey(name)
        if key then
            return P:IsSecondary(key) and CAT_SECONDARY or CAT_PROFESSION, key
        end
    end

    -- Weapon skills and Defense cap at 5x level in Classic. Guard against a
    -- level-1 edge where the cap coincides with something else by requiring a
    -- positive cap.
    local level = UnitLevel and UnitLevel("player") or 0
    if level > 0 and maxRank and maxRank > 0 and maxRank == level * 5 then
        return CAT_WEAPON, nil
    end

    return nil, nil
end

local function IconFor(category, key, name)
    if category == CAT_PROFESSION or category == CAT_SECONDARY then
        local P = ns.ProfessionData
        local icon = P and P:GetIcon(key) or nil
        if icon then return icon end
    elseif category == CAT_WEAPON and name then
        return WEAPON_ICONS[name:lower()] or WEAPON_ICON_FALLBACK
    end
    return WEAPON_ICON_FALLBACK
end

-- Class skill lines ("Balance", "Feral Combat", "Restoration"...) also cap at
-- 5 x level, so the weapon-skill test alone cannot tell them apart -- a level 18
-- druid saw three spurious 90/90 rows.
--
-- The class skill lines are exactly the talent tab names, and GetTalentTabInfo
-- returns those localized by the client. That gives a locale-proof identifier
-- with no name list to maintain.
--
-- Used two ways: to skip those lines directly, and to mark the header they sit
-- under so any other class skill beneath it (a rogue's Lockpicking, say) is
-- excluded as well rather than being mistaken for a weapon skill.
local function GetTalentTabNames()
    local names = {}
    if not GetNumTalentTabs or not GetTalentTabInfo then return names end
    local ok, count = pcall(GetNumTalentTabs)
    if not ok or not count then return names end

    for i = 1, count do
        -- Return order is not the same across clients: Classic Era returns the
        -- tab ID first and the name second (a druid reports 283/281/282, not
        -- Balance/Feral Combat/Restoration), while other builds put the name
        -- first. Comparing against the ID silently matched nothing, which is why
        -- three 90/90 class rows kept appearing.
        --
        -- So take the first return that is a genuine, non-numeric string rather
        -- than trusting either position.
        local okInfo, a, b = pcall(GetTalentTabInfo, i)
        if okInfo then
            local candidate
            if type(b) == "string" and b ~= "" and not tonumber(b) then
                candidate = b
            elseif type(a) == "string" and a ~= "" and not tonumber(a) then
                candidate = a
            end
            if candidate then names[candidate] = true end
        end
    end
    return names
end

function SK:Scan()
    local out = { [CAT_PROFESSION] = {}, [CAT_SECONDARY] = {}, [CAT_WEAPON] = {}, byName = {}, byKey = {} }
    if not GetNumSkillLines or not GetSkillLineInfo then
        cache, cacheDirty = out, false
        return out
    end

    local collapsed = ExpandAllHeaders()
    local talentTabs = GetTalentTabNames()

    -- First pass: read the lines and note which header each sits under, so a
    -- header holding a talent-tab name can disqualify all of its children.
    local lines, headerOf = {}, {}
    local currentHeader, classHeaders = nil, {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(i)
        if isHeader then
            currentHeader = name
        elseif name then
            lines[#lines + 1] = {
                name = name, rank = rank or 0, maxRank = maxRank or 0,
                modifier = modifier or 0,
            }
            headerOf[#lines] = currentHeader
            if talentTabs[name] and currentHeader then
                classHeaders[currentHeader] = true
            end
        end
    end

    RestoreHeaders(collapsed)

    for index = 1, #lines do
        local line = lines[index]
        local header = headerOf[index]
        local excluded = talentTabs[line.name] or (header and classHeaders[header])

        if not excluded then
            local category, key = Categorize(line.name, line.maxRank)
            if category then
                local entry = {
                    name = line.name,
                    key = key,
                    rank = line.rank,
                    maxRank = line.maxRank,
                    modifier = line.modifier,
                    category = category,
                    icon = IconFor(category, key, line.name),
                }
                out[category][#out[category] + 1] = entry
                out.byName[line.name] = entry
                if key then out.byKey[key] = entry end
            end
        end
    end

    -- Stable ordering: professions and secondary alphabetically, weapon skills
    -- by rank descending so the ones actually being levelled sit at the top.
    table.sort(out[CAT_PROFESSION], function(a, b) return a.name < b.name end)
    table.sort(out[CAT_SECONDARY], function(a, b) return a.name < b.name end)
    table.sort(out[CAT_WEAPON], function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name < b.name
    end)

    cache, cacheDirty = out, false
    return out
end

-- Lazy: nothing rescans until something asks and an event marked it dirty.
function SK:GetAll()
    if cacheDirty or not cache then return self:Scan() end
    return cache
end

-- The shared lookup. Returns rank, maxRank, modifier, category.
function SK:Get(name)
    if not name then return nil end
    local data = self:GetAll()
    local entry = data.byName[name]

    -- Profession spell names and legacy skill-line names are not guaranteed to
    -- be identical in Classic Era (for example, the spellbook can say
    -- "Herb Gathering" while GetSkillLineInfo reports "Herbalism"). Resolve
    -- either form through ProfessionData's canonical key before giving up.
    if not entry and ns.ProfessionData and ns.ProfessionData.GetKey then
        local key = ns.ProfessionData:GetKey(name)
        entry = key and data.byKey and data.byKey[key] or nil
    end

    if not entry then return nil end
    return entry.rank, entry.maxRank, entry.modifier, entry.category
end

function SK:Invalidate() cacheDirty = true end

-- A level-up changes the 5x-level cap used by weapon skills, but does not change
-- profession membership/ranks or the identity of the cached skill lines. Update
-- only that cap in-place rather than expanding/collapsing Blizzard skill headers
-- and rebuilding the entire shared scanner cache for one numeric change.
local function RefreshCachedWeaponCaps(level)
    if cacheDirty or type(cache) ~= "table" then return false end
    level = tonumber(level) or (UnitLevel and UnitLevel("player")) or 0
    if level <= 0 then return false end
    local cap = level * 5
    local weapons = cache[CAT_WEAPON]
    if type(weapons) ~= "table" then return false end
    for i = 1, #weapons do
        local entry = weapons[i]
        if entry then entry.maxRank = cap end
    end
    return true
end

-- -----------------------------------------------------------------------------
-- Display: a HUD column, same spirit as the FPS counter
-- -----------------------------------------------------------------------------

local function Fallback()
    return { "TOPLEFT", UIParent, "TOPLEFT", 10, -200 }
end

function SK:GetFrame() return display end
function SK:GetChildren() return display and { display } or {} end

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "TurboFaceSkillTracker", UIParent)
    display:SetSize(90, 20)
    display:SetPoint(unpack(Fallback()))
    display:SetFrameStrata("LOW")
    display:EnableMouse(false)
    rows = {}
    return display
end

local function EnsureRow(index)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, display)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    -- Trim the default icon border so small icons do not look muddy.
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetTextColor(1, 1, 1)

    rows[index] = row
    return row
end

local function CategoryEnabled(db, category)
    if category == CAT_PROFESSION then return db.skillTrackerProfessions ~= false end
    if category == CAT_SECONDARY then return db.skillTrackerSecondary ~= false end
    if category == CAT_WEAPON then return db.skillTrackerWeapons ~= false end
    return false
end

local function EquippedWeaponSkillSet()
    -- Defense is universal combat progression. Unarmed replaces absent melee
    -- weapons, while the actual equipped weapon types remain the filtered rows.
    local wanted = { ["defense"] = true }
    local hasMeleeWeapon = false
    if not GetInventoryItemLink then return wanted end

    for _, slot in ipairs(EQUIPPED_WEAPON_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local classID, subclassID
            if GetItemInfoInstant then
                local _, _, _, _, _, itemClass, itemSubclass = GetItemInfoInstant(link)
                classID, subclassID = itemClass, itemSubclass
            end
            if classID == 2 then -- LE_ITEM_CLASS_WEAPON
                local skill = WEAPON_SKILL_BY_SUBCLASS[subclassID]
                if skill then
                    wanted[skill] = true
                    if slot == 16 or slot == 17 then hasMeleeWeapon = true end
                end
            elseif GetItemInfo then
                -- Compatibility fallback for clients that do not expose item
                -- class IDs through GetItemInfoInstant. TurboFace is English-
                -- only, so these Classic subtype labels are a safe fallback.
                local _, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
                if itemType == "Weapon" and itemSubType then
                    local skill = WEAPON_SKILL_BY_SUBTYPE[itemSubType:lower()]
                    if skill then
                        wanted[skill] = true
                        if slot == 16 or slot == 17 then hasMeleeWeapon = true end
                    end
                end
            end
        end
    end

    if not hasMeleeWeapon then wanted["unarmed"] = true end
    return wanted
end

function SK:Update()
    if not display then return end

    local db = DB()
    if not Enabled() then
        display:Hide()
        return
    end
    display:Show()

    local data = self:GetAll()
    local fontSize = tonumber(db.skillTrackerFontSize) or 12
    local iconSize = tonumber(db.skillTrackerIconSize) or 14
    local spacing = tonumber(db.skillTrackerSpacing) or 2
    local rowHeight = math.max(iconSize, fontSize + 2)
    local equippedWeapons = db.skillTrackerEquippedWeaponsOnly == true
        and EquippedWeaponSkillSet() or nil

    local index, width = 0, 0
    for _, category in ipairs({ CAT_PROFESSION, CAT_SECONDARY, CAT_WEAPON }) do
        if CategoryEnabled(db, category) then
            for _, entry in ipairs(data[category]) do
                local include = not (category == CAT_WEAPON and equippedWeapons)
                    or equippedWeapons[entry.name:lower()] == true
                if include then
                    index = index + 1
                    local row = EnsureRow(index)
                    row:SetSize(120, rowHeight)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", display, "TOPLEFT", 0, -((index - 1) * (rowHeight + spacing)))

                    row.icon:SetTexture(entry.icon)
                    row.icon:SetSize(iconSize, iconSize)
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

                    local label = string.format("%d / %d", entry.rank, entry.maxRank)
                -- A temporary buff or item bonus reads as a modifier; show it so
                -- the number is not silently inflated.
                    if entry.modifier and entry.modifier ~= 0 then
                        label = string.format("%d|cff40ff40+%d|r / %d", entry.rank, entry.modifier, entry.maxRank)
                    end

                    row.text:SetText(label)
                    if ns.StyleFeatureFont then
                        ns:StyleFeatureFont(row.text, fontSize, "skillTrackerFont", "skillTrackerTextStyle")
                    end
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)

                -- Colour by headroom: at cap is the state worth noticing.
                    if entry.maxRank > 0 and entry.rank >= entry.maxRank then
                        row.text:SetTextColor(1, 0.82, 0)
                    else
                        row.text:SetTextColor(1, 1, 1)
                    end

                    row:Show()
                    local w = iconSize + 4 + (row.text:GetStringWidth() or 40)
                    if w > width then width = w end
                end
            end
        end
    end

    for i = index + 1, #rows do rows[i]:Hide() end

    local height = (index > 0) and (index * rowHeight + math.max(0, index - 1) * spacing) or 20
    display:SetSize(math.max(40, width), height)

    if self._lastRowCount ~= index then
        self._lastRowCount = index
        -- Re-register so the mover hit area matches the new size.
        self:RegisterMover()
    end
end

function SK:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    local fallback = Fallback()
    ns.Movers:RegisterElement("SkillTracker", display, {
        label = "Skill Tracker",
        overlayWidth = (display.GetWidth and display:GetWidth()) or 90,
        overlayHeight = (display.GetHeight and display:GetHeight()) or 20,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        getChildren = function() return SK:GetChildren() end,
        onApply = function() SK:Update() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("SkillTracker") end
end

-- -----------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------

local function HandleEvent(_, event, arg1)
    -- Equipment changes only affect the optional equipped-weapon display
    -- filter. PLAYER_LEVEL_UP only changes the weapon/Defense max cap. Neither
    -- case needs the expensive shared skill-line rescan.
    if event == "PLAYER_LEVEL_UP" then
        RefreshCachedWeaponCaps(arg1)
    elseif event ~= "PLAYER_EQUIPMENT_CHANGED" then
        SK:Invalidate()
    end

    -- Coalesce: SKILL_LINES_CHANGED fires several times in a row on login and
    -- on every skill-up, and a scan may touch header state.
    if ns.After then
        if SK._pending then return end
        SK._pending = true
        ns.After(0.2, function()
            SK._pending = false
            SK:Update()
        end)
    else
        SK:Update()
    end
end

local function OnEvent(frame, event, ...)
    HandleEvent(frame, event, ...)
end

function SK:Init()
    EnsureDisplay()

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    self:Refresh()
end

function SK:Refresh()
    if not display then return end

    eventFrame:UnregisterAllEvents()
    if Enabled() then
        -- PLAYER_LEVEL_UP matters because weapon caps move with level, which is
        -- also what identifies them.
        pcall(eventFrame.RegisterEvent, eventFrame, "SKILL_LINES_CHANGED")
        pcall(eventFrame.RegisterEvent, eventFrame, "CHAT_MSG_SKILL")
        pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_LEVEL_UP")
        pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_ENTERING_WORLD")
        if DB().skillTrackerEquippedWeaponsOnly == true then
            pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_EQUIPMENT_CHANGED")
        end
        self:RegisterMover()
    end

    self:Invalidate()
    self:Update()
end

ns.RegisterCPUProfileTarget("Utility/Skills:Update", SK.Update)
ns.RegisterCPUProfileTarget("Utility/Skills:Events", OnEvent, false)
