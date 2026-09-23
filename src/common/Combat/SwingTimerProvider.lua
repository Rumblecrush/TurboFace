local _, ns = ...

-- =============================================================================
-- Swing Timer runtime provider
--
-- The timer model/rendering is shared.  This provider owns only the client
-- substrate decisions that genuinely differ between Classic Era and Forever:
-- authoritative player-swing events, readable hostile attack-speed sources,
-- threat-as-engagement fallback, and optional Character-sheet damage capture.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

function Classic:UsesPlayerSwingEvent()
    return false
end

function Classic:CanReadTargetAttackSpeed()
    return true
end

function Classic:CanReadNameplateAttackSpeed()
    return true
end

function Classic:UsesThreatSituationEngagement()
    return true
end

function Classic:UsesCharacterDamageCapture()
    return false
end

function Classic:Attach()
    -- Classic obtains standalone weapon damage directly from UnitDamage and
    -- needs no Character/PaperDoll capture surface.
end

if Providers and Providers.Register then
    Providers:Register("swingTimers", "classic-cleu", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("swingTimers") or nil
end

local function Bool(method, classicFallback)
    local provider = Active()
    local fn = provider and provider[method]
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    if ns.Client and ns.Client:IsForever() then return false end
    return classicFallback == true
end

function ns.GetSwingTimerProvider()
    return Active()
end

function ns.SwingTimerProviderUsesPlayerSwingEvent()
    return Bool("UsesPlayerSwingEvent", false)
end

function ns.SwingTimerProviderCanReadTargetAttackSpeed()
    return Bool("CanReadTargetAttackSpeed", true)
end

function ns.SwingTimerProviderCanReadNameplateAttackSpeed()
    return Bool("CanReadNameplateAttackSpeed", true)
end

function ns.SwingTimerProviderUsesThreatSituationEngagement()
    return Bool("UsesThreatSituationEngagement", true)
end

function ns.SwingTimerProviderUsesCharacterDamageCapture()
    return Bool("UsesCharacterDamageCapture", false)
end

function ns.SwingTimerProviderAttach(ST)
    local provider = Active()
    local fn = provider and provider.Attach
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, provider, ST)
    return ok
end

function ns.SwingTimerProviderInstallCharacterDamageCapture(ST, eventFrame)
    local provider = Active()
    local fn = provider and provider.InstallCharacterDamageCapture
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, provider, ST, eventFrame)
    return ok and value == true
end

function ns.SwingTimerProviderRefreshCharacterDamageCapture(ST, eventFrame)
    local provider = Active()
    local fn = provider and provider.RefreshCharacterDamageCapture
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, provider, ST, eventFrame)
    return ok and value == true
end

function ns.SwingTimerProviderRunCharacterDamageProbe(ST, msg)
    local provider = Active()
    local fn = provider and provider.RunCharacterDamageProbe
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, provider, ST, msg)
    return ok and value == true
end