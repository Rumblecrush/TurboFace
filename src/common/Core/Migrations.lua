local _, ns = ...

-- =============================================================================
-- VARIABLE LOADING
-- =============================================================================

local DeepCopy = ns.DeepCopy
local MergeDefaults = ns.MergeDefaults

-- =============================================================================
-- SAVED-VARIABLE VERSIONING
-- Bump DB_VERSION and append a migration step whenever the shape of
-- TurboFaceDB changes. Steps run in order exactly once per profile.
-- Caches live in TurboFaceCacheDB (separate SavedVariable) so wiping caches
-- can never destroy user configuration; caches are auto-wiped whenever the
-- client build changes (NPC titles etc. may change between builds).
-- =============================================================================

-- dbVersion is the portable cross-client settings schema. Client-only changes
-- advance Core/Schema.lua's internal revision axis instead of forking this
-- migration chain.
local DB_VERSION = (ns.Schema and ns.Schema.PORTABLE_VERSION) or 79
ns.DB_VERSION = DB_VERSION

-- Final canonical cleanup for the pre-native nameplate renderer. Historical
-- migration steps stay intact so a profile can still upgrade from any older
-- schema; these lists define only what is forbidden in the current schema.
local RETIRED_NAMEPLATE_KEYS = {
    "width", "hpHeight", "castHeight", "scale", "targetScale",
    "friendlyScale", "healthBarBorder", "texture", "backgroundAlpha",
    "font", "fontSize", "healthValueFormat", "healthValueFontSize",
    "nameDisplayFormat", "nameTextYOffset", "nameInHealthbar",
    "hidePercentWhenFull", "friendlyNameOnly", "liteHealthWhenDamaged",
    "friendlyFontSize", "guildFontSize", "classColoredHealth",
    "classColoredName", "levelMode", "levelClassificationSuffix",
    "classificationStyle", "classificationAnchor", "classificationX",
    "classificationY", "classificationSize", "targetGlow", "targetArrow",
    "showCastbar", "showCastIcon", "showCastSpark", "showCastTimer",
    "nonTargetAlpha", "petScale", "threatTextAnchor",
    "threatTextFontSize", "threatTextOffsetX", "threatTextOffsetY",
    "executeRange", "totemDisplay", "raidMarkerAnchor", "raidMarkerSize",
    "raidMarkerX", "raidMarkerY", "stacking", "tankMode",
    "hpColor", "castColor", "noInterruptColor", "petColor",
    "targetGlowColor", "tappedColor", "hostileNameColor",
    "secureColor", "transColor", "insecureColor", "offTankColor",
    "dpsSecureColor", "dpsTransColor", "dpsAggroColor",
    "mouseoverGlowColor",
}

local RETIRED_BUBBLE_NAMEPLATE_KEYS = {
    "threatBubble", "threatScale", "threatXOffset", "threatYOffset",
    "threatPulseGrowth", "aggroSounds", "castReplacesPowerBar",
    "scale", "targetGrowthScale", "adjustRaidIcons", "enemyNPCNameShadow",
    "blizzardNameBehavior", "whiteNames", "healthTextFormat",
    "lockNameplatesOn", "questieCompatibility", "powerTextFormat",
    "barValueAmount", "barValuePercent",
}

local function PruneKeys(tbl, keys)
    if type(tbl) ~= "table" then return end
    for i = 1, #keys do tbl[keys[i]] = nil end
end

local function MoveLegacyXPSession(db)
    local xp = type(db) == "table" and db.experienceBar or nil
    local legacy = type(xp) == "table" and xp.session or nil
    if type(legacy) ~= "table" then return end
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.experienceBarSession) ~= "table"
        or next(TurboFaceCharDB.experienceBarSession) == nil
    then
        TurboFaceCharDB.experienceBarSession = DeepCopy(legacy)
    end
    xp.session = nil
end

local function RemoveRetiredBlizzardXPMover(db)
    local movers = type(db) == "table" and db.movers or nil
    local elements = type(movers) == "table" and movers.elements or nil
    if type(elements) ~= "table" then return end
    elements.XPBar = nil
    if movers.activeElement == "XPBar" then movers.activeElement = nil end
end

local function RemoveRetiredFlightBarSettings(db)
    local plus = type(db) == "table" and db.plus or nil
    if type(plus) ~= "table" then return end
    plus.showFlightTimes = nil
    plus.flightBarBackground = nil
    plus.flightBarDestination = nil
    plus.flightBarFillBar = nil
    plus.flightBarSpeech = nil
end

local RETIRED_INTERFACE_FONT_RESIZE_KEYS = {
    "resizeMailText", "mailFontSize",
    "resizeQuestText", "questFontSize",
    "resizeBookText", "bookFontSize",
}

local function RemoveRetiredInterfaceFontResizeSettings(db)
    local plus = type(db) == "table" and db.plus or nil
    PruneKeys(plus, RETIRED_INTERFACE_FONT_RESIZE_KEYS)
end

local Migrations = {
    -- v1 -> v2 (2026-07): deleted features (arena targeting/numbers, personal
    -- resource bar, hero power bars); NPC title cache moved to TurboFaceCacheDB.
    [1] = function(db)
        db.targetingMeIndicator = nil
        db.targetingMeColor = nil
        db.arenaNumbers = nil
        db.personal = nil
        db.cpOnPersonalBar = nil
        db.cpPersonalX = nil
        db.cpPersonalY = nil
        -- Move the NPC title cache out of the config DB
        if type(db.npcTitleCache) == "table" and TurboFaceCacheDB then
            TurboFaceCacheDB.npcTitles = TurboFaceCacheDB.npcTitles or {}
            for id, title in pairs(db.npcTitleCache) do
                TurboFaceCacheDB.npcTitles[id] = title
            end
        end
        db.npcTitleCache = nil
    end,

    -- v2 -> v3: target PVP icon anchor mirrored from left of the bar stack to
    -- the right edge of the frame; flip the old default X offset (-2 -> 2).
    -- Custom values are left alone.
    [2] = function(db)
        local uf = db.unitframes
        if type(uf) == "table" and uf.targetPVPIconX == -2 then
            uf.targetPVPIconX = 2
        end
    end,

    -- v3 -> v4: split the shared unit-frame health/power formats into
    -- independent Player, Target, Pet, and Party settings. Preserve each
    -- profile's existing appearance on first load.
    [3] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local health = uf.healthFormat or "current-max-pct"
        local power = uf.manaFormat or "percent"
        if uf.playerHealthFormat == nil then uf.playerHealthFormat = health end
        if uf.targetHealthFormat == nil then uf.targetHealthFormat = health end
        if uf.petHealthFormat == nil then uf.petHealthFormat = health end
        if uf.partyHealthFormat == nil then uf.partyHealthFormat = health end
        if uf.playerPowerFormat == nil then uf.playerPowerFormat = power end
        if uf.targetPowerFormat == nil then uf.targetPowerFormat = power end
        if uf.petPowerFormat == nil then uf.petPowerFormat = power end
        if uf.partyPowerFormat == nil then uf.partyPowerFormat = power end
    end,

    -- v4 -> v5: remove the OptionsGUI shadow copies for unit-frame and
    -- nameplate-aura settings. Runtime modules already use the nested tables;
    -- keep those canonical values when both copies exist, use a legacy flat
    -- value only to fill a missing nested value, then delete every mirror.
    [4] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then
            uf = {}
            db.unitframes = uf
        end
        local ufKeys = {
            "healthTexture","manaTexture","attackTexture","castTexture","hideBlizzardPlayerCastbar","showQueuedSwingDamage","castbarSpellValues",
            "barFontSize","font","textStyle","healthFormat","manaFormat",
            "playerHealthFormat","playerPowerFormat","targetHealthFormat","targetPowerFormat",
            "petHealthFormat","petPowerFormat","partyHealthFormat","partyPowerFormat",
            "totHealthFormat","totPowerFormat",
            "playerBarWidth","targetBarWidth","healthBarHeight","manaBarHeight","attackBarHeight","castBarHeight",
            "showLevelText","levelClassificationSuffix","restIconAnchor","barSpacing","nameFontSize",
            "classColored","colorBasedOnCurrentHealth","playerHealthColor","friendlyColor","enemyColor",
            "playerScale","showPlayerName","showHitIndicator","showRestIcon","showStatusTexture","showAttackBackground","showGroupIndicator","showPVPIcon",
            "playerPVPIconSize","playerPVPIconX","playerPVPIconY",
            "nanShieldEnabled","nanShieldHeight","nanShieldShowText","nanShieldPerSection",
            "targetScale","showTargetName","showToT","totScale","totTextFontSize","totNameFontSize","reverseTargetHP","showTargetPVPIcon",
            "targetPVPIconSize","targetPVPIconX","targetPVPIconY","showTargetXP","targetXPPerHP","targetXPColor","showComboPoints",
            "partyScale","partyBarWidth","partyHealthBarHeight","partyManaBarHeight","partyNameColor","showPartyNames",
        }
        for i = 1, #ufKeys do
            local key = ufKeys[i]
            local legacyKey = "uf_" .. key
            if uf[key] == nil and db[legacyKey] ~= nil then
                uf[key] = db[legacyKey]
            end
            db[legacyKey] = nil
        end

        local auras = db.auras
        if type(auras) ~= "table" then
            auras = {}
            db.auras = auras
        end
        local auraKeys = {
            "showDebuffs", "showBuffs", "maxDebuffs", "maxBuffs",
            "debuffIconWidth", "buffIconWidth", "buffFilterMode",
            "debuffFontSize", "buffFontSize",
        }
        for i = 1, #auraKeys do
            local key = auraKeys[i]
            if auras[key] == nil and db[key] ~= nil then
                auras[key] = db[key]
            end
            db[key] = nil
        end
    end,

    -- v5 -> v6: the v3 migration has already copied the old shared formats to
    -- each independent bar. Remove those legacy fields so profiles/exports do
    -- not keep redundant values that can drift from the active settings.
    [5] = function(db)
        local uf = db.unitframes
        if type(uf) == "table" then
            uf.healthFormat = nil
            uf.manaFormat = nil
        end
    end,

    -- v6 -> v7: persistent party-buff display owned by TurboFace. Defaults are
    -- copied explicitly here so existing profiles gain the feature once while
    -- still allowing later user changes to persist normally.
    [6] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then
            uf = {}
            db.unitframes = uf
        end
        if uf.partyBuffsEnabled == nil then uf.partyBuffsEnabled = true end
        if uf.partyBuffIconSize == nil then uf.partyBuffIconSize = 18 end
        if uf.partyBuffMax == nil then uf.partyBuffMax = 8 end
        if uf.partyBuffsPerRow == nil then uf.partyBuffsPerRow = 4 end
    end,

    -- v7 -> v8: optional class-only party reminder mode. It is opt-in so
    -- existing users keep the persistent full-buff display until enabled.
    [7] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then
            uf = {}
            db.unitframes = uf
        end
        if uf.partyClassRemindersEnabled == nil then
            uf.partyClassRemindersEnabled = false
        end
    end,

    -- v8 -> v9: class-only mode now keeps tracked buffs visible while active,
    -- with a dedicated larger icon size for swipe/countdown readability.
    [8] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then
            uf = {}
            db.unitframes = uf
        end
        if uf.partyClassBuffIconSize == nil then
            uf.partyClassBuffIconSize = 36
        end
    end,

    -- v9 -> v10: class-only party buffs now share player-aura timer styling
    -- and pulse shortly before expiration. Keep the warning window independent
    -- from the self-buff reminder so each feature can be tuned separately.
    [9] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then
            uf = {}
            db.unitframes = uf
        end
        if uf.partyClassBuffWarnSeconds == nil then
            uf.partyClassBuffWarnSeconds = 30
        end
    end,

    -- v10 -> v11: 1.15.9 imported HUD Edit Mode, so TurboFace handed
    -- Blizzard-frame placement back to Blizzard. The ActionBars module was
    -- removed entirely (native bars go back to Blizzard's own frames; custom
    -- bonus-page bars 7-10 were retired), and the unit-frame / action-bar /
    -- durability mover elements were deleted. The ChatAnchor module
    -- (account-wide chat position restore) was removed in the same pass.
    -- Prune their saved data so old positions cannot resurrect through
    -- profiles or imports.
    [10] = function(db)
        db.actionbars = nil
        db.chatAnchorEnabled = nil
        db.chatAnchorX, db.chatAnchorY = nil, nil
        db.chatAnchorW, db.chatAnchorH = nil, nil
        local movers = db.movers
        if type(movers) ~= "table" then return end
        local elements = movers.elements
        if type(elements) == "table" then
            -- TargetFrameToT is intentionally NOT pruned: Edit Mode has no
            -- separate Target of Target placement, so its mover survives.
            local removed = {
                "PlayerFrame", "TargetFrame", "PetFrame",
                "PartyMemberFrame1", "PartyMemberFrame2",
                "PartyMemberFrame3", "PartyMemberFrame4",
                "ActionBar1", "ActionBar3", "ActionBar4", "ActionBar5",
                "ActionBar6", "ActionBar7", "ActionBar8", "ActionBar9",
                "ActionBar10", "PetBar", "StanceBar", "MicroMenu", "BagsBar",
                "DurabilityFrame", "PlayerBuffs", "PlayerDebuffs",
            }
            local removedSet = {}
            for _, id in ipairs(removed) do
                elements[id] = nil
                removedSet[id] = true
            end
            if removedSet[movers.activeElement] then
                movers.activeElement = nil
            end
        end
        if type(movers.aura) == "table" then
            movers.aura.playerPerRow = nil
            movers.aura.playerBuffGrowth = nil
            movers.aura.playerDebuffGrowth = nil
        end
        -- Blizzard's Buff/Debuff options own player aura icon size now.
        db.auraPlayerBuffScale = nil
        db.auraPlayerDebuffScale = nil
    end,

    -- v11 -> v12: Bubble nameplates become TurboFace's locked Classic
    -- nameplate identity. Preserve the few BubbleUI controls that remain,
    -- translate prior port values, and remove obsolete piece-by-piece toggles.
    [11] = function(db)
        local old = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or {}
        db.bubbleNameplates = {
            lockNameplatesOn = old.lockNameplatesOn == true,
            barValueAmount = old.barValueAmount ~= false,
            barValuePercent = old.barValuePercent ~= false,
            scale = tonumber(old.scale) or tonumber(db.scale) or 1.0,
            targetGrowthScale = tonumber(old.targetGrowthScale) or tonumber(db.targetScale) or 1.2,
            threatScale = tonumber(old.threatScale) or tonumber(old.nameplateBubbleScale) or 1.0,
            threatXOffset = tonumber(old.threatXOffset) or 21,
            threatYOffset = tonumber(old.threatYOffset) or 0,
            threatPulseGrowth = tonumber(old.threatPulseGrowth) or tonumber(old.threatPulseGrowthPercent) or 5,
            adjustRaidIcons = old.adjustRaidIcons ~= false,
            questieCompatibility = old.questieCompatibility == true,
            muteAggroSounds = old.muteAggroSounds == true or old.aggroSounds == false,
            gainVolume = tonumber(old.gainVolume) or 1.0,
            lossVolume = tonumber(old.lossVolume) or 1.0,
        }

        local obsolete = {
            "width", "hpHeight", "castHeight", "friendlyScale",
            "healthBarBorder", "texture", "backgroundAlpha", "font",
            "fontSize", "healthValueFormat", "healthValueFontSize",
            "nameDisplayFormat", "nameTextYOffset", "nameInHealthbar",
            "hidePercentWhenFull", "friendlyNameOnly", "liteHealthWhenDamaged",
            "friendlyFontSize", "guildFontSize", "classColoredHealth",
            "classColoredName", "levelMode", "levelClassificationSuffix",
            "classificationStyle", "classificationAnchor", "classificationX",
            "classificationY", "classificationSize", "showCastbar",
            "showCastIcon", "showCastSpark", "showCastTimer",
            "highlightGlowEnabled", "highlightGlowLines",
            "highlightGlowFrequency", "highlightGlowLength",
            "highlightGlowThickness", "highlightGlowColor",
            "highlightSpells", "nonTargetAlpha", "petScale",
        }
        for i = 1, #obsolete do db[obsolete[i]] = nil end
    end,

    -- v12 -> v13: Bubble's compact aura presentation is retired. Restore the
    -- original TurboFace nameplate aura renderer and its configurable defaults.
    -- v12 pinned these values after every load, so replacing them here cannot
    -- overwrite a user-customized v12 aura layout.
    [12] = function(db)
        local auras = db.auras
        if type(auras) ~= "table" then
            auras = {}
            db.auras = auras
        end
        auras.showDebuffs = true
        auras.maxDebuffs = 6
        auras.debuffIconWidth = 20
        auras.debuffIconHeight = 16
        auras.debuffFontSize = 12
        auras.debuffStackFontSize = 11
        auras.debuffXOffset = 0
        auras.debuffYOffset = 0
        auras.debuffBorderMode = "COLOR_CODED"
        auras.debuffDurationAnchor = "BOTTOM"
        auras.debuffStackAnchor = "TOPRIGHT"
        auras.debuffSortMode = "LEAST_TIME"
        auras.showBuffs = true
        auras.buffFilterMode = "ONLY_DISPELLABLE"
        auras.maxBuffs = 4
        auras.buffIconWidth = 18
        auras.buffIconHeight = 18
        auras.buffFontSize = 10
        auras.buffStackFontSize = 10
        auras.buffXOffset = 0
        auras.buffYOffset = 0
        auras.buffGrowDirection = "CENTER"
        auras.buffDurationAnchor = "CENTER"
        auras.buffStackAnchor = "TOPRIGHT"
        auras.buffIconSpacing = 2
        auras.buffMinDuration = 0
        auras.buffMaxDuration = 600
        auras.buffBorderMode = "COLOR_CODED"
        auras.buffSortMode = "MOST_RECENT"
        auras.minDuration = 0
        auras.maxDuration = 0
        auras.growDirection = "CENTER"
        auras.iconSpacing = 2
    end,

    -- v13 -> v14: replace the two Bubble value checkboxes with independent
    -- health/power format selectors, and add the optional shared resource/cast
    -- StatusBar mode.
    [13] = function(db)
        local bubble = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or {}
        db.bubbleNameplates = bubble

        local showAmount = bubble.barValueAmount ~= false
        local showPercent = bubble.barValuePercent ~= false
        local legacyFormat
        if showAmount and showPercent then
            legacyFormat = "current-pct"
        elseif showAmount then
            legacyFormat = "current"
        elseif showPercent then
            legacyFormat = "percent"
        else
            legacyFormat = "none"
        end

        if bubble.healthTextFormat == nil then bubble.healthTextFormat = legacyFormat end
        if bubble.powerTextFormat == nil then bubble.powerTextFormat = legacyFormat end
        if bubble.castReplacesPowerBar == nil then bubble.castReplacesPowerBar = false end
        bubble.barValueAmount = nil
        bubble.barValuePercent = nil
    end,

    -- v14 -> v15: add separate friendly NPC/player presentation controls.
    [14] = function(db)
        local bubble = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or {}
        db.bubbleNameplates = bubble
        if bubble.friendlyNPCNameTitleOnly == nil then bubble.friendlyNPCNameTitleOnly = false end
        if bubble.friendlyPlayerDamagedOnly == nil then bubble.friendlyPlayerDamagedOnly = false end
    end,

    -- v15 -> v16: PlayerFrame now uses fixed Classic artwork and Blizzard-owned
    -- portrait/status elements. Remove retired player-only geometry and icon
    -- controls so imported profiles cannot imply that they still affect it.
    [15] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        for _, key in ipairs({
            "playerBarHeight", "playerBarPadX", "playerBarY1", "playerBarGap",
            "showPlayerName", "showRestIcon", "showStatusTexture",
            "showAttackBackground", "showCombatGlow", "combatGlowColor",
            "showGroupIndicator", "showPVPIcon", "playerPVPIconSize",
            "playerPVPIconX", "playerPVPIconY", "restIconAnchor",
        }) do
            uf[key] = nil
        end
    end,

    -- v16 -> v17: add an optional solid-white name color for Bubble nameplates.
    [16] = function(db)
        local bubble = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or {}
        db.bubbleNameplates = bubble
        if bubble.whiteNames == nil then bubble.whiteNames = false end
    end,

    -- v17 -> v18: the old white-name presentation was later retired. Keep
    -- this historical step only to discard the predecessor key cleanly.
    [17] = function(db)
        local bubble = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or {}
        db.bubbleNameplates = bubble
        bubble.whiteNames = nil
        bubble.blizzardNameBehavior = nil
    end,

    -- v18 -> v19: compact unit-frame timers and Blizzard-owned target status
    -- elements made several legacy settings inert. Remove them so profiles and
    -- SavedVariables describe only controls that still affect runtime behavior.
    [18] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        for _, key in ipairs({
            "castbarSpellValues", "showQueuedSwingDamage",
            "targetBarWidth", "targetBarHeight", "targetBarPadX",
            "targetBarY1", "targetBarGap", "attackBarHeight", "castBarHeight",
            "showLevelText", "levelClassificationSuffix", "neutralColor",
            "showTargetPVPIcon", "targetPVPIconSize",
            "targetPVPIconX", "targetPVPIconY",
        }) do
            uf[key] = nil
        end
    end,

    -- v19 -> v20: Party frames now use fixed 119x48 artwork. Remove the old
    -- freeform bar geometry controls; partyScale remains the single visual size
    -- control for the complete artwork/bar/portrait assembly.
    [19] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        uf.partyBarWidth = nil
        uf.partyHealthBarHeight = nil
        uf.partyManaBarHeight = nil
    end,

    -- v20 -> v21: the fixed 119x48 Target-of-Target artwork is native-scale.
    -- Remove the retired independent ToT scale multiplier from saved profiles.
    [20] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if uf then uf.totScale = nil end
    end,

    -- v21 -> v22: Target-of-Target now owns independent health/power formats.
    -- Preserve the former appearance by seeding them from Target, and increase
    -- the fitted ToT name by the requested three font points.
    [21] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        if uf.totHealthFormat == nil then
            uf.totHealthFormat = uf.targetHealthFormat or "current-max-pct"
        end
        if uf.totPowerFormat == nil then
            uf.totPowerFormat = uf.targetPowerFormat or "percent"
        end
        local oldSize = tonumber(uf.totNameFontSize)
        uf.totNameFontSize = math.max(5, math.min(18, (oldSize or 9) + 3))
    end,

    -- v22 -> v23: increase both fitted Target-of-Target font controls by two
    -- points. Apply this to existing profiles as well as the larger defaults.
    [22] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        local oldNameSize = tonumber(uf.totNameFontSize)
        local oldTextSize = tonumber(uf.totTextFontSize)
        uf.totNameFontSize = math.max(5, math.min(20, (oldNameSize or 12) + 2))
        uf.totTextFontSize = math.max(5, math.min(16, (oldTextSize or 7) + 2))
    end,

    -- v23 -> v24: introduce TurboFaceDB.modules master toggles.
    --
    -- Existing profiles must not change behavior on upgrade, so every gate is
    -- seeded ENABLED except where the profile already carried an equivalent
    -- opt-out. Two legacy flags map cleanly onto the new shape and are folded
    -- in (the originals are LEFT IN PLACE -- module code still reads them, and
    -- the GUI now writes both sides through the same control):
    --
    --   unitframes.partyEnabled      -> modules.unitframes.party
    --   power.actionOverlayEnabled   -> modules.hotbarPower.enabled
    --
    -- `power.enabled` is deliberately NOT folded into a single module gate: it
    -- historically governed the overlay AND the tick markers together, which
    -- the new schema splits into hotbarPower and playerTicks. Folding it would
    -- silently disable one of the two for anyone who had turned it off, so it
    -- stays as the shared PowerCost kill switch beneath both gates.
    [23] = function(db)
        if type(db.modules) ~= "table" then db.modules = {} end
        local m = db.modules

        local function seed(family, tbl)
            if type(m[family]) ~= "table" then m[family] = {} end
            for k, v in pairs(tbl) do
                if m[family][k] == nil then m[family][k] = v end
            end
        end

        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        local partyOn = true
        if uf and uf.partyEnabled == false then partyOn = false end

        seed("unitframes", {
            enabled = true, player = true, target = true,
            tot = true, party = partyOn, pet = true,
        })
        seed("nameplates",  { enabled = true })
        seed("auras",       { enabled = true })
        seed("class",       { enabled = true })
        seed("playerTicks", { enabled = true })

        local pw = type(db.power) == "table" and db.power or nil
        seed("hotbarPower", { enabled = not (pw and pw.actionOverlayEnabled == false) })
    end,

    -- v24 -> v25: remove the retired Plus sound-muting suite. Its old mute
    -- lists largely targeted sound kits from other expansions.
    --
    -- No unmute pass is needed: MuteSoundFile is runtime-only and is not
    -- persisted by the client, so a profile that had mutes active simply logs
    -- in unmuted once the applying code is gone.
    [24] = function(db)
        local p = db.plus
        if type(p) ~= "table" then return end
        p.muteGameSounds  = nil
        p.muteSounds      = nil
        p.muteMountSounds = nil
        p.muteMounts      = nil
    end,

    -- v25 -> v26: remove Potato PC Mode. It doubled every internal throttle via
    -- ns.c_throttleMultiplier; the multiplier and all of its use sites are gone,
    -- so the base intervals are now the only intervals. Tune those directly
    -- rather than reintroducing a global scaler.
    [25] = function(db)
        db.potatoMode = nil
    end,

    -- v26 -> v27 (2026-08): the minimap button is always on. Its enable key is
    -- removed rather than left orphaned, which also releases anyone who had it
    -- switched off -- otherwise a stale false would linger in the saved file
    -- looking like a live setting. minimapButtonAngle is kept.
    [26] = function(db)
        db.minimapButtonEnabled = nil
    end,

    -- v27 -> v28 (2026-08): unitframes.partyEnabled was a mirror of the
    -- modules.unitframes.party gate, written only by the Options checkbox
    -- handler. A profile apply or import replaces TurboFaceDB wholesale and
    -- never ran that handler, so the two could silently disagree -- and
    -- because the flag had no control of its own, a stale `false` was
    -- invisible and unfixable from the UI.
    --
    -- Fold it into the gate (an explicit false wins, matching what the user
    -- last saw) and drop the key. Runtime now reads the gate only.
    [27] = function(db)
        local uf = db.unitframes
        if type(uf) == "table" then
            if uf.partyEnabled == false then
                if type(db.modules) ~= "table" then db.modules = {} end
                if type(db.modules.unitframes) ~= "table" then db.modules.unitframes = {} end
                db.modules.unitframes.party = false
            end
            uf.partyEnabled = nil
        end
    end,

    -- v28 -> v29 (2026-08): the Lua nameplate stacking engine is disabled. It
    -- drove layout from nameplate:GetPoint(), but NamePlate base frames are
    -- restricted regions, so that call errors and taints TurboFace. Blizzard's
    -- native anti-overlap already does the job. Modern clients expose it via
    -- the Enemy bit of nameplateStackingTypes, owned by BubbleNameplates.
    --
    -- Clear the enable key so nothing can turn the engine back on from a saved
    -- profile. The tuning values are left alone: they are inert without the
    -- engine, and keeping them means a future CVar-based implementation can
    -- still read a user's spacing preference. See ARCHITECTURE 11.10.
    [28] = function(db)
        if type(db.stacking) == "table" then
            db.stacking.enabled = nil
        end
    end,

    -- v29 -> v30: the player DPS badge is now colored by the meter's selected
    -- metric, so its damage color moved from the level-text yellow to scarlet
    -- and a separate healing color was added. Only rewrite a profile still
    -- sitting on the old default; a color the user picked is left alone. The
    -- picker saves the keyed {r=,g=,b=} form, so matching the array form here
    -- also means a customized value can never be caught by accident.
    [29] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 0.82 and c[3] == 0 then
            uf.playerDPSColor = { 1, 0.141, 0 }
        end
    end,

    -- v30 -> v31: the badge damage scarlet was retuned from RGB 255/36/0 to
    -- 255/61/0. Step 29 above is deliberately left writing the old value rather
    -- than edited in place: it may already have run, so profiles arriving here
    -- by either route (never migrated, or migrated at v30) both land on the
    -- current default. A picked color is still left alone.
    [30] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 0.141 and c[3] == 0 then
            uf.playerDPSColor = { 1, 0.24, 0 }
        end
    end,

    -- v31 -> v32: badge damage color retuned again, 255/61/0 -> 255/128/0.
    -- Only the immediately preceding default needs matching: steps run in order,
    -- so a profile still on an older value has already been walked forward to it
    -- by 29/30 before this runs. A picked color is still left alone.
    [31] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 0.24 and c[3] == 0 then
            uf.playerDPSColor = { 1, 0.5, 0 }
        end
    end,

    -- v32 -> v33: badge damage color retuned again, 255/128/0 -> white. As with
    -- 30/31, only the immediately preceding default is matched; ordered steps
    -- have already walked older profiles forward to it.
    [32] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 0.5 and c[3] == 0 then
            uf.playerDPSColor = { 1, 1, 1 }
        end
    end,


    -- v33 -> v34: the minimap `squareMinimap` boolean became the `minimapShape`
    -- selector ("round" / "square" / "torn"), so the torn-edge mask is a third
    -- shape rather than a second boolean that could contradict the first.
    -- The old key is cleared rather than left alongside: it would survive in
    -- profile exports and read as a stale Plus key to ns.ValidatePlusSectionMap.
    [33] = function(db)
        local plus = db.plus
        if type(plus) ~= "table" then return end
        if plus.minimapShape == nil then
            plus.minimapShape = (plus.squareMinimap == true) and "square" or "round"
        end
        plus.squareMinimap = nil
    end,

    -- v34 -> v35: the short-lived "torn" minimap shape was removed in favour of
    -- selectable border textures. Anyone who had it selected is moved to
    -- "square", the shape it was a variant of. Without this step their stored
    -- value would no longer match any known shape and would silently fall
    -- through to the round restore path, quietly undoing their choice.
    [34] = function(db)
        local plus = db.plus
        if type(plus) ~= "table" then return end
        if plus.minimapShape == "torn" then
            plus.minimapShape = "square"
        end
    end,

    -- v35 -> v36: DoT prediction gained a second colour for the lethal case, so
    -- the base colour was lightened to read clearly against it. Only the exact
    -- previous default is retuned; a colour the user picked themselves is left
    -- alone. The defaults merge cannot do this on its own, because the old
    -- value is already written into their saved variables. Same rule as the
    -- playerDPSColor steps above.
    [35] = function(db)
        local c = db.dotPredictionColor
        if type(c) ~= "table" then return end
        if c.r == 0.6 and c.g == 0.3 and c.b == 0.9 then
            db.dotPredictionColor = { r = 0.847, g = 0.706, b = 0.973 }
        end
    end,

    -- v36 -> v37: badge damage color retuned again, white -> light red. Same
    -- rule as steps 30-32: only the immediately preceding default is matched,
    -- so a color the user picked themselves survives untouched. Note this key
    -- is a POSITIONAL array ({r,g,b}), unlike dotPredictionColor which is keyed
    -- ({r=,g=,b=}) -- they are not interchangeable.
    [36] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 1 and c[3] == 1 then
            uf.playerDPSColor = { 1, 0.28, 0.3 }
        end
    end,

    -- v37 -> v38: light red softened, 255/71/77 -> 255/89/89. Chained as its own
    -- step rather than folded into [36]: anyone who already logged in on v37 has
    -- the older red written to their saved variables and dbVersion 37, so [36]
    -- will never run for them again.
    [37] = function(db)
        local uf = db.unitframes
        if type(uf) ~= "table" then return end
        local c = uf.playerDPSColor
        if type(c) == "table" and c[1] == 1 and c[2] == 0.28 and c[3] == 0.3 then
            uf.playerDPSColor = { 1, 0.35, 0.35 }
        end
    end,

    -- v38 -> v39: lethal DoT prediction colour brightened, 48/25/52 ->
    -- 64/26/64. Only the exact previous default is matched, so a colour the
    -- user picked themselves survives. Note this key is KEYED ({r=,g=,b=}),
    -- unlike playerDPSColor which is positional -- see step [36].
    [38] = function(db)
        local c = db.dotPredictionLethalColor
        if type(c) ~= "table" then return end
        if c.r == 0.188 and c.g == 0.098 and c.b == 0.204 then
            db.dotPredictionLethalColor = { r = 0.25, g = 0.1, b = 0.25 }
        end
    end,

    -- v39 -> v40: lethal colour brightened again, 64/26/64 -> 77/31/77.
    -- Chained rather than folded into [38] for the same reason step [37]
    -- exists: anyone who already logged in on v39 has the previous value
    -- written to their saved variables and will never re-run [38].
    [39] = function(db)
        local c = db.dotPredictionLethalColor
        if type(c) ~= "table" then return end
        if c.r == 0.25 and c.g == 0.1 and c.b == 0.25 then
            db.dotPredictionLethalColor = { r = 0.3, g = 0.12, b = 0.3 }
        end
    end,

    -- v40 -> v41: lethal colour brightened a final notch, 77/31/77 -> 89/36/89.
    -- Chained for the same reason as [39].
    [40] = function(db)
        local c = db.dotPredictionLethalColor
        if type(c) ~= "table" then return end
        if c.r == 0.3 and c.g == 0.12 and c.b == 0.3 then
            db.dotPredictionLethalColor = { r = 0.35, g = 0.14, b = 0.35 }
        end
    end,

    -- v41 -> v42: split the Hearthstone mover's two helper features into
    -- independent options. Existing profiles had both helpers implicitly on
    -- whenever the Hearthstone widget was enabled, so seed both true to
    -- preserve their current appearance and behavior.
    [41] = function(db)
        if db.hearthTimerEnabled == nil then db.hearthTimerEnabled = true end
        if db.hearthAutoBindEnabled == nil then db.hearthAutoBindEnabled = true end
    end,

    -- v42 -> v43 (Classic Era 1.15.9): Blizzard now owns native nameplate
    -- size/target scaling and castbar presentation. Remove TurboFace's retired
    -- replacement-model controls and the legacy totem presentation mode.
    [42] = function(db)
        local bubble = db.bubbleNameplates
        if type(bubble) == "table" then
            bubble.castReplacesPowerBar = nil
            bubble.scale = nil
            bubble.targetGrowthScale = nil
        end
        db.scale = nil
        db.targetScale = nil
        db.friendlyScale = nil
        db.petScale = nil
        db.totemDisplay = nil
    end,

    -- v43 -> v44: native Blizzard health text replaces the retired TurboFace
    -- health-format control. Visibility locking and Questie offset ownership are
    -- also removed. Preserve the already validated 0.15.16 appearance by
    -- enabling centering against the full native chassis for existing profiles.
    [43] = function(db)
        local bubble = db.bubbleNameplates
        if type(bubble) ~= "table" then
            bubble = {}
            db.bubbleNameplates = bubble
        end
        bubble.centerHealthText = true
        bubble.centerHealthTextOnNameplate = true
        bubble.healthTextFormat = nil
        bubble.lockNameplatesOn = nil
        bubble.questieCompatibility = nil
    end,

    -- v44 -> v45: Pet happiness no longer owns a Unit Frames swipe/timer
    -- setting. The simpler Class Buff reminder uses classBuffFeedPet instead.
    [44] = function(db)
        local uf = db.unitframes
        if type(uf) == "table" then uf.petHappinessTimer = nil end
    end,

    -- v45 -> v46: retire the Plus Dismount helper family. Remove both the
    -- section gate and all four settings so old profiles/imports cannot carry
    -- invisible configuration for runtime that no longer exists.
    [45] = function(db)
        if type(db.modules) == "table" and type(db.modules.plus) == "table" then
            db.modules.plus.dismount = nil
        end
        if type(db.plus) == "table" then
            db.plus.standAndDismount = nil
            db.plus.dismountNoResource = nil
            db.plus.dismountNoMoving = nil
            db.plus.dismountNoTaxi = nil
        end
    end,

    -- v46 -> v47: Party/Pet aura presentation is an Aura subsystem, not a
    -- Unit Frames child. Move its persisted styling settings to db.auras and
    -- seed independent Aura child gates from the old effective UnitFrame gates
    -- so an upgrade preserves what the user was actually seeing before they
    -- choose new independent values in Global -> Auras.
    [46] = function(db)
        if type(db.auras) ~= "table" then db.auras = {} end
        if type(db.modules) ~= "table" then db.modules = {} end
        if type(db.modules.auras) ~= "table" then db.modules.auras = {} end

        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        local ufGate = type(db.modules.unitframes) == "table" and db.modules.unitframes or nil
        local auraGate = db.modules.auras
        local oldUFFamilyOn = not (ufGate and ufGate.enabled == false)
        if auraGate.party == nil then
            auraGate.party = oldUFFamilyOn and not (ufGate and ufGate.party == false)
        end
        if auraGate.pet == nil then
            auraGate.pet = oldUFFamilyOn and not (ufGate and ufGate.pet == false)
        end

        local keys = {
            "partyBuffsEnabled",
            "partyClassRemindersEnabled",
            "partyBuffIconSize",
            "partyClassBuffIconSize",
            "partyClassBuffWarnSeconds",
            "partyBuffMax",
            "partyBuffsPerRow",
        }
        if uf then
            for i = 1, #keys do
                local key = keys[i]
                if db.auras[key] == nil and uf[key] ~= nil then db.auras[key] = uf[key] end
                uf[key] = nil
            end
        end
    end,

    -- v47 -> v48: Target-of-Target debuffs become an independent Aura child
    -- instead of implicitly inheriting the Player/Target auraEnabled switch.
    -- Preserve the old effective intent and visual size on upgrade: users who
    -- had aura styling enabled keep ToT styling enabled, and ToT starts at the
    -- same scale that target debuffs used before the split.
    [47] = function(db)
        if type(db.modules) ~= "table" then db.modules = {} end
        if type(db.modules.auras) ~= "table" then db.modules.auras = {} end
        if type(db.auras) ~= "table" then db.auras = {} end

        local auraGate = db.modules.auras
        if auraGate.tot == nil then auraGate.tot = db.auraEnabled == true end
        if db.auras.totDebuffScale == nil then
            db.auras.totDebuffScale = tonumber(db.auraTargetDebuffScale) or 1
        end
    end,

    -- v48 -> v49: enemy nameplate swing timing becomes its own Nameplates
    -- feature instead of being fixed-on or borrowing Threat Bubble ownership.
    -- Seed it enabled so upgrades preserve the 0.15.60 visual behavior.
    [48] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        if db.bubbleNameplates.swingTimer == nil then
            db.bubbleNameplates.swingTimer = true
        end
    end,

    -- v49 -> v50: retire the legacy ThreatBubble shell/fill presentation.
    -- Preserve the old visibility choice, but canonicalize quantitative threat
    -- as a text-only number anchored beside the live health bar.
    [49] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        local bubble = db.bubbleNameplates
        if bubble.threatNumber == nil then
            bubble.threatNumber = bubble.threatBubble ~= false
        end
        bubble.threatBubble = nil
        bubble.threatScale = nil
        bubble.threatXOffset = nil
        bubble.threatYOffset = nil
        bubble.threatPulseGrowth = nil
    end,

    -- v50 -> v51: Threat Number owns its font-size setting beside its other
    -- presentation/audio controls. Preserve the current 0.15.62 appearance at
    -- 6px rather than inheriting the retired legacy threat-text size.
    [50] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        local bubble = db.bubbleNameplates
        if bubble.threatTextFontSize == nil then bubble.threatTextFontSize = 6 end
        db.threatTextFontSize = nil
        db.threatTextOffsetX = nil
        db.threatTextOffsetY = nil
    end,

    -- v51 -> v52: Grocery gains an Ammo category after Potions. Existing
    -- profiles default it on so upgrades preserve the prior show-all catalog
    -- behavior instead of silently hiding the newly added vendor items.
    [51] = function(db)
        if db.groceryFilterAmmo == nil then db.groceryFilterAmmo = true end
    end,

    -- v52 -> v53: friendly NPC Job Icon becomes an independent Nameplates
    -- feature instead of a fixed-on Bubble-era presentation detail. Preserve
    -- existing behavior for upgrades by defaulting the new gate on.
    [52] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        if db.bubbleNameplates.jobIcon == nil then db.bubbleNameplates.jobIcon = true end
    end,

    -- v53 -> v54: retire Friendly Name-Only: Blizzard Hover Colors. Friendly
    -- lite names use TurboFace's normal deterministic class/reaction colors and
    -- additive hover highlight; native plates keep Blizzard's own hover owner.
    [53] = function(db)
        local bubble = type(db.bubbleNameplates) == "table" and db.bubbleNameplates or nil
        if bubble then bubble.blizzardNameBehavior = nil end
    end,

    -- v54 -> v55: broaden the native name shadow workaround from NPC names to
    -- Blizzard-owned player names too. Rename the persisted gate to match the
    -- new generic scope while preserving each profile's prior enabled state.
    [54] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        local bubble = db.bubbleNameplates
        if bubble.nameTextShadow == nil then
            if bubble.enemyNPCNameShadow == nil then
                bubble.nameTextShadow = true
            else
                bubble.nameTextShadow = bubble.enemyNPCNameShadow ~= false
            end
        end
        bubble.enemyNPCNameShadow = nil
    end,

    -- v55 -> v56: finish the Blizzard-native nameplate cutover. Remove the
    -- last serialized settings that belonged to TurboFace's retired baseline
    -- renderer (custom raid marker, stacking simulation, health/cast/name skin,
    -- threat-color palette, target glow/arrows, and fallback-only geometry).
    [55] = function(db)
        PruneKeys(db, RETIRED_NAMEPLATE_KEYS)
        PruneKeys(db.bubbleNameplates, RETIRED_BUBBLE_NAMEPLATE_KEYS)
    end,

    -- v56 -> v57: Junk & Inventory gains the mutually-exclusive Bank item
    -- state plus a live-bank mass-withdraw control. Existing mark bindings now
    -- cycle all three states. Per-character discardPile values need no rewrite
    -- because the new "bank" value extends its boolean format.
    [56] = function(db)
        db.invBankMarkMouseShortcut = nil
        if db.invBankWithdrawAll == nil then db.invBankWithdrawAll = true end
    end,

    -- v57 -> v58: add native Speedrun Splits configuration. Historical PB and
    -- run data use dedicated SavedVariables rather than profile configuration.
    [57] = function(db)
        if type(db.speedrunSplits) ~= "table" then db.speedrunSplits = {} end
        if db.speedrunSplits.enabled == nil then db.speedrunSplits.enabled = false end
    end,

    -- v58 -> v59: the splits display gained an interactive partial-level
    -- toggle, so its new mover must not begin in click-through mode.
    [58] = function(db)
        if type(db.movers) ~= "table" then db.movers = {} end
        if type(db.movers.elements) ~= "table" then db.movers.elements = {} end
        if type(db.movers.elements.SpeedrunSplits) ~= "table" then
            db.movers.elements.SpeedrunSplits = {}
        end
        db.movers.elements.SpeedrunSplits.clickThrough = false
    end,

    -- v59 -> v60: add the optional UnstuckSkips presentation hook. Its
    -- checkbox must remain interactive under the mover framework.
    [59] = function(db)
        if db.unstuckSkipVisualEnabled == nil then db.unstuckSkipVisualEnabled = true end
        if type(db.movers) ~= "table" then db.movers = {} end
        if type(db.movers.elements) ~= "table" then db.movers.elements = {} end
        if type(db.movers.elements.UnstuckSkips) ~= "table" then
            db.movers.elements.UnstuckSkips = {}
        end
        if db.movers.elements.UnstuckSkips.enabled == nil then
            db.movers.elements.UnstuckSkips.enabled = true
        end
        db.movers.elements.UnstuckSkips.clickThrough = false
    end,

    -- v60 -> v61: item loot rows gain an independently toggleable vendor
    -- value column, enabled to expose the new presentation by default.
    [60] = function(db)
        if type(db.lootFrame) ~= "table" then db.lootFrame = {} end
        if db.lootFrame.showVendorValue == nil then db.lootFrame.showVendorValue = true end
    end,

    -- v61 -> v62: add an opt-in anchor amendment for Blizzard's new 1.15.9
    -- PvE rarity icon. Blizzard visibility remains unchanged by default.
    [61] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        if db.bubbleNameplates.rarityIconRight == nil then
            db.bubbleNameplates.rarityIconRight = false
        end
    end,

    -- v62 -> v63: pre-release configuration hygiene. Remove settings from
    -- retired feature generations that could still survive in current exports,
    -- fold the two old Power compatibility migrations into the versioned schema,
    -- and normalize the minimap-button angle so repeated historical drag values
    -- cannot serialize as multi-turn degree counts. No live user-facing setting
    -- is changed by this migration.
    [62] = function(db)
        local retiredTopLevel = {
            "classBuffWeaponOH", "druidPowerBarHeight", "fontOutline",
            "friendlyGuild", "groceryCornerX", "groceryCornerY",
            "netWorthLocked", "netWorthOutline",
        }
        PruneKeys(db, retiredTopLevel)

        if type(db.modules) == "table" and type(db.modules.plus) == "table" then
            db.modules.plus.maps = nil
        end

        local plus = type(db.plus) == "table" and db.plus or nil
        if plus then
            -- Older Maps settings were retired when TurboFace moved to the
            -- narrow MapTweaks ownership model (current keys use `map*`,
            -- singular). All historical `maps*` keys are therefore dead.
            for key in pairs(plus) do
                if type(key) == "string" and key:sub(1, 4) == "maps" then
                    plus[key] = nil
                end
            end
            plus.autoQuestAvailable = nil
            plus.autoQuestCompleted = nil
            plus.autoQuestKeyOverride = nil
            plus.automateQuests = nil
        end

        local power = type(db.power) == "table" and db.power or nil
        if power then
            -- These two compatibility migrations predated dbVersion. Perform
            -- them exactly once here, then stop persisting their guard flags.
            if power._powerColorSplitMigrated ~= true then
                -- Prefer already-present split settings. Some historical
                -- snapshots contain both the legacy shared fields and newer
                -- split fields; the newer values are authoritative there.
                if power.useCustomOverlayColor == nil and power.useCustomColor ~= nil then
                    power.useCustomOverlayColor = power.useCustomColor == true
                end
                if power.useCustomCounterColor == nil and power.useCustomColor ~= nil then
                    power.useCustomCounterColor = power.useCustomColor == true
                end
                if type(power.customColor) == "table" then
                    if type(power.overlayColor) ~= "table" then
                        power.overlayColor = DeepCopy(power.customColor)
                    end
                    if type(power.counterColor) ~= "table" then
                        power.counterColor = DeepCopy(power.customColor)
                    end
                end
            end
            if power._regenClockSplitMigrated ~= true then
                if power.manaTick == nil then
                    power.manaTick = power.fiveSecondRule ~= false
                end
                if power.manaTickBackground == nil then
                    power.manaTickBackground = power.fiveSecondRuleBackground ~= false
                end
            end
            power._powerColorSplitMigrated = nil
            power._regenClockSplitMigrated = nil
            power.useCustomColor = nil
            power.customColor = nil
            power.hideOverlap = nil
        end

        if type(db.auras) == "table" then
            db.auras.nameplateColorRules = nil
            -- Debuff stack text is now a fixed top-right presentation detail,
            -- not a user setting (Nameplates/Auras.lua never reads this key).
            db.auras.debuffStackAnchor = nil
        end

        local turboDebuffs = type(db.turboDebuffs) == "table" and db.turboDebuffs or nil
        if turboDebuffs then
            PruneKeys(turboDebuffs, {
                "nameOnlyAnchor", "nameOnlySize", "nameOnlyTimerSize",
                "nameOnlyXOffset", "nameOnlyYOffset",
            })
        end

        local movers = type(db.movers) == "table" and db.movers or nil
        if movers and type(movers.elements) == "table" then
            movers.elements.PlayerCombatTimers = nil
            movers.elements.TargetCombatTimers = nil
        end

        local angle = tonumber(db.minimapButtonAngle)
        if angle then db.minimapButtonAngle = angle % 360 end
    end,

    -- v63 -> v64: retire addon-wide typography ownership. TurboFace was still
    -- pre-release at this boundary, so old development profiles are not carried
    -- forward feature-by-feature. The current feature-local defaults become the
    -- clean public baseline; dated presets explicitly store intentional overrides.
    [63] = function(db)
        db.globalFont = nil
        db.textStyle = nil
        db.auraTimerFont = nil
    end,

    -- v64 -> v65: FPS Counter becomes a proper Speedrun feature gate instead
    -- of relying on its Movers element as the only activation switch. Preserve
    -- the pre-existing visible-by-default behavior for development profiles.
    [64] = function(db)
        if db.fpsCounterEnabled == nil then db.fpsCounterEnabled = true end
    end,

    -- v65 -> v66: split UnitFrame typography by semantic role. Development-era
    -- shared font/style values are retired; current Name and Bar defaults are
    -- the public baseline. Existing size/layout settings remain untouched.
    [65] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if uf then
            uf.font = nil
            uf.textStyle = nil
        end
    end,

    -- v66 -> v67: compact fixed-art UnitFrames own their text sizes instead
    -- of borrowing Player/Target sizes or hardcoded health/power sizes.
    [66] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        local sharedName = tonumber(uf.nameFontSize) or 10
        if uf.petNameFontSize == nil then uf.petNameFontSize = math.min(sharedName, 9) end
        if uf.partyNameFontSize == nil then uf.partyNameFontSize = math.min(sharedName, 9) end
        if uf.petBarFontSize == nil then uf.petBarFontSize = 8 end
        if uf.partyBarFontSize == nil then uf.partyBarFontSize = 8 end
        if uf.totBarFontSize == nil then uf.totBarFontSize = tonumber(uf.totTextFontSize) or 9 end
        uf.totTextFontSize = nil
    end,

    -- v67 -> v68: Druid Power Bar owns its typography rather than borrowing
    -- the generic Class font/style. Normalize the old 0=auto development
    -- size into the public explicit bar-text baseline.
    [67] = function(db)
        if db.druidPowerBarFont == nil then db.druidPowerBarFont = "Blizzard Narrow" end
        if db.druidPowerBarTextStyle == nil then db.druidPowerBarTextStyle = "OUTLINE" end
        if tonumber(db.druidPowerBarTextSize) == nil or tonumber(db.druidPowerBarTextSize) <= 0 then
            db.druidPowerBarTextSize = 11
        end
    end,

    -- v68 -> v69: NanShield gains feature-local typography and finally exposes
    -- its text visibility in Options. Preserve the former shared Bar appearance
    -- while enabling the number that had been factory-disabled with no UI path
    -- for users to turn it back on.
    [68] = function(db)
        local uf = type(db.unitframes) == "table" and db.unitframes or nil
        if not uf then return end
        if uf.nanShieldFont == nil then uf.nanShieldFont = uf.barFont or "Blizzard Narrow" end
        if uf.nanShieldTextStyle == nil then uf.nanShieldTextStyle = uf.barTextStyle or "OUTLINE" end
        if uf.nanShieldFontSize == nil then
            uf.nanShieldFontSize = math.max(4, (tonumber(uf.barFontSize) or 10) - 1)
        end
        uf.nanShieldShowText = true
    end,

    -- v69 -> v70: Health regen gets the same independently configurable
    -- marker-border ownership already used by Mana, 5SR, and Energy.
    [69] = function(db)
        local power = type(db.power) == "table" and db.power or nil
        if not power then return end
        if power.healthRegenBackground == nil then power.healthRegenBackground = true end
        if type(power.healthRegenBorderColor) ~= "table" then
            power.healthRegenBorderColor = { r = 0, g = 0, b = 0, a = 0.85 }
        end
    end,

    -- v70 -> v71: expose the remaining user-facing Blizzard nameplate layout
    -- and selection CVars through the existing reversible geometry owner.
    [70] = function(db)
        if type(db.bubbleNameplates) ~= "table" then db.bubbleNameplates = {} end
        local bubble = db.bubbleNameplates
        if bubble.overlapH == nil then bubble.overlapH = 1.35 end
        if bubble.selectedScale == nil then bubble.selectedScale = 1.00 end
        if bubble.selectedAlpha == nil then bubble.selectedAlpha = 1.00 end
        if bubble.notSelectedAlpha == nil then bubble.notSelectedAlpha = 1.00 end
    end,

    -- v71 -> v72: XP run/session history becomes per-character state with its
    -- own TFXP1 transfer format instead of travelling in settings profiles.
    [71] = function(db)
        MoveLegacyXPSession(db)
    end,

    -- v72 -> v73: Classic's HUD Edit Mode owns the native Blizzard XP/status
    -- tracking bar, so retire TurboFace's duplicate XPBar mover. ExperienceBar
    -- remains as the independently movable Luxthos-like XP widget.
    [72] = function(db)
        RemoveRetiredBlizzardXPMover(db)
    end,

    -- v73 -> v74: Flight Bar presentation is fixed and automatically active
    -- with its category. Only width and scale remain user-configurable.
    [73] = function(db)
        RemoveRetiredFlightBarSettings(db)
    end,

    -- v74 -> v75: integrate Lvl1QuickSetup as a TurboFace-native Speedrun
    -- subsystem. Its destructive automatic restore remains off by default; the
    -- old Plus movie-skip hook is retired in favor of level-one auto-skip owned
    -- by Quick Setup when that subsystem is explicitly enabled.
    [74] = function(db)
        if type(db.quickSetup) ~= "table" then db.quickSetup = {} end
        if db.quickSetup.enabled == nil then db.quickSetup.enabled = false end
        if db.quickSetup.autoSkipCinematic == nil then db.quickSetup.autoSkipCinematic = true end
        if type(db.plus) == "table" then db.plus.fasterMovieSkip = nil end
    end,

    -- v75 -> v76: make Pet name placement user-selectable. Profiles without an
    -- explicit choice adopt the new below-bars default; the above-frame anchor
    -- is available only through the new option.
    [75] = function(db)
        if type(db.unitframes) ~= "table" then db.unitframes = {} end
        if db.unitframes.petNameAboveBars == nil then
            db.unitframes.petNameAboveBars = false
        end
    end,

    -- v76 -> v77: the temporary Loot Frame border-tuning controls served their
    -- purpose and are now baked into static presentation again. Remove the
    -- transient profile keys so old tuning values cannot survive in exports.
    [76] = function(db)
        if type(db.lootFrame) ~= "table" then return end
        db.lootFrame.borderEdgeSize = nil
        db.lootFrame.borderInset = nil
    end,

    -- v77 -> v78: Loot Frame icon sizing is now derived directly from row
    -- height (rowHeight - fixed shell padding), so the independent iconSize
    -- setting is retired from saved profiles and imports.
    [77] = function(db)
        if type(db.lootFrame) ~= "table" then return end
        db.lootFrame.iconSize = nil
    end,

    -- v78 -> v79: retire the mail, quest, and book font-resize controls and
    -- their stored sizes. Blizzard owns these shared FontObjects again.
    [78] = RemoveRetiredInterfaceFontResizeSettings,

}

function ns:LoadVariables()
    -- SavedVariables can be edited or corrupted outside the addon.  Treat a
    -- non-table root exactly like a missing database so migration/default code
    -- never indexes an invalid value during login.
    if type(TurboFaceDB) ~= "table" then TurboFaceDB = {} end
    if type(TurboFaceCacheDB) ~= "table" then TurboFaceCacheDB = {} end

    -- ---- Cache DB: wipe whenever the client build changes ----
    local build = select(2, GetBuildInfo())
    if TurboFaceCacheDB.clientBuild ~= build then
        -- Normal discovery/cache data is build-specific, but ownership records
        -- are not caches: they are the exact client/addon settings TurboFace
        -- owes back to the user when a feature is disabled. Preserve those
        -- across client updates so a patch cannot strand an override forever.
        local cvarOwners = TurboFaceCacheDB.cvarOwners
        local cvarBitOwners = TurboFaceCacheDB.cvarBitOwners
        local questieOwners = TurboFaceCacheDB.questieOwners
        -- Hearthstone batch timing data is observational, not discovery cache:
        -- it is measured connection behaviour that a client patch does not
        -- invalidate, and it is the whole point of the account-wide pool that a
        -- freshly rerolled character inherits it. Wiping it every patch would
        -- put a speedrunner back to a cold start at exactly the wrong moment.
        local hearthBatch = TurboFaceCacheDB.hearthBatch
        -- Taxi route timing is player-observed account data, not client-build
        -- discovery state. Preserve learned routes across patches just like
        -- Hearth Batch timing measurements.
        local flightTimes = TurboFaceCacheDB.flightTimes
        for k in pairs(TurboFaceCacheDB) do TurboFaceCacheDB[k] = nil end
        TurboFaceCacheDB.clientBuild = build
        if type(cvarOwners) == "table" then TurboFaceCacheDB.cvarOwners = cvarOwners end
        if type(cvarBitOwners) == "table" then TurboFaceCacheDB.cvarBitOwners = cvarBitOwners end
        if type(questieOwners) == "table" then TurboFaceCacheDB.questieOwners = questieOwners end
        if type(hearthBatch) == "table" then TurboFaceCacheDB.hearthBatch = hearthBatch end
        if type(flightTimes) == "table" then TurboFaceCacheDB.flightTimes = flightTimes end
    end
    if type(TurboFaceCacheDB.npcTitles) ~= "table" then
        TurboFaceCacheDB.npcTitles = {}
    end

    -- Classic Era 1.15.9 removed these scalar CVars. Drop stale ownership debt
    -- left by older TurboFace builds; current stacking ownership lives in the
    -- bit-level cvarBitOwners store instead.
    do
        local owners = TurboFaceCacheDB.cvarOwners
        local function Drop(owner, cvar)
            local snapshot = type(owners) == "table" and owners[owner]
            if type(snapshot) ~= "table" then return end
            snapshot[cvar] = nil
            if next(snapshot) == nil then owners[owner] = nil end
        end
        Drop("nameplates.geometry", "nameplateMotion")
        Drop("nameplates.visibility", "nameplateShowFriends")
        Drop("nameplates.stacking", "nameplateAllowOverlap")
    end

    -- Prep127 and earlier Forever saves encoded client-only revisions as
    -- dbVersion 80/81. Convert those markers to the client revision axis before
    -- running the portable migration chain.
    if ns.Schema and ns.Schema.AdoptLegacyVersion then
        ns.Schema:AdoptLegacyVersion(TurboFaceDB)
    end

    -- ---- Ordered portable migrations (before defaults merge) ----
    -- A hand-edited/corrupt version marker must not make the comparison below
    -- throw during login. Unknown future versions are normalized without trying
    -- to run migrations backwards.
    local v = TurboFaceDB.dbVersion
    if type(v) ~= "number" or v < 1 or v % 1 ~= 0 then
        v = 1
    elseif v > DB_VERSION then
        v = DB_VERSION
    end
    while v < DB_VERSION do
        local step = Migrations[v]
        if step then step(TurboFaceDB) end
        v = v + 1
    end
    TurboFaceDB.dbVersion = DB_VERSION

    -- Client migrations are deliberately separate from dbVersion so Forever
    -- can evolve client-only settings without making TF1 profiles unreadable
    -- by Classic. They run before normalization/default merge, matching the
    -- historical migration ordering.
    if ns.Schema and ns.Schema.RunClientMigrations then
        ns.Schema:RunClientMigrations(TurboFaceDB)
    end

    ns.NormalizeKnownConfigTypes(TurboFaceDB, ns.defaults)
    MergeDefaults(TurboFaceDB, ns.defaults)
    if ns.Schema and ns.Schema.PostLoad then
        ns.Schema:PostLoad(TurboFaceDB)
    end
    -- Current-schema/import guard: settings imports must never resurrect the
    -- legacy account-wide session subtree.
    MoveLegacyXPSession(TurboFaceDB)
    RemoveRetiredBlizzardXPMover(TurboFaceDB)
    RemoveRetiredFlightBarSettings(TurboFaceDB)
    -- Current-schema/import guard: removed QoL font controls must not survive
    -- hand-edited or same-version profile imports.
    RemoveRetiredInterfaceFontResizeSettings(TurboFaceDB)
    -- Final Loot Frame border geometry is static again. Keep imports and
    -- hand-edited current-schema profiles from resurrecting the temporary
    -- 0.17.61 tuning controls.
    if type(TurboFaceDB.lootFrame) == "table" then
        TurboFaceDB.lootFrame.borderEdgeSize = nil
        TurboFaceDB.lootFrame.borderInset = nil
        -- Row height is the sole vertical-size control; icon size is derived
        -- at render time and must not survive in current-schema imports.
        TurboFaceDB.lootFrame.iconSize = nil
    end
    if type(TurboFaceDB.plus) == "table" then
        TurboFaceDB.plus.fasterMovieSkip = nil
        -- Retired in 0.17.41: Classic Era now has Blizzard-native backpack
        -- free-slot display, so TurboFace no longer owns or serializes it.
        TurboFaceDB.plus.showFreeBagSlots = nil
    end
    ns.ValidatePlusSectionMap()

    -- Current-schema guard: retired global typography keys are never serialized
    -- again, even if a hand-edited/current-version import tries to reintroduce them.
    TurboFaceDB.globalFont = nil
    TurboFaceDB.textStyle = nil
    TurboFaceDB.auraTimerFont = nil

    -- Normalize the live typography surface as well as historical migrations.
    -- This catches hand-edited/current-schema imports without restoring the old
    -- INHERIT semantics. Unknown/external font names collapse to Blizzard Default.
    do
        local function Font(name) return ns:NormalizeFontName(name) end
        local function TextStyle(style, fallback)
            if style == "SHADOW" or style == "OUTLINE" or style == "NONE" then return style end
            return fallback or "SHADOW"
        end
        local function Nested(key, defaultStyle)
            local t = TurboFaceDB[key]
            if type(t) ~= "table" then return end
            t.font = Font(t.font)
            t.textStyle = TextStyle(t.textStyle, defaultStyle)
        end
        if type(TurboFaceDB.unitframes) == "table" then
            local uf = TurboFaceDB.unitframes
            uf.font = nil
            uf.textStyle = nil
            uf.nameFont = Font(uf.nameFont)
            uf.nameTextStyle = TextStyle(uf.nameTextStyle, "SHADOW")
            uf.barFont = Font(uf.barFont)
            uf.barTextStyle = TextStyle(uf.barTextStyle, "OUTLINE")
            uf.nanShieldFont = Font(uf.nanShieldFont)
            uf.nanShieldTextStyle = TextStyle(uf.nanShieldTextStyle, "OUTLINE")
        end
        Nested("auras", "SHADOW")
        Nested("experienceBar", "SHADOW")
        Nested("lootFrame", "SHADOW")
        Nested("speedrunSplits", "SHADOW")
        Nested("power", "SHADOW")
        Nested("turboDebuffs", "OUTLINE")
        if type(TurboFaceDB.power) == "table" then
            TurboFaceDB.power.tickFont = Font(TurboFaceDB.power.tickFont)
            TurboFaceDB.power.tickTextStyle = TextStyle(TurboFaceDB.power.tickTextStyle, "SHADOW")
        end
        local flat = {
            {"classFont", "classTextStyle", "SHADOW"},
            {"combatMeterFont", "combatMeterTextStyle", "SHADOW"},
            {"swingTimersFont", "swingTimersTextStyle", "SHADOW"},
            {"castBarsFont", "castBarsTextStyle", "SHADOW"},
            {"leashTimerFont", "leashTimerTextStyle", "SHADOW"},
            {"skillTrackerFont", "skillTrackerTextStyle", "SHADOW"},
            {"hearthFont", "hearthTextStyle", "SHADOW"},
            {"unstuckSkipFont", "unstuckSkipTextStyle", "SHADOW"},
            {"netWorthFont", "netWorthTextStyle", "SHADOW"},
        }
        for i = 1, #flat do
            local f = flat[i]
            TurboFaceDB[f[1]] = Font(TurboFaceDB[f[1]])
            TurboFaceDB[f[2]] = TextStyle(TurboFaceDB[f[2]], f[3])
        end
    end

    -- 0.7.1 briefly passed the Nameplates checkbox arguments in the wrong
    -- order, which could create these visible-label strings as top-level DB
    -- keys before raising an error. They were never valid settings.
    TurboFaceDB["Cast Replaces Power Bar (reload required)"] = nil
    TurboFaceDB["Friendly NPC: Name + Title Only"] = nil
    TurboFaceDB["Friendly Player: Show Only When Damaged"] = nil

    -- The old Ctrl+Right-click junk toggle was replaced by a normal Blizzard
    -- keybinding. Remove the retired option from existing/imported profiles.
    TurboFaceDB.invRightClickMark = nil
    TurboFaceDB.invBankMarkMouseShortcut = nil

    -- Interrupt glow was retired with the TurboFace-owned nameplate castbar
    -- event engine. Prune legacy/imported values on every load so the removed
    -- feature cannot linger in SavedVariables or exported profiles.
    TurboFaceDB.highlightGlowEnabled = nil
    TurboFaceDB.highlightGlowLines = nil
    TurboFaceDB.highlightGlowFrequency = nil
    TurboFaceDB.highlightGlowLength = nil
    TurboFaceDB.highlightGlowThickness = nil
    TurboFaceDB.highlightGlowColor = nil
    TurboFaceDB.highlightSpells = nil

    -- Normalize the remaining TurboFace augmentation controls after every
    -- profile load/import. Native plate size, health art, and castbar
    -- presentation stay in Blizzard Settings; the explicit selection CVar
    -- controls below are reversibly owned while Nameplates is active.
    do
        local bubble = TurboFaceDB.bubbleNameplates
        if type(bubble) ~= "table" then
            bubble = DeepCopy(ns.defaults.bubbleNameplates)
            TurboFaceDB.bubbleNameplates = bubble
        end
        local function ClampNumber(value, fallback, low, high)
            value = tonumber(value) or fallback
            if value < low then return low end
            if value > high then return high end
            return value
        end
        bubble.threatNumber = bubble.threatNumber ~= false
        bubble.threatTextFontSize = ClampNumber(bubble.threatTextFontSize, 6, 6, 16)
        bubble.swingTimer = bubble.swingTimer ~= false
        bubble.powerBarOverlap = bubble.powerBarOverlap == true
        bubble.powerBarHeightPct = ClampNumber(bubble.powerBarHeightPct, 0.30, 0.10, 0.40)
        bubble.overlapV = ClampNumber(bubble.overlapV, 1.00, 0.50, 2.00)
        bubble.overlapH = ClampNumber(bubble.overlapH, 1.35, 0.50, 2.00)
        bubble.selectedScale = ClampNumber(bubble.selectedScale, 1.00, 0.50, 2.00)
        bubble.selectedAlpha = ClampNumber(bubble.selectedAlpha, 1.00, 0.00, 1.00)
        bubble.notSelectedAlpha = ClampNumber(bubble.notSelectedAlpha, 0.80, 0.00, 1.00)
        bubble.gainVolume = ClampNumber(bubble.gainVolume, 1, 0, 1)
        bubble.lossVolume = ClampNumber(bubble.lossVolume, 1, 0, 1)
        bubble.muteAggroSounds = bubble.muteAggroSounds == true
        bubble.jobIcon = bubble.jobIcon ~= false
        bubble.rarityIconRight = bubble.rarityIconRight == true
        bubble.nameTextShadow = bubble.nameTextShadow ~= false
        bubble.friendlyNPCNameTitleOnly = bubble.friendlyNPCNameTitleOnly == true
        bubble.friendlyPlayerDamagedOnly = bubble.friendlyPlayerDamagedOnly == true
        bubble.friendlyNPCDamagedOnly = bubble.friendlyNPCDamagedOnly == true
        bubble.centerHealthText = bubble.centerHealthText == true
        bubble.centerHealthTextOnNameplate = bubble.centerHealthTextOnNameplate == true

        -- Current-schema guard: old imports may bypass the exact historical
        -- path that first retired a field. Prune the full forbidden surface
        -- after defaults merge so no obsolete renderer option can reappear.
        PruneKeys(bubble, RETIRED_BUBBLE_NAMEPLATE_KEYS)
        PruneKeys(TurboFaceDB, RETIRED_NAMEPLATE_KEYS)

    end

    -- Locked visual style: the border texture and sizes are hardcoded
    -- (GetBarBorderStyle; ToT size in UnitFrames) and the bar gap is part of
    -- that look. Prune the removed settings and pin barSpacing so old saved
    -- values cannot resurrect a different layout.
    TurboFaceDB.barBorderTexture = nil
    TurboFaceDB.barBorderSize = nil
    -- Legacy Combat Meter imports could carry a configurable row count, but
    -- the current viewport is intentionally fixed at five rows.
    TurboFaceDB.combatMeterMaxRows = nil
    if type(TurboFaceDB.movers) == "table" and type(TurboFaceDB.movers.aura) == "table" then
        -- ToT aura layout is fixed to four slots in one row; retain historical
        -- import handling above, then remove the obsolete compatibility field.
        TurboFaceDB.movers.aura.totPerRow = nil
    end

    if type(TurboFaceDB.unitframes) == "table" then
        TurboFaceDB.unitframes.barSpacing = 2
        TurboFaceDB.unitframes.totBorderSize = nil
        -- Known UnitFrame settings from pre-fixed-art implementations. Keep the
        -- historical migrations that understand them, then remove the obsolete
        -- serialized surface after migrations/default normalization have run.
        local retiredUnitFrameKeys = {
            "attackBarHeight", "castBarHeight", "castbarSpellValues",
            "healthFormat", "manaFormat", "levelClassificationSuffix",
            "partyBarWidth", "partyHealthBarHeight", "partyManaBarHeight",
            "playerBarWidth", "healthBarHeight", "manaBarHeight",
            "playerPVPIconSize", "playerPVPIconX", "playerPVPIconY",
            "restIconAnchor", "showAttackBackground", "showComboPoints",
            "showGroupIndicator", "showLevelText", "showPVPIcon",
            "showPlayerName", "showQueuedSwingDamage", "showRestIcon",
            "showStatusTexture", "showTargetPVPIcon", "targetBarWidth",
            "targetPVPIconSize", "targetPVPIconX", "targetPVPIconY",
            "totScale", "totTextFontSize", "hidePortrait",
            "barFontStyle", "barTexture", "nameFontStyle",
        }
        for i = 1, #retiredUnitFrameKeys do
            TurboFaceDB.unitframes[retiredUnitFrameKeys[i]] = nil
        end
    end

    -- Very old profile exports also carried flat UnitFrame mirrors that never
    -- became part of the current canonical schema. They are known dead keys,
    -- not forward-compatible unknown data.
    local retiredUnitFrameMirrorKeys = {
        "uf_barFont", "uf_barFontStyle", "uf_barTexture",
        "uf_nameFont", "uf_nameFontStyle", "uf_playerBarHeight", "uf_targetBarHeight",
    }
    for i = 1, #retiredUnitFrameMirrorKeys do
        TurboFaceDB[retiredUnitFrameMirrorKeys[i]] = nil
    end

    -- One-time migration for the first Warrior Overpower indicator defaults.
    -- (Predates dbVersion; self-guarded via __migrations flag.)
    TurboFaceDB.__migrations = TurboFaceDB.__migrations or {}
    if not TurboFaceDB.__migrations.warriorOverpowerLeft20 then
        if TurboFaceDB.warriorOverpowerPosition == "RIGHT" then
            TurboFaceDB.warriorOverpowerPosition = "LEFT"
        end
        if tonumber(TurboFaceDB.warriorOverpowerSize) == 24 then
            TurboFaceDB.warriorOverpowerSize = 20
        end
        TurboFaceDB.__migrations.warriorOverpowerLeft20 = true
    end

    -- Validate live color tables only. Retired nameplate palette fields are
    -- pruned above and must never be recreated by normalization.
    local colorKeys = {
        "netWorthColor", "barBorderColor", "taggedIndicatorColor",
        "dotPredictionColor", "dotPredictionLethalColor",
        "healPredictionColor", "healPredictionOwnColor",
        "healPredictionHotColor", "healPredictionOwnHotColor",
    }
    for _, key in ipairs(colorKeys) do
        if type(TurboFaceDB[key]) ~= "table" or not TurboFaceDB[key].r then
            TurboFaceDB[key] = DeepCopy(ns.defaults[key])
        end
    end

    -- Cap the NPC title cache (rebuilds cheaply via tooltip scans)
    local n = 0
    for _ in pairs(TurboFaceCacheDB.npcTitles) do n = n + 1 end
    if n > 500 then
        for k in pairs(TurboFaceCacheDB.npcTitles) do TurboFaceCacheDB.npcTitles[k] = nil end
    end

    ns:UpdateSharedColors()

    if ns.UpdateDBCache then ns:UpdateDBCache() end
end