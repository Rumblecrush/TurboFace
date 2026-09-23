local _, ns = ...

-- =============================================================================
-- TurboFace ShieldData
--
-- Classic Era absorb-model facts used by the Player/Party shield renderer.
-- This file intentionally keeps only player-accessible shield families that
-- TurboFace can model from local caster stats or fixed rank values.  Unknown
-- shields can still render through UnitGetTotalAbsorbs when the client exposes
-- an authoritative non-zero total.
--
-- Saved-variable keys retain the historic `nanShield*` prefix for profile
-- compatibility; this data/engine is TurboFace-owned.
-- =============================================================================

local ShieldData = {}
ns.ShieldData = ShieldData

ShieldData.SCHOOL = {
    ALL      = 127,
    PHYSICAL = 1,
    MAGIC    = 126,
    HOLY     = 2,
    FIRE     = 4,
    NATURE   = 8,
    FROST    = 16,
    SHADOW   = 32,
    ARCANE   = 64,
}

ShieldData.schoolIds = {
    ShieldData.SCHOOL.ALL,
    ShieldData.SCHOOL.PHYSICAL,
    ShieldData.SCHOOL.MAGIC,
    ShieldData.SCHOOL.HOLY,
    ShieldData.SCHOOL.FIRE,
    ShieldData.SCHOOL.NATURE,
    ShieldData.SCHOOL.FROST,
    ShieldData.SCHOOL.SHADOW,
    ShieldData.SCHOOL.ARCANE,
}

-- TurboFace palette. Index order matches `schoolIds` above.
ShieldData.schoolColors = {
    { 0.80, 0.82, 0.86 }, -- All
    { 0.76, 0.62, 0.47 }, -- Physical
    { 0.42, 0.68, 0.88 }, -- Magic
    { 0.94, 0.82, 0.32 }, -- Holy
    { 0.88, 0.32, 0.18 }, -- Fire
    { 0.34, 0.72, 0.40 }, -- Nature
    { 0.32, 0.68, 0.88 }, -- Frost
    { 0.52, 0.36, 0.68 }, -- Shadow
    { 0.70, 0.42, 0.78 }, -- Arcane
}

local models = {}
local partyPowerWordShield = {}

local function AddRank(spellId, school, base, perLevel, startLevel, capLevel,
                       spellLevel, coefficient, powerSource, modifier)
    models[spellId] = {
        school = school,
        base = base or 0,
        perLevel = perLevel or 0,
        startLevel = startLevel or 0,
        capLevel = capLevel or 0,
        spellLevel = spellLevel or 0,
        coefficient = coefficient or 0,
        powerSource = powerSource,
        modifier = modifier,
    }
end

local function AddFixedRanks(school, rows, modifier)
    for i = 1, #rows do
        local r = rows[i]
        AddRank(r[1], school, r[2], 0, r[3] or 0, 0, r[3] or 0, 0, nil, modifier)
    end
end

-- Priest: Power Word: Shield. The base/per-level values preserve TurboFace's
-- established Classic calculation semantics; local Improved PW:S is applied by
-- the engine and external-caster shields use only the rank baseline.
local pws = {
    {17,43,0.8,6,11,6}, {592,87,1.2,12,17,12}, {600,157,1.6,18,23,18},
    {3747,233,2.0,24,29,24}, {6065,300,2.3,30,35,30},
    {6066,380,2.6,36,41,36}, {10898,483,3.0,42,47,42},
    {10899,604,3.4,48,53,48}, {10900,762,3.9,54,59,54},
    {10901,941,4.3,60,65,60}, {27607,941,4.3,60,65,60},
}
for i = 1, #pws do
    local r = pws[i]
    AddRank(r[1], ShieldData.SCHOOL.ALL, r[2], r[3], r[4], r[5], r[6], 0.10, "healing", "PWS")
    partyPowerWordShield[r[1]] = true
end

-- Mage shields and wards.
AddFixedRanks(ShieldData.SCHOOL.PHYSICAL, {
    {1463,119,20}, {8494,209,28}, {8495,299,36},
    {10191,389,44}, {10192,479,52}, {10193,569,60},
})
AddFixedRanks(ShieldData.SCHOOL.FIRE, {
    {543,165,20}, {8457,289,30}, {8458,469,40}, {10223,674,50}, {10225,919,60},
})
AddFixedRanks(ShieldData.SCHOOL.FROST, {
    {6143,164,22}, {8461,289,32}, {8462,469,42}, {10177,674,52}, {28609,919,60},
})
local iceBarrier = {
    {11426,437,2.8,40,46,40}, {13031,548,3.2,46,52,46},
    {13032,677,3.6,52,58,52}, {13033,817,4.0,58,64,58},
}
for i = 1, #iceBarrier do
    local r = iceBarrier[i]
    AddRank(r[1], ShieldData.SCHOOL.ALL, r[2], r[3], r[4], r[5], r[6], 0.10, "frost")
end

-- Warlock shields.
AddFixedRanks(ShieldData.SCHOOL.MAGIC, {
    {128,399,36}, {17729,649,48}, {17730,899,60},
})
local sacrifice = {
    {7812,304,2.3,16,22,16}, {19438,509,3.1,24,30,24},
    {19440,769,3.9,32,38,32}, {19441,1094,4.7,40,46,40},
    {19442,1469,5.5,48,54,48}, {19443,1904,6.4,56,62,56},
}
for i = 1, #sacrifice do
    local r = sacrifice[i]
    AddRank(r[1], ShieldData.SCHOOL.ALL, r[2], r[3], r[4], r[5], r[6], 0, nil, "VOIDWALKER")
end
AddFixedRanks(ShieldData.SCHOOL.SHADOW, {
    {6229,289,32}, {11739,469,42}, {11740,674,52}, {28610,919,60},
})

-- Classic protection-potion / protection-effect ranks. These are fixed absorb
-- values and therefore do not use player spell power or talent modifiers.
AddFixedRanks(ShieldData.SCHOOL.HOLY, {
    {7245,299,20}, {7246,524,25}, {7247,674,30}, {7248,974,35},
    {7249,1349,40}, {17545,1949,40},
})
AddFixedRanks(ShieldData.SCHOOL.FIRE, {
    {7230,299,20}, {7231,524,25}, {7232,674,30}, {7233,974,35},
    {7234,1349,40}, {17543,1949,35},
})
AddFixedRanks(ShieldData.SCHOOL.NATURE, {
    {7250,299,20}, {7251,524,25}, {7252,674,30}, {7253,974,35},
    {7254,1349,40}, {17546,1949,40},
})
AddFixedRanks(ShieldData.SCHOOL.FROST, {
    {7240,299,20}, {7236,524,25}, {7238,674,30}, {7237,974,35},
    {7239,1349,40}, {17544,1949,40},
})
AddFixedRanks(ShieldData.SCHOOL.SHADOW, {
    {7235,299,20}, {7241,524,25}, {7242,674,30}, {7243,974,35},
    {7244,1349,40}, {17548,1949,40},
})
AddFixedRanks(ShieldData.SCHOOL.ARCANE, {
    {17549,1949,35},
})

function ShieldData:Get(spellId)
    return spellId and models[spellId] or nil
end

function ShieldData:IsPartyPowerWordShield(spellId)
    return spellId and partyPowerWordShield[spellId] or false
end

function ShieldData:Count()
    local n = 0
    for _ in pairs(models) do n = n + 1 end
    return n
end
