local _, ns = ...

-- Personal notes live outside portable profiles so importing a UI preset never
-- replaces character text. SavedVariables are initialized only after login.
local Note = {}
ns.StickyNote = Note
local frame, edit, scroll, hint, collapseButton
local suspending = false
local MAX_LETTERS = 4000

local function Enabled()
    return ns.Opt("stickyNoteEnabled", false) == true
end
local EXPANDED_HEIGHT, COLLAPSED_HEIGHT = 230, 32

local function DB()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.stickyNote) ~= "table" then
        TurboFaceCharDB.stickyNote = { text = "", visible = false }
    end
    local db = TurboFaceCharDB.stickyNote
    if type(db.text) ~= "string" then db.text = "" end
    return db
end

local function Coordinate(value)
    return type(value) == "number" and value == value
        and math.abs(value) < 100000 and value or 0
end

local function Place()
    local db = DB()
    frame:ClearAllPoints()
    -- Store the expanded center so collapsing keeps the header in place.
    local lift = (EXPANDED_HEIGHT - frame:GetHeight()) / 2
    frame:SetPoint("CENTER", UIParent, "CENTER", Coordinate(db.x), Coordinate(db.y) + lift)
end

local function SavePosition()
    frame:StopMovingOrSizing()
    local x, y = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if x and y and px and py then
        local db = DB()
        db.x, db.y = x - px, y - py - (EXPANDED_HEIGHT - frame:GetHeight()) / 2
    end
end

local function ApplyCollapsed()
    local collapsed = DB().collapsed == true
    if collapsed then edit:ClearFocus() end
    scroll:SetShown(not collapsed)
    hint:SetShown(not collapsed)
    frame:SetHeight(collapsed and COLLAPSED_HEIGHT or EXPANDED_HEIGHT)
    collapseButton:SetText(collapsed and "+" or "-")
    Place()
end

local function CreateNote()
    if frame then return end
    frame = CreateFrame("Frame", "TurboFaceStickyNote", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(280, EXPANDED_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.12, 0.13, 0.15, 0.96)
    frame:SetBackdropBorderColor(0.32, 0.34, 0.38, 1)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -55, -1)
    header:SetHeight(29)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() edit:ClearFocus(); frame:StartMoving() end)
    header:SetScript("OnDragStop", SavePosition)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 11, 0)
    title:SetText("Sticky Note")
    title:SetTextColor(0.82, 0.83, 0.85)

    collapseButton = CreateFrame("Button", "TurboFaceStickyNoteCollapse", frame)
    collapseButton:SetSize(26, 27)
    collapseButton:SetPoint("TOPRIGHT", -28, -2)
    collapseButton:SetNormalFontObject("GameFontHighlightLarge")
    collapseButton:SetHighlightFontObject("GameFontNormalLarge")
    collapseButton:SetScript("OnClick", function() Note:SetCollapsed(not DB().collapsed) end)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 27)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetNormalFontObject("GameFontNormalLarge")
    close:SetHighlightFontObject("GameFontHighlightLarge")
    close:SetText("x")
    close:SetScript("OnClick", function() Note:Hide() end)

    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", -30, 26)
    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(0.88, 0.88, 0.86)
    edit:SetWidth(238)
    edit:SetMaxLetters(MAX_LETTERS)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)

    hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 8)
    hint:SetTextColor(0.60, 0.63, 0.67)
    hint:SetText("Drag header to move · Saves per character")
    local placeholder = scroll:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("TOPLEFT", 0, -2)
    placeholder:SetTextColor(0.60, 0.63, 0.67)
    placeholder:SetText("Click here to write a note...")
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        if userInput then DB().text = text end
        placeholder:SetShown(text == "")
        scroll:UpdateScrollChildRect()
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top = -y
        local current = scroll:GetVerticalScroll()
        if top < current then
            scroll:SetVerticalScroll(math.max(0, top))
        elseif top + height > current + scroll:GetHeight() then
            scroll:SetVerticalScroll(math.max(0, top + height - scroll:GetHeight()))
        end
    end)
    frame:SetScript("OnHide", function()
        SavePosition()
        edit:ClearFocus()
        if not suspending then DB().visible = false end
    end)
    -- Programmatic restoration must not overwrite saved text or steal focus.
    edit:SetText(DB().text)
    ApplyCollapsed()
end

function Note:SetCollapsed(collapsed)
    if not Enabled() then return end
    CreateNote()
    SavePosition()
    DB().collapsed = collapsed == true
    ApplyCollapsed()
end

function Note:Show()
    if not Enabled() then return end
    CreateNote()
    DB().visible = true
    frame:Show()
end

function Note:Hide()
    if not Enabled() then return end
    DB().visible = false
    if frame then frame:Hide() end
end

function Note:Toggle()
    if not Enabled() then return end
    if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function Note:ResetPosition()
    if not Enabled() then return end
    local db = DB()
    db.x, db.y = 0, 0
    if frame then frame:StopMovingOrSizing(); Place() end
end

function Note:Refresh()
    if not Enabled() then
        -- Suspend presentation without overwriting the user's last open state.
        -- A disabled login never creates the note or its character record.
        if frame then
            suspending = true
            frame:Hide()
            edit:ClearFocus()
            suspending = false
        end
        return
    end
    if DB().visible == true then self:Show() end
end

function Note:HandleSlash(args)
    if not Enabled() then
        ns:Chat("Note", "Enable Sticky Note in Options > Speedrun first.")
        return
    end
    local command = (args or ""):lower():match("^%s*(.-)%s*$")
    if command == "show" then self:Show()
    elseif command == "hide" then self:Hide()
    elseif command == "collapse" then self:SetCollapsed(true); self:Show()
    elseif command == "expand" then self:SetCollapsed(false); self:Show()
    elseif command == "reset" then self:ResetPosition(); self:Show()
    elseif command == "" then self:Toggle()
    else ns:Chat("Note", "Usage: /tf note [show|hide|collapse|expand|reset]. Reset only moves the note to the center.") end
end

SLASH_TURBOFACENOTE1 = "/tfnote"
SlashCmdList.TURBOFACENOTE = function(args) Note:HandleSlash(args) end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Note:Refresh()
end)
