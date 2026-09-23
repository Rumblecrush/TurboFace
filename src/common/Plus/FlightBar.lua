local _, ns = ...

-- TurboFace taxi timer.
-- Route durations use an attributed Flight Timer Classic baseline immediately,
-- then prefer this account's completed-flight measurements from
-- TurboFaceCacheDB. Unknown/new routes remain learnable.

local M = {}
ns.PlusFlight = M

local function Settings()
    return ns.PlusSettings()
end

local function Enabled()
    local section = not ns.PlusSectionEnabled or ns.PlusSectionEnabled("flightBar")
    return ns.MoverDependentEnabled(section)
end

local bar
local initialized = false
local takeTaxiHooked = false
local tooltipHooked = false
local classicTooltipHooked = false
local taxiButtonHookCount = 0
local registeredEvents = {}
local flightEvents
local pendingFlight
local faction
local ObserveTaxiState
-- TakeTaxiNode hooks run after Blizzard's protected function.  By then the
-- taxi map can already be closing and its node APIs may no longer return a
-- usable route.  Capture route identities while TAXIMAP_OPENED is active and
-- consume that immutable snapshot when the post-hook fires.
local routeSnapshot = {}

local function FlightStore()
    if type(TurboFaceCacheDB) ~= "table" then TurboFaceCacheDB = {} end
    if type(TurboFaceCacheDB.flightTimes) ~= "table" then TurboFaceCacheDB.flightTimes = {} end
    return TurboFaceCacheDB.flightTimes
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", "TurboFaceFlightBar", UIParent)
    bar:SetSize(230, 16)
    bar:SetStatusBarTexture(ns.GetTexture("Blizzard"))
    bar:Hide()

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 3, 0)
    bar.label:SetJustifyH("LEFT")

    bar.timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timer:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.timer:SetJustifyH("RIGHT")

    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then M:StopBar() end
    end)
    if ns.AttachBarBorder then ns:AttachBarBorder(nil, bar) end
    return bar
end

function M:StopBar()
    if not bar then return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
end

local function AnchorBar(frame)
    local moved = ns.Movers and ns.Movers.ApplyElement and ns.Movers:ApplyElement("FlightBar")
    if not moved and not frame:GetPoint() then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remain = seconds % 60
    if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, remain) end
    return ("%d:%02d"):format(minutes, remain)
end

local function StartCountdown(duration, destination)
    duration = tonumber(duration)
    if not Enabled() or not duration or duration <= 0 then M:StopBar(); return end

    local frame = EnsureBar()
    local p = Settings()
    frame:SetStatusBarTexture(ns.GetTexture("Blizzard"))
    frame:SetMinMaxValues(0, duration)
    frame:SetValue(0)
    frame:SetScale(tonumber(p.flightBarScale) or 1)
    frame:SetWidth(tonumber(p.flightBarWidth) or 230)
    frame:SetStatusBarColor(faction == "Alliance" and 0 or 1, faction == "Alliance" and 0.5 or 0.1,
        faction == "Alliance" and 1 or 0.1, 0.9)
    frame.label:SetText(destination or "")
    AnchorBar(frame)

    local started = GetTime()
    local lastSecond
    frame:SetScript("OnUpdate", function(self)
        if ObserveTaxiState and ObserveTaxiState() then return end
        local elapsed = GetTime() - started
        local remaining = duration - elapsed
        if remaining <= 0 then M:StopBar(); return end
        self:SetValue(elapsed)
        local second = math.floor(remaining)
        if second ~= lastSecond then
            lastSecond = second
            self.timer:SetText(FormatDuration(second))
        end
    end)
    frame:Show()
end

local function StartLearning(destination)
    if not Enabled() then M:StopBar(); return end

    local frame = EnsureBar()
    local p = Settings()
    frame:SetStatusBarTexture(ns.GetTexture("Blizzard"))
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)
    frame:SetScale(tonumber(p.flightBarScale) or 1)
    frame:SetWidth(tonumber(p.flightBarWidth) or 230)
    frame:SetStatusBarColor(faction == "Alliance" and 0 or 1, faction == "Alliance" and 0.5 or 0.1,
        faction == "Alliance" and 1 or 0.1, 0.9)
    frame.label:SetText((destination or "Flight") .. " — Learning")
    AnchorBar(frame)

    local started = GetTime()
    local lastSecond
    frame:SetScript("OnUpdate", function(self)
        if ObserveTaxiState and ObserveTaxiState() then return end
        local second = math.floor(GetTime() - started)
        if second ~= lastSecond then
            lastSecond = second
            self.timer:SetText(FormatDuration(second))
        end
    end)
    frame:Show()
end

local function ContinentMapID()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetMapInfo then return end
    local id = C_Map.GetBestMapForUnit("player")
    local info = id and C_Map.GetMapInfo(id)
    while info and info.mapType and info.mapType > 2 and info.parentMapID do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if info and info.mapType == 2 then return info.mapID end
end

local function Coord(value)
    value = tonumber(value)
    if not value then return end
    return ("%.3f"):format(value)
end

local function PushPoint(points, x, y)
    x, y = Coord(x), Coord(y)
    if not x or not y then return false end
    local point = x .. ":" .. y
    if points[#points] ~= point then points[#points + 1] = point end
    return true
end

local function RouteKey(node)
    node = tonumber(node)
    if not node or not NumTaxiNodes or node < 1 or node > NumTaxiNodes() then return end

    local current
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then current = i break end
    end
    if not current then return end

    local points = {}
    local routeCount = GetNumRoutes and tonumber(GetNumRoutes(node)) or 0
    if routeCount and routeCount > 0 and TaxiGetSrcX and TaxiGetSrcY and TaxiGetDestX and TaxiGetDestY then
        for segment = 1, routeCount do
            if not PushPoint(points, TaxiGetSrcX(node, segment), TaxiGetSrcY(node, segment)) then return end
            if not PushPoint(points, TaxiGetDestX(node, segment), TaxiGetDestY(node, segment)) then return end
        end
    else
        local sx, sy = TaxiNodePosition(current)
        local dx, dy = TaxiNodePosition(node)
        if not PushPoint(points, sx, sy) then return end
        if routeCount and routeCount > 1 and TaxiGetNodeSlot then
            for hop = 2, routeCount do
                local slot = TaxiGetNodeSlot(node, hop, true)
                local x, y = slot and TaxiNodePosition(slot)
                PushPoint(points, x, y)
            end
        end
        if not PushPoint(points, dx, dy) then return end
    end

    if #points < 2 then return end
    return table.concat(points, ":")
end

local function CurrentTaxiNode()
    if not NumTaxiNodes or not TaxiNodeGetType then return end
    for node = 1, NumTaxiNodes() do
        if TaxiNodeGetType(node) == "CURRENT" then return node end
    end
end

local function EndpointHash(node)
    if not node or not TaxiNodePosition then return end
    local x = TaxiNodePosition(node)
    x = tonumber(x)
    if not x then return end
    -- Flight Timer Classic's published data keys nodes by the taxi-map X
    -- coordinate at eight-decimal precision.
    return tostring(math.floor(x * 100000000))
end

local function DestinationName(node)
    local name = TaxiNodeName and TaxiNodeName(node)
    return name and strmatch(name, "[^,]+") or name
end

local function RouteRecord(continent, key)
    if not continent or not key then return end
    local root = FlightStore()
    local factionStore = root[faction]
    local continentStore = factionStore and factionStore[continent]
    return continentStore and continentStore[key], continent, key
end

local function SaveMeasurement(flight, elapsed)
    if not flight or not flight.continent or not flight.key then return end
    elapsed = tonumber(elapsed)
    if not elapsed or elapsed < 3 or elapsed > 3600 then return end

    local root = FlightStore()
    root[faction] = root[faction] or {}
    root[faction][flight.continent] = root[faction][flight.continent] or {}
    local bucket = root[faction][flight.continent]
    local old = bucket[flight.key]

    local samples = type(old) == "table" and tonumber(old.samples) or 0
    local previous = type(old) == "table" and tonumber(old.seconds) or tonumber(old)
    local seconds
    if previous and samples > 0 then
        -- Keep a bounded running mean so one laggy landing does not permanently
        -- dominate a route while newer measurements can still correct it.
        local weight = math.min(samples, 4)
        seconds = ((previous * weight) + elapsed) / (weight + 1)
        samples = weight + 1
    else
        seconds, samples = elapsed, 1
    end

    bucket[flight.key] = {
        seconds = math.floor(seconds * 10 + 0.5) / 10,
        samples = samples,
        destination = flight.destination,
        seedSeconds = flight.seedSeconds,
    }
end

local function CaptureRoute(node)
    local continent = ContinentMapID()
    local key = RouteKey(node)
    local current = CurrentTaxiNode()
    local route = {
        continent = continent,
        key = key,
        destination = DestinationName(node),
        sourceHash = EndpointHash(current),
        destinationHash = EndpointHash(node),
    }
    -- A complete full-route identity is required for observation, but the
    -- baseline can still provide a useful first-flight timer if only its two
    -- endpoint hashes are available on a particular client build.
    if not ((route.continent and route.key) or (route.sourceHash and route.destinationHash)) then return end
    return route
end

local function CaptureTaxiRoutes()
    wipe(routeSnapshot)
    if not NumTaxiNodes then return end
    local count = tonumber(NumTaxiNodes()) or 0
    for node = 1, count do
        local route = CaptureRoute(node)
        if route then routeSnapshot[node] = route end
    end
end

local function ResolveRoute(node)
    node = tonumber(node)
    if not node then return end
    return routeSnapshot[node] or CaptureRoute(node)
end

local function LearnedDuration(route)
    if not route then return end
    local record, continent, key = RouteRecord(route.continent, route.key)
    local seconds = type(record) == "table" and record.seconds or record
    return tonumber(seconds), continent, key
end

local function SeedDuration(route)
    if not route or not route.sourceHash or not route.destinationHash then return end
    local factionData = ns.PlusFlightSeedData and ns.PlusFlightSeedData[faction]
    local sourceData = factionData and factionData[route.sourceHash]
    return tonumber(sourceData and sourceData[route.destinationHash])
end

local function RouteDuration(route)
    local learned, continent, key = LearnedDuration(route)
    if learned then return learned, "learned", continent, key end
    return SeedDuration(route), "seed", continent, key
end

local function NodeFromButton(button)
    if not button then return end
    return tonumber(button.nodeIndex or button.slotIndex or (button.GetID and button:GetID()))
end

local function AddTooltip(button)
    if not Enabled() or not GameTooltip then return end
    local node = NodeFromButton(button)
    local route = node and ResolveRoute(node)
    local seconds = route and RouteDuration(route)
    if seconds then
        GameTooltip:AddLine("Flight Time: " .. FormatDuration(seconds), 0, 0.8, 1)
    elseif route then
        GameTooltip:AddLine("Flight Time: learns on first flight", 0.5, 0.7, 0.8)
    else
        return
    end
    GameTooltip:Show()
end

local function HookTaxiTooltips()
    if tooltipHooked then return end
    if type(TaxiNodeOnButtonEnter) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", AddTooltip)
        tooltipHooked = true
        classicTooltipHooked = true
    end
end

local function HookVisibleTaxiButtons()
    -- Classic's shared hover handler already covers every taxi button. Avoid a
    -- second per-button hook, which would append the learned line twice.
    if classicTooltipHooked then return end
    if not NumTaxiNodes then return end
    for i = 1, NumTaxiNodes() do
        local button = _G["TaxiButton" .. i]
        if button and button.HookScript and not button._tfFlightTooltipHooked then
            button._tfFlightTooltipHooked = true
            button:HookScript("OnEnter", AddTooltip)
            taxiButtonHookCount = taxiButtonHookCount + 1
        end
    end
end

local function FinishPendingFlight()
    if not pendingFlight then return false end
    local flight = pendingFlight
    pendingFlight = nil
    local started = flight.started or flight.requested
    if started then SaveMeasurement(flight, GetTime() - started) end
    M:StopBar()
    return true
end

local function CancelPendingFlight()
    pendingFlight = nil
    M:StopBar()
end

-- PLAYER_CONTROL_GAINED is the normal Classic landing signal. Also observe the
-- actual taxi state from the visible bar so a missed control event cannot leave
-- a completed flight unsaved or a timer stuck onscreen.
ObserveTaxiState = function()
    if not pendingFlight or not UnitOnTaxi then return false end
    if UnitOnTaxi("player") then
        pendingFlight.sawOnTaxi = true
        return false
    end
    if pendingFlight.sawOnTaxi then return FinishPendingFlight() end
    -- TakeTaxiNode's post-hook also runs when Blizzard rejects the purchase
    -- (for example, insufficient money). Do not leave a phantom timer/pending
    -- sample alive when taxi state never begins.
    if pendingFlight.requested and GetTime() - pendingFlight.requested > 5 then
        CancelPendingFlight()
        return true
    end
    return false
end

local function OnFlightEvent(_, event)
    if event == "TAXIMAP_OPENED" then
        CaptureTaxiRoutes()
        local after = ns.After or (C_Timer and C_Timer.After)
        if after then
            after(0, function()
                CaptureTaxiRoutes()
                HookVisibleTaxiButtons()
            end)
        else
            HookVisibleTaxiButtons()
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if pendingFlight and (not UnitOnTaxi or not UnitOnTaxi("player")) then CancelPendingFlight() end
        return
    end
    if not pendingFlight then return end

    if event == "PLAYER_CONTROL_LOST" then
        if not pendingFlight.started then pendingFlight.started = GetTime() end
        if UnitOnTaxi and UnitOnTaxi("player") then pendingFlight.sawOnTaxi = true end
        return
    end

    if event == "PLAYER_CONTROL_GAINED" then
        if UnitOnTaxi and UnitOnTaxi("player") then return end
        FinishPendingFlight()
    end
end

local function HookTakeTaxiNode()
    if takeTaxiHooked or type(TakeTaxiNode) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    takeTaxiHooked = true
    hooksecurefunc("TakeTaxiNode", function(node)
        if not Enabled() or UnitAffectingCombat("player") then return end
        local route = ResolveRoute(node)
        if not route then
            pendingFlight = nil
            M:StopBar()
            return
        end
        local duration, source, continent, key = RouteDuration(route)
        local destination = route.destination
        pendingFlight = {
            continent = continent,
            key = key,
            destination = destination,
            requested = GetTime(),
            seedSeconds = source == "seed" and duration or nil,
        }
        if duration then
            StartCountdown(duration, destination)
        else
            StartLearning(destination)
        end
    end)
end

local function HookFlightCancellation()
    if type(hooksecurefunc) ~= "function" then return end
    if type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", CancelPendingFlight)
    end
    if type(AcceptBattlefieldPort) == "function" then
        hooksecurefunc("AcceptBattlefieldPort", function(_, accept)
            if accept then CancelPendingFlight() end
        end)
    end
    if C_SummonInfo and type(C_SummonInfo.ConfirmSummon) == "function" then
        hooksecurefunc(C_SummonInfo, "ConfirmSummon", CancelPendingFlight)
    end
end

function M:GetDiagnostics()
    local seedRoutes = 0
    local seedFaction = ns.PlusFlightSeedData and ns.PlusFlightSeedData[faction]
    if type(seedFaction) == "table" then
        for _, destinations in pairs(seedFaction) do
            if type(destinations) == "table" then
                for _ in pairs(destinations) do seedRoutes = seedRoutes + 1 end
            end
        end
    end

    local learnedRoutes = 0
    local learnedFaction = type(TurboFaceCacheDB) == "table"
        and type(TurboFaceCacheDB.flightTimes) == "table"
        and TurboFaceCacheDB.flightTimes[faction]
    if type(learnedFaction) == "table" then
        for _, routes in pairs(learnedFaction) do
            if type(routes) == "table" then
                for _ in pairs(routes) do learnedRoutes = learnedRoutes + 1 end
            end
        end
    end

    local snapshotRoutes = 0
    for _ in pairs(routeSnapshot) do snapshotRoutes = snapshotRoutes + 1 end

    local eventCount = 0
    for _, ok in pairs(registeredEvents) do
        if ok then eventCount = eventCount + 1 end
    end

    local tooltipMode = classicTooltipHooked and "classic-handler"
        or (taxiButtonHookCount > 0 and "TaxiButton globals" or "none")

    return {
        enabled = Enabled(),
        initialized = initialized,
        seedRoutes = seedRoutes,
        learnedRoutes = learnedRoutes,
        pending = pendingFlight and (pendingFlight.destination or "yes") or "none",
        taxiAPI = type(NumTaxiNodes) == "function" and type(TakeTaxiNode) == "function"
            and type(TaxiNodeGetType) == "function" and type(TaxiNodePosition) == "function",
        takeTaxiHooked = takeTaxiHooked,
        eventCount = eventCount,
        taxiMapEvent = registeredEvents.TAXIMAP_OPENED == true,
        snapshotRoutes = snapshotRoutes,
        tooltipMode = tooltipMode,
    }
end

function M:Init()
    if initialized or not Enabled() then return end
    initialized = true
    faction = UnitFactionGroup("player") or "Neutral"

    local frame = EnsureBar()
    if ns.Movers and ns.Movers.RegisterElement then
        ns.Movers:RegisterElement("FlightBar", frame, {
            label = "Flight Bar",
            overlayWidth = 230,
            overlayHeight = 16,
            fallbackPoint = { "CENTER", UIParent, "CENTER", 0, -160 },
            defaultPoint = { "CENTER", UIParent, "CENTER", 0, -160 },
        })
    end

    if not flightEvents then
        flightEvents = CreateFrame("Frame")
        flightEvents:SetScript("OnEvent", OnFlightEvent)
    else
        flightEvents:SetScript("OnEvent", OnFlightEvent)
    end
    wipe(registeredEvents)
    local function Register(event)
        local ok
        if ns.API and ns.API.RegisterEvent then
            ok = ns.API.RegisterEvent(flightEvents, event)
        else
            ok = pcall(flightEvents.RegisterEvent, flightEvents, event)
        end
        registeredEvents[event] = ok == true
    end
    Register("PLAYER_CONTROL_LOST")
    Register("PLAYER_CONTROL_GAINED")
    Register("PLAYER_ENTERING_WORLD")
    Register("TAXIMAP_OPENED")

    HookTakeTaxiNode()
    HookTaxiTooltips()
    HookFlightCancellation()
end

function M:Refresh()
    if not Enabled() then
        self:StopBar()
        return
    end
    if not initialized then self:Init() end
end
