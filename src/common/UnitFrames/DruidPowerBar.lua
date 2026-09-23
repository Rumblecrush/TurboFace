local _, ns = ...

local function PlayerHealthBar()
    return (ns.UnitFrameProviderPlayerHealthBar and ns.UnitFrameProviderPlayerHealthBar()) or _G.PlayerFrameHealthBar
end
local function PlayerManaBar()
    return (ns.UnitFrameProviderPlayerManaBar and ns.UnitFrameProviderPlayerManaBar()) or _G.PlayerFrameManaBar
end

-- =============================================================================
-- TurboFace DruidPowerBar.lua
-- Classic Era, DRUID-only.
--
-- While shapeshifted into Bear (Rage) or Cat (Energy) form the Blizzard player
-- power bar shows the form's power, so mana is hidden. This adds a small mana
-- bar so a druid can watch mana for shifting / healing without leaving form.
--
-- Presentation ownership is automatic:
--   * TurboFace Player Unit Frame enabled -> baked into the fixed auxiliary-Mana
--     slot supplied by UI-Player-Portrait-Druid.tga.
--   * TurboFace Player Unit Frame disabled -> standalone legacy bar directly
--     beneath Blizzard's player power bar, with the shared tooltip border and
--     its own optional Movers element.
--   * Not a protected frame, so show/hide/anchor is safe in combat.
--   * Visible only in Bear/Cat form (UnitPowerType is Rage/Energy) and only
--     when the druid actually has a mana pool.
--   * Uses the modern power events (UNIT_POWER_UPDATE / UNIT_MAXPOWER /
--     UNIT_DISPLAYPOWER), never the removed 3.3.5-era UNIT_MANA path.
-- =============================================================================

local _, PLAYER_CLASS = UnitClass("player")
if PLAYER_CLASS ~= "DRUID" then return end

local DPB = ns.DruidPowerBar or {}
ns.DruidPowerBar = DPB

local CreateFrame     = CreateFrame
local UnitPower       = UnitPower
local UnitPowerMax    = UnitPowerMax
local UnitPowerType   = UnitPowerType
local GetCVar         = GetCVar
local GetCVarBool     = GetCVarBool
local PowerBarColor   = PowerBarColor
local tonumber        = tonumber
local math_max        = math.max
local math_min        = math.min
local math_floor      = math.floor


-- Resolve a bar texture the same way the unit frames do: LSM statusbar by name,
-- falling back to TurboFace's bundled texture table.

-- Power-type indices (Enum in Classic Era; literal fallback for safety).
local MANA_INDEX = (Enum and Enum.PowerType and Enum.PowerType.Mana)   or 0
local RAGE       = (Enum and Enum.PowerType and Enum.PowerType.Rage)   or 1
local ENERGY     = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

-- Forms in which we want the extra mana bar: Bear (Rage) and Cat (Energy).
local SHOW_IN_POWER = { [RAGE] = true, [ENERGY] = true }

local STANDALONE_BAR_H = 12
local STANDALONE_GAP = 2
local STANDALONE_FALLBACK_W = 150

local function UseEmbeddedMode()
    if ns.ModuleEnabled then
        return ns.ModuleEnabled("unitframes", "player")
    end
    return true
end

function DPB:IsEmbeddedMode() return UseEmbeddedMode() end
function DPB:IsStandaloneMode() return not UseEmbeddedMode() end

local function StandaloneBase()
    return PlayerManaBar() or PlayerHealthBar() or PlayerFrame or UIParent
end

local function StandaloneBarWidth()
    local health = PlayerHealthBar()
    if ns.GetBarBorderOutset and ns:GetBarBorderOutset() > 0 then
        local w = health and health.GetWidth and health:GetWidth()
        if w and w > 0 then return w end
    end
    local bd = PlayerFrame and PlayerFrame._srBackdrop
    if bd and bd.GetWidth then
        local w = bd:GetWidth()
        if w and w > 1 then return w end
    end
    local w = health and health.GetWidth and health:GetWidth()
    return (w and w > 0) and (w + 4) or STANDALONE_FALLBACK_W
end

local function MoverHidden()
    if UseEmbeddedMode() or not (ns.MoversEnabled and ns.MoversEnabled()) then return false end
    local movers = TurboFaceDB and TurboFaceDB.movers
    local elements = movers and movers.elements
    local db = elements and elements.DruidPowerBar
    return db and db.hidden == true
end

local bar
local ShouldShow
local manaAmtLast = -1   -- last mana value, for the "+X" regen tick-amount popup

-- ---------------------------------------------------------------------------
-- DB helpers (flat TurboFaceDB keys, defaults in Core/Config.lua)
-- ---------------------------------------------------------------------------
local DB = ns.DB   -- shared root accessor (Config.lua)


-- Gap between stacked player bars — matches the unit-frame bar spacing so the
-- druid bar lines up flush with the health/power bars.
local function StackGap()
    local u = TurboFaceDB and TurboFaceDB.unitframes
    return (u and u.barSpacing) or 2
end

-- Notify companion modules after the auxiliary bar changes visibility. The old
-- shared player backdrop is parked by the fixed-art prototype; swing/cast bars
-- still use the reanchor notification until their dedicated overhaul lands.
local function NotifyStackChanged()
    if ns.UF and ns.UF.RefreshPlayerBackdrop then ns.UF:RefreshPlayerBackdrop() end
    if ns.ST and ns.ST.ReanchorPlayer     then ns.ST:ReanchorPlayer()     end
end

-- ---------------------------------------------------------------------------
-- Style (texture + color) — mirrors the unit-frame bar styling
-- ---------------------------------------------------------------------------
local function ApplyStyle()
    if not bar then return end
    -- Texture first, then color (SetStatusBarTexture swaps the texture region, so
    -- the vertex color must be re-applied afterwards).
    --
    -- Embedded mode is visually owned by the TurboFace Player Unit Frame and
    -- therefore follows its power-bar texture. Standalone mode is Class-owned
    -- and uses the Druid Power Bar's own texture selection.
    local ufCfg = TurboFaceDB and TurboFaceDB.unitframes
    local texName
    if UseEmbeddedMode() then
        texName = (ufCfg and ufCfg.manaTexture) or "Blizzard"
    else
        texName = ns.Opt("druidPowerBarTexture", "Blizzard")
    end
    bar:SetStatusBarTexture(ns.ResolveStatusBarTexture(texName))
    local mana = PowerBarColor and PowerBarColor["MANA"]
    if mana then
        bar:SetStatusBarColor(mana.r, mana.g, mana.b)
    else
        bar:SetStatusBarColor(0, 0, 1)
    end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local function ApplyEmbeddedLayout()
    if not bar then return end
    local artX, artY, artW, artH
    if ns.UF and ns.UF.GetDruidPowerGeometry then
        artX, artY, artW, artH = ns.UF:GetDruidPowerGeometry()
    end
    local h = artH or 12

    bar:ClearAllPoints()
    if artX and PlayerFrameTexture then
        -- Fixed Druid artwork slot: position directly in source-texture space,
        -- independent of standalone mover state.
        bar:SetPoint("TOPLEFT", PlayerFrameTexture, "TOPLEFT", artX, -artY)
        bar:SetSize(artW, h)
    else
        -- Defensive fallback while the UnitFrame art finishes initializing.
        local anchor = PlayerFrameManaBar or PlayerFrameHealthBar
        if not anchor then return end
        local gap = StackGap()
        bar:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -gap)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
        bar:SetHeight(h)
    end

    if PlayerFrameManaBar and PlayerFrameManaBar.GetFrameStrata then
        bar:SetFrameStrata(PlayerFrameManaBar:GetFrameStrata() or "MEDIUM")
    end
    bar:SetFrameLevel(PlayerFrameManaBar and PlayerFrameManaBar:GetFrameLevel()
        or ((PlayerFrame:GetFrameLevel() or 0) + 1))
    if bar.textLayer then
        bar.textLayer:SetFrameStrata("HIGH")
        bar.textLayer:SetFrameLevel((bar:GetFrameLevel() or 0) + 20)
    end
    if bar.bg then bar.bg:Hide() end
    if bar.standaloneBorder then bar.standaloneBorder:Hide() end

    return h
end

local function ApplyStandaloneLayout()
    if not bar then return end
    local anchor = StandaloneBase()
    local h = STANDALONE_BAR_H

    bar:ClearAllPoints()
    bar:SetPoint("TOP", anchor, "BOTTOM", 0, -STANDALONE_GAP)
    bar:SetSize(StandaloneBarWidth(), h)
    if anchor and anchor.GetFrameStrata then
        bar:SetFrameStrata(anchor:GetFrameStrata() or "MEDIUM")
    else
        bar:SetFrameStrata("MEDIUM")
    end
    bar:SetFrameLevel((anchor and anchor.GetFrameLevel and anchor:GetFrameLevel() or 1) + 2)
    if bar.textLayer then
        bar.textLayer:SetFrameStrata("HIGH")
        bar.textLayer:SetFrameLevel((bar:GetFrameLevel() or 0) + 20)
    end
    if bar.bg then bar.bg:Show() end
    if bar.standaloneBorder and ns.AttachBarBorder then
        bar.standaloneBorder:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
        ns:AttachBarBorder(bar.standaloneBorder, bar)
    end

    return h
end

local function AnchorBar()
    if not bar then return end
    local h
    if UseEmbeddedMode() then
        h = ApplyEmbeddedLayout()
    else
        h = ApplyStandaloneLayout()
        -- Movers is initialized after this Class feature. Once active, reapply
        -- the saved standalone point after restoring the deterministic fallback
        -- anchor above. With Movers disabled the fallback remains authoritative.
        if ns.Movers and ns.Movers.active and ns.Movers.ApplyElement then
            ns.Movers:ApplyElement("DruidPowerBar")
        end
    end
    h = h or STANDALONE_BAR_H

    if bar.text and ns.StyleFeatureFont then
        local size = tonumber(ns.Opt("druidPowerBarTextSize", 11)) or 11
        if size < 1 then size = math_max(7, math_floor(h * 0.8)) end
        for _, fs in ipairs({ bar.text, bar.textLeft, bar.textRight }) do
            if fs then ns:StyleFeatureFont(fs, size, "druidPowerBarFont", "druidPowerBarTextStyle") end
        end

        bar.text:ClearAllPoints()
        bar.text:SetPoint("CENTER", bar, "CENTER", 0, -0.5)

        if bar.textLeft then
            bar.textLeft:ClearAllPoints()
            bar.textLeft:SetPoint("LEFT", bar, "LEFT", 2, -0.5)
            bar.textLeft:SetPoint("RIGHT", bar, "CENTER", -1, -0.5)
            bar.textLeft:SetJustifyH("LEFT")
        end
        if bar.textRight then
            bar.textRight:ClearAllPoints()
            bar.textRight:SetPoint("LEFT", bar, "CENTER", 1, -0.5)
            bar.textRight:SetPoint("RIGHT", bar, "RIGHT", -2, -0.5)
            bar.textRight:SetJustifyH("RIGHT")
        end
    end
end

-- Legacy stack extent API retained for companion compatibility. Fixed-art mode
-- returns zero because the Druid bar occupies a reserved slot inside the art.
function DPB:GetStackExtent()
    if UseEmbeddedMode() then return 0 end
    if not (bar and bar:IsShown()) then return 0 end
    return STANDALONE_GAP + STANDALONE_BAR_H
end

-- Public read-only access for companion modules such as PowerCost. Returning
-- the TurboFace-owned bar lets the shared mana ticker attach to the auxiliary
-- mana display while shifted without creating a second animation driver.
function DPB:GetBar()
    return bar
end

function DPB:RefreshBorder()
    if not (bar and bar.standaloneBorder) then return end
    if UseEmbeddedMode() then
        bar.standaloneBorder:Hide()
    elseif ns.AttachBarBorder then
        ns:AttachBarBorder(bar.standaloneBorder, bar)
    end
end

function DPB:RegisterMover()
    if not bar or UseEmbeddedMode() then return end
    if not (ns.Movers and ns.Movers.RegisterElement) then return end
    local base = StandaloneBase()
    local fallback = { "TOP", base, "BOTTOM", 0, -STANDALONE_GAP }
    ns.Movers:RegisterElement("DruidPowerBar", bar, {
        label = "Druid Power Bar",
        overlayWidth = bar:GetWidth(),
        overlayHeight = STANDALONE_BAR_H,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        isAvailable = function()
            return not UseEmbeddedMode()
                and (not ns.ModuleEnabled or ns.ModuleEnabled("class"))
                and ns.Opt("druidPowerBarEnabled", true) ~= false
        end,
        -- If a live options change moves this feature back into the baked-in
        -- UnitFrame mode, never allow a previously registered standalone mover
        -- to pull it out of the artwork slot.
        onApply = function()
            if UseEmbeddedMode() then
                ApplyEmbeddedLayout()
            elseif bar and ShouldShow then
                local wasShown = bar:IsShown()
                if ShouldShow() then bar:Show() else bar:Hide() end
                if wasShown ~= bar:IsShown() then NotifyStackChanged() end
            end
        end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("DruidPowerBar") end
end

-- ---------------------------------------------------------------------------
-- Status text (TurboFace-controlled, with the same formats as unit frames)
-- ---------------------------------------------------------------------------
local function UpdateText()
    local t = bar and bar.text
    local left = bar and bar.textLeft
    local right = bar and bar.textRight
    if not t then return end

    local function HideAll()
        t:SetText("")
        t:Hide()
        if left then left:SetText(""); left:Hide() end
        if right then right:SetText(""); right:Hide() end
    end

    local wantText = ns.Opt("druidPowerBarStatusText", false)
    if not wantText then
        HideAll()
        return
    end

    local cur = UnitPower("player", MANA_INDEX)
    local max = UnitPowerMax("player", MANA_INDEX)
    if max <= 0 then
        HideAll()
        return
    end

    local mode = ns.Opt("druidPowerBarTextFormat", "current-max")
    local pct = math_floor(cur / max * 100 + 0.5)

    if mode == "none" then
        HideAll()
        return
    elseif mode == "percent-current-blizzard" then
        t:SetText("")
        t:Hide()
        if left and right then
            left:SetText(pct .. "%")
            right:SetText(tostring(cur))
            left:Show()
            right:Show()
        end
        return
    end

    if left then left:SetText(""); left:Hide() end
    if right then right:SetText(""); right:Hide() end

    local str
    if mode == "percent" then
        str = pct .. "%"
    elseif mode == "current" then
        str = tostring(cur)
    elseif mode == "current-max-pct" then
        str = cur .. " / " .. max .. " (" .. pct .. "%)"
    elseif mode == "current-pct" then
        str = cur .. " (" .. pct .. "%)"
    else
        str = cur .. " / " .. max
    end

    t:SetText(str)
    t:Show()
end

-- ---------------------------------------------------------------------------
-- Value / max
-- ---------------------------------------------------------------------------
local function UpdateMax()
    if not bar then return end
    bar:SetMinMaxValues(0, UnitPowerMax("player", MANA_INDEX))
end

local function UpdateValue()
    if not bar or not bar:IsShown() then return end
    bar:SetValue(UnitPower("player", MANA_INDEX))
    UpdateText()
end

-- Regen "+X" tick-amount popup on the druid mana bar (mirrors PowerCost's HP /
-- power popups). Shown only while the bar is visible (i.e. shifted), follows the
-- power "tick amount" toggle, and is drawn/faded by ns.Power:ShowTickAmount.
local function ManaColor()
    -- Single source of truth: PowerCost's brightened resource color, so the
    -- druid-bar "+X" always matches the normal bar's mana popups exactly.
    if ns.Power and ns.Power.GetTickAmountColor then
        return ns.Power:GetTickAmountColor(MANA_INDEX)
    end
    -- Fallback (PowerCost unavailable): brightened mana blue (matches
    -- PowerCost's TICK_BRIGHTEN of 150/255).
    local c = PowerBarColor and PowerBarColor["MANA"]
    local r, g, b = 0.20, 0.40, 1.00
    if c then r, g, b = c.r, c.g, c.b end
    local function br(x) return math_min(1, (x or 0) + 150 / 255) end
    return br(r), br(g), br(b)
end

local function MaybeShowManaAmount()
    if not (bar and bar:IsShown()) then return end
    local pd = TurboFaceDB and TurboFaceDB.power
    if pd and pd.powerTickAmount == false then return end
    if not (ns.Power and ns.Power.ShowTickAmount) then return end
    local cur = UnitPower("player", MANA_INDEX) or 0
    if manaAmtLast >= 0 and cur > manaAmtLast then
        local r, g, b = ManaColor()
        ns.Power:ShowTickAmount(bar, cur - manaAmtLast, r, g, b)
    end
    manaAmtLast = cur
end

-- ---------------------------------------------------------------------------
-- Bar construction
-- ---------------------------------------------------------------------------
local function EnsureBar()
    if bar then return bar end
    if not PlayerFrame then return nil end

    bar = CreateFrame("StatusBar", "TurboFaceDruidPowerBar", PlayerFrame)
    -- Match the player power bar's strata so the two rows resolve against each
    -- other by frame level alone; level ordering is only meaningful within a
    -- strata. AnchorBar re-asserts this once PlayerFrameManaBar exists.
    bar:SetFrameStrata((PlayerFrameManaBar and PlayerFrameManaBar.GetFrameStrata
        and PlayerFrameManaBar:GetFrameStrata()) or "MEDIUM")
    bar:SetFrameLevel((PlayerFrame:GetFrameLevel() or 0) + 2)
    bar:EnableMouse(false)

    -- Dark fill behind the unfilled portion -- the SAME shade as every other
    -- bar background (per-bar _tfRingBG / ApplyBarBackdrop fill), so this bar
    -- reads as part of the health/power stack rather than a lighter box.
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)
    bar.bg = bg

    -- Standalone presentation uses the same locked Blizzard Tooltip border as
    -- TurboFace's legacy swing/cast bars. Embedded mode hides this ring because
    -- the UnitFrame artwork already owns the surrounding chrome.
    local border = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate")
    border:Hide()
    bar.standaloneBorder = border

    -- A dedicated foreground frame keeps the value text above the Druid art
    -- without lifting the StatusBar fill itself above the texture.
    local textLayer = CreateFrame("Frame", nil, bar)
    textLayer:SetAllPoints(bar)
    textLayer:SetFrameStrata("HIGH")
    textLayer:SetFrameLevel((bar:GetFrameLevel() or 0) + 20)
    textLayer:EnableMouse(false)
    bar.textLayer = textLayer

    local text = textLayer:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    text:SetPoint("CENTER", bar, "CENTER", 0, -0.5)
    text:SetText("")
    bar.text = text

    -- Blizzard-style dual layout for Percent Current (Blizzard): percent on
    -- the inside-left, current mana on the inside-right. These are TurboFace-
    -- owned FontStrings so Blizzard's global status-text CVar cannot rewrite
    -- or re-anchor them.
    local textLeft = textLayer:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    textLeft:SetPoint("LEFT", bar, "LEFT", 2, -0.5)
    textLeft:SetPoint("RIGHT", bar, "CENTER", -1, -0.5)
    textLeft:SetJustifyH("LEFT")
    textLeft:SetText("")
    textLeft:Hide()
    bar.textLeft = textLeft

    local textRight = textLayer:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    textRight:SetPoint("LEFT", bar, "CENTER", 1, -0.5)
    textRight:SetPoint("RIGHT", bar, "RIGHT", -2, -0.5)
    textRight:SetJustifyH("RIGHT")
    textRight:SetText("")
    textRight:Hide()
    bar.textRight = textRight

    DPB.bar = bar

    ApplyStyle()
    AnchorBar()
    bar:Hide()
    return bar
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------
ShouldShow = function()
    if ns.Opt("druidPowerBarEnabled", true) == false then return false end
    if MoverHidden() then return false end
    if UnitPowerMax("player", MANA_INDEX) <= 0 then return false end
    return SHOW_IN_POWER[UnitPowerType("player")] == true
end

local function UpdateVisibility()
    -- MODULE MASTER GATE: modules.class off -> no class-specific behavior at
    -- all. ns.ModuleEnabled fails open, so an unmigrated DB is unaffected.
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then
        -- Mirror the normal hide path rather than a bare return: this bar
        -- occupies a slot in the player bar stack, so the backdrop and the bars
        -- below it must be re-flowed or they keep the reserved gap.
        if bar then
            bar:Hide()
            manaAmtLast = -1
            NotifyStackChanged()
            if ns.Power and ns.Power.RefreshMarkers then ns.Power:RefreshMarkers() end
        end
        return
    end
    if not EnsureBar() then return end
    if ShouldShow() then
        AnchorBar()
        UpdateMax()
        bar:Show()
        UpdateValue()
        -- Re-baseline so becoming visible (shifting into form) doesn't count as
        -- one huge "+X" mana gain on the first tick.
        manaAmtLast = UnitPower("player", MANA_INDEX) or -1
    else
        bar:Hide()
        manaAmtLast = -1
    end
    -- Bar shown/hidden state is now settled; re-flow the backdrop + lower bars.
    NotifyStackChanged()
    -- Form/display-power event ordering is not guaranteed. Explicitly wake the
    -- shared marker driver after this bar's visibility settles so the hidden
    -- mana ticker appears immediately when shifting.
    if ns.Power and ns.Power.RefreshMarkers then ns.Power:RefreshMarkers() end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
-- The event frame is lazy: a Druid with this feature disabled should not pay
-- for an inert WoW frame merely because the class-specific file was loaded.
local frame
local initialized = false

local function DruidPowerOnEvent(_, event)
    if event == "UNIT_POWER_UPDATE" then
        UpdateValue()
        MaybeShowManaAmount()
    elseif event == "UNIT_MAXPOWER" then
        UpdateMax()
        UpdateValue()
    else
        -- PLAYER_ENTERING_WORLD / UPDATE_SHAPESHIFT_FORM / UNIT_DISPLAYPOWER
        -- all imply a possible form/visibility change.
        UpdateVisibility()
    end
end

local function EnsureEventFrame()
    if frame then return frame end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", DruidPowerOnEvent)
    return frame
end

-- ---------------------------------------------------------------------------
-- Public: activation / options refresh
-- ---------------------------------------------------------------------------
local function RuntimeAllowed()
    if ns.UnitFrameProviderAllowsDruidPowerBar and not ns.UnitFrameProviderAllowsDruidPowerBar() then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then return false end
    return ns.Opt("druidPowerBarEnabled", true) ~= false
end

local function DeactivateRuntime()
    if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    initialized = false
    if bar then UpdateVisibility() end
end

function DPB:Init()
    if initialized then return end
    if not RuntimeAllowed() then
        DeactivateRuntime()
        return
    end
    initialized = true

    local eventFrame = EnsureEventFrame()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")

    -- PLAYER_LOGIN is already in progress when Core activates us.
    UpdateVisibility()
end

function DPB:Refresh()
    if not RuntimeAllowed() then
        DeactivateRuntime()
        return
    end
    if not initialized then self:Init() end
    if not initialized or not EnsureBar() then return end
    ApplyStyle()
    AnchorBar()
    if not UseEmbeddedMode() and ns.Movers and ns.Movers.active then self:RegisterMover() end
    UpdateVisibility()
    if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("DruidPowerBar") end
end
