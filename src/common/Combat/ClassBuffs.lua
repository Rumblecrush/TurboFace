local _, ns = ...

-- =============================================================================
-- TurboFace ClassBuffs.lua — missing self-buff reminder tracker
--
-- TurboFace "missing buff" reminder. Each tracked buff shows a
-- glowing/pulsing icon ONLY while the buff is down (or about to expire); the
-- icon disappears once the buff is active. Icons lay out in a movable row that
-- registers with the Movers system (token: ClassBuffBar, move with /tfmove).
--
-- Catalog: Warrior Battle Shout; Shaman Lightning Shield + weapon imbues;
-- Druid Mark of the Wild + Thorns; Mage Arcane Intellect + armor family.
-- The CATALOG table is the extension point — add a class entry and the tab +
-- tracker pick it up automatically. Entries marked `partyReminder = true` are
-- also reused by UnitFrames to show which party members lack buffs this player
-- can provide. Reminders only fire for spells the player actually knows, so
-- low-level characters are not nagged about unlearned buffs.
--
-- Classic additionally gets the class-agnostic UNSPENT TALENT POINTS reminder.
-- Forever moved that concern to the standalone Speedrun text reminder, so the
-- active combat-presentation provider decides whether this module owns it.
--
-- Settings are flat TurboFaceDB keys (classBuff*) with defaults in Core/Config.lua.
-- =============================================================================

local _, PLAYER_CLASS = UnitClass("player")

-- Per-class tracked buffs. type:
--   "buff"      -> present if UnitBuff (by any rank name) is up
--   "weaponMH"  -> present if main-hand weapon has a temporary enchant
--   "procBuff"  -> INVERTED: the icon pops while the buff IS ACTIVE (proc
--                  indicator, e.g. Shaman Clearcasting), with a countdown
--
-- Classic Era/Hardcore Shaman cannot dual wield, so Shaman only tracks a
-- main-hand imbue. Tracking slot 17 would falsely warn when using a shield or
-- caster off-hand, because those occupy the off-hand slot but cannot be imbued.
local CATALOG = {
    WARRIOR = {
        -- LISTED FIRST deliberately, like the Shaman/Mage Clearcasting procs:
        -- icons lay out in catalog order, so the reactive window leads the row.
        --
        -- type "reactive" is an INVERTED reminder like procBuff -- it shows
        -- while the ability IS usable. Revenge opens for 5s after the warrior
        -- blocks, dodges or parries, and it is target-agnostic, which is why it
        -- belongs on this bar rather than on a nameplate like Overpower.
        --
        -- Availability comes from IsUsableSpell, the client's own answer to the
        -- question that greys the action-bar button. Deriving the window from
        -- combat-log block/dodge/parry events instead would mean re-implementing
        -- (and drifting from) what the client already tracks.
        --
        -- Ranks confirmed in Trainer/data/Warrior.lua at 14/24/34/44/54; 25288
        -- is carried over from ClassFeatures.lua's existing Revenge set.
        { key = "revenge", label = "Revenge", dbKey = "classBuffRevenge",
          type = "reactive", spellIDs = { 6572, 6574, 7379, 11600, 11601, 25288 },
          reactiveWindow = 5,
          reactiveMisses = { BLOCK = true, DODGE = true, PARRY = true } },
        { key = "battleShout", label = "Battle Shout", dbKey = "classBuffBattleShout",
          type = "buff", partyReminder = true,
          spellIDs = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    },
    SHAMAN = {
        -- Clearcasting proc from the Elemental Focus talent (buff aura 16246):
        -- pops while ACTIVE so the free damage spell isn't wasted. No knowledge
        -- gate -- without the talent the buff never appears, so the icon simply
        -- never fires (it does show during /test, which is harmless).
        -- LISTED FIRST deliberately: icons lay out in catalog order, so the
        -- proc always leads the reminder row when it appears.
        { key = "clearcasting", label = "Clearcasting", dbKey = "classBuffClearcasting",
          type = "procBuff", spellIDs = { 16246 } },
        { key = "lightningShield", label = "Lightning Shield", dbKey = "classBuffLightningShield",
          type = "buff", spellIDs = { 324, 325, 905, 945, 8134, 10431, 10432 } },
        { key = "weaponMainHand", label = "Weapon Imbue", dbKey = "classBuffWeaponMH",
          type = "weaponMH", imbueSpellIDs = { 8017, 8024, 8033, 8232 } },

        -- Totem effects are party-only class reminders. Unlike standing buffs,
        -- each elemental slot has mutually exclusive choices, so they appear on
        -- party frames only while the member actually has the effect. They never
        -- enter the player's missing-self-buff reminder queue.
        --
        -- spellIDs are the aura IDs observed on party members; knownSpellIDs
        -- are the corresponding totem casts in the Shaman spellbook.
        { key = "totemFireResistance", label = "Fire Resistance Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8185, 10534, 10535 }, knownSpellIDs = { 8184, 10537, 10538 } },
        { key = "totemFrostResistance", label = "Frost Resistance Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8182, 10476, 10477 }, knownSpellIDs = { 8181, 10478, 10479 } },
        { key = "totemNatureResistance", label = "Nature Resistance Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 10596, 10598, 10599 }, knownSpellIDs = { 10595, 10600, 10601 } },
        { key = "totemTranquilAir", label = "Tranquil Air Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 25909 }, knownSpellIDs = { 25908 } },
        { key = "totemHealingStream", label = "Healing Stream Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 5672, 6371, 6372, 10460, 10461 }, knownSpellIDs = { 5394, 6375, 6377, 10462, 10463 } },
        { key = "totemManaSpring", label = "Mana Spring Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 5677, 10491, 10493, 10494 }, knownSpellIDs = { 5675, 10495, 10496, 10497 } },
        { key = "totemStrengthOfEarth", label = "Strength of Earth Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8076, 8162, 8163, 10441, 25362 }, knownSpellIDs = { 8075, 8160, 8161, 10442, 25361 } },
        { key = "totemGraceOfAir", label = "Grace of Air Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8836, 10626, 25360 }, knownSpellIDs = { 8835, 10627, 25359 } },
        { key = "totemStoneskin", label = "Stoneskin Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8072, 8156, 8157, 10403, 10404, 10405 }, knownSpellIDs = { 8071, 8154, 8155, 10406, 10407, 10408 } },
        { key = "totemManaTide", label = "Mana Tide Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 16191, 17355, 17360 }, knownSpellIDs = { 16190 } },
        -- Classic represents the weapon-enchant and ranged-damage reductions
        -- with transient aura IDs. Their localized effect names match the
        -- learned totem names, so these entries intentionally match by name.
        { key = "totemWindfury", label = "Windfury Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8512, 10613, 10614, 25585 }, knownSpellIDs = { 8512, 10613, 10614, 25585 } },
        { key = "totemFlametongue", label = "Flametongue Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 8227, 8249, 10526, 16387 }, knownSpellIDs = { 8227, 8249, 10526, 16387 } },
        { key = "totemWindwall", label = "Windwall Totem",
          type = "buff", partyReminder = true, partyOnly = true, partyActiveOnly = true,
          spellIDs = { 15107, 15111, 15112 }, knownSpellIDs = { 15107, 15111, 15112 } },
    },
    DRUID = {
        -- 21849/21850 are Gift of the Wild (the group version): include them in
        -- the name set so either the single-target or group buff satisfies the
        -- Mark reminder. Icon still resolves from Mark rank 1.
        { key = "markOfTheWild", label = "Mark of the Wild", dbKey = "classBuffMarkOfTheWild",
          type = "buff", partyReminder = true,
          spellIDs = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 } },
        { key = "thorns", label = "Thorns", dbKey = "classBuffThorns",
          type = "buff", partyReminder = true,
          spellIDs = { 467, 782, 1075, 8914, 9756, 9910 } },
    },
    PALADIN = {
        -- LISTED FIRST deliberately, same reason as the Shaman Clearcasting
        -- proc: icons lay out in catalog order, so the seal reminder always
        -- leads the row and never gets pushed around by the blessing icon.
        --
        -- One reminder for all six seals -- ANY seal satisfies it, so it fires
        -- only when the paladin is running unsealed. Matching is by spell NAME,
        -- so every seal name must be represented; the extra ranks are there so
        -- KnowsAny finds one the player has trained.
        --
        -- Every ID below was confirmed twice: against Classic spell databases,
        -- and against Trainer/data/Paladin.lua, which places them at the
        -- expected trainer levels (Righteousness 10-58, Crusader 6-52, Light
        -- 30-60, Wisdom 38-58, Justice 22). The two that are absent from the
        -- trainer data are absent for good reasons: 21084 is the level-1
        -- starting seal, and Seal of Command is a Retribution talent.
        --
        -- NOTE: seals last 30 seconds, so out of combat this fires constantly
        -- by design. "Only show while in combat" (classBuffOnlyInCombat) is
        -- the intended pairing.
        { key = "seal", label = "Seal", dbKey = "classBuffSeal",
          type = "buff", combatOnlyDbKey = "classBuffSealOnlyInCombat", spellIDs = {
            -- Righteousness (r1 is the level-1 starting seal, then 7 trained)
            21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,
            -- The Crusader
            21082, 20162, 20305, 20306, 20307, 20308,
            -- Justice, Light, Wisdom
            20164, 20165, 20347, 20348, 20349, 20166, 20356, 20357,
            -- Command (Retribution talent, single rank)
            20375,
          } },

        -- One reminder for the whole Blessing family, on the Mage Armor model:
        -- ANY blessing satisfies it, so it fires only when the paladin is
        -- carrying no blessing at all. Matching is by spell NAME (see the
        -- nameCache build), so what matters is that every distinct blessing
        -- name is represented -- extra ranks are only there so KnowsAny can
        -- find one the player has actually trained.
        --
        -- Both the single and Greater forms of each are listed: they are
        -- separate spell names, so omitting the Greater ones would make a
        -- raid-buffed paladin get reminded anyway. Icon resolves from Blessing
        -- of Might rank 1 (the first ID below).
        --
        -- IDs verified against Classic databases rather than recalled. An ID
        -- that is wrong for this client is inert rather than harmful: the name
        -- lookup skips anything GetSpellInfo returns nil for.
        { key = "blessing", label = "Blessing", dbKey = "classBuffBlessing",
          type = "buff", spellIDs = {
            -- Might (7 ranks) + Greater Might (2)
            19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916,
            -- Wisdom (6 ranks) + Greater Wisdom (2)
            19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918,
            -- Kings + Greater Kings
            20217, 25898,
            -- Salvation + Greater Salvation
            1038, 25895,
            -- Light (3 ranks) + Greater Light
            19977, 19978, 19979, 25890,
            -- Sanctuary (4 ranks) + Greater Sanctuary
            20911, 20912, 20913, 20914, 25899,
            -- Freedom, Protection (3 ranks), Sacrifice (2 ranks)
            1044, 1022, 5599, 10278, 6940, 20729,
          } },

        -- One reminder for all seven auras -- ANY aura satisfies it. Unlike
        -- seals and blessings, auras have no duration: they only ever go
        -- missing because the paladin right-clicked one off and did not notice,
        -- which is exactly the case worth catching. No combat gate for the same
        -- reason -- a firing aura reminder always means something is wrong.
        --
        -- Ranks cross-checked against Trainer/data/Paladin.lua: Devotion
        -- 1-60, Retribution 16-56, Concentration 22, Shadow 28-52, Frost
        -- 32-56, Fire 36-60. Sanctity Aura is the one absentee, correctly so:
        -- it is a Retribution talent rather than a trained spell (verified
        -- separately as 20218). It still resolves by name, and the knowledge
        -- gate rides on Devotion Aura rank 1, which every paladin has from
        -- level 1 -- so an untalented paladin is not blocked from the reminder.
        { key = "aura", label = "Aura", dbKey = "classBuffAura",
          type = "buff", spellIDs = {
            -- Devotion (7 ranks)
            465, 10290, 643, 10291, 1032, 10292, 10293,
            -- Retribution (5 ranks)
            7294, 10298, 10299, 10300, 10301,
            -- Concentration (single rank)
            19746,
            -- Shadow / Frost / Fire Resistance (3 ranks each)
            19876, 19895, 19896, 19888, 19897, 19898, 19891, 19899, 19900,
            -- Sanctity (Retribution talent, single rank)
            20218,
          } },
    },
    WARLOCK = {
        -- One reminder for the whole armor line. Demon Skin and Demon Armor are
        -- the same ability renamed at rank 3, but they are DISTINCT localized
        -- spell names, and matching here is by name -- so both have to be in the
        -- set or a low-level warlock running Demon Skin would be told they have
        -- no armor up. Same reason the Mage entry carries Frost/Ice/Mage Armor
        -- together, except this line renames itself rather than branching.
        --
        -- Ranks confirmed in Trainer/data/Warlock.lua: Demon Skin r2 at 10,
        -- Demon Armor at 20/30/40/50/60. Demon Skin r1 (687) is absent there
        -- because warlocks start the game already knowing it -- the same
        -- signature as the Paladin's level-1 Seal of Righteousness.
        --
        -- Icon comes from spellIDs[1], so it is the Demon Skin art; the two are
        -- visually near-identical in Classic and this matches how the Mage
        -- armor entry already behaves.
        { key = "demonArmor", label = "Demon Armor", dbKey = "classBuffDemonArmor",
          type = "buff", spellIDs = {
            -- Demon Skin (starting rank, then trained at 10)
            687, 696,
            -- Demon Armor (20/30/40/50/60)
            706, 1086, 11733, 11734, 11735,
          } },
    },
    ROGUE = {
        -- Riposte, on the reminder bar rather than a nameplate: the parry
        -- window is a PLAYER state, and the Classic tooltip is explicit that
        -- Riposte can be used on an enemy that never parried you. Pinning the
        -- icon to the mob that happened to trigger it would imply a targeting
        -- restriction the ability does not have.
        --
        -- Same reactive machinery as the Warrior's Revenge: shown while the
        -- window is open, reverse swipe draining over it, no pulse. The
        -- cooldown gate applies only to the IsUsableSpell fallback, so a parry
        -- landing during Riposte's cooldown still lights the icon.
        --
        -- 14251 is a single-rank Combat talent, correctly absent from
        -- Trainer/data/Rogue.lua. No talent check is needed: an untalented
        -- rogue does not know the spell, so KnowsAny hides the entry.
        { key = "riposte", label = "Riposte", dbKey = "classBuffRiposte",
          type = "reactive", spellIDs = { 14251 },
          reactiveWindow = 5,
          reactiveMisses = { PARRY = true } },
    },
    HUNTER = {
        -- Mongoose Bite opens for five seconds after the hunter dodges an
        -- incoming attack. Like Revenge and Riposte, it can be used on any
        -- target, so the player-owned reminder bar is the correct surface.
        -- Ranks are trained at levels 16/30/44/58 in Trainer/data/Hunter.lua.
        { key = "mongooseBite", label = "Mongoose Bite", dbKey = "classBuffMongooseBite",
          type = "reactive", spellIDs = { 1495, 14269, 14270, 14271 },
          reactiveWindow = 5,
          reactiveMisses = { DODGE = true } },

        -- GetPetHappiness exposes the current tier, not the hidden happiness
        -- total. PetHappiness.lua caches that state once per second and this
        -- entry joins the normal reminder queue only while the pet is not Happy.
        { key = "feedPet", label = "Feed Pet", dbKey = "classBuffFeedPet",
          type = "petHappiness", icon = 132165 },

        -- One reminder for all six Aspects -- ANY aspect satisfies it, so it
        -- fires only when the hunter is running with no aspect at all. That
        -- deliberately includes the travel aspects: a hunter in Cheetah or Pack
        -- is aspected, just not for combat, and second-guessing that here would
        -- make the icon nag during every flight path run.
        --
        -- Every rank confirmed in Trainer/data/Hunter.lua: Hawk 10-58, Monkey
        -- 4, Cheetah 20, Beast 30, Pack 40, Wild 46/56. Hawk rank 7 (25296) is
        -- deliberately omitted -- it is absent from the trainer data and could
        -- not be confirmed for this client, and the six ranks below already
        -- cover both the name and the knowledge gate.
        { key = "aspect", label = "Aspect", dbKey = "classBuffAspect",
          type = "buff", spellIDs = {
            -- Hawk (6 ranks)
            13165, 14318, 14319, 14320, 14321, 14322,
            -- Monkey, Cheetah, Beast, Pack (single rank each)
            13163, 5118, 13161, 13159,
            -- Wild (2 ranks)
            20043, 20190,
          } },

        -- Talent-locked, and the gate is the point: rank 1 (19506) comes from
        -- the Marksmanship talent, which is why only ranks 2-3 (20905/20906 at
        -- levels 50/60) appear in the trainer data -- the same shape as the
        -- Priest's Divine Spirit. An untalented hunter knows none of these, so
        -- KnowsAny keeps the reminder hidden rather than nagging about a spell
        -- they cannot cast.
        { key = "trueshotAura", label = "Trueshot Aura", dbKey = "classBuffTrueshotAura",
          type = "buff", spellIDs = { 19506, 20905, 20906 } },
    },
    PRIEST = {
        -- Prayer of Fortitude (21562/21564) is in the same set so a raid-buffed
        -- priest is not reminded anyway -- the Mark of the Wild / Gift of the
        -- Wild pattern. It is absent from Trainer/data/Priest.lua because it is
        -- learned from a drop book rather than a trainer; the six Power Word
        -- ranks below are all confirmed there at levels 1/12/24/36/48/60.
        { key = "fortitude", label = "Power Word: Fortitude", dbKey = "classBuffFortitude",
          type = "buff", partyReminder = true,
          spellIDs = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 } },

        -- Self-only, so no partyReminder. Ranks confirmed in the trainer data
        -- at 12/20/30/40/50/60.
        { key = "innerFire", label = "Inner Fire", dbKey = "classBuffInnerFire",
          type = "buff", spellIDs = { 588, 7128, 602, 1006, 10951, 10952 } },

        -- Talent-gated, and the gate is the point: rank 1 (14752) comes from
        -- the Discipline talent, which is why only ranks 2-4 (14818/14819/27841
        -- at levels 40/50/60) appear in the trainer data. An untalented priest
        -- knows none of these, so KnowsAny keeps the reminder hidden for them
        -- instead of nagging about a spell they cannot cast.
        --
        -- Prayer of Spirit (27681, trainer level 60) is included for the same
        -- reason as Prayer of Fortitude above.
        { key = "divineSpirit", label = "Divine Spirit", dbKey = "classBuffDivineSpirit",
          type = "buff", spellIDs = { 14752, 14818, 14819, 27841, 27681 } },

        -- DEFAULT OFF. Dwarf-only racial (trainer data has it at level 20).
        -- No race check is needed here: a non-dwarf priest never learns 6346,
        -- so KnowsAny hides the entry on its own. Fear Ward is also consumed by
        -- the first fear rather than expiring, so left on it would fire
        -- constantly -- hence off unless deliberately enabled.
        { key = "fearWard", label = "Fear Ward", dbKey = "classBuffFearWard",
          type = "buff", spellIDs = { 6346 } },

        -- DEFAULT OFF: situational resistance buff, not a standing one.
        -- Prayer of Shadow Protection (27683) is in the set for the same reason
        -- as the other Prayers; it is absent from the trainer data because it
        -- comes from a drop book (Codex, Darkmaster Gandling). The three Shadow
        -- Protection ranks are confirmed there at 30/42/56.
        { key = "shadowProtection", label = "Shadow Protection", dbKey = "classBuffShadowProtection",
          type = "buff", spellIDs = { 976, 10957, 10958, 27683 } },
    },
    MAGE = {
        -- Clearcasting proc from the Arcane Concentration talent (12577); the
        -- buff aura itself is 12536. Same treatment as the Shaman Elemental
        -- Focus proc: procBuff is an INVERTED reminder that shows while the
        -- buff IS up, and no knowledge gate is needed because an untalented
        -- mage never sees the aura.
        --
        -- LISTED FIRST deliberately: icons lay out in catalog order, so the
        -- proc leads the row ahead of the Intellect and Armor reminders.
        --
        -- The key is `mageClearcasting`, NOT `clearcasting`: RebuildCaches
        -- walks every class in CATALOG and writes nameCache[e.key], so keys
        -- are global across the whole catalog. Reusing the Shaman's key would
        -- make the two overwrite each other in an order pairs() does not
        -- guarantee, and a mage could silently end up matching 16246.
        { key = "mageClearcasting", label = "Clearcasting",
          dbKey = "classBuffMageClearcasting",
          type = "procBuff", spellIDs = { 12536 } },
        -- 23028 is Arcane Brilliance (the group version): in the name set so a
        -- Brilliance buff satisfies the Intellect reminder.
        { key = "arcaneIntellect", label = "Arcane Intellect", dbKey = "classBuffArcaneIntellect",
          type = "buff", partyReminder = true,
          spellIDs = { 1459, 1460, 1461, 10156, 10157, 23028 } },
        -- One reminder for the whole armor family: satisfied by ANY of Ice Armor
        -- (7302, 7320, 10219, 10220), Mage Armor (6117, 22782, 22783), or the
        -- low-level Frost Armor ranks (168, 7300, 7301) -- it fires only when no
        -- armor is up at all. Frost Armor also makes the entry "known" from
        -- level 1. Icon resolves from Ice Armor rank 1.
        { key = "mageArmor", label = "Armor", dbKey = "classBuffMageArmor",
          type = "buff", spellIDs = { 7302, 7320, 10219, 10220, 6117, 22782, 22783, 168, 7300, 7301 } },
    },
}

-- Keep the player reminder list separate from the shared catalog. Party-frame
-- reminders consume the same catalog later, so appending class-agnostic entries
-- must not mutate a class's reusable definition table.
local MYBUFFS = {}
for _, entry in ipairs(CATALOG[PLAYER_CLASS] or {}) do
    MYBUFFS[#MYBUFFS + 1] = entry
end

local USES_TALENT_REMINDER = type(ns.CombatProviderUsesClassBuffTalentReminder) ~= "function"
    or ns.CombatProviderUsesClassBuffTalentReminder() == true

-- Class-agnostic: unspent talent points. type "talents" needs no spell
-- knowledge or aura scan -- presence is simply "no unspent points".
if USES_TALENT_REMINDER then
    MYBUFFS[#MYBUFFS + 1] = {
        key = "talentPoints", label = "Unspent Talent Points",
        dbKey = "classBuffTalentPoints", type = "talents", icon = 132222,
    }
end

local HAS_REACTIVE = false
for _, entry in ipairs(MYBUFFS) do
    if entry.type == "reactive" then HAS_REACTIVE = true break end
end

local HAS_DURATION_AURAS = false
for _, entry in ipairs(MYBUFFS) do
    if entry.type == "buff" or entry.type == "procBuff" then
        HAS_DURATION_AURAS = true
        break
    end
end

local CB = ns.ClassBuffs or {}
ns.ClassBuffs = CB
CB.CATALOG = CATALOG

local LCD = LibStub and LibStub("LibClassicDurations", true)

local GetTime            = GetTime
local UnitGUID           = UnitGUID
local CreateFrame        = CreateFrame
local InCombatLockdown   = InCombatLockdown
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemTexture = GetInventoryItemTexture
local GetWeaponEnchantInfo = ns.API.GetWeaponEnchantInfo or GetWeaponEnchantInfo
local IsUsableSpell      = IsUsableSpell
local GetSpellCooldown   = GetSpellCooldown
local UnitBuff           = ns.API.UnitBuff
local GetSpellInfo       = ns.API.GetSpellInfo
local GetSpellTexture    = ns.API.GetSpellTexture
local IsSpellKnown       = ns.API.IsSpellKnown
local IsPlayerSpell      = ns.API.IsPlayerSpell
local pairs, ipairs      = pairs, ipairs
local tonumber           = tonumber
local math_max, math_ceil = math.max, math.ceil

local FALLBACK_IMBUE_ICON = "Interface\\Icons\\Spell_Fire_FlameTongue"

local DB = ns.DB   -- shared root accessor (Config.lua)

-- ---------------------------------------------------------------------------
-- Known-spell / name caching
-- ---------------------------------------------------------------------------
local nameCache = {}   -- entry.key -> { [localizedName]=true }
local knownCache = {}  -- entry.key -> bool
local iconCache  = {}  -- entry.key -> texture path
local cachesReady = false


local function KnowsAny(ids)
    for _, id in ipairs(ids) do
        if ns.API.IsKnownSpellID(id) then return true end
    end
    return false
end

local function CacheBuffEntry(e)
    if not e or (e.type ~= "buff" and e.type ~= "procBuff" and e.type ~= "reactive") then return end
    local names = {}
    for _, id in ipairs(e.spellIDs or {}) do
        local n = GetSpellInfo(id)
        if n then names[n] = true end
    end
    nameCache[e.key] = names
    iconCache[e.key] = GetSpellTexture(e.spellIDs and e.spellIDs[1]) or FALLBACK_IMBUE_ICON
end

local function EnsureBuffEntryCache(e)
    if e and (e.type == "buff" or e.type == "procBuff") and not nameCache[e.key] then
        CacheBuffEntry(e)
    end
end

local function RebuildCaches()
    wipe(nameCache); wipe(knownCache); wipe(iconCache)

    -- Localized names/icons are useful for both the player's movable reminder
    -- bar and party-frame class reminders, so build them once for every class.
    for _, entries in pairs(CATALOG) do
        for _, e in ipairs(entries) do
            CacheBuffEntry(e)
        end
    end

    -- Knowledge checks remain player-only: the client cannot inspect another
    -- party member's spellbook, and the self-reminder should still ignore
    -- spells this character has not learned yet.
    for _, e in ipairs(MYBUFFS) do
        if e.type == "buff" then
            EnsureBuffEntryCache(e)
            knownCache[e.key] = KnowsAny(e.knownSpellIDs or e.spellIDs)
        elseif e.type == "procBuff" then
            -- No spellbook gate (talent-granted procs are not spellbook
            -- entries); the buff itself gates visibility.
            EnsureBuffEntryCache(e)
            knownCache[e.key] = true
        elseif e.type == "reactive" then
            -- Trained ability, so a real spellbook gate (unlike procBuff).
            EnsureBuffEntryCache(e)
            knownCache[e.key] = KnowsAny(e.spellIDs)
        elseif e.type == "talents" then
            -- Always "known": every character can earn talent points.
            knownCache[e.key] = true
            iconCache[e.key]  = e.icon
        elseif e.type == "petHappiness" then
            knownCache[e.key] = true
            iconCache[e.key] = e.icon
        else -- weapon imbue
            knownCache[e.key] = KnowsAny(e.imbueSpellIDs)
            local icon
            for _, id in ipairs(e.imbueSpellIDs) do
                if ns.API.IsKnownSpellID(id) then icon = GetSpellTexture(id); if icon then break end end
            end
            iconCache[e.key] = icon or GetSpellTexture(e.imbueSpellIDs[1]) or FALLBACK_IMBUE_ICON
        end
    end
    cachesReady = true
end

-- ---------------------------------------------------------------------------
-- Shared party-reminder API
--
-- UnitFrames/UnitFrames.lua uses this instead of maintaining a second spell catalog.
-- Only buffs this character can provide to party members are eligible. Entries
-- opt in with `partyReminder = true`; self-only auras, weapon enchants, and
-- talent points are excluded. A party unit's helpful auras are scanned once,
-- then matched against the enabled, known entries for the player's class.
--
-- Class-only party mode needs both sides of the state: missing buffs retain the
-- pulsing reminder treatment, while active buffs remain visible with their
-- duration/expiration data for a cooldown swipe and countdown text.
-- ---------------------------------------------------------------------------
local partyAuraNames = {}
local partyAuraSpellIDs = {}
local partyAuraPool = {}
local partyStateScratch = {}

local function ResolvePartyAuraDuration(unit, spellID, caster, duration, expirationTime)
    if (not duration or duration == 0) and LCD and spellID then
        local ok, resolvedDuration, resolvedExpiration =
            pcall(LCD.GetAuraDurationByUnit, LCD, unit, spellID, caster)
        if ok and resolvedDuration and resolvedDuration > 0 then
            return resolvedDuration, resolvedExpiration
        end
    end
    return duration, expirationTime
end

local function ScanPartyAuras(unit)
    wipe(partyAuraNames)
    wipe(partyAuraSpellIDs)

    local auraCount = 0
    for index = 1, 40 do
        local name, texture, count, _, duration, expirationTime, caster, _, _, spellID =
            UnitBuff(unit, index, "HELPFUL")
        if not name then break end

        duration, expirationTime =
            ResolvePartyAuraDuration(unit, spellID, caster, duration, expirationTime)

        auraCount = auraCount + 1
        local aura = partyAuraPool[auraCount]
        if not aura then
            aura = {}
            partyAuraPool[auraCount] = aura
        end
        aura.name = name
        aura.texture = texture
        aura.count = count
        aura.duration = duration
        aura.expirationTime = expirationTime
        aura.caster = caster
        aura.spellID = spellID

        partyAuraNames[name] = aura
        if spellID then partyAuraSpellIDs[spellID] = aura end
    end
end

local function FindPartyAura(entry)
    for _, spellID in ipairs(entry.spellIDs or {}) do
        local aura = partyAuraSpellIDs[spellID]
        if aura then return aura end
    end
    for auraName in pairs(nameCache[entry.key] or {}) do
        local aura = partyAuraNames[auraName]
        if aura then return aura end
    end
end

function CB:GetReminderIcon(entry)
    if not entry then return FALLBACK_IMBUE_ICON end
    if not cachesReady then RebuildCaches() end
    EnsureBuffEntryCache(entry)
    return iconCache[entry.key] or entry.icon or FALLBACK_IMBUE_ICON
end

function CB:CollectPartyBuffStates(unit, results, maxResults)
    results = results or {}
    if not cachesReady then RebuildCaches() end
    if not UnitBuff then
        wipe(results)
        return results, 0
    end

    local limit = math.max(0, tonumber(maxResults) or #MYBUFFS)
    local count = 0

    -- Resolve the enabled catalog entries first. Unsupported classes or a Class
    -- tab with every party-capable entry disabled return without scanning up to
    -- 40 auras on every party UNIT_AURA event.
    for _, entry in ipairs(MYBUFFS) do
        if entry.type == "buff" and entry.partyReminder == true
            and knownCache[entry.key]
            and (entry.partyOnly or ns.Opt(entry.dbKey, true) ~= false) then
            EnsureBuffEntryCache(entry)

            count = count + 1
            local state = results[count]
            if not state then
                state = {}
                results[count] = state
            end
            state.entry = entry
            state.present = false
            state.texture = self:GetReminderIcon(entry)
            state.count = 0
            state.duration = nil
            state.expirationTime = nil
            state.caster = nil
            state.spellID = nil
        end
    end

    for index = count + 1, #results do
        results[index] = nil
    end
    if count == 0 then return results, 0 end

    ScanPartyAuras(unit)
    local shown = 0
    for index = 1, count do
        local state = results[index]
        local aura = FindPartyAura(state.entry)
        if aura then
            state.present = true
            state.texture = aura.texture or state.texture
            state.count = aura.count or 0
            state.duration = aura.duration
            state.expirationTime = aura.expirationTime
            state.caster = aura.caster
            state.spellID = aura.spellID
        end

        if (not state.entry.partyActiveOnly or state.present) and shown < limit then
            shown = shown + 1
            if shown ~= index then results[shown] = state end
        end
    end

    for index = shown + 1, #results do
        results[index] = nil
    end
    return results, shown
end

-- Compatibility helper retained for callers/tests that only need the old
-- missing-only list. The party frames now consume CollectPartyBuffStates.
function CB:CollectMissingPartyBuffs(unit, results, maxResults)
    results = results or {}
    wipe(results)

    local _, stateCount = self:CollectPartyBuffStates(unit, partyStateScratch)
    local limit = tonumber(maxResults) or stateCount
    local count = 0
    for index = 1, stateCount do
        local state = partyStateScratch[index]
        if state and not state.present then
            count = count + 1
            results[count] = state.entry
            if count >= limit then break end
        end
    end
    return results, count
end

-- Weapon-imbue entries show the equipped weapon's own item icon (looked up
-- live, since weapons can be swapped); everything else uses the cached spell
-- icon. Falls back to the imbue icon when no weapon texture is available.
local WEAPON_SLOT = { weaponMH = 16, weaponOH = 17 }

-- Weapon imbues get a purple frame instead of the silver one, matching how
-- Blizzard styles temporary weapon enchants in the buff bar.
--
-- This is a vertex TINT of the one border texture, not a second asset. The
-- tint multiplies, so the near-black inner band (RGB 10/10/12) stays black
-- while the silver highlight (151/170/176) takes the colour. The factors below
-- were solved to land the highlight on the reference purple's hue: 151*0.83 =
-- 125, 170*0.34 = 58, 176*1.0 = 176. Blue is capped at 1.0 because vertex
-- colour can only darken, which is why the target was matched on hue rather
-- than on exact brightness.
local IMBUE_BORDER_TINT = { 0.83, 0.34, 1.00 }

-- Icons are pooled and reused, so a slot that previously held an imbue must be
-- reset -- otherwise a non-imbue reminder inherits the purple.
local function ApplyBorderTint(f, entry)
    if not f or not f.border then return end
    if entry and WEAPON_SLOT[entry.type] then
        f.border:SetVertexColor(IMBUE_BORDER_TINT[1], IMBUE_BORDER_TINT[2], IMBUE_BORDER_TINT[3])
    else
        f.border:SetVertexColor(1, 1, 1)
    end
end

local function ResolveIcon(e)
    local slot = WEAPON_SLOT[e.type]
    if slot then
        return GetInventoryItemTexture("player", slot) or iconCache[e.key] or FALLBACK_IMBUE_ICON
    end
    return iconCache[e.key] or FALLBACK_IMBUE_ICON
end

-- ---------------------------------------------------------------------------
-- Presence detection -> returns present(bool), remaining(seconds or nil)
-- ---------------------------------------------------------------------------
-- Player buff snapshot, rebuilt once per Evaluate.
--
-- HasBuff used to walk UnitBuff("player", 1..40) from index 1 for EVERY catalog
-- entry, so a class with two aura-backed reminders paid two full walks per
-- evaluation -- and Evaluate runs on every player UNIT_AURA. One shared pass
-- plus a name lookup gives the same answer for one walk, whatever the entry
-- count.
--
-- Both tables are reused, never reallocated: this is the post-combat aura-storm
-- path, where allocation is precisely what is being avoided.
--
-- The index is stored because the old scan returned the FIRST matching aura by
-- aura index, and a name set can legitimately match two active auras at once
-- (Mark of the Wild and Gift of the Wild share one set, as do the three Mage
-- armor families). Iterating the name set with pairs() would pick an arbitrary
-- one and could report the wrong remaining time, so the lowest index still wins.
local buffIndexByName = {}
local buffExpiryByName = {}

local function RefreshBuffSnapshot()
    wipe(buffIndexByName)
    wipe(buffExpiryByName)
    for i = 1, 40 do
        local name, _, _, _, _, expiration = UnitBuff("player", i)
        if not name then break end
        if buffIndexByName[name] == nil then
            buffIndexByName[name] = i
            buffExpiryByName[name] = (expiration and expiration > 0) and expiration or false
        end
    end
end

local function HasBuff(nameSet)
    if not nameSet then return false end
    local bestIndex, bestExpiry
    for name in pairs(nameSet) do
        local index = buffIndexByName[name]
        if index and (not bestIndex or index < bestIndex) then
            bestIndex = index
            bestExpiry = buffExpiryByName[name]
        end
    end
    if not bestIndex then return false end
    return true, bestExpiry and (bestExpiry - GetTime()) or nil
end

local function HasUnspentTalentPoints()
    if not UnitCharacterPoints then return false end
    return (tonumber(UnitCharacterPoints("player")) or 0) > 0
end

local function EntryPresence(e)
    if e.type == "buff" then
        return HasBuff(nameCache[e.key])
    elseif e.type == "talents" then
        -- "Present" means there is nothing to remind the player about.
        return not HasUnspentTalentPoints()
    elseif e.type == "weaponMH" then
        if not GetInventoryItemID("player", 16) then return true end -- no MH weapon: nothing to remind
        local has, mhExp = GetWeaponEnchantInfo()
        return has and true or false, (mhExp and mhExp > 0) and (mhExp / 1000) or nil
    elseif e.type == "weaponOH" then
        if not GetInventoryItemID("player", 17) then return true end -- no OH weapon equipped: skip
        local _, _, _, _, hasOff, ohExp = GetWeaponEnchantInfo()
        return hasOff and true or false, (ohExp and ohExp > 0) and (ohExp / 1000) or nil
    end
    return true
end

-- Is a reactive ability's window currently open?
--
-- Two sources, deliberately OR-ed:
--
--  1. IsUsableSpell -- authoritative, but STANCE-BLIND. Revenge requires
--     Defensive Stance, so an Arms warrior in Battle Stance always reads as
--     unusable even with the window wide open. With Tactical Mastery that is
--     exactly when the proc is worth seeing, since the warrior can swap stance
--     and still land it.
--
--  2. A combat-log window opened by our own block/dodge/parry. Stance-
--     independent, so it covers the case above.
--
-- Neither alone is sufficient: (1) misses the out-of-stance case, and (2)
-- cannot see a window the client granted for a reason we did not observe.
local reactiveUntil = {}   -- entry.key -> GetTime() expiry
local PLAYER_GUID          -- resolved at login; CLEU compares against it

-- Anything longer than the global cooldown is a real cooldown. Comparing
-- against 1.5 rather than 0 keeps the GCD after any other spell from reading
-- as "Revenge is spent".
local GCD_MAX = 1.5

local function ReactiveOnCooldown(names)
    if not names or not GetSpellCooldown then return false end
    for name in pairs(names) do
        local start, duration = GetSpellCooldown(name)
        if start and start > 0 and duration and duration > GCD_MAX then
            return true
        end
    end
    return false
end

-- Returns ready, remaining.
--
-- Two independent sources, and the cooldown applies to only ONE of them:
--
--  1. An observed window from our own block/dodge/parry. Shown even while the
--     ability is on cooldown -- that is the point. Avoidance is hard to notice
--     mid-fight and the default action bar gives no hint, so a window earned
--     during the cooldown must light up immediately rather than at the moment
--     the cooldown happens to end. Otherwise the warrior only starts reacting
--     after the cooldown, losing most of the window.
--
--  2. IsUsableSpell -- the client's own answer, used when we never saw the
--     avoidance (addon loaded mid-window). This one IS cooldown-gated, because
--     IsUsableSpell deliberately ignores cooldowns: after spending Revenge in
--     Defensive Stance it keeps answering "usable" for the full 5s, which would
--     leave the icon lit even though the window was just consumed.
--
-- Spending the ability is handled by ClearReactiveOnCast wiping the window, so
-- "just spent" and "spent, then avoided again" are genuinely different states
-- rather than both being suppressed by the cooldown.
--
-- `remaining` is nil in case 2, so the icon shows solid with no swipe rather
-- than inventing a duration.
local function IsReactiveReady(e)
    local until_ = reactiveUntil[e.key]
    if until_ then
        local remaining = until_ - GetTime()
        if remaining > 0 then return true, remaining end
        reactiveUntil[e.key] = nil
    end

    local names = nameCache[e.key]
    if ReactiveOnCooldown(names) then return false end
    if names and IsUsableSpell then
        for name in pairs(names) do
            if IsUsableSpell(name) then return true end
        end
    end
    return false
end

-- entry should nag right now?
local function ShouldRemind(e, warnSec)
    if not knownCache[e.key] then return false end
    if ns.Opt(e.dbKey, true) == false then return false end
    -- Per-entry combat gate, separate from the global classBuffOnlyInCombat.
    -- Seals last 30s, so out of combat a seal reminder is permanently on and
    -- becomes noise rather than information.
    if e.combatOnlyDbKey and ns.Opt(e.combatOnlyDbKey, false) and not InCombatLockdown() then
        return false
    end
    if e.type == "reactive" then
        -- INVERTED, like procBuff: show while the window is OPEN. No countdown
        -- is returned because IsUsableSpell reports availability, not time
        -- remaining, and inventing one would be a guess.
        local ready, remaining = IsReactiveReady(e)
        if ready then return true, remaining end
        return false
    end
    if e.type == "procBuff" then
        -- INVERTED reminder: show while the proc buff IS active, with its
        -- remaining time for the countdown text; hide once it fades/is spent.
        local present, remaining = HasBuff(nameCache[e.key])
        if present then return true, remaining end
        return false
    end
    if e.type == "petHappiness" then
        return ns.PetHappiness and ns.PetHappiness.NeedsFeed and ns.PetHappiness.NeedsFeed() or false
    end
    local present, remaining = EntryPresence(e)
    if not present then return true, 0 end
    if warnSec > 0 and remaining and remaining > 0 and remaining <= warnSec then
        return true, remaining
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Icon bar / frame pool
-- ---------------------------------------------------------------------------
local bar
local iconPool = {}

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "TurboFaceClassBuffBar", UIParent)
    bar:SetSize(40, 40)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
    bar:SetFrameStrata("MEDIUM")
    CB.bar = bar
    return bar
end

-- Rounded-square styling matching Blizzard's buff icons: a ~2px silver
-- highlight over a ~3px near-black band, corner radius ~13% of the icon.
--
-- Both textures are TurboFace-authored, traced from the measured pixel profile
-- of the live buff frame (silver reads RGB 151/170/176) rather than pointed at
-- a Blizzard path. Classic Era ships no buff-border texture to borrow: the
-- <button>Border on an aura button is the DEBUFF ring, hidden for buffs, which
-- is why the nameplate ring could reuse UI-Debuff-Overlays and this cannot.
--
-- The mask is what rounds the icon. Without it the square icon art shows
-- through outside the frame's rounded corners.
local ICON_MASK   = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Mask-Rounded"
local ICON_BORDER = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Border-Buff"
local BORDER_OUTSET = 2

local function MakeIcon(index)
    local f = CreateFrame("Frame", nil, EnsureBar())
    f:EnableMouse(false)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- A MaskTexture rather than icon:SetMask(): SetMask conflicts with the
    -- SetTexCoord crop above, whereas AddMaskTexture composes with it.
    -- CLAMPTOBLACKADDITIVE keeps the mask from tiling and leaves everything
    -- outside the rounded square fully transparent.
    if f.CreateMaskTexture and icon.AddMaskTexture then
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f)
        mask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        icon:AddMaskTexture(mask)
        f.iconMask = mask
    end

    -- Above the icon but below the OVERLAY text, so the timer stays readable.
    -- Sits BORDER_OUTSET outside the icon; the frame's dark band still reaches
    -- ~1.7px back inside the icon edge at that offset, so no background shows
    -- through the gap. Snapped to whole device pixels for the same reason the
    -- nameplate ring is: a raw offset at a fractional UI scale rounds
    -- inconsistently and shows up as an uneven edge on one side.
    local outset = BORDER_OUTSET
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        outset = PixelUtil.GetNearestPixelSize(BORDER_OUTSET, f:GetEffectiveScale(), 1)
    end
    local border = f:CreateTexture(nil, "ARTWORK", nil, 2)
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -outset, outset)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", outset, -outset)
    border:SetTexture(ICON_BORDER)
    f.border = border

    -- The old square black backing texture is gone: it sat 1px outside the
    -- frame and would poke past the rounded corners. The border's dark band
    -- now provides that separation from the background.

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetTextColor(1, 0.95, 0.2, 1)
    f.text = text

    -- Swipe for reactive windows. Created for every icon so the pool stays
    -- uniform, but only ever driven for entries that supply a duration.
    --
    -- Reversed: this represents a WINDOW OF AVAILABILITY draining away, not a
    -- cooldown filling up. Blizzard's default sweep uncovers the icon as time
    -- passes, which reads as "becoming ready" -- the opposite of what a closing
    -- Revenge window means. Reversed, the shade grows back over the icon as the
    -- window runs out.
    local cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cooldown:SetAllPoints(f)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    cooldown:SetFrameLevel((f:GetFrameLevel() or 0) + 1)
    cooldown:Hide()
    f.cooldown = cooldown

    local pulse = f:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local a1 = pulse:CreateAnimation("Alpha")
    a1:SetFromAlpha(1); a1:SetToAlpha(0.4); a1:SetDuration(0.5); a1:SetOrder(1)
    local a2 = pulse:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.4); a2:SetToAlpha(1); a2:SetDuration(0.5); a2:SetOrder(2)
    f.pulse = pulse

    f:Hide()
    iconPool[index] = f
    return f
end

local function GetIcon(index)
    return iconPool[index] or MakeIcon(index)
end

local function LayoutIcon(f, slot, size, spacing, growth)
    local step = size + spacing
    f:ClearAllPoints()
    if growth == "LEFT" then
        f:SetPoint("RIGHT", bar, "RIGHT", -slot * step, 0)
    elseif growth == "UP" then
        f:SetPoint("BOTTOM", bar, "BOTTOM", 0, slot * step)
    elseif growth == "DOWN" then
        f:SetPoint("TOP", bar, "TOP", 0, -slot * step)
    else -- RIGHT
        f:SetPoint("LEFT", bar, "LEFT", slot * step, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Evaluation
-- ---------------------------------------------------------------------------
local testUntil = 0

local function HideAllIcons()
    for _, f in pairs(iconPool) do
        if f.pulse then f.pulse:Stop() end
        if f.cooldown then f.cooldown:Hide() end
        f:Hide()
    end
end

-- Layout change-guard: SetTexture/SetPoint/font churn only happens when the
-- shown set (or its visuals) actually changes; steady-state ticks just refresh
-- the countdown text. lastSig captures everything that affects layout.
local lastSig

-- The /test positioning window needs Movers available but is not itself a
-- stored preference, so this is a bare Movers check rather than the
-- ns.MoverDependentEnabled gate used by SelfReminderActive below. The old
-- `(not ns.MoversEnabled) or ...` load-order fallback was dead: Core/Config.lua
-- loads second and every call here is at runtime.
local function MoversAvailable()
    return ns.MoversEnabled()
end

local function SelfReminderActive()
    local on = ns.Opt("classBuffEnabled", true) ~= false
    return ns.MoverDependentEnabled(on)
end

local function Evaluate()
    -- MODULE MASTER GATE: modules.class off -> no class-specific behavior at
    -- all. ns.ModuleEnabled fails open, so an unmigrated DB is unaffected.
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then
        if lastSig ~= "off" then lastSig = "off"; HideAllIcons() end
        return
    end
    local enabled = SelfReminderActive()
    local testing = GetTime() < testUntil and MoversAvailable()
    if not enabled and not testing then
        if lastSig ~= "off" then lastSig = "off"; HideAllIcons() end
        return
    end

    EnsureBar()

    if not testing and ns.Opt("classBuffOnlyInCombat", false) and not InCombatLockdown() then
        if lastSig ~= "off" then lastSig = "off"; HideAllIcons() end
        return
    end

    local size    = math_max(16, tonumber(ns.Opt("classBuffIconSize", 40)) or 40)
    local spacing = tonumber(ns.Opt("classBuffSpacing", 6)) or 6
    local warnSec = tonumber(ns.Opt("classBuffWarnSeconds", 0)) or 0
    local growth  = ns.Opt("classBuffGrowth", "RIGHT")
    local pulseOn = ns.Opt("classBuffPulse", true) ~= false

    -- One aura walk for the whole pass. Must happen before the ShouldRemind
    -- loop below, which reads the snapshot rather than calling UnitBuff itself.
    RefreshBuffSnapshot()

    bar:SetSize(size, size)

    -- Pass 1: decide what shows and build the layout signature
    local shows, rems, icons = {}, {}, {}
    local sig = size .. ":" .. spacing .. ":" .. growth .. ":" .. (pulseOn and 1 or 0)
    for i, e in ipairs(MYBUFFS) do
        local show, remaining
        if e.partyOnly then
            show = false
        elseif testing then
            show = (ns.Opt(e.dbKey, true) ~= false) and knownCache[e.key]
            remaining = 0
        else
            show, remaining = ShouldRemind(e, warnSec)
        end
        shows[i], rems[i] = show, remaining
        if show then
            icons[i] = ResolveIcon(e)
            sig = sig .. "|" .. i .. "=" .. tostring(icons[i])
        end
    end

    local layoutChanged = sig ~= lastSig
    lastSig = sig

    -- Pass 2: apply. Full layout only when the signature changed; countdown
    -- text refreshes every tick (it is the only per-tick visual).
    local slot = 0
    for i, e in ipairs(MYBUFFS) do
        if shows[i] then
            local f = GetIcon(slot)
            if layoutChanged then
                f:SetSize(size, size)
                f.icon:SetTexture(icons[i])
                ApplyBorderTint(f, e)
                LayoutIcon(f, slot, size, spacing, growth)
                f:SetAlpha(1)
                f:Show()
                -- Reactive windows read as a state, not an alarm: a pulsing
                -- icon fights the swipe for attention, so they stay solid
                -- regardless of the global pulse setting.
                if pulseOn and e.type ~= "reactive" then
                    if not f.pulse:IsPlaying() then f.pulse:Play() end
                else
                    f.pulse:Stop(); f:SetAlpha(1)
                end
            end
            if f.cooldown then
                local remaining = rems[i]
                if e.type == "reactive" and remaining and remaining > 0 then
                    -- Anchor the swipe to the FULL window, not the remaining
                    -- time, or every refresh would restart it from full.
                    local total = tonumber(e.reactiveWindow) or 5
                    f.cooldown:SetCooldown(GetTime() - (total - remaining), total)
                    f.cooldown:Show()
                else
                    f.cooldown:Hide()
                end
            end
            if f.text then
                local remaining = rems[i]
                -- procBuff icons always count down their remaining proc time;
                -- normal reminders only show text in the warn-before-expiry window
                if remaining and remaining > 0 and (warnSec > 0 or e.type == "procBuff") then
                    if layoutChanged then
                        ns:StyleFeatureFont(f.text, math_max(9, size * 0.4), "classFont", "classTextStyle")
                    end
                    f.text:SetText(math_ceil(remaining))
                    f.text:Show()
                else
                    f.text:SetText(""); f.text:Hide()
                end
            end
            slot = slot + 1
        end
    end

    if layoutChanged then
        -- hide any leftover icons from a previous, larger evaluation
        for i = slot, #iconPool do
            local f = iconPool[i]
            if f then
                f.pulse:Stop()
                if f.cooldown then f.cooldown:Hide() end
                f:Hide()
            end
        end
    end
end

-- Forward declaration: the reactive handlers below run long before the
-- coalescer is defined further down the file, and a local referenced above its
-- own declaration silently resolves to a nil global instead.
local QueueEvaluate

-- ---------------------------------------------------------------------------
-- Reactive window tracking (combat log)
--
-- Registered through the shared ns.CLEU dispatcher, and only for a class that
-- actually has a reactive entry -- see HAS_REACTIVE at activation.
-- ---------------------------------------------------------------------------
local REACTIVE_CLEU_EVENTS = { SWING_MISSED = true, SPELL_MISSED = true }

local function OnReactiveCombatLog(info)
    local subevent = info[2]
    if subevent ~= "SWING_MISSED" and subevent ~= "SPELL_MISSED" then return end

    -- The avoidance has to be OURS: destGUID is the player, i.e. we blocked,
    -- dodged or parried an incoming attack.
    if info[8] ~= PLAYER_GUID then return end

    local missType = (subevent == "SWING_MISSED") and info[12] or info[15]
    if not missType then return end

    local now = GetTime()
    local opened = false
    for _, e in ipairs(MYBUFFS) do
        if e.type == "reactive" and e.reactiveMisses and e.reactiveMisses[missType] then
            reactiveUntil[e.key] = now + (tonumber(e.reactiveWindow) or 5)
            opened = true
        end
    end
    if opened then QueueEvaluate() end
end

-- Using the ability consumes the window. Without this the icon would linger
-- for the remainder of the 5s after the warrior has already spent it.
local function ClearReactiveOnCast(spellID)
    if not spellID then return end
    for _, e in ipairs(MYBUFFS) do
        if e.type == "reactive" and reactiveUntil[e.key] then
            for _, id in ipairs(e.spellIDs or {}) do
                if id == spellID then
                    reactiveUntil[e.key] = nil
                    QueueEvaluate()
                    return
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Driver: cheap 0.5s ticker plus event nudges. Only runs for supported classes.
-- ---------------------------------------------------------------------------
local ticker

local function StartTicker()
    if ticker then return end
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(0.5, Evaluate)
    end
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    HideAllIcons()
end

local function SyncTicker()
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then
        StopTicker()
        return
    end
    if SelfReminderActive() or (GetTime() < testUntil and MoversAvailable()) then
        StartTicker()
    else
        StopTicker()
    end
end

local function RefreshPartyAuras()
    -- ClassBuffs only changes reminder state/content. PartyPetAuras owns its
    -- own gate/event/layout lifecycle, so request a content refresh rather than
    -- re-running the whole surface activation path.
    if ns.PartyAuras and ns.PartyAuras.UpdateAll then
        ns.PartyAuras.UpdateAll()
    end
end

local function PartyReminderActive()
    if ns.ModuleEnabled and not ns.ModuleEnabled("auras", "party") then return false end
    local auras = DB().auras
    return type(auras) == "table" and auras.partyClassRemindersEnabled == true
end

local function RuntimeNeeded()
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then return false end
    return SelfReminderActive()
        or PartyReminderActive()
        or (GetTime() < testUntil and MoversAvailable())
end

local function SyncPetHappinessRuntime()
    if ns.PetHappiness and ns.PetHappiness.SetActive then
        local enabled = SelfReminderActive() and ns.Opt("classBuffFeedPet", true) ~= false
        if enabled and ns.Opt("classBuffOnlyInCombat", false) and not InCombatLockdown() then
            enabled = false
        end
        ns.PetHappiness.SetActive(enabled)
    end
end

local function NeedsLCD()
    if not HAS_DURATION_AURAS then return false end
    return SelfReminderActive() or PartyReminderActive()
end

-- Event frame is lazy. ClassBuffs is activated from Core only after saved
-- module gates are normalized; a disabled reminder subsystem stays frameless.
local evt
local ClassBuffOnEvent
local EnsureEventFrame
local initialized = false
local lcdRegistered = false

local function SyncLCDRuntime()
    local shouldRegister = initialized and NeedsLCD()
    if shouldRegister and not lcdRegistered and LCD and LCD.RegisterFrame then
        pcall(LCD.RegisterFrame, LCD, EnsureEventFrame())
        lcdRegistered = true
    elseif not shouldRegister and lcdRegistered then
        if LCD and LCD.UnregisterFrame then pcall(LCD.UnregisterFrame, LCD, evt) end
        lcdRegistered = false
    end
end

-- Aura-driven evaluation is COALESCED, for the same reason AuraStyle.lua
-- coalesces its restyle: a burst of player UNIT_AURA events used to run a full
-- synchronous Evaluate() each. Post-combat is the worst case -- every proc,
-- shout, seal and HoT expires within a second or two of the fight ending, each
-- one its own event, each one a full layout pass.
--
-- 10 Hz matches the AuraStyle coalescer and is well inside the reaction time a
-- reminder bar needs. The 0.5 s ticker still drives countdown text, so a missed
-- coalescing window costs nothing visible.
--
-- Deliberately NOT registered as `immediate` (see ARCHITECTURE.md §4.5a): an
-- immediate pulse per invalidation is exactly what turns a coalescer back into
-- one callback per event.
local evaluateDirty = false
local evaluateToken = {}

local function EvaluateCoalescedTick()
    evaluateDirty = false
    ns.Cadence:Remove(evaluateToken)
    Evaluate()
end

function QueueEvaluate()
    if evaluateDirty then return end
    evaluateDirty = true
    ns.Cadence:Add(evaluateToken, 0.10, EvaluateCoalescedTick)
end

local function HandleClassBuffEvent(_, event, unit, _arg2, spellID)
    if event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        if unit and unit ~= "player" then return end
        -- Coalesced: the storm case. See QueueEvaluate above.
        QueueEvaluate()
    elseif event == "CHARACTER_POINTS_CHANGED" and USES_TALENT_REMINDER then
        Evaluate()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" then ClearReactiveOnCast(spellID) end
    elseif event == "SPELL_UPDATE_USABLE" or event == "SPELL_UPDATE_COOLDOWN" then
        -- Coalesced, not a direct Evaluate: this event also fires on cooldown
        -- and power changes, so it arrives in bursts. It must never reach the
        -- else branch below, which rebuilds the whole catalog cache.
        QueueEvaluate()
    elseif event == "SPELLS_CHANGED" or event == ns.API.LEARNED_SPELL_EVENT then
        RebuildCaches(); Evaluate(); RefreshPartyAuras()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        -- Combat state only changes visibility/ticker policy. Spell names, icons,
        -- and known-spell state cannot change merely because combat started or
        -- ended, so rebuilding the entire catalog here was wasted post-kill work.
        SyncTicker(); SyncPetHappinessRuntime(); Evaluate()
    else
        -- Login/equipment changes can affect known imbues/spells and still need
        -- the complete cache rebuild.
        PLAYER_GUID = PLAYER_GUID or UnitGUID("player")
        RebuildCaches(); SyncTicker(); Evaluate()
    end
end

ClassBuffOnEvent = function(frame, event, unit, arg2, arg3)
    ns.KillTrace("Combat/ClassBuffs:", event, HandleClassBuffEvent, frame, event, unit, arg2, arg3)
end

EnsureEventFrame = function()
    if evt then return evt end
    evt = CreateFrame("Frame")
    evt:SetScript("OnEvent", ClassBuffOnEvent)
    return evt
end

-- ---------------------------------------------------------------------------
-- Activation / public API
-- ---------------------------------------------------------------------------
local function RegisterRuntimeEvents()
    local frame = EnsureEventFrame()
    -- player-only registration: nameplate/party UNIT_AURA spam never dispatches here
    if frame.RegisterUnitEvent then
        frame:RegisterUnitEvent("UNIT_AURA", "player")
        frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    else
        frame:RegisterEvent("UNIT_AURA")
        frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    end
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent(ns.API.LEARNED_SPELL_EVENT)
    -- Leveling by itself does not change learned spells, localized spell names,
    -- icons, or party-buff capability. CHARACTER_POINTS_CHANGED below handles
    -- the one level-driven reminder that matters (new talent points) without a
    -- full all-class cache rebuild.
    if USES_TALENT_REMINDER then
        frame:RegisterEvent("CHARACTER_POINTS_CHANGED")  -- unspent talent points reminder
    end
    -- Fires the moment a reactive ability becomes usable or lapses, so the
    -- Revenge window does not wait up to 0.5s for the ticker to notice.
    -- Registered only for a class that has a reactive entry: it also fires on
    -- every cooldown and power change, which is pure overhead for everyone else.
    if HAS_REACTIVE then
        frame:RegisterEvent("SPELL_UPDATE_USABLE")
        -- Fires when the cooldown starts and again when it ends, so the icon
        -- clears on spend and returns promptly if window time survives.
        frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        -- Consuming the ability closes the window early.
        if frame.RegisterUnitEvent then
            frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
    end
end

local function DeactivateRuntime()
    if evt and evt.UnregisterAllEvents then evt:UnregisterAllEvents() end
    if lcdRegistered and LCD and LCD.UnregisterFrame then
        pcall(LCD.UnregisterFrame, LCD, evt)
    end
    lcdRegistered = false
    initialized = false
    -- Disabled means dormant (§1.4): a pending coalesced evaluation must not
    -- outlive the runtime that queued it.
    evaluateDirty = false
    if ns.Cadence then ns.Cadence:Remove(evaluateToken) end
    if ns.CLEU then ns.CLEU:Unregister(OnReactiveCombatLog) end
    if ns.PetHappiness and ns.PetHappiness.SetActive then ns.PetHappiness.SetActive(false) end
    wipe(reactiveUntil)
    StopTicker()
end

function CB:Init()
    if initialized then return end
    if not RuntimeNeeded() then
        DeactivateRuntime()
        return
    end
    initialized = true
    SyncPetHappinessRuntime()
    RegisterRuntimeEvents()
    PLAYER_GUID = PLAYER_GUID or UnitGUID("player")
    -- Shared dispatcher, and only for a class with a reactive entry, so no
    -- other class pays for combat-log decoding it will never use.
    if HAS_REACTIVE and ns.CLEU then
        ns.CLEU:Register(OnReactiveCombatLog, REACTIVE_CLEU_EVENTS)
    end

    -- Aura durations are a fallback for Classic API cases that omit duration /
    -- expiration. ClassBuffs therefore owns its LCD registration rather than
    -- relying on AuraStyle being enabled as an accidental side effect.
    SyncLCDRuntime()

    -- Core calls us while PLAYER_LOGIN is already being dispatched, so perform
    -- the old login initialization synchronously.
    RebuildCaches()
    SyncTicker()
    Evaluate()
    RefreshPartyAuras()
end

function CB:Refresh()
    if not RuntimeNeeded() then
        DeactivateRuntime()
        RefreshPartyAuras()
        return
    end
    if not initialized then self:Init() end
    if not initialized then return end
    SyncPetHappinessRuntime()
    RebuildCaches()
    lastSig = nil        -- settings changed: force a full re-layout
    SyncLCDRuntime()
    SyncTicker()
    if SelfReminderActive() and ns.Movers and ns.Movers.active then
        self:RegisterMover()
    end
    Evaluate()
    RefreshPartyAuras()
end

-- PetHappiness owns the once-per-second API read and calls this only when the
-- cached Happy/Content/Unhappy state crosses the reminder boundary.
function CB:RefreshPetHappinessReminder()
    if initialized then Evaluate() end
end

-- Force every enabled/known icon on for a few seconds so the bar can be placed.
function CB:Test(seconds)
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then return end
    if not MoversAvailable() then
        ns:Chat("Class", "Class Buff Bar requires TurboFace Movers to be enabled.")
        return
    end
    local duration = tonumber(seconds) or 5
    testUntil = GetTime() + duration
    if not initialized then self:Init() end
    if not initialized then return end
    RebuildCaches()
    StartTicker()
    Evaluate()
    -- If reminders themselves are disabled, tear the temporary ticker/runtime
    -- back down once the positioning test expires.
    if C_Timer and C_Timer.After then
        C_Timer.After(duration + 0.1, function() CB:Refresh() end)
    end
    ns:Chat("Class", "showing all tracked buff icons for 5s -- position the bar with /tfmove")
end

-- Register the bar with the Movers system (called from MoverSystems Init).
function CB:RegisterMover()
    if ns.ModuleEnabled and not ns.ModuleEnabled("class") then return end
    local testing = GetTime() < testUntil and MoversAvailable()
    if not SelfReminderActive() and not testing then return end
    if not ns.Movers or not ns.Movers.RegisterElement then return end
    EnsureBar()
    ns.Movers:RegisterElement("ClassBuffBar", bar, {
        label = "Class Buffs",
        overlayWidth = 180,
        overlayHeight = 44,
        fallbackPoint = { "CENTER", UIParent, "CENTER", 0, -140 },
        defaultPoint  = { "CENTER", UIParent, "CENTER", 0, -140 },
    })
end
