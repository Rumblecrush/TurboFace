local _, ns = ...

-- API boundary: all changed-in-retail APIs resolve through Compat.lua
local UnitBuff = ns.API.UnitBuff
local UnitDebuff = ns.API.UnitDebuff

local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear
local UnitAffectingCombat = UnitAffectingCombat

-- =============================================================================
-- TurboFace UnitFrames/UnitFrames.lua
-- Ported from EasyFrames by Usoltsev — Ace3 stripped, merged into TurboFace
-- Handles: player, target, pet, party frame layout + health coloring
-- Event-driven only — no OnUpdate polling
--
-- Multi-client ownership: this file contains the shared/readable Era renderer
-- and common UnitFrame helper vocabulary. Forever loads it for those shared
-- helpers, then UnitFrames/ForeverNativeAdapter.lua replaces the runtime Init/
-- Refresh entry points before Core initialization and owns all modern/protected
-- object discovery and detached rendering.
-- =============================================================================

local UF = {}
ns.UF = UF

-- Shared empty table for the `(TurboFaceDB.unitframes or EMPTY)` guards below so
-- the nil branch never allocates a throwaway table. Never mutated.
local EMPTY = {}

local COLOR_REFRESH_UNITS = {
    "player", "target", "pet", "party1", "party2", "party3", "party4",
}

-- Cached DB reference — set at Init(), refreshed at Refresh()
local d = nil
local function RefreshDBCache() d = TurboFaceDB.unitframes end

-- Per-element activation boundary. This helper intentionally lives near the top
-- of the file because several shared styling functions are declared before the
-- individual InitPlayer/InitTarget/etc. entry points.
local function UnitFrameGate(element)
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("unitframes", element)
end

-- =============================================================================
-- UTILS
-- =============================================================================

local function SetTextColor(fontString, color)
    if fontString and color then
        -- Accept both array {r,g,b} (defaults) and keyed {r=,g=,b=} (color picker).
        fontString:SetTextColor(ns:Color(color, 1, 1, 1))
    end
end

-- Unit-frame typography is split by semantic role.  All unit names share the
-- Name family; health/power/shield/numeric text shares the Bar family.  Compact
-- fixed-art frames may still pass their own size, but never their own face/style.
local function StyleUnitFrameName(fontString, size)
    if not fontString then return end
    local fontName = (d and d.nameFont) or "Blizzard Default"
    local style = (d and d.nameTextStyle) or "SHADOW"
    ns:StyleFont(fontString, ns:GetFontPath(fontName), size, nil, style)
end

local function StyleUnitFrameValue(fontString, size)
    if not fontString then return end
    local fontName = (d and d.barFont) or "Blizzard Narrow"
    local style = (d and d.barTextStyle) or "OUTLINE"
    ns:StyleFont(fontString, ns:GetFontPath(fontName), size, nil, style)
end

-- Health bar coloring — uses cached d
local function SetHealthColor(statusbar, unit)
    -- Player HP uses a single static, user-chosen color — no class/threat/HP-based
    -- shifting. (Target stays enemy/friendly static until threat features land.)
    if unit == "player" and d.playerHealthColor then
        local c = d.playerHealthColor
        statusbar:SetStatusBarColor(ns:Color(c, 0.1, 0.8, 0.1))
        return
    end

    if d.colorBasedOnCurrentHealth then
        local value = UnitHealth(unit)
        local _, max = statusbar:GetMinMaxValues()
        if max and max > 0 then
            local pct = value / max
            local r, g
            if pct > 0.5 then r = (1 - pct) * 2; g = 1
            else r = 1; g = pct * 2 end
            statusbar:SetStatusBarColor(r, g, 0)
        end
        return
    end

    if UnitIsPlayer(unit) and d.classColored then
        local _, class = UnitClass(unit)
        if class then
            local c = RAID_CLASS_COLORS[class]
            if c then statusbar:SetStatusBarColor(c.r, c.g, c.b) return end
        end
    end

    if UnitIsFriend("player", unit) then
        local c = d.friendlyColor
        statusbar:SetStatusBarColor(ns:Color(c))
    else
        local c = d.enemyColor
        statusbar:SetStatusBarColor(ns:Color(c))
    end
end

-- Generic value formatter shared by health and mana
local function FormatValue(current, max, fmt)
    fmt = fmt or "percent"
    if fmt == "none" then return "" end
    current = current or 0
    max = max or 0
    if fmt == "current" then
        return tostring(current)
    elseif fmt == "current-max" then
        return current .. " / " .. max
    elseif fmt == "current-max-pct" then
        if max == 0 then return current .. " / " .. max end
        return string.format("%d / %d (%d%%)", current, max, math.floor(current / max * 100 + 0.5))
    elseif fmt == "current-pct" then
        if max == 0 then return tostring(current) end
        return string.format("%d (%d%%)", current, math.floor(current / max * 100 + 0.5))
    else -- percent
        if max == 0 then return "0%" end
        return string.format("%d%%", math.floor(current / max * 100 + 0.5))
    end
end

-- Resolve the independently configured format for a specific unit/bar.
-- Player, Target, Pet, Party, and Target-of-Target each own separate settings.
local function GetValueFormat(unit, kind)
    local group = unit
    if unit == "targettarget" then group = "tot"
    elseif unit and unit:match("^party%d$") then group = "party" end

    local key
    if kind == "health" then
        key = group .. "HealthFormat"
        return d[key] or "current-max-pct"
    end
    key = group .. "PowerFormat"
    return d[key] or "percent"
end

-- =============================================================================
-- FRAME REPOSITIONING
-- =============================================================================

local function MoveRegion(frame, point, relativeTo, relativePoint, xOffset, yOffset)
    if not frame then return end
    frame._srAnchor = { point, relativeTo, relativePoint, xOffset, yOffset }
    frame._srSettingAnchor = true
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)
    frame._srSettingAnchor = false

    if not frame._srHookSetPoint then
        hooksecurefunc(frame, "SetPoint", function(self)
            if self._srSettingAnchor or not self._srAnchor then return end
            self._srSettingAnchor = true
            self:ClearAllPoints()
            self:SetPoint(unpack(self._srAnchor))
            self._srSettingAnchor = false
        end)
        frame._srHookSetPoint = true
    end
end





-- =============================================================================
-- BAR TEXTURES & FRAME ART
-- =============================================================================

local function HideBarBackground(bar)
    if not bar then return end
    local fillTex = bar:GetStatusBarTexture()
    for _, region in ipairs({bar:GetRegions()}) do
        -- _tfRingBG is TurboFace's own per-bar background (ring mode) -- the
        -- sweep must not eat it along with Blizzard's background art.
        if region ~= fillTex and region ~= bar._tfRingBG
        and region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetAlpha(0)
            region:Hide()
        end
    end
    if bar.Background then
        bar.Background:SetAlpha(0)
        bar.Background:Hide()
    end
end

local PLAYER_ART_BASE = "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\"
local PLAYER_ART_NORMAL = PLAYER_ART_BASE .. "UI-Player-Portrait.tga"
local PLAYER_ART_DRUID = PLAYER_ART_BASE .. "UI-Player-Portrait-Druid.tga"
local TARGET_ART = PLAYER_ART_BASE .. "UI-Target-Portrait.tga"
local TARGET_ART_ELITE = PLAYER_ART_BASE .. "UI-EliteTarget-Portrait.tga"
local TARGET_ART_RARE = PLAYER_ART_BASE .. "UI-RareTarget-Portrait.tga"
local TARGET_ART_RARE_ELITE = PLAYER_ART_BASE .. "UI-RareEliteTarget-Portrait.tga"
local TARGET_ART_BY_CLASSIFICATION = {
    elite = TARGET_ART_ELITE,
    worldboss = TARGET_ART_ELITE,
    rare = TARGET_ART_RARE,
    rareelite = TARGET_ART_RARE_ELITE,
}
local PARTY_ART = PLAYER_ART_BASE .. "UI-Party-Portrait.tga"
local TOT_ART = PLAYER_ART_BASE .. "UI-ToT-Portrait.tga"
local PET_ART = PLAYER_ART_BASE .. "UI-Pet-Portrait.tga"
local PLAYER_ART_X_OFFSET = -9
local PLAYER_ART_Y_OFFSET = -3
-- Druid v3 occupies the same region of its 256x128 sheet as the normal player
-- art (both bbox x40..231, y25), so the old +10 x / +0.5 y compensations for
-- the previous druid artwork no longer apply -- it anchors identically now.
local PLAYER_ART_DRUID_X_OFFSET = PLAYER_ART_X_OFFSET
local PLAYER_ART_DRUID_Y_OFFSET = PLAYER_ART_Y_OFFSET
-- The mirrored sheet's art sits at x24..215 instead of the old x40..231, i.e.
-- 16px further left inside the texture, and the frame anchors by CENTER. The
-- player art's centre is +7.5 from the texture centre and its -9 offset lands
-- it at -1.5 from the frame centre; the mirror wants +1.5, and its art centre
-- is -8.5, so the offset is 1.5 - (-8.5) = +10. Adjust here if it needs nudging.
local TARGET_ART_X_OFFSET = 10
local TARGET_ART_Y_OFFSET = -3
local _, PLAYER_CLASS = UnitClass("player")
local PLAYER_IS_DRUID = PLAYER_CLASS == "DRUID"

-- The druid sheet is used ONLY while shifted into cat or bear; caster, travel,
-- moonkin and tree all keep the normal player art. Detection is by power type
-- rather than form index because form indices differ per spec/expansion, and
-- this is the same signal DruidPowerBar:ShouldShow uses -- so the fourth bar
-- opening and the bar that fills it always appear and disappear together.
local DRUID_ART_POWER = {
    [Enum and Enum.PowerType and Enum.PowerType.Rage or 1] = true,
    [Enum and Enum.PowerType and Enum.PowerType.Energy or 3] = true,
}

-- Cached so the shapeshift handler only does work when the art actually flips.
local _lastDruidArt = nil

local function UseDruidArt()
    if not PLAYER_IS_DRUID then return false end
    return DRUID_ART_POWER[UnitPowerType("player")] == true
end

-- Classic Era 1.15.9 creates party members from PartyFrame's frame pool and
-- exposes them as PartyFrame.MemberFrame1..4 rather than the former global
-- PartyMemberFrame1..4 objects. Keep legacy fallbacks for older clients.
local function GetPartyMemberFrame(index)
    local legacy = _G["PartyMemberFrame" .. index]
    if legacy then return legacy end

    local party = _G.PartyFrame
    if not party then return nil end

    local member = party["MemberFrame" .. index]
    if member then return member end

    local pool = party.PartyMemberFramePool
    if pool and type(pool.EnumerateActive) == "function" then
        for frame in pool:EnumerateActive() do
            if frame and frame.layoutIndex == index then return frame end
        end
    end
    return nil
end

local function GetPartyMemberIndex(frame)
    if not frame then return nil end
    local index = tonumber(frame.layoutIndex)
    if index and index >= 1 and index <= 4 then return index end
    if frame.GetID then
        index = tonumber(frame:GetID())
        if index and index >= 1 and index <= 4 then return index end
    end
    local name = frame.GetName and frame:GetName()
    return name and tonumber(name:match("PartyMemberFrame([1-4])")) or nil
end

-- Pooled PartyMemberFrames are keyed by their visual layout slot, but Blizzard
-- assigns the roster unit separately. During the first GROUP_ROSTER_UPDATE the
-- frame can exist before UnitName("partyN") is cached, and pool order is not a
-- stronger source of truth than the frame's assigned unit.
local function GetPartyMemberUnit(index, frame)
    local unit = frame and frame.unit
    if type(unit) == "string" and unit:match("^party[1-4]$") then
        return unit
    end
    return index and ("party" .. index) or nil
end

local function RefreshPartyOwnedName(index, frame, unit)
    local nameText = frame and frame._tfPartyNameText
    if not nameText then return false end
    unit = unit or GetPartyMemberUnit(index, frame)
    nameText:SetText((unit and UnitName(unit)) or "")
    return true
end

-- Published for UnitFrames/Predictions.lua and retained as compatibility helpers for
-- other Blizzard-party-frame consumers. PartyPetAuras.lua owns its own lookup chain.
UF.GetPartyMemberFrame = GetPartyMemberFrame
UF.GetPartyMemberIndex = GetPartyMemberIndex

-- Forward declaration: the fixed Party geometry table is populated with the
-- other unit-frame layouts below, but this exported helper is declared earlier
-- for inter-file consumers. Keeping the local in lexical scope prevents Lua
-- from silently resolving PARTY_LAYOUT as a global.
local PARTY_LAYOUT

-- Inter-file geometry helpers for narrow augmentations that live inside the
-- TurboFace-owned Party name opening. UnitFrames remains the sole owner of the
-- fixed-art coordinates; consumers never duplicate PARTY_LAYOUT constants.
function UF.LayoutPartyNameOverlay(frame, overlay)
    if not frame or not overlay then return false end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PARTY_LAYOUT.artX + PARTY_LAYOUT.nameX,
        -(PARTY_LAYOUT.artY + PARTY_LAYOUT.nameY))
    overlay:SetSize(PARTY_LAYOUT.nameW, PARTY_LAYOUT.nameH)
    return true
end

function UF.GetPartyOwnedName(frame)
    return frame and frame._tfPartyNameText or nil
end

local function GetPartyHealthBar(index, frame)
    frame = frame or GetPartyMemberFrame(index)
    return (frame and (frame.HealthBar or frame.healthBar))
        or _G["PartyMemberFrame" .. index .. "HealthBar"]
end

-- Published for UnitFrames/Predictions.lua, which draws the heal overlay onto the
-- party health bars. Kept as a UF field rather than duplicated there so the
-- HealthBar/healthBar/_G fallback chain has exactly one definition.
UF.GetPartyHealthBar = GetPartyHealthBar

local function GetPartyManaBar(index, frame)
    frame = frame or GetPartyMemberFrame(index)
    return (frame and (frame.ManaBar or frame.manaBar))
        or _G["PartyMemberFrame" .. index .. "ManaBar"]
end

local function GetPartyPortrait(index, frame)
    frame = frame or GetPartyMemberFrame(index)
    return (frame and (frame.Portrait or frame.portrait))
        or _G["PartyMemberFrame" .. index .. "Portrait"]
end

local function GetPartyNameText(index, frame)
    frame = frame or GetPartyMemberFrame(index)
    return (frame and frame.PartyMemberOverlay and frame.PartyMemberOverlay.Name)
        or (frame and (frame.Name or frame.name))
        or _G["PartyMemberFrame" .. index .. "Name"]
end

local function GetPartyBackground(index, frame)
    frame = frame or GetPartyMemberFrame(index)
    return (frame and frame.Background)
        or _G["PartyMemberFrame" .. index .. "Background"]
end

local function ApplyPlayerFrameArtTexture()
    if not UnitFrameGate("player") then return end
    local tex = PlayerFrameTexture
    if not tex or tex._tfApplyingPlayerArt then return end
    tex._tfApplyingPlayerArt = true
    tex:SetTexture(UseDruidArt() and PLAYER_ART_DRUID or PLAYER_ART_NORMAL)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetSize(256, 128)
    local druidArt = UseDruidArt()
    local xOffset = druidArt and PLAYER_ART_DRUID_X_OFFSET or PLAYER_ART_X_OFFSET
    local yOffset = druidArt and PLAYER_ART_DRUID_Y_OFFSET or PLAYER_ART_Y_OFFSET
    MoveRegion(tex, "CENTER", tex:GetParent() or PlayerFrame, "CENTER", xOffset, yOffset)
    if tex.SetDrawLayer then tex:SetDrawLayer("ARTWORK", -4) end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:Show()
    tex._tfApplyingPlayerArt = false

    if not tex._tfPlayerArtHooked then
        hooksecurefunc(tex, "SetTexture", function(self)
            if not self._tfApplyingPlayerArt then
                ApplyPlayerFrameArtTexture()
            end
        end)
        tex._tfPlayerArtHooked = true
    end
end

local function ResolveTargetFrameArtTexture()
    local classification = UnitExists("target") and UnitClassification("target")
    return TARGET_ART_BY_CLASSIFICATION[classification] or TARGET_ART
end

local function ApplyTargetFrameArtTexture()
    if not UnitFrameGate("target") then return end
    local tex = TargetFrameTextureFrameTexture
        or (TargetFrame and TargetFrame.borderTexture)
    if not tex or tex._tfApplyingTargetArt then return end

    tex._tfApplyingTargetArt = true
    local art = ResolveTargetFrameArtTexture()
    tex:SetTexture(art)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetSize(256, 128)
    MoveRegion(tex, "CENTER", tex:GetParent() or TargetFrame, "CENTER", TARGET_ART_X_OFFSET, TARGET_ART_Y_OFFSET)
    if tex.SetDrawLayer then tex:SetDrawLayer("ARTWORK", -4) end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:Show()
    tex._tfApplyingTargetArt = false

    -- Blizzard swaps this texture whenever target classification changes.
    -- Reassert the matching TurboFace normal/elite/rare/rare-elite sheet while
    -- allowing its remaining target-state logic to keep running.
    if not tex._tfTargetArtHooked then
        hooksecurefunc(tex, "SetTexture", function(self)
            if not self._tfApplyingTargetArt then
                ApplyTargetFrameArtTexture()
            end
        end)
        tex._tfTargetArtHooked = true
    end
end

local function SetFrameArtTextures()
    -- Player and Target now use fixed 256x128 artwork while Blizzard continues
    -- to own their portrait and unit-state behavior.
    if UnitFrameGate("player") then ApplyPlayerFrameArtTexture() end
    if UnitFrameGate("target") then ApplyTargetFrameArtTexture() end

    -- Party/Pet use 119x48 fixed art; ToT uses its narrower 98x48 variant.
    -- layers in their respective layout paths. Do not repurpose Blizzard's
    -- native PetFrameTexture here; InitPet suppresses that chrome while
    -- preserving Blizzard's portrait/unit lifecycle.
end

local function SetAllBarTextures()
    local hpTex = ns.ResolveStatusBarTexture(d.healthTexture or "Blizzard")
    local mnTex = ns.ResolveStatusBarTexture(d.manaTexture   or "Blizzard")
    local healthBars, manaBars = {}, {}
    if UnitFrameGate("player") then
        if PlayerFrameHealthBar then tinsert(healthBars, PlayerFrameHealthBar) end
        if PlayerFrameManaBar then tinsert(manaBars, PlayerFrameManaBar) end
    end
    if UnitFrameGate("target") then
        if TargetFrameHealthBar then tinsert(healthBars, TargetFrameHealthBar) end
        if TargetFrameManaBar then tinsert(manaBars, TargetFrameManaBar) end
    end
    if UnitFrameGate("pet") then
        if PetFrameHealthBar then tinsert(healthBars, PetFrameHealthBar) end
        if PetFrameManaBar then tinsert(manaBars, PetFrameManaBar) end
    end
    if UnitFrameGate("tot") then
        if TargetFrameToTHealthBar then tinsert(healthBars, TargetFrameToTHealthBar) end
        if TargetFrameToTManaBar then tinsert(manaBars, TargetFrameToTManaBar) end
    end
    if UnitFrameGate("party") then
        for i = 1, 4 do
            local frame = GetPartyMemberFrame(i)
            local hb = GetPartyHealthBar(i, frame)
            local mb = GetPartyManaBar(i, frame)
            if hb then tinsert(healthBars, hb) end
            if mb then tinsert(manaBars, mb) end
        end
    end
    for _, bar in ipairs(healthBars) do
        if bar and bar.SetStatusBarTexture then
            bar:SetStatusBarTexture(hpTex)
            HideBarBackground(bar)
        end
    end
    for _, bar in ipairs(manaBars) do
        if bar and bar.SetStatusBarTexture then
            bar:SetStatusBarTexture(mnTex)
            HideBarBackground(bar)
        end
    end
    SetFrameArtTextures()
end

-- =============================================================================
-- TEXT SYSTEM
-- Classic Era 1.15.9 structure:
--   Blizzard owns the native TextStatusBar strings and rewrites them from the
--   global statusText CVar. Player, Target, Party, ToT, and fixed-art Pet use
--   TurboFace-owned center overlays.
--
-- Strategy: suppress Left/Right ONCE at init, cache center text reference per bar,
-- and update the owned center overlays from direct bar hooks plus unit events.
-- =============================================================================

-- Cache center FontString per bar — populated on first lookup, never recalculated
local barCenterTextCache = {}

local function UsesOwnedCenterText(bar)
    return bar == PlayerFrameHealthBar
        or bar == PlayerFrameManaBar
        or bar == TargetFrameHealthBar
        or bar == TargetFrameManaBar
        or (bar and bar._tfUseOwnedCenterText == true)
end

local function SuppressNativeCenterText(bar)
    if not bar or bar._tfNativeCenterSuppressed then return end
    local name = bar.GetName and bar:GetName()
    local native = name and _G[name .. "Text"] or bar.TextString
    if not native then return end

    native._tfSuppressing = true
    native:SetAlpha(0)
    native._tfSuppressing = false

    -- Blizzard status-text refreshes can show or re-alpha the native string after
    -- our formatter runs. Keep that layer invisible; TurboFace's owned FontString
    -- is the sole rendered center text for Player and Target bars.
    if native.SetAlpha then
        hooksecurefunc(native, "SetAlpha", function(self, alpha)
            if self._tfSuppressing or alpha == 0 then return end
            self._tfSuppressing = true
            self:SetAlpha(0)
            self._tfSuppressing = false
        end)
    end
    if native.Show then
        hooksecurefunc(native, "Show", function(self)
            if self._tfSuppressing then return end
            self._tfSuppressing = true
            self:SetAlpha(0)
            self._tfSuppressing = false
        end)
    end
    bar._tfNativeCenterSuppressed = true
end

local function GetDruidPlayerTextLayer(bar)
    if not PLAYER_IS_DRUID then return nil end
    if bar ~= PlayerFrameHealthBar and bar ~= PlayerFrameManaBar then return nil end

    local layer = bar._tfForegroundTextLayer
    if not layer then
        layer = CreateFrame("Frame", nil, bar)
        layer:SetAllPoints(bar)
        layer:EnableMouse(false)
        bar._tfForegroundTextLayer = layer
    end

    -- Keep only the text above the custom Druid artwork. Raising the StatusBar
    -- itself would also raise its fill, which must remain beneath the frame art.
    layer:SetFrameStrata("HIGH")
    layer:SetFrameLevel((bar:GetFrameLevel() or 0) + 20)
    return layer
end

local function GetCenterText(bar)
    if not bar then return nil end
    if barCenterTextCache[bar] then
        GetDruidPlayerTextLayer(bar) -- resync its level after Blizzard updates
        return barCenterTextCache[bar]
    end

    local txt
    local name = bar.GetName and bar:GetName()

    -- Blizzard owns and repeatedly rewrites Player/Target center strings from
    -- statusText CVar state. Use addon-owned overlays for those four bars so the
    -- independent TurboFace formats cannot be replaced by Blizzard defaults.
    if UsesOwnedCenterText(bar) then
        SuppressNativeCenterText(bar)
        txt = bar._tfCenterText
        if not txt and bar.CreateFontString then
            local owner = GetDruidPlayerTextLayer(bar) or bar._tfTextOwner or bar
            txt = owner:CreateFontString(nil, "OVERLAY")
            bar._tfCenterText = txt
        end
    else
        if name then
            txt = _G[name .. "Text"]
        end
        if not txt and bar.TextString then txt = bar.TextString end
    end

    -- Classic target bars have changed internal text objects across minor client
    -- builds.  Some builds expose only LeftText/RightText, and our styling hides
    -- those so the target HP/power numbers can disappear.  Keep a TurboFace-owned
    -- center FontString as a fallback for any bar without a native center string.
    if not txt and bar.CreateFontString then
        txt = bar._tfCenterText
        if not txt then
            txt = bar:CreateFontString(nil, "OVERLAY")
            bar._tfCenterText = txt
        end
    end

    if txt then
        if txt.SetDrawLayer then txt:SetDrawLayer("OVERLAY", 7) end
        barCenterTextCache[bar] = txt
    end
    return txt
end

local function ResolveBarUnit(bar)
    if not bar then return nil end

    -- Blizzard's compact ToT bars can retain a parent/owner unit token that is
    -- not the displayed unit. Resolve these bars by identity before trusting
    -- bar.unit, otherwise UnitHealth/UnitPower can query the wrong unit.
    if bar == TargetFrameToTHealthBar or bar == TargetFrameToTManaBar then return "targettarget" end
    if bar == PlayerFrameHealthBar or bar == PlayerFrameManaBar then return "player" end
    if bar == TargetFrameHealthBar or bar == TargetFrameManaBar then return "target" end
    if bar == PetFrameHealthBar or bar == PetFrameManaBar then return "pet" end
    if bar.unit then return bar.unit end

    for i = 1, 4 do
        if bar == GetPartyHealthBar(i) or bar == GetPartyManaBar(i) then
            return "party" .. i
        end
    end

    return nil
end

local function ManagedBarElement(bar)
    if bar == PlayerFrameHealthBar or bar == PlayerFrameManaBar then return "player" end
    if bar == TargetFrameHealthBar or bar == TargetFrameManaBar then return "target" end
    if bar == TargetFrameToTHealthBar or bar == TargetFrameToTManaBar then return "tot" end
    if bar == PetFrameHealthBar or bar == PetFrameManaBar then return "pet" end
    for i = 1, 4 do
        if bar == GetPartyHealthBar(i) or bar == GetPartyManaBar(i) then return "party" end
    end
    return nil
end

-- Suppress side texts ONCE — called at init, not on every update
local function SuppressBarSideTextsOnce(bar)
    local name = bar:GetName()
    local L = (name and _G[name .. "TextLeft"]) or bar.LeftText
    local R = (name and _G[name .. "TextRight"]) or bar.RightText
    if L or R then
        if L then L:SetAlpha(0) end
        if R then R:SetAlpha(0) end
    end
    if bar.RightText then bar.RightText:SetAlpha(0) end
    if bar.LeftText  then bar.LeftText:SetAlpha(0)  end
end

-- Blizzard-style dual value layout. This is intentionally TurboFace-owned rather
-- than reusing Blizzard's LeftText/RightText objects, because Blizzard rewrites
-- those from the global statusText CVar. Percent sits inside-left and current
-- sits inside-right, matching the selectable "Percent Current (Blizzard)" mode.
local BLIZZARD_DUAL_FORMAT = "percent-current-blizzard"

local function GetBlizzardDualTexts(bar)
    if not bar then return nil, nil end
    if bar._tfBlizzardCurrentText and bar._tfBlizzardPercentText then
        GetDruidPlayerTextLayer(bar) -- resync player/druid text layer when needed
        return bar._tfBlizzardCurrentText, bar._tfBlizzardPercentText
    end

    local owner = GetDruidPlayerTextLayer(bar) or bar._tfTextOwner or bar
    if not owner or not owner.CreateFontString then return nil, nil end

    local currentText = owner:CreateFontString(nil, "OVERLAY")
    local percentText = owner:CreateFontString(nil, "OVERLAY")
    if currentText.SetDrawLayer then currentText:SetDrawLayer("OVERLAY", 7) end
    if percentText.SetDrawLayer then percentText:SetDrawLayer("OVERLAY", 7) end
    currentText:SetAlpha(0)
    percentText:SetAlpha(0)
    bar._tfBlizzardCurrentText = currentText
    bar._tfBlizzardPercentText = percentText
    return currentText, percentText
end

local function SetBlizzardDualVisible(bar, visible)
    if not bar then return end
    local alpha = visible and 1 or 0
    if bar._tfBlizzardCurrentText then bar._tfBlizzardCurrentText:SetAlpha(alpha) end
    if bar._tfBlizzardPercentText then bar._tfBlizzardPercentText:SetAlpha(alpha) end
end

local function StyleBlizzardDualText(bar)
    local currentText, percentText = GetBlizzardDualTexts(bar)
    if not currentText or not percentText then return nil, nil end

    local fontName = ns:NormalizeFontName(d.barFont or "Blizzard Narrow")
    local fontStyle = d.barTextStyle or "OUTLINE"
    local fontSize = bar._tfTextSize or d.barFontSize or 10
    for _, fs in ipairs({ currentText, percentText }) do
        if fs._tfFontName ~= fontName or fs._tfFontSize ~= fontSize or fs._tfFontStyle ~= fontStyle then
            fs._tfFontName, fs._tfFontSize, fs._tfFontStyle = fontName, fontSize, fontStyle
            StyleUnitFrameValue(fs, fontSize)
        end
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    end
    if percentText.SetJustifyH then percentText:SetJustifyH("LEFT") end
    if currentText.SetJustifyH then currentText:SetJustifyH("RIGHT") end

    local yOffset = bar._tfTextYOffset or 0
    if PLAYER_IS_DRUID and (bar == PlayerFrameHealthBar or bar == PlayerFrameManaBar) then
        yOffset = -0.5
        GetDruidPlayerTextLayer(bar)
    end

    -- Keep both strings just inside the bar edges. Widths are split at center so
    -- compact Pet/Party/ToT bars clip gracefully instead of drawing through each
    -- other when values are unusually long. Geometry is only rewritten when its
    -- offset changes; ToT is protected, so never perform new anchor writes to its
    -- child text while combat lockdown is active.
    if bar._tfBlizzardDualYOffset ~= yOffset then
        local protectedToT = bar == TargetFrameToTHealthBar or bar == TargetFrameToTManaBar
        if not (protectedToT and InCombatLockdown()) then
            percentText:ClearAllPoints()
            percentText:SetPoint("LEFT", bar, "LEFT", 2, yOffset)
            percentText:SetPoint("RIGHT", bar, "CENTER", -1, yOffset)
            currentText:ClearAllPoints()
            currentText:SetPoint("LEFT", bar, "CENTER", 1, yOffset)
            currentText:SetPoint("RIGHT", bar, "RIGHT", -2, yOffset)
            bar._tfBlizzardDualYOffset = yOffset
        end
    end
    return currentText, percentText
end

local function UpdateBlizzardDualText(bar, current, max)
    local currentText, percentText = StyleBlizzardDualText(bar)
    if not currentText or not percentText then return false end
    current = current or 0
    max = max or 0
    currentText:SetText(tostring(current))
    local pct = (max > 0) and math.floor(current / max * 100 + 0.5) or 0
    percentText:SetText(pct .. "%")
    currentText:SetAlpha(1)
    percentText:SetAlpha(1)
    return true
end

-- Called from TextStatusBar hooks and unit events. Normal formats use one
-- centered string; Percent Current (Blizzard) uses the owned dual strings above.
local function UpdateBarText(bar)
    if not bar then return end
    local element = ManagedBarElement(bar)
    if not element or not UnitFrameGate(element) then return end
    local unit = ResolveBarUnit(bar)
    if not unit then return end
    local isProtectedToTBar = bar == TargetFrameToTHealthBar or bar == TargetFrameToTManaBar

    -- Re-suppress side texts unless this bar has been configured to show them
    if not bar._srShowSideTexts then
        if bar.RightText then bar.RightText:SetAlpha(0) end
        if bar.LeftText  then bar.LeftText:SetAlpha(0)  end
    end

    local txt = GetCenterText(bar)
    if not txt then return end

    -- Re-assert the configured font, but ONLY when the resolved font/style/size
    -- actually changed. This hook fires per-frame for a visible target's bars, and
    -- calling SetFont (+ the string work feeding it) every time was a large,
    -- needless source of CPU and GC churn -- the bug we were chasing. We key on the
    -- *resolved* Bar font + text style so local UnitFrame typography changes re-apply.
    local fontName  = ns:NormalizeFontName(d.barFont or "Blizzard Narrow")
    local fontStyle = d.barTextStyle or "OUTLINE"
    local fontSize = bar._tfTextSize or d.barFontSize or 10
    if txt._tfFontName ~= fontName or txt._tfFontSize ~= fontSize or txt._tfFontStyle ~= fontStyle then
        txt._tfFontName, txt._tfFontSize, txt._tfFontStyle = fontName, fontSize, fontStyle
        StyleUnitFrameValue(txt, fontSize)
    end

    -- Cache the bar kind once (avoid a string match on every update).
    local kind = bar._tfKind
    if kind == nil then
        local barName = bar:GetName() or ""
        kind = (barName:find("HealthBar") and "health")
            or (barName:find("ManaBar") and "mana")
            or false
        bar._tfKind = kind
    end

    if kind == "health" then
        -- Skip center text if this bar uses side texts instead
        if bar._srHideCenterText then
            txt:SetAlpha(0)
            return
        end
        local current = UnitHealth(unit)
        local max     = UnitHealthMax(unit)
        local fmt     = GetValueFormat(unit, "health")

        -- Blizzard renders its native Dead/Unconscious label in the target
        -- health opening. Keep TurboFace's owned numeric overlay out of that
        -- slot while the target has no health so "0" cannot overlap the state
        -- text. Clearing the cached values forces a fresh format on revival.
        if unit == "target" and ((UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)) or (current or 0) <= 0) then
            if not bar._tfDeadHidden then
                bar._tfDeadHidden = true
                bar._tfCur, bar._tfMax, bar._tfFmt = nil, nil, nil
                txt:SetText("")
            end
            SetBlizzardDualVisible(bar, false)
            txt:SetAlpha(0)
            txt:Hide()
            return
        end
        bar._tfDeadHidden = nil

        if current and max then
            if fmt == BLIZZARD_DUAL_FORMAT then
                txt:SetText("")
                txt:SetAlpha(0)
                if bar._tfCur ~= current or bar._tfMax ~= max or bar._tfFmt ~= fmt then
                    bar._tfCur, bar._tfMax, bar._tfFmt = current, max, fmt
                    UpdateBlizzardDualText(bar, current, max)
                else
                    -- Re-apply styling/anchors after typography or geometry refreshes
                    -- even when the underlying health value did not change.
                    StyleBlizzardDualText(bar)
                    SetBlizzardDualVisible(bar, true)
                end
                return
            end

            SetBlizzardDualVisible(bar, false)
            -- Only rebuild the string (FormatHealth -> string.format allocates)
            -- when the underlying value changed.
            if bar._tfCur ~= current or bar._tfMax ~= max or bar._tfFmt ~= fmt then
                bar._tfCur, bar._tfMax, bar._tfFmt = current, max, fmt
                txt:SetText(FormatValue(current, max, fmt))
            end
            txt:SetAlpha(1)
            if not isProtectedToTBar then txt:Show() end
        end
    elseif kind == "mana" then
        local fmt = GetValueFormat(unit, "power")
        if fmt == "none" then
            SetBlizzardDualVisible(bar, false)
            txt:SetAlpha(1)
            if bar._tfBlank ~= true then bar._tfBlank = true; txt:SetText("") end
        else
            local current = UnitPower(unit)
            local max     = UnitPowerMax(unit)
            if current and max then
                if max > 0 then
                    if fmt == BLIZZARD_DUAL_FORMAT then
                        txt:SetText("")
                        txt:SetAlpha(0)
                        if bar._tfCur ~= current or bar._tfMax ~= max or bar._tfFmt ~= fmt then
                            bar._tfCur, bar._tfMax, bar._tfFmt, bar._tfBlank = current, max, fmt, false
                            UpdateBlizzardDualText(bar, current, max)
                        else
                            StyleBlizzardDualText(bar)
                            SetBlizzardDualVisible(bar, true)
                        end
                        return
                    end

                    SetBlizzardDualVisible(bar, false)
                    if bar._tfCur ~= current or bar._tfMax ~= max or bar._tfFmt ~= fmt then
                        bar._tfCur, bar._tfMax, bar._tfFmt, bar._tfBlank = current, max, fmt, false
                        txt:SetText(FormatValue(current, max, fmt))
                    end
                    txt:SetAlpha(1)
                    if not isProtectedToTBar then txt:Show() end
                elseif bar._tfBlank ~= true then
                    bar._tfBlank = true
                    SetBlizzardDualVisible(bar, false)
                    txt:SetAlpha(1)
                    txt:SetText("")
                end
            end
        end
    end
end

local function InvalidateBarText(bar)
    if not bar then return end
    bar._tfCur = nil
    bar._tfMax = nil
    bar._tfFmt = nil
    bar._tfBlank = nil
end

local function RefreshTargetValueText()
    if not UnitFrameGate("target") then return end
    InvalidateBarText(TargetFrameHealthBar)
    InvalidateBarText(TargetFrameManaBar)
    UpdateBarText(TargetFrameHealthBar)
    UpdateBarText(TargetFrameManaBar)
end

-- =============================================================================
-- TEXT STYLING / POSITIONING
-- =============================================================================

-- Center a bar's text in the bar and apply the configured font. MoveRegion hooks
-- SetPoint so it stays centered even if Blizzard re-anchors the FontString.
local function StyleBarText(bar)
    if not bar then return end
    local txt = GetCenterText(bar)
    if not txt then return end
    StyleUnitFrameValue(txt, bar._tfTextSize or d.barFontSize or 10)
    if txt.SetJustifyH then txt:SetJustifyH("CENTER") end
    if txt.SetJustifyV then txt:SetJustifyV("MIDDLE") end
    local yOffset = bar._tfTextYOffset or 0
    if PLAYER_IS_DRUID and (bar == PlayerFrameHealthBar or bar == PlayerFrameManaBar) then
        yOffset = -0.5
        GetDruidPlayerTextLayer(bar)
    end
    MoveRegion(txt, "CENTER", bar, "CENTER", 0, yOffset)
    txt:SetAlpha(1)
    txt:Show()
end

-- Target level text and high-level/skull presentation remain Blizzard-owned.
-- TurboFace adds only a small decorative badge behind the native player/target
-- level presentation; Blizzard still owns the text/skull texture, color, value,
-- and visibility.
local LEVEL_BADGE_RING_TEXTURE = "Interface\\CharacterFrame\\TotemBorder"
local LEVEL_BADGE_BG_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- Shared visual target with the DPS/HPS badge.  Background opacity is
-- expressed ONLY through Texture:SetAlpha so refresh code cannot accidentally
-- multiply/override a second vertex-alpha path.  The old level-badge sync
-- hard-pinned object alpha to 1, which made attempts to tune transparency via
-- SetAlpha appear to do nothing.
local BADGE_BG_ALPHA   = 0.50
local BADGE_RING_ALPHA = 0.95

-- Draw sublevels for the level badge, all on ARTWORK.
--
-- The badge sits UNDER Blizzard's frame art, which measures at ARTWORK
-- sublevel 0 on 1.15.9 (PlayerFrameTexture and PlayerStatusTexture both).
-- Lifting it above the art was tried and reverted: it fixed nothing visible,
-- and with an opaque backing it would paint over the metalwork framing the
-- number. The number itself stays above the badge at sublevel 1.
--
-- Note the sublevels here are measured, not assumed -- an older comment in
-- this file claimed the status glow sat at ARTWORK 2 and washed over the
-- level number. It does not; it is at 0, below the number.
local BADGE_BG_SUBLEVEL   = -2
local BADGE_RING_SUBLEVEL = -1
local BADGE_TEXT_SUBLEVEL = 1

local function ResolvePlayerLevelText()
    return PlayerLevelText
        or (PlayerFrame and (PlayerFrame.levelText or PlayerFrame.LevelText))
        or (PlayerFrame and PlayerFrame.PlayerFrameContent
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelText)
end

local function ResolveTargetLevelText()
    return TargetFrameTextureFrameLevelText
        or (TargetFrame and (TargetFrame.levelText or TargetFrame.LevelText))
        or (TargetFrame and TargetFrame.TargetFrameContent
            and TargetFrame.TargetFrameContent.TargetFrameContentMain
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText)
end

local function SyncLevelBadge(levelText)
    local badge = levelText and levelText._tfLevelBadge
    if not badge then return end

    local text = levelText.GetText and levelText:GetText()
    local alpha = levelText.GetAlpha and levelText:GetAlpha() or 1
    local textVisible = levelText.IsShown and levelText:IsShown()
        and alpha > 0 and text ~= nil and text ~= ""
    local anchor = levelText
    local skullVisible = false

    -- Blizzard replaces the target level FontString with a separate high-level
    -- skull texture for UnitLevel == -1. The decorative TotemBorder belongs
    -- behind either native level presentation, so use the skull as the anchor
    -- without taking ownership of its texture or visibility.
    if levelText == ResolveTargetLevelText()
        and UnitExists("target") and UnitLevel("target") == -1 then
        local content = TargetFrame and TargetFrame.TargetFrameContent
            and TargetFrame.TargetFrameContent.TargetFrameContentMain
        local skull = TargetFrameTextureFrameHighLevelTexture
            or (TargetFrame and (TargetFrame.highLevelTexture or TargetFrame.HighLevelTexture))
            or (content and (content.HighLevelTexture or content.highLevelTexture))
        anchor = skull or levelText
        skullVisible = true
    end

    badge.background:ClearAllPoints()
    badge.background:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    badge.ring:ClearAllPoints()
    badge.ring:SetPoint("CENTER", anchor, "CENTER", 0, 0)

    local visible = textVisible or skullVisible

    if visible then
        -- Keep badge opacity deterministic and independent of Blizzard's
        -- FontString fade state.  Do NOT hard-pin the background to 1 here:
        -- this is the authoritative opacity path for the level badge.
        badge.background:SetAlpha(BADGE_BG_ALPHA)
        badge.ring:SetAlpha(BADGE_RING_ALPHA)
        badge.background:Show()
        badge.ring:Show()
    else
        badge.background:Hide()
        badge.ring:Hide()
    end
end

local function ResolveLevelBadgeOwner(levelText)
    if levelText == ResolvePlayerLevelText() then
        return (PlayerStatusTexture and PlayerStatusTexture:GetParent())
            or (PlayerFrameTexture and PlayerFrameTexture:GetParent())
            or PlayerFrame
    end

    if levelText == ResolveTargetLevelText() then
        local art = TargetFrameTextureFrameTexture
            or (TargetFrame and TargetFrame.borderTexture)
        return (art and art:GetParent()) or TargetFrame
    end

    return levelText and levelText.GetParent and levelText:GetParent()
end

local function EnsureLevelBadge(levelText)
    if not levelText then return end

    local owner = ResolveLevelBadgeOwner(levelText)
    if not owner or not owner.CreateTexture then return end

    local badge = levelText._tfLevelBadge
    if not badge then
        -- Decorative badge behind Blizzard's frame art; the number draws above
        -- both (see the sublevel constants).
        local background = owner:CreateTexture(nil, "ARTWORK", nil, BADGE_BG_SUBLEVEL)
        background:SetTexture(LEVEL_BADGE_BG_TEXTURE)
        background:SetSize(24, 24)
        background:SetPoint("CENTER", levelText, "CENTER", 0, 0)
        background:SetVertexColor(0, 0, 0, 1)
        background:SetAlpha(BADGE_BG_ALPHA)

        local ring = owner:CreateTexture(nil, "ARTWORK", nil, BADGE_RING_SUBLEVEL)
        ring:SetTexture(LEVEL_BADGE_RING_TEXTURE)
        ring:SetSize(32, 32)
        ring:SetPoint("CENTER", levelText, "CENTER", 0, 0)
        ring:SetVertexColor(0.95, 0.92, 0.75, 1)
        ring:SetAlpha(BADGE_RING_ALPHA)

        badge = { background = background, ring = ring, owner = owner }
        levelText._tfLevelBadge = badge

        if not levelText._tfLevelBadgeHooked then
            local function Refresh() SyncLevelBadge(levelText) end
            hooksecurefunc(levelText, "Show", Refresh)
            hooksecurefunc(levelText, "Hide", Refresh)
            hooksecurefunc(levelText, "SetAlpha", Refresh)
            hooksecurefunc(levelText, "SetText", Refresh)
            levelText._tfLevelBadgeHooked = true
        end
    else
        if badge.background.SetDrawLayer then
            badge.background:SetDrawLayer("ARTWORK", BADGE_BG_SUBLEVEL)
        end
        if badge.ring.SetDrawLayer then
            badge.ring:SetDrawLayer("ARTWORK", BADGE_RING_SUBLEVEL)
        end
        badge.background:ClearAllPoints()
        badge.background:SetPoint("CENTER", levelText, "CENTER", 0, 0)
        badge.ring:ClearAllPoints()
        badge.ring:SetPoint("CENTER", levelText, "CENTER", 0, 0)
    end

    -- Reapply on every refresh because Blizzard owns the native FontString.
    -- Must stay above the badge, which now sits above the frame art rather
    -- than below it.
    if levelText.SetDrawLayer then
        levelText:SetDrawLayer("ARTWORK", BADGE_TEXT_SUBLEVEL)
    end

    SyncLevelBadge(levelText)
end

local function RefreshLevelBadges()
    if UnitFrameGate("player") then EnsureLevelBadge(ResolvePlayerLevelText()) end
    if UnitFrameGate("target") then EnsureLevelBadge(ResolveTargetLevelText()) end
end

-- Player DPS/HPS badge ownership moved to Combat/DPSBadge.lua.  The badge
-- anchors to Blizzard's native PlayerFrame and is intentionally independent of
-- the TurboFace Unit Frames module family.

-- =============================================================================
-- TAGGED-MOB INDICATION
-- When the target is tap-denied (tagged by someone else), turn only the target
-- name dark grey (ns.BAR_BORDER_TAGGED, 55/55/55). Blizzard fully owns the
-- target level text, including its difficulty color.
-- NOTE: this used to also recolor the target-side borders (stack backdrop,
-- enemy swing bars, target castbar), but the locked Blizzard Tooltip border
-- art is not color-coded, so all border recoloring was removed. A future
-- tag indicator will require a separate visual if that feature is added.
-- =============================================================================
function UF.ApplyTargetTagState()
    if not UnitFrameGate("target") then return end
    if not UnitExists("target") then return end
    local tagged = UnitIsTapDenied and UnitIsTapDenied("target") or false

    -- Name text: tagged grey vs configured color
    if TargetFrame and TargetFrame.name then
        if tagged then
            local g = ns.BAR_BORDER_TAGGED
            TargetFrame.name:SetTextColor(g[1], g[2], g[3])
        else
            SetTextColor(TargetFrame.name, d and d.targetNameColor)
        end
    end

end
ns.UF_ApplyTargetTagState = UF.ApplyTargetTagState

-- =============================================================================
-- TARGET XP ESTIMATE  (top-right of the target HP bar)
-- Per-kill XP for the current target via the Classic formula, with elite (always)
-- and rested (while you currently have rested XP) baked in. Hidden for anything
-- that isn't an attackable, XP-giving NPC (players, friendlies, gray mobs, ?? mobs).
-- =============================================================================
local function XP_GrayLevel(P)
    if P <= 5 then return 0
    elseif P <= 39 then return P - 5 - math.floor(P / 10)
    else return P - 1 - math.floor(P / 5) end
end
local function XP_ZD(P)
    if P <= 7 then return 5
    elseif P <= 9 then return 6
    elseif P <= 11 then return 7
    elseif P <= 15 then return 8
    elseif P <= 19 then return 9
    elseif P <= 29 then return 11
    elseif P <= 39 then return 12
    elseif P <= 44 then return 13
    elseif P <= 49 then return 14
    elseif P <= 54 then return 15
    elseif P <= 59 then return 16
    else return 17 end
end
local function MobXP(P, M, rested, elite)
    local base = 5 * P + 45
    local mod
    if M >= P then
        mod = math.min(1.20, 1 + 0.05 * (M - P))
    elseif M > XP_GrayLevel(P) then
        mod = 1 - (P - M) / XP_ZD(P)
    else
        mod = 0
    end
    local xp = math.floor(base * mod + 0.5)
    if rested then xp = xp * 2 end
    if elite then xp = xp * 2 end
    return xp
end

local XP_ELITE = { elite = true, rareelite = true, worldboss = true }

local function ResolveTargetXPFS()
    if UF._targetXPFS then return UF._targetXPFS end
    if not TargetFrameHealthBar then return nil end
    UF._targetXPFS = TargetFrameHealthBar:CreateFontString(nil, "OVERLAY")
    return UF._targetXPFS
end

local function UpdateTargetXP()
    if not UnitFrameGate("target") then
        if UF._targetXPFS then UF._targetXPFS:Hide() end
        return
    end
    local fs = UF._targetXPFS
    if not fs then return end
    -- Hide for everything that isn't an attackable, computable, XP-giving NPC.
    if d.showTargetXP == false
       or not UnitExists("target")
       or UnitIsPlayer("target")
       or not UnitCanAttack("player", "target")
       or UnitIsDeadOrGhost("target")
       or (UnitXPMax("player") or 0) <= 0          -- player at max level / XP disabled
       or (IsXPUserDisabled and IsXPUserDisabled()) then
        fs:Hide()
        return
    end
    local M = UnitLevel("target")
    if not M or M < 1 then fs:Hide(); return end     -- ?? / skull (-1) -> uncomputable
    local P = UnitLevel("player")
    local rested = (GetXPExhaustion() or 0) > 0
    local elite  = XP_ELITE[UnitClassification("target")] == true
    local xp = MobXP(P, M, rested, elite)
    if xp <= 0 then fs:Hide(); return end            -- gray mob
    if d.targetXPPerHP then
        -- Speedrun efficiency: XP per 100 points of the mob's max health.
        local hp = UnitHealthMax("target")
        if not hp or hp <= 0 then fs:Hide(); return end
        fs:SetText(string.format("%.1f", xp / hp * 100))
    else
        fs:SetText(xp)
    end
    fs:Show()
end

-- Pet fixed-art suppression needs an alpha pin because Blizzard can reapply
-- native frame/attack chrome during pet refreshes. The portrait itself is never
-- passed through this helper; Blizzard retains ownership of that live texture.
local function PinAlphaZero(obj)
    if not obj or obj._srAlphaPinned then return end
    hooksecurefunc(obj, "SetAlpha", function(self, a)
        if self._srAlphaGuard then return end
        if a ~= 0 and self._tfPetChromeSuppressed then
            self._srAlphaGuard = true
            self:SetAlpha(0)
            self._srAlphaGuard = false
        end
    end)
    obj._srAlphaPinned = true
end


-- =============================================================================
-- BAR GEOMETRY
-- Player, Target, Party, ToT, and Pet health/power bars use fixed source-art coordinates.
-- Guard hooks reapply fixed geometry after Blizzard repositions protected bars.
-- =============================================================================

-- Fixed player-art geometry, expressed in source-texture pixels relative to
-- PlayerFrameTexture's 256x128 region. These are intentionally not profile
-- settings: the artwork and fills are tuned as one unit and will be refined
-- from in-game screenshots during this overhaul.
-- Geometry is in NATIVE TEXTURE PIXELS, 1:1 with frame units, because
-- SetFrameArtTextures draws the 256x128 sheet at SetSize(256, 128) and anchors
-- consumers to PlayerFrameTexture's TOPLEFT. Do not add a scale factor.
--
-- v5 artwork (0.11.4): the prebuilt attack/cast strip that used to sit at
-- y81..92 was REMOVED from the sheet. Everything above it is byte-identical to
-- v4 -- verified by pixel diff -- so name/health/power are untouched.
--
-- `reserve` is the melee/attack + cast row. It no longer indexes a hole in the
-- artwork; the row now supplies its own frame art (CastBar.tga, 121x14), so
-- these numbers position and size that art rather than describing an opening.
-- Width comes from the new texture (121) and the row is left-aligned to sit
-- flush with the health/power bars, which span x111..229.
local PLAYER_LAYOUT_NORMAL = {
    nameX = 114, nameY = 32, nameW = 112, nameH = 16,
    healthX = 111, healthY = 49, healthW = 118, healthH = 15,
    powerX = 111, powerY = 65, powerW = 118, powerH = 15,
    reserveX = 109, reserveY = 81, reserveW = 121, reserveH = 14,
}
-- Druid v3 artwork (0.11.14) is pixel-identical to the normal player sheet down
-- to y73 -- verified by diff -- and simply adds a FOURTH bar opening at y84..93
-- with the same x and width as health/power. So name/health/power keep the
-- normal geometry verbatim, the druid power row takes the next 16px slot
-- (49 -> 65 -> 81 follows the same stride), and the attack/cast row is pushed
-- one full slot down to y97 because y81 is now occupied.
--
-- The old druid sheet's bespoke 13px rows and x100 columns are gone: that art
-- began farther left inside its texture, and v3 does not.
local PLAYER_LAYOUT_DRUID = {
    nameX = 114, nameY = 32, nameW = 112, nameH = 16,
    healthX = 111, healthY = 49, healthW = 118, healthH = 15,
    powerX = 111, powerY = 65, powerW = 118, powerH = 15,
    druidX = 111, druidY = 81, druidW = 118, druidH = 15,
    reserveX = 109, reserveY = 97, reserveW = 121, reserveH = 14,
}

local function PlayerArtLayout()
    return UseDruidArt() and PLAYER_LAYOUT_DRUID or PLAYER_LAYOUT_NORMAL
end

-- Target v2 artwork (0.13.1) is a PIXEL-EXACT horizontal mirror of the player
-- v5 sheet -- verified by diff, zero differing pixels -- so every value here is
-- derived rather than tuned: for a 256-wide sheet x_mirror = 256 - x - w.
--   name    114,112 -> 30      health  111,118 -> 27
--   power   111,118 -> 27      reserve 109,121 -> 26
-- Row Y values and heights are identical to the player's; only x mirrors.
local TARGET_LAYOUT = {
    nameX = 30, nameY = 32, nameW = 112, nameH = 16,
    healthX = 27, healthY = 49, healthW = 118, healthH = 15,
    powerX = 27, powerY = 65, powerW = 118, powerH = 15,
    reserveX = 26, reserveY = 81, reserveW = 121, reserveH = 14,
}


-- Fixed party-art geometry in native 119x48 texture pixels. The three
-- full-width openings beside the portrait hold the unit name, health, and
-- power from top to bottom.
PARTY_LAYOUT = {
    artX = 0, artY = 0, artW = 119, artH = 48,
    -- Portrait and active bars deliberately extend beneath the decorative
    -- borders. Sizing them only to the fully transparent holes makes the
    -- contents look shrunken and leaves visible gaps around full bars.
    portraitX = 5, portraitY = 6, portraitW = 37, portraitH = 37,
    nameX = 45, nameY = 6, nameW = 70, nameH = 10,
    healthX = 45, healthY = 18, healthW = 70, healthH = 10,
    powerX = 45, powerY = 31, powerW = 70, powerH = 10,
}

-- Fixed Target-of-Target geometry in the native 98x48 artwork. The source
-- intentionally shifts the two active bar openings downward, leaving a compact
-- name area immediately above HP. The portrait and bars extend beneath the
-- decorative border, matching the party-frame fitting model.
local TOT_LAYOUT = {
    artX = 0, artY = 0, artW = 98, artH = 48,
    portraitX = 5, portraitY = 6, portraitW = 37, portraitH = 37,
    -- Blizzard places the ToT name below the HP/power stack. Keep that as the
    -- default while retaining the revised artwork's compact name area above as
    -- an optional presentation. The below anchor leaves a 3px gap after power.
    nameX = 45, nameAboveY = 2, nameBelowY = 38, nameW = 49, nameH = 13,
    healthX = 45, healthY = 17, healthW = 49, healthH = 8,
    powerX = 45, powerY = 28, powerW = 49, powerH = 8,
}


-- Fixed Pet geometry for UI-Pet-Portrait.tga. The source is a native 119x48
-- composition padded to 128x64 on disk. The portrait opening matches Party/ToT;
-- the two pet bar openings are taller and spaced farther apart.
local PET_LAYOUT = {
    artX = 0, artY = 0, artW = 119, artH = 48,
    portraitX = 5, portraitY = 6, portraitW = 37, portraitH = 37,
    -- The bottom layout occupies the clear strip after the power bar. The
    -- optional above layout retains the former bottom-to-frame-top anchor.
    nameX = 45, nameW = 70, nameH = 10,
    nameAboveGap = -2, nameBelowY = 37,
    healthX = 45, healthY = 8, healthW = 70, healthH = 13,
    powerX = 45, powerY = 22, powerW = 70, powerH = 13,
    -- Keep Blizzard's hunter happiness icon at its native proportions while
    -- fitting it into the fixed art immediately before the health opening.
    -- v3 alignment: half a pixel closer to the bar and one pixel lower.
    happinessW = 17, happinessH = 16, happinessGap = 0.5, happinessYOffset = -2,
}



-- Blizzard draws the portrait ring and name-bar status glow from one additive
-- atlas region (`UI-Player-Status`). The fixed TurboFace name opening sits
-- higher than Blizzard's original bar, so split that atlas into two textures:
-- keep the native portrait ring at its original anchor and place only the
-- horizontal name glow around the fixed name opening.
local PLAYER_STATUS_TEXTURE = "Interface\\CharacterFrame\\UI-Player-Status"
local PLAYER_STATUS_ATLAS_W, PLAYER_STATUS_ATLAS_H = 256, 128
local PLAYER_STATUS_PORTRAIT_RIGHT = 70
local PLAYER_STATUS_SOURCE_BOTTOM = 68
local PLAYER_STATUS_NAME_LEFT, PLAYER_STATUS_NAME_RIGHT = 70, 190
local PLAYER_STATUS_NAME_TOP, PLAYER_STATUS_NAME_BOTTOM = 16, 34

local function SyncPlayerNameStatusGlow()
    local status = PlayerStatusTexture
    local glow = status and status._tfNameBarGlow
    if not status or not glow then return end

    local r, g, b, a = status:GetVertexColor()
    local alpha = status:GetAlpha() or 1
    glow:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    glow:SetAlpha(alpha)
    glow._tfSyncedAlpha = alpha
    if status:IsShown() then glow:Show() else glow:Hide() end
end

-- Blizzard animates PlayerStatusTexture alpha at frame rate while resting/in
-- combat. Keep those post-hooks tiny: the old all-in-one sync re-read color,
-- alpha and visibility and re-applied all three on every SetAlpha call.
local function SyncPlayerNameStatusGlowShow(status)
    local glow = status and status._tfNameBarGlow
    if glow and not glow:IsShown() then glow:Show() end
end

local function SyncPlayerNameStatusGlowHide(status)
    local glow = status and status._tfNameBarGlow
    if glow and glow:IsShown() then glow:Hide() end
end

local function SyncPlayerNameStatusGlowAlpha(status, alpha)
    local glow = status and status._tfNameBarGlow
    if not glow then return end
    alpha = tonumber(alpha) or status:GetAlpha() or 1
    if glow._tfSyncedAlpha ~= alpha then
        glow._tfSyncedAlpha = alpha
        glow:SetAlpha(alpha)
    end
end

local function SyncPlayerNameStatusGlowColor(status, r, g, b, a)
    local glow = status and status._tfNameBarGlow
    if glow then glow:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
end

local function ApplyPlayerStatusGlowLayout()
    local status = PlayerStatusTexture
    local art = PlayerFrameTexture
    if not status or not art or status._tfApplyingGlowSplit then return end

    status._tfApplyingGlowSplit = true

    -- Portrait portion: preserve Blizzard's original screen position and
    -- vertical scaling while excluding the horizontal name-bar segment.
    status:SetTexture(PLAYER_STATUS_TEXTURE)
    if status.SetDrawLayer then status:SetDrawLayer("ARTWORK", 2) end
    status:SetTexCoord(
        0, PLAYER_STATUS_PORTRAIT_RIGHT / PLAYER_STATUS_ATLAS_W,
        0, PLAYER_STATUS_SOURCE_BOTTOM / PLAYER_STATUS_ATLAS_H
    )
    status:SetSize(PLAYER_STATUS_PORTRAIT_RIGHT, 66)
    MoveRegion(status, "TOPLEFT", PlayerFrame, "TOPLEFT", 19, -12)

    local glow = status._tfNameBarGlow
    if not glow then
        local owner = status:GetParent() or PlayerFrame
        glow = owner:CreateTexture(nil, "ARTWORK", nil, 2)
        glow:SetBlendMode("ADD")
        status._tfNameBarGlow = glow
    elseif glow.SetDrawLayer then
        glow:SetDrawLayer("ARTWORK", 2)
    end

    local layout = PlayerArtLayout()
    glow:SetTexture(PLAYER_STATUS_TEXTURE)
    glow:SetTexCoord(
        PLAYER_STATUS_NAME_LEFT / PLAYER_STATUS_ATLAS_W,
        PLAYER_STATUS_NAME_RIGHT / PLAYER_STATUS_ATLAS_W,
        PLAYER_STATUS_NAME_TOP / PLAYER_STATUS_ATLAS_H,
        PLAYER_STATUS_NAME_BOTTOM / PLAYER_STATUS_ATLAS_H
    )
    glow:SetSize(layout.nameW + 8, layout.nameH + 2)
    glow:ClearAllPoints()
    glow:SetPoint(
        "CENTER", art, "TOPLEFT",
        layout.nameX + layout.nameW * 0.5 - 1,
        -(layout.nameY + layout.nameH * 0.5)
    )

    status._tfApplyingGlowSplit = false
    SyncPlayerNameStatusGlow()

    if not status._tfGlowSplitHooked then
        hooksecurefunc(status, "Show", SyncPlayerNameStatusGlowShow)
        hooksecurefunc(status, "Hide", SyncPlayerNameStatusGlowHide)
        hooksecurefunc(status, "SetAlpha", SyncPlayerNameStatusGlowAlpha)
        hooksecurefunc(status, "SetVertexColor", SyncPlayerNameStatusGlowColor)

        local function ReapplySplit(self)
            if not self._tfApplyingGlowSplit then
                ApplyPlayerStatusGlowLayout()
            end
        end
        hooksecurefunc(status, "SetTexture", ReapplySplit)
        hooksecurefunc(status, "SetTexCoord", ReapplySplit)
        hooksecurefunc(status, "SetSize", ReapplySplit)
        status._tfGlowSplitHooked = true
    end
end

local function ParkFixedArtBarChrome(bar)
    if not bar then return end
    if bar._tfRing then bar._tfRing:Hide() end
    if bar._tfRingBG then bar._tfRingBG:Hide() end
end

local function ApplyPlayerBarGeometry()
    if not UnitFrameGate("player") then return end
    if not d or not PlayerFrameHealthBar then return end
    -- Re-anchoring the protected player bars is blocked in combat; defer and
    -- let PLAYER_REGEN_ENABLED re-apply the fixed texture geometry.
    if InCombatLockdown() then UF._pendingRefresh = true; return end

    local g = PlayerArtLayout()
    local anchor = PlayerFrameTexture or PlayerFrame

    local hb = PlayerFrameHealthBar
    hb._srSettingAnchor = true
    hb:ClearAllPoints()
    hb:SetPoint("TOPLEFT", anchor, "TOPLEFT", g.healthX, -g.healthY)
    hb:SetSize(g.healthW, g.healthH)
    hb._srSettingAnchor = false
    ParkFixedArtBarChrome(hb)

    local mb = PlayerFrameManaBar
    if mb then
        mb._srSettingAnchor = true
        mb:ClearAllPoints()
        mb:SetPoint("TOPLEFT", anchor, "TOPLEFT", g.powerX, -g.powerY)
        mb:SetSize(g.powerW, g.powerH)
        mb._srSettingAnchor = false
        ParkFixedArtBarChrome(mb)
    end
end

function UF:IsClassicPlayerArt()
    return true
end

function UF:GetPlayerArtLayout()
    return PlayerArtLayout()
end

function UF:GetDruidPowerGeometry()
    local g = PLAYER_LAYOUT_DRUID
    return g.druidX, g.druidY, g.druidW, g.druidH
end

-- Both sheets are now on v5/v3 artwork, neither of which draws its own
-- attack/cast strip, so the melee row always supplies its own CastBar.tga
-- border. Kept as a hook in case a future sheet reinstates a built-in slot.
function UF:PlayerArtHasBuiltinAttackSlot()
    return false
end

-- Exposed so other modules (SwingTimers, DruidPowerBar) can react to the
-- cat/bear art swap without duplicating the power-type test.
function UF:UsingDruidArt()
    return UseDruidArt()
end

function UF:GetPlayerReserveGeometry()
    local g = PlayerArtLayout()
    return g.reserveX, g.reserveY, g.reserveW, g.reserveH
end

-- Mirrors UF:PlayerArtHasBuiltinAttackSlot. True while the target sheet still
-- paints its own attack strip, in which case the target rows must NOT draw
-- their own border on top. Set false once a v5-equivalent target sheet lands.
function UF:TargetArtHasBuiltinAttackSlot()
    -- Target v2 mirrors player v5, which has no built-in attack strip, so the
    -- target rows now draw their own CastBar.tga border like the player rows.
    return false
end

function UF:GetTargetReserveGeometry()
    local g = TARGET_LAYOUT
    return g.reserveX, g.reserveY, g.reserveW, g.reserveH
end

local function ApplyTargetBarGeometry()
    if not UnitFrameGate("target") then return end
    if not d or not TargetFrameHealthBar then return end
    if InCombatLockdown() then UF._pendingRefresh = true; return end

    local g = TARGET_LAYOUT
    local anchor = TargetFrameTextureFrameTexture or TargetFrame

    local hb = TargetFrameHealthBar
    hb._srSettingAnchor = true
    hb:ClearAllPoints()
    hb:SetPoint("TOPLEFT", anchor, "TOPLEFT", g.healthX, -g.healthY)
    hb:SetSize(g.healthW, g.healthH)
    hb._srSettingAnchor = false
    ParkFixedArtBarChrome(hb)

    local mb = TargetFrameManaBar
    if mb then
        mb._srSettingAnchor = true
        mb:ClearAllPoints()
        mb:SetPoint("TOPLEFT", anchor, "TOPLEFT", g.powerX, -g.powerY)
        mb:SetSize(g.powerW, g.powerH)
        mb._srSettingAnchor = false
        ParkFixedArtBarChrome(mb)
    end
end

-- =============================================================================
-- PER-BAR BORDER RINGS (textured border mode)
-- With a textured border (e.g. Blizzard Tooltip), each status bar gets its own
-- ring anchored slightly OUTSIDE the bar so the art's ridge hugs the fill edge:
-- tight framing, and the HP/power rings meeting in the bar gap draw the
-- classic divider between the two bars. In Pixel/None mode rings are hidden
-- and the stack backdrop's own edge is the border (the original flat look).
-- Rings are TurboFace-owned frames; anchoring them to secure bars is safe.
-- =============================================================================
local ringBars = {}   -- registered bars, for style/color re-application
local ringSkipBG = {} -- bars that paint their own background (Druid aux bar)

local function ApplyBarRing(bar, skipBG, sizeOverride)
    if not bar then return end
    if skipBG then ringSkipBG[bar] = true end
    -- Per-bar edge-size override (e.g. ToT). Remembered on the bar so the
    -- override survives UF_ReapplyBarRings sweeps that don't know about it.
    if sizeOverride ~= nil then bar._tfRingSize = sizeOverride end
    local ring = bar._tfRing
    if (ns.GetBarBorderOutset and ns:GetBarBorderOutset() or 0) <= 0 then
        -- Pixel/None mode: the stack backdrop is the border AND the shared
        -- dark background, so both the ring and the per-bar background park.
        if ring then ring:Hide() end
        if bar._tfRingBG then bar._tfRingBG:Hide() end
        return
    end
    if not ring then
        ring = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate")
        ring:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
        bar._tfRing = ring
        ringBars[#ringBars + 1] = bar
    end
    -- Ring mode: each bar backs ITSELF (the shared stack fill is blanked by
    -- ApplyStackBackdrop), so no dark bleeds through the gap between bars.
    if not ringSkipBG[bar] then
        local bg = bar._tfRingBG
        if not bg then
            bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(bar)
            bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)
            bar._tfRingBG = bg
        end
        bg:SetAlpha(1)
        bg:Show()
    end
    ns:AttachBarBorder(ring, bar, bar._tfRingSize)
end

-- Style/color re-application for every live ring (ns:ReapplySharedBorders).
ns.UF_ReapplyBarRings = function()
    for _, bar in ipairs(ringBars) do
        ApplyBarRing(bar)
    end
end

-- The Blizzard PlayerFrameBackground is sized for the original compact
-- name/health/power stack. The new artwork raises the name opening and, for
-- Druids, adds a fourth fixed bar slot, so TurboFace replaces only that flat
-- backing region with a single solid-color texture sized from the source-art
-- coordinates. The decorative border remains part of PlayerFrameTexture.
local function ParkNativePlayerBackground()
    local native = PlayerFrameBackground
    if not native then return end

    native:SetAlpha(0)
    native:Hide()

    if not native._tfPlayerBackgroundHooked then
        hooksecurefunc(native, "Show", function(self)
            if self._tfParkingBackground then return end
            self._tfParkingBackground = true
            self:SetAlpha(0)
            self:Hide()
            self._tfParkingBackground = false
        end)
        native._tfPlayerBackgroundHooked = true
    end
end

local function PlayerBackdropBounds()
    local g = PlayerArtLayout()
    local left = math.min(g.nameX, g.healthX, g.powerX)
    local top = math.min(g.nameY, g.healthY, g.powerY)
    local right = math.max(
        g.nameX + g.nameW,
        g.healthX + g.healthW,
        g.powerX + g.powerW
    )
    local bottom = math.max(
        g.nameY + g.nameH,
        g.healthY + g.healthH,
        g.powerY + g.powerH
    )

    if g.druidX then
        left = math.min(left, g.druidX)
        top = math.min(top, g.druidY)
        right = math.max(right, g.druidX + g.druidW)
        bottom = math.max(bottom, g.druidY + g.druidH)
    end

    return left, top, right - left, bottom - top
end

local function ApplyPlayerBackdrop()
    if not UnitFrameGate("player") then return end
    if not PlayerFrame then return end

    ParkNativePlayerBackground()

    -- Keep all legacy TurboFace stack backdrops and per-bar rings parked. The
    -- fixed art supplies the border; this texture supplies only the dark fill
    -- visible through its transparent name and resource openings.
    if PlayerFrame._srBackdrop then
        PlayerFrame._srBackdrop:Hide()
    end
    ParkFixedArtBarChrome(PlayerFrameHealthBar)
    ParkFixedArtBarChrome(PlayerFrameManaBar)

    local art = PlayerFrameTexture or PlayerFrame
    local bg = PlayerFrame._tfPlayerBarStackBackground
    if not bg then
        bg = PlayerFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetColorTexture(0, 0, 0, 0.5)
        PlayerFrame._tfPlayerBarStackBackground = bg
    end

    local x, y, width, height = PlayerBackdropBounds()
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", art, "TOPLEFT", x, -y)
    bg:SetSize(width, height)
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetAlpha(1)
    bg:Show()
end

local function ParkTargetNativeTexture(texture, hookKey)
    if not texture then return end
    texture:SetAlpha(0)
    texture:Hide()

    if not texture[hookKey] then
        hooksecurefunc(texture, "Show", function(self)
            if self._tfParkingTargetTexture then return end
            self._tfParkingTargetTexture = true
            self:SetAlpha(0)
            self:Hide()
            self._tfParkingTargetTexture = false
        end)
        texture[hookKey] = true
    end
end

local function ParkNativeTargetBackgrounds()
    ParkTargetNativeTexture(TargetFrameBackground, "_tfTargetBackgroundHooked")
    ParkTargetNativeTexture(TargetFrameNameBackground, "_tfTargetNameBackgroundHooked")

    -- Blizzard's threat flash is shaped for the original frame/classification
    -- atlases. Keep it parked during this base artwork pass; a fitted split glow
    -- can be added later without disturbing Blizzard's threat calculations.
    ParkTargetNativeTexture(TargetFrameFlash, "_tfTargetFlashHooked")
end

local function TargetBackdropBounds()
    local g = TARGET_LAYOUT
    local left = math.min(g.nameX, g.healthX, g.powerX)
    local top = math.min(g.nameY, g.healthY, g.powerY)
    local right = math.max(g.nameX + g.nameW, g.healthX + g.healthW, g.powerX + g.powerW)
    local bottom = math.max(g.nameY + g.nameH, g.healthY + g.healthH, g.powerY + g.powerH)
    return left, top, right - left, bottom - top
end

local function ApplyTargetBackdrop()
    if not UnitFrameGate("target") then return end
    if not TargetFrame then return end

    ParkNativeTargetBackgrounds()
    if TargetFrame._srBackdrop then TargetFrame._srBackdrop:Hide() end
    ParkFixedArtBarChrome(TargetFrameHealthBar)
    ParkFixedArtBarChrome(TargetFrameManaBar)

    local art = TargetFrameTextureFrameTexture or TargetFrame
    local bg = TargetFrame._tfTargetBarStackBackground
    if not bg then
        bg = TargetFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        TargetFrame._tfTargetBarStackBackground = bg
    end

    local x, y, width, height = TargetBackdropBounds()
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", art, "TOPLEFT", x, -y)
    bg:SetSize(width, height)
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetAlpha(1)
    bg:Show()
end


-- =============================================================================
-- PLAYER FRAME
-- =============================================================================

-- SetScale on the secure unit frames (PlayerFrame/TargetFrame/PetFrame/party) is
-- a protected action in combat -- calling it then throws ADDON_ACTION_BLOCKED and
-- is ignored. Apply immediately out of combat; otherwise queue it and flush when
-- combat ends, so adjusting settings mid-fight no longer errors.
local pendingScales = {}

-- Mover offsets are stored/applied in the frame's LOCAL (scaled) coordinate
-- space, so changing a mover-managed frame's scale visually shifts it until
-- the mover re-applies (the "drifts down-right until nudged" bug). Re-apply
-- the element right after every scale change; token = the frame's global name.
local function ReapplyMoverFor(frame)
    if not (ns.Movers and ns.Movers.ApplyElement) then return end
    local name = frame and frame.GetName and frame:GetName()
    if name then ns.Movers:ApplyElement(name) end
end

local scaleWatcher
local function EnsureScaleWatcher()
    if scaleWatcher then return scaleWatcher end
    scaleWatcher = CreateFrame("Frame")
    scaleWatcher:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for frame, scale in pairs(pendingScales) do
            pendingScales[frame] = nil
            if frame and not InCombatLockdown() then
                frame:SetScale(scale)
                ReapplyMoverFor(frame)
            end
        end
    end)
    return scaleWatcher
end

local function SafeSetScale(frame, scale)
    if not frame then return end
    if InCombatLockdown() then
        pendingScales[frame] = scale
        EnsureScaleWatcher():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    frame:SetScale(scale)
    ReapplyMoverFor(frame)
end

-- Module master gates. Every per-unit styling entry point returns early when
-- its gate is off, which covers the event-driven call sites as well as Init/
-- Refresh. Because these functions restyle PROTECTED Blizzard frames in place,
-- turning a gate OFF only guarantees "TurboFace stops touching this frame from
-- now on" -- artwork already applied this session is cleared by the reload that
-- OptionsGUI prompts for. ns.ModuleEnabled fails open, so an unmigrated DB
-- behaves exactly as before.
local UFGate = UnitFrameGate

local function InitPlayer()
    if not UFGate("player") then return end
    SafeSetScale(PlayerFrame, d.playerScale or 1)
    SetFrameArtTextures()
    ApplyPlayerBarGeometry()
    ApplyPlayerStatusGlowLayout()
    ApplyPlayerBackdrop()
    EnsureLevelBadge(ResolvePlayerLevelText())

    -- Blizzard retains ownership of the player portrait, level, PVP/rest,
    -- attack, and status-state logic. TurboFace only splits the combined native
    -- status texture so the portrait ring stays native while the name-bar glow
    -- follows the higher fixed name opening.

    -- Guard hooks keep Blizzard repositions overridden. They re-read the fixed
    -- texture geometry, so health/power stay inside the artwork after updates.
    if not PlayerFrameHealthBar._srTFHooked then
        hooksecurefunc(PlayerFrameHealthBar, "SetPoint", function(self)
            if self._srSettingAnchor then return end
            ApplyPlayerBarGeometry()
        end)
        PlayerFrameHealthBar._srTFHooked = true
    end
    if PlayerFrameManaBar and not PlayerFrameManaBar._srTFHooked then
        hooksecurefunc(PlayerFrameManaBar, "SetPoint", function(self)
            if self._srSettingAnchor then return end
            ApplyPlayerBarGeometry()
        end)
        PlayerFrameManaBar._srTFHooked = true
    end

    -- TurboFace continues to own the dynamic bar values and formats. Regen tick
    -- markers and +X popups remain attached to these same Blizzard StatusBars.
    SuppressBarSideTextsOnce(PlayerFrameHealthBar)
    SuppressBarSideTextsOnce(PlayerFrameManaBar)
    StyleBarText(PlayerFrameHealthBar)
    StyleBarText(PlayerFrameManaBar)
    UpdateBarText(PlayerFrameHealthBar)
    UpdateBarText(PlayerFrameManaBar)

    -- Top artwork bar: player name only. The region is fixed to the source-art
    -- opening instead of floating above the health stack.
    if PlayerName then
        local g = PlayerArtLayout()
        StyleUnitFrameName(PlayerName, d.nameFontSize or 10)
        SetTextColor(PlayerName, d.playerNameColor)
        if PlayerName.SetJustifyH then PlayerName:SetJustifyH("CENTER") end
        if PlayerName.SetJustifyV then PlayerName:SetJustifyV("MIDDLE") end
        if PlayerName.SetWordWrap then PlayerName:SetWordWrap(false) end
        if PlayerName.SetNonSpaceWrap then PlayerName:SetNonSpaceWrap(false) end
        PlayerName:SetWidth(g.nameW - 4)
        PlayerName:SetHeight(g.nameH)
        MoveRegion(PlayerName, "CENTER", PlayerFrameTexture or PlayerFrame, "TOPLEFT",
            g.nameX + g.nameW * 0.5, -(g.nameY + g.nameH * 0.5))
        PlayerName:Show()
    end

    -- Hit-indicator control remains independent of the removed portrait/PVP/
    -- combat-icon styling. Blizzard owns all other status icons and animations.
    if not d.showHitIndicator and PlayerHitIndicator then
        PlayerHitIndicator:SetText(nil)
        if not PlayerHitIndicator._srHookSetText then
            hooksecurefunc(PlayerHitIndicator, "SetText", function(self, text, flag)
                if flag ~= "TFHookSetText" then self:SetText(nil, "TFHookSetText") end
            end)
            PlayerHitIndicator._srHookSetText = true
        end
    end
end

-- =============================================================================
-- TARGET FRAME
-- =============================================================================

-- =============================================================================
-- TARGET OF TARGET
-- Fixed 98x48 artwork with Blizzard's native portrait restored. TurboFace owns
-- only the presentation layers and fixed out-of-combat geometry; Blizzard keeps
-- secure visibility, unit updates, portrait selection, and click behavior.
-- =============================================================================

local function ResolveToTPortrait()
    local tot = TargetFrameToT
    if not tot then return nil end
    return TargetFrameToTPortrait
        or _G.TargetFrameToTTextureFramePortrait
        or tot.portrait
        or tot.Portrait
        or (tot.TextureFrame and (tot.TextureFrame.portrait or tot.TextureFrame.Portrait))
        or (tot.TargetFrameToTContent and tot.TargetFrameToTContent.Portrait)
end

-- Blizzard's four ToT debuff slots (TargetFrameToTDebuff1..4) are children of
-- the ToT button, so a naive recursive walk sweeps their icon/border textures
-- into the chrome set and alpha-zeroes them. They are real content, not frame
-- chrome: Blizzard keeps populating and showing them from
-- TargetOfTargetMixin:Update -> AuraUtil.RefreshAuras. Skip those subtrees.
local TOT_DEBUFF_COUNT = 4

local function ToTDebuffFrames()
    local out = {}
    for i = 1, TOT_DEBUFF_COUNT do
        local f = _G["TargetFrameToTDebuff" .. i]
        if f then out[#out + 1] = f end
    end
    return out
end

-- Capture Blizzard's original ToT chrome once, before TurboFace creates its own
-- art layers. Reapplying alpha after Blizzard refreshes avoids Show/Hide hooks on
-- the protected secure unit button and therefore preserves the 0.9.31 taint fix.
local function CollectToTNativeChrome()
    if UF._totNativeChromeCollected or not TargetFrameToT then return end
    UF._totNativeChromeCollected = true
    UF._totNativeChromeTextures = UF._totNativeChromeTextures or {}

    local portrait = ResolveToTPortrait()
    local hp, mn = TargetFrameToTHealthBar, TargetFrameToTManaBar
    local hpFill = hp and hp:GetStatusBarTexture()
    local mnFill = mn and mn:GetStatusBarTexture()

    local skip = {}
    for _, f in ipairs(ToTDebuffFrames()) do skip[f] = true end

    local function collectFrame(frame)
        if not frame or skip[frame] then return end
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region ~= portrait and region ~= hpFill and region ~= mnFill
                    and region.GetObjectType and region:GetObjectType() == "Texture" then
                    UF._totNativeChromeTextures[region] = true
                end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                collectFrame(child)
            end
        end
    end
    collectFrame(TargetFrameToT)
end

-- Installs that ran an earlier build already have the debuff textures in the
-- collected set with alpha 0 baked in. Drop them from the set and restore alpha
-- once per session so the icons come back without requiring a fresh profile.
local function ReleaseToTDebuffChrome()
    if UF._totDebuffChromeReleased then return end
    local frames = ToTDebuffFrames()
    if #frames == 0 then return end
    UF._totDebuffChromeReleased = true

    local collected = UF._totNativeChromeTextures
    local function release(frame)
        if not frame then return end
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "Texture" then
                    if collected then collected[region] = nil end
                    if region.SetAlpha then region:SetAlpha(1) end
                end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do release(child) end
        end
    end
    for _, f in ipairs(frames) do
        release(f)
        if f.SetAlpha then f:SetAlpha(1) end
    end
end

local function SuppressToTNativeChrome()
    CollectToTNativeChrome()
    ReleaseToTDebuffChrome()
    for texture in pairs(UF._totNativeChromeTextures or EMPTY) do
        if texture and texture.SetAlpha then texture:SetAlpha(0) end
    end
end

local function EnsureToTArtLayers()
    local tot = TargetFrameToT
    if not tot then return nil end
    local baseLevel = tot:GetFrameLevel() or 0

    local base = UF._totBaseLayer
    if not base then
        base = CreateFrame("Frame", nil, tot)
        base:EnableMouse(false)
        base.healthBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        base.powerBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        UF._totBaseLayer = base
    end
    base:SetFrameStrata(tot:GetFrameStrata())
    base:SetFrameLevel(baseLevel + 1)
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", tot, "TOPLEFT", TOT_LAYOUT.artX, -TOT_LAYOUT.artY)
    base:SetSize(TOT_LAYOUT.artW, TOT_LAYOUT.artH)

    local artFrame = UF._totArtFrame
    if not artFrame then
        artFrame = CreateFrame("Frame", nil, tot)
        artFrame:EnableMouse(false)
        artFrame.texture = artFrame:CreateTexture(nil, "ARTWORK")
        artFrame.texture:SetAllPoints(artFrame)
        UF._totArtFrame = artFrame
    end
    artFrame:SetFrameStrata(tot:GetFrameStrata())
    artFrame:SetFrameLevel(baseLevel + 5)
    artFrame:ClearAllPoints()
    artFrame:SetPoint("TOPLEFT", tot, "TOPLEFT", TOT_LAYOUT.artX, -TOT_LAYOUT.artY)
    artFrame:SetSize(TOT_LAYOUT.artW, TOT_LAYOUT.artH)
    artFrame.texture:SetTexture(TOT_ART)
    artFrame.texture:SetTexCoord(0, TOT_LAYOUT.artW / 128, 0, TOT_LAYOUT.artH / 64)
    artFrame.texture:SetVertexColor(1, 1, 1, 1)
    artFrame.texture:SetAlpha(1)

    local textLayer = UF._totTextLayer
    if not textLayer then
        textLayer = CreateFrame("Frame", nil, tot)
        textLayer:EnableMouse(false)
        UF._totTextLayer = textLayer
    end
    textLayer:SetFrameStrata(tot:GetFrameStrata())
    textLayer:SetFrameLevel(baseLevel + 6)
    textLayer:ClearAllPoints()
    textLayer:SetPoint("TOPLEFT", tot, "TOPLEFT", TOT_LAYOUT.artX, -TOT_LAYOUT.artY)
    textLayer:SetSize(TOT_LAYOUT.artW, TOT_LAYOUT.artH)

    return base, artFrame, textLayer
end

local function EnsureToTBarTextLayer(bar)
    if not bar or not TargetFrameToT then return nil end
    local layer = bar._tfToTTextLayer
    if not layer then
        layer = CreateFrame("Frame", nil, bar)
        layer:EnableMouse(false)
        bar._tfToTTextLayer = layer
    end
    layer:SetAllPoints(bar)
    layer:SetFrameStrata(TargetFrameToT:GetFrameStrata())
    layer:SetFrameLevel((TargetFrameToT:GetFrameLevel() or 0) + 6)
    return layer
end

local function RestoreAndFitToTPortrait()
    local tot = TargetFrameToT
    local portrait = ResolveToTPortrait()
    if not tot or not portrait then return end

    if portrait.SetScale then portrait:SetScale(1) end
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPLEFT", tot, "TOPLEFT",
        TOT_LAYOUT.artX + TOT_LAYOUT.portraitX,
        -(TOT_LAYOUT.artY + TOT_LAYOUT.portraitY))
    portrait:SetSize(TOT_LAYOUT.portraitW, TOT_LAYOUT.portraitH)
    if SetPortraitTexture then SetPortraitTexture(portrait, "targettarget") end
    portrait:SetAlpha(1)

    if tot.CreateMaskTexture and portrait.AddMaskTexture then
        local mask = UF._totPortraitMask
        if not mask then
            mask = tot:CreateMaskTexture(nil, "ARTWORK")
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            portrait:AddMaskTexture(mask)
            UF._totPortraitMask = mask
        end
        mask:ClearAllPoints()
        mask:SetAllPoints(portrait)
    end
end

-- TargetFrameToT is a protected SecureUnitButton. Never call Show/Hide on
-- frames, textures, or FontStrings in its hierarchy: even an addon-owned child
-- can taint Blizzard's later secure TargetOfTargetMixin:Update() visibility
-- decision. The fixed-art ToT therefore uses alpha-only presentation helpers.
local function SuppressToTBarBackground(bar)
    if not bar then return end
    local fillTex = bar:GetStatusBarTexture()
    for _, region in ipairs({ bar:GetRegions() }) do
        if region ~= fillTex and region ~= bar._tfRingBG
        and region.GetObjectType and region:GetObjectType() == "Texture"
        and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
    if bar.Background and bar.Background.SetAlpha then
        bar.Background:SetAlpha(0)
    end
end

local function ParkToTBarChrome(bar)
    if not bar then return end
    if bar._tfRing and bar._tfRing.SetAlpha then bar._tfRing:SetAlpha(0) end
    if bar._tfRingBG and bar._tfRingBG.SetAlpha then bar._tfRingBG:SetAlpha(0) end
end

local function StyleToTBarText(bar)
    if not bar then return end
    local txt = GetCenterText(bar)
    if not txt then return end
    StyleUnitFrameValue(txt, bar._tfTextSize or d.totBarFontSize or 9)
    if txt.SetJustifyH then txt:SetJustifyH("CENTER") end
    if txt.SetJustifyV then txt:SetJustifyV("MIDDLE") end
    MoveRegion(txt, "CENTER", bar, "CENTER", 0, bar._tfTextYOffset or 0)
    txt:SetAlpha(1)
end

-- Blizzard's debuff slots sit at the ToT button's own frame level, which puts
-- them underneath TurboFace's art (baseLevel+5) and text (baseLevel+6) layers.
-- Lift them clear. These are children of a protected SecureUnitButton, so the
-- write is gated on combat like every other ToT geometry change.
local function ApplyToTDebuffLevels()
    local tot = TargetFrameToT
    if not tot then return end
    if InCombatLockdown() then UF._pendingRefresh = true; return end
    local baseLevel = tot:GetFrameLevel() or 0
    for _, f in ipairs(ToTDebuffFrames()) do
        f:SetFrameStrata(tot:GetFrameStrata())
        f:SetFrameLevel(baseLevel + 8)
    end
end

local function ApplyToTArtGeometry()
    if not UnitFrameGate("tot") then return end
    local tot = TargetFrameToT
    local hp, mn = TargetFrameToTHealthBar, TargetFrameToTManaBar
    if not d or not tot or not hp then return end
    if InCombatLockdown() then UF._pendingRefresh = true; return end

    -- Fixed artwork is designed at native scale. The target frame's own scale
    -- can still affect its child naturally; TurboFace no longer adds a second
    -- independent ToT scale multiplier.
    SuppressToTNativeChrome()
    local base = EnsureToTArtLayers()
    RestoreAndFitToTPortrait()
    ApplyToTDebuffLevels()

    local baseLevel = tot:GetFrameLevel() or 0
    hp.forceHideText = true
    hp._tfUseOwnedCenterText = true
    hp._tfTextOwner = EnsureToTBarTextLayer(hp)
    hp._tfTextSize = d.totBarFontSize or 9
    hp._tfTextYOffset = 0
    hp._tfKind = "health"
    barCenterTextCache[hp] = nil
    hp:SetFrameStrata(tot:GetFrameStrata())
    hp:SetFrameLevel(baseLevel + 2)
    if hp.SetScale then hp:SetScale(1) end
    hp._srSettingAnchor = true
    hp:ClearAllPoints()
    hp:SetPoint("TOPLEFT", tot, "TOPLEFT",
        TOT_LAYOUT.artX + TOT_LAYOUT.healthX,
        -(TOT_LAYOUT.artY + TOT_LAYOUT.healthY))
    hp:SetSize(TOT_LAYOUT.healthW, TOT_LAYOUT.healthH)
    hp._srSettingAnchor = false
    SuppressToTBarBackground(hp)
    ParkToTBarChrome(hp)
    SuppressBarSideTextsOnce(hp)
    StyleToTBarText(hp)
    base.healthBG:ClearAllPoints()
    base.healthBG:SetAllPoints(hp)
    base.healthBG:SetColorTexture(0, 0, 0, 0.50)
    base.healthBG:SetAlpha(1)

    if mn then
        mn.forceHideText = true
        mn._tfUseOwnedCenterText = true
        mn._tfTextOwner = EnsureToTBarTextLayer(mn)
        mn._tfTextSize = d.totBarFontSize or 9
        mn._tfTextYOffset = 0
        mn._tfKind = "mana"
        barCenterTextCache[mn] = nil
        mn:SetFrameStrata(tot:GetFrameStrata())
        mn:SetFrameLevel(baseLevel + 2)
        if mn.SetScale then mn:SetScale(1) end
        mn._srSettingAnchor = true
        mn:ClearAllPoints()
        mn:SetPoint("TOPLEFT", tot, "TOPLEFT",
            TOT_LAYOUT.artX + TOT_LAYOUT.powerX,
            -(TOT_LAYOUT.artY + TOT_LAYOUT.powerY))
        mn:SetSize(TOT_LAYOUT.powerW, TOT_LAYOUT.powerH)
        mn._srSettingAnchor = false
        SuppressToTBarBackground(mn)
        ParkToTBarChrome(mn)
        SuppressBarSideTextsOnce(mn)
        StyleToTBarText(mn)
        base.powerBG:ClearAllPoints()
        base.powerBG:SetAllPoints(mn)
        base.powerBG:SetColorTexture(0, 0, 0, 0.50)
        base.powerBG:SetAlpha(1)
    end

    local totName = TargetFrameToTTextureFrameName or _G.TargetFrameToTName or tot.name
    if totName then
        StyleUnitFrameName(totName, d.totNameFontSize or 14)
        SetTextColor(totName, d.targetNameColor)
        if totName.SetJustifyH then totName:SetJustifyH("CENTER") end
        if totName.SetJustifyV then totName:SetJustifyV("MIDDLE") end
        if totName.SetWordWrap then totName:SetWordWrap(false) end
        if totName.SetNonSpaceWrap then totName:SetNonSpaceWrap(false) end
        if totName.SetDrawLayer then totName:SetDrawLayer("OVERLAY", 7) end
        local nameY = d.totNameAboveBars and TOT_LAYOUT.nameAboveY or TOT_LAYOUT.nameBelowY
        totName:ClearAllPoints()
        totName:SetPoint("TOPLEFT", tot, "TOPLEFT",
            TOT_LAYOUT.artX + TOT_LAYOUT.nameX,
            -(TOT_LAYOUT.artY + nameY))
        totName:SetSize(TOT_LAYOUT.nameW, TOT_LAYOUT.nameH)
        totName:SetAlpha(1)
    end

    -- Retire the former ring/backdrop presentation if this build is applied
    -- during development without a complete client restart.
    if UF._totBackdrop then UF._totBackdrop:SetAlpha(0) end

    InvalidateBarText(hp)
    UpdateBarText(hp)
    if mn then
        InvalidateBarText(mn)
        UpdateBarText(mn)
    end
end

local function RefreshToTValueText()
    if not UFGate("tot") then return end
    InvalidateBarText(TargetFrameToTHealthBar)
    InvalidateBarText(TargetFrameToTManaBar)
    UpdateBarText(TargetFrameToTHealthBar)
    UpdateBarText(TargetFrameToTManaBar)
end

local function InitToT()
    if not UFGate("tot") then return end
    local tot = TargetFrameToT
    if not tot then return end

    -- Keep ToT independent from the Target child gate. Install its protected-bar
    -- geometry hooks here rather than inside InitTarget().
    for _, bar in ipairs({ TargetFrameToTHealthBar, TargetFrameToTManaBar }) do
        if bar and not bar._tfToTArtHooked then
            hooksecurefunc(bar, "SetPoint", function(self)
                if self._srSettingAnchor then return end
                ApplyToTArtGeometry()
            end)
            bar._tfToTArtHooked = true
        end
    end

    -- Blizzard exclusively owns secure ToT visibility. TurboFace only changes
    -- the frame alpha out of combat for the existing Show ToT option.
    if not InCombatLockdown() then
        tot:SetAlpha(d.showToT and 1 or 0)
        ApplyToTArtGeometry()
    else
        -- Chrome/portrait content may refresh during combat, but geometry waits
        -- until PLAYER_REGEN_ENABLED to avoid protected-frame mutations.
        SuppressToTNativeChrome()
        local portrait = ResolveToTPortrait()
        if portrait then
            if SetPortraitTexture then SetPortraitTexture(portrait, "targettarget") end
            portrait:SetAlpha(1)
        end
    end

    local guid = UnitGUID("targettarget")
    if UF._totStyledGUID == guid and not ns._totStyleDirty then return end
    UF._totStyledGUID = guid
    ns._totStyleDirty = nil

    SuppressToTNativeChrome()
    local hp, mn = TargetFrameToTHealthBar, TargetFrameToTManaBar
    local totTextSize = d.totBarFontSize or 9
    for _, bar in ipairs({ hp, mn }) do
        local txt = bar and GetCenterText(bar)
        if txt then StyleUnitFrameValue(txt, totTextSize) end
    end

    local totName = TargetFrameToTTextureFrameName or _G.TargetFrameToTName or tot.name
    if totName then
        StyleUnitFrameName(totName, d.totNameFontSize or 14)
        SetTextColor(totName, d.targetNameColor)
    end
end

local function InitTarget()
    if not UFGate("target") then return end
    ns._totStyleDirty = true
    SafeSetScale(TargetFrame, d.targetScale or 1)
    ApplyTargetFrameArtTexture()
    ApplyTargetBarGeometry()
    ApplyTargetBackdrop()
    EnsureLevelBadge(ResolveTargetLevelText())

    -- Keep Blizzard's normal portrait-inclusive click area. The previous
    -- portrait-less layout cropped interaction to only the oversized bar stack.
    if not InCombatLockdown() and TargetFrame and TargetFrame.SetHitRectInsets then
        TargetFrame:SetHitRectInsets(19, 21, 12, 15)
    end

    -- Blizzard owns the portrait and refreshes it on target changes. Resolve the
    -- current object only so we can undo any stale alpha from older TurboFace
    -- layouts during a live upgrade/reload.
    UF._targetPortrait = TargetFramePortrait
        or (TargetFrame and TargetFrame.portrait)
        or (TargetFrame and TargetFrame.TargetFrameContent
            and TargetFrame.TargetFrameContent.TargetFrameContentMain
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.Portrait)
    if UF._targetPortrait then
        UF._targetPortrait:SetAlpha(1)
        UF._targetPortrait:Show()
    end

    if not TargetFrameHealthBar._srTFHooked then
        hooksecurefunc(TargetFrameHealthBar, "SetPoint", function(self)
            if self._srSettingAnchor then return end
            ApplyTargetBarGeometry()
        end)
        TargetFrameHealthBar._srTFHooked = true
    end
    if TargetFrameManaBar and not TargetFrameManaBar._srTFHooked then
        hooksecurefunc(TargetFrameManaBar, "SetPoint", function(self)
            if self._srSettingAnchor then return end
            ApplyTargetBarGeometry()
        end)
        TargetFrameManaBar._srTFHooked = true
    end

    TargetFrameHealthBar.forceHideText = true
    if TargetFrameManaBar then TargetFrameManaBar.forceHideText = true end
    SuppressBarSideTextsOnce(TargetFrameHealthBar)
    SuppressBarSideTextsOnce(TargetFrameManaBar)
    StyleBarText(TargetFrameHealthBar)
    StyleBarText(TargetFrameManaBar)
    UpdateBarText(TargetFrameHealthBar)
    UpdateBarText(TargetFrameManaBar)

    -- Blizzard continues to own dead/unconscious visibility and wording; only
    -- center those state labels inside the new fixed health opening.
    MoveRegion(TargetFrameTextureFrameDeadText, "CENTER", TargetFrameHealthBar, "CENTER", 0, 0)
    MoveRegion(TargetFrameTextureFrameUnconsciousText, "CENTER", TargetFrameHealthBar, "CENTER", 0, 0)
    TargetFrameHealthBar._srShowSideTexts = false
    TargetFrameHealthBar._srHideCenterText = false
    if TargetFrameHealthBar.LeftText then TargetFrameHealthBar.LeftText:SetAlpha(0) end
    if TargetFrameHealthBar.RightText then TargetFrameHealthBar.RightText:SetAlpha(0) end

    -- Blizzard fully owns the target level text and high-level/skull artwork.
    -- Do not alter its font, color, alpha, text, visibility, or update path.

    local xpFS = ResolveTargetXPFS()
    if xpFS then
        StyleUnitFrameValue(xpFS, math.max(6, (d.barFontSize or 10) - 2))
        SetTextColor(xpFS, d.targetXPColor)
        if xpFS.SetJustifyH then xpFS:SetJustifyH("RIGHT") end
        MoveRegion(xpFS, "TOPRIGHT", TargetFrameHealthBar, "TOPRIGHT", -3, -2)
        UpdateTargetXP()
    end

    if TargetFrame.name then
        local g = TARGET_LAYOUT
        StyleUnitFrameName(TargetFrame.name, d.nameFontSize or 10)
        SetTextColor(TargetFrame.name, d.targetNameColor)
        if TargetFrame.name.SetJustifyH then TargetFrame.name:SetJustifyH("CENTER") end
        if TargetFrame.name.SetJustifyV then TargetFrame.name:SetJustifyV("MIDDLE") end
        if TargetFrame.name.SetWordWrap then TargetFrame.name:SetWordWrap(false) end
        if TargetFrame.name.SetNonSpaceWrap then TargetFrame.name:SetNonSpaceWrap(false) end
        TargetFrame.name:SetWidth(g.nameW - 4)
        TargetFrame.name:SetHeight(g.nameH)
        MoveRegion(TargetFrame.name, "CENTER", TargetFrameTextureFrameTexture or TargetFrame, "TOPLEFT",
            g.nameX + g.nameW * 0.5, -(g.nameY + g.nameH * 0.5))
        if d.showTargetName then TargetFrame.name:Show() else TargetFrame.name:Hide() end
    end

    -- Classification still runs so Blizzard can handle minus-unit power state,
    -- but its native dragon texture is immediately replaced by the matching
    -- TurboFace fixed art selected for the target's current classification.
    if not UF._classificationHooked then
        UF._classificationHooked = ns.API.HookGlobalOrMethod(
            "TargetFrame_CheckClassification", TargetFrame, "CheckClassification",
            function()
                ApplyTargetFrameArtTexture()
                ApplyTargetBackdrop()
            end)
        if not UF._classificationHooked then
            UF._classificationHooked = true
            ns:Chat("Debug", "UnitFrames: no TargetFrame classification hook target on this client")
        end
    end

    TargetFrameHealthBar:SetReverseFill(d.reverseTargetHP or false)
    if TargetFrameManaBar then
        TargetFrameManaBar:SetReverseFill(d.reverseTargetHP or false)
    end

    -- Portrait, PVP, leader, raid marker, high-level skull, and dead/unconscious
    -- state remain Blizzard-owned. The old custom PVP sizing/positioning and the
    -- broad texture-frame suppression sweep are intentionally gone.
    ParkNativeTargetBackgrounds()
end

-- =============================================================================
-- PET FRAME
-- =============================================================================

local function EnsurePetArtLayers()
    if not PetFrame then return nil end
    local baseLevel = PetFrame:GetFrameLevel() or 0

    local base = PetFrame._tfPetBaseLayer
    if not base then
        base = CreateFrame("Frame", nil, PetFrame)
        base:EnableMouse(false)
        base.healthBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        base.powerBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        PetFrame._tfPetBaseLayer = base
    end
    base:SetFrameStrata(PetFrame:GetFrameStrata())
    base:SetFrameLevel(baseLevel + 1)
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", PetFrame, "TOPLEFT", PET_LAYOUT.artX, -PET_LAYOUT.artY)
    base:SetSize(PET_LAYOUT.artW, PET_LAYOUT.artH)

    local artFrame = PetFrame._tfPetArtFrame
    if not artFrame then
        artFrame = CreateFrame("Frame", nil, PetFrame)
        artFrame:EnableMouse(false)
        artFrame.texture = artFrame:CreateTexture(nil, "ARTWORK")
        artFrame.texture:SetAllPoints(artFrame)
        PetFrame._tfPetArtFrame = artFrame
    end
    artFrame:SetFrameStrata(PetFrame:GetFrameStrata())
    artFrame:SetFrameLevel(baseLevel + 5)
    artFrame:ClearAllPoints()
    artFrame:SetPoint("TOPLEFT", PetFrame, "TOPLEFT", PET_LAYOUT.artX, -PET_LAYOUT.artY)
    artFrame:SetSize(PET_LAYOUT.artW, PET_LAYOUT.artH)
    artFrame.texture:SetTexture(PET_ART)
    artFrame.texture:SetTexCoord(0, 119 / 128, 0, 48 / 64)
    artFrame.texture:SetVertexColor(1, 1, 1, 1)
    artFrame.texture:SetAlpha(1)
    artFrame:Show()

    local textLayer = PetFrame._tfPetTextLayer
    if not textLayer then
        textLayer = CreateFrame("Frame", nil, PetFrame)
        textLayer:EnableMouse(false)
        PetFrame._tfPetTextLayer = textLayer
    end
    textLayer:SetFrameStrata(PetFrame:GetFrameStrata())
    textLayer:SetFrameLevel(baseLevel + 6)
    textLayer:ClearAllPoints()
    textLayer:SetPoint("TOPLEFT", PetFrame, "TOPLEFT", PET_LAYOUT.artX, -PET_LAYOUT.artY)
    textLayer:SetSize(PET_LAYOUT.artW, PET_LAYOUT.artH)
    textLayer:Show()

    return base, artFrame, textLayer
end

local function EnsurePetBarTextLayer(bar)
    if not bar or not PetFrame then return nil end
    local layer = bar._tfPetTextLayer
    if not layer then
        layer = CreateFrame("Frame", nil, bar)
        layer:EnableMouse(false)
        bar._tfPetTextLayer = layer
    end
    layer:SetAllPoints(bar)
    layer:SetFrameStrata(PetFrame:GetFrameStrata())
    layer:SetFrameLevel((PetFrame:GetFrameLevel() or 0) + 6)
    return layer
end

local function RestoreAndFitPetPortrait()
    local portrait = PetPortrait or (PetFrame and (PetFrame.portrait or PetFrame.Portrait))
    if not PetFrame or not portrait then return nil end

    if portrait.SetScale then portrait:SetScale(1) end
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPLEFT", PetFrame, "TOPLEFT",
        PET_LAYOUT.artX + PET_LAYOUT.portraitX,
        -(PET_LAYOUT.artY + PET_LAYOUT.portraitY))
    portrait:SetSize(PET_LAYOUT.portraitW, PET_LAYOUT.portraitH)
    if SetPortraitTexture then SetPortraitTexture(portrait, "pet") end
    portrait:SetAlpha(1)
    portrait:Show()

    if PetFrame.CreateMaskTexture and portrait.AddMaskTexture then
        local mask = PetFrame._tfPetPortraitMask
        if not mask then
            mask = PetFrame:CreateMaskTexture(nil, "ARTWORK")
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            portrait:AddMaskTexture(mask)
            PetFrame._tfPetPortraitMask = mask
        end
        mask:ClearAllPoints()
        mask:SetAllPoints(portrait)
    end
    return portrait
end

-- PetFrameHappiness is Blizzard's Hunter-only happy/content/unhappy indicator.
-- Retain its texture, state updates, and tooltip; TurboFace owns only its fixed-art
-- geometry so it remains above the pet artwork instead of hanging outside it.
local function LayoutPetHappiness()
    local happiness = PetFrameHappiness
    if not PetFrame or not happiness then return end

    local width = PET_LAYOUT.happinessW
    local x = PET_LAYOUT.artX + PET_LAYOUT.healthX - width - PET_LAYOUT.happinessGap
    local y = PET_LAYOUT.artY + PET_LAYOUT.healthY + PET_LAYOUT.happinessYOffset
    happiness:SetFrameStrata(PetFrame:GetFrameStrata())
    happiness:SetFrameLevel((PetFrame:GetFrameLevel() or 0) + 6)
    happiness._tfSettingPetHappinessLayout = true
    happiness:ClearAllPoints()
    happiness:SetPoint("TOPLEFT", PetFrame, "TOPLEFT", x, -y)
    happiness:SetSize(width, PET_LAYOUT.happinessH)
    happiness._tfSettingPetHappinessLayout = false

    -- Blizzard normally lays this child out beside the native frame. Preserve
    -- the compact slot if a later native update attempts to restore that anchor.
    if not happiness._tfPetHappinessLayoutHooked then
        local function reapply(self)
            if self._tfSettingPetHappinessLayout or not UFGate("pet") then return end
            if InCombatLockdown() then UF._pendingRefresh = true; return end
            LayoutPetHappiness()
        end
        hooksecurefunc(happiness, "SetPoint", reapply)
        hooksecurefunc(happiness, "SetSize", reapply)
        happiness._tfPetHappinessLayoutHooked = true
    end
end

local function SuppressPetNativeChrome(portrait)
    if not PetFrame then return end
    local function suppress(texture)
        if not texture or texture == portrait then return end
        texture._tfPetChromeSuppressed = true
        texture:SetAlpha(0)
        PinAlphaZero(texture)
    end

    suppress(PetFrameTexture)
    suppress(PetFrameFlash)
    suppress(PetAttackModeTexture)
    for _, region in ipairs({PetFrame:GetRegions()}) do
        if region ~= portrait and region.GetObjectType and region:GetObjectType() == "Texture" then
            suppress(region)
        end
    end
end

local function InitPet()
    if not UFGate("pet") or not PetFrame then return end
    if InCombatLockdown() then UF._pendingRefresh = true; return end

    SafeSetScale(PetFrame, d.petScale or 1)
    local base, artFrame, textLayer = EnsurePetArtLayers()
    if not base or not artFrame or not textLayer then return end
    local portrait = RestoreAndFitPetPortrait()
    SuppressPetNativeChrome(portrait)
    LayoutPetHappiness()
    local buffContainer = ns.PartyAuras.EnsurePetBuffContainer(PetFrame)
    local debuffContainer = ns.PartyAuras.EnsurePetDebuffContainer(PetFrame)
    local suppressPetNativeAuras = ns.PartyAuras.SuppressPetNativeAuras
    if suppressPetNativeAuras then suppressPetNativeAuras(PetFrame) end

    local hb, mb = PetFrameHealthBar, PetFrameManaBar
    local baseLevel = PetFrame:GetFrameLevel() or 0
    if hb then
        hb.forceHideText = true
        hb._tfUseOwnedCenterText = true
        hb._tfTextOwner = EnsurePetBarTextLayer(hb)
        barCenterTextCache[hb] = nil
        hb._tfTextSize = d.petBarFontSize or 8
        hb._tfTextYOffset = 0
        hb._tfKind = "health"
        hb._tfPetFixedArt = true
        hb:SetFrameStrata(PetFrame:GetFrameStrata())
        hb:SetFrameLevel(baseLevel + 2)
        if hb.SetScale then hb:SetScale(1) end
        hb:SetStatusBarTexture(ns.ResolveStatusBarTexture(d.healthTexture or "Blizzard"))
        hb:SetAlpha(1)
        hb._srSettingAnchor = true
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", PetFrame, "TOPLEFT",
            PET_LAYOUT.artX + PET_LAYOUT.healthX,
            -(PET_LAYOUT.artY + PET_LAYOUT.healthY))
        hb:SetSize(PET_LAYOUT.healthW, PET_LAYOUT.healthH)
        hb._srSettingAnchor = false
        HideBarBackground(hb)
        base.healthBG:ClearAllPoints()
        base.healthBG:SetAllPoints(hb)
        base.healthBG:SetColorTexture(0, 0, 0, 0.50)
        base.healthBG:SetAlpha(1)
        base.healthBG:Show()
        SuppressBarSideTextsOnce(hb)
        StyleBarText(hb)
        ParkFixedArtBarChrome(hb)
        if not hb._tfPetValueHooked then
            hb:HookScript("OnValueChanged", UpdateBarText)
            hb._tfPetValueHooked = true
        end
        UpdateBarText(hb)
        if not hb._tfPetArtAnchorHooked then
            hooksecurefunc(hb, "SetPoint", function(self)
                if self._srSettingAnchor or not UFGate("pet") then return end
                if InCombatLockdown() then UF._pendingRefresh = true; return end
                InitPet()
            end)
            hb._tfPetArtAnchorHooked = true
        end
    end
    if mb then
        mb.forceHideText = true
        mb._tfUseOwnedCenterText = true
        mb._tfTextOwner = EnsurePetBarTextLayer(mb)
        barCenterTextCache[mb] = nil
        mb._tfTextSize = d.petBarFontSize or 8
        mb._tfTextYOffset = 0
        mb._tfKind = "mana"
        mb._tfPetFixedArt = true
        mb:SetFrameStrata(PetFrame:GetFrameStrata())
        mb:SetFrameLevel(baseLevel + 2)
        if mb.SetScale then mb:SetScale(1) end
        mb:SetStatusBarTexture(ns.ResolveStatusBarTexture(d.manaTexture or "Blizzard"))
        mb:SetAlpha(1)
        mb._srSettingAnchor = true
        mb:ClearAllPoints()
        mb:SetPoint("TOPLEFT", PetFrame, "TOPLEFT",
            PET_LAYOUT.artX + PET_LAYOUT.powerX,
            -(PET_LAYOUT.artY + PET_LAYOUT.powerY))
        mb:SetSize(PET_LAYOUT.powerW, PET_LAYOUT.powerH)
        mb._srSettingAnchor = false
        HideBarBackground(mb)
        base.powerBG:ClearAllPoints()
        base.powerBG:SetAllPoints(mb)
        base.powerBG:SetColorTexture(0, 0, 0, 0.50)
        base.powerBG:SetAlpha(1)
        base.powerBG:Show()
        SuppressBarSideTextsOnce(mb)
        StyleBarText(mb)
        ParkFixedArtBarChrome(mb)
        if not mb._tfPetValueHooked then
            mb:HookScript("OnValueChanged", UpdateBarText)
            mb._tfPetValueHooked = true
        end
        UpdateBarText(mb)
        if not mb._tfPetArtAnchorHooked then
            hooksecurefunc(mb, "SetPoint", function(self)
                if self._srSettingAnchor or not UFGate("pet") then return end
                if InCombatLockdown() then UF._pendingRefresh = true; return end
                InitPet()
            end)
            mb._tfPetArtAnchorHooked = true
        end
    end

    if PetName then
        StyleUnitFrameName(PetName, d.petNameFontSize or 9)
        SetTextColor(PetName, d.petNameColor)
        if PetName.SetJustifyH then PetName:SetJustifyH("CENTER") end
        if PetName.SetJustifyV then PetName:SetJustifyV("MIDDLE") end
        if PetName.SetWordWrap then PetName:SetWordWrap(false) end
        if PetName.SetNonSpaceWrap then PetName:SetNonSpaceWrap(false) end
        PetName:ClearAllPoints()
        local namePoint = d.petNameAboveBars and "BOTTOM" or "TOP"
        local nameY = d.petNameAboveBars and PET_LAYOUT.nameAboveGap
            or -(PET_LAYOUT.artY + PET_LAYOUT.nameBelowY)
        PetName:SetPoint(namePoint, PetFrame, "TOPLEFT",
            PET_LAYOUT.artX + PET_LAYOUT.nameX + PET_LAYOUT.nameW * 0.5, nameY)
        PetName:SetSize(PET_LAYOUT.nameW - 4, PET_LAYOUT.nameH)
        if d.showPetName then PetName:Show() else PetName:Hide() end
    end

    -- Pet auras use the same TurboFace-owned icon styling and shared settings
    -- as party auras, while remaining a separately gated Pet-frame surface.
    if buffContainer and debuffContainer then
        ns.PartyAuras.LayoutPetBuffs(PetFrame)
        ns.PartyAuras.LayoutPetDebuffs(PetFrame)
        ns.PartyAuras.UpdatePetBuffs(PetFrame)
        ns.PartyAuras.UpdatePetDebuffs(PetFrame)
    end

    -- The secure PetFrame keeps its native click/hover footprint. TurboFace
    -- changes presentation layers and bar geometry only.
end

-- =============================================================================
-- PARTY FRAMES
-- =============================================================================

-- Apply the fixed 119x48 party artwork (stored in a padded 128x64 texture) while retaining Blizzard's native unit
-- portrait and secure click/hover behavior. Bars render beneath the art, while
-- TurboFace-owned name/value strings render on a dedicated foreground layer.
-- Recursively zero every other Blizzard Texture/Model in the frame subtree.
local function HideUnitChrome(frame, skip)
    if not frame then return end
    local function kill(o)
        if not o then return end
        o:SetAlpha(0)
        if o.SetModelAlpha then o:SetModelAlpha(0) end
        if o.ClearModel    then o:ClearModel()     end
        if not o._srChromeKilled then
            o._srChromeKilled = true
            -- Pin alpha at 0: Blizzard re-renders portraits (SetPortraitTexture) and
            -- re-shows status art, so a one-shot SetAlpha(0) isn't enough.
            if o.SetAlpha then
                hooksecurefunc(o, "SetAlpha", function(s, a)
                    if a ~= 0 and not s._srChromeGuard then
                        s._srChromeGuard = true
                        s:SetAlpha(0)
                        s._srChromeGuard = false
                    end
                end)
            end
            if o.Show then
                hooksecurefunc(o, "Show", function(s) s:SetAlpha(0) end)
            end
        end
    end
    local function walk(f)
        if not f or skip[f] then return end
        if f.GetRegions then
            for _, r in ipairs({f:GetRegions()}) do
                if not skip[r] and r.GetObjectType and r:GetObjectType() == "Texture" then kill(r) end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({f:GetChildren()}) do
                if not skip[c] then
                    local ct = c.GetObjectType and c:GetObjectType()
                    if ct == "PlayerModel" or ct == "Model" then kill(c) else walk(c) end
                end
            end
        end
    end
    walk(frame)
end


local function EnsurePartyArtLayers(frame)
    local baseLevel = frame:GetFrameLevel() or 0

    local base = frame._tfPartyBaseLayer
    if not base then
        base = CreateFrame("Frame", nil, frame)
        base:EnableMouse(false)
        frame._tfPartyBaseLayer = base

        base.nameBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        base.healthBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
        base.powerBG = base:CreateTexture(nil, "BACKGROUND", nil, -7)
    end
    base:SetFrameStrata(frame:GetFrameStrata())
    base:SetFrameLevel(baseLevel + 1)
    base:ClearAllPoints()
    base:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY_LAYOUT.artX, -PARTY_LAYOUT.artY)
    base:SetSize(PARTY_LAYOUT.artW, PARTY_LAYOUT.artH)
    base:Show()

    local function PlaceBackground(texture, x, y, width, height)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", base, "TOPLEFT", x, -y)
        texture:SetSize(width, height)
        texture:SetColorTexture(0, 0, 0, 0.50)
        texture:SetAlpha(1)
        texture:Show()
    end
    PlaceBackground(base.nameBG, PARTY_LAYOUT.nameX, PARTY_LAYOUT.nameY, PARTY_LAYOUT.nameW, PARTY_LAYOUT.nameH)
    PlaceBackground(base.healthBG, PARTY_LAYOUT.healthX, PARTY_LAYOUT.healthY, PARTY_LAYOUT.healthW, PARTY_LAYOUT.healthH)
    PlaceBackground(base.powerBG, PARTY_LAYOUT.powerX, PARTY_LAYOUT.powerY, PARTY_LAYOUT.powerW, PARTY_LAYOUT.powerH)

    local artFrame = frame._tfPartyArtFrame
    if not artFrame then
        artFrame = CreateFrame("Frame", nil, frame)
        artFrame:EnableMouse(false)
        artFrame.texture = artFrame:CreateTexture(nil, "ARTWORK")
        artFrame.texture:SetAllPoints(artFrame)
        frame._tfPartyArtFrame = artFrame
    end
    artFrame:SetFrameStrata(frame:GetFrameStrata())
    artFrame:SetFrameLevel(baseLevel + 5)
    artFrame:ClearAllPoints()
    artFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY_LAYOUT.artX, -PARTY_LAYOUT.artY)
    artFrame:SetSize(PARTY_LAYOUT.artW, PARTY_LAYOUT.artH)
    artFrame.texture:SetTexture(PARTY_ART)
    -- The source art is padded to 128x64 for reliable WoW texture loading.
    -- Display only the original 119x48 painted region.
    artFrame.texture:SetTexCoord(0, 119 / 128, 0, 48 / 64)
    artFrame.texture:SetVertexColor(1, 1, 1, 1)
    artFrame.texture:SetAlpha(1)
    artFrame:Show()

    local textLayer = frame._tfPartyTextLayer
    if not textLayer then
        textLayer = CreateFrame("Frame", nil, frame)
        textLayer:EnableMouse(false)
        frame._tfPartyTextLayer = textLayer
    end
    textLayer:SetFrameStrata(frame:GetFrameStrata())
    textLayer:SetFrameLevel(baseLevel + 6)
    textLayer:ClearAllPoints()
    textLayer:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY_LAYOUT.artX, -PARTY_LAYOUT.artY)
    textLayer:SetSize(PARTY_LAYOUT.artW, PARTY_LAYOUT.artH)
    textLayer:Show()

    return base, artFrame, textLayer
end

local function EnsurePartyBarTextLayer(bar, frame)
    local layer = bar and bar._tfPartyTextLayer
    if not layer and bar then
        layer = CreateFrame("Frame", nil, bar)
        layer:EnableMouse(false)
        bar._tfPartyTextLayer = layer
    end
    if not layer then return nil end

    layer:SetAllPoints(bar)
    layer:SetFrameStrata(frame:GetFrameStrata())
    layer:SetFrameLevel((frame:GetFrameLevel() or 0) + 6)
    return layer
end

local function SuppressPartyNativeName(nameText)
    if not nameText or nameText._tfPartyNameSuppressed then return end
    nameText._tfPartyNameGuard = true
    nameText:SetAlpha(0)
    nameText._tfPartyNameGuard = false

    if nameText.SetAlpha then
        hooksecurefunc(nameText, "SetAlpha", function(self, alpha)
            if self._tfPartyNameGuard or alpha == 0 or not UnitFrameGate("party") then return end
            self._tfPartyNameGuard = true
            self:SetAlpha(0)
            self._tfPartyNameGuard = false
        end)
    end
    if nameText.Show then
        hooksecurefunc(nameText, "Show", function(self)
            if self._tfPartyNameGuard or not UnitFrameGate("party") then return end
            self._tfPartyNameGuard = true
            self:SetAlpha(0)
            self._tfPartyNameGuard = false
        end)
    end
    nameText._tfPartyNameSuppressed = true
end

local function UpdatePartyLeaderIcon(index, frame, textLayer)
    if not frame then return end
    local icon = frame._tfPartyLeaderIcon
    if not icon and textLayer then
        icon = textLayer:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", textLayer, "TOPLEFT", 16, 4)
        frame._tfPartyLeaderIcon = icon
    end
    if not icon then return end

    local unit = GetPartyMemberUnit(index, frame)
    if unit and UnitExists(unit) and UnitIsGroupLeader(unit) then
        icon:Show()
    else
        icon:Hide()
    end
end

local function ApplyPartyPortrait(frame, index, skip)
    local portrait = GetPartyPortrait(index, frame)
    if not portrait then return end
    skip[portrait] = true

    -- Pooled party-frame regions can retain Blizzard-applied local scaling.
    -- Normalize the portrait before applying fixed-art pixel geometry so its
    -- effective size matches the artwork rather than being scaled twice.
    if portrait.SetScale then portrait:SetScale(1) end
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PARTY_LAYOUT.artX + PARTY_LAYOUT.portraitX,
        -(PARTY_LAYOUT.artY + PARTY_LAYOUT.portraitY))
    portrait:SetSize(PARTY_LAYOUT.portraitW, PARTY_LAYOUT.portraitH)
    portrait:SetAlpha(1)
    portrait:Show()

    -- A mask is preferred when the client exposes MaskTexture support. The
    -- artwork itself still covers the square corners on older clients.
    if frame.CreateMaskTexture and portrait.AddMaskTexture then
        local mask = frame._tfPartyPortraitMask
        if not mask then
            mask = frame:CreateMaskTexture(nil, "ARTWORK")
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            portrait:AddMaskTexture(mask)
            frame._tfPartyPortraitMask = mask
        end
        mask:ClearAllPoints()
        mask:SetAllPoints(portrait)
        skip[mask] = true
    end
end

-- Party/Pet aura rendering is independently owned by PartyPetAuras.lua.

local function StyleOneParty(i, assignedFrame)
    local frame = assignedFrame or GetPartyMemberFrame(i)
    if not frame then return end
    -- Re-anchoring protected party bars is blocked in combat. Defer the complete
    -- fixed-art refresh until PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then UF._pendingParty = true; return end

    SafeSetScale(frame, d.partyScale or 1)
    local buffContainer = ns.PartyAuras.EnsureBuffContainer(frame)
    local debuffContainer = ns.PartyAuras.EnsureDebuffContainer(frame)
    if not UFGate("party") then
        if frame._tfPartyArtFrame then frame._tfPartyArtFrame:Hide() end
        if frame._tfPartyBaseLayer then frame._tfPartyBaseLayer:Hide() end
        if frame._tfPartyTextLayer then frame._tfPartyTextLayer:Hide() end
        if frame._tfPartyLeaderIcon then frame._tfPartyLeaderIcon:Hide() end
        if ns.NanShield and ns.NanShield.HidePartyFrame then
            ns.NanShield:HidePartyFrame(frame)
        end
        ns.PartyAuras.LayoutBuffs(frame)
        ns.PartyAuras.LayoutDebuffs(frame)
        return
    end

    local base, artFrame, textLayer = EnsurePartyArtLayers(frame)
    local hb = GetPartyHealthBar(i, frame)
    local mb = GetPartyManaBar(i, frame)
    local nativeName = GetPartyNameText(i, frame)

    -- Preserve the portrait, bars, and TurboFace-owned art/aura layers while
    -- parking Blizzard's old party-frame chrome and legacy aura regions.
    local skip = {
        [base] = true, [artFrame] = true, [textLayer] = true,
        [buffContainer] = true, [debuffContainer] = true,
    }
    if hb then skip[hb] = true end
    if mb then skip[mb] = true end
    if frame._tfPartyNanShield then skip[frame._tfPartyNanShield] = true end
    ApplyPartyPortrait(frame, i, skip)
    ns.PartyAuras.SuppressNativeAuras(frame, i, skip)
    HideUnitChrome(frame, skip)
    local nativeBG = GetPartyBackground(i, frame)
    if nativeBG then nativeBG:SetAlpha(0) end

    local baseLevel = frame:GetFrameLevel() or 0
    if hb then
        hb.forceHideText = true
        hb._tfUseOwnedCenterText = true
        hb._tfTextOwner = EnsurePartyBarTextLayer(hb, frame)
        barCenterTextCache[hb] = nil
        hb._tfTextSize = d.partyBarFontSize or 8
        hb._tfTextYOffset = 0
        hb._tfKind = "health"
        hb._tfPartyFixedArt = true
        hb:SetFrameStrata(frame:GetFrameStrata())
        hb:SetFrameLevel(baseLevel + 2)
        if hb.SetScale then hb:SetScale(1) end
        hb:SetStatusBarTexture(ns.ResolveStatusBarTexture(d.healthTexture or "Blizzard"))
        hb:SetAlpha(1)
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PARTY_LAYOUT.artX + PARTY_LAYOUT.healthX,
            -(PARTY_LAYOUT.artY + PARTY_LAYOUT.healthY))
        hb:SetSize(PARTY_LAYOUT.healthW, PARTY_LAYOUT.healthH)
        HideBarBackground(hb)
        base.healthBG:ClearAllPoints()
        base.healthBG:SetAllPoints(hb)
        base.healthBG:SetColorTexture(0, 0, 0, 0.50)
            SuppressBarSideTextsOnce(hb)
        StyleBarText(hb)
        ParkFixedArtBarChrome(hb)
        if not hb._tfPartyValueHooked then
            hb:HookScript("OnValueChanged", UpdateBarText)
            hb._tfPartyValueHooked = true
        end
        UpdateBarText(hb)
    end
    if mb then
        mb.forceHideText = true
        mb._tfUseOwnedCenterText = true
        mb._tfTextOwner = EnsurePartyBarTextLayer(mb, frame)
        barCenterTextCache[mb] = nil
        mb._tfTextSize = d.partyBarFontSize or 8
        mb._tfTextYOffset = 0
        mb._tfKind = "mana"
        mb._tfPartyFixedArt = true
        mb:SetFrameStrata(frame:GetFrameStrata())
        mb:SetFrameLevel(baseLevel + 2)
        if mb.SetScale then mb:SetScale(1) end
        mb:SetStatusBarTexture(ns.ResolveStatusBarTexture(d.manaTexture or "Blizzard"))
        mb:SetAlpha(1)
        mb:ClearAllPoints()
        mb:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PARTY_LAYOUT.artX + PARTY_LAYOUT.powerX,
            -(PARTY_LAYOUT.artY + PARTY_LAYOUT.powerY))
        mb:SetSize(PARTY_LAYOUT.powerW, PARTY_LAYOUT.powerH)
        HideBarBackground(mb)
        base.powerBG:ClearAllPoints()
        base.powerBG:SetAllPoints(mb)
        base.powerBG:SetColorTexture(0, 0, 0, 0.50)
        SuppressBarSideTextsOnce(mb)
        StyleBarText(mb)
        ParkFixedArtBarChrome(mb)
        if not mb._tfPartyValueHooked then
            mb:HookScript("OnValueChanged", UpdateBarText)
            mb._tfPartyValueHooked = true
        end
        UpdateBarText(mb)
    end

    SuppressPartyNativeName(nativeName)
    local nameText = frame._tfPartyNameText
    if not nameText then
        nameText = textLayer:CreateFontString(nil, "OVERLAY")
        frame._tfPartyNameText = nameText
    end
    StyleUnitFrameName(nameText, d.partyNameFontSize or 9)
    SetTextColor(nameText, d.partyNameColor)
    if nameText.SetJustifyH then nameText:SetJustifyH("CENTER") end
    if nameText.SetJustifyV then nameText:SetJustifyV("MIDDLE") end
    if nameText.SetWordWrap then nameText:SetWordWrap(false) end
    if nameText.SetNonSpaceWrap then nameText:SetNonSpaceWrap(false) end
    nameText:ClearAllPoints()
    nameText:SetPoint("TOPLEFT", textLayer, "TOPLEFT",
        PARTY_LAYOUT.nameX,
        -PARTY_LAYOUT.nameY)
    nameText:SetSize(PARTY_LAYOUT.nameW, PARTY_LAYOUT.nameH)
    RefreshPartyOwnedName(i, frame)
    if d.showPartyNames then nameText:Show() else nameText:Hide() end
    UpdatePartyLeaderIcon(i, frame, textLayer)

    ns.PartyAuras.LayoutBuffs(frame)
    ns.PartyAuras.LayoutDebuffs(frame)
    if ns.NanShield and ns.NanShield.PreparePartyFrame then
        ns.NanShield:PreparePartyFrame(frame, i)
    end

    -- Keep Blizzard's full secure hover/click area. The fixed art is visual only.
end


local function InitParty()
    if not UFGate("party") then return end
    for i = 1, 4 do
        local frame = GetPartyMemberFrame(i)
        StyleOneParty(i)
        ns.PartyAuras.UpdateBuffs(frame)
        ns.PartyAuras.UpdateDebuffs(frame)
    end

    if not UF._partyHooked then
        -- Blizzard re-anchors a member's bars whenever it refreshes (join/leave/role
        -- change), so re-apply our layout right after.
        local function OnMemberUpdate(self)
            local index = GetPartyMemberIndex(self)
            if index then
                StyleOneParty(index, self)
                ns.PartyAuras.UpdateBuffs(self)
                ns.PartyAuras.UpdateDebuffs(self)
            end
        end
        -- 1.15.9 creates PartyFrame members from a pool. Hook the mixin so
        -- every acquired member is restyled after Blizzard refreshes it, and
        -- hook pool initialization so the first set is styled after creation.
        if type(PartyMemberFrameMixin) == "table" and type(PartyMemberFrameMixin.UpdateMember) == "function" then
            hooksecurefunc(PartyMemberFrameMixin, "UpdateMember", OnMemberUpdate)
        elseif type(PartyMemberFrame_UpdateMember) == "function" then
            hooksecurefunc("PartyMemberFrame_UpdateMember", OnMemberUpdate)
        else
            for i = 1, 4 do
                local f = GetPartyMemberFrame(i)
                if f and type(f.UpdateMember) == "function" then
                    hooksecurefunc(f, "UpdateMember", OnMemberUpdate)
                end
            end
        end

        if PartyFrame and type(PartyFrame.InitializePartyMemberFrames) == "function" then
            hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", function()
                C_Timer.After(0, InitParty)
            end)
        end

        -- Party aura freshness is owned independently by PartyPetAuras.lua. Blizzard
        -- UpdateMember hooks above remain UnitFrame layout/reassignment hooks only.


        UF._partyHooked = true
    end
end

-- =============================================================================
-- HEALTH COLOR
-- =============================================================================

local function UpdateHealthColor(unit)
    if unit == "player" then
        if not UFGate("player") then return end
        SetHealthColor(PlayerFrameHealthBar, "player")
    elseif unit == "target" then
        if not UFGate("target") then return end
        SetHealthColor(TargetFrameHealthBar, "target")
    elseif unit == "pet" then
        if not UFGate("pet") then return end
        SetHealthColor(PetFrameHealthBar, "pet")
    else
        if not UFGate("party") then return end
        for i = 1, 4 do
            if unit == "party" .. i then
                local hb = GetPartyHealthBar(i)
                if hb then SetHealthColor(hb, unit) end
                break
            end
        end
    end
end

-- =============================================================================
-- INIT & EVENTS
-- =============================================================================

-- Unit-frame runtime event frames are created only when the family is enabled.
-- A profile that disables TurboFace Unit Frames should not allocate inert
-- helper frames merely because this file is present in the TOC.
local eventFrame, partyHealthEventFrame, totHealthEventFrame

local function EnsureUnitFrameEventFrames()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    partyHealthEventFrame = CreateFrame("Frame")
    totHealthEventFrame = CreateFrame("Frame")
end

-- Target-frame combo points are Blizzard-owned. TurboFace's optional combo-dot
-- renderer lives on nameplates (NameplateVisuals.lua); the old custom target
-- frame implementation was permanently disabled and has been removed.

function UF:Init()
    -- Whole-family opt-out: leave every Blizzard unit frame exactly as shipped.
    if not UFGate(nil) then return end
    -- Seed Unit Frame defaults into TurboFaceDB.
    if not TurboFaceDB.unitframes then TurboFaceDB.unitframes = {} end
    local db = TurboFaceDB.unitframes
    local defaults = ns.defaults.unitframes
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                for k2, v2 in pairs(v) do db[k][k2] = v2 end
            else
                db[k] = v
            end
        end
    end

    RefreshDBCache()
    SetAllBarTextures()
    InitPlayer()
    InitTarget()
    InitToT()
    InitPet()
    InitParty()

    for _, unit in ipairs(COLOR_REFRESH_UNITS) do
        UpdateHealthColor(unit)
    end

    EnsureUnitFrameEventFrames()

    -- Events. Player/target/pet health colors are owned by the secure post-hooks
    -- below; only party health needs an explicit unit event fallback.
    if eventFrame.RegisterUnitEvent then
        -- Classic's supported contract is two unit tokens per registration. Split
        -- this hot event across three inert helper frames rather than relying on
        -- undocumented extra arguments or waking Lua for every unit's health.
        eventFrame:RegisterUnitEvent("UNIT_HEALTH", "party1", "party2")
        partyHealthEventFrame:RegisterUnitEvent("UNIT_HEALTH", "party3", "party4")
        totHealthEventFrame:RegisterUnitEvent("UNIT_HEALTH", "targettarget")
    else
        eventFrame:RegisterEvent("UNIT_HEALTH")
    end
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    if eventFrame.RegisterUnitEvent then
        eventFrame:RegisterUnitEvent("UNIT_TARGET", "target")
    else
        eventFrame:RegisterEvent("UNIT_TARGET")
    end
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    -- Party names can arrive asynchronously after the pooled member frame was
    -- first styled. Refresh the owned name when the client reports it ready.
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
    eventFrame:RegisterEvent("UNIT_FACTION")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Target XP estimate triggers
    ns.RegisterUnitEvent(eventFrame, "UNIT_LEVEL", "target", "player")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
    eventFrame:RegisterEvent("UPDATE_EXHAUSTION")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")  -- druid player-art/form transition
    if eventFrame.RegisterUnitEvent then
        eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "target", "targettarget")
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "target", "targettarget")
        eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "target", "targettarget")
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "targettarget")
    else
        eventFrame:RegisterEvent("UNIT_MAXHEALTH")
        eventFrame:RegisterEvent("UNIT_MAXPOWER")
        eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
        eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
    end

    local function UnitFrameOnEvent(self, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            if UFGate("target") then ApplyTargetFrameArtTexture() end
            UpdateHealthColor("target")
            UpdateTargetXP()
            UF.ApplyTargetTagState()
            RefreshTargetValueText()
            RefreshLevelBadges()
            ns._totStyleDirty = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0, InitToT)
            else
                InitToT()
            end
            if UFGate("target") and TargetFrameNameBackground then
                TargetFrameNameBackground:SetVertexColor(0, 0, 0, 0)
                TargetFrameNameBackground:SetHeight(18)
            end
        elseif event == "UNIT_TARGET" and unit == "target" then
            ns._totStyleDirty = true
            if C_Timer and C_Timer.After then
                C_Timer.After(0, InitToT)
            else
                InitToT()
            end
        elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE"
            or event == "UPDATE_EXHAUSTION" then
            if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
                ns.CPUProfiler:MeasureKillNoReturn("UnitFrames:UpdateTargetXP", UpdateTargetXP)
            else
                UpdateTargetXP()
            end
            if event == "PLAYER_LEVEL_UP" then RefreshLevelBadges() end
        elseif event == "UNIT_LEVEL" then
            if unit == "target" or unit == "player" then
                UpdateTargetXP()
                RefreshLevelBadges()
            end
        elseif event == "UPDATE_SHAPESHIFT_FORM" then
            -- Cat/bear swaps the player sheet, which changes the bar geometry
            -- AND pushes the attack/cast row down a slot. Re-apply art, bars,
            -- and the compact timer stack together so they cannot disagree.
            -- Guarded on an actual change: UPDATE_SHAPESHIFT_FORM fires for
            -- every form, including ones that do not alter the art.
            if PLAYER_IS_DRUID then
                local nowDruidArt = UseDruidArt()
                if nowDruidArt ~= _lastDruidArt then
                    _lastDruidArt = nowDruidArt
                    ApplyPlayerFrameArtTexture()
                    ApplyPlayerBarGeometry()
                    if ns.DruidPowerBar and ns.DruidPowerBar.Refresh then
                        ns.DruidPowerBar:Refresh()
                    end
                    if ns.ST and ns.ST.ReanchorPlayer then ns.ST:ReanchorPlayer() end
                end
            end
        elseif (event == "UNIT_MAXHEALTH" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER") then
            if unit == "target" then
                RefreshTargetValueText()
            elseif unit == "targettarget" then
                RefreshToTValueText()
            end
        elseif event == "UNIT_POWER_UPDATE" and unit == "targettarget" then
            RefreshToTValueText()
        elseif event == "UNIT_NAME_UPDATE" and unit and unit:match("^party[1-4]$") then
            -- Resolve by Blizzard's assigned unit first: a pooled frame's
            -- layoutIndex describes placement, not necessarily roster identity.
            local fallbackIndex = tonumber(unit:match("^party([1-4])$"))
            local matched = false
            for index = 1, 4 do
                local frame = GetPartyMemberFrame(index)
                if frame and frame.unit == unit then
                    if not RefreshPartyOwnedName(index, frame, unit) then
                        if InCombatLockdown() then
                            UF._pendingParty = true
                        else
                            StyleOneParty(index, frame)
                        end
                    end
                    matched = true
                    break
                end
            end
            if not matched and fallbackIndex then
                local frame = GetPartyMemberFrame(fallbackIndex)
                if frame and not RefreshPartyOwnedName(fallbackIndex, frame, unit) then
                    if InCombatLockdown() then
                        UF._pendingParty = true
                    else
                        StyleOneParty(fallbackIndex, frame)
                    end
                end
            end
        elseif event == "PARTY_LEADER_CHANGED" then
            for index = 1, 4 do
                local frame = GetPartyMemberFrame(index)
                UpdatePartyLeaderIcon(index, frame, frame and frame._tfPartyTextLayer)
            end
        elseif event == "UNIT_HEALTH" and unit then
            if unit:match("^party[1-4]$") then
                UpdateHealthColor(unit)
            elseif unit == "targettarget" then
                RefreshToTValueText()
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_FACTION" then
            for _, u in ipairs(COLOR_REFRESH_UNITS) do
                UpdateHealthColor(u)
            end
            if event == "GROUP_ROSTER_UPDATE" then
                -- Blizzard may acquire/release pooled party members after the
                -- roster event itself. Re-run the fixed-art pass on the next
                -- frame so newly created members cannot miss initialization.
                ns.PartyAuras.UpdateAll()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, InitParty)
                else
                    InitParty()
                end
            end
            if event == "UNIT_FACTION" then
                UpdateTargetXP()          -- attackability may have changed
                UF.ApplyTargetTagState()     -- tap-denied state may have changed
            end
            if UFGate("target") and TargetFrameNameBackground then
                TargetFrameNameBackground:SetVertexColor(0, 0, 0, 0)
                TargetFrameNameBackground:SetHeight(18)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            SetAllBarTextures()
            InitPlayer()
            InitTarget()
            InitToT()
            InitParty()
            UpdateTargetXP()
        
            -- Blizzard performs additional PlayerFrame status-text updates during
            -- the first frame after entering the world. Reassert TurboFace's owned
            -- player text overlays after that startup pass so the saved per-bar
            -- formats are visible immediately after login or /reload.
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    SetFrameArtTextures()
                    ApplyPlayerBarGeometry()
                    -- PartyFrame's pool can finish acquiring members after the
                    -- initial PLAYER_ENTERING_WORLD pass.
                    InitParty()
                    if UFGate("player") then
                        SuppressNativeCenterText(PlayerFrameHealthBar)
                        SuppressNativeCenterText(PlayerFrameManaBar)
                        StyleBarText(PlayerFrameHealthBar)
                        StyleBarText(PlayerFrameManaBar)
                        PlayerFrameHealthBar._tfCur, PlayerFrameHealthBar._tfMax, PlayerFrameHealthBar._tfFmt = nil, nil, nil
                        PlayerFrameManaBar._tfCur, PlayerFrameManaBar._tfMax, PlayerFrameManaBar._tfFmt = nil, nil, nil
                        UpdateBarText(PlayerFrameHealthBar)
                        UpdateBarText(PlayerFrameManaBar)
                    end
                    RefreshLevelBadges()
                    -- One-shot border re-apply after the first frame: every
                    -- bar (including swing rows sized from config after
                    -- creation) now has its final height, so AttachBarBorder's
                    -- height clamp resolves the configured edge size instead
                    -- of one derived from pre-layout defaults.
                    if ns.ReapplySharedBorders then ns:ReapplySharedBorders() end
                end)
            else
                if UFGate("player") then
                    UpdateBarText(PlayerFrameHealthBar)
                    UpdateBarText(PlayerFrameManaBar)
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Apply any settings change / party relayout deferred during combat.
            if UF._pendingRefresh then
                UF._pendingRefresh = false
                UF._pendingParty = false   -- a full refresh re-inits the party too
                UF:Refresh()
            elseif UF._pendingParty then
                UF._pendingParty = false
                InitParty()
            end
        end
    end
    eventFrame:SetScript("OnEvent", UnitFrameOnEvent)
    partyHealthEventFrame:SetScript("OnEvent", UnitFrameOnEvent)
    totHealthEventFrame:SetScript("OnEvent", UnitFrameOnEvent)

    -- TextStatusBar hooks — update center text only, side texts suppressed at
    -- init. Classic exposes both global and mixin paths on some builds, so Target
    -- bars also receive direct method/value hooks even when the global exists.
    local function HookBarTextMethod(bar)
        if not bar or bar._tfTextMethodHooked then return end
        if type(bar.UpdateTextStringWithValues) == "function" then
            hooksecurefunc(bar, "UpdateTextStringWithValues", UpdateBarText)
            bar._tfTextMethodHooked = true
        elseif type(bar.UpdateTextString) == "function" then
            hooksecurefunc(bar, "UpdateTextString", UpdateBarText)
            bar._tfTextMethodHooked = true
        end
    end

    local textBars = {}
    local function addBar(bar) if bar then textBars[#textBars + 1] = bar end end
    if UFGate("player") then addBar(PlayerFrameHealthBar); addBar(PlayerFrameManaBar) end
    if UFGate("target") then addBar(TargetFrameHealthBar); addBar(TargetFrameManaBar) end
    if UFGate("pet") then addBar(PetFrameHealthBar); addBar(PetFrameManaBar) end
    if UFGate("tot") then addBar(TargetFrameToTHealthBar); addBar(TargetFrameToTManaBar) end
    if UFGate("party") then
        for i = 1, 4 do
            addBar(GetPartyHealthBar(i))
            addBar(GetPartyManaBar(i))
        end
    end

    if type(TextStatusBar_UpdateTextStringWithValues) == "function" then
        hooksecurefunc("TextStatusBar_UpdateTextStringWithValues", UpdateBarText)
        if type(TextStatusBar_UpdateTextString) == "function" then
            hooksecurefunc("TextStatusBar_UpdateTextString", UpdateBarText)
        end
    else
        for _, bar in ipairs(textBars) do HookBarTextMethod(bar) end
    end

    -- 1.15.9 can retain the legacy globals while Target/ToT update through their
    -- TextStatusBar methods. Always hook both directly so owned overlays stay
    -- current regardless of which Blizzard path is active.
    local directTextBars = {}
    local function addDirectBar(bar) if bar then directTextBars[#directTextBars + 1] = bar end end
    if UFGate("target") then
        addDirectBar(TargetFrameHealthBar); addDirectBar(TargetFrameManaBar)
    end
    if UFGate("tot") then
        addDirectBar(TargetFrameToTHealthBar); addDirectBar(TargetFrameToTManaBar)
    end
    for _, bar in ipairs(directTextBars) do
        if bar then
            HookBarTextMethod(bar)
            if not bar._tfValueTextHooked then
                bar:HookScript("OnValueChanged", UpdateBarText)
                bar._tfValueTextHooked = true
            end
        end
    end

    -- Blizzard resets the health bar color (to its default green) on every health
    -- change, which in combat happens constantly and clobbers our color. Re-apply
    -- our color AFTER Blizzard, but only on the bars we manage so we don't disturb
    -- party/raid frames.
    if not UF._healthColorHooked then
        local managed = {}
        if UFGate("player") and PlayerFrameHealthBar then managed[PlayerFrameHealthBar] = true end
        if UFGate("target") and TargetFrameHealthBar then managed[TargetFrameHealthBar] = true end
        if UFGate("pet") and PetFrameHealthBar then managed[PetFrameHealthBar] = true end
        local function reapply(bar)
            if bar and managed[bar] and bar.unit then SetHealthColor(bar, bar.unit) end
        end
        ns.RegisterCPUProfileTarget("UnitFrames/Hooks:HealthColor", reapply)
        if UnitFrameHealthBar_Update or UnitFrameHealthBar_OnValueChanged then
            if UnitFrameHealthBar_Update          then hooksecurefunc("UnitFrameHealthBar_Update", reapply) end
            if UnitFrameHealthBar_OnValueChanged  then hooksecurefunc("UnitFrameHealthBar_OnValueChanged", reapply) end
        else
            -- Globals gone (mixin client): post-hook the script path instead.
            -- HookScript is a secure post-hook, so this is as taint-safe as the
            -- hooksecurefunc form.
            for bar in pairs(managed) do
                bar:HookScript("OnValueChanged", reapply)
            end
        end
        UF._healthColorHooked = true
    end

    -- Blizzard re-applies the default mana-bar texture on power updates -- for the
    -- target and target-of-target this happens constantly (enemies regen / cast),
    -- so our configured texture flashes in then reverts to Blizzard's. Re-assert
    -- it on managed mana bars: the SetStatusBarTexture hook catches direct texture
    -- swaps, and the power-update hooks catch any reset riding along with a power
    -- change. (SetStatusBarTexture is cosmetic, so this is taint-safe on the
    -- secure target/ToT bars, same as the health-color hook above.)
    if not UF._manaTextureHooked then
        local managedMana = {}
        local function track(bar) if bar then managedMana[bar] = true end end
        if UFGate("player") then track(PlayerFrameManaBar) end
        if UFGate("target") then track(TargetFrameManaBar) end
        if UFGate("pet") then track(PetFrameManaBar) end
        if UFGate("tot") then track(TargetFrameToTManaBar) end
        if UFGate("party") then for i = 1, 4 do track(GetPartyManaBar(i)) end end

        local function reassert(bar)
            if not bar or not managedMana[bar] or bar._srManaTexGuard then return end
            local cfg = d or (TurboFaceDB and TurboFaceDB.unitframes) or {}
            bar._srManaTexGuard = true
            bar:SetStatusBarTexture(ns.ResolveStatusBarTexture(cfg.manaTexture or "Blizzard"))
            bar._srManaTexGuard = false
        end
        ns.RegisterCPUProfileTarget("UnitFrames/Hooks:ManaTexture", reassert)

        for bar in pairs(managedMana) do
            if bar.SetStatusBarTexture then
                hooksecurefunc(bar, "SetStatusBarTexture", function(self) reassert(self) end)
            end
        end
        if UnitFrameManaBar_Update     then hooksecurefunc("UnitFrameManaBar_Update", reassert)     end
        if UnitFrameManaBar_UpdateType then hooksecurefunc("UnitFrameManaBar_UpdateType", reassert) end
        UF._manaTextureHooked = true
    end
end

-- =============================================================================
-- REFRESH (called from OptionsGUI ApplySettings)
-- =============================================================================

-- Re-apply just the player bar-stack backdrop (and hit-rect). Called by the
-- Druid power bar when it shows/hides so the backdrop re-wraps the stack without
-- a full, combat-blocked UF:Refresh.
function UF:RefreshPlayerBackdrop()
    ApplyPlayerBackdrop()
end

-- Lightweight refresh for ClassBuffs settings/spellbook changes. This avoids a
-- full protected unit-frame re-layout when only the reminder set changed.
function UF:RefreshPartyAuras()
    if not d and TurboFaceDB and TurboFaceDB.unitframes then
        RefreshDBCache()
    end
    if not d then return end
    ns.PartyAuras.UpdateAll()
end

function UF:Refresh()
    if not UFGate(nil) then return end
    -- Re-laying out the Blizzard player/target/pet/party frames re-anchors protected
    -- frames (ClearAllPoints/SetPoint), which is blocked in combat. Defer the whole
    -- refresh to combat end if we're locked down (e.g. changing settings mid-fight).
    if InCombatLockdown() then
        UF._pendingRefresh = true
        return
    end
    UF._pendingRefresh = false
    RefreshDBCache()
    barCenterTextCache = {}  -- clear cache so font changes take effect
    SetAllBarTextures()
    -- The druid power row now takes its texture from unitframes.manaTexture, so
    -- it must restyle from the Unit Frames apply path too -- not just the Class
    -- tab's RefreshClassOptions, which is where it used to be driven from.
    if ns.DruidPowerBar and ns.DruidPowerBar.Refresh then ns.DruidPowerBar:Refresh() end
    InitPlayer()
    InitTarget()
    InitToT()
    InitPet()
    InitParty()
    for _, unit in ipairs(COLOR_REFRESH_UNITS) do
        UpdateHealthColor(unit)
    end
    -- Backdrops were just re-applied with the bright default border; restore the
    -- tagged grey if the current target is tap-denied.
    UF.ApplyTargetTagState()
    if ns.NanShield then ns.NanShield:Refresh() end   -- absorb bar tracks bar width/settings
end

ns.UF = UF

ns.RegisterCPUProfileTarget("UnitFrames/Core:Events", UnitFrameOnEvent)
ns.RegisterCPUProfileTarget("UnitFrames/Text:UpdateBarText", UpdateBarText)
ns.RegisterCPUProfileTarget("UnitFrames/Text:RefreshTarget", RefreshTargetValueText)
ns.RegisterCPUProfileTarget("UnitFrames/Text:RefreshToT", RefreshToTValueText)
ns.RegisterCPUProfileTarget("UnitFrames/PlayerStatus:SyncGlow", SyncPlayerNameStatusGlow, false)
ns.RegisterCPUProfileTarget("UnitFrames/PlayerStatus:GlowAlpha", SyncPlayerNameStatusGlowAlpha, false)
ns.RegisterCPUProfileTarget("UnitFrames/PlayerStatus:GlowColor", SyncPlayerNameStatusGlowColor, false)
ns.RegisterCPUProfileTarget("UnitFrames/PlayerStatus:GlowShow", SyncPlayerNameStatusGlowShow, false)
ns.RegisterCPUProfileTarget("UnitFrames/PlayerStatus:GlowHide", SyncPlayerNameStatusGlowHide, false)
