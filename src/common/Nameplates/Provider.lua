local _, ns = ...

-- =============================================================================
-- Nameplate client-provider contract
--
-- Shared nameplate policy should not ask which WoW client is running.  It asks
-- the active nameplate provider how Blizzard-owned plate work must be staged.
-- Classic registers the native Era behavior here; Forever's detached adapter
-- registers a higher-priority implementation later in the load sequence.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

function Classic:UsesLegacyAuraRows()
    return true
end

function Classic:DeferPowerUpdates()
    return false
end

function Classic:DeferHealPrediction()
    return false
end

function Classic:AfterNativeUpdate(fn)
    if type(fn) == "function" then fn() end
end

function Classic:ScheduleBatch(fn)
    if type(fn) ~= "function" then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

if Providers and Providers.Register then
    Providers:Register("nameplates", "classic-native", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("nameplates") or nil
end

function ns.GetNameplateProvider()
    return Active()
end

function ns.NameplateProviderUsesLegacyAuraRows()
    local provider = Active()
    local fn = provider and provider.UsesLegacyAuraRows
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value ~= false end
    end
    -- Fail closed on Forever if the detached provider has not registered yet.
    return not (ns.Client and ns.Client:IsForever())
end

function ns.NameplateProviderDeferPowerUpdates()
    local provider = Active()
    local fn = provider and provider.DeferPowerUpdates
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    return ns.Client and ns.Client:IsForever() or false
end

function ns.NameplateProviderDeferHealPrediction()
    local provider = Active()
    local fn = provider and provider.DeferHealPrediction
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    return ns.Client and ns.Client:IsForever() or false
end

function ns.NameplateProviderAfterNativeUpdate(fn)
    local provider = Active()
    local method = provider and provider.AfterNativeUpdate
    if type(method) == "function" then
        return method(provider, fn)
    end
    if type(fn) == "function" then fn() end
end

function ns.NameplateProviderScheduleBatch(fn)
    local provider = Active()
    local method = provider and provider.ScheduleBatch
    if type(method) == "function" then
        return method(provider, fn)
    end
    if C_Timer and type(C_Timer.After) == "function" then
        return C_Timer.After(0, fn)
    end
    if type(fn) == "function" then fn() end
end
