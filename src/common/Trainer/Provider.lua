local _, ns = ...

-- =============================================================================
-- Trainer presentation provider
--
-- Training data, queue semantics, grouping, and row construction are shared.
-- What differs by client is the Blizzard presentation substrate that hosts
-- those rows. Classic uses TurboFace's Era-style embedded spellbook/trainer
-- surfaces. Forever registers a higher-priority provider later and keeps the
-- detached/native-card presentation needed by its retail-derived UI.
-- =============================================================================

local Providers = ns.Providers
local Classic = {}

function Classic:IsSupported()
    return not (ns.Client and ns.Client:IsForever())
end

function Classic:UsesNativeTrainerCards()
    return false
end

function Classic:UsesSpellbookGrid()
    return false
end

function Classic:SpellbookListSizeBump()
    return 0
end

function Classic:OwnsEmbeddedSpellbookHost()
    return true
end

function Classic:OwnsDetachedProfessionHost()
    return false
end

-- Classic's Skills view historically labels weapon sources generically.  Keep
-- that presentation stable even though the shared SkillData catalog contains
-- the richer Forever source map.
function Classic:UsesDetailedWeaponMasterSources()
    return false
end

-- Era exposes profession ranks through the shared Skills engine, so SkillData
-- does not need to interrogate an open modern Professions page.
function Classic:UsesOpenProfessionSkillFallback()
    return false
end

if Providers and Providers.Register then
    Providers:Register("trainerUI", "classic-embedded", Classic, 10)
end

local function Active()
    return Providers and Providers:Get("trainerUI") or nil
end

function ns.GetTrainerUIProvider()
    return Active()
end

local function Bool(method, classicDefault, foreverDefault)
    local provider = Active()
    local fn = provider and provider[method]
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok then return value == true end
    end
    if ns.Client and ns.Client:IsForever() then return foreverDefault == true end
    return classicDefault == true
end

function ns.TrainerProviderUsesNativeTrainerCards()
    return Bool("UsesNativeTrainerCards", false, true)
end

function ns.TrainerProviderUsesSpellbookGrid()
    return Bool("UsesSpellbookGrid", false, true)
end

function ns.TrainerProviderSpellbookListSizeBump()
    local provider = Active()
    local fn = provider and provider.SpellbookListSizeBump
    if type(fn) == "function" then
        local ok, value = pcall(fn, provider)
        if ok and type(value) == "number" then return value end
    end
    return (ns.Client and ns.Client:IsForever()) and 8 or 0
end

function ns.TrainerProviderOwnsEmbeddedSpellbookHost()
    return Bool("OwnsEmbeddedSpellbookHost", true, false)
end

function ns.TrainerProviderOwnsDetachedProfessionHost()
    return Bool("OwnsDetachedProfessionHost", false, true)
end

function ns.TrainerProviderUsesDetailedWeaponMasterSources()
    return Bool("UsesDetailedWeaponMasterSources", false, true)
end

function ns.TrainerProviderUsesOpenProfessionSkillFallback()
    return Bool("UsesOpenProfessionSkillFallback", false, true)
end
