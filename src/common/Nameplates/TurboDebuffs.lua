local _, ns = ...
local UnitBuff, UnitDebuff = ns.API.UnitBuff, ns.API.UnitDebuff

-- TurboDebuffs: TurboFace's single high-priority aura display for nameplates.
--
-- The renderer and priority policy are TurboFace-owned.  The Classic Era aura
-- catalog below is intentionally small and behavior-oriented: it names the
-- player-facing control/cooldown families TurboFace wants to surface, then
-- resolves Blizzard's localized spell names at runtime so one canonical spell
-- covers every rank.  We deliberately do not carry rank-by-rank spell dumps,
-- expansion-only aliases, or private-server spell IDs.

local GetTime = GetTime
local GetSpellInfo = ns.API.GetSpellInfo
local CreateFrame = CreateFrame
local ceil = math.ceil
local pairs = pairs
local rawset = rawset
local rawget = rawget
local UnitIsUnit = ns.API.ReadUnitIsUnit
local UnitIsFriend = ns.API.ReadUnitIsFriend

-- Cached blacklist reference (set after initialization)
local AuraBlacklist

-- Timer colors (match Nameplates/Auras.lua)
local COLOR_RED = { 1.0, 0.2, 0.2 }
local COLOR_ORANGE = { 1.0, 0.5, 0.2 }
local COLOR_YELLOW = { 1.0, 1.0, 0.2 }
local COLOR_WHITE = { 1.0, 1.0, 1.0 }

-- Cached timer strings (avoids garbage from string concatenation)
local cachedMinutes = setmetatable({}, { __index = function(t, k)
    local v = k .. "m"
    rawset(t, k, v)
    return v
end })
local cachedHours = setmetatable({}, { __index = function(t, k)
    local v = k .. "h"
    rawset(t, k, v)
    return v
end })

-- =============================================================================
-- CLASSIC ERA IMPORTANT-AURA CATALOG
-- =============================================================================
-- Each number is one canonical Blizzard spell/effect ID used only to resolve a
-- localized aura name through GetSpellInfo().  Rank variants share that name,
-- so they require no duplicate entries.  Selection is intentionally limited to
-- high-information Classic Era PvP/control and cooldown auras; ordinary buffs,
-- permanent forms/stances, TBC/Wrath abilities, and private-server additions
-- are outside this feature's scope.
--
-- "interrupts" remains a profile category for compatibility, but the current
-- TurboDebuffs renderer is aura-driven.  Classic spell-school lockouts are not
-- reliably represented as UnitDebuff auras, so we do not pretend that a static
-- spell list can display them.  If TurboFace later adds a CLEU lockout tracker,
-- it can feed that category explicitly.
local AURA_FAMILIES = {
    immunities = {
        11958, -- Ice Block
        642,   -- Divine Shield
        1022,  -- Blessing of Protection
        19753, -- Divine Intervention (applied aura)
        19263, -- Deterrence
        8178,  -- Grounding Totem Effect
        6615,  -- Free Action Potion
    },

    cc = {
        -- Druid
        5211,  -- Bash
        9005,  -- Pounce
        2637,  -- Hibernate
        -- Hunter
        24394, -- Intimidation stun
        19386, -- Wyvern Sting
        19503, -- Scatter Shot
        3355,  -- Freezing Trap Effect
        1513,  -- Scare Beast
        -- Mage
        118,   -- Polymorph
        -- Paladin
        853,   -- Hammer of Justice
        20066, -- Repentance
        -- Priest
        8122,  -- Psychic Scream
        9484,  -- Shackle Undead
        -- Rogue
        1776,  -- Gouge
        2094,  -- Blind
        408,   -- Kidney Shot
        6770,  -- Sap
        1833,  -- Cheap Shot
        -- Warlock
        710,   -- Banish
        6789,  -- Death Coil
        6358,  -- Seduction
        5782,  -- Fear
        5484,  -- Howl of Terror
        -- Warrior
        12809, -- Concussion Blow
        5246,  -- Intimidating Shout
        7922,  -- Charge Stun
        20253, -- Intercept Stun
        -- Racials / engineering
        20549, -- War Stomp
        4068,  -- Iron Grenade
    },

    silence = {
        18469, -- Improved Counterspell silence
        15487, -- Silence
        24259, -- Spell Lock silence
        18425, -- Improved Kick silence
    },

    roots = {
        339,   -- Entangling Roots
        122,   -- Frost Nova
        12494, -- Frostbite
        19306, -- Counterattack
        19185, -- Entrapment
        23694, -- Improved Hamstring
        13099, -- Net-o-Matic
    },

    disarm = {
        676,   -- Disarm
        14251, -- Riposte
    },

    buffs_defensive = {
        -- Druid
        22812, -- Barkskin
        -- Mage
        11426, -- Ice Barrier
        1463,  -- Mana Shield
        543,   -- Fire Ward
        6143,  -- Frost Ward
        -- Paladin
        498,   -- Divine Protection
        1044,  -- Blessing of Freedom
        20925, -- Holy Shield
        -- Priest
        17,    -- Power Word: Shield
        6346,  -- Fear Ward
        -- Rogue
        5277,  -- Evasion
        -- Warlock
        7812,  -- Sacrifice
        6229,  -- Shadow Ward
        -- Warrior
        871,   -- Shield Wall
        12975, -- Last Stand
        18499, -- Berserker Rage
    },

    buffs_offensive = {
        -- Druid / Shaman
        17116, -- Nature's Swiftness (Druid)
        16188, -- Nature's Swiftness (Shaman)
        -- Hunter
        19574, -- Bestial Wrath
        3045,  -- Rapid Fire
        -- Mage
        12042, -- Arcane Power
        12043, -- Presence of Mind
        11129, -- Combustion
        -- Paladin
        20216, -- Divine Favor
        -- Priest
        10060, -- Power Infusion
        14751, -- Inner Focus
        -- Rogue
        13750, -- Adrenaline Rush
        14177, -- Cold Blood
        13877, -- Blade Flurry
        -- Shaman
        16166, -- Elemental Mastery
        -- Warrior
        1719,  -- Recklessness
        12328, -- Death Wish
        12292, -- Sweeping Strikes
    },

    buffs_other = {
        1850,  -- Dash
        2983,  -- Sprint
        5118,  -- Aspect of the Cheetah
        13159, -- Aspect of the Pack
        2645,  -- Ghost Wolf
    },

    snare = {
        -- Hunter
        5116,  -- Concussive Shot
        2974,  -- Wing Clip
        13810, -- Frost Trap Aura
        -- Mage
        116,   -- Frostbolt
        120,   -- Cone of Cold
        -- Priest
        15407, -- Mind Flay
        -- Rogue
        3409,  -- Crippling Poison
        -- Shaman
        3600,  -- Earthbind
        8056,  -- Frost Shock
        8034,  -- Frostbrand Attack
        -- Warlock
        18223, -- Curse of Exhaustion
        -- Warrior
        1715,  -- Hamstring
        12323, -- Piercing Howl
        -- Shared NPC/player movement effect
        1604,  -- Dazed
    },
}

local CATEGORY_BUILD_ORDER = {
    "immunities", "cc", "silence", "roots", "disarm",
    "buffs_defensive", "buffs_offensive", "buffs_other", "snare",
}

local AuraTypeByName = {}
local MindControlName
local CatalogBuilt = false

local function RegisterAuraFamily(auraType, spellIds)
    for i = 1, #spellIds do
        local name = GetSpellInfo(spellIds[i])
        if name and AuraTypeByName[name] == nil then
            AuraTypeByName[name] = auraType
        end
    end
end

local function BuildAuraCatalog()
    if CatalogBuilt then return end
    for i = 1, #CATEGORY_BUILD_ORDER do
        local auraType = CATEGORY_BUILD_ORDER[i]
        RegisterAuraFamily(auraType, AURA_FAMILIES[auraType])
    end
    MindControlName = GetSpellInfo(605) -- Mind Control
    AuraBlacklist = ns.AuraBlacklist
    CatalogBuilt = true
end

-- Expose the resolved runtime catalog only as a diagnostic/extension surface.
-- Consumers should treat it as read-only.
ns.TurboDebuffsAuraTypesByName = AuraTypeByName

local function GetAuraPriority(name)
    if not CatalogBuilt then BuildAuraCatalog() end
    local auraType = name and AuraTypeByName[name]
    if not auraType then return nil end

    local cfg = ns.c_turboDebuffs or {}
    if cfg[auraType] == false then return nil end

    local priorities = cfg.priority or {}
    return priorities[auraType] or 0, auraType
end

-- =============================================================================
-- AURA SCANNING
-- Returns winning aura: icon, expires, duration, priority, auraType, spellId
-- =============================================================================

-- Module-local state for callback (avoids allocations)
local scanTime = 0
local scanBest = {
    icon = nil,
    expires = 0,
    duration = 0,
    priority = 0,
    timeLeft = 0,
    auraType = nil,
    spellId = nil,
}
local scanMindControlled = false

-- Reset scan state before each unit scan
local function ResetScanState()
    scanTime = GetTime()
    scanBest.icon = nil
    scanBest.expires = 0
    scanBest.duration = 0
    scanBest.priority = 0
    scanBest.timeLeft = 0
    scanBest.auraType = nil
    scanBest.spellId = nil
    scanMindControlled = false
end

-- Evaluate one UnitBuff/UnitDebuff result against the resolved catalog.
local function TurboDebuffAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, nameplateShowPersonal, spellId)
    if not name or not spellId then return end
    
    -- Mind Control changes nameplate ownership semantics; hide the priority
    -- aura rather than presenting the control effect as an ordinary debuff.
    if MindControlName and name == MindControlName then
        scanMindControlled = true
        return
    end

    -- Blacklist stays keyed by concrete aura spell ID so user exclusions remain
    -- exact even though category matching is rank-agnostic by localized name.
    if AuraBlacklist and rawget(AuraBlacklist, spellId) then return end

    local p, auraType = GetAuraPriority(name)
    if not p then return end
    
    -- Calculate time remaining
    local timeLeft = (expires and expires > 0) and (expires - scanTime) or 0
    
    -- Reject expired auras (non-permanent with no time left)
    if expires and expires > 0 and timeLeft <= 0 then return end
    
    -- Compare: higher priority wins, tiebreaker = more time remaining
    if p > scanBest.priority or (p == scanBest.priority and timeLeft > scanBest.timeLeft) then
        scanBest.priority = p
        scanBest.icon = icon
        scanBest.expires = expires or 0
        scanBest.duration = duration or 0
        scanBest.timeLeft = timeLeft
        scanBest.spellId = spellId
        scanBest.auraType = auraType
    end
end

-- Scan harmful and helpful auras with Classic's indexed aura API.
local function ScanUnitAuras(unit)
    ResetScanState()
    
    -- Scan debuffs (HARMFUL)
    do
        local i = 1
        while true do
            local name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, _, spellId = UnitDebuff(unit, i)
            if not name then break end
            TurboDebuffAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, nil, spellId)
            i = i + 1
        end
    end
    
    -- Early exit if mind controlled
    if scanMindControlled then return nil end
    
    -- Scan buffs (HELPFUL)
    do
        local i = 1
        while true do
            local name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, _, spellId = UnitBuff(unit, i)
            if not name then break end
            TurboDebuffAuraCallback(name, icon, count, debuffType, duration, expires, caster, canStealOrPurge, nil, spellId)
            i = i + 1
        end
    end
    
    -- Early exit if mind controlled (found during buff scan)
    if scanMindControlled then return nil end
    
    -- Return best candidate
    if scanBest.icon then
        return scanBest.icon, scanBest.expires, scanBest.duration, scanBest.priority, scanBest.auraType, scanBest.spellId
    end
    return nil
end

-- =============================================================================
-- FRAME CREATION AND DISPLAY
-- =============================================================================

local PixelUtil = PixelUtil
local BORDER_TEX = "Interface\\Buttons\\WHITE8X8"
local BORDER_ALPHA = 0.9

-- Create pixel-perfect 1px border using PixelUtil
-- Uses shared ns.CreateTextureBorder if available, otherwise creates manually
local function CreateIconBorder(frame)
    -- Use shared border function if available (defined in Nameplates.lua)
    if ns.CreateTextureBorder then
        local border = ns.CreateTextureBorder(frame, 1)
        border:SetColor(0, 0, 0, BORDER_ALPHA)
        return border
    end
    
    -- Fallback: manual creation with PixelUtil
    local pixelSize = PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
    local border = ns.BorderMethods and setmetatable({}, ns.BorderMethods) or {}
    
    border.top = frame:CreateTexture(nil, "OVERLAY")
    border.top:SetTexture(BORDER_TEX)
    border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -pixelSize, pixelSize)
    border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", pixelSize, pixelSize)
    PixelUtil.SetHeight(border.top, pixelSize, 1)
    
    border.bottom = frame:CreateTexture(nil, "OVERLAY")
    border.bottom:SetTexture(BORDER_TEX)
    border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -pixelSize, -pixelSize)
    border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pixelSize, -pixelSize)
    PixelUtil.SetHeight(border.bottom, pixelSize, 1)
    
    border.left = frame:CreateTexture(nil, "OVERLAY")
    border.left:SetTexture(BORDER_TEX)
    border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -pixelSize, 0)
    border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -pixelSize, 0)
    PixelUtil.SetWidth(border.left, pixelSize, 1)
    
    border.right = frame:CreateTexture(nil, "OVERLAY")
    border.right:SetTexture(BORDER_TEX)
    border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", pixelSize, 0)
    border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pixelSize, 0)
    PixelUtil.SetWidth(border.right, pixelSize, 1)
    
    -- Add methods if metatable not available
    if not ns.BorderMethods then
        function border:SetColor(r, g, b, a)
            a = a and math.min(a, BORDER_ALPHA) or BORDER_ALPHA
            self.top:SetVertexColor(r, g, b, a)
            self.bottom:SetVertexColor(r, g, b, a)
            self.left:SetVertexColor(r, g, b, a)
            self.right:SetVertexColor(r, g, b, a)
        end
    end
    
    border:SetColor(0, 0, 0, BORDER_ALPHA)
    return border
end

-- Create TurboDebuff frame for a nameplate
local function CreateTurboDebuffFrame(myPlate)
    local cfg = ns.c_turboDebuffs or {}
    local size = cfg.size or 32
    
    local frame = CreateFrame("Frame", nil, myPlate)
    PixelUtil.SetSize(frame, size, size, 1, 1)
    frame:SetFrameLevel(myPlate:GetFrameLevel() + 10)
    frame.cachedSize = size
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Pixel-perfect border
    frame.border = CreateIconBorder(frame)
    
    -- Timer text (fake-centered via LEFT+RIGHT span to avoid sub-pixel jitter)
    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    frame.timer:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.timer:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    local timerSize = cfg.timerSize or (size / 2.5)
    ns:StyleFont(frame.timer, nil, timerSize, "turboDebuffs")
    frame.timer:SetTextColor(1, 1, 1)
    frame.timer:SetJustifyH("CENTER")
    frame.timer:SetJustifyV("MIDDLE")
    
    -- State
    frame.timeEnd = 0
    frame.lastTimerText = nil
    frame.cachedAnchor = nil
    frame.cachedXOff = nil
    frame.cachedYOff = nil
    frame.cachedAnchorFrame = nil
    
    -- Timer tick runs on the shared driver (ns.Timers) rather than a per-frame
    -- OnUpdate: there is one of these per nameplate, so a big pull would
    -- otherwise cost dozens of C-to-Lua dispatches per frame. OnShow/OnHide
    -- attach and detach, so the driver idles whenever no debuff is displayed.
    -- ns.Timers passes the same (self, elapsed) contract.
    local function TurboDebuffTimerTick(self, elapsed)
        local remain = self.timeEnd - GetTime()
        if remain > 0 then
            local text
            -- Match AuraStyle/Blizzard countdown semantics: whole units are
            -- ceiling-rounded, seconds remain visible below 90s, and there is
            -- no sub-second decimal phase before expiry.
            if remain < 90 then
                text = ceil(remain)
            elseif remain < 3600 then
                text = cachedMinutes[ceil(remain / 60)]
            else
                text = cachedHours[ceil(remain / 3600)]
            end
            if text ~= self.lastTimerText then
                self.timer:SetText(text)
                self.lastTimerText = text
            end
            -- Color based on time remaining (band-cached: SetTextColor only
            -- when crossing a threshold, not every frame)
            local band = (remain < 1 and 1) or (remain < 3 and 2) or (remain < 60 and 3) or 4
            if band ~= self.lastColorBand then
                self.lastColorBand = band
                local c = (band == 1 and COLOR_RED) or (band == 2 and COLOR_ORANGE)
                       or (band == 3 and COLOR_YELLOW) or COLOR_WHITE
                self.timer:SetTextColor(c[1], c[2], c[3])
            end
        elseif self.lastTimerText then
            -- Aura expired - hide frame (safety net for delayed UNIT_AURA)
            self.timer:SetText("")
            self.lastTimerText = nil
            self.lastColorBand = nil
            self:Hide()
        end
    end

    frame:SetScript("OnShow", function(self) ns.Timers:Add(self, TurboDebuffTimerTick) end)
    frame:SetScript("OnHide", function(self) ns.Timers:Remove(self) end)

    frame:Hide()
    return frame
end

-- Update TurboDebuff display for a plate
local function UpdateTurboDebuff(myPlate, unit)
    if not myPlate or not unit then return end
    if ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret() then
        if myPlate.turboDebuff then myPlate.turboDebuff:Hide() end
        return
    end
    
    local cfg = ns.c_turboDebuffs or {}
    if not cfg.enabled then
        if myPlate.turboDebuff then myPlate.turboDebuff:Hide() end
        return
    end
    
    -- Always hide on the player's own nameplate.
    if UnitIsUnit("player", unit) then
        if myPlate.turboDebuff then myPlate.turboDebuff:Hide() end
        return
    end
    
    -- Hide for friendlies if disabled
    if not cfg.showFriendly and UnitIsFriend("player", unit) then
        if myPlate.turboDebuff then myPlate.turboDebuff:Hide() end
        return
    end
    
    -- Create frame if needed
    if not myPlate.turboDebuff then
        myPlate.turboDebuff = CreateTurboDebuffFrame(myPlate)
    end
    
    local frame = myPlate.turboDebuff
    
    -- Scan for winning aura
    local icon, expires, duration, priority, auraType, spellId = ScanUnitAuras(unit)
    
    if icon then
        -- Full plates always use full plate settings
        local size = cfg.size or 32
        local anchor = cfg.anchor or "LEFT"
        local xOff = cfg.xOffset or 0
        local yOff = cfg.yOffset or 0
        local timerSize = cfg.timerSize or (size / 2.5)
        
        -- Update size (cached to avoid redundant PixelUtil calls)
        if frame.cachedSize ~= size then
            PixelUtil.SetSize(frame, size, size, 1, 1)
            frame.cachedSize = size
        end
        
        -- Update timer typography only when the local feature style changes.
        local fontName = cfg.font or ns.DEFAULT_FONT_NAME
        local textStyle = cfg.textStyle or "OUTLINE"
        if frame.cachedFont ~= fontName or frame.cachedTextStyle ~= textStyle or frame.cachedFontSize ~= timerSize then
            ns:StyleFont(frame.timer, nil, timerSize, "turboDebuffs")
            frame.cachedFont = fontName
            frame.cachedTextStyle = textStyle
            frame.cachedFontSize = timerSize
        end
        
        -- Position anchored to healthBar (cached to avoid redundant repositioning)
        local anchorFrame = myPlate.hp or myPlate
        if frame.cachedAnchor ~= anchor or frame.cachedXOff ~= xOff or frame.cachedYOff ~= yOff or frame.cachedAnchorFrame ~= anchorFrame then
            frame:ClearAllPoints()
            if anchor == "LEFT" then
                frame:SetPoint("RIGHT", anchorFrame, "LEFT", -4 + xOff, yOff)
            elseif anchor == "RIGHT" then
                frame:SetPoint("LEFT", anchorFrame, "RIGHT", 4 + xOff, yOff)
            elseif anchor == "TOP" then
                frame:SetPoint("BOTTOM", anchorFrame, "TOP", xOff, 4 + yOff)
            elseif anchor == "BOTTOM" then
                frame:SetPoint("TOP", anchorFrame, "BOTTOM", xOff, -4 + yOff)
            else
                frame:SetPoint("LEFT", anchorFrame, "LEFT", -size - 4 + xOff, yOff)
            end
            frame.cachedAnchor = anchor
            frame.cachedXOff = xOff
            frame.cachedYOff = yOff
            frame.cachedAnchorFrame = anchorFrame
        end
        
        -- Update icon (cached to avoid redundant SetTexture calls)
        if frame.cachedSpellId ~= spellId then
            frame.icon:SetTexture(icon)
            frame.cachedSpellId = spellId
        end
        
        -- Update timer
        if duration and duration > 0.2 then
            frame.timeEnd = expires
        else
            -- Permanent aura
            frame.timeEnd = 0
            frame.timer:SetText("")
            frame.lastTimerText = nil
        end
        
        frame:Show()
    else
        -- Clear timer state before hiding
        frame.timer:SetText("")
        frame.lastTimerText = nil
        frame.cachedSpellId = nil
        frame:Hide()
    end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

-- Called on UNIT_AURA for nameplate units (full plates)
function ns:UpdateTurboDebuff(myPlate, unit)
    UpdateTurboDebuff(myPlate, unit)
end

-- Called when full plate is hidden
function ns:HideTurboDebuff(myPlate)
    if myPlate and myPlate.turboDebuff then
        myPlate.turboDebuff.timer:SetText("")
        myPlate.turboDebuff.lastTimerText = nil
        myPlate.turboDebuff.expirationTime = nil
        myPlate.turboDebuff.spellID = nil
        myPlate.turboDebuff.duration = nil
        myPlate.turboDebuff.cachedSpellId = nil
        myPlate.turboDebuff:Hide()
    end
end

function ns:InitTurboDebuffs()
    if not (ns.c_turboDebuffs and ns.c_turboDebuffs.enabled) then return end
    BuildAuraCatalog()
end

-- Cache settings
function ns:CacheTurboDebuffsSettings()
    local td = TurboFaceDB and TurboFaceDB.turboDebuffs or ns.defaults.turboDebuffs or {}
    local defaults = ns.defaults.turboDebuffs or {}
    
    ns.c_turboDebuffs = {
        enabled = td.enabled == true,  -- Disabled by default
        showFriendly = td.showFriendly == true,
        
        -- Full plates
        size = td.size or defaults.size or 32,
        anchor = td.anchor or defaults.anchor or "LEFT",
        xOffset = td.xOffset or defaults.xOffset or 0,
        yOffset = td.yOffset or defaults.yOffset or 0,
        timerSize = td.timerSize or defaults.timerSize or 14,
        
        -- Category enables
        immunities = td.immunities ~= false,
        cc = td.cc ~= false,
        silence = td.silence ~= false,
        interrupts = td.interrupts ~= false,
        roots = td.roots ~= false,
        disarm = td.disarm ~= false,
        buffs_defensive = td.buffs_defensive == true,
        buffs_offensive = td.buffs_offensive == true,
        buffs_other = td.buffs_other == true,
        snare = td.snare == true,
        
        -- Priorities
        priority = td.priority or defaults.priority or {
            immunities = 80,
            cc = 70,
            silence = 60,
            interrupts = 55,
            roots = 50,
            disarm = 45,
            buffs_defensive = 40,
            buffs_offensive = 35,
            buffs_other = 30,
            snare = 25,
        },
    }
end
