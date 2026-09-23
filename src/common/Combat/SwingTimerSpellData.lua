local _, ns = ...

-- =============================================================================
-- Classic Era swing-interaction identities
--
-- This file contains TurboFace's compact description of the Classic mechanics
-- that need exceptions to the generic cast/swing rules in SwingTimers.lua.
--
-- Important design rule: spell *families* are matched by Blizzard's localized
-- spell name, using one canonical Classic spell ID per family. That means new
-- ranks do not require copied/static rank-ID dumps, and the data here describes
-- behavior rather than mirroring another addon's implementation tables.
-- =============================================================================

local data = {}
ns.SwingTimerSpellData = data

local API = ns.API or {}
local GetSpellInfo = API.GetSpellInfo or _G.GetSpellInfo
local IsCurrentSpell = API.IsCurrentSpell or _G.IsCurrentSpell

local function SpellName(spellID)
    if not spellID or not GetSpellInfo then return nil end
    return GetSpellInfo(spellID)
end

local function BuildFamilyNames(canonicalIDs, out)
    out = out or {}
    if not GetSpellInfo then return out end
    for i = 1, #canonicalIDs do
        local name = GetSpellInfo(canonicalIDs[i])
        if name then out[name] = true end
    end
    return out
end

local function MatchesFamily(spellID, canonicalIDs, cache)
    local name = SpellName(spellID)
    if not name then return false end
    BuildFamilyNames(canonicalIDs, cache)
    return cache[name] == true
end

-- Classic spells whose successful use restarts the melee clock even when there
-- was no ordinary UNIT_SPELLCAST_START to identify a completed hard cast.
-- Druid caster-form spell families are intentionally represented broadly: in
-- Classic, their instant casts restart the melee clock, and a normally cast
-- Nature spell can also become instant through Nature's Swiftness.
local RESET_ON_SUCCESS_FAMILIES = {
    16589, -- Noggenfogger Elixir item-use spell
    2645,  -- Ghost Wolf
    5384,  -- Feign Death
    20066, -- Repentance

    -- Druid caster-form spell families
    2893,  -- Abolish Poison
    8946,  -- Cure Poison
    339,   -- Entangling Roots
    770,   -- Faerie Fire
    21849, -- Gift of the Wild
    5185,  -- Healing Touch
    2637,  -- Hibernate
    1126,  -- Mark of the Wild
    8921,  -- Moonfire
    20484, -- Rebirth
    8936,  -- Regrowth
    774,   -- Rejuvenation
    2782,  -- Remove Curse
    2908,  -- Soothe Animal
    467,   -- Thorns
    5176,  -- Wrath
}
local resetOnSuccessNames = {}

function data.ResetsMeleeOnSuccess(spellID)
    return MatchesFamily(spellID, RESET_ON_SUCCESS_FAMILIES, resetOnSuccessNames)
end

-- Engineering throws have a visible cast time but do not use the same melee
-- restart rule as an ordinary completed player spell cast. One canonical ID is
-- enough for each distinct localized explosive name.
local HARD_CAST_RESET_EXEMPT_FAMILIES = {
    4054,  -- Rough Dynamite
    4064,  -- Rough Copper Bomb
    4061,  -- Coarse Dynamite
    8331,  -- Ez-Thro Dynamite
    4065,  -- Large Copper Bomb
    4066,  -- Small Bronze Bomb
    4062,  -- Heavy Dynamite
    4067,  -- Big Bronze Bomb
    4068,  -- Iron Grenade
    23000, -- Ez-Thro Dynamite II
    12421, -- Mithril Frag Bomb
    4069,  -- Big Iron Bomb
    12562, -- The Big One
    12543, -- Hi-Explosive Bomb
    23063, -- Dense Dynamite
    19769, -- Thorium Grenade
    19784, -- Dark Iron Bomb
    19821, -- Arcane Bomb
}
local hardCastResetExemptNames = {}

function data.SuppressHardCastReset(spellID)
    return MatchesFamily(spellID, HARD_CAST_RESET_EXEMPT_FAMILIES, hardCastResetExemptNames)
end

-- On-next-swing attacks are queue state, not ordinary casts. The four Classic
-- families below cover every rank because the localized base name is shared by
-- the ranks of the same ability.
local NEXT_MELEE_FAMILIES = {
    78,   -- Heroic Strike
    845,  -- Cleave
    2973, -- Raptor Strike
    6807, -- Maul
}
local nextMeleeNames = {}

function data.IsNextMelee(spellID)
    return MatchesFamily(spellID, NEXT_MELEE_FAMILIES, nextMeleeNames)
end

-- Read the queue from the client rather than inferring it from SENT/FAILED.
-- IsCurrentSpell accepts a spell name in Classic, so the check naturally
-- follows whichever rank the player actually has on the action bar.
function data.GetActiveNextMeleeSpell()
    if not IsCurrentSpell then return nil end
    BuildFamilyNames(NEXT_MELEE_FAMILIES, nextMeleeNames)
    for i = 1, #NEXT_MELEE_FAMILIES do
        local canonicalID = NEXT_MELEE_FAMILIES[i]
        local name = SpellName(canonicalID)
        if name and IsCurrentSpell(name) then
            return canonicalID
        end
    end
    return nil
end

function data.AnyNextMeleeQueued()
    return data.GetActiveNextMeleeSpell() ~= nil
end

-- Oil of Immolation's periodic Fire Shield damage is the only item-effect
-- swing restart TurboFace consumes from CLEU's SPELL_DAMAGE/SPELL_MISSED path.
-- Healing-potion spell IDs previously carried here could never enter that path
-- and were dead data, so they are intentionally not part of the clean model.
local ITEM_EFFECT_RESET_IDS = {
    [11350] = true, -- Fire Shield damage from Oil of Immolation
}

function data.ResetsMeleeOnItemEffect(spellID)
    return spellID and ITEM_EFFECT_RESET_IDS[spellID] == true or false
end
