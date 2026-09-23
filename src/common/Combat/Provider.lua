local _, ns = ...

-- =============================================================================
-- Combat presentation provider
--
-- Shared combat policy/data should not branch on the client flavor.  This
-- provider owns the small set of presentation capabilities that genuinely
-- differ because Forever yields protected/pooled Blizzard surfaces to the
-- native UI while Classic still permits the historical TurboFace renderers.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

-- Classic still owns the old ClassBuffs icon reminder for unspent talent
-- points.  Forever migrated this to the standalone Speedrun text reminder.
function Classic:UsesClassBuffTalentReminder()
    return true
end

-- Classic ClassFeatures may attach the reactive Overpower indicator directly
-- to the Era nameplate surface.  Forever's pooled CompactUnitFrames do not
-- permit that ownership model.
function Classic:SupportsReactiveNameplateIndicator()
    return true
end

if Providers and Providers.Register then
    Providers:Register("combatUI", "classic-readable", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("combatUI") or nil
end

function ns.GetCombatUIProvider()
    return Active()
end

function ns.CombatProviderUsesClassBuffTalentReminder()
    local provider = Active()
    local fn = provider and provider.UsesClassBuffTalentReminder
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    -- Fail closed on Forever if its provider has not registered yet.
    return not (ns.Client and ns.Client:IsForever())
end

function ns.CombatProviderSupportsReactiveNameplateIndicator()
    local provider = Active()
    local fn = provider and provider.SupportsReactiveNameplateIndicator
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    -- Direct native-nameplate ownership must never be assumed on Forever.
    return not (ns.Client and ns.Client:IsForever())
end