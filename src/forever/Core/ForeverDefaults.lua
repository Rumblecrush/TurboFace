local _, ns = ...

-- Forever-only defaults overlay. Real SavedVariables remain authoritative;
-- these values are used only when a setting has not been stored yet.

local function Copy(value)
    if ns.DeepCopy then return ns.DeepCopy(value) end
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[Copy(key)] = Copy(child) end
    return out
end

local function Overlay(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            Overlay(target[key], value)
        else
            target[key] = Copy(value)
        end
    end
end

local function SetModule(data, family, enabled, children)
    data.modules = type(data.modules) == "table" and data.modules or {}
    local row = { enabled = enabled == true }
    if type(children) == "table" then
        for key, value in pairs(children) do row[key] = value == true end
    end
    data.modules[family] = row
end

local function SetMover(data, name, values)
    data.movers = type(data.movers) == "table" and data.movers or {}
    data.movers.elements = type(data.movers.elements) == "table" and data.movers.elements or {}
    local row = type(data.movers.elements[name]) == "table" and data.movers.elements[name] or {}
    data.movers.elements[name] = row
    for key, value in pairs(values) do row[key] = value end
end

local DISABLED_PLUS_DEFAULTS = {
    "hideHitIndicators", "hideKeybindText", "hideMiniClock",
    "hideMiniDayNight", "hideMiniLFG", "hideMiniZoneText",
    "hideMiniZoomBtns", "hideRaidGroupLabels", "hideZoneText",
    "keepAudioSynced", "minimapZoneBanner", "noBagAutomation",
    "noCombatLogTab", "noConfirmLoot", "noRestedEmotes",
    "noScreenEffects", "noScreenGlow", "setWeatherDensity",
    "showRaidToggle",
}

local function BaseData()
    local profiles = ns.Profiles
    local base = profiles and profiles.GetPreset and profiles:GetPreset("Rumblecrush's Preset")
    return base and type(base.data) == "table" and Copy(base.data) or {}
end

local function BuildData()
    local data = BaseData()

    SetModule(data, "unitframes", false, {
        player = false, target = false, tot = false, party = false, pet = false,
    })
    SetModule(data, "nameplates", true)
    SetModule(data, "auras", false, { tot = false, party = false, pet = false })
    SetModule(data, "hotbarPower", true)
    SetModule(data, "playerTicks", true)
    SetModule(data, "swingTimers", false)
    SetModule(data, "castBars", false)
    SetModule(data, "class", false)
    data.modules.plus = {
        enabled = true, automation = true, social = false, interface = true,
        minimap = false, chat = true, system = true, flightBar = true, map = true,
    }

    data.plus = type(data.plus) == "table" and data.plus or {}
    local plusDefaults = ns.defaults and ns.defaults.plus
    if type(plusDefaults) == "table" then
        for key, defaultValue in pairs(plusDefaults) do
            if type(defaultValue) == "boolean" then data.plus[key] = true end
        end
    end
    for _, key in ipairs(DISABLED_PLUS_DEFAULTS) do data.plus[key] = false end
    data.plus.weatherLevel = 1

    data.dotPredictionEnabled = false
    data.healPredictionEnabled = false
    data.druidPowerBarEnabled = false
    data.classBuffEnabled = false
    data.combatMeterEnabled = false
    data.trainerEnabled = true
    data.hearthEnabled = true
    data.hearthTimerEnabled = true
    data.hearthAutoBindEnabled = true
    data.hearthBatchEnabled = true
    data.leashTimerEnabled = false
    data.trackerEnabled = false
    data.unstuckSkipVisualEnabled = false
    data.warriorOverpowerIndicator = false
    data.hunterCounterattackIndicator = false
    data.auraEnabled = false

    data.quickSetup = type(data.quickSetup) == "table" and data.quickSetup or {}
    data.quickSetup.enabled = true
    data.groceryEnabled = true
    data.groceryAutoBuy = true
    data.groceryShowButton = true
    data.bagSlotsEnabled = true
    data.netWorthEnabled = true
    data.fpsCounterEnabled = true
    data.talentReminderEnabled = true
    data.lootFrame = type(data.lootFrame) == "table" and data.lootFrame or {}
    data.lootFrame.enabled = true
    data.lootFrame.width = 220
    data.experienceBar = type(data.experienceBar) == "table" and data.experienceBar or {}
    data.experienceBar.enabled = true

    data.combinedBag = {
        point = "RIGHT", relativePoint = "RIGHT",
        x = -22.22224235534668, y = -173.5000305175781,
    }
    data.movers = type(data.movers) == "table" and data.movers or {}
    data.movers.activeElement = "GroceryButton"
    SetMover(data, "BagSlots",       { x = 400,  y = -510 })
    SetMover(data, "ExperienceBar",  { x = -875, y = -220 })
    SetMover(data, "FPSCounter",     { x = -400, y = -510 })
    SetMover(data, "GroceryButton",  { x = 555,  y = -580 })
    SetMover(data, "Hearthstone",    { x = -400, y = -525 })
    SetMover(data, "NetWorth",       { x = 400,  y = -525 })
    SetMover(data, "SpeedrunSplits", { x = -930, y = 495 })
    for _, name in ipairs({
        "BlizzardLootFrame", "GameTooltip", "LatencyBar", "MinimapClock",
        "MinimapLFG", "MinimapMail", "QuestTracker", "TargetBuffs",
        "TargetDebuffs", "TargetFrameToT", "ToTDebuffs",
    }) do
        SetMover(data, name, { enabled = false })
    end

    data.hearthTextStyle = "SHADOW"
    data.netWorthFontSize = 11
    data.unitframes = type(data.unitframes) == "table" and data.unitframes or {}
    data.unitframes.showPlayerDPS = false

    data.showComboPoints = true
    local bubble = type(data.bubbleNameplates) == "table" and data.bubbleNameplates or {}
    data.bubbleNameplates = bubble
    bubble.nameTextShadow = true
    bubble.jobIcon = true
    bubble.friendlyNPCNameTitleOnly = true
    bubble.threatNumber = true
    bubble.threatTextFontSize = tonumber(bubble.threatTextFontSize) or 14
    bubble.swingTimer = true
    bubble.muteAggroSounds = false
    bubble.rarityIconRight = false
    bubble.friendlyPlayerDamagedOnly = false
    bubble.friendlyNPCDamagedOnly = false
    bubble.centerHealthText = true
    bubble.centerHealthTextOnNameplate = true
    bubble.powerBarOverlap = false

    return data
end

Overlay(ns.defaults, BuildData())
ns.ForeverDefaults = { BuildData = BuildData }
