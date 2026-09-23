local _, ns = ...

-- Opt-in diagnostic for Classic's on-next-swing queue. It observes only; it
-- never casts, cancels, or changes the queue. Enable for the current session
-- with /tfqueue on and reproduce the unwanted Heroic Strike cancellation.
local QD = {}
ns.QueueDiagnostics = QD

local spellData = ns.SwingTimerSpellData or {}
local GetSpellInfo = ns.API and ns.API.GetSpellInfo
local enabled = false
local hooked = false
local entries = {}
local lastClientSpell
local MAX_ENTRIES = 80

local function SpellName(spellID)
    if not spellID then return "none" end
    local name = GetSpellInfo and GetSpellInfo(spellID)
    return name or ("spell:" .. tostring(spellID))
end

local function ClientQueuedSpell()
    if spellData.GetActiveNextMeleeSpell then
        return spellData.GetActiveNextMeleeSpell()
    end
end

local function Clean(value, limit)
    value = ns.API.SafeToString(value, "<secret>")
    value = value:gsub("[\r\n]+", " | "):gsub("%s+", " ")
    limit = limit or 240
    if #value > limit then value = value:sub(1, limit) .. "..." end
    return value
end

local function Stamp()
    return string.format("%.3f", (GetTime and GetTime()) or 0)
end

local function AddEntry(reason, detail, clientSpell)
    local line = "[" .. Stamp() .. "] " .. tostring(reason)
        .. " | client=" .. SpellName(clientSpell)
    if detail and detail ~= "" then line = line .. " | " .. Clean(detail) end
    entries[#entries + 1] = line
    if #entries > MAX_ENTRIES then table.remove(entries, 1) end
    return line
end

local function PrintContext()
    local first = math.max(1, #entries - 7)
    print("|cff00ccffTFQueue context (oldest -> newest):|r")
    for i = first, #entries do print("  " .. entries[i]) end
end

local function Snapshot(reason, detail)
    if not enabled then return end
    local clientSpell = ClientQueuedSpell()
    AddEntry(reason, detail, clientSpell)
    if clientSpell == lastClientSpell then return end

    if clientSpell then
        print("|cff00ccffTFQueue|r QUEUED " .. SpellName(clientSpell)
            .. " via " .. tostring(reason) .. " at " .. Stamp())
    elseif lastClientSpell then
        print("|cffff7f50TFQueue|r LOST " .. SpellName(lastClientSpell)
            .. " via " .. tostring(reason) .. " at " .. Stamp())
        PrintContext()
    end
    lastClientSpell = clientSpell
end

local function DeferredSnapshot(reason, detail)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Snapshot(reason, detail) end)
    else
        Snapshot(reason, detail)
    end
end

local function CallerStack()
    if not debugstack then return nil end
    return Clean(debugstack(3, 5, 0), 300)
end

local function InstallHooks()
    if hooked or not hooksecurefunc then return end
    hooked = true

    local function HookCancellation(name)
        if type(_G[name]) ~= "function" then return end
        pcall(hooksecurefunc, name, function()
            if not enabled then return end
            local stack = CallerStack()
            AddEntry("API " .. name, stack, ClientQueuedSpell())
            DeferredSnapshot("after API " .. name, stack)
        end)
    end

    HookCancellation("CancelQueuedSpell")
    HookCancellation("CancelCurrentSpell")
    HookCancellation("SpellStopCasting")

    if type(_G.UseAction) == "function" then
        pcall(hooksecurefunc, "UseAction", function(slot, checkCursor, onSelf)
            if not enabled then return end
            local actionType, id = GetActionInfo and GetActionInfo(slot)
            local detail = "slot=" .. tostring(slot)
                .. " type=" .. tostring(actionType) .. " id=" .. tostring(id)
                .. " checkCursor=" .. tostring(checkCursor)
                .. " onSelf=" .. tostring(onSelf)
            if actionType == "spell" then
                detail = detail .. " name=" .. SpellName(id)
            elseif actionType == "macro" and GetMacroInfo then
                local name, _, body = GetMacroInfo(id)
                detail = detail .. " macro=" .. Clean(name, 80)
                    .. " body=" .. Clean(body, 240)
            end
            AddEntry("API UseAction", detail, ClientQueuedSpell())
            DeferredSnapshot("after UseAction", detail)
        end)
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if not enabled then return end
    local arg1, arg2, arg3, arg4 = ...
    local detail

    if event == "UNIT_SPELLCAST_SENT" then
        detail = "unit=" .. ns.API.SafeToString(arg1) .. " target=" .. ns.API.SafeToString(arg2)
            .. " guid=" .. ns.API.SafeToString(arg3) .. " spell=" .. SpellName(arg4)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        detail = "unit=" .. ns.API.SafeToString(arg1) .. " guid=" .. ns.API.SafeToString(arg2)
            .. " spell=" .. SpellName(arg3)
    elseif event == "UNIT_POWER_UPDATE" then
        detail = "unit=" .. ns.API.SafeToString(arg1) .. " power=" .. ns.API.SafeToString(arg2)
            .. " rage=" .. ns.API.SafeToString(ns.API.ReadUnitPower("player", 1))
    elseif event == "UI_ERROR_MESSAGE" then
        detail = "code=" .. ns.API.SafeToString(arg1) .. " message=" .. Clean(arg2)
    elseif event == "PLAYER_TARGET_CHANGED" then
        detail = "target=" .. ns.API.SafeToString(ns.API.ReadUnitName("target"))
            .. " guid=" .. ns.API.SafeToString(ns.API.ReadUnitGUID("target"))
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_FORMS" then
        detail = "form=" .. tostring(GetShapeshiftForm and GetShapeshiftForm())
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        detail = "combat=" .. tostring(UnitAffectingCombat and UnitAffectingCombat("player"))
    end

    -- The state-changing event is delivered after the client updates
    -- IsCurrentSpell. A zero-delay confirmation also catches ordering quirks.
    Snapshot(event, detail)
    if event ~= "CURRENT_SPELL_CAST_CHANGED" then
        DeferredSnapshot("after " .. event, detail)
    end
end)

local EVENTS = {
    "CURRENT_SPELL_CAST_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ACTIONBAR_UPDATE_STATE",
    "UI_ERROR_MESSAGE",
}

local function OnCombatLog(combatInfo)
    if not enabled or not combatInfo then return end
    local sourceGUID = combatInfo[4]
    if sourceGUID ~= UnitGUID("player") then return end
    local subevent = combatInfo[2]
    local detail
    if subevent == "SWING_DAMAGE" then
        detail = "offhand=" .. tostring(combatInfo[21])
    elseif subevent == "SWING_MISSED" then
        detail = "miss=" .. tostring(combatInfo[12])
            .. " offhand=" .. tostring(combatInfo[13])
    elseif subevent == "SPELL_DAMAGE" then
        detail = "spell=" .. SpellName(combatInfo[12])
    elseif subevent == "SPELL_MISSED" then
        detail = "spell=" .. SpellName(combatInfo[12])
            .. " miss=" .. tostring(combatInfo[15])
    else
        return
    end
    Snapshot("CLEU " .. subevent, detail)
    DeferredSnapshot("after CLEU " .. subevent, detail)
end

local function SetEnabled(value)
    value = value == true
    if enabled == value then return end
    enabled = value
    frame:UnregisterAllEvents()
    if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end

    if enabled then
        entries = {}
        InstallHooks()
        for i = 1, #EVENTS do frame:RegisterEvent(EVENTS[i]) end
        if ns.RegisterUnitEvent then
            ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_SENT", "player")
            ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
            ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_FAILED", "player")
            ns.RegisterUnitEvent(frame, "UNIT_SPELLCAST_FAILED_QUIET", "player")
            ns.RegisterUnitEvent(frame, "UNIT_POWER_UPDATE", "player")
        end
        if ns.CLEU then
            ns.CLEU:Register(OnCombatLog, {
                SWING_DAMAGE = true, SWING_MISSED = true,
                SPELL_DAMAGE = true, SPELL_MISSED = true,
            })
        end
        lastClientSpell = ClientQueuedSpell()
        AddEntry("trace enabled", nil, lastClientSpell)
        print("|cff00ccffTFQueue|r tracing ON; reproduce the queue loss. Use /tfqueue dump afterward.")
        print("|cff00ccffTFQueue|r initial client state: " .. SpellName(lastClientSpell))
    else
        print("|cff00ccffTFQueue|r tracing OFF")
    end
end

SLASH_TFQUEUE1 = "/tfqueue"
SlashCmdList["TFQUEUE"] = function(message)
    local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" then
        SetEnabled(true)
    elseif command == "off" then
        SetEnabled(false)
    elseif command == "clear" then
        entries = {}
        lastClientSpell = ClientQueuedSpell()
        AddEntry("trace cleared", nil, lastClientSpell)
        print("|cff00ccffTFQueue|r history cleared")
    elseif command == "dump" then
        print("|cff00ccffTFQueue|r history (oldest -> newest), " .. tostring(#entries) .. " entries:")
        for i = 1, #entries do print("  " .. entries[i]) end
    else
        print("|cff00ccffTFQueue|r " .. (enabled and "ON" or "OFF")
            .. " — /tfqueue on | off | dump | clear")
    end
end
