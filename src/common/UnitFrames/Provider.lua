local _, ns = ...

-- =============================================================================
-- UnitFrame client-provider contract
--
-- Shared UnitFrame-adjacent features should not branch on the running client.
-- They ask the active UnitFrame provider which Blizzard ownership model is safe.
-- Classic registers the readable/native Era baseline here; Forever's detached
-- native adapter registers a higher-priority provider later in the load order.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

function Classic:UsesDetachedRenderer()
    return false
end

function Classic:AllowCustomPredictions()
    return true
end

function Classic:AllowNanShield()
    return true
end

function Classic:AllowDruidPowerBar()
    return true
end

function Classic:GetPlayerHealthBar()
    return (ns.UF and ns.UF.GetPlayerHealthBar and ns.UF.GetPlayerHealthBar()) or _G.PlayerFrameHealthBar
end

function Classic:GetPlayerManaBar()
    return (ns.UF and ns.UF.GetPlayerManaBar and ns.UF.GetPlayerManaBar()) or _G.PlayerFrameManaBar
end

if Providers and Providers.Register then
    Providers:Register("unitframes", "classic-readable", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("unitframes") or nil
end

function ns.GetUnitFrameProvider()
    return Active()
end

local function ProviderBool(method, classicFallback)
    local provider = Active()
    local fn = provider and provider[method]
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    if ns.Client and ns.Client:IsForever() then return false end
    return classicFallback == true
end

function ns.UnitFrameProviderUsesDetachedRenderer()
    return ProviderBool("UsesDetachedRenderer", false)
end

function ns.UnitFrameProviderAllowsCustomPredictions()
    return ProviderBool("AllowCustomPredictions", true)
end

function ns.UnitFrameProviderAllowsNanShield()
    return ProviderBool("AllowNanShield", true)
end

function ns.UnitFrameProviderAllowsDruidPowerBar()
    return ProviderBool("AllowDruidPowerBar", true)
end

local function ProviderFrame(method, legacy)
    local provider = Active()
    local fn = provider and provider[method]
    if type(fn) == "function" then
        local ok, frame = pcall(fn, provider)
        if ok and frame then return frame end
    end
    if ns.Client and ns.Client:IsForever() then return nil end
    return legacy
end

function ns.UnitFrameProviderPlayerHealthBar()
    return ProviderFrame("GetPlayerHealthBar", _G.PlayerFrameHealthBar)
end

function ns.UnitFrameProviderPlayerManaBar()
    return ProviderFrame("GetPlayerManaBar", _G.PlayerFrameManaBar)
end