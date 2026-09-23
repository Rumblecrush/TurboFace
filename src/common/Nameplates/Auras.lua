local _, ns = ...
local UnitBuff, UnitDebuff = ns.API.UnitBuff, ns.API.UnitDebuff

local Auras = ns.Auras or {}
ns.Auras = Auras
local initialized = false
local auraEventFrame

-- =============================================================================
-- LOCALIZED GLOBALS
-- =============================================================================
local UnitExists = ns.API.ReadUnitExists
local UnitIsFriend = ns.API.ReadUnitIsFriend
local GetTime = GetTime
local GetSpellInfo = ns.API.GetSpellInfo
local pairs, ipairs = pairs, ipairs
local tinsert, tremove, wipe = table.insert, table.remove, table.wipe
local floor, ceil = math.floor, math.ceil
local format = string.format
local rawget, rawset = rawget, rawset
local setmetatable = setmetatable
local unpack = unpack
local CreateFrame = CreateFrame
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear
local C_NamePlate = C_NamePlate
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local C_Timer = C_Timer
local AuraUtil = AuraUtil
local sort = table.sort

-- Ascension API (may or may not exist)

-- =============================================================================
-- CREATE TEXTURE BORDER UTILITY (uses shared system from Nameplates.lua)
-- =============================================================================
-- Borders come from the shared implementation in Nameplates.lua, which is
-- unconditionally loaded and publishes ns.CreateTextureBorder at file scope.
-- This file previously carried a full fallback copy "in case load order is
-- wrong". That copy was unreachable -- this is only called at runtime, long
-- after every file has loaded -- and had already drifted from the real one, so
-- a load-order accident would have silently produced differently-styled borders
-- rather than an obvious failure.
local function CreateTextureBorder(parent, thickness)
    return ns.CreateTextureBorder(parent, thickness)
end

-- =============================================================================
-- SPELL ICON CACHE
-- Lazy metatable caches icons on first access
-- =============================================================================
local IconCache = setmetatable({}, {
    __index = function(t, spellID)
        -- Only called if spellID not in cache
        local _, _, icon = GetSpellInfo(spellID)
        if icon then
            rawset(t, spellID, icon)  -- rawset bypasses __newindex
        end
        return icon
    end
})

-- Get cached icon - prefers aura data we already have
local function GetCachedIcon(spellID, iconFromAura)
    if iconFromAura then
        -- Cache from aura data (zero API calls)
        local cached = rawget(IconCache, spellID)
        if not cached then
            rawset(IconCache, spellID, iconFromAura)
        end
        return iconFromAura
    end
    -- Fallback: metatable triggers GetSpellInfo
    return IconCache[spellID]
end

-- =============================================================================
-- TIME STRING CACHE
-- Nameplate timers intentionally match AuraStyle/Blizzard countdown semantics:
-- ceiling-rounded whole units, seconds below 90s, and no sub-second phase.
-- =============================================================================
local secondTimeCache = setmetatable({}, {
    __index = function(t, k)
        local v = format("%d", k)
        rawset(t, k, v)
        return v
    end
})
local minuteTimeCache = setmetatable({}, {
    __index = function(t, k)
        local v = format("%dm", k)
        rawset(t, k, v)
        return v
    end
})
local hourTimeCache = setmetatable({}, {
    __index = function(t, k)
        local v = format("%dh", k)
        rawset(t, k, v)
        return v
    end
})

local function GetCachedTimeString(seconds)
    if seconds >= 3600 then
        return hourTimeCache[ceil(seconds / 3600)]
    elseif seconds >= 90 then
        return minuteTimeCache[ceil(seconds / 60)]
    elseif seconds > 0 then
        return secondTimeCache[ceil(seconds)]
    end
    return ""
end

-- =============================================================================
-- AURA DATA TABLE POOL
-- =============================================================================
local auraDataPool = {}
local MAX_DATA_POOL_SIZE = 100

local function AcquireAuraData()
    local data = tremove(auraDataPool)
    if not data then
        data = {}
    end
    return data
end

local function ReleaseAuraData(data)
    wipe(data)
    if #auraDataPool < MAX_DATA_POOL_SIZE then
        tinsert(auraDataPool, data)
    end
end

-- Release all aura data tables from a list back to pool
local function ReleaseAllAuraData(list)
    for i = #list, 1, -1 do
        ReleaseAuraData(list[i])
        list[i] = nil
    end
end

-- =============================================================================
-- REUSABLE COLLECTION TABLES
-- =============================================================================
local debuffCollector = {}
local buffCollector = {}

-- =============================================================================
-- BORDER COLORS
-- =============================================================================
local BORDER_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },  -- Blue (dispellable buffs on enemies)
    Curse   = { 0.60, 0.00, 1.00 },  -- Purple
    Disease = { 0.60, 0.40, 0.00 },  -- Brown
    Poison  = { 0.00, 0.60, 0.00 },  -- Green
    none    = { 0.80, 0.00, 0.00 },  -- Red (physical/no type debuffs)
}
local BUFF_COLOR_WHITE = { 1.00, 1.00, 1.00 }  -- White (non-dispellable buffs on enemies)

-- =============================================================================
-- TIMER COLORS
-- =============================================================================
local COLOR_WHITE = { 1.0, 1.0, 1.0 }

-- =============================================================================
-- TEXT ANCHOR POSITIONS
-- INNER positioning: Text stays inside the icon bounds
-- =============================================================================
local DURATION_ANCHORS = {
    -- {textPoint, iconPoint, offsetX, offsetY}
    TOP         = { "TOP", "TOP", 0, -2 },
    TOPLEFT     = { "TOPLEFT", "TOPLEFT", 2, -2 },
    TOPRIGHT    = { "TOPRIGHT", "TOPRIGHT", -2, -2 },
    CENTER      = { "CENTER", "CENTER", 0, 0 },
    BOTTOM      = { "BOTTOM", "BOTTOM", 0, 0 },
    BOTTOMLEFT  = { "BOTTOMLEFT", "BOTTOMLEFT", 2, 2 },
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2 },
}

-- OUTER positioning: the stack count sits just OUTSIDE the icon corner, unlike
-- the duration text above. Every offset pushes away from the icon centre.
local STACK_ANCHORS = {
    TOP         = { "TOP", "TOP", 0, 3 },
    TOPLEFT     = { "TOPLEFT", "TOPLEFT", -3, 3 },
    TOPRIGHT    = { "TOPRIGHT", "TOPRIGHT", 3, 3 },
    CENTER      = { "CENTER", "CENTER", 0, 0 },
    BOTTOM      = { "BOTTOM", "BOTTOM", 0, -3 },
    BOTTOMLEFT  = { "BOTTOMLEFT", "BOTTOMLEFT", -3, -3 },
    -- x was -3, a copy-paste of BOTTOMLEFT that pushed the count left instead
    -- of right and made the two anchors identical. Unreachable in practice --
    -- debuff stacks are forced to TOPRIGHT and buff stacks default to it.
    BOTTOMRIGHT = { "BOTTOMRIGHT", "BOTTOMRIGHT", 3, -3 },
}

-- =============================================================================
-- AURA ICON CREATION
-- Icon with square border, duration text, and stack count
-- =============================================================================
local BORDER_SIZE = 1  -- 1px thick square border

-- Swap an icon between the pixel border and Blizzard's rounded debuff ring.
--
-- Icons are pooled and reused, so building only the style current at creation
-- time would leave already-created icons on the old look after a settings
-- change. Both variants are kept once built and toggled by visibility; the
-- second is only allocated if that style is ever actually selected.
local function EnsureBorderStyle(icon)
    local want = ns.c_auraBorderStyle or "BLIZZARD"
    if icon._tfBorderStyle == want then return end

    if want == "BLIZZARD" then
        if not icon._tfBlizzBorder then
            icon._tfBlizzBorder = ns.CreateBlizzardAuraBorder(icon)
        end
        icon._tfPixelBorder = icon._tfPixelBorder or icon.border
        icon._tfPixelBorder:Hide()
        icon._tfBlizzBorder:Show()
        icon.border = icon._tfBlizzBorder
    else
        icon._tfPixelBorder = icon._tfPixelBorder or icon.border
        if icon._tfBlizzBorder then icon._tfBlizzBorder:Hide() end
        icon._tfPixelBorder:Show()
        icon.border = icon._tfPixelBorder
    end
    icon._tfBorderStyle = want
end

local function CreateAuraIcon(parent)
    local icon = CreateFrame("Frame", nil, parent)  -- No BackdropTemplate needed
    icon:SetSize(20, 20)
    icon:EnableMouse(false)  -- Pass through clicks

    -- Icon texture fills frame (border extends outside via CreateTextureBorder)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- 30% zoom

    -- Border style. Both variants expose the same :SetColor surface, so
    -- SetBorderColor and every filter/batching path below are unchanged.
    -- Built lazily and swapped by EnsureBorderStyle so a style change applies
    -- to pooled icons without a reload.
    icon.border = CreateTextureBorder(icon, BORDER_SIZE)
    icon._tfBorderStyle = "PIXEL"
    EnsureBorderStyle(icon)

    -- Nameplate debuffs use a real Blizzard cooldown swipe. The color-coded
    -- border is drawn one pixel outside the icon bounds, so the cooldown can
    -- cover the full icon without obscuring that border.
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, icon, "CooldownFrameTemplate")
    if not ok or not cooldown then
        ok, cooldown = pcall(CreateFrame, "Cooldown", nil, icon)
    end
    if cooldown then
        cooldown:SetAllPoints(icon)
        cooldown:SetFrameLevel((icon:GetFrameLevel() or 1) + 1)
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
        if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.68) end
        if cooldown.SetReverse then cooldown:SetReverse(true) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        cooldown:Hide()
    end
    icon.cooldown = cooldown

    -- Text needs its own higher frame so duration and stacks remain readable
    -- above the cooldown swipe on Classic 1.15.9.
    local textFrame = CreateFrame("Frame", nil, icon)
    textFrame:SetAllPoints(icon)
    textFrame:SetFrameLevel((icon:GetFrameLevel() or 1) + 3)
    textFrame:EnableMouse(false)
    icon.textFrame = textFrame

    -- Duration text (bottom center)
    icon.duration = textFrame:CreateFontString(nil, "OVERLAY")
    ns:StyleFont(icon.duration, nil, 10, "auras")
    icon.duration:SetPoint("BOTTOM", icon, "BOTTOM", 0, 0)
    icon.duration:SetTextColor(1, 1, 1)

    -- Stack count (top right)
    icon.count = textFrame:CreateFontString(nil, "OVERLAY")
    ns:StyleFont(icon.count, nil, 10, "auras")
    icon.count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 2, 2)
    icon.count:SetTextColor(1, 1, 1)

    return icon
end

-- =============================================================================
-- ICON FRAME POOL
-- =============================================================================
local MAX_POOL_SIZE = 120  -- Support 10+ mobs with 6+ auras each without mid-combat frame creation

local AuraPool = {
    inactive = {},    -- Stack of released icons ready for reuse
}

function AuraPool:Acquire(parent)
    local icon = tremove(self.inactive)
    if not icon then
        icon = CreateAuraIcon(parent)
    end
    icon:SetParent(parent)
    icon:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    if icon.cooldown then icon.cooldown:SetFrameLevel(icon:GetFrameLevel() + 1) end
    if icon.textFrame then icon.textFrame:SetFrameLevel(icon:GetFrameLevel() + 3) end
    return icon
end

function AuraPool:Release(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    ns.Timers:Remove(icon)
    icon.spellID = nil
    icon.expires = nil
    icon.elapsed = nil
    icon._cooldownExp = nil
    icon._cooldownDur = nil
    if icon.cooldown then
        if CooldownFrame_Clear then CooldownFrame_Clear(icon.cooldown) end
        icon.cooldown:Hide()
    end
    tinsert(self.inactive, icon)
end

function AuraPool:ReleaseAll(container)
    if not container or not container.icons then return end
    for i = #container.icons, 1, -1 do
        self:Release(container.icons[i])
        container.icons[i] = nil
    end
    container.displayedCount = 0
end

-- Release auras when plate is removed (stops OnUpdate timers, returns icons to pool)
function ns:CleanupPlateAuras(myPlate)
    if myPlate.debuffContainer then
        AuraPool:ReleaseAll(myPlate.debuffContainer)
    end
    if myPlate.buffContainer then
        AuraPool:ReleaseAll(myPlate.buffContainer)
    end
end

-- Trim pool to prevent unbounded growth (called on zone change)
function AuraPool:Trim()
    local count = #self.inactive
    if count <= MAX_POOL_SIZE then return end
    -- Remove excess icons from pool (they'll be garbage collected)
    for i = count, MAX_POOL_SIZE + 1, -1 do
        tremove(self.inactive)
    end
end

-- =============================================================================
-- BORDER COLOR HELPER
-- Handles border modes: DISABLED, COLOR_CODED/DISPELLABLE, CUSTOM
-- =============================================================================
local function SetBorderColor(icon, debuffType, isPurgeable, isDebuff, isPersonal)
    -- Cheap identity compare; only does work when the style actually changed.
    EnsureBorderStyle(icon)
    local borderMode = isDebuff and ns.c_debuffBorderMode or ns.c_buffBorderMode

    if borderMode == "DISABLED" then
        icon.border:SetColor(0, 0, 0, 0)  -- Fully transparent
    elseif borderMode == "CUSTOM" then
        local color = isDebuff and ns.c_debuffBorderColor or ns.c_buffBorderColor
        icon.border:SetColor(color[1], color[2], color[3], 1)
    else
        -- COLOR_CODED for debuffs, DISPELLABLE for buffs
        if isDebuff then
            -- Debuffs: use debuff type colors (Magic, Curse, Poison, Disease, none=red)
            local color = BORDER_COLORS[debuffType] or BORDER_COLORS.none
            icon.border:SetColor(color[1], color[2], color[3], 1)
        else
            -- Buffs: dispellable = blue, non-dispellable = white
            if isPurgeable then
                icon.border:SetColor(unpack(BORDER_COLORS.Magic))  -- Blue
            else
                icon.border:SetColor(unpack(BUFF_COLOR_WHITE))     -- White
            end
        end
    end
end

-- =============================================================================
-- DURATION TEXT UPDATE (Uses Time Cache)
-- =============================================================================
local function UpdateDurationText(icon)
    local timeLeft = icon.expires - GetTime()

    if timeLeft <= 0 then
        icon.duration:SetText("")
        return
    end

    -- Use cached time string
    icon.duration:SetText(GetCachedTimeString(timeLeft))

    -- Timer text is always white (matches the player/target aura timers).
    icon.duration:SetTextColor(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3])
end

-- =============================================================================
-- ADAPTIVE TIMER UPDATE
-- Whole-second Blizzard-style text does not need the former 10/20 Hz decimal
-- path. Use the same 4 Hz presentation cadence as Player/Target AuraStyle
-- while seconds are visible, and a cheaper cadence for minute/hour text.
-- =============================================================================
local function AuraTimerOnUpdate(icon, elapsed)
    icon.elapsed = icon.elapsed + elapsed

    local timeLeft = icon.expires - GetTime()

    local interval = (timeLeft < 90) and 0.25 or 0.5

    if icon.elapsed < interval then return end
    icon.elapsed = 0

    if timeLeft <= 0 then
        -- Aura expired - will be cleaned up on next UNIT_AURA
        icon.duration:SetText("")
        ns.Timers:Remove(icon)
        return
    end

    UpdateDurationText(icon)
end

-- =============================================================================
-- SETTINGS CACHE
-- Called from UpdateDBCache() when settings change
-- =============================================================================
function ns:CacheAuraSettings()
    local db = TurboFaceDB
    if db and not db.auras then db.auras = {} end
    local auras = db and db.auras or ns.defaults.auras

    -- Shared presentation
    ns.c_auraBorderStyle = auras.borderStyle or "BLIZZARD"

    -- Debuffs
    ns.c_showDebuffs = auras.showDebuffs ~= false
    ns.c_maxDebuffs = auras.maxDebuffs or 6
    ns.c_debuffIconWidth = auras.debuffIconWidth or 20
    -- Blizzard's ring is square art: stretched to a non-square icon its
    -- rounded corners flatten into ellipses. Derived here at read time
    -- rather than stored, because the Options "Debuff Icon Size" slider
    -- writes only debuffIconWidth -- a stored height would silently drift
    -- out of square the first time that slider moved.
    if ns.c_auraBorderStyle == "BLIZZARD" then
        ns.c_debuffIconHeight = ns.c_debuffIconWidth
    else
        ns.c_debuffIconHeight = auras.debuffIconHeight or 20
    end
    ns.c_debuffFontSize = auras.debuffFontSize or 10
    ns.c_debuffStackFontSize = auras.debuffStackFontSize or 10
    ns.c_debuffXOffset = auras.debuffXOffset or 0
    ns.c_debuffYOffset = auras.debuffYOffset or 0
    ns.c_debuffDurationAnchor = auras.debuffDurationAnchor or "BOTTOM"
    ns.c_debuffStackAnchor = "TOPRIGHT"   -- forced top-right (matches buffs / player-target)

    -- Buffs
    ns.c_showBuffs = auras.showBuffs ~= false
    ns.c_buffFilterMode = auras.buffFilterMode or "ONLY_DISPELLABLE"
    ns.c_maxBuffs = auras.maxBuffs or 4
    ns.c_buffIconWidth = auras.buffIconWidth or 18
    ns.c_buffIconHeight = auras.buffIconHeight or 18
    ns.c_buffFontSize = auras.buffFontSize or 10
    ns.c_buffStackFontSize = auras.buffStackFontSize or 10
    ns.c_buffXOffset = auras.buffXOffset or 0
    ns.c_buffYOffset = auras.buffYOffset or 0
    ns.c_buffGrowDirection = auras.buffGrowDirection or "CENTER"
    -- Fallback matches ns.defaults.auras.buffDurationAnchor; Core/Defaults.lua
    -- owns the canonical value (§3.1) and this used to say "BOTTOM".
    ns.c_buffDurationAnchor = auras.buffDurationAnchor or "CENTER"
    ns.c_buffStackAnchor = auras.buffStackAnchor or "TOPRIGHT"
    ns.c_buffIconSpacing = auras.buffIconSpacing or 2
    ns.c_buffMinDuration = auras.buffMinDuration or 0
    ns.c_buffMaxDuration = auras.buffMaxDuration or 300
    ns.c_buffBorderMode = auras.buffBorderMode or "COLOR_CODED"

    -- Duration filters (for debuffs)
    ns.c_minDuration = auras.minDuration or 0
    ns.c_maxDuration = auras.maxDuration or 300

    -- Layout
    ns.c_growDirection = auras.growDirection or "CENTER"
    ns.c_iconSpacing = auras.iconSpacing or 2
    ns.c_debuffSortMode = auras.debuffSortMode or "LEAST_TIME"
    ns.c_buffSortMode = auras.buffSortMode or "LEAST_TIME"

    -- Border modes
    ns.c_debuffBorderMode = auras.debuffBorderMode or "COLOR_CODED"

    -- Custom border colors
    local debuffBorderCol = auras.debuffBorderColor or { r = 0.8, g = 0, b = 0 }
    ns.c_debuffBorderColor = { debuffBorderCol.r, debuffBorderCol.g, debuffBorderCol.b }
    local buffBorderCol = auras.buffBorderColor or { r = 0.2, g = 0.8, b = 0.2 }
    ns.c_buffBorderColor = { buffBorderCol.r, buffBorderCol.g, buffBorderCol.b }

    -- Blacklist/Whitelist - ALWAYS reference DB tables directly for live updates
    -- Ensure tables exist in DB so references stay valid when user adds spells
    if db then
        if not db.auras.blacklist then db.auras.blacklist = {} end
        if not db.auras.whitelist then db.auras.whitelist = {} end
        ns.AuraBlacklist = db.auras.blacklist
        ns.AuraWhitelist = db.auras.whitelist
    else
        -- No DB yet, use empty tables (will be re-cached on PLAYER_LOGIN)
        ns.AuraBlacklist = {}
        ns.AuraWhitelist = {}
    end

    -- Refresh all visible plates with new settings (if API available)
    -- C_NamePlate.GetNamePlates may not exist during early addon loading
    if C_NamePlate.GetNamePlates then
        for i, namePlate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local myPlate = namePlate.TurboPlate
            if myPlate and myPlate.debuffContainer then
                ns:UpdateAuraPositions(myPlate)
                -- Refresh aura display if unit exists
                if myPlate.unit and UnitExists(myPlate.unit) then
                    ns:UpdateAuras(myPlate, myPlate.unit)
                end
            end
        end
    end
end

-- =============================================================================
-- FILTER CHAIN
-- Buff Filter Modes (enemy plates only):
--   ONLY_DISPELLABLE: Only dispellable buffs (bypass duration)
--   WHITELIST_DISPELLABLE: Whitelisted + dispellable (both bypass duration)
--   WHITELIST_ONLY: Only whitelisted buffs
--   ALL: All buffs, whitelisted/dispellable bypass duration, others get duration filter
-- =============================================================================

local function PassesFilters(spellID, duration, canStealOrPurge, auraType, debuffType)
    -- 1. BLACKLIST: Always reject first (applies to all modes, all plates)
    if rawget(ns.AuraBlacklist, spellID) then
        return false
    end

    -- 2. WHITELIST: Apply inside each branch so buff filter modes stay distinct
    local isWhitelisted = rawget(ns.AuraWhitelist, spellID)

    -- For buffs: treat Magic-type as dispellable (isStealable flag is unreliable on player targets)
    local isDispellable = canStealOrPurge or (auraType == "buff" and debuffType == "Magic")

    -- === ENEMY PLATES ONLY BELOW THIS POINT ===

    -- 3. BUFF FILTERING (enemy buffs only)
    if auraType == "buff" then
        local filterMode = ns.c_buffFilterMode

        -- Dispellable buffs bypass duration check in modes that allow dispellable buffs
        -- Whitelisted buffs bypass duration check in modes that allow whitelist

        if filterMode == "ONLY_DISPELLABLE" then
            -- Only dispellable buffs allowed, they bypass duration
            return isDispellable

        elseif filterMode == "WHITELIST_DISPELLABLE" then
            -- Whitelisted or dispellable passes
            if isWhitelisted or isDispellable then return true end
            return false  -- Non-dispellable, non-whitelisted rejected

        elseif filterMode == "WHITELIST_ONLY" then
            -- Only whitelisted buffs allowed
            return isWhitelisted

        else -- "ALL" (except blacklisted)
            -- Whitelisted bypasses duration check
            if isWhitelisted then return true end
            -- Dispellable bypasses duration check
            if isDispellable then return true end
            -- Non-dispellable, non-whitelisted falls through to duration check
        end

        -- Duration check for non-dispellable, non-whitelisted buffs only (ALL mode)
        local minDur = ns.c_buffMinDuration
        local maxDur = ns.c_buffMaxDuration
        if duration and duration > 0 then
            if minDur > 0 and duration < minDur then return false end
            if maxDur > 0 and duration > maxDur then return false end
        else
            -- Permanent aura - reject in ALL mode for non-dispellable/non-whitelisted
            return false
        end
        return true
    end

    -- 4. DEBUFF FILTERING (enemy debuffs = your DoTs)
    -- Whitelist bypasses all checks
    if isWhitelisted then return true end

    -- Duration check for debuffs
    local minDur = ns.c_minDuration
    local maxDur = ns.c_maxDuration
    if duration and duration > 0 then
        if minDur > 0 and duration < minDur then return false end
        if maxDur > 0 and duration > maxDur then return false end
    else
        -- Permanent aura - reject unless whitelisted (checked above)
        return false
    end

    return true
end

-- =============================================================================
-- REUSABLE CALLBACK STATE
-- =============================================================================
local currentAuraType = nil
local currentCollector = nil
local currentTime = 0

-- =============================================================================
-- CALLBACK FOR AuraUtil.ForEachAura
-- =============================================================================
local function ProcessAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, _, spellID)
    if not name then return end

    -- Filter check (pass debuffType for Magic-type stealable fallback)
    if not PassesFilters(spellID, duration, canStealOrPurge, currentAuraType, debuffType) then
        return
    end

    -- Acquire pooled data table
    local aura = AcquireAuraData()
    aura.name = name
    aura.icon = icon
    aura.count = count or 0
    aura.debuffType = debuffType
    aura.duration = duration
    aura.expires = expires or 0
    -- For buffs: treat Magic-type as stealable (isStealable flag unreliable on player targets)
    aura.canStealOrPurge = canStealOrPurge or (currentAuraType == "buff" and debuffType == "Magic")
    aura.spellID = spellID
    aura.isDebuff = (currentAuraType == "debuff")
    aura.timeLeft = (expires and expires > 0) and (expires - currentTime) or 0

    tinsert(currentCollector, aura)
end

-- =============================================================================
-- SORTING COMPARATORS (Pre-defined, not created inline in sort() call)
-- =============================================================================
local function SortByTimeRemaining(a, b)
    -- Least time remaining first (shortest duration at position 1)
    -- No duration auras go last
    if a.timeLeft == 0 then return false end
    if b.timeLeft == 0 then return true end
    return a.timeLeft < b.timeLeft
end

local function SortByMostRecent(a, b)
    -- Most recently applied/refreshed first (newest at position 1)
    -- Application time = expires - duration (works correctly for refreshed auras too)
    -- No duration auras go last
    if a.duration == 0 or a.expires == 0 then return false end
    if b.duration == 0 or b.expires == 0 then return true end
    local aApplied = a.expires - a.duration
    local bApplied = b.expires - b.duration
    return aApplied > bApplied
end

-- =============================================================================
-- POSITION ICONS (Layout with grow direction)
-- LEFT = grow right, RIGHT = grow left, CENTER = grow outward
-- Icons anchor from BOTTOM edge so height grows upward
-- =============================================================================
local function PositionIcons(container, count, iconWidth, spacing, growDir)
    if count == 0 then return end

    local outerWidth = iconWidth + (BORDER_SIZE * 2)
    local step = outerWidth + spacing
    local totalWidth = (count * outerWidth) + ((count - 1) * spacing)

    for i = 1, count do
        local icon = container.icons[i]
        if icon then
            icon:ClearAllPoints()

            if growDir == "CENTER" then
                local xOffset = (i - 1) * step - (totalWidth / 2) + (outerWidth / 2)
                icon:SetPoint("BOTTOM", container, "BOTTOM", xOffset, 0)
            elseif growDir == "LEFT" then
                local xOffset = (i - 1) * step
                icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", xOffset, 0)
            elseif growDir == "RIGHT" then
                local xOffset = -((i - 1) * step)
                icon:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", xOffset, 0)
            end
        end
    end
end

-- =============================================================================
-- DISPLAY AURAS (Show filtered, sorted auras on container)
-- Simple release-all-then-acquire pattern for correctness.
-- Performance comes from large pool (no frame creation mid-combat) and timer throttling.
-- =============================================================================
local function DisplayAuras(container, auras, maxCount, iconWidth, iconHeight, spacing, growDir, fontSize, stackFontSize, durationAnchor, stackAnchor, isPersonal)
    container.icons = container.icons or {}
    local icons = container.icons

    -- Get anchor positions
    local durAnchor = DURATION_ANCHORS[durationAnchor] or DURATION_ANCHORS.BOTTOM
    local stkAnchor = STACK_ANCHORS[stackAnchor] or STACK_ANCHORS.TOPRIGHT

    -- Release all current icons back to pool
    for i = #icons, 1, -1 do
        AuraPool:Release(icons[i])
        icons[i] = nil
    end

    -- Acquire and configure icons for current auras
    local count = 0
    for i = 1, #auras do
        if count >= maxCount then break end
        local aura = auras[i]
        count = count + 1

        local icon = AuraPool:Acquire(container)
        icons[count] = icon

        -- Size (square -- the Icon Size setting controls both dimensions)
        icon:SetSize(iconWidth, iconWidth)

        -- Texture
        icon.texture:SetTexture(GetCachedIcon(aura.spellID, aura.icon))
        icon.spellID = aura.spellID

        -- Border color
        SetBorderColor(icon, aura.debuffType, aura.canStealOrPurge, aura.isDebuff, isPersonal)

        -- Font sizes (stack count follows the same text size as the timer)
        ns:StyleFont(icon.duration, nil, fontSize, "auras")
        ns:StyleFont(icon.count, nil, fontSize, "auras")

        -- Duration text position
        icon.duration:ClearAllPoints()
        icon.duration:SetPoint(durAnchor[1], icon, durAnchor[2], durAnchor[3], durAnchor[4])

        -- Stack count position
        icon.count:ClearAllPoints()
        icon.count:SetPoint(stkAnchor[1], icon, stkAnchor[2], stkAnchor[3], stkAnchor[4])

        -- Stack count text
        if aura.count > 1 then
            icon.count:SetText(aura.count)
            icon.count:Show()
        else
            icon.count:Hide()
        end

        -- Debuff cooldown swipe. Buffs intentionally keep the clean icon-only
        -- presentation; the requested swipe applies to nameplate debuff timers.
        local timed = aura.expires > 0 and aura.duration and aura.duration > 0
        if icon.cooldown then
            if aura.isDebuff and timed and CooldownFrame_Set then
                if icon._cooldownExp ~= aura.expires or icon._cooldownDur ~= aura.duration then
                    CooldownFrame_Set(icon.cooldown, aura.expires - aura.duration, aura.duration, true)
                    icon._cooldownExp = aura.expires
                    icon._cooldownDur = aura.duration
                end
                icon.cooldown:Show()
            else
                if CooldownFrame_Clear then CooldownFrame_Clear(icon.cooldown) end
                icon.cooldown:Hide()
                icon._cooldownExp = nil
                icon._cooldownDur = nil
            end
        end

        -- Duration/timer setup
        icon.expires = aura.expires
        icon.elapsed = 0

        if aura.expires > 0 then
            -- Shared driver rather than a per-icon OnUpdate: a busy pull can have
            -- dozens of these, and each per-frame C-to-Lua dispatch costs more
            -- than the throttled work inside. AuraTimerOnUpdate is unchanged --
            -- ns.Timers hands it the same (icon, elapsed) and skips it while the
            -- icon is not visible, exactly as a frame script would.
            ns.Timers:Add(icon, AuraTimerOnUpdate)
            UpdateDurationText(icon)
            icon.duration:Show()
        else
            icon.duration:SetText("")
            icon.duration:Hide()
        end

        icon:Show()
    end

    -- Store displayed count
    container.displayedCount = count

    -- Position all icons
    PositionIcons(container, count, iconWidth, spacing, growDir)
end

-- =============================================================================
-- MAIN UPDATE FUNCTION
-- =============================================================================
function ns:UpdateAuras(myPlate, unit)
    -- MODULE MASTER GATE: modules.auras off -> no TurboFace nameplate aura
    -- icons are built, pooled, or refreshed.
    if ns.ModuleEnabled and not ns.ModuleEnabled("auras") then return end
    -- Forever owns the restricted presentation. Release addon-created rows and
    -- let UnitFrame.AurasFrame remain visible; never enumerate or interpret a
    -- secret aura domain.
    if ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret() then
        if myPlate then
            if myPlate.debuffContainer then
                AuraPool:ReleaseAll(myPlate.debuffContainer)
                myPlate.debuffContainer:Hide()
            end
            if myPlate.buffContainer then
                AuraPool:ReleaseAll(myPlate.buffContainer)
                myPlate.buffContainer:Hide()
            end
        end
        return
    end
    -- Early exit: no unit or containers
    if not unit or not UnitExists(unit) then return end

    if not myPlate.debuffContainer then return end

    -- Player's own plate is no longer TurboFace-styled (personal bar removed)
    if myPlate.isPlayer then return end

    -- === ENEMY NAMEPLATE AURAS ===
    -- Early exit: neither debuffs nor buffs enabled for enemy plates
    if not ns.c_showDebuffs and not ns.c_showBuffs then
        return
    end

    -- Early exit: friendly units don't show auras. FullPlateUpdate owns this
    -- derived state and UNIT_FACTION forces a plate refresh, so repeated aura
    -- batches do not need another UnitIsFriend() call. Keep a fallback for an
    -- early/uninitialized plate entering this path before its first full update.
    local isFriendly = myPlate.isFriendly
    if isFriendly == nil then
        isFriendly = UnitIsFriend("player", unit)
        myPlate.isFriendly = isFriendly
    end
    if isFriendly then
        AuraPool:ReleaseAll(myPlate.debuffContainer)
        AuraPool:ReleaseAll(myPlate.buffContainer)
        myPlate.debuffContainer:Hide()
        myPlate.buffContainer:Hide()
        return
    end

    currentTime = GetTime()

    -- Release previous aura data back to pool
    ReleaseAllAuraData(debuffCollector)
    ReleaseAllAuraData(buffCollector)

    -- Collect debuffs (HARMFUL|PLAYER = only your DoTs on enemy)
    if ns.c_showDebuffs then
        currentAuraType = "debuff"
        currentCollector = debuffCollector
do
            local i = 1
            while true do
                local name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, _, spellID = UnitDebuff(unit, i, "PLAYER")
                if not name then break end
                ProcessAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, nil, spellID)
                i = i + 1
            end
        end
        myPlate.debuffContainer:Show()
    else
        AuraPool:ReleaseAll(myPlate.debuffContainer)
        myPlate.debuffContainer:Hide()
    end

    -- Collect buffs (enemy buffs, filtered by mode)
    if ns.c_showBuffs then
        currentAuraType = "buff"
        currentCollector = buffCollector
do
            local i = 1
            while true do
                local name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, _, spellID = UnitBuff(unit, i)
                if not name then break end
                ProcessAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, nil, spellID)
                i = i + 1
            end
        end
        myPlate.buffContainer:Show()
    else
        AuraPool:ReleaseAll(myPlate.buffContainer)
        myPlate.buffContainer:Hide()
    end


    -- === SORT AURAS (skip if empty or single aura) ===
    if #debuffCollector > 1 then
        local sortFunc = ns.c_debuffSortMode == "MOST_RECENT" and SortByMostRecent or SortByTimeRemaining
        sort(debuffCollector, sortFunc)
    end
    if #buffCollector > 1 then
        local sortFunc = ns.c_buffSortMode == "MOST_RECENT" and SortByMostRecent or SortByTimeRemaining
        sort(buffCollector, sortFunc)
    end

    -- === DISPLAY (only for enabled containers) ===
    if ns.c_showDebuffs then
        DisplayAuras(myPlate.debuffContainer, debuffCollector, ns.c_maxDebuffs, ns.c_debuffIconWidth, ns.c_debuffIconHeight, ns.c_iconSpacing, ns.c_growDirection, ns.c_debuffFontSize, ns.c_debuffStackFontSize, ns.c_debuffDurationAnchor, ns.c_debuffStackAnchor, false)
    else
        myPlate.debuffContainer.displayedCount = 0
    end
    if ns.c_showBuffs then
        DisplayAuras(myPlate.buffContainer, buffCollector, ns.c_maxBuffs, ns.c_buffIconWidth, ns.c_buffIconHeight, ns.c_buffIconSpacing, ns.c_buffGrowDirection, ns.c_buffFontSize, ns.c_buffStackFontSize, ns.c_buffDurationAnchor, ns.c_buffStackAnchor, false)
    end

    -- Position containers immediately after display (displayedCount now accurate)
    ns:UpdateAuraPositions(myPlate)

end

-- =============================================================================
-- CREATE AURA CONTAINERS ON PLATE
-- =============================================================================
function ns:CreateAuraContainers(myPlate)
    if ns.ModuleEnabled and not ns.ModuleEnabled("auras") then return end
    if not myPlate or myPlate.debuffContainer then return end

    -- Debuff container (your DoTs)
    myPlate.debuffContainer = CreateFrame("Frame", nil, myPlate)
    myPlate.debuffContainer:SetSize(200, 30)
    myPlate.debuffContainer:EnableMouse(false)
    myPlate.debuffContainer.icons = {}

    -- Buff container (enemy buffs)
    myPlate.buffContainer = CreateFrame("Frame", nil, myPlate)
    myPlate.buffContainer:SetSize(200, 30)
    myPlate.buffContainer:EnableMouse(false)
    myPlate.buffContainer.icons = {}

    -- Release auras when plate hides
    myPlate:HookScript("OnHide", function(self)
        ns:CleanupPlateAuras(self)
    end)

    -- Positioning deferred to FullPlateUpdate->UpdateAuraPositions
end

-- =============================================================================
-- UPDATE AURA CONTAINER POSITIONS
-- Called when plate layout changes (not on every aura update)
-- Container visibility is managed by UpdateAuras() - this only handles positioning
-- =============================================================================
function ns:UpdateAuraPositions(myPlate)
    if not myPlate.debuffContainer then return end

    -- Hide aura containers for friendly units (they don't show auras)
    if myPlate.isFriendly then
        myPlate.debuffContainer:Hide()
        myPlate.buffContainer:Hide()
        return
    end

    -- Player's own plate is not TurboFace-styled
    if myPlate.isPlayer then return end

    -- Show containers (they may have been hidden by a prior friendly state).
    myPlate.debuffContainer:Show()
    myPlate.buffContainer:Show()

    local hpBar = myPlate.hp
    if not hpBar then return end  -- No valid anchor yet

    -- CENTER-mode aura rows use Blizzard's full health chassis. LEFT/RIGHT
    -- modes remain tied to the native health-bar edges.
    local auraCenterAnchor = hpBar
    local nameplate = myPlate.parentPlate or myPlate:GetParent()
    local unitFrame = (nameplate and nameplate.UnitFrame) or myPlate.nativeUnitFrame
    local healthBarsContainer = unitFrame and unitFrame.HealthBarsContainer
    if healthBarsContainer then auraCenterAnchor = healthBarsContainer end

    local nameAnchor = ns.GetNameplateNameAnchor(myPlate, true)
    local nameEnabled = nameAnchor and nameAnchor ~= hpBar and nameAnchor ~= myPlate

    -- Calculate Y offset to clear the visible name. Native name FontStrings are
    -- restricted on Classic 1.15.9, so do not ask them for geometry. Font
    -- metadata is safe to mirror (the native shadow amendment does the same); use its
    -- live size as the line-height estimate and fall back to the known native
    -- policy size.
    local nameHeightOffset = 0
    if nameEnabled and nameAnchor then
        local nameHeight = ns.NP_NATIVE_NAME_FALLBACK_SIZE or 10
        if nameAnchor.GetFont then
            local ok, _, fontSize = pcall(nameAnchor.GetFont, nameAnchor)
            if ok and type(fontSize) == "number" and fontSize > 0 then
                nameHeight = fontSize
            end
        end
        nameHeightOffset = nameHeight + 3
    end

    -- Reserve vertical space for the target combo dots (drawn between the name
    -- and the debuffs) so the debuff/buff rows are pushed up to clear them.
    if ns.ComboDebuffOffset then
        nameHeightOffset = nameHeightOffset + ns.ComboDebuffOffset(myPlate)
    end

    -- Position debuff container based on grow direction
    -- LEFT = align with left edge of healthbar, grow right
    -- RIGHT = align with right edge of healthbar, grow left
    -- CENTER = centered above healthbar (or name if visible)
    myPlate.debuffContainer:ClearAllPoints()
    local debuffGrowDir = ns.c_growDirection or "CENTER"
    -- Add BORDER_SIZE since the icon frame includes border padding
    -- Use fallback defaults (0) for XOffset/YOffset in case cache isn't initialized yet
    local debuffX = ns.c_debuffXOffset or 0
    local debuffY = (ns.c_debuffYOffset or 0) + nameHeightOffset + BORDER_SIZE

    if debuffGrowDir == "LEFT" then
        myPlate.debuffContainer:SetPoint("BOTTOMLEFT", hpBar, "TOPLEFT", debuffX, debuffY)
    elseif debuffGrowDir == "RIGHT" then
        myPlate.debuffContainer:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", debuffX, debuffY)
    else
        myPlate.debuffContainer:SetPoint("BOTTOM", auraCenterAnchor, "TOP", debuffX, debuffY)
    end

    -- Position buff container above debuffs (if visible) or at same level
    myPlate.buffContainer:ClearAllPoints()
    local debuffIconCount = myPlate.debuffContainer.displayedCount or 0
    -- Add BORDER_SIZE for buff positioning as well
    -- Use fallback defaults (0) for XOffset/YOffset in case cache isn't initialized yet
    local buffX = ns.c_buffXOffset or 0
    local buffY = (ns.c_buffYOffset or 0) + nameHeightOffset + BORDER_SIZE

    if debuffIconCount > 0 and ns.c_showDebuffs then
        -- Stack buffs above debuffs with 4px gap between rows (use height for vertical stacking)
        buffY = buffY + (ns.c_debuffIconHeight or 20) + 4
    end

    local buffGrowDir = ns.c_buffGrowDirection or "CENTER"
    if buffGrowDir == "LEFT" then
        myPlate.buffContainer:SetPoint("BOTTOMLEFT", hpBar, "TOPLEFT", buffX, buffY)
    elseif buffGrowDir == "RIGHT" then
        myPlate.buffContainer:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", buffX, buffY)
    else
        myPlate.buffContainer:SetPoint("BOTTOM", auraCenterAnchor, "TOP", buffX, buffY)
    end
end

-- =============================================================================
-- EVENT BATCHING
-- =============================================================================
-- Fast nameplate check (uses cached strsub)

-- =============================================================================
-- EVENT HANDLER SETUP
-- =============================================================================
local function SetupAuraEvents()
    local eventFrame = CreateFrame("Frame")

    -- Aura batch interval: 0.05s (50ms).
    local function GetAuraBatchInterval()
        return 0.05
    end

    -- Classic Era 1.15.8: C_Hook not available; replicate RegisterBucket with
    -- a standard OnEvent handler + C_Timer throttle for identical batching behavior.
    local auraBatchPending = false
    local auraBatchedUnits = {}  -- accumulates units between timer fires

    local function FlushAuraBatch()
        auraBatchPending = false
        local dc = ns.DebugCounters
        if dc then dc.auraFlush = dc.auraFlush + 1 end

        -- auraBatchedUnits is already a set, so UNIT_AURA bursts are deduped at
        -- insertion time. Process that set directly instead of copying it into
        -- a second scratch table every 50 ms. The callback is single-threaded;
        -- clear the set after the walk so new events begin the next batch.
        for unit in pairs(auraBatchedUnits) do
            local nameplate = GetNamePlateForUnit(unit)
            if nameplate then
                -- Update regular auras (full plates only)
                if nameplate.myPlate then
                    ns:UpdateAuras(nameplate.myPlate, unit)
                    -- Update TurboDebuff (TurboDebuffs priority aura)
                    if ns.UpdateTurboDebuff then
                        ns:UpdateTurboDebuff(nameplate.myPlate, unit)
                    end
                end
            end
        end
        wipe(auraBatchedUnits)

    end  -- FlushAuraBatch

    local function TraceAuraBatch() ns.KillTrace("Nameplates/Auras:", "AuraBatch", FlushAuraBatch) end

    ns.RegisterEvent(eventFrame, "UNIT_AURA")
    ns.RegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Trim pools and clear stale references on zone change. This event is
            -- owned only while the Auras module itself is active.
            AuraPool:Trim()
            return
        end
        if event == "UNIT_AURA" and unit then
            if not ns.IsNameplateUnit(unit) then return end
            local dc = ns.DebugCounters
            if dc then dc.unitAura = dc.unitAura + 1 end
            auraBatchedUnits[unit] = true
            if not auraBatchPending then
                auraBatchPending = true
                -- Kill-traced at the flush, not the event: the OnEvent branch
                -- only marks the unit dirty. A pull ending drops auras across
                -- every remaining plate at once, all coalesced into this pass.
                C_Timer.After(GetAuraBatchInterval(), TraceAuraBatch)
            end
        end
    end)

    ns.RegisterCPUProfileTarget("Nameplates/Auras:AuraBatch", FlushAuraBatch)
    ns.RegisterCPUProfileTarget("Nameplates/Auras:Events", eventFrame:GetScript("OnEvent"))
    return eventFrame
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function Auras:Init()
    if initialized then return end
    -- Client substrate ownership is provider-defined. Classic uses this legacy
    -- addon-owned aura row; Forever selects detached Blizzard AuraContainers.
    if ns.NameplateProviderUsesLegacyAuraRows
        and not ns.NameplateProviderUsesLegacyAuraRows() then return end
    if ns.ModuleEnabled then
        if not ns.ModuleEnabled("auras") then return end
        if not ns.ModuleEnabled("nameplates") then return end
    end
    initialized = true

    -- Cache aura settings only for the active module, then attach the batched
    -- UNIT_AURA driver. With Auras disabled this file remains eventless.
    ns:CacheAuraSettings()
    auraEventFrame = SetupAuraEvents()
end
