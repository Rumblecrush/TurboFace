local _, ns = ...

-- =============================================================================
-- TurboFace MapTweaks.lua — windowed world map movement and zoom.
--
-- Scope is deliberately narrow: restore the windowed map drag that Blizzard
-- ships broken, and add cursor-centred wheel zoom with optional extra zoom
-- levels. The map keeps Blizzard's border, title bar, maximise button and
-- UIPanel registration.
--
-- The map deliberately remains a normal Blizzard UIPanel: TurboFace does not
-- replace its border, title bar, maximise button, panel registration or base
-- layout. Only movement and zoom behavior are augmented.
--
-- Why the drag is broken on 1.15.9: Blizzard_WorldMap/Vanilla ships the title
-- dropdown with Lock and Reset entries, but never calls SetMovable on the
-- frame. WorldMapTitleDropdown_Reset therefore throws
--     WorldMapFrame:SetUserPlaced(): Frame is not movable or resizable
-- and the title-bar drag does nothing. SetMovable(true) clears the error but
-- not the drag, because the title bar has no working drag scripts to re-arm.
-- TurboFace therefore installs its own drag and owns the saved position, since
-- Blizzard's
-- SetUserPlaced persistence is the broken path.
--
-- Application model: RELOAD-APPLIED. Every feature installs its hooks once at
-- Init when its option is enabled, matching Interface/Chat/System (§20.3).
-- The zoom-maximum slider re-applies live.
--
-- No events, no CLEU consumer, no ns.Cadence client, no OnUpdate driver. With
-- the Map section off, Init returns before installing anything (§1.4).
-- =============================================================================

local M = {}
ns.PlusMap = M

local initialized = false
local movableApplied = false
local zoomApplied = false
local rememberApplied = false
local dragHandleKind = "none"

-- Forever 1.60.1.69913 uses the Mainline MapCanvas pin pool.  Any addon hook
-- on ScrollContainer's zoom/mouse-wheel path can taint that canvas and later
-- make Blizzard's quest data provider reach the protected
-- Button:SetPassThroughButtons() call from addon-tainted execution.  Keep the
-- entire native canvas -- methods, scripts, fields, providers, pools and pins --
-- Blizzard-owned on this build.  The top-level windowed-map drag is separate
-- and remains available because it never touches ScrollContainer.
local function NativeMapCanvasOwned()
    return ns.PlusProviderOwnsNativeMapCanvas and ns.PlusProviderOwnsNativeMapCanvas() or false
end

local function WorldMapID()
    if not WorldMapFrame then return end
    if type(WorldMapFrame.GetMapID) == "function" then
        local ok, mapID = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and mapID then return mapID end
    end
    return WorldMapFrame.mapID
end

local function ResolveDragHandle()
    local border = WorldMapFrame and WorldMapFrame.BorderFrame
    local modern = border and border.TitleContainer
    if modern and type(modern.RegisterForDrag) == "function" then
        return modern, "BorderFrame.TitleContainer"
    end
    if WorldMapTitleButton and type(WorldMapTitleButton.RegisterForDrag) == "function" then
        return WorldMapTitleButton, "WorldMapTitleButton"
    end
    if MiniWorldMapTitle and type(MiniWorldMapTitle.RegisterForDrag) == "function" then
        return MiniWorldMapTitle, "MiniWorldMapTitle"
    end
end

local function P()
    -- Per-section gated view of TurboFaceDB.plus: keys belonging to a disabled
    -- section read as nil, so each feature takes its own disabled branch.
    return ns.PlusSettings()
end

-- Blizzard's zoom mixin methods mutate canvas state that FrameXML reads back.
-- §1.3 forbids invoking a FrameXML function directly, so the unavoidable calls
-- go through securecall and our taint stops at the boundary.
local function SecureCanvas(container, method, ...)
    local fn = container and container[method]
    if type(fn) ~= "function" then return end
    if type(securecall) == "function" then
        securecall(fn, container, ...)
    else
        pcall(fn, container, ...)
    end
end

-- The modern MapCanvas normalized-scroll helpers divide by the canvas child's
-- width/height. During early login Blizzard_WorldMap can be loaded while those
-- dimensions are still zero, so merely having WorldMapFrame/ScrollContainer is
-- not enough to make canvas math safe. Keep all TurboFace reads/restores behind
-- one readiness check instead of probing FrameXML methods optimistically.
local function CanvasReady(container, requireZoomLevels)
    if not container or not container.Child then return false end

    local mapID = tonumber(container.mapID)
    if not mapID or mapID <= 0 then return false end

    local width, height = container:GetSize()
    local childWidth, childHeight = container.Child:GetSize()
    if type(width) ~= "number" or type(height) ~= "number"
        or type(childWidth) ~= "number" or type(childHeight) ~= "number"
        or width <= 0 or height <= 0 or childWidth <= 0 or childHeight <= 0 then
        return false
    end

    if requireZoomLevels then
        if type(container.zoomLevels) ~= "table" or not container.zoomLevels[1] then
            return false
        end
    end

    if type(container.GetCanvasScale) == "function" then
        local ok, scale = pcall(container.GetCanvasScale, container)
        if not ok or type(scale) ~= "number" or scale <= 0 then return false end
    end

    return true
end

local function ReadCanvasView(container)
    if not CanvasReady(container, true) then return end
    if type(container.GetCanvasScale) ~= "function"
        or type(container.GetNormalizedHorizontalScroll) ~= "function"
        or type(container.GetNormalizedVerticalScroll) ~= "function" then return end

    local okScale, scale = pcall(container.GetCanvasScale, container)
    local okX, horizontal = pcall(container.GetNormalizedHorizontalScroll, container)
    local okY, vertical = pcall(container.GetNormalizedVerticalScroll, container)
    if not okScale or not okX or not okY then return end
    if type(scale) ~= "number" or scale <= 0
        or type(horizontal) ~= "number" or type(vertical) ~= "number" then return end

    return scale, horizontal, vertical, tonumber(container.mapID)
end

-- =============================================================================
-- Movable windowed map
--
-- Blizzard ships the Vanilla title dropdown with Lock and Reset entries but
-- never makes the frame movable, so the drag does nothing and
-- WorldMapTitleDropdown_Reset throws on SetUserPlaced. SetMovable(true) fixes
-- the error but not the drag: the title bar has no working drag scripts to
-- re-arm. TurboFace installs a minimal drag handler without replacing the stock
-- map panel.
--
-- Because Blizzard's SetUserPlaced persistence is the broken path, TurboFace
-- has to own the saved position. It lives in a nested TurboFaceDB.map block
-- with its own DB() accessor (§9.1), not in the flat plus table: the Plus
-- settings proxy is read-only (§6.2) and this is runtime-written state.
-- Fullscreen is never touched; Blizzard keeps its own layout there.
-- =============================================================================

local function MapDB()
    if not TurboFaceDB then TurboFaceDB = {} end
    if type(TurboFaceDB.map) ~= "table" then TurboFaceDB.map = {} end
    return TurboFaceDB.map
end

local function SavePosition()
    if WorldMapFrame:IsMaximized() then return end
    local point, _, relPoint, x, y = WorldMapFrame:GetPoint()
    if not point then return end
    local db = MapDB()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function RestorePosition()
    if not P().mapMovable then return end
    if WorldMapFrame:IsMaximized() then return end
    local db = MapDB()
    if not db.point then return end
    WorldMapFrame:ClearAllPoints()
    WorldMapFrame:SetPoint(db.point, UIParent, db.relPoint, db.x or 0, db.y or 0)
end

-- Attach drag to an existing Blizzard title widget when there is one, so its
-- right-click dropdown keeps working. HookScript is safe whether or not a
-- script is already installed.
local function InstallDrag(frame)
    if frame._tfMapDragHooked then return end
    frame._tfMapDragHooked = true
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:HookScript("OnDragStart", function()
        if not P().mapMovable or WorldMapFrame:IsMaximized() then return end
        WorldMapFrame:StartMoving()
    end)
    frame:HookScript("OnDragStop", function()
        if not P().mapMovable then return end
        WorldMapFrame:StopMovingOrSizing()
        -- We persist the point ourselves, so keep the frame out of Blizzard's
        -- layout cache rather than letting two owners write the position.
        if WorldMapFrame:IsMovable() then WorldMapFrame:SetUserPlaced(false) end
        SavePosition()
    end)
end

local function ApplyMovable()
    if not P().mapMovable then return end
    if not WorldMapFrame or not WorldMapFrame.SetMovable then return end

    WorldMapFrame:SetMovable(true)
    -- Without this a mis-drag can strand the map off-screen with no reset.
    WorldMapFrame:SetClampedToScreen(true)

    local title, titleKind = ResolveDragHandle()
    if title then
        dragHandleKind = titleKind
        InstallDrag(title)
    else
        -- No usable Blizzard title widget: lay a drag strip across the top of
        -- the frame, inset on the right so the close and maximise buttons stay
        -- clickable. Presentation is untouched -- the strip has no texture.
        local handle = CreateFrame("Frame", nil, WorldMapFrame)
        handle:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 0)
        handle:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -60, 0)
        handle:SetHeight(24)
        handle:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 2)
        dragHandleKind = "TurboFace fallback"
        InstallDrag(handle)
    end
    movableApplied = true

    -- The map stays registered with UIPanelWindows (your call to keep default
    -- panel behaviour), so the panel manager re-anchors it on show. Re-apply
    -- after it, not instead of it.
    RestorePosition()
    WorldMapFrame:HookScript("OnShow", function()
        if not P().mapMovable then return end
        local NextFrame = RunNextFrame or function(fn) C_Timer.After(0, fn) end
        NextFrame(RestorePosition)
    end)
    -- On Forever do not post-hook a native map lifecycle method.  The deferred
    -- OnShow restore above is sufficient and keeps the MapCanvas call graph
    -- free of TurboFace callbacks.
    if not NativeMapCanvasOwned()
        and type(WorldMapFrame.SynchronizeDisplayState) == "function" then
        hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", RestorePosition)
    end
end

-- Put the map back at Blizzard's default spot. Exposed for the Options button
-- because the stock right-click Reset entry is the path that throws.
function M:ResetPosition()
    local db = MapDB()
    db.point, db.relPoint, db.x, db.y = nil, nil, nil, nil
    if WorldMapFrame and WorldMapScreenAnchor then
        WorldMapScreenAnchor:ClearAllPoints()
        WorldMapScreenAnchor:SetPoint("TOPLEFT", nil, "TOPLEFT", 16, -104)
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -104)
    elseif WorldMapFrame and WorldMapFrame.IsMovable and WorldMapFrame:IsMovable() then
        -- Modern WorldMapFrame layouts no longer expose WorldMapScreenAnchor.
        -- Clearing our saved point is still sufficient for the next Blizzard
        -- layout pass; opt out of user-placement persistence so Blizzard owns it.
        WorldMapFrame:SetUserPlaced(false)
    end
end

-- =============================================================================
-- Cursor-centred wheel zoom, and optional extra zoom levels
-- =============================================================================

local function ApplyZoom()
    if NativeMapCanvasOwned() then return end
    if not P().mapEnhancedZoom then return end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not container then return end
    if zoomApplied then return end
    zoomApplied = true

    -- Blizzard's own OnMouseWheel runs first and zooms about the canvas
    -- centre; this re-targets the same step at the cursor. Both handlers agree
    -- on the destination scale, so the visible result is one zoom step.
    container:HookScript("OnMouseWheel", function(self, delta)
        if not P().mapEnhancedZoom or not CanvasReady(self, true) then return end
        if type(self.GetNormalizedCursorPosition) ~= "function"
            or type(self.GetCurrentZoomRange) ~= "function"
            or type(self.GetCanvasScale) ~= "function" then return end
        local x, y = self:GetNormalizedCursorPosition()
        if not x or not y then return end
        local zoomOutScale, zoomInScale = self:GetCurrentZoomRange()
        local current = self:GetCanvasScale()
        if delta == 1 then
            if zoomInScale and zoomInScale > current then
                SecureCanvas(self, "InstantPanAndZoom", zoomInScale, x, y)
            end
        elseif zoomOutScale and zoomOutScale < current then
            SecureCanvas(self, "InstantPanAndZoom", zoomOutScale, x, y)
        end
    end)

    -- Rebuild the zoom ladder with a higher ceiling. Predicate-gated because
    -- hooksecurefunc cannot be removed (§7.5): with the option later turned
    -- off the callback returns immediately and Blizzard's own levels stand.
    if type(container.CreateZoomLevels) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    hooksecurefunc(container, "CreateZoomLevels", function(self)
        if not P().mapEnhancedZoom then return end
        local maxScale = tonumber(P().mapZoomMax) or 2
        if maxScale <= 1 then return end
        local mapID = self.mapID or WorldMapID()
        if not (C_Map and C_Map.GetMapArtLayers and mapID) then return end
        local okLayers, layers = pcall(C_Map.GetMapArtLayers, mapID)
        if not okLayers or type(layers) ~= "table" or not layers[1] then return end

        -- GetMapArtLayers returns a fresh table per call, so scaling
        -- layerInfo.maxScale below mutates a copy, not Blizzard's cache.
        local layerWidth = tonumber(layers[1].layerWidth)
        local layerHeight = tonumber(layers[1].layerHeight)
        local frameWidth, frameHeight = self:GetSize()
        if not layerWidth or not layerHeight or layerWidth <= 0 or layerHeight <= 0
            or type(frameWidth) ~= "number" or type(frameHeight) ~= "number"
            or frameWidth <= 0 or frameHeight <= 0 then return end
        local widthScale = frameWidth / layerWidth
        local heightScale = frameHeight / layerHeight
        self.baseScale = math.min(widthScale, heightScale)

        local MIN_SCALE_DELTA = 0.01
        local currentScale = 0
        self.zoomLevels = {}
        for layerIndex, layerInfo in ipairs(layers) do
            local layerMin = tonumber(layerInfo.minScale)
            local layerMax = tonumber(layerInfo.maxScale)
            local additionalSteps = tonumber(layerInfo.additionalZoomSteps) or 0
            if not layerMin or not layerMax then return end
            layerInfo.maxScale = layerMax * maxScale
            layerInfo.minScale = layerMin
            local zoomDelta = layerInfo.maxScale - layerInfo.minScale
            local numZoomLevels, zoomDeltaPerStep
            if zoomDelta > 0 then
                numZoomLevels = 2 + additionalSteps * maxScale
                zoomDeltaPerStep = zoomDelta / (numZoomLevels - 1)
            else
                numZoomLevels = 1
                zoomDeltaPerStep = 1
            end
            for zoomLevelIndex = 0, numZoomLevels - 1 do
                currentScale = math.max(
                    layerInfo.minScale + zoomDeltaPerStep * zoomLevelIndex,
                    currentScale + MIN_SCALE_DELTA)
                table.insert(self.zoomLevels,
                    { scale = currentScale * self.baseScale, layerIndex = layerIndex })
            end
        end
    end)
end

-- =============================================================================
-- Remember zoom and pan across map close/open
-- =============================================================================

local function ApplyRememberZoom()
    if NativeMapCanvasOwned() then return end
    if not P().mapRememberZoom then return end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not container then return end
    if rememberApplied then return end
    if type(container.GetCanvasScale) ~= "function"
        or type(container.GetNormalizedHorizontalScroll) ~= "function"
        or type(container.GetNormalizedVerticalScroll) ~= "function" then return end
    rememberApplied = true

    local NextFrame = RunNextFrame or function(fn) C_Timer.After(0, fn) end
    local lastScale, lastHorizontal, lastVertical, lastMapID

    local function CaptureView()
        local scale, horizontal, vertical, mapID = ReadCanvasView(container)
        if not scale then return false end
        lastScale, lastHorizontal, lastVertical, lastMapID = scale, horizontal, vertical, mapID
        return true
    end

    -- Never sample normalized scroll during Init. On modern/Forever MapCanvas the
    -- child can legitimately be 0x0 until Blizzard assigns a map and canvas art;
    -- the normalized getters divide by those dimensions. Capture only after the
    -- map has actually been initialized and shown.
    WorldMapFrame:HookScript("OnHide", function()
        if not P().mapRememberZoom then return end
        CaptureView()
    end)

    WorldMapFrame:HookScript("OnShow", function()
        if not P().mapRememberZoom then return end
        if not lastScale or not lastMapID then return end

        -- Blizzard establishes the map ID, zoom ladder, child dimensions, and its
        -- default ResetZoom from OnShow. Restore one frame later only if that full
        -- canvas state is usable and the player reopened the same map.
        NextFrame(function()
            if not P().mapRememberZoom or not CanvasReady(container, true) then return end
            if tonumber(container.mapID) ~= lastMapID then return end
            SecureCanvas(container, "InstantPanAndZoom", lastScale, lastHorizontal, lastVertical)
            SecureCanvas(container, "SetPanTarget", lastHorizontal, lastVertical)
        end)
    end)
end

-- =============================================================================
-- Refresh / init
-- =============================================================================

-- Live-appliable part: the zoom ceiling. Rebuilding the ladder needs
-- CreateZoomLevels to run again, which is a FrameXML method, hence securecall
-- (§1.3). Everything else installs once at Init and is flagged reload-required.
function M:Refresh()
    if NativeMapCanvasOwned() then return end
    if not P().mapEnhancedZoom then return end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not container or not WorldMapFrame:IsShown() then return end

    -- Forever's current MapCanvas CreateZoomLevels() reads self.mapID directly
    -- and immediately feeds it to C_Map.GetMapArtLayers(). WorldMapFrame may
    -- already report a map while the ScrollContainer has not inherited that ID
    -- yet, so using WorldMapID() as a guard is not sufficient and can crash the
    -- Blizzard mixin with GetMapArtLayers(nil). Never force a rebuild until the
    -- canvas itself owns a valid mapID; its normal map update will rebuild later.
    local mapID = tonumber(container.mapID)
    if not mapID or mapID <= 0 then return end
    if C_Map and C_Map.GetMapArtLayers then
        local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
        if not ok or type(layers) ~= "table" or not layers[1] then return end
    end

    if type(container.CreateZoomLevels) == "function" then
        SecureCanvas(container, "CreateZoomLevels")
    end
    if CanvasReady(container, true)
        and type(container.GetScaleForMaxZoom) == "function"
        and type(container.SetZoomTarget) == "function" then
        local ok, maxZoom = pcall(container.GetScaleForMaxZoom, container)
        if ok and type(maxZoom) == "number" and maxZoom > 0 then
            SecureCanvas(container, "SetZoomTarget", maxZoom)
        end
    end
end

function M:GetDiagnostics()
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    local p = P()
    return {
        enabled = p.mapMovable or p.mapEnhancedZoom or p.mapRememberZoom or false,
        initialized = initialized,
        frame = WorldMapFrame ~= nil,
        scrollContainer = container ~= nil,
        mapID = WorldMapID(),
        canvasMapID = container and container.mapID or nil,
        canvasReady = CanvasReady(container, true),
        canvasChildWidth = container and container.Child and container.Child:GetWidth() or nil,
        canvasChildHeight = container and container.Child and container.Child:GetHeight() or nil,
        zoomLevelCount = container and type(container.zoomLevels) == "table" and #container.zoomLevels or 0,
        movable = movableApplied,
        dragHandle = dragHandleKind,
        enhancedZoom = p.mapEnhancedZoom == true,
        zoomHook = zoomApplied,
        createZoomLevels = container and type(container.CreateZoomLevels) == "function" or false,
        rememberZoom = p.mapRememberZoom == true,
        rememberHook = rememberApplied,
        nativeCanvasOwned = NativeMapCanvasOwned(),
    }
end

function M:Init()
    local p = P()
    if not (p.mapMovable or p.mapEnhancedZoom or p.mapRememberZoom) then return end

    -- WorldMapFrame is load-on-demand on some Classic layouts, so do not assume
    -- the frame exists when TurboFace itself initializes.
    ns.API.OnAddonReady("Blizzard_WorldMap", function()
        if not WorldMapFrame then return end
        initialized = true
        ApplyMovable()
        ApplyZoom()
        ApplyRememberZoom()
    end)
end