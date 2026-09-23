local _, ns = ...

local function PlayerHealthBar()
    return (ns.UnitFrameProviderPlayerHealthBar and ns.UnitFrameProviderPlayerHealthBar()) or _G.PlayerFrameHealthBar
end

-- =============================================================================
-- TurboFace Shield Bar -- Player/Party absorb visualization.
--
-- The renderer and event/state model are TurboFace-owned. Classic Era lacks a
-- consistently useful per-shield remaining-absorb API, so known player shield
-- families use the compact model in UnitFrames/ShieldData.lua and combat-log
-- absorbed amounts maintain their remainder. If UnitGetTotalAbsorbs proves
-- authoritative on the running client, its total is used to reconcile the
-- modeled school segments.
--
-- Historic `nanShield*` profile keys and ns.NanShield method names are retained
-- for saved-profile/internal API compatibility.
-- =============================================================================

local NanShield = {}
ns.NanShield = NanShield

local UnitBuff = ns.API.UnitBuff
local UnitGetTotalAbsorbs = ns.API.UnitGetTotalAbsorbs
local IsReadableNumber = ns.API.IsReadableNumber or function(v) return type(v) == "number" end
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local GetSpellBonusHealing = GetSpellBonusHealing
local GetSpellBonusDamage = GetSpellBonusDamage
local GetTalentInfo = ns.API.GetTalentInfo
local IsPlayerSpell = IsPlayerSpell
local CreateFrame = CreateFrame
local select, ipairs, pairs, wipe, type = select, ipairs, pairs, wipe, type
local min, max, ceil = math.min, math.max, math.ceil

local function cfg()
    return (TurboFaceDB and TurboFaceDB.unitframes) or ns.defaults.unitframes
end

local function StyleNanShieldText(fontString, size)
    if not fontString then return end
    local d = cfg()
    ns:StyleFont(fontString, ns:GetFontPath(d.nanShieldFont or "Blizzard Narrow"),
        size or d.nanShieldFontSize or 9, nil, d.nanShieldTextStyle or "OUTLINE")
    fontString:SetTextColor(1, 1, 1, 1)
end

local _, PLAYER_CLASS = UnitClass("player")
local PLAYER_IS_PRIEST = PLAYER_CLASS == "PRIEST"

local function RuntimeEnabled()
    if ns.ModuleEnabled and not ns.ModuleEnabled("unitframes", "player") then return false end
    local d = (TurboFaceDB and TurboFaceDB.unitframes) or ns.defaults.unitframes
    return d.nanShieldEnabled ~= false
end

local function PartyRuntimeEnabled()
    if not PLAYER_IS_PRIEST then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("unitframes", "party") then return false end
    local d = (TurboFaceDB and TurboFaceDB.unitframes) or ns.defaults.unitframes
    return d.nanShieldEnabled ~= false
end

local function AnyRuntimeEnabled()
    return RuntimeEnabled() or PartyRuntimeEnabled()
end

-- ---------------------------------------------------------------------------
-- Shield data + local talent modifiers
-- ---------------------------------------------------------------------------
local ShieldData = ns.ShieldData
local schoolIds = ShieldData.schoolIds
local schoolColor = ShieldData.schoolColors
local schoolIdx = {}
for idx, id in ipairs(schoolIds) do schoolIdx[id] = idx end

local talentCache = {}
local function InvalidateTalentCache() wipe(talentCache) end

local function KnowsSpell(spellId)
    if type(IsPlayerSpell) == "function" then
        return IsPlayerSpell(spellId) and true or false
    end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        return C_SpellBook.IsSpellKnown(spellId) and true or false
    end
    return false
end

local function improvedPowerWordShieldMultiplier()
    local v = talentCache.ipws
    if v ~= nil then return v end

    if KnowsSpell(14769) then
        v = 1.15
    elseif KnowsSpell(14768) then
        v = 1.10
    elseif KnowsSpell(14748) then
        v = 1.05
    else
        -- Compatibility fallback for clients where passive talent spells are
        -- not reported by IsPlayerSpell/C_SpellBook.IsSpellKnown.
        local rank = GetTalentInfo and select(5, GetTalentInfo(1, 5)) or 0
        v = 1 + (rank or 0) * 0.05
    end
    talentCache.ipws = v
    return v
end

local function improvedVoidwalkerMultiplier()
    local v = talentCache.ivw
    if v ~= nil then return v end

    if KnowsSpell(18707) then
        v = 1.30
    elseif KnowsSpell(18706) then
        v = 1.20
    elseif KnowsSpell(18705) then
        v = 1.10
    else
        local rank = GetTalentInfo and select(5, GetTalentInfo(2, 5)) or 0
        v = 1 + (rank or 0) * 0.10
    end
    talentCache.ivw = v
    return v
end

local function ModelMultiplier(modifier)
    if modifier == "PWS" then return improvedPowerWordShieldMultiplier() end
    if modifier == "VOIDWALKER" then return improvedVoidwalkerMultiplier() end
    return 1
end

-- ---------------------------------------------------------------------------
-- Engine state
-- ---------------------------------------------------------------------------
local active        = 0
local spellSchool   = {}                       -- spellName -> schoolId
local currentAbsorb = {}                        -- spellName -> remaining
local maxAbsorb     = {}                        -- spellName -> max (at apply)
local schoolAbsorb  = {0,0,0,0,0,0,0,0,0}       -- per-school current totals
local totalAbsorb   = 0                         -- Σ maxAbsorb (the bar denominator)
local playerGUID
local absorbApiLive = false  -- UnitGetTotalAbsorbs has returned > 0 this session

local function CalculateAbsorbValue(spellId, info, sourceIsPlayer)
    -- External caster stats are unavailable in Classic Era. Use the spell's
    -- rank baseline instead of applying this player's power/talents to someone
    -- else's shield. Self-cast shields use only the power source explicitly
    -- owned by that family in ShieldData.
    local bonusPower = 0
    if sourceIsPlayer then
        if info.powerSource == "healing" and GetSpellBonusHealing then
            bonusPower = GetSpellBonusHealing() or 0
        elseif info.powerSource == "frost" and GetSpellBonusDamage then
            bonusPower = GetSpellBonusDamage(5) or 0
        end
    end

    local level = UnitLevel("player") or 1
    local capLevel = (info.capLevel and info.capLevel > 0) and info.capLevel or level
    local levels = max(0, min(level, capLevel) - (info.startLevel or 0))
    local spellLevel = info.spellLevel or 0
    local levelPenalty = min(1, 1 - (20 - spellLevel) * 0.03)
    if levelPenalty < 0 then levelPenalty = 0 end

    local modifier = sourceIsPlayer and ModelMultiplier(info.modifier) or 1
    return modifier * ((info.base or 0) + levels * (info.perLevel or 0))
        + bonusPower * (info.coefficient or 0) * levelPenalty
end

local function UpdateValues()
    local total, estimatedCurrent = 0, 0
    for i = 1, 9 do schoolAbsorb[i] = 0 end
    for spell, maxValue in pairs(maxAbsorb) do
        local key = schoolIdx[spellSchool[spell]]
        local current = currentAbsorb[spell] or 0
        total = total + maxValue
        estimatedCurrent = estimatedCurrent + current
        if key then
            schoolAbsorb[key] = schoolAbsorb[key] + current
        end
    end

    -- Classic Plus/future clients may expose an authoritative current absorb
    -- total. Preserve the school proportions from the local model, but scale
    -- their sum to the authoritative value so the displayed remainder is exact.
    --
    -- IMPORTANT: Classic Era 1.15 EXPOSES UnitGetTotalAbsorbs but it always
    -- returns 0 (the client does not track absorb amounts). Trusting that
    -- zero scaled every segment to nothing, blanking the bar for all shields.
    -- Only reconcile after the API has proven itself live by returning a
    -- nonzero value at least once this session.
    if ns.caps and ns.caps.absorbs and UnitGetTotalAbsorbs then
        local authoritative = UnitGetTotalAbsorbs("player")
        -- Modern clients may return a secret absorb total. Do not compare,
        -- divide, cache, or stringify it; simply skip authoritative
        -- reconciliation until the provider exposes a readable number.
        if IsReadableNumber(authoritative) then
            if authoritative > 0 then absorbApiLive = true end
            if absorbApiLive then
                if estimatedCurrent > 0 then
                    local scale = authoritative / estimatedCurrent
                    for i = 1, 9 do schoolAbsorb[i] = schoolAbsorb[i] * scale end
                elseif authoritative > 0 then
                    schoolAbsorb[1] = authoritative
                end
                if authoritative > total then total = authoritative end
            end
        end
    end

    totalAbsorb = total
    NanShield:UpdateBar(total, schoolAbsorb)
end

-- spellId required (from CLEU or UnitBuff); silent skips the redraw (rescan).
local function ApplyAura(spellName, spellId, silent, sourceIsPlayer)
    if not spellName or not spellId then return end
    local info = ShieldData:Get(spellId)
    if not info then return end

    -- Unknown source is treated as local for backward compatibility; explicit
    -- external sources use the baseline estimate described above.
    if sourceIsPlayer == nil then sourceIsPlayer = true end
    local value = CalculateAbsorbValue(spellId, info, sourceIsPlayer)
    if spellSchool[spellName] == nil then
        spellSchool[spellName] = info.school
    end

    if maxAbsorb[spellName] then
        currentAbsorb[spellName] = value
    else
        active = active + 1
        currentAbsorb[spellName] = value + (currentAbsorb[spellName] or 0)  -- damage-before-aura
    end
    maxAbsorb[spellName] = value
    if not silent then UpdateValues() end
end

local function RemoveAura(spellName)
    if currentAbsorb[spellName] then
        currentAbsorb[spellName] = nil
        active = active - 1
        if active < 1 then
            active = 0
            wipe(maxAbsorb)
            wipe(spellSchool)
        elseif cfg().nanShieldFixRemove ~= false then
            -- Default ON: a dropped shield leaves the denominator immediately so
            -- the bar re-scales (vs. leaving a phantom empty slot until all drop).
            maxAbsorb[spellName] = nil
            spellSchool[spellName] = nil
        end
        UpdateValues()
    end
end

local function ApplyDamage(spellName, value)
    local newValue = (currentAbsorb[spellName] or 0) - value
    if maxAbsorb[spellName] then
        currentAbsorb[spellName] = max(0, newValue)
        UpdateValues()
    else
        currentAbsorb[spellName] = newValue   -- damage landed before we saw the aura
    end
end

local function ResetValues()
    wipe(currentAbsorb)
    wipe(maxAbsorb)
    wipe(spellSchool)
    active = 0
    for i = 1, 255 do
        local name, _, _, _, _, _, caster, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        local sourceIsPlayer = caster and UnitIsUnit and UnitIsUnit(caster, "player") or nil
        ApplyAura(name, spellId, true, sourceIsPlayer)
    end
    UpdateValues()
end

-- ---------------------------------------------------------------------------
-- Segmented bar
-- ---------------------------------------------------------------------------
local bar, valueFS
local segs = {}
local segFS = {}                 -- per-school value FontStrings (per-section text mode)
local SEG_INSET = 1              -- keep segments inside the artwork opening
local SEG_TEXT_MIN = 4           -- smallest per-section font size before we hide it
local segTextGen = 0             -- bumped on settings change to force a restyle
local nanBarActive = false

local function UsesPlayerNameSlot()
    return ns.UF and ns.UF.IsClassicPlayerArt and ns.UF:IsClassicPlayerArt()
        and ns.UF.GetPlayerArtLayout and PlayerFrameTexture
end

local function SyncPlayerNameVisibility()
    if not PlayerName then return end
    if nanBarActive then
        PlayerName:Hide()
    else
        PlayerName:Show()
    end
end

local function SetNanBarActive(enabled)
    nanBarActive = not not enabled
    if bar then
        bar._tfNanBarActive = nanBarActive
        if nanBarActive then bar:Show() else bar:Hide() end
    end
    SyncPlayerNameVisibility()
end

-- Party-only Priest runtime must not mutate Blizzard/TurboFace Player name state
-- merely because it shares this engine. Restore PlayerName only if the Player
-- NanBar actually exists or was active in this session.
local function DisablePlayerSurface()
    if bar or nanBarActive then SetNanBarActive(false) end
end

local function ApplyNanBarChrome()
    if not bar then return end
    if UsesPlayerNameSlot() then
        -- The fixed PlayerFrame artwork already supplies the border and the
        -- shared Player backdrop supplies the empty/spent background. Keep the
        -- replacement bar itself transparent so it does not double-darken the
        -- name opening or cover the decorative frame edge.
        if bar.SetBackdrop then bar:SetBackdrop(nil) end
        if bar._tfRing then bar._tfRing:Hide() end
    else
        ns:ApplyBarBackdrop(bar)
    end
end

local function BarTexture()
    return ns.GetTexture(cfg().healthTexture)
end

local function EnsureBar()
    if bar then return bar end
    if not PlayerHealthBar() then return nil end
    bar = CreateFrame("Frame", "TurboFaceNanShield", PlayerFrame,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    -- Match the native Player health/power fill level. The custom
    -- PlayerFrameTexture frame then renders above the NanBar segments and
    -- supplies the visible border/edge clipping, just as it does for HP/power.
    bar:SetFrameLevel(PlayerHealthBar():GetFrameLevel() or 1)

    ApplyNanBarChrome()

    -- Text lift: FontStrings created directly on the bar render UNDER the
    -- child border-ring frame (child frames draw above all parent regions),
    -- and on this short bar the ring's edge art spans the full height --
    -- burying the numbers. All absorb text lives on this frame instead,
    -- leveled above the ring (ring = bar level + 2).
    local lift = CreateFrame("Frame", nil, bar)
    lift:SetAllPoints(bar)
    lift:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
    bar._tfTextLift = lift

    valueFS = lift:CreateFontString(nil, "OVERLAY")
    valueFS:SetPoint("CENTER", bar, "CENTER", 0, 0)
    valueFS:Hide()

    bar:Hide()
    return bar
end

function NanShield:LayoutBar()
    local b = EnsureBar()
    if not b or not PlayerHealthBar() then return end
    local d = cfg()
    b:ClearAllPoints()

    if UsesPlayerNameSlot() then
        -- Blizzard may refresh PlayerFrame child levels during layout updates.
        -- Re-pin the absorb fills to the same level as HP/power so the custom
        -- frame artwork always overlaps the bar while the lifted text remains
        -- readable above it.
        b:SetFrameLevel(PlayerHealthBar():GetFrameLevel() or 1)
        if b._tfTextLift then
            b._tfTextLift:SetFrameLevel((b:GetFrameLevel() or 1) + 3)
        end

        local g = ns.UF:GetPlayerArtLayout()
        -- NanBar replaces the name visually, but uses the same horizontal
        -- geometry as the health/power fills so all three bars align exactly.
        -- The health and name openings share a center in both artwork variants.
        -- NanBar keeps its current right edge but extends one additional pixel
        -- on the LEFT. Widen by 1 and move the center left by 0.5 so the
        -- expansion is asymmetric instead of growing on both sides.
        b:SetPoint(
            "CENTER", PlayerFrameTexture, "TOPLEFT",
            g.healthX + g.healthW * 0.5 - 0.5,
            -(g.nameY + g.nameH * 0.5)
        )
        b:SetSize(g.healthW + 2, g.nameH + 1)
        ApplyNanBarChrome()
    else
        local h   = d.nanShieldHeight or 8
        local gap = d.barSpacing or 1
        -- Legacy layout: sit above the HP bar. Pixel mode widens by the
        -- backdrop margin; textured mode matches the HP bar width exactly.
        local pad = (ns.GetBarBorderOutset and ns:GetBarBorderOutset() > 0) and 0 or 2
        b:SetPoint("BOTTOMLEFT",  PlayerHealthBar(), "TOPLEFT",  -(pad + 1), gap)
        b:SetPoint("BOTTOMRIGHT", PlayerHealthBar(), "TOPRIGHT",  pad, gap)
        b:SetHeight(h)
        ApplyNanBarChrome()
        if ns.GetBarBorderOutset and ns:GetBarBorderOutset() > 0 then
            if not b._tfRing then
                b._tfRing = CreateFrame("Frame", nil, b,
                    BackdropTemplateMixin and "BackdropTemplate")
                b._tfRing:SetFrameLevel((b:GetFrameLevel() or 1) + 2)
            end
            ns:AttachBarBorder(b._tfRing, b)
        elseif b._tfRing then
            b._tfRing:Hide()
        end
    end

    -- Keep Blizzard/TurboFace name refreshes from resurfacing the name while
    -- the absorb replacement is active.
    if PlayerName and not PlayerName._tfNanBarShowHooked then
        hooksecurefunc(PlayerName, "Show", function(self)
            if nanBarActive then self:Hide() end
        end)
        PlayerName._tfNanBarShowHooked = true
    end
    SyncPlayerNameVisibility()

    -- Bump the per-section text generation so any active block numbers re-style
    -- with the current font/size on the next bar update.
    segTextGen = segTextGen + 1
    if valueFS then
        StyleNanShieldText(valueFS, max(4, d.nanShieldFontSize or 9))
    end
end

-- Size a per-section number to fit inside its block: start at baseSize and step
-- down one point at a time to SEG_TEXT_MIN. Returns true if it fits (fs sized),
-- false if even the minimum overflows (caller hides it). SetFont only fires when
-- the chosen size or the settings generation actually changed.
local function FitSegText(fs, text, maxWidth, baseSize)
    local size = baseSize
    -- Apply a font BEFORE SetText: a freshly created FontString has none, and
    -- SetText would error "Font not set". Guarded so it only re-fonts on change.
    if fs._tfSize ~= size or fs._tfGen ~= segTextGen then
        fs._tfSize, fs._tfGen = size, segTextGen
        StyleNanShieldText(fs, size)
    end
    fs:SetText(text)
    while fs:GetStringWidth() > maxWidth do
        if size <= SEG_TEXT_MIN then return false end
        size = size - 1
        fs._tfSize, fs._tfGen = size, segTextGen
        StyleNanShieldText(fs, size)
    end
    return true
end

-- Render: lay out one proportional colored segment per school (index order),
-- packed left->right. Width 100% == totalAbsorb; the empty remainder is spent.
function NanShield:UpdateBar(total, values)
    local b = EnsureBar()
    if not b then return end
    local d = cfg()

    if not RuntimeEnabled() or not total or total <= 0 then
        SetNanBarActive(false)
        return
    end

    local barW = b:GetWidth()
    if not barW or barW <= 1 then
        barW = (PlayerHealthBar() and PlayerHealthBar():GetWidth()) or 160
    end
    local innerW = max(1, barW - SEG_INSET * 2)   -- fill area inside the border

    local tex = BarTexture()
    local perSection = d.nanShieldShowText and d.nanShieldPerSection
    local showCombined = d.nanShieldShowText and not perSection
    local baseSize   = max(SEG_TEXT_MIN, d.nanShieldFontSize or 9)

    -- Count active schools up front: per-section numbers only kick in once 2+
    -- schools are stacked. A single school keeps its value centered on the whole
    -- bar (like the combined total) even as the bar drains.
    local nSchools = 0
    for i = 1, 9 do
        local v = values[i]
        if v and v > 0 then nSchools = nSchools + 1 end
    end
    local perSectionActive = perSection and nSchools >= 2

    local x, used, remaining = 0, 0, 0
    for i = 1, 9 do
        local cur = values[i]
        if cur and cur > 0 then
            remaining = remaining + cur
            used = used + 1
            local seg = segs[used]
            if not seg then
                seg = b:CreateTexture(nil, "ARTWORK")
                segs[used] = seg
            end
            local w = cur / total * innerW
            seg:SetTexture(tex)
            local c = schoolColor[i]
            seg:SetVertexColor(c[1], c[2], c[3], 1)
            seg:ClearAllPoints()
            seg:SetPoint("TOPLEFT",    b, "TOPLEFT",    SEG_INSET + x,  -SEG_INSET)
            seg:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", SEG_INSET + x,   SEG_INSET)
            seg:SetWidth(max(0.5, w))
            seg:Show()

            -- Per-section number centered in this block, shrunk to fit (down to
            -- SEG_TEXT_MIN, then hidden). Only when 2+ schools are stacked.
            if perSectionActive then
                local fs = segFS[used]
                if not fs then
                    -- On the text-lift frame, above the border ring (see EnsureBar)
                    fs = (b._tfTextLift or b):CreateFontString(nil, "OVERLAY")
                    fs:SetPoint("CENTER", seg, "CENTER", 0, 0)
                    segFS[used] = fs
                end
                if FitSegText(fs, ceil(cur), max(1, w - 2), baseSize) then
                    fs:Show()
                else
                    fs:Hide()
                end
            elseif segFS[used] then
                segFS[used]:Hide()
            end

            x = x + w
        end
    end
    for j = used + 1, #segs  do segs[j]:Hide()  end
    for j = used + 1, #segFS do segFS[j]:Hide() end

    -- Centered total: combined-total mode, or per-section mode with a single
    -- school (before it sections out into 2+ blocks).
    if (showCombined or (perSection and not perSectionActive and used >= 1)) and valueFS then
        valueFS:SetText(ceil(remaining))
        valueFS:Show()
    elseif valueFS then
        valueFS:Hide()
    end

    SetNanBarActive(true)
end

-- ---------------------------------------------------------------------------
-- Priest party Power Word: Shield model + renderer
-- ---------------------------------------------------------------------------
-- Classic Era has no authoritative per-unit remaining-absorb API. For party
-- frames we therefore accept state only when THIS Priest directly applies a
-- known PW:S rank. That gives us the local caster's healing power/talents and a
-- trustworthy max value. We then subtract only SPELL_ABSORBED events attributed
-- to that shield and discard the model as soon as UNIT_AURA can no longer prove
-- the party member still has our PW:S.
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local partyShieldByGUID = {} -- destGUID -> { spellId, spellName, max, current }
local partyAuraWatch12, partyAuraWatch34

local function PartyIndexForGUID(guid)
    if not guid then return nil end
    for index = 1, 4 do
        if UnitGUID(PARTY_UNITS[index]) == guid then return index end
    end
    return nil
end

local function GetPartyFrame(index)
    return ns.UF and ns.UF.GetPartyMemberFrame and ns.UF.GetPartyMemberFrame(index) or nil
end

local function RestorePartyName(frame)
    local name = ns.UF and ns.UF.GetPartyOwnedName and ns.UF.GetPartyOwnedName(frame)
    if not name then return end
    if cfg().showPartyNames then
        -- The Party art/text layers may have been parked by an earlier disabled
        -- pass. Restoring the name must be fail-safe even if the optional
        -- NanShield renderer never completed its own layout.
        if frame and frame._tfPartyTextLayer then frame._tfPartyTextLayer:Show() end
        name:Show()
    else
        name:Hide()
    end
end

local function EnsurePartyBar(frame, forceLayout)
    if not frame then return nil end
    local b = frame._tfPartyNanShield
    if not b then
        -- Party member frames are protected. The overlay is normally prepared
        -- by UnitFrames' out-of-combat styling pass; never create it lazily from
        -- a combat-log event if that preparation did not happen.
        if InCombatLockdown and InCombatLockdown() then
            RestorePartyName(frame)
            return nil
        end
        b = CreateFrame("Frame", nil, frame)
        b:EnableMouse(false)
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetVertexColor(schoolColor[1][1], schoolColor[1][2], schoolColor[1][3], 1)

        local lift = CreateFrame("Frame", nil, b)
        lift:EnableMouse(false)
        lift:SetAllPoints(b)
        b._tfTextLift = lift

        b.valueFS = lift:CreateFontString(nil, "OVERLAY")
        b.valueFS:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.valueFS:SetJustifyH("CENTER")
        b.valueFS:SetJustifyV("MIDDLE")
        b:Hide()
        frame._tfPartyNanShield = b
    end

    b:SetFrameStrata(frame:GetFrameStrata())
    b:SetFrameLevel((frame:GetFrameLevel() or 0) + 2)
    if b._tfTextLift then
        b._tfTextLift:SetFrameStrata(frame:GetFrameStrata())
        b._tfTextLift:SetFrameLevel((frame:GetFrameLevel() or 0) + 6)
    end
    if forceLayout then b._tfPartyLayoutReady = nil end
    if not b._tfPartyLayoutReady then
        if InCombatLockdown and InCombatLockdown() then
            b:Hide()
            RestorePartyName(frame)
            return nil
        end
        local laidOut = ns.UF and ns.UF.LayoutPartyNameOverlay
            and ns.UF.LayoutPartyNameOverlay(frame, b)
        if not laidOut then
            b:Hide()
            RestorePartyName(frame)
            return nil
        end
        b._tfPartyLayoutReady = true
    end

    b.fill:SetTexture(BarTexture())
    StyleNanShieldText(b.valueFS, max(SEG_TEXT_MIN, cfg().nanShieldFontSize or 9))
    return b
end

local function UpdatePartyFrame(index)
    local frame = GetPartyFrame(index)
    if not frame then return end
    local b = frame._tfPartyNanShield
    local guid = UnitGUID(PARTY_UNITS[index])
    local state = guid and partyShieldByGUID[guid] or nil

    if not PartyRuntimeEnabled() or not state or not state.max or state.max <= 0 or state.current <= 0 then
        if b then b:Hide() end
        RestorePartyName(frame)
        return
    end

    b = EnsurePartyBar(frame, false)
    if not b then
        RestorePartyName(frame)
        return
    end

    local width = b:GetWidth() or 70
    local innerW = max(1, width - SEG_INSET * 2)
    local ratio = min(1, max(0, state.current / state.max))
    local fillW = ratio * innerW
    b.fill:ClearAllPoints()
    b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", SEG_INSET, -SEG_INSET)
    b.fill:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", SEG_INSET, SEG_INSET)
    b.fill:SetWidth(max(0.5, fillW))
    if fillW > 0 then b.fill:Show() else b.fill:Hide() end
    if cfg().nanShieldShowText then
        b.valueFS:SetText(ceil(state.current))
        b.valueFS:Show()
    else
        b.valueFS:Hide()
    end

    local name = ns.UF and ns.UF.GetPartyOwnedName and ns.UF.GetPartyOwnedName(frame)
    if name then name:Hide() end
    b:Show()
end

local function RefreshPartyFrames()
    for index = 1, 4 do UpdatePartyFrame(index) end
end

local function ClearPartyShield(guid)
    if not guid or not partyShieldByGUID[guid] then return end
    partyShieldByGUID[guid] = nil
    local index = PartyIndexForGUID(guid)
    if index then UpdatePartyFrame(index) end
end

local function ClearAllPartyShields()
    wipe(partyShieldByGUID)
    RefreshPartyFrames()
end

local function ApplyPartyShield(destGUID, spellId, spellName)
    if not PartyRuntimeEnabled() or not destGUID or not ShieldData:IsPartyPowerWordShield(spellId) then return end
    local index = PartyIndexForGUID(destGUID)
    if not index then return end
    local info = ShieldData:Get(spellId)
    if not info then return end

    local value = CalculateAbsorbValue(spellId, info, true)
    partyShieldByGUID[destGUID] = {
        spellId = spellId,
        spellName = spellName,
        max = value,
        current = value,
    }
    UpdatePartyFrame(index)
end

local function ApplyPartyAbsorbDamage(destGUID, spellName, amount)
    local state = destGUID and partyShieldByGUID[destGUID]
    if not state or not spellName or spellName ~= state.spellName then return end
    state.current = max(0, (state.current or 0) - (amount or 0))
    local index = PartyIndexForGUID(destGUID)
    if index then UpdatePartyFrame(index) end
end

local function PartyAuraStillOurs(unit, state)
    if not unit or not state then return false end
    for i = 1, 255 do
        local name, _, _, _, _, _, caster, _, _, spellId = UnitBuff(unit, i)
        if not name then break end
        if ShieldData:IsPartyPowerWordShield(spellId) then
            return name == state.spellName and caster and UnitIsUnit and UnitIsUnit(caster, "player") or false
        end
    end
    return false
end

local function ValidatePartyAuraUnit(unit)
    if not PartyRuntimeEnabled() or type(unit) ~= "string" or not unit:match("^party[1-4]$") then return end
    local guid = UnitGUID(unit)
    local state = guid and partyShieldByGUID[guid]
    if not state then return end
    if not PartyAuraStillOurs(unit, state) then
        ClearPartyShield(guid)
    end
end

local function ReconcilePartyShields()
    if not PartyRuntimeEnabled() then
        ClearAllPartyShields()
        return
    end

    local live = {}
    for index = 1, 4 do
        local unit = PARTY_UNITS[index]
        local guid = UnitGUID(unit)
        if guid then
            live[guid] = true
            local state = partyShieldByGUID[guid]
            if state and not PartyAuraStillOurs(unit, state) then
                partyShieldByGUID[guid] = nil
            end
        end
    end
    for guid in pairs(partyShieldByGUID) do
        if not live[guid] then partyShieldByGUID[guid] = nil end
    end
    RefreshPartyFrames()
end

local function EnsurePartyAuraWatchers()
    if partyAuraWatch12 then return end
    partyAuraWatch12 = CreateFrame("Frame")
    partyAuraWatch34 = CreateFrame("Frame")
    local function OnPartyAura(_, _, unit) ValidatePartyAuraUnit(unit) end
    partyAuraWatch12:SetScript("OnEvent", OnPartyAura)
    partyAuraWatch34:SetScript("OnEvent", OnPartyAura)
end

local function SetPartyAuraEvents(active)
    if partyAuraWatch12 then partyAuraWatch12:UnregisterAllEvents() end
    if partyAuraWatch34 then partyAuraWatch34:UnregisterAllEvents() end
    if not active then return end
    EnsurePartyAuraWatchers()
    ns.RegisterUnitEvent(partyAuraWatch12, "UNIT_AURA", "party1", "party2")
    ns.RegisterUnitEvent(partyAuraWatch34, "UNIT_AURA", "party3", "party4")
end

function NanShield:PreparePartyFrame(frame, index)
    if not frame then return end
    if not PartyRuntimeEnabled() then
        self:HidePartyFrame(frame)
        return
    end
    local b = EnsurePartyBar(frame, true)
    if not b then
        RestorePartyName(frame)
        return
    end
    if index then UpdatePartyFrame(index) end
end

function NanShield:HidePartyFrame(frame)
    if not frame then return end
    if frame._tfPartyNanShield then frame._tfPartyNanShield:Hide() end
    RestorePartyName(frame)
end

-- ---------------------------------------------------------------------------
-- Events / init
-- ---------------------------------------------------------------------------
local TRACKED = {
    SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true,
    SPELL_AURA_REMOVED = true, SPELL_ABSORBED = true,
}

local function ExtractAbsorbPayload(e)
    -- SPELL_ABSORBED has two layouts. With a triggering spell, the absorbing
    -- shield name is field 20 and amount is 22; for melee they are 17 and 19.
    local p20 = e[20]
    if type(p20) == "string" then return p20, e[22] or 0 end
    return e[17], e[19] or 0
end

-- Receives the packed CombatLogGetCurrentEventInfo() payload from ns.CLEU
-- (decoded once, centrally), so we index fields instead of re-invoking the C
-- call per argument.
local function OnCombatLog(e)
    local subevent, destGUID = e[2], e[8]
    if not TRACKED[subevent] or not destGUID then return end

    -- Priest party model: only direct local PW:S applications establish state.
    -- An external PW:S application/refresh to a tracked member invalidates our
    -- estimate immediately because that shield's caster stats are unknowable.
    if PartyRuntimeEnabled() then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            local spellId = e[12]
            if ShieldData:IsPartyPowerWordShield(spellId) and PartyIndexForGUID(destGUID) then
                if e[4] == playerGUID then
                    ApplyPartyShield(destGUID, spellId, e[13])
                else
                    ClearPartyShield(destGUID)
                end
            end
        elseif subevent == "SPELL_AURA_REMOVED" then
            local state = partyShieldByGUID[destGUID]
            if state and (ShieldData:IsPartyPowerWordShield(e[12]) or e[13] == state.spellName) then
                ClearPartyShield(destGUID)
            end
        elseif subevent == "SPELL_ABSORBED" then
            local absorbName, amount = ExtractAbsorbPayload(e)
            ApplyPartyAbsorbDamage(destGUID, absorbName, amount)
        end
    end

    -- The Player model coexists with the party surface and accepts all
    -- shield families modeled by ShieldData.
    if not RuntimeEnabled() or destGUID ~= playerGUID then return end
    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        ApplyAura(e[13], e[12], false, e[4] == playerGUID) -- spellName, spellId, source
    elseif subevent == "SPELL_AURA_REMOVED" then
        RemoveAura(e[13])
    elseif subevent == "SPELL_ABSORBED" then
        local absorbName, amount = ExtractAbsorbPayload(e)
        ApplyDamage(absorbName, amount)
    end
end

-- Re-apply the absorb bar backdrop + ring to the current shared border style
-- and color (settings change). LayoutBar owns the ring/width mode logic.
function ns.NanShield_ReapplyBorder()
    if bar then
        ApplyNanBarChrome()
        NanShield:LayoutBar()
    end
    if PartyRuntimeEnabled() then RefreshPartyFrames() end
end

local eventFrame
local initialized = false

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    if PartyRuntimeEnabled() then eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE") end
    if RuntimeEnabled() and ns.caps and ns.caps.absorbs then
        ns.RegisterUnitEvent(eventFrame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
    end
end

-- Player and Party are independent presentation demands under the shared Shield
-- Bar setting. The Player surface tracks all supported self absorbs; the Party
-- surface exists only for Priests and only for directly cast local PW:S.
function NanShield:Refresh()
    if ns.UnitFrameProviderAllowsNanShield and not ns.UnitFrameProviderAllowsNanShield() then return end
    local playerOn = RuntimeEnabled()
    local partyOn = PartyRuntimeEnabled()
    if not playerOn and not partyOn then
        ns.CLEU:Unregister(OnCombatLog)
        SetEvents(false)
        SetPartyAuraEvents(false)
        DisablePlayerSurface()
        ClearAllPartyShields()
        return
    end

    if not initialized then
        self:Init()
        return
    end

    SetEvents(true)
    SetPartyAuraEvents(partyOn)
    ns.CLEU:Register(OnCombatLog, TRACKED)

    if playerOn then
        self:LayoutBar()
        UpdateValues()
    else
        DisablePlayerSurface()
    end

    if partyOn then
        RefreshPartyFrames()
    else
        ClearAllPartyShields()
    end
end

function NanShield:Init()
    if ns.UnitFrameProviderAllowsNanShield and not ns.UnitFrameProviderAllowsNanShield() then return end
    if initialized or not AnyRuntimeEnabled() then return end
    initialized = true
    playerGUID = UnitGUID("player")
    InvalidateTalentCache()

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if not AnyRuntimeEnabled() then return end
        if event == "PLAYER_ENTERING_WORLD" then
            playerGUID = UnitGUID("player")
            InvalidateTalentCache()
            -- Party remainder cannot be reconstructed accurately after a load or
            -- zone transition, so wait for the next direct local PW:S cast.
            wipe(partyShieldByGUID)
            if RuntimeEnabled() then
                NanShield:LayoutBar()
                ResetValues()
            else
                DisablePlayerSurface()
            end
            RefreshPartyFrames()
            ns.CLEU:Register(OnCombatLog, TRACKED)
        elseif event == "GROUP_ROSTER_UPDATE" then
            ReconcilePartyShields()
        elseif event == "CHARACTER_POINTS_CHANGED" then
            InvalidateTalentCache()
        elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" and RuntimeEnabled() then
            UpdateValues()
        end
    end)

    SetEvents(true)
    SetPartyAuraEvents(PartyRuntimeEnabled())
    ns.CLEU:Register(OnCombatLog, TRACKED)

    if RuntimeEnabled() then
        self:LayoutBar()
        ResetValues()
    else
        DisablePlayerSurface()
    end

    -- Do not reconstruct party shields at login; exact remaining absorb is only
    -- known for shields whose local application we observed this session.
    wipe(partyShieldByGUID)
    RefreshPartyFrames()
end

-- Diagnostic: "/tfshield" injects a fake Power Word: Shield (Rank 1) through
-- the full estimation + render path, so the bar can be tested without a
-- priest. "/tfshield clear" rescans real buffs, dropping the fake. If the bar
-- renders from the fake but never from real shields, the fault is data-side
-- (CLEU/aura detection), not the visual path.
SLASH_TFSHIELD1 = "/tfshield"
SlashCmdList["TFSHIELD"] = function(msg)
    if msg and msg:match("clear") then
        ResetValues()
        ns:Chat("nanShield", "test shield cleared (rescanned real buffs).")
        return
    end
    ApplyAura("TF Test Shield", 17, false, true)
    ns:Chat("nanShield", "test shield applied in the Player name slot. '/tfshield clear' removes it.")
end
