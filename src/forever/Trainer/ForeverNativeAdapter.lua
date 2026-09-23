local _, ns = ...

-- Forever keeps the shared Trainer data/row policy, but its retail-derived
-- Spellbook/Professions surfaces require detached pages and native-styled cards.
local FOREVER = {}

function FOREVER:IsSupported()
    return ns.Client and ns.Client:IsForever() or false
end

function FOREVER:UsesNativeTrainerCards()
    return true
end

function FOREVER:UsesSpellbookGrid()
    return true
end

function FOREVER:SpellbookListSizeBump()
    return 8
end

function FOREVER:OwnsEmbeddedSpellbookHost()
    return false
end

function FOREVER:OwnsDetachedProfessionHost()
    return true
end

function FOREVER:UsesDetailedWeaponMasterSources()
    return true
end

function FOREVER:UsesOpenProfessionSkillFallback()
    return true
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("trainerUI", "forever-detached", FOREVER, 100)
end
