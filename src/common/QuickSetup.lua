local addonName, ns = ...

local QuickSetup = {}
ns.QuickSetup = QuickSetup

local ENGINE_VERSION = "1.0.4.12-tf1"
local PROFILE_SCHEMA_VERSION = 1
local EXPORT_PREFIX = "TFL1QS1:"

local CLASS_TOKENS = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}

local function ClassDisplayName(token)
    if type(token) ~= "string" or token == "" then return "Unknown" end
    return token:sub(1, 1) .. token:sub(2):lower()
end

local QUICK_SETUP_CVARS = {
    "deselectOnClick",
    "showTargetOfTarget",
    "instantQuestText",
    "statusText",
    "statusTextDisplay",
    "cameraView",
    "cameraSmoothStyle",
    "cameraPivot",
    "cameraDistanceMaxZoomFactor",
    "showTutorials",
    "autoLootDefault",
    "nameplateShowEnemies",
}

-- UnitClass/UnitRace are read at file scope for speed, but on a slow client with many
-- addons initializing the player unit is not always resolvable that early. Every consumer
-- goes through ResolveCharacterTokens() so a nil token can never index a saved table.
local _, class = UnitClass("player")
local _, race = UnitRace("player")

local function ResolveCharacterTokens()
	if type(class) ~= "string" or class == "" then
		local _, resolvedClass = UnitClass("player")
		class = resolvedClass
	end
	if type(race) ~= "string" or race == "" then
		local _, resolvedRace = UnitRace("player")
		race = resolvedRace
	end
	return type(class) == "string" and class ~= "" and type(race) == "string" and race ~= ""
end

-- Automatic setup is retried across logins when it does not complete, but it must not
-- retry forever: a character whose spells and items simply are not available yet would
-- otherwise be re-cleaned on every single login.
local MAX_BOOTSTRAP_ATTEMPTS = 3

-- Number of retries for a single failing restore stage before the stage is skipped.
local AUTO_STAGE_RETRIES = 2

-- Frames a paused job will wait for combat to end before giving up. The job also listens
-- for PLAYER_REGEN_ENABLED; this poll exists because that event is not guaranteed to
-- arrive for every lockdown condition.
local MAX_COMBAT_WAITS = 60

-- Experience allowance for "fresh level one". Raise this if players report that automatic
-- setup is skipped because they gained a little XP before the addon finished loading.
-- Setup is still gated on the character GUID, so raising it cannot re-clean an already
-- configured character.
local FRESH_XP_ALLOWANCE = 0

local MAX_ACTION_SLOTS = math.max(
	tonumber(_G.MAX_ACTION_BUTTONS) or 120,
	(tonumber(_G.MULTIBAR_7_ACTIONBAR_PAGE) or 15) * (tonumber(_G.NUM_MULTIBAR_BUTTONS) or 12),
	180
)
local API = ns.API or {}
local QUICK_POLICY = (ns.Client and ns.Client.quickSetupPolicy) or {}
local function QuickPolicy(key) return QUICK_POLICY[key] == true end
local function APIAvailable(name)
    return API.IsAvailable and API.IsAvailable(name)
end
local GetActionInfoCompat = API.GetActionInfo
local GetActionTextCompat = API.GetActionText
local PlaceActionCompat = API.PlaceAction
local PickupActionCompat = API.PickupAction
local PickupSpellCompat = API.PickupSpell
local PickupItemCompat = API.PickupItem
local RequestLoadItemDataByIDCompat = API.RequestLoadItemDataByID
local PickupMacroCompat = API.PickupMacro
local GetMacroIndexByNameCompat = API.GetMacroIndexByName
local EditMacroCompat = API.EditMacro
local DeleteMacroCompat = API.DeleteMacro
local SetCVarCompat = API.SetCVar
local GetCVarCompat = API.GetCVar
local GetActionBarTogglesCompat = API.GetActionBarToggles
local SetActionBarTogglesCompat = API.SetActionBarToggles
local MAX_ACCOUNT_MACROS_COMPAT = _G.MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS_COMPAT = _G.MAX_CHARACTER_MACROS or 18
if QuickPolicy("modernMacroLimits") and type(API.GetMacroLimits) == "function" then
	MAX_ACCOUNT_MACROS_COMPAT, MAX_CHARACTER_MACROS_COMPAT = API.GetMacroLimits()
end

local ACTION_BAR_SETTING_KEYS = {
    [2] = "PROXY_SHOW_ACTIONBAR_2",
    [3] = "PROXY_SHOW_ACTIONBAR_3",
    [4] = "PROXY_SHOW_ACTIONBAR_4",
    [5] = "PROXY_SHOW_ACTIONBAR_5",
    [6] = "PROXY_SHOW_ACTIONBAR_6",
    [7] = "PROXY_SHOW_ACTIONBAR_7",
    [8] = "PROXY_SHOW_ACTIONBAR_8",
}

local sessionActionBarOverrides = {}
local sessionActionBarDriverFrames = {}
local restoreRuntimeActive = false
local runtimeCleanupPending = false

local ApplyBlizzardOptions
local MaybeReleaseRestoreRuntime

local ApplyEditModeLayout
local ApplyPendingEditModeLayout
local pendingEditModeLayout
local editModeRetryScheduled = false

-- Automatic login restoration is intentionally spread across frames. Action placement,
-- binding mutation, and other UI work can become expensive when many addons initialize
-- at the same time; each scheduled callback receives a fresh script execution budget.
local AUTO_BINDING_SCAN_BATCH = 60
local AUTO_BINDING_MUTATION_BATCH = 30
local AUTO_ACTION_CLEAR_BATCH = 24
local AUTO_ACTION_PLACE_BATCH = 2
local automaticRestoreJob
local ProcessAutomaticRestoreJob
local FinalizeAutomaticRestore
local StartAutomaticActionRetry
local eventFrame

-- Stage transition table. It is also used by the error handler to skip a stage that keeps
-- failing instead of abandoning the whole job partway through.
local AUTO_STAGE_ORDER = {
	macros = "bindings",
	bindings = "placeActions",
	placeActions = "clearActions",
	clearActions = "blizzardOptions",
	blizzardOptions = "editMode",
	editMode = "finish",
}

local function PrintMessage(message)
    if ns and ns.Chat then
        ns:Chat("Quick Setup", tostring(message))
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTurboFace Quick Setup:|r " .. tostring(message))
    end
end

local function CountEntries(tbl)
	local count = 0
	if type(tbl) == "table" then
		for _ in pairs(tbl) do
			count = count + 1
		end
	end
	return count
end

local function EnsureStores()
    if type(TurboFaceProfilesDB) ~= "table" then TurboFaceProfilesDB = {} end
    if type(TurboFaceProfilesDB.quickSetup) ~= "table" then TurboFaceProfilesDB.quickSetup = {} end
    local root = TurboFaceProfilesDB.quickSetup
    if type(root.classes) ~= "table" then root.classes = {} end
    root.schemaVersion = PROFILE_SCHEMA_VERSION

    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.quickSetup) ~= "table" then TurboFaceCharDB.quickSetup = {} end
    return root, TurboFaceCharDB.quickSetup
end

local function ProfilesRoot()
    local root = EnsureStores()
    return root
end

local function CharRoot()
    local _, root = EnsureStores()
    return root
end

local function Config()
    if type(TurboFaceDB) ~= "table" then return nil end
    if type(TurboFaceDB.quickSetup) ~= "table" then TurboFaceDB.quickSetup = {} end
    return TurboFaceDB.quickSetup
end

local function GetClassProfile(token)
    if type(token) ~= "string" or not CLASS_TOKENS[token] then return nil end
    local root = ProfilesRoot()
    local profile = root.classes[token]
    return type(profile) == "table" and profile or nil
end

local function EnsureClassProfile(token)
    if type(token) ~= "string" or not CLASS_TOKENS[token] then return nil end
    local root = ProfilesRoot()
    local profile = root.classes[token]
    if type(profile) ~= "table" then
        profile = { version = PROFILE_SCHEMA_VERSION, class = token }
        root.classes[token] = profile
    end
    profile.version = PROFILE_SCHEMA_VERSION
    profile.class = token
    return profile
end

local function CaptureCVars(profileToken)
    local profile = EnsureClassProfile(profileToken)
    if not profile or not APIAvailable("GetCVar") then return 0 end
    profile.cvars = {}
    local count = 0
    for _, variable in ipairs(QUICK_SETUP_CVARS) do
        local ok, value = pcall(GetCVarCompat, variable)
        if ok and value ~= nil then
            profile.cvars[variable] = tostring(value)
            count = count + 1
        end
    end
    return count
end

local function ApplyCVars(profileToken)
	local profile = GetClassProfile(profileToken)
	local saved = profile and profile.cvars
	if type(saved) ~= "table" then return 0 end
	local baseline = {}
	for _, variable in ipairs(QUICK_SETUP_CVARS) do
		if saved[variable] ~= nil then baseline[variable] = tostring(saved[variable]) end
	end
	if QuickPolicy("cvarBaseline") and type(ns.ApplyCVarBaseline) == "function" then
		return ns.ApplyCVarBaseline(baseline)
	end
	if not APIAvailable("SetCVar") then return 0 end
	local count = 0
	for _, variable in ipairs(QUICK_SETUP_CVARS) do
		local value = baseline[variable]
        if value ~= nil then
            local ok = pcall(SetCVarCompat, variable, tostring(value))
            if ok then count = count + 1 end
        end
    end
    return count
end

local function NormalizeBoolean(value)
	if value == true or value == 1 or value == "1" then return true end
	if value == false or value == 0 or value == "0" then return false end
	return nil
end

local function GetSavedActionBarOptions(profileToken)
    local profile = GetClassProfile(profileToken)
    local blizzard = profile and profile.blizzard
    return blizzard and blizzard.actionBars
end

local function GetSavedEditModeLayout(profileToken)
    local profile = GetClassProfile(profileToken)
    local blizzard = profile and profile.blizzard
    return blizzard and blizzard.editModeLayout
end

local function GetEditModePresetCount()
	local meta = Enum and Enum.EditModePresetLayoutsMeta
	return meta and tonumber(meta.NumValues) or 2
end

local function GetEditModeLayoutTypeValue(name, fallback)
	local layoutTypes = Enum and Enum.EditModeLayoutType
	local value = layoutTypes and layoutTypes[name]
	return value ~= nil and value or fallback
end

local EDIT_MODE_LAYOUT_PRESET = GetEditModeLayoutTypeValue("Preset", 0)
local EDIT_MODE_LAYOUT_ACCOUNT = GetEditModeLayoutTypeValue("Account", 1)
local EDIT_MODE_LAYOUT_CHARACTER = GetEditModeLayoutTypeValue("Character", 2)

local function GetPresetLayoutName(layoutIndex)
	local presetLayouts = Enum and Enum.EditModePresetLayouts
	-- Enum.EditModePresetLayouts is zero-based, while activeLayout and
	-- C_EditMode.SetActiveLayout use the one-based full layout index space.
	local presetIndex = tonumber(layoutIndex)
	if QuickPolicy("oneBasedEditModeLayout") and presetIndex then presetIndex = presetIndex - 1 end
	local modernIndex = presetLayouts and presetLayouts.Modern or (QuickPolicy("oneBasedEditModeLayout") and 0 or 1)
	local classicIndex = presetLayouts and presetLayouts.Classic or (QuickPolicy("oneBasedEditModeLayout") and 1 or 2)
	if presetIndex == modernIndex then
		return _G.LAYOUT_STYLE_MODERN or "Modern"
	elseif presetIndex == classicIndex then
		return _G.LAYOUT_STYLE_CLASSIC or "Classic"
	end
	return "Preset " .. tostring(layoutIndex)
end

local function GetCurrentEditModeLayouts()
	if not C_EditMode or type(C_EditMode.GetLayouts) ~= "function" then return nil end
	local ok, layoutInfo = pcall(C_EditMode.GetLayouts)
	if not ok or type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table"
		or tonumber(layoutInfo.activeLayout) == nil then
		return nil
	end
	return layoutInfo
end

-- C_EditMode.GetLayouts() returns only editable layouts in layoutInfo.layouts,
-- while activeLayout uses the full index space after Blizzard's preset layouts.
local function GetEditModeLayoutByFullIndex(layoutInfo, layoutIndex)
	layoutIndex = tonumber(layoutIndex)
	if not layoutIndex then return nil end
	local presetCount = GetEditModePresetCount()
	if layoutIndex >= 1 and layoutIndex <= presetCount then
		return {
			layoutName = GetPresetLayoutName(layoutIndex),
			layoutType = EDIT_MODE_LAYOUT_PRESET,
		}
	end
	return layoutInfo.layouts[layoutIndex - presetCount]
end

local function GetEditModeLayoutTypeLabel(layoutType)
	if layoutType == EDIT_MODE_LAYOUT_PRESET then return "preset" end
	if layoutType == EDIT_MODE_LAYOUT_ACCOUNT then return "account" end
	if layoutType == EDIT_MODE_LAYOUT_CHARACTER then return "character" end
	return "type " .. tostring(layoutType)
end

local function DescribeSavedEditModeLayout(profile)
	local saved = GetSavedEditModeLayout(profile)
	if type(saved) ~= "table" then return "none" end
	local name = saved.name or saved.layoutName or (saved.index and ("layout " .. saved.index)) or "unknown"
	return tostring(name) .. " (" .. GetEditModeLayoutTypeLabel(saved.layoutType) .. ")"
end

local function SaveEditModeLayout(profile)
	local layoutInfo = GetCurrentEditModeLayouts()
	if not layoutInfo then
		error("Edit Mode layouts are not available")
	end

	local activeIndex = tonumber(layoutInfo.activeLayout)
	local activeLayout = GetEditModeLayoutByFullIndex(layoutInfo, activeIndex)
	if not activeLayout then
		error("Could not resolve the selected Edit Mode layout")
	end

    local storedProfile = EnsureClassProfile(profile)
    storedProfile.blizzard = storedProfile.blizzard or {}
    storedProfile.blizzard.editModeLayout = {
		index = activeIndex,
		name = activeLayout.layoutName,
		layoutType = activeLayout.layoutType,
	}
	return 1
end

local function EditModeLayoutMatches(saved, candidate)
	if type(candidate) ~= "table" then return false end
	local savedName = saved.name or saved.layoutName
	if savedName and candidate.layoutName ~= savedName then return false end
	if saved.layoutType ~= nil and candidate.layoutType ~= saved.layoutType then return false end
	return true
end

local function ResolveSavedEditModeLayoutIndex(saved, layoutInfo)
	if type(saved) == "number" then
		saved = { index = saved }
	end
	if type(saved) ~= "table" then return nil end

	local presetCount = GetEditModePresetCount()
	local savedIndex = tonumber(saved.index)
	if saved.layoutType == EDIT_MODE_LAYOUT_PRESET then
		if savedIndex and savedIndex >= 1 and savedIndex <= presetCount then
			return savedIndex
		end
		for layoutIndex = 1, presetCount do
			if EditModeLayoutMatches(saved, GetEditModeLayoutByFullIndex(layoutInfo, layoutIndex)) then
				return layoutIndex
			end
		end
	end

	local savedName = saved.name or saved.layoutName
	if savedName then
		for customIndex, candidate in ipairs(layoutInfo.layouts) do
			if EditModeLayoutMatches(saved, candidate) then
				return presetCount + customIndex
			end
		end
	end

	-- The index is only a fallback when it still points to the same named/type layout.
	if savedIndex and EditModeLayoutMatches(saved, GetEditModeLayoutByFullIndex(layoutInfo, savedIndex)) then
		return savedIndex
	end
	return nil
end

local function QueueEditModeLayout(profile, quiet, attempt, scheduleTimer)
	pendingEditModeLayout = {
		profile = profile,
		quiet = quiet,
		attempt = attempt or 1,
	}
	if scheduleTimer == false or editModeRetryScheduled or not C_Timer or type(C_Timer.After) ~= "function" then return end
	editModeRetryScheduled = true
	C_Timer.After(1, function()
		editModeRetryScheduled = false
		ApplyPendingEditModeLayout()
	end)
end

ApplyEditModeLayout = function(profile, quiet, attempt)
	local saved = GetSavedEditModeLayout(profile)
	local result = {
		stored = 0,
		matched = 0,
		changed = 0,
		failed = 0,
		deferred = 0,
		missing = 0,
		name = nil,
		layoutType = nil,
		targetIndex = nil,
	}
	if type(saved) ~= "table" and type(saved) ~= "number" then return result end

	result.stored = 1
	if type(saved) == "table" then
		result.name = saved.name or saved.layoutName
		result.layoutType = saved.layoutType
	end
	attempt = attempt or 1

	if InCombatLockdown() then
		result.deferred = 1
		QueueEditModeLayout(profile, quiet, attempt + 1, false)
		return result
	end

	local layoutInfo = GetCurrentEditModeLayouts()
	if not layoutInfo then
		if attempt <= 6 then
			result.deferred = 1
			QueueEditModeLayout(profile, quiet, attempt + 1)
		else
			result.failed = 1
		end
		return result
	end

	local targetIndex = ResolveSavedEditModeLayoutIndex(saved, layoutInfo)
	result.targetIndex = targetIndex
	if not targetIndex then
		result.missing = 1
		return result
	end

	if tonumber(layoutInfo.activeLayout) == targetIndex then
		pendingEditModeLayout = nil
		result.matched = 1
		return result
	end

	if not C_EditMode or type(C_EditMode.SetActiveLayout) ~= "function" then
		result.failed = 1
		return result
	end

	local ok = pcall(C_EditMode.SetActiveLayout, targetIndex)
	if not ok then
		result.failed = 1
		return result
	end

	local verifiedLayouts = GetCurrentEditModeLayouts()
	if verifiedLayouts and tonumber(verifiedLayouts.activeLayout) == targetIndex then
		pendingEditModeLayout = nil
		result.matched = 1
		result.changed = 1
	else
		result.deferred = 1
		QueueEditModeLayout(profile, quiet, attempt + 1)
	end
	return result
end

ApplyPendingEditModeLayout = function()
	local request = pendingEditModeLayout
	if not request then return end
	pendingEditModeLayout = nil

	local result = ApplyEditModeLayout(request.profile, request.quiet, request.attempt)
	if result.deferred == 0 and not request.quiet then
		if result.missing > 0 then
			local typeText = result.layoutType == EDIT_MODE_LAYOUT_CHARACTER and " Character-specific layouts are not shared with a newly created character." or ""
			PrintMessage("Saved Edit Mode layout '" .. tostring(result.name or "unknown") .. "' is not available on this character." .. typeText)
		elseif result.failed > 0 then
			PrintMessage("Failed to apply the saved Edit Mode layout.")
		elseif result.stored > 0 then
			PrintMessage("Applied saved Edit Mode layout '" .. tostring(result.name or result.targetIndex)
				.. "'; " .. result.changed .. " layout change.")
		end
	end
	if MaybeReleaseRestoreRuntime then MaybeReleaseRestoreRuntime() end
end

local function CountSavedActionBarOptions(profile)
	local actionBars = GetSavedActionBarOptions(profile)
	local count = 0
	if type(actionBars) == "table" then
		for bar = 2, 8 do
			if NormalizeBoolean(actionBars[bar]) ~= nil then
				count = count + 1
			end
		end
	end
	return count
end

local function ReadCurrentActionBarOptions()
	local values = {}
	local count = 0

	-- The live Blizzard ActionBar controller itself reads these proxy settings.
	-- Prefer them when Settings has finished loading so Save Class Profile captures
	-- what the player is actually seeing right now, not just next-load storage.
	if type(Settings) == "table" and type(Settings.GetValue) == "function" then
		for bar = 2, 8 do
			local key = ACTION_BAR_SETTING_KEYS[bar]
			local ok, value = pcall(Settings.GetValue, key)
			value = ok and NormalizeBoolean(value) or nil
			if value ~= nil then
				values[bar] = value
				count = count + 1
			end
		end
		if count == 7 then
			for bar = 2, 8 do
				if sessionActionBarOverrides[bar] ~= nil then
					values[bar] = sessionActionBarOverrides[bar]
				end
			end
			return values, count
		end
		wipe(values)
		count = 0
	end

	if not APIAvailable("GetActionBarToggles") then
		return values, count
	end

	local toggles = { pcall(GetActionBarTogglesCompat) }
	if not toggles[1] then
		return values, count
	end

	-- pcall occupies index 1, so Blizzard Action Bar 2 maps to toggles[2],
	-- Action Bar 3 to toggles[3], ... through Action Bar 8 at toggles[8].
	for bar = 2, 8 do
		local value = NormalizeBoolean(toggles[bar])
		if value ~= nil then
			values[bar] = value
			count = count + 1
		end
	end
	if count == 7 then
		for bar = 2, 8 do
			if sessionActionBarOverrides[bar] ~= nil then
				values[bar] = sessionActionBarOverrides[bar]
			end
		end
	end
	return values, count
end

-- Blizzard's live Settings proxy is intentionally never written by Quick Setup.
-- Even when routed through securecallfunction(), addon-driven Settings.SetValue can
-- leave the native ActionBarMixin update path tainted and later block protected
-- ActionButton:SetShown() calls in combat. Instead, current-session visibility is
-- mirrored with SecureStateDriver while SetActionBarToggles persists the same state
-- for the next normal login. State drivers are session-local and disappear naturally
-- on logout/reload, at which point Blizzard's persisted settings own the bars again.
local ACTION_BAR_FRAME_NAMES = {
    [2] = "MultiBarBottomLeft",
    [3] = "MultiBarBottomRight",
    [4] = "MultiBarRight",
    [5] = "MultiBarLeft",
    [6] = "MultiBar5",
    [7] = "MultiBar6",
    [8] = "MultiBar7",
}

-- Match the important default-controller transitions: secondary bars should not
-- cover vehicle/override/possess UIs. Stance/bonus pages intentionally do not hide
-- the secondary bars in Blizzard's normal action-bar state.
local ACTION_BAR_VISIBLE_DRIVER = "[vehicleui] hide; [overridebar] hide; [possessbar] hide; show"
local ACTION_BAR_HIDDEN_DRIVER = "hide"

local function ApplySessionActionBarDriver(bar, desired)
    if type(RegisterStateDriver) ~= "function" then
        return false, "RegisterStateDriver unavailable"
    end
    local frameName = ACTION_BAR_FRAME_NAMES[bar]
    local frame = frameName and _G[frameName]
    if not frame then
        return false, "missing frame " .. tostring(frameName)
    end
    local condition = desired and ACTION_BAR_VISIBLE_DRIVER or ACTION_BAR_HIDDEN_DRIVER
    local ok, err = pcall(RegisterStateDriver, frame, "visibility", condition)
    if not ok then return false, tostring(err) end
    sessionActionBarOverrides[bar] = desired == true
    sessionActionBarDriverFrames[bar] = frame
    return true
end

local function ReleaseSessionActionBarDrivers(reason)
    local count = 0
    for _ in pairs(sessionActionBarDriverFrames) do count = count + 1 end
    if count == 0 then
        runtimeCleanupPending = false
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        runtimeCleanupPending = true
        return false
    end
    if type(UnregisterStateDriver) ~= "function" then
        runtimeCleanupPending = true
        return false
    end

    local failed = 0
    for bar, frame in pairs(sessionActionBarDriverFrames) do
        local ok = pcall(UnregisterStateDriver, frame, "visibility")
        if ok then
            sessionActionBarDriverFrames[bar] = nil
        else
            failed = failed + 1
        end
    end
    runtimeCleanupPending = failed > 0
    return failed == 0
end

local function SaveBlizzardOptions(profile)
    local actionBars, count = ReadCurrentActionBarOptions()
    if count ~= 7 then
        error("Could not read all Blizzard Action Bar 2-8 settings")
    end

    local storedProfile = EnsureClassProfile(profile)
    storedProfile.blizzard = storedProfile.blizzard or {}
    storedProfile.blizzard.actionBars = actionBars
    return count
end

ApplyBlizzardOptions = function(profile, quiet)
    local actionBars = GetSavedActionBarOptions(profile)
    local result = { stored = 0, matched = 0, changed = 0, failed = 0, deferred = 0, queued = 0, persisted = 0, live = 0 }
    if type(actionBars) ~= "table" then return result end

    for bar = 2, 8 do
        if NormalizeBoolean(actionBars[bar]) ~= nil then
            result.stored = result.stored + 1
        end
    end
    if result.stored == 0 then return result end


    if InCombatLockdown and InCombatLockdown() then
        result.deferred = result.stored
        return result
    end

    local current, currentCount = ReadCurrentActionBarOptions()
    if currentCount ~= 7 then
        result.failed = result.stored
        return result
    end

    local desiredArgs = {}
    local changedBars = {}
    for bar = 2, 8 do
        local desired = NormalizeBoolean(actionBars[bar])
        local existing = current[bar]
        if desired == nil then
            desired = existing
        elseif desired == existing then
            result.matched = result.matched + 1
        else
            changedBars[#changedBars + 1] = bar
        end
        desiredArgs[bar - 1] = desired == true
    end

    if #changedBars == 0 then
        return result
    end

    -- Persist the complete seven-toggle profile through Blizzard's dedicated C API.
    -- This does not alter the current Settings proxy values; it becomes native state
    -- on the next ordinary login/reload, after which no TurboFace driver is needed.
    local persistOK = false
    if APIAvailable("SetActionBarToggles") then
        local ok = pcall(SetActionBarTogglesCompat,
            desiredArgs[1], desiredArgs[2], desiredArgs[3], desiredArgs[4],
            desiredArgs[5], desiredArgs[6], desiredArgs[7])
        persistOK = ok
        if ok then result.persisted = #changedBars end
    end

    -- No-reload current-session mirror. RegisterStateDriver is the Blizzard-supported
    -- secure mechanism for controlling visibility of protected frames. We never call
    -- Settings.SetValue, MultiActionBar_Update, Show/Hide, or SetShown here.
    local liveFailed = 0
    for _, bar in ipairs(changedBars) do
        local desired = desiredArgs[bar - 1] == true
        local ok = ApplySessionActionBarDriver(bar, desired)
        if ok then
            result.changed = result.changed + 1
            result.live = result.live + 1
        else
            liveFailed = liveFailed + 1
        end
    end

    if liveFailed > 0 then
        -- If persistence succeeded, failed session mirrors still self-heal on the next
        -- normal login. Track only those failed mirrors as queued; a successful live
        -- mirror does not need a user reload.
        if persistOK then
            result.queued = liveFailed
        else
            result.failed = liveFailed
        end
    end
    return result
end

local function IsFreshLevelOne()
	local level = tonumber(UnitLevel("player"))
	local xp = tonumber(UnitXP("player"))
	return level == 1 and xp ~= nil and xp <= FRESH_XP_ALLOWANCE
end

local function IsUsablePlayerName(name)
    if type(name) ~= "string" or name == "" then return false end
    if name == _G.UNKNOWNOBJECT or name == _G.UKNOWNBEING or name == "Unknown" then return false end
    return true
end

local function GetCharacterIdentity()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) ~= "string" or not guid:match("^Player%-") then return nil end
    local name = UnitName("player")
    if not IsUsablePlayerName(name) then return nil end
    local realm = GetRealmName()
    if type(realm) ~= "string" or realm == "" then return nil end
    return guid, realm .. ":" .. name
end

local function GetCharacterBootstrapState()
    local guid, identity = GetCharacterIdentity()
    if not guid then return nil end
    local charRoot = CharRoot()
    local previous = charRoot.bootstrap

    local previousGUID, previousAttempts, previousComplete
    if type(previous) == "table" then
        previousGUID = previous.guid
        previousAttempts = tonumber(previous.attempts) or 0
        previousComplete = previous.complete
        if previousComplete == nil then previousComplete = true end
    end

    local sameCharacter = previousGUID ~= nil and previousGUID == guid
    local attempts = sameCharacter and previousAttempts or 0
    local completed = sameCharacter and previousComplete or false
    local exhausted = attempts >= MAX_BOOTSTRAP_ATTEMPTS

    return {
        identity = identity,
        guid = guid,
        previousGUID = previousGUID,
        attempts = attempts,
        completed = completed,
        exhausted = exhausted,
        firstSetup = (not completed) and (not exhausted),
        recreated = previousGUID ~= nil and previousGUID ~= guid,
    }
end

local function WriteCharacterBootstrap(state, complete, attempts)
    if not state or not state.guid then return end
    local charRoot = CharRoot()
    charRoot.bootstrap = {
        guid = state.guid,
        identity = state.identity,
        class = class,
        race = race,
        time = time(),
        version = ENGINE_VERSION,
        complete = complete and true or false,
        attempts = tonumber(attempts) or 0,
    }
end

local function MarkCharacterBootstrapped(state)
    WriteCharacterBootstrap(state, true, state and state.attempts or 0)
end

local function MarkCharacterBootstrapAttempt(state)
    if not state then return 0 end
    local attempts = (tonumber(state.attempts) or 0) + 1
    state.attempts = attempts
    WriteCharacterBootstrap(state, false, attempts)
    return attempts
end

local function ClearCharacterBootstrap()
    local charRoot = CharRoot()
    if charRoot.bootstrap == nil then return false end
    charRoot.bootstrap = nil
    return true
end

-- A restore counts as successful only if it actually moved data onto the character.
-- Partial results are normal (unlearned spells, uncached items) and still count.
local function RestoreLooksSuccessful(macroResult, actionResult)
	macroResult = type(macroResult) == "table" and macroResult or {}
	actionResult = type(actionResult) == "table" and actionResult or {}

	local macroStored = tonumber(macroResult.stored) or 0
	local macroFailed = tonumber(macroResult.failed) or 0
	if macroStored > 0 and macroFailed >= macroStored then return false end

	local actionStored = tonumber(actionResult.stored) or 0
	local actionLoaded = tonumber(actionResult.loaded) or 0
	if actionStored > 0 and actionLoaded == 0 then return false end

	return true
end

local function BuildMacroNameMaps()
	local maps = { account = {}, character = {} }
	if not GetNumMacros or not GetMacroInfo then return maps end

	local accountCount, characterCount = GetNumMacros()
	for index = 1, accountCount or 0 do
		local macroName = GetMacroInfo(index)
		if macroName and maps.account[macroName] == nil then
			maps.account[macroName] = index
		end
	end

	for offset = 1, math.min(characterCount or 0, MAX_CHARACTER_MACROS_COMPAT) do
		local index = MAX_ACCOUNT_MACROS_COMPAT + offset
		local macroName = GetMacroInfo(index)
		if macroName and maps.character[macroName] == nil then
			maps.character[macroName] = index
		end
	end
	return maps
end

local function FindMacroByNameInScope(name, perCharacter, maps)
	if not name then return 0 end
	maps = maps or BuildMacroNameMaps()
	local index = perCharacter and maps.character[name] or maps.account[name]
	return tonumber(index) or 0
end

local function RemoveStaleCharacterMacros(profile)
	local storedProfile = GetClassProfile(profile)
	local macros = storedProfile and storedProfile.macros
	if type(macros) ~= "table" or not GetNumMacros or not GetMacroInfo or not APIAvailable("DeleteMacro") then
		return 0, 0
	end

	local desired = {}
	for _, macro in ipairs(macros) do
		if type(macro) == "table" and macro[1] and macro[4] == nil then
			desired[macro[1]] = true
		end
	end

	local _, characterCount = GetNumMacros()
	local removed = 0
	local failed = 0
	for offset = math.min(characterCount or 0, MAX_CHARACTER_MACROS_COMPAT), 1, -1 do
		local index = MAX_ACCOUNT_MACROS_COMPAT + offset
		local macroName = GetMacroInfo(index)
		if macroName and not desired[macroName] then
			local ok = pcall(DeleteMacroCompat, index)
			if ok then
				removed = removed + 1
			else
				failed = failed + 1
			end
		end
	end
	return removed, failed
end

local function SynchronizeMacros(profile, exact)
	local storedProfile = GetClassProfile(profile)
	local macros = storedProfile and storedProfile.macros
	local createMacro = _G.CreateMacro
	local result = {
		stored = CountEntries(macros),
		created = 0,
		updated = 0,
		removed = 0,
		cleanupFailed = 0,
		failed = 0,
	}
	if type(macros) ~= "table" or not createMacro or not GetMacroInfo then return result end

	if exact then
		result.removed, result.cleanupFailed = RemoveStaleCharacterMacros(profile)
	end

	-- Build the name maps once. The previous implementation rescanned every macro for
	-- each saved macro, which made macro synchronization quadratic on macro-heavy accounts.
	local maps = BuildMacroNameMaps()
	for _, macro in ipairs(macros) do
		if type(macro) == "table" and macro[1] then
			local name, icon, body = macro[1], macro[2], macro[3]
			local perCharacter = macro[4] == nil
			local scopeMap = perCharacter and maps.character or maps.account
			local macroIndex = tonumber(scopeMap[name]) or 0

			if macroIndex > 0 then
				if perCharacter and APIAvailable("EditMacro") then
					local _, currentIcon, currentBody = GetMacroInfo(macroIndex)
					if currentIcon ~= icon or currentBody ~= body then
						local ok, editedIndex = pcall(EditMacroCompat, macroIndex, name, icon, body)
						if ok and editedIndex then
							result.updated = result.updated + 1
						else
							result.failed = result.failed + 1
						end
					end
				end
			else
				local ok, createdIndex = pcall(createMacro, name, icon, body, perCharacter)
				if ok and createdIndex then
					result.created = result.created + 1
					scopeMap[name] = createdIndex
				else
					result.failed = result.failed + 1
				end
			end
		end
	end
	return result
end

local function FindMacroIndexForAction(name, scope, maps)
	if maps then
		if scope == "character" then
			-- Prep69 inferred scope from C_ActionBar.GetActionInfo's numeric actionID.
			-- Forever's value is not the legacy absolute macro index, so old profiles
			-- can carry a false character scope for an account macro. Prefer the saved
			-- scope, but fall back by name rather than reporting the macro missing.
			return tonumber(QuickPolicy("macroScopeBySnapshot") and (maps.character[name] or maps.account[name]) or maps.character[name]) or 0
		elseif scope == "account" then
			return tonumber(QuickPolicy("macroScopeBySnapshot") and (maps.account[name] or maps.character[name]) or maps.account[name]) or 0
		end
		local mapped = maps.account[name] or maps.character[name]
		if mapped then return tonumber(mapped) or 0 end
	end

	if scope == "character" then
		return FindMacroByNameInScope(name, true, maps)
	elseif scope == "account" then
		return FindMacroByNameInScope(name, false, maps)
	end
	return APIAvailable("GetMacroIndexByName") and GetMacroIndexByNameCompat(name) or 0
end

local function TryPickupSpell(spellID)
	if not APIAvailable("PickupSpell") then return false end
	local ok = pcall(PickupSpellCompat, spellID)
	return ok and GetCursorInfo() == "spell"
end

local function TryPickupItem(itemID)
	if not APIAvailable("PickupItem") then return false end

	local ok = pcall(PickupItemCompat, itemID)
	local pickedUp = ok and GetCursorInfo() == "item"
	if not pickedUp and APIAvailable("RequestLoadItemDataByID") then
		pcall(RequestLoadItemDataByIDCompat, itemID)
	end
	return pickedUp
end

local function GetSortedPlacementSlots(placements, requestedSlots)
	local slots = {}
	local seen = {}
	local function AddSlot(value)
		local slot = tonumber(value)
		if slot and slot >= 1 and slot <= MAX_ACTION_SLOTS and slot == math.floor(slot)
			and not seen[slot] and (placements[slot] ~= nil or placements[tostring(slot)] ~= nil) then
			seen[slot] = true
			table.insert(slots, slot)
		end
	end

	if type(requestedSlots) == "table" then
		for _, slot in ipairs(requestedSlots) do AddSlot(slot) end
	else
		for slot in pairs(placements) do AddSlot(slot) end
	end
	table.sort(slots)
	return slots
end

local function NewActionResult(stored)
	return {
		stored = stored or 0,
		loaded = 0,
		missingMacros = 0,
		unavailableSpells = 0,
		unavailableItems = 0,
		failed = 0,
		retrySlots = {},
		retryLookup = {},
	}
end

local function AddActionRetrySlot(result, slot)
	if slot and not result.retryLookup[slot] then
		result.retryLookup[slot] = true
		table.insert(result.retrySlots, slot)
	end
end

local function PlaceSavedAction(slot, savedAction, result, macroMaps)
	local actionKind
	local actionValue
	local actionScope
	if type(savedAction) == "table" then
		actionKind = savedAction.kind or savedAction[1]
		actionValue = savedAction.value or savedAction[2]
		actionScope = savedAction.scope
	elseif type(savedAction) == "number" then
		actionKind = "legacy"
		actionValue = savedAction
	else
		actionKind = "macro"
		actionValue = savedAction
	end

	local numericValue = tonumber(actionValue)
	local pickedUp = false
	local pickedKind = actionKind
	if ClearCursor then ClearCursor() end

	if actionKind == "macro" and actionValue then
		local macroIndex = FindMacroIndexForAction(actionValue, actionScope, macroMaps)
		if macroIndex > 0 and APIAvailable("PickupMacro") then
			local ok = pcall(PickupMacroCompat, macroIndex)
			pickedUp = ok and GetCursorInfo() == "macro"
		else
			result.missingMacros = result.missingMacros + 1
		end
	elseif actionKind == "spell" and numericValue then
		pickedUp = TryPickupSpell(numericValue)
		if not pickedUp then
			result.unavailableSpells = result.unavailableSpells + 1
		end
	elseif actionKind == "item" and numericValue then
		pickedUp = TryPickupItem(numericValue)
		if not pickedUp then
			result.unavailableItems = result.unavailableItems + 1
		end
	elseif actionKind == "legacy" and numericValue then
		pickedUp = TryPickupSpell(numericValue)
		if pickedUp then
			pickedKind = "spell"
		else
			if ClearCursor then ClearCursor() end
			pickedUp = TryPickupItem(numericValue)
			if pickedUp then
				pickedKind = "item"
			else
				result.unavailableSpells = result.unavailableSpells + 1
				result.unavailableItems = result.unavailableItems + 1
			end
		end
	else
		result.failed = result.failed + 1
	end

	if pickedUp then
		local ok = pcall(PlaceActionCompat, slot)
		local verified = false
		if ok and APIAvailable("GetActionInfo") then
			local placedKind, placedValue = GetActionInfoCompat(slot)
			if pickedKind == "macro" then
				local placedName = APIAvailable("GetActionText") and GetActionTextCompat(slot)
				verified = placedKind == "macro" and placedName == actionValue
			elseif pickedKind == "spell" then
				verified = placedKind == "spell" and tonumber(placedValue) == numericValue
			elseif pickedKind == "item" then
				verified = placedKind == "item" and tonumber(placedValue) == numericValue
			end
		end

		if verified then
			result.loaded = result.loaded + 1
		else
			result.failed = result.failed + 1
			AddActionRetrySlot(result, slot)
		end
	else
		AddActionRetrySlot(result, slot)
	end

	if ClearCursor then ClearCursor() end
end

local function CreateActionLoadState(profile, requestedSlots)
	local storedProfile = GetClassProfile(profile)
	local placements = storedProfile and storedProfile.actions
	if type(placements) ~= "table" then
		return { done = true, result = NewActionResult(0) }
	end

	local slots = GetSortedPlacementSlots(placements, requestedSlots)
	local result = NewActionResult(#slots)
	if not APIAvailable("PlaceAction") or not GetCursorInfo then
		result.failed = #slots
		for _, slot in ipairs(slots) do AddActionRetrySlot(result, slot) end
		return { done = true, result = result }
	end

	return {
		placements = placements,
		slots = slots,
		index = 1,
		macroMaps = BuildMacroNameMaps(),
		result = result,
		done = #slots == 0,
	}
end

local function ProcessActionLoadBatch(state, batchSize)
	if state.done then return true end
	local lastIndex = math.min(#state.slots, state.index + (batchSize or #state.slots) - 1)
	for index = state.index, lastIndex do
		local slot = state.slots[index]
		local savedAction = state.placements[slot]
		if savedAction == nil then savedAction = state.placements[tostring(slot)] end
		PlaceSavedAction(slot, savedAction, state.result, state.macroMaps)
	end
	state.index = lastIndex + 1
	state.done = state.index > #state.slots
	return state.done
end

local function LoadActionButtons(profile, requestedSlots)
	local state = CreateActionLoadState(profile, requestedSlots)
	while not ProcessActionLoadBatch(state, math.huge) do end
	return state.result
end

local function CreateActionClearState(profile)
	local storedProfile = GetClassProfile(profile)
	local placements = storedProfile and storedProfile.actions
	local state = {
		placements = placements,
		slot = 1,
		result = { cleared = 0, failed = 0 },
		done = false,
	}
	if type(placements) ~= "table" or not APIAvailable("PickupAction") or not APIAvailable("GetActionInfo") then
		state.done = true
	end
	return state
end

local function ProcessActionClearBatch(state, batchSize)
	if state.done then return true end
	local lastSlot = math.min(MAX_ACTION_SLOTS, state.slot + (batchSize or MAX_ACTION_SLOTS) - 1)
	for slot = state.slot, lastSlot do
		if state.placements[slot] == nil and state.placements[tostring(slot)] == nil then
			local actionType = GetActionInfoCompat(slot)
			if actionType then
				if ClearCursor then ClearCursor() end
				local ok = pcall(PickupActionCompat, slot)
				if ClearCursor then ClearCursor() end
				local remainingType = GetActionInfoCompat(slot)
				if ok and not remainingType then
					state.result.cleared = state.result.cleared + 1
				else
					state.result.failed = state.result.failed + 1
				end
			end
		end
	end
	state.slot = lastSlot + 1
	state.done = state.slot > MAX_ACTION_SLOTS
	return state.done
end

local function ClearUnstoredActionButtons(profile)
	local state = CreateActionClearState(profile)
	while not ProcessActionClearBatch(state, math.huge) do end
	return state.result
end

local function SaveActionButtons(profile)
    local storedProfile = EnsureClassProfile(profile)
	if not APIAvailable("GetActionInfo") then
		error("Neither GetActionInfo nor C_ActionBar.GetActionInfo is available")
	end

	local actions = {}
	local unsupportedActions = {}
	local macroScopes = {}
	for _, macro in ipairs(storedProfile.macros or {}) do
		if type(macro) == "table" and type(macro[1]) == "string" then
			local macroScope = macro[4] == nil and "character" or "account"
			local existing = macroScopes[macro[1]]
			macroScopes[macro[1]] = existing and existing ~= macroScope and "ambiguous" or macroScope
		end
	end
	local function RecordUnsupported(slot, actionType)
		unsupportedActions[slot] = tostring(actionType or "unknown")
	end
	local saved = 0
	for actionSlot = 1, MAX_ACTION_SLOTS do
		local actionType, actionID = GetActionInfoCompat(actionSlot)
		if actionType == "macro" then
			local macroName = APIAvailable("GetActionText") and GetActionTextCompat(actionSlot)
			if macroName and macroName ~= "" then
				-- On Forever/modern C_ActionBar, actionID is not guaranteed to be the
				-- old absolute macro-list index. Scope comes from the macro snapshot that
				-- SaveMacros just built. Duplicate names remain deliberately unscoped so
				-- restore can resolve either list by name.
				local scope
				if QuickPolicy("macroScopeBySnapshot") then
					scope = macroScopes[macroName]
					if scope == "ambiguous" then scope = nil end
				else
					local macroIndex = tonumber(actionID)
					if macroIndex then scope = macroIndex > MAX_ACCOUNT_MACROS_COMPAT and "character" or "account" end
				end
				actions[actionSlot] = { kind = "macro", value = macroName, scope = scope }
				saved = saved + 1
			else
				if QuickPolicy("preserveUnsupportedActions") then RecordUnsupported(actionSlot, actionType) end
			end
		elseif actionType == "spell" and actionID then
			actions[actionSlot] = { kind = "spell", value = actionID }
			saved = saved + 1
		elseif actionType == "item" and actionID then
			actions[actionSlot] = { kind = "item", value = actionID }
			saved = saved + 1
		elseif actionType then
			-- Exact restoration clears every action slot that is absent from the
			-- saved placement map. Preserve an explicit record for action kinds we
			-- cannot recreate so that cleanup can fail safe instead of erasing them.
			if QuickPolicy("preserveUnsupportedActions") then RecordUnsupported(actionSlot, actionType) end
		end
	end
	-- Commit only after the complete scan succeeds, retaining the previous valid
	-- action snapshot if a client API throws partway through enumeration.
	storedProfile.actions = actions
	storedProfile.unsupportedActions = QuickPolicy("preserveUnsupportedActions") and next(unsupportedActions) and unsupportedActions or nil
	return saved
end

local function SaveKeyBinds(profile)
    local storedProfile = EnsureClassProfile(profile)
    storedProfile.bindings = {}
	local saved = 0

	for index = 1, GetNumBindings() do
		local binding = { GetBinding(index, true) }
		local command = binding[1]
		for keyIndex = 3, #binding do
			local key = binding[keyIndex]
			if key then
				storedProfile.bindings[key] = command
				saved = saved + 1
			end
		end
	end
	return saved
end

local function CreateKeyBindLoadState(profile)
	local storedProfile = GetClassProfile(profile)
	local bindings = storedProfile and storedProfile.bindings
	local state = {
		bindings = bindings,
		stored = CountEntries(bindings),
		loaded = 0,
		phase = "done",
		done = true,
	}
	if type(bindings) ~= "table" or InCombatLockdown() or not LoadBindings or not GetNumBindings
		or not GetBinding or not SetBinding or not SaveBindings then
		return state
	end

	LoadBindings(CHARACTER_BINDINGS or 2)
	state.phase = "scan"
	state.done = false
	state.bindingIndex = 1
	state.bindingCount = GetNumBindings()
	state.clearKeys = {}
	state.clearLookup = {}
	state.clearIndex = 1
	state.desiredKeys = {}
	state.applyIndex = 1
	for key in pairs(bindings) do table.insert(state.desiredKeys, key) end
	table.sort(state.desiredKeys)
	return state
end

local function ProcessKeyBindLoadBatch(state, scanBatchSize, mutationBatchSize)
	if state.done then return true end

	if state.phase == "scan" then
		local lastIndex = math.min(state.bindingCount, state.bindingIndex + (scanBatchSize or state.bindingCount) - 1)
		for index = state.bindingIndex, lastIndex do
			local binding = { GetBinding(index, true) }
			for keyIndex = 3, #binding do
				local key = binding[keyIndex]
				if key and state.bindings[key] == nil and not state.clearLookup[key] then
					state.clearLookup[key] = true
					table.insert(state.clearKeys, key)
				end
			end
		end
		state.bindingIndex = lastIndex + 1
		if state.bindingIndex > state.bindingCount then state.phase = "clear" end
		return false
	end

	if state.phase == "clear" then
		local lastIndex = math.min(#state.clearKeys, state.clearIndex + (mutationBatchSize or #state.clearKeys) - 1)
		for index = state.clearIndex, lastIndex do
			SetBinding(state.clearKeys[index])
		end
		state.clearIndex = lastIndex + 1
		if state.clearIndex > #state.clearKeys then state.phase = "apply" end
		return false
	end

	if state.phase == "apply" then
		local lastIndex = math.min(#state.desiredKeys, state.applyIndex + (mutationBatchSize or #state.desiredKeys) - 1)
		for index = state.applyIndex, lastIndex do
			local key = state.desiredKeys[index]
			if SetBinding(key, state.bindings[key]) then
				state.loaded = state.loaded + 1
			end
		end
		state.applyIndex = lastIndex + 1
		if state.applyIndex > #state.desiredKeys then state.phase = "save" end
		return false
	end

	SaveBindings(CHARACTER_BINDINGS or 2)
	state.phase = "done"
	state.done = true
	return true
end

local function LoadKeyBinds(profile)
	local state = CreateKeyBindLoadState(profile)
	while not ProcessKeyBindLoadBatch(state, math.huge, math.huge) do end
	return state.loaded
end

local function SaveMacros(profile)
	if not GetNumMacros or not GetMacroInfo then
		error("Macro APIs are unavailable")
	end
    local accountCount, characterCount = GetNumMacros()
    local storedProfile = EnsureClassProfile(profile)
    storedProfile.macros = {}

	local saved = 0
	for index = 1, accountCount do
		local name, icon, body = GetMacroInfo(index)
		if name then
			table.insert(storedProfile.macros, { name, icon, body, true })
			saved = saved + 1
		end
	end

	for index = 1, characterCount do
		local name, icon, body = GetMacroInfo(MAX_ACCOUNT_MACROS_COMPAT + index)
		if name then
			table.insert(storedProfile.macros, { name, icon, body })
			saved = saved + 1
		end
	end
	return saved
end

local function RunSaveSection(label, callback)
	local ok, result = xpcall(callback, geterrorhandler())
	if not ok then
		PrintMessage(label .. " failed; see BugSack for details.")
		return 0, false
	end
	return tonumber(result) or 0, true
end

local function SaveProfile(profile)
	profile = profile or class
	if InCombatLockdown() then
		PrintMessage("Cannot save while in combat.")
		return false
	end

	local macroCount, macrosOK = RunSaveSection("Macro save", function()
		return SaveMacros(profile)
	end)
	local bindingCount, bindingsOK = RunSaveSection("Keybind save", function()
		return SaveKeyBinds(profile)
	end)
	local actionCount, actionsOK = RunSaveSection("Action-bar save", function()
		return SaveActionButtons(profile)
	end)
	local unsupportedActionCount = CountEntries((GetClassProfile(profile) or {}).unsupportedActions)
	local blizzardOptionCount, blizzardOptionsOK = RunSaveSection("Blizzard option save", function()
		return SaveBlizzardOptions(profile)
	end)
	local editModeLayoutCount, editModeLayoutOK = RunSaveSection("Edit Mode layout save", function()
		return SaveEditModeLayout(profile)
	end)


    local cvarCount, cvarsOK = RunSaveSection("CVar save", function()
        return CaptureCVars(profile)
    end)

    local version, build, _, tocVersion = GetBuildInfo()
    local savedAt = time()
    ProfilesRoot().lastSave = {
        profile = profile,
        character = UnitName("player"),
        realm = GetRealmName(),
        time = savedAt,
        version = version,
        build = build,
        tocVersion = tocVersion,
        macros = macroCount,
        bindings = bindingCount,
        actions = actionCount,
		blizzardOptions = blizzardOptionCount,
		editModeLayouts = editModeLayoutCount,
		editModeLayout = GetSavedEditModeLayout(profile),
		unsupportedActions = unsupportedActionCount,
	}

    local allOK = macrosOK and bindingsOK and actionsOK and blizzardOptionsOK and editModeLayoutOK and cvarsOK
	PrintMessage((allOK and "Saved" or "Partially saved") .. " profile " .. profile .. ": "
		.. macroCount .. " macros, " .. bindingCount .. " keybinds, " .. actionCount .. " action slots, "
        .. blizzardOptionCount .. " Blizzard options, " .. editModeLayoutCount .. " Edit Mode layout ("
        .. DescribeSavedEditModeLayout(profile) .. "), " .. cvarCount .. " CVars.")
	if unsupportedActionCount > 0 then
		PrintMessage("Recorded " .. unsupportedActionCount .. " unsupported action type(s); exact restore will preserve unstored slots instead of clearing them.")
	end
	PrintMessage(QuickPolicy("externalPersistence") and "Log out normally, then run the Forever save helper to preserve this profile for the next login." or "Use /reload or log out normally to write the SavedVariables file to disk.")
	return allOK
end

local function DefaultedResult(result, defaults)
	if type(result) ~= "table" then result = {} end
	for key, value in pairs(defaults) do
		if result[key] == nil then result[key] = value end
	end
	return result
end

local function ReportLoadResults(profile, source, exact, storedBindings, macroResult, bindingCount,
	staleActionResult, actionResult, blizzardOptionResult, editModeLayoutResult)
	-- A stage can be skipped when it errors repeatedly, so no result table is guaranteed.
	macroResult = DefaultedResult(macroResult,
		{ stored = 0, created = 0, updated = 0, removed = 0, cleanupFailed = 0, failed = 0 })
	staleActionResult = DefaultedResult(staleActionResult, { cleared = 0, failed = 0, skippedUnsupported = 0 })
	actionResult = DefaultedResult(actionResult, { stored = 0, loaded = 0, missingMacros = 0,
		unavailableSpells = 0, unavailableItems = 0, failed = 0 })
	blizzardOptionResult = DefaultedResult(blizzardOptionResult,
		{ stored = 0, matched = 0, changed = 0, failed = 0, deferred = 0, queued = 0, persisted = 0, live = 0 })
	editModeLayoutResult = DefaultedResult(editModeLayoutResult,
		{ stored = 0, matched = 0, changed = 0, failed = 0, deferred = 0, missing = 0 })
	storedBindings = tonumber(storedBindings) or 0
	bindingCount = tonumber(bindingCount) or 0

	local prefix = source == "automatic" and "Automatically loaded" or "Loaded"
	local syncedMacros = math.max(0, macroResult.stored - macroResult.failed)
	PrintMessage(prefix .. " profile " .. profile .. ": synced " .. syncedMacros .. "/" .. macroResult.stored
		.. " macros, applied " .. bindingCount .. "/" .. storedBindings .. " keybinds, placed "
		.. actionResult.loaded .. "/" .. actionResult.stored .. " action slots.")
	if exact and (macroResult.removed > 0 or staleActionResult.cleared > 0) then
		PrintMessage("Fresh-character cleanup: removed " .. macroResult.removed
			.. " stale character macros and cleared " .. staleActionResult.cleared .. " stale action slots.")
	end
	if exact and staleActionResult.skippedUnsupported > 0 then
		PrintMessage("Fresh-character action cleanup was skipped because the saved profile contains "
			.. staleActionResult.skippedUnsupported .. " unsupported action type(s). Supported actions were still restored.")
	end
	if macroResult.failed > 0 or macroResult.cleanupFailed > 0 or staleActionResult.failed > 0 then
		PrintMessage("Setup details: macro sync failures " .. macroResult.failed
			.. ", stale-macro removal failures " .. macroResult.cleanupFailed
			.. ", action-slot clear failures " .. staleActionResult.failed .. ".")
	end
	if actionResult.missingMacros > 0 or actionResult.unavailableSpells > 0
		or actionResult.unavailableItems > 0 or actionResult.failed > 0 then
		PrintMessage("Action details: missing macros " .. actionResult.missingMacros
			.. ", unavailable spells " .. actionResult.unavailableSpells
			.. ", unavailable items " .. actionResult.unavailableItems
			.. ", failed placements " .. actionResult.failed .. ".")
	end
	if blizzardOptionResult.stored > 0 then
		if blizzardOptionResult.deferred > 0 then
			PrintMessage("Blizzard action-bar options are waiting until they can be safely applied out of combat.")
		else
			PrintMessage("Blizzard action-bar options: " .. blizzardOptionResult.matched .. "/"
				.. blizzardOptionResult.stored .. " matched; " .. (blizzardOptionResult.live or blizzardOptionResult.changed or 0)
				.. " changed live, " .. (blizzardOptionResult.persisted or 0) .. " persisted for next login, "
				.. (blizzardOptionResult.queued or 0) .. " waiting for next login, "
				.. blizzardOptionResult.failed .. " failed.")
		end
	end
	if editModeLayoutResult.stored > 0 then
		if editModeLayoutResult.deferred > 0 then
			PrintMessage("Edit Mode layout selection is waiting for Blizzard's layout data to finish loading.")
		elseif editModeLayoutResult.missing > 0 then
			local typeText = editModeLayoutResult.layoutType == EDIT_MODE_LAYOUT_CHARACTER
				and " Character-specific layouts are not shared with a newly created character." or ""
			PrintMessage("Saved Edit Mode layout '" .. tostring(editModeLayoutResult.name or "unknown")
				.. "' is not available on this character." .. typeText)
		else
			PrintMessage("Edit Mode layout '" .. tostring(editModeLayoutResult.name or editModeLayoutResult.targetIndex)
				.. "': " .. editModeLayoutResult.matched .. "/" .. editModeLayoutResult.stored
				.. " matched; " .. editModeLayoutResult.changed .. " changed, "
				.. editModeLayoutResult.failed .. " failed.")
		end
	end
end

local restoreScheduled = false

local function NotifyActionBarReloadIfNeeded(job)
	local result = job and job.blizzardOptionResult
	if type(result) ~= "table" or (tonumber(result.queued) or 0) <= 0 then
		return false
	end
	PrintMessage("Some Blizzard action-bar visibility changes could not be applied live and are queued for the next login.")
	return true
end

FinalizeAutomaticRestore = function(job)
	if not job or job.finalized then return end
	job.finalized = true
	restoreRuntimeActive = false
	ReleaseSessionActionBarDrivers("restore finalized")
	if MaybeReleaseRestoreRuntime then MaybeReleaseRestoreRuntime() end

    -- Manual staged applies reuse the same engine but have no automatic
    -- bootstrap record to mark/retry. Their completion is intentionally local.
    if not job.bootstrapState then
		NotifyActionBarReloadIfNeeded(job)
		return
	end

	local cleanRun = (tonumber(job.failedStages) or 0) == 0
	if cleanRun and RestoreLooksSuccessful(job.macroResult, job.actionResult) then
		MarkCharacterBootstrapped(job.bootstrapState)
		NotifyActionBarReloadIfNeeded(job)
		return
	end

	-- The old build marked the character bootstrapped unconditionally. A run that restored
	-- nothing then looked identical to a successful one, and the next login silently did
	-- nothing at all. Incomplete runs are now recorded as attempts so they retry.
	local attempts = MarkCharacterBootstrapAttempt(job.bootstrapState)
	if attempts >= MAX_BOOTSTRAP_ATTEMPTS then
		PrintMessage("Setup did not fully apply after " .. attempts
			.. " attempts and will not retry automatically. Use Apply Stored Profile, or Reset Character Record to start over.")
	else
		PrintMessage("Setup was incomplete (attempt " .. attempts .. " of " .. MAX_BOOTSTRAP_ATTEMPTS
			.. "); it will retry on next login. Use Apply Stored Profile to retry now.")
	end
end

local function ScheduleAutomaticRestoreStep(job, delay)
	if automaticRestoreJob ~= job then return end

	-- The combat poll and PLAYER_REGEN_ENABLED can both try to resume the same job. Only the
	-- most recently scheduled step is allowed to run, so the job never advances twice a frame.
	job.stepToken = (tonumber(job.stepToken) or 0) + 1
	local token = job.stepToken

	local function Callback()
		if automaticRestoreJob ~= job or job.stepToken ~= token then return end

		local stageBefore = job.stage
		local ok = xpcall(function()
			ProcessAutomaticRestoreJob(job)
		end, geterrorhandler())
		if ok then
			job.stageErrors = 0
			return
		end

		-- One failing stage must not abandon the job. By the time most stages run, macros
		-- have already been synchronized and bindings rewritten, so bailing out leaves the
		-- character in a worse state than never having started.
		job.stageErrors = (tonumber(job.stageErrors) or 0) + 1
		if job.stage == stageBefore and job.stageErrors <= AUTO_STAGE_RETRIES then
			ScheduleAutomaticRestoreStep(job, 0.5)
			return
		end

		job.stageErrors = 0
		job.failedStages = (tonumber(job.failedStages) or 0) + 1
		local nextStage = stageBefore and AUTO_STAGE_ORDER[stageBefore]
		if nextStage then
			job.stage = nextStage
			PrintMessage("Setup stage '" .. tostring(stageBefore) .. "' failed; skipping it and continuing.")
			ScheduleAutomaticRestoreStep(job, 0.5)
		else
			automaticRestoreJob = nil
			restoreScheduled = false
				PrintMessage(QuickPolicy("externalPersistence") and "Automatic restore was interrupted; use Apply Stored Profile to retry." or "Automatic restore was interrupted; use /reload or Apply Stored Profile to retry.")
			FinalizeAutomaticRestore(job)
		end
	end

	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(delay or 0, Callback)
	else
		Callback()
	end
end

StartAutomaticActionRetry = function(profile, retrySlots, job)
	if type(retrySlots) ~= "table" or #retrySlots == 0 or not C_Timer or type(C_Timer.After) ~= "function" then
		FinalizeAutomaticRestore(job)
		return
	end
	local copiedSlots = {}
	for index, slot in ipairs(retrySlots) do copiedSlots[index] = slot end

	local state
	local combatWaits = 0
	local function ProcessRetry()
        if job and job.exact and not IsFreshLevelOne() then
            FinalizeAutomaticRestore(job)
            return
        end
		if InCombatLockdown() then
			combatWaits = combatWaits + 1
			if combatWaits > MAX_COMBAT_WAITS then
				FinalizeAutomaticRestore(job)
				return
			end
			C_Timer.After(1, ProcessRetry)
			return
		end

		-- State construction is inside the pcall too: this runs from a bare C_Timer callback,
		-- so an unprotected error here would strand the job without ever finalizing it.
		local ok, done = pcall(function()
			state = state or CreateActionLoadState(profile, copiedSlots)
			return ProcessActionLoadBatch(state, AUTO_ACTION_PLACE_BATCH)
		end)
		if not ok or type(state) ~= "table" then
			-- The retry pass is best effort; a failure here must not strand the bootstrap flag.
			FinalizeAutomaticRestore(job)
			return
		end

		if done then
			-- Fold retry successes into the job totals so the completion check sees them.
			if job and type(job.actionResult) == "table" then
				job.actionResult.loaded = (tonumber(job.actionResult.loaded) or 0)
					+ (tonumber(state.result.loaded) or 0)
			end
			if state.result.loaded < state.result.stored then
				PrintMessage("Action-bar retry for " .. profile .. ": placed " .. state.result.loaded .. "/"
					.. state.result.stored .. "; missing macros " .. state.result.missingMacros
					.. ", unavailable spells " .. state.result.unavailableSpells
					.. ", unavailable items " .. state.result.unavailableItems
					.. ", failed " .. state.result.failed .. ".")
			end
			FinalizeAutomaticRestore(job)
		else
			C_Timer.After(0, ProcessRetry)
		end
	end
	C_Timer.After(3, ProcessRetry)
end

ProcessAutomaticRestoreJob = function(job)
	if automaticRestoreJob ~= job then return end

	if InCombatLockdown() then
		-- PLAYER_REGEN_ENABLED normally resumes the job, but it is not guaranteed to arrive
		-- for every lockdown condition, so poll as well rather than stalling forever.
		job.waitingForCombat = true
		job.combatWaits = (tonumber(job.combatWaits) or 0) + 1
		if job.combatWaits <= MAX_COMBAT_WAITS then
			ScheduleAutomaticRestoreStep(job, 1)
		else
			automaticRestoreJob = nil
			restoreScheduled = false
			PrintMessage("Setup timed out waiting for combat to end; use Apply Stored Profile when out of combat.")
			FinalizeAutomaticRestore(job)
		end
		return
	end
	job.waitingForCombat = false
	job.combatWaits = 0

	-- Each stage builds its own working state lazily. If a stage is retried or skipped after
	-- an error, the next stage can still construct what it needs instead of hitting a nil.
	if job.stage == "macros" then
		job.macroResult = SynchronizeMacros(job.profile, job.exact == true)
		job.stage = "bindings"
		ScheduleAutomaticRestoreStep(job)
		return
	end

	if job.stage == "bindings" then
		job.bindingState = job.bindingState or CreateKeyBindLoadState(job.profile)
		if ProcessKeyBindLoadBatch(job.bindingState, AUTO_BINDING_SCAN_BATCH, AUTO_BINDING_MUTATION_BATCH) then
			job.bindingCount = job.bindingState.loaded
			job.stage = "placeActions"
		end
		ScheduleAutomaticRestoreStep(job)
		return
	end

	-- Placement runs before cleanup. The old order cleared every unstored slot first, so an
	-- error between the two phases left the player with a wiped action bar and nothing back.
	if job.stage == "placeActions" then
		job.actionLoadState = job.actionLoadState or CreateActionLoadState(job.profile)
		if ProcessActionLoadBatch(job.actionLoadState, AUTO_ACTION_PLACE_BATCH) then
			job.actionResult = job.actionLoadState.result
			job.stage = "clearActions"
		end
		ScheduleAutomaticRestoreStep(job)
		return
	end

	if job.stage == "clearActions" then
        if job.exact and (tonumber(job.unsupportedActions) or 0) == 0 then
            job.actionClearState = job.actionClearState or CreateActionClearState(job.profile)
            if ProcessActionClearBatch(job.actionClearState, AUTO_ACTION_CLEAR_BATCH) then
                job.staleActionResult = job.actionClearState.result
                job.stage = "blizzardOptions"
            end
        else
            job.staleActionResult = {
				cleared = 0,
				failed = 0,
				skippedUnsupported = job.exact and (tonumber(job.unsupportedActions) or 0) or 0,
			}
            job.stage = "blizzardOptions"
        end
		ScheduleAutomaticRestoreStep(job)
		return
	end

	if job.stage == "blizzardOptions" then
		job.blizzardOptionResult = ApplyBlizzardOptions(job.profile, false)
		job.stage = "editMode"
		ScheduleAutomaticRestoreStep(job)
		return
	end

	if job.stage == "editMode" then
		job.editModeLayoutResult = ApplyEditModeLayout(job.profile, false)
		job.stage = "finish"
		ScheduleAutomaticRestoreStep(job)
		return
	end

	ReportLoadResults(job.profile, job.source or "automatic", job.exact == true, job.storedBindings, job.macroResult,
		job.bindingCount, job.staleActionResult, job.actionResult,
		job.blizzardOptionResult, job.editModeLayoutResult)
	if (tonumber(job.failedStages) or 0) > 0 then
		PrintMessage("Note: " .. job.failedStages .. " setup stage(s) were skipped after repeated errors.")
	end

	local retrySlots = type(job.actionResult) == "table" and job.actionResult.retrySlots or nil
	automaticRestoreJob = nil
	-- The bootstrap flag is written by FinalizeAutomaticRestore once the retry pass has had
	-- its chance, so late successes still count toward completion.
	StartAutomaticActionRetry(job.profile, retrySlots, job)
end

local function ResumeAutomaticRestoreAfterCombat()
	local job = automaticRestoreJob
	if job and job.waitingForCombat then
		job.waitingForCombat = false
		job.combatWaits = 0
		ScheduleAutomaticRestoreStep(job)
	end
end

-- Records why automatic setup did or did not run so the integrated debug/status surface can report it.
local lastRestoreDecision = "not evaluated"

local function StartStagedRestore(profileToken, exact, source, bootstrapState)
    if automaticRestoreJob then return false, "a restore job is already running" end
    if exact and not IsFreshLevelOne() then
        return false, "exact fresh-character restore requires Level 1 with 0 XP"
    end
    local storedProfile = GetClassProfile(profileToken) or {}
    local storedMacros = CountEntries(storedProfile.macros)
    local storedBindings = CountEntries(storedProfile.bindings)
    local storedActions = CountEntries(storedProfile.actions)
	local unsupportedActions = CountEntries(storedProfile.unsupportedActions)
    if storedMacros == 0 and storedBindings == 0 and storedActions == 0 then
        return false, "no stored profile exists for " .. tostring(profileToken)
    end
    restoreScheduled = false
    automaticRestoreJob = {
        profile = profileToken,
        bootstrapState = bootstrapState,
        storedBindings = storedBindings,
        exact = exact == true,
        source = source or "manual",
		unsupportedActions = unsupportedActions,
        stage = "macros",
    }
	restoreRuntimeActive = true
	if eventFrame then
		eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
    ScheduleAutomaticRestoreStep(automaticRestoreJob)
    return true
end

local function AttemptAutomaticRestore(attempt)
	local level = tonumber(UnitLevel("player"))
	local xp = tonumber(UnitXP("player"))
	local bootstrapState = GetCharacterBootstrapState()
	if not level or level == 0 or xp == nil or not bootstrapState or not ResolveCharacterTokens() then
		if attempt < 15 then
			C_Timer.After(1, function()
				AttemptAutomaticRestore(attempt + 1)
			end)
		else
			restoreScheduled = false
			lastRestoreDecision = "character identity or level/XP data never became available"
			PrintMessage("Automatic restore could not read character identity or level/XP data; use Apply Stored Profile.")
		end
		return
	end

	if automaticRestoreJob then
		lastRestoreDecision = "a restore job is already running"
		return
	end

	if not IsFreshLevelOne() then
		restoreScheduled = false
		lastRestoreDecision = "character is not a fresh level one (level " .. level .. ", xp " .. xp .. ")"
		return
	end

	if not bootstrapState.firstSetup then
		restoreScheduled = false
		-- This used to return with no output at all, which is what a player experiences as
		-- "quick setup does nothing" on a character that already ran setup once.
		if bootstrapState.exhausted then
			lastRestoreDecision = "retry budget exhausted after " .. bootstrapState.attempts .. " incomplete attempts"
			PrintMessage("Automatic setup is disabled for this character after " .. bootstrapState.attempts
				.. " incomplete attempts. Use Apply Stored Profile to retry, or Reset Character Record to re-enable it.")
		else
			lastRestoreDecision = "setup already completed for this character GUID"
			PrintMessage("Setup already ran on this character. Use Apply Stored Profile to load the profile again, "
				.. "or Reset Character Record if the character was never actually set up.")
		end
		return
	end

	if InCombatLockdown() then
		if attempt < 30 then
			C_Timer.After(1, function() AttemptAutomaticRestore(attempt + 1) end)
		else
			restoreScheduled = false
			lastRestoreDecision = "still in combat lockdown after 30 seconds"
			PrintMessage("Automatic restore is waiting for combat to end; use Apply Stored Profile afterward if needed.")
		end
		return
	end

	local storedMacros = CountEntries((GetClassProfile(class) or {}).macros)
	local storedBindings = CountEntries((GetClassProfile(class) or {}).bindings)
	local storedActions = CountEntries((GetClassProfile(class) or {}).actions)
	if storedMacros == 0 and storedBindings == 0 and storedActions == 0 then
		restoreScheduled = false
		lastRestoreDecision = "no stored profile for " .. tostring(class)
		PrintMessage("No stored profile exists for " .. tostring(class)
			.. ". Save one on a configured character with Save Current Class Profile.")
		return
	end

	if bootstrapState.recreated then
		PrintMessage("Detected a recreated character name; cleaning inherited character data before setup.")
	end
	if bootstrapState.attempts > 0 then
		PrintMessage("Resuming setup after a previous incomplete attempt ("
			.. bootstrapState.attempts .. " of " .. MAX_BOOTSTRAP_ATTEMPTS .. ").")
	end

	lastRestoreDecision = "running"
    local started, startErr = StartStagedRestore(class, true, "automatic", bootstrapState)
    if not started then
        restoreScheduled = false
        lastRestoreDecision = startErr or "could not start restore"
    end
end

local function ScheduleAutomaticRestore()
	if restoreScheduled then return end
	restoreScheduled = true
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(1, function()
			AttemptAutomaticRestore(1)
		end)
	else
		AttemptAutomaticRestore(1)
	end
end

local initialized = false
local automaticConfigState = false
local cinematicConfigState = false
eventFrame = CreateFrame("Frame")

MaybeReleaseRestoreRuntime = function()
	if restoreRuntimeActive or automaticRestoreJob or pendingEditModeLayout or runtimeCleanupPending then
		return false
	end
	-- CINEMATIC_START is owned by the independent Auto-skip option and remains
	-- registered when enabled. These two events belong only to the restore engine.
	eventFrame:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	return true
end

-- Cinematic skipping is independent from the destructive automatic restore
-- master. Arm it as soon as the file loads when the persisted option is on so
-- a fresh-character intro cannot outrun PLAYER_LOGIN. The callback performs no
-- CVar writes; persistent CVar ownership remains Core-login-only.
do
    local raw = type(TurboFaceDB) == "table" and TurboFaceDB.quickSetup
    if type(raw) == "table" and raw.autoSkipCinematic ~= false then
        eventFrame:RegisterEvent("CINEMATIC_START")
    end
end

function QuickSetup:Init()
    if initialized then return end

    EnsureStores()
    local cfg = Config()
    local charRoot = CharRoot()
    local pending = charRoot.pendingManualApply
    automaticConfigState = cfg and cfg.enabled == true or false
    cinematicConfigState = cfg and cfg.autoSkipCinematic == true or false
    initialized = true

    -- Cinematic skipping is a standalone Level-1 convenience toggle. It does
    -- not require automatic profile restoration to be enabled.
    if cinematicConfigState then
        eventFrame:RegisterEvent("CINEMATIC_START")
    else
        eventFrame:UnregisterEvent("CINEMATIC_START")
    end

    local runtimeRequested = type(pending) == "table" or automaticConfigState
    if not runtimeRequested then
        lastRestoreDecision = "automatic setup disabled"
        return
    end

    -- The persistent CVar baseline is only safe at this early Core-owned login
    -- boundary. If player identity is unexpectedly unavailable here, do not retry
    -- after Plus/System has initialized; leave any manual handoff intact and ask
    -- for a reload instead of performing a late conflicting write.
    if not ResolveCharacterTokens() then
        lastRestoreDecision = "player identity unavailable at early CVar boundary"
		PrintMessage(QuickPolicy("externalPersistence") and "Could not resolve class/race at the early login boundary; try Apply Stored Profile after login finishes." or "Could not resolve class/race at the early login boundary; /reload before applying Quick Setup.")
        return
    end

    local hasPending = type(pending) == "table" and CLASS_TOKENS[pending.class] and pending.class == class
    if pending ~= nil and not hasPending then
        -- Per-character handoffs should always match the character class. A stale
        -- or malformed handoff must never survive forever or target another class.
        charRoot.pendingManualApply = nil
        pending = nil
    end
    if not hasPending and not automaticConfigState then
        lastRestoreDecision = "automatic setup disabled"
        return
    end

    if hasPending then
        -- Apply the persistent baseline now, before Plus/System is initialized.
        ApplyCVars(pending.class)
        charRoot.pendingManualApply = nil
        local pendingExact = pending.exact == true
        C_Timer.After(0.5, function()
            local bootstrapState = pendingExact and GetCharacterBootstrapState() or nil
            local started, err = StartStagedRestore(pending.class, pendingExact, "manual", bootstrapState)
            if not started then PrintMessage(err or "Could not start stored profile apply.") end
        end)
    elseif automaticConfigState then
        local level = tonumber(UnitLevel("player"))
        local xp = tonumber(UnitXP("player"))
        if level == 1 and xp ~= nil and xp <= FRESH_XP_ALLOWANCE then
            -- One-shot persistent baseline before Plus/System acquires temporary CVar ownership.
            ApplyCVars(class)
            -- Blizzard Action Bars 2-8 are restored later in the staged job with
            -- temporary secure visibility drivers. Those drivers are explicitly
            -- released when the one-shot bootstrap finishes.
            ScheduleAutomaticRestore()
        elseif level and level > 0 and xp ~= nil then
            -- The automatic engine still records its normal non-fresh decision,
            -- but no persistent CVars are changed on established characters.
            ScheduleAutomaticRestore()
        else
            lastRestoreDecision = "level/XP unavailable at early CVar boundary"
			PrintMessage(QuickPolicy("externalPersistence") and "Level/XP was unavailable at the early login boundary; use Apply Stored Profile after login finishes." or "Level/XP was unavailable at the early login boundary; /reload before automatic setup.")
        end
    end
end

function QuickSetup:Refresh()
    if not initialized then return end
    local cfg = Config()
    local enabled = cfg and cfg.enabled == true or false
    local cinematic = cfg and cfg.autoSkipCinematic == true or false

    -- Cinematic ownership is independent and can be toggled live.
    if cinematic then
        eventFrame:RegisterEvent("CINEMATIC_START")
    else
        eventFrame:UnregisterEvent("CINEMATIC_START")
    end

    if enabled ~= automaticConfigState then
        if enabled then
            -- Enabling mid-session deliberately does not start a restore. Quick Setup's
            -- persistent CVar baseline must be applied at the early login boundary before
            -- Plus/System acquires temporary CVar ownership, so arm it for the next reload.
			if QuickPolicy("externalPersistence") then
				lastRestoreDecision = "enabled; automatic setup will arm on next login"
				PrintMessage("Enabled for the next login. Log out and run the Forever save helper to persist this setting.")
			else
				lastRestoreDecision = "enabled; automatic setup will arm on next reload"
				PrintMessage("Enabled. /reload to arm automatic Level 1 setup for this character.")
			end
        else
            restoreScheduled = false
            lastRestoreDecision = "automatic setup disabled"
            -- A staged restore that has already begun is allowed to finish. Aborting between
            -- macro/binding/action stages could leave the character in a partially rewritten state.
            if automaticRestoreJob then
                PrintMessage("Disabled for future logins; the restore already in progress will finish safely.")
            else
                MaybeReleaseRestoreRuntime()
            end
        end
    end

    automaticConfigState = enabled
    cinematicConfigState = cinematic
end

function QuickSetup:GetCurrentClassToken()
    ResolveCharacterTokens()
    return class
end

function QuickSetup:GetStoredClassTokens()
    local out = {}
    local root = ProfilesRoot()
    for token, profile in pairs(root.classes) do
        if CLASS_TOKENS[token] and type(profile) == "table" then
            out[#out + 1] = token
        end
    end
    table.sort(out)
    return out
end

function QuickSetup:HasProfile(token)
    local profile = GetClassProfile(token)
    return type(profile) == "table"
        and (CountEntries(profile.macros) > 0 or CountEntries(profile.bindings) > 0 or CountEntries(profile.actions) > 0)
end

function QuickSetup:SaveCurrentClassProfile()
    if not ResolveCharacterTokens() then
        PrintMessage("Character class is not available yet.")
        return false
    end
    return SaveProfile(class)
end

function QuickSetup:ApplyCurrentClassProfile()
    if not ResolveCharacterTokens() then
        PrintMessage("Character class is not available yet.")
        return false
    end
    if InCombatLockdown() then
        PrintMessage("Cannot apply a stored profile while in combat.")
        return false
    end
    if not self:HasProfile(class) then
        PrintMessage("No stored profile exists for " .. tostring(class) .. ".")
        return false
    end

	-- A reload handoff cannot work while Forever fails to reload SavedVariables:
	-- the generated preload would restore the older character snapshot and erase
	-- the pending flag. Start the same staged engine immediately instead. The CVar
	-- baseline helper updates ownership snapshots without fighting active overrides.
	if QuickPolicy("immediateManualApply") then
		local exact = IsFreshLevelOne()
		local bootstrapState = exact and GetCharacterBootstrapState() or nil
		local started, err = StartStagedRestore(class, exact, "manual", bootstrapState)
		if not started then PrintMessage(err or "Could not start stored profile apply."); return false end
		CharRoot().pendingManualApply = nil
		local cvarCount = ApplyCVars(class)
		PrintMessage("Applying stored " .. tostring(class) .. " profile now (" .. cvarCount .. " CVar baselines updated).")
		return true
	end
	local charRoot = CharRoot()
	charRoot.pendingManualApply = { class = class, exact = IsFreshLevelOne(), time = time() }
	PrintMessage("Stored " .. tostring(class) .. " profile is prepared. Type /reload to apply it.")
	return true
end

function QuickSetup:ResetCharacterRecord()
	local cleared = ClearCharacterBootstrap()
	if cleared then
		if QuickPolicy("immediateResetRetry") and Config() and Config().enabled == true and IsFreshLevelOne() and not automaticRestoreJob then
			ApplyCVars(class); ScheduleAutomaticRestore()
			PrintMessage("Cleared the setup record; automatic setup is starting again now.")
		elseif QuickPolicy("externalPersistence") then
			PrintMessage("Cleared the setup record. Log out and run the Forever save helper to preserve the reset for a future login.")
		else
			PrintMessage("Cleared the setup record for this character. /reload to run automatic setup again.")
		end
    else
        PrintMessage("No setup record exists for this character; automatic setup is already eligible to run.")
    end
    return cleared
end

local function DescribeBootstrapState(state)
    if not state then return "identity unavailable" end
    if state.exhausted then return "disabled after " .. state.attempts .. " incomplete attempts" end
    if state.completed then return "already applied" end
    if state.attempts > 0 then
        return "not yet applied (" .. state.attempts .. " incomplete attempt(s))"
    end
    return "not yet applied"
end

function QuickSetup:GetStatusText(token)
    token = token or self:GetCurrentClassToken()
    if not token then return "Character class unavailable" end
    local profile = GetClassProfile(token) or {}
    local bootstrapState = token == class and GetCharacterBootstrapState() or nil
	return ClassDisplayName(token) .. ": " .. CountEntries(profile.macros) .. " macros / "
		.. CountEntries(profile.bindings) .. " bindings / " .. CountEntries(profile.actions) .. " actions"
		.. (CountEntries(profile.unsupportedActions) > 0 and (" / " .. CountEntries(profile.unsupportedActions) .. " unsupported") or "")
		.. " / Edit Mode: "
		.. DescribeSavedEditModeLayout(token) .. (token == class and (" / " .. DescribeBootstrapState(bootstrapState)) or "")
end

function QuickSetup:DebugStatus()
    local state = GetCharacterBootstrapState()
	local profile = GetClassProfile(class) or {}
	local driverCount = 0
	for _ in pairs(sessionActionBarDriverFrames) do driverCount = driverCount + 1 end
    PrintMessage("Debug " .. ENGINE_VERSION .. " | class=" .. tostring(class) .. " race=" .. tostring(race)
        .. " level=" .. tostring(UnitLevel("player")) .. " xp=" .. tostring(UnitXP("player"))
        .. " fresh=" .. tostring(IsFreshLevelOne()) .. " combat=" .. tostring(InCombatLockdown()))
    PrintMessage("Debug identity | guid=" .. tostring(state and state.guid)
        .. " storedGuid=" .. tostring(state and state.previousGUID)
        .. " recreated=" .. tostring(state and state.recreated))
    PrintMessage("Debug gate | firstSetup=" .. tostring(state and state.firstSetup)
        .. " completed=" .. tostring(state and state.completed)
        .. " attempts=" .. tostring(state and state.attempts)
        .. " exhausted=" .. tostring(state and state.exhausted))
    PrintMessage("Debug job | scheduled=" .. tostring(restoreScheduled)
        .. " stage=" .. tostring(automaticRestoreJob and automaticRestoreJob.stage)
        .. " waitingForCombat=" .. tostring(automaticRestoreJob and automaticRestoreJob.waitingForCombat)
        .. " failedStages=" .. tostring(automaticRestoreJob and automaticRestoreJob.failedStages)
		.. " drivers=" .. tostring(driverCount)
			.. " cleanupPending=" .. tostring(runtimeCleanupPending)
			.. " editModePending=" .. tostring(pendingEditModeLayout ~= nil)
	        .. " | decision: " .. tostring(lastRestoreDecision))
	PrintMessage("Debug profile | macroLimits=" .. tostring(MAX_ACCOUNT_MACROS_COMPAT) .. "/"
		.. tostring(MAX_CHARACTER_MACROS_COMPAT) .. " actions=" .. tostring(CountEntries(profile.actions))
		.. " unsupportedActions=" .. tostring(CountEntries(profile.unsupportedActions)))
end

local function RejectUnknownKeys(tbl, allowed, label)
    for key in pairs(tbl) do
        if not allowed[key] then return false, "unknown " .. label .. " field: " .. tostring(key) end
    end
    return true
end

local function ValidateImportedProfile(token, source)
    if not CLASS_TOKENS[token] then return nil, "invalid class token" end
    if type(source) ~= "table" then return nil, "missing profile" end
    if source.version ~= PROFILE_SCHEMA_VERSION then return nil, "unsupported Quick Setup profile version" end
    if source.class ~= token then return nil, "profile class does not match payload class" end
	local okKeys, keyErr = RejectUnknownKeys(source, { version=true, class=true, macros=true, bindings=true,
		actions=true, unsupportedActions=true, blizzard=true, cvars=true }, "profile")
    if not okKeys then return nil, keyErr end

    local clean = { version = PROFILE_SCHEMA_VERSION, class = token }

    if source.macros ~= nil then
        if type(source.macros) ~= "table" then return nil, "macros must be a table" end
        clean.macros = {}
        local macroCount, maxMacroIndex = 0, 0
        for key in pairs(source.macros) do
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
                return nil, "invalid macro table key"
            end
            macroCount = macroCount + 1
            if key > maxMacroIndex then maxMacroIndex = key end
        end
        if macroCount > (MAX_ACCOUNT_MACROS_COMPAT + MAX_CHARACTER_MACROS_COMPAT) then
            return nil, "too many macros"
        end
        if maxMacroIndex ~= macroCount then return nil, "macro list must be contiguous" end
        for i = 1, maxMacroIndex do
            local macro = source.macros[i]
            if type(macro) ~= "table" or type(macro[1]) ~= "string" or macro[1] == ""
                or (#macro[1] > 64) then
                return nil, "invalid macro entry"
            end
            for key in pairs(macro) do
                if key ~= 1 and key ~= 2 and key ~= 3 and key ~= 4 then
                    return nil, "unknown macro entry field: " .. tostring(key)
                end
            end
            local icon = macro[2]
            if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then
                return nil, "invalid macro icon"
            end
            if type(macro[3]) ~= "string" or #macro[3] > 4096 then return nil, "invalid macro body" end
            if macro[4] ~= nil and macro[4] ~= true then return nil, "invalid macro scope" end
            clean.macros[i] = { macro[1], icon, macro[3], macro[4] }
        end
    end

    if source.bindings ~= nil then
        if type(source.bindings) ~= "table" then return nil, "bindings must be a table" end
        clean.bindings = {}
        local count = 0
        for key, command in pairs(source.bindings) do
            count = count + 1
            if count > 512 or type(key) ~= "string" or #key > 64
                or type(command) ~= "string" or #command > 128 then
                return nil, "invalid binding entry"
            end
            clean.bindings[key] = command
        end
    end

	if source.actions ~= nil then
		if type(source.actions) ~= "table" then return nil, "actions must be a table" end
		clean.actions = {}
		for rawSlot, action in pairs(source.actions) do
			local slot = rawSlot
			if type(slot) ~= "number" or slot < 1 or slot > MAX_ACTION_SLOTS or slot ~= math.floor(slot) or type(action) ~= "table" then return nil, "invalid action slot" end
			local actionKeysOK, actionKeyErr = RejectUnknownKeys(action, { kind=true, value=true, scope=true }, "action")
			if not actionKeysOK then return nil, actionKeyErr end
			local kind, value = action.kind, action.value
			if kind ~= "macro" and kind ~= "spell" and kind ~= "item" then return nil, "invalid action type" end
			if kind == "macro" then
				if type(value) ~= "string" or value == "" or #value > 64 then return nil, "invalid macro action" end
				if action.scope ~= nil and action.scope ~= "account" and action.scope ~= "character" then return nil, "invalid macro action scope" end
				clean.actions[slot] = { kind=kind, value=value, scope=action.scope }
			else
				if type(value) ~= "number" or value < 1 or value ~= math.floor(value) then return nil, "invalid action id" end
				clean.actions[slot] = { kind=kind, value=value }
			end
		end
	end

	if source.unsupportedActions ~= nil then
		if type(source.unsupportedActions) ~= "table" then return nil, "unsupported actions must be a table" end
		clean.unsupportedActions = {}
		for slot, actionType in pairs(source.unsupportedActions) do
			if type(slot) ~= "number" or slot < 1 or slot > MAX_ACTION_SLOTS or slot ~= math.floor(slot) or type(actionType) ~= "string" or actionType == "" or #actionType > 64 then return nil, "invalid unsupported action" end
			clean.unsupportedActions[slot] = actionType
		end
		if next(clean.unsupportedActions) == nil then clean.unsupportedActions = nil end
	end

    if source.blizzard ~= nil then
        if type(source.blizzard) ~= "table" then return nil, "blizzard settings must be a table" end
        local blizzKeysOK, blizzKeyErr = RejectUnknownKeys(source.blizzard, { actionBars=true, editModeLayout=true }, "Blizzard")
        if not blizzKeysOK then return nil, blizzKeyErr end
        clean.blizzard = {}
        if source.blizzard.actionBars ~= nil then
            if type(source.blizzard.actionBars) ~= "table" then return nil, "invalid action-bar settings" end
            for key, value in pairs(source.blizzard.actionBars) do
                if type(key) ~= "number" or key < 2 or key > 8 or key ~= math.floor(key) or type(value) ~= "boolean" then
                    return nil, "invalid action-bar setting"
                end
            end
            clean.blizzard.actionBars = {}
            for bar = 2, 8 do
                local value = source.blizzard.actionBars[bar]
                if type(value) ~= "boolean" then return nil, "missing or invalid action-bar setting" end
                clean.blizzard.actionBars[bar] = value
            end
        end
        if source.blizzard.editModeLayout ~= nil then
            local saved = source.blizzard.editModeLayout
            if type(saved) ~= "table" then return nil, "invalid Edit Mode layout" end
            local layoutKeysOK, layoutKeyErr = RejectUnknownKeys(saved, { index=true, name=true, layoutType=true }, "Edit Mode")
            if not layoutKeysOK then return nil, layoutKeyErr end
            local index = tonumber(saved.index)
            if index and (index < 1 or index ~= math.floor(index)) then return nil, "invalid Edit Mode index" end
            if saved.name ~= nil and (type(saved.name) ~= "string" or #saved.name > 128) then
                return nil, "invalid Edit Mode name"
            end
            if saved.layoutType ~= nil and type(saved.layoutType) ~= "number" then
                return nil, "invalid Edit Mode type"
            end
            clean.blizzard.editModeLayout = { index = index, name = saved.name, layoutType = saved.layoutType }
        end
    end

    if source.cvars ~= nil then
        if type(source.cvars) ~= "table" then return nil, "CVars must be a table" end
        clean.cvars = {}
        local allow = {}
        for _, name in ipairs(QUICK_SETUP_CVARS) do allow[name] = true end
        for name, value in pairs(source.cvars) do
            if not allow[name] then return nil, "unknown Quick Setup CVar: " .. tostring(name) end
            local t = type(value)
            if t ~= "string" and t ~= "number" and t ~= "boolean" then return nil, "invalid CVar value" end
            clean.cvars[name] = tostring(value)
        end
    end

    return clean
end

function QuickSetup:ExportClassProfile(token)
    token = token or self:GetCurrentClassToken()
    if not CLASS_TOKENS[token] then return nil, "invalid class" end
    local profile = GetClassProfile(token)
    if not profile then return nil, "no stored " .. token .. " Quick Setup profile" end
    if not (ns.Profiles and ns.Profiles.Serialize) then return nil, "profile serializer unavailable" end
    return EXPORT_PREFIX .. ns.Profiles.Serialize({ version = 1, class = token, profile = profile })
end

function QuickSetup:ValidateImport(str)
    if type(str) ~= "string" then return nil, "empty string" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "not a valid Lvl1QuickSetup export (expected TFL1QS1 prefix)"
    end
    if not (ns.Profiles and ns.Profiles.Deserialize) then return nil, "profile parser unavailable" end
    local parsed, err = ns.Profiles.Deserialize(str:sub(#EXPORT_PREFIX + 1))
    if not parsed then return nil, err end
    if parsed.version ~= 1 or not CLASS_TOKENS[parsed.class] then
        return nil, "unsupported or invalid Lvl1QuickSetup payload"
    end
    local payloadKeysOK, payloadKeyErr = RejectUnknownKeys(parsed, { version=true, class=true, profile=true }, "payload")
    if not payloadKeysOK then return nil, payloadKeyErr end
    local clean, validationErr = ValidateImportedProfile(parsed.class, parsed.profile)
    if not clean then return nil, validationErr end
    return { class = parsed.class, profile = clean }
end

function QuickSetup:ImportClassProfile(payload)
    if type(payload) ~= "table" or not CLASS_TOKENS[payload.class] or type(payload.profile) ~= "table" then
        return false
    end
    local clean, err = ValidateImportedProfile(payload.class, payload.profile)
    if not clean then
        PrintMessage("Import failed: " .. tostring(err))
        return false
    end
    ProfilesRoot().classes[payload.class] = clean
    PrintMessage("Imported " .. payload.class .. " Lvl1QuickSetup profile. The active character was not changed.")
    return true
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ApplyPendingEditModeLayout()
    elseif event == "PLAYER_REGEN_ENABLED" then
		if runtimeCleanupPending then
			ReleaseSessionActionBarDrivers("combat ended")
		end
        ApplyPendingEditModeLayout()
        ResumeAutomaticRestoreAfterCombat()
		MaybeReleaseRestoreRuntime()
    elseif event == "CINEMATIC_START" then
        local cfg = Config()
        if cfg and cfg.autoSkipCinematic and tonumber(UnitLevel("player")) == 1 then
            if StopCinematic then StopCinematic() end
            if CameraZoomOut then CameraZoomOut(50) end
        end
    end
end)
