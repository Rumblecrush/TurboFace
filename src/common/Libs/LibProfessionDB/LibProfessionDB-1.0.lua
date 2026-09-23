-- LibProfessionDB-1.0
-- A standalone, offline profession/recipe database for World of Warcraft:
-- look up a crafting recipe's name, reagents, skill-up difficulty tiers,
-- required skill, produced item, and enriched effect text — all without the
-- trade skill window being open and without any runtime scan.
--
-- WoW exposes recipe data only while a profession window is open (and only for
-- professions the player knows), so the data is pre-built from the game's own
-- client DBC tables (SkillLineAbility / SpellReagents / SpellEffect /
-- SpellItemEnchantment / ItemSparse) and shipped here as static, per-game-
-- version / per-locale data files under Data/<version>/<locale>/<Profession>.lua.
--
-- Usage (any addon):
--   local DB = LibStub("LibProfessionDB-1.0", true)
--   if DB and DB:IsReady() then
--       local r = DB:GetRecipe(333, 13626)       -- Enchant Chest - Minor Stats
--       -- r = { name, difficulty={orange,yellow,green,grey}, reagents={[id]=n},
--       --       requiredSkill, effect, itemId, craftedItemId, teaches }
--       for _, hit in ipairs(DB:Search({ query = "agility" })) do
--           print(hit.profId, hit.recipeId, hit.name, hit.effect)
--       end
--   end
--
-- Data is loaded by the shipped Data files via lib:LoadRecipes(profId, recipes).
-- Other addons may also call LoadRecipes to contribute / top-up recipes.

-- The TOG multi-root VS Code workspace disables the Lua 5.1 builtin library for
-- analysis, so the language server flags standard globals (pairs, next, type,
-- tonumber, table, ...) as undefined inside this folder. Every global this file
-- uses is a standard Lua builtin or a declared WoW API, so silence the false
-- positives here rather than re-declaring the whole Lua stdlib per workspace.
---@diagnostic disable: undefined-global

local MAJOR, MINOR = "LibProfessionDB-1.0", 11
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end   -- a same-or-newer version is already loaded

-- Persistent state across library upgrades.
lib.recipes    = lib.recipes    or {}   -- [profId] = { [recipeId] = entry }
lib.profCounts = lib.profCounts or {}   -- [profId] = recipe count
lib.count      = lib.count      or 0    -- total recipes loaded
lib.meta       = lib.meta       or {}   -- { locale, game }
-- Applied-enchant catalog: the permanent gear enchants NO profession crafts —
-- applied by a consumable item (Dire Maul arcanums, Zul'Gurub / Zandalar head /
-- shoulder / leg enchants, armor kits, shield spikes). Keyed by SpellItemEnchantment
-- id, stitched from LoadEnchantsCore (slots/stats/itemId) + LoadEnchantsNames (name).
-- Kept OUT of `recipes` on purpose: these aren't profession recipes, so they never
-- appear via GetProfessions()/GetRecipes(). Query them with GetEnchant /
-- EnchantsForSlot / IterateEnchants, which also fold in the craftable enchants.
lib.enchants = lib.enchants or {}       -- [enchantId] = { slots, stats, itemId, name }

-- Recipe-scroll data. Moved here from LibItemDB-1.0 (MINOR 19) on 2026-08-06:
-- these are facts about RECIPES, keyed by craft spell id exactly as `recipes` is,
-- so they belong with recipe data. LibItemDB keeps GetLink/GetName, which answer
-- questions about an *item*.
--
--   recipeItems:      [craftSpellID] = teachingItemID. From the DBC join
--                     ItemEffect.SpellID -> SpellEffect[Effect=36].EffectTriggerSpell.
--   skillRankBooks:   [craftSpellID] = true for a skill-RANK book ("Expert Fishing -
--                     The Bass and You"). It genuinely teaches a spell, so the join
--                     resolves it, but it is not a craft recipe.
--   syntheticRecipes: [craftSpellID] = { skillLineID, craftedItemID } for a recipe
--                     with NO real scroll -- roughly a third, trainer-taught.
--                     **There is no itemID field and never will be:** a fabricated
--                     id is permanently cache-cold and fails silently in every item
--                     API, so consumers branch on isSynthetic instead.
--   recipeScrollPrefixes: [skillLineID] = localized prefix ("Plans: ", "Plans : " --
--                     French puts a space before the colon, zhCN uses a full-width
--                     one). DERIVED at build time, never transcribed.
--   recipeScrollUseText:  [skillLineID] = "Teaches you how to sew %s." Derived from
--                     the TEACHING SPELL's description, not the scroll item's -- the
--                     item field is populated for 60 of 1,073 Vanilla scrolls
--                     against the spell's 1,022.
lib.recipeItems          = lib.recipeItems          or {}
lib.skillRankBooks       = lib.skillRankBooks       or {}
lib.syntheticRecipes     = lib.syntheticRecipes     or {}
lib.recipeScrollPrefixes = lib.recipeScrollPrefixes or {}
-- [skillLineID] = how many real scrolls the prefix above was derived from. See
-- GetRecipeScrollPrefix; a separate table rather than a richer value so a data
-- file generated before this existed still loads unchanged.
lib.recipeScrollPrefixSamples = lib.recipeScrollPrefixSamples or {}
lib.recipeScrollUseText  = lib.recipeScrollUseText  or {}

-- Never-implemented recipes (MINOR 9). [craftSpellID] = true for a recipe that
-- exists in the client's spell tables but was never obtainable by any means, in
-- any expansion -- no trainer, no vendor, no drop, no quest.
--
-- No client signal reveals this, which is why it has to be shipped: the spell
-- resolves, the crafted item resolves, and every generic "is this real on this
-- client" heuristic passes. Consumers listing recipes a character has yet to
-- learn were showing them as attainable -- Stormcloth Pants, Rune Edge, Blood
-- Talon, Elixir of Tongues -- with no way to tell them from a recipe the player
-- simply has not found yet.
--
-- Curated by AllTheThings (MIT), extracted at build time by
-- tools/build-hidden-recipes.py. See the Credits section of README.md.
lib.hiddenRecipes        = lib.hiddenRecipes        or {}

-- How a recipe is acquired (MINOR 9). [craftSpellID] = SkillLineAbility.AcquireMethod,
-- stored ONLY when non-zero -- 0 is the default and the large majority.
--
--   1 = granted automatically when the character learns the profession.
--
-- This is the answer to a question that otherwise looks like missing data. Trainer,
-- vendor, drop and quest sources all come from community server databases, and a
-- residue is left that none of them mention -- 87 of 1,261 Vanilla recipes. 26 of
-- those are AcquireMethod 1: Minor Healing Potion, Rough Sharpening Stone, Linen
-- Bandage, Smelt Copper. Nothing teaches them because knowing the profession IS how
-- you get them, so a browser should say "Learned with profession", not "Unknown".
lib.acquireMethods       = lib.acquireMethods       or {}

-- Where a recipe comes from (MINOR 10). Moved here from TOGProfessionMaster's
-- private `addon.sourceDB`, which was a single all-expansion merged set; this is
-- per-version like every other table here, so a Vanilla client is not carrying
-- Cata's drop tables.
--
--   sources:     [craftSpellID] = { t = {npcID,...}, v = ..., d = ..., q = ..., c = ... }
--   sourceNames: [npcID] = "Alchemist Mallory"
--
-- THE ONE-LETTER KEYS ARE NOT AN ABBREVIATION HABIT, they are the reason this
-- ships at all. There are 364,592 source rows; at the previous format's 19.3
-- bytes per row a per-version split came to ~21 MB. Compact keys and bare id
-- arrays bring all five versions to about what the single merged copy cost.
-- Consumers never see them — GetRecipeSources spells the kinds out in full.
--
--   t trainer · v vendor · d drop · q quest · c container (opened, e.g. clams)
--
-- WHY IDS AND NAMES RATHER THAN JUST THE KINDS. Every consumer at the time of
-- writing only rendered a label ("Trainer", "Vendor"), so shipping a five-bit
-- mask would have been enough and ~100 KB. That is the wrong optimisation: the
-- point of source data is to answer "where do I get this", and "Trainer" does
-- not. There is no client API that maps an npc id to a name offline, so the
-- names have to ship or the ids are undisplayable.
--
-- NAMES ARE ENGLISH ONLY, and that is a real limitation rather than an
-- oversight. They come from the emulator world databases' creature_template,
-- which is not localized. Recipe names here ship in 12 locales; source npc
-- names ship in one. A consumer showing them to a non-English client is showing
-- an English string — decide that deliberately.
lib.sources              = lib.sources              or {}
lib.sourceNames          = lib.sourceNames          or {}

-- One-letter storage key -> the name a consumer sees. Order is the display
-- order: how you would most usefully be told where to get something.
local SOURCE_KINDS = {
    { key = "t", name = "trainer"   },
    { key = "v", name = "vendor"    },
    { key = "q", name = "quest"     },
    { key = "c", name = "container" },
    { key = "d", name = "drop"      },
}

-- ---------------------------------------------------------------------------
-- Game-version detection.
--
-- Recipe data is point-in-time per flavour, so we ship a Data tree per game
-- (Vanilla / TBC / Wrath / Cata / Mists). Every shipped data file guards on
-- BOTH GetLocale() and lib:IsGameVersion(...) before calling LoadRecipes, so a
-- running client only ever registers the recipes for ITS flavour + language —
-- never the whole multi-version, multi-locale set, even if a file is loaded on
-- the wrong client. The flavour is derived from the interface build number
-- (same ranges TOGProfessionMaster's Compat.lua uses). No Retail flavour ships.
-- ---------------------------------------------------------------------------
local function detectGameVersion()
    local _, _, _, iface = GetBuildInfo()
    iface = tonumber(iface) or 0
    if     iface < 20000 then return "Vanilla"
    elseif iface < 30000 then return "TBC"
    elseif iface < 40000 then return "Wrath"
    elseif iface < 50000 then return "Cata"
    else                      return "Mists"
    end
end

-- The flavour string for the running client ("Vanilla"/"TBC"/"Wrath"/"Cata"/"Mists").
function lib:GetGameVersion()
    if not self.gameVersion then self.gameVersion = detectGameVersion() end
    return self.gameVersion
end

-- True if `name` matches the running client's flavour. Used by the data files
-- as a load guard so only the right game's recipes register.
function lib:IsGameVersion(name)
    return name == self:GetGameVersion()
end

-- ---------------------------------------------------------------------------
-- Data loading — called by the shipped Data files.
--
-- To avoid shipping every locale-independent field once per language, the data
-- is split into two halves that merge into one stitched view:
--   * Core (locale-independent) — loaded ONCE per game via LoadCore: the
--     structural fields { difficulty, reagents, requiredSkill, teaches,
--     craftedItemId, itemId, phase, enchantId, enchantSlot, stats }. Core files
--     guard on IsGameVersion only.
--   * Names (localized) — loaded for the ACTIVE locale only via LoadNames:
--     { name, effect }. Name files guard on GetLocale() + IsGameVersion.
-- Both merge into self.recipes[profId][recipeId], so every query below
-- (GetRecipe, Search, Iterate, …) reads one stitched entry of the shape:
--   { name, effect?, difficulty, reagents, requiredSkill?, teaches,
--     craftedItemId?, itemId?, phase?, enchantId?, enchantSlot?, stats? }
-- The last three are enchant enrichment, present only on recipes whose craft
-- applies a permanent enchant (Enchanting recipes + Engineering scopes/tinkers).
-- Each TOC lists core files before name files, so the recipe SET (and the
-- count) is established by LoadCore; LoadNames only fills in the strings.
-- ---------------------------------------------------------------------------
local function slotFor(self, profId)
    local slot = self.recipes[profId]
    if not slot then slot = {}; self.recipes[profId] = slot end
    return slot
end

-- Locale-independent fields for a profession. { [recipeId] = { difficulty,
-- reagents, requiredSkill?, teaches, craftedItemId?, itemId?, phase? } }.
function lib:LoadCore(profId, core)
    if type(profId) ~= "number" or type(core) ~= "table" then return end
    self.meta.game = self.meta.game or self:GetGameVersion()
    local slot = slotFor(self, profId)
    for recipeId, c in pairs(core) do
        local e = slot[recipeId]
        if not e then
            e = {}; slot[recipeId] = e
            self.count = self.count + 1
            self.profCounts[profId] = (self.profCounts[profId] or 0) + 1
        end
        e.difficulty    = c.difficulty
        e.reagents      = c.reagents
        e.teaches       = c.teaches
        e.requiredSkill = c.requiredSkill
        e.requiredSpec  = c.requiredSpec
        e.craftedItemId = c.craftedItemId
        e.itemId        = c.itemId
        e.phase         = c.phase
        -- Enchant enrichment (Enchanting recipes only; nil elsewhere):
        --   enchantId   = SpellItemEnchantment id (the enchant number in an item
        --                 link) — maps an applied/worn enchant back to its recipe.
        --   enchantSlot = target slot category ("HANDS"/"WRIST"/"WEAPON2H"/…).
        --   stats       = { [GetItemStats key] = amount }, e.g. ITEM_MOD_AGILITY_SHORT.
        e.enchantId     = c.enchantId
        e.enchantSlot   = c.enchantSlot
        e.stats         = c.stats
    end
    self._enchById = nil   -- invalidate the lazy enchant catalog index
end

-- Localized strings for the active locale. { [recipeId] = { name, effect? } }.
function lib:LoadNames(profId, names)
    if type(profId) ~= "number" or type(names) ~= "table" then return end
    self.meta.locale = self.meta.locale or (GetLocale and GetLocale())
    self.meta.game   = self.meta.game   or self:GetGameVersion()
    local slot = slotFor(self, profId)
    for recipeId, n in pairs(names) do
        local e = slot[recipeId]
        -- _core establishes the recipe SET (every TOC lists the _core file
        -- before the locale name files, so core has always loaded by now). A
        -- name with NO matching core entry is a stale leftover — e.g. a spell
        -- dropped from _core by an exclusion but still present in a name file
        -- that wasn't regenerated. Skip it instead of resurrecting a
        -- difficulty-less, reagent-less phantom recipe into the set.
        if e then
            e.name   = n.name
            e.effect = n.effect
        end
    end
    self._enchById = nil   -- invalidate the lazy enchant catalog index
end

-- ---------------------------------------------------------------------------
-- Applied-enchant catalog loaders — called by the shipped Enchanting data files
-- (the catalog rides those files, so it loads on every client without its own
-- TOC entry). Same core + names split as recipes: LoadEnchantsCore carries the
-- locale-independent { slots, stats, itemId }; LoadEnchantsNames the localized
-- { name }. Keyed by SpellItemEnchantment id.
-- ---------------------------------------------------------------------------
-- { [enchantId] = { slots = {"HEAD",…}, stats = { [key]=amt }?, itemId? } }.
function lib:LoadEnchantsCore(core)
    if type(core) ~= "table" then return end
    for enchantId, c in pairs(core) do
        local e = self.enchants[enchantId]
        if not e then e = {}; self.enchants[enchantId] = e end
        e.slots  = c.slots
        e.stats  = c.stats
        e.itemId = c.itemId
    end
    self._enchById = nil
end

-- { [enchantId] = { name = "…" } } for the active locale. Core establishes the
-- catalog SET (its file loads first), so a name with no core entry is skipped.
function lib:LoadEnchantsNames(names)
    if type(names) ~= "table" then return end
    for enchantId, n in pairs(names) do
        local e = self.enchants[enchantId]
        if e then e.name = n.name end
    end
    self._enchById = nil
end

-- Back-compat: split a self-contained { [recipeId] = full entry } table into a
-- core + names load. The shipped data files call LoadCore/LoadNames directly;
-- this keeps any caller still using the old single-call API working.
function lib:LoadRecipes(profId, recipes)
    if type(profId) ~= "number" or type(recipes) ~= "table" then return end
    local core, names = {}, {}
    for recipeId, e in pairs(recipes) do
        core[recipeId] = {
            difficulty    = e.difficulty,
            reagents      = e.reagents,
            teaches       = e.teaches,
            requiredSkill = e.requiredSkill,
            requiredSpec  = e.requiredSpec,
            craftedItemId = e.craftedItemId,
            itemId        = e.itemId,
            phase         = e.phase,
            enchantId     = e.enchantId,
            enchantSlot   = e.enchantSlot,
            stats         = e.stats,
        }
        names[recipeId] = { name = e.name, effect = e.effect }
    end
    self:LoadCore(profId, core)
    self:LoadNames(profId, names)
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Recipe scrolls -- loaders
-- ---------------------------------------------------------------------------

-- { [craftSpellIDStr] = teachingItemID }
function lib:LoadRecipeItems(t)
    if type(t) ~= "table" then return end
    for spellStr, itemID in pairs(t) do
        local spellID = tonumber(spellStr)
        if spellID and tonumber(itemID) then self.recipeItems[spellID] = tonumber(itemID) end
    end
end

-- The rank-book subset of the above: { [craftSpellIDStr] = true }.
function lib:LoadSkillRankBooks(t)
    if type(t) ~= "table" then return end
    for spellStr in pairs(t) do
        local spellID = tonumber(spellStr)
        if spellID then self.skillRankBooks[spellID] = true end
    end
end

-- Recipes with no real scroll: { [craftSpellIDStr] = { skillLineID, craftedItemID } }.
function lib:LoadSyntheticRecipes(t)
    if type(t) ~= "table" then return end
    for spellStr, rec in pairs(t) do
        local spellID = tonumber(spellStr)
        if spellID and type(rec) == "table" then self.syntheticRecipes[spellID] = rec end
    end
end

-- Localized scroll prefixes: { [skillLineIDStr] = "Plans: " }. Only the active
-- locale's file loads (each self-guards on GetLocale()).
function lib:LoadRecipeScrollPrefixes(t)
    if type(t) ~= "table" then return end
    for lineStr, prefix in pairs(t) do
        local line = tonumber(lineStr)
        if line and type(prefix) == "string" then self.recipeScrollPrefixes[line] = prefix end
    end
end

-- How many real scrolls each prefix above was derived from: { [skillLineIDStr] = n }.
-- Ships beside the prefixes, in the same per-locale file, because the sample size is a
-- property of that locale's derivation and not of the profession.
function lib:LoadRecipeScrollPrefixSamples(t)
    if type(t) ~= "table" then return end
    for lineStr, n in pairs(t) do
        local line, count = tonumber(lineStr), tonumber(n)
        if line and count then self.recipeScrollPrefixSamples[line] = count end
    end
end

-- Acquisition methods: { [craftSpellIDStr] = acquireMethod }, non-zero only.
function lib:LoadAcquireMethods(t)
    if type(t) ~= "table" then return end
    for spellStr, method in pairs(t) do
        local spellID, m = tonumber(spellStr), tonumber(method)
        if spellID and m then self.acquireMethods[spellID] = m end
    end
end

-- Never-implemented recipes: { [craftSpellIDStr] = true }.
function lib:LoadHiddenRecipes(t)
    if type(t) ~= "table" then return end
    for spellStr, v in pairs(t) do
        local spellID = tonumber(spellStr)
        if spellID and v then self.hiddenRecipes[spellID] = true end
    end
end

-- Recipe sources: { [craftSpellIDStr] = { t = {npcID,...}, v = {...}, ... } }.
-- Merges rather than replaces, so a later file can add kinds for a spell an
-- earlier one already covered.
function lib:LoadSources(t)
    if type(t) ~= "table" then return end
    for spellStr, kinds in pairs(t) do
        local spellID = tonumber(spellStr)
        if spellID and type(kinds) == "table" then
            local slot = self.sources[spellID]
            if not slot then
                slot = {}
                self.sources[spellID] = slot
            end
            for key, ids in pairs(kinds) do
                if type(ids) == "number" then
                    -- A `<key>n` true-count. Sum rather than overwrite so a
                    -- merge of two files reports the combined total, matching
                    -- what the concatenated id lists below represent.
                    slot[key] = (slot[key] or 0) + ids
                elseif type(ids) == "table" and #ids > 0 then
                    local into = slot[key]
                    if not into then
                        slot[key] = ids
                    else
                        for i = 1, #ids do into[#into + 1] = ids[i] end
                    end
                end
            end
        end
    end
end

-- Source npc/object names: { [npcIDStr] = "Alchemist Mallory" }. English only —
-- see the note on lib.sourceNames.
function lib:LoadSourceNames(t)
    if type(t) ~= "table" then return end
    for idStr, name in pairs(t) do
        local id = tonumber(idStr)
        if id and type(name) == "string" and name ~= "" then self.sourceNames[id] = name end
    end
end

-- Localized "Use:" sentences: { [skillLineIDStr] = "Teaches you how to sew %s." }.
function lib:LoadRecipeScrollUseText(t)
    if type(t) ~= "table" then return end
    for lineStr, text in pairs(t) do
        local line = tonumber(lineStr)
        if line and type(text) == "string" then self.recipeScrollUseText[line] = text end
    end
end

-- ---------------------------------------------------------------------------
-- Recipe scrolls -- queries
-- ---------------------------------------------------------------------------

--- The item that teaches a recipe, or nil when there is none.
--- nil is a real and common answer -- roughly a third of recipes are trainer-taught
--- and no such item exists -- so a caller MUST have a fallback rather than treating
--- nil as missing data. Second return says whether it is a skill-RANK book.
--- @return number|nil itemID, boolean isRankBook
function lib:GetRecipeItem(spellID)
    local itemID = self.recipeItems[spellID]
    if not itemID then return nil, false end
    return itemID, self.skillRankBooks[spellID] == true
end

--- Every recipe spell that has a teaching item. The live table -- read-only.
function lib:GetRecipeItems() return self.recipeItems end

--- Was this recipe never actually obtainable in the live game? (MINOR 9)
---
--- true means AllTheThings files it under "Never Implemented": the spell shipped
--- in the client's tables but nothing in the world ever taught it. Distinct from
--- "removed from the game", which was once obtainable, and from a recipe belonging
--- to a later expansion, which the per-version data already excludes.
---
--- Intended for lists of recipes a player could still acquire -- a "what am I
--- missing" view should drop these, because the answer is "nothing you can do".
--- Feature-detect it (`if lib.IsHiddenRecipe and lib:IsHiddenRecipe(id)`) so the
--- call stays inert against a ProfessionDB older than MINOR 9.
--- @return boolean
function lib:IsHiddenRecipe(spellID)
    return self.hiddenRecipes[spellID] == true
end

--- Every never-implemented recipe spell for this client. The live table -- read-only.
function lib:GetHiddenRecipes() return self.hiddenRecipes end

--- Where a recipe can be obtained (MINOR 10), or nil when nothing is known.
---
--- nil is a real answer covering roughly a quarter of recipes, and a caller must
--- render it as "unknown" rather than as an empty Sources heading — a blank
--- heading reads as a bug in the addon rather than a gap in the data. Before
--- calling it unknown, check `IsAutoTaughtRecipe`: those have no source anywhere
--- because knowing the profession IS how you get them, so the honest label is
--- "Learned with profession".
---
--- Returns a fresh table, safe to keep and mutate:
---
---     { trainer = { { id = 1355, name = "Alchemist Mallory" }, ... },
---       vendor  = { ... }, quest = {}, container = {}, drop = {} }
---
--- Only kinds that have at least one entry are present, so `next(t)` is never
--- nil on a non-nil return and `for kind, npcs in pairs(t)` needs no emptiness
--- guard. `name` is nil for an id the name map does not cover; show the kind
--- alone in that case rather than an id. Names are ENGLISH ONLY — see the note
--- on lib.sourceNames.
---
--- **EACH LIST CARRIES `.total`, AND IT IS NOT ALWAYS `#list`.** Lists are
--- capped at 12 ids in the shipped data, because 1,649 recipes drop from 50+
--- creatures apiece and the uncapped set costs 8 MB to say "drops from
--- everything". `.total` is the real number. A caller that renders a count MUST
--- use `.total` — printing `#list` would tell a player Rough Grinding Stone
--- drops from 12 creatures when it drops from 912. Iterate the list to name
--- examples, then say "and N more" from `.total - #list`.
---
--- Feature-detect it (`if lib.GetRecipeSources then`) so a consumer stays inert
--- against a ProfessionDB older than MINOR 10.
--- @return table|nil
function lib:GetRecipeSources(spellID)
    local raw = self.sources[spellID]
    if not raw then return nil end
    local out, any = {}, false
    for i = 1, #SOURCE_KINDS do
        local kind = SOURCE_KINDS[i]
        local ids  = raw[kind.key]
        if ids and #ids > 0 then
            local list = {}
            for j = 1, #ids do
                list[j] = { id = ids[j], name = self.sourceNames[ids[j]] }
            end
            -- `<key>n` is present only when the shipped list was truncated.
            list.total = raw[kind.key .. "n"] or #ids
            out[kind.name], any = list, true
        end
    end
    if not any then return nil end
    return out
end

--- Just which KINDS of source a recipe has — `{ trainer = true, vendor = true }`
--- — or nil. The cheap form for a caller that only renders labels: it allocates
--- one small table instead of walking every npc id, which matters in a list that
--- draws hundreds of rows per frame.
--- @return table|nil
function lib:GetRecipeSourceKinds(spellID)
    local raw = self.sources[spellID]
    if not raw then return nil end
    local out, any = {}, false
    for i = 1, #SOURCE_KINDS do
        local kind = SOURCE_KINDS[i]
        local ids  = raw[kind.key]
        if ids and #ids > 0 then out[kind.name], any = true, true end
    end
    if not any then return nil end
    return out
end

--- The English name of a source npc / game object, or nil.
--- @return string|nil
function lib:GetSourceName(npcID) return self.sourceNames[npcID] end

--- SkillLineAbility.AcquireMethod for a recipe (MINOR 9). Defaults to 0.
--- 1 means the recipe is granted automatically on learning the profession.
--- @return number
function lib:GetAcquireMethod(spellID)
    return self.acquireMethods[spellID] or 0
end

--- Is this recipe granted automatically when the profession is learned? (MINOR 9)
---
--- These have no trainer, vendor, drop or quest entry anywhere, and that is not a
--- data gap -- there is nothing in the world to find. A "where does this come from"
--- display should read "Learned with profession" rather than "Unknown".
--- @return boolean
function lib:IsAutoTaughtRecipe(spellID)
    return self.acquireMethods[spellID] == 1
end

--- The localized scroll prefix for a profession ("Plans: "), or nil, PLUS the
--- number of real scrolls it was derived from.
---
---   local prefix, samples = DB:GetRecipeScrollPrefix(186)   --> "Manual: ", 1
---
--- nil for the gathering lines, which have no craft scrolls to derive one from.
---
--- WHY THE SECOND RETURN EXISTS. The prefix is a majority vote over real scroll
--- names, and Mining's whole vote is ONE scroll -- so "Manual: Smelt Truesilver"
--- is rendered for 22 synthetic descriptors on the strength of a single sample.
--- That is not wrong (the synthetic path never claims the item is real) and
--- suppressing it below a threshold would cost those 22 a usable header. The
--- actual defect was that a consumer could not TELL, and so had no basis on
--- which to prefer its own heading. A threshold decides that for everyone, once,
--- invisibly; a count lets each consumer decide and can be ignored for free.
--- Raised by ItemDB 2026-08-06 (docs/DEPENDENCY_CONTRACTS.md section 2).
---
--- The count is NIL when the prefix is nil, never 0: "no prefix" and "a prefix
--- derived from no samples" must stay distinguishable, and the second is not a
--- state that can exist -- a prefix only comes into being by winning a vote.
--- It is also nil for data generated before this shipped, which is a real state
--- and reads correctly as "unknown", not as "zero samples".
function lib:GetRecipeScrollPrefix(skillLineID)
    local prefix = self.recipeScrollPrefixes[skillLineID]
    if prefix == nil then return nil end
    return prefix, self.recipeScrollPrefixSamples[skillLineID]
end

--- A scroll-shaped descriptor for a recipe with NO real teaching item, or nil.
---
--- The exact complement of GetRecipeItem: every recipe answers one or the other,
--- never both, so a consumer can draw one tooltip shape throughout instead of a
--- seam where the real scrolls run out. nil for a rank book, which is not a recipe.
---
--- **No itemID field, ever** -- see the syntheticRecipes note above.
---
--- `requiredSkill` is deliberately ABSENT. LibItemDB shipped it and it was wrong
--- for ~313 of 572 records (SkillLineAbility.MinSkillLineRank is a floor of 1 on
--- eight of twelve skill lines, not the skill needed), which rendered "Requires
--- Mining (1)" on a recipe needing 230. This library already carries the correct
--- per-recipe value on the recipe itself -- GetRecipe(profId, spellID).requiredSkill
--- -- so duplicating it here could only ever let the two disagree.
function lib:GetSyntheticRecipeScroll(spellID)
    local rec = self.syntheticRecipes[spellID]
    if not rec then return nil end

    local skillLineID, craftedItemID = rec[1], rec[2]
    local prefix = self.recipeScrollPrefixes[skillLineID]
    -- Read off _G at CALL time, deliberately: a load-time capture of an absent
    -- global bakes nil in permanently, and the name is only needed on demand.
    local getSpellInfo = _G.GetSpellInfo
    local spellName = getSpellInfo and getSpellInfo(spellID)

    local useTemplate = self.recipeScrollUseText[skillLineID]
    local useText
    if useTemplate and spellName then useText = useTemplate:format(spellName) end

    return {
        name          = (prefix and spellName) and (prefix .. spellName) or nil,
        prefix        = prefix,
        useText       = useText,
        professionID  = skillLineID,
        -- 0 in the data means "produces no item" (every enchant). Report nil, not
        -- 0, so a caller cannot pass a falsy-but-numeric id to an item API.
        craftedItemID = (craftedItemID ~= 0) and craftedItemID or nil,
        isSynthetic   = true,
    }
end

function lib:IsReady() return self.count > 0 end
function lib:Count()   return self.count end

-- locale, game the loaded data was captured for (nil until the first LoadRecipes).
function lib:GetMeta() return self.meta.locale, self.meta.game end

-- ---------------------------------------------------------------------------
-- Profession / recipe lookups
-- ---------------------------------------------------------------------------
-- { profId, ... } of professions that have data loaded, ascending.
function lib:GetProfessions()
    local out = {}
    for profId in pairs(self.recipes) do out[#out + 1] = profId end
    table.sort(out)
    return out
end

function lib:HasProfession(profId) return self.recipes[profId] ~= nil end
function lib:ProfessionCount(profId) return self.profCounts[profId] or 0 end

-- The raw { [recipeId] = entry } table for a profession (nil if not loaded).
-- Treat as read-only.
function lib:GetRecipes(profId) return self.recipes[profId] end

-- A single recipe entry (nil if unknown).
function lib:GetRecipe(profId, recipeId)
    local slot = self.recipes[profId]
    return slot and slot[recipeId] or nil
end

function lib:HasRecipe(profId, recipeId)
    local slot = self.recipes[profId]
    return slot ~= nil and slot[recipeId] ~= nil
end

-- Convenience field accessors (all nil-safe).
function lib:GetName(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.name
end
function lib:GetReagents(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.reagents
end
function lib:GetEffect(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.effect
end
-- difficulty = { orange, yellow, green, grey } skill thresholds.
function lib:GetDifficulty(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.difficulty
end
function lib:GetRequiredSkill(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.requiredSkill
end
-- itemId = recipe-scroll item that teaches this recipe (nil for trainer-only).
function lib:GetItemID(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.itemId
end
-- craftedItemId = item the recipe produces (nil for enchants / when == itemId).
function lib:GetCraftedItemID(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.craftedItemId
end
-- enchantId = the SpellItemEnchantment id (the enchant number carried in an item
-- link's enchant slot). Only Enchanting recipes have one; nil otherwise. Lets a
-- consumer map an enchant already applied to a worn item back to its recipe.
function lib:GetEnchantId(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.enchantId
end
-- enchantSlot = target slot category for an enchant ("HANDS", "WRIST", "CHEST",
-- "BACK", "SHIELD", "WEAPON1H", "WEAPON2H", "HEAD", "LEGS", "FEET", …), derived
-- authoritatively from the recipe spell's equipped-item restriction. nil for
-- non-enchant recipes and utility enchants with no slot (Mining, Fishing, …).
function lib:GetEnchantSlot(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.enchantSlot
end
-- stats = { [key] = amount } structured stat deltas for an enchant, keyed by the
-- game's own GetItemStats keys (ITEM_MOD_AGILITY_SHORT, RESISTANCE0_NAME = armor,
-- …) so they sum straight into item-stat totals. nil when the enchant carries no
-- static stat (procs / on-use effects like Crusader).
function lib:GetStats(profId, recipeId)
    local r = self:GetRecipe(profId, recipeId); return r and r.stats
end

-- ---------------------------------------------------------------------------
-- Enchant catalog — a unified, slot-indexed view over EVERY enchant, whether an
-- enchanter crafts it (from `recipes`, via the enchantId/enchantSlot/stats a
-- recipe carries) or an item applies it (from `enchants`: arcanums / ZG / kits).
-- Built lazily and cached; invalidated whenever recipe or enchant data loads.
--
-- A catalog entry is normalized to:
--   { id, name, effect, slots = { "HEAD", … }, stats?, itemId?,
--     source = "craft"|"item", profId?, recipeId? }
-- `slots` is ALWAYS an array (item enchants can target several slots, e.g. an
-- arcanum on HEAD+LEGS or an armor kit on four slots); a craftable enchant has a
-- single-element array. `effect` is the human-readable stat text either way.
-- ---------------------------------------------------------------------------
local function addToSlots(bySlot, slots, entry)
    if not slots then return end
    for i = 1, #slots do
        local s = slots[i]
        local b = bySlot[s]
        if not b then b = {}; bySlot[s] = b end
        b[#b + 1] = entry
    end
end

local function buildEnchantIndex(self)
    local byId, bySlot = {}, {}
    -- Craftable enchants (recipes carrying an enchantId). Single-slot.
    for profId, slot in pairs(self.recipes) do
        for recipeId, r in pairs(slot) do
            if r.enchantId then
                local e = {
                    id = r.enchantId, name = r.name, effect = r.effect,
                    slots = r.enchantSlot and { r.enchantSlot } or nil,
                    stats = r.stats, source = "craft",
                    profId = profId, recipeId = recipeId,
                }
                byId[r.enchantId] = e
                addToSlots(bySlot, e.slots, e)
            end
        end
    end
    -- Item-applied enchants. Multi-slot; the SIE name is also the effect text.
    for enchantId, a in pairs(self.enchants) do
        local e = {
            id = enchantId, name = a.name, effect = a.name,
            slots = a.slots, stats = a.stats, itemId = a.itemId, source = "item",
        }
        byId[enchantId] = e
        addToSlots(bySlot, a.slots, e)
    end
    self._enchById, self._enchBySlot = byId, bySlot
end

local function ensureEnchantIndex(self)
    if not self._enchById then buildEnchantIndex(self) end
end

-- Catalog entry for a SpellItemEnchantment id (nil if unknown). Covers craftable
-- and item-applied enchants alike.
function lib:GetEnchant(enchantId)
    ensureEnchantIndex(self)
    return self._enchById[enchantId]
end

-- Array of catalog entries applicable to a slot ("HEAD", "SHOULDER", "WRIST",
-- "HANDS", "CHEST", "LEGS", "FEET", "BACK", "WAIST", "SHIELD", "WEAPON1H",
-- "WEAPON2H"). Empty table when none. Unions craftable + item-applied enchants.
function lib:EnchantsForSlot(slot)
    ensureEnchantIndex(self)
    return self._enchBySlot[slot] or {}
end

-- Iterate every catalog entry: for enchantId, entry in DB:IterateEnchants() do
function lib:IterateEnchants()
    ensureEnchantIndex(self)
    local id
    return function()
        local e
        id, e = next(self._enchById, id)
        if id == nil then return nil end
        return id, e
    end
end

-- ---------------------------------------------------------------------------
-- Search. opts:
--   query   substring match on recipe name AND enriched effect text
--           (case-insensitive). "" matches everything.
--   profId  restrict to one profession (number) or nil for all
--   max     result cap (default 300)
-- Returns an array of { profId, recipeId, name, effect, difficulty,
-- requiredSkill, reagents, itemId, craftedItemId }, sorted by name, with a
-- `.capped` flag when the cap was hit.
-- ---------------------------------------------------------------------------
function lib:Search(opts)
    opts = opts or {}
    local query  = (opts.query or ""):lower()
    local onlyP  = opts.profId
    local max    = opts.max or 300

    local results, capped = {}, false
    for profId, slot in pairs(self.recipes) do
        if onlyP == nil or profId == onlyP then
            for recipeId, r in pairs(slot) do
                local name   = r.name or ""
                local effect = r.effect
                if query == ""
                   or name:lower():find(query, 1, true)
                   or (effect and effect:lower():find(query, 1, true)) then
                    results[#results + 1] = {
                        profId        = profId,
                        recipeId      = recipeId,
                        name          = r.name,
                        effect        = r.effect,
                        difficulty    = r.difficulty,
                        requiredSkill = r.requiredSkill,
                        reagents      = r.reagents,
                        itemId        = r.itemId,
                        craftedItemId = r.craftedItemId,
                        enchantId     = r.enchantId,
                        enchantSlot   = r.enchantSlot,
                        stats         = r.stats,
                    }
                    if #results >= max then capped = true; break end
                end
            end
        end
        if capped then break end
    end
    table.sort(results, function(a, b) return (a.name or "") < (b.name or "") end)
    results.capped = capped
    return results
end

-- ---------------------------------------------------------------------------
-- Iterator over recipes. Pass a profId to iterate one profession, or nil for
-- every loaded recipe:
--   for profId, recipeId, entry in DB:Iterate() do ... end
--   for profId, recipeId, entry in DB:Iterate(333) do ... end
-- ---------------------------------------------------------------------------
function lib:Iterate(profId)
    if profId ~= nil then
        local slot = self.recipes[profId] or {}
        local rid
        return function()
            local entry
            rid, entry = next(slot, rid)
            if rid == nil then return nil end
            return profId, rid, entry
        end
    end
    local pid, slot = next(self.recipes)
    local rid
    return function()
        -- Guard on `slot`, the thing about to be indexed, rather than on `pid`.
        -- They are always both nil or both set (one `next` produces the pair), so
        -- this is the same loop -- but guarding the sibling left the language
        -- server unable to narrow `slot` and reporting `next(slot, rid)` as a
        -- possible nil index forever. Guarding the variable you are actually
        -- about to use is both honest and checkable.
        while slot ~= nil do
            local entry
            rid, entry = next(slot, rid)
            if rid ~= nil then return pid, rid, entry end
            pid, slot = next(self.recipes, pid)
            rid = nil
        end
        return nil
    end
end
