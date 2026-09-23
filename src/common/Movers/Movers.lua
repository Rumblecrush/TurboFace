local _, ns = ...

-- =============================================================================
-- TurboFace Movers
-- Classic Era 1.15.x-only mover foundation for TurboFace.
-- Provides lock/unlock drag overlays, saved unit-frame anchors, and player/target
-- aura anchor layout without Retail Edit Mode or cross-version MoveAny code.
-- =============================================================================

local M = {}
ns.Movers = M

local _G = _G
local UIParent = UIParent
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local math_floor = math.floor
local math_ceil = math.ceil
local math_min = math.min
local math_abs = math.abs
local string_format = string.format
local IsShiftKeyDown = IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown
local GetCursorPosition = GetCursorPosition
local GetFramerate = GetFramerate
local tonumber = tonumber
local tostring = tostring
local type = type
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local wipe = wipe
local unpack = unpack

local DEFAULTS = ns.defaults.movers
local QUEST_TRACKER_MOVER_AVAILABLE = ns.FeatureAvailable("movers.questTracker", true)

local GENERIC_ELEMENT_DEFAULTS = { enabled = true, hidden = false, clickThrough = false }

local elements = {}
local order = {}
M.initialized = false
M.active = false
local needsAuraUpdate = false
local activeElementID

local moverParent
local eventFrame
local auraDriver
local auraDriverScheduled = false
local gridFrame
local auraDelayedQueued = false

-- Unit-frame, action-bar, and durability movers were removed when 1.15.9
-- imported HUD Edit Mode: Blizzard now owns placement of those frames.
-- Movers remain for TurboFace-created elements plus select Blizzard systems
-- that Edit Mode cannot position independently (stock loot and group rolls).

local MergeDefaults = ns.MergeDefaults
local After = ns.After
local function Chat(msg) ns:Chat("Movers", msg) end

local function DB()
    if not TurboFaceDB then TurboFaceDB = {} end
    if type(TurboFaceDB.movers) ~= "table" then TurboFaceDB.movers = {} end
    MergeDefaults(TurboFaceDB.movers, DEFAULTS)


    return TurboFaceDB.movers
end

local function ElementDB(id)
    local db = DB()
    if type(db.elements) ~= "table" then db.elements = {} end
    if type(db.elements[id]) ~= "table" then db.elements[id] = {} end
    MergeDefaults(db.elements[id], DEFAULTS.elements[id] or GENERIC_ELEMENT_DEFAULTS)
    MergeDefaults(db.elements[id], GENERIC_ELEMENT_DEFAULTS)
    return db.elements[id]
end

local function AuraDB()
    local db = DB()
    if type(db.aura) ~= "table" then db.aura = {} end
    MergeDefaults(db.aura, DEFAULTS.aura)
    return db.aura
end

local function RoundTo(v, step)
    step = tonumber(step) or 0
    if step <= 1 then return math_floor((v or 0) + 0.5) end
    if (v or 0) >= 0 then
        return math_floor(v / step + 0.5) * step
    end
    return math_ceil(v / step - 0.5) * step
end

local function IsProtected(frame)
    return frame and frame.IsProtected and frame:IsProtected()
end

local function RelativeScale(frame)
    if frame and frame.GetEffectiveScale then
        local scale = frame:GetEffectiveScale()
        if scale and scale > 0 then return scale end
    end
    return 1
end

local function VisualOffsetToFrameOffset(frame, rel, x, y)
    -- Saved mover coordinates are stored in UIParent/screen space so a frame
    -- still lands under the cursor after its own scale changes. WoW applies a
    -- frame's effective scale to SetPoint offsets, so scaled-down bars need
    -- larger raw offsets and scaled-up bars need smaller raw offsets.
    x, y = x or 0, y or 0
    local frameScale = RelativeScale(frame)
    local relScale = RelativeScale(rel or UIParent)
    if frameScale <= 0 or relScale <= 0 then return x, y end
    local factor = frameScale / relScale
    if factor > 0 and math_abs(factor - 1) > 0.0001 then
        return x / factor, y / factor
    end
    return x, y
end

local function SafeClearAndSetPoint(frame, point, rel, relPoint, x, y)
    if not frame then return false end
    rel = rel or UIParent
    local ox, oy = VisualOffsetToFrameOffset(frame, rel, x or 0, y or 0)
    frame:ClearAllPoints()
    frame:SetPoint(point or "CENTER", rel, relPoint or point or "CENTER", ox, oy)
    return true
end

local function CapturePoint(frame)
    if not frame or not frame.GetPoint then return nil end
    local point, rel, relPoint, x, y = frame:GetPoint(1)
    if not point then return nil end
    return { point, rel or UIParent, relPoint or point, x or 0, y or 0 }
end

local function DefaultCenterPoint(frame)
    if not frame or not frame.GetCenter then return { "CENTER", UIParent, "CENTER", 0, 0 } end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and cy and ux and uy then
        return { "CENTER", UIParent, "CENTER", cx - ux, cy - uy }
    end
    return { "CENTER", UIParent, "CENTER", 0, 0 }
end

local function SavedPoint(edb)
    if edb and edb.point then
        return edb.point, UIParent, edb.relativePoint or edb.point, edb.x or 0, edb.y or 0
    end
end

local function ClearSavedPoint(edb)
    if not edb then return end
    edb.point = nil
    edb.relativePoint = nil
    edb.x = nil
    edb.y = nil
end

local function PointFromCenter(frame)
    if not frame or not frame.GetCenter then return nil end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and cy and ux and uy then
        return { "CENTER", UIParent, "CENTER", cx - ux, cy - uy }
    end
    return nil
end

local function CursorPositionFromCenter()
    if not GetCursorPosition then return 0, 0 end
    local scale = RelativeScale(UIParent)
    local x, y = GetCursorPosition()
    local ux, uy = UIParent:GetCenter()
    if not x or not y or not ux or not uy then return 0, 0 end
    return (x / scale) - ux, (y / scale) - uy
end

local function CurrentElementXY(id, info)
    local edb = ElementDB(id)
    if edb.point == "CENTER" and edb.x ~= nil and edb.y ~= nil then
        return RoundTo(tonumber(edb.x) or 0, 1), RoundTo(tonumber(edb.y) or 0, 1)
    end

    local p = PointFromCenter(info and info.frame)
    if p then return RoundTo(p[4] or 0, 1), RoundTo(p[5] or 0, 1) end
    return 0, 0
end

-- Mover overlays use BackdropTemplate on Classic Era. Calling geometry readers on
-- a backdrop frame while Blizzard is refreshing its nine-slice coordinates can
-- re-enter Backdrop.lua's own measurement path. Overlay positions are fully known
-- to us, so never measure the overlay itself: while dragging use the coordinates
-- already computed by the drag driver; otherwise use the owned element's position.
local function OverlayElementXY(id, overlay)
    if overlay and overlay.turboFaceDragging and overlay.turboFaceDragCurrentX ~= nil then
        return overlay.turboFaceDragCurrentX or 0, overlay.turboFaceDragCurrentY or 0
    end
    return CurrentElementXY(id, elements[id])
end

local function SaveElementXY(id, x, y, useSnap)
    local db = DB()
    local edb = ElementDB(id)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    if useSnap ~= false and db.snapToGrid ~= false then
        local step = tonumber(db.snapSize) or 1
        x, y = RoundTo(x, step), RoundTo(y, step)
    else
        x, y = RoundTo(x, 1), RoundTo(y, 1)
    end
    edb.point = "CENTER"
    edb.relativePoint = "CENTER"
    edb.x = x
    edb.y = y
    return x, y
end

local function NudgeStep()
    local db = DB()
    local step = tonumber(db.nudgeStep) or 1
    if step < 1 then step = 1 end
    if step > 100 then step = 100 end
    if IsShiftKeyDown and IsShiftKeyDown() then
        step = tonumber(db.snapSize) or step
        if step < 1 then step = 1 end
    end
    if IsAltKeyDown and IsAltKeyDown() then
        step = step * 10
    end
    return step
end

local function SaveOverlayCenter(id, overlay)
    if not overlay then return end
    local x, y = OverlayElementXY(id, overlay)
    SaveElementXY(id, x or 0, y or 0, true)
end

local function FrameWidth(frame, fallback)
    if frame and frame.GetWidth then
        local w = frame:GetWidth()
        if w and w > 0 then return w end
    end
    return fallback or 120
end

local function FrameHeight(frame, fallback)
    if frame and frame.GetHeight then
        local h = frame:GetHeight()
        if h and h > 0 then return h end
    end
    return fallback or 32
end

local function EnsureMoverParent()
    if moverParent then return moverParent end
    moverParent = CreateFrame("Frame", "TurboFaceMoverParent", UIParent)
    moverParent:SetAllPoints(UIParent)
    moverParent:SetFrameStrata("DIALOG")
    moverParent:Hide()
    return moverParent
end

local function EnsureGridFrame()
    if gridFrame then return gridFrame end
    local parent = EnsureMoverParent()
    gridFrame = CreateFrame("Frame", "TurboFaceMoverGrid", parent)
    gridFrame:SetAllPoints(parent)
    gridFrame:SetFrameLevel(parent:GetFrameLevel() + 1)
    gridFrame:EnableMouse(false)
    gridFrame.lines = {}
    gridFrame:Hide()
    return gridFrame
end

local function AcquireGridLine(index)
    local f = EnsureGridFrame()
    local line = f.lines[index]
    if not line then
        line = f:CreateTexture(nil, "BACKGROUND")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.lines[index] = line
    end
    line:ClearAllPoints()
    line:Show()
    return line
end

local function SetLineColor(line, r, g, b, a)
    if line.SetColorTexture then
        line:SetColorTexture(r, g, b, a)
    elseif line.SetVertexColor then
        line:SetVertexColor(r, g, b, a)
    end
end


local function AddUniqueFrame(list, seen, frame)
    if frame and not seen[frame] then
        seen[frame] = true
        list[#list + 1] = frame
    end
end

local function CollectElementFrames(info)
    local list, seen = {}, {}
    if not info then return list end

    AddUniqueFrame(list, seen, info.frame)

    if type(info.children) == "table" then
        for _, child in ipairs(info.children) do
            AddUniqueFrame(list, seen, child)
        end
    end

    if type(info.getChildren) == "function" then
        local ok, children = pcall(info.getChildren, info)
        if ok and type(children) == "table" then
            for _, child in ipairs(children) do
                AddUniqueFrame(list, seen, child)
            end
        end
    end

    return list
end

local function ElementAvailable(info)
    if not info or type(info.isAvailable) ~= "function" then return true end
    local ok, available = pcall(info.isAvailable, info)
    return ok and available ~= false
end

local function SetFrameMouse(frame, enabled)
    if not frame then return end
    if frame.EnableMouse then frame:EnableMouse(enabled) end
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(enabled) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(enabled) end
end

local function ReleaseInteractionState(info)
    if not info then return end

    if info._tfHiddenAlpha then
        for frame, alpha in pairs(info._tfHiddenAlpha) do
            if frame and frame.SetAlpha then frame:SetAlpha(alpha or 1) end
            info._tfHiddenAlpha[frame] = nil
        end
    end

    if info._tfMouseDisabled then
        for frame in pairs(info._tfMouseDisabled) do
            SetFrameMouse(frame, true)
            info._tfMouseDisabled[frame] = nil
        end
    end
end

local function ApplyInteractionState(id, info)
    if not id or not info then return end
    local edb = ElementDB(id)
    local hidden = edb.hidden == true
    local clickThrough = edb.clickThrough == true
    local frames = CollectElementFrames(info)

    info._tfHiddenAlpha = info._tfHiddenAlpha or {}
    info._tfMouseDisabled = info._tfMouseDisabled or {}

    if hidden then
        for _, frame in ipairs(frames) do
            if frame.SetAlpha then
                if info._tfHiddenAlpha[frame] == nil and frame.GetAlpha then
                    info._tfHiddenAlpha[frame] = frame:GetAlpha()
                end
                frame:SetAlpha(0)
            end
        end
    elseif info._tfHiddenAlpha then
        for frame, alpha in pairs(info._tfHiddenAlpha) do
            if frame and frame.SetAlpha then frame:SetAlpha(alpha or 1) end
            info._tfHiddenAlpha[frame] = nil
        end
    end

    local disableMouse = clickThrough or (hidden and info.hiddenVisualOnly ~= true)
    if disableMouse then
        for _, frame in ipairs(frames) do
            info._tfMouseDisabled[frame] = true
            SetFrameMouse(frame, false)
        end
    elseif info._tfMouseDisabled then
        for frame in pairs(info._tfMouseDisabled) do
            SetFrameMouse(frame, true)
            info._tfMouseDisabled[frame] = nil
        end
    end
end

function M:UpdateGrid()
    local db = DB()
    if db.enabled == false or db.locked ~= false or db.showGrid ~= true then
        if gridFrame then gridFrame:Hide() end
        return
    end

    local f = EnsureGridFrame()
    local w = (UIParent.GetWidth and UIParent:GetWidth()) or 0
    local h = (UIParent.GetHeight and UIParent:GetHeight()) or 0
    if w <= 0 or h <= 0 then f:Hide(); return end

    local spacing = tonumber(db.gridSize) or tonumber(db.snapSize) or 32
    if spacing < 4 then spacing = 4 end
    if spacing > 200 then spacing = 200 end

    local alpha = tonumber(db.gridAlpha) or 0.14
    if alpha < 0.04 then alpha = 0.04 end
    if alpha > 0.6 then alpha = 0.6 end

    local halfW = w / 2
    local halfH = h / 2
    local index = 1

    local minX = -math_floor(halfW / spacing) * spacing
    local maxX = math_floor(halfW / spacing) * spacing
    local x = minX
    while x <= maxX do
        local line = AcquireGridLine(index)
        index = index + 1
        line:SetSize(x == 0 and 2 or 1, h)
        line:SetPoint("CENTER", UIParent, "CENTER", x, 0)
        if x == 0 then
            SetLineColor(line, 0, 0.85, 1, math_min(alpha * 3, 0.75))
        else
            SetLineColor(line, 1, 1, 1, alpha)
        end
        x = x + spacing
    end

    local minY = -math_floor(halfH / spacing) * spacing
    local maxY = math_floor(halfH / spacing) * spacing
    local y = minY
    while y <= maxY do
        local line = AcquireGridLine(index)
        index = index + 1
        line:SetSize(w, y == 0 and 2 or 1)
        line:SetPoint("CENTER", UIParent, "CENTER", 0, y)
        if y == 0 then
            SetLineColor(line, 0, 0.85, 1, math_min(alpha * 3, 0.75))
        else
            SetLineColor(line, 1, 1, 1, alpha)
        end
        y = y + spacing
    end

    for i = index, #f.lines do
        f.lines[i]:Hide()
    end

    f:Show()
end

local function AuraRuntimeNeeded()
    local db = DB()
    if db.enabled == false or db.auraLayout == false then return false end
    return ElementDB("TargetBuffs").enabled ~= false or ElementDB("TargetDebuffs").enabled ~= false
end

local function EnsureEventFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_REGEN_ENABLED" then
                for id, info in pairs(elements) do
                    if info.pending then
                        info.pending = nil
                        M:ApplyElement(id)
                    end
                end
                M:RequestAuraUpdate()
            elseif event == "PLAYER_ENTERING_WORLD" then
                if M.RegisterSystemFrameMovers then M.RegisterSystemFrameMovers(M) end
                M:ApplyAll()
                M:RequestAuraUpdate()
            elseif event == "PLAYER_TARGET_CHANGED" then
                M:RequestAuraUpdate()
            elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "UPDATE_QUEST_WATCH" then
                if M._QueueQuestTrackerApply then M._QueueQuestTrackerApply(false) end
            elseif event == "UNIT_AURA" then
                if arg1 == "target" then M:RequestAuraUpdate() end
            end
        end)
    end
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if AuraRuntimeNeeded() then
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        if eventFrame.RegisterUnitEvent then
            eventFrame:RegisterUnitEvent("UNIT_AURA", "target")
        else
            eventFrame:RegisterEvent("UNIT_AURA")
        end
    end

    -- Quest tracker event names have varied between Classic-era FrameXML
    -- revisions. Register them only when that mover is actually enabled.
    if QUEST_TRACKER_MOVER_AVAILABLE and ElementDB("QuestTracker").enabled ~= false then
        local function SafeRegister(event)
            if eventFrame.RegisterEvent then pcall(eventFrame.RegisterEvent, eventFrame, event) end
        end
        SafeRegister("QUEST_LOG_UPDATE")
        SafeRegister("QUEST_WATCH_UPDATE")
        SafeRegister("UPDATE_QUEST_WATCH")
    end
    return eventFrame
end

local function EnsureAuraDriver()
    if auraDriver then return auraDriver end
    -- Token frame retained for mover-family compatibility; coalescing is done
    -- with a next-frame callback instead of a frame-rate OnUpdate gate.
    auraDriver = CreateFrame("Frame")
    auraDriver:Hide()
    return auraDriver
end

local function ScheduleAuraDriver()
    if auraDriverScheduled then return end
    auraDriverScheduled = true
    After(0, function()
        auraDriverScheduled = false
        if not M.active or not AuraRuntimeNeeded() or not needsAuraUpdate then return end
        needsAuraUpdate = false
        M:UpdateAuraLayout()
    end)
end

local function UpdateOverlayText(id, liveOverlay)
    local info = elements[id]
    local overlay = info and info.overlay
    if not overlay then return end

    if overlay.label then
        local edb = ElementDB(id)
        local status = ""
        if edb.hidden == true then status = status .. " |cffff5555Hidden|r" end
        if edb.clickThrough == true then status = status .. " |cffccccccClick-through|r" end
        overlay.label:SetText((info.label or id) .. status)
    end

    if not overlay.coord then return end
    local db = DB()
    if db.showCoordinates == false then
        overlay.coord:Hide()
        return
    end

    local x, y
    if liveOverlay then
        x, y = OverlayElementXY(id, overlay)
    else
        x, y = CurrentElementXY(id, info)
    end
    overlay.coord:SetText(string_format("X: %d   Y: %d", RoundTo(x or 0, 1), RoundTo(y or 0, 1)))
    overlay.coord:Show()
end

local function OverlayLabel(overlay, text)
    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", overlay, "CENTER", 0, 7)
    label:SetJustifyH("CENTER")
    label:SetTextColor(1, 1, 1)
    label:SetText(text)
    overlay.label = label

    local coord = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coord:SetPoint("CENTER", overlay, "CENTER", 0, -9)
    coord:SetJustifyH("CENTER")
    coord:SetTextColor(0, 0.85, 1)
    coord:SetText("X: 0   Y: 0")
    overlay.coord = coord
end

local function UpdatePrecisionPanelButtons(id, panel)
    if not panel then return end
    local edb = ElementDB(id)
    if panel.hideBtn then
        panel.hideBtn:SetText(edb.hidden == true and "Hide: On" or "Hide: Off")
    end
    if panel.clickBtn then
        panel.clickBtn:SetText(edb.clickThrough == true and "Click: Off" or "Click: On")
    end
end

local function EnsurePrecisionPanel(id, overlay)
    if overlay.precisionPanel then return overlay.precisionPanel end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local panel = CreateFrame("Frame", nil, overlay, template)
    panel:SetSize(136, 72)
    panel:SetPoint("TOP", overlay, "BOTTOM", 0, -3)
    panel:SetFrameLevel(overlay:GetFrameLevel() + 1)
    panel:EnableMouse(false)
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        panel:SetBackdropColor(0.02, 0.06, 0.08, 0.86)
        panel:SetBackdropBorderColor(0, 0.85, 1, 0.85)
    end

    local function MakeButton(text, x, y, w, h, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(w or 30, h or 16)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end

    MakeButton("Y+", 53, -4, 30, 16, function() M:NudgeElement(id, 0, 1) end)
    MakeButton("X-", 18, -22, 30, 16, function() M:NudgeElement(id, -1, 0) end)
    MakeButton("X+", 88, -22, 30, 16, function() M:NudgeElement(id, 1, 0) end)
    MakeButton("Y-", 53, -40, 30, 16, function() M:NudgeElement(id, 0, -1) end)

    panel.hideBtn = MakeButton("Hide: Off", 6, -56, 60, 14, function()
        local edb = ElementDB(id)
        M:SetElementHidden(id, edb.hidden ~= true)
    end)
    panel.clickBtn = MakeButton("Click: On", 70, -56, 60, 14, function()
        local edb = ElementDB(id)
        M:SetElementClickThrough(id, edb.clickThrough ~= true)
    end)

    panel:Hide()
    overlay.precisionPanel = panel
    UpdatePrecisionPanelButtons(id, panel)
    return panel
end

local function PositionPrecisionPanel(id, overlay, panel)
    if not overlay then return end
    panel = panel or overlay.precisionPanel
    if not panel then return end

    local _, y = OverlayElementXY(id, overlay)

    panel:ClearAllPoints()
    if (tonumber(y) or 0) < 0 then
        -- Lower-half / negative Y elements need their precision panel above
        -- the mover so the buttons do not cover the bar or fall off-screen.
        panel:SetPoint("BOTTOM", overlay, "TOP", 0, 3)
    else
        panel:SetPoint("TOP", overlay, "BOTTOM", 0, -3)
    end
end

local function ElementIsSelectable(id)
    if not id or not elements[id] then return false end
    if ElementDB(id).enabled == false then return false end
    return true
end

function M:GetActiveElement()
    local id = activeElementID or DB().activeElement
    if ElementIsSelectable(id) then
        activeElementID = id
        return id
    end
    return nil
end

local RefreshOverlayVisuals

function M:SetActiveElement(id, updateAll)
    if not ElementIsSelectable(id) then return end
    if activeElementID == id and DB().activeElement == id and updateAll ~= true then
        if updateAll == false and RefreshOverlayVisuals then RefreshOverlayVisuals() end
        return
    end
    activeElementID = id
    DB().activeElement = id
    if updateAll ~= false then
        self:UpdateOverlays()
    elseif RefreshOverlayVisuals then
        RefreshOverlayVisuals()
    end
end

local function UpdateOverlayVisual(id, overlay)
    if not overlay then return end
    local active = (M:GetActiveElement() == id)

    if overlay.SetBackdropColor then
        if active then
            overlay:SetBackdropColor(0, 0.75, 1, 0.28)
            overlay:SetBackdropBorderColor(1, 0.9, 0.15, 1)
        else
            overlay:SetBackdropColor(0, 0.75, 1, 0.18)
            overlay:SetBackdropBorderColor(0, 0.95, 1, 0.9)
        end
    end

    if overlay.precisionPanel then
        local db = DB()
        UpdatePrecisionPanelButtons(id, overlay.precisionPanel)
        PositionPrecisionPanel(id, overlay, overlay.precisionPanel)
        if db.enabled == false or db.locked ~= false or db.showNudgeControls == false or not active or ElementDB(id).enabled == false then
            overlay.precisionPanel:Hide()
        else
            overlay.precisionPanel:Show()
        end
    end
end

RefreshOverlayVisuals = function()
    for _, visualId in ipairs(order) do
        local info = elements[visualId]
        if info and info.overlay then
            UpdateOverlayVisual(visualId, info.overlay)
        end
    end
end

local function BeginOverlayDrag(id, overlay)
    local mx, my = CursorPositionFromCenter()
    local startX, startY = OverlayElementXY(id, overlay)
    overlay.turboFaceDragging = true
    overlay.turboFaceDragMouseX = mx
    overlay.turboFaceDragMouseY = my
    overlay.turboFaceDragStartX = startX or 0
    overlay.turboFaceDragStartY = startY or 0
    overlay.turboFaceDragCurrentX = startX or 0
    overlay.turboFaceDragCurrentY = startY or 0

    overlay:SetScript("OnUpdate", function(o)
        local cx, cy = CursorPositionFromCenter()
        local x = (o.turboFaceDragStartX or 0) + (cx - (o.turboFaceDragMouseX or cx))
        local y = (o.turboFaceDragStartY or 0) + (cy - (o.turboFaceDragMouseY or cy))
        o.turboFaceDragCurrentX = x
        o.turboFaceDragCurrentY = y
        o:ClearAllPoints()
        o:SetPoint("CENTER", UIParent, "CENTER", x, y)
        UpdateOverlayText(id, o)
        PositionPrecisionPanel(id, o, o.precisionPanel)
    end)
end

local function EndOverlayDrag(id, overlay)
    overlay:SetScript("OnUpdate", nil)
    if overlay.StopMovingOrSizing then overlay:StopMovingOrSizing() end
    SaveOverlayCenter(id, overlay)
    overlay.turboFaceDragging = nil
    overlay.turboFaceDragMouseX = nil
    overlay.turboFaceDragMouseY = nil
    overlay.turboFaceDragStartX = nil
    overlay.turboFaceDragStartY = nil
    overlay.turboFaceDragCurrentX = nil
    overlay.turboFaceDragCurrentY = nil
end

local function CreateOverlay(id, info)
    local parent = EnsureMoverParent()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local overlay = CreateFrame("Button", "TurboFaceMoverOverlay_" .. id, parent, template)
    overlay:SetMovable(true)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    if overlay.RegisterForClicks then overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(parent:GetFrameLevel() + 20)
    overlay:SetClampedToScreen(false)
    overlay:SetSize(info.overlayWidth or FrameWidth(info.frame, 120), info.overlayHeight or FrameHeight(info.frame, 32))

    if overlay.SetBackdrop then
        overlay:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        overlay:SetBackdropColor(0, 0.75, 1, 0.18)
        overlay:SetBackdropBorderColor(0, 0.95, 1, 0.9)
    end

    OverlayLabel(overlay, info.label or id)
    EnsurePrecisionPanel(id, overlay)
    UpdateOverlayText(id)

    overlay:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(info.label or id, 0, 0.8, 1)
            GameTooltip:AddLine("Click or drag to select this mover.", 1, 1, 1)
            GameTooltip:AddLine("Precision buttons only show on the selected mover.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Use X-/X+/Y-/Y+ for exact nudging; Shift uses snap size, Alt uses 10x.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Use Hide and Click buttons for selected-element visibility/click-through.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click to reset this mover.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Use /tf lock or /tfmove lock when done.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            M:SetActiveElement(id)
        end
    end)
    overlay:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            M:ResetElement(id)
        end
    end)
    overlay:SetScript("OnDragStart", function(self)
        if DB().locked or DB().enabled == false then return end
        M:SetActiveElement(id, false)
        BeginOverlayDrag(id, self)
    end)
    overlay:SetScript("OnDragStop", function(self)
        EndOverlayDrag(id, self)
        M:ApplyElement(id)
        M:UpdateOverlay(id)
        M:RequestAuraUpdate()
    end)

    overlay:Hide()
    info.overlay = overlay
    return overlay
end

function M:UpdateOverlay(id)
    local info = elements[id]
    if not info then return end
    local overlay = info.overlay or CreateOverlay(id, info)
    local db = DB()
    local edb = ElementDB(id)

    if db.enabled == false or db.locked ~= false or edb.enabled == false then
        if overlay.precisionPanel then overlay.precisionPanel:Hide() end
        overlay:Hide()
        return
    end

    -- Optional runtime availability lets a registered mover disappear while its
    -- owning feature is disabled without rewriting the user's mover preference.
    if not ElementAvailable(info) then
        if overlay.precisionPanel then overlay.precisionPanel:Hide() end
        overlay:Hide()
        return
    end

    -- Action bars, the micro menu, and bag buttons can refresh while mover mode
    -- is open. Do not let those refreshes re-anchor an overlay that the player is
    -- actively dragging, or the overlay feels like it is snapping/frictioning back
    -- toward the live bar every frame.
    if overlay.turboFaceDragging then
        overlay:Show()
        UpdateOverlayText(id, overlay)
        UpdateOverlayVisual(id, overlay)
        return
    end

    overlay:SetSize(info.overlayWidth or FrameWidth(info.frame, 120), info.overlayHeight or FrameHeight(info.frame, 32))
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", info.frame, "CENTER", 0, 0)
    UpdateOverlayText(id)
    overlay:Show()
    UpdateOverlayVisual(id, overlay)
end

function M:UpdateOverlays()
    if not moverParent then return end
    local db = DB()
    if db.enabled ~= false and db.locked == false then
        moverParent:Show()
    else
        moverParent:Hide()
    end

    self:UpdateGrid()

    for _, id in ipairs(order) do
        self:UpdateOverlay(id)
    end
    if RefreshOverlayVisuals then RefreshOverlayVisuals() end
end

local function ApplyDefaultPoint(info)
    if not info or not info.frame then return false end
    local p = info.defaultPoint or DefaultCenterPoint(info.frame)
    info.applying = true
    local ok = SafeClearAndSetPoint(info.frame, p[1], p[2], p[3], p[4], p[5])
    info.applying = false
    return ok
end

function M:ApplyElement(id)
    local info = elements[id]
    if not info or not info.frame then return end

    -- onApply callbacks may legitimately resize/reconfigure their owner and then
    -- call RegisterElement again (Hearthstone is one example). Treat registration
    -- during an apply as metadata invalidation, not as a nested apply. Without
    -- this full-lifecycle guard the same mover can recurse Apply -> onApply ->
    -- RegisterElement -> Apply until Classic's C stack overflows.
    if info.inApplyElement then
        info.overlayRefreshPending = true
        return
    end
    info.inApplyElement = true

    local db = DB()
    local edb = ElementDB(id)

    if db.enabled == false or edb.enabled == false then
        if info.overlay then info.overlay:Hide() end
        if info.onApply then pcall(info.onApply, info, edb, false) end
        info.inApplyElement = nil
        if info.overlayRefreshPending then
            info.overlayRefreshPending = nil
            self:UpdateOverlay(id)
        end
        return
    end

    -- Runtime-unavailable elements remain registered so their standalone mover
    -- preferences survive mode changes, but the mover must relinquish all live
    -- ownership. In particular, an embedded cast bar's SetPoint must not be
    -- overwritten by a saved standalone point on the next deferred reapply.
    if not ElementAvailable(info) then
        if info.overlay then info.overlay:Hide() end
        ReleaseInteractionState(info)
        info.inApplyElement = nil
        if info.overlayRefreshPending then
            info.overlayRefreshPending = nil
            self:UpdateOverlay(id)
        end
        return
    end

    if IsProtected(info.frame) and InCombatLockdown and InCombatLockdown() then
        info.pending = true
        info.inApplyElement = nil
        return
    end

    local point, rel, relPoint, x, y = SavedPoint(edb)
    info.applying = true
    if point then
        SafeClearAndSetPoint(info.frame, point, rel, relPoint, x, y)
    elseif info.defaultPoint then
        SafeClearAndSetPoint(info.frame, info.defaultPoint[1], info.defaultPoint[2], info.defaultPoint[3], info.defaultPoint[4], info.defaultPoint[5])
    elseif info.fallbackPoint then
        SafeClearAndSetPoint(info.frame, info.fallbackPoint[1], info.fallbackPoint[2], info.fallbackPoint[3], info.fallbackPoint[4], info.fallbackPoint[5])
    end
    info.applying = false
    ApplyInteractionState(id, info)
    if info.onApply then pcall(info.onApply, info, edb, true) end

    info.inApplyElement = nil
    if info.overlayRefreshPending then
        info.overlayRefreshPending = nil
        self:UpdateOverlay(id)
    end
end

function M:ApplyAll()
    for _, id in ipairs(order) do
        self:ApplyElement(id)
    end
    self:UpdateAuraLayout()
    self:UpdateOverlays()
end

function M:RegisterElement(id, frame, opts)
    if not id or not frame or DB().enabled == false then return end
    local edb = ElementDB(id)
    if edb.enabled == false then
        local existing = elements[id]
        if existing then
            if existing.inApplyElement then
                existing.overlayRefreshPending = true
                return
            end
            self:ApplyElement(id)
            self:UpdateOverlay(id)
        end
        return
    end
    opts = opts or {}

    local info = elements[id]
    if not info then
        info = { id = id }
        elements[id] = info
        tinsert(order, id)
    end

    info.frame = frame
    info.label = opts.label or id
    info.overlayWidth = opts.overlayWidth
    info.overlayHeight = opts.overlayHeight
    info.fallbackPoint = opts.fallbackPoint
    info.defaultPoint = opts.defaultPoint or info.defaultPoint or CapturePoint(frame) or opts.fallbackPoint
    info.children = opts.children or info.children
    info.getChildren = opts.getChildren or info.getChildren
    info.hiddenVisualOnly = opts.hiddenVisualOnly == true or info.hiddenVisualOnly == true
    info.onApply = opts.onApply or info.onApply
    info.isAvailable = opts.isAvailable or info.isAvailable

    if not info.overlay then CreateOverlay(id, info) end

    if not info.hooked then
        info.hooked = true
        if hooksecurefunc then
            -- One reusable callback per element + a pending flag, so a frame
            -- being repositioned repeatedly doesn't allocate a closure per
            -- SetPoint call or queue duplicate After(0) timers.
            info.reapplyFn = info.reapplyFn or function()
                info.reapplyPending = nil
                if info.applying then return end
                M:ApplyElement(id)
                M:UpdateOverlay(id)
            end
            hooksecurefunc(frame, "SetPoint", function()
                if info.applying or info.reapplyPending or not M.active then return end
                if not ElementAvailable(info) then return end
                local edb = ElementDB(id)
                if not edb.point or edb.enabled == false or DB().enabled == false then return end
                info.reapplyPending = true
                After(0, info.reapplyFn)
            end)
        end
    end

    -- If the owner re-registers itself from its own onApply callback, all
    -- metadata above is now current. Defer visual refresh to the outer apply
    -- instead of recursively applying the same element.
    if info.inApplyElement then
        info.overlayRefreshPending = true
        return
    end

    self:ApplyElement(id)
    self:UpdateOverlay(id)
end

function M:Refresh()
    local db = DB()
    if db.enabled == false then
        M.active = false
        if eventFrame then eventFrame:UnregisterAllEvents() end
        if auraDriver then auraDriver:Hide() end
        if moverParent then moverParent:Hide() end
        if gridFrame then gridFrame:Hide() end
        self:UpdateOverlays()
        if self.RefreshDependents then self:RefreshDependents() end
        return
    end

    if not M.initialized then
        self:Init()
        if self.RefreshDependents then self:RefreshDependents() end
        return
    end

    M.active = true
    EnsureEventFrame()
    if AuraRuntimeNeeded() then EnsureAuraDriver() elseif auraDriver then auraDriver:Hide() end
    if moverParent then moverParent:Show() end
    if M._RegisterAuraMovers then M._RegisterAuraMovers(self) end
    if M._RegisterToTMover then M._RegisterToTMover(self) end
    if M.RegisterSystemFrameMovers then M.RegisterSystemFrameMovers(self) end
    if M._HookAuraUpdates then M._HookAuraUpdates(self) end
    self:ApplyAll()
    self:RequestAuraUpdate()
    if self.RefreshDependents then self:RefreshDependents() end
end

function M:Unlock()
    local db = DB()
    db.enabled = true
    db.locked = false
    if not M.initialized or not M.active then self:Refresh() end
    self:ApplyAll()
    Chat("movers unlocked. Click or drag a cyan box to select it; only that mover shows the nudge buttons.")
end

function M:Lock()
    DB().locked = true
    self:UpdateOverlays()
    Chat("movers locked.")
end

function M:ToggleLock()
    if DB().locked == false then
        self:Lock()
    else
        self:Unlock()
    end
end

-- Read-only companion to SetElementHidden so other modules can offer their own
-- hide/show affordance without reaching into the Movers element DB.
function M:IsElementHidden(id)
    if not id or not elements[id] then return false end
    return ElementDB(id).hidden == true
end

function M:SetElementHidden(id, hidden)
    local info = elements[id]
    if not info then return end
    local edb = ElementDB(id)
    edb.hidden = hidden == true
    self:SetActiveElement(id, false)
    self:ApplyElement(id)
    self:UpdateOverlay(id)
    self:RequestAuraUpdate()
    if RefreshOverlayVisuals then RefreshOverlayVisuals() end
end

function M:SetElementClickThrough(id, clickThrough)
    local info = elements[id]
    if not info then return end
    local edb = ElementDB(id)
    edb.clickThrough = clickThrough == true
    self:SetActiveElement(id, false)
    self:ApplyElement(id)
    self:UpdateOverlay(id)
    self:RequestAuraUpdate()
    if RefreshOverlayVisuals then RefreshOverlayVisuals() end
end

function M:ResetElement(id)
    local info = elements[id]
    if not info then return end
    self:SetActiveElement(id, false)
    ClearSavedPoint(ElementDB(id))
    if IsProtected(info.frame) and InCombatLockdown and InCombatLockdown() then
        info.pending = true
        Chat((info.label or id) .. " reset queued until combat ends.")
    else
        ApplyDefaultPoint(info)
        ApplyInteractionState(id, info)
        if info.onApply then pcall(info.onApply, info, ElementDB(id), true) end
        self:RequestAuraUpdate()
        Chat((info.label or id) .. " reset.")
    end
    self:UpdateOverlay(id)
end

function M:ResetAll()
    for id in pairs(elements) do
        ClearSavedPoint(ElementDB(id))
    end
    activeElementID = nil
    DB().activeElement = nil
    self:ApplyAll()
    if RefreshOverlayVisuals then RefreshOverlayVisuals() end
    Chat("all mover positions reset.")
end

function M:NudgeElement(id, dx, dy)
    local info = elements[id]
    if not info or not info.frame then return end
    self:SetActiveElement(id, false)

    local x, y = CurrentElementXY(id, info)
    local step = NudgeStep()
    x = (x or 0) + ((tonumber(dx) or 0) * step)
    y = (y or 0) + ((tonumber(dy) or 0) * step)
    SaveElementXY(id, x, y, false)

    if IsProtected(info.frame) and InCombatLockdown and InCombatLockdown() then
        info.pending = true
    else
        self:ApplyElement(id)
    end
    self:UpdateOverlay(id)
    self:RequestAuraUpdate()
end

function M:RequestAuraUpdate(immediate)
    if not AuraRuntimeNeeded() then
        needsAuraUpdate = false
        if auraDriver then auraDriver:Hide() end
        return
    end
    needsAuraUpdate = true

    -- BuffFrame_UpdateAllBuffAnchors and TargetFrame_UpdateAuras can briefly
    -- put Blizzard aura buttons back at their stock anchors.  When the caller
    -- is a post-hook from those functions, re-layout immediately in the same
    -- frame so the old position never has a rendered frame to flicker.  Keep a
    -- tiny delayed pass as a safety net for buttons Blizzard creates/shows
    -- just after the hook returns.
    if immediate == true and M.active then
        self:UpdateAuraLayout()
        if not auraDelayedQueued then
            auraDelayedQueued = true
            After(0, function()
                auraDelayedQueued = false
                if M.active then self:UpdateAuraLayout() end
            end)
        end
        needsAuraUpdate = false
        return
    end

    EnsureAuraDriver()
    ScheduleAuraDriver()
end


-- =============================================================================
-- Shared internals for MoverNameplates/Auras.lua / Movers/Systems.lua (loaded after us).
-- Underscore-prefixed = internal to the mover family; not a public API.
-- =============================================================================
M._elements = elements
M._DB = DB
M._ElementDB = ElementDB
M._AuraDB = AuraDB
M._Chat = Chat
M._IsProtected = IsProtected
M._FrameWidth = FrameWidth
M._FrameHeight = FrameHeight
M._EnsureMoverParent = EnsureMoverParent
M._ApplyInteractionState = ApplyInteractionState
M._CapturePoint = CapturePoint
M._EnsureAuraDriver = EnsureAuraDriver
M._AuraRuntimeNeeded = AuraRuntimeNeeded
M._PointFromCenter = PointFromCenter
M._AddUniqueFrame = AddUniqueFrame
M._EnsureEventFrame = EnsureEventFrame
M._order = order
