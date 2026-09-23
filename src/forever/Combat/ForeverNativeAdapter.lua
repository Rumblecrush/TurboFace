local _, ns = ...

local compat = ns.Compat
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true) then return end

-- =============================================================================
-- Forever combat-presentation ownership
--
-- Forever keeps the shared combat policy/data but yields the two presentation
-- surfaces below to safer standalone/native implementations.
-- =============================================================================

local Forever = {}

function Forever:IsSupported()
    return true
end

function Forever:UsesClassBuffTalentReminder()
    return false
end

function Forever:SupportsReactiveNameplateIndicator()
    return false
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("combatUI", "forever-secret-safe", Forever, 100)
end