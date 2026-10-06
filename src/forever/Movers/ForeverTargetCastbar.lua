local _, ns = ...

-- Forever keeps target-cast state and rendering inside Blizzard's native
-- TargetFrameSpellBar. This adapter owns position only: a normal TurboFace
-- mover moves an addon-owned anchor, and the native bar is attached to that
-- anchor without reading cast data or replacing any of Blizzard's regions.

local M = ns.Movers
local compat = ns.Compat
if not (M and compat and compat.IS_TARGET_FOREVER_BUILD == true
    and ns.FeatureAvailable("movers.nativeTargetCastbar", false)) then
    return
end

local API = ns.API
local After = ns.After
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc

local ELEMENT_ID = "NativeTargetCastBar"
local FALLBACK_POINT = { "CENTER", UIParent, "CENTER", 0, -200 }

local anchor
local nativeFrame
local stockPoint
local hookedFrames = setmetatable({}, { __mode = "k" })
local globalHooked = false
local applying = false
local queued = false
local pendingAction
local lastError
local eventFrame

local function Field(owner, key)
    local ok, value = pcall(function() return owner and owner[key] end)
    return ok and value or nil
end

local function ResolveNativeFrame()
    local target = _G.TargetFrame
    local frame = _G.TargetFrameSpellBar
        or Field(target, "spellbar")
        or Field(target, "SpellBar")
        or Field(target, "castBar")
        or Field(target, "CastBar")
    if frame then nativeFrame = frame end
    return frame or nativeFrame
end

local function SafeFrameName(frame)
    if not frame or type(frame.GetName) ~= "function" then return "nil" end
    local ok, name = pcall(frame.GetName, frame)
    return ok and name or "unreadable"
end

local function FrameIsProtected(frame)
    if not frame or type(frame.IsProtected) ~= "function" then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected == true
end

local function SafeCapturePoint(frame)
    if not frame or type(frame.GetPoint) ~= "function" then return nil end
    local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok or type(point) ~= "string" then return nil end
    return { point, relative or UIParent, relativePoint or point, x or 0, y or 0 }
end

local function SafeCenterPoint(frame)
    local pointFromCenter = M._PointFromCenter
    if type(pointFromCenter) ~= "function" then return nil end
    local ok, point = pcall(pointFromCenter, frame)
    return ok and type(point) == "table" and point or nil
end

local function EnsureAnchor()
    if anchor then return anchor end
    anchor = M._EnsureAnchor("TurboFaceNativeTargetCastbarMoverAnchor", 150, 16)
    anchor:EnableMouse(false)
    anchor:Show()
    return anchor
end

local function OwnsPosition()
    if not M.active then return false end
    local db = M._DB()
    local edb = M._ElementDB(ELEMENT_ID)
    return db.enabled ~= false and edb.enabled ~= false
end

local function NativeWriteBlocked(frame)
    return InCombatLockdown and InCombatLockdown() and FrameIsProtected(frame)
end

local function RememberError(err)
    if API and API.SafeToString then lastError = API.SafeToString(err)
    else lastError = tostring(err) end
end

local function SafeValue(value)
    if API and API.SafeToString then return API.SafeToString(value) end
    local ok, text = pcall(tostring, value)
    return ok and text or "unreadable"
end

local function RestoreNativePosition(frame)
    frame = frame or ResolveNativeFrame()
    if not frame then return false end
    if NativeWriteBlocked(frame) then
        pendingAction = "restore"
        return false
    end

    applying = true
    local ok, err
    if type(_G.Target_Spellbar_AdjustPosition) == "function" then
        ok, err = pcall(_G.Target_Spellbar_AdjustPosition, frame)
    elseif stockPoint then
        ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(stockPoint[1], stockPoint[2], stockPoint[3], stockPoint[4], stockPoint[5])
        end)
    else
        ok = false
        err = "no native layout function or captured stock point"
    end
    applying = false

    if not ok then
        RememberError(err)
        pendingAction = "restore"
        return false
    end
    pendingAction = nil
    lastError = nil
    return true
end

local function ApplyNativePosition()
    local frame = ResolveNativeFrame()
    local moverAnchor = EnsureAnchor()
    if not frame or not moverAnchor then return false end
    if not OwnsPosition() then return RestoreNativePosition(frame) end
    if NativeWriteBlocked(frame) then
        pendingAction = "apply"
        return false
    end

    applying = true
    local ok, err = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", moverAnchor, "CENTER", 0, 0)
    end)
    applying = false

    if not ok then
        RememberError(err)
        pendingAction = "apply"
        return false
    end
    pendingAction = nil
    lastError = nil
    return true
end

local function QueueApply()
    if queued then return end
    queued = true
    After(0, function()
        queued = false
        if OwnsPosition() then ApplyNativePosition() end
    end)
end

local function HookNativeFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true

    -- Blizzard recomputes this anchor on cast show, target classification,
    -- target-of-target visibility and aura layout. Reapply after that native
    -- pass instead of replacing any castbar scripts or state.
    if hooksecurefunc and type(frame.SetPoint) == "function" then
        hooksecurefunc(frame, "SetPoint", function()
            if applying or not OwnsPosition() then return end
            QueueApply()
        end)
    end
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            if OwnsPosition() then QueueApply() end
        end)
    end
end

local function InstallGlobalHook()
    if globalHooked or not hooksecurefunc
        or type(_G.Target_Spellbar_AdjustPosition) ~= "function" then
        return
    end
    globalHooked = true
    hooksecurefunc("Target_Spellbar_AdjustPosition", function(frame)
        if applying or frame ~= ResolveNativeFrame() or not OwnsPosition() then return end
        QueueApply()
    end)
end

local function EnsureEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            After(0, function()
                if M.active and M.RegisterNativeTargetCastbarMover then
                    M:RegisterNativeTargetCastbarMover()
                end
            end)
        elseif pendingAction == "restore" or not OwnsPosition() then
            RestoreNativePosition()
        else
            ApplyNativePosition()
        end
    end)
end

function M:RegisterNativeTargetCastbarMover()
    local frame = ResolveNativeFrame()
    if not frame then return end

    stockPoint = stockPoint or SafeCapturePoint(frame)
    local defaultPoint = SafeCenterPoint(frame) or FALLBACK_POINT
    local existing = self._elements[ELEMENT_ID]
    if existing and existing.defaultPoint then defaultPoint = existing.defaultPoint end

    HookNativeFrame(frame)
    InstallGlobalHook()
    EnsureEvents()

    self:RegisterElement(ELEMENT_ID, EnsureAnchor(), {
        label = "Target Unit Cast Bar",
        overlayWidth = 160,
        overlayHeight = 24,
        fallbackPoint = FALLBACK_POINT,
        defaultPoint = defaultPoint,
        positionOnly = true,
        onApply = function(_, _, enabled)
            if enabled then ApplyNativePosition() else RestoreNativePosition() end
        end,
    })
end

function M:ReleaseNativeTargetCastbarMover()
    RestoreNativePosition()
end

function M:NativeTargetCastbarProbe()
    local frame = ResolveNativeFrame()
    local point = SafeCapturePoint(frame)
    local relativeName = point and SafeFrameName(point[2]) or "nil"
    local p = point and point[1] or "nil"
    local rp = point and point[3] or "nil"
    local x = point and point[4] or "nil"
    local y = point and point[5] or "nil"
    ns:Chat("Movers", ("native target castbar: frame=%s protected=%s owns=%s pending=%s point=%s relative=%s relativePoint=%s x=%s y=%s error=%s"):format(
        SafeFrameName(frame), SafeValue(FrameIsProtected(frame)), SafeValue(OwnsPosition()),
        SafeValue(pendingAction), SafeValue(p), SafeValue(relativeName), SafeValue(rp),
        SafeValue(x), SafeValue(y), SafeValue(lastError)))
end
