local _, ns = ...

-- =============================================================================
-- TurboFace Aura Styling (Misc)
-- Adds a cooldown swipe + countdown timer text to PLAYER and TARGET buff/debuff
-- icons, plus a per-group scale. Durations come from the embedded
-- LibClassicDurations, so this replaces the OmniCC + ClassicAuraDurations combo.
--
-- Approach: restyle Blizzard's own aura buttons in place; TurboFace Movers can
-- position them. For the target frame we hook TargetFrame_UpdateAuras (the
-- same entry point ClassicAuraDurations used); for the player buff bar -- which
-- ClassicAuraDurations never touched, hence "it only worked on the target" -- we
-- walk the BuffButton/DebuffButton frames on UNIT_AURA.
-- =============================================================================

local AS = {}
ns.AuraStyle = AS
local initialized = false
local runtimeActive = false

local LCD = LibStub and LibStub("LibClassicDurations", true)

local CooldownFrame_Set   = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear
local UnitBuff, UnitDebuff = ns.API.UnitBuff, ns.API.UnitDebuff
local GetWeaponEnchantInfo = ns.API.GetWeaponEnchantInfo
local GetTime  = GetTime
local floor, ceil = math.floor, math.ceil
local _G = _G

local function AuraDataReadable()
    return not (ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret())
end


-- Buttons currently showing a timed aura -> their expiration time. The ticker
-- below updates their timer text from this.
local active = {}

-- Temporary weapon enchants (shaman imbues, sharpening/weapon stones, oils) are
-- a separate system: GetWeaponEnchantInfo() gives REMAINING time, not a total
-- duration. We derive a stable expiration timestamp per slot and remember a
-- duration estimate (refreshed when the enchant is reapplied) so the swipe
-- drains correctly and the change-guard doesn't re-fire every poll.
local tempExp, tempDur = {}, {}

-- Bumped whenever timer-font settings change, so ApplyTimerFont only calls
-- SetFont when it actually needs to (not on every style pass).
local fontGen = 0

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local function C() return TurboFaceDB or {} end
local function AuraDB()
    local db = C()
    return type(db.auras) == "table" and db.auras or {}
end
-- AuraStyle owns two independent consumers behind the Auras family master:
-- normal Player/Target styling keeps the historical auraEnabled opt-in, while
-- Target-of-Target debuffs use their own modules.auras.tot child gate.
local function AuraFamilyEnabled()
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("auras")
end
local function PlayerTargetEnabled()
    return AuraFamilyEnabled() and C().auraEnabled == true
end
local function ToTEnabled()
    return AuraFamilyEnabled() and ((not ns.ModuleEnabled) or ns.ModuleEnabled("auras", "tot"))
end
local function RuntimeNeeded()
    return PlayerTargetEnabled() or ToTEnabled()
end
local function ShowSwipe() return C().auraShowSwipe ~= false end
local function ShowTimer() return C().auraShowTimer ~= false end

-- When Movers are disabled, Blizzard owns the aura chains. Apply one small
-- presentation correction to the chain root only; every later button follows
-- that root through Blizzard's existing anchors. Remember the applied points
-- so repeated target/ToT refreshes cannot accumulate the offset. If Blizzard
-- rebuilds the root anchors, the mismatch lets us reapply exactly once.
local TARGET_BLIZZARD_AURA_NUDGE_X = 3
local TOT_BLIZZARD_DEBUFF_NUDGE_X = 1

local function AnchorPointsMatch(button, expected)
    if not expected or not button.GetNumPoints or not button.GetPoint then return false end
    if button:GetNumPoints() ~= #expected then return false end
    for i = 1, #expected do
        local point, relativeTo, relativePoint, x, y = button:GetPoint(i)
        local saved = expected[i]
        if point ~= saved[1] or relativeTo ~= saved[2] or relativePoint ~= saved[3]
            or (x or 0) ~= saved[4] or (y or 0) ~= saved[5]
        then
            return false
        end
    end
    return true
end

local function SetAnchorPoints(button, points)
    button:ClearAllPoints()
    for i = 1, #points do button:SetPoint(unpack(points[i])) end
end

local function ReleaseBlizzardAuraNudge(button)
    local state = button and button._tfBlizzardAuraNudgeState
    if not state then return end
    -- Undo only our still-intact points. If Blizzard or Movers already rebuilt
    -- the anchors, their newer ownership wins and there is nothing to restore.
    if AnchorPointsMatch(button, state.applied) then
        SetAnchorPoints(button, state.original)
    end
    button._tfBlizzardAuraNudgeState = nil
end

local function MoversOwnAuraPosition(elementID)
    if not ns.MoversEnabled or not ns.MoversEnabled() then return false end
    local movers = C().movers
    if type(movers) ~= "table" then return true end
    if movers.auraLayout == false then return false end
    local elements = movers.elements
    local element = type(elements) == "table" and elements[elementID] or nil
    return type(element) ~= "table" or element.enabled ~= false
end

local function NudgeBlizzardAuraRoot(button, elementID, inheritedNudge, nudgeX)
    if MoversOwnAuraPosition(elementID) or inheritedNudge then
        ReleaseBlizzardAuraNudge(button)
        return false
    end
    if not button or not button.GetNumPoints or not button.GetPoint
        or not button.ClearAllPoints or not button.SetPoint
    then
        return
    end
    nudgeX = nudgeX or TARGET_BLIZZARD_AURA_NUDGE_X
    local state = button._tfBlizzardAuraNudgeState
    if state and state.nudgeX ~= nudgeX then
        ReleaseBlizzardAuraNudge(button)
        state = nil
    end
    if state and AnchorPointsMatch(button, state.applied) then return true end

    local count = button:GetNumPoints()
    if count < 1 then return false end
    local original = {}
    local nudged = {}
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = button:GetPoint(i)
        original[i] = { point, relativeTo, relativePoint, x or 0, y or 0 }
        nudged[i] = { point, relativeTo, relativePoint, (x or 0) + nudgeX, y or 0 }
    end
    SetAnchorPoints(button, nudged)
    button._tfBlizzardAuraNudgeState = {
        original = original,
        applied = nudged,
        nudgeX = nudgeX,
    }
    return true
end


-- ---------------------------------------------------------------------------
-- Time formatting, matched to Blizzard's aura duration behavior:
--  * CEILING rounding -- 2:30 left reads "3m" (Blizzard never rounds down).
--  * Seconds only start below 90s (Blizzard shows "2m" at 90.1, "90" at 90).
-- Second return is time until the text next changes (ticker redraw hint).
-- ---------------------------------------------------------------------------
local function FormatTime(s)
    if s >= 3600 then
        return ceil(s / 3600) .. "h", s % 3600
    elseif s >= 90 then
        return ceil(s / 60) .. "m", s % 60
    elseif s > 0 then
        return ceil(s) .. "", s % 1
    end
    return "", 0
end

-- ---------------------------------------------------------------------------
-- Duration resolution (fill in missing durations via LibClassicDurations)
-- ---------------------------------------------------------------------------
local function ResolveDuration(unit, spellId, caster, duration, expirationTime)
    if (not duration or duration == 0) and LCD and spellId then
        local ok, d, e = pcall(LCD.GetAuraDurationByUnit, LCD, unit, spellId, caster)
        if ok and d and d > 0 then
            return d, e
        end
    end
    return duration, expirationTime
end

-- ---------------------------------------------------------------------------
-- Per-button widgets
-- ---------------------------------------------------------------------------
-- The region our swipe/text should cover. Legacy buttons are icon-sized, but
-- the 1.15.9 retail-import buttons are TALLER than their icon: the button
-- frame reserves a text zone underneath for Blizzard's duration. Anchoring to
-- the whole button there stretches the swipe over that zone and drops the
-- timer below the icon, so prefer the Icon region whenever the button has one.
local function IconRegion(button)
    return button.Icon or button.icon or button
end

local function GetCooldown(button)
    -- Prefer Blizzard's existing cooldown frame (target buttons have one named
    -- <button>Cooldown); otherwise create our own once. The template name varies
    -- between clients, so create defensively and fall back to a bare Cooldown --
    -- this is exactly why the target worked (existing frame) but the player did
    -- not (created frame erroring on a missing template).
    if button._tfCD then return button._tfCD end
    local name = button.GetName and button:GetName()
    local cd = button.cooldown or button.Cooldown or (name and _G[name .. "Cooldown"])
    if not cd then
        local ok, made = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
        if not ok or not made then
            ok, made = pcall(CreateFrame, "Cooldown", nil, button)
        end
        if made then
            made:SetAllPoints(IconRegion(button))
            if made.SetDrawEdge then made:SetDrawEdge(false) end
            if made.SetSwipeColor then made:SetSwipeColor(0, 0, 0, 0.7) end
            -- Match the target buttons' aura swipe direction. Blizzard's existing
            -- cooldown frames (used by the target) already wind down correctly;
            -- a freshly created frame defaults to the ability-cooldown direction,
            -- which looks reversed for an aura, so flip it.
            if made.SetReverse then made:SetReverse(true) end
        end
        cd = made
    end
    button._tfCD = cd
    return cd
end

local function GetTimerFS(button, cd)
    if button._tfTimer then return button._tfTimer end
    -- Text must sit ABOVE the cooldown swipe. A FontString on the button (or on
    -- the cooldown frame) renders under the swipe, so give it its own frame with
    -- a higher frame level than the cooldown.
    local tf = CreateFrame("Frame", nil, button)
    tf:SetAllPoints(IconRegion(button))
    local base = button:GetFrameLevel() or 1
    if cd and cd.GetFrameLevel then
        local cl = cd:GetFrameLevel()
        if cl and cl > base then base = cl end
    end
    tf:SetFrameLevel(base + 5)
    local fs = tf:CreateFontString(nil, "OVERLAY")
    -- Countdown sits along the bottom edge, just inside the icon.
    fs:SetPoint("BOTTOM", IconRegion(button), "BOTTOM", 0, 1)
    button._tfTextFrame = tf
    button._tfTimer = fs
    return fs
end

-- Effective button scale, for counter-scaling text. SetScale scales every
-- child region, so a 135% button would also blow up the timer/count text;
-- dividing the font size by the scale keeps text the same visual size on
-- player (1.0) and target (e.g. 1.35) auras.
local function ButtonScale(button)
    local s = (button.GetScale and button:GetScale()) or 1
    if not s or s <= 0 then s = 1 end
    return s
end

local function ApplyTimerFont(button, sizeOffset)
    if not button._tfTimer then return end
    local s = ButtonScale(button)
    sizeOffset = sizeOffset or 0
    if button._tfFontGen == fontGen and button._tfFontScale == s
        and button._tfFontOffset == sizeOffset
    then
        return
    end
    button._tfFontGen = fontGen
    button._tfFontScale = s
    button._tfFontOffset = sizeOffset
    local size = ((C().auraTimerSize or 14) + sizeOffset) / s
    ns:StyleFont(button._tfTimer, nil, size, "auras")
end

-- Catch Blizzard's stack-count FontString (e.g. Lightning Shield's charges),
-- move it to the top-right corner, lift it above the cooldown swipe, and put it
-- under our font styling. We only restyle/reposition -- Blizzard still owns the
-- text content and its show/hide (it hides the count when <= 1).
local function GetCountFS(button)
    if button._tfCount ~= nil then return button._tfCount or nil end
    local nm = button.GetName and button:GetName()
    local cnt = button.count or button.Count or (nm and _G[nm .. "Count"])
    button._tfCount = cnt or false
    return cnt or nil
end

local function StyleCount(button)
    local cnt = GetCountFS(button)
    if not cnt then return end
    -- Re-parent onto our text frame (above the swipe) and pin to the top-right.
    if button._tfTextFrame and cnt.GetParent and cnt:GetParent() ~= button._tfTextFrame then
        cnt:SetParent(button._tfTextFrame)
    end
    cnt:ClearAllPoints()
    cnt:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    -- Guarded so SetFont only runs when the timer-font settings or the button
    -- scale actually change. Counter-scaled like the timer text.
    local s = ButtonScale(button)
    if button._tfCountGen ~= fontGen or button._tfCountScale ~= s then
        button._tfCountGen = fontGen
        button._tfCountScale = s
        local size = math.max(8, C().auraTimerSize or 14) / s
        ns:StyleFont(cnt, nil, size, "auras")
    end
end

-- Hide Blizzard's own duration text below the PLAYER buff/debuff icons (it's
-- redundant now that we draw our own timer). Legacy buttons expose it as
-- <name>Duration / button.duration; the 1.15.9+ pooled buttons may keep it as
-- an unnamed direct-region FontString with no table key, so fall back to a
-- region scan (our timer lives on a child frame and the count FS is excluded,
-- so the only direct FontString left is the duration).
local function FindBlizzDurationFS(button)
    local nm = button.GetName and button:GetName()
    local dur = button.duration or button.Duration or (nm and _G[nm .. "Duration"])
    if dur then return dur end
    local count = GetCountFS(button)
    if button.GetRegions then
        for _, region in ipairs({ button:GetRegions() }) do
            if region ~= count and region.GetObjectType
                and region:GetObjectType() == "FontString" then
                return region
            end
        end
    end
end

local ClearButton
local function HideBlizzDuration(button)
    if not ShowTimer() then return end
    -- Modern (1.15.9+) BuffFrame/DebuffFrame aura buttons are unnamed pooled
    -- frames; the player enumeration tags them with _tfIsPlayerAura instead.
    local nm = button.GetName and button:GetName()
    local isPlayerAura = button._tfIsPlayerAura
        or (nm and (nm:find("^BuffButton") or nm:find("^DebuffButton") or nm:find("^TempEnchant")))
    if not isPlayerAura then return end
    local dur = FindBlizzDurationFS(button)
    if dur and not dur._tfHidden then
        dur._tfHidden = true
        dur._tfAllowBlizzDuration = nil
        dur:SetAlpha(0)
        dur:Hide()
        -- Blizzard re-reveals this FS through several paths across builds;
        -- post-hook them all so it can never flicker back in.
        if dur.Show then
            hooksecurefunc(dur, "Show", function(self)
                if not self._tfAllowBlizzDuration then self:Hide() end
            end)
        end
        if dur.SetShown then
            hooksecurefunc(dur, "SetShown", function(self, shown)
                if shown and not self._tfAllowBlizzDuration then self:Hide() end
            end)
        end
        if dur.SetAlpha then
            hooksecurefunc(dur, "SetAlpha", function(self, a)
                if a and a > 0 and not self._tfAllowBlizzDuration and not self._tfAlphaGuard then
                    self._tfAlphaGuard = true
                    self:SetAlpha(0)
                    self._tfAlphaGuard = false
                end
            end)
        end
    end
end

local function SuspendButtonOverlay(button)
    if not button then return end
    -- Do not clear button._tfCD here: on modern frames it can be Blizzard's
    -- own cooldown widget, which is precisely the approved secret renderer we
    -- are handing control back to.
    button._tfExpiration = nil
    button._tfLastExp = nil
    button._tfLastDur = nil
    button._tfRawId = nil
    button._tfRawExp = nil
    button._tfRawDur = nil
    button._tfKey = nil
    active[button] = nil
    if button._tfTimer then
        button._tfTimer:SetText("")
        button._tfTimer:Hide()
    end
    local duration = FindBlizzDurationFS(button)
    if duration and duration._tfHidden then
        duration._tfAllowBlizzDuration = true
        duration:SetAlpha(1)
        duration:Show()
    end
end

-- Style one button given its resolved aura data.
local function StyleButton(button, scale, duration, expirationTime, timerFontOffset)
    if not button then return end

    if scale and scale > 0 and button.SetScale and button._tfScale ~= scale then
        -- Blizzard aura buttons are NOT protected frames, so scaling them
        -- mid-combat is safe and taint-free. This matters most for target
        -- debuffs, which practically only exist while in combat -- a blanket
        -- InCombatLockdown() bail here meant their scale never applied.
        -- Only genuinely protected buttons defer to the post-combat restyle.
        if not InCombatLockdown() or not (button.IsProtected and button:IsProtected()) then
            button:SetScale(scale)
            button._tfScale = scale
            -- Scale changes button footprint; re-flow the mover aura layout so
            -- row/column steps are computed with the new size.
            if ns.Movers and ns.Movers.RequestAuraUpdate then
                ns.Movers:RequestAuraUpdate()
            end
        end
    end

    local cd = GetCooldown(button)
    local timed = expirationTime and expirationTime > 0 and duration and duration > 0

    -- Only touch the swipe when the aura actually changed, so a polling rescan
    -- doesn't restart the cooldown animation every tick.
    if button._tfLastExp ~= expirationTime or button._tfLastDur ~= duration then
        button._tfLastExp = expirationTime
        button._tfLastDur = duration
        if cd then
            if ShowSwipe() and timed then
                CooldownFrame_Set(cd, expirationTime - duration, duration, true)
            else
                CooldownFrame_Clear(cd)
            end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        end
    end

    local fs = GetTimerFS(button, cd)
    ApplyTimerFont(button, timerFontOffset)
    HideBlizzDuration(button)
    StyleCount(button)
    if ShowTimer() and timed then
        button._tfExpiration = expirationTime
        button._tfKey = nil          -- let the ticker draw the text (next tick)
        active[button] = true
        fs:Show()
    else
        button._tfExpiration = nil
        button._tfKey = nil
        active[button] = nil
        fs:SetText("")
    end
end

ClearButton = function(button)
    if not button then return end
    button._tfExpiration = nil
    button._tfLastExp = nil
    button._tfLastDur = nil
    -- Raw (pre-resolve) values from UnitBuff/UnitDebuff, used by the target
    -- change-guard so an unchanged aura skips ResolveDuration + StyleButton.
    button._tfRawId = nil
    button._tfRawExp = nil
    button._tfRawDur = nil
    button._tfKey = nil
    active[button] = nil
    if button._tfTimer then button._tfTimer:SetText("") end
    if button._tfCD then CooldownFrame_Clear(button._tfCD) end
end

-- ---------------------------------------------------------------------------
-- TARGET frame (hooked onto TargetFrame_UpdateAuras, mirroring CAD's iteration)
-- ---------------------------------------------------------------------------
local MAX_T_BUFFS   = 32
local MAX_T_DEBUFFS = 16

-- Lazily-built cache of "<frame>Buff<i>" / "<frame>Debuff<i>" strings so the
-- target loops don't re-concatenate names on every update.
local tNameCache = {}
local function tNames(frameName)
    local c = tNameCache[frameName]
    if not c then
        c = { buff = {}, debuff = {} }
        for i = 1, MAX_T_BUFFS do c.buff[i] = frameName .. "Buff" .. i end
        for i = 1, MAX_T_DEBUFFS do c.debuff[i] = frameName .. "Debuff" .. i end
        tNameCache[frameName] = c
    end
    return c
end

function AS:StyleTargetFrame(self)
    if not PlayerTargetEnabled() or not self or not self.unit then return end
    local unit = self.unit
    local name = self:GetName()
    local names = tNames(name)
    if not AuraDataReadable() then
        for i = 1, MAX_T_BUFFS do SuspendButtonOverlay(_G[names.buff[i]]) end
        for i = 1, MAX_T_DEBUFFS do SuspendButtonOverlay(_G[names.debuff[i]]) end
        return
    end
    local buffScale   = C().auraTargetBuffScale   or 1
    local debuffScale = C().auraTargetDebuffScale or 1
    -- Scale applies even in combat for unprotected buttons (all normal aura
    -- buttons). Only a genuinely protected button defers to PLAYER_REGEN_ENABLED,
    -- so only for those do we treat scale as "matching" during lockdown (to
    -- avoid re-running LCD + restyle on every update all combat long).
    local lockdown = InCombatLockdown()
    local function scaleBlocked(btn)
        return lockdown and btn.IsProtected and btn:IsProtected()
    end

    -- Buffs map 1:1 to UnitBuff index
    for i = 1, MAX_T_BUFFS do
        local btn = _G[names.buff[i]]
        if not btn then break end
        if btn:IsShown() then
            local bname, _, _, _, duration, expirationTime, caster, _, _, spellId = UnitBuff(unit, i)
            if bname then
                -- Change-guard: when the API already supplies a duration (your own
                -- auras always do) and nothing about this button's aura changed
                -- since last pass, skip the LCD lookup + restyle entirely. This is
                -- what kills the self-target churn, since TargetFrame_UpdateAuras
                -- fires far more often than the auras actually change.
                -- The scale check makes scale-slider changes bypass the guard;
                -- without it a known-duration aura never picked up a new scale.
                if not (duration and duration > 0
                        and btn._tfRawId == spellId
                        and btn._tfRawExp == expirationTime
                        and btn._tfRawDur == duration
                        and (scaleBlocked(btn) or btn._tfScale == buffScale)) then
                    btn._tfRawId, btn._tfRawExp, btn._tfRawDur = spellId, expirationTime, duration
                    local rdur, rexp = ResolveDuration(unit, spellId, caster, duration, expirationTime)
                    StyleButton(btn, buffScale, rdur, rexp)
                end
            else
                ClearButton(btn)
            end
        else
            ClearButton(btn)
        end
    end
    local targetBuffRoot = _G[names.buff[1]]
    local targetBuffNudged = NudgeBlizzardAuraRoot(targetBuffRoot, "TargetBuffs")

    -- Debuffs don't map 1:1 to aura indices -- Blizzard filters them, so button N
    -- can show debuff index M (>= N). Replicate that walk (the CAD approach):
    -- advance the aura index, and only advance the frame number for debuffs that
    -- pass the show filter. GetID() is unreliable here (can be 0), so don't use it.
    local frameNum = 1
    local index = 1
    local maxD = self.maxDebuffs or MAX_T_DEBUFFS
    while frameNum <= maxD and index <= 60 do
        local dname, _, _, _, duration, expirationTime, caster, _, _, spellId,
              _, _, casterIsPlayer, nameplateShowAll = UnitDebuff(unit, index, "INCLUDE_NAME_PLATE_ONLY")
        if not dname then break end
        local show = true
        if _G.TargetFrame_ShouldShowDebuffs then
            show = TargetFrame_ShouldShowDebuffs(unit, caster, nameplateShowAll, casterIsPlayer)
        end
        if show then
            local btn = _G[names.debuff[frameNum] or (name .. "Debuff" .. frameNum)]
            if btn then
                if not (duration and duration > 0
                        and btn._tfRawId == spellId
                        and btn._tfRawExp == expirationTime
                        and btn._tfRawDur == duration
                        and (scaleBlocked(btn) or btn._tfScale == debuffScale)) then
                    btn._tfRawId, btn._tfRawExp, btn._tfRawDur = spellId, expirationTime, duration
                    local rdur, rexp = ResolveDuration(unit, spellId, caster, duration, expirationTime)
                    StyleButton(btn, debuffScale, rdur, rexp)
                end
            end
            frameNum = frameNum + 1
        end
        index = index + 1
    end
    -- Clear any debuff buttons we didn't fill this pass.
    for i = frameNum, MAX_T_DEBUFFS do
        local btn = _G[names.debuff[i]]
        if btn then ClearButton(btn) end
    end
    -- Blizzard anchors Target debuffs to the buff chain when buffs are visible.
    -- In that case the buff root's +3 already carries through, so a second
    -- direct debuff nudge would become +6. With no buffs, debuffs need their own
    -- root correction so a debuff-only target still moves the requested +3.
    local targetDebuffRoot = _G[names.debuff[1]]
    -- Blizzard's Target aura layout propagates the visible buff root's X
    -- correction into the debuff group even when GetPoint() does not expose a
    -- direct buff-button relativeTo. Visibility is therefore the authoritative
    -- inheritance signal: buffs shown means debuffs already carry +3; no buffs
    -- shown means the debuff-only layout needs its own +3.
    local inheritsBuffNudge = targetBuffNudged and targetBuffRoot
        and targetBuffRoot.IsShown and targetBuffRoot:IsShown()
    NudgeBlizzardAuraRoot(targetDebuffRoot, "TargetDebuffs", inheritsBuffNudge)
end

-- ---------------------------------------------------------------------------
-- TARGET OF TARGET debuffs
--
-- Four static frames (TargetFrameToTDebuff1..4). Blizzard populates them from
-- TargetOfTargetMixin:Update -> AuraUtil.RefreshAuras, but Update only runs on
-- target changes (UNIT_TARGET / PLAYER_TARGET_CHANGED / GROUP_ROSTER_UPDATE) --
-- TargetFrame never registers UNIT_AURA for "targettarget", and UNIT_AURA does
-- not fire for indirect units anyway. Stock behaviour is therefore stale icons
-- until you re-target, so TurboFace populates the slots itself on a throttled
-- driver rather than waiting for Blizzard.
--
-- Safe to drive directly: TargetFrameToTDebuff1:IsProtected() is false, false --
-- protection is not inherited from the ToT SecureUnitButton -- so Show/Hide and
-- SetPoint on these frames are legal in combat. Note this is content
-- population, NOT a call into Blizzard's own aura functions; the reason the
-- refresh is written out here instead of calling AuraUtil.RefreshAuras is that
-- invoking Blizzard FrameXML from addon code is what taints it.
--
-- $parentCooldown means GetCooldown() finds a real cooldown frame, and the
-- template has no count FontString, so StyleCount() no-ops.
-- ---------------------------------------------------------------------------
local MAX_TOT_DEBUFFS = 4
local totDebuffNames = {}
for i = 1, MAX_TOT_DEBUFFS do totDebuffNames[i] = "TargetFrameToTDebuff" .. i end

-- The stock overlay has a fairly heavy edge at ToT's enlarged debuff scale.
-- Stretching only that overlay outward by half a layout pixel preserves its
-- artwork and dispel tint while making the ring fractionally thinner. The
-- button, icon, hit rect, spacing, and timer geometry remain unchanged.
local TOT_DEBUFF_BORDER_OUTSET = 0.5
local function ThinToTDebuffBorder(border, button)
    if not border or not button or border._tfToTThinEdge then return end
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", button, "TOPLEFT",
        -TOT_DEBUFF_BORDER_OUTSET, TOT_DEBUFF_BORDER_OUTSET)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",
        TOT_DEBUFF_BORDER_OUTSET, -TOT_DEBUFF_BORDER_OUTSET)
    border._tfToTThinEdge = true
end

local totPoll  -- created in AS:Init()
local ToTPollTick

local function ToTDebuffFilter(unit)
    -- Mirrors the template's own OnEnter tooltip filter so our index walk and
    -- the tooltip agree about which debuff slot N holds.
    if GetCVarBool and GetCVarBool("showDispelDebuffs")
            and UnitCanAssist and UnitCanAssist("player", unit) then
        return "RAID"
    end
end

local function WakeToTPoll()
    if totPoll and ToTPollTick and ToTEnabled() and UnitExists("targettarget") then
        ns.Cadence:Add(totPoll, 0.25, ToTPollTick, true)
    end
end

local function HideToTDebuff(btn)
    if not btn then return end
    ClearButton(btn)
    btn._tfToTId = nil
    btn._tfToTExp = nil
    if btn:IsShown() then btn:Hide() end
end

function AS:StyleToTDebuffs()
    if not _G.TargetFrameToTDebuff1 then return end

    local unit = "targettarget"
    -- When the ToT Aura child is disabled, leave Blizzard's slots completely
    -- alone. Missing targettarget is different: while TurboFace owns this
    -- surface, stale slots must be hidden as soon as the indirect unit vanishes.
    if not ToTEnabled() then return end
    if not AuraDataReadable() then
        for i = 1, MAX_TOT_DEBUFFS do SuspendButtonOverlay(_G[totDebuffNames[i]]) end
        return
    end
    if not UnitExists(unit) then
        for i = 1, MAX_TOT_DEBUFFS do HideToTDebuff(_G[totDebuffNames[i]]) end
        return
    end

    local filter = ToTDebuffFilter(unit)
    local scale = tonumber(AuraDB().totDebuffScale) or 1

    for i = 1, MAX_TOT_DEBUFFS do
        local btn = _G[totDebuffNames[i]]
        if btn then
            local dname, icon, _, debuffType, duration, expirationTime, caster,
                  _, _, spellId = UnitDebuff(unit, i, filter)
            if dname then
                local btnName = btn:GetName()
                local iconTex = _G[btnName .. "Icon"]
                if iconTex and icon and btn._tfToTId ~= spellId then
                    iconTex:SetTexture(icon)
                end

                -- Blizzard tints the UI-Debuff-Overlays border by dispel school.
                local border = _G[btnName .. "Border"]
                ThinToTDebuffBorder(border, btn)
                if border and btn._tfToTId ~= spellId then
                    local col = DebuffTypeColor and DebuffTypeColor[debuffType or "none"]
                    if col then border:SetVertexColor(col.r, col.g, col.b) end
                end

                if not btn:IsShown() then btn:Show() end

                -- Only re-resolve durations when the aura in this slot actually
                -- changed; the driver re-runs several times a second.
                if btn._tfToTId ~= spellId or btn._tfToTExp ~= expirationTime
                        or btn._tfScale ~= scale then
                    btn._tfToTId, btn._tfToTExp = spellId, expirationTime
                    btn._tfRawId, btn._tfRawExp, btn._tfRawDur = spellId, expirationTime, duration
                    local rdur, rexp = ResolveDuration(unit, spellId, caster, duration, expirationTime)
                    StyleButton(btn, scale, rdur, rexp, -1)
                end
                -- Font-setting refreshes do not alter aura identity or scale,
                -- so keep this guarded call outside the slot-change branch.
                ApplyTimerFont(btn, -1)
            else
                HideToTDebuff(btn)
            end
        end
    end
    NudgeBlizzardAuraRoot(_G[totDebuffNames[1]], "ToTDebuffs", nil,
        TOT_BLIZZARD_DEBUFF_NUDGE_X)
end

-- ---------------------------------------------------------------------------
-- PLAYER buff bar -- updated on UNIT_AURA
--
-- Two client shapes:
--  * Legacy (pre-1.15.9): global BuffButton1../DebuffButton1.. frames plus
--    TempEnchant1/2, styled by index against UnitBuff/UnitDebuff.
--  * Modern (1.15.9+ retail BuffFrame import, Edit Mode-managed): pooled,
--    unnamed buttons in BuffFrame.auraFrames / DebuffFrame.auraFrames.
--    Buttons carry auraInstanceID when C_UnitAuras is live; otherwise fall
--    back to GetID() as an aura index. Temp-enchant buttons carry the
--    inventory slot (16/17) as their ID and have no auraInstanceID.
-- ---------------------------------------------------------------------------
local MAX_P_AURAS = 40

-- Pre-build the button name strings ONCE, so the hot loop does a plain table
-- lookup (_G[buffNames[i]]) instead of allocating a fresh "BuffButton"..i string
-- every iteration, every call. This was a major source of GC churn.
local buffNames, debuffNames = {}, {}
for i = 1, MAX_P_AURAS do
    buffNames[i]   = "BuffButton" .. i
    debuffNames[i] = "DebuffButton" .. i
end

local StyleTempEnchant -- defined below; also used by the modern-path walker

-- Fallback aura lookup for clients whose pooled buttons carry auraInstanceID
-- but that lack (or nil-return from) GetAuraDataByAuraInstanceID: scan the
-- unit's auras by index once per pass and map instanceID -> aura data.
-- (Shaman Lightning Shield styled nothing while the weapon imbue worked --
-- imbue buttons resolve through their slot ID, regular buffs needed this map.)
local instScanMap = {}
local function BuildInstanceScan(filter)
    wipe(instScanMap)
    for i = 1, 40 do
        local a = ns.API.GetReadableAuraDataByIndex("player", i, filter)
        if not a then break end
        local auraInstanceID = a.auraInstanceID
        if ns.API.CanAccessValue(auraInstanceID) and auraInstanceID ~= nil then
            instScanMap[auraInstanceID] = a
        end
    end
    return instScanMap
end

-- Last-tier fallback needing NO aura-instance APIs: walk UnitBuff/UnitDebuff
-- and index the auras by icon texture, then match buttons through their Icon.
-- Entries are consumed as buttons claim them so two auras sharing one icon
-- each style once (order-ambiguous in that rare case, but never dropped).
local texScanMap = {}
local function BuildTextureScan(filter)
    wipe(texScanMap)
    local get = (filter == "HELPFUL") and UnitBuff or UnitDebuff
    for i = 1, 40 do
        local aname, icon, _, _, duration, expirationTime, caster, _, _, spellId = get("player", i)
        if not aname then break end
        -- A texture ID/path can itself be secret on a Blizzard-owned aura
        -- button. Secret values may be stored, but they may not be used as Lua
        -- table keys, so the icon fallback must fail closed when unreadable.
        if ns.API.CanAccessValue(icon) and icon ~= nil then
            local list = texScanMap[icon]
            if not list then list = {}; texScanMap[icon] = list end
            list[#list + 1] = { duration = duration, expirationTime = expirationTime,
                                caster = caster, spellId = spellId }
        end
    end
    return texScanMap
end

local function StyleModernPlayerAuras(container, filter, scale)
    local frames = container and container.auraFrames
    if type(frames) ~= "table" then return false end
    local scan    -- built lazily, only when the direct lookup fails
    local texScan -- built lazily, only when no instance/index route worked
    for _, btn in pairs(frames) do
        if type(btn) == "table" and btn.IsShown then
            if not btn:IsShown() then
                ClearButton(btn)
            else
                btn._tfIsPlayerAura = true
                local handled = false
                local instID = btn.auraInstanceID
                -- Do not even truth-test a secret auraInstanceID.  The native
                -- button can keep displaying it; TurboFace simply skips its
                -- custom overlay until the identifier becomes readable again.
                if ns.API.CanAccessValue(instID) and instID ~= nil then
                    local a = ns.API.GetReadableAuraDataByAuraInstanceID("player", instID)
                    if not a then
                        if scan == nil then scan = BuildInstanceScan(filter) or false end
                        if scan then a = scan[instID] end
                    end
                    if a then
                        local dur, exp = ResolveDuration("player", a.spellId,
                            a.sourceUnit, a.duration, a.expirationTime)
                        StyleButton(btn, scale, dur, exp)
                        handled = true
                    end
                end
                if not handled then
                    local id = (btn.GetID and btn:GetID()) or 0
                    if filter == "HELPFUL" and id >= 16 and id <= 18 and GetWeaponEnchantInfo then
                        -- Temp-enchant button: ID is the inventory slot.
                        local has1, exp1, _, _, has2, exp2 = GetWeaponEnchantInfo()
                        local slot = id - 15
                        StyleTempEnchant(btn, slot, scale,
                            slot == 1 and has1 or has2, slot == 1 and exp1 or exp2)
                        handled = true
                    elseif id > 0 then
                        local get = (filter == "HELPFUL") and UnitBuff or UnitDebuff
                        local aname, _, _, _, duration, expirationTime, caster, _, _, spellId = get("player", id)
                        if aname then
                            local dur, exp = ResolveDuration("player", spellId, caster, duration, expirationTime)
                            StyleButton(btn, scale, dur, exp)
                            handled = true
                        end
                    end
                end
                if not handled then
                    -- No instance API, no index: match by icon texture.
                    local iconRegion = IconRegion(btn)
                    local iconTex = iconRegion ~= btn and iconRegion.GetTexture
                        and iconRegion:GetTexture() or nil
                    -- GetTexture() on a Blizzard-owned aura region can return an
                    -- opaque/secret texture identifier in restricted combat.
                    -- Never use that value as a Lua table key.
                    if ns.API.CanAccessValue(iconTex) and iconTex ~= nil then
                        if texScan == nil then texScan = BuildTextureScan(filter) end
                        local list = texScan[iconTex]
                        local a = list and table.remove(list, 1)
                        if a then
                            local dur, exp = ResolveDuration("player", a.spellId,
                                a.caster, a.duration, a.expirationTime)
                            StyleButton(btn, scale, dur, exp)
                            handled = true
                        end
                    end
                end
                if not handled then ClearButton(btn) end
            end
        end
    end
    return true
end

function AS:StylePlayer()
    if not PlayerTargetEnabled() then return end
    if not AuraDataReadable() then
        for _, container in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
            local frames = container and container.auraFrames
            if type(frames) == "table" then
                for _, button in pairs(frames) do SuspendButtonOverlay(button) end
            end
        end
        for i = 1, MAX_P_AURAS do
            SuspendButtonOverlay(_G[buffNames[i]])
            SuspendButtonOverlay(_G[debuffNames[i]])
        end
        return
    end
    -- Player icon size is Blizzard-owned (Buff/Debuff options: size, padding,
    -- limit). Pass nil so StyleButton never touches player button scale;
    -- TurboFace only draws timers, swipes, and count styling here.
    local buffScale, debuffScale = nil, nil

    -- Modern containers first; each falls back to its legacy loop when the
    -- container shape is absent so mixed/partial client imports still style.
    local modernBuffs   = StyleModernPlayerAuras(_G.BuffFrame,   "HELPFUL", buffScale)
    local modernDebuffs = StyleModernPlayerAuras(_G.DebuffFrame, "HARMFUL", debuffScale)
    if modernBuffs and modernDebuffs then return end
    if modernBuffs then
        -- Only the legacy debuff walk remains needed.
        for i = 1, MAX_P_AURAS do
            local btn = _G[debuffNames[i]]
            if btn and btn:IsShown() then
                local idx = btn:GetID() or i
                local dname, _, _, _, duration, expirationTime, caster, _, _, spellId = UnitDebuff("player", idx)
                if dname then
                    duration, expirationTime = ResolveDuration("player", spellId, caster, duration, expirationTime)
                    StyleButton(btn, debuffScale, duration, expirationTime)
                else
                    ClearButton(btn)
                end
            elseif btn then
                ClearButton(btn)
            end
        end
        return
    end

    for i = 1, MAX_P_AURAS do
        local btn = _G[buffNames[i]]
        if btn and btn:IsShown() then
            local idx = btn:GetID() or i
            local bname, _, _, _, duration, expirationTime, caster, _, _, spellId = UnitBuff("player", idx)
            if bname then
                duration, expirationTime = ResolveDuration("player", spellId, caster, duration, expirationTime)
                StyleButton(btn, buffScale, duration, expirationTime)
            else
                ClearButton(btn)
            end
        elseif btn then
            ClearButton(btn)
        end
    end

    for i = 1, MAX_P_AURAS do
        local btn = _G[debuffNames[i]]
        if btn and btn:IsShown() then
            local idx = btn:GetID() or i
            local dname, _, _, _, duration, expirationTime, caster, _, _, spellId = UnitDebuff("player", idx)
            if dname then
                duration, expirationTime = ResolveDuration("player", spellId, caster, duration, expirationTime)
                StyleButton(btn, debuffScale, duration, expirationTime)
            else
                ClearButton(btn)
            end
        elseif btn then
            ClearButton(btn)
        end
    end

    self:StyleTempEnchants()
end

-- ---------------------------------------------------------------------------
-- Temporary weapon enchants (TempEnchant1 = main hand, TempEnchant2 = off hand)
-- ---------------------------------------------------------------------------
StyleTempEnchant = function(button, slot, scale, active1, remainingMs)
    if not button then return end
    if not active1 or not remainingMs or remainingMs <= 0 then
        tempExp[slot], tempDur[slot] = nil, nil
        ClearButton(button)
        return
    end
    local remaining = remainingMs / 1000
    local now = GetTime()
    local computed = now + remaining
    local exp = tempExp[slot]
    -- New, or jumped by >2s (reapplied / different enchant) -> refresh the
    -- baseline so the swipe restarts; otherwise keep the stable expiration.
    if not exp or math.abs(computed - exp) > 2 then
        exp = computed
        tempExp[slot] = exp
        tempDur[slot] = remaining
    end
    StyleButton(button, scale, tempDur[slot], exp)
end

function AS:StyleTempEnchants()
    if not GetWeaponEnchantInfo then return end
    local scale = nil -- player icon size is Blizzard-owned
    local has1, exp1, _, _, has2, exp2 = GetWeaponEnchantInfo()
    local b1 = _G.TempEnchant1
    local b2 = _G.TempEnchant2
    if b1 then StyleTempEnchant(b1, 1, scale, has1, exp1) end
    if b2 then StyleTempEnchant(b2, 2, scale, has2, exp2) end
end
-- LibClassicDurations treats its registration argument as an ownership token;
-- it does not require Frame methods. Reuse a plain token for both LCD demand and
-- the shared countdown cadence instead of allocating a hidden UI frame.
local ticker = {}

local function AuraTimerTick(_, elapsed)
    local now = GetTime()
    local show = ShowTimer()
    local any = false
    for btn in pairs(active) do
        any = true
        local exp = btn._tfExpiration
        if not exp or not btn._tfTimer then
            active[btn] = nil
        else
            local remaining = exp - now
            if remaining <= 0 then
                if btn._tfKey ~= nil then btn._tfTimer:SetText(""); btn._tfKey = nil end
                active[btn] = nil
            elseif show then
                local key
                if remaining >= 3600 then key = floor(remaining / 3600) + 10000000
                elseif remaining >= 90 then key = floor(remaining / 60) + 100000
                else key = floor(remaining) end
                if btn._tfKey ~= key then
                    btn._tfKey = key
                    btn._tfTimer:SetText((FormatTime(remaining)))
                end
            elseif btn._tfKey ~= nil then
                btn._tfTimer:SetText(""); btn._tfKey = nil
            end
        end
    end
    if not any then ns.Cadence:Remove(ticker) end
end
ns.RegisterCPUProfileTarget("Auras/PlayerTarget:TimerTick", AuraTimerTick)

-- Restart the timer cadence whenever something is being tracked.
local function StartTicker()
    if next(active) then ns.Cadence:Add(ticker, 0.25, AuraTimerTick) end
end

-- ---------------------------------------------------------------------------
-- Init / Refresh
-- ---------------------------------------------------------------------------
function AS:Init()
    if initialized or not RuntimeNeeded() then return end
    initialized = true

    -- Activate LibClassicDurations only when at least one AuraStyle consumer
    -- (Player/Target or ToT) needs duration resolution. A disabled Auras family
    -- never reaches this point, so LCD, hooks, events, pollers, and backups stay inert.
    if LCD and LCD.RegisterFrame then
        pcall(LCD.RegisterFrame, LCD, ticker)
        -- LibClassicDurations is embedded in TurboFace and therefore contributes
        -- to addon CPU totals. Expose its hot combat-log entry points so library
        -- work does not disappear into the profiler's untracked bucket.
        local lcdFrame = LCD.frame
        if lcdFrame then
            ns.RegisterCPUProfileTarget("Libs/ClassicDurations:OnEvent", lcdFrame:GetScript("OnEvent"), false)
            ns.RegisterCPUProfileTarget("Libs/ClassicDurations:CLEU", lcdFrame.COMBAT_LOG_EVENT_UNFILTERED, false)
            ns.RegisterCPUProfileTarget("Libs/ClassicDurations:CombatLog", lcdFrame.CombatLogHandler, false)
        end
    end
    runtimeActive = true

    -- Target: same hook point ClassicAuraDurations used, but COALESCED. Blizzard
    -- fires TargetFrame_UpdateAuras many times per second, and when you're self-
    -- targeted every player aura change routes through here too. Instead of doing
    -- a full LCD-backed restyle on each call, flag it dirty and flush at most
    -- ~10x/sec. The coalescer frame is hidden whenever there is no pending work.
    local dirty = false
    local targetDirty = false
    local totDirty = false
    local targetFrames = {}
    local poll

    local WakePoll
    WakePoll = function()
        -- Replaced with the cadence-backed implementation once poll is created.
    end

    do
        local function OnTargetAuras(self)
            if not PlayerTargetEnabled() or not self then return end
            targetFrames[self] = true
            targetDirty = true
            WakePoll()
        end
        -- Classic global, or the mixin method on clients where Blizzard ported
        -- TargetFrame. If neither exists the low-frequency compat timer below
        -- still refreshes target auras, just more slowly.
        ns.API.HookGlobalOrMethod("TargetFrame_UpdateAuras",
            TargetFrame, "UpdateAuras", OnTargetAuras)
        ns.RegisterCPUProfileTarget("Auras/PlayerTarget:TargetAuraHook", OnTargetAuras, false)

        -- ToT debuffs only ever refresh inside TargetOfTargetMixin:Update (it
        -- calls AuraUtil.RefreshAuras), so post-hook that instead of listening
        -- for UNIT_AURA, which does not fire reliably for an indirect unit.
        -- hooksecurefunc, never a direct call: Update is the function whose
        -- self:Show() we must not taint.
        local tot = _G.TargetFrameToT
        if tot and type(tot.Update) == "function" then
            local function OnToTUpdate()
                if not ToTEnabled() then return end
                totDirty = true
                WakePoll()
                -- Update fires when a ToT appears or the target changes; that is
                -- the cue to start the driver, which then stops itself once no
                -- target of target exists.
                WakeToTPoll()
            end
            hooksecurefunc(tot, "Update", OnToTUpdate)
            ns.RegisterCPUProfileTarget("Auras/PlayerTarget:ToTUpdateHook", OnToTUpdate, false)
        end
    end

    -- Player auras via events, COALESCED. A burst of UNIT_AURA events (common in
    -- combat) sets a dirty flag instead of each one triggering a full re-walk.
    local ev = CreateFrame("Frame")
    local function UpdateAuraEvents()
        ev:UnregisterAllEvents()
        if not PlayerTargetEnabled() then return end
        -- player-only: nameplate/party UNIT_AURA bursts never reach this handler.
        ns.RegisterUnitEvent(ev, "UNIT_AURA", "player")
        ns.RegisterEvent(ev, "PLAYER_ENTERING_WORLD")
        -- Weapon imbues/stones/oils fire no UNIT_AURA; UNIT_INVENTORY_CHANGED covers
        -- the normal apply/remove path immediately. A low-frequency timer below is a
        -- compatibility fallback rather than an always-on frame poll.
        if ev.RegisterUnitEvent then
            ns.RegisterUnitEvent(ev, "UNIT_INVENTORY_CHANGED", "player")
        else
            ns.RegisterEvent(ev, "UNIT_INVENTORY_CHANGED")
        end
        ns.RegisterEvent(ev, "PLAYER_REGEN_ENABLED")
    end
    UpdateAuraEvents()
    ev:SetScript("OnEvent", function(_, event, unit)
        if not PlayerTargetEnabled() then return end
        if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
        dirty = true
        WakePoll()
        if event == "PLAYER_REGEN_ENABLED" and _G.TargetFrame_UpdateAuras
                and UnitExists and UnitExists("target") then
            -- securecall, never a direct call: TargetFrame_UpdateAuras creates
            -- the TargetFrameBuffN/DebuffN globals on demand, so a direct call
            -- would taint them (and every later secure UpdateAuras that reads
            -- them back at TargetFrame.lua:742). The post-hook still fires.
            securecall("TargetFrame_UpdateAuras", TargetFrame)
        end
    end)
    self._ev = ev
    self._updateEvents = UpdateAuraEvents

    poll = {} -- cadence token; no frame API required
    AS._pollCount = 0
    local function DirtyPollTick()
        if not RuntimeNeeded() then
            ns.Cadence:Remove(poll)
            return
        end
        -- Kill-trace boundaries sit on the FLUSH, not on the OnEvent handler
        -- above: that handler only sets a flag and wakes the coalescer, so
        -- measuring it would report ~0 while the real post-combat restyle cost
        -- lands here, one 10 Hz pulse later.
        if dirty then
            dirty = false
            if PlayerTargetEnabled() then
                ns.KillTrace("AuraStyle:", "StylePlayer", AS.StylePlayer, AS)
            end
        end
        if targetDirty then
            targetDirty = false
            for f in pairs(targetFrames) do
                if PlayerTargetEnabled() then
                    ns.KillTrace("AuraStyle:", "StyleTarget", AS.StyleTargetFrame, AS, f)
                end
                targetFrames[f] = nil
            end
        end
        if totDirty then
            totDirty = false
            if ToTEnabled() then
                ns.KillTrace("AuraStyle:", "StyleToTDebuffs", AS.StyleToTDebuffs, AS)
            end
        end
        StartTicker()
        if not dirty and not targetDirty and not totDirty then ns.Cadence:Remove(poll) end
    end
    -- WakePoll is defined above before poll exists; swap its implementation now
    -- that the token and callback are available.
    WakePoll = function()
        if poll and RuntimeNeeded() and (dirty or targetDirty or totDirty) then
            -- This is a coalescer, not a latency-sensitive animation. Do NOT
            -- request an immediate pulse here: Blizzard can dirty Target/ToT
            -- auras hundreds of times per second, and an immediate add after
            -- every one-shot flush defeats the intended 10 Hz batching.
            ns.Cadence:Add(poll, 0.10, DirtyPollTick)
        end
    end
    self._poll = poll
    self._wakePoll = WakePoll
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:Events", ev:GetScript("OnEvent"))
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:DirtyTick", DirtyPollTick)

    -- ToT debuff driver. Blizzard gives no event for "targettarget" aura
    -- changes (see the ToT section above), so this is the one place TurboFace
    -- must poll. It runs at 4/sec and only while a ToT actually exists --
    -- StyleToTDebuffs hides the slots and this cadence job stops itself otherwise --
    -- so the idle cost is zero. Woken by the TargetFrameToT:Update post-hook,
    -- which fires exactly when a ToT appears.
    totPoll = {} -- cadence token; no frame API required
    ToTPollTick = function()
        if not ToTEnabled() then
            ns.Cadence:Remove(totPoll)
            return
        end
        AS:StyleToTDebuffs()
        StartTicker()
        if not UnitExists("targettarget") then ns.Cadence:Remove(totPoll) end
    end
    self._totPoll = totPoll
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:ToTTick", ToTPollTick)
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:StyleTarget", AS.StyleTargetFrame)
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:StyleToT", AS.StyleToTDebuffs)
    ns.RegisterCPUProfileTarget("Auras/PlayerTarget:StylePlayer", AS.StylePlayer)

    -- A cancellable generation token turns C_Timer.After into a lightweight
    -- periodic compatibility rescan without keeping an OnUpdate alive. Two
    -- seconds is frequent enough to catch rare missing enchant/aura notifications
    -- while halving the old full-rescan cadence.
    local backupGeneration = 0
    local function StopBackup()
        backupGeneration = backupGeneration + 1
    end
    local function ScheduleBackup()
        StopBackup()
        if not PlayerTargetEnabled() or not (C_Timer and C_Timer.After) then return end
        local token = backupGeneration
        C_Timer.After(2, function()
            if token ~= backupGeneration or not PlayerTargetEnabled() then return end
            AS._pollCount = AS._pollCount + 1
            dirty = true
            WakePoll()
            ScheduleBackup()
        end)
    end
    self._stopBackup = StopBackup
    self._scheduleBackup = ScheduleBackup

    -- NOTE: We intentionally do NOT register an LCD callback here. Registering
    -- ANY LCD callback triggers CallbackHandler's OnUsed, which flips
    -- enableEnemyBuffTracking on inside the library (core.lua OnUsed) and makes
    -- it do per-event enemy GUID tracking + RegenerateBuffList table-building
    -- that we never consume. The "learned a duration late" case is already
    -- covered: the 2s timer-based backup rescan re-resolves player auras, and
    -- target auras re-resolve whenever TargetFrame_UpdateAuras fires.

    self:Refresh()
end

function AS:Refresh()
    -- Player/Target and ToT are independent Aura consumers. Initialize the
    -- shared hooks/tokens when either one first becomes necessary.
    if not initialized and RuntimeNeeded() then
        self:Init()
        return
    end

    fontGen = fontGen + 1
    if RuntimeNeeded() then
        if initialized and not runtimeActive then
            runtimeActive = true
            if LCD and LCD.RegisterFrame then pcall(LCD.RegisterFrame, LCD, ticker) end
        end
        if self._updateEvents then self._updateEvents() end

        if PlayerTargetEnabled() then
            AS:StylePlayer()
            if _G.TargetFrame_UpdateAuras and UnitExists and UnitExists("target") then
                -- securecall: see the PLAYER_REGEN_ENABLED nudge note above.
                securecall("TargetFrame_UpdateAuras", TargetFrame)
            end
            StartTicker()
            if self._scheduleBackup then self._scheduleBackup() end
        else
            if self._stopBackup then self._stopBackup() end
            -- auraEnabled is a live Player/Target presentation switch. If ToT
            -- remains independently enabled, clear only Player/Target-owned
            -- timer/swipe state and restore target-button scales.
            for i = 1, MAX_P_AURAS do
                local b = _G[buffNames[i]];   if b then ClearButton(b) end
                local d = _G[debuffNames[i]]; if d then ClearButton(d) end
            end
            local tf = _G.TargetFrame
            if tf and tf.GetName then
                local names = tNames(tf:GetName())
                for i = 1, MAX_T_BUFFS do
                    local b = _G[names.buff[i]]
                    if b then if b._tfScale then b:SetScale(1); b._tfScale = nil end; ClearButton(b) end
                end
                for i = 1, MAX_T_DEBUFFS do
                    local d = _G[names.debuff[i]]
                    if d then if d._tfScale then d:SetScale(1); d._tfScale = nil end; ClearButton(d) end
                end
            end
        end

        if ToTEnabled() then
            AS:StyleToTDebuffs()
            WakeToTPoll()
        else
            if self._totPoll then ns.Cadence:Remove(self._totPoll) end
            -- Hand the four slots back to Blizzard when only the ToT child is off.
            for i = 1, MAX_TOT_DEBUFFS do
                local t = _G[totDebuffNames[i]]
                if t then
                    if t._tfScale then t:SetScale(1); t._tfScale = nil end
                    t._tfToTId, t._tfToTExp = nil, nil
                    ClearButton(t)
                end
            end
        end
    else
        if runtimeActive then
            runtimeActive = false
            if self._ev and self._ev.UnregisterAllEvents then self._ev:UnregisterAllEvents() end
            if LCD and LCD.UnregisterFrame then pcall(LCD.UnregisterFrame, LCD, ticker) end
        end
        ns.Cadence:Remove(ticker)
        if self._poll then ns.Cadence:Remove(self._poll) end
        if self._totPoll then ns.Cadence:Remove(self._totPoll) end
        if self._stopBackup then self._stopBackup() end
        for btn in pairs(active) do ClearButton(btn) end
        for i = 1, MAX_P_AURAS do
            local b = _G[buffNames[i]];   if b and b._tfTimer then b:SetScale(1); b._tfScale = nil; ClearButton(b) end
            local d = _G[debuffNames[i]]; if d and d._tfTimer then d:SetScale(1); d._tfScale = nil; ClearButton(d) end
        end
        for i = 1, MAX_TOT_DEBUFFS do
            local t = _G[totDebuffNames[i]]
            if t then
                if t._tfScale then t:SetScale(1); t._tfScale = nil end
                t._tfToTId, t._tfToTExp = nil, nil
                ClearButton(t)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- /tfaura -- diagnostic: dumps the pipeline state and force-styles BuffButton1
-- so we can see exactly where the player path breaks.
-- ---------------------------------------------------------------------------
SLASH_TFAURA1 = "/tfaura"
SlashCmdList["TFAURA"] = function()
    local function p(...) print("|cff00ccffTFAura|r", ...) end
    p("player/target:", tostring(PlayerTargetEnabled()), "| ToT:", tostring(ToTEnabled()), "| LCD:", LCD and "yes" or "NO",
      "| polls:", AS._pollCount or 0)
    -- Find a buff button that is actually shown. Modern (1.15.9+) pooled
    -- buttons first, then the legacy BuffButton globals.
    local shown, target = 0, nil
    p("C_UnitAuras:", type(C_UnitAuras),
      "| byInstance:", type(C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID),
      "| buffByIndex:", type(C_UnitAuras and C_UnitAuras.GetBuffDataByIndex))
    local modernFrames = _G.BuffFrame and _G.BuffFrame.auraFrames
    if type(modernFrames) == "table" then
        for _, btn in pairs(modernFrames) do
            if type(btn) == "table" and btn.IsShown and btn:IsShown() then
                shown = shown + 1
                if not target then target = btn end
                local ic = btn.Icon or btn.icon
                p(("  btn: id=%s inst=%s icon=%s tex=%s h=%s"):format(
                    tostring(btn.GetID and btn:GetID()),
                    tostring(btn.auraInstanceID),
                    tostring(ic ~= nil),
                    tostring(ic and ic.GetTexture and ic:GetTexture()),
                    tostring(btn.GetHeight and math.floor(btn:GetHeight() + 0.5))))
            end
        end
        p("modern BuffFrame.auraFrames shown:", shown)
    else
        for i = 1, MAX_P_AURAS do
            local b2 = _G["BuffButton" .. i]
            if b2 and b2:IsShown() then
                shown = shown + 1
                if not target then target = b2 end
            end
        end
        p("legacy shown buff buttons:", shown)
    end
    local b = target or _G.BuffButton1
    if not b then p("no buff buttons exist right now -- get a buff first"); return end
    local id = (b.GetID and b:GetID()) or 0
    p("testing:", tostring(b.GetName and b:GetName() or "(unnamed modern button)"),
      "| shown:", tostring(b:IsShown()), "| id:", id,
      "| auraInstanceID:", tostring(b.auraInstanceID))
    local n, d, e, caster, sid
    if b.auraInstanceID then
        local a = ns.API.GetReadableAuraDataByAuraInstanceID("player", b.auraInstanceID)
        if a then n, d, e, caster, sid = a.name, a.duration, a.expirationTime, a.sourceUnit, a.spellId end
        p("instance data:", tostring(n), "| dur:", tostring(d), "| exp:", tostring(e))
    else
        n, _, _, _, d, e, caster, _, _, sid = UnitBuff("player", id)
        p("UnitBuff:", tostring(n), "| dur:", tostring(d), "| exp:", tostring(e))
    end
    local dur, exp = ResolveDuration("player", sid, caster, d, e)
    p("resolved:", "dur:", tostring(dur), "| exp:", tostring(exp))
    -- Force a guaranteed visible 30s swipe + 'TEST' onto this SHOWN button.
    b._tfLastExp, b._tfLastDur = nil, nil
    b._tfIsPlayerAura = true
    StyleButton(b, 1, dur, exp)
    if b._tfCD then CooldownFrame_Set(b._tfCD, GetTime(), 30, true) end
    if b._tfTimer then b._tfTimer:SetText("TEST") end
    p("forced 30s swipe + 'TEST' -- do you see them now?")
    -- Target buff/debuff scale diagnostics
    if UnitExists and UnitExists("target") then
        p("target scales -- buff opt:", C().auraTargetBuffScale or 1,
          "| debuff opt:", C().auraTargetDebuffScale or 1,
          "| inCombat:", tostring(InCombatLockdown()))
        for i = 1, 16 do
            local d = _G["TargetFrameDebuff" .. i]
            if d and d:IsShown() then
                p(("TargetFrameDebuff%d: scale=%.2f | _tfScale=%s | size=%.0f | protected=%s"):format(
                    i, d:GetScale(), tostring(d._tfScale), d:GetWidth(),
                    tostring(d.IsProtected and d:IsProtected())))
            end
        end
    end
    -- Temp weapon enchant info
    if GetWeaponEnchantInfo then
        local h1, e1, _, _, h2, e2 = GetWeaponEnchantInfo()
        p("WeaponEnchant MH:", tostring(h1), "rem(ms):", tostring(e1),
          "| OH:", tostring(h2), "rem(ms):", tostring(e2))
        p("TempEnchant1:", tostring(_G.TempEnchant1), "| TempEnchant2:", tostring(_G.TempEnchant2))
    end
end
