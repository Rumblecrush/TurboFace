local _, ns = ...

-- =============================================================================
-- TurboFace Hearthstone batching
--
-- Fires ConfirmBinder() so it lands in the same server batch tick as the
-- Hearthstone cast completing, which binds you to the innkeeper you are
-- standing at while the hearth teleports you to your OLD home.
--
-- TIMING MODEL
-- The server processes packets in discrete batch ticks (~10ms on Era). At the
-- tick boundary where the cast completes it processes the cast plus everything
-- received since the previous boundary, so the safe arrival window is
-- (T_end - tick, T_end]. Up to a full tick early is fine; one moment late is
-- not. Failure is therefore asymmetric:
--
--   same tick as T_end -> bind updates AND we teleport away        (success)
--   one or more ticks early -> bind updates, then we hearth to it  (wasted)
--   after T_end -> we teleport, popup dies with us, bind unchanged (wasted)
--
-- ANCHOR
-- The anchor is GetTime() at the UseAction/UseContainerItem hook, i.e. the
-- moment the client sends the use packet -- NOT UNIT_SPELLCAST_START. Both the
-- use packet and the confirm packet travel the same upstream path, so firing at
-- anchor + 10s arrives at the same phase within the tick cycle as the cast
-- start did, and upstream latency cancels out with no need to estimate it.
-- UNIT_SPELLCAST_START would bake in a full round trip of error instead; it is
-- used here only to confirm the cast actually began.
--
-- THE LIMITING FACTOR IS FRAME RATE
-- ConfirmBinder() can only be called from a frame, so the send lands somewhere
-- inside one frame interval. The window is ~10ms wide, so a 60fps client
-- (16.7ms frames) cannot reliably hit it at all, while anything past ~150fps
-- has frame quantization comfortably inside the window and is limited by
-- network jitter instead. Hence the temporary maxfps FLOOR (see RaiseFPS: it
-- never lowers an existing cap), and hence ReportFrameBudget() telling the user
-- when their frame interval makes the attempt hopeless rather than failing
-- silently.
--
-- SELF-CALIBRATION
-- The three outcomes above are distinguishable after the fact from
-- GetBindLocation() plus whether we moved, so the module measures its own error
-- and nudges a per-character lead offset. That turns the unknowns (true tick
-- size on a realm, typical jitter, whether packets flush at frame end) into
-- things we measure instead of assume.
-- =============================================================================

local HB = {}
ns.HearthBatch = HB

local CreateFrame       = CreateFrame
local GetTime           = GetTime
local GetCVar           = GetCVar
local GetFramerate      = GetFramerate
local GetBindLocation   = GetBindLocation
local GetActionInfo     = GetActionInfo
local UnitCastingInfo   = UnitCastingInfo
local hooksecurefunc    = hooksecurefunc

local HEARTHSTONE_ITEM  = 6948
local HEARTHSTONE_SPELL = 8690
local ASTRAL_RECALL     = 556
local CAST_SECONDS      = 10

-- How close to the fire moment a cast-end event must be before we assume it is
-- the cast completing rather than an interruption. Wide enough to cover a
-- server message arriving early, narrow enough that a mid-cast interrupt is
-- still treated as one.
local CAST_END_GRACE    = 0.15

-- Lead is how far before anchor+10s we aim. Default 6ms centres us in a ~10ms
-- window with slightly more tolerance for a late packet than an early one,
-- since late is the more common jitter direction. Calibration moves it.
local DEFAULT_LEAD      = 0.006
local MIN_LEAD          = 0.000
local MAX_LEAD          = 0.012
local LEAD_STEP         = 0.0015

local CVAR_OWNER        = "hearthbatch.maxfps"

local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or _G.IsCurrentSpell

local ConfirmBinder
if C_PlayerInteractionManager and C_PlayerInteractionManager.ConfirmationInteraction
        and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Binder then
    ConfirmBinder = function()
        return C_PlayerInteractionManager.ConfirmationInteraction(Enum.PlayerInteractionType.Binder)
    end
else
    ConfirmBinder = _G.ConfirmBinder
end

local driver, events
local hooksInstalled = false

-- Attempt state. Nil between attempts; a table for the duration of one cast.
local attempt

-- Rolling frame-interval estimate, sampled during the cast only.
local frameSamples, frameSampleCount = {}, 0

-- Model constants, declared here because the storage layer below needs the
-- sample threshold when deciding whether a realm has enough data of its own.
local BATCH_WINDOW       = 0.010   -- assumed server batch tick
local DEFAULT_JITTER     = 0.004   -- prior until we have enough samples
local MIN_JITTER         = 0.0005
-- Sufficiency is judged on PAIR count (MIN_PAIRS), not sample count: pairs are
-- what the estimator consumes, and a sample whose neighbours were rejected
-- contributes nothing. Fitting from too few was what produced the 80% -> 51%
-- cliff for a player going 4/4.

local DB = ns.DB   -- shared root accessor (Config.lua)

-- -----------------------------------------------------------------------------
-- Storage
--
-- Timing data is a property of the connection path and the server, not of the
-- character, so it pools account-wide keyed by realm. That matters most for
-- rerolling: a fresh character inherits both the converged lead (so its first
-- hearth fires at the optimum instead of walking there from the 6ms default)
-- and enough samples for the readout to mean something immediately.
--
-- Keyed by realm rather than pooled blindly: a US-West and an EU character have
-- genuinely different paths, and merging them inflates the apparent spread and
-- reads as high jitter on both. Fallback chain is realm -> all realms -> prior.
--
-- Lives in TurboFaceCacheDB, which is outside profile/import snapshots -- your
-- measured jitter should not travel with someone else's exported profile -- and
-- is preserved across client builds by an explicit exception in Core/Config.lua.
--
-- Everything is timestamped and age-evicted. Pooling removes the implicit
-- recency that per-character data had: a lifetime tally spans ISP changes,
-- wifi-to-ethernet moves and new hardware, and stale samples mixed with current
-- ones produce a confident number about conditions that no longer exist. That
-- is worse than a cold start because it does not announce itself.
-- -----------------------------------------------------------------------------
local MAX_AGE            = 30 * 24 * 60 * 60  -- 30 days
local MAX_RTT_SAMPLES    = 40
local MAX_OUTCOMES       = 30

local function Store()
    if type(TurboFaceCacheDB) ~= "table" then TurboFaceCacheDB = {} end
    if type(TurboFaceCacheDB.hearthBatch) ~= "table" then
        TurboFaceCacheDB.hearthBatch = {}
    end
    local hb = TurboFaceCacheDB.hearthBatch
    if type(hb.realms) ~= "table" then hb.realms = {} end
    return hb
end

local function RealmKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName())
    if type(realm) ~= "string" or realm == "" then return "Unknown" end
    return (realm:gsub("%s+", ""))
end

local function RealmStore(key)
    local hb = Store()
    key = key or RealmKey()
    if type(hb.realms[key]) ~= "table" then
        hb.realms[key] = { rtt = {}, outcomes = {} }
    end
    local r = hb.realms[key]
    if type(r.rtt) ~= "table" then r.rtt = {} end
    if type(r.outcomes) ~= "table" then r.outcomes = {} end
    return r
end

-- Drops entries older than MAX_AGE and trims to the cap, oldest first.
local function Prune(list, cap, now)
    if type(list) ~= "table" then return end
    now = now or time()
    local i = 1
    while i <= #list do
        local e = list[i]
        if type(e) ~= "table" or type(e.t) ~= "number" or (now - e.t) > MAX_AGE then
            table.remove(list, i)
        else
            i = i + 1
        end
    end
    while #list > cap do table.remove(list, 1) end
end

-- Collects RTT samples for the estimator, newest realm data first.
-- Returns the sample values, plus a tier: "realm", "account", or "prior".
-- Exposes this realm's ordered sample entries and, separately, every realm's as
-- a list of groups. Tiering is decided by the caller on PAIR count, not sample
-- count: a sample-count gate short-circuited before pairs were ever built and
-- then reported "0 usable pairs", which conflated "we did not look" with "we
-- looked and everything was rejected".
local function CollectSamples()
    local now = time()
    local realm = RealmStore()
    Prune(realm.rtt, MAX_RTT_SAMPLES, now)

    -- Kept per realm and never interleaved: a difference taken across two
    -- realms would be comparing two different network paths.
    local hb = Store()
    local groups = {}
    for _, r in pairs(hb.realms) do
        if type(r) == "table" and type(r.rtt) == "table" and #r.rtt > 0 then
            Prune(r.rtt, MAX_RTT_SAMPLES, now)
            if #r.rtt > 0 then groups[#groups + 1] = r.rtt end
        end
    end

    return realm.rtt, groups
end

-- Hit record for the Beta blend, same fallback chain. Capped and age-evicted so
-- a run of misses from a bad-wifi era cannot drag the estimate down forever.
local function CollectOutcomes()
    local now = time()
    local realm = RealmStore()
    Prune(realm.outcomes, MAX_OUTCOMES, now)

    local hits, attempts = 0, #realm.outcomes
    for i = 1, attempts do
        if realm.outcomes[i].ok then hits = hits + 1 end
    end
    if attempts > 0 then return hits, attempts, "realm" end

    local hb = Store()
    hits, attempts = 0, 0
    for _, r in pairs(hb.realms) do
        if type(r) == "table" and type(r.outcomes) == "table" then
            Prune(r.outcomes, MAX_OUTCOMES, now)
            for i = 1, #r.outcomes do
                attempts = attempts + 1
                if r.outcomes[i].ok then hits = hits + 1 end
            end
        end
    end
    return hits, attempts, (attempts > 0) and "account" or "prior"
end

local function Enabled()
    -- The FPS Counter is the required live presentation surface for batching's
    -- success estimate. Keep the runtime inert if that dependency is disabled.
    local db = DB()
    return db.hearthBatchEnabled == true and db.fpsCounterEnabled == true
end

-- Lead follows the same chain: this realm's calibrated value, else the median
-- of what other realms converged on, else the configured default. Inheriting a
-- converged lead is arguably worth more than the readout -- it is the
-- difference between a fresh character's first hearth firing at the optimum and
-- burning its early batches rediscovering it.
local function Lead()
    local r = RealmStore()
    if type(r.lead) ~= "number" then
        local hb = Store()
        local leads = {}
        for key, other in pairs(hb.realms) do
            if type(other) == "table" and type(other.lead) == "number" then
                leads[#leads + 1] = other.lead
            end
        end
        if #leads > 0 then
            table.sort(leads)
            r.lead = leads[math.ceil(#leads / 2)]
        else
            r.lead = DB().hearthBatchLead or DEFAULT_LEAD
        end
    end
    if r.lead < MIN_LEAD then r.lead = MIN_LEAD end
    if r.lead > MAX_LEAD then r.lead = MAX_LEAD end
    return r.lead
end

-- One-time fold of pre-pool per-character data into this realm's store. The
-- character was on this realm, so its samples belong here.
local function MigrateCharData()
    if type(TurboFaceCharDB) ~= "table" then return end
    local old = TurboFaceCharDB.hearthBatch
    if type(old) ~= "table" then return end

    local r = RealmStore()
    local stamp = time()
    if type(old.rtt) == "table" then
        for i = 1, #old.rtt do
            local v = old.rtt[i]
            if type(v) == "number" then
                r.rtt[#r.rtt + 1] = { t = stamp, v = v }
            end
        end
    end
    -- The old record was a bare tally with no per-attempt detail, so replay it
    -- as individual outcomes to fit the new capped, timestamped shape.
    local attempts, hits = tonumber(old.attempts) or 0, tonumber(old.hits) or 0
    for i = 1, attempts do
        r.outcomes[#r.outcomes + 1] = { t = stamp, ok = (i <= hits) }
    end
    if type(old.lead) == "number" and type(r.lead) ~= "number" then
        r.lead = old.lead
    end

    Prune(r.rtt, MAX_RTT_SAMPLES, stamp)
    Prune(r.outcomes, MAX_OUTCOMES, stamp)
    TurboFaceCharDB.hearthBatch = nil
end

local function TargetFPS()
    local v = tonumber(DB().hearthBatchFPS) or 300
    if v < 60 then v = 60 end
    if v > 1000 then v = 1000 end
    return v
end

-- -----------------------------------------------------------------------------
-- Popup detection
--
-- StaticPopup_FindVisible matches on the popup's "which" key, so this is exact
-- and position independent -- unlike scanning StaticPopup1's localized text,
-- which breaks when another dialog occupies slot 1 or on a non-English client.
-- -----------------------------------------------------------------------------
local function BinderPopupVisible()
    if _G.StaticPopup_FindVisible then
        return _G.StaticPopup_FindVisible("CONFIRM_BINDER") ~= nil
    end
    -- Fallback: scan every popup slot rather than assuming slot 1.
    for i = 1, 4 do
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() and p.which == "CONFIRM_BINDER" then return true end
    end
    return false
end

-- -----------------------------------------------------------------------------
-- maxfps ownership
--
-- This is a FLOOR, never a ceiling: the CVar is only written when the player's
-- existing cap is lower than the target, because the point is to shrink the
-- frame interval below the batch window. Writing it unconditionally would clamp
-- an uncapped client down to the target and make the timing worse.
--
-- maxfps 0 means uncapped, so there is nothing to raise -- and writing a number
-- over it would impose a cap that did not exist.
--
-- Routed through ns.ApplyOwnedCVars so the snapshot lives in TurboFaceCacheDB.
-- maxfps is persisted client-side: a disconnect or crash mid-cast would
-- otherwise leave the user permanently uncapped with no record of the original
-- value. Ownership means the next login can put it back.
-- -----------------------------------------------------------------------------
local function CurrentMaxFPS()
    return tonumber(GetCVar("maxfps") or "") or 0
end

local function RaiseFPS()
    if not ns.ApplyOwnedCVars then return end
    local current = CurrentMaxFPS()
    if current == 0 then return end          -- already uncapped
    if current >= TargetFPS() then return end -- already faster than we would ask for
    ns.ApplyOwnedCVars(CVAR_OWNER, true, { maxfps = TargetFPS() })
end

local function RestoreFPS()
    if not ns.ReleaseOwnedCVars then return end
    ns.ReleaseOwnedCVars(CVAR_OWNER)
end

-- -----------------------------------------------------------------------------
-- Frame interval measurement
-- -----------------------------------------------------------------------------
local function ResetFrameSamples()
    frameSampleCount = 0
    cachedInterval = nil
end

local function SampleFrame(elapsed)
    if elapsed <= 0 then return end
    frameSampleCount = frameSampleCount + 1
    frameSamples[(frameSampleCount % 16) + 1] = elapsed
end

-- Median of the recent samples: robust against a single GC hitch in a way a
-- mean is not, which matters because one 40ms stall would otherwise convince us
-- to fire a frame early for the rest of the cast.
--
-- Both the scratch table and the result are reused. This runs on every frame of
-- the driver -- 8000 times over a cast at 800fps -- so allocating a table per
-- call would generate exactly the kind of GC pressure that makes a frame land
-- late during the ten seconds where frame timing is the whole game. The median
-- of a rolling window does not move meaningfully within 250ms.
local frameScratch = {}
local cachedInterval, cachedIntervalAt = nil, 0

local function FrameInterval()
    local now = GetTime()
    if cachedInterval and (now - cachedIntervalAt) < 0.25 then
        return cachedInterval
    end

    local n = 0
    for i = 1, 16 do
        local v = frameSamples[i]
        if v then n = n + 1; frameScratch[n] = v end
    end
    -- Clear any stale tail so table.sort sees the right length.
    for i = n + 1, 16 do frameScratch[i] = nil end

    local value
    if n == 0 then
        local fps = GetFramerate() or 60
        value = (fps > 0) and (1 / fps) or 0.0167
    else
        table.sort(frameScratch)
        value = frameScratch[math.ceil(n / 2)]
    end

    cachedInterval, cachedIntervalAt = value, now
    return value
end

-- -----------------------------------------------------------------------------
-- Success probability model
--
-- Arrival lands at T_end - lead + e + j, where e is frame-quantization error and
-- j is the difference in upstream transit between the use packet and the confirm
-- packet. Success requires arrival in (T_end - W, T_end], i.e.
--
--     e + j  in  (lead - W, lead]
--
-- With nearest-frame selection e is ~uniform on [-d/2, +d/2] for frame interval
-- d. Modelling j as zero-mean normal with spread sigma, the sum has CDF
--
--     F(t) = (sigma / 2a) * [ Psi((t+a)/sigma) - Psi((t-a)/sigma) ],
--     Psi(z) = z*Phi(z) + phi(z),   a = d/2
--
-- so P = F(lead) - F(lead - W). Two things this makes explicit and worth
-- internalising: latency itself does not appear (it cancels via the anchor --
-- see the ANCHOR note), only its *variance* does; and once d is well under W,
-- adding frame rate buys nothing and jitter is the whole story.
--
-- W is the one input we cannot measure. It is Blizzard's batch tick, taken as
-- 10ms; if a realm differs, the calibrated lead absorbs the offset but this
-- estimate will be biased. Treat the number as a guide, not a guarantee -- the
-- observed hit rate in /tf hearthbatch is the ground truth.
-- -----------------------------------------------------------------------------

local function Phi(z)
    -- Abramowitz & Stegun 7.1.26 error function approximation.
    local sign = (z < 0) and -1 or 1
    local x = math.abs(z) / math.sqrt(2)
    local t = 1 / (1 + 0.3275911 * x)
    local y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
        - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
    return 0.5 * (1 + sign * y)
end

local function Psi(z)
    return z * Phi(z) + math.exp(-0.5 * z * z) / math.sqrt(2 * math.pi)
end

local function SumCDF(t, a, sigma)
    if a <= 0 then return Phi(t / math.max(sigma, MIN_JITTER)) end
    if sigma < MIN_JITTER then
        -- Degenerate to the pure uniform case rather than dividing by ~zero.
        if t <= -a then return 0 end
        if t >= a then return 1 end
        return (t + a) / (2 * a)
    end
    return (sigma / (2 * a)) * (Psi((t + a) / sigma) - Psi((t - a) / sigma))
end

-- Live frame interval when no attempt is running. GetFramerate is already
-- smoothed, which is what we want for a steady-state readout.
local function CurrentFrameInterval()
    local fps = GetFramerate and tonumber(GetFramerate()) or nil
    if not fps or fps <= 0 then return 1 / 60 end
    return 1 / fps
end

-- -----------------------------------------------------------------------------
-- Jitter estimation from successive differences
--
-- Each sample is (server cast start - our local send time): upstream transit,
-- plus the server queue until the next batch tick, plus downstream transit and
-- client frame dispatch. Only the transit terms are jitter.
--
-- Taking the SPREAD of those samples was wrong, and produced a 22ms reading for
-- a player going 4/4. Samples are minutes or hours apart, so their spread is
-- dominated by slow drift in baseline latency -- route changes, congestion, time
-- of day. What actually breaks a batch is the difference in transit between two
-- packets sent 10 SECONDS apart, and latency is strongly autocorrelated at that
-- scale: a baseline that wanders 15ms across an evening barely moves within a
-- single cast. Drift inflated the estimate while barely affecting real success.
--
-- Differencing temporally adjacent samples cancels the drift and leaves the
-- short-timescale variation. Pairs are rejected when they sit too far apart in
-- time, or when the client's own reported latency moved between them, since
-- those differences carry exactly the drift we are removing.
--
-- Differencing changes the distribution, so the single-sample model cannot be
-- reused: the uniform queue term becomes triangular (U1 - U2) and the jitter
-- term gains a factor of sqrt(2). ModelMADDiff builds the matching CDF by
-- integrating SumCDF over the second uniform.
--
-- Accuracy is still limited -- an order statistic cannot cleanly separate a small
-- jitter from a 10ms uniform -- which is why HB:SuccessChance weights the model
-- against the observed hit rate rather than trusting it outright.
-- -----------------------------------------------------------------------------
-- Window sizing is set by how samples actually arrive, which the first attempt
-- got wrong: 3600s was chosen as "close enough that the baseline has not moved"
-- without checking it against the cadence that produces samples. The Hearthstone
-- cooldown is 60 minutes, so hearth-to-hearth pairs are ALWAYS wider than an
-- hour and every pair was silently rejected.
--
-- Real cadences: alt-hopping on one realm gives samples minutes apart, Astral
-- Recall gives 15, hearth gives 60+. Twenty minutes admits the first two -- the
-- ones close enough for the baseline to still be the same -- and excludes the
-- third, which is the pair that carries drift rather than jitter.
local PAIR_MAX_GAP       = 1200   -- 20 min: alt-swap and Astral Recall pairs

-- A pair wider than that is still usable IF we can show the baseline did not
-- move, by subtracting each sample's own reported latency. Coarser (GetNetStats
-- is smoothed and integer-millisecond) so it is the fallback, not the default.
local PAIR_WIDE_GAP      = 6 * 3600
local PAIR_MAX_LAT_DRIFT = 0.015  -- reported-latency movement that voids a pair
local MIN_PAIRS          = 6

local function ModelMADDiff(sigma)
    -- D = U1 - U2 + N(0, sigma*sqrt(2)), symmetric about zero, so its MAD is
    -- the point where the CDF reaches 0.75.
    local a = BATCH_WINDOW / 2
    local sd = sigma * math.sqrt(2)
    local STEPS = 16

    local function CDF(t)
        -- Condition on U2 = u and average: F(t) = mean over u of F_{U1+G}(t+u).
        local acc = 0
        for i = 1, STEPS do
            local u = BATCH_WINDOW * (i - 0.5) / STEPS
            acc = acc + SumCDF(t + u - a, a, sd)
        end
        return acc / STEPS
    end

    local lo, hi = 0, 0.3
    for _ = 1, 24 do
        local m = (lo + hi) / 2
        if CDF(m) < 0.75 then lo = m else hi = m end
    end
    return (lo + hi) / 2
end

-- ModelMADDiff is monotone in sigma but far too costly to invert per call, so
-- the curve is tabulated once, lazily, and interpolated afterwards.
local diffTable
local DIFF_TABLE_MAX = 0.030
local DIFF_TABLE_N   = 32

local function EnsureDiffTable()
    if diffTable then return diffTable end
    diffTable = {}
    for i = 0, DIFF_TABLE_N do
        local sigma = DIFF_TABLE_MAX * i / DIFF_TABLE_N
        diffTable[i] = { sigma = sigma, mad = ModelMADDiff(sigma) }
    end
    return diffTable
end

local function FitSigmaFromDiff(observedMAD)
    local t = EnsureDiffTable()
    if observedMAD <= t[0].mad then return MIN_JITTER end
    for i = 1, DIFF_TABLE_N do
        if observedMAD <= t[i].mad then
            local lo, hi = t[i - 1], t[i]
            local span = hi.mad - lo.mad
            local frac = (span > 0) and ((observedMAD - lo.mad) / span) or 0
            return lo.sigma + frac * (hi.sigma - lo.sigma)
        end
    end
    return DIFF_TABLE_MAX
end

-- Successive differences from one realm's ordered samples, contaminated pairs
-- dropped. Never call across realms: that would difference two network paths.
--
-- Two admission routes:
--   * close in time  -> difference the raw values; the baseline cannot have
--                       moved much over minutes
--   * further apart  -> only if both samples carry a valid reported latency and
--                       it did not move; difference the baseline-SUBTRACTED
--                       values so measured drift is removed rather than assumed
--                       away
local function AppendPairs(entries, out)
    for i = 2, #entries do
        local prev, cur = entries[i - 1], entries[i]
        if type(prev) == "table" and type(cur) == "table"
                and type(prev.v) == "number" and type(cur.v) == "number" then
            local gap = (cur.t or 0) - (prev.t or 0)

            -- Latency is reported in ms and reads 0 or nil before the client has
            -- data -- notably right after a login, which alt-hopping produces a
            -- lot of. Treat those as absent rather than as a real zero.
            local pl = (type(prev.lat) == "number" and prev.lat > 0) and prev.lat or nil
            local cl = (type(cur.lat) == "number" and cur.lat > 0) and cur.lat or nil
            local haveLat = (pl ~= nil and cl ~= nil)
            local drifted = haveLat and (math.abs(cl - pl) / 1000 > PAIR_MAX_LAT_DRIFT)

            if gap < 0 then
                -- clock oddity; skip
            elseif gap <= PAIR_MAX_GAP and not drifted then
                out[#out + 1] = math.abs(cur.v - prev.v)
            elseif haveLat and not drifted and gap <= PAIR_WIDE_GAP then
                local a = prev.v - (pl / 1000)
                local b = cur.v - (cl / 1000)
                out[#out + 1] = math.abs(b - a)
            end
        end
    end
end

local fitCache = { n = -1, last = nil, tier = nil, sigma = DEFAULT_JITTER, mad = 0 }

-- Returns sigma, pair count, observed pair MAD, tier, sample count.
local function JitterSigma()
    local realmEntries, groups = CollectSamples()

    local pairs_ = {}
    AppendPairs(realmEntries, pairs_)
    local tier = "realm"

    if #pairs_ < MIN_PAIRS then
        -- Not enough on this realm: borrow every realm's pairs. Wider than the
        -- truth if the player spans regions, but a real measurement of
        -- something beats an assumption about nothing.
        local pooled = {}
        for i = 1, #groups do AppendPairs(groups[i], pooled) end
        if #pooled >= MIN_PAIRS then
            pairs_, tier = pooled, "account"
        else
            -- The raw spread is not an acceptable fallback -- it is the
            -- drift-contaminated statistic this section exists to replace -- so
            -- hold the prior and report what is actually missing.
            return DEFAULT_JITTER, #pairs_, nil, "prior", #realmEntries
        end
    end

    local n = #pairs_
    local last = pairs_[n]
    if fitCache.n == n and fitCache.last == last and fitCache.tier == tier then
        return fitCache.sigma, n, fitCache.mad, tier, #realmEntries
    end

    -- The fit costs a tabulation pass on first use, and the new sample lands at
    -- UNIT_SPELLCAST_START -- mid-cast, with the fire frame still ahead. Serve
    -- the stale value until the attempt is over.
    if attempt then
        return fitCache.sigma, n, fitCache.mad, tier, #realmEntries
    end

    table.sort(pairs_)
    -- Median of |differences|, matched against the model's own MAD. Deliberately
    -- unscaled: the normal-consistency factor would be wrong for this mixture.
    local mad = pairs_[math.ceil(n / 2)]

    fitCache.n, fitCache.last, fitCache.tier = n, last, tier
    fitCache.mad = mad
    fitCache.sigma = FitSigmaFromDiff(mad)
    return fitCache.sigma, n, mad, tier, #realmEntries
end

local function RecordRTTSample(delta)
    if type(delta) ~= "number" or delta <= 0 or delta > 2 then return end
    local r = RealmStore()
    local now = time()
    -- Store the client's own reported world latency alongside the measurement.
    -- It is coarse and smoothed, but it is enough to tell whether the baseline
    -- moved between two samples -- which is what separates slow drift from the
    -- short-timescale jitter that actually breaks a batch.
    local _, _, _, world = GetNetStats and GetNetStats()
    r.rtt[#r.rtt + 1] = { t = now, v = delta, lat = tonumber(world) or nil }
    Prune(r.rtt, MAX_RTT_SAMPLES, now)
end

-- Returns probability (0-1), frame interval, corrected jitter sigma, sample
-- count, and the raw observed spread before quantization was removed.
function HB:Estimate(frameInterval)
    local d = frameInterval or CurrentFrameInterval()
    local sigma, pairCount, observed, tier, sampleCount = JitterSigma()
    local lead = Lead()
    local a = d / 2

    local p = SumCDF(lead, a, sigma) - SumCDF(lead - BATCH_WINDOW, a, sigma)
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p, d, sigma, pairCount, observed, tier, sampleCount
end


-- bind changed + we moved  -> the confirm landed in the cast's tick   (success)
-- bind changed + we stayed -> confirm landed in an earlier tick       (early)
-- bind unchanged           -> confirm arrived after the teleport      (late)
-- -----------------------------------------------------------------------------
-- The model is noisy at low sample counts and assumes a 10ms batch window we
-- cannot verify, while the observed hit rate is unbiased but slow to converge.
-- Blend them: treat the model as a Beta prior whose weight scales with how many
-- clean sample pairs back it, and
-- update with the real record. Early on the model dominates; after a few dozen
-- hearths the truth takes over, whatever the model believed.
-- The model's authority has to scale with how much it actually knows. A fit
-- from a handful of noisy pairs should not outvote a real record: at 4/4 with a
-- badly-fitted 18% model, a flat weight of 6 dragged the readout to 51%, which
-- was the model asserting confidence it had not earned.
local PRIOR_WEIGHT_MAX = 6
local PRIOR_WEIGHT_MIN = 1.5
local PRIOR_FULL_PAIRS = 12

local function PriorWeight(pairCount, tier)
    if tier == "prior" then
        -- Pure assumption. Keep just enough weight to give a fresh account a
        -- starting number, and let the first few real outcomes dominate.
        return PRIOR_WEIGHT_MIN
    end
    local frac = (pairCount or 0) / PRIOR_FULL_PAIRS
    if frac > 1 then frac = 1 end
    return PRIOR_WEIGHT_MIN + (PRIOR_WEIGHT_MAX - PRIOR_WEIGHT_MIN) * frac
end

function HB:SuccessChance()
    local modelP, _, _, pairCount, _, jitterTier = self:Estimate()
    local hits, attempts, tier = CollectOutcomes()
    local w = PriorWeight(pairCount, jitterTier)
    local blended = ((modelP * w) + hits) / (w + attempts)
    if blended < 0 then blended = 0 elseif blended > 1 then blended = 1 end
    return blended, modelP, hits, attempts, tier, w
end


-- bind changed + we moved  -> the confirm landed in the cast's tick   (success)
-- bind changed + we stayed -> confirm landed in an earlier tick       (early)
-- bind unchanged           -> confirm arrived after the teleport      (late)
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- Outcome classification and calibration
--
-- bind changed + we moved  -> the confirm landed in the cast's tick   (success)
-- bind changed + we stayed -> confirm landed in an earlier tick       (early)
-- bind unchanged           -> confirm arrived after the teleport      (late)
-- -----------------------------------------------------------------------------
local function Nudge(deltaSeconds, why)
    local r = RealmStore()
    local before = Lead()
    local after = before + deltaSeconds
    if after < MIN_LEAD then after = MIN_LEAD end
    if after > MAX_LEAD then after = MAX_LEAD end
    -- Calibration is realm-scoped: the next character on this realm inherits it.
    r.lead = after
    if after ~= before and DB().hearthBatchVerbose then
        ns:Chat("Hearth", string.format("%s -- lead %.1fms -> %.1fms",
            why, before * 1000, after * 1000))
    end
end

local function ReportFrameBudget(interval, windowGuess)
    if not interval or interval <= 0 then return end
    local ms = interval * 1000
    if ms <= windowGuess then return end
    ns:Chat("Hearth", string.format(
        "frame interval was %.1fms against a ~%.0fms window -- batching is unreliable below ~%dfps. Check vsync and any fps cap.",
        ms, windowGuess, math.ceil(1000 / windowGuess) * 2))
end

-- Where the player is, for the movement test. Map position beats zone text: it
-- survives a hearth home whose subzone name matches the inn's, and it does not
-- depend on the zone string having refreshed after a loading screen.
local function PositionSnapshot()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or not pos.GetXY then return { map = mapID } end
    local x, y = pos:GetXY()
    return { map = mapID, x = x, y = y }
end

-- A batch always teleports you. The question is *where to*: on a hit you land at
-- the old home, and on an early fire the bind was already updated so you land at
-- the inn you are standing in -- a teleport that moves you a few yards at most.
-- So the discriminator is a large displacement, not the existence of a teleport.
local MOVE_THRESHOLD = 0.05  -- normalized map units

local function Moved(before, after)
    if not before or not after then return nil end          -- unknowable
    if not before.map or not after.map then return nil end
    if before.map ~= after.map then return true end          -- different map: certain
    if not (before.x and before.y and after.x and after.y) then return nil end
    local dx, dy = after.x - before.x, after.y - before.y
    return math.sqrt(dx * dx + dy * dy) > MOVE_THRESHOLD
end

-- Returns outcome, new bind location. Outcome may be "unknown": position data
-- was unavailable, so we cannot tell a hit from an early fire.
local function Classify(a)
    local bindAfter = GetBindLocation()
    local bindChanged = (bindAfter ~= nil and bindAfter ~= a.bindBefore)

    if not bindChanged then
        -- The confirm never landed, so we teleported with the old bind intact.
        -- No position test needed: this one is unambiguous.
        return "late", bindAfter
    end

    local moved = Moved(a.posBefore, PositionSnapshot())
    if moved == nil then return "unknown", bindAfter end
    return moved and "success" or "early", bindAfter
end

local function FinishAttempt(a)
    if not a or a.classified then return end
    a.classified = true

    -- A cast-end event arrived before we fired and we could not confirm the
    -- cast actually completed, so we cannot tell a hit from an interrupted cast
    -- whose confirm still landed. Same rule as an unknown position read.
    if a.suspect then
        if DB().hearthBatchVerbose then
            ns:Chat("Hearth", string.format(
                "batch result unclear (%s near cast end) -- calibration unchanged",
                tostring(a.suspect)))
        end
        return
    end

    local outcome = Classify(a)

    -- A misclassification is not neutral: a false "early" walks the lead toward
    -- the edge of the window and makes real failures more likely, so an
    -- uncertain read must change nothing. Record no outcome and nudge nothing.
    if outcome == "unknown" then
        if DB().hearthBatchVerbose then
            ns:Chat("Hearth", "batch result unclear (no position data) -- calibration unchanged")
        end
        return
    end

    local r = RealmStore()
    local now = time()
    r.outcomes[#r.outcomes + 1] = { t = now, ok = (outcome == "success") }
    Prune(r.outcomes, MAX_OUTCOMES, now)

    if outcome == "success" then
        if DB().hearthBatchVerbose then
            local hits, attempts = CollectOutcomes()
            ns:Chat("Hearth", string.format("batch hit (%d/%d recent)", hits, attempts))
        end
        return
    end

    if outcome == "early" then
        -- Landed in an earlier tick: aim closer to the cast end.
        Nudge(-LEAD_STEP, "bound but landed at the new home (fired early)")
    else
        -- Arrived after the teleport: aim further ahead of the cast end.
        Nudge(LEAD_STEP, "teleported without rebinding (fired late)")
    end

    ReportFrameBudget(a.fireInterval, 10)
end

-- -----------------------------------------------------------------------------
-- The driver
--
-- Nearest-frame selection, not first-frame-past-target. The send lands on some
-- frame boundary either side of the target; firing on whichever boundary is
-- closest centres the error at +/- half a frame instead of letting it run a
-- full frame late, which is the unsafe direction.
-- -----------------------------------------------------------------------------
local function OnDriverUpdate(self, elapsed)
    local a = attempt
    if not a then
        self:SetScript("OnUpdate", nil)
        self:Hide()
        return
    end

    SampleFrame(elapsed)

    local now = GetTime()
    local remaining = a.target - now
    if remaining <= 0 then
        HB:Fire("target passed")
        return
    end

    -- If the next frame would land beyond the target, this frame is the closest
    -- boundary we will get.
    local interval = FrameInterval()
    if remaining < (interval * 0.5) then
        HB:Fire("nearest frame")
    end
end

function HB:Fire(reason)
    local a = attempt
    if not a or a.fired then return end
    a.fired = true
    a.fireTime = GetTime()
    a.fireInterval = FrameInterval()
    a.fireReason = reason

    if driver then
        driver:SetScript("OnUpdate", nil)
        driver:Hide()
    end

    -- Only worth sending if the popup survived the cast; if the player answered
    -- or moved out of range there is nothing to confirm.
    if BinderPopupVisible() and ConfirmBinder then
        ConfirmBinder()
    else
        a.classified = true
    end

    RestoreFPS()

    -- Do NOT classify on a fixed delay. A hearth teleport runs a loading screen,
    -- and position/zone APIs read stale or empty until it completes -- that race
    -- is what made a genuine hit report as "did not teleport". PLAYER_ENTERING_WORLD
    -- is the real signal; this timer is only the backstop for a hearth that never
    -- crossed a map boundary and so never loaded.
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            FinishAttempt(a)
            if attempt == a then attempt = nil end
        end)
    else
        attempt = nil
    end
end

local function AbortAttempt(why)
    local a = attempt
    attempt = nil
    if driver then
        driver:SetScript("OnUpdate", nil)
        driver:Hide()
    end
    RestoreFPS()
    if a and not a.fired and DB().hearthBatchVerbose then
        ns:Chat("Hearth", "batch aborted (" .. tostring(why) .. ")")
    end
end

local function StartAttempt()
    if not Enabled() or attempt then return end
    if not BinderPopupVisible() then return end
    if not driver then return end

    -- The anchor is this frame's boundary: the frame from which the use packet
    -- is sent. See the ANCHOR note at the top of the file.
    local anchor = GetTime()

    attempt = {
        anchor     = anchor,
        target     = anchor + CAST_SECONDS - Lead(),
        bindBefore = GetBindLocation(),
        posBefore  = PositionSnapshot(),
        fired      = false,
    }

    ResetFrameSamples()
    RaiseFPS()

    driver:Show()
    driver:SetScript("OnUpdate", OnDriverUpdate)

    -- Watchdog: nothing may strand maxfps, even if every cast event is missed.
    if C_Timer and C_Timer.After then
        local a = attempt
        C_Timer.After(CAST_SECONDS + 3, function()
            if attempt == a and not a.fired then AbortAttempt("watchdog") end
        end)
    end
end

-- -----------------------------------------------------------------------------
-- Events and hooks
-- -----------------------------------------------------------------------------
local function OnEvent(self, event, unit, _, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Recover a maxfps snapshot stranded by a crash or disconnect mid-cast.
        RestoreFPS()

        -- The hearth's loading screen just finished, so this is the earliest
        -- point the new position is real. Settle briefly first: map data can lag
        -- the event by a frame or two.
        local a = attempt
        if a and a.fired and not a.classified then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, function()
                    FinishAttempt(a)
                    if attempt == a then attempt = nil end
                end)
            else
                FinishAttempt(a)
                attempt = nil
            end
        end
        return
    end

    if unit ~= "player" then return end
    if spellID ~= HEARTHSTONE_SPELL and spellID ~= ASTRAL_RECALL then return end

    if event == "UNIT_SPELLCAST_START" then
        -- Not used for timing (see ANCHOR): only to confirm the cast began, and
        -- to sample how long the round trip took. The spread of those samples
        -- feeds the jitter term in HB:Estimate.
        local a = attempt
        if a then
            a.castConfirmed = true
            local startTime = select(4, UnitCastingInfo("player"))
            if startTime and startTime > 0 then
                RecordRTTSample((startTime / 1000) - a.anchor)
            end
        end
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Definitive completion. Never an abort, whatever arrives afterwards.
        local a = attempt
        if a then a.succeeded = true end
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_STOP" then
        local a = attempt
        if not a or a.fired then return end

        -- STOP also fires on a successful cast. Ordinarily it arrives well after
        -- we fire -- the client only learns the cast ended once the server says
        -- so, about a round trip after the moment we aim at -- but the margin is
        -- only as wide as the lead if the message arrives early, and aborting
        -- here would tear the driver down and lose a batch that was about to
        -- land. So inside the grace window we do NOT abort.
        local nearEnd = (GetTime() >= (a.target - CAST_END_GRACE))
        if a.succeeded or nearEnd then
            -- Let the driver fire. But a real interrupt this late would send a
            -- confirm with no teleport behind it, which classifies as "bound but
            -- landed at the new home" and would nudge the lead the wrong way.
            -- Mark it so the attempt records nothing rather than mislearning.
            if not a.succeeded then a.suspect = event end
            return
        end

        AbortAttempt(event)
    end
end

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- Predicate-gated one-way hooks (ARCHITECTURE.md 1.3): installed on first
    -- enable and inert afterwards, since hooksecurefunc cannot be removed.
    if _G.C_Container and _G.C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(...)
            if not Enabled() then return end
            if C_Container.GetContainerItemID(...) == HEARTHSTONE_ITEM then
                StartAttempt()
            end
        end)
    elseif _G.UseContainerItem then
        hooksecurefunc("UseContainerItem", function(...)
            if not Enabled() then return end
            if _G.GetContainerItemID(...) == HEARTHSTONE_ITEM then
                StartAttempt()
            end
        end)
    end

    hooksecurefunc("UseAction", function(...)
        if not Enabled() then return end
        local kind, id = GetActionInfo(...)
        if kind == "item" and id == HEARTHSTONE_ITEM then
            StartAttempt()
        elseif kind == "spell" and id == ASTRAL_RECALL then
            StartAttempt()
        elseif kind == "macro" and IsCurrentSpell
                and (IsCurrentSpell(HEARTHSTONE_SPELL) or IsCurrentSpell(ASTRAL_RECALL)) then
            StartAttempt()
        end
    end)
end

local function SetEvents(active)
    if not events then return end
    events:UnregisterAllEvents()
    if not active then return end
    -- player-only: the handler discards every other unit (see OnEvent).
    ns.RegisterUnitEvent(events, "UNIT_SPELLCAST_START", "player")
    ns.RegisterUnitEvent(events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ns.RegisterUnitEvent(events, "UNIT_SPELLCAST_INTERRUPTED", "player")
    ns.RegisterUnitEvent(events, "UNIT_SPELLCAST_FAILED", "player")
    ns.RegisterUnitEvent(events, "UNIT_SPELLCAST_STOP", "player")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- -----------------------------------------------------------------------------
-- Public surface
-- -----------------------------------------------------------------------------
-- Scope defaults to this realm. "all" wipes every realm's pool, which is the
-- right move after an ISP or hardware change invalidates the whole history.
function HB:ResetCalibration(scope)
    if scope == "all" then
        local hb = Store()
        hb.realms = {}
        fitCache.n, fitCache.tier = -1, nil
        ns:Chat("Hearth", "calibration reset for all realms")
        return
    end

    local key = RealmKey()
    Store().realms[key] = nil
    fitCache.n, fitCache.tier = -1, nil
    ns:Chat("Hearth", string.format("calibration reset for %s -- lead %.1fms",
        key, Lead() * 1000))
end

function HB:Status()
    local blended, modelP, hits, attempts, outcomeTier = self:SuccessChance()
    local _, d, sigma, pairCount, observed, jitterTier, sampleCount = self:Estimate()

    local function Scope(tier)
        if tier == "realm" then return RealmKey()
        elseif tier == "account" then return "all realms" end
        return "assumed"
    end

    ns:Chat("Hearth", string.format("success chance |cff00ccff%.0f%%|r  (model %.0f%%, frame %.1fms)",
        blended * 100, modelP * 100, d * 1000))

    if jitterTier == "prior" then
        -- Say which of the two is missing: too few samples, or samples whose
        -- pairs were all rejected as too far apart or baseline-drifted.
        local why
        if (sampleCount or 0) < 2 then
            why = string.format("%d samples, need 2+ to form any pair", sampleCount or 0)
        else
            why = string.format("%d samples but only %d clean pairs, need %d",
                sampleCount, pairCount or 0, MIN_PAIRS)
        end
        ns:Chat("Hearth", string.format("jitter %.1fms assumed -- %s | lead %.1fms",
            sigma * 1000, why, Lead() * 1000))
    else
        ns:Chat("Hearth", string.format("jitter %.1fms from %d pairs of %d samples (%s), pair MAD %.1fms | lead %.1fms",
            sigma * 1000, pairCount, sampleCount or 0, Scope(jitterTier),
            (observed or 0) * 1000, Lead() * 1000))
    end

    if attempts > 0 then
        ns:Chat("Hearth", string.format("recent record %d/%d (%.0f%%) across %s",
            hits, attempts, hits / attempts * 100, Scope(outcomeTier)))
    else
        ns:Chat("Hearth", "no attempts recorded yet")
    end
end

function HB:Init()
    -- Fold any pre-pool per-character data in before anything reads the store.
    MigrateCharData()
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    -- Always recover a stranded snapshot, even when the feature is off now.
    RestoreFPS()
    self:Refresh()
end

function HB:Refresh()
    local on = Enabled()
    if on then InstallHooks() end
    SetEvents(on)
    if not on then AbortAttempt("disabled") end
end
