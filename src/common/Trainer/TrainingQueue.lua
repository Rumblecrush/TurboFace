local _, ns = ...
local Trainer = ns.Trainer

-- =============================================================================
-- TRAINING QUEUE
--
-- Per-character, explicit opt-in auto-training. A queue record identifies one
-- exact class spell rank, one general Skill (weapon/profession starter), or one
-- trainer-taught profession skill. Records remain
-- queued while unavailable or unaffordable and are removed only once the
-- service is confirmed learned/used (or the player manually removes it).
-- =============================================================================

local attemptedThisVisit = {}
local purchaseInFlight = false
local purchaseBatchID = 0
local insufficientFundsNotified = false
local trainerApiWarningShown = false
local spellDataRetryScheduled = false
local lastQueueTrace = { reason = "never-run" }

local function SetQueueTrace(reason, detail)
    lastQueueTrace.reason = reason
    lastQueueTrace.detail = detail
    lastQueueTrace.time = GetTime and GetTime() or nil
end

local function GetQueue()
    local ch = TurboFaceTrainerCharDB and TurboFaceTrainerCharDB.character
    if not ch then return nil end
    if type(ch.trainingQueue) ~= "table" then ch.trainingQueue = {} end
    return ch.trainingQueue
end

local function NormalizeOwner(owner)
    if owner == nil then return nil end
    return tostring(owner)
end

local function QueueFallbackLess(a, b)
    local ar, br = a.record, b.record
    local aOrder = tonumber(ar.order)
    local bOrder = tonumber(br.order)
    if aOrder and bOrder and aOrder ~= bOrder then return aOrder < bOrder end
    if aOrder and not bOrder then return true end
    if bOrder and not aOrder then return false end

    local aLevel = tonumber(ar.level) or 0
    local bLevel = tonumber(br.level) or 0
    if aLevel ~= bLevel then return aLevel < bLevel end

    local aSpell = tonumber(ar.spellID)
    local bSpell = tonumber(br.spellID)
    if aSpell and bSpell and aSpell ~= bSpell then return aSpell < bSpell end
    if aSpell and not bSpell then return true end
    if bSpell and not aSpell then return false end

    local aName = tostring(ar.name or "")
    local bName = tostring(br.name or "")
    if aName ~= bName then return aName < bName end
    return tostring(a.key) < tostring(b.key)
end

local function GetOrderedContextQueue(queue, scope, owner)
    local list = {}
    owner = NormalizeOwner(owner)
    for key, record in pairs(queue or {}) do
        if record.scope == scope and NormalizeOwner(record.owner) == owner then
            list[#list + 1] = { key = key, record = record }
        end
    end

    table.sort(list, QueueFallbackLess)

    -- Normalize to a compact 1..N priority sequence. This also migrates queues
    -- created before explicit ordering existed: their first order matches the
    -- old UI's deterministic level/spell ordering, then becomes persistent.
    for index, item in ipairs(list) do
        item.record.order = index
    end
    return list
end

local function RefreshQueueDisplays(scope)
    if scope == "profession" then
        if Trainer.ProfessionRefresh then Trainer.ProfessionRefresh() end
    else
        if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList()
        elseif Trainer.RefreshList then Trainer.RefreshList() end
    end
end

function Trainer:GetTrainingQueueKey(entry, scope, owner)
    if not entry or not scope or not owner then return nil end
    owner = NormalizeOwner(owner)
    local identity
    if self:IsSaneSpellID(entry.spellID) then
        identity = "spell:" .. tostring(entry.spellID)
    elseif entry.name then
        identity = table.concat({
            "name", tostring(entry.name),
            "rank", tostring(entry.rankNum or 0),
            "level", tostring(entry.level or 0),
        }, ":")
    else
        return nil
    end
    return tostring(scope) .. "|" .. owner .. "|" .. identity
end

function Trainer:PrepareTrainingQueueEntry(entry, scope, owner)
    if not entry or not scope or not owner then return nil end
    local key = self:GetTrainingQueueKey(entry, scope, owner)
    entry.trainingQueueScope = scope
    entry.trainingQueueOwner = NormalizeOwner(owner)
    entry.trainingQueueKey = key
    return key
end

function Trainer:IsEntryQueued(entry)
    local queue = GetQueue()
    local key = entry and entry.trainingQueueKey
    return queue and key and queue[key] ~= nil or false
end

function Trainer:RemoveEntryFromTrainingQueue(entry)
    local queue = GetQueue()
    local key = entry and entry.trainingQueueKey
    if queue and key then queue[key] = nil end
end

function Trainer:ToggleTrainingQueue(entry)
    if not entry or not entry.trainingQueueKey then return end
    local queue = GetQueue()
    if not queue then return end

    local key = entry.trainingQueueKey
    if queue[key] then
        queue[key] = nil
        GetOrderedContextQueue(queue, entry.trainingQueueScope, entry.trainingQueueOwner)
    else
        local contextQueue = GetOrderedContextQueue(queue, entry.trainingQueueScope, entry.trainingQueueOwner)
        queue[key] = {
            scope = entry.trainingQueueScope,
            owner = entry.trainingQueueOwner,
            spellID = entry.spellID,
            name = entry.name,
            rankNum = entry.rankNum,
            hasRealRank = entry.hasRealRank and true or false,
            level = entry.level,
            order = #contextQueue + 1,
        }
    end

    RefreshQueueDisplays(entry.trainingQueueScope)
end

function Trainer:GetTrainingQueueOrder(entry)
    local queue = GetQueue()
    local key = entry and entry.trainingQueueKey
    if not queue or not key or not queue[key] then return nil end
    local record = queue[key]
    GetOrderedContextQueue(queue, record.scope, record.owner)
    return tonumber(record.order)
end

function Trainer:CanMoveTrainingQueueEntry(entry, direction)
    local queue = GetQueue()
    local key = entry and entry.trainingQueueKey
    local record = queue and key and queue[key]
    if not record then return false end

    local ordered = GetOrderedContextQueue(queue, record.scope, record.owner)
    for index, item in ipairs(ordered) do
        if item.key == key then
            local target = index + direction
            return target >= 1 and target <= #ordered
        end
    end
    return false
end

function Trainer:MoveTrainingQueueEntry(entry, direction)
    direction = direction < 0 and -1 or 1
    local queue = GetQueue()
    local key = entry and entry.trainingQueueKey
    local record = queue and key and queue[key]
    if not record then return end

    local ordered = GetOrderedContextQueue(queue, record.scope, record.owner)
    for index, item in ipairs(ordered) do
        if item.key == key then
            local target = index + direction
            if target < 1 or target > #ordered then return end
            item.record.order, ordered[target].record.order = ordered[target].record.order, item.record.order
            GetOrderedContextQueue(queue, record.scope, record.owner)
            RefreshQueueDisplays(record.scope)
            return
        end
    end
end

function Trainer:SetTrainingQueueRuntime(active)
    if active then return end
    -- Invalidate any delayed fallback from a purchase batch that was started
    -- before Trainer was switched off. The callback may still wake once, but
    -- its batch id can no longer match and no trainer work is resurrected.
    purchaseBatchID = purchaseBatchID + 1
    purchaseInFlight = false
    wipe(attemptedThisVisit)
    insufficientFundsNotified = false
    trainerApiWarningShown = false
end

function Trainer:BeginTrainingQueueVisit()
    wipe(attemptedThisVisit)
    purchaseInFlight = false
    purchaseBatchID = purchaseBatchID + 1
    insufficientFundsNotified = false
    trainerApiWarningShown = false
end

function Trainer:EndTrainingQueueVisit()
    -- Invalidate purchase/spell-data fallback timers from the trainer that just
    -- closed. The next TRAINER_SHOW starts with a fresh attempt set.
    purchaseBatchID = purchaseBatchID + 1
    purchaseInFlight = false
    spellDataRetryScheduled = false
end

-- A trainer refresh is the authoritative signal that the previous purchase
-- batch has reached the client. Let the normal delayed capture rescan the
-- refreshed list immediately instead of waiting for the fallback timer.
function Trainer:TrainingQueueTrainerUpdated()
    if purchaseInFlight then
        purchaseInFlight = false
    end
end

local function RankNumber(rankText)
    if type(rankText) ~= "string" then return 0 end
    return tonumber(rankText:match("%d+")) or 0
end

local function QueueRecordMatchesService(record, serviceName, serviceRank, serviceSpellID)
    if not record or not serviceName then return false end

    -- Numeric spell identity is authoritative whenever both sides have it.
    -- Never fall through from a numeric mismatch to same-name matching: clients
    -- can omit trainer rank text, so multiple ranks may share one serviceName.
    -- Falling through here can let an unavailable later rank overwrite the
    -- available exact-rank service in servicesByKey.
    if record.spellID and serviceSpellID then
        return record.spellID == serviceSpellID
    end

    -- Compatibility fallback only for trainer snapshots where one side truly
    -- lacks a usable numeric spell ID. Real rank text remains a disambiguator
    -- when Blizzard exposes it; otherwise same-name fallback is intentionally
    -- limited to the no-ID case above.
    if record.name ~= serviceName then return false end
    if record.hasRealRank then
        return (record.rankNum or 0) == RankNumber(serviceRank)
    end
    return true
end

local function FindQueueMatch(queue, scope, owner, serviceName, serviceRank, serviceSpellID)
    for key, record in pairs(queue) do
        if record.scope == scope and NormalizeOwner(record.owner) == owner
            and QueueRecordMatchesService(record, serviceName, serviceRank, serviceSpellID) then
            return key, record
        end
    end
end

local function GetOpenTrainerQueueContext(queue)
    local _, classToken = UnitClass("player")
    local skillsOwner = NormalizeOwner(classToken)

    -- General-skill trainers are heterogeneous: weapon masters and unlearned
    -- profession starters may use the same Blizzard trainer frame, while an
    -- already-known profession trainer can also expose its Apprentice starter
    -- as a USED row. Give the Skills queue control only when this exact trainer
    -- actually offers a queued Skills service. That prevents a harmless USED
    -- starter row from stealing an ordinary profession auto-training session.
    if Trainer.currentTrainerHasGeneralSkills and skillsOwner and GetNumTrainerServices then
        for i = 1, GetNumTrainerServices() do
            local serviceName, serviceRank, serviceType = Trainer:GetTrainerServiceInfoCompat(i)
            if serviceName and serviceType ~= "header" then
                local serviceSpellID = Trainer:GetSpellIDForService(i)
                local generalSkillID = Trainer:ResolveGeneralSkillSpellID(serviceSpellID, serviceName, serviceRank)
                if generalSkillID then
                    local key = FindQueueMatch(queue, "skills", skillsOwner, serviceName, serviceRank, generalSkillID)
                    if key then return "skills", skillsOwner end
                end
            end
        end
    end

    if IsTradeskillTrainer and IsTradeskillTrainer() then
        local professionKey = Trainer:DetectTrainerProfession()
        if professionKey then return "profession", NormalizeOwner(professionKey) end
        return nil, nil
    end

    -- A weapon master/general-skill trainer with no matching queued Skills row
    -- should do nothing, not masquerade as the player's class trainer.
    if Trainer.currentTrainerHasGeneralSkills then return nil, nil end

    if classToken then return "class", NormalizeOwner(classToken) end
    return nil, nil
end

local function IsQueueRecordKnown(record)
    local spellID = record and record.spellID
    if not spellID then return false end
    if record.scope == "skills" and Trainer:IsProfessionStarterSpell(spellID)
        and Trainer.IsProfessionStarterKnown and Trainer:IsProfessionStarterKnown(spellID) then
        return true
    end
    if record.scope == "skills" and Trainer:IsProfessionRankSpell(spellID)
        and Trainer.IsProfessionRankSpellKnown and Trainer:IsProfessionRankSpellKnown(spellID) then
        return true
    end
    if ns.API and ns.API.IsKnownSpellID and ns.API.IsKnownSpellID(spellID) then return true end
    return false
end

local function IsQueueRecordUnavailable(record)
    local spellID = record and record.spellID
    if not spellID or record.scope ~= "skills" then return false end
    if Trainer:IsProfessionRankSpell(spellID)
        and Trainer.IsProfessionRankTrainable
        and not Trainer:IsProfessionRankTrainable(spellID) then
        return true
    end
    return Trainer.IsProfessionStarterUnavailable
        and Trainer:IsProfessionStarterUnavailable(spellID) or false
end

function Trainer:ProcessTrainingQueue()
    if not Trainer.tooltipActive then SetQueueTrace("inactive") return end
    if purchaseInFlight then SetQueueTrace("purchase-in-flight") return end

    local queue = GetQueue()
    if not queue or not next(queue) then SetQueueTrace("queue-empty") return end

    if type(GetNumTrainerServices) ~= "function"
        or type(GetTrainerServiceInfo) ~= "function"
        or type(BuyTrainerService) ~= "function" then
        SetQueueTrace("missing-api")
        if not trainerApiWarningShown then
            trainerApiWarningShown = true
            ns:Chat("Trainer", "|cffffcc00Auto-training API boundary missing.|r Open the trainer and run /tf debug trainer.")
        end
        return
    end

    -- On clients with load-on-demand C_Spell metadata, queue records already
    -- carry numeric IDs, so warm those IDs before resolving trainer rows by
    -- localized name. Clients without that API simply return false here.
    local requestedSpellData = false
    for _, record in pairs(queue) do
        if record and record.spellID and self:RequestSpellDataIfNeeded(record.spellID) then
            requestedSpellData = true
        end
    end
    if requestedSpellData and C_Timer and not spellDataRetryScheduled then
        spellDataRetryScheduled = true
        C_Timer.After(0.25, function()
            spellDataRetryScheduled = false
            if Trainer.tooltipActive then Trainer:ProcessTrainingQueue() end
        end)
    end

    local scope, owner = GetOpenTrainerQueueContext(queue)
    if not scope or not owner then SetQueueTrace("no-context") return end

    local hasContextQueue = false
    local prunedKnown = false
    for key, record in pairs(queue) do
        if record.scope == scope and NormalizeOwner(record.owner) == owner then
            if IsQueueRecordKnown(record) or IsQueueRecordUnavailable(record) then
                queue[key] = nil
                attemptedThisVisit[key] = nil
                prunedKnown = true
            else
                hasContextQueue = true
            end
        end
    end
    if prunedKnown then RefreshQueueDisplays(scope) end
    if not hasContextQueue then
        -- A stale Skills record can be the only reason this trainer initially
        -- selected the Skills context. Once it is pruned, immediately give an
        -- underlying profession context a chance in the same trainer refresh.
        if scope == "skills" then self:ProcessTrainingQueue() end
        SetQueueTrace("no-context-queue", tostring(scope) .. "/" .. tostring(owner))
        return
    end

    -- Trainer indices are affected by Blizzard's service filters. A queued
    -- purchase must be able to see "available" rows even if the player hid that
    -- category in the native trainer dropdown. Enabling it is harmless and the
    -- native UI immediately reflects the same state.
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter
        and not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", true)
        SetQueueTrace("enabling-available-filter")
        if C_Timer then C_Timer.After(0.1, function() Trainer:ProcessTrainingQueue() end) end
        return
    end

    self:ExpandAllTrainerHeaders()

    local queueChanged = false
    local candidates = {}
    local remainingMoney = GetMoney and (GetMoney() or 0) or 0
    local moneyBlockedThisPass = false
    local servicesByKey = {}
    local matchedServiceCount = 0

    -- First map the current trainer snapshot back to queue records. The service
    -- list order is Blizzard-owned and must not decide player priority.
    for i = 1, GetNumTrainerServices() do
        local serviceName, serviceRank, serviceType = self:GetTrainerServiceInfoCompat(i)
        if serviceName and serviceType ~= "header" then
            local serviceSpellID = self:GetSpellIDForService(i)
            if scope == "skills" then
                serviceSpellID = self:ResolveGeneralSkillSpellID(serviceSpellID, serviceName, serviceRank) or serviceSpellID
            end
            local key = FindQueueMatch(queue, scope, owner, serviceName, serviceRank, serviceSpellID)
            if key then
                matchedServiceCount = matchedServiceCount + 1
                if serviceType == "used" then
                    queue[key] = nil
                    attemptedThisVisit[key] = nil
                    queueChanged = true
                else
                    servicesByKey[key] = {
                        index = i,
                        serviceType = serviceType,
                        cost = tonumber(GetTrainerServiceCost and GetTrainerServiceCost(i)) or 0,
                    }
                end
            end
        end
    end

    if queueChanged then RefreshQueueDisplays(scope) end

    -- The visible Training Queue is the affordability priority. Walk its
    -- persistent order from top to bottom and reserve money in exactly that
    -- order. Unavailable entries are skipped for now, but an AVAILABLE entry
    -- that cannot be afforded blocks every lower-priority purchase this visit.
    -- This prevents a cheap lower row from jumping ahead of the player's first
    -- choice merely because Blizzard listed it earlier in the trainer window.
    local orderedQueue = GetOrderedContextQueue(queue, scope, owner)
    for _, item in ipairs(orderedQueue) do
        local key = item.key
        local service = servicesByKey[key]
        if service and service.serviceType == "available" and not attemptedThisVisit[key] then
            if service.cost <= remainingMoney then
                candidates[#candidates + 1] = { index = service.index, key = key, cost = service.cost }
                remainingMoney = remainingMoney - service.cost
            else
                moneyBlockedThisPass = true
                break
            end
        end
    end

    if moneyBlockedThisPass and not insufficientFundsNotified then
        insufficientFundsNotified = true
        ns:Chat("Trainer", "|cffffcc00Not enough money to train everything in your Training Queue.|r Unaffordable entries will stay queued.")
    end

    if #candidates == 0 then
        -- Same mixed-trainer case as the known-state prune above, except the
        -- trainer itself confirmed the Skills service as USED during mapping.
        if queueChanged and scope == "skills" then self:ProcessTrainingQueue() end
        SetQueueTrace("no-candidates", ("context=%s/%s matched=%d moneyBlocked=%s"):format(
            tostring(scope), tostring(owner), matchedServiceCount, tostring(moneyBlockedThisPass)))
        return
    end

    -- Queue order has already decided WHICH services receive the player's
    -- money. Buying a trainer service can reindex Blizzard's visible list, so
    -- submit that selected set from the bottom upward to keep lower indices
    -- stable. This internal API-call order never changes queue priority; newly
    -- unlocked ranks are picked up by the next trainer refresh/rescan.
    table.sort(candidates, function(a, b) return a.index > b.index end)

    purchaseInFlight = true
    purchaseBatchID = purchaseBatchID + 1
    local thisBatchID = purchaseBatchID
    local firstError

    for _, candidate in ipairs(candidates) do
        attemptedThisVisit[candidate.key] = true
        local ok, err = pcall(BuyTrainerService, candidate.index)
        if not ok and not firstError then
            firstError = err
        end
    end

    if firstError then
        ns:Chat("Trainer", "|cffff5555Auto-training error:|r " .. tostring(firstError))
    end
    SetQueueTrace(firstError and "purchase-error" or "purchase-submitted",
        ("count=%d error=%s"):format(#candidates, tostring(firstError)))

    -- Purchases normally fire TRAINER_UPDATE. Events.lua clears the in-flight
    -- gate on that refresh, allowing the normal 0.1s capture to immediately
    -- process newly unlocked ranks. Keep a fallback for client/server paths that
    -- coalesce or omit the event. The batch id prevents an older timer from
    -- clearing a newer batch's gate.
    if C_Timer then
        C_Timer.After(0.35, function()
            if thisBatchID ~= purchaseBatchID then return end
            purchaseInFlight = false
            if not Trainer.tooltipActive then return end
            if Trainer.CaptureTrainer then Trainer:CaptureTrainer() end
            Trainer:ProcessTrainingQueue()
        end)
    else
        purchaseInFlight = false
    end
end

-- Read-only live probe for the trainer compatibility boundary. It never
-- purchases anything. Run `/tf debug trainer` while the NPC trainer is open.
function Trainer:DebugTrainingQueue()
    local function Safe(v)
        if ns.API and ns.API.SafeToString then return ns.API.SafeToString(v, "<secret>") end
        local ok, text = pcall(tostring, v)
        return ok and text or "<unreadable>"
    end
    local function Bool(v) return v and "yes" or "no" end

    ns:Chat("TrainerDbg", ("active=%s queueDB=%s GetNum=%s GetInfo=%s GetCost=%s Buy=%s C_Trainer=%s C_SpellCache=%s"):format(
        Bool(Trainer.tooltipActive), Bool(TurboFaceTrainerCharDB and TurboFaceTrainerCharDB.character),
        Bool(type(GetNumTrainerServices) == "function"), Bool(type(GetTrainerServiceInfo) == "function"),
        Bool(type(GetTrainerServiceCost) == "function"), Bool(type(BuyTrainerService) == "function"),
        Bool(type(C_Trainer) == "table"),
        Bool(C_Spell and type(C_Spell.IsSpellDataCached) == "function")))

    local queue = GetQueue()
    local queueCount = 0
    for _ in pairs(queue or {}) do queueCount = queueCount + 1 end
    ns:Chat("TrainerDbg", "queueRecords=" .. tostring(queueCount)
        .. " lastProcess=" .. Safe(lastQueueTrace.reason) .. " detail=" .. Safe(lastQueueTrace.detail))
    local shown = 0
    for key, record in pairs(queue or {}) do
        shown = shown + 1
        if shown <= 12 then
            local cached = "n/a"
            if record.spellID and C_Spell and type(C_Spell.IsSpellDataCached) == "function" then
                local ok, value = pcall(C_Spell.IsSpellDataCached, record.spellID)
                if ok then cached = Safe(value) else cached = "error" end
            end
            ns:Chat("TrainerDbg", ("Q[%d] key=%s scope=%s owner=%s spell=%s name=%s rank=%s realRank=%s level=%s cached=%s known=%s attempted=%s"):format(
                shown, Safe(key), Safe(record.scope), Safe(record.owner), Safe(record.spellID), Safe(record.name),
                Safe(record.rankNum), Safe(record.hasRealRank), Safe(record.level), cached, Safe(IsQueueRecordKnown(record)),
                Safe(attemptedThisVisit[key])))
        end
    end
    if queueCount > 12 then ns:Chat("TrainerDbg", "queue output truncated at 12") end

    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then
        ns:Chat("TrainerDbg", "Cannot enumerate trainer rows: service API missing.")
        return
    end

    local okCount, countOrErr = pcall(GetNumTrainerServices)
    if not okCount then
        ns:Chat("TrainerDbg", "GetNumTrainerServices ERROR: " .. Safe(countOrErr))
        return
    end
    local count = tonumber(countOrErr) or 0
    ns:Chat("TrainerDbg", "trainerServices=" .. Safe(countOrErr) .. " currentTrainerHasGeneralSkills=" .. Safe(Trainer.currentTrainerHasGeneralSkills))

    local scope, owner = GetOpenTrainerQueueContext(queue or {})
    ns:Chat("TrainerDbg", "resolvedContext=" .. Safe(scope) .. "/" .. Safe(owner))

    for i = 1, math.min(count, 30) do
        local okRaw, a, b, c, d = pcall(GetTrainerServiceInfo, i)
        if not okRaw then
            ns:Chat("TrainerDbg", ("S[%d] GetInfo ERROR=%s"):format(i, Safe(a)))
        else
            local name, rank, category, expanded, layout = self:GetTrainerServiceInfoCompat(i)
            local levelReq = GetTrainerServiceLevelReq and select(2, pcall(GetTrainerServiceLevelReq, i)) or nil
            local cost = GetTrainerServiceCost and select(2, pcall(GetTrainerServiceCost, i)) or nil
            local spellID = self:GetSpellIDForService(i)
            local matchKey = nil
            if scope and owner and name and category ~= "header" then
                local matchSpellID = spellID
                if scope == "skills" then
                    matchSpellID = self:ResolveGeneralSkillSpellID(matchSpellID, name, rank) or matchSpellID
                end
                matchKey = FindQueueMatch(queue or {}, scope, owner, name, rank, matchSpellID)
            end
            ns:Chat("TrainerDbg", ("S[%d] raw={%s | %s | %s | %s} norm={name=%s rank=%s type=%s expanded=%s layout=%s} level=%s cost=%s spell=%s match=%s"):format(
                i, Safe(a), Safe(b), Safe(c), Safe(d), Safe(name), Safe(rank), Safe(category), Safe(expanded),
                Safe(layout), Safe(levelReq), Safe(cost), Safe(spellID), Safe(matchKey)))
        end
    end
    if count > 30 then ns:Chat("TrainerDbg", "trainer row output truncated at 30") end
end

