local _, ns = ...

-- =============================================================================
-- PvP enemy-player health estimator
--
-- Classic Era intentionally exposes percentage health for hostile players rather
-- than their absolute current/max HP. DoT prediction needs an absolute max-health
-- basis to convert known damage into bar width, so this service learns a short-
-- lived estimate from observed percentage movement versus combat-log health
-- damage/healing. It owns no UI and never persists estimates across sessions/zones.
--
-- The service is dormant unless DotPrediction asks it to run. It registers as a
-- filtered consumer of TurboFace's shared ns.CLEU dispatcher; it never owns a raw
-- COMBAT_LOG_EVENT_UNFILTERED frame.
-- =============================================================================

local PHE = {}
ns.PvPHealthEstimate = PHE

local UnitExists        = UnitExists
local UnitGUID          = UnitGUID
local UnitHealth        = ns.API.ReadUnitHealth
local UnitHealthMax     = ns.API.ReadUnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitIsPlayer      = UnitIsPlayer
local UnitCanAttack     = UnitCanAttack
local GetTime           = GetTime
local abs               = math.abs
local max               = math.max
local min               = math.min

local MAX_SAMPLES          = 6
local MATCH_WINDOW         = 1.50
local STALE_BASELINE       = 4.00
local MIN_PERCENT_DELTA    = 0.20
local MAX_ESTIMATED_HEALTH = 200000
local MIN_ESTIMATED_HEALTH = 100
local CONSISTENT_SPREAD    = 0.20
local HIGH_SPREAD          = 0.14

local CONF_UNKNOWN = 0
local CONF_LOW     = 1
local CONF_MEDIUM  = 2
local CONF_HIGH    = 3

local CONF_LABEL = {
    [CONF_UNKNOWN] = "UNKNOWN",
    [CONF_LOW] = "LOW",
    [CONF_MEDIUM] = "MEDIUM",
    [CONF_HIGH] = "HIGH",
}

-- states[destGUID] = {
--   unit, lastPct, lastPctAt,
--   pendingNet, pendingSince, pendingEvents,
--   values={}, weights={}, n,
--   estimate, confidence, spread, seen,
-- }
local states = {}
local scratch = {}
local enabled = false

local HEALTH_CLEU_EVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    ENVIRONMENTAL_DAMAGE = true,
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
    UNIT_DIED = true,
    UNIT_DESTROYED = true,
}

local function IsPercentageOnlyEnemyPlayer(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    if UnitCanAttack and not UnitCanAttack("player", unit) then return false end
    local maximum = UnitHealthMax(unit) or 0
    local current = UnitHealth(unit) or 0
    return maximum == 100 and current >= 0 and current <= 100
end

local function ReadPercent(unit)
    if UnitHealthPercent then
        -- 1.15.9's percentage helper returns a floating-point percentage basis.
        -- Keep the call and normalization inside pcall so a future secret-value
        -- behavior change cannot break the prediction engine.
        local ok, value = pcall(function()
            local v = UnitHealthPercent(unit, true)
            if type(v) ~= "number" then return nil end
            if v >= 0 and v <= 1.000001 then return v * 100 end
            return v
        end)
        if ok and type(value) == "number" then
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return value
        end
    end

    local current = UnitHealth(unit) or 0
    local maximum = UnitHealthMax(unit) or 0
    if maximum <= 0 then return nil end
    return (current / maximum) * 100
end

local function ClearPending(state)
    state.pendingNet = 0
    state.pendingSince = nil
    state.pendingEvents = 0
end

local function NewState(unit, guid, pct, now)
    local state = {
        unit = unit,
        guid = guid,
        lastPct = pct,
        lastPctAt = now,
        pendingNet = 0,
        pendingEvents = 0,
        values = {},
        weights = {},
        n = 0,
        confidence = CONF_UNKNOWN,
        seen = now,
    }
    states[guid] = state
    return state
end

local function RecomputeEstimate(state)
    local count = min(state.n or 0, MAX_SAMPLES)
    if count <= 0 then
        state.estimate = nil
        state.confidence = CONF_UNKNOWN
        state.spread = nil
        return
    end

    for i = 1, count do scratch[i] = state.values[i] end
    for i = count + 1, MAX_SAMPLES do scratch[i] = nil end
    table.sort(scratch)
    local median = scratch[math.ceil(count / 2)]
    if not median or median <= 0 then
        state.estimate = nil
        state.confidence = CONF_UNKNOWN
        return
    end

    -- Ignore samples that disagree wildly with the median. Max-health buffs,
    -- uncaptured regen, or percentage-update/CLEU ordering can create a bad
    -- transition; one such sample must not poison an otherwise stable estimate.
    local weighted, totalWeight, inliers, maxDeviation, totalPct = 0, 0, 0, 0, 0
    for i = 1, count do
        local value = state.values[i]
        local weight = state.weights[i] or 1
        local deviation = abs(value - median) / median
        if deviation <= 0.35 then
            local cappedWeight = min(20, max(0.20, weight))
            weighted = weighted + (value * cappedWeight)
            totalWeight = totalWeight + cappedWeight
            totalPct = totalPct + weight
            inliers = inliers + 1
            if deviation > maxDeviation then maxDeviation = deviation end
        end
    end

    if inliers <= 0 or totalWeight <= 0 then
        state.estimate = nil
        state.confidence = CONF_LOW
        state.spread = nil
        return
    end

    state.estimate = weighted / totalWeight
    state.spread = maxDeviation

    if inliers >= 3 and maxDeviation <= HIGH_SPREAD then
        state.confidence = CONF_HIGH
    elseif inliers >= 2 and maxDeviation <= CONSISTENT_SPREAD then
        state.confidence = CONF_MEDIUM
    elseif inliers == 1 and totalPct >= 8 then
        -- One large percentage transition has relatively little rounding error,
        -- and is useful enough to make world-PvP prediction available quickly.
        state.confidence = CONF_MEDIUM
    else
        state.confidence = CONF_LOW
    end
end

local function PushEstimate(state, estimate, pctDelta, now)
    if not estimate or estimate < MIN_ESTIMATED_HEALTH or estimate > MAX_ESTIMATED_HEALTH then return end
    state.n = (state.n or 0) + 1
    local slot = ((state.n - 1) % MAX_SAMPLES) + 1
    state.values[slot] = estimate
    state.weights[slot] = pctDelta
    state.seen = now
    RecomputeEstimate(state)
end

local function ObserveState(state, unit, now)
    if not state or not unit or not UnitExists(unit) then return end
    if UnitGUID(unit) ~= state.guid then return end

    local pct = ReadPercent(unit)
    if pct == nil then return end
    state.unit = unit
    state.seen = now

    if state.lastPct == nil then
        state.lastPct = pct
        state.lastPctAt = now
        ClearPending(state)
        return
    end

    local pctDelta = state.lastPct - pct -- positive == health lost
    if abs(pctDelta) < 0.001 then
        -- A combat event may arrive before the client advances the visible
        -- percentage. Keep its pending net change for the subsequent update.
        if state.pendingSince and (now - state.pendingSince) > MATCH_WINDOW then
            ClearPending(state)
            state.lastPct = pct
            state.lastPctAt = now
        end
        return
    end

    local pending = state.pendingNet or 0
    local pendingAge = state.pendingSince and (now - state.pendingSince) or nil

    if pending ~= 0 and pendingAge and pendingAge <= MATCH_WINDOW
        and (pending * pctDelta) > 0 and abs(pctDelta) >= MIN_PERCENT_DELTA then
        local estimate = abs(pending) * 100 / abs(pctDelta)
        PushEstimate(state, estimate, abs(pctDelta), now)
        state.lastPct = pct
        state.lastPctAt = now
        ClearPending(state)
        return
    end

    if pending ~= 0 then
        -- A visible transition occurred but the accumulated combat-log delta
        -- cannot explain it (regen, max-health change, missed event, or timing
        -- mismatch). Reject the sample and start from the new visible baseline.
        state.lastPct = pct
        state.lastPctAt = now
        ClearPending(state)
        return
    end

    -- Health moved before the matching CLEU reached this handler. Hold the old
    -- baseline briefly; OnCombatLog calls ObserveState again after accumulating
    -- the event, allowing either event ordering to produce the same sample.
    if (now - (state.lastPctAt or now)) > MATCH_WINDOW then
        state.lastPct = pct
        state.lastPctAt = now
        ClearPending(state)
    end
end

local function HealthDeltaFromCombatLog(e)
    local sub = e[2]
    if sub == "SWING_DAMAGE" then
        return tonumber(e[12]) or 0
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        return tonumber(e[13]) or 0
    elseif sub == "RANGE_DAMAGE" or sub == "SPELL_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE" then
        return tonumber(e[15]) or 0
    elseif sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL" then
        local amount = tonumber(e[15]) or 0
        local overheal = tonumber(e[16]) or 0
        return -max(0, amount - overheal)
    end
    return nil
end

local function OnCombatLog(e)
    local destGUID = e[8]
    if not destGUID then return end

    local sub = e[2]
    if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        states[destGUID] = nil
        return
    end

    local state = states[destGUID]
    if not state then return end

    local delta = HealthDeltaFromCombatLog(e)
    if not delta or delta == 0 then return end

    local now = GetTime()
    if (now - (state.seen or now)) > STALE_BASELINE then
        -- The token was not observed recently enough to safely associate the
        -- next health movement with its old percentage baseline.
        if state.unit and UnitExists(state.unit) and UnitGUID(state.unit) == destGUID then
            state.lastPct = ReadPercent(state.unit)
            state.lastPctAt = now
        end
        ClearPending(state)
        state.seen = now
        return
    end

    if not state.pendingSince then state.pendingSince = now end
    state.pendingNet = (state.pendingNet or 0) + delta
    state.pendingEvents = (state.pendingEvents or 0) + 1

    -- UnitHealthPercent(..., true) can already reflect the CLEU event before a
    -- UNIT_HEALTH callback is delivered, so attempt the observation immediately.
    if state.unit and UnitExists(state.unit) and UnitGUID(state.unit) == destGUID then
        ObserveState(state, state.unit, now)
    end
end

function PHE:GetHealthBasis(unit)
    if not unit or not UnitExists(unit) then return nil, nil, "UNKNOWN", "missing" end

    local current = UnitHealth(unit) or 0
    local maximum = UnitHealthMax(unit) or 0
    if not IsPercentageOnlyEnemyPlayer(unit) then
        if current <= 0 or maximum <= 0 then return nil, nil, "UNKNOWN", "native" end
        return current, maximum, "EXACT", "native"
    end

    local guid = UnitGUID(unit)
    if not guid then return nil, nil, "UNKNOWN", "percentage" end
    local now = GetTime()
    local pct = ReadPercent(unit)
    if pct == nil then return nil, nil, "UNKNOWN", "percentage" end

    local state = states[guid]
    if not state then
        state = NewState(unit, guid, pct, now)
    else
        state.unit = unit
        ObserveState(state, unit, now)
    end

    if state.estimate and state.confidence >= CONF_MEDIUM then
        local estimatedCurrent = state.estimate * (pct / 100)
        return estimatedCurrent, state.estimate, CONF_LABEL[state.confidence], "estimated"
    end

    return nil, nil, CONF_LABEL[state.confidence or CONF_UNKNOWN], "percentage"
end

function PHE:GetDebugInfo(unit)
    if not unit or not UnitExists(unit) then return { source = "missing", confidence = "UNKNOWN" } end
    local guid = UnitGUID(unit)
    local pct = IsPercentageOnlyEnemyPlayer(unit) and ReadPercent(unit) or nil
    local state = guid and states[guid] or nil
    if not state then
        return {
            source = pct and "percentage" or "native",
            confidence = pct and "UNKNOWN" or "EXACT",
            percent = pct,
        }
    end
    return {
        source = state.estimate and "estimated" or "percentage",
        confidence = CONF_LABEL[state.confidence or CONF_UNKNOWN],
        percent = pct,
        estimatedMax = state.estimate,
        samples = min(state.n or 0, MAX_SAMPLES),
        spread = state.spread,
        pendingNet = state.pendingNet or 0,
    }
end

function PHE:Reset()
    wipe(states)
end

function PHE:SetEnabled(want)
    want = want == true
    if want == enabled then return end
    enabled = want
    if want then
        if ns.CLEU then ns.CLEU:Register(OnCombatLog, HEALTH_CLEU_EVENTS) end
    else
        if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
        self:Reset()
    end
end

function PHE:IsEnabled()
    return enabled
end

ns.RegisterCPUProfileTarget("Combat/PvPHealthEstimate:CLEU", OnCombatLog)
