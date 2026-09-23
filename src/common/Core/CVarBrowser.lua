local addonName, ns = ...

-- =============================================================================
-- TurboFace CVar Browser — opt-in developer/debug utility
--
-- Commands:
--   /tf cvars
--   /tf cvars <search>
--   /tf debug cvars
--
-- Design goals:
--   * zero frame/event cost until the browser is opened
--   * enumerate the client registry on each open/explicit refresh
--   * no normal-play SavedVariables; optional export snapshots persist only on explicit Save
--   * no permanent SetCVar/ConsoleExec hooks
--   * expose enough metadata to make patch-day CVar archaeology practical
-- =============================================================================

local Browser = {}
ns.CVarBrowser = Browser

local GetAllCommands = ConsoleGetAllCommands or (C_Console and C_Console.GetAllCommands)
local GetInfo = C_CVar and C_CVar.GetCVarInfo
local ROW_HEIGHT = 22
local VISIBLE_ROWS = 18

local CATEGORY_NAMES = {
    [0] = "Debug",
    [1] = "Graphics",
    [2] = "Console",
    [3] = "Combat",
    [4] = "Game",
    [5] = "Default",
    [6] = "Net",
    [7] = "Sound",
    [8] = "GM",
    [9] = "None",
}

local frame, exportFrame
local exportPages = {}
local exportPageIndex = 1
local EXPORT_PAGE_MAX_CHARS = 30000
local allCVars = {}
local allByName = {}
local filteredCVars = {}
local selectedName

local function Trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

local function SafeCVarInfo(name)
    if not GetInfo or not name then return nil end
    local ok, value, defaultValue, account, character, locked, secure, readOnly = pcall(GetInfo, name)
    if not ok then return nil end
    return value, defaultValue, account, character, locked, secure, readOnly
end

local function CVarExists(name)
    if not name or name == "" then return false end
    return SafeCVarInfo(name) ~= nil
end

local function SafeValue(v)
    if v == nil then return "" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<unavailable>"
end

local function ExportField(v)
    local s = SafeValue(v)
    s = s:gsub("[\r\n\t]+", " ")

    -- Some client CVars are not human text at all; Blizzard stores compact
    -- bitfields/serialized state in strings that can contain raw C0 control
    -- bytes (for example 0x01/0x02). Passing those bytes into a Classic
    -- multiline EditBox can make an otherwise valid export page render blank.
    -- Preserve the value semantically for copy/paste by escaping only those
    -- non-printable bytes. The structured SavedVariables snapshot deliberately
    -- keeps the raw client value unchanged.
    s = s:gsub("[%z\1-\8\11\12\14-\31\127]", function(ch)
        return ("\\x%02X"):format(string.byte(ch))
    end)

    -- Copy/export uses a visible ASCII pipe separator instead of tab characters.
    -- Escape any literal pipes inside client-provided fields so a pasted row keeps
    -- an unambiguous column boundary without relying on font/tab rendering.
    s = s:gsub("|", "\\|")
    s = s:gsub("  +", " ")
    return Trim(s)
end

local function GetCurrent(name)
    if not name then return "" end
    local ok, value = pcall(GetCVar, name)
    return ok and SafeValue(value) or "<error>"
end

local function IsDefaultValue(value, defaultValue)
    if value == nil or defaultValue == nil then return false end
    local vn, dn = tonumber(value), tonumber(defaultValue)
    if vn ~= nil and dn ~= nil then
        return math.abs(vn - dn) < 0.0000001
    end
    return tostring(value) == tostring(defaultValue)
end

local function BuildFlags(entry)
    local flags = {}
    if entry.secure then flags[#flags + 1] = "SEC" end
    if entry.locked then flags[#flags + 1] = "LOCK" end
    if entry.readOnly then flags[#flags + 1] = "RO" end
    if entry.account then flags[#flags + 1] = "ACC" end
    if entry.character then flags[#flags + 1] = "CHAR" end
    return (#flags > 0) and table.concat(flags, " ") or "-"
end

local function RefreshEntry(entry)
    if not entry then return end
    local value, defaultValue, account, character, locked, secure, readOnly = SafeCVarInfo(entry.name)
    entry.value = SafeValue(value ~= nil and value or GetCurrent(entry.name))
    entry.defaultValue = SafeValue(defaultValue)
    entry.account = account and true or false
    entry.character = character and true or false
    entry.locked = locked and true or false
    entry.secure = secure and true or false
    entry.readOnly = readOnly and true or false
    entry.isDefault = IsDefaultValue(entry.value, entry.defaultValue)
    entry.flags = BuildFlags(entry)
end

local function EnumerateCVars()
    wipe(allCVars)
    wipe(allByName)

    if type(GetAllCommands) ~= "function" then
        return false, "ConsoleGetAllCommands/C_Console.GetAllCommands is unavailable on this client."
    end

    local ok, commands = pcall(GetAllCommands)
    if not ok or type(commands) ~= "table" then
        return false, "The client did not return a console command registry."
    end

    local seen = {}
    for _, info in ipairs(commands) do
        local name = type(info) == "table" and info.command or nil
        if name and info.commandType == 0 and not seen[name:lower()] and CVarExists(name) then
            seen[name:lower()] = true
            local entry = {
                name = name,
                description = SafeValue(info.help),
                categoryID = tonumber(info.category) or 9,
                category = CATEGORY_NAMES[tonumber(info.category) or 9] or tostring(info.category or "None"),
            }
            RefreshEntry(entry)
            allCVars[#allCVars + 1] = entry
            allByName[name:lower()] = entry
        end
    end

    table.sort(allCVars, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return true
end

local function GetSelectedEntry()
    if not selectedName then return nil end
    return allByName[selectedName:lower()]
end

local function MatchesFilter(entry, needle)
    if needle == "" then return true end
    local function has(v)
        return tostring(v or ""):lower():find(needle, 1, true) ~= nil
    end
    return has(entry.name)
        or has(entry.description)
        or has(entry.category)
        or has(entry.value)
        or has(entry.defaultValue)
        or has(entry.flags)
end

local function ApplyFilter()
    wipe(filteredCVars)
    local needle = frame and frame.search and Trim(frame.search:GetText()):lower() or ""
    for _, entry in ipairs(allCVars) do
        if MatchesFilter(entry, needle) then
            filteredCVars[#filteredCVars + 1] = entry
        end
    end
end

local function UpdateInspector()
    if not frame then return end
    local entry = GetSelectedEntry()
    if not entry then
        frame.detailName:SetText("Select a CVar")
        frame.detailDescription:SetText("Click a row to inspect its current/default value and metadata.")
        frame.detailMeta:SetText("")
        frame.valueEdit:SetText("")
        frame.valueEdit:Disable()
        frame.setButton:Disable()
        frame.resetButton:Disable()
        return
    end

    RefreshEntry(entry)
    frame.detailName:SetText(entry.name)
    frame.detailDescription:SetText(entry.description ~= "" and entry.description or "(No client help text.)")
    frame.detailMeta:SetFormattedText(
        "Current: |cffffffff%s|r    Default: |cffffffff%s|r    Category: |cffffffff%s|r    Flags: |cffffffff%s|r",
        entry.value ~= "" and entry.value or "<empty>",
        entry.defaultValue ~= "" and entry.defaultValue or "<none>",
        entry.category,
        entry.flags)
    frame.valueEdit:Enable()
    frame.valueEdit:SetText(entry.value)
    frame.valueEdit:SetCursorPosition(0)

    local blocked = entry.readOnly or entry.locked
    if blocked then
        frame.setButton:Disable()
        frame.resetButton:Disable()
    else
        frame.setButton:Enable()
        if entry.defaultValue ~= "" then frame.resetButton:Enable() else frame.resetButton:Disable() end
    end
end

local function UpdateRows()
    if not frame then return end

    if FauxScrollFrame_Update then
        FauxScrollFrame_Update(frame.scroll, #filteredCVars, VISIBLE_ROWS, ROW_HEIGHT)
    end
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(frame.scroll)) or 0

    for i = 1, VISIBLE_ROWS do
        local row = frame.rows[i]
        local entry = filteredCVars[offset + i]
        if entry then
            row.entryName = entry.name
            row.name:SetText(entry.name)
            row.category:SetText(entry.category)
            row.value:SetText(entry.value)
            row.defaultValue:SetText(entry.defaultValue)
            row.flags:SetText(entry.flags)
            if entry.name == selectedName then
                row.highlight:Show()
            else
                row.highlight:Hide()
            end
            if entry.isDefault then
                row.value:SetTextColor(0.82, 0.82, 0.82)
            else
                row.value:SetTextColor(1.0, 0.45, 0.30)
            end
            row:Show()
        else
            row.entryName = nil
            row:Hide()
        end
    end

    frame.status:SetFormattedText("Showing %d / %d CVars", #filteredCVars, #allCVars)
end

local function RefreshValuesOnly()
    for _, entry in ipairs(allCVars) do RefreshEntry(entry) end
    ApplyFilter()
    UpdateRows()
    UpdateInspector()
end

local function BuildExportText()
    local version, build, buildDate, tocVersion = "?", "?", "?", "?"
    if GetBuildInfo then
        local ok, a, b, c, d = pcall(GetBuildInfo)
        if ok then
            version, build, buildDate, tocVersion = SafeValue(a), SafeValue(b), SafeValue(c), SafeValue(d)
        end
    end

    local query = frame and frame.search and Trim(frame.search:GetText()) or ""
    local lines = {
        "# TurboFace CVar Browser Export",
        ("# Client: %s | Build: %s | Build date: %s | Interface: %s"):format(
            ExportField(version), ExportField(build), ExportField(buildDate), ExportField(tocVersion)),
        ("# Filter: %s"):format(query ~= "" and ExportField(query) or "<none>"),
        ("# CVars: %d filtered / %d registered"):format(#filteredCVars, #allCVars),
        "# Flags: SEC=secure; LOCK=locked; RO=read-only; ACC=account-stored; CHAR=character-stored",
        [[# Fields are separated by " | ". Literal pipes inside fields are escaped as \|. Description is the help text supplied by the WoW client.]],
        "CVar | Category | Current | Default | Modified | Flags | Description",
    }

    for _, entry in ipairs(filteredCVars) do
        lines[#lines + 1] = table.concat({
            ExportField(entry.name),
            ExportField(entry.category),
            ExportField(entry.value),
            ExportField(entry.defaultValue),
            entry.isDefault and "no" or "yes",
            ExportField(entry.flags),
            ExportField(entry.description ~= "" and entry.description or "(No client help text.)"),
        }, " | ")
    end

    return table.concat(lines, "\n")
end

local function BuildSnapshotEntries()
    local entries = {}
    for _, entry in ipairs(filteredCVars) do
        entries[#entries + 1] = {
            name = entry.name,
            category = entry.category,
            current = entry.value,
            defaultValue = entry.defaultValue,
            modified = not entry.isDefault,
            flags = entry.flags,
            description = entry.description ~= "" and entry.description or "(No client help text.)",
        }
    end
    return entries
end

local function SaveExportSnapshot()
    if not frame then return end

    -- Save into a dedicated per-character variable so the snapshot lands in the
    -- same character-level TurboFace.lua file developers commonly grab while
    -- reproducing client behavior. Keep it structured instead of one giant
    -- escaped string so uploaded SavedVariables are easy to inspect directly.
    RefreshValuesOnly()
    local query = frame.search and Trim(frame.search:GetText()) or ""
    local stamp = date and date("%Y-%m-%d %H:%M:%S") or tostring(time and time() or "unknown")
    local version, build, buildDate, tocVersion = "?", "?", "?", "?"
    if GetBuildInfo then
        local ok, a, b, c, d = pcall(GetBuildInfo)
        if ok then
            version, build, buildDate, tocVersion = SafeValue(a), SafeValue(b), SafeValue(c), SafeValue(d)
        end
    end

    TurboFaceCVarExportCharDB = {
        schema = 2,
        filter = query,
        count = #filteredCVars,
        total = #allCVars,
        savedAt = stamp,
        client = {
            version = version,
            build = build,
            buildDate = buildDate,
            interface = tocVersion,
        },
        entries = BuildSnapshotEntries(),
    }

    local message = ("Saved %d CVar%s to the per-character CVar snapshot. /reload or logout, then upload the character SavedVariables/TurboFace.lua file."):format(
        #filteredCVars, #filteredCVars == 1 and "" or "s")
    if ns.Chat then
        ns:Chat("CVars", message)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("TurboFace CVars: " .. message)
    end
end

local function SplitExportText(text)
    local pages = {}
    local current = {}
    local currentLen = 0

    local function Flush()
        if #current == 0 then return end
        pages[#pages + 1] = table.concat(current, "\n")
        wipe(current)
        currentLen = 0
    end

    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if #line > EXPORT_PAGE_MAX_CHARS then
            Flush()
            local pos = 1
            while pos <= #line do
                pages[#pages + 1] = line:sub(pos, pos + EXPORT_PAGE_MAX_CHARS - 1)
                pos = pos + EXPORT_PAGE_MAX_CHARS
            end
        else
            local addLen = #line + ((#current > 0) and 1 or 0)
            if #current > 0 and (currentLen + addLen) > EXPORT_PAGE_MAX_CHARS then
                Flush()
                addLen = #line
            end
            current[#current + 1] = line
            currentLen = currentLen + addLen
        end
    end
    Flush()

    if #pages == 0 then
        pages[1] = "# No CVar rows matched the current filter."
    end
    return pages
end

local function ShowExportPage(index, selectText)
    local f = exportFrame
    if not f then return end

    local pageCount = math.max(1, #exportPages)
    exportPageIndex = math.max(1, math.min(tonumber(index) or 1, pageCount))
    local pageText = exportPages[exportPageIndex] or ""
    local text = ("# Export page %d/%d\n%s"):format(exportPageIndex, pageCount, pageText)
    local _, breaks = text:gsub("\n", "\n")
    local contentHeight = math.max(430, ((breaks or 0) + 2) * 15)

    f.edit:SetHeight(contentHeight)
    f.edit:SetText(" ") -- primes Classic font/editbox rendering before the real payload

    local function ApplyText()
        if not f or not f:IsShown() then return end
        f.edit:SetText(text)
        f.edit:SetCursorPosition(0)
        f.scroll:SetVerticalScroll(0)
        if selectText then
            f.edit:SetFocus()
            f.edit:HighlightText()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, ApplyText)
    else
        ApplyText()
    end

    if exportPageIndex > 1 then f.prevButton:Enable() else f.prevButton:Disable() end
    if exportPageIndex < pageCount then f.nextButton:Enable() else f.nextButton:Disable() end
    f.status:SetFormattedText("%d CVars exported — page %d/%d — Ctrl+C copies this page", f.exportCount or 0, exportPageIndex, pageCount)
end

local function EnsureExportFrame()
    if exportFrame then return exportFrame end

    local f = CreateFrame("Frame", "TurboFaceCVarExport", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(840, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("TurboFace CVar Export")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText("Copy export is paged to stay inside Classic EditBox limits. Save writes a structured per-character snapshot.")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local panel = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 16, -62)
    panel:SetPoint("BOTTOMRIGHT", -34, 54)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    panel:SetBackdropColor(0.015, 0.015, 0.015, 0.82)

    local scroll = CreateFrame("ScrollFrame", "TurboFaceCVarExportScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    -- AIO/AceGUI uses 0 for an unlimited multiline EditBox. We still page at
    -- 30k characters so no single payload approaches client implementation limits.
    edit:SetMaxLetters(0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetTextColor(1, 1, 1)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")
    edit:SetWidth(750)
    edit:SetHeight(430)
    if edit.SetCountInvisibleLetters then edit:SetCountInvisibleLetters(false) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        local yPos = -y
        local offset = scroll:GetVerticalScroll()
        if yPos < offset then
            scroll:SetVerticalScroll(yPos)
        else
            local bottom = yPos + (cursorHeight or 0) - scroll:GetHeight()
            if bottom > offset then scroll:SetVerticalScroll(bottom) end
        end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    f.scroll = scroll

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", 18, 20)
    f.status = status

    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(72, 22)
    prev:SetPoint("BOTTOMRIGHT", -382, 16)
    prev:SetText("Prev")
    prev:SetScript("OnClick", function() ShowExportPage(exportPageIndex - 1, true) end)
    f.prevButton = prev

    local nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextButton:SetSize(72, 22)
    nextButton:SetPoint("BOTTOMRIGHT", -302, 16)
    nextButton:SetText("Next")
    nextButton:SetScript("OnClick", function() ShowExportPage(exportPageIndex + 1, true) end)
    f.nextButton = nextButton

    local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save:SetSize(96, 22)
    save:SetPoint("BOTTOMRIGHT", -198, 16)
    save:SetText("Save")
    save:SetScript("OnClick", SaveExportSnapshot)
    save:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Save CVar snapshot", 1, 0.82, 0)
        GameTooltip:AddLine("Stores every filtered row as structured data in TurboFaceCVarExportCharDB.", 1, 1, 1, true)
        GameTooltip:AddLine("After /reload or logout, upload the character-level SavedVariables/TurboFace.lua file.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    save:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectAll:SetSize(92, 22)
    selectAll:SetPoint("BOTTOMRIGHT", -98, 16)
    selectAll:SetText("Select All")
    selectAll:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "TurboFaceCVarExport"
    end

    exportFrame = f
    return f
end

local function ShowExport()
    if not frame then return end
    RefreshValuesOnly()
    local f = EnsureExportFrame()
    exportPages = SplitExportText(BuildExportText())
    exportPageIndex = 1
    f.exportCount = #filteredCVars
    f:Show()
    f:Raise()
    ShowExportPage(1, true)
end

local function FullRefresh()
    local ok, err = EnumerateCVars()
    if not ok then
        if ns.Chat then ns:Chat("CVars", err) end
    end
    ApplyFilter()
    UpdateRows()
    UpdateInspector()
end

local function SetSelectedValue(value)
    local entry = GetSelectedEntry()
    if not entry then return end
    RefreshEntry(entry)

    if entry.readOnly then
        ns:Chat("CVars", entry.name .. " is read-only.")
        return
    end
    if entry.locked then
        ns:Chat("CVars", entry.name .. " is locked from user changes.")
        return
    end
    if entry.secure and InCombatLockdown and InCombatLockdown() then
        ns:Chat("CVars", entry.name .. " is secure and cannot be changed in combat.")
        return
    end

    local setter = SetCVar or (C_CVar and C_CVar.SetCVar)
    if type(setter) ~= "function" then
        ns:Chat("CVars", "SetCVar is unavailable on this client.")
        return
    end

    local ok, err = pcall(setter, entry.name, tostring(value or ""))
    if not ok then
        ns:Chat("CVars", ("Failed to set %s: %s"):format(entry.name, tostring(err)))
        return
    end

    RefreshValuesOnly()
end

local function CreateColumnHeader(parent, text, x, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, -4)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text)
    return fs
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "TurboFaceCVarBrowser", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(900, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("TurboFace CVar Browser")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText("Developer/debug view of the CVars registered by the current WoW client.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(86, 22)
    refresh:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", -6, -10)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", FullRefresh)
    frame.refreshButton = refresh

    local export = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    export:SetSize(86, 22)
    export:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    export:SetText("Export")
    export:SetScript("OnClick", ShowExport)
    export:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Export current CVar results", 1, 0.82, 0)
        GameTooltip:AddLine("Exports every CVar matching the current search, including current/default values, flags, and the client description.", 1, 1, 1, true)
        GameTooltip:AddLine("Clear the search first to export the full registry.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    export:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.exportButton = export

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(86, 22)
    save:SetPoint("RIGHT", export, "LEFT", -6, 0)
    save:SetText("Save")
    save:SetScript("OnClick", SaveExportSnapshot)
    save:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Save current CVar results", 1, 0.82, 0)
        GameTooltip:AddLine("Stores every filtered CVar as structured data in TurboFaceCVarExportCharDB.", 1, 1, 1, true)
        GameTooltip:AddLine("After /reload or logout, upload the character-level SavedVariables/TurboFace.lua file.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("WoW's addon sandbox cannot create a standalone .txt file.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    save:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.saveButton = save

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -17)
    searchLabel:SetText("Search")

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(440, 22)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(120)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function()
        ApplyFilter()
        if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(frame.scroll, 0) end
        UpdateRows()
    end)
    frame.search = search

    local list = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    list:SetPoint("TOPLEFT", 14, -98)
    list:SetPoint("TOPRIGHT", -14, -98)
    list:SetHeight((VISIBLE_ROWS * ROW_HEIGHT) + 26)
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    list:SetBackdropColor(0.02, 0.02, 0.02, 0.72)
    frame.list = list

    CreateColumnHeader(list, "CVar", 8, 260)
    CreateColumnHeader(list, "Category", 276, 82)
    CreateColumnHeader(list, "Current", 366, 150)
    CreateColumnHeader(list, "Default", 524, 150)
    CreateColumnHeader(list, "Flags", 682, 110)

    local scroll = CreateFrame("ScrollFrame", "TurboFaceCVarBrowserScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -24)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateRows)
    end)
    frame.scroll = scroll

    frame.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 4, -(24 + (i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", -26, 0)
        row:RegisterForClicks("LeftButtonUp")

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then bg:SetColorTexture(1, 1, 1, 0.025) else bg:SetColorTexture(0, 0, 0, 0) end

        local highlight = row:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.15, 0.55, 0.95, 0.18)
        highlight:Hide()
        row.highlight = highlight

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.06)

        local function Cell(x, width, justify)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0)
            fs:SetWidth(width)
            fs:SetJustifyH(justify or "LEFT")
            fs:SetWordWrap(false)
            return fs
        end
        row.name = Cell(4, 260)
        row.category = Cell(272, 82)
        row.value = Cell(362, 150, "RIGHT")
        row.defaultValue = Cell(520, 150, "RIGHT")
        row.flags = Cell(678, 110)

        row:SetScript("OnClick", function(self)
            if not self.entryName then return end
            local now = GetTime()
            local doubleClick = self._tfLastClick and (now - self._tfLastClick) <= 0.25
            self._tfLastClick = now
            selectedName = self.entryName
            UpdateRows()
            UpdateInspector()
            if doubleClick then
                frame.valueEdit:SetFocus()
                frame.valueEdit:HighlightText()
            end
        end)
        row:SetScript("OnEnter", function(self)
            local name = self.entryName
            if not name then return end
            local entry
            for _, e in ipairs(filteredCVars) do if e.name == name then entry = e break end end
            if not entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(entry.name, 1, 0.82, 0)
            if entry.description ~= "" then
                GameTooltip:AddLine(entry.description, 1, 1, 1, true)
            end
            GameTooltip:AddDoubleLine("Current", entry.value, 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Default", entry.defaultValue ~= "" and entry.defaultValue or "<none>", 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Flags", entry.flags, 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.rows[i] = row
    end

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 4, -4)
    frame.status = status

    local detail = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    detail:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -22)
    detail:SetPoint("BOTTOMRIGHT", -14, 14)
    detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    detail:SetBackdropColor(0.02, 0.02, 0.02, 0.55)

    local detailName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailName:SetPoint("TOPLEFT", 10, -9)
    detailName:SetPoint("RIGHT", -10, 0)
    detailName:SetJustifyH("LEFT")
    frame.detailName = detailName

    local detailDescription = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailDescription:SetPoint("TOPLEFT", detailName, "BOTTOMLEFT", 0, -6)
    detailDescription:SetPoint("RIGHT", -10, 0)
    detailDescription:SetHeight(32)
    detailDescription:SetJustifyH("LEFT")
    detailDescription:SetJustifyV("TOP")
    detailDescription:SetWordWrap(true)
    frame.detailDescription = detailDescription

    local detailMeta = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailMeta:SetPoint("TOPLEFT", detailDescription, "BOTTOMLEFT", 0, -5)
    detailMeta:SetPoint("RIGHT", -10, 0)
    detailMeta:SetJustifyH("LEFT")
    frame.detailMeta = detailMeta

    local valueLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLabel:SetPoint("BOTTOMLEFT", 10, 13)
    valueLabel:SetText("Set value")

    local valueEdit = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
    valueEdit:SetSize(300, 22)
    valueEdit:SetPoint("LEFT", valueLabel, "RIGHT", 10, 0)
    valueEdit:SetAutoFocus(false)
    valueEdit:SetMaxLetters(255)
    valueEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    valueEdit:SetScript("OnEnterPressed", function(self)
        SetSelectedValue(self:GetText())
        self:ClearFocus()
    end)
    frame.valueEdit = valueEdit

    local setButton = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    setButton:SetSize(70, 22)
    setButton:SetPoint("LEFT", valueEdit, "RIGHT", 8, 0)
    setButton:SetText("Set")
    setButton:SetScript("OnClick", function() SetSelectedValue(valueEdit:GetText()) end)
    frame.setButton = setButton

    local resetButton = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    resetButton:SetSize(90, 22)
    resetButton:SetPoint("LEFT", setButton, "RIGHT", 6, 0)
    resetButton:SetText("Default")
    resetButton:SetScript("OnClick", function()
        local entry = GetSelectedEntry()
        if entry and entry.defaultValue ~= "" then SetSelectedValue(entry.defaultValue) end
    end)
    frame.resetButton = resetButton

    frame.eventFrame = CreateFrame("Frame")
    frame.eventFrame:SetScript("OnEvent", function(_, event, cvarName)
        if event ~= "CVAR_UPDATE" or not frame:IsShown() then return end
        local entry = cvarName and allByName[tostring(cvarName):lower()] or nil
        if entry then
            RefreshEntry(entry)
            ApplyFilter()
            UpdateRows()
            if selectedName and selectedName:lower() == entry.name:lower() then
                UpdateInspector()
            end
        else
            -- A new/late-registered CVar can appear after login; explicit Refresh
            -- remains the authoritative way to rebuild the registry.
            UpdateRows()
        end
    end)

    frame:SetScript("OnShow", function()
        frame.eventFrame:RegisterEvent("CVAR_UPDATE")
        FullRefresh()
    end)
    frame:SetScript("OnHide", function()
        frame.eventFrame:UnregisterEvent("CVAR_UPDATE")
        GameTooltip:Hide()
    end)

    if UISpecialFrames then
        UISpecialFrames[#UISpecialFrames + 1] = "TurboFaceCVarBrowser"
    end

    UpdateInspector()
    return frame
end

function Browser:Open(searchText)
    local f = EnsureFrame()
    if searchText ~= nil then
        f.search:SetText(Trim(searchText))
    end
    f:Show()
    f:Raise()
end

function Browser:Toggle(searchText)
    local f = EnsureFrame()
    if f:IsShown() and Trim(searchText) == "" then
        f:Hide()
    else
        self:Open(searchText)
    end
end

function Browser:Refresh()
    if frame and frame:IsShown() then FullRefresh() end
end

function Browser:Export()
    local f = EnsureFrame()
    if not f:IsShown() then f:Show() end
    ShowExport()
end

function Browser:SaveSnapshot()
    local f = EnsureFrame()
    if not f:IsShown() then f:Show() end
    SaveExportSnapshot()
end
