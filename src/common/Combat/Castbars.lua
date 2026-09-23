local _, ns = ...

-- =============================================================================
-- TurboFace Castbars
-- Modern player/target cast engine with separate baked-compact and
-- legacy-standalone presentation modes.
-- into TurboFace unit frames; runtime ownership is independent of Unit Frames.
-- Standalone player/target castbar event pipeline.
-- =============================================================================

local Castbars = {}
ns.Castbars = Castbars

-- =============================================================================
-- CONSTANTS
-- =============================================================================

-- Fixed compact cast rows supplied by the unit-frame artwork set.
local COMPACT_BAR_ART = "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\CastBar.tga"
-- Mirrored artwork for the target stack (pixel-exact flip of CastBar.tga).
local COMPACT_TARGET_BAR_ART = "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\TargetCastBar.tga"
-- Castbar.tga v2 (0.11.4): 121x14, was 104x12. Interior opening measured
-- at x4..115, y3..8. Insets stay at 2 so the fill deliberately runs a
-- little under the border, matching the previous look.
local COMPACT_BAR_W, COMPACT_BAR_H = 121, 14
local COMPACT_INSET_X, COMPACT_INSET_Y = 2, 2
local COMPACT_FILL_OFFSET_Y = 2
local COMPACT_FILL_W = COMPACT_BAR_W - COMPACT_INSET_X * 2
-- Baked cast fill/background extends one extra pixel on the visual RIGHT.
-- Player is left-anchored so width alone grows right; Target is mirrored/right-
-- anchored, so ConfigureCastbarPresentation also moves its right inset outward.
local COMPACT_CAST_RIGHT_EXTEND = 1
local COMPACT_CAST_FILL_W = COMPACT_FILL_W - 2 + COMPACT_CAST_RIGHT_EXTEND
local COMPACT_TARGET_CAST_RIGHT_INSET = COMPACT_INSET_X - COMPACT_CAST_RIGHT_EXTEND
local COMPACT_FILL_H = COMPACT_BAR_H - COMPACT_INSET_Y * 2
-- Match the compact timer stack's intentional 2px texture overlap.
local COMPACT_STACK_GAP = -2
local COMPACT_CAST_X = 0.5
-- Mirror the player's half-pixel nudge across the target frame.
local COMPACT_TARGET_CAST_X = -0.5
-- Player cast row BORDER ART only: shift CastBar.tga 1px left and 1px up
-- within the frame. The frame itself, the background, and the fill all stay
-- put -- only the drawn border moves. Kept separate from COMPACT_INSET_X/Y so
-- the target cast row and the ranged row are unaffected.
-- Vertical nudge for the cast timer text. Positive is UP.
-- Raised 0.5 in 0.11.12 and another 0.5 in 0.11.13, lowered 0.5 in 0.12.8.
-- Applies to BOTH cast rows (player and target); the swing and ranged rows
-- have their own constants in SwingTimers.lua and are unaffected.
local COMPACT_TIMER_TEXT_Y = 2.0

-- Resolve the configured cast-bar fill texture
local function GetCastTexture()
    local u = TurboFaceDB and TurboFaceDB.unitframes
    -- Legacy storage path retained for profile compatibility; this is now a
    -- Global combat-timer option because standalone rows consume it too.
    local name = (u and u.castTexture) or "Blizzard"
    return ns.GetTexture(name)
end

local BAR_COLOR  = { 0.0, 0.8, 1.0 }   -- cyan cast bar
local INT_COLOR  = { 1.0, 0.2, 0.2 }   -- red when interrupted
local HOLD_TIME  = 1.2                  -- seconds to show interrupted/failed state

local STANDALONE_DEFAULT_H = 12
local STANDALONE_DEFAULT_W = 150
local STANDALONE_GAP = 2

local function StandaloneCastWidth()
    local v = TurboFaceDB and tonumber(TurboFaceDB.castBarsStandaloneWidth)
    return math.max(80, math.min(300, v or STANDALONE_DEFAULT_W))
end

local function StandaloneCastHeight()
    local v = TurboFaceDB and tonumber(TurboFaceDB.castBarsStandaloneHeight)
    return math.max(8, math.min(30, v or STANDALONE_DEFAULT_H))
end

local function StandaloneAttackHeight()
    local v = TurboFaceDB and tonumber(TurboFaceDB.swingTimersStandaloneHeight)
    return math.max(8, math.min(30, v or 12))
end

local function UseEmbeddedCast(stackKey)
    if ns.ST and ns.ST.UsesEmbeddedStack then return ns.ST:UsesEmbeddedStack(stackKey) end
    local u = TurboFaceDB and TurboFaceDB.unitframes
    if u and u.embedCombatTimers == false then return false end
    if not ns.ModuleEnabled then return true end
    return ns.ModuleEnabled("unitframes", stackKey == "target" and "target" or "player")
end

-- =============================================================================
-- STATE
-- =============================================================================

-- Target castbar state
local castbar    = nil
-- The module table itself is the shared-cadence token; no hidden driver frame
-- is needed. The scheduler is registered only while a cast/hold is in progress.
local CastTick

local active     = false
local isChannel  = false
local startTime  = 0
local endTime    = 0
local duration   = 0
local holdTime   = 0
-- Target equivalent of pCastGUID: a target queueing another spell mid-cast
-- fires FAILED for the queued spell, not the one on the bar.
local castGUIDShown = nil

-- Player castbar state (same structure, separate vars)
local pCastbar    = nil
local pActive     = false
local pIsChannel  = false
local pStartTime  = 0
local pEndTime    = 0
local pDuration   = 0
local pHoldTime   = 0
-- castGUID of the cast currently on the bar. Spamming another spell while a
-- cast is in progress fires UNIT_SPELLCAST_FAILED for the SPAMMED spell,
-- not the one being cast, so the bar must match GUIDs before reacting or it
-- reads "Failed" mid-cast. Same guard SwingTimers.lua uses for this case.
local pCastGUID   = nil

-- =============================================================================
-- BLIZZARD DEFAULT PLAYER CASTBAR SUPPRESSION
-- =============================================================================

local BLIZZARD_PLAYER_CASTBAR_NAMES = {
    "CastingBarFrame",       -- Classic Era default player cast bar
    "PlayerCastingBarFrame", -- present on some modernized Classic clients
}
local blizzardCastbarHooks = {}
local blizzardCastbarSuppressed = {}

-- MODULE MASTER GATE for the cast rows. Keep this helper above the Blizzard
-- castbar suppression code so the master switch also governs native-frame
-- behavior, not just TurboFace's custom rows.
local function CastGateOff()
    if not ns.ModuleEnabled then return false end
    return not ns.ModuleEnabled("castBars")
end

local function ShouldHideBlizzardPlayerCastbar()
    if CastGateOff() then return false end
    local u = TurboFaceDB and TurboFaceDB.unitframes
    return not (u and u.hideBlizzardPlayerCastbar == false)
end

local function EachBlizzardPlayerCastbar(callback)
    local seen = {}
    for _, name in ipairs(BLIZZARD_PLAYER_CASTBAR_NAMES) do
        local frame = _G[name]
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
end

local function SafeHideBlizzardCastbar(frame)
    if not frame or frame == pCastbar then return end
    blizzardCastbarSuppressed[frame] = true
    if frame.Hide then pcall(frame.Hide, frame) end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.EnableMouse then frame:EnableMouse(false) end
end

local function RestoreBlizzardCastbar(frame)
    if not frame or frame == pCastbar then return end
    if not blizzardCastbarSuppressed[frame] then return end
    blizzardCastbarSuppressed[frame] = nil
    if frame.SetAlpha then frame:SetAlpha(1) end
    if frame.EnableMouse then frame:EnableMouse(true) end
end

local function HideBlizzardPlayerCastbar()
    if not ShouldHideBlizzardPlayerCastbar() then
        EachBlizzardPlayerCastbar(RestoreBlizzardCastbar)
        return
    end
    EachBlizzardPlayerCastbar(SafeHideBlizzardCastbar)
end

local function InstallBlizzardPlayerCastbarHider()
    EachBlizzardPlayerCastbar(function(frame)
        if not blizzardCastbarHooks[frame] and frame.HookScript then
            blizzardCastbarHooks[frame] = true
            frame:HookScript("OnShow", function(self)
                if ShouldHideBlizzardPlayerCastbar() then
                    SafeHideBlizzardCastbar(self)
                end
            end)
        end
    end)
    HideBlizzardPlayerCastbar()
end

-- =============================================================================
-- FRAME CREATION
-- =============================================================================

local function ConfigureCastbarPresentation(f, isTarget)
    if not f then return end
    local stackKey = isTarget and "target" or "player"
    local embedded = UseEmbeddedCast(stackKey)
    f._embeddedPresentation = embedded
    f._isTargetCastbar = isTarget
    f.bar:SetTexture(GetCastTexture())

    f.bg:ClearAllPoints()
    f.bar:ClearAllPoints()
    f.timerText:ClearAllPoints()
    f.icon:ClearAllPoints()
    f.spellText:ClearAllPoints()

    if embedded then
        f:SetSize(COMPACT_BAR_W, COMPACT_BAR_H)
        f._fillWidth = COMPACT_CAST_FILL_W
        if isTarget then
            f.bg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -COMPACT_TARGET_CAST_RIGHT_INSET, -COMPACT_INSET_Y + COMPACT_FILL_OFFSET_Y)
            f.bar:SetPoint("RIGHT", f.bg, "RIGHT", 0, 0)
        else
            f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_INSET_X, -COMPACT_INSET_Y + COMPACT_FILL_OFFSET_Y)
            f.bar:SetPoint("LEFT", f.bg, "LEFT", 0, 0)
        end
        f.bg:SetSize(COMPACT_CAST_FILL_W, COMPACT_FILL_H)
        f.bar:SetHeight(COMPACT_FILL_H)
        f.spark:SetSize(6, COMPACT_FILL_H + 2)
        f.compactBorder:SetTexture(isTarget and COMPACT_TARGET_BAR_ART or COMPACT_BAR_ART)
        f.compactBorder:Show()
        f.standaloneBorder:Hide()
        f.icon:Hide()
        f.spellText:Hide()
        ns:StyleFeatureFont(f.timerText, 8, "castBarsFont", "castBarsTextStyle")
        f.timerText:SetPoint("CENTER", f, "CENTER", 0, COMPACT_TIMER_TEXT_Y)
        f.timerText:SetJustifyH("CENTER")
    else
        local w = StandaloneCastWidth()
        local h = StandaloneCastHeight()
        f:SetSize(w, h)
        f._fillWidth = w
        f.bg:SetAllPoints(f)
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.bar:SetHeight(h)
        f.spark:SetSize(8, h + 4)
        f.compactBorder:Hide()
        if ns.AttachBarBorder then ns:AttachBarBorder(f.standaloneBorder, f) end
        f.standaloneBorder:Show()

        f.icon:SetSize(math.max(h - 4, 1), math.max(h - 4, 1))
        f.icon:SetPoint("LEFT", f, "LEFT", 2, 0)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        ns:StyleFeatureFont(f.spellText, 9, "castBarsFont", "castBarsTextStyle")
        f.spellText:SetPoint("LEFT", f, "LEFT", h + 4, 0)
        f.spellText:SetPoint("RIGHT", f, "RIGHT", -30, 0)
        f.spellText:SetJustifyH("CENTER")

        ns:StyleFeatureFont(f.timerText, 9, "castBarsFont", "castBarsTextStyle")
        f.timerText:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        f.timerText:SetJustifyH("RIGHT")
    end
end

local function CreateCastbarFrame(name, isTarget)
    local f = CreateFrame("Frame", name, UIParent)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)
    f.bg = bg

    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(1)
    bar:SetTexture(GetCastTexture())
    bar:SetVertexColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3])
    f.bar = bar

    local spark = f:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetVertexColor(1, 1, 1, 0.8)
    spark:Hide()
    f.spark = spark

    local compactBorder = f:CreateTexture(nil, "OVERLAY")
    compactBorder:SetAllPoints()
    f.compactBorder = compactBorder

    local standaloneBorder = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    f.standaloneBorder = standaloneBorder

    local icon = f:CreateTexture(nil, "OVERLAY")
    f.icon = icon

    local spellText = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(spellText, 9, "castBarsFont", "castBarsTextStyle")
    spellText:SetTextColor(1, 1, 1)
    f.spellText = spellText

    local timerText = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(timerText, 8, "castBarsFont", "castBarsTextStyle")
    timerText:SetTextColor(1, 1, 1)
    f.timerText = timerText

    ConfigureCastbarPresentation(f, isTarget)
    return f
end

local function CreateCastbar()
    return CreateCastbarFrame("TurboFaceTargetCastbar", true)
end

local function CreatePlayerCastbar()
    return CreateCastbarFrame("TurboFacePlayerCastbar", false)
end

-- =============================================================================
-- LOGIC
-- =============================================================================

local function SetBarColor(r, g, b)
    if castbar then
        castbar.bar:SetVertexColor(r, g, b)
    end
end

local function ResizeCastbar(f)
    if not f then return end
    ConfigureCastbarPresentation(f, f._isTargetCastbar == true)
end

local AnchorTargetCastbar
local SetCompactTimerText

local FRAME_STRATA_BELOW = {
    TOOLTIP = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "FULLSCREEN",
    FULLSCREEN = "DIALOG",
    DIALOG = "HIGH",
    HIGH = "MEDIUM",
    MEDIUM = "LOW",
    LOW = "BACKGROUND",
    BACKGROUND = "BACKGROUND",
}

local function TargetTimerStrata()
    local tot = TargetFrameToT
    local strata = tot and tot.GetFrameStrata and tot:GetFrameStrata() or "MEDIUM"
    return FRAME_STRATA_BELOW[strata] or "LOW"
end

local function RaiseTargetCastbarAboveAttack()
    if not castbar or not UseEmbeddedCast("target") then return end

    local attack = _G.TurboFaceEnemySwingFrame or TargetFrameManaBar
    if attack then
        if castbar.SetFrameStrata then
            -- Keep the target cast row in the same lower-than-ToT strata as
            -- the attack row. Frame level still preserves cast-over-attack.
            castbar:SetFrameStrata(TargetTimerStrata())
        end
        if attack.GetFrameLevel and castbar.SetFrameLevel then
            -- The compact target attack text lives three levels above its base.
            -- Keep the whole cast row above it so the overlap is deterministic.
            castbar:SetFrameLevel((attack:GetFrameLevel() or 1) + 5)
        end
    end
end

AnchorTargetCastbar = function()
    if not castbar then return end
    ResizeCastbar(castbar)

    if not UseEmbeddedCast("target") then
        castbar:ClearAllPoints()
        local base = TargetFrameManaBar or TargetFrame or UIParent
        castbar:SetPoint("TOP", base, "BOTTOM", 0, -(STANDALONE_GAP + StandaloneAttackHeight() + STANDALONE_GAP))
        castbar._placementMode = "standalone"
        if ns.Movers and ns.Movers.ApplyElement then ns.Movers:ApplyElement("TargetCastBar") end
        return
    end

    castbar._placementMode = "embedded"
    if ns.ST and ns.ST.ReanchorTarget then ns.ST:ReanchorTarget() end
    RaiseTargetCastbarAboveAttack()
    castbar:ClearAllPoints()
    local attack = _G.TurboFaceEnemySwingFrame or TargetFrameManaBar
    if ns.ST and ns.ST.RegisterCompactRow then
        ns.ST:RegisterCompactRow(castbar, "target")
        ns.ST:PlaceCompactRow(castbar)
    else
        castbar:SetPoint("TOP", attack, "BOTTOM", COMPACT_TARGET_CAST_X, -COMPACT_STACK_GAP)
    end
end

local function ShowCast(name, texture, start, finish, channel)
    if not castbar then return end

    ResizeCastbar(castbar)

    active      = true
    if CastTick then ns.Cadence:Add(Castbars, 1 / 60, CastTick, true) end
    isChannel   = channel
    startTime   = start  / 1000
    endTime     = finish / 1000
    duration    = math.max((finish - start) / 1000, 0.001)
    holdTime    = 0

    castbar.timerText:SetTextColor(1, 1, 1)
    castbar.timerText._lastTenths = nil
    SetCompactTimerText(castbar.timerText, endTime - GetTime())
    if not castbar._embeddedPresentation then
        castbar.spellText:SetText(name or "")
        castbar.spellText:SetTextColor(1, 1, 1)
        if texture then castbar.icon:SetTexture(texture) castbar.icon:Show() else castbar.icon:Hide() end
        castbar.spellText:Show()
    end
    SetBarColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3])
    castbar.bar:SetWidth(0.001)
    castbar.spark:Show()
    castbar:Show()
    AnchorTargetCastbar()
end

local function TargetCastMatches(castGUID)
    if not active then return true end
    if not castGUIDShown or not castGUID then return true end
    return castGUIDShown == castGUID
end

local function StopCast()
    -- If showing interrupted/failed, don't hide immediately
    if holdTime > 0 then return end
    active   = false
    holdTime = 0
    if castbar then
        castbar:Hide()
        castbar.spark:Hide()
    end
end

local function FailCast(event)
    if not castbar or not active then return end
    holdTime    = HOLD_TIME
    if CastTick then ns.Cadence:Add(Castbars, 1 / 60, CastTick, true) end
    castbar.spark:Hide()

    local label = (event == "UNIT_SPELLCAST_FAILED") and (FAILED or "Failed") or (INTERRUPTED or "Interrupted")
    castbar.timerText._lastTenths = nil
    if castbar._embeddedPresentation then
        castbar.timerText:SetText(label)
        castbar.timerText:SetTextColor(1, 0.3, 0.1)
    else
        castbar.spellText:SetText(label)
        castbar.spellText:SetTextColor(1, 0.3, 0.1)
    end
    SetBarColor(INT_COLOR[1], INT_COLOR[2], INT_COLOR[3])
    castbar.bar:SetWidth(castbar._fillWidth or COMPACT_CAST_FILL_W)
end

-- The cast row sits BEHIND the attack row. The two overlap by design
-- (COMPACT_STACK_GAP is negative), and the attack bar should win that seam, so
-- the whole cast row -- background, fill, border, spark, and timer text -- is
-- pushed one level below the melee frame's base.
--
-- Same strata is required for the level comparison to mean anything: frame
-- level only orders frames within a strata, so leaving them on different
-- stratas would make the result depend on strata order instead.
local function LowerPlayerCastbarBehindMelee()
    if not pCastbar or not UseEmbeddedCast("player") then return end

    local swing = _G.TurboFacePlayerSwingFrame or PlayerFrameManaBar
    if swing then
        if swing.GetFrameStrata and pCastbar.SetFrameStrata then
            pCastbar:SetFrameStrata(swing:GetFrameStrata() or "MEDIUM")
        end
        if swing.GetFrameLevel and pCastbar.SetFrameLevel then
            -- Frame levels cannot go negative, so clamp at 0. If the melee row
            -- is itself at 0 the two tie and the ordering is undefined -- lift
            -- the melee row rather than lowering this one further.
            local swingLevel = swing:GetFrameLevel() or 1
            if swingLevel < 1 and swing.SetFrameLevel then
                swing:SetFrameLevel(1)
                swingLevel = 1
            end
            pCastbar:SetFrameLevel(math.max(swingLevel - 1, 0))
        end
    end
end

local function AnchorPlayerCastbar()
    if not pCastbar then return end
    ResizeCastbar(pCastbar)

    if not UseEmbeddedCast("player") then
        pCastbar:ClearAllPoints()
        local base = PlayerFrameManaBar or PlayerFrame or UIParent
        pCastbar:SetPoint("TOP", base, "BOTTOM", 0, -(STANDALONE_GAP + (StandaloneAttackHeight() + STANDALONE_GAP) * 3))
        pCastbar._placementMode = "standalone"
        if ns.Movers and ns.Movers.ApplyElement then ns.Movers:ApplyElement("PlayerCastBar") end
        return
    end

    pCastbar._placementMode = "embedded"
    LowerPlayerCastbarBehindMelee()
    if ns.ST and ns.ST.ReanchorPlayer then
        ns.ST:ReanchorPlayer()
        return
    end
    pCastbar:ClearAllPoints()
    local swing = _G.TurboFacePlayerSwingFrame or PlayerFrameManaBar
    if ns.ST and ns.ST.RegisterCompactRow then
        ns.ST:RegisterCompactRow(pCastbar)
        ns.ST:PlaceCompactRow(pCastbar)
    else
        pCastbar:SetPoint("TOP", swing, "BOTTOM", COMPACT_CAST_X, -COMPACT_STACK_GAP)
    end
end

-- =============================================================================
-- CAST PRESENTATION TEXT
-- Embedded rows intentionally show only progress + remaining time. Standalone
-- rows restore the older spell-icon / centered-spell-name / right-time layout.
-- =============================================================================

SetCompactTimerText = function(fontString, remaining)
    if not fontString then return end
    local tenths = math.floor(math.max(remaining or 0, 0) * 10 + 0.5)
    if fontString._lastTenths ~= tenths then
        fontString._lastTenths = tenths
        fontString:SetFormattedText("%.1f", tenths / 10)
    end
end

local function ShowPlayerCast(name, texture, start, finish, channel, spellID)
    if not pCastbar then return end

    ResizeCastbar(pCastbar)

    pActive    = true
    if CastTick then ns.Cadence:Add(Castbars, 1 / 60, CastTick, true) end
    pIsChannel = channel
    pStartTime = start  / 1000
    pEndTime   = finish / 1000
    pDuration  = math.max((finish - start) / 1000, 0.001)
    pHoldTime  = 0

    pCastbar.timerText:SetTextColor(1, 1, 1)
    pCastbar.timerText._lastTenths = nil
    SetCompactTimerText(pCastbar.timerText, pEndTime - GetTime())
    if not pCastbar._embeddedPresentation then
        pCastbar.spellText:SetText(name or "")
        pCastbar.spellText:SetTextColor(1, 1, 1)
        if texture then pCastbar.icon:SetTexture(texture) pCastbar.icon:Show() else pCastbar.icon:Hide() end
        pCastbar.spellText:Show()
    end
    pCastbar.bar:SetVertexColor(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3])
    pCastbar.bar:SetWidth(0.001)
    pCastbar.spark:Show()
    pCastbar:Show()
    AnchorPlayerCastbar()
end

-- True when an incoming terminal event belongs to the cast currently shown.
--
-- Fails OPEN when either GUID is missing: some Classic Era events (notably
-- channel starts) do not carry a usable castGUID, and in that case the old
-- unconditional behaviour is still correct. Only a confirmed mismatch -- a real
-- other spell -- is ignored, so this cannot strand the bar on a cast that
-- genuinely ended.
local function PlayerCastMatches(castGUID)
    if not pActive then return true end
    if not pCastGUID or not castGUID then return true end
    return pCastGUID == castGUID
end

local function StopPlayerCast()
    if pHoldTime > 0 then return end
    pActive   = false
    pHoldTime = 0
    if pCastbar then
        pCastbar:Hide()
        pCastbar.spark:Hide()
    end
    AnchorPlayerCastbar()
end

local function FailPlayerCast(event)
    if not pCastbar or not pActive then return end
    pHoldTime = HOLD_TIME
    if CastTick then ns.Cadence:Add(Castbars, 1 / 60, CastTick, true) end
    pCastbar.spark:Hide()
    local label = (event == "UNIT_SPELLCAST_FAILED") and (FAILED or "Failed") or (INTERRUPTED or "Interrupted")
    pCastbar.timerText._lastTenths = nil
    if pCastbar._embeddedPresentation then
        pCastbar.timerText:SetText(label)
        pCastbar.timerText:SetTextColor(1, 0.3, 0.1)
    else
        pCastbar.spellText:SetText(label)
        pCastbar.spellText:SetTextColor(1, 0.3, 0.1)
    end
    pCastbar.bar:SetVertexColor(INT_COLOR[1], INT_COLOR[2], INT_COLOR[3])
    pCastbar.bar:SetWidth(pCastbar._fillWidth or COMPACT_CAST_FILL_W)
end

-- =============================================================================
-- CADENCE TICK
-- =============================================================================

CastTick = function(self, elapsed)
    local now = GetTime()

    -- ── Target castbar ───────────────────────────────────────────────────────
    if castbar then
        if holdTime > 0 then
            holdTime = holdTime - elapsed
            if holdTime <= 0 then
                holdTime = 0
                active   = false
                castbar:Hide()
                castbar.spark:Hide()
            end
        elseif active then
            if not UnitExists("target") then
                StopCast()
            else
                local pct
                if isChannel then
                    pct = (endTime - now) / duration
                else
                    pct = (now - startTime) / duration
                end
                pct = math.max(0, math.min(1, pct))
                local fillW = castbar._fillWidth or COMPACT_CAST_FILL_W
                local barW = math.max(pct * fillW, 0.001)
                castbar.bar:SetWidth(barW)
                castbar.spark:ClearAllPoints()
                if castbar._embeddedPresentation then
                    castbar.spark:SetPoint("CENTER", castbar, "RIGHT", -(COMPACT_TARGET_CAST_RIGHT_INSET + barW), COMPACT_FILL_OFFSET_Y)
                else
                    castbar.spark:SetPoint("CENTER", castbar, "LEFT", barW, 0)
                end
                SetCompactTimerText(castbar.timerText, endTime - now)
                if now >= endTime then StopCast() end
            end
        end
    end

    -- ── Player castbar ───────────────────────────────────────────────────────
    if pCastbar then
        if pHoldTime > 0 then
            pHoldTime = pHoldTime - elapsed
            if pHoldTime <= 0 then
                pHoldTime = 0
                pActive   = false
                pCastbar:Hide()
                pCastbar.spark:Hide()
                AnchorPlayerCastbar()
            end
        elseif pActive then
            local ppct
            if pIsChannel then
                ppct = (pEndTime - now) / pDuration
            else
                ppct = (now - pStartTime) / pDuration
            end
            ppct = math.max(0, math.min(1, ppct))
            local pFillW = pCastbar._fillWidth or COMPACT_CAST_FILL_W
            local pBarW = math.max(ppct * pFillW, 0.001)
            pCastbar.bar:SetWidth(pBarW)
            pCastbar.spark:ClearAllPoints()
            if pCastbar._embeddedPresentation then
                pCastbar.spark:SetPoint("CENTER", pCastbar, "LEFT", COMPACT_INSET_X + pBarW, COMPACT_FILL_OFFSET_Y)
            else
                pCastbar.spark:SetPoint("CENTER", pCastbar, "LEFT", pBarW, 0)
            end
            SetCompactTimerText(pCastbar.timerText, pEndTime - now)
            if now >= pEndTime then StopPlayerCast() end
        end
    end

    -- Nothing casting and no fail/interrupt hold: park the driver until the
    -- next cast event shows it again
    if not active and holdTime <= 0 and not pActive and pHoldTime <= 0 then
        ns.Cadence:Remove(Castbars)
    end
end

-- =============================================================================
-- EVENTS
-- =============================================================================

local eventFrame
local CastEventHandler
local eventsRegistered = false

local function EnsureCastEventFrame()
    if eventFrame then return eventFrame end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", CastEventHandler)
    return eventFrame
end

local function RegisterCastEvents()
    if eventsRegistered then return end
    local frame = EnsureCastEventFrame()
    eventsRegistered = true
    -- player+target only, which is Blizzard's two-token maximum. The handler
    -- routes on `unit == "player"` then `unit ~= "target" -> return`.
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_START", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_STOP", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_FAILED", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_INTERRUPTED", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_DELAYED", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_CHANNEL_START", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "target")
    ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "target")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

CastEventHandler = function(self, event, unit, castGUID)
    if CastGateOff() then
        HideBlizzardPlayerCastbar() -- restores Blizzard visibility if needed
        return
    end
    InstallBlizzardPlayerCastbarHider()
    -- All spellcast events pass unit as first arg
    if event == "PLAYER_TARGET_CHANGED" then
        active   = false
        holdTime = 0
        castGUIDShown = nil
        if castbar then castbar:Hide() castbar.spark:Hide() end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Left combat — hide player castbar if no active cast
        if not pActive then
            if pCastbar then pCastbar:Hide() end
            AnchorPlayerCastbar()
        end
        return
    end

    -- Player events
    if unit == "player" then
        if event == "UNIT_SPELLCAST_START" then
            local name, _, texture, start, finish = UnitCastingInfo("player")
            local spellID = select(9, UnitCastingInfo("player"))
            if name then
                pCastGUID = castGUID
                ShowPlayerCast(name, texture, start, finish, false, spellID)
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            local name, _, texture, start, finish = UnitChannelInfo("player")
            local spellID = select(8, UnitChannelInfo("player"))
            if name then
                pCastGUID = castGUID
                ShowPlayerCast(name, texture, start, finish, true, spellID)
            end

        elseif event == "UNIT_SPELLCAST_DELAYED" then
            local name, _, _, start, finish = UnitCastingInfo("player")
            if name and pActive then
                pStartTime = start / 1000
                pEndTime   = finish / 1000
                pDuration  = math.max((finish - start) / 1000, 0.001)
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            local name, _, _, start, finish = UnitChannelInfo("player")
            if name and pActive then
                pStartTime = start / 1000
                pEndTime   = finish / 1000
                pDuration  = math.max((finish - start) / 1000, 0.001)
            end

        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if PlayerCastMatches(castGUID) then
                pCastGUID = nil
                StopPlayerCast()
            end

        elseif event == "UNIT_SPELLCAST_FAILED" then
            if PlayerCastMatches(castGUID) then
                pCastGUID = nil
                FailPlayerCast("UNIT_SPELLCAST_FAILED")
            end

        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            if PlayerCastMatches(castGUID) then
                pCastGUID = nil
                FailPlayerCast("UNIT_SPELLCAST_INTERRUPTED")
            end
        end
        return
    end

    if unit ~= "target" then return end

    if event == "UNIT_SPELLCAST_START" then
        -- NOTE: UnitCastingInfo's notInterruptible return is deliberately not
        -- read here. Nameplate castbars colour uninterruptible casts via
        -- The target unit castbar has no nameplate-color dependency;
        -- equivalent treatment yet. Wire ShowCast up to it rather than
        -- destructuring a value nothing consumes.
        local name, _, texture, start, finish = UnitCastingInfo("target")
        if name then
            castGUIDShown = castGUID
            ShowCast(name, texture, start, finish, false)
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local name, _, texture, start, finish = UnitChannelInfo("target")
        if name then
            castGUIDShown = castGUID
            ShowCast(name, texture, start, finish, true)
        end

    elseif event == "UNIT_SPELLCAST_DELAYED" then
        local name, _, _, start, finish = UnitCastingInfo("target")
        if name and active then
            startTime = start  / 1000
            endTime   = finish / 1000
            duration  = math.max((finish - start) / 1000, 0.001)
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local name, _, _, start, finish = UnitChannelInfo("target")
        if name and active then
            startTime = start  / 1000
            endTime   = finish / 1000
            duration  = math.max((finish - start) / 1000, 0.001)
        end

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if TargetCastMatches(castGUID) then
            castGUIDShown = nil
            StopCast()
        end

    elseif event == "UNIT_SPELLCAST_FAILED" then
        if TargetCastMatches(castGUID) then
            castGUIDShown = nil
            FailCast("UNIT_SPELLCAST_FAILED")
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if TargetCastMatches(castGUID) then
            castGUIDShown = nil
            FailCast("UNIT_SPELLCAST_INTERRUPTED")
        end
    end
end

-- =============================================================================
-- PUBLIC
-- =============================================================================

-- Baked cast rows use the current 121x14 compact UnitFrame geometry. Standalone
-- rows reuse the same cast engine but switch to the legacy tooltip-border, spell
-- icon/name, right-side countdown presentation and independent movers.
local function HideAllCastRows()
    if pCastbar then pCastbar:Hide() end
    if castbar then castbar:Hide() end
end

local function DeactivateRuntime()
    if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
    eventsRegistered = false
    if ns.Cadence then ns.Cadence:Remove(Castbars) end
    active, pActive = false, false
    holdTime, pHoldTime = 0, 0
    castGUIDShown, pCastGUID = nil, nil
    HideAllCastRows()
    HideBlizzardPlayerCastbar()
end

function Castbars:RegisterTimerMovers(movers)
    if not movers or not movers.RegisterElement then return end
    local function available(stackKey)
        if UseEmbeddedCast(stackKey) then return false end
        if not ns.ModuleEnabled then return true end
        return ns.ModuleEnabled("castBars")
    end
    if pCastbar then
        movers:RegisterElement("PlayerCastBar", pCastbar, {
            label = "Player Cast Bar", overlayWidth = pCastbar:GetWidth(), overlayHeight = pCastbar:GetHeight(),
            defaultPoint = { pCastbar:GetPoint(1) },
            isAvailable = function() return available("player") end,
        })
    end
    if castbar then
        movers:RegisterElement("TargetCastBar", castbar, {
            label = "Target Cast Bar", overlayWidth = castbar:GetWidth(), overlayHeight = castbar:GetHeight(),
            defaultPoint = { castbar:GetPoint(1) },
            isAvailable = function() return available("target") end,
        })
    end
end

function Castbars:Init()
    if CastGateOff() then
        DeactivateRuntime()
        return
    end
    RegisterCastEvents()
    castbar  = CreateCastbar()
    pCastbar = CreatePlayerCastbar()
    InstallBlizzardPlayerCastbarHider()
    AnchorTargetCastbar()
    AnchorPlayerCastbar()

    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() if Castbars.Refresh then Castbars:Refresh() end end)
    end
end

function Castbars:Refresh()
    if CastGateOff() then
        DeactivateRuntime()
        return
    end
    RegisterCastEvents()
    InstallBlizzardPlayerCastbarHider()
    ResizeCastbar(castbar)
    ResizeCastbar(pCastbar)

    if castbar then AnchorTargetCastbar() end
    if pCastbar then AnchorPlayerCastbar() end

    if castbar then ConfigureCastbarPresentation(castbar, true) end
    if pCastbar then ConfigureCastbarPresentation(pCastbar, false) end
end

ns.Castbars = Castbars

ns.RegisterCPUProfileTarget("Combat/Castbars:Events", CastEventHandler)
ns.RegisterCPUProfileTarget("Combat/Castbars:Tick", CastTick)
