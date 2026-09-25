local _, ns = ...

-- =============================================================================
-- TurboFace DoT prediction engine
--
-- Empirical periodic-damage predictor shared by nameplates and unit frames.
--
-- DESIGN
--   * Aura data is authoritative for whether a DoT currently exists.
--   * The combat log is authoritative for what a tick actually did.
--   * Runtime state is separated by target -> caster -> spell, so timing from a
--     pet, a replaced pet, or a future non-player caster can never collide.
--   * Tick cadence is learned only from successive ticks of the SAME aura
--     instance. Learned intervals are cached by spell ID plus a rank-name fallback
--     across reloads/build-local sessions; damage is intentionally not persisted
--     because gear/modifiers move.
--   * Consumers can ask for both the total damage remaining over the aura(s) and
--     the next periodic wave, following the useful distinction made by
--     HealBarsClassic between "next tick" and "whole duration" prediction.
--
-- The engine owns no frames. Consumers should use GetBarRegion() for the current
-- total-remaining visualization, or GetPrediction() for richer future UI work.
-- =============================================================================

local DP = {}
ns.DotPrediction = DP

local UnitGUID      = UnitGUID
local LCD           = LibStub and LibStub("LibClassicDurations", true)
local UnitExists    = UnitExists
local UnitHealth    = ns.API.ReadUnitHealth
local UnitHealthMax = ns.API.ReadUnitHealthMax
local GetTime       = GetTime
local C_Timer_After = C_Timer and C_Timer.After
local abs           = math.abs
local floor         = math.floor
local max           = math.max
local min           = math.min

local MAX_SAMPLES        = 5
local DEFAULT_INTERVAL   = 3
local MIN_INTERVAL       = 0.8
local MAX_INTERVAL       = 12
local ENTRY_TTL          = 120
local SPELL_SAMPLE_TTL   = 600
local SWEEP_INTERVAL     = 30
local CACHE_TTL          = 0.50 -- safety rescan; UNIT_AURA/ticks invalidate immediately
local TICK_EPSILON       = 0.35
local REFRESH_THRESHOLD  = 0.50 -- fraction of one interval by which expiry must extend
local CRIT_FALLBACK_SCALE = 0.50 -- conservative display-only estimate until a normal tick exists

-- targetState[destGUID][sourceGUID][spellID] = {
--   samples={}, n=0, lastTick=0, nextTick=0, expiration=0, duration=0,
--   active=false, seen=0
-- }
--
-- casterSpell[sourceGUID][spellID] contains damage-only fallback samples. It is
-- deliberately NOT used to learn cadence: interleaved ticks on different mobs
-- are not an interval and were the main correctness flaw in the first engine.
local targetState = {}
local casterSpell = {}
local spellTiming = {}
local projCache   = {}

local playerGUID, petGUID
local registered = false
local CLEU_EVENTS = { SPELL_PERIODIC_DAMAGE = true, UNIT_DIED = true, UNIT_DESTROYED = true }
local lastSweep = 0

local consumers = {}
local NotifyUnit
local medianScratch = {}

-- Nameplate-specific safety reconciliation. UNIT_AURA can arrive before a pooled
-- Blizzard nameplate has finished binding into TurboFace's unit/GUID maps, and
-- native health-bar geometry can settle a frame after NAME_PLATE_UNIT_ADDED. One
-- deduplicated 50 ms retry closes both races without introducing a permanent poll.
local NAMEPLATE_RECONCILE_DELAY = 0.05
local nameplateReconcileUnits = {} -- [unit] = GUID captured when queued
local nameplateReconcilePending = false
local dotNameplateGUIDs = {} -- minimal lifecycle identity when Nameplates enhancements are off
local ZERO_PREDICTION = {
    remainingDamage = 0, dotCount = 0, activeDotCount = 0,
    nextTickDamage = 0, nextEventDamage = 0, nextEventTime = nil,
}

local DB = ns.DB   -- shared root accessor (Config.lua)
local PvPHealth = ns.PvPHealthEstimate

local function Enabled()
    if ns.Client and ns.Client.IsSettingDevelopmentRestricted
        and ns.Client:IsSettingDevelopmentRestricted("dotPredictionEnabled") then
        return false
    end
    return DB().dotPredictionEnabled == true
end

-- Party DoT inclusion.
--
-- Scoped to party1-4 and their pets ON PURPOSE -- open party and dungeon play,
-- not raids. Raid tokens are deliberately absent: a raid boss can carry far
-- more DoTs than Classic Era's 16-debuff cap can even report, so the sum would
-- be silently short and the lethal colour would lie in exactly the situation
-- where it matters most. A 5-man never gets near that ceiling.
local PARTY_TOKENS = {}
for i = 1, 4 do
    PARTY_TOKENS["party" .. i] = true
    PARTY_TOKENS["partypet" .. i] = true
end

local partyGUIDs = {}

local function IncludeParty()
    return DB().dotPredictionIncludeParty == true
end

local function RefreshPartyGUIDs()
    wipe(partyGUIDs)
    if not registered or not IncludeParty() then return end
    for token in pairs(PARTY_TOKENS) do
        local guid = UnitExists(token) and UnitGUID(token)
        if guid then partyGUIDs[guid] = true end
    end
end

local function IsPartyGUID(guid)
    return guid ~= nil and partyGUIDs[guid] == true
end

-- LibClassicDurations only tracks the combat log while at least one consumer
-- has called RegisterFrame -- TurboFace's own modification, see the note at the
-- top of Libs/LibClassicDurations/core.lua, so embedding the library costs
-- nothing for addons that do not use it.
--
-- Merely holding a LibStub handle is NOT enough: without this registration
-- GetAuraDurationByGUID has nothing to answer from and every party DoT is
-- silently skipped by the expiry guard in ScanUnit.
--
-- Registered only while the engine has a presentation consumer AND party
-- inclusion is on. A saved option alone must not keep the library collecting
-- when neither prediction surface needs it (§1.4).
local lcdFrame
local lcdRegistered = false

local function SyncDurationLib()
    if not LCD or not LCD.RegisterFrame then return end
    local want = registered and IncludeParty()
    if want == lcdRegistered then return end
    lcdFrame = lcdFrame or CreateFrame("Frame")
    local ok
    if want then
        ok = pcall(LCD.RegisterFrame, LCD, lcdFrame)
    else
        ok = pcall(LCD.UnregisterFrame, LCD, lcdFrame)
    end
    if ok then lcdRegistered = want end
end

local function NewDamageEntry()
    return {
        samples = {}, n = 0,
        critSamples = {}, cn = 0,
        lastTick = 0, nextTick = 0,
        expiration = 0, duration = 0,
        active = false, seen = 0,
    }
end

local function NewSampleEntry()
    return { samples = {}, n = 0, critSamples = {}, cn = 0, seen = 0 }
end

local function NewTimingEntry()
    return { intervals = {}, ni = 0, seen = 0 }
end

local function SampleCount(entry)
    return min(entry and entry.n or 0, MAX_SAMPLES)
end

local function CriticalSampleCount(entry)
    return min(entry and entry.cn or 0, MAX_SAMPLES)
end

local function IntervalCount(entry)
    return min(entry and entry.ni or 0, MAX_SAMPLES)
end

-- MAX_SAMPLES is tiny. Reuse one scratch table instead of allocating a sorted
-- copy every time a nameplate asks for a prediction.
local function Median(list, count)
    if not list or not count or count <= 0 then return nil end
    for i = 1, count do medianScratch[i] = list[i] end
    for i = count + 1, MAX_SAMPLES do medianScratch[i] = nil end
    table.sort(medianScratch)
    return medianScratch[math.ceil(count / 2)]
end

local function PushSample(entry, amount, now)
    entry.n = entry.n + 1
    local slot = ((entry.n - 1) % MAX_SAMPLES) + 1
    entry.samples[slot] = amount
    entry.seen = now
end

local function PushCriticalSample(entry, amount, now)
    entry.cn = entry.cn + 1
    local slot = ((entry.cn - 1) % MAX_SAMPLES) + 1
    entry.critSamples[slot] = amount * CRIT_FALLBACK_SCALE
    entry.seen = now
end

local function PushInterval(entry, delta, now)
    if delta < MIN_INTERVAL or delta > MAX_INTERVAL then return false end
    entry.ni = entry.ni + 1
    local slot = ((entry.ni - 1) % MAX_SAMPLES) + 1
    entry.intervals[slot] = delta
    entry.seen = now
    return true
end

local function GetTargetEntry(destGUID, sourceGUID, spellID, create)
    local byCaster = targetState[destGUID]
    if not byCaster then
        if not create then return nil end
        byCaster = {}
        targetState[destGUID] = byCaster
    end

    local bySpell = byCaster[sourceGUID]
    if not bySpell then
        if not create then return nil end
        bySpell = {}
        byCaster[sourceGUID] = bySpell
    end

    local entry = bySpell[spellID]
    if not entry and create then
        entry = NewDamageEntry()
        bySpell[spellID] = entry
    end
    return entry
end

local function GetCasterSpellEntry(sourceGUID, spellID, create)
    local bySpell = casterSpell[sourceGUID]
    if not bySpell then
        if not create then return nil end
        bySpell = {}
        casterSpell[sourceGUID] = bySpell
    end
    local entry = bySpell[spellID]
    if not entry and create then
        entry = NewSampleEntry()
        bySpell[spellID] = entry
    end
    return entry
end

local function GetTimingEntry(spellID, create)
    local entry = spellTiming[spellID]
    if not entry and create then
        entry = NewTimingEntry()
        spellTiming[spellID] = entry
    end
    return entry
end

-- -----------------------------------------------------------------------------
-- Build-local persistent cadence cache
-- -----------------------------------------------------------------------------
local function IntervalCache()
    if type(TurboFaceCacheDB) ~= "table" then return nil, nil end
    if type(TurboFaceCacheDB.dotPredictionIntervals) ~= "table" then
        TurboFaceCacheDB.dotPredictionIntervals = {}
    end
    if type(TurboFaceCacheDB.dotPredictionIntervalNames) ~= "table" then
        TurboFaceCacheDB.dotPredictionIntervalNames = {}
    end
    return TurboFaceCacheDB.dotPredictionIntervals, TurboFaceCacheDB.dotPredictionIntervalNames
end

local function ValidCachedInterval(value)
    if type(value) == "table" then value = value.interval end
    value = tonumber(value)
    if value and value >= MIN_INTERVAL and value <= MAX_INTERVAL then return value end
    return nil
end

local function CachedInterval(spellID, spellName)
    if type(TurboFaceCacheDB) ~= "table" then return nil end

    local byID = TurboFaceCacheDB.dotPredictionIntervals
    local value = byID and ValidCachedInterval(byID[spellID])
    if value then return value, "cache-id" end

    -- Ranks of the same Classic spell normally share cadence. This name fallback
    -- lets a newly trained rank inherit timing without sharing its damage samples.
    local byName = TurboFaceCacheDB.dotPredictionIntervalNames
    if spellName and byName then
        value = ValidCachedInterval(byName[spellName])
        if value then return value, "cache-rank" end
    end
    return nil
end

local function PersistInterval(spellID, spellName, timing)
    if not timing or IntervalCount(timing) < 2 then return end
    local value = Median(timing.intervals, IntervalCount(timing))
    if not value then return end

    local byID, byName = IntervalCache()
    if not byID then return end

    local old = CachedInterval(spellID, spellName)
    -- Do not let a tiny amount of fresh jitter replace a stable cached cadence
    -- with something wildly different. Three current observations are enough to
    -- deliberately relearn it if the client behavior really changed.
    if old and IntervalCount(timing) < 3 then
        local tolerance = max(0.35, old * 0.25)
        if abs(value - old) > tolerance then return end
    end

    local record = { interval = value, samples = timing.ni }
    byID[spellID] = record
    if spellName and spellName ~= "" and byName then
        byName[spellName] = { interval = value, samples = timing.ni }
    end
end

local function ExpectedInterval(spellID, spellName)
    local timing = spellTiming[spellID]
    if timing then
        local value = Median(timing.intervals, IntervalCount(timing))
        if value then return value, "observed" end
    end

    local cached, cacheSource = CachedInterval(spellID, spellName)
    if cached then return cached, cacheSource end

    return DEFAULT_INTERVAL, "default"
end

-- When we already know a cadence, a delayed/missed combat-log tick can produce
-- a 2x/3x delta. Fold a clean multiple back down before feeding it to the model.
local function NormalizeObservedInterval(spellID, spellName, delta)
    if not delta or delta < MIN_INTERVAL then return nil end

    local baseline = CachedInterval(spellID, spellName)
    local timing = spellTiming[spellID]
    if timing then
        baseline = Median(timing.intervals, IntervalCount(timing)) or baseline
    end

    local candidate = delta
    if baseline and baseline > 0 and delta > (baseline * 1.5) then
        local multiple = floor((delta / baseline) + 0.5)
        if multiple >= 2 and multiple <= 6 then
            local folded = delta / multiple
            local tolerance = max(0.25, baseline * 0.18)
            if abs(folded - baseline) <= tolerance then
                candidate = folded
            end
        end
    end

    if candidate < MIN_INTERVAL or candidate > MAX_INTERVAL then return nil end

    if baseline then
        local tolerance = max(0.50, baseline * 0.35)
        if abs(candidate - baseline) > tolerance then return nil end
    end

    return candidate
end

local function ObserveInterval(spellID, spellName, delta, now)
    local candidate = NormalizeObservedInterval(spellID, spellName, delta)
    if not candidate then return end
    local timing = GetTimingEntry(spellID, true)
    if PushInterval(timing, candidate, now) then
        PersistInterval(spellID, spellName, timing)
    end
end

-- -----------------------------------------------------------------------------
-- Damage lookups
-- -----------------------------------------------------------------------------
local function ExpectedTick(spellID, destGUID, sourceGUID)
    local entry = GetTargetEntry(destGUID, sourceGUID, spellID, false)
    if entry then
        local value = Median(entry.samples, SampleCount(entry))
        if value then return value, true end
        -- A first tick can crit before the engine has ever seen this spell's
        -- ordinary damage. Keep critical observations in a separate ring and
        -- use a conservative half-value only as a temporary display fallback;
        -- the first normal sample immediately takes precedence above.
        value = Median(entry.critSamples, CriticalSampleCount(entry))
        if value then return value, false end
    end

    local spellEntry = GetCasterSpellEntry(sourceGUID, spellID, false)
    if spellEntry then
        local value = Median(spellEntry.samples, SampleCount(spellEntry))
        if value then return value, false end
        value = Median(spellEntry.critSamples, CriticalSampleCount(spellEntry))
        if value then return value, false end
    end

    return nil, false
end

local function AuraCasterGUID(source)
    if source == "player" then
        return playerGUID or UnitGUID("player")
    elseif source == "pet" then
        return petGUID or UnitGUID("pet")
    end
    -- Party members and their pets, opt-in. Everything else still returns nil,
    -- so a stray hostile or unknown caster is ignored exactly as before.
    if source and IncludeParty() and PARTY_TOKENS[source] then
        return UnitGUID(source)
    end
    return nil
end

local function ResolveAuraCasterGUID(source, destGUID, spellID, fromPlayerOrPet)
    local sourceGUID = AuraCasterGUID(source)
    if sourceGUID or not spellID then return sourceGUID end

    -- Classic can transiently expose isFromPlayerOrPlayerPet/castByPlayer while
    -- omitting sourceUnit on a nameplate aura. The combat log has already keyed
    -- any observed tick by the real caster, so recover that attribution instead
    -- of letting the aura scan deactivate a valid prediction.
    local byCaster = destGUID and targetState[destGUID]
    if playerGUID and byCaster and byCaster[playerGUID]
        and byCaster[playerGUID][spellID] and byCaster[playerGUID][spellID].active then
        return playerGUID
    end
    if petGUID and byCaster and byCaster[petGUID]
        and byCaster[petGUID][spellID] and byCaster[petGUID][spellID].active then
        return petGUID
    end

    -- A direct destination/caster tick above is sufficient evidence even when
    -- Classic omitted both aura ownership fields. Broader caster-wide recovery
    -- still requires Blizzard's player/pet ownership bit so another caster's
    -- same-named aura cannot borrow our history.
    if not fromPlayerOrPet then return nil end

    -- Before this particular target's first tick, a caster-wide normal/fallback
    -- sample can still identify which owned unit previously dealt this spell.
    if playerGUID and casterSpell[playerGUID] and casterSpell[playerGUID][spellID] then
        return playerGUID
    end
    if petGUID and casterSpell[petGUID] and casterSpell[petGUID][spellID] then
        return petGUID
    end
    return playerGUID or petGUID
end

-- Final periodic ticks generally coincide with aura expiration. When no real
-- tick has been observed for this aura instance yet, align backwards from the
-- expiry boundary rather than pretending the scan itself was the application.
local function AlignNextTickFromExpiration(expiration, interval, now)
    if not expiration or expiration <= now or not interval or interval <= 0 then return nil end
    local remaining = expiration - now
    local periods = floor(remaining / interval)
    local nextTick = expiration - (periods * interval)
    if nextTick <= (now + 0.02) then nextTick = nextTick + interval end
    if nextTick > (expiration + TICK_EPSILON) then return nil end
    return nextTick
end

local function ResolveNextTick(entry, expiration, interval, now)
    if entry.lastTick and entry.lastTick > 0 then
        local elapsed = now - entry.lastTick
        local periods = floor(elapsed / interval) + 1
        local nextTick = entry.lastTick + (periods * interval)
        if nextTick <= (expiration + TICK_EPSILON) then
            return nextTick
        end
    end

    if entry.nextTick and entry.nextTick > now and entry.nextTick <= (expiration + TICK_EPSILON) then
        return entry.nextTick
    end

    return AlignNextTickFromExpiration(expiration, interval, now)
end

local function CountTicks(nextTick, expiration, interval)
    if not nextTick or not expiration or not interval or interval <= 0 then return 0 end
    if nextTick > (expiration + TICK_EPSILON) then return 0 end
    local count = floor(((expiration - nextTick) + TICK_EPSILON) / interval) + 1
    if count < 0 then return 0 end
    return count
end

-- -----------------------------------------------------------------------------
-- Aura scanning / prediction building
-- -----------------------------------------------------------------------------
local function MarkTargetAurasUnseen(guid)
    local byCaster = targetState[guid]
    if not byCaster then return end
    for _, bySpell in pairs(byCaster) do
        for _, entry in pairs(bySpell) do
            if entry.active then entry._auraSeen = false end
        end
    end
end

local function FinalizeTargetAuras(guid, now)
    local byCaster = targetState[guid]
    if not byCaster then return end
    for _, bySpell in pairs(byCaster) do
        for _, entry in pairs(bySpell) do
            if entry.active then
                if entry._auraSeen then
                    entry._auraSeen = nil
                else
                    -- Keep damage samples as a target-specific fallback, but an
                    -- expired/removed aura must never donate its old tick clock
                    -- to the next application.
                    entry.active = false
                    entry.lastTick = 0
                    entry.nextTick = 0
                    entry.expiration = 0
                    entry.duration = 0
                    entry._auraSeen = nil
                    entry.seen = now
                end
            end
        end
    end
end

local function ScanUnit(unit, guid, now, withDetails)
    local totalRemaining = 0
    local contributingDots = 0
    local activeDots = 0 -- active harmful auras confirmed as periodic by damage samples
    local nextTickDamage = 0 -- one next tick from each currently predictable DoT
    local nextEventDamage = 0
    local nextEventTime = nil
    local details = withDetails and {} or nil

    MarkTargetAurasUnseen(guid)

    for i = 1, 40 do
        -- Scan all harmful auras so pet-cast effects are not lost. Attribution is
        -- resolved from the aura source token and kept as a caster GUID.
        local name, icon, count, debuffType, duration, expiration, source, _, _, spellID,
            _, _, fromPlayerOrPet =
            ns.API.UnitDebuff(unit, i, "HARMFUL")
        if not name then break end

        local sourceGUID = ResolveAuraCasterGUID(source, guid, spellID, fromPlayerOrPet)

        -- Classic withholds duration/expiration for debuffs the player did not
        -- cast: both come back as 0. Without this the party branch above would
        -- resolve a caster and then fall straight through the expiry guard, so
        -- party DoTs would still contribute nothing. LibClassicDurations is
        -- already embedded and tracks applications per caster from the combat
        -- log, which is exactly the missing piece.
        if sourceGUID and spellID and LCD
            and (not expiration or expiration <= 0)
            and sourceGUID ~= playerGUID and sourceGUID ~= petGUID then
            local ok, d, e = pcall(LCD.GetAuraDurationByGUID, LCD, guid, spellID, sourceGUID)
            if ok and d and d > 0 and e then
                duration, expiration = d, e
            end
        end

        if sourceGUID and spellID and expiration and expiration > now then
            local entry = GetTargetEntry(guid, sourceGUID, spellID, true)
            local interval, intervalSource = ExpectedInterval(spellID, name)
            local oldExpiration = entry.expiration or 0
            local wasActive = entry.active == true

            -- A materially extended expiry is a refresh/reapplication. Preserve
            -- learned damage, but reset the instance clock so an old aura cannot
            -- schedule ticks for the new one.
            if wasActive and oldExpiration > 0 and interval > 0 then
                if (expiration - oldExpiration) > (interval * REFRESH_THRESHOLD) then
                    entry.lastTick = 0
                    entry.nextTick = AlignNextTickFromExpiration(expiration, interval, now) or (now + interval)
                end
            elseif not wasActive then
                entry.lastTick = 0
                entry.nextTick = AlignNextTickFromExpiration(expiration, interval, now) or (now + interval)
            end

            entry.active = true
            entry.expiration = expiration
            entry.duration = duration or 0
            entry._auraSeen = true
            entry.seen = now

            local tick, exact = ExpectedTick(spellID, guid, sourceGUID)
            if tick then activeDots = activeDots + 1 end
            local nextTick = ResolveNextTick(entry, expiration, interval, now)
            entry.nextTick = nextTick or 0

            local ticks = tick and CountTicks(nextTick, expiration, interval) or 0
            local remainingDamage = (tick and ticks > 0) and (tick * ticks) or 0

            if remainingDamage > 0 then
                totalRemaining = totalRemaining + remainingDamage
                contributingDots = contributingDots + 1
                nextTickDamage = nextTickDamage + tick

                if nextTick and (not nextEventTime or nextTick < (nextEventTime - 0.02)) then
                    nextEventTime = nextTick
                    nextEventDamage = tick
                elseif nextTick and nextEventTime and abs(nextTick - nextEventTime) <= 0.02 then
                    -- Simultaneous next ticks are one chronological event wave.
                    nextEventDamage = nextEventDamage + tick
                end
            end

            if details then
                details[#details + 1] = {
                    name = name,
                    icon = icon,
                    count = count or 0,
                    debuffType = debuffType,
                    spellID = spellID,
                    source = source,
                    sourceGUID = sourceGUID,
                    expirationTime = expiration,
                    duration = duration or 0,
                    tickDamage = tick,
                    exactTick = exact,
                    interval = interval,
                    intervalSource = intervalSource,
                    nextTickTime = nextTick,
                    remainingTicks = ticks,
                    remainingDamage = remainingDamage,
                }
            end
        end
    end

    FinalizeTargetAuras(guid, now)

    return {
        remainingDamage = totalRemaining,
        dotCount = contributingDots,
        activeDotCount = activeDots,
        nextTickDamage = nextTickDamage,
        nextEventDamage = nextEventDamage,
        nextEventTime = nextEventTime,
        effects = details,
    }
end

-- -----------------------------------------------------------------------------
-- Nameplate repaint / reconciliation helpers
-- -----------------------------------------------------------------------------
local function CurrentNameplateUnitForGUID(guid)
    if not guid then return nil end
    local unit = ns.guidToNameplateUnit and ns.guidToNameplateUnit[guid]
    if unit and UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    return nil
end

local function NotifyNameplateGUID(guid)
    local unit = CurrentNameplateUnitForGUID(guid)
    if unit and NotifyUnit then NotifyUnit(unit) end
end

local function FlushNameplateReconcile()
    -- Swap the batch before invoking consumers. A mismatch repair can re-enter the
    -- nameplate lifecycle and queue another reconcile; that new work must land in
    -- a fresh table instead of being wiped at the end of this flush.
    local pending = nameplateReconcileUnits
    nameplateReconcileUnits = {}
    nameplateReconcilePending = false

    if not registered then
        wipe(pending)
        return
    end

    for unit, expectedGUID in pairs(pending) do
        if UnitExists(unit) and UnitGUID(unit) == expectedGUID then
            -- A first-pass scan can legitimately have cached zero while Blizzard
            -- was still finalizing aura metadata or the native plate substrate.
            -- Force one authoritative rescan at the settled boundary.
            projCache[expectedGUID] = nil
            if NotifyUnit then NotifyUnit(unit) end
        end
    end
    wipe(pending)
end

local function QueueNameplateReconcile(unit, guid)
    if not C_Timer_After or not unit or not guid then return end
    nameplateReconcileUnits[unit] = guid
    if nameplateReconcilePending then return end
    nameplateReconcilePending = true
    C_Timer_After(NAMEPLATE_RECONCILE_DELAY, FlushNameplateReconcile)
end

-- -----------------------------------------------------------------------------
-- Combat log
-- -----------------------------------------------------------------------------
local function CleanupDeadDotGUID(guid)
    if guid then
        targetState[guid] = nil
        projCache[guid] = nil
    end
end

local function OnCombatLog(e)
    local sub = e[2]

    if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        local destGUID = e[8]
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("DotPrediction:DeathCleanup", CleanupDeadDotGUID, destGUID)
        else
            CleanupDeadDotGUID(destGUID)
        end
        return
    end

    if sub ~= "SPELL_PERIODIC_DAMAGE" then return end

    local sourceGUID = e[4]
    -- Party ticks are accepted so their damage is LEARNED from real hits, the
    -- same as ours, rather than assumed from a table. LibClassicDurations
    -- supplies the timing; the combat log still supplies the damage.
    if sourceGUID ~= playerGUID and sourceGUID ~= petGUID
        and not IsPartyGUID(sourceGUID) then
        return
    end

    local destGUID, spellID, spellName, amount = e[8], e[12], e[13], e[15]
    if not destGUID or not spellID or type(amount) ~= "number" or amount <= 0 then return end

    local now = GetTime()
    local entry = GetTargetEntry(destGUID, sourceGUID, spellID, true)

    if entry.lastTick and entry.lastTick > 0 then
        ObserveInterval(spellID, spellName, now - entry.lastTick, now)
    end

    local interval = ExpectedInterval(spellID, spellName)
    entry.lastTick = now
    entry.nextTick = now + interval
    entry.active = true -- a periodic tick is direct evidence the effect exists now
    entry.seen = now

    -- Critical periodic ticks (where supported) are valid timing evidence but a
    -- poor baseline for ordinary future ticks. The CLEU critical flag is arg 21
    -- for SPELL_PERIODIC_DAMAGE in Classic's payload.
    local isCrit = e[21] == true or e[21] == 1
    if not isCrit then
        PushSample(entry, amount, now)
        PushSample(GetCasterSpellEntry(sourceGUID, spellID, true), amount, now)
    else
        PushCriticalSample(entry, amount, now)
        PushCriticalSample(GetCasterSpellEntry(sourceGUID, spellID, true), amount, now)
    end

    projCache[destGUID] = nil

    -- Nameplate health events and CLEU do not have a guaranteed ordering. A
    -- UNIT_HEALTH can therefore repaint before this tick teaches us its damage,
    -- leaving the newly learned prediction invisible until another unrelated
    -- event. TurboFace already maintains an O(1) GUID -> nameplate-token map, so
    -- repaint that exact visible plate now instead of scanning all unit tokens.
    NotifyNameplateGUID(destGUID)

    if (now - lastSweep) >= SWEEP_INTERVAL then
        DP:_Sweep(now)
    end
end

-- -----------------------------------------------------------------------------
-- Public prediction API
-- -----------------------------------------------------------------------------
function DP:GetPrediction(unit)
    if not Enabled() or not unit or not UnitExists(unit) then
        return ZERO_PREDICTION
    end

    local guid = UnitGUID(unit)
    if not guid then return ZERO_PREDICTION end

    local now = GetTime()
    if (now - lastSweep) >= SWEEP_INTERVAL then self:_Sweep(now) end

    -- Prediction state is primarily event-driven: UNIT_AURA and periodic-damage
    -- events invalidate immediately. Keep a slow 0.5s safety rescan so an aura
    -- removal/expiry can never remain stale if the client drops or delays an
    -- expected UNIT_AURA. The previous 0.1s expiry forced up to ten 40-debuff
    -- scans per second on every damaged plate and was unnecessarily bursty.
    -- Health movement still uses current UnitHealth in GetBarRegion().
    local cached = projCache[guid]
    if cached and (now - (cached.at or 0)) < CACHE_TTL then return cached.prediction end

    local prediction = ScanUnit(unit, guid, now, false)
    local slot = cached or {}
    slot.prediction = prediction
    slot.at = now
    projCache[guid] = slot
    return prediction
end

-- Backwards-compatible API used by the current bars.
function DP:GetProjectedDamage(unit)
    local prediction = self:GetPrediction(unit)
    return prediction.remainingDamage or 0, prediction.dotCount or 0
end

-- Sum of one next tick from each predictable active DoT. The second/third
-- returns identify the earliest chronological tick wave specifically.
function DP:GetNextTickDamage(unit)
    local prediction = self:GetPrediction(unit)
    return prediction.nextTickDamage or 0,
           prediction.nextEventDamage or 0,
           prediction.nextEventTime
end

-- Detailed allocation is intentionally opt-in; ordinary nameplate health passes
-- only need the cached summary above.
function DP:GetEffectBreakdown(unit)
    if not Enabled() or not unit or not UnitExists(unit) then return {} end
    local guid = UnitGUID(unit)
    if not guid then return {} end
    local prediction = ScanUnit(unit, guid, GetTime(), true)
    -- The detailed scan is authoritative too, so update the cheap summary cache.
    projCache[guid] = { prediction = {
        remainingDamage = prediction.remainingDamage,
        dotCount = prediction.dotCount,
        activeDotCount = prediction.activeDotCount,
        nextTickDamage = prediction.nextTickDamage,
        nextEventDamage = prediction.nextEventDamage,
        nextEventTime = prediction.nextEventTime,
    }, at = GetTime() }
    return prediction.effects or {}, prediction
end

-- Lethality is a presentation input, not a separate query: callers already
-- receive the flag as GetBarRegion's third return, so they pass it straight
-- through rather than recomputing the prediction.
function DP:GetColor(lethal)
    local db = DB()
    local c, dr, dg, db_ = db.dotPredictionColor, 0.847, 0.706, 0.973
    if lethal then
        c, dr, dg, db_ = db.dotPredictionLethalColor, 0.35, 0.14, 0.35
    end
    local r, g, b = dr, dg, db_
    if type(c) == "table" then
        r = tonumber(c.r) or r
        g = tonumber(c.g) or g
        b = tonumber(c.b) or b
    end
    local alpha = tonumber(db.dotPredictionAlpha) or 0.75
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    return r, g, b, alpha
end

function DP:ShowOnNameplates()
    if not Enabled() or DB().dotPredictionNameplates == false then return false end
    return true
end

function DP:NeedsDotOnlyNameplateLifecycle()
    return self:ShowOnNameplates()
        and ns.ModuleEnabled and not ns.ModuleEnabled("nameplates")
end

function DP:ShowOnUnitFrames(unit)
    if not Enabled() or DB().dotPredictionUnitFrames == false then return false end
    -- The renderer attaches to Blizzard's native target health bars. TurboFace
    -- Unit Frames only restyles those bars and is not a prerequisite.
    if unit == nil then return true end
    return unit == "target" or unit == "targettarget"
end

function DP:RuntimeNeeded()
    return self:ShowOnNameplates() or self:ShowOnUnitFrames()
end

function DP:GetHealthBasis(unit)
    if PvPHealth and PvPHealth.GetHealthBasis then
        return PvPHealth:GetHealthBasis(unit)
    end
    local health = UnitHealth(unit) or 0
    local maxHealth = UnitHealthMax(unit) or 0
    if health <= 0 or maxHealth <= 0 then return nil, nil, "UNKNOWN", "native" end
    return health, maxHealth, "EXACT", "native"
end

function DP:GetBarRegion(unit, barWidth)
    if not barWidth or barWidth <= 0 then return nil end

    local damage = self:GetProjectedDamage(unit)
    if damage <= 0 then return nil end

    -- Classic Era reports hostile-player health as percentages instead of
    -- absolute current/max HP. PvPHealthEstimate supplies a confidence-gated
    -- combat-derived basis; UNKNOWN/LOW confidence deliberately suppresses the
    -- width projection rather than treating "73/100" as 73 actual HP.
    local health, maxHealth, confidence, source = self:GetHealthBasis(unit)
    if not health or not maxHealth or health <= 0 or maxHealth <= 0 then return nil end

    local healthPoint = (health / maxHealth) * barWidth
    local predicted = health - damage
    if predicted < 0 then predicted = 0 end
    local predictedPoint = (predicted / maxHealth) * barWidth

    local width = healthPoint - predictedPoint
    if width <= 0.5 then return nil end

    return predictedPoint, width, (damage >= health), confidence, source
end

function DP:WillDie(unit)
    local damage = self:GetProjectedDamage(unit)
    if damage <= 0 then return false, 0 end
    local health = self:GetHealthBasis(unit)
    if not health or health <= 0 then return false, damage end
    return damage >= health, damage
end

-- Diagnostics for a specific spell/caster/target. sourceGUID is optional for
-- backwards compatibility; omitted means player first, then pet.
function DP:GetTickInfo(spellID, guid, sourceGUID)
    if not spellID then return nil end

    sourceGUID = sourceGUID or playerGUID
    local tick, exact = nil, false
    local entry
    if guid and sourceGUID then
        entry = GetTargetEntry(guid, sourceGUID, spellID, false)
        tick, exact = ExpectedTick(spellID, guid, sourceGUID)
    end
    if not tick and petGUID and petGUID ~= sourceGUID and guid then
        local petTick, petExact = ExpectedTick(spellID, guid, petGUID)
        if petTick then
            sourceGUID = petGUID
            entry = GetTargetEntry(guid, sourceGUID, spellID, false)
            tick, exact = petTick, petExact
        end
    end

    local spellName
    if ns.API and ns.API.GetSpellInfo then spellName = ns.API.GetSpellInfo(spellID) end
    local interval, intervalSource = ExpectedInterval(spellID, spellName)
    return {
        tick = tick,
        exact = exact,
        interval = interval,
        intervalSource = intervalSource,
        samples = entry and SampleCount(entry) or 0,
        lastTick = entry and entry.lastTick or 0,
        nextTick = entry and entry.nextTick or 0,
        sourceGUID = sourceGUID,
    }
end

-- -----------------------------------------------------------------------------
-- Housekeeping / events
-- -----------------------------------------------------------------------------
function DP:_Sweep(now)
    now = now or GetTime()
    if (now - lastSweep) < SWEEP_INTERVAL then return end
    lastSweep = now

    for destGUID, byCaster in pairs(targetState) do
        local targetEmpty = true
        for sourceGUID, bySpell in pairs(byCaster) do
            local casterEmpty = true
            for spellID, entry in pairs(bySpell) do
                if (now - (entry.seen or 0)) > ENTRY_TTL then
                    bySpell[spellID] = nil
                else
                    casterEmpty = false
                    targetEmpty = false
                end
            end
            if casterEmpty then byCaster[sourceGUID] = nil end
        end
        if targetEmpty then
            targetState[destGUID] = nil
            projCache[destGUID] = nil
        end
    end

    for sourceGUID, bySpell in pairs(casterSpell) do
        local empty = true
        for spellID, entry in pairs(bySpell) do
            if (now - (entry.seen or 0)) > SPELL_SAMPLE_TTL then
                bySpell[spellID] = nil
            else
                empty = false
            end
        end
        if empty then casterSpell[sourceGUID] = nil end
    end

    for guid, slot in pairs(projCache) do
        if (now - (slot.at or 0)) > ENTRY_TTL then projCache[guid] = nil end
    end
end

function DP:ResetTargets()
    wipe(targetState)
    wipe(projCache)
    wipe(nameplateReconcileUnits)
    if PvPHealth and PvPHealth.Reset then PvPHealth:Reset() end
    lastSweep = GetTime()
end

function DP:Reset()
    self:ResetTargets()
    wipe(casterSpell)
    wipe(spellTiming)
end

function DP:RegisterConsumer(fn)
    if fn then consumers[fn] = true end
end

NotifyUnit = function(unit)
    for fn in pairs(consumers) do fn(unit) end
end

local function RelevantAuraUnit(unit)
    if unit == "target" or unit == "targettarget" then return true end
    return type(unit) == "string" and string.match(unit, "^nameplate%d+$") ~= nil
end

function DP:RefreshAll()
    -- Notify presentation only. Refresh owns event/library demand and identities.
    NotifyUnit("target")
    NotifyUnit("targettarget")
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid and self:ShowOnNameplates() then
                dotNameplateGUIDs[unit] = guid
                ns.guidToNameplateUnit[guid] = unit
            end
            NotifyUnit(unit)
            if guid and self:ShowOnNameplates() then QueueNameplateReconcile(unit, guid) end
        end
    end
end

function DP:RequestNameplateReconcile(unit)
    if not registered or not self:ShowOnNameplates() or not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    projCache[guid] = nil
    QueueNameplateReconcile(unit, guid)
end

-- Called by the Blizzard-native nameplate lifecycle after TurboFace has bound a
-- pooled plate to a unit. FullPlateUpdate performs the immediate render; this
-- one delayed reconcile exists only to cross the native layout/binding boundary.
function DP:OnNameplateBound(unit)
    self:RequestNameplateReconcile(unit)
end

function DP:Init()
    playerGUID = UnitGUID("player")
    petGUID = UnitGUID("pet")
    if not self._eventFrame then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then
                if not unit or not UnitExists(unit) then return end
                local guid = UnitGUID(unit)
                if not guid then return end
                dotNameplateGUIDs[unit] = guid
                ns.guidToNameplateUnit[guid] = unit
                projCache[guid] = nil
                NotifyUnit(unit)
                QueueNameplateReconcile(unit, guid)
                return
            end

            if event == "NAME_PLATE_UNIT_REMOVED" then
                local guid = unit and dotNameplateGUIDs[unit]
                dotNameplateGUIDs[unit] = nil
                if guid and ns.guidToNameplateUnit[guid] == unit then
                    ns.guidToNameplateUnit[guid] = nil
                end
                if unit then nameplateReconcileUnits[unit] = nil end
                if ns.NP and ns.NP.ReleaseDotPredictionPlate then
                    ns.NP.ReleaseDotPredictionPlate(unit)
                end
                return
            end

            if event == "UNIT_HEALTH" and unit and ns.IsNameplateUnit
                and ns.IsNameplateUnit(unit) then
                NotifyUnit(unit)
                return
            end

            if event == "PLAYER_ENTERING_WORLD" then
                playerGUID = UnitGUID("player")
                petGUID = UnitGUID("pet")
                RefreshPartyGUIDs()
                -- Zone transitions invalidate unit/GUID instance state, but the
                -- player's recent spell samples and learned cadence remain useful.
                DP:ResetTargets()
                DP:RefreshAll()
                return
            end

            if event == "PLAYER_REGEN_ENABLED" then
                -- A unit-frame consumer enabled in combat may have deferred its
                -- first Blizzard-bar texture/hook. One post-combat refresh finishes
                -- that setup without ever mutating Blizzard-owned UI in lockdown.
                DP:RefreshAll()
                return
            end

            if event == "GROUP_ROSTER_UPDATE" then
                RefreshPartyGUIDs()
                wipe(projCache)
                DP:RefreshAll()
                return
            end

            if event == "UNIT_PET" then
                -- UNIT_PET reports the pet's owner, not the pet unit token.
                if unit ~= "player" and not (IncludeParty() and PARTY_TOKENS[unit]) then return end
                petGUID = UnitGUID("pet")
                RefreshPartyGUIDs()
                -- A party pet can change without the player's pet changing.
                wipe(projCache)
                DP:RefreshAll()
                return
            end

            if event == "UNIT_AURA" and unit and RelevantAuraUnit(unit) then
                local guid = UnitGUID(unit)
                if guid then projCache[guid] = nil end
                NotifyUnit(unit)

                -- UNIT_AURA is token-scoped, not GUID-broadcast. When the target
                -- is also visible as a nameplate the client is not required to
                -- emit both aliases in a useful order, so bridge target/ToT aura
                -- invalidation to the mapped nameplate explicitly.
                local isNameplate = ns.IsNameplateUnit and ns.IsNameplateUnit(unit)
                if guid and not isNameplate then NotifyNameplateGUID(guid) end

                -- Nameplate aura metadata/binding can settle just after the raw
                -- event. Keep the immediate path for responsiveness, then perform
                -- one deduplicated identity-validated retry on the current plate.
                local plateUnit = guid and CurrentNameplateUnitForGUID(guid)
                if plateUnit then QueueNameplateReconcile(plateUnit, guid) end
            end
        end)
        self._eventFrame = f
        ns.RegisterCPUProfileTarget("Combat/DotPrediction:Events", f:GetScript("OnEvent"))
    end

    self:Refresh()
end

function DP:Refresh()
    local on = self:RuntimeNeeded()
    local f = self._eventFrame
    local stateChanged = false

    -- PvP health estimation is a subordinate runtime of DoT prediction: it
    -- shares the central CLEU dispatcher and is completely dormant when no DoT
    -- presentation surface needs the engine.
    if PvPHealth and PvPHealth.SetEnabled then PvPHealth:SetEnabled(on) end

    if on and not registered then
        IntervalCache()
        ns.CLEU:Register(OnCombatLog, CLEU_EVENTS)
        if f then
            f:RegisterEvent("GROUP_ROSTER_UPDATE")
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:RegisterEvent("UNIT_PET")
            f:RegisterEvent("UNIT_AURA")
            if self:NeedsDotOnlyNameplateLifecycle() then
                f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
                f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
                f:RegisterEvent("UNIT_HEALTH")
            end
        end
        registered = true
        stateChanged = true
        playerGUID = UnitGUID("player")
        petGUID = UnitGUID("pet")
    elseif not on and registered then
        ns.CLEU:Unregister(OnCombatLog)
        if f then f:UnregisterAllEvents() end
        registered = false
        stateChanged = true
        self:Reset()
    end

    -- Settings can change while already grouped, with no roster event. Rebuild
    -- before notifying renderers; dormant engines retain no party membership.
    RefreshPartyGUIDs()
    wipe(projCache)
    SyncDurationLib()

    -- Nameplate presentation is independent of the optional Nameplates
    -- enhancement family. Keep only this lightweight lifecycle subscribed when
    -- the DoT surface requests it; unit-frame-only prediction needs neither.
    if registered and f then
        if self:NeedsDotOnlyNameplateLifecycle() then
            f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
            f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            f:RegisterEvent("UNIT_HEALTH")
        else
            if f.UnregisterEvent then
                f:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
                f:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
                f:UnregisterEvent("UNIT_HEALTH")
            end
        end
    end

    -- While disabled at startup the module is fully dormant. Once active, refresh
    -- consumers for visibility/color changes; on teardown, refresh once to hide.
    if on or stateChanged then self:RefreshAll() end
end

ns.RegisterCPUProfileTarget("Combat/DotPrediction:CLEU", OnCombatLog)
