local _, ns = ...

local compat = ns.Compat
local FNP = ns.ForeverNameplates
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true and FNP) then return end

-- =============================================================================
-- Forever detached nameplate auras
-- =============================================================================
-- Modern Forever aura values may be secret. Blizzard's AuraContainer is the
-- supported renderer for that domain: it performs the aura query, filtering,
-- duration binding, and UNIT_AURA updates internally. TurboFace supplies only
-- addon-owned containers/buttons and presentation options.
--
-- Ownership boundary:
--   * both AuraContainers are direct children of UIParent;
--   * they may use the native health bar only as a write-only anchor target;
--   * no aura data, duration, native geometry, or native frame state is read;
--   * no field or child is attached to a Blizzard nameplate object.
-- =============================================================================

local FA = {
    supported = false,
    created = 0,
    active = 0,
    lastError = nil,
}
FNP.Auras = FA

local CreateFrame = CreateFrame
local UIParent = UIParent
local API = ns.API
local AuraContainerSortMethod = AuraContainerSortMethod
local AuraContainerSortDirection = AuraContainerSortDirection
local AnchorUtil = AnchorUtil

do
    local getTemplate = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    if type(getTemplate) == "function" then
        local ok, info = pcall(getTemplate, "CustomAuraContainerTemplate")
        FA.supported = ok and (not API.CanAccessValue or API.CanAccessValue(info)) and info ~= nil
    end
    FA.supported = FA.supported
        and type(CreateFrame) == "function"
        and type(AnchorUtil) == "table"
        and type(AnchorUtil.FlowDirection) == "table"
        and type(AuraContainerSortMethod) == "table"
        and type(AuraContainerSortDirection) == "table"
end

local function Safe(label, owner, methodName, ...)
    local method = owner and owner[methodName]
    if type(method) ~= "function" then
        FA.lastError = label .. ": missing " .. methodName
        return false
    end
    local ok, a = pcall(method, owner, ...)
    if not ok then
        FA.lastError = label .. ": " .. tostring(a)
        return false
    end
    return true, a
end

local function Enabled()
    if not FA.supported then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    if ns.ModuleEnabled and not ns.ModuleEnabled("auras") then return false end
    return ns.c_showDebuffs ~= false or ns.c_showBuffs ~= false
end

local function CopySet(source)
    local output = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if value then output[key] = true end
        end
    end
    return output
end

local function MergeSet(first, second)
    local output = CopySet(first)
    if type(second) == "table" then
        for key, value in pairs(second) do
            if value then output[key] = true end
        end
    end
    return output
end

local function SetFont(fontString, size)
    if ns.StyleFont then
        ns:StyleFont(fontString, nil, size, "auras")
    else
        fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
    fontString:SetTextColor(1, 1, 1, 1)
end

local durationFormatter
local function DurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    durationFormatter = false
    if C_StringUtil and type(C_StringUtil.CreateNumericRuleFormatter) == "function" then
        local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
        if ok and formatter and type(formatter.AddBreakpoint) == "function" then
            -- Match TurboFace's established countdown presentation without
            -- reading the secret remaining duration ourselves: whole seconds,
            -- then compact minutes/hours. Blizzard owns the bound value and
            -- applies these formatting rules inside the AuraContainer.
            formatter:AddBreakpoint({threshold = 0, step = 1, format = "%d"})
            formatter:AddBreakpoint({
                threshold = 90,
                format = "%dm",
                components = {{div = 60, step = 1}},
            })
            formatter:AddBreakpoint({
                threshold = 3600,
                format = "%dh",
                components = {{div = 3600, step = 1}},
            })
            durationFormatter = formatter
        end
    end
    return durationFormatter or nil
end

local BORDER_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"
local BORDER_COORDS = {0.296875, 0.5703125, 0, 0.515625}

local function StyleButton(controller, button)
    local width = controller.width or 20
    local height = controller.height or width
    button:SetSize(width, height)
    if button.Icon then button.Icon:SetSize(width, height) end
    if button.Cooldown then button.Cooldown:SetSize(width, height) end
    if button.Border then button.Border:SetSize(width + 2, height + 2) end
    if button.Count then SetFont(button.Count, controller.stackSize or 10) end
    if button.TimerText then SetFont(button.TimerText, controller.fontSize or 10) end
end

local function InitializeAuraButton(controller, button)
    if button._tfForeverInitialized then
        return
    end
    button._tfForeverInitialized = true
    button:EnableMouse(false)
    if button.EnableMouseMotion then button:EnableMouseMotion(false) end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon
    Safe("button-icon", button, "SetIcon", icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("CENTER")
    cooldown:EnableMouse(false)
    if cooldown.EnableMouseMotion then cooldown:EnableMouseMotion(false) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
    if cooldown.SetSwipeColor then cooldown:SetSwipeColor(0, 0, 0, 0.68) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
    button.Cooldown = cooldown
    Safe("button-duration", button, "SetDurationCooldown", cooldown)

    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
    button.Count = count
    Safe("button-count", button, "SetApplicationCount", count)

    local timer = cooldown:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("CENTER")
    button.TimerText = timer
    local formatter = DurationFormatter()
    if formatter and type(button.SetDurationText) == "function" then
        Safe("button-timer", button, "SetDurationText", timer, {textFormatter = formatter})
    else
        timer:Hide()
    end

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER_TEXTURE)
    border:SetTexCoord(unpack(BORDER_COORDS))
    border:SetPoint("CENTER")
    border:SetVertexColor(controller.kind == "debuff" and 0.8 or 1,
        controller.kind == "debuff" and 0 or 1,
        controller.kind == "debuff" and 0 or 1, 1)
    button.Border = border

    local styleEnum = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if type(button.SetAuraBorder) == "function" and styleEnum and styleEnum.PreserveAsset then
        local colors = {
            None = CreateColor(0.80, 0.00, 0.00, 1),
            Magic = CreateColor(0.20, 0.60, 1.00, 1),
            Curse = CreateColor(0.60, 0.00, 1.00, 1),
            Disease = CreateColor(0.60, 0.40, 0.00, 1),
            Poison = CreateColor(0.00, 0.60, 0.00, 1),
            Bleed = CreateColor(0.80, 0.00, 0.00, 1),
            Enrage = CreateColor(1.00, 0.50, 0.00, 1),
        }
        Safe("button-border", button, "SetAuraBorder", border, {
            showIcon = false,
            showWhenHarmful = controller.kind == "debuff",
            showWhenHelpful = controller.kind == "buff",
            showWithoutDispelType = true,
            style = styleEnum.PreserveAsset,
            customDispelColorMap = colors,
        })
    end

    controller.buttons[#controller.buttons + 1] = button
    StyleButton(controller, button)
end

local function CreateController(st, kind)
    local controller = {kind = kind, buttons = {}, groups = {}}
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent,
        "CustomAuraContainerTemplate")
    if not ok or not container then
        FA.lastError = kind .. " create: " .. tostring(container)
        return nil
    end
    controller.frame = container
    container:SetSize(1, 1)
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(55)
    container:EnableMouse(false)
    if container.EnableMouseMotion then container:EnableMouseMotion(false) end
    container:Hide()
    st[kind .. "Auras"] = controller
    FA.created = FA.created + 1
    return controller
end

local function EnsureController(st, kind)
    return st[kind .. "Auras"] or CreateController(st, kind)
end

local function Direction(grow)
    if grow == "LEFT" then
        return AnchorUtil.FlowDirection.Left, "BOTTOMRIGHT", "BOTTOMRIGHT", "TOPRIGHT"
    end
    return AnchorUtil.FlowDirection.Right, "BOTTOMLEFT", "BOTTOMLEFT", "TOPLEFT"
end

local function CandidateBase(minimum, maximum)
    local candidate = {excludeSpellIDs = CopySet(ns.AuraBlacklist)}
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or 0
    if minimum > 0 then candidate.minDuration = minimum end
    if maximum > 0 then candidate.maxDuration = maximum end
    return candidate
end

local function DesiredGroups(controller)
    if controller.kind == "debuff" then
        local main = CandidateBase(ns.c_minDuration, ns.c_maxDuration)
        local whitelist = CopySet(ns.AuraWhitelist)
        if next(whitelist) then
            main.excludeSpellIDs = MergeSet(main.excludeSpellIDs, whitelist)
            return {
                {filter = "HARMFUL|PLAYER", candidates = {includeSpellIDs = whitelist,
                    excludeSpellIDs = CopySet(ns.AuraBlacklist)}},
                {filter = "HARMFUL|PLAYER", candidates = main},
            }
        end
        return {{filter = "HARMFUL|PLAYER", candidates = main}}
    end

    local mode = ns.c_buffFilterMode or "ONLY_DISPELLABLE"
    local blacklist = CopySet(ns.AuraBlacklist)
    local whitelist = CopySet(ns.AuraWhitelist)
    local dispellable = {
        includeDispelTypes = {Magic = true, Enrage = true},
        excludeSpellIDs = MergeSet(blacklist, whitelist),
    }
    if mode == "WHITELIST_ONLY" then
        return {{filter = "HELPFUL", candidates = {
            includeSpellIDs = whitelist, excludeSpellIDs = blacklist,
        }}}
    elseif mode == "WHITELIST_DISPELLABLE" then
        return {
            {filter = "HELPFUL", candidates = {
                includeSpellIDs = whitelist, excludeSpellIDs = blacklist,
            }},
            {filter = "HELPFUL", candidates = dispellable},
        }
    elseif mode == "ALL" then
        local main = CandidateBase(ns.c_buffMinDuration, ns.c_buffMaxDuration)
        main.excludeSpellIDs = MergeSet(main.excludeSpellIDs, whitelist)
        main.excludeDispelTypes = {Magic = true, Enrage = true}
        return {
            {filter = "HELPFUL", candidates = {
                includeSpellIDs = whitelist, excludeSpellIDs = blacklist,
            }},
            {filter = "HELPFUL", candidates = dispellable},
            {filter = "HELPFUL", candidates = main},
        }
    end
    dispellable.excludeSpellIDs = blacklist
    return {{filter = "HELPFUL", candidates = dispellable}}
end

local function ConfigureController(controller, hp)
    local kind = controller.kind
    local isDebuff = kind == "debuff"
    local enabled = isDebuff and ns.c_showDebuffs ~= false or not isDebuff and ns.c_showBuffs ~= false
    if not enabled or not hp then
        Safe(kind .. " disable", controller.frame, "SetEnabled", false)
        controller.frame:Hide()
        controller.active = false
        controller.unit = nil
        return false
    end
    -- Aura buttons become forbidden as soon as Blizzard binds secret aura
    -- state. All button/layout styling therefore happens exactly once, before
    -- SetUnit. General nameplate refreshes must never restyle bound buttons or
    -- reconfigure their container.
    if controller.configured then return true end

    controller.width = tonumber(isDebuff and ns.c_debuffIconWidth or ns.c_buffIconWidth) or 20
    controller.height = tonumber(isDebuff and ns.c_debuffIconHeight or ns.c_buffIconHeight) or controller.width
    controller.fontSize = tonumber(isDebuff and ns.c_debuffFontSize or ns.c_buffFontSize) or 10
    controller.stackSize = tonumber(isDebuff and ns.c_debuffStackFontSize or ns.c_buffStackFontSize) or 10
    controller.maxCount = math.max(1, math.floor(tonumber(isDebuff and ns.c_maxDebuffs or ns.c_maxBuffs) or 4))
    controller.spacing = tonumber(isDebuff and ns.c_iconSpacing or ns.c_buffIconSpacing) or 2
    local layout = {
        elementSpacing = controller.spacing,
        lineSpacing = 2,
        groupLineSpacing = 2,
        elementWidth = controller.width,
        elementHeight = controller.height,
        maximumLineSize = controller.maxCount * (controller.width + controller.spacing) + 1,
    }
    local groups = DesiredGroups(controller)
    for index = 1, #groups do
        local name = "group" .. index
        local group = groups[index]
        local options = {
            maxFrameCount = controller.maxCount,
            sortMethod = AuraContainerSortMethod.Expiration,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = group.candidates,
            initializeFrame = function(button) InitializeAuraButton(controller, button) end,
            layout = layout,
        }
        if not controller.groups[name] then
            Safe(kind .. " add-group", controller.frame, "AddAuraGroup", name, group.filter, options)
            controller.groups[name] = true
        else
            Safe(kind .. " filter", controller.frame, "SetAuraGroupFilterString", name, group.filter)
            Safe(kind .. " candidates", controller.frame, "SetAuraGroupCandidateFilters", name, group.candidates)
            Safe(kind .. " max", controller.frame, "SetAuraGroupMaxFrameCount", name, controller.maxCount)
            Safe(kind .. " sort", controller.frame, "SetAuraGroupSortMethod", name,
                AuraContainerSortMethod.Expiration, AuraContainerSortDirection.Normal)
            Safe(kind .. " layout", controller.frame, "SetAuraGroupLayout", name, layout)
        end
    end
    local index = #groups + 1
    while controller.groups["group" .. index] do
        local name = "group" .. index
        Safe(kind .. " clear-filter", controller.frame, "SetAuraGroupFilterString", name, "")
        Safe(kind .. " clear-max", controller.frame, "SetAuraGroupMaxFrameCount", name, 0)
        index = index + 1
    end

    local grow = isDebuff and ns.c_growDirection or ns.c_buffGrowDirection
    local horizontal, flowAnchor, point, relativePoint = Direction(grow)
    local totalWidth = controller.maxCount * controller.width
        + math.max(0, controller.maxCount - 1) * controller.spacing
    controller.frame:SetSize(totalWidth, controller.height)
    Safe(kind .. " flow-anchor", controller.frame, "SetFlowLayoutAnchorPoint", flowAnchor)
    Safe(kind .. " flow-direction", controller.frame, "SetFlowLayoutGrowthDirection",
        horizontal, AnchorUtil.FlowDirection.Up)
    Safe(kind .. " flow-size", controller.frame, "SetFlowLayoutMaximumLineSize", layout.maximumLineSize)

    controller.frame:ClearAllPoints()
    local x = tonumber(isDebuff and ns.c_debuffXOffset or ns.c_buffXOffset) or 0
    local y = tonumber(isDebuff and ns.c_debuffYOffset or ns.c_buffYOffset) or 0
    y = y + 15
    if not isDebuff and ns.c_showDebuffs ~= false then
        y = y + (tonumber(ns.c_debuffIconHeight) or 20) + 4
    end
    if grow == "CENTER" then
        controller.frame:SetPoint("BOTTOM", hp, "TOP", x, y)
        Safe(kind .. " center-anchor", controller.frame, "SetFlowLayoutAnchorPoint", "BOTTOMLEFT")
    else
        controller.frame:SetPoint(point, hp, relativePoint, x, y)
    end
    controller.configured = true
    return true
end

local function DisableController(controller)
    if not controller then return end
    Safe(controller.kind .. " disable", controller.frame, "SetEnabled", false)
    controller.frame:Hide()
    controller.unit = nil
    controller.active = false
end

function FA:Bind(st, hp)
    if not st then return end
    if not Enabled() or not st.unit or not hp
        or API.ReadUnitCanAttack("player", st.unit) ~= true
    then
        self:Release(st)
        return
    end

    local active = false
    for _, kind in ipairs({"debuff", "buff"}) do
        local controller = EnsureController(st, kind)
        if controller and ConfigureController(controller, hp) then
            if controller.unit ~= st.unit or not controller.active then
                Safe(kind .. " enable", controller.frame, "SetEnabled", true)
                Safe(kind .. " unit", controller.frame, "SetUnit", st.unit)
                controller.unit = st.unit
                controller.frame:Show()
                controller.active = true
            end
            active = true
        end
    end
    st.foreverAurasActive = active
    self:RefreshCount()
end

function FA:Release(st)
    if not st then return end
    DisableController(st.debuffAuras)
    DisableController(st.buffAuras)
    st.foreverAurasActive = nil
end

function FA:RefreshCount()
    local count = 0
    for _, st in pairs(FNP.statesByUnit) do
        if st.foreverAurasActive then count = count + 1 end
    end
    self.active = count
end
