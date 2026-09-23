local _, ns = ...

-- Native cumulative /played splits. Full levels and every 10% XP boundary are
-- checkpoints, so level 12 produces 12.1 through 12.9 before Level 13.
local Splits = {}
ns.SpeedrunSplits = Splits

local CreateFrame, GetTime = CreateFrame, GetTime
local UnitClass, UnitLevel, UnitRace = UnitClass, UnitLevel, UnitRace
local UnitXP, UnitXPMax = UnitXP, UnitXPMax
local floor, max, min = math.floor, math.max, math.min
local format, sort = string.format, table.sort

local FALLBACK_POINT = { "TOPLEFT", UIParent, "TOPLEFT", 5, -120 }
local DISPLAY_WIDTH = 255
local display, eventFrame
local initialized, synchronized = false, false
local totalAnchor, anchorAt, levelAnchor, levelAnchorAt, pendingOrdinal

local function Chat(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTurboFace Splits:|r " .. tostring(message))
    end
end

local function Config()
    local db = ns.DB()
    return db.speedrunSplits or ns.defaults.speedrunSplits
end

local function Enabled() return Config().enabled == true end

local function AccountDB()
    if type(TurboFaceSpeedrunDB) ~= "table" then TurboFaceSpeedrunDB = {} end
    if type(TurboFaceSpeedrunDB.profiles) ~= "table" then TurboFaceSpeedrunDB.profiles = {} end
    TurboFaceSpeedrunDB.schema = 1
    return TurboFaceSpeedrunDB
end

local function CharacterDB()
    if type(TurboFaceSpeedrunCharDB) ~= "table" then TurboFaceSpeedrunCharDB = {} end
    if type(TurboFaceSpeedrunCharDB.run) ~= "table" then TurboFaceSpeedrunCharDB.run = {} end
    return TurboFaceSpeedrunCharDB
end

local function CopyMap(source)
    local copy = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(key) == "number" and type(value) == "number" then copy[key] = value end
        end
    end
    return copy
end

local function ProfileKey()
    local _, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    return tostring(raceFile or "UNKNOWN") .. ":" .. tostring(classFile or "UNKNOWN")
end

local function Profile()
    local profiles = AccountDB().profiles
    local key = ProfileKey()
    local profile = profiles[key]
    if type(profile) ~= "table" then profile = {}; profiles[key] = profile end
    if type(profile.pb) ~= "table" then profile.pb = {} end
    if type(profile.gold) ~= "table" then profile.gold = {} end
    return profile, key
end

local function CurrentOrdinal()
    local level = max(1, tonumber(UnitLevel("player")) or 1)
    local current = max(0, tonumber(UnitXP("player")) or 0)
    local total = max(0, tonumber(UnitXPMax("player")) or 0)
    local tenth = total > 0 and floor(current * 10 / total) or 0
    return level * 10 + min(9, max(0, tenth))
end

local function SplitLabel(ordinal)
    ordinal = tonumber(ordinal) or 10
    local level, tenth = floor(ordinal / 10), ordinal % 10
    if tenth == 0 then return "Level " .. level end
    return level .. "." .. tenth
end

local function EnsureRun(reset, checkRecreatedCharacter)
    local char = CharacterDB()
    local profile, key = Profile()
    local run = char.run
    local current = CurrentOrdinal()
    local wrongIdentity = run.profileKey and run.profileKey ~= key
    -- Only test this at PLAYER_ENTERING_WORLD. During PLAYER_LEVEL_UP Classic
    -- can briefly return the old UnitLevel while the event argument already
    -- names the new level; treating that transient mismatch as character
    -- recreation would discard the run that was just completed.
    local recreated = checkRecreatedCharacter and current < 20
        and tonumber(run.observedOrdinal) and run.observedOrdinal >= 20
    if reset or wrongIdentity or recreated then run = {}; char.run = run end
    run.profileKey = key
    if type(run.times) ~= "table" then run.times = {} end
    if type(run.referencePB) ~= "table" then run.referencePB = CopyMap(profile.pb) end
    if run.times[10] == nil then run.times[10] = 0 end
    return run, profile
end

local function CurrentTotalTime()
    if synchronized and totalAnchor and anchorAt then
        return max(0, totalAnchor + (GetTime() - anchorAt))
    end
    return tonumber((EnsureRun(false)).lastTotal)
end

local function CurrentLevelTime()
    if synchronized and levelAnchor and levelAnchorAt then
        return max(0, levelAnchor + (GetTime() - levelAnchorAt))
    end
    return 0
end

local function FormatTime(seconds, signed)
    seconds = tonumber(seconds) or 0
    local prefix = ""
    if signed then
        if seconds < 0 then prefix = "-"; seconds = -seconds
        elseif seconds > 0 then prefix = "+" end
    end
    seconds = floor(seconds + 0.0001)
    local days = floor(seconds / 86400)
    local hours = floor((seconds % 86400) / 3600)
    local minutes = floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if Config().showDays and days > 0 then
        return format("%s%d:%02d:%02d:%02d", prefix, days, hours, minutes, secs)
    end
    hours = hours + days * 24
    if hours > 0 then return format("%s%d:%02d:%02d", prefix, hours, minutes, secs) end
    return format("%s%d:%02d", prefix, minutes, secs)
end

local function MoverHidden()
    local movers = ns.DB().movers
    local elements = type(movers) == "table" and movers.elements
    local entry = type(elements) == "table" and elements.SpeedrunSplits
    return type(entry) == "table" and entry.hidden == true
end

local function DisplayEnabled()
    return Enabled() and ns.MoversEnabled() and not MoverHidden()
end

local function StyleDisplay()
    if not display then return end
    local size = Config().fontSize or 12
    local styleKey = table.concat({
        tostring(size), tostring(Config().scale or 1),
        tostring(Config().font), tostring(Config().textStyle),
    }, ":")
    if display._tfStyleKey == styleKey then return end
    display._tfStyleKey = styleKey
    ns:StyleFont(display.labels, nil, size, "speedrunSplits")
    ns:StyleFont(display.deltas, nil, size, "speedrunSplits")
    ns:StyleFont(display.times, nil, size, "speedrunSplits")
    ns:StyleFont(display.timer, nil, size, "speedrunSplits")
    if display.partialToggle and display.partialToggle.GetFontString then
        ns:StyleFont(display.partialToggle:GetFontString(), nil, max(8, size - 1), "speedrunSplits")
    end
    display:SetScale(Config().scale or 1)
end

local function EnsureDisplay()
    if display then return display end
    display = CreateFrame("Frame", "TurboFaceSpeedrunSplits", UIParent)
    display:SetPoint(FALLBACK_POINT[1], FALLBACK_POINT[2], FALLBACK_POINT[3], FALLBACK_POINT[4], FALLBACK_POINT[5])
    display:SetSize(DISPLAY_WIDTH, 160)
    display:SetFrameStrata("LOW")
    display:EnableMouse(false)

    display.labels = display:CreateFontString(nil, "OVERLAY")
    display.labels:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 0)
    display.labels:SetWidth(72); display.labels:SetJustifyH("LEFT"); display.labels:SetJustifyV("TOP")
    display.deltas = display:CreateFontString(nil, "OVERLAY")
    display.deltas:SetPoint("TOPLEFT", display, "TOPLEFT", 76, 0)
    display.deltas:SetWidth(72); display.deltas:SetJustifyH("RIGHT"); display.deltas:SetJustifyV("TOP")
    display.times = display:CreateFontString(nil, "OVERLAY")
    display.times:SetPoint("TOPLEFT", display, "TOPLEFT", 154, 0)
    display.times:SetWidth(96); display.times:SetJustifyH("RIGHT"); display.times:SetJustifyV("TOP")
    display.timer = display:CreateFontString(nil, "OVERLAY")
    display.timer:SetJustifyH("LEFT"); display.timer:SetTextColor(1, 1, 1)

    display.partialToggle = CreateFrame("Button", nil, display, "UIPanelButtonTemplate")
    display.partialToggle:SetSize(150, 22)
    display.partialToggle:SetScript("OnClick", function()
        local cfg = Config()
        cfg.showPartials = not cfg.showPartials
        if ns.PlayUISound then ns:PlayUISound("option") end
        Splits:UpdateDisplay()
    end)
    display:SetScript("OnShow", function() ns.Cadence:Add(Splits, 1.0, Splits.Tick) end)
    display:SetScript("OnHide", function() ns.Cadence:Remove(Splits) end)
    StyleDisplay()
    if display:IsShown() then ns.Cadence:Add(Splits, 1.0, Splits.Tick) end
    return display
end

local function ComparisonColor(diff, gold)
    if not Config().colorComparisons then return "|cffffffff" end
    if gold then return "|cffffff00" end
    if diff and diff < 0 then return "|cff00aa00" end
    if diff and diff > 0 then return "|cffff4040" end
    return "|cffffffff"
end

local function RowOrdinals(current, count)
    local rows, cfg = {}, Config()
    if cfg.showPartials then
        local finish = current + (cfg.showNext and 1 or 0)
        -- Level 1 is retained internally as the zero-time run anchor, but a
        -- permanent visible "Level 1  0:00" row carries no split information.
        for ordinal = max(11, finish - count + 1), finish do rows[#rows + 1] = ordinal end
    else
        local finish = floor(current / 10) + (cfg.showNext and 1 or 0)
        for level = max(2, finish - count + 1), finish do rows[#rows + 1] = level * 10 end
    end
    return rows
end

function Splits:UpdateDisplay()
    if not DisplayEnabled() then if display then display:Hide() end; return end
    local frame, cfg = EnsureDisplay(), Config()
    local run, profile = EnsureRun(false)
    local current, total = CurrentOrdinal(), CurrentTotalTime() or 0
    local nextOrdinal = cfg.showPartials and (current + 1) or ((floor(current / 10) + 1) * 10)
    local rowCount = min(40, max(3, floor(tonumber(cfg.visibleRows) or 12)))
    local rows = RowOrdinals(current, rowCount)
    local labels = { "|cffffd100Split|r" }
    local deltas = { "|cffffd100Delta|r" }
    local times = { "|cffffd100Time|r" }

    for _, ordinal in ipairs(rows) do
        labels[#labels + 1] = SplitLabel(ordinal)
        local actual, reference = run.times[ordinal], run.referencePB[ordinal]
        local shownTime, diff = actual or reference
        if actual and reference then diff = actual - reference
        elseif ordinal == nextOrdinal and reference and total > 0 then diff = total - reference end
        local previous = run.times[ordinal - 1]
        local segment = actual and previous and (actual - previous)
        local gold = segment and profile.gold[ordinal] and math.abs(segment - profile.gold[ordinal]) < 0.01
        local color = ComparisonColor(diff, gold)
        deltas[#deltas + 1] = cfg.showDelta and diff and (color .. FormatTime(diff, true) .. "|r") or ""
        times[#times + 1] = shownTime and (color .. FormatTime(shownTime) .. "|r") or ""
    end

    frame.labels:SetText(table.concat(labels, "\n"))
    frame.deltas:SetText(table.concat(deltas, "\n"))
    frame.times:SetText(table.concat(times, "\n"))
    local lastTime, lastOrdinal = nil, 0
    for ordinal, value in pairs(run.times) do
        local eligible = cfg.showPartials or ordinal % 10 == 0
        if eligible and ordinal <= current and ordinal >= lastOrdinal and type(value) == "number" then
            lastOrdinal, lastTime = ordinal, value
        end
    end
    -- Level 1's synthetic zero is not a useful segment anchor for an addon
    -- first enabled midway through a character. Until a real checkpoint in the
    -- current level exists, use Blizzard's authoritative time-this-level value.
    local currentLevelStart = floor(current / 10) * 10
    local segmentTime = lastTime and lastOrdinal >= currentLevelStart and max(0, total - lastTime)
        or CurrentLevelTime()
    local lineHeight = (cfg.fontSize or 12) + 2
    local footerGap = lineHeight * 0.5
    -- Anchor the footer to the rendered split text, with a small visual break
    -- equal to half a row. This stays consistent across font/UI-scale changes
    -- without returning to an estimated whole-table offset.
    frame.timer:ClearAllPoints()
    frame.timer:SetPoint("TOPLEFT", frame.labels, "BOTTOMLEFT", 0, -footerGap)
    frame.timer:SetText(format("Total %s   %s - %s", FormatTime(total), SplitLabel(nextOrdinal), FormatTime(segmentTime)))
    frame.partialToggle:ClearAllPoints()
    frame.partialToggle:SetPoint("TOPLEFT", frame.timer, "BOTTOMLEFT", 0, -5)
    frame.partialToggle:SetText(cfg.showPartials and "Hide Partial Levels" or "Show Partial Levels")

    local tableHeight = frame.labels.GetStringHeight and frame.labels:GetStringHeight()
        or ((#rows + 1) * lineHeight)
    local timerHeight = frame.timer.GetStringHeight and frame.timer:GetStringHeight()
        or lineHeight
    local newHeight = tableHeight + footerGap + timerHeight + 27
    local heightChanged = math.abs((frame:GetHeight() or 0) - newHeight) > 0.01
    frame:SetSize(DISPLAY_WIDTH, newHeight)
    if heightChanged and ns.Movers and ns.Movers.UpdateOverlay then
        ns.Movers:UpdateOverlay("SpeedrunSplits")
    end
    StyleDisplay(); frame:Show()
end

local function SaveRun(automatic)
    local run, profile = EnsureRun(false)
    local count = 0
    for ordinal, value in pairs(run.times) do
        if type(ordinal) == "number" and type(value) == "number" then
            profile.pb[ordinal] = value; count = count + 1
        end
    end
    if count > 0 then
        Chat((automatic and "New PB saved automatically" or "Current run saved as PB") .. " (" .. count .. " checkpoints).")
    else Chat("No checkpoints are available to save yet.") end
end

local function RecordCheckpoint(ordinal, timestamp)
    local run, profile = EnsureRun(false)
    if run.times[ordinal] ~= nil then return end
    run.times[ordinal] = timestamp

    -- Match the original SpeedrunSplits baseline behavior: the first observed
    -- time for a missing Race/Class checkpoint becomes its PB immediately.
    -- referencePB is a frozen copy from the start of this character's run, so
    -- these newly seeded entries are available to future characters without
    -- making the current run compare against itself.
    if profile.pb[ordinal] == nil then profile.pb[ordinal] = timestamp end

    local previous = run.times[ordinal - 1]
    if previous then
        local segment = max(0, timestamp - previous)
        if profile.gold[ordinal] == nil or segment < profile.gold[ordinal] then profile.gold[ordinal] = segment end
    end
    local autoLevel = min(60, max(2, floor(tonumber(Config().autoSaveLevel) or 60)))
    if ordinal == autoLevel * 10 then
        local reference = run.referencePB[ordinal]
        if reference == nil or timestamp < reference then SaveRun(true) end
    end
end

local function ProcessProgress(targetOrdinal)
    local run = EnsureRun(false)
    targetOrdinal = tonumber(targetOrdinal) or CurrentOrdinal()
    if not synchronized then pendingOrdinal = max(pendingOrdinal or 0, targetOrdinal); return end
    if run.observedOrdinal == nil then run.observedOrdinal = targetOrdinal; return end
    if targetOrdinal <= run.observedOrdinal then return end
    local timestamp = CurrentTotalTime()
    if not timestamp then return end
    for ordinal = run.observedOrdinal + 1, targetOrdinal do RecordCheckpoint(ordinal, timestamp) end
    run.observedOrdinal = targetOrdinal
end

function Splits.Tick() Splits:UpdateDisplay() end
function Splits:SaveCurrentRun() SaveRun(false); Splits:UpdateDisplay() end

function Splits:ResetCurrentRun()
    local run = EnsureRun(true)
    run.observedOrdinal = CurrentOrdinal()
    run.lastTotal = CurrentTotalTime() or run.lastTotal
    Chat("Current run checkpoints reset; the saved PB was kept.")
    self:UpdateDisplay()
end

function Splits:PrintCurrentRun()
    local run, ordinals = EnsureRun(false), {}
    for ordinal in pairs(run.times) do ordinals[#ordinals + 1] = ordinal end
    sort(ordinals); Chat("Current run:")
    for _, ordinal in ipairs(ordinals) do Chat(SplitLabel(ordinal) .. "  " .. FormatTime(run.times[ordinal])) end
end

function Splits:ImportLegacy()
    local _, raceFile = UnitRace("player")
    local _, classFile = UnitClass("player")
    local oldPB = type(SpeedrunSplitsPB) == "table" and SpeedrunSplitsPB[raceFile]
    oldPB = type(oldPB) == "table" and oldPB[classFile] or nil
    local oldGold = type(SpeedrunSplitsGold) == "table" and SpeedrunSplitsGold[raceFile]
    oldGold = type(oldGold) == "table" and oldGold[classFile] or nil
    if type(oldPB) ~= "table" then
        Chat("No loaded SpeedrunSplits data found. Enable the original addon once alongside TurboFace, then retry.")
        return false
    end
    local run, profile = EnsureRun(false)
    local count = 0
    for level, value in pairs(oldPB) do
        level, value = tonumber(level), tonumber(value)
        if level and value and level >= 1 then profile.pb[level * 10] = value; count = count + 1 end
    end
    if type(oldGold) == "table" then
        for level, value in pairs(oldGold) do
            level, value = tonumber(level), tonumber(value)
            if level and value and level >= 1 then profile.gold[level * 10] = value end
        end
    end
    run.referencePB = CopyMap(profile.pb)
    Chat("Imported " .. count .. " full-level PB checkpoints from SpeedrunSplits.")
    self:UpdateDisplay(); return true
end

local function OnEvent(_, event, arg1, arg2)
    if not Enabled() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        synchronized = false; totalAnchor, anchorAt, levelAnchor, levelAnchorAt = nil, nil, nil, nil
        EnsureRun(false, true); RequestTimePlayed()
    elseif event == "TIME_PLAYED_MSG" then
        totalAnchor, anchorAt = tonumber(arg1) or 0, GetTime()
        levelAnchor, levelAnchorAt = tonumber(arg2) or 0, anchorAt
        synchronized = true
        local run = EnsureRun(false); run.lastTotal = totalAnchor
        local target = max(CurrentOrdinal(), pendingOrdinal or 0)
        pendingOrdinal = nil; ProcessProgress(target)
    elseif event == "PLAYER_LEVEL_UP" then
        levelAnchor, levelAnchorAt = 0, GetTime()
        ProcessProgress((tonumber(arg1) or UnitLevel("player")) * 10)
    elseif event == "PLAYER_XP_UPDATE" then ProcessProgress(CurrentOrdinal())
    elseif event == "PLAYER_LOGOUT" then
        local run = EnsureRun(false); run.lastTotal = CurrentTotalTime() or run.lastTotal
    end
    Splits:UpdateDisplay()
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "TIME_PLAYED_MSG", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_LOGOUT" }
local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if active then for _, event in ipairs(EVENTS) do eventFrame:RegisterEvent(event) end end
end

function Splits:RegisterMover()
    if not display or not ns.Movers or not ns.Movers.RegisterElement then return end
    ns.Movers:RegisterElement("SpeedrunSplits", display, {
        label = "Speedrun Splits", overlayWidth = DISPLAY_WIDTH, overlayHeight = display:GetHeight(),
        fallbackPoint = FALLBACK_POINT, defaultPoint = FALLBACK_POINT, isAvailable = Enabled,
        children = { display.partialToggle },
        onApply = function() Splits:UpdateDisplay() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("SpeedrunSplits") end
end

function Splits:Refresh()
    if not initialized then if Enabled() then self:Init() end; return end
    SetEvents(Enabled())
    if Enabled() then
        EnsureRun(false)
        if not synchronized then RequestTimePlayed() end
        if ns.MoversEnabled() then EnsureDisplay(); self:RegisterMover() end
    end
    self:UpdateDisplay()
end

function Splits:Init()
    if initialized then self:Refresh(); return end
    if not Enabled() then return end
    initialized = true; EnsureRun(false)
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
    SetEvents(true)
    if ns.MoversEnabled() then EnsureDisplay(); self:RegisterMover() end
    synchronized = false; RequestTimePlayed(); self:UpdateDisplay()
end

SLASH_TURBOFACESPLITS1 = "/tfsplits"
SlashCmdList.TURBOFACESPLITS = function(message)
    local command = tostring(message or ""):lower():match("^%s*(%S*)")
    if command == "save" then Splits:SaveCurrentRun()
    elseif command == "reset" then Splits:ResetCurrentRun()
    elseif command == "print" then Splits:PrintCurrentRun()
    elseif command == "import" then Splits:ImportLegacy()
    else Chat("Commands: /tfsplits save, reset, print, import") end
end

ns.RegisterCPUProfileTarget("Utility/SpeedrunSplits:Event", OnEvent)
ns.RegisterCPUProfileTarget("Utility/SpeedrunSplits:Tick", Splits.Tick, false)
