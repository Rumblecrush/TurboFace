local _, ns = ...

-- =============================================================================
-- DEFAULTS
-- =============================================================================

ns.defaults = {
    -- =========================================================================
    -- MODULE MASTER TOGGLES
    -- One opt-out switch per user-facing feature family, plus per-element
    -- children where a family is meaningfully separable (the five unit frames).
    --
    -- Contract:
    --   * These flags gate FEATURE ACTIVATION, not cosmetics. A disabled family
    --     must leave Blizzard's own frame/behavior untouched -- TurboFace simply
    --     never applies its styling, hooks, or drivers.
    --   * Because TurboFace restyles PROTECTED Blizzard frames in place, a
    --     toggle change is only guaranteed clean across a UI reload. OptionsGUI
    --     prompts for /reload on every master toggle, matching the established
    --     profile-apply reload boundary.
    --   * Every gate must be read through ns.ModuleEnabled(), never indexed
    --     directly, so a corrupt or partially-migrated DB defaults to ENABLED
    --     rather than silently disabling the addon.
    -- =========================================================================
    modules = {
        unitframes = {
            enabled = true,
            player  = true,
            target  = true,
            tot     = true,   -- target of target
            party   = true,
            pet     = true,
        },
        nameplates      = { enabled = true },
        auras           = { enabled = true, tot = true, party = true, pet = true },
        hotbarPower     = { enabled = false },  -- Hotbar Power Overlay (action-button cost overlay + counter)
        playerTicks     = { enabled = true },   -- Player Bar Tick Markers; independent of Unit Frames styling
        swingTimers     = { enabled = true },   -- standalone-capable melee/ranged swing rows
        castBars        = { enabled = true },   -- standalone-capable player/target cast rows
        class           = { enabled = true },
        -- Plus has NO master toggle; each section gates itself. `enabled` stays
        -- true so ns.ModuleEnabled("plus", section) falls through to the element.
        plus = {
            enabled = true,
            automation = false, social = false, interface = true, minimap = false,
            chat = false, system = true, flightBar = true,
            map = true,
        },
    },

    -- Warrior: Overpower nameplate indicator after an enemy dodges your attack
    warriorOverpowerIndicator = true,
    warriorOverpowerSize      = 20,
    warriorOverpowerDuration  = 5,
    warriorOverpowerPosition  = "LEFT", -- LEFT | RIGHT | TOP | BOTTOM
    warriorOverpowerShowTimer = true,
    warriorOverpowerSwipe     = true,
    warriorOverpowerMargin    = 4,
    warriorOverpowerOffsetX   = 0,
    warriorOverpowerOffsetY   = 0,
    -- Hunter Counterattack: same shape as the Warrior block above, resolved by
    -- class in Nameplates.lua into the shared ns.c_reactive* cache.
    hunterCounterattackIndicator = true,
    hunterCounterattackSize      = 20,
    hunterCounterattackDuration  = 5,
    hunterCounterattackPosition  = "LEFT",
    hunterCounterattackShowTimer = true,
    hunterCounterattackSwipe     = true,
    hunterCounterattackMargin    = 4,
    hunterCounterattackOffsetX   = 0,
    hunterCounterattackOffsetY   = 0,

    -- Class-owned additive text (reactive windows / reminder labels).
    classFont      = "Blizzard Default",
    classTextStyle = "SHADOW",

    -- Druid: extra mana bar under the player power bar while in Bear/Cat form
    druidPowerBarEnabled    = true,
    druidPowerBarStatusText = false,
    druidPowerBarFont       = "Blizzard Narrow",
    druidPowerBarTextStyle  = "OUTLINE",
    druidPowerBarTextSize   = 11,
    druidPowerBarTextFormat = "current-max",
    druidPowerBarTexture    = "Blizzard",

    -- Class buff reminders (ClassBuffs.lua): glowing icon while a self-buff is down
    classBuffEnabled       = true,
    classBuffOnlyInCombat  = false,
    classBuffIconSize      = 40,
    classBuffSpacing       = 6,
    classBuffWarnSeconds   = 0,      -- also remind when remaining <= this (0 = only when fully missing)
    classBuffGrowth        = "UP",   -- RIGHT | LEFT | UP | DOWN
    classBuffPulse         = true,
    -- per-buff toggles (Warrior)
    classBuffRevenge       = true,   -- Warrior: reactive window after block/dodge/parry
    classBuffRiposte       = true,   -- Rogue: reactive window after a parry
    classBuffDemonArmor    = true,   -- Warlock: Demon Skin / Demon Armor line
    classBuffBattleShout   = true,
    classBuffBlessing      = true,   -- Paladin: any Blessing satisfies it
    classBuffSeal          = true,   -- Paladin: any Seal satisfies it
    -- On by default: seals last 30s, so out of combat the reminder would
    -- otherwise sit on screen permanently.
    classBuffSealOnlyInCombat = true,
    classBuffAura          = true,   -- Paladin: any Aura satisfies it
    classBuffFortitude     = true,   -- Priest: PW:Fortitude / Prayer of Fortitude
    classBuffInnerFire     = true,
    classBuffDivineSpirit  = true,   -- Priest: Divine Spirit / Prayer of Spirit
    -- Off by default: Fear Ward is consumed by the first fear rather than
    -- expiring, and Shadow Protection is situational.
    classBuffFearWard      = false,
    classBuffShadowProtection = false,
    classBuffMageClearcasting = true,   -- Mage: Arcane Concentration proc
    classBuffAspect        = true,   -- Hunter: any Aspect satisfies it
    classBuffTrueshotAura  = true,   -- Hunter: Marksmanship talent
    classBuffMongooseBite  = true,   -- Hunter: reactive window after a dodge
    classBuffFeedPet       = true,   -- Hunter: reminder while pet is Content or Unhappy
    -- per-buff toggles (Shaman)
    classBuffLightningShield = true,
    classBuffWeaponMH      = true,
    classBuffClearcasting  = true,   -- Shaman: Elemental Focus proc (shows while ACTIVE)

    -- Hearthstone bind-location display (movable via token "Hearthstone").
    -- Timer and one-shot innkeeper auto-bind are independently optional so the
    -- base bind-location readout can stay enabled without either helper.
    hearthEnabled         = false,
    hearthTimerEnabled    = true,
    hearthAutoBindEnabled = true,
    hearthFont             = "Blizzard Default",
    hearthTextStyle        = "SHADOW",
    hearthFontSize         = 12,

    -- Presentation hook for the optional UnstuckSkips addon. Target selection
    -- remains owned by that addon; the estimated service cooldown is per-char.
    unstuckSkipVisualEnabled = false,
    unstuckSkipFont           = "Blizzard Default",
    unstuckSkipTextStyle      = "SHADOW",
    unstuckSkipFontSize       = 12,

    -- Hearthstone batching. Off by default: it temporarily raises maxfps and
    -- only pays off for players who deliberately use the technique.
    -- hearthBatchLead is the starting lead in seconds; the live value is
    -- calibrated per character in TurboFaceCharDB.hearthBatch.
    hearthBatchEnabled = false,
    -- A floor, not a cap: applied only while the cast runs, and only when the
    -- player's existing maxfps is lower. Uncapped clients are left alone.
    hearthBatchFPS     = 300,
    hearthBatchLead    = 0.006,
    hearthBatchVerbose = true,
    -- Show the estimated batch success chance next to the FPS counter.
    hearthBatchOnFPS   = true,

    -- Standalone FPS HUD. The Movers entry owns placement/hide/click-through;
    -- this root gate owns whether the feature exists at all.
    fpsCounterEnabled = false,

    -- DoT prediction: projected damage-over-time damage drawn inside the health
    -- fill. The engine learns tick size/timing empirically; see Combat/DotPrediction.lua.
    dotPredictionEnabled     = true,
    dotPredictionNameplates  = true,
    dotPredictionUnitFrames  = true,
    -- Light purple while the target survives the DoTs; deep purple once the
    -- projection says they do not. Retuned from the old { 0.6, 0.3, 0.9 } in
    -- DB v36 so the two states read as clearly different.
    dotPredictionColor       = { r = 0.847, g = 0.706, b = 0.973 },
    dotPredictionLethalColor = { r = 0.35, g = 0.14, b = 0.35 },
    -- Stored as a 0-1 fraction, shown as a percentage by the slider (isPct).
    -- Party/dungeon only (party1-4 + pets); raid tokens are excluded, see
    -- the note in Combat/DotPrediction.lua.
    dotPredictionIncludeParty = true,
    dotPredictionAlpha       = 0.75,

    -- Heal prediction: Blizzard-native direct incoming heals plus ONE next HoT
    -- tick per active periodic heal. The renderer lives in UnitFrames/UnitFrames.lua.
    healPredictionEnabled      = true,
    healPredictionPlayer       = true,
    healPredictionTarget       = true,
    healPredictionToT          = true,
    healPredictionPet          = true,
    healPredictionParty        = true,
    healPredictionHots         = true,
    healPredictionSeparateOwn  = true,
    healPredictionSeparateHots = true,
    healPredictionCasterTint   = false,
    healPredictionColor        = { r = 0.20, g = 0.90, b = 0.30 },
    healPredictionOwnColor     = { r = 0.20, g = 0.80, b = 1.00 },
    healPredictionHotColor     = { r = 0.65, g = 1.00, b = 0.30 },
    healPredictionOwnHotColor  = { r = 0.35, g = 1.00, b = 0.85 },
    healPredictionAlpha        = 0.65,
    -- Fraction beyond the normal 100% bar width allowed for visible overheal.
    healPredictionOverheal     = 0,
    healPredictionMaxSegments  = 6,
    healPredictionMinPercent   = 0,

    -- Lightweight Combat Meter: local CLEU-only accounting intended for
    -- leveling and 5-player content. No addon comms or raid analytics.
    combatMeterEnabled     = false,
    combatMeterView        = "current", -- "current" | "overall"
    combatMeterMetric      = "damage",  -- "damage" | "healing"
    combatMeterWidth       = 260,
    combatMeterBarAlpha    = 0.42,
    combatMeterMergeWindow = 1.5,
    combatMeterRefresh     = 0.25,
    combatMeterFont        = "Blizzard Default",
    combatMeterTextStyle   = "SHADOW",

    -- Standalone swing/cast rows use feature-local text presentation even
    -- when baked into TurboFace unit-frame artwork.
    swingTimersFont             = "Blizzard Default",
    swingTimersTextStyle        = "OUTLINE",
    swingTimersStandaloneWidth  = 160,
    swingTimersStandaloneHeight = 15,
    castBarsFont                = "Blizzard Default",
    castBarsTextStyle           = "OUTLINE",
    castBarsStandaloneWidth     = 160,
    castBarsStandaloneHeight    = 15,

    -- Enemy leash countdown: independent of Nameplates/UnitFrames, but the
    -- floating display is intentionally mover-dependent.
    leashTimerEnabled      = false,
    leashTimerFont         = "Blizzard Default",
    leashTimerTextStyle    = "SHADOW",
    leashTimerFontSize     = 12,

    -- Independent PlayerFrame DPS/HPS badge.  show/color settings remain under
    -- unitframes below for profile compatibility; font size is standalone.
    playerDPSBadgeFontSize = 9,

    -- Skill tracker HUD (movable via token "SkillTracker")
    skillTrackerEnabled     = false,
    skillTrackerProfessions = true,
    skillTrackerSecondary   = true,
    skillTrackerWeapons     = true,
    skillTrackerEquippedWeaponsOnly = false,
    skillTrackerFont        = "Blizzard Default",
    skillTrackerTextStyle   = "SHADOW",
    skillTrackerFontSize    = 12,
    skillTrackerIconSize    = 14,
    skillTrackerSpacing     = 2,
    classBuffMarkOfTheWild = true,
    classBuffThorns        = true,
    classBuffArcaneIntellect = true,
    classBuffMageArmor     = true,
    classBuffTalentPoints  = true,   -- class-agnostic: unspent talent points (icon 132222)

    -- TurboFace augments Blizzard's 1.15.9 nameplate chassis. Only independent
    -- information layers and the explicit reversible layout/selection CVars
    -- remain configurable here; native health, cast, and threat presentation
    -- stay under Blizzard/user control.
    -- Nameplate combo dots. Blizzard owns the target-frame combo display.
    showComboPoints = true,

    bubbleNameplates = {
        -- Blizzard 1.15.9 owns rarity-icon visibility, classification, atlas,
        -- and scale. TurboFace may move only the existing PvE rarity texture
        -- from its native left-side parent to the right edge of the chassis.
        rarityIconRight = true,
        -- Blizzard owns the health-text values and formatting. TurboFace may
        -- optionally re-anchor those native restricted FontStrings. The second
        -- toggle chooses the full Blizzard plate chassis instead of the
        -- shortened health-fill StatusBar as the centering reference.
        centerHealthText  = true,
        centerHealthTextOnNameplate = true,
        -- Classic Era's native SLUG name FontString can ignore its configured
        -- shadow. TurboFace may add an independent black glyph underlay behind
        -- Blizzard-owned NPC and player names as a visual workaround.
        nameTextShadow = true,
        -- Native NPC power presentation. When enabled, the custom resource
        -- overlays the bottom of Blizzard's health bar. Disabled means the
        -- nameplate power subsystem is fully dormant.
        powerBarOverlap   = false,
        -- Embedded-mode height as a fraction of the live Blizzard health-bar
        -- height. UI range: 10%..40%.
        powerBarHeightPct = 0.30,
        -- Friendly NPC service/profession glyph. Independent of friendly
        -- name/title-only presentation; always anchors immediately left of the
        -- visible Blizzard NPC name.
        jobIcon = true,
        friendlyNPCNameTitleOnly = true,
        friendlyPlayerDamagedOnly = true,
        -- Friendly NPCs render name-only until damaged, then show the full
        -- plate with health. Aimed at escort quests.
        friendlyNPCDamagedOnly = true,
        -- Independent hostile combat-information surfaces. Threat Number owns
        -- only quantitative threat presentation; Nameplate Swing Timer owns the
        -- full-chassis enemy attack timing strip.
        threatNumber      = false,
        -- Text-only hostile threat presentation. Keep the current 6px visual
        -- as the default; the Nameplates tab exposes a live 6..16px slider.
        threatTextFontSize = 6,
        swingTimer        = true,
        -- Blizzard nameplate layout/selection CVars. TurboFace owns these only
        -- while the Nameplates module is active and restores the captured user
        -- values when the module releases ownership.
        -- Overlap values are plate-size multipliers; alpha values are 0..1.
        overlapV          = 1.00,
        overlapH          = 1.35,
        selectedScale     = 1.00,
        selectedAlpha     = 1.00,
        notSelectedAlpha  = 0.80,
        muteAggroSounds   = false,
        gainVolume        = 1.0,
        lossVolume        = 1.0,
    },


    -- Quest indicators
    showQuestNPCs       = true,
    showQuestObjectives = true,
    questIconScale      = 100,
    questIconAnchor     = "LEFT",
    questIconX          = 0,
    questIconY          = 0,

    -- Shared bar-border + tagged-mob indicator colors (unit frames, swing
    -- timers, castbars, nanShield borders; nameplate + UF tagged grey)
    barBorderColor       = { r = 200/255, g = 200/255, b = 200/255 },
    taggedIndicatorColor = {
        r = 0.2156862745098039,
        g = 0.2156862745098039,
        b = 0.2156862745098039,
    },

    -- Aura tracking
    auras = {
        -- "BLIZZARD" = rounded debuff ring matching target/ToT debuffs,
        -- "PIXEL" = the original 1px square border.
        borderStyle          = "BLIZZARD",
        font                 = "Blizzard Default",
        textStyle            = "OUTLINE",
        showDebuffs          = true,
        maxDebuffs           = 6,
        debuffIconWidth      = 26,
        debuffIconHeight     = 16,
        debuffFontSize       = 11,
        debuffStackFontSize  = 11,
        debuffXOffset        = 0,
        debuffYOffset        = 3,
        debuffBorderMode     = "COLOR_CODED",
        debuffDurationAnchor = "BOTTOM",
        debuffSortMode       = "LEAST_TIME",
        showBuffs            = true,
        buffFilterMode       = "ONLY_DISPELLABLE",
        maxBuffs             = 4,
        buffIconWidth        = 26,
        buffIconHeight       = 18,
        buffFontSize         = 11,
        buffStackFontSize    = 10,
        buffXOffset          = 0,
        buffYOffset          = 0,
        -- Target-of-Target debuffs are independently aura-owned. This scale is
        -- migrated from the historical shared target-debuff scale in DB v48.
        totDebuffScale       = 1,
        buffGrowDirection    = "CENTER",
        buffDurationAnchor   = "CENTER",
        buffStackAnchor      = "TOPRIGHT",
        buffIconSpacing      = 2,
        buffMinDuration      = 0,
        buffMaxDuration      = 600,
        buffBorderMode       = "COLOR_CODED",
        buffSortMode         = "MOST_RECENT",
        minDuration          = 0,
        maxDuration          = 0,
        growDirection        = "CENTER",
        iconSpacing          = 2,
        debuffBorderColor    = { r=0.8, g=0,   b=0   },
        buffBorderColor      = { r=0.2, g=0.8, b=0.2 },
        blacklist            = {},
        whitelist            = {},

        -- Blizzard Party/Pet-frame aura augmentation. These surfaces are Aura
        -- children, independent of whether TurboFace restyles the underlying
        -- unit frames. Party and Pet share sizing/layout settings; class-only
        -- reminders apply only to Party.
        partyBuffsEnabled          = true,
        partyClassRemindersEnabled = true,
        partyBuffIconSize          = 18,
        partyClassBuffIconSize     = 36,
        partyClassBuffWarnSeconds  = 30,
        partyBuffMax               = 8,
        partyBuffsPerRow           = 4,
    },

    -- TurboDebuffs
    turboDebuffs = {
        enabled           = false,
        showFriendly      = false,
        size              = 32,
        anchor            = "RIGHT",
        xOffset           = 0,
        yOffset           = 0,
        timerSize         = 22,
        font              = "Blizzard Default",
        textStyle         = "OUTLINE",
        immunities        = true,
        cc                = true,
        silence           = true,
        interrupts        = true,
        roots             = true,
        disarm            = true,
        buffs_defensive   = true,
        buffs_offensive   = true,
        buffs_other       = true,
        snare             = true,
        priority = {
            immunities      = 80,
            cc              = 70,
            silence         = 60,
            roots           = 55,
            disarm          = 50,
            buffs_defensive = 45,
            buffs_offensive = 40,
            buffs_other     = 35,
            snare           = 30,
            interrupts      = 25,
        },
    },

    -- =========================================================================
    -- UNIT FRAMES (EasyFrames BSD lineage; see THIRD_PARTY_NOTICES.md)
    -- =========================================================================
    unitframes = {
        -- General
        healthTexture       = "Blizzard",   -- HP bar fill texture
        manaTexture         = "Blizzard",   -- mana/power bar fill texture
        attackTexture       = "Blizzard Raid Bar", -- swing/attack bar fill texture
        castTexture         = "Blizzard Raid Bar", -- cast bar fill texture
        hideBlizzardPlayerCastbar = true, -- global cast-timer presentation preference (legacy storage path)
        embedCombatTimers   = false,       -- bake player/target swing+cast rows into enabled TurboFace unit frames
        -- Typography is split by semantic role. Names mirror Blizzard's
        -- normal unit-name presentation; numeric/bar values use the narrow
        -- outlined style traditionally associated with compact status text.
        nameFont            = "Blizzard Default",
        nameTextStyle       = "SHADOW",
        nameFontSize        = 10,          -- Player/Target unit-name text size
        barFont             = "Blizzard Narrow",
        barTextStyle        = "OUTLINE",
        barFontSize         = 12,          -- Player/Target health/power/shield value size
        -- Per-unit value text. Every visible bar has its own setting.
        playerHealthFormat  = "percent-current-blizzard",
        playerPowerFormat   = "percent-current-blizzard",
        targetHealthFormat  = "current-max-pct",
        targetPowerFormat   = "percent",
        petHealthFormat     = "current-max-pct",
        petPowerFormat      = "percent-current-blizzard",
        partyHealthFormat   = "current-max-pct",
        partyPowerFormat    = "percent",
        totHealthFormat     = "percent",
        totPowerFormat      = "percent",


        -- Stack spacing
        barSpacing          = 2,           -- gap between stacked bars -- LOCKED (forced in LoadVariables; part of the frozen border style)

        -- Health coloring
        classColored             = true,
        colorBasedOnCurrentHealth = false,
        playerHealthColor   = { 0.15, 0.65, 0.15 },  -- static player HP color (user-chosen)
        friendlyColor       = { 0, 1, 0 },
        enemyColor          = { 1, 0, 0 },

        -- Player
        playerScale         = 1,
        playerNameColor     = { 1, 0.82, 0 },
        showHitIndicator    = true,
        showPlayerDPS       = true,                -- independent DPS/HPS badge beside Blizzard player level text
        -- Badge text is colored by the meter's selected metric, so the two live
        -- side by side rather than one shared color.
        playerDPSColor      = { 1, 0.35, 0.35 },   -- light red, RGB 255/89/89 (damage)
        playerHPSColor      = { 0, 1, 0.498 },     -- spring green, RGB 0/255/127 (healing)

        -- Shield Bars (legacy nanShield* keys retained for profile compatibility)
        nanShieldEnabled    = true,
        nanShieldHeight     = 8,
        nanShieldShowText   = true,    -- show the remaining-absorb number(s) on the bar
        nanShieldPerSection = true,    -- per-school number in each block vs. one combined total
        nanShieldFixRemove  = true,    -- a dropped shield leaves the bar's total immediately (re-scales)
        nanShieldFont       = "Blizzard Narrow",
        nanShieldTextStyle  = "OUTLINE",
        nanShieldFontSize   = 11,

        -- Target
        targetScale         = 1,
        targetNameColor     = { 1, 0.82, 0 },
        showTargetName      = true,
        showToT             = true,
        totBarFontSize      = 9,    -- ToT health/power value text size
        totNameFontSize     = 8,
        totNameAboveBars    = false, -- Blizzard-style default is below HP/power; optional above layout
        reverseTargetHP     = false,
        showTargetXP        = true,                  -- per-kill XP estimate, top-right of target HP bar
        targetXPPerHP       = false,                 -- show XP / max-health instead of raw XP
        targetXPColor       = { 0.580, 0.0, 0.545 }, -- RGB 148,0,139 (magenta)

        -- Pet
        petScale            = 1,
        petNameColor        = { 1, 0.82, 0 },
        showPetName         = true,
        petNameFontSize     = 8,
        petNameAboveBars    = false, -- below HP/power by default; optional legacy above layout
        petBarFontSize      = 8,

        -- Party
        partyScale           = 1,
        partyNameColor       = { 1, 0.82, 0 },
        showPartyNames       = true,
        partyNameFontSize    = 8,
        partyBarFontSize     = 8,
    },

    -- =========================================================================
    -- MOVERS (Classic Era-only, TurboFace-native)
    -- =========================================================================
    movers = {
        enabled = true,
        locked = true,
        snapToGrid = true,
        snapSize = 5,
        showGrid = true,
        gridSize = 32,
        gridAlpha = 0.14,
        showCoordinates = true,
        showNudgeControls = true,
        nudgeStep = 1,
        auraLayout = true,
        activeElement = "LootFrame",
        aura = {
            -- Player aura layout removed: Edit Mode places BuffFrame/DebuffFrame.
            spacingX = 6,
            spacingY = 10,
            targetPerRow = 8,
            targetBuffGrowth = "RIGHT_DOWN",
            targetDebuffGrowth = "RIGHT_DOWN",
            -- ToT has exactly four debuff slots; runtime layout is fixed to one
            -- row of four, so there is no persisted per-row setting.
            totDebuffGrowth = "RIGHT_DOWN",
        },
        elements = {
            -- Blizzard unit-frame / action-bar / durability movers removed:
            -- HUD Edit Mode (1.15.9+) owns those. TurboFace retains movers for
            -- its own elements, Target of Target, and stock loot/group-roll
            -- systems that Edit Mode cannot position independently.
            TargetFrameToT    = { enabled = false, hidden = false, clickThrough = false },
            MinimapMail       = { enabled = false, hidden = false, clickThrough = false },
            MinimapClock      = { enabled = false, hidden = false, clickThrough = false },
            MinimapLFG        = { enabled = false, hidden = false, clickThrough = false },
            SkillTracker      = { enabled = true, hidden = false, clickThrough = false },
            TargetBuffs       = { enabled = false, hidden = false, clickThrough = false },
            TargetDebuffs     = { enabled = false, hidden = false, clickThrough = false },
            ToTDebuffs        = { enabled = false, hidden = false, clickThrough = false },
            ExperienceBar     = { enabled = true, hidden = false, clickThrough = false },
            LatencyBar        = { enabled = false, hidden = false, clickThrough = false },
            QuestTracker      = { enabled = true, hidden = false, clickThrough = false },
            FPSCounter        = { enabled = true, hidden = false, clickThrough = true },
            BagSlots          = { enabled = true, hidden = false, clickThrough = true },
            GameTooltip       = { enabled = false, hidden = false, clickThrough = false },
            LootFrame         = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = 290,
            },
            BlizzardLootFrame = { enabled = false, hidden = false, clickThrough = false },
            GroupLootRolls    = { enabled = false, hidden = false, clickThrough = false },
            NetWorth          = {
                enabled = true, hidden = false, clickThrough = true,
                point = "CENTER", relativePoint = "CENTER", x = 685, y = -410,
            },
            Hearthstone       = { enabled = true, hidden = false, clickThrough = true },
            UnstuckSkips      = { enabled = true, hidden = false, clickThrough = false },
            TrackingIcon      = { enabled = true, hidden = false, clickThrough = true },
            ClassBuffBar      = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -160,
            },
            DruidPowerBar     = { enabled = true },
            FlightBar         = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = 320,
            },
            CombatMeter       = { enabled = true, hidden = false, clickThrough = false },
            LeashTimer        = { enabled = true, hidden = false, clickThrough = true },
            SpeedrunSplits    = { enabled = true, hidden = false, clickThrough = false },
            GroceryButton     = { enabled = true, hidden = false, clickThrough = false },
            PlayerMainSwingTimer = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -268,
            },
            PlayerOffhandSwingTimer = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -285,
            },
            PlayerRangedSwingTimer = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -251,
            },
            PlayerCastBar = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -234,
            },
            TargetSwingTimer = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -217,
            },
            TargetCastBar = {
                enabled = true, hidden = false, clickThrough = false,
                point = "CENTER", relativePoint = "CENTER", x = 0, y = -200,
            },
        },
    },

    -- =========================================================================
    -- PLUS (TurboFace utility and social features)
    -- =========================================================================
    plus = {
        -- Automation
        automateGossip       = false,
        autoQuestAccept      = false,
        autoQuestTurnIn      = false,
        acceptSummon         = false,
        -- Spirit healer: selects "return to life" and confirms the sickness
        -- warning. Destructive (durability + Resurrection Sickness), so off by
        -- default; hold shift at either step to cancel.
        automateSpiritHealer = false,
        acceptRes            = false,
        acceptResNoCombat    = true,
        releasePvP           = false,
        releaseNoAlterac     = false,
        releaseDelay         = 200,    -- ms before auto-release (shift cancels)
        autoRepair           = false,
        autoRepairSummary    = true,
        -- Social
        blockDuels           = false,
        blockPartyInvites    = false,
        blockFriendRequests  = false,
        blockSharedQuests    = false,
        acceptPartyFriends   = false,
        friendlyGuild        = true,   -- guild members count as friends
        inviteFromWhisper    = false,
        inviteFriendsOnly    = true,
        inviteKeyword        = "inv",
        -- Interface tweaks (reload-applied)
        hideHitIndicators    = false,
        hideZoneText         = false,
        hideKeybindText      = false,
        hideMacroText        = false,
        hideRaidGroupLabels  = false,
        showRaidToggle       = false,
        enhanceQuestLevels   = true,
        enhanceQuestDifficulty = true,
        hideMiniZoomBtns     = false,
        hideMiniClock        = false,
        hideMiniDayNight     = false,
        hideMiniZoneText     = false,
        hideMiniLFG          = false,
        -- "round" (Blizzard default) or "square". Replaced the old
        -- squareMinimap boolean in DB v34; a third "torn" shape existed
        -- briefly and was removed in v35.
        minimapShape         = "round",
        minimapBorderTexture = "Blizzard Dark",
        -- Manual nudge on top of the per-texture inset, for LSM borders
        -- registered by other addons. 0 = use the texture's own value.
        minimapBorderOffset  = 0,
        -- Zone text point size; nil/0 falls back to Blizzard's own height.
        minimapZoneTextSize  = 12,
        minimapZoneBanner    = false,
        minimapSize          = 140,    -- square minimap size (140 = 100%)
        minimapBorderWidth   = 3,
        -- World map (MapTweaks.lua; reload-applied except the zoom ceiling).
        -- mapMovable only calls SetMovable(true); Blizzard still owns the drag,
        -- the title dropdown's lock state and the saved position.
        mapMovable           = true,
        mapEnhancedZoom      = true,
        mapZoomMax           = 2,      -- zoom ceiling multiplier, 1 = Blizzard
        mapRememberZoom      = false,
        -- Chat (ChatTweaks.lua; reload-applied)
        unclampChat          = false,
        noChatFade           = false,
        noChatButtons        = false,
        noCombatLogTab       = false,
        chatTextOutline      = false,
        -- System tweaks
        noScreenGlow         = false,
        noScreenEffects      = false,
        setWeatherDensity    = false,
        weatherLevel         = 3,      -- 0..3 (Very Low..High)
        maxCameraZoom        = true,
        noRestedEmotes       = false,
        keepAudioSynced      = false,
        noBagAutomation      = false,
        noConfirmLoot        = false,
        fasterLooting        = true,
        showVendorPrice      = true,
        -- Flight bar (category-enabled; presentation is fixed)
        flightBarWidth       = 230,
        flightBarScale       = 1,
    },

    -- =========================================================================
    -- EXPERIENCE BAR (TurboFace XP/session bar)
    -- =========================================================================
    experienceBar = {
        enabled = false,
        showAtMaxLevel = false,
        hideBlizzardXPBar = true,
        resetSessionOnReload = false,
        showIncompleteQuestBar = true,
        showXPPerHourText = true,
        showQuestRestedText = true,
        showLevelTimeText = true,
        showSessionTimeText = true,
        textBlockAbove = false,
        showInsideLevelText = true,
        showInsidePercentText = true,
        width = 420,
        height = 18,
        scale = 1,
        fontSize = 11,
        font = "Blizzard Default",
        textStyle = "SHADOW",
        texture = "Minimalist",
        colorXP = { r = 0.18, g = 0.38, b = 0.92 },
        colorComplete = { r = 1.00, g = 0.58, b = 0.00 },
        colorIncomplete = { r = 0.85, g = 0.36, b = 0.00 },
        colorRested = { r = 0.31, g = 0.56, b = 1.00 },
    },

    -- Account-wide race/class PBs live in TurboFaceSpeedrunDB; current-run
    -- checkpoints live in TurboFaceSpeedrunCharDB and never enter profiles.
    speedrunSplits = {
        enabled = false,
        showPartials = true,
        showNext = true,
        showDelta = true,
        colorComparisons = true,
        showDays = false,
        visibleRows = 12,
        autoSaveLevel = 60,
        font = "Blizzard Default",
        textStyle = "SHADOW",
        fontSize = 12,
        scale = 1,
    },

    -- Lvl1 Quick Setup: account-wide class setup profiles live separately in
    -- TurboFaceProfilesDB.quickSetup; GUID/bootstrap completion is per-character
    -- in TurboFaceCharDB.quickSetup. The automatic restore toggle is intentionally
    -- off by default because applying a setup rewrites macros, keybinds, and action bars.
    quickSetup = {
        enabled = false,
        autoSkipCinematic = true,
    },

    -- =========================================================================
    -- LOOT FRAME (lean TurboFace loot toast frame)
    -- =========================================================================
    lootFrame = {
        enabled = true,
        showMoney = true,
        showVendorValue = true,
        combineDuplicates = true,
        showStackCount = true,
        duration = 7,
        maxItems = 6,
        width = 220,
        rowHeight = 32,
        spacing = 0,
        scale = 1,
        fontSize = 12,
        font = "Blizzard Default",
        textStyle = "SHADOW",
        backgroundAlpha = 0.62,
    },


    -- =========================================================================
    -- POWER / MissingPower-style overlays and tick markers
    -- =========================================================================
    power = {
        enabled = true,

        -- Hotbar counter text is independently styled from regen tick popups.
        font = "Blizzard Default",
        textStyle = "SHADOW",
        tickFont = "Blizzard Default",
        tickTextStyle = "SHADOW",

        -- Action button power-cost overlay
        actionOverlayEnabled = true,
        showActionCounter = true,
        overlayAlpha = 0.55,
        fontSize = 12,
        decimals = 1,
        displayIfLowerThan = 10,
        textAnchor = "CENTER",
        textOffsetX = 0,
        textOffsetY = 0,
        useCustomOverlayColor = false,
        overlayColor = { r = 1.00, g = 0.00, b = 0.00, a = 1.00 },
        useCustomCounterColor = false,
        counterColor = { r = 1.00, g = 1.00, b = 1.00, a = 0.95 },

        -- Player power/health bar tick markers
        manaTick = true,
        manaTickBackground = true,
        fiveSecondRule = true,
        fiveSecondRuleBackground = true,
        energyTick = true,
        energyTickBackground = true,
        rageDecay = true,
        rageDecayBackground = true,
        healthRegen = true,
        healthRegenBackground = true,
        -- Regen "+X" tick-amount popups (companion to the markers above): a
        -- resource-colored number that pops at the tick marker on each regen
        -- tick. healthTickAmount = HP bar; powerTickAmount = power bar (and the
        -- druid mana bar while shifted).
        healthTickAmount = false,
        powerTickAmount = false,
        tickAmountSize = 16,
        tickAmountOffsetX = 78,
        tickAmountOffsetY = 0,
        tickWidth = 1,
        tickBorderWidth = 3,
        tickColor = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
        tickBorderColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.85 },
        fiveSecondRuleColor = { r = 0.45, g = 0.75, b = 1.00, a = 1.00 },
        fiveSecondRuleBorderColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.85 },
        energyTickColor = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
        energyTickBorderColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.85 },
        rageDecayColor = { r = 1.00, g = 0.35, b = 0.35, a = 1.00 },
        rageDecayBorderColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.85 },
        healthRegenColor = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
        healthRegenBorderColor = { r = 0.00, g = 0.00, b = 0.00, a = 0.85 },
    },

    -- =========================================================================
    -- SPEEDRUN: Junk & Inventory (InventoryManager.lua + Inventory/Bank.lua).
    -- Grays are junk by default; keybinds assign mutually-exclusive Junk,
    -- Useful, or Bank state, destroy the cheapest junk, or immediately destroy
    -- the hovered bag item. Bank-marked stacks auto-deposit on bank open, and
    -- optional Ctrl+Right Click withdraws all matching bank stacks. Configurable
    -- modifier+right-click shortcuts cover combinations Blizzard's binding UI
    -- does not reliably capture. discardPile lives in
    -- TurboFaceCharDB (per-character saved variable, not listed here).
    -- =========================================================================
    invEnabled                    = true,   -- master enable for Junk/Useful/Bank item management
    invAutoSell                   = true,   -- auto-sell junk when a merchant opens
    invShowJunkIcon               = true,   -- Junk coin / Bank banker overlays in Blizzard and Baganator views
    invMarkMouseShortcut          = "CTRL-RIGHT", -- optional modifier + right-click Junk/Useful/Bank cycle
    invBankWithdrawAll            = true,   -- Ctrl+Right Click a live bank stack to withdraw all matching item IDs
    invDeleteHoveredEnabled       = false,  -- safety gate: allow destructive hovered-item deletion
    invDeleteHoveredMouseShortcut = "NONE", -- optional backup modifier + right-click delete shortcut

    -- =========================================================================
    -- SPEEDRUN: Grocery List (Grocery.lua). A standing shopping list of vendor
    -- consumables; the next merchant that stocks a queued item sells it to you
    -- automatically and the line clears. The QUEUE itself is per-character and
    -- lives in TurboFaceCharDB.grocery (not listed here) -- what a mage keeps
    -- stocked is not what a warrior keeps stocked. Only the launcher button is
    -- mover-dependent; auto-buy runs with Movers disabled.
    -- =========================================================================
    -- =========================================================================
    -- SPEEDRUN: Trainer Spells (Trainer/*). Shows upcoming class-trainer spells,
    -- profession skills and recipes. Bulk captured data lives in its own
    -- SavedVariables (TurboFaceTrainerDB / TurboFaceTrainerCharDB), not here,
    -- so profile exports stay small.
    -- =========================================================================
    trainerEnabled     = true,     -- master enable for the trainer spell list

    groceryEnabled     = false,    -- master enable for the grocery system
    groceryAutoBuy     = true,     -- buy queued items when a merchant opens
    groceryShowButton  = true,     -- floating launcher button (needs Movers)
    groceryChatSummary = true,     -- announce successful purchases in chat
    groceryShowQueue   = true,     -- shopping-list popout attached to the window
    groceryQueueSeen   = false,    -- has the popout auto-opened once already
    groceryBorderMode  = "auto",   -- "auto" | "legacy" | "nineslice" (see Grocery.lua)
    groceryFilterFood   = true,     -- catalog filter: show Food entries
    groceryFilterDrink  = true,     -- catalog filter: show Drink entries
    groceryFilterPotion = true,     -- catalog filter: show Potion entries
    groceryFilterAmmo   = true,     -- catalog filter: show Ammo entries
    groceryFilterUsable = false,    -- hide entries above the player's current level
    groceryFramePoint  = "CENTER", -- list window position (plain dialog memory)
    groceryFrameX      = 0,
    groceryFrameY      = 0,

    -- =========================================================================
    -- PLUS: Minimap tracking icon (MinimapTracker.lua). TurboFace-owned
    -- replacement for Blizzard's minimap tracking indicator; movable via the
    -- TrackingIcon mover.
    -- =========================================================================
    trackerEnabled      = false,  -- master enable for the tracking icon
    trackerHideBlizzard = true,   -- hide Blizzard's MiniMapTracking button
    trackerShowInactive = true,   -- dimmed placeholder when nothing is tracked
    trackerSize         = 20,     -- icon size (px)
    trackerAlpha        = 1,      -- icon opacity
    trackerBorder       = true,   -- shared bar-style border + background

    -- =========================================================================
    -- MISC: Minimap button (MinimapButton.lua). Rides the minimap edge; left-
    -- click opens the config panel, right-click toggles the movers. Angle is
    -- saved so it stays where you drag it. There is deliberately NO enable
    -- key: the button is always on (see MinimapButton.lua for why), so only
    -- the position persists.
    -- =========================================================================
    minimapButtonAngle   = 200,   -- position around the minimap edge (degrees)

    -- =========================================================================
    -- SPEEDRUN: Free Bag Slots display (BagSlots.lua). Shows only the number of
    -- empty slots across the backpack and equipped bags. It is standalone;
    -- Movers can reposition/hide it when enabled, but are not required.
    -- =========================================================================
    bagSlotsEnabled = false,                 -- opt-in

    -- =========================================================================
    -- SPEEDRUN: Net Worth display (your money + vendor value of bag junk, computed
    -- by TurboFace's own InventoryManager). Standalone TurboFace runtime.
    -- Position/hide/click-through are handled by the shared mover framework;
    -- legacy netWorthPoint/X/Y are kept as a one-time fallback for old layouts.
    -- =========================================================================
    netWorthEnabled  = true,
    netWorthLabel    = true,                   -- show "NW:" prefix
    netWorthFont      = "Blizzard Default",
    netWorthTextStyle = "SHADOW",
    netWorthFontSize  = 14,
    netWorthColor    = { r = 1, g = 0.82, b = 0 },  -- label color (gold)
    netWorthPoint    = "CENTER",
    netWorthX        = 0,
    netWorthY        = -220,

    -- =========================================================================
    -- GLOBAL: Aura styling (cooldown swipe + timer text + per-group scale on
    -- player & target buffs/debuffs). Durations via embedded LibClassicDurations.
    -- =========================================================================
    auraEnabled           = true,
    auraShowSwipe         = true,
    auraShowTimer         = true,
    auraTimerSize         = 11,
    -- Player aura icon size removed: Blizzard's Buff/Debuff options own icon
    -- size, padding, and limit on 1.15.9+. TurboFace only styles timers/swipes.
    auraTargetBuffScale   = 1,
    auraTargetDebuffScale = 1,


}

-- Client-only settings are layered onto the portable Classic baseline here.
-- They remain runtime/profile data, but their defaults do not advance the
-- portable dbVersion or fork this entire file.
if ns.Schema and ns.Schema.ApplyClientDefaults then
    ns.Schema:ApplyClientDefaults(ns.defaults)
end