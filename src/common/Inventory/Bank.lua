local _, ns = ...

-- =============================================================================
-- TurboFace Bank.lua — marked-item deposits and live-bank mass withdrawal
--
-- InventoryManager owns the per-character Junk/Useful/Bank classification and
-- shared bag-addon button integration. This module owns bank-session events and
-- physical container transfers. It never reads Baganator's cached/offline data;
-- both Blizzard and Baganator ultimately resolve to live bag/slot coordinates.
-- =============================================================================

local BANK = {}
ns.Bank = BANK

local GetContainerNumSlots = ns.API.GetContainerNumSlots
local GetContainerItemID = ns.API.GetContainerItemID
local UseContainerItem = ns.API.UseContainerItem
local GetCursorInfo = GetCursorInfo
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown
local GetTime = GetTime
local CreateFrame = CreateFrame

local NUM_BAGS = _G.NUM_BAG_SLOTS or 4
local BANK_CONTAINER = _G.BANK_CONTAINER or -1
local NUM_BANK_BAGS = _G.NUM_BANKBAGSLOTS or 7
local FIRST_BANK_BAG = NUM_BAGS + 1
local TRANSFER_BATCH = 8
local TRANSFER_INTERVAL = 0.20
local MAX_TRANSFER_PASSES = 40

local bankOpen = false
local initialized = false
local eventFrame
local transferGeneration = 0
local activeTransfer
local hookedButtons = setmetatable({}, { __mode = "k" })
local lastWithdrawID, lastWithdrawAt

local function Enabled()
    return ns.Opt("invEnabled", true)
end

local function Delay(seconds, fn)
    if ns.After then ns.After(seconds, fn)
    elseif C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

local function ForEachPlayerSlot(fn)
    for bag = 0, NUM_BAGS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            fn(bag, slot)
        end
    end
end

local function ForEachModernCharacterBankSlot(fn)
    -- Mainline/Forever character banks are tab-backed C_Container bags rather
    -- than the Classic BANK_CONTAINER + purchased-bank-bag range. Prefer the
    -- live BankPanel data Blizzard already populated so TurboFace does not need
    -- to call C_Bank secret-argument APIs merely to discover visible storage.
    local panel = _G.BankFrame and _G.BankFrame.BankPanel
    local charType = _G.Enum and Enum.BankType and Enum.BankType.Character
    if not (panel and charType ~= nil) then return false end

    local data = panel.purchasedBankTabData
    if type(data) ~= "table" or #data == 0 then return false end

    local found = false
    for _, tabData in ipairs(data) do
        local bagID = tabData and tabData.ID
        local bankType = tabData and tabData.bankType
        if bagID ~= nil and (bankType == nil or bankType == charType) then
            local slots = GetContainerNumSlots(bagID) or 0
            if slots > 0 then
                found = true
                for slot = 1, slots do fn(bagID, slot) end
            end
        end
    end
    return found
end

local function ForEachBankSlot(fn)
    if ForEachModernCharacterBankSlot(fn) then return end

    -- Classic fallback.
    for slot = 1, (GetContainerNumSlots(BANK_CONTAINER) or 0) do
        fn(BANK_CONTAINER, slot)
    end
    for bag = FIRST_BANK_BAG, FIRST_BANK_BAG + NUM_BANK_BAGS - 1 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            fn(bag, slot)
        end
    end
end

local function CancelTransfer()
    transferGeneration = transferGeneration + 1
    activeTransfer = nil
end

local function ClearCompletedDepositMarks(state)
    if state.kind ~= "deposit" or not state.markedIDs then return false end

    local carried = {}
    ForEachPlayerSlot(function(bag, slot)
        local id = GetContainerItemID(bag, slot)
        if id then carried[id] = true end
    end)

    local cleared = false
    for id in pairs(state.markedIDs) do
        if not carried[id] and ns.Inv:ClearBankMark(id) then cleared = true end
    end
    return cleared
end

local function FinishTransfer(state, remaining)
    if activeTransfer ~= state then return end
    activeTransfer = nil
    local clearedMarks = ClearCompletedDepositMarks(state)
    if ns.Inv then ns.Inv:UpdateBags(clearedMarks) end

    if remaining and remaining > 0 then
        local action = state.kind == "deposit" and "deposit" or "withdraw"
        ns:Chat("Bank", "could not " .. action .. " " .. remaining
            .. " matching stack(s); check bag/bank space and locked items")
    elseif state.kind == "deposit" and state.issued > 0 then
        ns:Chat("Bank", "deposited Bank items and returned their state to Useful")
    elseif state.kind == "withdraw" then
        ns:Chat("Bank", "withdrew all available stacks of " .. state.link)
    end
end

local ProcessTransfer

local function StartTransfer(kind, itemID, link)
    if not (Enabled() and bankOpen) then return false end
    CancelTransfer()
    local state = {
        kind = kind,
        itemID = itemID,
        link = link or (itemID and ("item:" .. itemID)) or "the item",
        generation = transferGeneration,
        passes = 0,
        issued = 0,
        markedIDs = kind == "deposit" and {} or nil,
    }
    activeTransfer = state
    Delay(0, function() ProcessTransfer(state) end)
    return true
end

ProcessTransfer = function(state)
    if activeTransfer ~= state or state.generation ~= transferGeneration
        or not (Enabled() and bankOpen) then
        return
    end

    state.passes = state.passes + 1
    local matching, issued, locked = 0, 0, 0

    local function Visit(bag, slot)
        local id, _, _, _, isLocked = ns.Inv.SlotInfo(bag, slot)
        local matches
        if state.kind == "deposit" then
            matches = id and ns.Inv:IsBank(id)
            if matches then state.markedIDs[id] = true end
        else
            matches = id == state.itemID
        end
        if not matches then return end

        matching = matching + 1
        if isLocked then
            locked = locked + 1
        elseif issued < TRANSFER_BATCH and not GetCursorInfo() then
            UseContainerItem(bag, slot)
            issued = issued + 1
            state.issued = state.issued + 1
        end
    end

    if state.kind == "deposit" then
        ForEachPlayerSlot(Visit)
    else
        ForEachBankSlot(Visit)
    end

    if matching == 0 then
        FinishTransfer(state, 0)
        return
    end

    if state.passes >= MAX_TRANSFER_PASSES then
        FinishTransfer(state, matching)
        return
    end

    -- Container transfers and lock releases are asynchronous. Rescan physical
    -- slots rather than trusting a rendered bag-addon view or a speculative
    -- destination. This also merges into partial stacks when Blizzard can.
    if issued > 0 or locked > 0 then
        Delay(TRANSFER_INTERVAL, function() ProcessTransfer(state) end)
    else
        FinishTransfer(state, matching)
    end
end

function BANK:DepositMarked()
    return StartTransfer("deposit")
end

function BANK:WithdrawAll(itemID)
    if not itemID then return false end
    local _, link = ns.API.GetItemInfo(itemID)
    return StartTransfer("withdraw", itemID, link)
end

function BANK:HandleModifiedClick(bag, slot, mouseButton, modernCharacterBank)
    if mouseButton ~= "RightButton" or not ns.Opt("invBankWithdrawAll", true)
        or not (Enabled() and bankOpen)
        or not IsControlKeyDown() or IsShiftKeyDown() or IsAltKeyDown()
        or not (modernCharacterBank or ns.Inv.IsBankSlot(bag, slot)) then
        return false
    end

    local itemID = GetContainerItemID(bag, slot)
    if not itemID then return false end

    -- A Baganator button may run both its TurboFace PreClick hook and the
    -- underlying Blizzard modified-click path. Treat both deliveries as one
    -- hardware action.
    local now = GetTime and GetTime() or 0
    if itemID == lastWithdrawID and lastWithdrawAt and (now - lastWithdrawAt) < 0.20 then
        return true
    end
    lastWithdrawID, lastWithdrawAt = itemID, now
    self:WithdrawAll(itemID)
    return true
end

local function ModernCharacterBankLocation(button)
    if not button then return nil end
    local getBankTabID = button.GetBankTabID
    local getContainerSlotID = button.GetContainerSlotID
    local getBankType = button.GetBankType
    if type(getBankTabID) ~= "function" or type(getContainerSlotID) ~= "function"
        or type(getBankType) ~= "function" then
        return nil
    end

    local okType, bankType = pcall(getBankType, button)
    local charType = _G.Enum and Enum.BankType and Enum.BankType.Character
    if not okType or charType == nil or bankType ~= charType then return nil end

    local okBag, bag = pcall(getBankTabID, button)
    local okSlot, slot = pcall(getContainerSlotID, button)
    bag, slot = tonumber(bag), tonumber(slot)
    if not okBag or not okSlot or not bag or not slot or slot < 1 then return nil end
    if slot > (GetContainerNumSlots(bag) or 0) then return nil end
    return bag, slot
end

function BANK:TrackButton(button)
    if not button or not button.HookScript or hookedButtons[button] then return end
    local ok = pcall(button.HookScript, button, "PreClick", function(self, mouseButton)
        -- Forever/Mainline banks use BankPanelItemButtonMixin and identify
        -- storage with a bank-tab bag ID + container-slot ID. These buttons do
        -- not satisfy the Classic BankFrameItemN location rules.
        local bag, slot = ModernCharacterBankLocation(self)
        if bag ~= nil then
            BANK:HandleModifiedClick(bag, slot, mouseButton, true)
            return
        end

        bag, slot = ns.Inv.BagSlotFromFrame(self)
        BANK:HandleModifiedClick(bag, slot, mouseButton, false)
    end)
    if ok then hookedButtons[button] = true end
end

function BANK:UpdateBankButtons()
    if not (bankOpen and ns.Inv and ns.Inv.StyleButton) then return end

    -- Mainline/Forever: BankPanel owns a pooled set of BankPanelItemButtonMixin
    -- buttons. Track the live pool for Ctrl+Right-click withdrawal. Do not pass
    -- these through InventoryManager's Classic bank-slot validator; their tab
    -- IDs are modern C_Container bag IDs.
    local panel = _G.BankFrame and _G.BankFrame.BankPanel
    if panel and type(panel.EnumerateValidItems) == "function" then
        local ok, iterator = pcall(panel.EnumerateValidItems, panel)
        if ok and iterator then
            for button in iterator do
                if Enabled() then self:TrackButton(button) end
            end
        end
    end

    -- Classic fallback.
    local slots = GetContainerNumSlots(BANK_CONTAINER) or (_G.NUM_BANKGENERIC_SLOTS or 28)
    for i = 1, slots do
        local button = _G["BankFrameItem" .. i] or _G["BankFrameItemButton" .. i]
        if button then
            ns.Inv.StyleButton(button, BANK_CONTAINER, button:GetID() or i)
            if Enabled() then self:TrackButton(button) end
        end
    end
end

local modernBankMixinHooked = false

local function HookModernBankButtons()
    if modernBankMixinHooked then return end
    local mixin = _G.BankPanelItemButtonMixin
    if type(mixin) ~= "table" or type(mixin.Init) ~= "function" or not hooksecurefunc then return end
    hooksecurefunc(mixin, "Init", function(button)
        if bankOpen and Enabled() then BANK:TrackButton(button) end
    end)
    modernBankMixinHooked = true
end

local function HandleEvent(event)
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        HookModernBankButtons()
        BANK:UpdateBankButtons()
        -- Allow Blizzard's pooled bank buttons (and Baganator, when present) to
        -- settle before tracking the final live set and starting auto-deposit.
        Delay(0.05, function()
            if bankOpen then BANK:UpdateBankButtons() end
        end)
        Delay(0.20, function()
            -- A very fast Ctrl+Right Click may already have started a user-
            -- requested withdrawal. Never let the delayed automatic deposit
            -- replace that explicit action.
            if bankOpen and Enabled() and not activeTransfer then BANK:DepositMarked() end
        end)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        CancelTransfer()
    elseif bankOpen then
        BANK:UpdateBankButtons()
    end
end

local function SetEvents(active)
    if not eventFrame then return end
    eventFrame:UnregisterAllEvents()
    if not active then
        bankOpen = false
        CancelTransfer()
        return
    end
    eventFrame:RegisterEvent("BANKFRAME_OPENED")
    eventFrame:RegisterEvent("BANKFRAME_CLOSED")
    -- These two refresh events vary across Blizzard branches; the open/close
    -- events are required, while optional slot events are feature-detected by
    -- protected registration so a missing event cannot disable bank runtime.
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYERBANKSLOTS_CHANGED")
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYERBANKBAGSLOTS_CHANGED")
end

function BANK:Init()
    if not initialized then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event) HandleEvent(event) end)
        initialized = true
    end
    HookModernBankButtons()
    SetEvents(Enabled())
end

function BANK:Refresh()
    if not initialized then
        if Enabled() then self:Init() end
        return
    end
    SetEvents(Enabled())
    if Enabled() and bankOpen then self:UpdateBankButtons() end
end
