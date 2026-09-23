local _, ns = ...

-- TurboFace-owned Party/Pet aura renderer. This is an Aura subsystem, not a
-- Unit Frames child: it can augment Blizzard's stock PartyFrame/PetFrame or
-- TurboFace-restyled frames with the same owned icons, borders, swipes, timers,
-- and class-only party reminders.
local PartyAuras = {}
ns.PartyAuras = PartyAuras

local function D()
    return (TurboFaceDB and TurboFaceDB.auras) or (ns.defaults and ns.defaults.auras) or {}
end

local function PartyGate()
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("auras", "party")
end

local function PetGate()
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("auras", "pet")
end

-- Classic Era 1.15.9 creates party members from PartyFrame's pool and exposes
-- them as PartyFrame.MemberFrame1..4. Keep the legacy global fallback for older
-- Classic layouts. These lookups live here so aura rendering does not depend on
-- the Unit Frames subsystem existing or being initialized.
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

local PARTY_BUFF_MAX_CAP = 16
local PARTY_DEBUFF_MAX = 4
local PARTY_BUFF_SPACING = 2
local PARTY_BUFF_GAP = 5
local PARTY_AURA_RECONCILE_INTERVAL = 1.0

-- Party helpful auras use the same TurboFace-authored silver rounded frame as
-- the Class Buff reminder bar, but with a tighter 1px outset sized for the
-- smaller party-aura icons. Harmful auras use Blizzard's rounded debuff ring
-- tinted by debuff/dispel school. Keep the fallback table local so Classic
-- clients that fail to expose DebuffTypeColor never degrade to a black ring.
local PARTY_BUFF_MASK = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Mask-Rounded"
local PARTY_BUFF_BORDER = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Border-Buff"
local PARTY_BUFF_BORDER_OUTSET = 1
local PARTY_DEBUFF_FALLBACK_COLORS = {
    none    = { r = 0.80, g = 0.00, b = 0.00 },
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

-- Party aura freshness is TurboFace-owned. Do not rely on Blizzard's pooled
-- party-frame OnEvent implementation to forward every UNIT_AURA transition: the
-- method can exist even when a particular frame is not registered for that
-- event. Two C-filtered watchers cover party1..party4 without waking Lua for
-- player/target/nameplate aura traffic. A low-frequency reconciliation pass is
-- retained as a self-healing safety net for missed client events and natural
-- expirations.
local partyAuraWatch12, partyAuraWatch34
local partyAuraReconcileDriver = {} -- cadence token; no frame API required
local partyAuraEventsActive = false
local petAuraWatch
local petAuraReconcileDriver = {} -- cadence token; no frame API required
local petAuraEventsActive = false
local partyLayoutPending = false
local petLayoutPending = false
local auraDeferredFrame
local DeferredAuraOnEvent
local partyFrameHooksInstalled = false

local function EnsurePartyAuraWatchers()
    if partyAuraWatch12 then return partyAuraWatch12, partyAuraWatch34 end
    partyAuraWatch12 = CreateFrame("Frame")
    partyAuraWatch34 = CreateFrame("Frame")
    return partyAuraWatch12, partyAuraWatch34
end

local function EnsurePetAuraWatcher()
    if petAuraWatch then return petAuraWatch end
    petAuraWatch = CreateFrame("Frame")
    return petAuraWatch
end

local function EnsureDeferredAuraFrame()
    if auraDeferredFrame then return auraDeferredFrame end
    auraDeferredFrame = CreateFrame("Frame")
    auraDeferredFrame:SetScript("OnEvent", DeferredAuraOnEvent)
    return auraDeferredFrame
end

local function ArmDeferredLayout()
    ns.RegisterEvent(EnsureDeferredAuraFrame(), "PLAYER_REGEN_ENABLED")
end
local UpdatePartyBuffs, UpdatePartyDebuffs, UpdateAllPartyAuras
local UpdatePetBuffs, UpdatePetDebuffs, UpdateAllPetAuras
local ResetPartyBuffIcon

local function AuraDataReadable()
    return not (ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret())
end

local function SuspendOwnedAuraContainer(container)
    if not container then return end
    for index = 1, #(container.icons or {}) do ResetPartyBuffIcon(container.icons[index]) end
    container:Hide()
end
local PartyAuraReconcileTick
local PetAuraReconcileTick

-- Timed Party/Pet buffs and debuffs use live countdown text. Track their
-- handful of active icons in one shared 0.25s driver instead of attaching an
-- OnUpdate to every icon. The driver also knows the exact expiration boundary,
-- which lets it request a real aura rescan if an expiry UNIT_AURA is missed.
local activePartyAuraTimers = {}
local expiredPartyAuraFrames = {}
local partyAuraTimerDriver = {} -- cadence token; no frame API required
local PartyAuraTimerTick

local function FormatPartyAuraTime(remaining)
    -- Match AuraStyle/TargetFrame exactly: whole units are ceiling-rounded,
    -- seconds remain visible below 90s, and there is no sub-second phase.
    if remaining >= 3600 then
        local value = math.ceil(remaining / 3600)
        return value .. "h", value + 10000000
    elseif remaining >= 90 then
        local value = math.ceil(remaining / 60)
        return value .. "m", value + 100000
    elseif remaining > 0 then
        local value = math.ceil(remaining)
        return tostring(value), value
    end
    return "", 0
end

local function PartyClassWarnSeconds()
    local value = tonumber(D().partyClassBuffWarnSeconds)
    return math.max(0, value or 30)
end

local StopPartyBuffPulse

local function StartPartyBuffPulse(button)
    if not button then return end
    button:SetAlpha(1)
    if button._tfPulse and not button._tfPulse:IsPlaying() then
        button._tfPulse:Play()
    end
end

local function UpdatePartyBuffExpiryPulse(button, remaining)
    local warnSeconds = PartyClassWarnSeconds()
    if warnSeconds > 0 and remaining and remaining > 0 and remaining <= warnSeconds then
        StartPartyBuffPulse(button)
    else
        StopPartyBuffPulse(button)
    end
end

local function ClearPartyAuraTimer(button)
    if not button then return end
    activePartyAuraTimers[button] = nil
    button._tfTimerExpiration = nil
    button._tfTimerKey = nil
    button._tfAuraOwnerFrame = nil
    if button._tfTimer then
        button._tfTimer:SetText("")
        button._tfTimer:Hide()
    end
end

local function TrackPartyAuraTimer(button, expirationTime, ownerFrame)
    if not button or not button._tfTimer or not expirationTime or expirationTime <= 0 then
        ClearPartyAuraTimer(button)
        StopPartyBuffPulse(button)
        return
    end
    button._tfTimerExpiration = expirationTime
    button._tfTimerKey = nil
    button._tfAuraOwnerFrame = ownerFrame
    activePartyAuraTimers[button] = true
    button._tfTimer:Show()
    UpdatePartyBuffExpiryPulse(button, expirationTime - GetTime())
    if PartyAuraTimerTick then ns.Cadence:Add(partyAuraTimerDriver, 0.25, PartyAuraTimerTick) end
end

PartyAuraTimerTick = function()
    local now = GetTime()
    local any = false
    for button in pairs(activePartyAuraTimers) do
        local expirationTime = button._tfTimerExpiration
        local remaining = expirationTime and (expirationTime - now) or 0
        if remaining <= 0 or not button:IsShown() then
            local ownerFrame = button._tfAuraOwnerFrame
            if remaining <= 0 and ownerFrame then
                expiredPartyAuraFrames[ownerFrame] = true
            end
            ClearPartyAuraTimer(button)
            StopPartyBuffPulse(button)
        else
            any = true
            local text, key = FormatPartyAuraTime(remaining)
            if button._tfTimerKey ~= key then
                button._tfTimerKey = key
                button._tfTimer:SetText(text)
            end
            UpdatePartyBuffExpiryPulse(button, remaining)
        end
    end

    -- Do this after walking the active-timer table: a refresh can legitimately
    -- add/remove timer entries, so mutating that table recursively mid-iteration
    -- would make expiration handling nondeterministic.
    for frame in pairs(expiredPartyAuraFrames) do
        expiredPartyAuraFrames[frame] = nil
        if frame == PetFrame then
            if UpdatePetBuffs then UpdatePetBuffs(frame) end
            if UpdatePetDebuffs then UpdatePetDebuffs(frame) end
        else
            if UpdatePartyBuffs then UpdatePartyBuffs(frame) end
            if UpdatePartyDebuffs then UpdatePartyDebuffs(frame) end
        end
    end

    if not any and not next(activePartyAuraTimers) then
        ns.Cadence:Remove(partyAuraTimerDriver)
    end
end

local function ClampPartyBuffSetting(value, fallback, minimum, maximum)
    value = tonumber(value) or fallback
    value = math.floor(value + 0.5)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function EnsurePartyBuffContainer(frame)
    if frame._tfPartyBuffContainer then return frame._tfPartyBuffContainer end

    local container = CreateFrame("Frame", nil, frame)
    container:EnableMouse(false)
    container:SetFrameLevel((frame:GetFrameLevel() or 1) + 6)
    container.icons = {}
    frame._tfPartyBuffContainer = container
    return container
end

local function EnsurePartyDebuffContainer(frame)
    if frame._tfPartyDebuffContainer then return frame._tfPartyDebuffContainer end

    local container = CreateFrame("Frame", nil, frame)
    container:EnableMouse(false)
    container:SetFrameLevel((frame:GetFrameLevel() or 1) + 6)
    container.icons = {}
    frame._tfPartyDebuffContainer = container
    return container
end

local function EnsurePetBuffContainer(frame)
    if frame._tfPetBuffContainer then return frame._tfPetBuffContainer end

    local container = CreateFrame("Frame", nil, frame)
    container:EnableMouse(false)
    container:SetFrameLevel((frame:GetFrameLevel() or 1) + 7)
    container.icons = {}
    frame._tfPetBuffContainer = container
    return container
end

local function EnsurePetDebuffContainer(frame)
    if frame._tfPetDebuffContainer then return frame._tfPetDebuffContainer end

    local container = CreateFrame("Frame", nil, frame)
    container:EnableMouse(false)
    container:SetFrameLevel((frame:GetFrameLevel() or 1) + 7)
    container.icons = {}
    frame._tfPetDebuffContainer = container
    return container
end

-- Classic Era's pooled party-member template owns an AuraFrameContainer that
-- can acquire fresh Blizzard aura buttons after TurboFace finishes styling the
-- frame. Hiding only the buttons that exist during the first pass is therefore
-- insufficient: newly pooled debuffs reappear at Blizzard's default anchor.
-- Pin the native container itself transparent so all present and future native
-- aura children stay suppressed, while TurboFace's independent aura containers
-- remain fully visible.
local function PinPartyNativeAuraAlpha(container)
    if not container then return end
    container._tfNativePartyAurasSuppressed = true
    container:SetAlpha(0)
    if container.EnableMouse then container:EnableMouse(false) end
    if container._tfNativePartyAuraHooksInstalled then return end

    if container.SetAlpha then
        hooksecurefunc(container, "SetAlpha", function(self, alpha)
            if self._tfNativePartyAurasSuppressed and alpha ~= 0 and not self._tfNativePartyAuraAlphaGuard then
                self._tfNativePartyAuraAlphaGuard = true
                self:SetAlpha(0)
                self._tfNativePartyAuraAlphaGuard = false
            end
        end)
    end
    if container.Show then
        hooksecurefunc(container, "Show", function(self)
            if self._tfNativePartyAurasSuppressed and self:GetAlpha() ~= 0 and not self._tfNativePartyAuraAlphaGuard then
                self._tfNativePartyAuraAlphaGuard = true
                self:SetAlpha(0)
                self._tfNativePartyAuraAlphaGuard = false
            end
        end)
    end

    container._tfNativePartyAuraHooksInstalled = true
end


local function RestorePartyNativeAuraAlpha(container)
    if not container or not container._tfNativePartyAurasSuppressed then return end
    container._tfNativePartyAurasSuppressed = nil
    container._tfNativePartyAuraAlphaGuard = true
    container:SetAlpha(1)
    container._tfNativePartyAuraAlphaGuard = false
end

local function SuppressPartyNativeAuras(frame, index, skip)
    if not frame then return end
    local suppress = PartyGate() and AuraDataReadable()

    -- Current pooled Classic party frames. When UnitFrames supplies `skip`,
    -- always protect Blizzard's aura container from the generic chrome walker;
    -- only pin it invisible when the independent Party Aura surface is enabled.
    local container = frame.AuraFrameContainer or frame.auraFrameContainer
    if container then
        if suppress then PinPartyNativeAuraAlpha(container) else RestorePartyNativeAuraAlpha(container) end
        if skip then skip[container] = true end
    end

    -- Legacy globals/fields remain supported for older Classic layouts.
    for auraIndex = 1, 4 do
        local button = frame["Debuff" .. auraIndex]
            or (index and _G["PartyMemberFrame" .. index .. "Debuff" .. auraIndex])
        if button then
            if suppress then PinPartyNativeAuraAlpha(button) else RestorePartyNativeAuraAlpha(button) end
            if skip then skip[button] = true end
        end
    end
end

local function SuppressPetNativeAuras(frame, skip)
    if not frame then return end
    local suppress = PetGate() and AuraDataReadable()

    local container = frame.AuraFrameContainer or frame.auraFrameContainer
    if container then
        if suppress then PinPartyNativeAuraAlpha(container) else RestorePartyNativeAuraAlpha(container) end
        if skip then skip[container] = true end
    end

    -- Classic clients have used both frame fields and global button names for
    -- pet auras. Protect every candidate from UnitFrames' chrome walker; hide
    -- it only when the independent Pet Aura surface is enabled.
    for index = 1, PARTY_BUFF_MAX_CAP do
        local button = frame["Buff" .. index] or _G["PetFrameBuff" .. index]
        if button then
            if suppress then PinPartyNativeAuraAlpha(button) else RestorePartyNativeAuraAlpha(button) end
            if skip then skip[button] = true end
        end
    end
    for index = 1, PARTY_DEBUFF_MAX do
        local button = frame["Debuff" .. index] or _G["PetFrameDebuff" .. index]
        if button then
            if suppress then PinPartyNativeAuraAlpha(button) else RestorePartyNativeAuraAlpha(button) end
            if skip then skip[button] = true end
        end
    end
end

local function ShowPartyBuffBorder(button)
    if not button then return end
    if button._tfDebuffBorder then button._tfDebuffBorder:Hide() end
    if button._tfBuffBorder then
        button._tfBuffBorder:SetVertexColor(1, 1, 1, 1)
        button._tfBuffBorder:Show()
    end
end

local function ResolvePartyDebuffColor(debuffType)
    local key = debuffType or "none"
    local color = DebuffTypeColor and DebuffTypeColor[key]
    if color then return color.r or 0.8, color.g or 0, color.b or 0 end
    color = PARTY_DEBUFF_FALLBACK_COLORS[key] or PARTY_DEBUFF_FALLBACK_COLORS.none
    return color.r, color.g, color.b
end

local function ShowPartyDebuffBorder(button, debuffType)
    if not button then return end
    if button._tfBuffBorder then button._tfBuffBorder:Hide() end
    local border = button._tfDebuffBorder
    if not border then return end
    local r, g, b = ResolvePartyDebuffColor(debuffType)
    if border.SetColor then
        border:SetColor(r, g, b, 1)
    elseif border.SetColorTexture then
        border:SetColorTexture(r, g, b, 1)
    elseif border.SetVertexColor then
        border:SetVertexColor(r, g, b, 1)
    end
    border:Show()
end

local function EnsurePartyBuffIcon(container, index)
    local button = container.icons[index]
    if button then return button end

    button = CreateFrame("Frame", nil, container)
    button:EnableMouse(false)
    button:SetFrameLevel((container:GetFrameLevel() or 1) + 1)

    -- Helpful and harmful party auras deliberately use different border art.
    -- Buffs match Combat/ClassBuffs.lua's silver rounded reminder frame; debuffs
    -- match Blizzard's rounded UI-Debuff-Overlays ring so its vertex tint reads
    -- clearly as Magic/Curse/Disease/Poison/physical.
    local buffOutset = PARTY_BUFF_BORDER_OUTSET
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        buffOutset = PixelUtil.GetNearestPixelSize(PARTY_BUFF_BORDER_OUTSET, button:GetEffectiveScale(), 1)
    end
    local buffBorder = button:CreateTexture(nil, "ARTWORK", nil, 2)
    buffBorder:SetPoint("TOPLEFT", button, "TOPLEFT", -buffOutset, buffOutset)
    buffBorder:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", buffOutset, -buffOutset)
    buffBorder:SetTexture(PARTY_BUFF_BORDER)
    button._tfBuffBorder = buffBorder

    if ns.CreateBlizzardAuraBorder then
        button._tfDebuffBorder = ns.CreateBlizzardAuraBorder(button)
        button._tfDebuffBorder:Hide()
    else
        local debuffBorder = button:CreateTexture(nil, "OVERLAY")
        debuffBorder:SetAllPoints(button)
        debuffBorder:SetColorTexture(0.8, 0, 0, 1)
        debuffBorder:Hide()
        button._tfDebuffBorder = debuffBorder
    end

    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button._tfTexture = texture

    if button.CreateMaskTexture and texture.AddMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetAllPoints(button)
        mask:SetTexture(PARTY_BUFF_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
        button._tfIconMask = mask
    end
    ShowPartyBuffBorder(button)

    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if not ok or not cooldown then
        ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button)
    end
    if cooldown then
        -- Match the shared/nameplate aura treatment: the rounded ring sits just
        -- outside the icon, so the cooldown swipe can cover the full icon rect.
        cooldown:SetAllPoints(button)
        cooldown:EnableMouse(false)
        cooldown:SetFrameLevel((button:GetFrameLevel() or 1) + 1)
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
        if cooldown.SetDrawSwipe then cooldown:SetDrawSwipe(true) end
        if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.68) end
        if cooldown.SetReverse then cooldown:SetReverse(true) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
    end
    button._tfCooldown = cooldown

    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(button)
    textLayer:EnableMouse(false)
    textLayer:SetFrameLevel((button:GetFrameLevel() or 1) + 2)
    local count = textLayer:CreateFontString(nil, "OVERLAY")
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    button._tfCount = count

    local timer = textLayer:CreateFontString(nil, "OVERLAY")
    -- Match AuraStyle's player-unit-frame countdown: white text tucked just
    -- inside the bottom edge and rendered above the cooldown swipe.
    timer:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
    timer:SetJustifyH("CENTER")
    timer:SetTextColor(1, 1, 1, 1)
    timer:Hide()
    button._tfTimer = timer
    button._tfTextLayer = textLayer

    -- Missing class-buff reminders keep the same silver frame as other helpful
    -- auras; the pulse, not a different border color, communicates missing state.
    local pulse = button:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.4)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.4)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetOrder(2)
    button._tfPulse = pulse

    container.icons[index] = button
    return button
end

local function ClearPartyBuffCooldown(button)
    local cooldown = button and button._tfCooldown
    if not cooldown then return end
    button._tfLastExpiration = nil
    button._tfLastDuration = nil
    if CooldownFrame_Clear then
        CooldownFrame_Clear(cooldown)
    elseif cooldown.SetCooldown then
        cooldown:SetCooldown(0, 0)
    end
    cooldown:Hide()
end

local function SetPartyBuffCooldown(button, duration, expirationTime)
    local cooldown = button and button._tfCooldown
    local timed = duration and duration > 0 and expirationTime and expirationTime > 0
    if not cooldown or not timed then
        ClearPartyBuffCooldown(button)
        return false
    end

    if button._tfLastExpiration ~= expirationTime or button._tfLastDuration ~= duration then
        button._tfLastExpiration = expirationTime
        button._tfLastDuration = duration
        if CooldownFrame_Set then
            CooldownFrame_Set(cooldown, expirationTime - duration, duration, true)
        elseif cooldown.SetCooldown then
            cooldown:SetCooldown(expirationTime - duration, duration)
        end
    end
    cooldown:Show()
    return true
end

StopPartyBuffPulse = function(button)
    if not button then return end
    if button._tfPulse then button._tfPulse:Stop() end
    button:SetAlpha(1)
end

ResetPartyBuffIcon = function(button)
    if not button then return end
    ClearPartyBuffCooldown(button)
    ClearPartyAuraTimer(button)
    StopPartyBuffPulse(button)
    ShowPartyBuffBorder(button)
    if button._tfCount then
        button._tfCount:SetText("")
        button._tfCount:Hide()
    end
    button:Hide()
end

local function PartyBuffDisplayEnabled()
    return PartyGate() and (D().partyClassRemindersEnabled == true or D().partyBuffsEnabled ~= false)
end

local function PartyDebuffDisplayEnabled()
    -- Debuffs are core party-frame information and remain visible even when the
    -- optional persistent buff list is disabled.
    return PartyGate()
end

local function LayoutPartyBuffs(frame)
    local container = EnsurePartyBuffContainer(frame)
    if not PartyBuffDisplayEnabled() then
        for index = 1, #container.icons do
            ResetPartyBuffIcon(container.icons[index])
        end
        container:Hide()
        return
    end

    local classMode = D().partyClassRemindersEnabled == true
    local iconSize
    if classMode then
        iconSize = ClampPartyBuffSetting(D().partyClassBuffIconSize, 36, 20, 48)
    else
        iconSize = ClampPartyBuffSetting(D().partyBuffIconSize, 18, 10, 32)
    end
    local maxBuffs = ClampPartyBuffSetting(D().partyBuffMax, 8, 1, PARTY_BUFF_MAX_CAP)
    local perRow = ClampPartyBuffSetting(D().partyBuffsPerRow, 4, 1, 8)
    if perRow > maxBuffs then perRow = maxBuffs end

    container:ClearAllPoints()
    -- Buffs live on the left side of the party artwork. Anchor the container by
    -- its right edge so icon 1 stays nearest the frame and additional columns
    -- grow outward to the left.
    if PartyGate() and frame._tfPartyArtFrame then
        container:SetPoint("TOPRIGHT", frame._tfPartyArtFrame, "TOPLEFT", -PARTY_BUFF_GAP, -4)
    else
        container:SetPoint("TOPRIGHT", frame, "TOPLEFT", -PARTY_BUFF_GAP, -10)
    end

    local rows = math.ceil(maxBuffs / perRow)
    local columns = math.min(maxBuffs, perRow)
    container:SetSize(
        columns * iconSize + math.max(0, columns - 1) * PARTY_BUFF_SPACING,
        rows * iconSize + math.max(0, rows - 1) * PARTY_BUFF_SPACING
    )

    for index = 1, PARTY_BUFF_MAX_CAP do
        local button = container.icons[index]
        if index <= maxBuffs then
            button = EnsurePartyBuffIcon(container, index)
            button:SetSize(iconSize, iconSize)
            button:ClearAllPoints()
            local column = (index - 1) % perRow
            local row = math.floor((index - 1) / perRow)
            button:SetPoint(
                "TOPRIGHT", container, "TOPRIGHT",
                -column * (iconSize + PARTY_BUFF_SPACING),
                -row * (iconSize + PARTY_BUFF_SPACING)
            )
            ns:StyleFont(button._tfCount, nil, math.max(8, math.floor(iconSize * 0.55)), "auras")
            -- Reuse the same configured size/style as Player/Target AuraStyle.
            ns:StyleFont(button._tfTimer, nil,
                math.max(8, tonumber(TurboFaceDB and TurboFaceDB.auraTimerSize) or 14), "auras")
        elseif button then
            ResetPartyBuffIcon(button)
        end
    end

    container._tfIconSize = iconSize
    container._tfClassMode = classMode
    container._tfMaxBuffs = maxBuffs
    container._tfPerRow = perRow
end

local function LayoutPartyDebuffs(frame)
    local container = EnsurePartyDebuffContainer(frame)
    if not PartyDebuffDisplayEnabled() then
        for index = 1, #container.icons do
            ResetPartyBuffIcon(container.icons[index])
        end
        container:Hide()
        return
    end

    -- Debuffs use the normal party-aura size even when class-only reminders are
    -- enlarged. They share the same border, swipe, count, and timer treatment.
    local iconSize = ClampPartyBuffSetting(D().partyBuffIconSize, 18, 10, 32)
    local perRow = math.min(PARTY_DEBUFF_MAX,
        ClampPartyBuffSetting(D().partyBuffsPerRow, 4, 1, 8))

    container:ClearAllPoints()
    -- Debuffs are independent of the buff list and always live on the right
    -- side of the party artwork, growing outward from the frame.
    if PartyGate() and frame._tfPartyArtFrame then
        container:SetPoint("TOPLEFT", frame._tfPartyArtFrame, "TOPRIGHT", PARTY_BUFF_GAP, 0)
    else
        container:SetPoint("TOPLEFT", frame, "TOPRIGHT", PARTY_BUFF_GAP, -6)
    end

    local rows = math.ceil(PARTY_DEBUFF_MAX / perRow)
    local columns = math.min(PARTY_DEBUFF_MAX, perRow)
    container:SetSize(
        columns * iconSize + math.max(0, columns - 1) * PARTY_BUFF_SPACING,
        rows * iconSize + math.max(0, rows - 1) * PARTY_BUFF_SPACING
    )

    for index = 1, PARTY_DEBUFF_MAX do
        local button = EnsurePartyBuffIcon(container, index)
        button:SetSize(iconSize, iconSize)
        button:ClearAllPoints()
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:SetPoint(
            "TOPLEFT", container, "TOPLEFT",
            column * (iconSize + PARTY_BUFF_SPACING),
            -row * (iconSize + PARTY_BUFF_SPACING)
        )
        ns:StyleFont(button._tfCount, nil, math.max(8, math.floor(iconSize * 0.55)), "auras")
        ns:StyleFont(button._tfTimer, nil,
            math.max(8, tonumber(TurboFaceDB and TurboFaceDB.auraTimerSize) or 14), "auras")
    end

    container._tfIconSize = iconSize
    container._tfMaxDebuffs = PARTY_DEBUFF_MAX
    container._tfPerRow = perRow
end

UpdatePartyBuffs = function(frame)
    if not frame then return end
    local container = frame._tfPartyBuffContainer
    if not AuraDataReadable() then
        SuspendOwnedAuraContainer(container)
        return
    end
    if not PartyBuffDisplayEnabled() then
        if container then
            for index = 1, #container.icons do
                ResetPartyBuffIcon(container.icons[index])
            end
            container:Hide()
        end
        return
    end

    if not container or not container._tfMaxBuffs then
        -- The aura widgets are TurboFace-owned, but their layout is anchored to a
        -- protected party frame. Build/reflow them out of combat, then limit
        -- combat-time updates to textures, counts, cooldowns, and visibility.
        if InCombatLockdown and InCombatLockdown() then
            partyLayoutPending = true
            ArmDeferredLayout()
            return
        end
        container = container or EnsurePartyBuffContainer(frame)
        LayoutPartyBuffs(frame)
    end
    if not UnitBuff then
        container:Hide()
        return
    end
    local maxBuffs = container._tfMaxBuffs
        or ClampPartyBuffSetting(D().partyBuffMax, 8, 1, PARTY_BUFF_MAX_CAP)
    local id = GetPartyMemberIndex(frame)
    local unit = id and ("party" .. id)
    if not unit or not UnitExists(unit) then
        for index = 1, #container.icons do
            ResetPartyBuffIcon(container.icons[index])
        end
        container:Hide()
        return
    end

    -- Class-only mode replaces the normal aura list, but every enabled,
    -- party-capable class buff remains visible. Missing buffs use the pulsing
    -- silver reminder treatment; active buffs use the actual aura state with a
    -- cooldown swipe, white bottom countdown text, and an expiry-warning pulse.
    if D().partyClassRemindersEnabled == true then
        local states = frame._tfPartyClassBuffStates
        if not states then
            states = {}
            frame._tfPartyClassBuffStates = states
        end

        local count = 0
        if (not UnitIsConnected or UnitIsConnected(unit))
            and ns.ClassBuffs and ns.ClassBuffs.CollectPartyBuffStates then
            local _, found = ns.ClassBuffs:CollectPartyBuffStates(unit, states, maxBuffs)
            count = found or 0
        else
            wipe(states)
        end

        for index = 1, maxBuffs do
            local button = EnsurePartyBuffIcon(container, index)
            local state = states[index]
            if state and state.entry then
                button._tfTexture:SetTexture(state.texture or ns.ClassBuffs:GetReminderIcon(state.entry))
                if state.present then
                    ShowPartyBuffBorder(button)
                    if state.count and state.count > 1 then
                        button._tfCount:SetText(state.count)
                        button._tfCount:Show()
                    else
                        button._tfCount:SetText("")
                        button._tfCount:Hide()
                    end
                    if SetPartyBuffCooldown(button, state.duration, state.expirationTime) then
                        TrackPartyAuraTimer(button, state.expirationTime, frame)
                    else
                        ClearPartyAuraTimer(button)
                        StopPartyBuffPulse(button)
                    end
                else
                    ClearPartyBuffCooldown(button)
                    ClearPartyAuraTimer(button)
                    button._tfCount:SetText("")
                    button._tfCount:Hide()
                    ShowPartyBuffBorder(button)
                    StartPartyBuffPulse(button)
                end
                button:Show()
            else
                ResetPartyBuffIcon(button)
            end
        end
        for index = maxBuffs + 1, #container.icons do
            ResetPartyBuffIcon(container.icons[index])
        end

        if count > 0 then container:Show() else container:Hide() end
        return
    end

    local shown = 0
    for index = 1, maxBuffs do
        local name, texture, count, _, duration, expirationTime = UnitBuff(unit, index, "HELPFUL")
        local button = EnsurePartyBuffIcon(container, index)
        if name and texture then
            shown = shown + 1
            StopPartyBuffPulse(button)
            ShowPartyBuffBorder(button)
            button._tfTexture:SetTexture(texture)
            if count and count > 1 then
                button._tfCount:SetText(count)
                button._tfCount:Show()
            else
                button._tfCount:SetText("")
                button._tfCount:Hide()
            end

            if SetPartyBuffCooldown(button, duration, expirationTime) then
                TrackPartyAuraTimer(button, expirationTime, frame)
            else
                ClearPartyAuraTimer(button)
            end
            button:Show()
        else
            ResetPartyBuffIcon(button)
        end
    end

    for index = maxBuffs + 1, #container.icons do
        ResetPartyBuffIcon(container.icons[index])
    end

    if shown > 0 then container:Show() else container:Hide() end
end

UpdatePartyDebuffs = function(frame)
    if not frame then return end
    local container = frame._tfPartyDebuffContainer
    if not AuraDataReadable() then
        SuspendOwnedAuraContainer(container)
        return
    end
    if not PartyDebuffDisplayEnabled() then
        if container then
            for index = 1, #container.icons do
                ResetPartyBuffIcon(container.icons[index])
            end
            container:Hide()
        end
        return
    end

    if not container or not container._tfMaxDebuffs then
        if InCombatLockdown and InCombatLockdown() then
            partyLayoutPending = true
            ArmDeferredLayout()
            return
        end
        container = container or EnsurePartyDebuffContainer(frame)
        LayoutPartyDebuffs(frame)
    end
    if not UnitDebuff then
        container:Hide()
        return
    end

    local id = GetPartyMemberIndex(frame)
    local unit = id and ("party" .. id)
    if not unit or not UnitExists(unit) then
        for index = 1, #container.icons do
            ResetPartyBuffIcon(container.icons[index])
        end
        container:Hide()
        return
    end

    local shown = 0
    for index = 1, PARTY_DEBUFF_MAX do
        local name, texture, count, debuffType, duration, expirationTime = UnitDebuff(unit, index, "HARMFUL")
        local button = EnsurePartyBuffIcon(container, index)
        if name and texture then
            shown = shown + 1
            StopPartyBuffPulse(button)
            button._tfTexture:SetTexture(texture)

            ShowPartyDebuffBorder(button, debuffType)

            if count and count > 1 then
                button._tfCount:SetText(count)
                button._tfCount:Show()
            else
                button._tfCount:SetText("")
                button._tfCount:Hide()
            end

            if SetPartyBuffCooldown(button, duration, expirationTime) then
                TrackPartyAuraTimer(button, expirationTime, frame)
            else
                ClearPartyAuraTimer(button)
            end
            button:Show()
        else
            ResetPartyBuffIcon(button)
        end
    end

    for index = PARTY_DEBUFF_MAX + 1, #container.icons do
        ResetPartyBuffIcon(container.icons[index])
    end

    if shown > 0 then container:Show() else container:Hide() end
end

local function PetBuffDisplayEnabled()
    return PetGate() and D().partyBuffsEnabled ~= false
end

local function PetDebuffDisplayEnabled()
    -- Like party debuffs, pet debuffs are core combat information and do not
    -- depend on the optional persistent helpful-aura list.
    return PetGate()
end

local function LayoutPetBuffs(frame)
    local container = EnsurePetBuffContainer(frame)
    if not PetBuffDisplayEnabled() then
        for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
        container:Hide()
        return
    end

    local iconSize = ClampPartyBuffSetting(D().partyBuffIconSize, 18, 10, 32)
    local maxBuffs = ClampPartyBuffSetting(D().partyBuffMax, 8, 1, PARTY_BUFF_MAX_CAP)
    local perRow = ClampPartyBuffSetting(D().partyBuffsPerRow, 4, 1, 8)
    if perRow > maxBuffs then perRow = maxBuffs end

    container:ClearAllPoints()
    local anchor = frame._tfPetArtFrame or frame
    container:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -PARTY_BUFF_GAP, 0)
    local rows = math.ceil(maxBuffs / perRow)
    local columns = math.min(maxBuffs, perRow)
    container:SetSize(
        columns * iconSize + math.max(0, columns - 1) * PARTY_BUFF_SPACING,
        rows * iconSize + math.max(0, rows - 1) * PARTY_BUFF_SPACING
    )

    for index = 1, PARTY_BUFF_MAX_CAP do
        local button = container.icons[index]
        if index <= maxBuffs then
            button = EnsurePartyBuffIcon(container, index)
            button:SetSize(iconSize, iconSize)
            button:ClearAllPoints()
            local column = (index - 1) % perRow
            local row = math.floor((index - 1) / perRow)
            button:SetPoint("TOPRIGHT", container, "TOPRIGHT",
                -column * (iconSize + PARTY_BUFF_SPACING),
                -row * (iconSize + PARTY_BUFF_SPACING))
            ns:StyleFont(button._tfCount, nil, math.max(8, math.floor(iconSize * 0.55)), "auras")
            ns:StyleFont(button._tfTimer, nil,
                math.max(8, tonumber(TurboFaceDB and TurboFaceDB.auraTimerSize) or 14), "auras")
        elseif button then
            ResetPartyBuffIcon(button)
        end
    end

    container._tfIconSize = iconSize
    container._tfMaxBuffs = maxBuffs
    container._tfPerRow = perRow
end

local function LayoutPetDebuffs(frame)
    local container = EnsurePetDebuffContainer(frame)
    if not PetDebuffDisplayEnabled() then
        for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
        container:Hide()
        return
    end

    local iconSize = ClampPartyBuffSetting(D().partyBuffIconSize, 18, 10, 32)
    local perRow = math.min(PARTY_DEBUFF_MAX,
        ClampPartyBuffSetting(D().partyBuffsPerRow, 4, 1, 8))
    container:ClearAllPoints()
    local anchor = frame._tfPetArtFrame or frame
    container:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PARTY_BUFF_GAP, 0)
    local rows = math.ceil(PARTY_DEBUFF_MAX / perRow)
    local columns = math.min(PARTY_DEBUFF_MAX, perRow)
    container:SetSize(
        columns * iconSize + math.max(0, columns - 1) * PARTY_BUFF_SPACING,
        rows * iconSize + math.max(0, rows - 1) * PARTY_BUFF_SPACING
    )

    for index = 1, PARTY_DEBUFF_MAX do
        local button = EnsurePartyBuffIcon(container, index)
        button:SetSize(iconSize, iconSize)
        button:ClearAllPoints()
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:SetPoint("TOPLEFT", container, "TOPLEFT",
            column * (iconSize + PARTY_BUFF_SPACING),
            -row * (iconSize + PARTY_BUFF_SPACING))
        ns:StyleFont(button._tfCount, nil, math.max(8, math.floor(iconSize * 0.55)), "auras")
        ns:StyleFont(button._tfTimer, nil,
            math.max(8, tonumber(TurboFaceDB and TurboFaceDB.auraTimerSize) or 14), "auras")
    end

    container._tfIconSize = iconSize
    container._tfMaxDebuffs = PARTY_DEBUFF_MAX
    container._tfPerRow = perRow
end

UpdatePetBuffs = function(frame)
    frame = frame or PetFrame
    if not frame then return end
    local container = frame._tfPetBuffContainer
    if not AuraDataReadable() then
        SuspendOwnedAuraContainer(container)
        return
    end
    if not PetBuffDisplayEnabled() then
        if container then
            for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
            container:Hide()
        end
        return
    end
    if not container or not container._tfMaxBuffs then
        if InCombatLockdown and InCombatLockdown() then
            petLayoutPending = true
            ArmDeferredLayout()
            return
        end
        container = container or EnsurePetBuffContainer(frame)
        LayoutPetBuffs(frame)
    end
    if not UnitBuff or not UnitExists("pet") then
        for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
        container:Hide()
        return
    end

    local shown = 0
    for index = 1, container._tfMaxBuffs do
        local name, texture, count, _, duration, expirationTime = UnitBuff("pet", index, "HELPFUL")
        local button = EnsurePartyBuffIcon(container, index)
        if name and texture then
            shown = shown + 1
            StopPartyBuffPulse(button)
            ShowPartyBuffBorder(button)
            button._tfTexture:SetTexture(texture)
            if count and count > 1 then
                button._tfCount:SetText(count)
                button._tfCount:Show()
            else
                button._tfCount:SetText("")
                button._tfCount:Hide()
            end
            if SetPartyBuffCooldown(button, duration, expirationTime) then
                TrackPartyAuraTimer(button, expirationTime, frame)
            else
                ClearPartyAuraTimer(button)
            end
            button:Show()
        else
            ResetPartyBuffIcon(button)
        end
    end
    for index = container._tfMaxBuffs + 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
    if shown > 0 then container:Show() else container:Hide() end
end

UpdatePetDebuffs = function(frame)
    frame = frame or PetFrame
    if not frame then return end
    local container = frame._tfPetDebuffContainer
    if not AuraDataReadable() then
        SuspendOwnedAuraContainer(container)
        return
    end
    if not PetDebuffDisplayEnabled() then
        if container then
            for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
            container:Hide()
        end
        return
    end
    if not container or not container._tfMaxDebuffs then
        if InCombatLockdown and InCombatLockdown() then
            petLayoutPending = true
            ArmDeferredLayout()
            return
        end
        container = container or EnsurePetDebuffContainer(frame)
        LayoutPetDebuffs(frame)
    end
    if not UnitDebuff or not UnitExists("pet") then
        for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
        container:Hide()
        return
    end

    local shown = 0
    for index = 1, PARTY_DEBUFF_MAX do
        local name, texture, count, debuffType, duration, expirationTime = UnitDebuff("pet", index, "HARMFUL")
        local button = EnsurePartyBuffIcon(container, index)
        if name and texture then
            shown = shown + 1
            StopPartyBuffPulse(button)
            button._tfTexture:SetTexture(texture)
            ShowPartyDebuffBorder(button, debuffType)
            if count and count > 1 then
                button._tfCount:SetText(count)
                button._tfCount:Show()
            else
                button._tfCount:SetText("")
                button._tfCount:Hide()
            end
            if SetPartyBuffCooldown(button, duration, expirationTime) then
                TrackPartyAuraTimer(button, expirationTime, frame)
            else
                ClearPartyAuraTimer(button)
            end
            button:Show()
        else
            ResetPartyBuffIcon(button)
        end
    end
    for index = PARTY_DEBUFF_MAX + 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
    if shown > 0 then container:Show() else container:Hide() end
end

local function PreparePartyAuraFrame(frame, index, forceLayout)
    if not frame or not PartyGate() then return end
    if InCombatLockdown and InCombatLockdown() then
        partyLayoutPending = true
        ArmDeferredLayout()
        return
    end
    local buffContainer = EnsurePartyBuffContainer(frame)
    local debuffContainer = EnsurePartyDebuffContainer(frame)
    -- Re-check native ownership even after the custom surface is prepared:
    -- pooled Blizzard aura containers can be created/replaced later. The pin
    -- helper is idempotent after its first hook.
    SuppressPartyNativeAuras(frame, index)
    if forceLayout or not frame._tfPartyAuraSurfacePrepared
        or not buffContainer._tfMaxBuffs or not debuffContainer._tfMaxDebuffs then
        LayoutPartyBuffs(frame)
        LayoutPartyDebuffs(frame)
        frame._tfPartyAuraSurfacePrepared = true
    end
    UpdatePartyBuffs(frame)
    UpdatePartyDebuffs(frame)
end

local function PreparePetAuraFrame(forceLayout)
    local frame = PetFrame
    if not frame or not PetGate() then return end
    if InCombatLockdown and InCombatLockdown() then
        petLayoutPending = true
        ArmDeferredLayout()
        return
    end
    local buffContainer = EnsurePetBuffContainer(frame)
    local debuffContainer = EnsurePetDebuffContainer(frame)
    SuppressPetNativeAuras(frame)
    if forceLayout or not frame._tfPetAuraSurfacePrepared
        or not buffContainer._tfMaxBuffs or not debuffContainer._tfMaxDebuffs then
        LayoutPetBuffs(frame)
        LayoutPetDebuffs(frame)
        frame._tfPetAuraSurfacePrepared = true
    end
end

UpdateAllPetAuras = function(forceLayout)
    if not PetGate() then return end
    PreparePetAuraFrame(forceLayout == true)
    -- Lockdown defers layout, not content on already-prepared aura widgets.
    -- The content routines themselves defer first creation when necessary.
    UpdatePetBuffs(PetFrame)
    UpdatePetDebuffs(PetFrame)
end

UpdateAllPartyAuras = function(forceLayout)
    if not PartyGate() then return end
    for index = 1, 4 do
        local frame = GetPartyMemberFrame(index)
        if frame then PreparePartyAuraFrame(frame, index, forceLayout == true) end
    end
end

local function AnyPartyUnitExists()
    for index = 1, 4 do
        if UnitExists("party" .. index) then return true end
    end
    return false
end

local function UpdatePartyUnitAuras(unit)
    if not PartyGate() or type(unit) ~= "string" then return end
    local index = tonumber(unit:match("^party([1-4])$"))
    if not index then return end
    local frame = GetPartyMemberFrame(index)
    if not frame then return end
    UpdatePartyBuffs(frame)
    UpdatePartyDebuffs(frame)
end

local function RefreshReconcileCadence()
    if partyAuraEventsActive and PartyGate() and AnyPartyUnitExists() then
        ns.Cadence:Add(partyAuraReconcileDriver, PARTY_AURA_RECONCILE_INTERVAL, PartyAuraReconcileTick)
    else
        ns.Cadence:Remove(partyAuraReconcileDriver)
    end
end

PartyAuraReconcileTick = function()
    if not partyAuraEventsActive or not PartyGate() or not AnyPartyUnitExists() then
        ns.Cadence:Remove(partyAuraReconcileDriver)
        return
    end
    UpdateAllPartyAuras()
end

local function OnPartyAuraEvent(_, event, unit)
    if event == "UNIT_AURA" then
        UpdatePartyUnitAuras(unit)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        UpdateAllPartyAuras()
        RefreshReconcileCadence()
    end
end

function PartyAuras.SetActive(active)
    active = active == true
    if active == partyAuraEventsActive then
        if active then RefreshReconcileCadence() end
        return
    end

    partyAuraEventsActive = active
    if partyAuraWatch12 then partyAuraWatch12:UnregisterAllEvents() end
    if partyAuraWatch34 then partyAuraWatch34:UnregisterAllEvents() end

    if active then
        local watch12, watch34 = EnsurePartyAuraWatchers()
        ns.RegisterUnitEvent(watch12, "UNIT_AURA", "party1", "party2")
        ns.RegisterUnitEvent(watch34, "UNIT_AURA", "party3", "party4")
        ns.RegisterEvent(watch12, "GROUP_ROSTER_UPDATE")
        ns.RegisterEvent(watch12, "PLAYER_ENTERING_WORLD")
        watch12:SetScript("OnEvent", OnPartyAuraEvent)
        watch34:SetScript("OnEvent", OnPartyAuraEvent)
        RefreshReconcileCadence()
    else
        ns.Cadence:Remove(partyAuraReconcileDriver)
        ns.Cadence:Remove(partyAuraTimerDriver)
        for button in pairs(activePartyAuraTimers) do
            ClearPartyAuraTimer(button)
            StopPartyBuffPulse(button)
        end
        for index = 1, 4 do
            local frame = GetPartyMemberFrame(index)
            if frame then
                for _, container in ipairs({ frame._tfPartyBuffContainer, frame._tfPartyDebuffContainer }) do
                    if container then
                        for iconIndex = 1, #container.icons do ResetPartyBuffIcon(container.icons[iconIndex]) end
                        container:Hide()
                    end
                end
            end
        end
    end
end

local function RefreshPetReconcileCadence()
    if petAuraEventsActive and PetGate() and UnitExists("pet") then
        ns.Cadence:Add(petAuraReconcileDriver, PARTY_AURA_RECONCILE_INTERVAL, PetAuraReconcileTick)
    else
        ns.Cadence:Remove(petAuraReconcileDriver)
    end
end

PetAuraReconcileTick = function()
    if not petAuraEventsActive or not PetGate() or not UnitExists("pet") then
        ns.Cadence:Remove(petAuraReconcileDriver)
        return
    end
    UpdateAllPetAuras()
end

local function OnPetAuraEvent(_, event, unit)
    if event == "UNIT_AURA" then
        if unit == "pet" then UpdateAllPetAuras() end
    elseif event == "UNIT_PET" then
        if unit == "player" then
            UpdateAllPetAuras()
            RefreshPetReconcileCadence()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateAllPetAuras()
        RefreshPetReconcileCadence()
    end
end

function PartyAuras.SetPetActive(active)
    active = active == true
    if active == petAuraEventsActive then
        if active then RefreshPetReconcileCadence() end
        return
    end

    petAuraEventsActive = active
    if petAuraWatch then petAuraWatch:UnregisterAllEvents() end
    if active then
        local watch = EnsurePetAuraWatcher()
        ns.RegisterUnitEvent(watch, "UNIT_AURA", "pet")
        ns.RegisterUnitEvent(watch, "UNIT_PET", "player")
        ns.RegisterEvent(watch, "PLAYER_ENTERING_WORLD")
        watch:SetScript("OnEvent", OnPetAuraEvent)
        RefreshPetReconcileCadence()
    else
        ns.Cadence:Remove(petAuraReconcileDriver)
        local frame = PetFrame
        for _, container in ipairs({ frame and frame._tfPetBuffContainer, frame and frame._tfPetDebuffContainer }) do
            if container then
                for index = 1, #container.icons do ResetPartyBuffIcon(container.icons[index]) end
                container:Hide()
            end
        end
    end
end

-- Party/Pet aura surfaces are independently initialized from Core.lua. Hooks
-- below are one-way by WoW design, so module-child gate changes are reload-
-- oriented just like other protected-frame presentation gates.
local function InstallPartyFrameHooks()
    if partyFrameHooksInstalled then return end
    partyFrameHooksInstalled = true

    local function OnMemberUpdate(frame)
        if not PartyGate() then return end
        local index = GetPartyMemberIndex(frame)
        if not index then return end
        if InCombatLockdown and InCombatLockdown() then
            partyLayoutPending = true
            ArmDeferredLayout()
            return
        end
        PreparePartyAuraFrame(frame, index)
    end

    if type(PartyMemberFrameMixin) == "table" and type(PartyMemberFrameMixin.UpdateMember) == "function" then
        hooksecurefunc(PartyMemberFrameMixin, "UpdateMember", OnMemberUpdate)
    elseif type(PartyMemberFrame_UpdateMember) == "function" then
        hooksecurefunc("PartyMemberFrame_UpdateMember", OnMemberUpdate)
    end
end

local function RefreshDeferredEvent()
    if partyLayoutPending or petLayoutPending then
        ns.RegisterEvent(EnsureDeferredAuraFrame(), "PLAYER_REGEN_ENABLED")
    elseif auraDeferredFrame then
        auraDeferredFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

DeferredAuraOnEvent = function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    local doParty = partyLayoutPending
    local doPet = petLayoutPending
    partyLayoutPending = false
    petLayoutPending = false
    if auraDeferredFrame then auraDeferredFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    if doParty and PartyGate() then UpdateAllPartyAuras() end
    if doPet and PetGate() then UpdateAllPetAuras() end
    RefreshDeferredEvent()
end

function PartyAuras:Refresh()
    local partyOn = PartyGate()
    local petOn = PetGate()
    if partyOn then InstallPartyFrameHooks() end
    self.SetActive(partyOn)
    self.SetPetActive(petOn)

    if InCombatLockdown and InCombatLockdown() then
        if partyOn then partyLayoutPending = true end
        if petOn then petLayoutPending = true end
        RefreshDeferredEvent()
        return
    end

    if partyOn then UpdateAllPartyAuras(true) end
    if petOn then UpdateAllPetAuras(true) end
end

function PartyAuras:Init()
    -- The party-frame hook is irreversible, so do not install it for a profile
    -- that starts with party auras disabled. Refresh installs it on live enable.
    self:Refresh()
end

-- PartyAuras owns the event boundary now. The public full-refresh entry point is
-- still kill-traced separately because options/ClassBuffs can request it outside
-- the unit-event path.
local function TracePartyAuraUpdate()
    ns.KillTrace("Auras/PartyPet:", "UpdateAll", UpdateAllPartyAuras)
end

local function UpdateAllPartyBuffs()
    TracePartyAuraUpdate()
end

PartyAuras.EnsureBuffContainer = EnsurePartyBuffContainer
PartyAuras.EnsureDebuffContainer = EnsurePartyDebuffContainer
PartyAuras.SuppressNativeAuras = SuppressPartyNativeAuras
PartyAuras.LayoutBuffs = LayoutPartyBuffs
PartyAuras.LayoutDebuffs = LayoutPartyDebuffs
PartyAuras.UpdateBuffs = UpdatePartyBuffs
PartyAuras.UpdateDebuffs = UpdatePartyDebuffs
PartyAuras.UpdateAll = UpdateAllPartyBuffs
PartyAuras.EnsurePetBuffContainer = EnsurePetBuffContainer
PartyAuras.EnsurePetDebuffContainer = EnsurePetDebuffContainer
PartyAuras.SuppressPetNativeAuras = SuppressPetNativeAuras
PartyAuras.LayoutPetBuffs = LayoutPetBuffs
PartyAuras.LayoutPetDebuffs = LayoutPetDebuffs
PartyAuras.UpdatePetBuffs = UpdatePetBuffs
PartyAuras.UpdatePetDebuffs = UpdatePetDebuffs
PartyAuras.UpdateAllPet = UpdateAllPetAuras

ns.RegisterCPUProfileTarget("Auras/PartyPet:TimerTick", PartyAuraTimerTick)
ns.RegisterCPUProfileTarget("Auras/PartyPet:UpdateBuffs", UpdatePartyBuffs)
ns.RegisterCPUProfileTarget("Auras/PartyPet:UpdateDebuffs", UpdatePartyDebuffs)
ns.RegisterCPUProfileTarget("Auras/PartyPet:UpdateAll", UpdateAllPartyAuras)
ns.RegisterCPUProfileTarget("Auras/PartyPet:Reconcile", PartyAuraReconcileTick)
ns.RegisterCPUProfileTarget("Auras/Pet:UpdateAll", UpdateAllPetAuras)
ns.RegisterCPUProfileTarget("Auras/Pet:Reconcile", PetAuraReconcileTick)
