local _, ns = ...

local compat = ns.Compat
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true) then return end

-- =============================================================================
-- WoW Forever native-safe nameplate adapter
-- =============================================================================
-- Forever nameplates are pooled Blizzard CompactUnitFrames. Health/max-health
-- and other gameplay values can become secret in combat, and mutating the
-- Blizzard UnitFrame/healthBar (including attaching addon fields/children) can
-- taint Blizzard's later CompactUnitFrame work.
--
-- Ownership rule for this adapter:
--   * Blizzard owns the nameplate root, UnitFrame, health/power/cast/aura frames,
--     names, classification art, and every secret gameplay value.
--   * TurboFace stores state only in external Lua side tables.
--   * TurboFace visuals are UIParent-owned detached frames that may ANCHOR TO
--     Blizzard regions but never mutate them.
--   * No GetPoint/GetLeft/GetRight/GetCenter/geometry measurement is performed
--     on Blizzard nameplate regions.
--   * Nameplate geometry/selection preferences use Blizzard CVars only.
--
-- This Forever baseline restores the options that fit that ownership
-- model: overlap/selection CVars, combo points, friendly NPC title/job icon,
-- detached current-health text, threat number, aggro audio, and enemy swing
-- timing. Options that
-- inherently rewrite Blizzard-owned regions stay dormant until a separate safe
-- strategy exists (rarity-icon relocation, damaged-only chassis suppression,
-- and native power-bar geometry).
-- =============================================================================

local FNP = {
    initialized = false,
    runtimeActive = false,
    eventsRegistered = 0,
    refreshCount = 0,
    addedCount = 0,
    removedCount = 0,
    lastReason = "startup",
    lastError = nil,
    statesByRoot = setmetatable({}, { __mode = "k" }),
    statesByUnit = {},
    activeSwing = {},
    aggroByGUID = {},
}
ns.ForeverNameplates = FNP

local API = ns.API
local BNP = ns.BubbleNameplates
local CreateFrame = CreateFrame
local GetTime = GetTime
local floor = math.floor
local max = math.max
local min = math.min

local ROOT = "Interface\\AddOns\\TurboFace\\Textures\\BubbleNameplates\\"
local SOUND_ROOT = "Interface\\AddOns\\TurboFace\\Sounds\\BubbleNameplates\\"
local TEX_ATTACK_READY = ROOT .. "Nameplate-AttackIndicator.tga"
local TEX_SWING = ROOT .. "Nameplate-SwingGlow.tga"
local TEX_COMBO = "Interface\\AddOns\\TurboFace\\Textures\\Circle_White"
local SOUND_GAIN = SOUND_ROOT .. "GainAggro.mp3"
local SOUND_LOSS = SOUND_ROOT .. "LoseAggro.mp3"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The native root includes the name row above the health chassis. Its center
-- is six UI units above the health-text row on Forever's fixed plate layout.
local WHOLE_PLATE_HEALTH_TEXT_Y = -6

local _, PLAYER_CLASS = API.ReadUnitClass("player")
local COMBO_CLASS = PLAYER_CLASS == "ROGUE" or PLAYER_CLASS == "DRUID"
local IS_DRUID = PLAYER_CLASS == "DRUID"
local MAX_CP = 5

local DEFERRED_OPTIONS = {
    "rarityIconRight",
    "friendlyPlayerDamagedOnly",
    "friendlyNPCDamagedOnly",
    "powerBarOverlap",
    "powerBarHeightPct",
}

local function Enabled()
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("nameplates")
end

local function BubbleDB()
    local root = type(TurboFaceDB) == "table" and TurboFaceDB or ns.defaults or {}
    local db = root.bubbleNameplates
    if type(db) ~= "table" then
        db = (ns.defaults and ns.defaults.bubbleNameplates) or {}
    end
    return db
end

local function Safe(label, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        FNP.lastError = label .. ": " .. tostring(a)
        return false
    end
    return true, a, b, c, d
end

local function RunNextFrame(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0, fn) else fn() end
end

-- Register the Forever nameplate substrate behind the shared provider contract.
-- Shared nameplate code can now ask how work must be staged without branching
-- on the client flavor or touching this detached adapter directly.
function FNP:IsSupported()
    return true
end

function FNP:UsesLegacyAuraRows()
    return false
end

function FNP:DeferPowerUpdates()
    return true
end

function FNP:DeferHealPrediction()
    return true
end

function FNP:AfterNativeUpdate(fn)
    if type(fn) == "function" then RunNextFrame(fn) end
end

function FNP:ScheduleBatch(fn)
    if type(fn) == "function" then RunNextFrame(fn) end
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("nameplates", "forever-detached", FNP, 100)
end

local function NativePlate(unit)
    if not unit or not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil
end

local function NativeRegions(root)
    local uf = root and root.UnitFrame
    if not uf then return nil end
    local hc = uf.HealthBarsContainer
    local hp = uf.healthBar or (hc and (hc.healthBar or hc.HealthBar))
    local power = uf.powerBar or (uf.PowerBar) or (uf.PowerBarsContainer and uf.PowerBarsContainer.PowerBar)
    local name = uf.name or uf.Name
    return uf, hp, power, name
end

local function StateFor(root)
    if not root then return nil end
    local st = FNP.statesByRoot[root]
    if not st then
        st = { root = root }
        FNP.statesByRoot[root] = st
    end
    return st
end

local function EnsureOverlay(st)
    if st.overlay then return st.overlay end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:EnableMouse(false)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    st.overlay = f
    return f
end

local function AttachOverlay(st)
    local f = EnsureOverlay(st)
    f:ClearAllPoints()
    -- Write-only anchor: this changes only TurboFace's detached frame. We never
    -- query the native plate's position/size.
    f:SetPoint("CENTER", st.root, "CENTER", 0, 0)
    f:Show()
    return f
end

local function HideState(st)
    if not st then return end
    if FNP.Auras then FNP.Auras:Release(st) end
    if st.overlay then st.overlay:Hide() end
    FNP.activeSwing[st] = nil
end

local function UpdateNameShadow(st)
    -- Forever's native name FontString now supplies its own shadow. Older
    -- adapter builds simulated that missing treatment by drawing a second copy
    -- of the unit name, which now visibly duplicates every NPC label. Never
    -- create that workaround on Forever; hide an existing session object when
    -- upgrading through a live options refresh.
    if st and st.nameShadow then st.nameShadow:Hide() end
end

local function EnsureHealthText(st)
    if st.healthText then return st.healthText end
    local f = EnsureOverlay(st):CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    f:SetTextColor(1, 1, 1, 1)
    f:SetShadowColor(0, 0, 0, 1)
    f:SetShadowOffset(1, -1)
    f:SetJustifyH("CENTER")
    f:SetWordWrap(false)
    st.healthText = f
    return f
end

local function UpdateHealthText(st, hp)
    local f = EnsureHealthText(st)
    if ns.c_nameplateCenterHealthText == false or not hp or not st.unit
        or type(API.WriteUnitHealthText) ~= "function"
    then
        f:Hide()
        return
    end

    -- Forever's HealthBarsContainer and health fill report the same center, so
    -- using the container made both options visually identical. The detached
    -- overlay is already anchored CENTER-to-CENTER on the Blizzard nameplate
    -- root; use that safe addon-owned point for the whole-plate choice.
    local target = ns.c_nameplateCenterHealthTextOnNameplate ~= false
        and EnsureOverlay(st) or hp
    if not target then
        f:Hide()
        return
    end

    f:ClearAllPoints()
    local yOffset = ns.c_nameplateCenterHealthTextOnNameplate ~= false
        and WHOLE_PLATE_HEALTH_TEXT_Y or 0
    f:SetPoint("CENTER", target, "CENTER", 0, yOffset)
    local written, err = API.WriteUnitHealthText(f, st.unit)
    if written then
        f:Show()
        st.healthTextError = nil
    else
        f:Hide()
        st.healthTextError = err
    end
end

local function NPCIDFromUnit(unit)
    local guid = API.ReadUnitGUID(unit)
    if type(guid) ~= "string" then return nil end
    local id = select(6, strsplit("-", guid))
    return id and tonumber(id) or nil
end

local function FriendlyNPC(unit)
    local isPlayer = API.ReadUnitIsPlayer(unit)
    if isPlayer ~= false then return false end
    local controlled = API.ReadUnitPlayerControlled(unit)
    if controlled == true then return false end
    return API.ReadUnitIsFriend("player", unit) == true
end

local function GetCachedTitle(unit)
    if not FriendlyNPC(unit) then return nil end
    local id = NPCIDFromUnit(unit)
    if not id then return nil end
    local cache = ns.c_npcTitleCache
    local title = type(cache) == "table" and cache[id] or nil
    if type(title) == "string" and title ~= "" then return title end
    if ns.QueueNPCTitleScan then ns.QueueNPCTitleScan(id, unit) end
    return nil
end

local function EnsureTitle(st)
    if st.title then return st.title end
    local f = EnsureOverlay(st):CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 8, "")
    f:SetTextColor(0.72, 0.72, 0.72, 1)
    f:SetJustifyH("CENTER")
    f:SetWordWrap(false)
    st.title = f
    return f
end

local function UpdateTitle(st, nameRegion)
    local f = EnsureTitle(st)
    if not ns.c_nameplateFriendlyNPCNameTitleOnly or not nameRegion or not FriendlyNPC(st.unit) then
        f:Hide()
        return nil
    end
    local title = GetCachedTitle(st.unit)
    if not title then
        f:Hide()
        return nil
    end
    f:ClearAllPoints()
    f:SetPoint("TOP", nameRegion, "BOTTOM", 0, -1)
    f:SetText("<" .. title .. ">")
    f:Show()
    return title
end

local function EnsureJob(st)
    if st.jobFrame then return st.jobFrame end
    local f = CreateFrame("Frame", nil, EnsureOverlay(st))
    f:SetSize(12, 12)
    f:EnableMouse(false)
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetAllPoints(f)
    st.jobFrame = f
    return f
end

local function UpdateJob(st, nameRegion, knownTitle)
    local f = EnsureJob(st)
    if not ns.c_nameplateJobIcon or not nameRegion or not FriendlyNPC(st.unit)
        or not BNP or type(BNP.ResolveJob) ~= "function" or type(BNP.SetJobTexture) ~= "function"
    then
        f:Hide()
        return
    end
    local title = knownTitle
    if title == nil then title = GetCachedTitle(st.unit) end
    local kind = BNP.ResolveJob(st.unit, title)
    if not kind then
        f:Hide()
        return
    end
    BNP.SetJobTexture(f.icon, kind)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", nameRegion, "LEFT", -4, 0)
    f:Show()
end

local function EnsureThreat(st)
    if st.threat then return st.threat end
    local f = EnsureOverlay(st):CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ns.c_nameplateThreatFontSize or 6, "OUTLINE")
    f:SetJustifyH("RIGHT")
    f:SetTextColor(0.2, 1, 0.2, 1)
    st.threat = f
    return f
end

local function ThreatEligible(unit)
    if not unit then return false end
    if API.ReadUnitIsPlayer(unit) == true then return false end
    if API.ReadUnitPlayerControlled(unit) == true then return false end
    if API.ReadUnitCanAttack("player", unit) ~= true then return false end
    return true
end

local function AddThreatAlias(list, token)
    if API.ReadUnitExists(token) == true then list[#list + 1] = token end
end

local function CollectThreatAliases()
    local list = {}
    AddThreatAlias(list, "target")
    AddThreatAlias(list, "focus")
    AddThreatAlias(list, "mouseover")
    AddThreatAlias(list, "pettarget")

    local inRaid, inGroup = false, false
    if IsInRaid then
        local ok, value = pcall(IsInRaid)
        inRaid = ok and value == true
    end
    if not inRaid and IsInGroup then
        local ok, value = pcall(IsInGroup)
        inGroup = ok and value == true
    end

    local count = 0
    if (inRaid or inGroup) and GetNumGroupMembers then
        local ok, value = pcall(GetNumGroupMembers)
        if ok and API.IsReadableNumber(value) then count = max(0, floor(value)) end
    end
    if inRaid then
        for i = 1, count do AddThreatAlias(list, "raid" .. i .. "target") end
    elseif inGroup then
        for i = 1, max(0, count - 1) do AddThreatAlias(list, "party" .. i .. "target") end
    end
    return list
end

local function ResolveThreatAlias(unit, aliases)
    if not unit then return nil end
    aliases = aliases or CollectThreatAliases()
    for i = 1, #aliases do
        if API.ReadUnitIsUnit(unit, aliases[i]) == true then return aliases[i] end
    end
    return nil
end

local function SetThreatColor(f, value)
    local display = min(200, max(0, floor((value or 0) + 0.5)))
    local r, g, b = 0.2, 1, 0.2
    if display > 180 then r, g, b = 0.65, 0.2, 1
    elseif display > 145 then r, g, b = 0.2, 0.45, 1
    elseif display > 100 then r, g, b = 1, 0.55, 0.1
    elseif display >= 100 then r, g, b = 1, 0, 0
    elseif display >= 71 then r, g, b = 1, 0.55, 0.1
    elseif display >= 31 then r, g, b = 1, 0.95, 0.2 end
    f:SetTextColor(r, g, b, 1)
end

local function PlayAggro(gained)
    if not ns.c_nameplateAggroSounds or not ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())) then return end
    local volume = gained and ns.c_nameplateAggroGainVolume or ns.c_nameplateAggroLossVolume
    volume = tonumber(volume) or 0
    if volume <= 0 then return end
    local ok, played, handle = pcall(PlaySoundFile, gained and SOUND_GAIN or SOUND_LOSS, "Master")
    if ok and played and handle and C_Sound and C_Sound.SetSoundVolume then
        pcall(C_Sound.SetSoundVolume, handle, volume)
    end
end

local function UpdateThreat(st, hp, aliases)
    local f = EnsureThreat(st)
    local db = BubbleDB()
    local wantsNumber = db.threatNumber ~= false and ThreatEligible(st.unit)
    local isTarget = API.ReadUnitIsUnit(st.unit, "target") == true
    local wantsAudio = isTarget and ns.c_nameplateAggroSounds
        and ((IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()))

    if not wantsNumber and not wantsAudio then
        f:Hide()
        st.threatToken = nil
        return
    end

    -- Direct nameplateN threat queries are secret on Forever. Resolve the plate
    -- to a stable public mob alias before entering the compatibility boundary.
    local mobToken = ResolveThreatAlias(st.unit, aliases)
    if not mobToken then
        f:Hide()
        st.threatToken = nil
        if st.guid then FNP.aggroByGUID[st.guid] = nil end
        return
    end
    st.threatToken = mobToken
    local tanking, status, scaled = API.ReadUnitThreatPercent("player", mobToken)
    if tanking == nil and status == nil and scaled == nil then
        f:Hide()
        if st.guid then FNP.aggroByGUID[st.guid] = nil end
        return
    end

    local value = tonumber(scaled)
    if value == nil then
        local s = tonumber(status) or 0
        value = s > 0 and (s / 3 * 100) or 0
    end
    if tanking == true and value < 100 then value = 100 end
    value = min(200, max(0, value))

    if wantsNumber and hp then
        local size = tonumber(ns.c_nameplateThreatFontSize) or 6
        f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        f:ClearAllPoints()
        f:SetPoint("RIGHT", hp, "LEFT", -5, 0)
        f:SetFormattedText("%.0f", value)
        SetThreatColor(f, value)
        f:Show()
    else
        f:Hide()
    end

    if wantsAudio and st.guid then
        local old = FNP.aggroByGUID[st.guid]
        if old ~= nil and old ~= tanking then PlayAggro(tanking == true) end
        FNP.aggroByGUID[st.guid] = tanking == true
    elseif st.guid then
        FNP.aggroByGUID[st.guid] = nil
    end
end

local function EnsureCombo(st)
    if st.combo then return st.combo end
    local f = CreateFrame("Frame", nil, EnsureOverlay(st))
    f:SetSize(43, 7)
    f:EnableMouse(false)
    f.dots = {}
    for i = 1, MAX_CP do
        local d = f:CreateTexture(nil, "OVERLAY")
        d:SetTexture(TEX_COMBO)
        d:SetSize(7, 7)
        d:SetPoint("LEFT", f, "LEFT", (i - 1) * 9, 0)
        f.dots[i] = d
    end
    st.combo = f
    return f
end

local function ComboAllowed(st)
    if not COMBO_CLASS or ns.c_showComboPoints == false then return false end
    if not st or API.ReadUnitIsUnit(st.unit, "target") ~= true then return false end
    if IS_DRUID and GetShapeshiftFormID then
        local ok, form = pcall(GetShapeshiftFormID)
        if not ok or form ~= (CAT_FORM or 1) then return false end
    end
    return true
end

local function UpdateCombo(st, nameRegion, hp)
    local f = EnsureCombo(st)
    if not ComboAllowed(st) then f:Hide(); return false end
    local cp = API.GetComboPoints and API.GetComboPoints("player", "target") or nil
    if type(cp) ~= "number" then f:Hide(); return false end
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", nameRegion or hp or st.root, "TOP", 0, 3)
    for i = 1, MAX_CP do
        if i <= cp then f.dots[i]:SetVertexColor(0.90, 0.10, 0.10, 1)
        else f.dots[i]:SetVertexColor(0.35, 0.35, 0.35, 0.45) end
    end
    f:Show()
    return true
end

local function EnsureSwing(st)
    if st.swing then return st.swing end
    local f = CreateFrame("Frame", nil, EnsureOverlay(st))
    f:SetHeight(3)
    f:EnableMouse(false)

    f.progress = CreateFrame("StatusBar", nil, f)
    f.progress:SetAllPoints(f)
    f.progress:SetMinMaxValues(0, 1)
    f.progress:SetStatusBarTexture(TEX_SWING)
    f.progress:SetStatusBarColor(1, 1, 1, 0.8)

    f.ready = f:CreateTexture(nil, "OVERLAY")
    f.ready:SetTexture(TEX_ATTACK_READY)
    f.ready:SetSize(10, 10)
    f.ready:SetPoint("CENTER", f, "RIGHT", 7, 0)
    f.ready:Hide()

    st.swing = f
    return f
end

local function StopSwing(st)
    FNP.activeSwing[st] = nil
    if st and st.swing then st.swing:Hide() end
end

function FNP:RefreshSwingState(st)
    if not st or not st.unit or ns.c_nameplateSwingTimer == false
        or API.ReadUnitCanAttack("player", st.unit) ~= true
    then
        StopSwing(st)
        return
    end
    local guid = st.guid
    local owner = ns.SwingTimers
    local state = guid and owner and owner.GetNameplateState and owner:GetNameplateState(guid)
    if not state and guid and owner and owner.PrimeNameplateState then
        state = owner:PrimeNameplateState(guid, st.unit)
    end
    if not state or not state.readyAt then
        StopSwing(st)
        return
    end
    st.swingState = state
    FNP.activeSwing[st] = true
    self:UpdateSwingVisual(st, GetTime())
    self:RefreshSwingDriver()
end

function FNP:UpdateSwingVisual(st, now)
    local state = st and st.swingState
    local _, hp = NativeRegions(st and st.root)
    if not state or not hp or not st.unit or not st.guid then StopSwing(st); return end
    if API.ReadUnitGUID(st.unit) ~= st.guid then StopSwing(st); return end

    local f = EnsureSwing(st)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -1)
    f:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -1)

    local remaining = (state.readyAt or now) - now
    local duration = max(0.1, tonumber(state.duration) or 2)
    local inCombat = false
    if UnitAffectingCombat then
        local ok, value = pcall(UnitAffectingCombat, "player")
        if ok and API.CanAccessValue(value) then inCombat = value == true end
    end
    if remaining > 0 then
        local progress = 1 - min(1, remaining / duration)
        f.progress:SetValue(progress)
        f.progress:Show()
        f.ready:Hide()
        f:Show()
    elseif inCombat then
        f.progress:Hide()
        f.ready:Show()
        f:Show()
    else
        StopSwing(st)
    end
end

function FNP:SwingTick()
    if not Enabled() or ns.c_nameplateSwingTimer == false then
        for st in pairs(self.activeSwing) do StopSwing(st) end
        self:RefreshSwingDriver()
        return
    end
    local now = GetTime()
    local any = false
    for st in pairs(self.activeSwing) do
        any = true
        self:UpdateSwingVisual(st, now)
    end
    if not any then self:RefreshSwingDriver() end
end

function FNP:RefreshSwingDriver()
    if not ns.Cadence then return end
    if next(self.activeSwing) and Enabled() and ns.c_nameplateSwingTimer ~= false then
        ns.Cadence:Add("TurboFaceForeverNameplateSwing", 1 / 30, function() FNP:SwingTick() end, true)
    else
        ns.Cadence:Remove("TurboFaceForeverNameplateSwing")
    end
end

function FNP:RefreshComboDriver()
    if not ns.Cadence then return end
    local targetState
    for _, st in pairs(self.statesByUnit) do
        if ComboAllowed(st) then targetState = st break end
    end
    if targetState then
        ns.Cadence:Add("TurboFaceForeverNameplateCombo", 0.10, function()
            local st = FNP.statesByUnit.target
            if not st then
                for _, candidate in pairs(FNP.statesByUnit) do
                    if API.ReadUnitIsUnit(candidate.unit, "target") == true then st = candidate break end
                end
            end
            if st then
                local _, hp, _, name = NativeRegions(st.root)
                UpdateCombo(st, name, hp)
            end
        end, true)
    else
        ns.Cadence:Remove("TurboFaceForeverNameplateCombo")
    end
end

function FNP:ThreatTick()
    if not Enabled() or (ns.c_nameplateThreatNumber == false and not ns.c_nameplateAggroSounds) then
        for _, st in pairs(self.statesByUnit) do
            if st.threat then st.threat:Hide() end
            if st.guid then self.aggroByGUID[st.guid] = nil end
        end
        self:RefreshThreatDriver()
        return
    end

    local aliases = CollectThreatAliases()
    self.lastThreatAliasCount = #aliases
    for _, st in pairs(self.statesByUnit) do
        local _, hp = NativeRegions(st.root)
        UpdateThreat(st, hp, aliases)
    end
end

function FNP:RefreshThreatDriver()
    if not ns.Cadence then return end
    local wanted = next(self.statesByUnit) and Enabled()
        and (ns.c_nameplateThreatNumber ~= false or ns.c_nameplateAggroSounds)
    if wanted then
        ns.Cadence:Add("TurboFaceForeverNameplateThreat", 0.20, function()
            FNP:ThreatTick()
        end, true)
    else
        ns.Cadence:Remove("TurboFaceForeverNameplateThreat")
    end
end

function FNP:Bind(unit, root, reason)
    if not Enabled() or not unit or not root then return end
    local st = StateFor(root)

    -- A pooled root may have belonged to another token previously. Remove only
    -- our external mapping; never stamp lifecycle fields onto the Blizzard root.
    if st.unit and st.unit ~= unit and self.statesByUnit[st.unit] == st then
        self.statesByUnit[st.unit] = nil
    end

    st.unit = unit
    st.guid = API.ReadUnitGUID(unit)
    st.lastReason = reason or "bind"
    self.statesByUnit[unit] = st
    AttachOverlay(st)

    ns.unitToNameplate = ns.unitToNameplate or {}
    ns.unitToNameplateGUID = ns.unitToNameplateGUID or {}
    ns.guidToNameplateUnit = ns.guidToNameplateUnit or {}
    ns.unitToNameplate[unit] = root
    ns.unitToNameplateGUID[unit] = st.guid
    if st.guid then ns.guidToNameplateUnit[st.guid] = unit end

    local _, hp, _, nameRegion = NativeRegions(root)
    UpdateNameShadow(st, nameRegion)
    UpdateHealthText(st, hp)
    local title = UpdateTitle(st, nameRegion)
    UpdateJob(st, nameRegion, title)
    UpdateThreat(st, hp)
    UpdateCombo(st, nameRegion, hp)
    self:RefreshSwingState(st)
    if self.Auras then self.Auras:Bind(st, hp) end
    self:RefreshThreatDriver()

    self.addedCount = self.addedCount + 1
end

function FNP:Remove(unit, reason)
    local st = unit and self.statesByUnit[unit]
    if not st then return end
    self.statesByUnit[unit] = nil
    HideState(st)
    if st.guid then
        if ns.guidToNameplateUnit and ns.guidToNameplateUnit[st.guid] == unit then
            ns.guidToNameplateUnit[st.guid] = nil
        end
        self.aggroByGUID[st.guid] = nil
    end
    if ns.unitToNameplate then ns.unitToNameplate[unit] = nil end
    if ns.unitToNameplateGUID then ns.unitToNameplateGUID[unit] = nil end
    st.unit = nil
    st.guid = nil
    st.swingState = nil
    st.lastReason = reason or "remove"
    self.removedCount = self.removedCount + 1
    self:RefreshSwingDriver()
    self:RefreshComboDriver()
    self:RefreshThreatDriver()
    if self.Auras then self.Auras:RefreshCount() end
end

function FNP:RefreshUnit(unit, reason)
    if not Enabled() then return end
    local root = NativePlate(unit)
    if not root then
        self:Remove(unit, reason or "missing")
        return
    end
    self:Bind(unit, root, reason or "refresh-unit")
end

function FNP:RefreshAll(reason)
    self.refreshCount = self.refreshCount + 1
    self.lastReason = reason or "refresh-all"

    if ns.UpdateDBCache then ns:UpdateDBCache() end
    if BNP and BNP.ApplyNameplateCVars then Safe("ApplyNameplateCVars", BNP.ApplyNameplateCVars, BNP) end

    if not Enabled() then
        local unit = next(self.statesByUnit)
        while unit do
            self:Remove(unit, "disabled")
            unit = next(self.statesByUnit)
        end
        self:RefreshSwingDriver()
        self:RefreshComboDriver()
        self:RefreshThreatDriver()
        return
    end

    local seen = {}
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, root in ipairs(plates) do
                local unit = API.GetPlateUnitToken and API.GetPlateUnitToken(root) or nil
                if unit and API.ReadUnitExists(unit) == true then
                    seen[unit] = true
                    self:Bind(unit, root, reason or "refresh-all")
                end
            end
        end
    end
    local stale = {}
    for unit in pairs(self.statesByUnit) do
        if not seen[unit] then stale[#stale + 1] = unit end
    end
    for i = 1, #stale do self:Remove(stale[i], "stale") end
    self:RefreshComboDriver()
    self:RefreshThreatDriver()
    if self.Auras then self.Auras:RefreshCount() end
end

function FNP:OnEnemySwing(guid)
    local unit = guid and ns.guidToNameplateUnit and ns.guidToNameplateUnit[guid]
    local st = unit and self.statesByUnit[unit]
    if st then self:RefreshSwingState(st) end
end

function FNP:Refresh()
    if not self.initialized then
        self:Init()
        return
    end
    if Enabled() then self:ActivateRuntime() else self:DeactivateRuntime() end
    self:RefreshAll("options")
end

local eventFrame = CreateFrame("Frame")
FNP.eventFrame = eventFrame

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        RunNextFrame(function()
            if Enabled() then FNP:RefreshUnit(unit, "added") end
        end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        FNP:Remove(unit, "removed")
    elseif event == "PLAYER_ENTERING_WORLD" then
        RunNextFrame(function() FNP:RefreshAll("enter-world") end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        RunNextFrame(function()
            FNP:ThreatTick()
            for _, st in pairs(FNP.statesByUnit) do
                local _, hp, _, name = NativeRegions(st.root)
                UpdateCombo(st, name, hp)
            end
            FNP:RefreshComboDriver()
        end)
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        FNP:ThreatTick()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local st = unit and FNP.statesByUnit[unit]
        if st then local _, hp = NativeRegions(st.root); UpdateHealthText(st, hp) end
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_FACTION" then
        local st = unit and FNP.statesByUnit[unit]
        if st then
            local _, hp, _, name = NativeRegions(st.root)
            UpdateNameShadow(st, name)
            local title = UpdateTitle(st, name)
            UpdateJob(st, name, title)
            UpdateThreat(st, hp)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        FNP:RefreshThreatDriver()
        FNP:ThreatTick()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
            if unit ~= "player" then return end
        end
        for _, st in pairs(FNP.statesByUnit) do
            if API.ReadUnitIsUnit(st.unit, "target") == true then
                local _, hp, _, name = NativeRegions(st.root)
                UpdateCombo(st, name, hp)
                break
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- NPC title scans deferred by Core may complete immediately after combat.
        RunNextFrame(function() FNP:RefreshAll("regen") end)
    end
end)

local RUNTIME_EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_NAME_UPDATE", "UNIT_FACTION", "GROUP_ROSTER_UPDATE", "UPDATE_SHAPESHIFT_FORM",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "PLAYER_REGEN_ENABLED",
}

function FNP:ActivateRuntime()
    if self.runtimeActive or not Enabled() then return end
    self.runtimeActive = true
    self.eventsRegistered = 0
    for i = 1, #RUNTIME_EVENTS do
        if API.RegisterEvent(eventFrame, RUNTIME_EVENTS[i]) then
            self.eventsRegistered = self.eventsRegistered + 1
        end
    end
end

function FNP:DeactivateRuntime()
    if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
    self.runtimeActive = false
    self.eventsRegistered = 0
    if ns.Cadence then
        ns.Cadence:Remove("TurboFaceForeverNameplateSwing")
        ns.Cadence:Remove("TurboFaceForeverNameplateCombo")
        ns.Cadence:Remove("TurboFaceForeverNameplateThreat")
    end
end

function FNP:Init()
    if self.initialized then return end
    self.initialized = true
    if Enabled() then self:ActivateRuntime() end

    -- Existing systems publish enemy swing snapshots through BubbleNameplates.
    -- Replace only those public callbacks; the Era renderer itself never starts.
    if BNP then
        BNP.OnEnemySwing = function(_, guid) FNP:OnEnemySwing(guid) end
        BNP.RefreshSwingFeature = function() FNP:RefreshAll("swing-option") end
        BNP.OnTargetChanged = function() FNP:RefreshAll("target-change") end
    end

    self:RefreshAll("init")
end

function FNP:GetDiagnostics()
    local visible, swing, healthTextVisible, threatVisible, threatMapped = 0, 0, 0, 0, 0
    local healthTextError
    for _, st in pairs(self.statesByUnit) do
        if st.overlay and st.overlay:IsShown() then visible = visible + 1 end
        if st.healthText and st.healthText:IsShown() then healthTextVisible = healthTextVisible + 1 end
        if st.threat and st.threat:IsShown() then threatVisible = threatVisible + 1 end
        if st.threatToken then threatMapped = threatMapped + 1 end
        if st.healthTextError then healthTextError = st.healthTextError end
    end
    for _ in pairs(self.activeSwing) do swing = swing + 1 end
    return {
        mode = "forever-detached-native",
        initialized = self.initialized,
        runtimeActive = self.runtimeActive,
        enabled = Enabled(),
        visible = visible,
        events = self.eventsRegistered,
        refreshCount = self.refreshCount,
        activeSwing = swing,
        cvars = BNP and type(BNP.ApplyNameplateCVars) == "function",
        combo = COMBO_CLASS and ns.c_showComboPoints ~= false,
        jobIcon = ns.c_nameplateJobIcon == true,
        threat = ns.c_nameplateThreatNumber ~= false,
        threatVisible = threatVisible,
        threatMapped = threatMapped,
        threatAliases = self.lastThreatAliasCount or 0,
        swing = ns.c_nameplateSwingTimer == true,
        healthText = ns.c_nameplateCenterHealthText ~= false,
        healthTextVisible = healthTextVisible,
        healthTextError = healthTextError,
        nameShadow = "blizzard-native",
        title = ns.c_nameplateFriendlyNPCNameTitleOnly == true,
        aurasSupported = self.Auras and self.Auras.supported == true,
        aurasActive = self.Auras and self.Auras.active or 0,
        auraError = self.Auras and self.Auras.lastError or nil,
        deferred = table.concat(DEFERRED_OPTIONS, ","),
        lastReason = self.lastReason,
        lastError = self.lastError,
    }
end

-- Public refresh boundary used by the existing Options/other subsystem callers.
ns.UpdateAllPlates = function() FNP:RefreshAll("UpdateAllPlates") end
ns.RefreshPlateForUnit = function(unit) FNP:RefreshUnit(unit, "RefreshPlateForUnit") end
