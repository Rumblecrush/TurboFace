local _, ns = ...

-- =============================================================================
-- TurboFace Loot Frame
-- Lean TurboFace loot-toast frame for WoW Classic Era 1.15.x.
-- Intentionally trimmed to item/money loot only: no reputation, currency, AH/TSM,
-- banned lists, profession quality, socket/tertiary parsing, or cross-version code.
-- =============================================================================

local Loot = {}
ns.Loot = Loot

local _G = _G
local UIParent = UIParent
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetMoney = GetMoney
local GetItemInfo = ns.API.GetItemInfo
local FormatMoneyCompat = ns.API.FormatMoney
local UnitName = UnitName
local tostring = tostring
local tonumber = tonumber
local type = type
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_match = string.match
local string_find = string.find
local string_sub = string.sub
local strsplit = strsplit

local defaults = ns.defaults.lootFrame

local frame, eventFrame
local initialized = false
local entries = {}
local lastMoney
local lootOpen = false
local recentLootTime = 0
local moneyChatCredit = 0
local moneyPlayerCredit = 0
local moneyCreditTime = 0
local MONEY_RECONCILE_WINDOW = 1.50
local LOOT_ICON_MASK = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Mask-Rounded"
local LOOT_ICON_BORDER = "Interface\\AddOns\\TurboFace\\Textures\\Icon-Border-Buff"
local LOOT_ROW_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local LOOT_ROW_PAD_X = 3
local LOOT_ROW_PAD_Y = 3
local LOOT_ROW_EDGE_SIZE = 7
local LOOT_ROW_INSET = 1.2
local LOOT_ICON_LEFT_NUDGE = -0.5
local registerMoverQueued = false
local rendering = false
local renderQueued = false
local SetEvents

local MergeDefaults = ns.MergeDefaults
local After = ns.After

local function DB()
    if not TurboFaceDB then TurboFaceDB = {} end
    if type(TurboFaceDB.lootFrame) ~= "table" then TurboFaceDB.lootFrame = {} end
    MergeDefaults(TurboFaceDB.lootFrame, defaults)
    return TurboFaceDB.lootFrame
end

local function Enabled()
    local on = DB().enabled ~= false
    return ns.MoverDependentEnabled(on)
end

local function ClampNumber(v, fallback, minVal, maxVal)
    v = tonumber(v) or fallback
    if minVal and v < minVal then v = minVal end
    if maxVal and v > maxVal then v = maxVal end
    return v
end

local function FormatMoney(amount)
    amount = tonumber(amount) or 0
    -- Use the shared modern money boundary so Forever renders Blizzard's native
    -- coin-gold / coin-silver / coin-copper atlases. This same formatter is used
    -- by the Trainer surfaces and retains legacy/plain-text fallbacks in Compat.
    if FormatMoneyCompat then return FormatMoneyCompat(amount) end
    local g = math_floor(amount / 10000)
    local s = math_floor((amount - g * 10000) / 100)
    local c = amount % 100
    if g > 0 then return g .. "g " .. s .. "s " .. c .. "c" end
    if s > 0 then return s .. "s " .. c .. "c" end
    return c .. "c"
end

local function MoneyIcon(amount)
    amount = tonumber(amount) or 0
    if amount >= 10000 then return 133784 end -- gold coin stack
    if amount >= 100 then return 133786 end  -- silver coin stack
    return 133788                         -- copper coin stack
end

local function EscapePattern(text)
    return tostring(text or ""):gsub("([%%%^%$%(%)%%.%[%]%*%+%-%?])", "%%%1")
end

local function MoneyNumber(text)
    if not text then return 0 end
    return tonumber((tostring(text):gsub(",", ""))) or 0
end

local function MoneyWordValue(msg, word, value)
    if not word or word == "" then return 0 end
    local n = string_match(msg or "", "([%d,]+)%s*" .. EscapePattern(word))
    return MoneyNumber(n) * value
end

local function ParseMoneyMessage(msg)
    msg = tostring(msg or "")
    if msg == "" then return 0 end

    local copper = 0

    -- Normal Classic chat text is word-based, for example "You loot 3 Silver, 12 Copper."
    copper = copper + MoneyWordValue(msg, "Gold", 10000)
    copper = copper + MoneyWordValue(msg, "gold", 10000)
    copper = copper + MoneyWordValue(msg, "Silver", 100)
    copper = copper + MoneyWordValue(msg, "silver", 100)
    copper = copper + MoneyWordValue(msg, "Copper", 1)
    copper = copper + MoneyWordValue(msg, "copper", 1)

    -- Symbol fallbacks, useful for localized coin strings or icon-adjacent chat output.
    copper = copper + MoneyWordValue(msg, GOLD_AMOUNT_SYMBOL or "g", 10000)
    copper = copper + MoneyWordValue(msg, SILVER_AMOUNT_SYMBOL or "s", 100)
    copper = copper + MoneyWordValue(msg, COPPER_AMOUNT_SYMBOL or "c", 1)

    if copper > 0 then return copper end

    -- Fallbacks for clients/addons that render coin icons in chat strings.
    local g = MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-UI%-GoldIcon")) + MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-Gold"))
    local s = MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-UI%-SilverIcon")) + MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-Silver"))
    local c = MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-UI%-CopperIcon")) + MoneyNumber(string_match(msg, "([%d,]+)%s*|T[^|]-Copper"))
    return (g * 10000) + (s * 100) + c
end

local function StripRealm(name)
    if not name then return nil end
    local short = string_match(name, "^([^%-]+)")
    return short or name
end

local function PlayerName()
    local name = UnitName and UnitName("player")
    return StripRealm(name)
end

local function OwnLootMessage(msg, receiver)
    if receiver and receiver ~= "" then
        return StripRealm(receiver) == PlayerName()
    end
    msg = tostring(msg or "")
    return string_find(msg, "You receive", 1, true) or string_find(msg, "You loot", 1, true)
end

local function ExtractItemLink(msg)
    msg = tostring(msg or "")
    local link, pos = string_match(msg, "(|c%x+|Hitem:.-|h%[.-%]|h|r)()")
    if link then return link, pos end
    link, pos = string_match(msg, "(|Hitem:.-|h%[.-%]|h)()")
    return link, pos
end

local function ExtractStackCount(msg, pos)
    local suffix = pos and string_sub(msg, pos) or msg
    local n = tonumber(string_match(suffix or "", "[xX](%d+)"))
    return (n and n > 0) and n or 1
end

local function LinkName(link)
    return string_match(tostring(link or ""), "%[(.-)%]") or tostring(link or "Loot")
end

local function ItemInfo(link)
    local name, itemLink, quality, icon, sellPrice
    if GetItemInfo then
        name, itemLink, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfo(link)
    end
    return name or LinkName(link), itemLink or link, quality or 1,
        icon or "Interface\\Icons\\INV_Misc_QuestionMark", tonumber(sellPrice) or 0
end

local function LinkItemID(link)
    return tonumber(string_match(tostring(link or ""), "item:(%d+)"))
end

local function QualityColor(quality)
    local q = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if q then return q.r or 1, q.g or 1, q.b or 1 end
    return 1, 1, 1
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "TurboFaceLootFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    frame:SetSize(defaults.width, defaults.rowHeight)
    frame:SetScale(defaults.scale)
    frame.rows = {}
    frame:Hide()

    return frame
end

local function StyleRow(row, db)
    local h = ClampNumber(db.rowHeight, defaults.rowHeight, 18, 80)
    -- Icon size is derived from row height so Loot Frame sizing has one
    -- vertical control. The fixed shell padding is subtracted once from
    -- the configured content height, preserving the intentionally tight
    -- rounded-shell/icon relationship as the row grows or shrinks.
    local iconSize = math_max(12, h - LOOT_ROW_PAD_Y)
    local width = ClampNumber(db.width, defaults.width, 120, 600)
    local fontSize = ClampNumber(db.fontSize, defaults.fontSize, 6, 24)
    local bgAlpha = ClampNumber(db.backgroundAlpha, defaults.backgroundAlpha, 0, 1)
    local key = table.concat({ tostring(width), tostring(h), tostring(iconSize), tostring(fontSize),
        tostring(bgAlpha), tostring(db.showVendorValue ~= false) }, "|")

    if row._tfLootStyleKey == key then return end
    row._tfLootStyleKey = key

    -- Width/rowHeight remain the content-box settings. The rounded shell adds
    -- three pixels on every side: enough clearance for the rounded icon frame
    -- while keeping the final Tooltip edge visually tight to the icon. Icon
    -- size follows row height automatically (rowHeight - shell padding).
    row:SetHeight(h + LOOT_ROW_PAD_Y * 2)
    row:SetWidth(width + LOOT_ROW_PAD_X * 2)
    if row.SetBackdrop then
        -- Tooltip border is Blizzard's scalable rounded-rectangle edge. Its
        -- corner slices retain their proportions at every configured row width.
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = LOOT_ROW_BORDER,
            edgeSize = LOOT_ROW_EDGE_SIZE,
            insets = {
                left = LOOT_ROW_INSET, right = LOOT_ROW_INSET,
                top = LOOT_ROW_INSET, bottom = LOOT_ROW_INSET,
            },
        })
        row:SetBackdropColor(0.03, 0.03, 0.03, bgAlpha)
        row:SetBackdropBorderColor(0.01, 0.01, 0.01, 1)
    end

    row.icon:SetSize(iconSize, iconSize)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 3 + LOOT_ROW_PAD_X + LOOT_ICON_LEFT_NUDGE, 0)

    row.count:ClearAllPoints()
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
    row.count:SetJustifyH("RIGHT")

    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    if db.showVendorValue ~= false then
        row.vendor:Show()
        row.text:SetPoint("RIGHT", row.vendor, "LEFT", -8, 0)
    else
        row.vendor:Hide()
        row.text:SetPoint("RIGHT", row, "RIGHT", -8 - LOOT_ROW_PAD_X, 0)
    end
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    if ns.StyleFont then ns:StyleFont(row.text, nil, fontSize, "lootFrame") end
    if ns.StyleFont then ns:StyleFont(row.count, nil, math_max(8, fontSize - 1), "lootFrame") end
    if ns.StyleFont then ns:StyleFont(row.vendor, nil, math_max(8, fontSize - 1), "lootFrame") end
end

local function AcquireRow(index)
    local f = EnsureFrame()
    if f.rows[index] then return f.rows[index] end

    local row = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if row.CreateMaskTexture and row.icon.AddMaskTexture then
        row.iconMask = row:CreateMaskTexture()
        row.iconMask:SetAllPoints(row.icon)
        row.iconMask:SetTexture(LOOT_ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        row.icon:AddMaskTexture(row.iconMask)
    end
    row.iconBorder = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.iconBorder:SetTexture(LOOT_ICON_BORDER)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetTextColor(1, 1, 1)
    row.vendor = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.vendor:SetPoint("RIGHT", row, "RIGHT", -6 - LOOT_ROW_PAD_X, 0)
    row.vendor:SetJustifyH("RIGHT")
    row.vendor:SetTextColor(1, 0.82, 0)

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        if self.link and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        -- Shift-click still inserts the item link into chat (no dismiss).
        if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
            return
        end
        -- Plain left-click dismisses this toast immediately, overriding the
        -- visibility duration timer. (Loot: method call so the late-defined
        -- RemoveEntry local is resolved at click time, not closure time.)
        if button == "LeftButton" and self.entry then
            if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            Loot:Dismiss(self.entry)
        end
    end)

    f.rows[index] = row
    return row
end

local function HideUnusedRows(startIndex)
    local f = EnsureFrame()
    for i = startIndex, #(f.rows or {}) do
        f.rows[i]:Hide()
    end
end

function Loot:GetMoverWidth()
    local db = DB()
    return ClampNumber(db.width, defaults.width, 120, 600) + LOOT_ROW_PAD_X * 2
end

function Loot:GetMoverHeight()
    local db = DB()
    local count = #entries
    if count < 1 then count = 1 end
    local h = ClampNumber(db.rowHeight, defaults.rowHeight, 18, 80)
    local spacing = ClampNumber(db.spacing, defaults.spacing, 0, 24)
    local visualH = h + LOOT_ROW_PAD_Y * 2
    return (count * visualH) + ((count - 1) * spacing)
end

function Loot:GetFrame()
    return frame
end

function Loot:GetChildren()
    return frame and frame.rows or {}
end

function Loot:Layout()
    local db = DB()
    local f = EnsureFrame()
    local w = self:GetMoverWidth()
    local h = self:GetMoverHeight()
    local scale = ClampNumber(db.scale, defaults.scale, 0.5, 2.5)
    local key = table.concat({ tostring(w), tostring(h), tostring(scale) }, "|")

    if f._tfLootLayoutKey ~= key then
        f._tfLootLayoutKey = key
        f:SetSize(w, h)
        f:SetScale(scale)
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("LootFrame") end
    end
end

local function QueueRender()
    if renderQueued then return end
    renderQueued = true
    After(0, function()
        renderQueued = false
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("LootFrame:Render", Loot.Render, Loot)
        else
            Loot:Render()
        end
    end)
end

local function CancelExpire(entry)
    if not entry then return end
    entry.expireToken = nil
    local timer = entry.expireTimer
    entry.expireTimer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

local function RemoveEntry(entry)
    local removed = false
    for i = #entries, 1, -1 do
        if entries[i] == entry then
            tremove(entries, i)
            removed = true
            break
        end
    end
    if removed then
        CancelExpire(entry)
        QueueRender()
    end
end

-- Left-click dismissal: drop the entry now and invalidate/cancel its pending
-- expiry timer so a dismissed/trimmed toast cannot wake TurboFace later.
function Loot:Dismiss(entry)
    if not entry then return end
    CancelExpire(entry)
    RemoveEntry(entry)
end

local function ScheduleExpire(entry)
    local db = DB()
    local duration = ClampNumber(db.duration, defaults.duration, 1, 30)
    CancelExpire(entry)

    -- Prefer a cancellable timer. Repeated money/item merges reset one timer
    -- instead of leaving a trail of stale After() callbacks that all wake at
    -- the old expiry times.
    if C_Timer and C_Timer.NewTimer then
        local timer
        timer = C_Timer.NewTimer(duration, function()
            if entry.expireTimer ~= timer then return end
            entry.expireTimer = nil
            RemoveEntry(entry)
        end)
        entry.expireTimer = timer
        return
    end

    local token = {}
    entry.expireToken = token
    After(duration, function()
        if entry.expireToken == token then
            entry.expireToken = nil
            RemoveEntry(entry)
        end
    end)
end

function Loot:Render()
    if rendering then return end
    if not frame and not Enabled() then return end
    rendering = true

    local db = DB()
    local f = EnsureFrame()
    self:Layout()

    if not Enabled() or #entries == 0 then
        HideUnusedRows(1)
        f:Hide()
        rendering = false
        return
    end

    f:Show()
    local spacing = ClampNumber(db.spacing, defaults.spacing, 0, 24)

    for i, entry in ipairs(entries) do
        local row = AcquireRow(i)
        StyleRow(row, db)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        else
            row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, -spacing)
            row:SetPoint("TOPRIGHT", f.rows[i - 1], "BOTTOMRIGHT", 0, -spacing)
        end

        row.link = entry.link
        row.entry = entry   -- for left-click dismissal
        row.icon:SetTexture(entry.icon)
        if entry.type == "money" then
            row.iconBorder:SetVertexColor(1, 0.82, 0)
            row.text:SetText(entry.text or "Money")
            row.text:SetTextColor(1, 0.82, 0)
            row.count:SetText("")
            row.vendor:SetText("")
        else
            local r, g, b = QualityColor(entry.quality)
            row.iconBorder:SetVertexColor(r, g, b)
            row.text:SetText(entry.link or entry.name or "Loot")
            row.text:SetTextColor(r, g, b)
            if db.showStackCount and (entry.count or 1) > 1 then row.count:SetText(tostring(entry.count)) else row.count:SetText("") end
            local vendorValue = (tonumber(entry.vendorPrice) or 0) * (tonumber(entry.count) or 1)
            if db.showVendorValue ~= false and vendorValue > 0 then
                row.vendor:SetText(FormatMoney(vendorValue))
            else
                row.vendor:SetText("")
            end
        end
        row:Show()
    end

    HideUnusedRows(#entries + 1)
    rendering = false
end

local function ExistingEntry(key, entryType)
    for i, entry in ipairs(entries) do
        if entry.key == key and entry.type == entryType then return entry, i end
    end
end

function Loot:AddEntry(entry)
    local db = DB()
    if not Enabled() or not entry then return end

    entry.count = tonumber(entry.count) or 1
    entry.type = entry.type or "item"
    entry.key = entry.key or entry.link or entry.name or entry.type

    if db.combineDuplicates ~= false then
        local old, index = ExistingEntry(entry.key, entry.type)
        if old then
            if entry.type == "money" then
                old.price = (tonumber(old.price) or 0) + (tonumber(entry.price) or 0)
                old.text = FormatMoney(old.price)
                old.icon = MoneyIcon(old.price)
                old.count = 1
            else
                old.count = (old.count or 1) + (entry.count or 1)
                old.text = entry.text or old.text
                old.icon = entry.icon or old.icon
                old.link = entry.link or old.link
                old.quality = entry.quality or old.quality
                old.itemID = entry.itemID or old.itemID
                if (tonumber(entry.vendorPrice) or 0) > 0 then
                    old.vendorPrice = entry.vendorPrice
                end
            end
            tremove(entries, index)
            tinsert(entries, 1, old)
            ScheduleExpire(old)
            QueueRender()
            return
        end
    end

    tinsert(entries, 1, entry)
    while #entries > ClampNumber(db.maxItems, defaults.maxItems, 1, 12) do
        local dropped = tremove(entries)
        CancelExpire(dropped)
    end
    ScheduleExpire(entry)
    QueueRender()
end

function Loot:AddItem(link, count)
    if not link then return end
    local name, resolvedLink, quality, icon, vendorPrice = ItemInfo(link)
    self:AddEntry({
        type = "item",
        key = resolvedLink or link,
        link = resolvedLink or link,
        name = name,
        count = count or 1,
        quality = quality,
        icon = icon,
        itemID = LinkItemID(resolvedLink or link),
        vendorPrice = vendorPrice,
    })
end

local function RefreshItemInfo(itemID)
    itemID = tonumber(itemID)
    local changed = false
    for _, entry in ipairs(entries) do
        if entry.type == "item" and (not itemID or entry.itemID == itemID) then
            local name, link, quality, icon, vendorPrice = ItemInfo(entry.link)
            entry.name, entry.link, entry.quality, entry.icon = name, link, quality, icon
            entry.itemID = entry.itemID or LinkItemID(link)
            entry.vendorPrice = vendorPrice
            changed = true
        end
    end
    if changed then QueueRender() end
end

function Loot:AddMoney(amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    self:AddEntry({
        type = "money",
        key = "money",
        name = "Money",
        text = FormatMoney(amount),
        count = 1,
        quality = 1,
        icon = MoneyIcon(amount),
        price = amount,
    })
end

function Loot:Clear()
    for i = #entries, 1, -1 do
        CancelExpire(entries[i])
        entries[i] = nil
    end
    QueueRender()
end

function Loot:Test()
    self:AddEntry({ type = "item", key = "test1", name = "Some Epic Sword", link = "|cffa335ee|Hitem:18832:::::::::::::|h[Some Epic Sword]|h|r", quality = 4, icon = 135274, count = 1, vendorPrice = 12345 })
    self:AddEntry({ type = "item", key = "test2", name = "Metal Hat", link = "|cff0070dd|Hitem:16731:::::::::::::|h[Metal Hat]|h|r", quality = 3, icon = 136031, count = 2, vendorPrice = 6789 })
    if DB().showMoney then self:AddMoney(12345) end
end

function Loot:InvalidateRowStyles()
    local f = frame
    if not f or not f.rows then return end
    for _, row in ipairs(f.rows) do
        row._tfLootStyleKey = nil
    end
end

function Loot:RegisterMover()
    if not Enabled() or registerMoverQueued then return end
    registerMoverQueued = true
    After(0, function()
        registerMoverQueued = false
        if ns.Movers and ns.Movers.RegisterElement then
            local f = EnsureFrame()
            ns.Movers:RegisterElement("LootFrame", f, {
                label = "Loot Frame",
                overlayWidth = Loot:GetMoverWidth(),
                overlayHeight = Loot:GetMoverHeight(),
                fallbackPoint = { "CENTER", UIParent, "CENTER", 0, 180 },
                defaultPoint = { "CENTER", UIParent, "CENTER", 0, 180 },
                getChildren = function() return Loot:GetChildren() end,
                onApply = function() Loot:Layout() end,
            })
        end
    end)
end

function Loot:Refresh()
    DB()
    if not frame then
        if Enabled() then self:Init() end
        return
    end
    local active = Enabled()
    if initialized then SetEvents(active) end
    self:InvalidateRowStyles()
    self:Render()
    if active then self:RegisterMover() end
end

local function OnChatLoot(msg, author, language, channelString, receiver)
    if not OwnLootMessage(msg, receiver) then return end
    local link, pos = ExtractItemLink(msg)
    if not link then return end
    recentLootTime = GetTime and GetTime() or 0
    Loot:AddItem(link, ExtractStackCount(msg, pos))
end

local function AddMoneyFromEvent(amount, source)
    local db = DB()
    if db.showMoney == false then return end

    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local now = GetTime and GetTime() or 0
    if (now - (moneyCreditTime or 0)) > MONEY_RECONCILE_WINDOW then
        moneyChatCredit = 0
        moneyPlayerCredit = 0
    end
    moneyCreditTime = now
    recentLootTime = now

    -- Classic can report the same money pickup through CHAT_MSG_MONEY and
    -- PLAYER_MONEY, and PLAYER_MONEY may collapse several quickly-looted bodies
    -- into one aggregate delta. Reconcile amounts as source credits rather than
    -- comparing one exact amount/time pair. This preserves two legitimate
    -- bodies that happen to drop the same amount while still suppressing the
    -- counterpart event (including aggregate deltas).
    local displayAmount = amount
    if source == "chat" then
        local matched = math_min(displayAmount, moneyPlayerCredit)
        moneyPlayerCredit = moneyPlayerCredit - matched
        displayAmount = displayAmount - matched
        if displayAmount > 0 then moneyChatCredit = moneyChatCredit + displayAmount end
    else
        local matched = math_min(displayAmount, moneyChatCredit)
        moneyChatCredit = moneyChatCredit - matched
        displayAmount = displayAmount - matched
        if displayAmount > 0 then moneyPlayerCredit = moneyPlayerCredit + displayAmount end
    end

    if displayAmount > 0 then Loot:AddMoney(displayAmount) end
end

local function OnChatMoney(msg)
    local amount = ParseMoneyMessage(msg)
    if amount <= 0 then return end
    AddMoneyFromEvent(amount, "chat")
end

local function OnPlayerMoney()
    local money = GetMoney and GetMoney() or 0
    if lastMoney == nil then lastMoney = money; return end

    local delta = money - lastMoney
    lastMoney = money
    if delta <= 0 then return end

    local now = GetTime and GetTime() or 0
    if lootOpen or (now - (recentLootTime or 0)) <= 2 then
        AddMoneyFromEvent(delta, "money")
    end
end

SetEvents = function(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then return end
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("CHAT_MSG_MONEY")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("LOOT_CLOSED")
    eventFrame:RegisterEvent("PLAYER_MONEY")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function Loot:Init()
    if initialized then
        SetEvents(Enabled())
        return
    end
    DB()
    if not Enabled() then return end

    initialized = true
    EnsureFrame()
    lastMoney = GetMoney and GetMoney() or 0

    local function HandleLootEvent(event, ...)
        if not Enabled() then return end
        if event == "CHAT_MSG_LOOT" then
            OnChatLoot(...)
        elseif event == "CHAT_MSG_MONEY" then
            OnChatMoney(...)
        elseif event == "LOOT_OPENED" then
            lootOpen = true
            recentLootTime = GetTime and GetTime() or 0
        elseif event == "LOOT_CLOSED" then
            lootOpen = false
        elseif event == "PLAYER_MONEY" then
            OnPlayerMoney()
        elseif event == "PLAYER_ENTERING_WORLD" then
            lastMoney = GetMoney and GetMoney() or lastMoney or 0
            Loot:Refresh()
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            local itemID, success = ...
            if success ~= false then RefreshItemInfo(itemID) end
        end
    end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("LootFrame:" .. tostring(event), HandleLootEvent, event, ...)
        else
            HandleLootEvent(event, ...)
        end
    end)
    ns.RegisterCPUProfileTarget("Utility/LootFrame:Events", HandleLootEvent)
    SetEvents(true)

    self:Refresh()
end
