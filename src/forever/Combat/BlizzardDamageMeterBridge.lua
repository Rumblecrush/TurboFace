local _, ns = ...

-- =============================================================================
-- TurboFace Combat/BlizzardDamageMeterBridge.lua
--
-- Forever/Mainline damage-meter adapter for the independent PlayerFrame badge.
-- Blizzard owns combat accounting. TurboFace reads only the public aggregated
-- C_DamageMeter session source and renders the local player's opaque DPS/HPS
-- value directly into an addon-owned FontString.
--
-- IMPORTANT SECRET-VALUE CONTRACT:
--   * `isLocalPlayer` is NeverSecret and may be inspected.
--   * `amountPerSecond` may be secret in combat. Never compare, type-check,
--     round, divide, stringify, cache, or use it as a table key.
--   * The opaque rate may only be forwarded to an API that explicitly accepts
--     secret arguments. The badge currently uses FontString:SetFormattedText.
-- =============================================================================

local Bridge = {}
ns.BlizzardDamageMeterBridge = Bridge

local DB = ns.DB
local API = ns.API
local PLACEHOLDER = "-"
local CURRENT_STALE_AFTER = 30

local eventFrame
local initialized = false
local updateQueued = false
local lastCombatEndAt

local debugState = {
    events = 0,
    api = false,
    available = false,
    availabilityReason = nil,
    lastQueryOK = false,
    lastFoundPlayer = false,
    lastRateSecret = false,
    lastRenderOK = false,
    lastSourceCount = 0,
    lastError = nil,
}

local function ScalarIsSecret(value)
    local fn = _G.issecretvalue
    if type(fn) ~= "function" then return false end
    local ok, secret = pcall(fn, value)
    return ok and secret == true
end

local function SafeField(tbl, key)
    if ScalarIsSecret(tbl) then return nil, false end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok then return nil, false end
    return value, true
end

local function MeterAPIReady()
    return type(_G.C_DamageMeter) == "table"
        and type(C_DamageMeter.GetCombatSessionFromType) == "function"
        and type(C_DamageMeter.IsDamageMeterAvailable) == "function"
        and type(_G.Enum) == "table"
        and type(Enum.DamageMeterSessionType) == "table"
        and Enum.DamageMeterSessionType.Current ~= nil
        and Enum.DamageMeterSessionType.Overall ~= nil
        and type(Enum.DamageMeterType) == "table"
        and Enum.DamageMeterType.DamageDone ~= nil
        and Enum.DamageMeterType.HealingDone ~= nil
end

function Bridge:IsSupported()
    return MeterAPIReady()
end

function Bridge:GetMetric()
    return DB().combatMeterMetric == "healing" and "healing" or "damage"
end

function Bridge:GetView()
    return DB().combatMeterView == "overall" and "overall" or "current"
end

local function ScheduleBadgeUpdate()
    if updateQueued then return end
    updateQueued = true
    local function Run()
        updateQueued = false
        if ns.DPSBadge and ns.DPSBadge.Update then ns.DPSBadge:Update() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end

function Bridge:SetMetric(metric)
    DB().combatMeterMetric = metric == "healing" and "healing" or "damage"
    ScheduleBadgeUpdate()
    return self:GetMetric()
end

function Bridge:SetView(view)
    DB().combatMeterView = view == "overall" and "overall" or "current"
    ScheduleBadgeUpdate()
    return self:GetView()
end

function Bridge:Reset()
    if not self:IsSupported() or type(C_DamageMeter.ResetAllCombatSessions) ~= "function" then return false end
    local ok, err = pcall(C_DamageMeter.ResetAllCombatSessions)
    if not ok then
        debugState.lastError = tostring(err)
        return false
    end
    debugState.lastError = nil
    ScheduleBadgeUpdate()
    return true
end

function Bridge:CanToggleDisplay()
    -- TurboFace deliberately does not own or toggle Blizzard's Damage Meter UI.
    return false
end

function Bridge:IsDisplayHidden()
    return false
end

function Bridge:ToggleDisplay()
    return nil
end

function Bridge:GetBadgeTooltipHint()
    return "Uses Blizzard's built-in Damage Meter data."
end

local function SessionTypeForView(view)
    return view == "overall" and Enum.DamageMeterSessionType.Overall
        or Enum.DamageMeterSessionType.Current
end

local function MeterTypeForMetric(metric)
    return metric == "healing" and Enum.DamageMeterType.HealingDone
        or Enum.DamageMeterType.DamageDone
end

local function CurrentViewIsStale(view)
    if view ~= "current" then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    if not lastCombatEndAt then return true end
    return (GetTime() - lastCombatEndAt) > CURRENT_STALE_AFTER
end

-- Returns the local player's opaque amountPerSecond plus a non-secret found flag.
-- The first return MUST remain opaque to all callers.
function Bridge:GetOpaquePlayerRate()
    debugState.lastQueryOK = false
    debugState.lastFoundPlayer = false
    debugState.lastRateSecret = false
    debugState.lastSourceCount = 0
    debugState.lastError = nil

    debugState.api = self:IsSupported()
    if not debugState.api then
        debugState.lastError = "C_DamageMeter unavailable"
        return nil, false
    end

    local okAvailable, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
    if not okAvailable then
        debugState.available = false
        debugState.availabilityReason = nil
        debugState.lastError = tostring(available)
        return nil, false
    end
    debugState.available = available == true
    debugState.availabilityReason = reason
    if not debugState.available then
        debugState.lastError = "Blizzard Damage Meter unavailable"
        return nil, false
    end

    local view = self:GetView()
    if CurrentViewIsStale(view) then
        debugState.lastQueryOK = true
        return nil, false
    end

    local sessionType = SessionTypeForView(view)
    local meterType = MeterTypeForMetric(self:GetMetric())
    local okSession, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
    if not okSession then
        debugState.lastError = tostring(session)
        return nil, false
    end
    if ScalarIsSecret(session) then
        debugState.lastError = "session object is secret"
        return nil, false
    end

    local sources, gotSources = SafeField(session, "combatSources")
    if not gotSources or ScalarIsSecret(sources) or type(sources) ~= "table" then
        debugState.lastError = "combatSources unavailable"
        return nil, false
    end

    local okCount, count = pcall(function() return #sources end)
    if not okCount then
        debugState.lastError = "combatSources length unavailable"
        return nil, false
    end
    debugState.lastSourceCount = count

    for i = 1, count do
        local source, gotSource = SafeField(sources, i)
        if gotSource and not ScalarIsSecret(source) and type(source) == "table" then
            local isLocal, gotLocal = SafeField(source, "isLocalPlayer")
            if gotLocal and isLocal == true then
                local rate, gotRate = SafeField(source, "amountPerSecond")
                if not gotRate then
                    debugState.lastError = "local amountPerSecond unavailable"
                    return nil, false
                end
                debugState.lastQueryOK = true
                debugState.lastFoundPlayer = true
                debugState.lastRateSecret = ScalarIsSecret(rate)
                -- Never retain `rate` in module state; return it only as an opaque
                -- transient value to the badge's secret-capable render call.
                return rate, true
            end
        end
    end

    debugState.lastQueryOK = true
    return nil, false
end

function Bridge:RenderPlayerRate(fontString)
    if not fontString or type(fontString.SetFormattedText) ~= "function" then return false end
    local rate, found = self:GetOpaquePlayerRate()
    if not found then
        fontString:SetText(PLACEHOLDER)
        debugState.lastRenderOK = true
        return false
    end

    -- SetFormattedText is the intentional secret-value sink. Do not pre-format
    -- the value in Lua: arithmetic/string formatting on a secret rate is illegal.
    local ok, err = pcall(fontString.SetFormattedText, fontString, "%.0f", rate)
    debugState.lastRenderOK = ok
    if not ok then
        debugState.lastError = tostring(err)
        fontString:SetText(PLACEHOLDER)
        return false
    end
    return true
end

function Bridge:GetDebugState()
    local out = {}
    for k, v in pairs(debugState) do out[k] = v end
    out.metric = self:GetMetric()
    out.view = self:GetView()
    out.initialized = initialized
    return out
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    debugState.events = 0
    if not active then return end
    for _, event in ipairs({
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        "DAMAGE_METER_CURRENT_SESSION_UPDATED",
        "DAMAGE_METER_RESET",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }) do
        if API and API.RegisterEvent and API.RegisterEvent(eventFrame, event) then
            debugState.events = debugState.events + 1
        end
    end
end

function Bridge:Refresh()
    if ns.Providers and not ns.Providers:IsActive("combatMeter", self) then
        SetEvents(false)
        return
    end
    debugState.api = self:IsSupported()
    local badgeEnabled = ns.DPSBadge and ns.DPSBadge.Enabled and ns.DPSBadge:Enabled()
    SetEvents(debugState.api and badgeEnabled == true)
    ScheduleBadgeUpdate()
end

function Bridge:Init()
    if ns.Providers and not ns.Providers:IsActive("combatMeter", self) then return end
    if initialized then
        self:Refresh()
        return
    end
    initialized = true
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            lastCombatEndAt = nil
        elseif event == "PLAYER_REGEN_ENABLED" then
            lastCombatEndAt = GetTime()
        elseif event == "PLAYER_ENTERING_WORLD" then
            if UnitAffectingCombat and UnitAffectingCombat("player") then
                lastCombatEndAt = nil
            end
        end
        ScheduleBadgeUpdate()
    end)
    self:Refresh()
end

function Bridge:HandleSlash(args)
    local cmd = (args or ""):lower():match("^%s*(%S+)") or "status"
    if cmd == "damage" then self:SetMetric("damage"); return true end
    if cmd == "healing" or cmd == "heal" then self:SetMetric("healing"); return true end
    if cmd == "current" then self:SetView("current"); return true end
    if cmd == "overall" then self:SetView("overall"); return true end
    if cmd == "reset" then self:Reset(); return true end

    local s = self:GetDebugState()
    local msg = ("Blizzard meter bridge: api=%s available=%s events=%d view=%s metric=%s query=%s player=%s secretRate=%s render=%s sources=%d error=%s")
        :format(tostring(s.api), tostring(s.available), s.events or 0, tostring(s.view), tostring(s.metric),
            tostring(s.lastQueryOK), tostring(s.lastFoundPlayer), tostring(s.lastRateSecret),
            tostring(s.lastRenderOK), s.lastSourceCount or 0, tostring(s.lastError or "none"))
    if ns.Chat then ns:Chat("Meter", msg) elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("TurboFace Meter: " .. msg) end
    return true
end

if ns.Providers then
    -- Prefer Blizzard's public aggregation backend on clients that expose it;
    -- the shared TurboFace CLEU meter remains the lower-priority fallback.
    ns.Providers:Register("combatMeter", "blizzard-damage-meter", Bridge, 100)
end
