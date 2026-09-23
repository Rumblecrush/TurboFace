local _, ns = ...

-- =============================================================================
-- TurboFace Heal Prediction engine
--
-- Comms-free incoming-heal prediction for TurboFace unit frames.
--
-- DESIGN
--   * Direct incoming heals come from Blizzard's UnitGetIncomingHeals API.
--   * Direct heals are split by caster when Blizzard exposes that attribution.
--   * HoTs contribute ONLY their next scheduled tick, matching the useful
--     near-term semantics used by HealBarsClassic rather than treating an entire
--     HoT duration as immediately available health.
--   * Helpful auras are authoritative for whether normal HoTs still exist.
--   * SPELL_PERIODIC_HEAL is authoritative for what a HoT tick actually healed.
--   * HoT state is keyed target -> caster -> spell so identical HoTs from two
--     casters never overwrite one another.
--   * This file owns no textures or Blizzard frame mutations. UnitFrames/UnitFrames.lua is
--     only a renderer/consumer.
-- =============================================================================

local HP = {}
ns.HealPrediction = HP

local UnitGUID      = UnitGUID
local UnitExists    = UnitExists
local UnitHealth    = ns.API.ReadUnitHealth
local UnitHealthMax = ns.API.ReadUnitHealthMax
local UnitClass     = UnitClass
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitGetIncomingHeals = ns.API.ReadUnitIncomingHeals
local GetTime       = GetTime
local floor         = math.floor
local max           = math.max
local min           = math.min
local abs           = math.abs

local UnitBuff = ns.API and ns.API.UnitBuff or UnitBuff

local DEFAULT_INTERVAL = 3
local MIN_INTERVAL = 0.75
local MAX_INTERVAL = 12
local TICK_EPSILON = 0.25
local CACHE_TTL = 0.05
local TRANSIENT_GRACE = 0.55
local HOT_TTL = 30

-- In-game Classic Era aura ranks cross-checked against TurboFace's bundled
-- LibClassicDurations data. Values are the unmodified base amount of ONE tick;
-- observed combat-log ticks replace these estimates as soon as available.
local HOT_DATA = {
    -- Priest: Renew (3s)
    [139] = { interval = 3, baseTick = 9 },
    [6074] = { interval = 3, baseTick = 20 },
    [6075] = { interval = 3, baseTick = 35 },
    [6076] = { interval = 3, baseTick = 49 },
    [6077] = { interval = 3, baseTick = 63 },
    [6078] = { interval = 3, baseTick = 80 },
    [10927] = { interval = 3, baseTick = 102 },
    [10928] = { interval = 3, baseTick = 130 },
    [10929] = { interval = 3, baseTick = 162 },
    [25315] = { interval = 3, baseTick = 194 },
    [22009] = { interval = 3, baseTick = 13 }, -- T2 Greater Heal Renew proc

    -- Druid: Rejuvenation (3s)
    [774] = { interval = 3, baseTick = 8 },
    [1058] = { interval = 3, baseTick = 14 },
    [1430] = { interval = 3, baseTick = 29 },
    [2090] = { interval = 3, baseTick = 45 },
    [2091] = { interval = 3, baseTick = 61 },
    [3627] = { interval = 3, baseTick = 76 },
    [8910] = { interval = 3, baseTick = 97 },
    [9839] = { interval = 3, baseTick = 122 },
    [9840] = { interval = 3, baseTick = 152 },
    [9841] = { interval = 3, baseTick = 189 },
    [25299] = { interval = 3, baseTick = 222 },

    -- Druid: Regrowth HoT (3s, Classic Era ranks)
    [8936] = { interval = 3, baseTick = 14 },
    [8938] = { interval = 3, baseTick = 25 },
    [8939] = { interval = 3, baseTick = 37 },
    [8940] = { interval = 3, baseTick = 49 },
    [8941] = { interval = 3, baseTick = 61 },
    [9750] = { interval = 3, baseTick = 78 },
    [9856] = { interval = 3, baseTick = 98 },
    [9857] = { interval = 3, baseTick = 123 },
    [9858] = { interval = 3, baseTick = 152 },

    -- Hunter: Mend Pet (1s in Classic Era)
    [136] = { interval = 1, baseTick = 20 },
    [3111] = { interval = 1, baseTick = 38 },
    [3661] = { interval = 1, baseTick = 68 },
    [3662] = { interval = 1, baseTick = 103 },
    [13542] = { interval = 1, baseTick = 142 },
    [13543] = { interval = 1, baseTick = 189 },
    [13544] = { interval = 1, baseTick = 245 },

    -- Druid: Tranquility channel. No pre-first-tick amount is fabricated; this
    -- metadata only gives the correct cadence once the first periodic heal lands.
    [740] = { interval = 2 },
    [8918] = { interval = 2 },
    [9862] = { interval = 2 },
    [9863] = { interval = 2 },
    [25817] = { interval = 2 },
}

local POH_SPELLS = {
    [596] = true, [996] = true, [10960] = true, [10961] = true, [25316] = true,
}

-- Used only to estimate a HoT before its first observed periodic tick. This does
-- NOT attempt to simulate healing coefficients. A native incoming direct-heal
-- amount divided by the spell's base average gives a lightweight caster ratio;
-- the first actual HoT tick immediately supersedes the estimate.
local CALIBRATION_HEALS = {
    -- Priest
    [2061]=193,[9472]=258,[9473]=327,[9474]=400,[10915]=518,[10916]=644,[10917]=812,
    [2050]=45,[2052]=71,[2053]=135,
    [2054]=295,[2055]=429,[6063]=566,[6064]=712,
    [2060]=899,[10963]=1149,[10964]=1437,[10965]=1798,[25314]=1966,
    [596]=301,[996]=444,[10960]=657,[10961]=939,[25316]=1041,
    -- Paladin
    [635]=39,[639]=76,[647]=159,[1026]=310,[1042]=491,[3472]=698,[10328]=945,[10329]=1246,[25292]=1590,
    [19750]=62,[19939]=96,[19940]=145,[19941]=197,[19942]=267,[19943]=343,
    -- Shaman
    [331]=34,[332]=64,[547]=129,[913]=268,[939]=376,[959]=536,[8005]=740,[10395]=1017,[10396]=1367,[25357]=1620,
    [8004]=162,[8008]=247,[8010]=337,[10466]=458,[10467]=631,[10468]=832,
    [1064]=320,[10622]=405,[10623]=551,
    -- Druid
    [5185]=37,[5186]=88,[5187]=189,[5188]=363,[5189]=572,[6778]=742,[8903]=936,[9758]=1199,[9888]=1516,[9889]=1890,[25297]=2267,
    [8936]=82,[8938]=164,[8939]=240,[8940]=318,[8941]=405,[9750]=511,[9856]=646,[9857]=809,[9858]=1003,
}

local TRACKED_UNITS = {
    "player", "target", "targettarget", "pet",
    "party1", "party2", "party3", "party4",
}

-- hotState[targetGUID][casterGUID][spellID] = state
local hotState = {}
local casterRatios = {}
local runtimePeriodicSpells = {}
local unitCache = {}
local lastAuraScan = {}
local consumers = {}
local rosterUnits = {}
local rosterByGUID = {}
local rosterSubgroup = {}
local activeAoECasts = {}
local nativeByCasterScratch = {}
local registered = false
local CLEU_EVENTS = {
    UNIT_DIED = true, UNIT_DESTROYED = true, SPELL_AURA_REMOVED = true,
    SPELL_PERIODIC_HEAL = true,
}

local ZERO_PREDICTION = {
    total = 0, direct = 0, hot = 0, segmentCount = 0,
    segments = {},
}

local DB = ns.DB   -- shared root accessor (Config.lua)

local function Enabled()
    return DB().healPredictionEnabled == true
        and (not ns.caps or ns.caps.healPrediction ~= false)
        and type(UnitGetIncomingHeals) == "function"
end

local function ShowUnit(unit)
    if not Enabled() then return false end
    -- Prediction textures attach directly to Blizzard's native health bars.
    -- TurboFace Unit Frames styling may be disabled without disabling prediction.
    local db = DB()
    if unit == "player" then return db.healPredictionPlayer ~= false end
    if unit == "target" then return db.healPredictionTarget ~= false end
    if unit == "targettarget" then return db.healPredictionToT ~= false end
    if unit == "pet" then return db.healPredictionPet ~= false end
    if type(unit) == "string" and string.match(unit, "^party%d+$") then
        return db.healPredictionParty ~= false
    end
    return false
end

local function RuntimeNeeded()
    for i = 1, #TRACKED_UNITS do
        if ShowUnit(TRACKED_UNITS[i]) then return true end
    end
    return false
end

local function FindTrackedUnitByGUID(guid)
    if not guid then return nil end
    for i = 1, #TRACKED_UNITS do
        local unit = TRACKED_UNITS[i]
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end
    return nil
end

local function RebuildRoster()
    wipe(rosterUnits)
    wipe(rosterByGUID)
    wipe(rosterSubgroup)

    local function Add(unit, subgroup)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid or rosterByGUID[guid] then return end
        rosterByGUID[guid] = unit
        if subgroup then rosterSubgroup[guid] = subgroup end
        rosterUnits[#rosterUnits + 1] = unit
    end

    if IsInRaid and IsInRaid() then
        local raidCount = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, raidCount do
            local subgroup = nil
            if GetRaidRosterInfo then
                local _, _, sg = GetRaidRosterInfo(i)
                subgroup = sg
            end
            Add("raid" .. i, subgroup)
        end
        -- Pet is useful as a possible caster for native attribution, but Prayer
        -- of Healing must never treat it as a subgroup target.
        Add("pet", nil)
    else
        Add("player", 1)
        local partyCount = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, partyCount do Add("party" .. i, 1) end
        Add("pet", nil)
    end
end

local function GetHotState(targetGUID, casterGUID, spellID, create)
    local byCaster = hotState[targetGUID]
    if not byCaster then
        if not create then return nil end
        byCaster = {}
        hotState[targetGUID] = byCaster
    end
    local bySpell = byCaster[casterGUID]
    if not bySpell then
        if not create then return nil end
        bySpell = {}
        byCaster[casterGUID] = bySpell
    end
    local state = bySpell[spellID]
    if not state and create then
        local data = HOT_DATA[spellID]
        state = {
            interval = data and data.interval or DEFAULT_INTERVAL,
            tickEstimate = nil,
            lastTickTime = 0,
            nextTickTime = nil,
            expirationTime = 0,
            transientUntil = 0,
            auraBound = false,
            seen = false,
            updatedAt = GetTime(),
        }
        bySpell[spellID] = state
    end
    return state
end

local function RemoveHotState(targetGUID, casterGUID, spellID)
    local byCaster = hotState[targetGUID]
    local bySpell = byCaster and byCaster[casterGUID]
    if not bySpell then return end
    bySpell[spellID] = nil
    if not next(bySpell) then byCaster[casterGUID] = nil end
    if not next(byCaster) then hotState[targetGUID] = nil end
end

local function SeedTickEstimate(state, casterGUID, spellID)
    -- Until a real ordinary tick has been observed, keep the base estimate in
    -- sync with any better caster calibration learned from native direct heals.
    if state.observedTick then return end
    local data = HOT_DATA[spellID]
    if not data or not data.baseTick then return end
    local ratio = casterRatios[casterGUID] or 1
    state.tickEstimate = data.baseTick * ratio
end

local function AlignNextTickFromExpiration(expiration, interval, now)
    if not expiration or expiration <= now or not interval or interval <= 0 then return nil end
    local remaining = expiration - now
    local periods = floor(remaining / interval)
    local nextTick = expiration - (periods * interval)
    if nextTick <= (now + 0.02) then nextTick = nextTick + interval end
    if nextTick > (expiration + TICK_EPSILON) then return nil end
    return nextTick
end

local function ResolveNextTick(state, now)
    local interval = state.interval or DEFAULT_INTERVAL
    local expiration = state.expirationTime

    if state.lastTickTime and state.lastTickTime > 0 then
        local elapsed = max(0, now - state.lastTickTime)
        local periods = floor(elapsed / interval) + 1
        local nextTick = state.lastTickTime + periods * interval
        if not expiration or expiration <= 0 or nextTick <= (expiration + TICK_EPSILON) then
            return nextTick
        end
    end

    if state.nextTickTime and state.nextTickTime > now then
        if not expiration or expiration <= 0 or state.nextTickTime <= (expiration + TICK_EPSILON) then
            return state.nextTickTime
        end
    end

    if expiration and expiration > 0 then
        return AlignNextTickFromExpiration(expiration, interval, now)
    end
    return nil
end

local function NotifyUnit(unit)
    if not unit then return end
    for fn in pairs(consumers) do fn(unit) end
end

local function NotifyGUID(guid)
    local unit = FindTrackedUnitByGUID(guid)
    if unit then NotifyUnit(unit) end
end

local function InvalidateUnit(unit)
    local guid = unit and UnitGUID(unit)
    if guid then unitCache[guid] = nil end
end

local function ScanAuras(unit)
    if not unit or not UnitExists(unit) then return false end
    local now = GetTime()
    if lastAuraScan[unit] == now then return false end
    lastAuraScan[unit] = now

    local targetGUID = UnitGUID(unit)
    if not targetGUID then return false end
    local byCaster = hotState[targetGUID]
    if byCaster then
        for _, bySpell in pairs(byCaster) do
            for _, state in pairs(bySpell) do
                if state.auraBound then state.seen = false end
            end
        end
    end

    local changed = false
    for i = 1, 40 do
        local name, _, _, _, duration, expirationTime, source, _, _, spellID = UnitBuff(unit, i)
        if not name then break end
        if spellID then
            local casterGUID = source and UnitGUID(source)
            local known = HOT_DATA[spellID] or runtimePeriodicSpells[spellID]
            if known and casterGUID then
                local state = GetHotState(targetGUID, casterGUID, spellID, true)
                local wasAuraBound = state.auraBound
                local oldExpiration = state.expirationTime or 0
                state.auraBound = true
                state.seen = true
                state.duration = duration or state.duration or 0
                state.expirationTime = expirationTime or 0
                state.updatedAt = now
                SeedTickEstimate(state, casterGUID, spellID)

                local interval = state.interval or DEFAULT_INTERVAL
                if not state.nextTickTime then
                    state.nextTickTime = AlignNextTickFromExpiration(state.expirationTime, interval, now)
                        or (now + interval)
                elseif oldExpiration > 0 and state.expirationTime > oldExpiration + (interval * 0.5) then
                    -- Refresh/reapplication resets the tick clock for Classic HoTs.
                    state.lastTickTime = 0
                    state.nextTickTime = now + interval
                    changed = true
                end
                if not wasAuraBound then changed = true end
            end
        end
    end

    byCaster = hotState[targetGUID]
    if byCaster then
        local removals = {}
        for casterGUID, bySpell in pairs(byCaster) do
            for spellID, state in pairs(bySpell) do
                if state.auraBound and not state.seen then
                    removals[#removals + 1] = { casterGUID, spellID }
                end
            end
        end
        for i = 1, #removals do
            RemoveHotState(targetGUID, removals[i][1], removals[i][2])
            changed = true
        end
    end

    if changed then unitCache[targetGUID] = nil end
    return changed
end

local function CasterCastInfo(casterUnit)
    if not casterUnit or not UnitExists(casterUnit) then return nil, nil, nil end
    local _, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo(casterUnit)
    if spellID then return spellID, (startMS or 0) / 1000, (endMS or 0) / 1000 end
    local _, _, _, startCMS, endCMS, _, _, channelSpellID = UnitChannelInfo(casterUnit)
    if channelSpellID then return channelSpellID, (startCMS or 0) / 1000, (endCMS or 0) / 1000 end
    return nil, nil, nil
end

local function ValidPrayerOfHealingTarget(casterGUID, targetGUID)
    local casterGroup = rosterSubgroup[casterGUID]
    local targetGroup = rosterSubgroup[targetGUID]
    return casterGroup ~= nil and targetGroup ~= nil and casterGroup == targetGroup
end

local function CalibrateCaster(casterGUID, spellID, amount)
    local base = spellID and CALIBRATION_HEALS[spellID]
    if not base or base <= 0 or not amount or amount <= 0 then return end
    local ratio = amount / base
    -- Defensive clamp: native attribution can occasionally represent more than
    -- one heal; do not let one pathological sample poison all pre-first-tick HoTs.
    if ratio < 0.25 or ratio > 6 then return end
    local old = casterRatios[casterGUID]
    casterRatios[casterGUID] = old and (old * 0.7 + ratio * 0.3) or ratio

    -- A same-frame aura scan may already have seeded a HoT before the native
    -- direct-heal attribution became available. Refresh only unobserved seeds
    -- immediately so the first rendered prediction benefits from calibration.
    for _, byCaster in pairs(hotState) do
        local bySpell = byCaster[casterGUID]
        if bySpell then
            for hotSpellID, state in pairs(bySpell) do
                SeedTickEstimate(state, casterGUID, hotSpellID)
            end
        end
    end
end

local function GetCasterClass(casterUnit, casterGUID)
    if casterUnit and UnitExists(casterUnit) then
        local _, class = UnitClass(casterUnit)
        if class then return class end
    end
    if GetPlayerInfoByGUID and casterGUID then
        local _, class = GetPlayerInfoByGUID(casterGUID)
        return class
    end
    return nil
end

-- Every emitted prediction segment owns an endTime. Keep the sort comparator
-- static so uncached prediction builds do not allocate a new closure.
local function ComparePredictionSegments(a, b)
    local at, bt = a.endTime, b.endTime
    if at == bt then
        if a.kind ~= b.kind then return a.kind == "direct" end
        return (a.amount or 0) > (b.amount or 0)
    end
    return at < bt
end

local function BuildPrediction(unit)
    if not ShowUnit(unit) or not UnitExists(unit) then return ZERO_PREDICTION end

    local targetGUID = UnitGUID(unit)
    if not targetGUID then return ZERO_PREDICTION end
    local now = GetTime()
    local cached = unitCache[targetGUID]
    if cached and cached.unit == unit and (now - cached.time) <= CACHE_TTL then
        return cached.prediction
    end

    local segments = {}
    local totalDirect, totalHot = 0, 0
    local nativeTotal = UnitGetIncomingHeals(unit) or 0
    local attributed = 0
    local nativeByCaster = nativeByCasterScratch
    wipe(nativeByCaster)
    local playerGUID = UnitGUID("player")

    if nativeTotal > 0 then
        for i = 1, #rosterUnits do
            local casterUnit = rosterUnits[i]
            local amount = UnitGetIncomingHeals(unit, casterUnit)
            if amount and amount > 0 then
                local casterGUID = UnitGUID(casterUnit)
                if casterGUID then nativeByCaster[casterGUID] = amount end
                local spellID, startTime, endTime = CasterCastInfo(casterUnit)
                if casterGUID then CalibrateCaster(casterGUID, spellID, amount) end
                local seg = {
                    kind = "direct",
                    amount = amount,
                    casterGUID = casterGUID,
                    casterUnit = casterUnit,
                    class = GetCasterClass(casterUnit, casterGUID),
                    isMine = casterGUID ~= nil and casterGUID == playerGUID,
                    spellID = spellID,
                    startTime = startTime or now,
                    endTime = endTime or now,
                }
                segments[#segments + 1] = seg
                attributed = attributed + amount
                totalDirect = totalDirect + amount
                if attributed >= nativeTotal then break end
            end
        end

        -- Preserve native truth even when the caster is outside our group roster.
        local remainder = nativeTotal - attributed
        if remainder > 0.5 then
            segments[#segments + 1] = {
                kind = "direct", amount = remainder, isMine = false,
                startTime = now, endTime = now,
            }
            totalDirect = totalDirect + remainder
        end
    end

    -- Prayer of Healing is deterministic by subgroup, but Classic's native
    -- incoming-heal API can omit secondary targets. Inject only a missing caster
    -- segment for the caster's subgroup. Chain Heal is deliberately not guessed.
    for i = 1, #rosterUnits do
        local casterUnit = rosterUnits[i]
        local casterGUID = UnitGUID(casterUnit)
        if casterGUID and (nativeByCaster[casterGUID] or 0) <= 0 then
            local spellID, startTime, endTime = CasterCastInfo(casterUnit)
            if spellID and POH_SPELLS[spellID] and ValidPrayerOfHealingTarget(casterGUID, targetGUID) then
                local base = CALIBRATION_HEALS[spellID]
                if base and base > 0 then
                    local amount = base * (casterRatios[casterGUID] or 1)
                    segments[#segments + 1] = {
                        kind = "direct", amount = amount, casterGUID = casterGUID,
                        casterUnit = casterUnit, class = GetCasterClass(casterUnit, casterGUID),
                        isMine = casterGUID == playerGUID, spellID = spellID,
                        startTime = startTime or now, endTime = endTime or now,
                        syntheticAoE = true,
                    }
                    totalDirect = totalDirect + amount
                end
            end
        end
    end

    -- Scan after direct attribution/calibration so a newly observed HoT can use
    -- the caster ratio learned from the heal that is currently in flight.
    if DB().healPredictionHots ~= false then ScanAuras(unit) end

    if DB().healPredictionHots ~= false then
        local byCaster = hotState[targetGUID]
        if byCaster then
            for casterGUID, bySpell in pairs(byCaster) do
                for spellID, state in pairs(bySpell) do
                    local valid = true
                    if state.auraBound then
                        valid = state.expirationTime and state.expirationTime > now
                    elseif state.transientUntil and state.transientUntil > 0 then
                        valid = state.transientUntil > now
                    elseif (now - (state.updatedAt or 0)) > HOT_TTL then
                        valid = false
                    end

                    if valid and state.tickEstimate and state.tickEstimate > 0 then
                        local nextTick = ResolveNextTick(state, now)
                        local expiration = state.expirationTime or 0
                        if nextTick and (expiration <= 0 or nextTick <= expiration + TICK_EPSILON) then
                            local casterUnit = rosterByGUID[casterGUID]
                            local seg = {
                                kind = "hot_tick",
                                amount = state.tickEstimate,
                                casterGUID = casterGUID,
                                casterUnit = casterUnit,
                                class = GetCasterClass(casterUnit, casterGUID),
                                isMine = casterGUID == playerGUID,
                                spellID = spellID,
                                startTime = nextTick,
                                endTime = nextTick,
                                nextTickTime = nextTick,
                                interval = state.interval,
                                expirationTime = expiration,
                            }
                            segments[#segments + 1] = seg
                            totalHot = totalHot + state.tickEstimate
                        end
                    end
                end
            end
        end
    end

    table.sort(segments, ComparePredictionSegments)

    local prediction = {
        total = totalDirect + totalHot,
        direct = totalDirect,
        hot = totalHot,
        segmentCount = #segments,
        segments = segments,
        nativeDirect = nativeTotal,
    }
    unitCache[targetGUID] = { time = now, unit = unit, prediction = prediction }
    return prediction
end

local function CleanupDeadHealGUID(guid)
    if guid then
        hotState[guid] = nil
        unitCache[guid] = nil
        NotifyGUID(guid)
    end
end

local function OnCombatLog(e)
    local sub = e[2]
    local sourceGUID, destGUID, spellID = e[4], e[8], e[12]

    if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("HealPrediction:DeathCleanup", CleanupDeadHealGUID, destGUID)
        else
            CleanupDeadHealGUID(destGUID)
        end
        return
    end

    if sub == "SPELL_AURA_REMOVED" then
        if sourceGUID and destGUID and spellID then
            local state = GetHotState(destGUID, sourceGUID, spellID, false)
            if state then
                RemoveHotState(destGUID, sourceGUID, spellID)
                unitCache[destGUID] = nil
                NotifyGUID(destGUID)
            end
        end
        return
    end

    if sub ~= "SPELL_PERIODIC_HEAL" then return end
    local amount = e[15]
    if not sourceGUID or not destGUID or not spellID or type(amount) ~= "number" or amount <= 0 then return end

    runtimePeriodicSpells[spellID] = true
    local now = GetTime()
    local state = GetHotState(destGUID, sourceGUID, spellID, true)
    local data = HOT_DATA[spellID]
    local baseline = state.interval or (data and data.interval) or DEFAULT_INTERVAL

    if state.lastTickTime and state.lastTickTime > 0 then
        local delta = now - state.lastTickTime
        if delta >= MIN_INTERVAL and delta <= MAX_INTERVAL then
            -- Fold a clean missed-tick multiple back toward the existing cadence.
            if baseline and delta > baseline * 1.5 then
                local multiple = floor(delta / baseline + 0.5)
                if multiple >= 2 and multiple <= 6 then
                    local folded = delta / multiple
                    if abs(folded - baseline) <= max(0.25, baseline * 0.2) then delta = folded end
                end
            end
            if not baseline or abs(delta - baseline) <= max(0.5, baseline * 0.4) then
                state.interval = baseline and (baseline * 0.8 + delta * 0.2) or delta
            end
        end
    end

    state.lastTickTime = now
    state.nextTickTime = now + (state.interval or DEFAULT_INTERVAL)
    state.updatedAt = now
    if not state.auraBound then
        state.transientUntil = state.nextTickTime + TRANSIENT_GRACE
    end

    -- A critical periodic heal is valid timing evidence but a poor prediction for
    -- the ordinary next tick. Keep the prior/base estimate in that case.
    local isCrit = e[21] == true or e[21] == 1
    if not isCrit or not state.tickEstimate then
        -- The game's actual non-critical tick is the best estimate for the next
        -- ordinary tick; unlike cadence, there is little value in lagging behind
        -- a real modifier change with a moving average.
        state.tickEstimate = amount
        if not isCrit then state.observedTick = true end
    end

    unitCache[destGUID] = nil
    NotifyGUID(destGUID)
end

function HP:GetPrediction(unit)
    return BuildPrediction(unit)
end

function HP:GetSegments(unit)
    local prediction = BuildPrediction(unit)
    return prediction.segments or ZERO_PREDICTION.segments, prediction
end

function HP:ShowOnUnit(unit)
    return ShowUnit(unit)
end

function HP:RuntimeNeeded()
    return RuntimeNeeded()
end

function HP:GetOverhealFraction()
    local value = tonumber(DB().healPredictionOverheal) or 0
    return max(0, min(1, value))
end

function HP:GetMaxSegments()
    local value = floor(tonumber(DB().healPredictionMaxSegments) or 6)
    return max(1, min(10, value))
end

function HP:GetMinFraction()
    local value = tonumber(DB().healPredictionMinPercent) or 0
    return max(0, min(0.25, value / 100))
end

function HP:GetColor(segment)
    local db = DB()
    local isHot = segment and segment.kind == "hot_tick"
    local isMine = segment and segment.isMine
    local color

    if db.healPredictionSeparateOwn ~= false and isMine then
        if isHot and db.healPredictionSeparateHots ~= false then
            color = db.healPredictionOwnHotColor
        else
            color = db.healPredictionOwnColor
        end
    elseif isHot and db.healPredictionSeparateHots ~= false then
        color = db.healPredictionHotColor
    else
        color = db.healPredictionColor
    end

    color = color or { r = 0.25, g = 1.0, b = 0.25 }
    local r, g, b = color.r or 0.25, color.g or 1, color.b or 0.25

    if db.healPredictionCasterTint == true and segment and not segment.isMine and segment.class then
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[segment.class]
        if classColor then r, g, b = classColor.r, classColor.g, classColor.b end
    end

    local a = tonumber(db.healPredictionAlpha) or 0.65
    return r, g, b, max(0.1, min(1, a))
end

function HP:RegisterConsumer(fn)
    if fn then consumers[fn] = true end
end

function HP:RefreshUnit(unit)
    if not unit then return end
    InvalidateUnit(unit)
    if ShowUnit(unit) and UnitExists(unit) and DB().healPredictionHots ~= false then ScanAuras(unit) end
    NotifyUnit(unit)
end

local function RefreshTrackedAliases(unit)
    local guid = unit and UnitGUID(unit)
    if not guid then return end
    for i = 1, #TRACKED_UNITS do
        local tracked = TRACKED_UNITS[i]
        if UnitExists(tracked) and UnitGUID(tracked) == guid then
            HP:RefreshUnit(tracked)
        end
    end
end

function HP:RefreshAll()
    for i = 1, #TRACKED_UNITS do
        local unit = TRACKED_UNITS[i]
        InvalidateUnit(unit)
        if UnitExists(unit) then
            if ShowUnit(unit) and DB().healPredictionHots ~= false then ScanAuras(unit) end
            NotifyUnit(unit)
        else
            NotifyUnit(unit)
        end
    end
end

function HP:Reset()
    wipe(hotState)
    wipe(unitCache)
    wipe(lastAuraScan)
    wipe(casterRatios)
    wipe(runtimePeriodicSpells)
    wipe(activeAoECasts)
end

function HP:Init()
    RebuildRoster()
    if not self._eventFrame then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_ENTERING_WORLD" then
                wipe(hotState)
                wipe(unitCache)
                wipe(lastAuraScan)
                RebuildRoster()
                HP:RefreshAll()
                return
            end

            if event == "GROUP_ROSTER_UPDATE" then
                RebuildRoster()
                wipe(unitCache)
                HP:RefreshAll()
                return
            end

            if event == "PLAYER_REGEN_ENABLED" then
                HP:RefreshAll()
                return
            end

            if event == "PLAYER_TARGET_CHANGED" then
                HP:RefreshUnit("target")
                HP:RefreshUnit("targettarget")
                return
            end

            if event == "UNIT_TARGET" and unit == "target" then
                HP:RefreshUnit("targettarget")
                return
            end

            if event == "UNIT_PET" then
                RebuildRoster()
                HP:RefreshUnit("pet")
                return
            end

            if event == "UNIT_SPELLCAST_START" then
                local guid = unit and UnitGUID(unit)
                if guid and rosterByGUID[guid] then
                    local spellID = CasterCastInfo(unit)
                    if spellID and POH_SPELLS[spellID] then
                        activeAoECasts[guid] = true
                        HP:RefreshAll()
                    end
                end
                return
            end

            if event == "UNIT_SPELLCAST_DELAYED" then
                local guid = unit and UnitGUID(unit)
                if guid and activeAoECasts[guid] then HP:RefreshAll() end
                return
            end

            if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
                or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
                local guid = unit and UnitGUID(unit)
                if guid and activeAoECasts[guid] then
                    activeAoECasts[guid] = nil
                    HP:RefreshAll()
                end
                return
            end

            if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_AURA" or event == "UNIT_MAXHEALTH" then
                -- The client may fire an event for raid1 while the same GUID is
                -- also displayed as target. Refresh every TurboFace-rendered unit
                -- token that aliases the changed GUID rather than assuming the
                -- event token itself is one of our frame tokens.
                RefreshTrackedAliases(unit)
            end
        end)
        self._eventFrame = f
        ns.RegisterCPUProfileTarget("Combat/HealPrediction:Events", f:GetScript("OnEvent"))
    end
    self:Refresh()
end

function HP:Refresh()
    local on = RuntimeNeeded()
    local f = self._eventFrame

    if on and not registered then
        if ns.CLEU then ns.CLEU:Register(OnCombatLog, CLEU_EVENTS) end
        if f then
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
            f:RegisterEvent("GROUP_ROSTER_UPDATE")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:RegisterEvent("PLAYER_TARGET_CHANGED")
            ns.RegisterUnitEvent(f, "UNIT_TARGET", "target")
            f:RegisterEvent("UNIT_SPELLCAST_START")
            f:RegisterEvent("UNIT_SPELLCAST_DELAYED")
            f:RegisterEvent("UNIT_SPELLCAST_STOP")
            f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
            f:RegisterEvent("UNIT_SPELLCAST_FAILED")
            f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            f:RegisterEvent("UNIT_HEAL_PREDICTION")
            f:RegisterEvent("UNIT_AURA")
            f:RegisterEvent("UNIT_MAXHEALTH")
            f:RegisterUnitEvent("UNIT_PET", "player")
        end
        registered = true
        RebuildRoster()
    elseif not on and registered then
        if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
        if f then f:UnregisterAllEvents() end
        registered = false
        wipe(unitCache)
        wipe(activeAoECasts)
    end

    self:RefreshAll()
end

ns.RegisterCPUProfileTarget("Combat/HealPrediction:CLEU", OnCombatLog)
