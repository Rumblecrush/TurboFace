local addonName, ns = ...

-- =============================================================================
-- TurboFace Debug.lua — lightweight diagnostics harness (G5)
--
--   /tf debug          toggle the live stats readout
--   /tf debug cpu      addon CPU/memory snapshot (needs scriptProfile CVar)
--   /tf debug cpu start/stop/report  subsystem peak profiler (0.5s windows)
--   /tf debug reset    zero the counters
--   /tf debug popups   print every StaticPopup_Show name (popup identification)
--   /tf debug modules  print module / Movers / Plus effective activation state
--   /tf debug regen    print shared regen heartbeat / 5SR source state
--   /tf debug meter    print Combat Meter runtime/current/overall state
--   /tf debug cvars    open the developer CVar browser
--   /tf debug hptext   inspect native health-text centering/anchors
--
-- Design: hot paths do `local dc = ns.DebugCounters; if dc then ... end`.
-- When debug is OFF, ns.DebugCounters is nil, so the cost at every
-- instrumented site is one table lookup + branch. No allocations either way.
-- =============================================================================

local Debug = {}
ns.Debug = Debug
local UnitGUID = ns.API.ReadUnitGUID

ns.DebugCounters = nil  -- nil = disabled (hot-path contract)

-- -----------------------------------------------------------------------------
-- Retired diagnostic cleanup (0.17.35).
--
-- The temporary action-bar taint tracer persisted its arm state across reloads and
-- temporarily raised Blizzard's taintLog CVar. Restore the pre-debug value once
-- for users upgrading while the tracer was armed, then discard all diagnostic
-- cache keys. This has no ongoing runtime role after the first load.
-- -----------------------------------------------------------------------------
do
    if type(TurboFaceCacheDB) == "table" then
        local previous = TurboFaceCacheDB.taintDebugPreviousLogLevel
        if SetCVar and previous ~= nil and tostring(previous) ~= "unavailable" then
            pcall(SetCVar, "taintLog", tostring(previous))
        end
        TurboFaceCacheDB.taintDebugArmed = nil
        TurboFaceCacheDB.taintDebugPreviousLogLevel = nil
        TurboFaceCacheDB.taintDebugLastIncident = nil
    end
end

local COUNTER_KEYS = {
    "cleu",          -- combat log events decoded
    "cleuHandlers",  -- filtered consumer calls actually dispatched
    "unitAura",      -- UNIT_AURA events seen
    "auraFlush",     -- aura batch flushes
    "healthTick",    -- dirty-health batch runs
    "plateAdded",    -- nameplates assigned
}

local function NewCounters()
    local t = {}
    for _, k in ipairs(COUNTER_KEYS) do t[k] = 0 end
    return t
end

-- -----------------------------------------------------------------------------
-- SafeCall: module-entry error isolation. A broken module logs loudly once
-- instead of killing everything after it in the init chain.
-- -----------------------------------------------------------------------------
local reported = {}
function ns.SafeCall(tag, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok and not reported[tag] then
        reported[tag] = true
        ns:Chat("Debug", ("|cffff5555%s failed:|r %s"):format(tostring(tag), tostring(err)))
    end
    return ok
end

-- -----------------------------------------------------------------------------
-- Live readout frame (movable, 1s refresh)
-- -----------------------------------------------------------------------------
local frame
local lastMem = 0

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "TurboFaceDebugFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(230, 110)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -120)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    if ns.ApplyBarBackdrop then ns:ApplyBarBackdrop(frame) end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("|cff00ccffTurbo|cffffffffFace|r debug (/tf debug)")

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 8, -22)
    text:SetJustifyH("LEFT")
    text:SetSpacing(2)
    frame.text = text

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 1 then return end
        local dt = self.elapsed
        self.elapsed = 0
        local dc = ns.DebugCounters
        if not dc then return end

        local mem = collectgarbage and collectgarbage("count") or 0
        local memDelta = (mem - lastMem) / dt
        lastMem = mem

        self.text:SetFormattedText(
            "CLEU/s: %.0f   handlers/s: %.0f\nUNIT_AURA/s: %.0f   Aura flush/s: %.0f\nHP batch/s: %.0f   Plate adds/s: %.0f\nLua mem: %.1f MB  (%+.0f KB/s total)",
            dc.cleu / dt, dc.cleuHandlers / dt,
            dc.unitAura / dt, dc.auraFlush / dt,
            dc.healthTick / dt, dc.plateAdded / dt,
            mem / 1024, memDelta)
        for _, k in ipairs(COUNTER_KEYS) do dc[k] = 0 end
    end)
    return frame
end

function Debug:Toggle()
    if ns.DebugCounters then
        ns.DebugCounters = nil
        if frame then frame:Hide() end
        ns:Chat("Debug", "off")
    else
        ns.DebugCounters = NewCounters()
        lastMem = collectgarbage and collectgarbage("count") or 0
        EnsureFrame():Show()
        ns:Chat("Debug", "on — counters reset each second")
    end
end

function Debug:Reset()
    if ns.DebugCounters then ns.DebugCounters = NewCounters() end
end

-- CPU subsystem profiling lives in Core/CPUProfiler.lua.
-- Keeping it separate prevents the lightweight debug harness from owning a
-- comparatively large opt-in diagnostics subsystem.

-- -----------------------------------------------------------------------------
-- /tf debug diag — patch-day client surface probe. Prints what THIS client
-- actually exposes for the systems that break across Blizzard patches (status
-- text, unit-frame bar text objects, nameplates) so fixes target facts instead
-- of guesses. Run it with a hostile nameplate on screen for full plate info.
-- -----------------------------------------------------------------------------
local function Desc(tag, r)
    if not r then return tag .. "=nil" end
    local shown = (r.IsShown and r:IsShown()) and "shown" or "HIDDEN"
    local alpha = (r.GetAlpha and ("%.2f"):format(r:GetAlpha())) or "?"
    local text  = r.GetText and r:GetText() or nil
    return ("%s=%s a=%s%s"):format(tag, shown, alpha,
        (text and text ~= "") and (" ['" .. text .. "']") or "")
end

local function Fields(f, pattern, wantType)
    local out = {}
    for k, v in pairs(f) do
        if type(k) == "string" and type(v) == wantType and k:find(pattern) then
            out[#out + 1] = k
        end
    end
    table.sort(out)
    return (#out > 0) and table.concat(out, " ") or "(none)"
end

function Debug:Diag()
    local function C(msg) ns:Chat("Diag", msg) end
    C("=== TurboFace client probe (" .. (GetBuildInfo and table.concat({GetBuildInfo()}, "/") or "?") .. ") ===")

    -- Status text system
    local cvars = {}
    for _, cv in ipairs({ "statusText", "statusTextDisplay", "statusTextPercentage" }) do
        cvars[#cvars + 1] = cv .. "=" .. tostring(GetCVar and GetCVar(cv))
    end
    C("cvars: " .. table.concat(cvars, "  "))
    C(("globals: TSB_UpdateWithValues=%s TSB_Update=%s TextStatusBarMixin=%s"):format(
        type(TextStatusBar_UpdateTextStringWithValues),
        type(TextStatusBar_UpdateTextString), type(TextStatusBarMixin)))
    local hb = PlayerFrameHealthBar
    if hb then
        C("PlayerFrameHealthBar methods: " .. Fields(hb, "[Tt]ext", "function"))
        C("  update methods: " .. Fields(hb, "Update", "function"))
        C("  " .. Desc("TextString", hb.TextString) .. "  " .. Desc("LeftText", hb.LeftText)
            .. "  " .. Desc("RightText", hb.RightText))
        C("  " .. Desc("_tfCenterText", hb._tfCenterText) .. "  (empty/nil = UpdateBarText never ran)")
    else
        C("PlayerFrameHealthBar: NIL")
    end

    -- Nameplates
    C(("ns.CreatePlateFrame=%s ns.FullPlateUpdate=%s ns.UpdateDBCache=%s"):format(
        type(ns.CreatePlateFrame), type(ns.FullPlateUpdate), type(ns.UpdateDBCache)))
    local npCvars = {}
    for _, cv in ipairs({ "nameplateShowAll", "nameplateShowEnemies", "nameplateMaxDistance" }) do
        npCvars[#npCvars + 1] = cv .. "=" .. tostring(GetCVar and GetCVar(cv))
    end
    C("cvars: " .. table.concat(npCvars, "  "))
    local plates = (C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()) or {}
    local tracked = 0
    for _ in pairs(ns.unitToPlate or {}) do tracked = tracked + 1 end
    C(("plates visible: %d   ns.unitToPlate tracked: %d"):format(#plates, tracked))
    local p = plates[1]
    if p then
        C("plate1 " .. Desc((p.GetName and p:GetName()) or "?", p))
        C("  frame-table children: " .. Fields(p, ".", "table"))
        if p.UnitFrame then
            C("  " .. Desc("UnitFrame", p.UnitFrame) .. "  healthBar: " .. Desc("hb", p.UnitFrame.healthBar))
        else
            C("  UnitFrame: NIL (Blizzard restructured the plate!)")
        end
        local mp = p.myPlate
        if mp then
            C("  " .. Desc("myPlate", mp) .. ("  init=%s unit=%s"):format(
                tostring(mp._initialized), tostring(mp.unit)))
            -- Geometry reads can hit "Can't measure restricted regions" on
            -- clients with retail-style protected nameplates — never fatal here.
            local ok, geo = pcall(function()
                local pt, rel, relPt, x, y = mp:GetPoint(1)
                return ("size=%.0fx%.0f point=%s->%s %s %.0f,%.0f"):format(
                    mp:GetWidth(), mp:GetHeight(), tostring(pt), tostring(relPt),
                    (rel and rel.GetName and rel:GetName()) or tostring(rel), x or 0, y or 0)
            end)
            C("  geometry: " .. (ok and geo or "|cffff5555RESTRICTED (retail-style protected plates)|r"))
        else
            C("  myPlate: NIL (TurboFace never built a plate for this frame)")
        end
    else
        C("  (no plates on screen — target an enemy and rerun for plate detail)")
    end
end

-- -----------------------------------------------------------------------------
-- /tf debug modules — modularity-state probe. This is deliberately calculated
-- on demand instead of maintaining mirrors of runtime state. It is meant for
-- validating "disabled means dormant" combinations after profile changes and
-- /reloads, especially Movers-dependent widgets and Plus section gates.
-- -----------------------------------------------------------------------------
local function EnabledWord(value)
    return value and "|cff55ff55ON|r" or "|cffff5555OFF|r"
end

function Debug:ModuleReport()
    local function C(msg) ns:Chat("Modules", msg) end
    local function Gate(family, element)
        if ns.ModuleEnabled then return ns.ModuleEnabled(family, element) end
        return true
    end

    C("=== TurboFace effective module state ===")
    C(("Unit Frames %s  player=%s target=%s ToT=%s party=%s pet=%s"):format(
        EnabledWord(Gate("unitframes")),
        EnabledWord(Gate("unitframes", "player")),
        EnabledWord(Gate("unitframes", "target")),
        EnabledWord(Gate("unitframes", "tot")),
        EnabledWord(Gate("unitframes", "party")),
        EnabledWord(Gate("unitframes", "pet"))))
    if ns.Compat and ns.Compat.IS_TARGET_FOREVER_BUILD == true and ns.UF and ns.UF.GetDiagnostics then
        local u = ns.UF:GetDiagnostics()
        C(("UnitFrames Forever: mode=%s init=%s player=%s hp=%s power=%s target=%s hp=%s power=%s ToT=%s pet=%s party=%d events=%d refresh=%d pending=%s nativeValues=%s predictions=%s nanShield=%s err=%s"):format(
            tostring(u.mode or "?"), tostring(u.initialized == true), tostring(u.player == true),
            tostring(u.playerHealth == true), tostring(u.playerPower == true), tostring(u.target == true),
            tostring(u.targetHealth == true), tostring(u.targetPower == true), tostring(u.tot == true),
            tostring(u.pet == true), tonumber(u.partyFrames) or 0, tonumber(u.events) or 0,
            tonumber(u.refreshCount) or 0, tostring(u.pendingCombat == true), tostring(u.nativeValues == true),
            tostring(u.customPredictions == true), tostring(u.nanShield == true), tostring(u.lastError or "none")))
    end
    C(("Nameplates %s  Auras %s ToT=%s party=%s pet=%s  Class %s"):format(
        EnabledWord(Gate("nameplates")), EnabledWord(Gate("auras")),
        EnabledWord(Gate("auras", "tot")), EnabledWord(Gate("auras", "party")), EnabledWord(Gate("auras", "pet")),
        EnabledWord(Gate("class"))))
    if ns.Compat and ns.Compat.IS_TARGET_FOREVER_BUILD == true then
        if ns.ForeverNameplates and ns.ForeverNameplates.GetDiagnostics then
            local n = ns.ForeverNameplates:GetDiagnostics()
            C(("Nameplates Forever: mode=%s init=%s runtime=%s enabled=%s visible=%d nativeHidden=%d events=%d refresh=%d cvars=%s combo=%s job=%s threat=%s/%d mapped=%d aliases=%d swing=%s healthText=%s/%d power=%s/%d sink=%d/%d shadow=%s title=%s activeSwing=%d auras=%s/%d deferred=%s err=%s healthErr=%s powerErr=%s auraErr=%s"):format(
                tostring(n.mode or "?"), tostring(n.initialized == true), tostring(n.runtimeActive == true), tostring(n.enabled == true),
                tonumber(n.visible) or 0, tonumber(n.hiddenByNative) or 0,
                tonumber(n.events) or 0, tonumber(n.refreshCount) or 0,
                tostring(n.cvars == true), tostring(n.combo == true), tostring(n.jobIcon == true),
                tostring(n.threat == true), tonumber(n.threatVisible) or 0,
                tonumber(n.threatMapped) or 0, tonumber(n.threatAliases) or 0,
                tostring(n.swing == true), tostring(n.healthText == true),
                tonumber(n.healthTextVisible) or 0, tostring(n.power == true),
                tonumber(n.powerVisible) or 0, tonumber(n.powerSinkOK) or 0,
                tonumber(n.powerSinkFailed) or 0, tostring(n.nameShadow or false),
                tostring(n.title == true), tonumber(n.activeSwing) or 0, tostring(n.aurasSupported == true),
                tonumber(n.aurasActive) or 0, tostring(n.deferred or "none"),
                tostring(n.lastError or "none"), tostring(n.healthTextError or "none"),
                tostring(n.powerError or "none"),
                tostring(n.auraError or "none")))
        else
            C("Nameplates Forever: runtime=BLOCKED reason=detached-adapter-missing")
        end
    end
    C(("Hotbar Power %s  Player Ticks %s  Swing Timers %s  Cast Bars %s"):format(
        EnabledWord(Gate("hotbarPower")), EnabledWord(Gate("playerTicks")),
        EnabledWord(Gate("swingTimers")), EnabledWord(Gate("castBars"))))

    -- This was `ns.MoversEnabled and ns.MoversEnabled() or true`, the same
    -- and/or idiom that broke the real gate: `false or true` is true, so this
    -- diagnostic reported Movers ON in exactly the case it exists to reveal.
    local moversOn = ns.MoversEnabled()
    C("Movers " .. EnabledWord(moversOn))

    local db = type(TurboFaceDB) == "table" and TurboFaceDB or {}
    local xp = type(db.experienceBar) == "table" and db.experienceBar or {}
    local loot = type(db.lootFrame) == "table" and db.lootFrame or {}
    -- Go through the shared gate rather than re-deriving it, and coerce first:
    -- ns.MoverDependentEnabled fails open on nil (see its contract note).
    local function Dep(localOn) return ns.MoverDependentEnabled(localOn and true or false) end
    C(("Mover-dependent: XP=%s Loot=%s NetWorth=%s Hearth=%s Tracker=%s SelfClassBuff=%s Flight=%s"):format(
        EnabledWord(Dep(xp.enabled ~= false)),
        EnabledWord(Dep(loot.enabled ~= false)),
        -- Net Worth and Skill Tracker are opt-in (`== true`). On clients with
        -- C_DamageMeter, the historical TurboFace Combat Meter window is retired
        -- and the independent DPS/HPS badge reads Blizzard's backend instead.
        -- The rest default on. Keep these polarities in step with each owner's
        -- own Enabled(), or this report drifts from the runtime it describes.
        EnabledWord(Dep(db.netWorthEnabled == true)),
        EnabledWord(Dep(db.hearthEnabled ~= false)),
        EnabledWord(Dep(db.trackerEnabled ~= false)),
        EnabledWord(Dep(Gate("class") and db.classBuffEnabled ~= false)),
        EnabledWord(Dep(Gate("plus", "flightBar")))))
    local meterProvider = ns.Providers and ns.Providers:Get("combatMeter") or ns.CombatMeter
    local meterProviderName = ns.Providers and ns.Providers:GetName("combatMeter") or "turboface-local"
    local usesBlizzardMeter = meterProviderName == "blizzard-damage-meter"
    C(("Mover-dependent: SkillTracker=%s CombatMeterWindow=%s GroceryButton=%s"):format(
        EnabledWord(Dep(db.skillTrackerEnabled == true)),
        usesBlizzardMeter and "BLIZZARD" or EnabledWord(Dep(db.combatMeterEnabled == true)),
        EnabledWord(Dep(true))))
    if usesBlizzardMeter and meterProvider and meterProvider.GetDebugState then
        local dm = meterProvider:GetDebugState()
        C(("DamageBadge: provider=%s api=%s available=%s events=%d view=%s metric=%s query=%s player=%s secretRate=%s render=%s sources=%d error=%s"):format(
            tostring(meterProviderName),
            tostring(dm.api), tostring(dm.available), dm.events or 0, tostring(dm.view), tostring(dm.metric),
            tostring(dm.lastQueryOK), tostring(dm.lastFoundPlayer), tostring(dm.lastRateSecret),
            tostring(dm.lastRenderOK), dm.lastSourceCount or 0, tostring(dm.lastError or "none")))
    end

    C(("Plus: automation=%s social=%s interface=%s minimap=%s map=%s chat=%s system=%s flightBar=%s"):format(
        EnabledWord(Gate("plus", "automation")), EnabledWord(Gate("plus", "social")),
        EnabledWord(Gate("plus", "interface")), EnabledWord(Gate("plus", "minimap")),
        EnabledWord(Gate("plus", "map")), EnabledWord(Gate("plus", "chat")),
        EnabledWord(Gate("plus", "system")), EnabledWord(Gate("plus", "flightBar"))))

    if ns.PlusSystem and ns.PlusSystem.GetFastLootDiagnostics then
        local fast = ns.PlusSystem:GetFastLootDiagnostics()
        C(("FastLoot: runtime=%s LOOT_READY=%s lootAPI=%s infoAPI=%s method=%s last=%d locked=%d"):format(
            EnabledWord(fast.enabled), tostring(fast.eventValid), tostring(fast.lootAPI),
            tostring(fast.lootInfoAPI), tostring(fast.methodAPI), fast.lastLooted or 0,
            fast.lastSkippedLocked or 0))
    end

    if ns.PlusMap and ns.PlusMap.GetDiagnostics then
        local map = ns.PlusMap:GetDiagnostics()
        C(("Map: runtime=%s initialized=%s frame=%s scroll=%s mapID=%s movable=%s drag=%s zoomHook=%s CreateZoomLevels=%s rememberHook=%s"):format(
            EnabledWord(map.enabled), tostring(map.initialized), tostring(map.frame),
            tostring(map.scrollContainer), tostring(map.mapID), tostring(map.movable),
            tostring(map.dragHandle), tostring(map.zoomHook), tostring(map.createZoomLevels),
            tostring(map.rememberHook)))
    end

    if ns.PlusFlight and ns.PlusFlight.GetDiagnostics then
        local flight = ns.PlusFlight:GetDiagnostics()
        C(("Flight: runtime=%s initialized=%s taxiAPI=%s TakeTaxiHook=%s events=%d TAXIMAP=%s snapshot=%d tooltip=%s seed=%d learned=%d pending=%s"):format(
            EnabledWord(flight.enabled), tostring(flight.initialized), tostring(flight.taxiAPI),
            tostring(flight.takeTaxiHooked), flight.eventCount or 0, tostring(flight.taxiMapEvent),
            flight.snapshotRoutes or 0, tostring(flight.tooltipMode), flight.seedRoutes or 0,
            flight.learnedRoutes or 0, tostring(flight.pending)))
    end

    local owners = type(TurboFaceCacheDB) == "table" and TurboFaceCacheDB.cvarOwners
    local ownerNames = {}
    if type(owners) == "table" then
        for owner in pairs(owners) do ownerNames[#ownerNames + 1] = tostring(owner) end
        table.sort(ownerNames)
    end
    C("Active CVar owners: " .. (#ownerNames > 0 and table.concat(ownerNames, ", ") or "(none)"))

    local bitOwners = type(TurboFaceCacheDB) == "table" and TurboFaceCacheDB.cvarBitOwners
    local bitOwnerNames = {}
    if type(bitOwners) == "table" then
        for owner in pairs(bitOwners) do bitOwnerNames[#bitOwnerNames + 1] = tostring(owner) end
        table.sort(bitOwnerNames)
    end
    C("Active CVar bit owners: " .. (#bitOwnerNames > 0 and table.concat(bitOwnerNames, ", ") or "(none)"))
end

-- -----------------------------------------------------------------------------
-- /tf trainerstyleprobe [row] — read-only inspection of Forever's live native
-- trainer presentation. With no row number it discovers likely service-card
-- frames. Passing a candidate number prints that frame's geometry, anchors,
-- backdrop, textures/atlases, font settings, colors, and immediate children.
-- Nothing is hooked or modified; close the trainer to discard the live objects.
-- -----------------------------------------------------------------------------
function Debug:TrainerStyleProbe(selector)
    local function C(message) ns:Chat("TrainerStyle", message) end
    local function Safe(object, methodName, ...)
        local method = object and object[methodName]
        if type(method) ~= "function" then return nil end
        local result = {pcall(method, object, ...)}
        if not result[1] then return nil end
        table.remove(result, 1)
        return unpack(result)
    end
    local function SafeString(value)
        if value == nil then return "nil" end
        if ns.API and ns.API.CanAccessValue and not ns.API.CanAccessValue(value) then return "<secret>" end
        local ok, text = pcall(tostring, value)
        return ok and text or "<unreadable>"
    end
    local function Number(value)
        return type(value) == "number" and ("%.1f"):format(value) or "?"
    end
    local function PreciseNumber(value)
        return type(value) == "number" and ("%.4f"):format(value) or "?"
    end
    local function ObjectName(object)
        local name = Safe(object, "GetDebugName") or Safe(object, "GetName")
        if name and name ~= "" then return SafeString(name) end
        return "<anonymous " .. SafeString(Safe(object, "GetObjectType") or type(object)) .. ">"
    end
    local function Multi(object, methodName)
        local method = object and object[methodName]
        if type(method) ~= "function" then return {} end
        local values = {pcall(method, object)}
        if not values[1] then return {} end
        table.remove(values, 1)
        return values
    end
    local function PointSummary(object)
        local count = Safe(object, "GetNumPoints") or 0
        local output = {}
        for index = 1, math.min(count, 2) do
            local point, relative, relativePoint, x, y = Safe(object, "GetPoint", index)
            output[#output + 1] = ("%s>%s:%s,%s"):format(
                SafeString(point), relative and ObjectName(relative) or "nil",
                Number(x), Number(y))
            if relativePoint and relativePoint ~= point then
                output[#output] = output[#output] .. "/" .. SafeString(relativePoint)
            end
        end
        return #output > 0 and table.concat(output, " ") or "none"
    end
    local function Color(methodOwner, methodName)
        local r, g, b, a = Safe(methodOwner, methodName)
        if type(r) ~= "number" then return "?" end
        return ("%.2f,%.2f,%.2f,%.2f"):format(r, g or 0, b or 0, a == nil and 1 or a)
    end
    local function FieldName(owner, value)
        if type(owner) ~= "table" then return nil end
        for key, candidate in pairs(owner) do
            if candidate == value and type(key) == "string" then return key end
        end
        return nil
    end
    local function TextureIdentity(texture)
        local atlas = Safe(texture, "GetAtlas")
        if atlas then return "atlas=" .. SafeString(atlas) end
        return "texture=" .. SafeString(Safe(texture, "GetTexture"))
    end
    local function DescribeRegion(region, owner, prefix)
        local objectType = Safe(region, "GetObjectType") or "Region"
        local label = FieldName(owner, region) or ObjectName(region)
        local layer, sublevel = Safe(region, "GetDrawLayer")
        local common = ("%s%s[%s] shown=%s size=%sx%s layer=%s:%s point=%s"):format(
            prefix, label, objectType, tostring(Safe(region, "IsShown") == true),
            Number(Safe(region, "GetWidth")), Number(Safe(region, "GetHeight")),
            SafeString(layer), SafeString(sublevel), PointSummary(region))
        if objectType == "FontString" then
            local path, size, flags = Safe(region, "GetFont")
            local text = Safe(region, "GetText")
            text = SafeString(text):gsub("|", "!"):gsub("[\r\n]", " ")
            if #text > 48 then text = text:sub(1, 45) .. "..." end
            C(common)
            C(("%s  font=%s size=%s flags=%s color=%s justify=%s/%s text=%q"):format(
                prefix, SafeString(path), Number(size), SafeString(flags),
                Color(region, "GetTextColor"), SafeString(Safe(region, "GetJustifyH")),
                SafeString(Safe(region, "GetJustifyV")), text))
        elseif objectType == "Texture" or objectType == "MaskTexture" then
            local coordinates = Multi(region, "GetTexCoord")
            local coordinateText = {}
            for index = 1, #coordinates do
                coordinateText[index] = PreciseNumber(coordinates[index])
            end
            local marginLeft, marginTop, marginRight, marginBottom = Safe(region, "GetTextureSliceMargins")
            local sliceMode = Safe(region, "GetTextureSliceMode")
            C(common)
            C(("%s  %s vertex=%s blend=%s desat=%s texcoord8=%s"):format(
                prefix, TextureIdentity(region), Color(region, "GetVertexColor"),
                SafeString(Safe(region, "GetBlendMode")), tostring(Safe(region, "IsDesaturated") == true),
                #coordinateText > 0 and table.concat(coordinateText, ",") or "none"))
            C(("%s  sliceMargins=%s,%s,%s,%s sliceMode=%s tile=%s/%s"):format(
                prefix, PreciseNumber(marginLeft), PreciseNumber(marginTop),
                PreciseNumber(marginRight), PreciseNumber(marginBottom), SafeString(sliceMode),
                tostring(Safe(region, "GetHorizTile") == true),
                tostring(Safe(region, "GetVertTile") == true)))
        else
            C(common)
        end
    end
    local function DescribeFrame(frame, prefix, includeRegions)
        local objectType = Safe(frame, "GetObjectType") or "Frame"
        C(("%s%s[%s] shown=%s size=%sx%s scale=%s alpha=%s strata=%s level=%s mouse=%s"):format(
            prefix, ObjectName(frame), SafeString(objectType),
            tostring(Safe(frame, "IsShown") == true), Number(Safe(frame, "GetWidth")),
            Number(Safe(frame, "GetHeight")), Number(Safe(frame, "GetScale")),
            Number(Safe(frame, "GetAlpha")), SafeString(Safe(frame, "GetFrameStrata")),
            SafeString(Safe(frame, "GetFrameLevel")), tostring(Safe(frame, "IsMouseEnabled") == true)))
        C(prefix .. "  point=" .. PointSummary(frame) .. " parent="
            .. ObjectName(Safe(frame, "GetParent")))
        local backdrop = Safe(frame, "GetBackdrop")
        if type(backdrop) == "table" then
            C(("%s  backdrop bg=%s edge=%s tile=%s edgeSize=%s bgColor=%s borderColor=%s"):format(
                prefix, SafeString(backdrop.bgFile), SafeString(backdrop.edgeFile),
                tostring(backdrop.tile == true), Number(backdrop.edgeSize),
                Color(frame, "GetBackdropColor"), Color(frame, "GetBackdropBorderColor")))
        end
        for _, methodName in ipairs({"GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetDisabledTexture"}) do
            local texture = Safe(frame, methodName)
            if texture then DescribeRegion(texture, frame, prefix .. "  " .. methodName .. ":") end
        end
        if includeRegions then
            local regions = Multi(frame, "GetRegions")
            C(prefix .. "  regions=" .. tostring(#regions) .. " children=" .. tostring(#Multi(frame, "GetChildren")))
            for _, region in ipairs(regions) do DescribeRegion(region, frame, prefix .. "  ") end
        end
    end

    local roots, rootSeen = {}, {}
    local function AddRoot(name, object)
        local objectKind = type(object)
        if objectKind ~= "table" and objectKind ~= "userdata" then return end
        if rootSeen[object] or type(object.GetObjectType) ~= "function" then return end
        if Safe(object, "IsShown") ~= true then return end
        rootSeen[object] = true
        roots[#roots + 1] = {name = name, frame = object}
    end
    AddRoot("ClassTrainerFrame", rawget(_G, "ClassTrainerFrame"))
    AddRoot("TrainerFrame", rawget(_G, "TrainerFrame"))
    for name, object in pairs(_G) do
        if type(name) == "string" and name:lower():find("trainer", 1, true) then AddRoot(name, object) end
    end
    table.sort(roots, function(a, b) return a.name < b.name end)

    if #roots == 0 then
        C("No shown Blizzard trainer frame found. Open a class trainer, then rerun /tf trainerstyleprobe.")
        return
    end

    local nodes, visited = {}, {}
    local function Walk(object, path, depth)
        if visited[object] or #nodes >= 700 or depth > 9 then return end
        visited[object] = true
        nodes[#nodes + 1] = {frame = object, path = path, depth = depth}
        local children = Multi(object, "GetChildren")
        for index, child in ipairs(children) do
            local segment = FieldName(object, child) or Safe(child, "GetName") or ("child" .. index)
            Walk(child, path .. "/" .. SafeString(segment), depth + 1)
        end
    end
    for _, root in ipairs(roots) do Walk(root.frame, root.name, 0) end

    local candidates = {}
    for _, node in ipairs(nodes) do
        local frame = node.frame
        local width, height = Safe(frame, "GetWidth"), Safe(frame, "GetHeight")
        if Safe(frame, "IsShown") == true and type(width) == "number" and type(height) == "number"
            and width >= 240 and width <= 900 and height >= 34 and height <= 130 then
            local fonts, textures = 0, 0
            for _, region in ipairs(Multi(frame, "GetRegions")) do
                local kind = Safe(region, "GetObjectType")
                if kind == "FontString" then fonts = fonts + 1 end
                if kind == "Texture" then textures = textures + 1 end
            end
            local score = fonts * 4 + textures * 2
            if height >= 55 and height <= 100 then score = score + 5 end
            if (Safe(frame, "GetObjectType") or "") == "Button" then score = score + 4 end
            if score > 0 then
                candidates[#candidates + 1] = {
                    frame = frame, path = node.path, width = width, height = height,
                    fonts = fonts, textures = textures, score = score,
                }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.height ~= b.height then return a.height > b.height end
        return a.path < b.path
    end)

    selector = type(selector) == "string" and selector:match("^%s*(.-)%s*$") or selector
    local rootRequested = type(selector) == "string" and tonumber(selector:match("^root%s+(%d+)$")) or nil
    local requested = tonumber(selector)
    C(("build=%s roots=%d nodes=%d rowCandidates=%d"):format(
        GetBuildInfo and select(2, GetBuildInfo()) or "?", #roots, #nodes, #candidates))
    if rootRequested then
        local root = roots[rootRequested]
        if not root then
            C(("ROOT[%d] does not exist; valid range is 1-%d"):format(rootRequested, #roots))
            return
        end
        C(("=== ROOT[%d] %s ==="):format(rootRequested, root.name))
        local objectType = Safe(root.frame, "GetObjectType")
        if objectType == "Texture" or objectType == "MaskTexture" or objectType == "FontString" then
            DescribeRegion(root.frame, nil, "")
        else
            DescribeFrame(root.frame, "", true)
            for index, child in ipairs(Multi(root.frame, "GetChildren")) do
                C(("--- child %d ---"):format(index))
                DescribeFrame(child, "C ", false)
            end
        end
        return
    end
    if not requested then
        for index, root in ipairs(roots) do
            if index <= 12 then
                C(("ROOT[%d] %s = %s"):format(index, root.name, ObjectName(root.frame)))
            end
        end
        for index, candidate in ipairs(candidates) do
            if index > 12 then break end
            C(("ROW[%d] score=%d size=%sx%s fonts=%d textures=%d %s"):format(
                index, candidate.score, Number(candidate.width), Number(candidate.height),
                candidate.fonts, candidate.textures, candidate.path))
        end
        if #candidates > 0 then
            C("Run /tf trainerstyleprobe 1 (or another ROW number) for exact styling details.")
            C("Run /tf trainerstyleprobe root 2 (or another ROOT number) for background/inset details.")
        else
            C("No row-sized frame matched; keep the trainer list visible and send this summary.")
        end
        return
    end

    local candidate = candidates[requested]
    if not candidate then
        C(("ROW[%s] does not exist; valid range is 1-%d"):format(SafeString(requested), #candidates))
        return
    end
    C(("=== ROW[%d] %s ==="):format(requested, candidate.path))
    DescribeFrame(candidate.frame, "", true)
    local parent = Safe(candidate.frame, "GetParent")
    if parent then
        C("--- parent ---")
        DescribeFrame(parent, "P ", false)
    end
    local children = Multi(candidate.frame, "GetChildren")
    for index, child in ipairs(children) do
        C(("--- child %d/%d ---"):format(index, #children))
        DescribeFrame(child, "C ", true)
    end
end

-- -----------------------------------------------------------------------------
-- /tf professionprobe [crafting|tabs|tab N|root N|button N] — bounded, read-only inspection of
-- Forever's Retail-derived Professions window. The summary captures the current
-- profession API state and discovers visible native roots/buttons; detail modes
-- expose anchors and artwork needed to place a detached TurboFace launcher.
-- Nothing is hooked, retained, selected, hidden, or otherwise modified.
-- -----------------------------------------------------------------------------
function Debug:ProfessionProbe(selector)
    local function C(message) ns:Chat("ProfessionProbe", message) end
    local function Safe(object, methodName, ...)
        local method = object and object[methodName]
        if type(method) ~= "function" then return nil end
        local result = {pcall(method, object, ...)}
        if not result[1] then return nil end
        table.remove(result, 1)
        return unpack(result)
    end
    local function Call(owner, methodName, ...)
        local method = type(owner) == "table" and owner[methodName] or nil
        if type(method) ~= "function" then return false, "missing" end
        local result = {pcall(method, ...)}
        if not result[1] then return false, result[2] end
        table.remove(result, 1)
        return true, result
    end
    local function SafeString(value)
        if value == nil then return "nil" end
        if ns.API and ns.API.CanAccessValue and not ns.API.CanAccessValue(value) then return "<secret>" end
        local ok, result = pcall(tostring, value)
        return ok and result or "<unreadable>"
    end
    local function ReadableNumber(value)
        if ns.API and ns.API.IsReadableNumber then return ns.API.IsReadableNumber(value) end
        return type(value) == "number"
    end
    local function Number(value)
        if not ReadableNumber(value) then return "?" end
        local ok, result = pcall(string.format, "%.1f", value)
        return ok and result or "?"
    end
    local function ObjectName(object)
        if not object then return "nil" end
        local name = Safe(object, "GetDebugName") or Safe(object, "GetName")
        if name and name ~= "" then return SafeString(name) end
        return "<anonymous " .. SafeString(Safe(object, "GetObjectType") or type(object)) .. ">"
    end
    local function Multi(object, methodName)
        local method = object and object[methodName]
        if type(method) ~= "function" then return {} end
        local values = {pcall(method, object)}
        if not values[1] then return {} end
        table.remove(values, 1)
        return values
    end
    local function FieldName(owner, value)
        if type(owner) ~= "table" then return nil end
        for key, candidate in pairs(owner) do
            if candidate == value and type(key) == "string" then return key end
        end
        return nil
    end
    local function PointSummary(object)
        local count = Safe(object, "GetNumPoints") or 0
        local output = {}
        for index = 1, math.min(count, 2) do
            local point, relative, relativePoint, x, y = Safe(object, "GetPoint", index)
            output[#output + 1] = ("%s>%s:%s,%s"):format(
                SafeString(point), ObjectName(relative), Number(x), Number(y))
            if relativePoint and relativePoint ~= point then
                output[#output] = output[#output] .. "/" .. SafeString(relativePoint)
            end
        end
        return #output > 0 and table.concat(output, " ") or "none"
    end
    local function ScalarSummary(value)
        local kind = type(value)
        if kind == "string" then return string.format("%q", SafeString(value)) end
        if kind == "number" or kind == "boolean" then return SafeString(value) end
        return nil
    end
    local function TableSummary(value)
        if type(value) ~= "table" then return SafeString(value) end
        local fields, array = {}, {}
        for key, candidate in pairs(value) do
            local scalar = ScalarSummary(candidate)
            if scalar then
                if type(key) == "number" and key >= 1 and key <= 12 then
                    array[#array + 1] = {key = key, text = scalar}
                elseif type(key) == "string" and #fields < 16 then
                    fields[#fields + 1] = key .. "=" .. scalar
                end
            end
        end
        table.sort(fields)
        table.sort(array, function(a, b) return a.key < b.key end)
        for _, entry in ipairs(array) do fields[#fields + 1] = "[" .. entry.key .. "]=" .. entry.text end
        return #fields > 0 and "{" .. table.concat(fields, ", ") .. "}" or "{table}"
    end
    local function ResultsSummary(values)
        if type(values) ~= "table" or #values == 0 then return "nil" end
        local output = {}
        for index = 1, math.min(#values, 4) do
            output[#output + 1] = "[" .. index .. "]=" .. TableSummary(values[index])
        end
        return table.concat(output, " ")
    end
    local function TextureSummary(texture)
        if not texture then return "none" end
        local atlas = Safe(texture, "GetAtlas")
        local identity = atlas and ("atlas=" .. SafeString(atlas))
            or ("texture=" .. SafeString(Safe(texture, "GetTexture")))
        return identity .. " point=" .. PointSummary(texture)
    end
    local interestingFields = {
        "professionID", "professionId", "skillLineID", "skillLineId", "tradeSkillLineID",
        "selectedSkillLineID", "selectedProfessionID", "tabID", "layoutIndex", "recipeID",
    }
    local function FieldSummary(object)
        if type(object) ~= "table" then return "none" end
        local output = {}
        for _, key in ipairs(interestingFields) do
            local scalar = ScalarSummary(rawget(object, key))
            if scalar then output[#output + 1] = key .. "=" .. scalar end
        end
        return #output > 0 and table.concat(output, " ") or "none"
    end
    local function DescribeFrame(frame, prefix, includeRegions)
        C(("%s%s[%s] shown=%s size=%sx%s point=%s parent=%s fields=%s"):format(
            prefix, ObjectName(frame), SafeString(Safe(frame, "GetObjectType") or "Frame"),
            tostring(Safe(frame, "IsShown") == true), Number(Safe(frame, "GetWidth")),
            Number(Safe(frame, "GetHeight")), PointSummary(frame), ObjectName(Safe(frame, "GetParent")),
            FieldSummary(frame)))
        for _, methodName in ipairs({"GetNormalTexture", "GetHighlightTexture", "GetPushedTexture", "GetCheckedTexture"}) do
            local texture = Safe(frame, methodName)
            if texture then C(prefix .. "  " .. methodName .. " " .. TextureSummary(texture)) end
        end
        local text = Safe(frame, "GetText")
        if text and text ~= "" then C(prefix .. "  text=" .. string.format("%q", SafeString(text))) end
        if includeRegions then
            for index, region in ipairs(Multi(frame, "GetRegions")) do
                local objectType = Safe(region, "GetObjectType")
                if objectType == "Texture" or objectType == "MaskTexture" then
                    C(("%s  region[%d] %s %s"):format(prefix, index, ObjectName(region), TextureSummary(region)))
                elseif objectType == "FontString" then
                    local regionText = Safe(region, "GetText")
                    C(("%s  region[%d] %s text=%q"):format(
                        prefix, index, ObjectName(region), SafeString(regionText)))
                end
            end
        end
    end

    local roots, rootSeen = {}, {}
    local function AddRoot(name, object)
        local objectKind = type(object)
        if objectKind ~= "table" and objectKind ~= "userdata" then return end
        if rootSeen[object] or type(object.GetObjectType) ~= "function" then return end
        if Safe(object, "IsShown") ~= true then return end
        rootSeen[object] = true
        roots[#roots + 1] = {name = name, frame = object}
    end
    AddRoot("ProfessionsFrame", rawget(_G, "ProfessionsFrame"))
    AddRoot("TradeSkillFrame", rawget(_G, "TradeSkillFrame"))
    for name, object in pairs(_G) do
        local lower = type(name) == "string" and name:lower() or ""
        if lower:find("profession", 1, true) or lower:find("tradeskill", 1, true) then
            AddRoot(name, object)
        end
    end
    table.sort(roots, function(a, b) return a.name < b.name end)

    if #roots == 0 then
        C("No shown Blizzard profession frame found. Open the Professions window, then rerun /tf professionprobe.")
        return
    end

    C("build=" .. SafeString(GetBuildInfo and select(2, GetBuildInfo()) or "?"))
    local tradeSkillAPI = rawget(_G, "C_TradeSkillUI")
    for _, methodName in ipairs({
        "GetBaseProfessionInfo", "GetChildProfessionInfo", "GetTradeSkillLine",
        "GetAllProfessionTradeSkillLines", "IsTradeSkillReady",
    }) do
        local ok, values = Call(tradeSkillAPI, methodName)
        C("API C_TradeSkillUI." .. methodName .. "=" .. (ok and ResultsSummary(values) or ("<" .. SafeString(values) .. ">")))
    end
    if type(rawget(_G, "GetTradeSkillLine")) == "function" then
        local result = {pcall(rawget(_G, "GetTradeSkillLine"))}
        local ok = table.remove(result, 1)
        C("API GetTradeSkillLine=" .. (ok and ResultsSummary(result) or ("<" .. SafeString(result[1]) .. ">")))
    else
        C("API GetTradeSkillLine=<missing>")
    end

    local nodes, visited = {}, {}
    local function Walk(object, path, depth)
        if visited[object] or #nodes >= 900 or depth > 10 then return end
        visited[object] = true
        nodes[#nodes + 1] = {frame = object, path = path, depth = depth}
        for index, child in ipairs(Multi(object, "GetChildren")) do
            local segment = FieldName(object, child) or Safe(child, "GetName") or ("child" .. index)
            Walk(child, path .. "/" .. SafeString(segment), depth + 1)
        end
    end
    for _, root in ipairs(roots) do Walk(root.frame, root.name, 0) end

    local buttons = {}
    for _, node in ipairs(nodes) do
        local frame = node.frame
        local objectType = Safe(frame, "GetObjectType")
        local width, height = Safe(frame, "GetWidth"), Safe(frame, "GetHeight")
        if (objectType == "Button" or objectType == "CheckButton") and Safe(frame, "IsShown") == true
            and ReadableNumber(width) and ReadableNumber(height)
            and width >= 18 and width <= 220 and height >= 18 and height <= 120 then
            local score = 4
            local lowerPath = node.path:lower()
            if lowerPath:find("tab", 1, true) then score = score + 6 end
            if lowerPath:find("profession", 1, true) then score = score + 3 end
            if lowerPath:find("spellbutton", 1, true) then score = score + 12 end
            if lowerPath:find("professionscontentframe", 1, true) then score = score + 8 end
            if Safe(frame, "GetNormalTexture") then score = score + 2 end
            local checked = Safe(frame, "GetChecked")
            local selected = Safe(frame, "IsSelected")
            if checked == true or selected == true then score = score + 5 end
            buttons[#buttons + 1] = {
                frame = frame, path = node.path, width = width, height = height,
                score = score, checked = checked, selected = selected,
            }
        end
    end
    table.sort(buttons, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.path < b.path
    end)

    selector = type(selector) == "string" and selector:match("^%s*(.-)%s*$") or ""
    local rootRequested = tonumber(selector:match("^root%s+(%d+)$"))
    local buttonRequested = tonumber(selector:match("^button%s+(%d+)$"))
    local professionTabRequested = tonumber(selector:match("^tab%s+(%d+)$"))
    C(("roots=%d nodes=%d buttons=%d"):format(#roots, #nodes, #buttons))
    if rootRequested then
        local root = roots[rootRequested]
        if not root then
            C(("ROOT[%d] does not exist; valid range is 1-%d"):format(rootRequested, #roots))
            return
        end
        C(("=== ROOT[%d] %s ==="):format(rootRequested, root.name))
        DescribeFrame(root.frame, "", true)
        for index, child in ipairs(Multi(root.frame, "GetChildren")) do
            C("--- child " .. index .. " ---")
            DescribeFrame(child, "C ", false)
        end
        return
    end
    if buttonRequested then
        local button = buttons[buttonRequested]
        if not button then
            C(("BUTTON[%d] does not exist; valid range is 1-%d"):format(buttonRequested, #buttons))
            return
        end
        C(("=== BUTTON[%d] %s ==="):format(buttonRequested, button.path))
        DescribeFrame(button.frame, "", true)
        local parent = Safe(button.frame, "GetParent")
        if parent then
            C("--- parent ---")
            DescribeFrame(parent, "P ", true)
        end
        return
    end
    if professionTabRequested then
        local frame = rawget(_G, "ProfessionsFrame")
        local tab = type(frame) == "table"
            and rawget(frame, "Professions" .. professionTabRequested .. "Tab") or nil
        if not tab then
            C(("Native profession TAB[%d] does not exist; expected range is 1-7"):format(professionTabRequested))
            return
        end
        C(("=== PROFESSION TAB[%d] ==="):format(professionTabRequested))
        DescribeFrame(tab, "", true)
        for index, child in ipairs(Multi(tab, "GetChildren")) do
            C("--- child " .. index .. " ---")
            DescribeFrame(child, "C ", true)
        end
        return
    end
    if selector == "crafting" then
        local frame = rawget(_G, "ProfessionsFrame")
        local craftingPage = type(frame) == "table" and rawget(frame, "CraftingPage") or nil
        if not craftingPage or Safe(craftingPage, "IsShown") ~= true then
            C("The native CraftingPage is not shown. Open a profession's crafting page and retry.")
            return
        end
        C("=== CRAFTING PAGE ===")
        DescribeFrame(craftingPage, "", true)
        for index, child in ipairs(Multi(craftingPage, "GetChildren")) do
            C("--- child " .. index .. " ---")
            DescribeFrame(child, "C ", true)
        end
        return
    end
    if selector == "tabs" then
        local frame = rawget(_G, "ProfessionsFrame")
        if not frame or Safe(frame, "IsShown") ~= true then
            C("The native ProfessionsFrame is not shown. Open it and retry.")
            return
        end
        local names = {"ProfessionsOverviewTab"}
        for index = 1, 7 do names[#names + 1] = "Professions" .. index .. "Tab" end
        C("=== PROFESSION TABS ===")
        for _, name in ipairs(names) do
            local tab = type(frame) == "table" and rawget(frame, name) or nil
            if tab then
                DescribeFrame(tab, name .. " ", true)
                for index, child in ipairs(Multi(tab, "GetChildren")) do
                    DescribeFrame(child, name .. ".child" .. index .. " ", true)
                end
            end
        end
        return
    end

    for index, root in ipairs(roots) do
        if index > 16 then break end
        C(("ROOT[%d] %s=%s size=%sx%s point=%s fields=%s"):format(
            index, root.name, ObjectName(root.frame), Number(Safe(root.frame, "GetWidth")),
            Number(Safe(root.frame, "GetHeight")), PointSummary(root.frame), FieldSummary(root.frame)))
    end
    for index, button in ipairs(buttons) do
        if index > 20 then break end
        C(("BUTTON[%d] score=%d type=%s size=%sx%s checked=%s selected=%s fields=%s %s"):format(
            index, button.score, SafeString(Safe(button.frame, "GetObjectType")),
            Number(button.width), Number(button.height), SafeString(button.checked),
            SafeString(button.selected), FieldSummary(button.frame), button.path))
    end
    C("Run /tf professionprobe button N for the proposed launcher area or a profession tab.")
    C("Run /tf professionprobe root N for the native frame/content hierarchy.")
    C("Run /tf professionprobe crafting for the header controls and content bounds.")
end

-- -----------------------------------------------------------------------------
-- /tf professiondataprobe
-- /tf professiondataprobe recipes [page]
-- /tf professiondataprobe recipe <recipeID>
-- /tf professiondataprobe categories [page]
-- /tf professiondataprobe trainer [page]
-- /tf professiondataprobe apis [page]
-- /tf professiondataprobe capture recipes
-- /tf professiondataprobe capture trainer
--
-- Bounded, read-only discovery of Forever's actual profession data contract.
-- Unlike ProfessionProbe (native frame layout), this probe records the modern
-- recipe/catalog values and the legacy-shaped trainer rows that we need to
-- rebuild the changed Forever training database. It installs no hooks, retains
-- no native tables or frames, and never selects, learns, trains, or crafts.
-- -----------------------------------------------------------------------------
function Debug:ProfessionDataProbe(selector)
    local function C(message) ns:Chat("ProfessionData", message) end
    local api = rawget(_G, "C_TradeSkillUI")
    local PAGE_SIZE = 6

    local function Accessible(value)
        return not (ns.API and ns.API.CanAccessValue)
            or ns.API.CanAccessValue(value) == true
    end

    local function Text(value)
        if value == nil then return "nil" end
        if not Accessible(value) then return "<secret>" end
        local ok, result = pcall(tostring, value)
        if not ok then return "<unreadable>" end
        if #result > 120 then result = result:sub(1, 117) .. "..." end
        return result
    end

    local function Summary(value, depth, seen)
        if not Accessible(value) then return "<secret>" end
        if type(value) ~= "table" then return Text(value) end
        depth = depth or 0
        if depth >= 2 then return "{...}" end
        seen = seen or {}
        if seen[value] then return "{cycle}" end
        seen[value] = true
        local entries = {}
        for key, candidate in pairs(value) do
            entries[#entries + 1] = {key = Text(key), value = candidate}
        end
        table.sort(entries, function(a, b) return a.key < b.key end)
        local output = {}
        for index = 1, math.min(#entries, 18) do
            local entry = entries[index]
            output[#output + 1] = entry.key .. "="
                .. Summary(entry.value, depth + 1, seen)
        end
        if #entries > 18 then output[#output + 1] = "+" .. (#entries - 18) .. " fields" end
        seen[value] = nil
        return "{" .. table.concat(output, ", ") .. "}"
    end

    -- SavedVariables-safe recursive copy. Modern profession records are nested
    -- and can contain values that the client will not serialize (functions,
    -- userdata, secret values). Keep all readable scalar/table evidence while
    -- bounding pathological tables and recursion.
    local function SnapshotValue(value, depth, seen)
        if not Accessible(value) then return "<secret>" end
        local valueType = type(value)
        if valueType == "nil" or valueType == "string"
            or valueType == "number" or valueType == "boolean" then
            return value
        end
        if valueType ~= "table" then return "<" .. valueType .. ">" end
        depth = depth or 0
        if depth >= 8 then return "<depth-limit>" end
        seen = seen or {}
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local output, count = {}, 0
        for key, candidate in pairs(value) do
            local keyType = type(key)
            if (keyType == "string" or keyType == "number") and Accessible(key) then
                count = count + 1
                if count <= 250 then
                    output[key] = SnapshotValue(candidate, depth + 1, seen)
                end
            end
        end
        if count > 250 then output.__truncatedEntries = count - 250 end
        seen[value] = nil
        return output
    end

    local function Call(methodName, ...)
        local method = type(api) == "table" and api[methodName] or nil
        if type(method) ~= "function" then return false, "missing" end
        local values = {pcall(method, ...)}
        local ok = table.remove(values, 1)
        if not ok then return false, values[1] end
        return true, values
    end

    local function First(methodName, ...)
        local ok, values = Call(methodName, ...)
        return ok and values[1] or nil, ok and nil or values
    end

    local function BaseInfo()
        local info = First("GetBaseProfessionInfo")
        return type(info) == "table" and info or nil
    end

    local function NumericIDs(value, output, seen)
        if type(value) ~= "table" then return end
        for _, candidate in pairs(value) do
            local id = tonumber(candidate)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                output[#output + 1] = id
            end
        end
    end

    local function RecipeIDs()
        local ids, seen, sources = {}, {}, {}
        local info = BaseInfo()
        local professionID = info and tonumber(info.professionID)
        local requests = {
            {"GetAllRecipeIDs"},
            {"GetFilteredRecipeIDs"},
            {"GetRecipeIDsBySkillLine", professionID},
            {"GetRecipesInSkillLine", professionID},
        }
        for _, request in ipairs(requests) do
            if request[2] ~= nil or request[1] == "GetAllRecipeIDs"
                or request[1] == "GetFilteredRecipeIDs" then
                local ok, values
                if request[2] ~= nil then
                    ok, values = Call(request[1], request[2])
                else
                    ok, values = Call(request[1])
                end
                if ok then
                    local before = #ids
                    for _, value in ipairs(values) do NumericIDs(value, ids, seen) end
                    sources[#sources + 1] = request[1] .. ":" .. (#ids - before)
                elseif values ~= "missing" then
                    sources[#sources + 1] = request[1] .. ":error"
                end
            end
        end
        table.sort(ids)
        return ids, sources
    end

    local function PageBounds(total, requested)
        local pages = math.max(1, math.ceil(total / PAGE_SIZE))
        local page = math.max(1, math.min(tonumber(requested) or 1, pages))
        return page, pages, (page - 1) * PAGE_SIZE + 1,
            math.min(page * PAGE_SIZE, total)
    end

    local function RecipeLine(recipeID)
        local info = First("GetRecipeInfo", recipeID)
        if type(info) ~= "table" then return "id=" .. recipeID .. " info=" .. Text(info) end
        local fields = {}
        for _, key in ipairs({
            "name", "recipeID", "spellID", "categoryID", "skillLineAbilityID",
            "learned", "disabled", "favorite", "relativeDifficulty", "maxQuality",
            "supportsQualities", "isRecraft", "isSalvageRecipe",
        }) do
            if info[key] ~= nil then fields[#fields + 1] = key .. "=" .. Text(info[key]) end
        end
        return "id=" .. recipeID .. (#fields > 0 and (" " .. table.concat(fields, " ")) or " info={table}")
    end

    local function EnsureCapture(professionKey)
        if type(TurboFaceCompatDB) ~= "table" then TurboFaceCompatDB = {} end
        local root = TurboFaceCompatDB.professionDataProbe
        if type(root) ~= "table" then
            root = {format = 1, professions = {}}
            TurboFaceCompatDB.professionDataProbe = root
        end
        root.format = 1
        root.professions = type(root.professions) == "table" and root.professions or {}
        professionKey = tostring(professionKey or "Unknown")
        local record = root.professions[professionKey]
        if type(record) ~= "table" then
            record = {}
            root.professions[professionKey] = record
        end
        local version, currentBuild, interface
        if type(GetBuildInfo) == "function" then
            local buildDate
            version, currentBuild, buildDate, interface = GetBuildInfo()
        end
        record.client = {
            version = version, build = currentBuild, interface = interface,
            project = WOW_PROJECT_ID,
        }
        record.profession = SnapshotValue(BaseInfo())
        root.latestProfession = professionKey
        root.latestBuild = currentBuild
        return record, professionKey
    end

    local function CaptureRecipe(recipeID)
        local record = {recipeID = recipeID}
        local function CaptureOne(field, methodName, ...)
            local ok, values = Call(methodName, ...)
            if ok then
                if #values == 1 then record[field] = SnapshotValue(values[1])
                elseif #values > 1 then record[field] = SnapshotValue(values) end
            elseif values ~= "missing" then
                record.errors = record.errors or {}
                record.errors[methodName] = Text(values)
            end
        end
        CaptureOne("info", "GetRecipeInfo", recipeID)
        CaptureOne("sourceText", "GetRecipeSourceText", recipeID)
        CaptureOne("itemLink", "GetRecipeItemLink", recipeID)
        CaptureOne("requirements", "GetRecipeRequirements", recipeID)
        CaptureOne("schematic", "GetRecipeSchematic", recipeID, false)
        CaptureOne("cooldown", "GetRecipeCooldown", recipeID)
        CaptureOne("tradeSkillLine", "GetTradeSkillLineForRecipe", recipeID)
        CaptureOne("qualityItemIDs", "GetRecipeQualityItemIDs", recipeID)
        return record
    end

    local function CaptureTrainerServices()
        local trainer = ns.Trainer
        local professionKey = trainer and trainer.DetectTrainerProfession
            and trainer:DetectTrainerProfession() or nil
        local info = BaseInfo()
        professionKey = professionKey or (info and info.professionName)
            or (info and info.professionID) or "Unknown"
        local record, storedKey = EnsureCapture(professionKey)
        local count = type(GetNumTrainerServices) == "function" and GetNumTrainerServices() or 0
        if type(count) ~= "number" then count = 0 end
        local services = {}
        for index = 1, count do
            local name, rankText, status
            if trainer and trainer.GetTrainerServiceInfoCompat then
                name, rankText, status = trainer:GetTrainerServiceInfoCompat(index)
            elseif type(GetTrainerServiceInfo) == "function" then
                name, rankText, status = GetTrainerServiceInfo(index)
            end
            services[index] = SnapshotValue({
                index = index,
                name = name,
                rankText = rankText,
                status = status,
                spellID = trainer and trainer.GetSpellIDForService
                    and trainer:GetSpellIDForService(index) or nil,
                skillReq = trainer and trainer.GetSkillReqForService
                    and trainer:GetSkillReqForService(index) or nil,
                levelReq = type(GetTrainerServiceLevelReq) == "function"
                    and GetTrainerServiceLevelReq(index) or nil,
                cost = type(GetTrainerServiceCost) == "function"
                    and GetTrainerServiceCost(index) or nil,
                skillLine = type(GetTrainerServiceSkillLine) == "function"
                    and GetTrainerServiceSkillLine(index) or nil,
                icon = type(GetTrainerServiceIcon) == "function"
                    and GetTrainerServiceIcon(index) or nil,
            })
        end
        record.trainerServices = services
        record.trainerServiceCount = count
        record.trainerCapturedAt = time and time() or nil
        C(("Captured %d trainer services for %s in TurboFaceCompatDB.professionDataProbe."):format(
            count, storedKey))
        if count > 0 then C("Log out to character selection before asking ChatGPT to extract the SavedVariables file.") end
    end

    selector = type(selector) == "string" and selector:lower():match("^%s*(.-)%s*$") or ""
    selector = selector:gsub("%s+", " ")
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    local info = BaseInfo()
    local ready = First("IsTradeSkillReady")

    if selector == "capture trainer" then
        CaptureTrainerServices()
        return
    end

    if selector == "capture" or selector == "capture recipes" then
        if self._professionDataCapture then
            C("A recipe capture is already running.")
            return
        end
        local ids = RecipeIDs()
        if #ids == 0 then
            C("No recipe IDs found. Open a profession crafting page and retry.")
            return
        end
        local professionKey = info and (info.professionName or info.professionID) or "Unknown"
        local record, storedKey = EnsureCapture(professionKey)
        record.recipes = {}
        record.recipeCount = #ids
        record.recipeCaptureComplete = false
        record.recipeCapturedAt = nil
        local state = {ids = ids, index = 1, record = record, professionKey = storedKey}
        self._professionDataCapture = state
        C(("Capturing %d recipes for %s in bounded batches; keep the profession page open."):format(
            #ids, storedKey))
        local function Step()
            if self._professionDataCapture ~= state then return end
            local last = math.min(state.index + 19, #state.ids)
            for index = state.index, last do
                local recipeID = state.ids[index]
                state.record.recipes[recipeID] = CaptureRecipe(recipeID)
            end
            state.index = last + 1
            if state.index <= #state.ids then
                if last % 100 == 0 then C(("Capture progress: %d/%d"):format(last, #state.ids)) end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, Step)
                else
                    Step()
                end
                return
            end
            state.record.recipeCaptureComplete = true
            state.record.recipeCapturedAt = time and time() or nil
            self._professionDataCapture = nil
            C(("Captured %d/%d recipes for %s in TurboFaceCompatDB.professionDataProbe."):format(
                #state.ids, #state.ids, state.professionKey))
            C("Log out to character selection before asking ChatGPT to extract the SavedVariables file.")
        end
        Step()
        return
    end

    if selector == "" then
        local ids, sources = RecipeIDs()
        C("build=" .. Text(build) .. " ready=" .. Text(ready)
            .. " profession=" .. Summary(info) .. " recipes=" .. #ids
            .. " sources=" .. table.concat(sources, ","))
        C("Open one profession page, then use: /tf professiondataprobe recipes 1")
        C("Details: recipe ID | categories 1 | trainer 1 | apis 1 | capture recipes")
        return
    end

    local recipeID = tonumber(selector:match("^recipe%s+(%d+)$"))
    if recipeID then
        C("build=" .. Text(build) .. " === RECIPE " .. recipeID .. " ===")
        for _, methodName in ipairs({
            "GetRecipeInfo", "GetRecipeDescription", "GetRecipeSourceText",
            "GetRecipeItemLink", "GetRecipeRequirements", "GetRecipeSchematic",
            "GetRecipeCooldown", "GetTradeSkillLineForRecipe",
            "GetRecipeNumItemsProduced", "GetRecipeQualityItemIDs",
        }) do
            local ok, values
            if methodName == "GetRecipeSchematic" then
                ok, values = Call(methodName, recipeID, false)
            else
                ok, values = Call(methodName, recipeID)
            end
            if ok then
                local rendered = {}
                for index = 1, math.min(#values, 4) do
                    rendered[#rendered + 1] = "[" .. index .. "]=" .. Summary(values[index])
                end
                C(methodName .. "=" .. (#rendered > 0 and table.concat(rendered, " ") or "nil"))
            else
                C(methodName .. "=<" .. Text(values) .. ">")
            end
        end
        return
    end

    local recipePage = selector:match("^recipes%s*(%d*)$")
    if recipePage ~= nil then
        local ids, sources = RecipeIDs()
        local page, pages, first, last = PageBounds(#ids, recipePage)
        C(("build=%s profession=%s recipes=%d page=%d/%d sources=%s"):format(
            Text(build), Text(info and info.professionName), #ids, page, pages,
            table.concat(sources, ",")))
        for index = first, last do C(("R[%d] %s"):format(index, RecipeLine(ids[index]))) end
        if last < #ids then C("Next: /tf professiondataprobe recipes " .. (page + 1)) end
        return
    end

    local categoryPage = selector:match("^categories%s*(%d*)$")
    if categoryPage ~= nil then
        local categories = First("GetCategories")
        categories = type(categories) == "table" and categories or {}
        local page, pages, first, last = PageBounds(#categories, categoryPage)
        C(("build=%s categories=%d page=%d/%d"):format(Text(build), #categories, page, pages))
        for index = first, last do
            local categoryID = categories[index]
            local categoryInfo = First("GetCategoryInfo", categoryID)
            C(("C[%d] id=%s info=%s"):format(index, Text(categoryID), Summary(categoryInfo)))
        end
        if last < #categories then C("Next: /tf professiondataprobe categories " .. (page + 1)) end
        return
    end

    local trainerPage = selector:match("^trainer%s*(%d*)$")
    if trainerPage ~= nil then
        local count = type(GetNumTrainerServices) == "function" and GetNumTrainerServices() or 0
        if type(count) ~= "number" then count = 0 end
        local page, pages, first, last = PageBounds(count, trainerPage)
        local trainer = ns.Trainer
        local professionKey = trainer and trainer.DetectTrainerProfession
            and trainer:DetectTrainerProfession() or nil
        C(("build=%s trainerProfession=%s services=%d page=%d/%d"):format(
            Text(build), Text(professionKey), count, page, pages))
        for index = first, last do
            local name, rankText, status
            if trainer and trainer.GetTrainerServiceInfoCompat then
                name, rankText, status = trainer:GetTrainerServiceInfoCompat(index)
            elseif type(GetTrainerServiceInfo) == "function" then
                name, rankText, status = GetTrainerServiceInfo(index)
            end
            local spellID = trainer and trainer.GetSpellIDForService
                and trainer:GetSpellIDForService(index) or nil
            local skillReq = trainer and trainer.GetSkillReqForService
                and trainer:GetSkillReqForService(index) or nil
            local levelReq = type(GetTrainerServiceLevelReq) == "function"
                and GetTrainerServiceLevelReq(index) or nil
            local cost = type(GetTrainerServiceCost) == "function"
                and GetTrainerServiceCost(index) or nil
            local skillLine = type(GetTrainerServiceSkillLine) == "function"
                and GetTrainerServiceSkillLine(index) or nil
            C(("T[%d] name=%s rank=%s status=%s spellID=%s skillReq=%s levelReq=%s cost=%s skillLine=%s"):format(
                index, Text(name), Text(rankText), Text(status), Text(spellID), Text(skillReq),
                Text(levelReq), Text(cost), Text(skillLine)))
        end
        if count == 0 then C("No trainer services found. Open the profession trainer, then retry.") end
        if last < count then C("Next: /tf professiondataprobe trainer " .. (page + 1)) end
        return
    end

    local apiPage = selector:match("^apis%s*(%d*)$")
    if apiPage ~= nil then
        local names = {}
        if type(api) == "table" then
            for name, value in pairs(api) do
                if type(name) == "string" and type(value) == "function"
                    and (name:find("Recipe", 1, true) or name:find("Profession", 1, true)
                        or name:find("SkillLine", 1, true) or name:find("Categor", 1, true)) then
                    names[#names + 1] = name
                end
            end
        end
        table.sort(names)
        local page, pages, first, last = PageBounds(#names, apiPage)
        C(("build=%s relevantAPIs=%d page=%d/%d"):format(Text(build), #names, page, pages))
        for index = first, last do C(("API[%d] C_TradeSkillUI.%s"):format(index, names[index])) end
        if last < #names then C("Next: /tf professiondataprobe apis " .. (page + 1)) end
        return
    end

    C("Usage: /tf professiondataprobe [recipes N|recipe ID|categories N|trainer N|apis N|capture recipes|capture trainer]")
end

-- -----------------------------------------------------------------------------
-- /tf nameplateapiprobe [plate N]
--
-- Read-only inventory of the Forever nameplate surfaces that can support a
-- Blizzard-native implementation. The summary deliberately reports capability
-- presence rather than exercising setters. Plate detail reads only identity and
-- well-known object references: it never measures native geometry, reads native
-- text/status values, installs hooks, registers events, or retains Blizzard
-- frames after the command returns.
-- -----------------------------------------------------------------------------
function Debug:NameplateAPIProbe(selector)
    local function C(message) ns:Chat("NameplateAPI", message) end

    local function Accessible(value)
        return not (ns.API and ns.API.CanAccessValue)
            or ns.API.CanAccessValue(value) == true
    end

    local function Text(value)
        if value == nil then return "nil" end
        if not Accessible(value) then return "<secret>" end
        local ok, result = pcall(tostring, value)
        return ok and result or "<unreadable>"
    end

    local function Field(owner, key)
        if owner == nil then return nil end
        local ok, value = pcall(function() return owner[key] end)
        if not ok or not Accessible(value) then return nil end
        return value
    end

    local function HasFunction(owner, key)
        return type(Field(owner, key)) == "function"
    end

    local function Call(owner, methodName, ...)
        local method = Field(owner, methodName)
        if type(method) ~= "function" then return nil end
        local result = {pcall(method, owner, ...)}
        if not result[1] then return nil end
        table.remove(result, 1)
        return unpack(result)
    end

    local function ObjectLabel(object)
        if object == nil then return "nil" end
        local objectType = Call(object, "GetObjectType") or type(object)
        local name = Call(object, "GetDebugName") or Call(object, "GetName")
        return name and (Text(objectType) .. ":" .. Text(name)) or Text(objectType)
    end

    local function Flag(value)
        return value == true and "yes" or "no"
    end

    local cNamePlate = rawget(_G, "C_NamePlate")
    local cManager = rawget(_G, "C_NamePlateManager")
    local cCurve = rawget(_G, "C_CurveUtil")
    local cXML = rawget(_G, "C_XMLUtil")
    local cAuras = rawget(_G, "C_UnitAuras")
    local cDuration = rawget(_G, "C_DurationUtil")
    local textureGroup = rawget(_G, "TextureLoadingGroupMixin")
    local cooldownMixin = rawget(_G, "CooldownFrameMixin")
    local enum = rawget(_G, "Enum")
    local luaCurveType = Field(enum, "LuaCurveType")

    local templateAvailable = false
    local getTemplateInfo = Field(cXML, "GetTemplateInfo")
    if type(getTemplateInfo) == "function" then
        local ok, info = pcall(getTemplateInfo, "CustomAuraContainerTemplate")
        templateAvailable = ok and Accessible(info) and info ~= nil
    end

    local version, build, _, interface = "?", "?", nil, "?"
    if type(GetBuildInfo) == "function" then
        version, build, _, interface = GetBuildInfo()
    end

    C(("build=%s version=%s interface=%s targetForever=%s"):format(
        Text(build), Text(version), Text(interface),
        Flag(ns.Compat and ns.Compat.IS_TARGET_FOREVER_BUILD == true)))
    C(("plates list=%s lookup=%s size=%s enemySize=%s friendlySize=%s friendlyClickThrough=%s"):format(
        Flag(HasFunction(cNamePlate, "GetNamePlates")),
        Flag(HasFunction(cNamePlate, "GetNamePlateForUnit")),
        Flag(HasFunction(cNamePlate, "SetNamePlateSize")),
        Flag(HasFunction(cNamePlate, "SetNamePlateEnemySize")),
        Flag(HasFunction(cNamePlate, "SetNamePlateFriendlySize")),
        Flag(HasFunction(cNamePlate, "SetNamePlateFriendlyClickThrough"))))
    C(("manager simplified=%s hitTestInsets=%s textureTags=%s/%s"):format(
        Flag(HasFunction(cManager, "SetNamePlateSimplified")),
        Flag(HasFunction(cManager, "SetNamePlateHitTestInsets")),
        Flag(HasFunction(textureGroup, "AddTexture")),
        Flag(HasFunction(textureGroup, "RemoveTexture"))))
    C(("secretColor curve=%s step=%s unitHealthPercent=%s createColor=%s accessCheck=%s"):format(
        Flag(HasFunction(cCurve, "CreateColorCurve")),
        Flag(Field(luaCurveType, "Step") ~= nil),
        Flag(type(rawget(_G, "UnitHealthPercent")) == "function"),
        Flag(type(rawget(_G, "CreateColor")) == "function"),
        Flag(type(rawget(_G, "canaccessvalue")) == "function")))
    C(("auras template=%s duration=%s baseDuration=%s unitAuras=%s durationObject=%s cooldownDuration=%s"):format(
        Flag(templateAvailable),
        Flag(HasFunction(cAuras, "GetAuraDuration")),
        Flag(HasFunction(cAuras, "GetAuraBaseDuration")),
        Flag(HasFunction(cAuras, "GetUnitAuras")),
        Flag(HasFunction(cDuration, "CreateDuration")),
        Flag(HasFunction(cooldownMixin, "SetCooldownFromDurationObject"))))

    local plates = {}
    local getNamePlates = Field(cNamePlate, "GetNamePlates")
    if type(getNamePlates) == "function" then
        local ok, result = pcall(getNamePlates)
        if ok and Accessible(result) and type(result) == "table" then
            for index = 1, #result do plates[#plates + 1] = result[index] end
        end
    end

    local requested = type(selector) == "string"
        and tonumber(selector:match("^%s*plate%s+(%d+)%s*$")) or nil

    local function PlateData(root)
        local unit
        if ns.API and ns.API.GetPlateUnitToken then
            local ok, result = pcall(ns.API.GetPlateUnitToken, root)
            if ok then unit = result end
        end
        if unit ~= nil and not Accessible(unit) then unit = nil end
        local unitFrame = Field(root, "UnitFrame")
        local healthContainer = Field(unitFrame, "HealthBarsContainer")
        local health = Field(unitFrame, "healthBar") or Field(healthContainer, "healthBar")
            or Field(healthContainer, "HealthBar")
        local power = Field(unitFrame, "powerBar") or Field(unitFrame, "PowerBar")
        local cast = Field(unitFrame, "castBar") or Field(unitFrame, "CastBar")
        local name = Field(unitFrame, "name") or Field(unitFrame, "Name")
        local auras = Field(unitFrame, "BuffFrame") or Field(unitFrame, "Auras")
            or Field(unitFrame, "AuraFrame")
        local standard, forbidden
        local lookup = Field(cNamePlate, "GetNamePlateForUnit")
        if unit and type(lookup) == "function" then
            local okStandard, standardResult = pcall(lookup, unit)
            if okStandard and Accessible(standardResult) then standard = standardResult end
            local okForbidden, forbiddenResult = pcall(lookup, unit, true)
            if okForbidden and Accessible(forbiddenResult) then forbidden = forbiddenResult end
        end
        local isForbidden = Call(root, "IsForbidden") == true
        return unit, unitFrame, health, power, cast, name, auras,
            standard == root, forbidden == root, isForbidden
    end

    C("visible=" .. #plates .. " (identity/region presence only; no native values or geometry read)")
    if requested then
        local root = plates[requested]
        if not root then
            C(("PLATE[%d] does not exist; valid range is 1-%d"):format(requested, #plates))
            return
        end
        local unit, unitFrame, health, power, cast, name, auras,
            standardMatch, forbiddenMatch, isForbidden = PlateData(root)
        local guid = unit and ns.API and ns.API.ReadUnitGUID and ns.API.ReadUnitGUID(unit) or nil
        local exists = unit and ns.API and ns.API.ReadUnitExists and ns.API.ReadUnitExists(unit) or nil
        local friendly = unit and ns.API and ns.API.ReadUnitIsFriend
            and ns.API.ReadUnitIsFriend("player", unit) or nil
        local player = unit and ns.API and ns.API.ReadUnitIsPlayer and ns.API.ReadUnitIsPlayer(unit) or nil
        C(("=== PLATE[%d] unit=%s guid=%s exists=%s friendly=%s player=%s forbidden=%s ==="):format(
            requested, Text(unit), Text(guid), Text(exists), Text(friendly), Text(player), Flag(isForbidden)))
        C(("root=%s standardLookup=%s forbiddenLookup=%s unitFrame=%s"):format(
            ObjectLabel(root), Flag(standardMatch), Flag(forbiddenMatch), ObjectLabel(unitFrame)))
        C(("regions health=%s power=%s cast=%s name=%s auras=%s"):format(
            ObjectLabel(health), ObjectLabel(power), ObjectLabel(cast),
            ObjectLabel(name), ObjectLabel(auras)))
        local state = unit and ns.ForeverNameplates and ns.ForeverNameplates.statesByUnit
            and ns.ForeverNameplates.statesByUnit[unit] or nil
        C(("turboFaceState=%s overlay=%s"):format(
            Flag(state ~= nil), ObjectLabel(state and state.overlay)))
        return
    end

    for index = 1, math.min(#plates, 10) do
        local unit, unitFrame, health, power, cast, name, auras,
            standardMatch, forbiddenMatch, isForbidden = PlateData(plates[index])
        C(("PLATE[%d] unit=%s forbidden=%s lookup=%s/%s regions=%s%s%s%s%s"):format(
            index, Text(unit), Flag(isForbidden), Flag(standardMatch), Flag(forbiddenMatch),
            health and "H" or "-", power and "P" or "-", cast and "C" or "-",
            name and "N" or "-", auras and "A" or "-"))
    end
    if #plates > 10 then C("Only the first 10 visible plates are listed.") end
    C("Run /tf nameplateapiprobe plate N for one plate's safe object inventory.")
end

function Debug:HandleSlash(args)
    args = (args or ""):lower():match("^%s*(.-)%s*$") or ""
    args = args:gsub("%s+", " ")
    if args == "reset" then
        self:Reset()
        ns:Chat("Debug", "counters reset")
    elseif args == "diag" then
        self:Diag()
    elseif args == "plates" then
        ns.DebugPlateTrace = not ns.DebugPlateTrace or nil
        ns:Chat("Plates", ns.DebugPlateTrace and "event trace ON — ADDED/REMOVED will print" or "event trace off")
    elseif args == "popups" then
        -- Prints every StaticPopup as it is shown. Used to identify the real
        -- popup name on a client where the spirit healer confirmation is not
        -- XP_LOSS / XP_LOSS_NO_SICKNESS (see Automation.lua).
        ns.DebugPopupTrace = not ns.DebugPopupTrace or nil
        if ns.DebugPopupTrace and ns.PlusAutomation and ns.PlusAutomation.EnsurePopupHook then
            ns.PlusAutomation:EnsurePopupHook()
        end
        ns:Chat("Popups", ns.DebugPopupTrace
            and "popup trace ON — every StaticPopup_Show will print its name"
            or "popup trace off")
    elseif args == "cvars" or args:match("^cvars ") then
        local query = args:match("^cvars%s*(.*)$") or ""
        if ns.CVarBrowser and ns.CVarBrowser.Open then
            ns.CVarBrowser:Open(query)
        else
            ns:Chat("CVars", "browser unavailable")
        end
    elseif args == "modules" then
        self:ModuleReport()
    elseif args == "compat" then
        if ns.CompatReport then ns.CompatReport() end
    elseif args == "shadow" then
        self:ShadowProbe()
    elseif args == "hptext" or args == "healthtext" then
        self:HealthTextProbe()
    elseif args == "nameplateapiprobe" or args:match("^nameplateapiprobe ") then
        self:NameplateAPIProbe(args:match("^nameplateapiprobe%s*(.*)$"))
    elseif args == "dots" then
        -- Read-only. Dumps what the DoT engine can actually see on the current
        -- target: whether party inclusion is on, whether LibClassicDurations is
        -- registered, and per-aura the caster token, Blizzard's expiration, and
        -- what LCD can supply for it.
        local db = ns.DB and ns.DB() or {}
        local LCD = LibStub and LibStub("LibClassicDurations", true)
        ns:Chat("Dots", string.format("enabled=%s includeParty=%s LCD=%s lcdTracking=%s",
            tostring(db.dotPredictionEnabled), tostring(db.dotPredictionIncludeParty),
            tostring(LCD ~= nil),
            tostring(LCD ~= nil and LCD.activeFrames ~= nil and next(LCD.activeFrames) ~= nil)))
        if not UnitExists("target") then
            ns:Chat("Dots", "no target — target something with DoTs on it")
            return
        end
        local guid = UnitGUID("target")
        local DP = ns.DotPrediction
        local plateUnit = guid and ns.guidToNameplateUnit and ns.guidToNameplateUnit[guid]
        local plate = plateUnit and ns.NP and ns.NP.ResolveDotPredictionPlate
            and ns.NP.ResolveDotPredictionPlate(plateUnit)
            or (plateUnit and ns.unitToPlate and ns.unitToPlate[plateUnit])
        local hp = plate and plate.hp
        local prediction = DP and DP:GetPrediction(plateUnit or "target") or nil
        local dotShown = hp and hp._tfDotBar and hp._tfDotBar:IsShown() or false
        ns:Chat("Dots", string.format(
            "plate unit=%s mapped=%s mode=%s liveGUID=%s cachedGUID=%s hpWidth=%s overlay=%s remaining=%s",
            tostring(plateUnit or "-"), tostring(plate ~= nil),
            tostring(plate and (plate._tfDotOnly and "dot-only" or "enhanced") or "-"),
            tostring(plateUnit and UnitGUID(plateUnit) or "-"),
            tostring(plate and plate.cachedGUID or "-"),
            hp and string.format("%.1f", hp:GetWidth() or 0) or "-",
            tostring(dotShown), tostring(prediction and math.floor(prediction.remainingDamage or 0) or "-")))

        if DP and DP.GetHealthBasis then
            local currentBasis, maxBasis, confidence, source = DP:GetHealthBasis(plateUnit or "target")
            ns:Chat("Dots", string.format("health basis source=%s confidence=%s current=%s max=%s",
                tostring(source or "?"), tostring(confidence or "?"),
                currentBasis and string.format("%.0f", currentBasis) or "?",
                maxBasis and string.format("%.0f", maxBasis) or "?"))
        end

        if hp then
            local dot = hp._tfDotBar
            local bg = hp._tfDotBarBG
            local fill = hp.GetStatusBarTexture and hp:GetStatusBarTexture()
            local dl, ds
            if dot and dot.GetDrawLayer then dl, ds = dot:GetDrawLayer() end
            local bl, bs
            if bg and bg.GetDrawLayer then bl, bs = bg:GetDrawLayer() end
            local fl, fs
            if fill and fill.GetDrawLayer then fl, fs = fill:GetDrawLayer() end
            local vr, vg, vb, va
            if dot and dot.GetVertexColor then vr, vg, vb, va = dot:GetVertexColor() end
            local nativeUF = plate and (plate.nativeUnitFrame or (plate.parentPlate and plate.parentPlate.UnitFrame))
            local nativeHP = nativeUF and (nativeUF.healthBar or (nativeUF.HealthBarsContainer and nativeUF.HealthBarsContainer.healthBar))
            ns:Chat("Dots", string.format(
                "render hp=%sx%s nativeHP=%s hpShown=%s hpAlpha=%.2f dot=%sx%s dotAlpha=%.2f inset=%s",
                string.format("%.1f", hp:GetWidth() or 0), string.format("%.1f", hp:GetHeight() or 0),
                tostring(nativeHP == hp), tostring(hp.IsShown and hp:IsShown() or false),
                hp.GetEffectiveAlpha and (hp:GetEffectiveAlpha() or 0) or (hp.GetAlpha and (hp:GetAlpha() or 0) or 0),
                dot and string.format("%.1f", dot:GetWidth() or 0) or "-",
                dot and string.format("%.1f", dot:GetHeight() or 0) or "-",
                dot and dot.GetEffectiveAlpha and (dot:GetEffectiveAlpha() or 0) or (dot and dot.GetAlpha and (dot:GetAlpha() or 0) or 0),
                tostring(plate and plate._lastDotBottomInset or "-")))
            ns:Chat("Dots", string.format(
                "layers fill=%s:%s bg=%s:%s dot=%s:%s rgba=%s",
                tostring(fl or "-"), tostring(fs or "-"),
                tostring(bl or "-"), tostring(bs or "-"),
                tostring(dl or "-"), tostring(ds or "-"),
                (vr and string.format("%.2f,%.2f,%.2f,%.2f", vr, vg, vb, va or 1)) or "-"))
        end

        local now, shown = GetTime(), 0
        for i = 1, 40 do
            local name, _, _, _, duration, expiration, source, _, _, spellID =
                ns.API.UnitDebuff("target", i, "HARMFUL")
            if not name then break end
            shown = shown + 1
            local lcdDur
            if LCD and spellID and source and source ~= "player" and source ~= "pet" then
                local srcGUID = UnitGUID(source)
                local okc, d = pcall(LCD.GetAuraDurationByGUID, LCD, guid, spellID, srcGUID)
                lcdDur = okc and d or nil
            end
            local tickInfo
            if DP and spellID then
                local sourceGUID = source and UnitGUID(source) or nil
                tickInfo = DP:GetTickInfo(spellID, guid, sourceGUID)
            end
            ns:Chat("Dots", string.format("%d %s id=%s src=%s exp=%s lcd=%s tick=%s interval=%s[%s]",
                i, tostring(name), tostring(spellID), tostring(source),
                (expiration and expiration > 0) and string.format("%.1fs", expiration - now) or "0",
                lcdDur and string.format("%.1fs", lcdDur) or "-",
                tickInfo and tickInfo.tick and string.format("%.0f", tickInfo.tick) or "unlearned",
                tickInfo and tickInfo.interval and string.format("%.2f", tickInfo.interval) or "-",
                tostring(tickInfo and tickInfo.intervalSource or "-")))
        end
        if shown == 0 then ns:Chat("Dots", "target has no harmful auras") end

    elseif args == "zone" then
        -- Read-only dump of everything that could explain a missing minimap
        -- zone text. Nothing here mutates state -- an earlier hand-typed probe
        -- did, and poisoned its own reading.
        local p = (ns.PlusSettings and ns.PlusSettings()) or {}
        ns:Chat("Zone", string.format("shape=%s banner=%s hideZoneText=%s",
            tostring(p.minimapShape), tostring(p.minimapZoneBanner),
            tostring(p.hideMiniZoneText)))

        -- Frame names differ across the 1.15.9 retail-derived minimap, so
        -- report which of the candidates actually resolve.
        local cluster = MinimapCluster
        local btn = MinimapZoneTextButton or (cluster and cluster.ZoneTextButton)
        local txt = MinimapZoneText
            or (btn and btn.Text)
            or (cluster and cluster.ZoneTextButton and cluster.ZoneTextButton.Text)
        ns:Chat("Zone", string.format("globals: Button=%s Text=%s Cluster.ZoneTextButton=%s",
            tostring(MinimapZoneTextButton ~= nil), tostring(MinimapZoneText ~= nil),
            tostring(cluster ~= nil and cluster.ZoneTextButton ~= nil)))

        if not btn then
            ns:Chat("Zone", "no zone text button found under any known name")
        else
            local par = btn.GetParent and btn:GetParent()
            ns:Chat("Zone", string.format("button: shown=%s alpha=%.2f parent=%s strata=%s",
                tostring(btn:IsShown()),
                btn.GetAlpha and btn:GetAlpha() or -1,
                tostring(par and par.GetName and par:GetName() or par),
                tostring(btn.GetFrameStrata and btn:GetFrameStrata())))
            local point, _, relPoint, x, y = btn:GetPoint()
            ns:Chat("Zone", string.format("anchor: %s -> %s  x=%s y=%s  size=%sx%s",
                tostring(point), tostring(relPoint), tostring(x), tostring(y),
                tostring(btn.GetWidth and math.floor(btn:GetWidth() or 0)),
                tostring(btn.GetHeight and math.floor(btn:GetHeight() or 0))))
        end
        if txt then
            ns:Chat("Zone", string.format("text: shown=%s alpha=%.2f value=%q",
                tostring(txt:IsShown()),
                txt.GetAlpha and txt:GetAlpha() or -1,
                tostring(txt.GetText and txt:GetText() or "")))
        end
        ns:Chat("Zone", string.format("minimap=%dx%d cluster=%dx%d toggleShown=%s",
            math.floor(Minimap and Minimap:GetWidth() or 0),
            math.floor(Minimap and Minimap:GetHeight() or 0),
            math.floor(cluster and cluster:GetWidth() or 0),
            math.floor(cluster and cluster:GetHeight() or 0),
            tostring(MinimapToggleButton and MinimapToggleButton:IsShown())))
    elseif args == "heals" then
        local HP = ns.HealPrediction
        if not HP then ns:Chat("Heals", "engine not loaded") return end
        local db = TurboFaceDB or {}
        ns:Chat("Heals", string.format("enabled=%s player=%s target=%s tot=%s pet=%s party=%s hots=%s",
            tostring(db.healPredictionEnabled == true), tostring(db.healPredictionPlayer ~= false),
            tostring(db.healPredictionTarget ~= false), tostring(db.healPredictionToT ~= false),
            tostring(db.healPredictionPet ~= false), tostring(db.healPredictionParty ~= false),
            tostring(db.healPredictionHots ~= false)))

        local unit = UnitExists("target") and "target" or "player"
        local prediction = HP:GetPrediction(unit)
        ns:Chat("Heals", string.format("%s: total=%.0f direct=%.0f next-HoT=%.0f segments=%d hp=%d/%d",
            unit, prediction.total or 0, prediction.direct or 0, prediction.hot or 0,
            prediction.segmentCount or 0, UnitHealth(unit) or 0, UnitHealthMax(unit) or 0))
        local now = GetTime()
        local segments = prediction.segments or {}
        for i = 1, #segments do
            local seg = segments[i]
            local eta = seg.endTime and math.max(0, seg.endTime - now) or 0
            ns:Chat("Heals", string.format("  %d %s amount=%.0f caster=%s%s spell=%s eta=%.2fs",
                i, tostring(seg.kind), seg.amount or 0, tostring(seg.casterUnit or seg.casterGUID or "unknown"),
                seg.isMine and " [mine]" or "", tostring(seg.spellID or "?"), eta))
        end

    elseif args == "meter" then
        local CM = ns.CombatMeter
        if not (CM and CM.GetDebugState) then
            ns:Chat("Meter", "Combat Meter engine not loaded")
            return
        end
        local state = CM:GetDebugState()
        local currentCount, overallCount, rosterCount = 0, 0, 0
        for _ in pairs(state.currentActors or {}) do currentCount = currentCount + 1 end
        for _ in pairs(state.overallActors or {}) do overallCount = overallCount + 1 end
        for _ in pairs(state.roster or {}) do rosterCount = rosterCount + 1 end
        ns:Chat("Meter", string.format(
            "window=%s badgeConsumer=%s runtimeNeeded=%s runtime=%s current=%s dmg=%.0f dur=%.2fs actors=%d | overall dmg=%.0f dur=%.2fs actors=%d | rosterGUIDs=%d",
            tostring(state.windowEnabled), tostring(state.badgeConsumer), tostring(state.runtimeNeeded),
            tostring(state.runtime), tostring(state.currentActive),
            state.currentDamage or 0, state.currentDuration or 0, currentCount,
            state.overallDamage or 0, state.overallDuration or 0, overallCount, rosterCount))

    elseif args == "regen" then
        local P = ns.Power
        if not (P and P.GetRegenDebugState) then
            ns:Chat("Regen", "PowerCost regen engine not loaded")
            return
        end
        local s = P:GetRegenDebugState()
        ns:Chat("Regen", string.format(
            "shared=%s next=%s anchor=%.3f | 5SR=%.2fs pendingSpend=%s",
            tostring(s.sharedSource or "unknown"),
            s.sharedNextIn and string.format("%.2fs", s.sharedNextIn) or "unknown",
            s.sharedAnchor or 0, s.fiveSRRemaining or 0, tostring(s.pendingManaSpend == true)))
        ns:Chat("Regen", string.format(
            "mana=%s/%s energy=%s/%s rage=%s/%s grace=%.2fs health=%s (manaLast=%.3f energyLast=%.3f rageLast=%.3f healthLast=%.3f)",
            tostring(s.manaPhaseKnown == true),
            s.manaNextIn and string.format("%.2fs", s.manaNextIn) or "?",
            tostring(s.energyPhaseKnown == true),
            s.energyNextIn and string.format("%.2fs", s.energyNextIn) or "?",
            tostring(s.rageDecayPhaseKnown == true),
            s.rageNextIn and string.format("%.2fs", s.rageNextIn) or "?",
            s.rageGraceRemaining or 0,
            tostring(s.healthPhaseKnown == true),
            s.manaTickLastObserved or 0, s.energyTickLastObserved or 0,
            s.rageDecayLastObserved or 0, s.healthTickLastObserved or 0))

    elseif args == "skills" then
        -- Raw skill-panel dump. The talent-tab exclusion is not catching the
        -- class skill lines, so print what the client actually reports rather
        -- than assuming the names match.
        if not GetNumSkillLines or not GetSkillLineInfo then
            ns:Chat("Skills", "skill line API unavailable")
            return
        end

        local tabs = {}
        if GetNumTalentTabs and GetTalentTabInfo then
            local ok, count = pcall(GetNumTalentTabs)
            ns:Chat("Skills", string.format("GetNumTalentTabs = %s%s",
                tostring(ok and count or "error"),
                (not ok or not count or count == 0) and "  |cffff5555<- no tabs, exclusion cannot fire|r" or ""))
            if ok and count then
                for i = 1, count do
                    -- Print both leading returns: Classic Era gives the tab ID
                    -- first and the name second, other builds the reverse.
                    local okInfo, a, b = pcall(GetTalentTabInfo, i)
                    -- On failure `a` is the error message, and the string test
                    -- below would accept it as a tab name. Discard both.
                    if not okInfo then a, b = nil, nil end
                    local candidate
                    if type(b) == "string" and b ~= "" and not tonumber(b) then candidate = b
                    elseif type(a) == "string" and a ~= "" and not tonumber(a) then candidate = a end
                    ns:Chat("Skills", string.format('  tab %d: [1]=%s [2]=%s -> using %s', i,
                        tostring(a), tostring(b),
                        candidate and ('"' .. candidate .. '"') or "|cffff5555nothing usable|r"))
                    if candidate then tabs[candidate] = true end
                end
            end
        else
            ns:Chat("Skills", "|cffff5555GetTalentTabInfo missing on this client|r")
        end

        local level = UnitLevel and UnitLevel("player") or 0
        ns:Chat("Skills", string.format("player level %d, weapon cap would be %d", level, level * 5))

        local header = "(none)"
        for i = 1, GetNumSkillLines() do
            local name, isHeader, isExpanded, rank, _, modifier, maxRank = GetSkillLineInfo(i)
            if isHeader then
                header = tostring(name)
                ns:Chat("Skills", string.format("[header] %s (expanded=%s)", header, tostring(isExpanded)))
            else
                local flag = ""
                if name and tabs[name] then flag = "  <- matches talent tab"
                elseif maxRank and level > 0 and maxRank == level * 5 then flag = "  <- 5x level" end
                ns:Chat("Skills", string.format('  under "%s": "%s" %s/%s mod=%s%s',
                    header, tostring(name), tostring(rank), tostring(maxRank),
                    tostring(modifier), flag))
            end
        end

    elseif args == "trainerstyleprobe" or args == "trainerstyle"
        or args:match("^trainerstyleprobe %d+$") or args:match("^trainerstyle %d+$")
        or args:match("^trainerstyleprobe root %d+$") or args:match("^trainerstyle root %d+$") then
        local selector = args:match("^trainerstyleprobe%s*(.-)$")
            or args:match("^trainerstyle%s*(.-)$")
        self:TrainerStyleProbe(selector)
    elseif args == "professionprobe"
        or args == "professionprobe crafting"
        or args == "professionprobe tabs"
        or args:match("^professionprobe tab %d+$")
        or args:match("^professionprobe root %d+$")
        or args:match("^professionprobe button %d+$") then
        self:ProfessionProbe(args:match("^professionprobe%s*(.-)$"))
    elseif args == "professiondataprobe"
        or args:match("^professiondataprobe recipes%s*%d*$")
        or args:match("^professiondataprobe recipe %d+$")
        or args:match("^professiondataprobe categories%s*%d*$")
        or args:match("^professiondataprobe trainer%s*%d*$")
        or args:match("^professiondataprobe apis%s*%d*$")
        or args == "professiondataprobe capture"
        or args == "professiondataprobe capture recipes"
        or args == "professiondataprobe capture trainer" then
        self:ProfessionDataProbe(args:match("^professiondataprobe%s*(.-)$"))
    elseif args == "trainer" then
        -- Dumps the inputs the profession rank-known check depends on. Added
        -- because "Apprentice Cooking" should match the same rule that fixed
        -- First Aid, so one of these values is not what it looks like.
        local T = ns.Trainer
        if not T then ns:Chat("Trainer", "module not loaded") return end
        if T.DebugTrainingQueue then T:DebugTrainingQueue() end

        local modernBook = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
        local attachedBook = T.ForeverSpellbookFrame
        local loaderListening = T.SpellbookLoader and T.SpellbookLoader.IsEventRegistered
            and T.SpellbookLoader:IsEventRegistered("ADDON_LOADED") or false
        local selectedTab = attachedBook and attachedBook.GetTab and attachedBook:GetTab() or nil
        local trainingTab = T.ForeverSpellbookTrainingTab
        local skillsTab = T.ForeverSpellbookSkillsTab
        ns:Chat("Trainer", string.format(
            "spellbook modern=%s attached=%s loader=%s detached=%s trainingShown=%s skillsShown=%s selected=%s",
            tostring(modernBook ~= nil), tostring(attachedBook ~= nil), tostring(loaderListening),
            tostring(T.ForeverSpellbookDetached == true),
            tostring(trainingTab and trainingTab:IsShown() or false),
            tostring(skillsTab and skillsTab:IsShown() or false),
            tostring(selectedTab)))

        local raw = GetTradeSkillLine and GetTradeSkillLine()
        local usable = type(raw) == "string" and raw ~= "" and raw ~= "UNKNOWN"
            and not (UNKNOWN and raw == UNKNOWN)
        local key = (usable and T.GetProfessionKey) and T:GetProfessionKey(raw) or nil
        if not key and T.DetectTrainerProfession then key = T:DetectTrainerProfession() end

        -- The name the rank check matches against, resolved from the key rather
        -- than from window state.
        local line = (key and T.GetProfessionDisplayName) and T:GetProfessionDisplayName(key) or nil
        if not line and usable then line = raw end

        ns:Chat("Trainer", string.format("GetTradeSkillLine() = %s%s",
            raw and ('"' .. tostring(raw) .. '"') or "nil",
            usable and "" or "  |cffff5555<- sentinel, window closed|r"))
        ns:Chat("Trainer", string.format("profession key      = %s", tostring(key)))
        ns:Chat("Trainer", string.format("matching name       = %s", line and ('"' .. line .. '"') or "nil"))

        -- Via the shared engine, so this reports exactly what the rank check
        -- sees rather than a second scan with different collapsed-header
        -- behaviour.
        local rank, maxRank = 0, 0
        if line and ns.Skills and ns.Skills.Get then
            local r, m = ns.Skills:Get(line)
            rank, maxRank = r or 0, m or 0
        end
        ns:Chat("Trainer", string.format("skill rank/max      = %d / %d%s",
            rank, maxRank, maxRank == 0 and "  |cffff5555<- max is 0, rank check cannot fire|r" or ""))

        local db = TurboFaceTrainerDB
        if not db then ns:Chat("Trainer", "TurboFaceTrainerDB is nil") return end

        -- Dump every stored profession key with its entry count. If the row the
        -- user sees is not under the key we resolved, this shows where it is.
        local function CountEntries(levels)
            local buckets, entries = 0, 0
            if type(levels) == "table" then
                for _, bucket in pairs(levels) do
                    buckets = buckets + 1
                    if type(bucket) == "table" then
                        for _ in pairs(bucket) do entries = entries + 1 end
                    end
                end
            end
            return buckets, entries
        end

        for label, root in pairs({ professionData = db.professionData, recipeData = db.recipeData }) do
            if type(root) == "table" then
                for storedKey, levels in pairs(root) do
                    local b, e = CountEntries(levels)
                    ns:Chat("Trainer", string.format("%s[%s]: %d buckets, %d entries%s",
                        label, tostring(storedKey), b, e,
                        (storedKey == key) and "  <- resolved key" or ""))
                end
            else
                ns:Chat("Trainer", label .. " is nil")
            end
        end

        -- Raw entry names under the resolved key, verbatim, no filtering.
        local data = key and db.professionData and db.professionData[key]
        if not data then ns:Chat("Trainer", "no professionData under the resolved key") return end

        local shown = 0
        for skillReq, entries in pairs(data) do
            for name, entry in pairs(entries) do
                if shown < 15 then
                    shown = shown + 1
                    local sid = type(entry) == "table" and entry.spellID or nil
                    local sub
                    if sid and GetSpellInfo then local _, s2 = GetSpellInfo(sid); sub = s2 end
                    local cap = (T.GetProfessionRankCap and line)
                        and T:GetProfessionRankCap(tostring(name), line, sid) or nil
                    ns:Chat("Trainer", string.format('  [%s] key=%s(%s) spellID=%s sub=%s rank=%s cap=%s',
                        tostring(skillReq), tostring(name), type(name), tostring(sid),
                        (sub and sub ~= "") and sub or "none",
                        tostring(type(entry) == "table" and entry.rank or nil), tostring(cap)))
                end
            end
        end
        if shown == 0 then ns:Chat("Trainer", "resolved key exists but holds no entries") end
    else
        self:Toggle()
    end
    return true
end

-- -----------------------------------------------------------------------------
-- /tf debug hptext — inspect TurboFace's restricted-safe, write-only anchor
-- amendment. Blizzard's 1.15.9 health FontStrings reject FrameMeasurement, so
-- this probe deliberately never calls GetPoint/GetCenter/GetLeft/GetRight on
-- those regions.
-- -----------------------------------------------------------------------------
function Debug:HealthTextProbe()
    local function C(msg) ns:Chat("HPText", msg) end

    local nativePlate
    if UnitExists and UnitExists("target") and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        nativePlate = C_NamePlate.GetNamePlateForUnit("target")
    end
    if not nativePlate then
        for _, mp in pairs(ns.unitToPlate or {}) do
            local plate = mp and (mp.parentPlate or (mp.GetParent and mp:GetParent()))
            if plate and plate.UnitFrame then
                nativePlate = plate
                break
            end
        end
    end

    if not nativePlate then
        C("no native nameplate found — target or mouseover a unit and rerun")
        return
    end

    local unitFrame = nativePlate.UnitFrame
    local container = unitFrame and unitFrame.HealthBarsContainer
    local healthBar, text, leftText, rightText
    if ns.GetNativeHealthTextCenterRegions then
        healthBar, text, leftText, rightText = ns.GetNativeHealthTextCenterRegions(nativePlate)
    end
    if not healthBar then
        C("sampled nameplate has no native health-text regions")
        return
    end

    local centerTargetLabel, centerYOffset = "healthBar", 0
    local liveHook, regionHooks, pending, hookError = false, false, false, nil
    local mode, applyCount, restoreError, restoreMode = "unknown", 0, nil, nil
    if ns.GetNativeHealthTextCenterRuntime then
        local _target
        _target, centerTargetLabel, centerYOffset, liveHook, regionHooks, pending, hookError,
            mode, applyCount, restoreError, restoreMode = ns.GetNativeHealthTextCenterRuntime(nativePlate)
    end

    local function NumberLabel(value)
        if type(value) == "number" then return ("%.3f"):format(value) end
        return "?"
    end

    local function SafeNumberMethod(object, methodName)
        local method = object and object[methodName]
        if type(method) ~= "function" then return nil end
        local ok, value = pcall(method, object)
        if ok and type(value) == "number" then return value end
        return nil
    end

    local function RegionStatus(label, region)
        C(("%s: present=%s geometry=not queried (restricted region)"):format(
            label, tostring(region ~= nil)))
    end

    local style = "?"
    if C_CVar and C_CVar.GetCVar then
        local ok, value = pcall(C_CVar.GetCVar, "nameplateStyle")
        if ok and value ~= nil then style = tostring(value) end
    end
    local classic = NamePlateSetupOptions and NamePlateSetupOptions.useClassicHealthBar
    local barWidth = SafeNumberMethod(healthBar, "GetWidth")
    local chassisWidth = SafeNumberMethod(container, "GetWidth")

    C("=== Blizzard nameplate-health text center probe ===")
    local centerEnabled = ns.c_nameplateCenterHealthText ~= false
    local wholePlateTarget = ns.c_nameplateCenterHealthTextOnNameplate ~= false
    local centered = ns.IsNativeHealthTextCentered
        and ns.IsNativeHealthTextCentered(nativePlate) or false
    C(("enabled=%s targetMode=%s centered=%s pairGap=%s nativeChassis=%s"):format(
        tostring(centerEnabled),
        wholePlateTarget and "entire-nameplate" or "health-bar",
        tostring(centered),
        tostring(ns.GetNativeHealthTextCenterGap
            and ns.GetNativeHealthTextCenterGap() or "?"),
        tostring(nativePlate._tfTurboNativeHealthChassis == true)))
    C(("style=%s useClassicHealthBar=%s target=%s yOffset=%s"):format(
        tostring(style), tostring(classic), tostring(centerTargetLabel or "?"),
        NumberLabel(centerYOffset or 0)))
    C(("mode=%s applyCount=%s live frame hook=%s region hooks=%s reconcile pending=%s"):format(
        tostring(mode or "unknown"), tostring(applyCount or 0), tostring(liveHook),
        tostring(regionHooks), tostring(pending)))
    C(("fillWidth=%s chassisWidth=%s restoreMode=%s"):format(
        NumberLabel(barWidth), NumberLabel(chassisWidth), tostring(restoreMode or "none")))

    RegionStatus("Text", text)
    RegionStatus("RightText (numeric in BOTH mode)", rightText)
    RegionStatus("LeftText (percent in BOTH mode)", leftText)
    C("native FontString anchors/bounds intentionally unmeasured; 1.15.9 blocks FrameMeasurement on these regions")

    local err = ns.GetNativeHealthTextCenterError
        and ns.GetNativeHealthTextCenterError(nativePlate) or nil
    if hookError then
        C("|cffff5555live-hook error: " .. tostring(hookError) .. "|r")
    end
    if restoreError then
        C("|cffff5555last restore error: " .. tostring(restoreError) .. "|r")
    end
    if err then
        C("|cffff5555last centering error: " .. tostring(err) .. "|r")
    elseif centered and not hookError and not restoreError then
        C("restricted-safe anchor amendment applied; Blizzard still owns text, font, color, visibility, and values")
    elseif not centered and not hookError and not restoreError then
        C("|cffffaa00centering is not active on this sampled plate; inspect enabled/nativeChassis/style and applyCount above|r")
    end
end

-- -----------------------------------------------------------------------------
-- /tf debug shadow — inspect the active native nameplate-shadow path.
-- The current test build uses a private runtime FontObject on Blizzard's own
-- SLUG name FontString; no duplicate black glyph underlay should exist.
-- -----------------------------------------------------------------------------
function Debug:ShadowProbe()
    local function C(msg) ns:Chat("Shadow", msg) end

    local source, nativePlate
    local fallbackSource, fallbackPlate
    for _, mp in pairs(ns.unitToPlate or {}) do
        local plate = mp and (mp.parentPlate or (mp.GetParent and mp:GetParent()))
        local uf = plate and plate.UnitFrame
        local candidate = uf and uf.name
        if candidate and candidate.GetFont then
            if not fallbackSource then
                fallbackSource, fallbackPlate = candidate, plate
            end
            if ns.IsNativeNameShadowApplied and ns.IsNativeNameShadowApplied(plate) then
                source, nativePlate = candidate, plate
                break
            end
        end
    end
    source = source or fallbackSource
    nativePlate = nativePlate or fallbackPlate

    if not source then
        C("no visible native nameplate name found — target or mouseover a nameplated unit and rerun")
        return
    end

    C("=== Blizzard nameplate-name native FontObject probe ===")
    local path, size, flags = source:GetFont()
    C(("source font: %s | size=%s | flags=%q"):format(
        tostring(path), tostring(size), tostring(flags or "")))
    local fontObject = source.GetFontObject and source:GetFontObject() or nil
    C("source fontObject=" .. tostring(fontObject and (fontObject.GetName and fontObject:GetName() or fontObject) or "nil"))

    if source.GetShadowColor then
        local r, g, b, a = source:GetShadowColor()
        C(("source native shadow color: %s,%s,%s,%s"):format(
            tostring(r), tostring(g), tostring(b), tostring(a)))
    end
    if source.GetShadowOffset then
        local ox, oy = source:GetShadowOffset()
        C(("source native shadow offset: %s,%s"):format(tostring(ox), tostring(oy)))
    end

    local configured = nativePlate and ns.IsNativeNameShadowApplied
        and ns.IsNativeNameShadowApplied(nativePlate) or false
    local visible = nativePlate and ns.IsNativeNameShadowVisible
        and ns.IsNativeNameShadowVisible(nativePlate) or false
    local mode = ns.GetNativeNameShadowMode and ns.GetNativeNameShadowMode() or "unknown"
    C(("TurboFace mode=%s configured=%s visible=%s"):format(
        tostring(mode), tostring(configured), tostring(visible)))

    local shadow = nativePlate and ns.GetNativeNameShadowUnderlay
        and ns.GetNativeNameShadowUnderlay(nativePlate) or nil
    C("duplicate underlay exists=" .. tostring(shadow ~= nil) .. " (expected false in native FontObject test)")

    local offsetX, offsetY = 2, -2
    if ns.GetNativeNameShadowOffset then offsetX, offsetY = ns.GetNativeNameShadowOffset() end
    C(("requested native FontObject shadow offset=%s,%s"):format(tostring(offsetX), tostring(offsetY)))

    local err = ns.GetNativeNameShadowError and ns.GetNativeNameShadowError(nativePlate)
    if err then
        C("|cffff5555native FontObject error: " .. tostring(err) .. "|r")
    elseif configured then
        C("native FontObject is applied to Blizzard's own name FontString; visually confirm the shadow and normal name rendering")
    else
        C("|cffffaa00native FontObject is not active on this sampled plate; inspect the name-shadow setting and eligible unit type|r")
    end
end
