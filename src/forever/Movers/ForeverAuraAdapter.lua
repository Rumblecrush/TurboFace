local _, ns = ...

local compat = ns.Compat
local M = ns.Movers
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true and M) then return end

-- Forever target auras are secret-backed and no longer have the legacy
-- TargetFrameBuff*/TargetFrameDebuff* buttons used by Classic.  Keep the
-- shared mover anchors/SavedVariables, but render their contents through
-- Blizzard's supported CustomAuraContainerTemplate.

local Provider = { controllers = {}, supported = false, lastError = nil }
ns.MoverAuraProvider = Provider

local API = ns.API
local CreateFrame = CreateFrame
local UIParent = UIParent
local AnchorUtil = AnchorUtil
local SortMethod = AuraContainerSortMethod
local SortDirection = AuraContainerSortDirection

do
    local getTemplate = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    if type(getTemplate) == "function" then
        local ok, info = pcall(getTemplate, "CustomAuraContainerTemplate")
        Provider.supported = ok
            and (not API.CanAccessValue or API.CanAccessValue(info))
            and info ~= nil
    end
    Provider.supported = Provider.supported
        and type(CreateFrame) == "function"
        and type(AnchorUtil) == "table"
        and type(AnchorUtil.FlowDirection) == "table"
        and type(SortMethod) == "table"
        and type(SortDirection) == "table"
end

local function Safe(label, owner, methodName, ...)
    local okMethod, method = pcall(function() return owner and owner[methodName] end)
    if not okMethod or type(method) ~= "function" then
        Provider.lastError = label .. ": missing " .. methodName
        return false
    end
    local ok, result = pcall(method, owner, ...)
    if not ok then
        Provider.lastError = label .. ": " .. (API.SafeToString and API.SafeToString(result) or tostring(result))
        return false
    end
    return true, result
end

local durationFormatter
local function DurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    durationFormatter = false
    if C_StringUtil and type(C_StringUtil.CreateNumericRuleFormatter) == "function" then
        local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
        if ok and formatter and type(formatter.AddBreakpoint) == "function" then
            formatter:AddBreakpoint({ threshold = 0, step = 1, format = "%d" })
            formatter:AddBreakpoint({
                threshold = 90, format = "%dm",
                components = { { div = 60, step = 1 } },
            })
            formatter:AddBreakpoint({
                threshold = 3600, format = "%dh",
                components = { { div = 3600, step = 1 } },
            })
            durationFormatter = formatter
        end
    end
    return durationFormatter or nil
end

local function SetFont(fontString, size)
    if ns.AuraPresentation then
        ns.AuraPresentation:StyleText(fontString)
    elseif ns.StyleFont then
        ns:StyleFont(fontString, nil, size, "auras")
    else
        fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
    fontString:SetTextColor(1, 1, 1, 1)
end

local BORDER_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"
local BORDER_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }

local function InitializeButton(controller, button)
    if button._tfForeverMoverAura then return end
    button._tfForeverMoverAura = true
    controller.buttonCount = (controller.buttonCount or 0) + 1
    button:SetSize(controller.iconSize, controller.iconSize)

    -- AuraButton owns the secret aura tooltip binding. Enable only its motion
    -- channel and explicitly disable clicks/cancellation so hover information
    -- works without the detached icons intercepting gameplay clicks.
    Safe(controller.id .. " cancel", button, "SetCancelAuraButtons", nil)
    Safe(controller.id .. " tooltip-combat", button, "SetHideTooltipInCombat", false)
    Safe(controller.id .. " tooltip-anchor", button, "SetTooltipAnchorPoint", "ANCHOR_BOTTOMRIGHT")
    Safe(controller.id .. " motion", button, "SetMouseMotionEnabled", not controller.clickThrough)
    Safe(controller.id .. " clicks", button, "SetMouseClickEnabled", false)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    Safe(controller.id .. " icon", button, "SetIcon", icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:EnableMouse(false)
    if cooldown.EnableMouseMotion then cooldown:EnableMouseMotion(false) end
    if ns.AuraPresentation then ns.AuraPresentation:ConfigureCooldown(cooldown) end
    Safe(controller.id .. " duration", button, "SetDurationCooldown", cooldown)

    local count = button:CreateFontString(nil, "OVERLAY")
    if ns.AuraPresentation then
        ns.AuraPresentation:AnchorCount(count, button)
    else
        count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    end
    SetFont(count, math.max(8, math.floor(controller.iconSize * 0.48)))
    Safe(controller.id .. " count", button, "SetApplicationCount", count)

    local timer = cooldown:CreateFontString(nil, "OVERLAY")
    if ns.AuraPresentation then
        ns.AuraPresentation:AnchorTimer(timer, button)
    else
        timer:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
    end
    SetFont(timer, math.max(8, math.floor(controller.iconSize * 0.48)))
    local formatter = DurationFormatter()
    if (not ns.AuraPresentation or ns.AuraPresentation:ShowTimer())
        and formatter and type(button.SetDurationText) == "function"
    then
        Safe(controller.id .. " timer", button, "SetDurationText", timer, { textFormatter = formatter })
    else
        timer:Hide()
    end

    -- Match ForeverNameplates/ForeverAuras exactly: center an explicitly sized
    -- UI-Debuff-Overlays ring around the icon. The previous four-corner
    -- anchors were geometrically close, but target aura sizes can be
    -- fractional after applying auraTargetDebuffScale (1.35 is common). That
    -- made opposite edges round independently and the target ring could look
    -- softer or thicker than the nameplate ring.
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER_TEXTURE)
    border:SetTexCoord(unpack(BORDER_COORDS))
    border:SetPoint("CENTER")
    border:SetSize(controller.iconSize + 2, controller.iconSize + 2)
    border:SetVertexColor(controller.helpful and 1 or 0.8,
        controller.helpful and 1 or 0,
        controller.helpful and 1 or 0, 1)
    button.Border = border

    local styleEnum = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if type(button.SetAuraBorder) == "function" and styleEnum and styleEnum.PreserveAsset then
        Safe(controller.id .. " border", button, "SetAuraBorder", border, {
            showIcon = false,
            showWhenHarmful = not controller.helpful,
            showWhenHelpful = controller.helpful,
            showWithoutDispelType = true,
            style = styleEnum.PreserveAsset,
            customDispelColorMap = {
                None = CreateColor(0.80, 0.00, 0.00, 1),
                Magic = CreateColor(0.20, 0.60, 1.00, 1),
                Curse = CreateColor(0.60, 0.00, 1.00, 1),
                Disease = CreateColor(0.60, 0.40, 0.00, 1),
                Poison = CreateColor(0.00, 0.60, 0.00, 1),
                Bleed = CreateColor(0.80, 0.00, 0.00, 1),
                Enrage = CreateColor(1.00, 0.50, 0.00, 1),
            },
        })
    end
end

local function Growth(value)
    if value == "RIGHT_UP" then
        return "BOTTOMLEFT", AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up
    elseif value == "LEFT_UP" then
        return "BOTTOMRIGHT", AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Up
    elseif value == "LEFT_DOWN" then
        return "TOPRIGHT", AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down
    end
    return "TOPLEFT", AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down
end

local function Config(id)
    local db = TurboFaceDB or {}
    local moverAura = db.movers and db.movers.aura or {}
    local aura = db.auras or {}
    if id == "TargetBuffs" then
        return "target", true, 32, tonumber(db.auraTargetBuffScale) or 1,
            tonumber(moverAura.targetPerRow) or 8, moverAura.targetBuffGrowth or "RIGHT_DOWN"
    elseif id == "TargetDebuffs" then
        return "target", false, 32, tonumber(db.auraTargetDebuffScale) or 1,
            tonumber(moverAura.targetPerRow) or 8, moverAura.targetDebuffGrowth or "RIGHT_DOWN"
    end
    return "targettarget", false, 4, tonumber(aura.totDebuffScale) or 1,
        4, moverAura.totDebuffGrowth or "RIGHT_DOWN"
end

local function Disable(controller)
    if not controller then return end
    Safe(controller.id .. " disable", controller.frame, "SetEnabled", false)
    controller.frame:Hide()
    controller.active = false
end

local function UnitPresent(unit)
    if type(UnitExists) ~= "function" then return false end
    local ok, present = pcall(UnitExists, unit)
    if not ok or (API.CanAccessValue and not API.CanAccessValue(present)) then return false end
    return present == true
end

local function AuraGroups(helpful)
    if not helpful then
        return {
            { name = "harmful", filter = "HARMFUL", candidates = { excludeSpellIDs = {} } },
        }
    end

    -- Match the proven Forever nameplate "ALL" partition. AuraContainer's
    -- candidate policy is explicit rather than treating a nearly-empty
    -- candidate record as an implicit match-all for helpful auras.
    local whitelist = {}
    return {
        {
            name = "helpful-whitelist", filter = "HELPFUL",
            candidates = { includeSpellIDs = whitelist, excludeSpellIDs = {} },
        },
        {
            name = "helpful-dispellable", filter = "HELPFUL",
            candidates = {
                includeDispelTypes = { Magic = true, Enrage = true },
                excludeSpellIDs = whitelist,
            },
        },
        {
            name = "helpful-other", filter = "HELPFUL",
            candidates = {
                excludeSpellIDs = whitelist,
                excludeDispelTypes = { Magic = true, Enrage = true },
            },
        },
    }
end

local function CreateController(id, anchor, spacingX, spacingY, clickThrough)
    local unit, helpful, maximum, scale, perRow, growth = Config(id)
    perRow = math.max(1, math.floor(perRow))
    local iconSize = (id == "ToTDebuffs" and 20 or 21) * math.max(0.5, scale)
    local signature = table.concat({ unit, tostring(helpful), maximum, iconSize,
        perRow, growth, spacingX, spacingY, tostring(clickThrough),
        ns.AuraPresentation and ns.AuraPresentation:GetSignature() or "default" }, ":")
    local previous = Provider.controllers[id]
    if previous and previous.signature == signature then return previous end
    Disable(previous)

    local controller = {
        id = id, unit = unit, helpful = helpful, maximum = maximum,
        iconSize = iconSize, signature = signature, buttonCount = 0,
        clickThrough = clickThrough == true,
    }
    local ok, frame = pcall(CreateFrame, "AuraContainer", nil, UIParent,
        "CustomAuraContainerTemplate")
    if not ok or not frame then
        Provider.lastError = id .. " create: " .. (API.SafeToString and API.SafeToString(frame) or tostring(frame))
        return nil
    end
    controller.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(5)
    frame:EnableMouse(false)

    local anchorPoint, horizontal, vertical = Growth(growth)
    local layout = {
        elementSpacing = spacingX,
        lineSpacing = spacingY,
        groupLineSpacing = spacingY,
        elementWidth = iconSize,
        elementHeight = iconSize,
        maximumLineSize = perRow * (iconSize + spacingX) + 1,
    }
    for _, group in ipairs(AuraGroups(helpful)) do
        local options = {
            maxFrameCount = maximum,
            sortMethod = SortMethod.Expiration,
            sortDirection = SortDirection.Normal,
            candidateFilters = group.candidates,
            initializeFrame = function(button) InitializeButton(controller, button) end,
            layout = layout,
        }
        if not Safe(id .. " " .. group.name, frame, "AddAuraGroup",
            group.name, group.filter, options)
        then
            frame:Hide()
            return nil
        end
    end
    Safe(id .. " flow-anchor", frame, "SetFlowLayoutAnchorPoint", anchorPoint)
    Safe(id .. " flow-direction", frame, "SetFlowLayoutGrowthDirection", horizontal, vertical)
    Safe(id .. " flow-size", frame, "SetFlowLayoutMaximumLineSize", layout.maximumLineSize)

    local rows = math.max(1, math.ceil(maximum / perRow))
    frame:SetSize(perRow * iconSize + math.max(0, perRow - 1) * spacingX,
        rows * iconSize + math.max(0, rows - 1) * spacingY)
    frame:ClearAllPoints()
    frame:SetPoint(anchorPoint, anchor, anchorPoint, 0, 0)
    frame:Hide()
    Provider.controllers[id] = controller
    return controller
end

local ids = { "TargetBuffs", "TargetDebuffs", "ToTDebuffs" }
local nativeHookInstalled = false

local function ElementOwns(id)
    local db = TurboFaceDB and TurboFaceDB.movers
    local element = db and db.elements and db.elements[id]
    return Provider.supported and db and db.enabled ~= false and db.auraLayout ~= false
        and type(element) == "table" and element.enabled ~= false and element.hidden ~= true
end

local function GetNativeTargetAuraContainer()
    local targetFrame = _G.TargetFrame
    local getter = targetFrame and targetFrame.GetAuraContainer
    if type(getter) ~= "function" then return nil end
    local ok, container = pcall(getter, targetFrame)
    if not ok or (API.CanAccessValue and not API.CanAccessValue(container)) then return nil end
    return container
end

local function SuppressNativeTargetAuras()
    local container = GetNativeTargetAuraContainer()
    if not container then return end
    if Provider.nativeMaxBuffs == nil then
        local ok, value = Safe("native target buffs default", container, "GetMaxBuffs")
        if ok and (not API.CanAccessValue or API.CanAccessValue(value)) then
            Provider.nativeMaxBuffs = tonumber(value)
        end
    end
    if Provider.nativeMaxDebuffs == nil then
        local ok, value = Safe("native target debuffs default", container, "GetMaxDebuffs")
        if ok and (not API.CanAccessValue or API.CanAccessValue(value)) then
            Provider.nativeMaxDebuffs = tonumber(value)
        end
    end
    local buffsOwned = ElementOwns("TargetBuffs")
    local debuffsOwned = ElementOwns("TargetDebuffs")
    if buffsOwned then
        Safe("native target buffs", container, "SetMaxBuffs", 0)
    elseif Provider.nativeMaxBuffs then
        Safe("native target buffs restore", container, "SetMaxBuffs", Provider.nativeMaxBuffs)
    end
    if debuffsOwned then
        Safe("native target debuffs", container, "SetMaxDebuffs", 0)
    elseif Provider.nativeMaxDebuffs then
        Safe("native target debuffs restore", container, "SetMaxDebuffs", Provider.nativeMaxDebuffs)
    end
    if buffsOwned and debuffsOwned then
        Safe("native target auras", container, "Hide")
    elseif not buffsOwned and not debuffsOwned then
        Safe("native target auras restore", container, "Show")
        Safe("native target auras refresh", container, "UpdateAllAuras")
    end
end

local function InstallNativeSuppressionHook()
    if nativeHookInstalled then return end
    local targetFrame = _G.TargetFrame
    if not (targetFrame and type(targetFrame.ConfigureAuraContainer) == "function"
        and type(hooksecurefunc) == "function")
    then
        return
    end
    nativeHookInstalled = true
    hooksecurefunc(targetFrame, "ConfigureAuraContainer", SuppressNativeTargetAuras)
end

function Provider:InvalidateUnit(unit)
    for _, controller in pairs(self.controllers) do
        if controller.unit == unit then Disable(controller) end
    end
end

function Provider:Update(movers)
    InstallNativeSuppressionHook()
    SuppressNativeTargetAuras()
    local db = TurboFaceDB and TurboFaceDB.movers or nil
    local elements = db and db.elements or nil
    local enabled = self.supported and db and db.enabled ~= false and db.auraLayout ~= false
    local moverAura = db and db.aura or {}
    local spacingX = tonumber(moverAura.spacingX) or 0
    local spacingY = tonumber(moverAura.spacingY) or 0

    for _, id in ipairs(ids) do
        local edb = elements and elements[id]
        local unit = Config(id)
        local active = enabled and UnitPresent(unit)
            and type(edb) == "table" and edb.enabled ~= false and edb.hidden ~= true
        local info = M._elements and M._elements[id]
        if active and info and info.frame then
            movers:ApplyElement(id)
            local controller = CreateController(id, info.frame, spacingX, spacingY,
                edb.clickThrough == true)
            if controller then
                if not controller.active then
                    Safe(id .. " enable", controller.frame, "SetEnabled", true)
                    Safe(id .. " unit", controller.frame, "SetUnit", controller.unit)
                    controller.frame:Show()
                    controller.active = true
                end
            end
        else
            Disable(self.controllers[id])
        end
    end
end
