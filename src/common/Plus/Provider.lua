local _, ns = ...

-- =============================================================================
-- Plus / native-UI client-provider contract
--
-- Shared QoL policy should not branch on the WoW client. It asks this provider
-- which Blizzard-owned surfaces TurboFace may safely augment. Classic owns the
-- Era MapCanvas augmentation path; Forever registers a higher-priority provider
-- that yields protected MapCanvas zoom/pan ownership to Blizzard.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

function Classic:OwnsNativeMapCanvas()
    return false
end

function Classic:SupportsVendorPriceTooltip()
    return true
end

if Providers and Providers.Register then
    Providers:Register("plusUI", "classic-ui", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("plusUI") or nil
end

function ns.GetPlusUIProvider()
    return Active()
end

function ns.PlusProviderOwnsNativeMapCanvas()
    local provider = Active()
    local fn = provider and provider.OwnsNativeMapCanvas
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    -- Fail closed if Forever's provider has not registered yet.
    return ns.Client and ns.Client:IsForever() or false
end

function ns.PlusProviderSupportsVendorPriceTooltip()
    local provider = Active()
    local fn = provider and provider.SupportsVendorPriceTooltip
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    -- Tooltip augmentation is optional presentation work. Fail closed whenever
    -- no client provider explicitly owns it.
    return false
end