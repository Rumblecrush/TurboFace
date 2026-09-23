local addonName, ns = ...

-- =============================================================================
-- TurboFace CPUProfiler.lua
--
-- Opt-in subsystem CPU profiler. It is completely parked until the user starts
-- a session. The profiler reads Blizzard's scriptProfile counters; gameplay hot
-- paths are never wrapped or timed by TurboFace itself. Registered targets use
-- exclusive/self CPU by default so parent/child targets cannot double-count the
-- same work when computing the tracked-vs-untracked breakdown.
--
-- Commands:
--   /tf cpu start
--   /tf cpu report
--   /tf cpu stop
--   /tf cpu status
-- The equivalent /tf debug cpu ... forms are routed here by Core.lua.
-- =============================================================================

local CPU = {}
ns.CPUProfiler = CPU

local P = {
    running = false,
    interval = 0.50,
    maxPeaks = 6,
    baseline = {},
    aggregate = {},
    states = {},
    peaks = { combat = {}, out = {} },
    topTags = {},
    topMs = {},
    topCalls = {},
    nativeBaseline = nil,
}

local function Chat(msg)
    if ns.Chat then
        ns:Chat("CPU", msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("TurboFace CPU: " .. tostring(msg))
    elseif print then
        print("TurboFace CPU: " .. tostring(msg))
    end
end

local function NormalizeArgs(args)
    args = (args or ""):lower():match("^%s*(.-)%s*$") or ""
    return args:gsub("%s+", " ")
end

local function ProfilingReady(verbose)
    local cvar = GetCVar and GetCVar("scriptProfile") or nil
    if tostring(cvar) ~= "1" then
        if verbose ~= false then
            Chat("scriptProfile is OFF. Run |cffffff78/console scriptProfile 1|r, then |cffffff78/reload|r, then |cffffff78/tf cpu start|r.")
        end
        return false, "scriptProfile off"
    end
    if not UpdateAddOnCPUUsage or not GetAddOnCPUUsage then
        if verbose ~= false then Chat("addon CPU APIs are unavailable on this client.") end
        return false, "addon CPU API unavailable"
    end
    if not GetFunctionCPUUsage then
        if verbose ~= false then
            Chat("GetFunctionCPUUsage is unavailable on this client; subsystem attribution cannot run.")
        end
        return false, "function CPU API unavailable"
    end
    return true
end

local function ReadFunctionCPU(target)
    if not target or type(target.fn) ~= "function" then return 0, 0 end
    -- Detailed rows intentionally use inclusive call-tree CPU. That makes a
    -- cadence/event entry point answer the question users actually care about:
    -- "how expensive was everything this callback caused?" Parent/child rows
    -- can therefore overlap and MUST NOT be summed to derive coverage.
    local total, calls = GetFunctionCPUUsage(target.fn, true)
    return tonumber(total) or 0, tonumber(calls) or 0
end

local function CountTrackedPlates()
    local n = 0
    for _ in pairs(ns.unitToPlate or {}) do n = n + 1 end
    return n
end

local nativeEnum = Enum and Enum.AddOnProfilerMetric
local function NativeMetricID(name, fallback)
    local value = nativeEnum and nativeEnum[name]
    if value ~= nil then return value end
    return fallback
end

-- Resolve through Enum when available so Classic Era 1.15.9 / BCC 2.5.6
-- builds use the client's own metric identifiers. Numeric fallbacks preserve
-- compatibility with the original 1.15.6 AddOnProfiler surface.
local NATIVE_METRIC = {
    SessionAverageTime = NativeMetricID("SessionAverageTime", 0),
    RecentAverageTime = NativeMetricID("RecentAverageTime", 1),
    EncounterAverageTime = NativeMetricID("EncounterAverageTime", 2),
    LastTime = NativeMetricID("LastTime", 3),
    PeakTime = NativeMetricID("PeakTime", 4),
    CountTimeOver1Ms = NativeMetricID("CountTimeOver1Ms", 5),
    CountTimeOver5Ms = NativeMetricID("CountTimeOver5Ms", 6),
    CountTimeOver10Ms = NativeMetricID("CountTimeOver10Ms", 7),
    CountTimeOver50Ms = NativeMetricID("CountTimeOver50Ms", 8),
}

local function NativeProfilerReady()
    return C_AddOnProfiler and type(C_AddOnProfiler.GetAddOnMetric) == "function"
end

local function NativeMetric(metric)
    if not NativeProfilerReady() then return nil end
    local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, addonName, metric)
    if not ok then return nil end
    return tonumber(value)
end

local function NativeTickRate()
    if not (C_AddOnProfiler and type(C_AddOnProfiler.GetTicksPerSecond) == "function") then return nil end
    local ok, value = pcall(C_AddOnProfiler.GetTicksPerSecond)
    value = ok and tonumber(value) or nil
    if not value or value <= 0 then return nil end
    return value
end

local function ReadNativeSnapshot()
    if not NativeProfilerReady() then return nil end
    local tickRate = NativeTickRate()
    local session = NativeMetric(NATIVE_METRIC.SessionAverageTime) or 0
    local recent = NativeMetric(NATIVE_METRIC.RecentAverageTime) or 0
    return {
        at = GetTime and GetTime() or 0,
        -- GetTicksPerSecond() is the profiler clock frequency (used by
        -- MeasureCall elapsedTicks), not the UI-frame/tick rate represented by
        -- RecentAverageTime. Keep it for diagnostics only; do NOT convert
        -- ms/tick into a CPU percentage with it.
        profilerClockHz = tickRate,
        session = session,
        recent = recent,
        last = NativeMetric(NATIVE_METRIC.LastTime) or 0,
        peak = NativeMetric(NATIVE_METRIC.PeakTime) or 0,
        over1 = NativeMetric(NATIVE_METRIC.CountTimeOver1Ms) or 0,
        over5 = NativeMetric(NATIVE_METRIC.CountTimeOver5Ms) or 0,
        over10 = NativeMetric(NATIVE_METRIC.CountTimeOver10Ms) or 0,
        over50 = NativeMetric(NATIVE_METRIC.CountTimeOver50Ms) or 0,
    }
end

local function PrintNativeSnapshot(snap)
    if not snap then
        Chat("native C_AddOnProfiler metrics are unavailable on this client")
        return false
    end
    Chat(string.format("native always-on: sessionAvg=%.3fms/tick recentAvg=%.3fms/tick last=%.3fms peak=%.3fms | >1ms=%d >5ms=%d >10ms=%d >50ms=%d",
        snap.session, snap.recent, snap.last, snap.peak, snap.over1, snap.over5, snap.over10, snap.over50))
    return true
end

local function CaptureNativeBaseline()
    local snap = ReadNativeSnapshot()
    if not snap then
        Chat("native C_AddOnProfiler metrics are unavailable on this client")
        return false
    end
    P.nativeBaseline = snap
    Chat(string.format("native baseline captured: peak=%.3fms | >1ms=%d >5ms=%d >10ms=%d >50ms=%d",
        snap.peak, snap.over1, snap.over5, snap.over10, snap.over50))
    return true
end

local function PrintNativeDelta()
    if not P.nativeBaseline then
        Chat("no native baseline. Run |cffffff78/tf cpu native baseline|r first.")
        return false
    end
    local now = ReadNativeSnapshot()
    if not now then
        Chat("native C_AddOnProfiler metrics are unavailable on this client")
        return false
    end
    local b = P.nativeBaseline
    local elapsed = math.max(0, (now.at or 0) - (b.at or 0))
    local d1 = math.max(0, now.over1 - b.over1)
    local d5 = math.max(0, now.over5 - b.over5)
    local d10 = math.max(0, now.over10 - b.over10)
    local d50 = math.max(0, now.over50 - b.over50)
    local newPeak = now.peak > (b.peak + 0.0005)
    Chat(string.format("native delta %.1fs: recentAvg=%.3fms/tick last=%.3fms | +>1ms=%d +>5ms=%d +>10ms=%d +>50ms=%d | newPeak=%s%s",
        elapsed, now.recent, now.last, d1, d5, d10, d50,
        newPeak and "YES" or "no", newPeak and string.format(" (%.3fms)", now.peak) or ""))
    return true
end

local function PrintNativeProfiler()
    local snap = ReadNativeSnapshot()
    if not PrintNativeSnapshot(snap) then return false end
    if P.nativeBaseline then PrintNativeDelta() end
    return true
end

local function PrintNativeTop()
    if not (C_AddOnProfiler and type(C_AddOnProfiler.GetTopKAddOnsForMetric) == "function") then
        Chat("native top-addon metrics are unavailable on this client")
        return false
    end
    local function PrintTop(label, metric)
        local ok, rows = pcall(C_AddOnProfiler.GetTopKAddOnsForMetric, metric, 5)
        if not ok or type(rows) ~= "table" then
            Chat("native top " .. label .. ": unavailable")
            return
        end
        local parts = {}
        for i = 1, math.min(5, #rows) do
            local row = rows[i]
            if type(row) == "table" then
                parts[#parts + 1] = string.format("%s=%.3f", tostring(row.addOnName or "?"), tonumber(row.metricValue) or 0)
            end
        end
        Chat("native top " .. label .. ": " .. (#parts > 0 and table.concat(parts, " | ") or "none"))
    end
    PrintTop("recentAvg(ms/tick)", NATIVE_METRIC.RecentAverageTime)
    PrintTop("peak(ms)", NATIVE_METRIC.PeakTime)
    return true
end


-- -----------------------------------------------------------------------------
-- Native kill/post-combat window tracer
-- -----------------------------------------------------------------------------
-- This is intentionally independent of scriptProfile. When enabled it sleeps
-- until either a hostile UNIT_DIED/UNIT_DESTROYED CLEU arrives or combat ends.
-- Death opens a four-second aftermath trace; PLAYER_REGEN_ENABLED starts a fresh
-- five-second post-combat trace so a late combat drop cannot fall outside the
-- diagnostic window. Selected TurboFace boundaries can additionally call
-- MeasureKillNoReturn(), which uses C_AddOnProfiler.MeasureCall when available.
-- That gives us precise elapsed/allocation data without globally profiling every
-- Lua function in the addon. The command remains `/tf cpu kill` for compatibility.
local KILL_WINDOW = 4.0
local COMBAT_EXIT_WINDOW = 5.0
local KILL_SAMPLE_INTERVAL = 0.02
local KILL_MAX_RECORDS = 8
local killTrace = {
    enabled = false,
    records = {},
    active = nil,
    ticker = nil,
    eventFrame = nil,
}
P.killTrace = killTrace

local function KillNow()
    return GetTime and GetTime() or 0
end

local function KillWindowActive()
    local r = killTrace.active
    return killTrace.enabled and r and KillNow() <= (r.endsAt or 0)
end

local function KillAddMarker(event, detail)
    local r = killTrace.active
    if not r or KillNow() > (r.endsAt or 0) then return end
    local markers = r.markers
    if #markers >= 30 then return end
    markers[#markers + 1] = {
        t = KillNow() - r.startedAt,
        event = tostring(event or "?"),
        detail = detail and tostring(detail) or nil,
    }
end


local function KillRecordMeasurement(tag, elapsedMs, allocatedBytes, deallocatedBytes)
    local r = killTrace.active
    if not r or KillNow() > (r.endsAt or 0) then return end
    elapsedMs = tonumber(elapsedMs) or 0
    allocatedBytes = tonumber(allocatedBytes) or 0
    deallocatedBytes = tonumber(deallocatedBytes) or 0
    local m = r.measurements[tag]
    if not m then
        m = { ms = 0, calls = 0, alloc = 0, dealloc = 0, max = 0 }
        r.measurements[tag] = m
    end
    m.ms = m.ms + elapsedMs
    m.calls = m.calls + 1
    m.alloc = m.alloc + allocatedBytes
    m.dealloc = m.dealloc + deallocatedBytes
    if elapsedMs > m.max then m.max = elapsedMs end
end

function CPU:IsKillTraceWindowActive()
    return KillWindowActive()
end

-- For no-return update/cleanup functions only. Outside an active kill window it
-- is exactly one branch plus the original call. During a window, MeasureCall is
-- the preferred Classic 1.15.9/BCC 2.5.6-era native measurement path.
function CPU:MeasureKillNoReturn(tag, fn, ...)
    if type(fn) ~= "function" then return end
    if not KillWindowActive() then
        fn(...)
        return
    end

    if C_AddOnProfiler and type(C_AddOnProfiler.MeasureCall) == "function" then
        -- Do not pcall and retry on failure: MeasureCall executes fn itself, so
        -- retrying after an error could duplicate side effects. Let normal Lua
        -- error semantics propagate exactly as the original call would.
        local results = C_AddOnProfiler.MeasureCall(fn, ...)
        if type(results) == "table" then
            KillRecordMeasurement(tag,
                results.elapsedMilliseconds,
                results.allocatedBytes,
                results.deallocatedBytes)
        end
        return
    end

    -- Very old fallback: still useful for elapsed time, but no allocations.
    local before = debugprofilestop and debugprofilestop() or nil
    fn(...)
    if before and debugprofilestop then
        KillRecordMeasurement(tag, debugprofilestop() - before, 0, 0)
    end
end

function CPU:RecordKillDuration(tag, elapsedMs)
    if KillWindowActive() then
        KillRecordMeasurement(tag, elapsedMs, 0, 0)
    end
end


local EnsurePostCombatTrace

-- Shared kill-boundary wrapper.
--
-- Every instrumented site needs the same three properties: do nothing measurable
-- when no kill window is open, build the tag string ONLY inside a window (it is
-- per-event concatenation, so it must not run on the normal path), and call the
-- handler with its original arguments and error semantics either way. Twelve
-- sites wrote that guard out by hand before this existed; the eight boundaries
-- added in 0.15.4 use this instead of a thirteenth through twentieth copy.
--
-- Idle cost is one table lookup and one branch, which is what the hand-written
-- form cost too. Usage:
--
--     f:SetScript("OnEvent", function(_, event, ...)
--         ns.KillTrace("AuraStyle:", event, HandleAuraEvent, event, ...)
--     end)
--
-- The older hand-written sites are equivalent and were deliberately left alone
-- rather than mass-edited during a diagnostic change (§1.5); migrate them
-- opportunistically when touching those files for other reasons.
function ns.KillTrace(prefix, event, fn, ...)
    if type(fn) ~= "function" then return end
    if killTrace.enabled and event == "PLAYER_REGEN_ENABLED" and EnsurePostCombatTrace then
        EnsurePostCombatTrace()
    end
    if killTrace.enabled and KillWindowActive() then
        CPU:MeasureKillNoReturn(tostring(prefix) .. tostring(event), fn, ...)
    else
        fn(...)
    end
end

local function KillInsertTopSample(r, ms, t)
    local list = r.topSamples
    list[#list + 1] = { ms = ms, t = t }
    table.sort(list, function(a, b) return a.ms > b.ms end)
    while #list > 5 do table.remove(list) end
end

local function KillNearestMarker(r, t)
    local best, bestDist
    for i = 1, #r.markers do
        local m = r.markers[i]
        local d = math.abs((m.t or 0) - (t or 0))
        if not bestDist or d < bestDist then
            best, bestDist = m, d
        end
    end
    return best
end

local function KillFinishRecord()
    local r = killTrace.active
    if not r then return end
    if killTrace.ticker then
        if killTrace.ticker.Cancel then killTrace.ticker:Cancel() end
        killTrace.ticker = nil
    end
    r.finishedAt = KillNow()
    r.finalNative = ReadNativeSnapshot()
    local b, n = r.baseNative, r.finalNative
    if b and n then
        r.d1 = math.max(0, n.over1 - b.over1)
        r.d5 = math.max(0, n.over5 - b.over5)
        r.d10 = math.max(0, n.over10 - b.over10)
        r.d50 = math.max(0, n.over50 - b.over50)
    else
        r.d1, r.d5, r.d10, r.d50 = 0, 0, 0, 0
    end
    killTrace.records[#killTrace.records + 1] = r
    while #killTrace.records > KILL_MAX_RECORDS do table.remove(killTrace.records, 1) end
    killTrace.active = nil

    local near = KillNearestMarker(r, r.maxAt or 0)
    local nearText = near and (near.event .. (near.detail and ("(" .. near.detail .. ")") or "")) or "none"
    Chat(string.format("kill trace: %s maxNativeTick=%.3fms @+%.3fs near=%s | +>1=%d +>5=%d +>10=%d +>50=%d",
        r.name or "mob", r.maxLast or 0, r.maxAt or 0, nearText,
        r.d1 or 0, r.d5 or 0, r.d10 or 0, r.d50 or 0))
end

local function KillSample()
    local r = killTrace.active
    if not r then return end
    local now = KillNow()
    local last = NativeMetric(NATIVE_METRIC.LastTime) or 0
    local rel = now - r.startedAt
    if last > (r.maxLast or 0) then
        r.maxLast = last
        r.maxAt = rel
    end
    KillInsertTopSample(r, last, rel)
    if now >= (r.endsAt or 0) then KillFinishRecord() end
end

local function KillStartRecord(name, guid, subevent, windowSeconds)
    if not killTrace.enabled then return end
    if killTrace.active then KillFinishRecord() end
    local now = KillNow()
    local window = tonumber(windowSeconds) or KILL_WINDOW
    local r = {
        name = name or "mob",
        guid = guid,
        subevent = subevent,
        startedAt = now,
        endsAt = now + window,
        baseNative = ReadNativeSnapshot(),
        markers = {},
        measurements = {},
        topSamples = {},
        maxLast = 0,
        maxAt = 0,
    }
    killTrace.active = r
    KillAddMarker(subevent or "UNIT_DIED", name)
    if C_Timer and C_Timer.NewTicker then
        killTrace.ticker = C_Timer.NewTicker(KILL_SAMPLE_INTERVAL, KillSample)
    elseif C_Timer and C_Timer.After then
        -- Classic fallback: sparse checkpoints if NewTicker is unavailable.
        local checkpoints = {0, 0.05, 0.10, 0.25, 0.50, 1.0, 2.0}
        if window > 2.0 then checkpoints[#checkpoints + 1] = window end
        for _, delay in ipairs(checkpoints) do C_Timer.After(delay, KillSample) end
    end
end

EnsurePostCombatTrace = function()
    if not killTrace.enabled then return false end
    local now = KillNow()
    local r = killTrace.active
    -- Several PLAYER_REGEN_ENABLED consumers can ask for the window during the
    -- same event dispatch. The first one starts it; later consumers must join
    -- that record rather than finishing/restarting it and losing earlier work.
    if r and r.subevent == "PLAYER_REGEN_ENABLED"
        and now - (r.startedAt or now) <= 0.25
        and now <= (r.endsAt or 0) then
        return true
    end
    KillStartRecord("post-combat", nil, "PLAYER_REGEN_ENABLED", COMBAT_EXIT_WINDOW)
    return true
end


local function KillDeathCLEU(e)
    if not killTrace.enabled or type(e) ~= "table" then return end
    local subevent = e[2]
    if subevent ~= "UNIT_DIED" and subevent ~= "UNIT_DESTROYED" then return end
    local guid, name, flags = e[8], e[9], e[10]
    if not guid or guid == (UnitGUID and UnitGUID("player")) then return end

    -- Prefer hostile deaths. If the Classic build lacks the reaction constant,
    -- accept non-player deaths rather than silently losing the trace.
    local hostile = true
    if COMBATLOG_OBJECT_REACTION_HOSTILE and bit and bit.band and flags then
        hostile = bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    end
    if hostile then KillStartRecord(name, guid, subevent) end
end

local KILL_EVENTS = {
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_MONEY",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "BAG_UPDATE_DELAYED",
    "PLAYER_MONEY",
}

local function KillEventOnEvent(_, event, arg1)
    if not killTrace.enabled then return end

    -- Combat exit is its own trace trigger, not merely a marker inside a death
    -- trace. This closes the old blind spot where the final hostile death could
    -- precede PLAYER_REGEN_ENABLED by more than the four-second kill window.
    if event == "PLAYER_REGEN_ENABLED" then
        EnsurePostCombatTrace()
        return
    end

    if not KillWindowActive() then return end
    local detail
    if event == "NAME_PLATE_UNIT_REMOVED" then detail = arg1
    elseif event == "UNIT_AURA" then detail = arg1
    end
    KillAddMarker(event, detail)
end

local function EnsureKillEventFrame()
    if killTrace.eventFrame then return killTrace.eventFrame end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", KillEventOnEvent)
    killTrace.eventFrame = f
    return f
end

local function SetKillTraceEnabled(enabled)
    enabled = enabled == true
    if killTrace.enabled == enabled then return end
    killTrace.enabled = enabled
    local f = EnsureKillEventFrame()
    f:UnregisterAllEvents()
    if ns.CLEU then ns.CLEU:Unregister(KillDeathCLEU) end

    if enabled then
        for i = 1, #KILL_EVENTS do f:RegisterEvent(KILL_EVENTS[i]) end
        if f.RegisterUnitEvent then
            f:RegisterUnitEvent("UNIT_AURA", "player", "target")
        end
        -- On legacy clients without RegisterUnitEvent, omit this optional marker
        -- rather than waking the diagnostic frame for every UNIT_AURA globally.
        if ns.CLEU then
            ns.CLEU:Register(KillDeathCLEU, { UNIT_DIED = true, UNIT_DESTROYED = true })
        end
    else
        if killTrace.active then KillFinishRecord() end
    end
end

local function PrintKillRecord(r, index)
    if not r then return end
    Chat(string.format("kill #%d %s: maxNativeTick=%.3fms @+%.3fs | +>1=%d +>5=%d +>10=%d +>50=%d",
        index, r.name or "mob", r.maxLast or 0, r.maxAt or 0,
        r.d1 or 0, r.d5 or 0, r.d10 or 0, r.d50 or 0))

    if r.topSamples and #r.topSamples > 0 then
        local parts = {}
        for i = 1, math.min(3, #r.topSamples) do
            local q = r.topSamples[i]
            parts[#parts + 1] = string.format("%.3fms@+%.3fs", q.ms or 0, q.t or 0)
        end
        Chat("   top native ticks: " .. table.concat(parts, " | "))
    end

    local rows = {}
    for tag, m in pairs(r.measurements or {}) do
        rows[#rows + 1] = { tag = tag, m = m }
    end
    table.sort(rows, function(a, b) return (a.m.ms or 0) > (b.m.ms or 0) end)
    for i = 1, math.min(6, #rows) do
        local row, m = rows[i], rows[i].m
        Chat(string.format("   %s: %.3fms/%d max=%.3fms alloc=%+.1fKB",
            row.tag, m.ms or 0, m.calls or 0, m.max or 0,
            ((m.alloc or 0) - (m.dealloc or 0)) / 1024))
    end

    if r.markers and #r.markers > 0 then
        local parts = {}
        for i = 1, math.min(14, #r.markers) do
            local m = r.markers[i]
            parts[#parts + 1] = string.format("+%.3f %s%s", m.t or 0, m.event or "?",
                m.detail and ("(" .. m.detail .. ")") or "")
        end
        Chat("   events: " .. table.concat(parts, " | "))
    end
end

local function PrintKillTraceReport()
    if killTrace.active then KillSample() end
    Chat(string.format("kill trace: %s | saved=%d%s", killTrace.enabled and "ON" or "off",
        #killTrace.records, killTrace.active and " | active window" or ""))
    local first = math.max(1, #killTrace.records - 4)
    for i = first, #killTrace.records do PrintKillRecord(killTrace.records[i], i) end
end

local function NewCPUState()
    return { wall = 0, addon = 0, profiler = 0, samples = 0, targets = {}, calls = {} }
end

local function StateKey()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return "combat" end
    return "out"
end

local function SortDeltas(deltas)
    table.sort(deltas, function(a, b)
        if a.ms == b.ms then return a.tag < b.tag end
        return a.ms > b.ms
    end)
end

local function InsertPeak(list, peak, limit)
    list[#list + 1] = peak
    table.sort(list, function(a, b) return a.pct > b.pct end)
    while #list > limit do table.remove(list) end
end

local function PeakQualifies(list, pct, limit)
    if #list < (limit or P.maxPeaks) then return true end
    local last = list[#list]
    return not last or pct > (last.pct or 0)
end

local function PushTopSample(tag, ms, calls)
    local tags, vals, callVals = P.topTags, P.topMs, P.topCalls
    for i = 1, 4 do
        if ms > (vals[i] or -1) then
            for j = 4, i + 1, -1 do
                tags[j], vals[j], callVals[j] = tags[j - 1], vals[j - 1], callVals[j - 1]
            end
            tags[i], vals[i], callVals[i] = tag, ms, calls
            return
        end
    end
end

local function ResetTopSample()
    for i = 1, 4 do
        P.topTags[i], P.topMs[i], P.topCalls[i] = nil, nil, nil
    end
end

local function FormatTopEntries(entries, maxCount)
    local out = {}
    local n = math.min(maxCount or 4, #entries)
    for i = 1, n do
        local e = entries[i]
        out[#out + 1] = string.format("%s %.2fms/%d", e.tag, e.ms or 0, e.calls or 0)
    end
    return #out > 0 and table.concat(out, " | ") or "(no registered target CPU)"
end

local function Sample()
    if not P.running then return false end

    local now = GetTime()
    local wall = now - (P.lastWall or now)
    if wall <= 0 then return false end

    -- GetFunctionCPUUsage cannot account the still-running invocation of Sample
    -- itself, but at the start of this call it can see all previously completed
    -- sampler calls. Keep that cost visible instead of letting profiler
    -- bookkeeping masquerade as gameplay CPU in the next addon-wide delta.
    local profilerTotal = 0
    if GetFunctionCPUUsage then
        profilerTotal = tonumber((GetFunctionCPUUsage(Sample, true))) or 0
    end
    local profilerDelta = math.max(0, profilerTotal - (P.lastProfilerTotal or profilerTotal))
    P.lastProfilerTotal = profilerTotal

    -- Use TurboFace's own attributed memory rather than the process-wide Lua
    -- heap. The latter includes Blizzard UI and every other addon.
    local memKB = 0
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        memKB = tonumber(GetAddOnMemoryUsage(addonName)) or 0
    end
    local memDeltaKB = memKB - (P.lastMemKB or memKB)
    P.lastMemKB = memKB

    UpdateAddOnCPUUsage()
    local addonNow = GetAddOnCPUUsage(addonName) or 0
    local addonDelta = math.max(0, addonNow - (P.lastAddon or addonNow))

    local stateKey = StateKey()
    local state = P.states[stateKey]
    if not state then return false end
    state.wall = state.wall + wall
    state.addon = state.addon + addonDelta
    state.profiler = state.profiler + profilerDelta
    state.samples = state.samples + 1

    ResetTopSample()
    local targets = ns.CPUProfileTargets or {}
    for tag, target in pairs(targets) do
        local total, calls = ReadFunctionCPU(target)
        local base = P.baseline[tag]
        if not base then
            base = { total = total, calls = calls }
            P.baseline[tag] = base
        end
        local dms = math.max(0, total - (base.total or 0))
        local dcalls = math.max(0, calls - (base.calls or 0))
        base.total, base.calls = total, calls
        if dms > 0 or dcalls > 0 then
            state.targets[tag] = (state.targets[tag] or 0) + dms
            state.calls[tag] = (state.calls[tag] or 0) + dcalls
            P.aggregate[tag] = (P.aggregate[tag] or 0) + dms
            PushTopSample(tag, dms, dcalls)
        end
    end

    local pct = addonDelta / (wall * 1000) * 100
    local peakList = P.peaks[stateKey]
    if PeakQualifies(peakList, pct, P.maxPeaks) then
        local entries = {}
        for i = 1, 4 do
            local tag = P.topTags[i]
            if tag then
                entries[#entries + 1] = { tag = tag, ms = P.topMs[i] or 0, calls = P.topCalls[i] or 0 }
            end
        end
        InsertPeak(peakList, {
            pct = pct,
            addonMs = addonDelta,
            wall = wall,
            profilerMs = profilerDelta,
            entries = entries,
            plates = CountTrackedPlates(),
            timers = ns.Timers and ns.Timers.Count and ns.Timers:Count() or 0,
            cadence = ns.Cadence and ns.Cadence.Count and ns.Cadence:Count() or 0,
            cadenceHz = ns.Cadence and ns.Cadence.FastestHz and ns.Cadence:FastestHz() or 0,
            memDeltaKB = memDeltaKB,
            at = now,
        }, P.maxPeaks)
    end

    -- Take the next addon baseline only after the per-function queries. This
    -- prevents the sampling pass itself from being charged to the next window.
    UpdateAddOnCPUUsage()
    P.lastAddon = GetAddOnCPUUsage(addonName) or addonNow
    P.lastWall = GetTime()
    return true
end

local function StopSampler()
    if P.sampler then
        if P.sampler.Cancel then P.sampler:Cancel() end
        P.sampler = nil
    end
end

local function StartSampler()
    StopSampler()
    if not (C_Timer and C_Timer.NewTicker) then
        Chat("C_Timer.NewTicker is unavailable; CPU sampler cannot start on this client.")
        return false
    end
    -- Native 0.5-second timer: the profiler itself no longer receives one Lua
    -- callback per rendered frame simply to decide whether a sample is due.
    P.sampler = C_Timer.NewTicker(P.interval, Sample)
    return true
end

local function CaptureBaseline()
    wipe(P.baseline)
    for tag, target in pairs(ns.CPUProfileTargets or {}) do
        local total, calls = ReadFunctionCPU(target)
        P.baseline[tag] = { total = total, calls = calls }
    end
    UpdateAddOnCPUUsage()
    P.lastAddon = GetAddOnCPUUsage(addonName) or 0
    P.lastWall = GetTime()
    P.lastProfilerTotal = tonumber((GetFunctionCPUUsage(Sample, true))) or 0
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        P.lastMemKB = tonumber(GetAddOnMemoryUsage(addonName)) or 0
    else
        P.lastMemKB = 0
    end
end

function CPU:Snapshot()
    if not ProfilingReady(true) then return end
    UpdateAddOnCPUUsage()
    local cpu = GetAddOnCPUUsage(addonName) or 0
    local mem = 0
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        mem = GetAddOnMemoryUsage(addonName) or 0
    end
    Chat(("snapshot: %.0f ms addon CPU since login/reset | %.0f KB memory"):format(cpu, mem))
end

function CPU:Start()
    if not ProfilingReady(true) then return end
    P.running = false
    P.aggregate = {}
    P.states = { combat = NewCPUState(), out = NewCPUState() }
    P.peaks = { combat = {}, out = {} }
    CaptureBaseline()
    P.running = true
    if not StartSampler() then
        P.running = false
        return
    end
    local count = 0
    for _ in pairs(ns.CPUProfileTargets or {}) do count = count + 1 end
    Chat(string.format("STARTED — %d subsystem entry points, %.1fs windows; combat and out-of-combat recorded separately.", count, P.interval))
end

local function PrintState(label, state)
    if not state or state.wall <= 0 then
        Chat(label .. ": no samples")
        return
    end
    local avg = state.addon / (state.wall * 1000) * 100
    local profilerPct = state.profiler / (state.wall * 1000) * 100
    Chat(string.format("%s: avg %.2f%% | %.1f ms / %.1fs | %d windows | profiler≈%.2f%% (%.1fms)",
        label, avg, state.addon, state.wall, state.samples, profilerPct, state.profiler))
    local rows = {}
    for tag, ms in pairs(state.targets) do
        rows[#rows + 1] = { tag = tag, ms = ms, calls = state.calls[tag] or 0 }
    end
    SortDeltas(rows)
    for i = 1, math.min(8, #rows) do
        local r = rows[i]
        Chat(string.format("  #%d %s — %.1f ms / %d calls", i, r.tag, r.ms, r.calls))
    end
end

local function PrintPeaks(label, peaks)
    if not peaks or #peaks == 0 then return end
    Chat(label .. " peak windows:")
    for i = 1, math.min(4, #peaks) do
        local p = peaks[i]
        Chat(string.format("  #%d %.2f%% (%.2fms/%.2fs) plates=%d cadence=%d@%.0fHz auraTimers=%d mem=%+.0fKB profiler≈%.2fms",
            i, p.pct, p.addonMs, p.wall, p.plates or 0, p.cadence or 0, p.cadenceHz or 0, p.timers or 0, p.memDeltaKB or 0, p.profilerMs or 0))
        Chat("     " .. FormatTopEntries(p.entries, 4))
    end
end

function CPU:Report()
    -- Always acknowledge the command first. If a future client/API issue stops
    -- report generation, the user can distinguish command routing from data.
    Chat("report requested — session is " .. (P.running and "RUNNING" or "stopped"))
    if not P.states.combat then
        Chat("no profiler session exists yet — use |cffffff78/tf cpu start|r")
        return
    end
    if P.running and P.lastWall and (GetTime() - P.lastWall) >= (P.interval * 0.25) then
        Sample()
    end
    Chat("=== TurboFace subsystem CPU report ===")
    Chat("detail rows are INCLUSIVE call-tree CPU; parent/child rows may overlap and are not summed as coverage")
    PrintNativeProfiler()
    PrintState("Out of combat", P.states.out)
    PrintPeaks("Out of combat", P.peaks.out)
    PrintState("Combat", P.states.combat)
    PrintPeaks("Combat", P.peaks.combat)
end

function CPU:Stop()
    if P.running then
        if P.lastWall and (GetTime() - P.lastWall) >= (P.interval * 0.25) then Sample() end
        P.running = false
        StopSampler()
        Chat("STOPPED")
    else
        Chat("stop requested, but profiler was not running")
    end
    self:Report()
end

function CPU:Status()
    local ready, reason = ProfilingReady(false)
    local count = 0
    for _ in pairs(ns.CPUProfileTargets or {}) do count = count + 1 end
    Chat(string.format("status: %s | scriptProfile=%s | native=%s | targets=%d | session=%s | cadenceClients=%d@%.0fHz",
        ready and "READY" or tostring(reason), tostring(GetCVar and GetCVar("scriptProfile") or "?"), NativeProfilerReady() and "yes" or "no",
        count, P.running and "RUNNING" or (P.states.combat and "stopped/has report" or "none"),
        ns.Cadence and ns.Cadence.Count and ns.Cadence:Count() or 0,
        ns.Cadence and ns.Cadence.FastestHz and ns.Cadence:FastestHz() or 0))
end

function CPU:HandleSlash(args)
    args = NormalizeArgs(args)
    if args == "" or args == "status" then
        self:Status()
    elseif args == "start" then
        self:Start()
    elseif args == "report" then
        self:Report()
    elseif args == "stop" then
        self:Stop()
    elseif args == "snapshot" then
        self:Snapshot()
    elseif args == "native" then
        PrintNativeProfiler()
    elseif args == "native baseline" or args == "native reset" then
        CaptureNativeBaseline()
    elseif args == "native delta" or args == "native report" then
        PrintNativeDelta()
    elseif args == "native top" then
        PrintNativeTop()
    elseif args == "kill start" or args == "death start" then
        wipe(killTrace.records)
        SetKillTraceEnabled(true)
        Chat("kill trace STARTED — native-only 4.0s post-death + 5.0s post-combat windows; scriptProfile is not required")
    elseif args == "kill stop" or args == "death stop" then
        SetKillTraceEnabled(false)
        Chat("kill trace STOPPED")
        PrintKillTraceReport()
    elseif args == "kill report" or args == "death report" then
        PrintKillTraceReport()
    elseif args == "kill clear" or args == "death clear" then
        wipe(killTrace.records)
        Chat("kill trace history cleared")
    else
        Chat("usage: /tf cpu start | report | stop | status | snapshot | native [baseline|delta|top] | kill [start|report|stop|clear]")
    end
    return true
end
