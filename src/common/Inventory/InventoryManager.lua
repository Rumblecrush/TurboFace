local _, ns = ...

-- =============================================================================
-- TurboFace InventoryManager.lua — item-state marking / junk selling / deleting
--
-- Reimplements the useful parts of the RXPGuides inventory manager as a
-- self-contained TurboFace module (no RXPGuides dependency). Provides:
--   * IsJunk(): gray (Poor) items are junk automatically; per-item overrides
--     (mark junk / protect as useful) live in TurboFaceCharDB.discardPile.
--   * One keybind cycles the hovered item through Junk, Useful, and Bank.
--     Bank.lua owns deposit/withdraw behavior; this file owns state and icons.
--   * Coin/banker overlay icons on marked items in Blizzard bags/bank.
--   * Auto-sell all junk when a merchant window opens (optional).
--   * GetNetWorth() = money + vendor value of bag junk (used by NetWorth.lua).
--   * DeleteCheapest(): destroys the single lowest-value junk item.
--   * DeleteHovered(): destroys the player-bag item currently under the mouse,
--     but only while the explicit invDeleteHoveredEnabled safety gate is on.
--     Both delete actions are wired to CLICK bindings in Bindings.xml so the
--     protected cursor-delete path runs from a hardware event.
--
-- Junk classification, auto-sell, and DeleteCheapest only target gray/marked
-- junk. DeleteHovered is the intentional exception: after its dedicated safety
-- checkbox is enabled it can destroy any carried bag item under the mouse.
-- Settings are flat TurboFaceDB keys (inv*) with defaults in Core/Defaults.lua.
-- discardPile is PER-CHARACTER (TurboFaceCharDB, SavedVariablesPerCharacter):
-- what counts as junk on a hunter is not junk on a shaman.
-- =============================================================================

local INV = {}
ns.Inv = INV

-- API boundary: container APIs resolve through Compat.lua (normalized so
-- GetContainerItemInfo always returns an info table)
local GetContainerNumSlots    = ns.API.GetContainerNumSlots
local GetContainerItemID      = ns.API.GetContainerItemID
local GetContainerItemInfoRaw = ns.API.GetContainerItemInfo
local PickupContainerItem     = ns.API.PickupContainerItem
local UseContainerItem        = ns.API.UseContainerItem

local GetItemInfo          = ns.API.GetItemInfo
local GetMoney             = GetMoney
local FormatMoney = ns.API.FormatMoney
local GetCursorInfo        = GetCursorInfo
local DeleteCursorItem     = DeleteCursorItem
local PickupMerchantItem  = PickupMerchantItem
local GetMouseFoci         = GetMouseFoci
local GetMouseFocus        = GetMouseFocus
local IsControlKeyDown     = IsControlKeyDown
local IsShiftKeyDown       = IsShiftKeyDown
local IsAltKeyDown         = IsAltKeyDown
local GetTime              = GetTime
local CreateFrame          = CreateFrame
local hooksecurefunc       = hooksecurefunc
local select, type         = select, type

local NUM_BAGS = _G.NUM_BAG_SLOTS or 4            -- backpack (0) + bags 1..NUM_BAGS
local MAX_CONTAINER_FRAMES = _G.NUM_CONTAINER_FRAMES or 13
local BANK_CONTAINER = _G.BANK_CONTAINER or -1
local NUM_BANK_BAGS = _G.NUM_BANKBAGSLOTS or 7
local FIRST_BANK_BAG = NUM_BAGS + 1
local BANKER_ICON = ns.BANK_ICON_TEXTURE

-- Items that must never be treated as junk regardless of quality/marking.
local EXCLUSIONS = {
    [6948]  = true,   -- Hearthstone
}

-- ---------------------------------------------------------------------------
-- DB access (flat inv* settings in TurboFaceDB; discardPile per-character)
-- ---------------------------------------------------------------------------
-- Per-character junk marks. TurboFaceCharDB is a SavedVariablesPerCharacter,
-- so each character keeps its own discardPile (true = force junk, false =
-- protect as useful, "bank" = auto-deposit at the character bank). Lazily
-- created; safe to call any time after login.
local function CharDB()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.discardPile) ~= "table" then TurboFaceCharDB.discardPile = {} end
    return TurboFaceCharDB
end

-- One-time cleanup: junk marks used to live account-wide in
-- TurboFaceDB.inventory.discardPile (2026-07 migration; decision: start clean
-- per character rather than seed alts with another character's marks).
local function PruneLegacyMarks()
    local db = TurboFaceDB
    if db and type(db.inventory) == "table" then
        db.inventory.discardPile = nil
        if next(db.inventory) == nil then db.inventory = nil end
    end
end


-- ---------------------------------------------------------------------------
-- Slot / junk helpers
-- ---------------------------------------------------------------------------
-- Returns id, count, quality, hasNoValue, isLocked for a bag slot (nil if empty).
local function SlotInfo(bag, slot)
    local id = GetContainerItemID(bag, slot)
    if not id then return nil end
    local count, quality, hasNoValue, isLocked = 1, nil, false, false
    if GetContainerItemInfoRaw then
        local info = GetContainerItemInfoRaw(bag, slot)
        if type(info) == "table" then
            count      = info.stackCount or 1
            quality    = info.quality
            hasNoValue = info.hasNoValue
            isLocked   = info.isLocked or false
        end
    end
    return id, count, quality, hasNoValue, isLocked
end

-- Is this item junk? Poor quality is junk by default; discardPile overrides win
-- (true = force junk, false = force useful/protected).
function INV:IsJunk(id, quality)
    if not id or EXCLUSIONS[id] then return false end
    local override = CharDB().discardPile[id]
    if override ~= nil then return override == true end
    if quality == nil then
        quality = select(3, GetItemInfo(id))
    end
    return quality == 0   -- Enum.ItemQuality.Poor
end

function INV:IsBank(id)
    return id ~= nil and CharDB().discardPile[id] == "bank"
end

local function ItemPrice(id)
    return (select(11, GetItemInfo(id))) or 0
end

-- ---------------------------------------------------------------------------
-- Net worth (money + vendor value of bag junk)
-- ---------------------------------------------------------------------------
local junkValueCache = 0
local junkValueDirty = true

function INV:InvalidateJunkValue()
    junkValueDirty = true
end

function INV:GetJunkValue()
    if not junkValueDirty then return junkValueCache end

    local total = 0
    for bag = 0, NUM_BAGS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id, count, quality = SlotInfo(bag, slot)
            if id and self:IsJunk(id, quality) then
                total = total + ItemPrice(id) * (count or 1)
            end
        end
    end
    junkValueCache = total
    junkValueDirty = false
    return total
end

function INV:GetNetWorth()
    return (GetMoney() or 0) + self:GetJunkValue()
end

-- ---------------------------------------------------------------------------
-- Hovered player-bag slot
-- ---------------------------------------------------------------------------
-- Keybinds need a stable way to resolve the bag item currently under the mouse.
-- Support Blizzard ContainerFrame buttons and bag addons such as Baganator, but
-- deliberately reject bank/equipment/storage locations: these actions are for
-- the player's carried inventory only (bags 0..NUM_BAGS).
local function IsPlayerBagSlot(bag, slot)
    bag, slot = tonumber(bag), tonumber(slot)
    if not bag or not slot then return false end
    if bag < 0 or bag > NUM_BAGS or slot < 1 then return false end
    local slots = GetContainerNumSlots(bag) or 0
    return slot <= slots
end

local function IsBankSlot(bag, slot)
    bag, slot = tonumber(bag), tonumber(slot)
    if not bag or not slot or slot < 1 then return false end
    if bag ~= BANK_CONTAINER and (bag < FIRST_BANK_BAG or bag >= FIRST_BANK_BAG + NUM_BANK_BAGS) then
        return false
    end
    return slot <= (GetContainerNumSlots(bag) or 0)
end

local function IsStorageSlot(bag, slot)
    return IsPlayerBagSlot(bag, slot) or IsBankSlot(bag, slot)
end

local function SafeMethod(frame, method)
    local fn = frame and frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, frame)
    if not ok then return nil end
    return a, b
end

local baganatorItemButtons = setmetatable({}, { __mode = "k" })

local function BagSlotFromItemLocation(location)
    if type(location) ~= "table" then return nil end

    -- Baganator's live buttons expose a plain item-location table in BGR.
    local bag, slot = location.bagID, location.slotIndex
    if IsStorageSlot(bag, slot) then return tonumber(bag), tonumber(slot) end

    -- Also accept Blizzard ItemLocationMixin-style objects.
    if type(location.IsBagAndSlot) == "function" then
        local okBag, isBag = pcall(location.IsBagAndSlot, location)
        if okBag and isBag and type(location.GetBagAndSlot) == "function" then
            local okLoc, locBag, locSlot = pcall(location.GetBagAndSlot, location)
            if okLoc and IsStorageSlot(locBag, locSlot) then
                return tonumber(locBag), tonumber(locSlot)
            end
        end
    end
end

local function BagSlotFromFrame(frame)
    local f = frame
    for _ = 1, 10 do
        if not f then break end

        -- Baganator live item buttons keep the authoritative bag/slot here.
        local bgr = f.BGR
        if type(bgr) == "table" then
            local bag, slot = BagSlotFromItemLocation(bgr.itemLocation)
            if bag ~= nil then return bag, slot end
        end

        -- Modern bag-button mixins, including Baganator live buttons.
        local bag = SafeMethod(f, "GetBagID")
        local slot = SafeMethod(f, "GetID")
        if IsStorageSlot(bag, slot) then return tonumber(bag), tonumber(slot) end

        -- ItemLocation-backed buttons when available.
        local location = SafeMethod(f, "GetItemLocation")
        local locBag, locSlot = BagSlotFromItemLocation(location)
        if locBag ~= nil then return locBag, locSlot end

        -- Classic's main bank-container buttons do not necessarily expose a
        -- GetBagID method or ContainerFrame parent. Their stable global name
        -- and button ID identify physical BANK_CONTAINER slots.
        local frameName = SafeMethod(f, "GetName")
        if type(frameName) == "string"
            and (frameName:match("^BankFrameItem%d+$")
                or frameName:match("^BankFrameItemButton%d+$")) then
            local bankSlot = SafeMethod(f, "GetID")
            if IsBankSlot(BANK_CONTAINER, bankSlot) then
                return BANK_CONTAINER, tonumber(bankSlot)
            end
        end

        -- Classic Blizzard ContainerFrame item buttons: slot is the button ID,
        -- bag is the parent ContainerFrame ID. Restrict by frame name so a
        -- random child/parent pair with numeric IDs can never be mistaken for a
        -- bag slot.
        local parent = SafeMethod(f, "GetParent")
        local parentName = parent and SafeMethod(parent, "GetName")
        if type(parentName) == "string" and parentName:match("^ContainerFrame%d+$") then
            local parentBag = SafeMethod(parent, "GetID")
            local childSlot = SafeMethod(f, "GetID")
            if IsStorageSlot(parentBag, childSlot) then
                return tonumber(parentBag), tonumber(childSlot)
            end
        end

        -- Baganator's Classic live buttons use parent:GetID() for the bag.
        -- Only accept this relaxed form when the button carries live BGR data;
        -- cached bank/alt-view buttons do not have a live itemLocation.
        if type(f.BGR) == "table" and parent then
            local parentBag = SafeMethod(parent, "GetID")
            local childSlot = SafeMethod(f, "GetID")
            if IsStorageSlot(parentBag, childSlot) then
                return tonumber(parentBag), tonumber(childSlot)
            end
        end

        f = parent
    end
end

local function HoveredBaganatorSlot()
    -- Buttons seen by TurboFace's Baganator corner widget are kept weakly so
    -- pooled frames can disappear naturally. This avoids depending on
    -- GetMouseFoci() through Baganator's nested/pool-reparented frame tree.
    for button in pairs(baganatorItemButtons) do
        if button and button.IsShown and button:IsShown()
            and button.IsMouseOver and button:IsMouseOver() then
            local bag, slot = BagSlotFromFrame(button)
            if IsPlayerBagSlot(bag, slot) then return bag, slot end
        end
    end

    -- Current Baganator versions also expose the visible view. Use it as a
    -- fallback so hover actions work even before the corner widget has touched
    -- every pooled button.
    local api = _G.Baganator and Baganator.API
    if api and type(api.GetView) == "function" then
        local ok, view = pcall(api.GetView)
        if ok and type(view) == "table" and type(view.itemButtons) == "table" then
            for _, button in pairs(view.itemButtons) do
                if button and button.IsShown and button:IsShown()
                    and button.IsMouseOver and button:IsMouseOver() then
                    baganatorItemButtons[button] = true
                    local bag, slot = BagSlotFromFrame(button)
                    if IsPlayerBagSlot(bag, slot) then return bag, slot end
                end
            end
        end
    end
end

local function HoveredBagSlot()
    local bag, slot = HoveredBaganatorSlot()
    if bag ~= nil then return bag, slot end

    if GetMouseFoci then
        -- GetMouseFoci is a vararg API on modern clients. Capture every focus
        -- instead of only the first return value. Some builds/addons may wrap
        -- those foci in a single array, so support both shapes.
        local foci = { GetMouseFoci() }
        if #foci == 1 and type(foci[1]) == "table" and not foci[1].GetParent
            and foci[1][1] ~= nil then
            foci = foci[1]
        end
        for i = 1, #foci do
            bag, slot = BagSlotFromFrame(foci[i])
            if IsPlayerBagSlot(bag, slot) then return bag, slot end
        end
    elseif GetMouseFocus then
        bag, slot = BagSlotFromFrame(GetMouseFocus())
        if IsPlayerBagSlot(bag, slot) then return bag, slot end
    end
end

INV.IsPlayerBagSlot = IsPlayerBagSlot
INV.IsBankSlot = IsBankSlot
INV.BagSlotFromFrame = BagSlotFromFrame
INV.SlotInfo = SlotInfo

-- ---------------------------------------------------------------------------
-- Marking
-- ---------------------------------------------------------------------------
local INVENTORY_MOUSE_SHORTCUTS = {
    ["CTRL-RIGHT"]           = { ctrl = true,  shift = false, alt = false },
    ["SHIFT-RIGHT"]          = { ctrl = false, shift = true,  alt = false },
    ["ALT-RIGHT"]            = { ctrl = false, shift = false, alt = true  },
    ["CTRL-SHIFT-RIGHT"]     = { ctrl = true,  shift = true,  alt = false },
    ["CTRL-ALT-RIGHT"]       = { ctrl = true,  shift = false, alt = true  },
    ["SHIFT-ALT-RIGHT"]      = { ctrl = false, shift = true,  alt = true  },
    ["CTRL-SHIFT-ALT-RIGHT"] = { ctrl = true,  shift = true,  alt = true  },
}

local function MouseShortcutMatches(settingKey, mouseButton)
    if mouseButton ~= "RightButton" then return false end
    local rule = INVENTORY_MOUSE_SHORTCUTS[ns.Opt(settingKey, "NONE")]
    if not rule then return false end
    return (not not IsControlKeyDown()) == rule.ctrl
       and (not not IsShiftKeyDown()) == rule.shift
       and (not not IsAltKeyDown()) == rule.alt
end

local function MarkMouseShortcutMatches(mouseButton)
    return MouseShortcutMatches("invMarkMouseShortcut", mouseButton)
end

local function DeleteMouseShortcutMatches(mouseButton)
    return ns.Opt("invDeleteHoveredEnabled", false)
       and MouseShortcutMatches("invDeleteHoveredMouseShortcut", mouseButton)
end

local lastToggleID, lastToggleKind, lastToggleAt

local function DuplicateToggle(id, kind)
    local now = GetTime and GetTime() or 0
    if id == lastToggleID and kind == lastToggleKind and lastToggleAt
        and (now - lastToggleAt) < 0.20 then
        return true
    end
    lastToggleID, lastToggleKind, lastToggleAt = id, kind, now
    return false
end

function INV:ToggleJunk(id)
    if not id then return end

    -- A Baganator button can pass through both its own script and Blizzard's
    -- modified-click handler. Suppress duplicate delivery from the same mouse
    -- click without affecting normal repeated use.
    if DuplicateToggle(id, "state") then return end

    local marks = CharDB().discardPile
    local current = marks[id]
    local nextState
    if current == "bank" then
        nextState = false
    elseif EXCLUSIONS[id] then
        -- Junk exclusions remain bankable; they simply skip the invalid Junk
        -- state in this item's cycle.
        nextState = "bank"
    elseif current == true then
        nextState = "bank"
    elseif current == false then
        nextState = true
    elseif self:IsJunk(id) then
        nextState = "bank"
    else
        nextState = true
    end
    marks[id] = nextState

    local _, link = GetItemInfo(id)
    link = link or ("item:" .. id)
    if nextState == true then
        ns:Chat("Junk", "marked " .. link .. " as |cffff5555JUNK|r")
    elseif nextState == "bank" then
        ns:Chat("Junk", "marked " .. link .. " as |cffffff00BANK|r")
    else
        ns:Chat("Junk", "marked " .. link .. " as |cff55ff55USEFUL|r")
    end
    self:UpdateBags(true)
    if ns.NW then ns.NW:Update() end
end

function INV:ClearBankMark(id)
    if id and CharDB().discardPile[id] == "bank" then
        CharDB().discardPile[id] = false
        return true
    end
    return false
end

function INV:ToggleHoveredJunk()
    if not ns.Opt("invEnabled", true) then return end
    local bag, slot = HoveredBagSlot()
    if bag == nil then
        ns:Chat("Junk", "hover a carried bag item before cycling Junk / Useful / Bank")
        return
    end
    local id = GetContainerItemID(bag, slot)
    if not id then return end
    self:ToggleJunk(id)
end

local function ToggleJunkAtSlot(bag, slot)
    if not (ns.Opt("invEnabled", true) and IsPlayerBagSlot(bag, slot)) then return end
    local id = GetContainerItemID(bag, slot)
    if id then INV:ToggleJunk(id) end
end

local DeleteBagSlot

local function HandleBagMouseShortcut(frame, mouseButton)
    local bag, slot = BagSlotFromFrame(frame)

    -- A live bank withdrawal owns Ctrl+Right Click before all configurable
    -- carried-bag shortcuts. Bank.lua verifies bank-open state and location.
    if ns.Bank and ns.Bank.HandleModifiedClick
        and ns.Bank:HandleModifiedClick(bag, slot, mouseButton) then
        return
    end

    if not IsPlayerBagSlot(bag, slot) then return end

    -- The destructive shortcut wins if a user accidentally assigns the same
    -- modifier combination to both actions. Never let one click both delete an
    -- item and toggle its junk state.
    if DeleteMouseShortcutMatches(mouseButton) then
        if bag ~= nil and DeleteBagSlot then DeleteBagSlot(bag, slot) end
        return
    end

    if not MarkMouseShortcutMatches(mouseButton) then return end
    if bag ~= nil then ToggleJunkAtSlot(bag, slot) end
end

function INV:ResetMarks()
    wipe(CharDB().discardPile)
    ns:Chat("Junk", "cleared this character's Junk/Useful/Bank marks (grays are still auto-junk)")
    self:UpdateBags(true)
    if ns.Bank and ns.Bank.UpdateBankButtons then ns.Bank:UpdateBankButtons() end
    if ns.NW then ns.NW:Update() end
end

-- ---------------------------------------------------------------------------
-- Selling
-- ---------------------------------------------------------------------------
local function MerchantSellTabOpen()
    return MerchantFrame and MerchantFrame:IsShown()
        and (MerchantFrame.selectedTab == nil or MerchantFrame.selectedTab == 1)
end

-- The server silently drops sell requests beyond roughly a dozen per batch,
-- so a single pass over a full bag of junk "sells" only part of it. Sell in
-- small batches with a delay, re-scanning the bags between passes (which also
-- retries anything the server dropped), until a pass finds nothing left.
local SELL_BATCH      = 8      -- sell requests per pass; stays below Classic's merchant burst limit
local SELL_INTERVAL   = 0.25   -- let Blizzard process each burst before issuing the next
local SELL_SETTLE      = 0.15   -- keep the sell phase busy until the final bag/money update can settle
local MAX_SELL_PASSES = 40     -- safety cap (~8s worst case)
local AUTO_SELL_RETRY_INTERVAL = 0.15
local MAX_AUTO_SELL_ATTEMPTS   = 30   -- ~4.5s for bag addons/merchant UI to settle
local sellRunning     = false
local autoSellPending = false
local autoSellGeneration = 0

local function Delay(sec, fn)
    if ns.After then ns.After(sec, fn)
    elseif C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

local function FinishSell(state)
    -- Keep sellRunning true through a short settle window. Grocery.lua treats
    -- this flag as the vendor phase barrier, so purchases cannot begin while
    -- the final BAG_UPDATE/money update from selling is still in flight.
    Delay(SELL_SETTLE, function()
        sellRunning = false
        local earned = (GetMoney() or 0) - state.before
        if earned > 0 then
            ns:Chat("Junk", "sold junk for " .. FormatMoney(earned))
        elseif state.verbose then
            if (state.blocked or 0) > 0 then
                ns:Chat("Junk", "WoW blocked the junk sell request")
            elseif (state.lastLocked or 0) > 0 then
                ns:Chat("Junk", "junk slots are still locked; close/reopen the merchant and try again")
            elseif (state.lastSellable or 0) > 0 then
                ns:Chat("Junk", "found sellable junk, but the merchant did not accept the sale request")
            else
                ns:Chat("Junk", "no sellable junk in your bags")
            end
        end
        if ns.NW then ns.NW:Update() end
    end)
end

local function BaganatorActive()
    return _G.Baganator ~= nil
end

-- Selling is always based on the physical player bag/slot, never on a rendered
-- item button. Blizzard bags use the normal UseContainerItem merchant path.
--
-- Baganator is handled with the cursor -> merchant path instead. This avoids
-- any interaction between Baganator's live/pool-backed item buttons and the
-- protected item-use path: pick up the physical container slot, then hand the
-- cursor item directly to the merchant. If the merchant does not consume it,
-- immediately return it to the original slot so TurboFace never leaves an item
-- stranded on the cursor.
--
-- Do NOT require GetItemInfo()'s vendor price here. Item data can be uncached
-- even while a bag addon can already render/classify the item. The container
-- info's hasNoValue flag is the cheap slot-level gate for vendor value.
local function SellBagSlot(bag, slot)
    if BaganatorActive() and PickupContainerItem and PickupMerchantItem then
        local picked = pcall(PickupContainerItem, bag, slot)
        if picked and GetCursorInfo() == "item" then
            local sold = pcall(PickupMerchantItem, 0)
            if sold and not GetCursorInfo() then return true end

            -- Sale rejected: put the exact item back where it came from, then
            -- fall through to the normal merchant-use path.
            if GetCursorInfo() == "item" then pcall(PickupContainerItem, bag, slot) end
            if GetCursorInfo() then ClearCursor() end
        end
    end

    if not UseContainerItem then return false end
    return pcall(UseContainerItem, bag, slot)
end

local function SellPass(state)
    state.passes = state.passes + 1

    -- Merchant closed mid-run (or feature toggled off): report what we got.
    if not ns.Opt("invEnabled", true) or not MerchantSellTabOpen() then
        FinishSell(state)
        return
    end

    -- Something on the cursor blocks UseContainerItem; retry shortly instead
    -- of aborting the whole run.
    if GetCursorInfo() then
        if state.passes < MAX_SELL_PASSES then
            Delay(SELL_INTERVAL, function() SellPass(state) end)
        else
            FinishSell(state)
        end
        return
    end

    -- Re-scan the bags fresh each pass: sold slots have emptied, and anything
    -- the server dropped last pass is still junk and gets retried. Only slots
    -- that CURRENTLY hold junk are sold, so a re-shuffled bag can never sell
    -- the wrong item.
    local soldThisPass, lockedThisPass = 0, 0
    local foundThisPass, sellableThisPass = 0, 0
    for bag = 0, NUM_BAGS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id, _, quality, hasNoValue, isLocked = SlotInfo(bag, slot)
            if id and INV:IsJunk(id, quality) then
                foundThisPass = foundThisPass + 1
                if not hasNoValue then
                    sellableThisPass = sellableThisPass + 1
                    if isLocked then
                        -- Bag addons can briefly rebuild/lock live slots while a
                        -- merchant opens. Never touch a locked slot; retry after
                        -- BAG_UPDATE settles instead of treating it as unsellable.
                        lockedThisPass = lockedThisPass + 1
                    elseif SellBagSlot(bag, slot) then
                        soldThisPass = soldThisPass + 1
                        if soldThisPass >= SELL_BATCH then break end
                    else
                        state.blocked = (state.blocked or 0) + 1
                    end
                end
            end
        end
        if soldThisPass >= SELL_BATCH then break end
    end
    state.sold = state.sold + soldThisPass
    state.lastFound = foundThisPass
    state.lastSellable = sellableThisPass
    state.lastLocked = lockedThisPass

    -- If a bag UI has slots temporarily locked, keep waiting even if this pass
    -- could not issue a sale. Otherwise, any attempted sales get a fresh rescan
    -- so server-dropped requests are retried until the bags are actually clean.
    if (soldThisPass > 0 or lockedThisPass > 0) and state.passes < MAX_SELL_PASSES then
        Delay(SELL_INTERVAL, function() SellPass(state) end)
    else
        FinishSell(state)
    end
end

function INV:SellJunk(verbose)
    if not ns.Opt("invEnabled", true) then return false end
    if not MerchantSellTabOpen() then
        if verbose then ns:Chat("Junk", "open a merchant to sell junk") end
        return false
    end
    -- Auto-sell + manual button cannot double-run. Treat an existing run as a
    -- successful start so the merchant-open retry loop does not keep polling.
    if sellRunning then return true end
    sellRunning = true
    SellPass({ before = GetMoney() or 0, sold = 0, blocked = 0, passes = 0, verbose = verbose })
    return true
end

-- Baganator can still be rebuilding/sorting its physical bag slots when
-- MERCHANT_SHOW fires. The old auto-sell path waited a single fixed delay and
-- then gave up forever if the merchant frame or bag state was not ready at
-- that exact instant. Manual "Sell Junk Now" worked because the player clicked
-- it after the UI had settled.
--
-- Use a short generation-scoped handshake instead: while this merchant session
-- remains open and Auto-sell is enabled, keep trying until SellJunk can start.
-- Once SellJunk starts, its own pass loop handles temporarily locked slots.
local function CancelPendingAutoSell()
    autoSellGeneration = autoSellGeneration + 1
    autoSellPending = false
end

local function BeginAutoSell()
    CancelPendingAutoSell()
    local generation = autoSellGeneration
    autoSellPending = true

    local function TryStart(attempt)
        if generation ~= autoSellGeneration then return end
        if not ns.Opt("invEnabled", true) or not ns.Opt("invAutoSell", true) then
            autoSellPending = false
            return
        end
        if INV:SellJunk(false) then
            autoSellPending = false
            return
        end

        if attempt < MAX_AUTO_SELL_ATTEMPTS then
            Delay(AUTO_SELL_RETRY_INTERVAL, function()
                TryStart(attempt + 1)
            end)
        else
            autoSellPending = false
        end
    end

    -- Give Blizzard's merchant frame one frame to finish showing. Baganator no
    -- longer needs a guessed 0.30s magic delay; the retry loop adapts to however
    -- long its bag rebuild actually takes on this client/session.
    Delay(0.05, function() TryStart(1) end)
end

-- Vendor-phase API used by Grocery.lua. These deliberately expose state rather
-- than coupling the modules together with callbacks: Grocery can wait for the
-- sell phase when both features are enabled, while either module remains fully
-- standalone when its counterpart is disabled.
function INV:IsVendorAutoSellEnabled()
    return ns.Opt("invEnabled", true) and ns.Opt("invAutoSell", true)
end

function INV:IsVendorSellBusy()
    return sellRunning or autoSellPending
end

function INV:EnsureVendorAutoSell()
    if not self:IsVendorAutoSellEnabled() then return false end
    BeginAutoSell()
    return true
end

-- ---------------------------------------------------------------------------
-- Deleting the cheapest junk item (keybind target)
-- ---------------------------------------------------------------------------
local function FindCheapestJunk()
    local bestBag, bestSlot, bestValue
    for bag = 0, NUM_BAGS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id, count, quality = SlotInfo(bag, slot)
            if id and INV:IsJunk(id, quality) then
                local value = ItemPrice(id) * (count or 1)
                if not bestValue or value < bestValue then
                    bestBag, bestSlot, bestValue = bag, slot, value
                end
            end
        end
    end
    return bestBag, bestSlot
end

function INV:DeleteCheapest()
    if not ns.Opt("invEnabled", true) then return end
    if GetCursorInfo() then return end
    local bag, slot = FindCheapestJunk()
    if not bag then
        ns:Chat("Junk", "no junk in your bags to delete")
        return
    end
    local id, count = SlotInfo(bag, slot)
    local _, link = GetItemInfo(id)
    PickupContainerItem(bag, slot)
    DeleteCursorItem()
    if GetCursorInfo() then ClearCursor() end
    local suffix = (count and count > 1) and ("x" .. count) or ""
    ns:Chat("Junk", "destroyed " .. (link or ("item:" .. tostring(id))) .. suffix)
    self:UpdateBags()
    if ns.NW then ns.NW:Update() end
end

-- Delete popups are a UI-layer confirmation around DeleteCursorItem(). For the
-- explicit TurboFace destructive hotkey, issue the confirmation call during the
-- same hardware event and dismiss any popup that Blizzard constructed along the
-- way. This behavior is intentionally scoped to this one keybind; normal manual
-- item deletion keeps Blizzard's confirmation flow untouched.
local DELETE_POPUP_TYPES = {
    DELETE_ITEM = true,
    DELETE_GOOD_ITEM = true,
    DELETE_QUEST_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

local function VisibleDeletePopup()
    local maxDialogs = tonumber(_G.STATICPOPUP_NUMDIALOGS) or 4
    for i = 1, maxDialogs do
        local dialog = _G["StaticPopup" .. i]
        if dialog and dialog.IsShown and dialog:IsShown() and DELETE_POPUP_TYPES[dialog.which] then
            return dialog
        end
    end
end

local function AcceptVisibleDeletePopup()
    local dialog = VisibleDeletePopup()
    if not dialog then return false end

    -- Rare/quest deletion dialogs gate Button1 behind a localized confirmation
    -- word. Fill it only for this TurboFace-triggered delete.
    local editBox = dialog.editBox
    if editBox and editBox.SetText then
        editBox:SetText(_G.DELETE_ITEM_CONFIRM_STRING or "DELETE")
    end

    local button = dialog.button1
    if not button and dialog.GetName then
        local name = dialog:GetName()
        if name then button = _G[name .. "Button1"] end
    end
    if button and button.Click then
        button:Click()
        return true
    end
    return false
end

local function HideVisibleDeletePopup()
    local dialog = VisibleDeletePopup()
    if dialog and dialog.Hide then dialog:Hide() end
end

DeleteBagSlot = function(bag, slot)
    if not (ns.Opt("invEnabled", true) and ns.Opt("invDeleteHoveredEnabled", false)) then return end
    if not IsPlayerBagSlot(bag, slot) then return end
    if GetCursorInfo() then
        ns:Chat("Junk", "clear your cursor before using Delete Hovered Item")
        return
    end

    local id, count = SlotInfo(bag, slot)
    if not id then return end
    local _, link = GetItemInfo(id)

    PickupContainerItem(bag, slot)
    local cursorType = GetCursorInfo()
    if cursorType ~= "item" then
        if GetCursorInfo() then ClearCursor() end
        return
    end

    -- First call destroys ordinary items or enters Blizzard's confirmation
    -- state. If the item remains on the cursor, the second call confirms while
    -- this binding's hardware event is still active. Some clients construct the
    -- static popup synchronously; accept that path as a fallback.
    DeleteCursorItem()
    if GetCursorInfo() then
        DeleteCursorItem()
    end
    if GetCursorInfo() then
        AcceptVisibleDeletePopup()
    end

    local deleted = not GetCursorInfo()
    if not deleted then
        -- Never strand the item on the cursor if the client rejects the action.
        HideVisibleDeletePopup()
        ClearCursor()
        ns:Chat("Junk", "WoW blocked deletion of " .. (link or ("item:" .. tostring(id))))
        return
    end

    -- A synchronously-created confirmation can linger for a frame even though
    -- the item is already gone. Remove only delete dialogs created by this path.
    HideVisibleDeletePopup()

    local suffix = (count and count > 1) and ("x" .. count) or ""
    ns:Chat("Junk", "destroyed " .. (link or ("item:" .. tostring(id))) .. suffix)
    INV:UpdateBags()
    if ns.NW then ns.NW:Update() end
end

function INV:DeleteHovered()
    if not (ns.Opt("invEnabled", true) and ns.Opt("invDeleteHoveredEnabled", false)) then return end

    local bag, slot = HoveredBagSlot()
    if bag == nil then
        ns:Chat("Junk", "hover a bag item before using Delete Hovered Item")
        return
    end
    DeleteBagSlot(bag, slot)
end

-- ---------------------------------------------------------------------------
-- Junk icon overlay on the default Blizzard bag buttons
-- ---------------------------------------------------------------------------
local function StyleButton(button, bag, slot)
    local id, _, quality = SlotInfo(bag, slot)
    local enabled = ns.Opt("invEnabled", true) and ns.Opt("invShowJunkIcon", true)
    local showBank = enabled and id and INV:IsBank(id)
    local showJunk = enabled and id and not showBank and INV:IsJunk(id, quality)
    if showJunk then
        if not button.TFJunkIcon then
            local t = button:CreateTexture(nil, "OVERLAY")
            ns.API.SetCoinIcon(t, "gold")
            t:SetSize(15, 15)
            t:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
            button.TFJunkIcon = t
        end
        button.TFJunkIcon:Show()
    elseif button.TFJunkIcon then
        button.TFJunkIcon:Hide()
    end

    if showBank then
        if not button.TFBankIcon then
            local t = button:CreateTexture(nil, "OVERLAY")
            t:SetTexture(BANKER_ICON)
            t:SetSize(15, 15)
            t:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
            button.TFBankIcon = t
        end
        button.TFBankIcon:Show()
    elseif button.TFBankIcon then
        button.TFBankIcon:Hide()
    end
end

INV.StyleButton = StyleButton

local function ClearTurboFaceItemOverlays(button)
    if not button then return end
    if button.TFJunkIcon then button.TFJunkIcon:Hide() end
    if button.TFBankIcon then button.TFBankIcon:Hide() end
end

local function StyleContainerItemButton(button)
    if not button then return end

    -- Retail/Forever Blizzard bags use pooled ContainerFrameItemButtonTemplate
    -- buttons. Combined bags cannot derive the physical bag from the parent,
    -- so always trust the button's own GetBagID()/GetID() pair when present.
    local bag = SafeMethod(button, "GetBagID")
    local slot = SafeMethod(button, "GetID")

    -- Mainline also creates four extended backpack item buttons while the
    -- account-security bonus slots are locked. Those buttons are pooled with
    -- real item buttons, so they can inherit a TurboFace overlay from a prior
    -- use. They are outside C_Container's current slot count and must be kept
    -- visually inert. Clearing before returning also handles any future pooled
    -- non-storage placeholder cleanly.
    if not IsStorageSlot(bag, slot) then
        ClearTurboFaceItemOverlays(button)
        return
    end

    StyleButton(button, tonumber(bag), tonumber(slot))
    if ns.Bank and ns.Bank.TrackButton then ns.Bank:TrackButton(button) end
end

local function UpdateContainer(frame)
    if not frame then return end

    -- Modern Mainline/Forever containers own an anonymous, pooled set of item
    -- buttons. This works for both ContainerFrameCombinedBags and individual
    -- bag windows, and avoids relying on Classic globals such as
    -- ContainerFrame1Item1.
    local pool = frame.itemButtonPool
    if pool and type(pool.EnumerateActive) == "function" then
        for button in pool:EnumerateActive() do
            StyleContainerItemButton(button)
        end
        return
    end

    -- Classic fallback: item buttons are stable globals named from the parent.
    if not frame.GetName then return end
    local name = frame:GetName()
    if not name then return end
    local bag = frame:GetID()
    local i = 1
    local button = _G[name .. "Item" .. i]
    while button do
        StyleButton(button, bag, button:GetID())
        if ns.Bank and ns.Bank.TrackButton then ns.Bank:TrackButton(button) end
        i = i + 1
        button = _G[name .. "Item" .. i]
    end
end

-- ---------------------------------------------------------------------------
-- Baganator compatibility
-- ---------------------------------------------------------------------------
-- Baganator owns its own item buttons, so Blizzard ContainerFrame overlays will
-- never appear there. Register TurboFace as a Baganator junk source and add a
-- dedicated top-right corner widget that uses the same INV:IsJunk() rules.
local baganatorJunkRegistered = false
local baganatorCornerRegistered = false
local baganatorBankCornerRegistered = false
local baganatorRuntimeActive = false
local baganatorMouseHooked = setmetatable({}, { __mode = "k" })

local function HookBaganatorMouseShortcuts(itemButton)
    if not (baganatorRuntimeActive and itemButton and itemButton.HookScript) then return end
    if baganatorMouseHooked[itemButton] then return end
    -- Baganator freezes some of its runtime tables/objects. Never write our
    -- bookkeeping onto Baganator-owned buttons; keep it in a TurboFace-owned
    -- weak table so pooled buttons can still be collected normally.
    local ok = pcall(itemButton.HookScript, itemButton, "PreClick", function(self, mouseButton)
        HandleBagMouseShortcut(self, mouseButton)
    end)
    if ok then
        baganatorMouseHooked[itemButton] = true
    end
end

local function TrackBaganatorItemButton(itemButton)
    if not itemButton then return end
    baganatorItemButtons[itemButton] = true
    HookBaganatorMouseShortcuts(itemButton)
    if ns.Bank and ns.Bank.TrackButton then ns.Bank:TrackButton(itemButton) end
end

local function ActivateBaganatorRuntime()
    if baganatorRuntimeActive then return end
    baganatorRuntimeActive = true
    -- Corner widgets may already have handed us pooled item buttons during the
    -- early plugin-registration phase. Attach the mouse shortcut now that the
    -- Inventory module is actually active.
    for button in pairs(baganatorItemButtons) do
        HookBaganatorMouseShortcuts(button)
        if ns.Bank and ns.Bank.TrackButton then ns.Bank:TrackButton(button) end
    end
end

local function RequestBaganatorRefresh()
    if _G.Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
        if Baganator.Constants and Baganator.Constants.RefreshReason then
            Baganator.API.RequestItemButtonsRefresh({ Baganator.Constants.RefreshReason.ItemWidgets })
        else
            Baganator.API.RequestItemButtonsRefresh()
        end
    end
end

local function RegisterBaganator()
    if not (_G.Baganator and Baganator.API) then return false end
    local api = Baganator.API
    local changed = false

    -- IMPORTANT: this provider registration must happen during addon loading,
    -- not only at PLAYER_LOGIN. Baganator builds its Junk Detection choices
    -- from registered providers; registering too late makes "TurboFace" vanish
    -- from that dropdown even though the callback itself is valid.
    if not baganatorJunkRegistered and type(api.RegisterJunkPlugin) == "function" then
        local ok = pcall(api.RegisterJunkPlugin, "TurboFace", "turboface", function(bagID, slotID, itemID, itemLink)
            if not ns.Opt("invEnabled", true) then return false end
            local id, _, quality = SlotInfo(bagID, slotID)
            id = id or itemID
            if not id and itemLink then
                id = tonumber(itemLink:match("item:(%d+)"))
            end
            return id and INV:IsJunk(id, quality) or false
        end)
        if ok then
            baganatorJunkRegistered = true
            changed = true
        end
    end

    if not baganatorCornerRegistered and type(api.RegisterCornerWidget) == "function" then
        -- Independent top-right coin. This does not depend on Baganator's
        -- selected Junk Detection plugin, so TurboFace marks still get a visual
        -- even if the user has Baganator configured for another junk provider.
        local ok = pcall(api.RegisterCornerWidget,
            "TurboFace Junk Coin", "turboface_junk_coin_v2",
            function(coin, details)
                if not (ns.Opt("invEnabled", true) and ns.Opt("invShowJunkIcon", true)) then return false end

                local itemButton = coin and coin.GetParent and coin:GetParent()
                local bag, slot = itemButton and BagSlotFromFrame(itemButton)

                local id, _, quality
                if bag ~= nil and slot ~= nil then
                    id, _, quality = SlotInfo(bag, slot)
                end
                if not id and details then
                    id = details.itemID
                    quality = details.quality
                    if not id and details.itemLink then
                        id = tonumber(details.itemLink:match("item:(%d+)"))
                    end
                end

                return id and INV:IsJunk(id, quality) or false
            end,
            function(itemButton)
                TrackBaganatorItemButton(itemButton)
                local t = itemButton:CreateTexture(nil, "OVERLAY")
                ns.API.SetCoinIcon(t, "gold")
                t:SetSize(15, 15)
                t.padding = 0
                return t
            end,
            { corner = "top_right", priority = 1 }, true
        )
        if ok then
            baganatorCornerRegistered = true
            changed = true
        end
    end


    if not baganatorBankCornerRegistered and type(api.RegisterCornerWidget) == "function" then
        local ok = pcall(api.RegisterCornerWidget,
            "TurboFace Bank", "turboface_bank_icon_v1",
            function(icon, details)
                if not (ns.Opt("invEnabled", true) and ns.Opt("invShowJunkIcon", true)) then return false end

                local itemButton = icon and icon.GetParent and icon:GetParent()
                local bag, slot = itemButton and BagSlotFromFrame(itemButton)
                local id
                if bag ~= nil and slot ~= nil then id = GetContainerItemID(bag, slot) end
                if not id and details then
                    id = details.itemID
                    if not id and details.itemLink then
                        id = tonumber(details.itemLink:match("item:(%d+)"))
                    end
                end
                return id and INV:IsBank(id) or false
            end,
            function(itemButton)
                TrackBaganatorItemButton(itemButton)
                local t = itemButton:CreateTexture(nil, "OVERLAY")
                t:SetTexture(BANKER_ICON)
                t:SetSize(15, 15)
                t:SetTexCoord(0, 1, 0, 1)
                t.padding = 0
                return t
            end,
            { corner = "top_right", priority = 2 }, true
        )
        if ok then
            baganatorBankCornerRegistered = true
            changed = true
        end
    end

    if changed and ns.Opt("invEnabled", true) then RequestBaganatorRefresh() end
    return baganatorJunkRegistered and baganatorBankCornerRegistered
end

-- Baganator plugin discovery happens before PLAYER_LOGIN on some versions/load
-- orders. OptionalDeps normally guarantees Baganator is already loaded before
-- TurboFace, so register immediately. Keep a tiny one-shot ADDON_LOADED bridge
-- as a fallback for unusual load-on-demand ordering. This is integration
-- metadata only; the Inventory event/hook runtime still waits for INV:Init().
local baganatorLoader
if not RegisterBaganator() then
    baganatorLoader = CreateFrame("Frame")
    baganatorLoader:RegisterEvent("ADDON_LOADED")
    baganatorLoader:RegisterEvent("PLAYER_LOGIN")
    baganatorLoader:SetScript("OnEvent", function(self, event, loadedAddon)
        if event == "ADDON_LOADED" and loadedAddon ~= "Baganator" then return end
        local registered = RegisterBaganator()
        -- PLAYER_LOGIN is the final fallback attempt. Do not leave an event
        -- listener alive forever if a future Baganator build removes/renames
        -- the junk-provider API; INV:Init() can still retry optional widgets.
        if registered or event == "PLAYER_LOGIN" then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end

function INV:UpdateBags(refreshBaganatorWidgets)
    self:InvalidateJunkValue()

    -- Retail/Forever combined bags are a dedicated container outside the
    -- ContainerFrame1..N sequence.
    local combined = _G.ContainerFrameCombinedBags
    if combined and combined.IsShown and combined:IsShown() then
        UpdateContainer(combined)
    end

    for i = 1, MAX_CONTAINER_FRAMES do
        local f = _G["ContainerFrame" .. i]
        if f and f.IsShown and f:IsShown() then UpdateContainer(f) end
    end

    if ns.Bank and ns.Bank.UpdateBankButtons then ns.Bank:UpdateBankButtons() end

    -- Ordinary BAG_UPDATE_DELAYED already drives Baganator's own live-bag
    -- refresh. RequestItemButtonsRefresh(ItemWidgets) is intentionally broader:
    -- Baganator marks every visible bag pending so third-party corner widgets
    -- can be reevaluated. Calling it again for every loot/bag mutation causes a
    -- redundant second widget pass. Only force that pass when TurboFace-only
    -- state changed without a bag-data change (junk mark/settings).
    if refreshBaganatorWidgets then RequestBaganatorRefresh() end
end

-- ---------------------------------------------------------------------------
-- Runtime activation: when Inventory is disabled at login, no bag hooks or
-- WoW events are installed. Hooks are one-way once enabled during a session,
-- but every callback remains preference-gated and a reload returns to a fully
-- dormant state. Pure helpers (IsJunk/GetNetWorth) remain available to Net Worth.
-- ---------------------------------------------------------------------------
local hooksInstalled = false
local initialized = false
local evt

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- Classic container refresh path.
    if _G.ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            if ns.Opt("invEnabled", true) then UpdateContainer(frame) end
        end)
    end

    -- Retail/Forever container refresh path. Modern Blizzard bags use pooled,
    -- anonymous ContainerFrameItemButtonTemplate buttons and call the mixin's
    -- UpdateJunkItem for each visible slot in both combined and separate modes.
    local modernMixin = _G.ContainerFrameItemButtonMixin
    if type(modernMixin) == "table" and type(modernMixin.UpdateJunkItem) == "function" then
        hooksecurefunc(modernMixin, "UpdateJunkItem", function(self)
            if ns.Opt("invEnabled", true) then
                StyleContainerItemButton(self)
            end
        end)
    end

    -- Blizzard's default keybinding UI does not reliably capture modified
    -- Button2 combinations. TurboFace therefore offers configurable fallback
    -- modifier+RightClick shortcuts and handles them only on actual bag buttons.
    if _G.ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, mouseButton)
            HandleBagMouseShortcut(self, mouseButton)
        end)
    elseif type(modernMixin) == "table" and type(modernMixin.OnModifiedClick) == "function" then
        hooksecurefunc(modernMixin, "OnModifiedClick", function(self, mouseButton)
            HandleBagMouseShortcut(self, mouseButton)
        end)
    end
end

-- Binding buttons exist regardless of activation so Bindings.xml always has
-- stable CLICK targets. Every public action is invEnabled-gated, making the
-- buttons inert while Junk & Inventory is disabled.
local deleteBtn = _G.TurboFaceDeleteJunk or CreateFrame("Button", "TurboFaceDeleteJunk", UIParent)
deleteBtn:SetScript("OnClick", function() INV:DeleteCheapest() end)

local markHoveredBtn = _G.TurboFaceMarkHoveredJunk or CreateFrame("Button", "TurboFaceMarkHoveredJunk", UIParent)
markHoveredBtn:SetScript("OnClick", function() INV:ToggleHoveredJunk() end)

local deleteHoveredBtn = _G.TurboFaceDeleteHoveredItem or CreateFrame("Button", "TurboFaceDeleteHoveredItem", UIParent)
deleteHoveredBtn:SetScript("OnClick", function() INV:DeleteHovered() end)

_G.BINDING_HEADER_TURBOFACE = "TurboFace"
_G["BINDING_NAME_CLICK TurboFaceDeleteJunk:LeftButton"] = "Delete Cheapest Junk Item"
_G["BINDING_NAME_CLICK TurboFaceMarkHoveredJunk:LeftButton"] = "Cycle Hovered Item: Junk / Useful / Bank"
_G["BINDING_NAME_CLICK TurboFaceDeleteHoveredItem:LeftButton"] = "Delete Hovered Bag Item"

local merchantShowFallbackInstalled = false

local function InstallMerchantShowFallback()
    if merchantShowFallbackInstalled then return end
    local frame = _G.MerchantFrame
    if not (frame and frame.HookScript) then return end
    merchantShowFallbackInstalled = true
    frame:HookScript("OnShow", function()
        if ns.Opt("invEnabled", true) and ns.Opt("invAutoSell", true) then
            BeginAutoSell()
        end
    end)
end

local function HandleInventoryEvent(event)
    if not ns.Opt("invEnabled", true) then return end
    if event == "MERCHANT_SHOW" then
        -- The event is the canonical auto-sell trigger. Install an OnShow
        -- fallback as well so future merchant opens still work even if another
        -- bag addon changes Blizzard's merchant-frame event plumbing.
        InstallMerchantShowFallback()
        if ns.Opt("invAutoSell", true) then BeginAutoSell() end
    elseif event == "MERCHANT_CLOSED" then
        CancelPendingAutoSell()
    else
        -- BAG_UPDATE_DELAYED already represents Blizzard's coalesced bag-data
        -- change. Registration/migration work belongs to Init, and Baganator
        -- independently processes the same bag change. Only refresh TurboFace's
        -- visible Blizzard-bag overlays here.
        INV:UpdateBags()
    end
end

local function EnsureEventRuntime()
    if evt then return true end
    evt = CreateFrame("Frame")
    evt:SetScript("OnEvent", function(_, event)
        if ns.CPUProfiler and ns.CPUProfiler.MeasureKillNoReturn and ns.CPUProfiler:IsKillTraceWindowActive() then
            ns.CPUProfiler:MeasureKillNoReturn("Inventory:" .. tostring(event), HandleInventoryEvent, event)
        else
            HandleInventoryEvent(event)
        end
    end)
    return true
end

local function SetEvents(active)
    if not evt then return end
    evt:UnregisterAllEvents()
    if not active then return end
    evt:RegisterEvent("PLAYER_ENTERING_WORLD")
    evt:RegisterEvent("MERCHANT_SHOW")
    evt:RegisterEvent("MERCHANT_CLOSED")
    evt:RegisterEvent("BAG_UPDATE_DELAYED")
end

function INV:Init()
    local active = ns.Opt("invEnabled", true)
    if initialized then
        SetEvents(active)
        if active then InstallMerchantShowFallback() end
        return
    end
    if not active then return end

    CharDB()
    PruneLegacyMarks()

    -- IMPORTANT: establish the merchant/event runtime BEFORE any optional bag
    -- addon integration. Previously `initialized` was set first and Baganator
    -- setup ran before `evt` existed. If any Baganator API/hook raised an
    -- error, Core.SafeCall caught it, but Inventory remained marked initialized
    -- forever with no MERCHANT_SHOW listener. Manual Sell Junk Now still worked
    -- because it calls SellJunk directly, which made the failure look like an
    -- auto-sell timing problem.
    EnsureEventRuntime()
    SetEvents(true)
    initialized = true

    -- These integrations are useful but non-critical. Isolate them individually
    -- so a third-party API change can never disable TurboFace's core vendor
    -- event path again.
    if ns.SafeCall then
        ns.SafeCall("Inventory:BagHooks", InstallHooks)
        ns.SafeCall("Inventory:BaganatorRegister", RegisterBaganator)
        ns.SafeCall("Inventory:BaganatorRuntime", ActivateBaganatorRuntime)
    else
        pcall(InstallHooks)
        pcall(RegisterBaganator)
        pcall(ActivateBaganatorRuntime)
    end

    InstallMerchantShowFallback()
    self:UpdateBags(true)
end

-- Public refresh (called from OptionsGUI when inventory settings change).
function INV:Refresh()
    local active = ns.Opt("invEnabled", true)
    if active and not initialized then
        self:Init()
        if ns.Bank and ns.Bank.Refresh then ns.Bank:Refresh() end
        return
    end
    SetEvents(active)
    CharDB()
    self:UpdateBags(true) -- settings changed: force TurboFace widget reevaluation
    if ns.Bank and ns.Bank.Refresh then ns.Bank:Refresh() end
    if ns.NW then ns.NW:Update() end
end

-- Manual sell entry point for the options button.
function INV:SellNow()
    self:SellJunk(true)
end

ns.RegisterCPUProfileTarget("Inventory/Manager:UpdateBags", INV.UpdateBags)
