local _, ns = ...

-- Blizzard owns the native nameplate health text's content, formatting, font,
-- color, visibility, and update lifecycle. TurboFace owns one deliberately
-- narrow, optional presentation amendment: on normal native full plates,
-- re-anchor the existing Blizzard FontStrings at a user-selected native center.
--
-- Classic Era 1.15.9 marks these health-text FontStrings as restricted regions.
-- Addon code may not measure them with GetPoint/GetCenter/GetLeft/GetRight (or
-- related FrameMeasurement methods). This module is therefore WRITE-ONLY with
-- respect to their geometry: it never reads, snapshots, compares, or verifies
-- native anchors. It writes the desired anchors directly and asks Blizzard's
-- actual pooled UnitFrame:UpdateAnchors method to restore native layout.
--
-- Blizzard uses three FontStrings on NamePlateHealthBarMixin:
--   Text      - numeric-only or percentage-only display
--   RightText - numeric value in BOTH mode
--   LeftText  - percentage in BOTH mode
--
-- Blizzard's plate chassis and health-fill StatusBar are not always the same
-- width. The user can therefore center against either HealthBarsContainer
-- (the full native nameplate/chassis) or the live healthBar (the fill only).

local C_NamePlate = C_NamePlate
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local pcall = pcall
local setmetatable = setmetatable
local tostring = tostring
local tonumber = tonumber
local type = type

local HALF_PAIR_GAP = 1
local TEXT_Y_OFFSET = 0

-- Weak keys bind state to Blizzard's pooled native health bars.
local nativeHealthTextState = setmetatable({}, { __mode = "k" })

local ApplyNativeHealthTextCenteringInternal

local function ResolveNativeHealthText(nameplate)
    local unitFrame = nameplate and nameplate.UnitFrame
    local container = unitFrame and unitFrame.HealthBarsContainer
    local healthBar = unitFrame and (unitFrame.healthBar or (container and container.healthBar)) or nil
    if not healthBar then return nil end
    return unitFrame, container, healthBar, healthBar.Text, healthBar.LeftText, healthBar.RightText
end

local function ResolveAnchorStyles()
    local constants = NamePlateConstants
    return constants and constants.NAME_ANCHOR_STYLES or nil
end

local function ResolveAnchorStyle()
    local setup = NamePlateSetupOptions
    if setup and setup.unitNameAnchorStyle ~= nil then
        return setup.unitNameAnchorStyle
    end
    return nil
end

local function NativeNameIsInsideHealthBar()
    local styles = ResolveAnchorStyles()
    local anchorStyle = ResolveAnchorStyle()
    if styles and anchorStyle ~= nil then
        return anchorStyle == styles.InsideHealthBar
    end

    -- Defensive fallback if the setup table is unavailable on a compatible
    -- Classic branch. Modern and Block place the unit name inside the HP bar.
    local styleEnum = Enum and Enum.NamePlateStyle
    local style = C_CVar and C_CVar.GetCVar and tonumber(C_CVar.GetCVar("nameplateStyle")) or nil
    if styleEnum and style then
        return style == styleEnum.Modern or style == styleEnum.Block
    end
    return false
end

local function ResolveCenterTarget(container, healthBar)
    if ns.c_nameplateCenterHealthTextOnNameplate ~= false and container then
        return container, "HealthBarsContainer (entire nameplate)", TEXT_Y_OFFSET
    end
    return healthBar, "healthBar (fill only)", TEXT_Y_OFFSET
end

local function ShouldCenterNativeHealthText(nameplate)
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    if ns.c_nameplateCenterHealthText == false then return false end
    if not (nameplate and nameplate._tfTurboNativeHealthChassis == true) then return false end
    if NativeNameIsInsideHealthBar() then return false end

    local unitFrame, _, healthBar, text, leftText, rightText = ResolveNativeHealthText(nameplate)
    if unitFrame and type(unitFrame.IsShowOnlyName) == "function" and securecall then
        local ok, showOnlyName = pcall(securecall, unitFrame.IsShowOnlyName, unitFrame)
        if ok and showOnlyName == true then return false end
    end
    return healthBar ~= nil and text ~= nil and leftText ~= nil and rightText ~= nil
end

local function ClearHealthTextAnchors(state)
    local regions = state.regions
    regions.text:ClearAllPoints()
    regions.leftText:ClearAllPoints()
    regions.rightText:ClearAllPoints()
end

local function ApplyCenteredAnchors(state)
    local target = state.centerTarget
    local yOffset = state.centerYOffset or 0
    local regions = state.regions
    local text, leftText, rightText = regions.text, regions.leftText, regions.rightText

    -- Do not use PixelUtil.SetPoint here. Raw SetPoint avoids helper-side scale
    -- queries against the restricted FontStrings.
    ClearHealthTextAnchors(state)
    text:SetPoint("CENTER", target, "CENTER", 0, yOffset)

    -- Blizzard displays numeric value in RightText and percentage in LeftText
    -- when BOTH is enabled. Split them around the same center without reading
    -- text widths, bounds, or anchor geometry.
    rightText:SetPoint("RIGHT", target, "CENTER", -HALF_PAIR_GAP, yOffset)
    leftText:SetPoint("LEFT", target, "CENTER", HALF_PAIR_GAP, yOffset)
end

-- Static 1.15.9 fallback used only if the live Blizzard layout method cannot be
-- invoked. It mirrors NamePlateUnitFrameMixin:UpdateAnchors for these three
-- FontStrings and does not read any restricted geometry.
local function ApplyBlizzardAnchorPolicy(state)
    local unitFrame = state.unitFrame
    local healthBar = state.healthBar
    local regions = state.regions
    local text, leftText, rightText = regions.text, regions.leftText, regions.rightText

    ClearHealthTextAnchors(state)

    local showOnlyName = false
    if unitFrame and type(unitFrame.IsShowOnlyName) == "function" and securecall then
        local ok, value = pcall(securecall, unitFrame.IsShowOnlyName, unitFrame)
        showOnlyName = ok and value == true
    end
    if showOnlyName then return true end

    local setup = NamePlateSetupOptions
    local styles = ResolveAnchorStyles()
    local anchorStyle = ResolveAnchorStyle()
    if not (setup and styles and anchorStyle ~= nil) then return false end

    if anchorStyle == styles.InsideHealthBar then
        leftText:SetPoint("RIGHT", healthBar, "RIGHT", -4, 0)
        rightText:SetPoint("RIGHT", leftText, "LEFT", -2, 0)
        text:SetPoint("RIGHT", rightText, "LEFT", 2, 0)
    elseif anchorStyle == styles.CenteredAboveHealthBar then
        local yOffset = setup.useClassicHealthBar and -0.5 or 0
        leftText:SetPoint("RIGHT", healthBar, "RIGHT", -4, yOffset)
        rightText:SetPoint("RIGHT", leftText, "LEFT", -2, 0)
        text:SetPoint("RIGHT", rightText, "LEFT", 2, 0)
    else -- NamePlateConstants.NAME_ANCHOR_STYLES.AboveHealthBar
        leftText:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", -4, 2)
        rightText:SetPoint("BOTTOMRIGHT", leftText, "BOTTOMLEFT", -2, 0)
        text:SetPoint("BOTTOMRIGHT", rightText, "BOTTOMLEFT", 2, 0)
    end
    return true
end

local function RestoreThroughBlizzard(state)
    local unitFrame = state.unitFrame
    if unitFrame and type(unitFrame.UpdateAnchors) == "function" and securecall then
        local ok, err = pcall(securecall, unitFrame.UpdateAnchors, unitFrame)
        if ok then
            state.restoreMode = "Blizzard UpdateAnchors"
            state.lastRestoreError = nil
            return true
        end
        state.lastRestoreError = "UpdateAnchors: " .. tostring(err)
    end

    local ok, result = pcall(ApplyBlizzardAnchorPolicy, state)
    if ok and result == true then
        state.restoreMode = "static 1.15.9 fallback"
        state.lastRestoreError = nil
        return true
    end

    local fallbackError = ok and "static fallback unavailable" or tostring(result)
    if state.lastRestoreError then
        state.lastRestoreError = state.lastRestoreError .. " | fallback: " .. fallbackError
    else
        state.lastRestoreError = fallbackError
    end
    return false
end

local function ResolveNameplateFromUnitFrame(unitFrame, fallback)
    if unitFrame and unitFrame.GetNamePlateFrame and securecall then
        local ok, nameplate = pcall(securecall, unitFrame.GetNamePlateFrame, unitFrame)
        if ok and nameplate then return nameplate end
    end
    return fallback
end

local function InstallLiveHook(state)
    local unitFrame = state.unitFrame
    if state.updateAnchorsHooked or not (hooksecurefunc and unitFrame)
        or type(unitFrame.UpdateAnchors) ~= "function"
    then
        return
    end

    local ok, err = pcall(hooksecurefunc, unitFrame, "UpdateAnchors", function(frame)
        if state.syncing or not state.enabled then return end
        state.nameplate = ResolveNameplateFromUnitFrame(frame, state.nameplate)
        if state.nameplate and ApplyNativeHealthTextCenteringInternal then
            ApplyNativeHealthTextCenteringInternal(state.nameplate)
        end
    end)

    if ok then
        state.updateAnchorsHooked = true
        state.lastHookError = nil
    else
        state.lastHookError = tostring(err)
    end
end

local function EnsureState(nameplate)
    local unitFrame, container, healthBar, text, leftText, rightText = ResolveNativeHealthText(nameplate)
    if not (unitFrame and healthBar and text and leftText and rightText) then return nil end

    local state = nativeHealthTextState[healthBar]
    if not state then
        state = {
            enabled = false,
            applied = false,
            syncing = false,
            applyCount = 0,
        }
        nativeHealthTextState[healthBar] = state
    end

    state.nameplate = nameplate
    state.unitFrame = unitFrame
    state.container = container
    state.healthBar = healthBar
    state.regions = state.regions or {}
    state.regions.text = text
    state.regions.leftText = leftText
    state.regions.rightText = rightText
    state.centerTarget, state.centerTargetLabel, state.centerYOffset = ResolveCenterTarget(container, healthBar)

    InstallLiveHook(state)
    return state
end

local function RestoreStateBody(state)
    state.enabled = false
    state.applied = false
    return RestoreThroughBlizzard(state)
end

function ns.RestoreNativeNameplateHealthTextPosition(nameplate)
    local _, _, healthBar = ResolveNativeHealthText(nameplate)
    local state = healthBar and nativeHealthTextState[healthBar]
    if not state or state.syncing then return false end

    state.syncing = true
    local ok, result = pcall(RestoreStateBody, state)
    state.syncing = false

    if not ok then
        state.lastRestoreError = tostring(result)
        return false
    end
    return result == true
end

local function ApplyStateBody(state)
    ApplyCenteredAnchors(state)
    state.enabled = true
    state.applied = true
    state.applyCount = (state.applyCount or 0) + 1
    state.lastError = nil
    return true
end

ApplyNativeHealthTextCenteringInternal = function(nameplate)
    if not ShouldCenterNativeHealthText(nameplate) then
        ns.RestoreNativeNameplateHealthTextPosition(nameplate)
        return false
    end

    local state = EnsureState(nameplate)
    if not state or state.syncing then return false end

    state.syncing = true
    local ok, result = pcall(ApplyStateBody, state)
    state.syncing = false
    if not ok then
        local failure = tostring(result)
        state.enabled = false
        state.applied = false

        -- A failed write must not leave a partially cleared native layout.
        state.syncing = true
        local rollbackOK, rollbackResult = pcall(RestoreStateBody, state)
        state.syncing = false
        if not rollbackOK or rollbackResult ~= true then
            local rollbackError = rollbackOK and (state.lastRestoreError or "restore returned false")
                or tostring(rollbackResult)
            failure = failure .. " | rollback: " .. rollbackError
        end
        state.lastError = failure
        return false
    end
    return result == true
end

function ns.ApplyNativeHealthTextCentering(nameplate)
    return ApplyNativeHealthTextCenteringInternal(nameplate)
end

function ns.RefreshNativeHealthTextCentering()
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if not plates then return end

    for _, nameplate in pairs(plates) do
        if ShouldCenterNativeHealthText(nameplate) then
            ApplyNativeHealthTextCenteringInternal(nameplate)
        else
            ns.RestoreNativeNameplateHealthTextPosition(nameplate)
        end
    end
end

function ns.IsNativeHealthTextCentered(nameplate)
    local _, container, healthBar = ResolveNativeHealthText(nameplate)
    local state = healthBar and nativeHealthTextState[healthBar]
    local desiredTarget = healthBar and ResolveCenterTarget(container, healthBar) or nil
    return state and state.enabled == true and state.applied == true
        and state.centerTarget == desiredTarget
        and ShouldCenterNativeHealthText(nameplate) or false
end

function ns.GetNativeHealthTextCenterRegions(nameplate)
    local _, _, healthBar, text, leftText, rightText = ResolveNativeHealthText(nameplate)
    return healthBar, text, leftText, rightText
end

function ns.GetNativeHealthTextCenterRuntime(nameplate)
    local _, container, healthBar = ResolveNativeHealthText(nameplate)
    local state = healthBar and nativeHealthTextState[healthBar]
    local target, label, yOffset
    if healthBar then
        -- Report the currently configured target even while centering is off;
        -- the last-applied pooled state may intentionally retain an older target
        -- until the amendment is enabled again.
        target, label, yOffset = ResolveCenterTarget(container, healthBar)
    end

    return target, label, yOffset or 0,
        state and state.updateAnchorsHooked == true or false,
        false, -- no hooks are installed on restricted FontString methods
        false, -- no timer/reconcile loop exists
        state and state.lastHookError or nil,
        "restricted-write-only",
        state and state.applyCount or 0,
        state and state.lastRestoreError or nil,
        state and state.restoreMode or nil
end

function ns.GetNativeHealthTextCenterError(nameplate)
    local _, _, healthBar = ResolveNativeHealthText(nameplate)
    local state = healthBar and nativeHealthTextState[healthBar]
    return state and state.lastError or nil
end

function ns.GetNativeHealthTextCenterGap()
    return HALF_PAIR_GAP * 2
end
