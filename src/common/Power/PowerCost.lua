local _, ns = ...

-- =============================================================================
-- TurboFace Power/PowerCost.lua
-- MissingPower-style features adapted for Classic Era and Forever:
--   * action-button missing-power overlay + cast counter
-- =============================================================================

local Power = {}
ns.Power = Power

local _G = _G
local UIParent = UIParent
local CreateFrame = CreateFrame
local UnitPower = UnitPower
local UnitPowerType = UnitPowerType
local InCombatLockdown = InCombatLockdown
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellPowerCost = ns.API.GetSpellPowerCost
local GetActionInfo = ns.API.GetActionInfo
local HasAction = ns.API.HasAction
local GetActionSpell = ns.API.GetActionSpell
local HasActionSpell = ns.API.IsAvailable and ns.API.IsAvailable("GetActionSpell") or false
local GetMacroSpell = ns.API.GetMacroSpell
local GetMacroBody = ns.API.GetMacroBody
local IsSpellKnown = ns.API.IsSpellKnown
local IsPlayerSpell = ns.API.IsPlayerSpell
local GetNumSpellTabs = ns.API.GetNumSpellTabs
local GetSpellTabInfo = ns.API.GetSpellTabInfo
local GetSpellBookItemName = ns.API.GetSpellBookItemName
local BOOKTYPE_SPELL = BOOKTYPE_SPELL
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local GetPetActionInfo = GetPetActionInfo
local PowerBarColor = PowerBarColor
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local tonumber = tonumber
local tostring = tostring
local type = type
local ipairs = ipairs
local pairs = pairs
local wipe = wipe

local DEFAULTS = ns.defaults.power
local MergeDefaults = ns.MergeDefaults
local After = ns.After

local POWER_MANA  = (Enum and Enum.PowerType and Enum.PowerType.Mana)  or 0
local POWER_RAGE  = (Enum and Enum.PowerType and Enum.PowerType.Rage)  or 1
local POWER_FOCUS = (Enum and Enum.PowerType and Enum.PowerType.Focus) or 2
local POWER_ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local BUTTON_PREFIXES = {
    { prefix = "ActionButton", max = 12 },
    { prefix = "MultiBarBottomLeftButton", max = 12 },
    { prefix = "MultiBarBottomRightButton", max = 12 },
    { prefix = "MultiBarRightButton", max = 12 },
    { prefix = "MultiBarLeftButton", max = 12 },
    { prefix = "PetActionButton", max = 10, pet = true },
    { prefix = "StanceButton", max = 10, stance = true },
    { prefix = "ActionBar7Button", max = 12 },
    { prefix = "ActionBar8Button", max = 12 },
    { prefix = "ActionBar9Button", max = 12 },
    { prefix = "ActionBar10Button", max = 12 },
}

local ANCHORS = {
    CENTER = true,
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    RIGHT = true,
    BOTTOMRIGHT = true,
    BOTTOM = true,
    BOTTOMLEFT = true,
    LEFT = true,
}

local buttons = {}
local buttonSeen = {}
local buttonData = {}
-- Forever action buttons are protected Blizzard frames.  Overlay ownership must
-- remain completely external: parenting a frame to a button or writing an
-- addon field onto it can taint later native action/cooldown work.  Weak keys
-- let Blizzard discard/rebuild buttons without leaving stale addon state.
local overlayByButton = setmetatable({}, { __mode = "k" })
local spellCostCache = {}
local powerCache = {}
local secretCurveCache = {}
local initialized = false
local eventFrame
local renderQueued = false
local rebuildQueued = false
-- Coalesced rebuild policy. Structural state changes can require re-resolving
-- action slots/macros without invalidating the much more expensive per-spell
-- cost cache or recollecting the fixed Blizzard button frames.
local rebuildAllowCombat = false
local rebuildRefreshButtons = false
local rebuildInvalidateSpellCosts = false
local postCombatRebuildNeeded = false
local postCombatRefreshButtons = false
local postCombatInvalidateSpellCosts = false
local cachedDB
local dbMerged = false

-- Regen/tick state is owned by Power/RegenTicks.lua.

local function DB(forceMerge)
    if not TurboFaceDB then TurboFaceDB = {} end
    if type(TurboFaceDB.power) ~= "table" then TurboFaceDB.power = {} end
    local db = TurboFaceDB.power

    -- Defaults are merged once on load/refresh instead of every render/tick.
    -- Power markers run on an OnUpdate driver, so repeatedly deep-merging the
    -- default table there was a measurable CPU cost.
    if forceMerge or not dbMerged then
        MergeDefaults(db, DEFAULTS)
        dbMerged = true

        -- Legacy Power color/regen compatibility is handled by the versioned
        -- Core/Migrations.lua schema before defaults are merged. Runtime code
        -- therefore owns only current settings and never persists migration flags.
    end

    cachedDB = db
    return db
end
local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue or 0
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local ROUND_MULT = { [0] = 1, [1] = 10, [2] = 100, [3] = 1000 }
local COUNT_FORMAT = { [1] = "%0.1f", [2] = "%0.2f", [3] = "%0.3f" }
local function RoundDown(value, decimals)
    decimals = tonumber(decimals) or 0
    local mult = ROUND_MULT[decimals] or (10 ^ decimals)
    return math_floor((tonumber(value) or 0) * mult) / mult
end

local function FormatCount(amount, decimals)
    amount = tonumber(amount) or 0
    decimals = tonumber(decimals) or 0
    if decimals <= 0 or amount > 99 then
        return tostring(math_floor(amount))
    end
    local value = RoundDown(amount, decimals)
    local fmt = COUNT_FORMAT[decimals] or ("%0." .. decimals .. "f")
    return string.format(fmt, value):gsub("0+$", ""):gsub("%.$", "")
end

local function ColorWithAlpha(color, dr, dg, db, da)
    if type(color) ~= "table" then return dr, dg, db, da end
    return color.r or color[1] or dr, color.g or color[2] or dg, color.b or color[3] or db, color.a or color[4] or da
end

local function GetPlayerPowerType()
    local ptype = POWER_MANA
    if UnitPowerType then
        local n = UnitPowerType("player")
        if n ~= nil then ptype = n end
    end
    return ptype
end

local function DisableFrameMouse(frame)
    if not frame then return end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
end

local function AddButton(button, seen)
    if not button or seen[button] then return end
    seen[button] = true
    buttons[#buttons + 1] = button
end

local function CollectButtons()
    wipe(buttons)
    wipe(buttonSeen)
    for _, spec in ipairs(BUTTON_PREFIXES) do
        for i = 1, spec.max do
            local button = _G[spec.prefix .. i]
            AddButton(button, buttonSeen)
        end
    end
end

local function EnsureActionTextFont(fontString, size)
    if not fontString then return false end

    size = Clamp(size, 6, 32)

    if ns.StyleFont then
        ns:StyleFont(fontString, nil, size, "power")
    end

    local font = fontString:GetFont()
    if not font and _G.GameFontNormal and _G.GameFontNormal.GetFont then
        local gameFont, _, gameFlags = _G.GameFontNormal:GetFont()
        if gameFont then
            fontString:SetFont(gameFont, size, gameFlags or "OUTLINE")
            font = fontString:GetFont()
        end
    end

    if not font and STANDARD_TEXT_FONT then
        fontString:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        font = fontString:GetFont()
    end

    if not font then
        fontString:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        font = fontString:GetFont()
    end

    return font ~= nil
end

local function SafeSetActionText(fontString, text, size)
    if not fontString then return end
    if EnsureActionTextFont(fontString, size or (cachedDB and cachedDB.fontSize) or DEFAULTS.fontSize or 12) then
        fontString:SetText(text or "")
    end
end

local function CreateActionOverlay(button)
    if not button then return nil end
    local existing = overlayByButton[button]
    if existing then return existing end
    if InCombatLockdown and InCombatLockdown() then return nil end

    -- Direct UIParent ownership is the Forever taint boundary.  The protected
    -- action button is used only as a write-only anchor; it is never parented
    -- to, hooked, or mutated by this feature.
    local overlay = CreateFrame("Frame", nil, UIParent)
    if button.GetFrameStrata and overlay.SetFrameStrata then
        overlay:SetFrameStrata(button:GetFrameStrata())
    end
    overlay:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 8)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    DisableFrameMouse(overlay)
    overlay:Show()

    overlay.fill = CreateFrame("Frame", nil, overlay)
    overlay.fill:SetFrameLevel(overlay:GetFrameLevel() + 1)
    overlay.fill:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
    overlay.fill:SetWidth(1)
    overlay.fill:SetHeight(1)
    overlay.fill:SetAlpha(0)
    DisableFrameMouse(overlay.fill)
    overlay.fill:Show()

    overlay.fill.texture = overlay.fill:CreateTexture(nil, "OVERLAY")
    overlay.fill.texture:SetAllPoints(overlay.fill)
    overlay.fill.texture:SetColorTexture(0.3, 0.3, 1, 1)

    -- Forever can make player power opaque to addon arithmetic.  Blizzard's
    -- StatusBar accepts that secret scalar directly and performs the fill
    -- calculation internally.  It remains a child of the detached overlay,
    -- never of the protected action button.
    overlay.secretBar = CreateFrame("StatusBar", nil, overlay)
    overlay.secretBar:SetFrameLevel(overlay:GetFrameLevel() + 1)
    overlay.secretBar:SetAllPoints(overlay)
    overlay.secretBar:SetOrientation("VERTICAL")
    overlay.secretBar:SetMinMaxValues(0, 1)
    overlay.secretBar:SetValue(0)
    DisableFrameMouse(overlay.secretBar)
    overlay.secretTexture = overlay.secretBar:CreateTexture(nil, "OVERLAY")
    -- Keep the texture itself neutral.  The StatusBar color setter is one of
    -- Blizzard's explicit secret-aspect sinks, so the live fill alpha/color is
    -- applied there rather than multiplying a pre-tinted texture.
    overlay.secretTexture:SetColorTexture(1, 1, 1, 1)
    overlay.secretBar:SetStatusBarTexture(overlay.secretTexture)
    overlay.secretBar:Hide()

    overlay.textFrame = CreateFrame("Frame", nil, overlay)
    overlay.textFrame:SetFrameLevel(overlay:GetFrameLevel() + 2)
    overlay.textFrame:SetAllPoints(overlay)
    DisableFrameMouse(overlay.textFrame)
    overlay.textFrame:Show()

    overlay.text = overlay.textFrame:CreateFontString(nil, "OVERLAY")
    local db = cachedDB or DB()
    EnsureActionTextFont(overlay.text, Clamp(db.fontSize, 6, 32))
    overlay._fontSize = Clamp(db.fontSize, 6, 32)
    SafeSetActionText(overlay.text, "", overlay._fontSize)
    overlay.text:SetTextColor(1, 1, 1, 0.95)

    overlayByButton[button] = overlay
    return overlay
end

local function NormalizeMacroSpellToken(token)
    if type(token) ~= "string" then return nil end
    token = token:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    token = token:gsub("^!", "")
    token = token:gsub("^%s*/%S+%s+", "")
    token = token:gsub("^%s*%b[]%s*", "")
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    token = token:match("^([^,;]+)") or token
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    -- Numeric /use targets, item slots, and item links are not spell costs.
    if tonumber(token) then return nil end
    if token:find("|Hitem:") or token:find("item:") then return nil end
    return token
end

local spellbookKnownNames = {}
local spellbookKnownNamesDirty = true

-- Macro resolution can ask about several distinct spell names during one action
-- rebuild. Scanning the complete spellbook once per SPELLS_CHANGED epoch is
-- cheaper than rescanning every tab for each first-seen macro token.
local function InvalidateSpellbookKnownNames()
    spellbookKnownNamesDirty = true
    wipe(spellbookKnownNames)
end

local function EnsureSpellbookKnownNames()
    if not spellbookKnownNamesDirty then return end
    wipe(spellbookKnownNames)

    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
        local tabs = GetNumSpellTabs() or 0
        for tab = 1, tabs do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            offset = offset or 0
            numSpells = numSpells or 0
            for i = offset + 1, offset + numSpells do
                local spellName = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
                if spellName and spellName ~= "" then
                    spellbookKnownNames[spellName:lower()] = true
                end
            end
        end
    end

    spellbookKnownNamesDirty = false
end

local function PlayerKnowsSpell(spell)
    if not spell then return false end
    local spellID = spell
    local name, resolvedID
    if GetSpellInfo then
        -- NOTE: 'GetSpellInfo and GetSpellInfo(spell)' would truncate the call
        -- to one return value, leaving resolvedID permanently nil
        name, _, _, _, _, _, resolvedID = GetSpellInfo(spell)
    end
    if resolvedID then spellID = resolvedID end

    if type(spellID) == "number" then
        if IsSpellKnown and IsSpellKnown(spellID) then return true end
        if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    end

    if not name and type(spell) == "string" then
        name = spell:gsub("%s*%b()%s*$", "")
    end
    if not name or name == "" then return false end

    EnsureSpellbookKnownNames()
    return spellbookKnownNames[name:lower()] == true
end

-- Resolves a /cast line's macro conditionals against current player state, so
-- "[noform:1] Bear Form" yields Bear Form in caster form and nothing in Bear.
--
-- The previous code stripped the %b[] blocks and threw them away, then took the
-- first token the player knew. For the standard form macro --
--     /cast [noform:1] Bear Form
--     /cast [form:1] Maul
-- -- that always resolved to Bear Form, so a shifted druid saw its mana cost
-- instead of Maul's rage cost. Conditions are the whole point of these macros.
--
-- Returns nil when the line's conditions exclude it, which tells the caller to
-- move on to the next line rather than fall back to this line's spell.
local function EvaluateMacroConditions(rest)
    if type(rest) ~= "string" or rest == "" then return nil end

    if _G.SecureCmdOptionParse then
        -- securecall per ARCHITECTURE 1.3: this is Blizzard FrameXML, and we do
        -- not invoke it bare even though it reads as a pure parser.
        local ok, resolved = pcall(securecall, _G.SecureCmdOptionParse, rest)
        if ok then
            -- nil or "" means no clause matched: the line does not fire now.
            if resolved == nil or resolved == "" then return nil end
            return resolved
        end
    end

    -- Fallback for clients without the parser: strip condition blocks, which is
    -- the old state-blind behaviour. Better than losing the overlay entirely.
    local changed = true
    while changed do
        local newRest = rest:gsub("^%s*%b[]%s*", "")
        changed = newRest ~= rest
        rest = newRest
    end
    return rest
end

local function ResolveMacroSpell(macroID)
    if not macroID then return nil end

    -- GetMacroSpell can return the #showtooltip spell even when the macro does
    -- not actually cast that spell. Parse the body first so non-cast helper
    -- macros do not receive missing-power overlays/counters.
    local body = GetMacroBody and GetMacroBody(macroID)
    if type(body) == "string" and body ~= "" then
        for line in body:gmatch("[^\r\n]+") do
            local cmd, rest = line:match("^%s*/([%a]+)%s*(.*)$")
            if cmd then
                cmd = cmd:lower()
                if cmd == "cast" or cmd == "castsequence" or cmd == "castrandom" then
                    local resolved = EvaluateMacroConditions(rest or "")
                    if resolved then
                        -- castsequence advances between casts, and only the game
                        -- tracks where in the sequence we are. GetMacroSpell is a
                        -- C API (no taint concern) and knows the current step.
                        if cmd == "castsequence" and GetMacroSpell then
                            local step = GetMacroSpell(macroID)
                            if step and PlayerKnowsSpell(step) then return step end
                        end

                        -- Strip castsequence modifiers such as reset=target
                        -- before choosing the first concrete spell token.
                        resolved = resolved:gsub("^%s*reset=%S+%s+", "")
                        resolved = resolved:gsub("^%s*reset=[^,;]+[,;]%s*", "")
                        local token = NormalizeMacroSpellToken(resolved)
                        if token and PlayerKnowsSpell(token) then
                            return token
                        end
                    end
                    -- resolved == nil: this line's conditions exclude it right
                    -- now, so fall through and try the next line.
                end
            end
        end
        return nil
    end

    local spell = GetMacroSpell and GetMacroSpell(macroID)
    if spell and PlayerKnowsSpell(spell) then return spell end
    return nil
end

local function GetButtonAction(button)
    if not button then return nil end

    local name = button.GetName and button:GetName() or ""
    if name:find("^StanceButton") then
        local id = button.GetID and button:GetID() or tonumber(name:match("(%d+)$"))
        if id and GetShapeshiftFormInfo then
            local _, _, _, spellID = GetShapeshiftFormInfo(id)
            if spellID then return "spell", spellID end
        end
        return nil
    end

    if name:find("^PetActionButton") then
        local id = button.GetID and button:GetID() or tonumber(name:match("(%d+)$"))
        if id and GetPetActionInfo then
            local petName, _, _, _, _, _, spellID = GetPetActionInfo(id)
            if spellID then return "spell", spellID end
            if petName and type(petName) == "string" and petName ~= "" then return "spell", petName end
        end
        return nil
    end

    local action
    if button.GetAttribute then action = button:GetAttribute("action") end
    if action == nil then action = button._state_action end
    if action == nil then action = button.action end
    if action == nil and _G.ActionButton_GetPagedID then action = _G.ActionButton_GetPagedID(button) end
    if action == nil and _G.ActionButton_CalculateAction then action = _G.ActionButton_CalculateAction(button) end
    if type(action) == "string" then action = tonumber(action) end

    if type(action) == "number" and action > 0 and HasAction and HasAction(action) and GetActionInfo then
        local actionType, id = GetActionInfo(action)
        if actionType == "macro" then
            -- Forever exposes C_ActionBar.GetSpell(actionSlot), which resolves
            -- the spell represented by a macro action in the current secure
            -- state. Prefer that native answer so stance-conditioned Warrior
            -- macros follow Blizzard's own active branch instead of TurboFace
            -- reimplementing macro semantics. Older Classic clients retain the
            -- body/GetMacroSpell fallback below.
            if HasActionSpell then
                local ok, actionSpell = pcall(GetActionSpell, action)
                if ok and actionSpell then
                    return "spell", actionSpell, action, "macro-native"
                end
            end
            local macroSpell = ResolveMacroSpell(id)
            if macroSpell then return "spell", macroSpell, action, "macro-fallback" end
            return nil
        end
        return actionType, id, action, actionType
    end

    return nil
end

local function GetCostForSpell(spell)
    if not spell or not GetSpellPowerCost then return nil end
    -- Keep the cache safe across druid/stance power-type changes. A form swap
    -- may change the player's active resource even when a macro resolves to a
    -- spell name seen previously, so resource type is part of the cache key.
    local playerPowerType = GetPlayerPowerType()
    local key = tostring(spell) .. ":" .. tostring(playerPowerType)
    if spellCostCache[key] ~= nil then return spellCostCache[key] end

    local spellID = spell
    local name, resolvedID
    if GetSpellInfo then
        -- NOTE: 'GetSpellInfo and GetSpellInfo(spell)' would truncate the call
        -- to one return value, leaving resolvedID permanently nil
        name, _, _, _, _, _, resolvedID = GetSpellInfo(spell)
    end
    if resolvedID then spellID = resolvedID end

    local costs = GetSpellPowerCost(spellID) or (name and GetSpellPowerCost(name))
    local found
    if type(costs) == "table" then
        for i = 1, #costs do
            local c = costs[i]
            if c and c.cost and c.cost > 0 and c.type ~= nil then
                if not found or c.type == playerPowerType then
                    found = { cost = c.cost, type = c.type, spellID = spellID, name = name }
                    if c.type == playerPowerType then break end
                end
            end
        end
    end

    spellCostCache[key] = found or false
    return found
end

local function DefaultPowerColor(powerType, alpha)
    local c = PowerBarColor and PowerBarColor[powerType]
    if c then
        return c.r or 1, c.g or 1, c.b or 1, alpha or 0.9
    end
    if powerType == POWER_RAGE then return 1, 0, 0, alpha or 0.9 end
    if powerType == POWER_ENERGY then return 1, 0.8, 0, alpha or 0.9 end
    if powerType == POWER_FOCUS then return 1, 0.5, 0.25, alpha or 0.9 end
    return 0.3, 0.3, 1, alpha or 0.9
end

local function OverlayColor(powerType, db)
    db = db or cachedDB or DB()
    if db.useCustomOverlayColor then
        return ColorWithAlpha(db.overlayColor, 1, 0, 0, 1)
    end
    return DefaultPowerColor(powerType, 1)
end

local function CounterColor(powerType, db)
    db = db or cachedDB or DB()
    if db.useCustomCounterColor then
        return ColorWithAlpha(db.counterColor, 1, 1, 1, 0.95)
    end
    return DefaultPowerColor(powerType, 0.95)
end

local function ClearExistingOverlay(button)
    local overlay = button and overlayByButton[button]
    if not overlay then return end
    overlay.fill:SetAlpha(0)
    if overlay.secretBar then overlay.secretBar:Hide() end
    overlay:Hide()
    overlay._lastText = ""
    SafeSetActionText(overlay.text, "", overlay._fontSize or ((cachedDB and cachedDB.fontSize) or DEFAULTS.fontSize or 12))
end

local function CurveAPI()
    local curveUtil = _G.C_CurveUtil
    local curveType = _G.Enum and _G.Enum.LuaCurveType
    if type(curveUtil) ~= "table" or type(curveUtil.CreateCurve) ~= "function"
        or type(curveType) ~= "table" or curveType.Step == nil
    then
        return nil
    end
    return curveUtil, curveType.Step
end

local function AddCurvePoint(curve, x, y)
    return curve and type(curve.AddPoint) == "function"
        and pcall(curve.AddPoint, curve, x, y)
end

local function BuildStepCurve(points)
    local curveUtil, stepType = CurveAPI()
    if not curveUtil then return nil end
    local ok, curve = pcall(curveUtil.CreateCurve)
    if not ok or not curve then return nil end
    if type(curve.SetType) == "function" then
        local typed = pcall(curve.SetType, curve, stepType)
        if not typed then return nil end
    end
    for i = 1, #points do
        if not AddCurvePoint(curve, points[i][1], points[i][2]) then return nil end
    end
    return curve
end

local function SecretCurves(cost, maxPower, decimals, threshold, fillAlpha)
    -- A tenth-of-a-cast is the practical Forever ceiling.  More precision
    -- would require thousands of step points per distinct spell cost and is not
    -- visually useful on an action button.
    maxPower = tonumber(maxPower)
    if not maxPower or maxPower <= 0 then return nil end
    decimals = math_min(1, math_max(0, tonumber(decimals) or 0))
    threshold = tonumber(threshold) or 0
    local maximumCount = threshold > 0 and threshold or 20
    maximumCount = math_max(1, math_min(maximumCount, 100))
    local key = table.concat({ tostring(cost), tostring(maxPower), tostring(decimals), tostring(maximumCount), tostring(fillAlpha) }, ":")
    local cached = secretCurveCache[key]
    if cached then return cached end

    local multiplier = decimals == 0 and 1 or 10
    local countPoints = {}
    local maxSteps = math_min(maximumCount * multiplier, math_floor((maxPower / cost) * multiplier))
    for step = 0, maxSteps do
        countPoints[#countPoints + 1] = { (step * cost / multiplier) / maxPower, step / multiplier }
    end
    if #countPoints == 0 then countPoints[1] = { 0, 0 } end
    if countPoints[#countPoints][1] < 1 then
        countPoints[#countPoints + 1] = { 1, countPoints[#countPoints][2] }
    end

    -- UnitPowerPercent evaluates curves over a normalized [0,1] resource
    -- domain. All normalization math here uses only readable spell cost and
    -- readable player max power; the current power value never enters Lua.
    local costPoint = cost / maxPower
    local visibilityEnd = (maximumCount * cost) / maxPower
    local epsilon = math_min(0.00001, costPoint / 1000)
    local counterAlpha = BuildStepCurve({
        { 0, 0 }, { epsilon, 1 },
        { math_max(epsilon, visibilityEnd - epsilon), 1 }, { visibilityEnd, 0 },
    })
    local fillVisibility = BuildStepCurve({
        { 0, 0 }, { epsilon, fillAlpha },
        -- UnitPowerPercent evaluates this curve in normalized [0,1] space.
        -- Hide the missing-power tint as soon as the first cast is affordable;
        -- the cast counter may continue to show 1.x / 2.x / etc independently.
        { math_max(epsilon, costPoint - epsilon), fillAlpha }, { costPoint, 0 },
    })
    local count = BuildStepCurve(countPoints)
    if not count or not counterAlpha or not fillVisibility then return nil end
    cached = { count = count, counterAlpha = counterAlpha, fillAlpha = fillVisibility }
    secretCurveCache[key] = cached
    return cached
end

local function EvaluateUnitPowerCurve(powerType, curve)
    if not curve or not ns.API.GetUnitPowerPercentOpaque then return false end
    return ns.API.GetUnitPowerPercentOpaque("player", powerType, false, curve)
end

local function SetSecretActionText(fontString, value)
    if not fontString then return false end
    -- Do not stringify or format the curve result in addon Lua.  Forever's
    -- FontString native formatter is the sink: it receives the secret number as
    -- an untouched vararg and performs the conversion on the UI side.
    if type(fontString.SetFormattedText) == "function" then
        return pcall(fontString.SetFormattedText, fontString, "%s", value)
    end
    return pcall(fontString.SetText, fontString, value)
end

local function RenderSecretPower(overlay, powerType, cost, maxPower, opaquePower, db, fontSize, overlayAlpha)
    overlay._secretValueOK = false
    overlay._secretMaxPowerOK = type(maxPower) == "number" and maxPower > 0
    overlay._secretFillCurveOK = false
    overlay._secretFillSinkOK = false
    overlay._secretCountCurveOK = false
    overlay._secretTextSinkOK = false
    overlay._secretCounterCurveOK = false
    overlay._secretCounterSinkOK = false

    local _, _, _, configuredFillAlpha = OverlayColor(powerType, db)
    local fillAlpha = overlayAlpha * Clamp(configuredFillAlpha or 1, 0, 1)
    local curves = SecretCurves(cost, maxPower, db.decimals, db.displayIfLowerThan, fillAlpha)
    if not curves or not overlay.secretBar then return false end

    overlay.fill:SetAlpha(0)
    overlay.secretBar:Show()
    overlay.secretBar:SetAlpha(1)
    overlay.secretBar:SetMinMaxValues(0, cost)
    local valueOK = pcall(overlay.secretBar.SetValue, overlay.secretBar, opaquePower)
    local alphaOK, secretFillAlpha = EvaluateUnitPowerCurve(powerType, curves.fillAlpha)
    local r, g, b = OverlayColor(powerType, db)
    -- SetAlpha(secret) proved too opaque to diagnose in Prep119.  StatusBar
    -- color is an explicit secret-aspect sink, so feed the curve-produced alpha
    -- directly into that setter and keep the frame's ordinary alpha at 1.
    local appliedFill = alphaOK
        and pcall(overlay.secretBar.SetStatusBarColor, overlay.secretBar, r, g, b, secretFillAlpha)
    if not (valueOK and appliedFill) then
        overlay.secretBar:SetAlpha(0)
    end

    if overlay._fontSize ~= fontSize then
        overlay._fontSize = fontSize
        EnsureActionTextFont(overlay.text, fontSize)
    end
    overlay.text:SetAlpha(1)
    local countOK, textOK, textAlphaOK, appliedTextAlpha = true, true, true, true
    if db.showActionCounter == false then
        overlay.text:SetAlpha(0)
        SafeSetActionText(overlay.text, "", fontSize)
    else
        local secretCount, secretTextAlpha
        countOK, secretCount = EvaluateUnitPowerCurve(powerType, curves.count)
        textAlphaOK, secretTextAlpha = EvaluateUnitPowerCurve(powerType, curves.counterAlpha)
        textOK = countOK and SetSecretActionText(overlay.text, secretCount)
        local tr, tg, tb, ta = CounterColor(powerType, db)
        -- As with the fill, visibility travels through the native color aspect
        -- instead of Region:SetAlpha(secret).  No Lua operation touches the
        -- curve result.
        appliedTextAlpha = textAlphaOK
            and pcall(overlay.text.SetTextColor, overlay.text, tr, tg, tb, secretTextAlpha)
        if not (textOK and appliedTextAlpha) then
            overlay.text:SetAlpha(0)
        end
    end

    -- Probe state contains only ordinary success booleans.  Never retain or
    -- stringify the opaque input or any curve result for diagnostics.
    overlay._secretValueOK = valueOK
    overlay._secretFillCurveOK = alphaOK
    overlay._secretFillSinkOK = appliedFill
    overlay._secretCountCurveOK = countOK
    overlay._secretTextSinkOK = textOK
    overlay._secretCounterCurveOK = textAlphaOK
    overlay._secretCounterSinkOK = appliedTextAlpha

    -- Fill and counter are independent.  A rejected text sink must not hide a
    -- working StatusBar (and vice versa), which was Prep119's all-or-nothing
    -- failure mode.
    return valueOK or textOK
end

-- =============================================================================
-- MODULE MASTER GATES
-- PowerCost owns two independently opt-out-able features that used to share the
-- single `power.enabled` flag:
--   * modules.hotbarPower -> the action-button cost overlay and counter
--   * modules.playerTicks -> the player health/power bar tick markers
-- The legacy db.enabled / db.actionOverlayEnabled flags are still honored on top
-- of the gates, so nothing a user already turned off comes back on.
-- =============================================================================
local function ModGate(family)
    return (not ns.ModuleEnabled) or ns.ModuleEnabled(family)
end

local function OverlayEnabled(db)
    if not ModGate("hotbarPower") then return false end
    return db.enabled ~= false and db.actionOverlayEnabled ~= false
end

local function TicksEnabled(db)
    if not ModGate("playerTicks") then return false end
    return db.enabled ~= false
end

local function RebuildCosts(refreshButtons, invalidateSpellCosts)
    local db = DB()
    local deferredFrameCreation = false
    wipe(buttonData)

    -- Button objects are stable after login; action/page/form changes alter the
    -- action IDs they resolve to, not the frame objects themselves. Likewise, a
    -- form/page change does not alter the intrinsic cost of a known spell. Keep
    -- both caches warm unless the caller explicitly owns an invalidation event.
    if refreshButtons or #buttons == 0 then
        CollectButtons()
    end
    if invalidateSpellCosts then
        wipe(spellCostCache)
    end

    if not OverlayEnabled(db) then
        for _, button in ipairs(buttons) do
            ClearExistingOverlay(button)
        end
        return false
    end

    local fontSize = Clamp(db.fontSize, 6, 32)
    for _, button in ipairs(buttons) do
        local actionType, id = GetButtonAction(button)
        local costInfo
        if actionType == "spell" or actionType == "macro" then
            costInfo = GetCostForSpell(id)
        end

        -- Do not allocate overlay frames for empty buttons or no-cost abilities.
        -- Existing overlays are only cleared when a button changes from costed
        -- to empty/no-cost.
        if costInfo then
            local overlay = CreateActionOverlay(button)
            if overlay then
                overlay:Show()
                if overlay._fontSize ~= fontSize then
                    overlay._fontSize = fontSize
                    EnsureActionTextFont(overlay.text, fontSize)
                end
                buttonData[button] = { cost = costInfo.cost, type = costInfo.type, spellID = costInfo.spellID, overlay = overlay }
            elseif InCombatLockdown and InCombatLockdown() then
                -- The cost data was resolved, but the overlay frame could not be
                -- allocated safely in combat. One post-combat rebuild is needed.
                deferredFrameCreation = true
            end
        else
            ClearExistingOverlay(button)
        end
    end
    return deferredFrameCreation
end
local function PositionActionText(overlay, button, db)
    if not overlay or not overlay.text or not button then return end
    local anchor = db.textAnchor
    if not ANCHORS[anchor] then anchor = "CENTER" end
    if overlay._lastAnchor == anchor and overlay._lastX == db.textOffsetX and overlay._lastY == db.textOffsetY then return end
    overlay._lastAnchor = anchor
    overlay._lastX = db.textOffsetX
    overlay._lastY = db.textOffsetY
    overlay.text:ClearAllPoints()
    overlay.text:SetPoint("CENTER", overlay, anchor, tonumber(db.textOffsetX) or 0, tonumber(db.textOffsetY) or 0)
end

local function RenderActionOverlay()
    local db = DB()
    if not OverlayEnabled(db) then return end

    wipe(powerCache)
    local fontSize = Clamp(db.fontSize, 6, 32)
    local decimals = Clamp(db.decimals, 0, 3)
    local threshold = tonumber(db.displayIfLowerThan) or 0
    local overlayAlpha = Clamp(db.overlayAlpha, 0, 1)

    for button, data in pairs(buttonData) do
        local overlay = data.overlay or overlayByButton[button]
        if overlay and data.cost and data.cost > 0 then
            local buttonShown = not button.IsShown or button:IsShown()
            if not buttonShown then
                overlay:Hide()
            else
                overlay:Show()
            local powerType = data.type
            local powerState = powerCache[powerType]
            if not powerState then
                local readable = ns.API.ReadUnitPower("player", powerType)
                powerState = {
                    readable = readable,
                    maxPower = ns.API.ReadUnitPowerMax("player", powerType),
                }
                if readable == nil and ns.API.GetUnitPowerOpaque then
                    local ok, opaque = ns.API.GetUnitPowerOpaque("player", powerType)
                    if ok and ns.API.IsSecretValue(opaque) then
                        powerState.secret = true
                        powerState.opaque = opaque
                    end
                end
                powerCache[powerType] = powerState
            end
            local current = powerState.readable

            if overlay._fontSize ~= fontSize then
                overlay._fontSize = fontSize
                EnsureActionTextFont(overlay.text, fontSize)
            end
            PositionActionText(overlay, button, db)

            if current == nil then
                if powerState.secret then
                    local rendered = RenderSecretPower(
                        overlay, powerType, data.cost, powerState.maxPower, powerState.opaque,
                        db, fontSize, overlayAlpha)
                    if not rendered then
                        overlay.fill:SetAlpha(0)
                        overlay.secretBar:SetAlpha(0)
                    end
                else
                    overlay.fill:SetAlpha(0)
                    overlay.secretBar:Hide()
                    overlay.text:SetAlpha(0)
                    SafeSetActionText(overlay.text, "", fontSize)
                end
            else
            overlay.secretBar:Hide()
            overlay.text:SetAlpha(1)
            local amount = current / data.cost
            local missingRatio = 0
            if current < data.cost then missingRatio = math_max(0, math_min(1, current / data.cost)) end

            local w = button.GetWidth and button:GetWidth() or 36
            local h = button.GetHeight and button:GetHeight() or 36
            if not w or w <= 0 then w = 36 end
            if not h or h <= 0 then h = 36 end

            if missingRatio > 0 then
                local fillH = math_max(1, h * missingRatio)
                local y = fillH - h
                overlay.fill:ClearAllPoints()
                overlay.fill:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, y)
                overlay.fill:SetWidth(w)
                overlay.fill:SetHeight(fillH)
                local r, g, b, a = OverlayColor(powerType, db)
                overlay.fill:SetAlpha(overlayAlpha * Clamp(a or 1, 0, 1))
                overlay.fill.texture:SetColorTexture(r, g, b, 1)
            else
                overlay.fill:SetAlpha(0)
            end

            local wantText = ""
            if db.showActionCounter ~= false and amount > 0 and (threshold <= 0 or amount < threshold) then
                wantText = FormatCount(amount, decimals)
            end
            if overlay._lastText ~= wantText then
                overlay._lastText = wantText
                SafeSetActionText(overlay.text, wantText, fontSize)
            end
            local tr, tg, tb, ta = CounterColor(powerType, db)
            if overlay._tr ~= tr or overlay._tg ~= tg or overlay._tb ~= tb or overlay._ta ~= ta then
                overlay._tr, overlay._tg, overlay._tb, overlay._ta = tr, tg, tb, ta
                overlay.text:SetTextColor(tr, tg, tb, ta or 0.9)
            end
            end
            end
        end
    end
end

local function QueueRender()
    if renderQueued then return end
    renderQueued = true
    After(0.05, function()
        renderQueued = false
        RenderActionOverlay()
    end)
end

-- Structural rebuilds are normally deferred in combat unless the triggering
-- event can actually change slot/macro resolution. Shapeshifting is the key
-- exception: form changes can alter the spell resolved by a conditional macro,
-- so those rebuilds are allowed to update existing overlays immediately.
-- CreateActionOverlay still refuses to create new frames in combat; any missing
-- overlay frame is caught by the single deferred PLAYER_REGEN_ENABLED rebuild.
local function PerformQueuedRebuild(refreshButtons, invalidateSpellCosts)
    local deferred = RebuildCosts(refreshButtons, invalidateSpellCosts)
    RenderActionOverlay()
    if deferred then postCombatRebuildNeeded = true end
end

local function QueueRebuild(delay, allowInCombat, refreshButtons, invalidateSpellCosts)
    -- Latch policy bits so a lower-cost request cannot swallow a stronger one
    -- while the 100 ms coalescing window is already armed.
    if allowInCombat then rebuildAllowCombat = true end
    if refreshButtons then rebuildRefreshButtons = true end
    if invalidateSpellCosts then rebuildInvalidateSpellCosts = true end
    if rebuildQueued then return end
    rebuildQueued = true
    After(delay or 0.10, function()
        rebuildQueued = false
        local allow = rebuildAllowCombat
        local refresh = rebuildRefreshButtons
        local invalidate = rebuildInvalidateSpellCosts
        rebuildAllowCombat = false
        rebuildRefreshButtons = false
        rebuildInvalidateSpellCosts = false
        if not allow and InCombatLockdown and InCombatLockdown() then
            -- Remember skipped structural work and preserve its invalidation
            -- requirements for the single post-combat catch-up rebuild.
            postCombatRebuildNeeded = true
            if refresh then postCombatRefreshButtons = true end
            if invalidate then postCombatInvalidateSpellCosts = true end
            return
        end
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("Power/PowerCost:Rebuild", PerformQueuedRebuild, refresh, invalidate)
        else
            PerformQueuedRebuild(refresh, invalidate)
        end
    end)
end

-- Regen marker/state implementation lives in Power/RegenTicks.lua.

function Power:ShowTickAmount(bar, amount, r, g, b)
    if ns.RegenTicks then return ns.RegenTicks:ShowTickAmount(bar, amount, r, g, b) end
end

function Power:GetTickAmountColor(pt)
    if ns.RegenTicks then return ns.RegenTicks:GetTickAmountColor(pt) end
    return 1, 1, 1
end

function Power:GetRegenDebugState()
    return ns.RegenTicks and ns.RegenTicks:GetDebugState() or nil
end

local function OnEvent(_, event, arg1, arg2, arg3)
    local db = cachedDB or DB()
    local overlayOn = OverlayEnabled(db)
    local ticksOn = TicksEnabled(db)

    -- RegenTicks owns all player regen/5SR state. PowerCost keeps the shared
    -- event frame so UNIT_* registrations remain coalesced when both features
    -- are active, then forwards only when the player-tick gate is enabled.
    -- Kill-traced here rather than inside RegenTicks: this is the only call
    -- site, and RegenTicks owns no event frame of its own. Health markers become
    -- eligible the moment combat ends, so this path wakes exactly post-kill.
    if ticksOn and ns.RegenTicks then
        ns.KillTrace("Power/RegenTicks:", event, ns.RegenTicks.OnEvent,
                     ns.RegenTicks, event, arg1, arg2, arg3, db)
    end

    if not overlayOn then return end

    if event == "PLAYER_REGEN_ENABLED" then
        if postCombatRebuildNeeded then
            postCombatRebuildNeeded = false
            local refresh = postCombatRefreshButtons
            local invalidate = postCombatInvalidateSpellCosts
            postCombatRefreshButtons = false
            postCombatInvalidateSpellCosts = false
            QueueRebuild(0.05, false, refresh, invalidate)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then QueueRender() end
    elseif event == "UNIT_DISPLAYPOWER" or event == "UNIT_POWER_UPDATE"
        or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
        if arg1 == "player" then QueueRender() end
    elseif event == "SPELL_UPDATE_USABLE" then
        -- SPELL_UPDATE_USABLE is a presentation/usability signal, not a
        -- structural action-bar change. Classic can emit it repeatedly around
        -- target/combat transitions. Routing it through QueueRebuild() caused
        -- a full button/macro/cost rescan each time. Live tracing showed that
        -- work was the dominant avoidable post-combat cost. Power/resource
        -- state is already reflected by RenderActionOverlay(), so keep this on
        -- the cheap coalesced render path. If a future macro condition requires
        -- extra resolution coverage, add a targeted macro refresh rather than
        -- restoring a global rebuild here.
        QueueRender()
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
        or event == "SPELLS_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "UPDATE_BINDINGS" then
        if event == "SPELLS_CHANGED" then InvalidateSpellbookKnownNames() end
        local resolutionChanged = (event == "UPDATE_SHAPESHIFT_FORM")
            or (event == "UPDATE_BONUS_ACTIONBAR")
            or (event == "ACTIONBAR_PAGE_CHANGED")
            or (event == "ACTIONBAR_SLOT_CHANGED")
        -- Form/page/slot changes require action and macro re-resolution, but
        -- they do not change the intrinsic cost of already-known spells or the
        -- identity of Blizzard's button frames. SPELLS_CHANGED owns the cost
        -- cache invalidation because learned ranks/talents can change it.
        local invalidateCosts = (event == "SPELLS_CHANGED")
        QueueRebuild(0.10, resolutionChanged, false, invalidateCosts)
    elseif event == "PLAYER_ENTERING_WORLD" then
        InvalidateSpellbookKnownNames()
        QueueRebuild(0.35, false, true, true)
    end
end

local function RegisterEventSafe(frame, event)
    if frame and frame.RegisterEvent then pcall(frame.RegisterEvent, frame, event) end
end

local function RegisterUnitEventSafe(frame, event, unit)
    if frame and frame.RegisterUnitEvent then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if ok then return end
    end
    RegisterEventSafe(frame, event)
end


-- Register only the event families required by the two independently-gated
-- features. Shared player power events are subscribed once when either feature
-- needs them; each OnEvent branch above still checks its own gate before doing
-- work, so disabling one half does not leave its calculations running.
local function ConfigureRuntimeEvents(db)
    db = db or cachedDB or DB()
    local overlayOn = OverlayEnabled(db)
    local ticksOn = TicksEnabled(db)
    if not (overlayOn or ticksOn) then
        if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
        if ns.RegenTicks then ns.RegenTicks:Refresh(db) end
        return false
    end

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    elseif eventFrame.UnregisterAllEvents then
        eventFrame:UnregisterAllEvents()
    end

    RegisterEventSafe(eventFrame, "PLAYER_ENTERING_WORLD")
    RegisterEventSafe(eventFrame, "PLAYER_REGEN_ENABLED")

    if overlayOn then
        RegisterEventSafe(eventFrame, "ACTIONBAR_SLOT_CHANGED")
        RegisterEventSafe(eventFrame, "ACTIONBAR_PAGE_CHANGED")
        RegisterEventSafe(eventFrame, "SPELLS_CHANGED")
        RegisterEventSafe(eventFrame, "SPELL_UPDATE_USABLE")
        RegisterEventSafe(eventFrame, "UPDATE_BINDINGS")
    end

    if ticksOn then
        RegisterEventSafe(eventFrame, "PLAYER_REGEN_DISABLED")
        RegisterUnitEventSafe(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        RegisterUnitEventSafe(eventFrame, "UNIT_HEALTH", "player")
        RegisterUnitEventSafe(eventFrame, "UNIT_MAXHEALTH", "player")
    end

    if overlayOn or ticksOn then
        RegisterEventSafe(eventFrame, "UPDATE_SHAPESHIFT_FORM")
        RegisterEventSafe(eventFrame, "UPDATE_BONUS_ACTIONBAR")
        RegisterUnitEventSafe(eventFrame, "UNIT_DISPLAYPOWER", "player")
        RegisterUnitEventSafe(eventFrame, "UNIT_POWER_UPDATE", "player")
        RegisterUnitEventSafe(eventFrame, "UNIT_MAXPOWER", "player")
    end

    return true
end

function Power:RenderOnly()
    DB(true)
    if not initialized then return end
    RenderActionOverlay()
    if ns.RegenTicks then ns.RegenTicks:Refresh(cachedDB) end
end

-- Lightweight marker-only wake path used by the Druid auxiliary mana bar after
-- its visibility changes. This avoids rebuilding or rerendering action overlays.
function Power:RefreshMarkers()
    if not initialized then return end
    if ns.RegenTicks then ns.RegenTicks:Refresh(cachedDB or DB()) end
end

function Power:QueueRebuild(delay)
    -- Public/manual rebuild keeps the historical full-invalidation semantics.
    QueueRebuild(delay or 0.10, false, true, true)
end

function Power:Refresh(mode)
    DB(true)
    if not initialized then
        self:Init()
        if not initialized then return end
    end
    ConfigureRuntimeEvents(cachedDB)
    if ns.RegenTicks then ns.RegenTicks:Refresh(cachedDB) end
    if mode == "render" then
        RenderActionOverlay()
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    RebuildCosts(true, true)
    RenderActionOverlay()
end
function Power:Init()
    if initialized then return end
    DB(true)

    -- If both public feature gates are off, PowerCost owns no event frame,
    -- no delayed refreshes, and no tick driver. Refresh() can still activate it
    -- later if a non-master option is enabled live.
    if not ConfigureRuntimeEvents(cachedDB) then return end
    initialized = true

    if TicksEnabled(cachedDB) and ns.RegenTicks then
        ns.RegenTicks:Reset(cachedDB)
    end

    After(0.50, function() Power:Refresh() end)
    After(1.50, function() Power:Refresh() end)
end

-- Bounded, read-only live evidence for Forever action-bar drift.  This reports
-- only TurboFace-owned state plus public action/spell metadata; it never walks
-- native regions or mutates a Blizzard button.
function Power:Probe()
    local db = DB(true)
    if not (InCombatLockdown and InCombatLockdown()) then self:Refresh() end
    if #buttons == 0 then CollectButtons() end

    local resolved, costed, overlayCount, shown, samples = 0, 0, 0, 0, 0
    local macroNative, macroFallback = 0, 0
    for _, button in ipairs(buttons) do
        if not button.IsShown or button:IsShown() then shown = shown + 1 end
        if overlayByButton[button] then overlayCount = overlayCount + 1 end

        local okAction, actionType, id, slot, source = pcall(GetButtonAction, button)
        if okAction and actionType then
            resolved = resolved + 1
            if source == "macro-native" then
                macroNative = macroNative + 1
            elseif source == "macro-fallback" then
                macroFallback = macroFallback + 1
            end
            local okCost, costInfo = pcall(GetCostForSpell, id)
            if okCost and costInfo then costed = costed + 1 end
            if samples < 6 then
                samples = samples + 1
                local current = costInfo and ns.API.ReadUnitPower("player", costInfo.type) or nil
                ns:Chat("PowerProbe", string.format(
                    "B[%d] %s slot=%s type=%s source=%s id=%s cost=%s powerType=%s current=%s overlay=%s",
                    samples,
                    tostring(button.GetName and button:GetName() or "unnamed"),
                    ns.API.SafeToString(slot, "nil"), ns.API.SafeToString(actionType, "nil"),
                    ns.API.SafeToString(source, "nil"),
                    ns.API.SafeToString(id, "nil"),
                    ns.API.SafeToString(costInfo and costInfo.cost, okCost and "none" or "error"),
                    ns.API.SafeToString(costInfo and costInfo.type, "nil"),
                    ns.API.SafeToString(current, "nil"),
                    tostring(overlayByButton[button] ~= nil)))
            end
        end
    end

    ns:Chat("PowerProbe", string.format(
        "initialized=%s gate=%s enabled=%s actionOverlay=%s buttons=%d shown=%d resolved=%d costed=%d overlays=%d macroNative=%d macroFallback=%d actionAPI=%s actionSpellAPI=%s",
        tostring(initialized), tostring(ModGate("hotbarPower")),
        tostring(db.enabled ~= false), tostring(db.actionOverlayEnabled ~= false),
        #buttons, shown, resolved, costed, overlayCount, macroNative, macroFallback,
        tostring(ns.API.IsAvailable and ns.API.IsAvailable("GetActionInfo") or false),
        tostring(HasActionSpell)))

    local rawPowerOK, rawPower = pcall(UnitPower, "player", POWER_RAGE)
    local rawPowerSecret = rawPowerOK and ns.API.IsSecretValue(rawPower) or false
    local sink = self._probeStatusBar
    if not sink then
        sink = CreateFrame("StatusBar", nil, UIParent)
        sink:SetSize(1, 1)
        sink:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
        sink:SetMinMaxValues(0, 100)
        sink:Hide()
        self._probeStatusBar = sink
    end
    local sinkOK = rawPowerOK and pcall(sink.SetValue, sink, rawPower) or false

    local powerPercent = _G.UnitPowerPercent
    local percentOK, percentValue = false, nil
    if type(powerPercent) == "function" then
        percentOK, percentValue = pcall(powerPercent, "player", POWER_RAGE, true)
    end

    local curveUtil = _G.C_CurveUtil
    local colorCurveOK, colorCurve = false, nil
    if type(curveUtil) == "table" and type(curveUtil.CreateColorCurve) == "function" then
        colorCurveOK, colorCurve = pcall(curveUtil.CreateColorCurve)
    end
    local numberCurveOK, numberCurve = false, nil
    if type(curveUtil) == "table" and type(curveUtil.CreateCurve) == "function" then
        numberCurveOK, numberCurve = pcall(curveUtil.CreateCurve)
    end
    ns:Chat("PowerProbe", string.format(
        "secretPath rawOK=%s rawSecret=%s statusBarSink=%s powerPercentAPI=%s percentOK=%s percent=%s colorCurve=%s colorAddPoint=%s colorEvaluate=%s numberCurve=%s numberAddPoint=%s numberEvaluate=%s",
        tostring(rawPowerOK), tostring(rawPowerSecret), tostring(sinkOK),
        tostring(type(powerPercent) == "function"), tostring(percentOK),
        ns.API.SafeToString(percentValue, "secret"), tostring(colorCurveOK),
        tostring(colorCurveOK and type(colorCurve.AddPoint) == "function"),
        tostring(colorCurveOK and type(colorCurve.Evaluate) == "function"),
        tostring(numberCurveOK),
        tostring(numberCurveOK and type(numberCurve.AddPoint) == "function"),
        tostring(numberCurveOK and type(numberCurve.Evaluate) == "function")))

    local renderOverlay
    for _, data in pairs(buttonData) do
        if data and data.overlay and data.cost and data.cost > 0 then
            renderOverlay = data.overlay
            break
        end
    end
    if renderOverlay then
        ns:Chat("PowerProbe", string.format(
            "render value=%s maxPower=%s fillCurve=%s fillSink=%s countCurve=%s textSink=%s counterCurve=%s counterSink=%s formattedText=%s statusBarColor=%s",
            tostring(renderOverlay._secretValueOK),
            tostring(renderOverlay._secretMaxPowerOK),
            tostring(renderOverlay._secretFillCurveOK),
            tostring(renderOverlay._secretFillSinkOK),
            tostring(renderOverlay._secretCountCurveOK),
            tostring(renderOverlay._secretTextSinkOK),
            tostring(renderOverlay._secretCounterCurveOK),
            tostring(renderOverlay._secretCounterSinkOK),
            tostring(renderOverlay.text and type(renderOverlay.text.SetFormattedText) == "function"),
            tostring(renderOverlay.secretBar and type(renderOverlay.secretBar.SetStatusBarColor) == "function")))
    end
end

ns.RegisterCPUProfileTarget("Power/PowerCost:Events", OnEvent, false)
