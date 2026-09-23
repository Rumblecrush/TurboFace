local _, ns = ...

-- API boundary: all changed-in-retail APIs resolve through Compat.lua
local GetQuestLogTitle = ns.API.GetQuestLogTitle
local GetNumQuestLogEntries = ns.API.GetNumQuestLogEntries
local GetQuestLogSelection = ns.API.GetQuestLogSelection
local SelectQuestLogEntry = ns.API.SelectQuestLogEntry
local GetQuestLogRewardXP = ns.API.GetQuestLogRewardXP
local HaveQuestRewardData = ns.API.HaveQuestRewardData
local RequestLoadQuestByID = ns.API.RequestLoadQuestByID
local IsQuestComplete = ns.API.IsQuestComplete
local QuestReadyForTurnIn = ns.API.QuestReadyForTurnIn

-- =============================================================================
-- TurboFace Experience Bar
-- TurboFace XP/session bar reconstructed from the project owner's own prior
-- configuration for WoW Classic Era 1.15.x.
-- Tracks current XP, quest XP, rested XP, XP/hour, time-to-level, /played time,
-- and renders complete/incomplete quest + rested overlays on a movable bar.
-- =============================================================================

local XP = {}
ns.XP = XP

local _G = _G
local UIParent = UIParent
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax
local UnitLevel = UnitLevel
local GetXPExhaustion = GetXPExhaustion
local RequestTimePlayed = RequestTimePlayed
local IsXPUserDisabled = IsXPUserDisabled or function() return false end
local GetTime = GetTime
local Time = time
local math_floor = math.floor
local math_ceil = math.ceil
local math_min = math.min
local math_max = math.max
local string_format = string.format
local tostring = tostring
local tonumber = tonumber
local type = type
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local unpack = unpack

local defaults = ns.defaults.experienceBar

local frame, eventFrame, timePlayedTimer
local initialized = false
local hideHooksInstalled = false
local blizzardXPBarSuppressed = false
local questUpdateQueued = false
local questRewardCache = {}
local requestingTimePlayed = false
local appearanceKey

local blizzardXPFrames = {
    "StatusTrackingBarManager",
    "MainStatusTrackingBarContainer",
    "MainMenuExpBar",
    "ExhaustionTick",
}

local MergeDefaults = ns.MergeDefaults
local After = ns.After

local function DB()
    if not TurboFaceDB then TurboFaceDB = {} end
    if type(TurboFaceDB.experienceBar) ~= "table" then TurboFaceDB.experienceBar = {} end
    MergeDefaults(TurboFaceDB.experienceBar, defaults)
    return TurboFaceDB.experienceBar
end

local function SessionDB()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.experienceBarSession) ~= "table" then
        TurboFaceCharDB.experienceBarSession = {}
    end
    local s = TurboFaceCharDB.experienceBarSession
    s.gainedXP = s.gainedXP or 0
    s.lastXP = s.lastXP or (UnitXP and UnitXP("player")) or 0
    s.maxXP = s.maxXP or (UnitXPMax and UnitXPMax("player")) or 0
    s.startTime = s.startTime or (Time and Time()) or 0
    s.realTotalTime = s.realTotalTime or 0
    s.realLevelTime = s.realLevelTime or 0
    s.lastTimePlayedRequest = s.lastTimePlayedRequest or 0
    return s
end

local function Enabled(db)
    db = db or DB()
    local on = db.enabled ~= false
    return ns.MoverDependentEnabled(on)
end

local function Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math_floor((tonumber(num) or 0) * mult + 0.5) / mult
end

local function Trim(s)
    s = tostring(s or "")
    if strtrim then return strtrim(s, " :/-|") end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^[ :/%-%|]+", ""):gsub("[ :/%-%|]+$", "")
    return s
end

local function FormatLarge(n)
    n = tonumber(n) or 0
    if FormatLargeNumber then return FormatLargeNumber(n) end
    local s = tostring(math_floor(n + 0.5))
    local left, num, right = s:match("^([^%d]*%d)(%d*)(.-)$")
    if not left then return s end
    return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function FormatTimeLeft(seconds, format)
    seconds = tonumber(seconds) or 0
    if seconds <= 59 then return "< 1m" end

    local d, h, m, s
    if ChatFrame_TimeBreakDown then
        d, h, m, s = ChatFrame_TimeBreakDown(seconds)
    else
        d = math_floor(seconds / 86400)
        seconds = seconds - d * 86400
        h = math_floor(seconds / 3600)
        seconds = seconds - h * 3600
        m = math_floor(seconds / 60)
        s = seconds - m * 60
    end

    local t = format or "%dd %hh %mm"
    local function pad(v) return v < 10 and ("0" .. v) or tostring(v) end
    local subs = {
        ["%%D([Dd]?)"] = d > 0 and (pad(d) .. "%1") or "",
        ["%%d([Dd]?)"] = d > 0 and (d .. "%1") or "",
        ["%%H([Hh]?)"] = (d > 0 or h > 0) and (pad(h) .. "%1") or "",
        ["%%h([Hh]?)"] = (d > 0 or h > 0) and (h .. "%1") or "",
        ["%%M([Mm]?)"] = pad(m) .. "%1",
        ["%%m([Mm]?)"] = m .. "%1",
        ["%%S([Ss]?)"] = pad(s) .. "%1",
        ["%%s([Ss]?)"] = s .. "%1",
    }
    for k, v in pairs(subs) do t = t:gsub(k, v) end
    return Trim(t:gsub("^%s*0*", ""):gsub("^%s*[DdHhMm]", ""))
end

local function GetMaxLevel(expansionLevel)
    if GetMaxPlayerLevel and GetMaxLevelForExpansionLevel then
        local exp = expansionLevel or (GetExpansionLevel and GetExpansionLevel()) or 0
        return math_min(GetMaxPlayerLevel(), GetMaxLevelForExpansionLevel(exp))
    end
    if GetMaxPlayerLevel then return GetMaxPlayerLevel() end
    return 60
end

local function PlayerIsMaxLevel()
    return (UnitLevel and UnitLevel("player") or 1) >= GetMaxLevel()
end

local function Color(dbColor, r, g, b)
    if ns.Color then return ns:Color(dbColor, r, g, b) end
    if type(dbColor) == "table" then return dbColor.r or dbColor[1] or r, dbColor.g or dbColor[2] or g, dbColor.b or dbColor[3] or b end
    return r, g, b
end

local function ResolveTexture(name)
    name = name or defaults.texture

    -- SharedMedia overrides ns.GetTexture as a dot function, while Core/Config.lua
    -- originally defines it as a colon method. Avoid the dot/colon ambiguity here
    -- so Experience texture dropdown changes resolve to the selected texture.
    if ns.LSM and ns.LSM.Fetch then
        local ok, path = pcall(ns.LSM.Fetch, ns.LSM, "statusbar", name)
        if ok and path then return path end
    end

    if type(ns.Textures) == "table" then
        for _, tex in ipairs(ns.Textures) do
            if tex.name == name and tex.path then return tex.path end
        end
    end

    return "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
end

local function FrameDimension(value, fallback)
    value = tonumber(value) or 0
    if value > 0 then return value end
    return fallback
end

local function SafeSetColorTexture(tex, r, g, b, a)
    if not tex then return end
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a or 1)
    else
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(r, g, b, a or 1)
    end
end

local function ClearTimePlayedRequest()
    if timePlayedTimer then
        timePlayedTimer:Cancel()
        timePlayedTimer = nil
    end
    requestingTimePlayed = false
end

local function RequestPlayedTime()
    if requestingTimePlayed then return end
    ClearTimePlayedRequest()
    requestingTimePlayed = true
    if C_Timer and C_Timer.NewTimer then
        timePlayedTimer = C_Timer.NewTimer(0.5, function()
            if RequestTimePlayed then RequestTimePlayed() end
        end)
    elseif RequestTimePlayed then
        RequestTimePlayed()
    end
end

local function CurrentSession()
    return SessionDB()
end

function XP:GetSessionSnapshot()
    local out = {}
    for key, value in pairs(CurrentSession()) do out[key] = value end
    return out
end

function XP:ImportSession(imported)
    if type(imported) ~= "table" then return false end
    local session = CurrentSession()
    wipe(session)
    for key, value in pairs(imported) do session[key] = value end
    SessionDB() -- restore any omitted live fields with safe current-character values
    requestingTimePlayed = false
    ClearTimePlayedRequest()
    if self.Update then self:Update(true) end
    return true
end

local function ResetSession()
    local s = CurrentSession()
    s.gainedXP = 0
    s.lastXP = (UnitXP and UnitXP("player")) or 0
    s.maxXP = (UnitXPMax and UnitXPMax("player")) or 0
    s.startTime = (Time and Time()) or 0
end

local function GetQuestCount()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return C_QuestLog.GetNumQuestLogEntries() end
    if GetNumQuestLogEntries then return GetNumQuestLogEntries() end
    return 0
end

local function GetQuestID(index)
    if C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then return C_QuestLog.GetQuestIDForLogIndex(index) end
    if GetQuestLogTitle then return select(8, GetQuestLogTitle(index)) end
    return 0
end

local function IsQuestDone(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(questID) end
    if IsQuestComplete then return IsQuestComplete(questID) end
    return false
end

local function IsQuestReady(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(questID) end
    if QuestReadyForTurnIn then return QuestReadyForTurnIn(questID) end
    return false
end

local modernQuestRewardAPI = HaveQuestRewardData ~= nil

local function QuestLogIsOpen()
    if modernQuestRewardAPI then return false end
    local questLog = _G.QuestLogFrame
    if questLog and questLog.IsShown and questLog:IsShown() then return true end
    local questMap = _G.QuestMapFrame
    if questMap and questMap.IsShown and questMap:IsShown() then return true end
    return false
end

local function EnsureQuestLogHideHooks()
    if modernQuestRewardAPI then return end
    local frames = { _G.QuestLogFrame, _G.QuestMapFrame }
    for i = 1, #frames do
        local f = frames[i]
        if f and f.HookScript and not f._tfXPQuestHideHooked then
            f._tfXPQuestHideHooked = true
            f:HookScript("OnHide", function()
                if XP._questScanDeferred then
                    XP._questScanDeferred = nil
                    XP:QueueQuestXPUpdate()
                end
            end)
        end
    end
end

local function GetQuestRewardXPForEntry(index, questID)
    if not questID or questID <= 0 then return 0, true, false end
    local cached = questRewardCache[questID]
    if cached ~= nil then return cached, true, false end

    if modernQuestRewardAPI then
        -- Modern clients load quest reward data asynchronously. Until readiness
        -- is true, zero means "not loaded" rather than "no XP reward".
        if not HaveQuestRewardData(questID) then
            if RequestLoadQuestByID then pcall(RequestLoadQuestByID, questID) end
            return 0, false, false
        end
        local rewardXP = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
        rewardXP = tonumber(rewardXP) or 0
        questRewardCache[questID] = rewardXP
        return rewardXP, true, false
    end

    if SelectQuestLogEntry then SelectQuestLogEntry(index) end
    local rewardXP = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    rewardXP = tonumber(rewardXP) or 0
    -- Legacy clients can report zero transiently, so only cache positive values.
    if rewardXP > 0 then questRewardCache[questID] = rewardXP end
    return rewardXP, true, SelectQuestLogEntry ~= nil
end

function XP:UpdateQuestXP()
    EnsureQuestLogHideHooks()
    if QuestLogIsOpen() then
        -- Legacy reward lookup selects quest-log entries. Avoid mutating the
        -- player's visible selection while Blizzard's quest UI is open.
        self._questScanDeferred = true
        return false
    end

    local questXP, completeXP, incompleteXP = 0, 0, 0
    local selected = (not modernQuestRewardAPI and GetQuestLogSelection and GetQuestLogSelection()) or 0
    local selectionChanged = false
    local rewardDataPending = false
    local numQ = GetQuestCount()

    for i = 1, numQ do
        local questID = GetQuestID(i) or 0
        if questID > 0 then
            local rewardXP, rewardReady, selectedEntry = GetQuestRewardXPForEntry(i, questID)
            if selectedEntry then selectionChanged = true end
            if not rewardReady then
                rewardDataPending = true
            elseif rewardXP > 0 then
                questXP = questXP + rewardXP
                if IsQuestDone(questID) or IsQuestReady(questID) then
                    completeXP = completeXP + rewardXP
                else
                    incompleteXP = incompleteXP + rewardXP
                end
            end
        end
    end

    -- Do not replace a complete snapshot with a partial modern async scan.
    if rewardDataPending then
        self._questRewardDataPending = true
        return false
    end

    self._questRewardDataPending = nil
    self.questXP = questXP
    self.completeXP = completeXP
    self.incompleteXP = incompleteXP

    if selectionChanged and SelectQuestLogEntry then
        pcall(SelectQuestLogEntry, selected or 0)
    end
    return true
end

function XP:QueueQuestXPUpdate()
    if questUpdateQueued then return end
    questUpdateQueued = true
    local function Run()
        questUpdateQueued = false
        XP:UpdateQuestXP()
        XP:Update()
    end
    After(0.2, Run)
end

local function HideBlizzardXPBar()
    local db = DB()
    local hide = Enabled(db) and db.hideBlizzardXPBar == true
    if hide then
        blizzardXPBarSuppressed = true
        for _, name in ipairs(blizzardXPFrames) do
            local f = _G[name]
            if f and f.Hide then
                if f.Hide then f:Hide() end
            end
        end
    elseif blizzardXPBarSuppressed then
        -- Only undo state TurboFace actually imposed in this session. Starting
        -- with the XP module disabled must not force-show Blizzard frames.
        blizzardXPBarSuppressed = false
        for _, name in ipairs(blizzardXPFrames) do
            local f = _G[name]
            if f and (name == "StatusTrackingBarManager" or name == "MainStatusTrackingBarContainer" or name == "MainMenuExpBar") then
                if f.Show then f:Show() end
            end
        end
    end
end

local function InstallBlizzardHideHooks()
    if hideHooksInstalled then return end
    hideHooksInstalled = true
    if not hooksecurefunc then return end
    for _, name in ipairs(blizzardXPFrames) do
        local f = _G[name]
        if f and f.Show then
            hooksecurefunc(f, "Show", function(self)
                local db = DB()
                if Enabled(db) and db.hideBlizzardXPBar == true then self:Hide() end
            end)
        end
    end
end

local function ExperienceTick()
    XP:Update()
end

local function EnsureFrame()
    if frame then return frame end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "TurboFaceExperienceBar", UIParent, template)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0)

    frame.bg = frame.bar:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame.bar)
    SafeSetColorTexture(frame.bg, 0, 0, 0, 0.55)

    frame.complete = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.incomplete = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.rested = frame.bar:CreateTexture(nil, "ARTWORK")

    frame.levelText = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.levelText:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
    frame.levelText:SetJustifyH("LEFT")

    frame.xpText = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.xpText:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
    frame.xpText:SetJustifyH("CENTER")

    frame.percentText = frame.bar:CreateFontString(nil, "OVERLAY")
    frame.percentText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
    frame.percentText:SetJustifyH("RIGHT")

    frame.lines = {}
    for i = 1, 4 do
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("CENTER")
        fs:SetPoint("TOP", i == 1 and frame.bar or frame.lines[i - 1], i == 1 and "BOTTOM" or "BOTTOM", 0, i == 1 and -3 or -1)
        fs:SetTextColor(0.86, 0.86, 0.86)
        frame.lines[i] = fs
    end

    frame:SetScript("OnSizeChanged", function() XP:UpdateSegments() end)
    frame:SetScript("OnShow", function(self) ns.Cadence:Add(self, 1.0, ExperienceTick) end)
    frame:SetScript("OnHide", function(self) ns.Cadence:Remove(self) end)
    if frame:IsShown() then ns.Cadence:Add(frame, 1.0, ExperienceTick) end

    return frame
end

local function Segment(texture, total, startValue, widthValue, height)
    total = tonumber(total) or 0
    if not texture then return end
    if total <= 0 then texture:Hide(); return end

    local bar = frame and frame.bar
    local barWidth = bar and bar:GetWidth() or 0
    if barWidth <= 1 then barWidth = (DB().width or defaults.width) - 2 end

    local start = math_min(total, math_max(0, tonumber(startValue) or 0))
    local finish = math_min(total, math_max(start, start + (tonumber(widthValue) or 0)))
    local w = finish - start
    if w <= 0 then texture:Hide(); return end

    texture:ClearAllPoints()
    texture:SetPoint("LEFT", bar, "LEFT", (start / total) * barWidth, 0)
    texture:SetSize(math_max(1, (w / total) * barWidth), height or (bar and bar:GetHeight()) or defaults.height)
    texture:Show()
end

function XP:UpdateSegments(state)
    if not frame or not frame.bar then return end
    local db = DB()
    state = state or self.state or {}
    local currentXP = state.currentXP or 0
    local totalXP = state.totalXP or 0
    local completeXP = state.completeXP or 0
    local incompleteXP = db.showIncompleteQuestBar and (state.incompleteXP or 0) or 0
    local restedXP = state.restedXP or 0
    local h = frame.bar:GetHeight() or db.height or defaults.height

    Segment(frame.complete, totalXP, currentXP, completeXP, h)
    Segment(frame.incomplete, totalXP, currentXP + completeXP, incompleteXP, h)
    Segment(frame.rested, totalXP, currentXP + completeXP + incompleteXP, restedXP, h)
end

local function VisibleLineTexts(state)
    local db = DB()
    local out = {}

    if not state.isMaxLevel and db.showXPPerHourText then
        local hourlyXP = state.hourlyXP or 0
        local hourlyText
        if hourlyXP > 10000 then hourlyText = string_format("%sK", Round(hourlyXP / 1000, 1))
        else hourlyText = FormatLarge(hourlyXP) end
        out[#out + 1] = string_format("Level in: %s (%s XP/Hour)", state.timeToLevelText or "--", hourlyText)
    end

    if not state.isMaxLevel and db.showQuestRestedText then
        out[#out + 1] = string_format("C: |cFFFF9700%s%%|r - R: |cFF4F90FF%s%%|r", Round(state.percentcomplete or 0, 1), Round(state.percentrested or 0, 1))
    end

    if db.showLevelTimeText then
        if state.isMaxLevel then out[#out + 1] = "Time played: " .. (state.totalTimeText or "")
        else out[#out + 1] = "Time this level: " .. (state.levelTimeText or "") end
    end

    if db.showSessionTimeText then
        out[#out + 1] = "Time this session: " .. (state.sessionTimeText or "")
    end

    return out
end


local function ColorKey(c)
    if type(c) ~= "table" then return tostring(c or "") end
    return tostring(c.r or c[1] or "") .. ":" .. tostring(c.g or c[2] or "") .. ":" .. tostring(c.b or c[3] or "") .. ":" .. tostring(c.a or c[4] or "")
end

local function AppearanceKey(db)
    return table.concat({
        tostring(db.enabled ~= false),
        tostring(db.width or defaults.width),
        tostring(db.height or defaults.height),
        tostring(db.fontSize or defaults.fontSize),
        tostring(db.scale or defaults.scale),
        tostring(db.texture or defaults.texture),
        tostring(db.textBlockAbove == true),
        tostring(db.showXPPerHourText == true),
        tostring(db.showQuestRestedText == true),
        tostring(db.showLevelTimeText == true),
        tostring(db.showSessionTimeText == true),
        ColorKey(db.colorXP),
        ColorKey(db.colorComplete),
        ColorKey(db.colorIncomplete),
        ColorKey(db.colorRested),
    }, "|")
end

local function ApplyAppearance(force)
    local db = DB()
    local f = EnsureFrame()
    local key = AppearanceKey(db)
    if not force and appearanceKey == key then return end
    local width = math_max(120, tonumber(db.width) or defaults.width)
    local barHeight = math_max(6, tonumber(db.height) or defaults.height)
    local fontSize = math_max(6, tonumber(db.fontSize) or defaults.fontSize)
    local scale = math_max(0.35, math_min(3, tonumber(db.scale) or 1))
    local lines = 0
    if db.enabled ~= false then
        if db.showXPPerHourText then lines = lines + 1 end
        if db.showQuestRestedText then lines = lines + 1 end
        if db.showLevelTimeText then lines = lines + 1 end
        if db.showSessionTimeText then lines = lines + 1 end
    end
    local lineHeight = math_max(6, fontSize - 1) + 3
    local gap = lines > 0 and 5 or 0
    local totalHeight = barHeight + math_max(0, lines) * lineHeight + gap

    -- Keep the XP object itself transparent: no outer grey border/backdrop and
    -- no dark panel behind the out-of-bar text block. The only background kept
    -- is the actual bar fill behind current XP.
    if f.SetBackdrop then f:SetBackdrop(nil) end
    f:SetScale(scale)
    f:SetSize(width, totalHeight)

    f.bar:ClearAllPoints()
    if db.textBlockAbove == true then
        f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    else
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    end
    f.bar:SetHeight(barHeight)

    for i, fs in ipairs(f.lines) do
        fs:ClearAllPoints()
        if db.textBlockAbove == true then
            if i == 1 then
                fs:SetPoint("BOTTOM", f.bar, "TOP", 0, 3)
            else
                fs:SetPoint("BOTTOM", f.lines[i - 1], "TOP", 0, 1)
            end
        else
            if i == 1 then
                fs:SetPoint("TOP", f.bar, "BOTTOM", 0, -3)
            else
                fs:SetPoint("TOP", f.lines[i - 1], "BOTTOM", 0, -1)
            end
        end
    end

    local texPath = ResolveTexture(db.texture)
    f.bar:SetStatusBarTexture(texPath)
    f.complete:SetTexture(texPath)
    f.incomplete:SetTexture(texPath)
    f.rested:SetTexture(texPath)

    local xr, xg, xb = Color(db.colorXP, defaults.colorXP.r, defaults.colorXP.g, defaults.colorXP.b)
    local cr, cg, cb = Color(db.colorComplete, defaults.colorComplete.r, defaults.colorComplete.g, defaults.colorComplete.b)
    local ir, ig, ib = Color(db.colorIncomplete, defaults.colorIncomplete.r, defaults.colorIncomplete.g, defaults.colorIncomplete.b)
    local rr, rg, rb = Color(db.colorRested, defaults.colorRested.r, defaults.colorRested.g, defaults.colorRested.b)
    f.bar:SetStatusBarColor(xr, xg, xb, 1)
    f.complete:SetVertexColor(cr, cg, cb, 0.88)
    f.incomplete:SetVertexColor(ir, ig, ib, 0.58)
    f.rested:SetVertexColor(rr, rg, rb, 0.55)

    if ns.StyleFont then
        ns:StyleFont(f.levelText, nil, fontSize, "experienceBar")
        ns:StyleFont(f.xpText, nil, fontSize, "experienceBar")
        ns:StyleFont(f.percentText, nil, fontSize, "experienceBar")
        for _, fs in ipairs(f.lines) do ns:StyleFont(fs, nil, math_max(6, fontSize - 1), "experienceBar") end
    end

    f.levelText:SetTextColor(1, 0.82, 0)
    f.xpText:SetTextColor(1, 1, 1)
    f.percentText:SetTextColor(1, 1, 1)
    appearanceKey = key
end

function XP:BuildState()
    local db = DB()
    local session = CurrentSession()
    local currentTime = (Time and Time()) or 0
    local level = (UnitLevel and UnitLevel("player")) or 1
    local currentXP = (UnitXP and UnitXP("player")) or 0
    local totalXP = (UnitXPMax and UnitXPMax("player")) or 0
    local remainingXP = math_max(0, totalXP - currentXP)
    local restedXP = (GetXPExhaustion and GetXPExhaustion()) or 0
    local totalTime = session.realTotalTime or 0
    local levelTime = session.realLevelTime or 0
    local sessionTime = 0
    local hourlyXP = 0
    local timeToLevel = 0
    local isMax = PlayerIsMaxLevel()

    if db.showLevelTimeText and (session.lastTimePlayedRequest or 0) > 0 then
        totalTime = currentTime - session.lastTimePlayedRequest + (session.realTotalTime or 0)
        levelTime = currentTime - session.lastTimePlayedRequest + (session.realLevelTime or 0)
    end

    if db.showSessionTimeText or db.showXPPerHourText then
        if (session.startTime or 0) > 0 then
            sessionTime = currentTime - session.startTime
            local coeff = sessionTime / 3600
            if coeff > 0 and (session.gainedXP or 0) > 0 then
                hourlyXP = math_ceil((session.gainedXP or 0) / coeff)
                if hourlyXP > 0 then timeToLevel = math_ceil(remainingXP / hourlyXP * 3600) end
            end
        end
    end

    local completeXP = self.completeXP or 0
    local incompleteXP = self.incompleteXP or 0
    local questXP = self.questXP or 0

    return {
        level = level,
        currentXP = currentXP,
        totalXP = totalXP,
        remainingXP = remainingXP,
        restedXP = restedXP,
        questXP = questXP,
        completeXP = completeXP,
        incompleteXP = incompleteXP,
        hourlyXP = hourlyXP,
        timeToLevel = timeToLevel,
        timeToLevelText = timeToLevel > 0 and FormatTimeLeft(timeToLevel) or "--",
        totalTime = totalTime,
        totalTimeText = FormatTimeLeft(totalTime),
        levelTime = levelTime,
        levelTimeText = FormatTimeLeft(levelTime),
        sessionTime = sessionTime,
        sessionTimeText = FormatTimeLeft(sessionTime),
        percentXP = totalXP > 0 and ((currentXP / totalXP) * 100) or 0,
        percentremaining = totalXP > 0 and ((remainingXP / totalXP) * 100) or 0,
        percentrested = totalXP > 0 and ((restedXP / totalXP) * 100) or 0,
        percentquest = totalXP > 0 and ((questXP / totalXP) * 100) or 0,
        percentcomplete = totalXP > 0 and ((completeXP / totalXP) * 100) or 0,
        percentincomplete = totalXP > 0 and ((incompleteXP / totalXP) * 100) or 0,
        totalpercentcomplete = totalXP > 0 and (((completeXP + currentXP) / totalXP) * 100) or 0,
        isMaxLevel = isMax,
    }
end

function XP:Update(forceAppearance)
    local db = DB()
    if not Enabled(db) then
        if frame then frame:Hide() end
        HideBlizzardXPBar() -- disabled/dependency-off state restores Blizzard's bar
        return
    end
    HideBlizzardXPBar()
    ApplyAppearance(forceAppearance == true)

    local show = not IsXPUserDisabled() and (db.showAtMaxLevel == true or not PlayerIsMaxLevel())
    if not show then
        if frame then frame:Hide() end
        return
    end

    local f = EnsureFrame()
    local state = self:BuildState()
    self.state = state

    if state.isMaxLevel then
        f.bar:SetMinMaxValues(0, 1)
        f.bar:SetValue(1)
        f.levelText:SetText("Level " .. tostring(state.level))
        f.xpText:SetText("Max Level")
        f.percentText:SetText("100%")
    else
        f.bar:SetMinMaxValues(0, math_max(1, state.totalXP or 1))
        f.bar:SetValue(state.currentXP or 0)
        f.levelText:SetText("Level " .. tostring(state.level))
        f.xpText:SetText(string_format("%s / %s -- %s", FormatLarge(state.currentXP), FormatLarge(state.totalXP), FormatLarge(state.remainingXP)))
        if (state.percentcomplete or 0) > 0 then
            f.percentText:SetText(string_format("%s%% (%s%%)", Round(state.percentXP, 1), Round(state.totalpercentcomplete, 1)))
        else
            f.percentText:SetText(string_format("%s%%", Round(state.percentXP, 1)))
        end
    end

    if db.showInsideLevelText == false then f.levelText:Hide() else f.levelText:Show() end
    if db.showInsidePercentText == false then f.percentText:Hide() else f.percentText:Show() end

    local lineTexts = VisibleLineTexts(state)
    for i, fs in ipairs(f.lines) do
        local text = lineTexts[i]
        if text and text ~= "" then fs:SetText(text); fs:Show()
        else fs:SetText(""); fs:Hide() end
    end

    self:UpdateSegments(state)
    f:Show()
end

function XP:RegisterMover()
    if not Enabled() then return end
    local f = EnsureFrame()
    if ns.Movers and ns.Movers.RegisterElement then
        ns.Movers:RegisterElement("ExperienceBar", f, {
            label = "Luxthos-like XP",
            overlayWidth = FrameDimension(f:GetWidth(), defaults.width),
            overlayHeight = FrameDimension(f:GetHeight(), 70),
            fallbackPoint = { "BOTTOM", UIParent, "BOTTOM", 0, 190 },
            defaultPoint = { "BOTTOM", UIParent, "BOTTOM", 0, 190 },
        })
        if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("ExperienceBar") end
    end
end

function XP:Refresh()
    local db = DB()
    if not Enabled(db) then
        if eventFrame then eventFrame:UnregisterAllEvents() end
        ClearTimePlayedRequest()
        if frame then frame:Hide() end
        HideBlizzardXPBar()
        return
    end
    if not initialized then
        self:Init()
        return
    end
    self:SetEvents(true)
    EnsureFrame()
    InstallBlizzardHideHooks()
    EnsureQuestLogHideHooks()
    HideBlizzardXPBar()
    self:UpdateQuestXP()
    self:Update(true)
    self:RegisterMover()
    if DB().showLevelTimeText and (CurrentSession().lastTimePlayedRequest or 0) <= 0 then RequestPlayedTime() end
end

local XP_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP",
    "UPDATE_EXHAUSTION",
    "ENABLE_XP_GAIN",
    "DISABLE_XP_GAIN",
    "TIME_PLAYED_MSG",
    "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED",
    "UPDATE_EXPANSION_LEVEL",
    "MAX_EXPANSION_LEVEL_UPDATED",
}
if modernQuestRewardAPI then
    XP_EVENTS[#XP_EVENTS + 1] = "QUEST_DATA_LOAD_RESULT"
    XP_EVENTS[#XP_EVENTS + 1] = "QUEST_REMOVED"
    XP_EVENTS[#XP_EVENTS + 1] = "QUEST_TURNED_IN"
end

function XP:SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    for _, event in ipairs(XP_EVENTS) do eventFrame:RegisterEvent(event) end
end

local function RunExperienceUpdateWithDiagnostics()
    if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
        ns.CPUProfiler:MeasureKillNoReturn("ExperienceBar:Update", XP.Update, XP)
    else
        XP:Update()
    end
end

function XP:Init()
    if initialized then
        self:SetEvents(Enabled())
        return
    end
    local db = DB()
    if not Enabled(db) then
        HideBlizzardXPBar()
        return
    end
    initialized = true
    EnsureFrame()
    InstallBlizzardHideHooks()
    EnsureQuestLogHideHooks()
    HideBlizzardXPBar()
    self:UpdateQuestXP()
    self:Update()
    self:RegisterMover()

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
        local db = DB()
        if not Enabled(db) then return end
        local s = CurrentSession()
        local currentXP = (UnitXP and UnitXP("player")) or 0
        local maxXP = (UnitXPMax and UnitXPMax("player")) or 0
        local currentTime = (Time and Time()) or 0

        if event == "PLAYER_ENTERING_WORLD" then
            if arg1 or (arg2 and db.resetSessionOnReload) then ResetSession() end
            if arg1 or arg2 then
                s.realTotalTime = 0
                s.realLevelTime = 0
                s.lastTimePlayedRequest = 0
                HideBlizzardXPBar()
            end
            if db.showLevelTimeText and (s.lastTimePlayedRequest or 0) <= 0 then RequestPlayedTime() end
        elseif event == "PLAYER_LEVEL_UP" then
            wipe(questRewardCache)
            s.realLevelTime = 0
            s.maxXP = maxXP
            s.lastXP = currentXP
            s.lastTimePlayedRequest = currentTime
        elseif event == "UPDATE_EXPANSION_LEVEL" or event == "MAX_EXPANSION_LEVEL_UPDATED" then
            if currentTime - (s.startTime or 0) >= (86400 * 3) then s.startTime = currentTime end
        elseif event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and arg1 == "player") then
            XP:QueueQuestXPUpdate()
        elseif event == "QUEST_DATA_LOAD_RESULT" then
            if arg2 then XP:QueueQuestXPUpdate() end
        elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            if arg1 then questRewardCache[arg1] = nil end
            XP:QueueQuestXPUpdate()
        elseif event == "TIME_PLAYED_MSG" and arg2 then
            s.realTotalTime = arg1 or 0
            s.realLevelTime = arg2 or 0
            s.lastTimePlayedRequest = currentTime
            ClearTimePlayedRequest()
        elseif event == "PLAYER_XP_UPDATE" then
            local gainedXP = currentXP - (s.lastXP or currentXP)
            if gainedXP < 0 then gainedXP = (s.maxXP or maxXP) - (s.lastXP or 0) + currentXP end
            if gainedXP > 0 then s.gainedXP = (s.gainedXP or 0) + gainedXP end
            s.lastXP = currentXP
            s.maxXP = maxXP
        end

        RunExperienceUpdateWithDiagnostics()
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("ExperienceBar") end
    end)
    self:SetEvents(true)
    if modernQuestRewardAPI then
        -- The initial scan can request reward data before the event frame exists.
        self:QueueQuestXPUpdate()
    end

    self:Update()
end

ns.RegisterCPUProfileTarget("Utility/ExperienceBar:Update", XP.Update)
ns.RegisterCPUProfileTarget("Utility/ExperienceBar:Tick", ExperienceTick, false)
