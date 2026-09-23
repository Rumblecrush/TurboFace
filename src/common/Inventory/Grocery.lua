local _, ns = ...

-- =============================================================================
-- TurboFace Grocery List (Speedrun tab)
--
-- A standing shopping list for vendor consumables. You queue what you want
-- while you are out in the world; the next time you open a merchant that
-- actually stocks one of those items, TurboFace buys it for you and clears
-- that line from the list.
--
--   * A vendor-styled window (right-click a row to add one, Alt+right-click a
--     full stack, Shift+right-click to remove one, Ctrl+right-click to clear
--     the line). Open it from the floating launcher button, the Misc options
--     tab, or /tfgrocery.
--   * MERCHANT_SHOW scans the merchant inventory once, matches it against the
--     queue, and buys in batches. Hold Shift at the vendor to skip a run.
--   * Clearing contract (from the feature spec): once TurboFace has attempted
--     an item's order it clears that line, INCLUDING the "not enough money"
--     case, and says so in chat. Deliberate exceptions that KEEP the line
--     queued, because the player can fix them on the spot and re-opening the
--     vendor should just work:
--         - the vendor does not stock the item at all;
--         - there is no bag room for it;
--         - the vendor wants an alternate currency (extendedCost).
--
-- OWNERSHIP
--   Settings      flat grocery* keys in TurboFaceDB (defaults in Core/Config.lua).
--   Gate          groceryEnabled (dbKey gate, same style as invEnabled /
--                 hearthEnabled). Auto-buy additionally needs groceryAutoBuy.
--   Queue         TurboFaceCharDB.grocery = { [catalogKey] = count }. Ordinary
--                 rows use itemID keys; negative keys are reserved for synthetic
--                 catch-all food tiers. Per character on purpose.
--   Mover         "GroceryButton" -- the LAUNCHER BUTTON only. The list window
--                 is an ordinary draggable dialog and the auto-buy runtime is
--                 not mover-dependent, so turning Movers off costs you the
--                 button, not the feature (/tfgrocery still opens it).
--   Runtime       one event frame (MERCHANT_SHOW / MERCHANT_CLOSED, plus
--                 GET_ITEM_INFO_RECEIVED / PLAYER_LEVEL_UP only while the
--                 window is open). No
--                 ticker, no OnUpdate. Purchases are spaced with ns.After and
--                 are generation-scoped so MERCHANT_CLOSED cancels them.
--
-- Disabled means dormant: with groceryEnabled off nothing is constructed and
-- no events are registered.
-- =============================================================================

local G = {}
ns.Grocery = G

local CreateFrame   = CreateFrame
local GameTooltip   = GameTooltip
local UIParent      = UIParent
local GetMoney      = GetMoney
local GetCoinTextureString = ns.API.GetCoinTextureString
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown  = IsAltKeyDown
local math_abs      = math.abs
local math_ceil     = math.ceil
local math_floor    = math.floor
local math_min      = math.min
local math_max      = math.max
local tonumber, type, ipairs, pairs = tonumber, type, ipairs, pairs
local select, next = select, next
local tinsert, tsort = table.insert, table.sort
local wipe = wipe

-- Forever's authoritative merchant metadata is a C_MerchantFrame table while
-- Classic uses multiple-return globals. Compat normalizes both to the Classic
-- signature consumed below and fails closed when a value is unavailable.
local GetMerchantNumItems     = ns.API.GetMerchantNumItems
local GetMerchantItemInfo     = ns.API.GetMerchantItemInfo
local GetMerchantItemLink     = ns.API.GetMerchantItemLink
local GetMerchantItemID       = ns.API.GetMerchantItemID
local GetMerchantItemMaxStack = ns.API.GetMerchantItemMaxStack
local GetMerchantItemCostInfo = ns.API.GetMerchantItemCostInfo
local BuyMerchantItem         = ns.API.BuyMerchantItem

local GetItemInfo          = ns.API.GetItemInfo
local GetItemInfoInstant   = ns.API.GetItemInfoInstant
local GetItemIcon          = ns.API.GetItemIcon
local GetContainerNumSlots = ns.API.GetContainerNumSlots
local GetContainerItemID   = ns.API.GetContainerItemID
local GetContainerItemInfo = ns.API.GetContainerItemInfo

local Delay = ns.After

local NUM_BAGS = _G.NUM_BAG_SLOTS or 4

-- ---------------------------------------------------------------------------
-- CATALOG
--
-- The shopping catalog: what the window offers, not what any given vendor
-- stocks. Vendor availability is resolved live from the merchant inventory.
--
--   id       itemID used for both the merchant match and the tooltip.
--   icon     optional texture override. Existing entries may pin a fileID;
--            entries that omit it resolve through GetItemIcon / GetItemInfoInstant,
--            both of which can supply the icon before full GetItemInfo caching.
--   name     fallback label for that same uncached-first-login case; the real
--            localized name replaces it as soon as the client returns it.
--   category section grouping; the catalog is kept sorted by category then
--            minLevel so a plain row-major grid fill groups drinks together
--            and food together with no special-case layout code.
--   minLevel fallback required PLAYER level, shown on the button and used for
--            sort order before GetItemInfo has cached the real value. Zero means
--            no formal requirement (the vendor-food UI calls that Level 1).
--   stack    fallback stack size for Alt+right-click before the item caches.
--   perBuy   how many items one vendor purchase yields. Classic vendors sell
--            food/drink five at a time and the Ammo catalog in lots of 200, so
--            one right-click always means one real vendor purchase. This is the UI's default
--            step only: at an open merchant the live `quantity` return from
--            GetMerchantItemInfo is authoritative, so a vendor that disagrees
--            still buys correctly. Omit it (or set 1) for singly-sold goods.
--   foodTier  only on synthetic catch-all rows ("Level X Food"). These queue a
--            tier request rather than a concrete itemID; merchant scanning
--            resolves the request to one real Food entry sold by that vendor.
--
-- Adding an ordinary item is a one-line edit here. Catch-all tiers intentionally
-- live beside the catalog so their UI and queue semantics stay data-driven.
-- ---------------------------------------------------------------------------
local CATEGORY_ORDER = { "Drink", "Food", "Potion", "Ammo" }

local CATALOG = {
    -- Drinks: the standard vendor water progression, one tier per 10 levels.
    { id =  159, icon = 132794, name = "Refreshing Spring Water", category = "Drink", minLevel =  0, stack = 20, perBuy = 5 },
    { id = 1179, icon = 132815, name = "Ice Cold Milk",           category = "Drink", minLevel =  5, stack = 20, perBuy = 5 },
    { id = 1205, icon = 132796, name = "Melon Juice",             category = "Drink", minLevel = 15, stack = 20, perBuy = 5 },
    { id = 1708, icon = 132799, name = "Sweet Nectar",            category = "Drink", minLevel = 25, stack = 20, perBuy = 5 },
    { id = 1645, icon = 132789, name = "Moonberry Juice",         category = "Drink", minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8766, icon = 134712, name = "Morning Glory Dew",       category = "Drink", minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: catch-all tier requests. These are synthetic queue keys, not WoW
    -- itemIDs. At a merchant they resolve to the first concrete food in the
    -- matching player-use tier that the vendor sells. iconItem supplies only
    -- representative artwork; the purchased item can be any food type.
    -- Catch-all food tiers use the matching fruit-progression icon so they are
    -- visually distinct from the concrete food families while still reading
    -- naturally as food at a glance. iconItem only supplies artwork; merchant
    -- resolution still uses foodTier and never treats these as real item IDs.
    { id = -100006, name = "Level 1 Food",  category = "Food", minLevel =  0, stack = 20, perBuy = 5, foodTier =  1, iconItem = 4536 }, -- Shiny Red Apple
    { id = -100005, name = "Level 5 Food",  category = "Food", minLevel =  5, stack = 20, perBuy = 5, foodTier =  5, iconItem = 4537 }, -- Tel'Abim Banana
    { id = -100004, name = "Level 15 Food", category = "Food", minLevel = 15, stack = 20, perBuy = 5, foodTier = 15, iconItem = 4538 }, -- Snapvine Watermelon
    { id = -100003, name = "Level 25 Food", category = "Food", minLevel = 25, stack = 20, perBuy = 5, foodTier = 25, iconItem = 4539 }, -- Goldenbark Apple
    { id = -100002, name = "Level 35 Food", category = "Food", minLevel = 35, stack = 20, perBuy = 5, foodTier = 35, iconItem = 4602 }, -- Moon Harvest Pumpkin
    { id = -100001, name = "Level 45 Food", category = "Food", minLevel = 45, stack = 20, perBuy = 5, foodTier = 45, iconItem = 8953 }, -- Deep Fried Plantains

    -- Food: meat progression.
    { id =  117, icon = 133972, name = "Tough Jerky",             category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 2287, icon = 133974, name = "Haunch of Meat",          category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id = 3770, icon = 133970, name = "Mutton Chop",             category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 3771, icon = 133969, name = "Wild Hog Shank",         category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 4599, icon = 133970, name = "Cured Ham Steak",         category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8952, icon = 133971, name = "Roasted Quail",           category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: bread progression.
    { id = 4540, name = "Tough Hunk of Bread",                    category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 4541, name = "Freshly Baked Bread",                    category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id = 4542, name = "Moist Cornbread",                        category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 4544, name = "Mulgore Spice Bread",                    category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 4601, name = "Soft Banana Bread",                      category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8950, name = "Homemade Cherry Pie",                    category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: cheese progression (only the requested entries).
    { id = 2070, name = "Darnassian Bleu",                        category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 16167, name = "Versicolor Treat",                    category = "Food",  minLevel =   5, stack = 20, perBuy = 5 },
    { id = 1707, name = "Stormwind Brie",                       category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id =  414, name = "Dalaran Sharp",                          category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id =  422, name = "Dwarven Mild",                           category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 3927, name = "Fine Aged Cheddar",                      category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8932, name = "Alterac Swiss",                          category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: fruit progression (only the requested entries).
    { id = 4536, name = "Shiny Red Apple",                        category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 4537, name = "Tel'Abim Banana",                        category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id = 4538, name = "Snapvine Watermelon",                  category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 4539, name = "Goldenbark Apple",                       category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 4602, name = "Moon Harvest Pumpkin",                   category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8953, name = "Deep Fried Plantains",                   category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: fungus progression (only the requested entries).
    { id = 4604, name = "Forest Mushroom Cap",                    category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 4605, name = "Red-speckled Mushroom",                  category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id = 4606, name = "Spongy Morel",                           category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 4607, name = "Delicious Cave Mold",                  category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 4608, name = "Raw Black Truffle",                      category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8948, name = "Dried King Bolete",                      category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: fish progression.
    { id =  787, name = "Slitherskin Mackerel",                   category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 4592, name = "Longjaw Mud Snapper",                    category = "Food",  minLevel =  5, stack = 20, perBuy = 5 },
    { id = 4593, name = "Bristle Whisker Catfish",                category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 4594, name = "Rockscale Cod",                          category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 21552, name = "Striped Yellowtail",                    category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 8957, name = "Spinefin Halibut",                       category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Food: Night Elf / regional vendor foods requested for the catalog.
    { id = 16166, name = "Bean Soup",                             category = "Food",  minLevel =   0, stack = 20, perBuy = 5 },
    { id = 16170, name = "Steamed Mandu",                         category = "Food",  minLevel = 15, stack = 20, perBuy = 5 },
    { id = 16169, name = "Wild Ricecake",                         category = "Food",  minLevel = 25, stack = 20, perBuy = 5 },
    { id = 16168, name = "Heaven Peach",                          category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 21030, name = "Darnassus Kimchi Pie",                  category = "Food",  minLevel = 35, stack = 20, perBuy = 5 },
    { id = 21031, name = "Cabbage Kimchi",                        category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },
    { id = 21033, name = "Radish Kimchi",                         category = "Food",  minLevel = 45, stack = 20, perBuy = 5 },

    -- Potions: vendor-available healing and mana potions. These are sold
    -- singly and stack to five on Classic Era.
    { id =  858, name = "Lesser Healing Potion",                  category = "Potion", minLevel =  3, stack = 5, perBuy = 1 },
    { id = 2455, name = "Minor Mana Potion",                      category = "Potion", minLevel =  5, stack = 5, perBuy = 1 },
    { id =  929, name = "Healing Potion",                         category = "Potion", minLevel = 12, stack = 5, perBuy = 1 },
    { id = 3385, name = "Lesser Mana Potion",                     category = "Potion", minLevel = 14, stack = 5, perBuy = 1 },
    { id = 1710, name = "Greater Healing Potion",                 category = "Potion", minLevel = 21, stack = 5, perBuy = 1 },
    { id = 3827, name = "Mana Potion",                            category = "Potion", minLevel = 22, stack = 5, perBuy = 1 },
    { id = 6149, name = "Greater Mana Potion",                    category = "Potion", minLevel = 31, stack = 5, perBuy = 1 },
    { id = 3928, name = "Superior Healing Potion",                category = "Potion", minLevel = 35, stack = 5, perBuy = 1 },

    -- Ammo: arrows, shot and thrown weapons. One Grocery purchase is one
    -- vendor lot of 200 items for every entry in this category. Required
    -- levels are intentionally left to live GetItemInfo metadata; the fallback
    -- is zero so cold-cache clients do not invent requirements we do not own.
    { id =  2512, name = "Rough Arrow",             category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  2515, name = "Sharp Arrow",             category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3030, name = "Razor Arrow",             category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id = 11285, name = "Jagged Arrow",            category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },

    { id =  2516, name = "Light Shot",              category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  2519, name = "Heavy Shot",              category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3033, name = "Solid Shot",              category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id = 11284, name = "Accurate Slugs",          category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },

    { id =  3111, name = "Crude Throwing Axe",      category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3131, name = "Weighted Throwing Axe",   category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3135, name = "Sharp Throwing Axe",      category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3137, name = "Deadly Throwing Axe",     category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id = 15326, name = "Gleaming Throwing Axe",   category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },

    { id =  2947, name = "Small Throwing Knife",    category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  2946, name = "Balanced Throwing Knife", category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3107, name = "Keen Throwing Knife",     category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id =  3108, name = "Heavy Throwing Knife",    category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
    { id = 15327, name = "Wicked Throwing Knife",   category = "Ammo", minLevel = 0, stack = 200, perBuy = 200 },
}

-- Sorted once at load: category order first. Within Food, synthetic catch-all
-- tiers are always pinned ahead of concrete foods so the default first page is
-- the six Drinks followed by the six Level X Food rows. Concrete entries then
-- sort by required level as before.
do
    local rank = {}
    for i, name in ipairs(CATEGORY_ORDER) do rank[name] = i end
    tsort(CATALOG, function(a, b)
        local ra, rb = rank[a.category] or 99, rank[b.category] or 99
        if ra ~= rb then return ra < rb end

        if a.category == "Food" then
            local aSynthetic = a.foodTier ~= nil
            local bSynthetic = b.foodTier ~= nil
            if aSynthetic ~= bSynthetic then return aSynthetic end
            if aSynthetic and bSynthetic and a.foodTier ~= b.foodTier then
                return a.foodTier < b.foodTier
            end
        end

        if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
        return a.id < b.id
    end)
end

local catalogByID = {}
for _, entry in ipairs(CATALOG) do catalogByID[entry.id] = entry end

-- ---------------------------------------------------------------------------
-- Settings + queue storage
-- ---------------------------------------------------------------------------
-- Resolve TurboFaceDB on every read: a profile switch or import replaces the
-- table wholesale, so a cached pointer would go stale (ARCHITECTURE 3.5).


local function Enabled()
    return ns.Opt("groceryEnabled", true) == true
end

-- The launcher button is the only mover-dependent piece of this feature.
local function ButtonEnabled()
    if not Enabled() or ns.Opt("groceryShowButton", true) ~= true then return false end
    return ns.MoverDependentEnabled(true)
end

-- Per-character queue. Lazily created; safe to call any time after login.
local function Queue()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.grocery) ~= "table" then TurboFaceCharDB.grocery = {} end
    return TurboFaceCharDB.grocery
end

local function QueuedCount(itemID)
    return tonumber(Queue()[itemID]) or 0
end

local MAX_QUEUE = 500        -- ordinary consumables
local MAX_AMMO_QUEUE = 10000 -- 50 vendor lots / stacks of 200

-- How many items one vendor purchase yields (5 for food/drink, 200 for Ammo).
local function BuyUnit(entry)
    if type(entry) ~= "table" then entry = catalogByID[entry] end
    local unit = entry and tonumber(entry.perBuy) or 1
    return (unit and unit >= 1) and math_floor(unit) or 1
end

-- Stored counts are always whole purchases. You cannot buy three waters from a
-- vendor that sells them five at a time, so a queue of 3 would only ever be a
-- promise the merchant step could not keep -- it would silently round up to 5
-- and the chat summary would not match the list. Snapping on write keeps the
-- number on screen equal to the number that lands in your bags.
local function SetQueued(itemID, count)
    local entry = catalogByID[itemID]
    local unit = BuyUnit(entry or itemID)
    local cap = (entry and entry.category == "Ammo") and MAX_AMMO_QUEUE or MAX_QUEUE
    count = math_floor(tonumber(count) or 0)
    if count < 0 then count = 0 end
    if unit > 1 then count = math_floor(count / unit) * unit end
    if count > cap then count = math_floor(cap / unit) * unit end
    local q = Queue()
    q[itemID] = (count > 0) and count or nil
    return count
end

-- ---------------------------------------------------------------------------
-- Item info helpers
-- ---------------------------------------------------------------------------
local function IsFoodCatchAll(entry)
    return type(entry) == "table" and tonumber(entry.foodTier) ~= nil
end

-- Full GetItemInfo metadata is immutable for the life of the client session.
-- Cache only successful lookups: a cold-cache nil is deliberately not retained,
-- so GET_ITEM_INFO_RECEIVED can make the next redraw populate the entry.
local itemInfoCache = {}
local function CatalogItemInfo(entry)
    if IsFoodCatchAll(entry) then return nil end
    local id = entry and entry.id
    if not id then return nil end

    local cached = itemInfoCache[id]
    if cached then return cached end

    local name, link, quality, _, minLevel, _, _, stack, _, icon = GetItemInfo(id)
    if not name then return nil end

    cached = {
        name = name,
        link = link,
        quality = quality,
        minLevel = tonumber(minLevel) or tonumber(entry.minLevel) or 0,
        stack = tonumber(stack) or tonumber(entry.stack) or 20,
        icon = icon,
    }
    itemInfoCache[id] = cached
    return cached
end

local function ItemName(entry)
    if IsFoodCatchAll(entry) then return entry.name end
    local info = CatalogItemInfo(entry)
    return (info and info.name) or entry.name or ("item:" .. tostring(entry.id))
end

local function ItemLink(entry)
    if IsFoodCatchAll(entry) then return nil end
    local info = CatalogItemInfo(entry)
    return info and info.link or nil
end

local function ItemStack(entry)
    if IsFoodCatchAll(entry) then return tonumber(entry.stack) or 20 end
    local info = CatalogItemInfo(entry)
    return (info and info.stack) or tonumber(entry.stack) or 20
end

local function ItemLevelReq(entry)
    if IsFoodCatchAll(entry) then
        local tier = tonumber(entry.foodTier) or 1
        return tier == 1 and 0 or tier
    end
    local info = CatalogItemInfo(entry)
    return (info and info.minLevel) or tonumber(entry.minLevel) or 0
end

-- Vendor-food tiers are named for the minimum PLAYER level shown in the
-- Classic vendor-food chart. The first tier has no formal requirement, but is
-- presented as "Level 1 Food" in the Grocery UI.
local function FoodTier(entry)
    if not entry or entry.category ~= "Food" or IsFoodCatchAll(entry) then return nil end
    local req = ItemLevelReq(entry)
    if req <= 1 then return 1 end
    if req == 5 or req == 15 or req == 25 or req == 35 or req == 45 then return req end
    return nil
end

-- Observed vendor prices, per character.
--
-- A merchant's asking price is NOT derivable from the item's sell price: it
-- moves with your reputation discount with that vendor's faction (the reference
-- vendor asks 22c for five waters where the undiscounted price is 25c). So the
-- window never guesses -- it shows the real unit price last seen at a merchant
-- and shows nothing until it has seen one.
local function PriceStore()
    if type(TurboFaceCharDB) ~= "table" then TurboFaceCharDB = {} end
    if type(TurboFaceCharDB.groceryPrices) ~= "table" then TurboFaceCharDB.groceryPrices = {} end
    return TurboFaceCharDB.groceryPrices
end

local function RememberPrice(itemID, unitPrice)
    if not itemID or not unitPrice or unitPrice <= 0 then return end
    PriceStore()[itemID] = math_floor(unitPrice)
end

-- Unit price (per single item) last seen at a vendor, or nil if never seen.
local function KnownUnitPrice(itemID)
    local p = tonumber(PriceStore()[itemID])
    return (p and p > 0) and p or nil
end

-- Explicit catalog icons remain valid, but new entries do not need to carry a
-- fileID. The compatibility layer's icon/instant-info APIs resolve the texture
-- from the client item database without waiting for full GetItemInfo caching.
local function ItemIcon(entry)
    if entry.icon then return entry.icon end

    if not IsFoodCatchAll(entry) then
        local info = CatalogItemInfo(entry)
        if info and info.icon then return info.icon end
    end

    local iconID = IsFoodCatchAll(entry) and entry.iconItem or entry.id

    if GetItemIcon then
        local icon = GetItemIcon(iconID)
        if icon then return icon end
    end

    if GetItemInfoInstant then
        local icon = select(5, GetItemInfoInstant(iconID))
        if icon then return icon end
    end

    return select(10, GetItemInfo(iconID))
end

local function CarriedCount(itemID)
    local fn = ns.API.GetItemCount
    return (fn and fn(itemID)) or 0
end

local function ColoredName(entry)
    local name = ItemName(entry)
    if IsFoodCatchAll(entry) then return "|cffffffff" .. name .. "|r" end
    local info = CatalogItemInfo(entry)
    local quality = info and info.quality
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. name .. "|r" end
    return "|cffffffff" .. name .. "|r"
end

-- Bag capacity check. One pass over the carried bags returns both the free-slot
-- count and whether a partial stack of this item could absorb more, so a full
-- bag with a half-empty water stack still counts as "can receive".
local function CanReceive(itemID, maxStack)
    local partial = false
    for bag = 0, NUM_BAGS do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = GetContainerItemID(bag, slot)
            if not id then
                return true
            elseif id == itemID and not partial then
                local info = GetContainerItemInfo(bag, slot)
                local count = (type(info) == "table") and info.stackCount or nil
                if count and count < (maxStack or 20) then partial = true end
            end
        end
    end
    return partial
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
local function Chat(msg)
    ns:Chat("Grocery", msg)
end

local function Announce(msg)
    if ns.Opt("groceryChatSummary", true) ~= true then return end
    Chat(msg)
end

-- =============================================================================
-- AUTO-BUY
--
-- MERCHANT_SHOW can arrive before the merchant inventory is populated, so the
-- start is a short generation-scoped retry (same shape as InventoryManager's
-- auto-sell handshake) rather than one guessed delay. Once a run starts, each
-- BuyMerchantItem call is spaced so the server does not drop requests.
-- =============================================================================
local MERCHANT_RETRY_INTERVAL = 0.15
local MAX_MERCHANT_ATTEMPTS   = 20     -- ~3s for the merchant list to populate
local BUY_INTERVAL            = 0.15   -- seconds between purchase calls
local MAX_BUY_CALLS           = 60     -- safety cap on one merchant session

local generation = 0    -- bumped by MERCHANT_CLOSED / disable to void pending work
local session           -- active buy run, nil when idle
local merchantSessionOpen = false

local function CancelRun()
    generation = generation + 1
    session = nil
end

local function MerchantOpen()
    if merchantSessionOpen then return true end
    if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then return true end
    local ok, count = pcall(GetMerchantNumItems)
    return ok and tonumber(count) ~= nil and tonumber(count) > 0
end

-- itemID -> merchant index for everything this vendor stocks.
local function ScanMerchant()
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    if not count or count <= 0 then return nil end
    local map, order = {}, {}
    for index = 1, count do
        local id = GetMerchantItemID and GetMerchantItemID(index)
        local link
        if not id then
            link = GetMerchantItemLink(index)
            id = link and GetItemInfoInstant(link)
        end
        if id and not map[id] then
            map[id] = index
            order[#order + 1] = id
            -- Learn this vendor's real asking price for anything in the
            -- catalog, discount included, so the window can stop guessing.
            if catalogByID[id] then
                local _, _, price, quantity = GetMerchantItemInfo(index)
                price, quantity = tonumber(price), math_max(tonumber(quantity) or 1, 1)
                if price and price > 0 then RememberPrice(id, price / quantity) end
            end
        end
    end
    return map, order
end

-- Resolve a synthetic "Level X Food" line against this merchant. Normal tiers
-- use vendor-slot order as the arbitrary tiebreaker. The sole deliberate
-- preference is Longjaw Mud Snapper (4592) in the Level 5 tier: it is far
-- cheaper than the other food of the same player-use tier, so take it whenever
-- this vendor stocks it.
local function ResolveFoodCatchAll(entry, map, order)
    local tier = tonumber(entry and entry.foodTier)
    if not tier then return nil end

    if tier == 5 and map[4592] then
        return catalogByID[4592], map[4592]
    end

    for _, itemID in ipairs(order or {}) do
        local concrete = catalogByID[itemID]
        if concrete and FoodTier(concrete) == tier then
            return concrete, map[itemID]
        end
    end
    return nil
end

-- Queue entries in a stable order (catalog order first, then any stragglers).
local function QueuedEntries()
    local out = {}
    for itemID, count in pairs(Queue()) do
        if (tonumber(count) or 0) > 0 then
            tinsert(out, catalogByID[itemID] or { id = itemID, name = nil })
        end
    end
    tsort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Turn one queued line into a purchase job, or return nil plus a reason to
-- leave it queued. Everything is computed in BATCHES: a merchant sells `q`
-- items for `price`, so a batch is the indivisible purchase unit and the cost
-- arithmetic stays in integer copper.
local function BuildJob(entry, index, wanted, queueID)
    -- Only the FIRST FIVE returns of GetMerchantItemInfo are identical across
    -- every Classic client revision; the tail (isPurchasable/isUsable/
    -- extendedCost) has shifted positions between vanilla and the retail-derived
    -- 1.15.x FrameXML. Alternate-currency detection therefore uses
    -- GetMerchantItemCostInfo, which is what Blizzard's own MerchantFrame uses.
    local name, _, price, quantity, numAvailable, isPurchasable, _, hasExtendedCost =
        GetMerchantItemInfo(index)
    if not price then return nil, "unavailable" end

    local costItems = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
    if hasExtendedCost == true or (tonumber(costItems) or 0) > 0 then return nil, "currency" end
    if isPurchasable == false then return nil, "notpurchasable" end

    quantity = math_max(tonumber(quantity) or 1, 1)
    price = math_max(tonumber(price) or 0, 0)
    if price <= 0 then return nil, "unavailable" end

    -- maxStack is in ITEMS, numAvailable is in BATCHES, and BuyMerchantItem's
    -- amount is in ITEMS -- confirmed by Blizzard's own stack-split path, which
    -- compares min(numAvailable * quantity, maxStack).
    local maxStack = math_max(tonumber(GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)) or quantity, quantity)
    if not CanReceive(entry.id, maxStack) then return nil, "bagspace" end

    local needed = math_ceil(wanted / quantity)

    -- numAvailable is -1 for unlimited stock, otherwise a batch count.
    local available = tonumber(numAvailable)
    if available and available >= 0 then
        needed = math_min(needed, available)
        if needed <= 0 then return nil, "unavailable" end
    end

    return {
        entry     = entry,
        queueID   = queueID or entry.id,
        index     = index,
        name      = name or ItemName(entry),
        wanted    = wanted,
        price     = price,
        quantity  = quantity,
        perCall   = math_max(math_floor(maxStack / quantity), 1),
        remaining = needed,
        bought    = 0,
        spent     = 0,
        short     = false,
    }
end

local FinishRun, RunStep

-- One purchase call, then reschedule. Returns nothing; RunStep owns the loop.
function RunStep()
    if not session or session.gen ~= generation then return end

    if not MerchantOpen() then
        -- Vendor gone mid-order. Anything already delivered is credited against
        -- the line rather than clearing it, so the remainder rides along to the
        -- next vendor -- same reasoning as the bag-space and out-of-stock cases.
        local job = session.jobs[session.jobIndex]
        if job and job.bought > 0 then
            job.aborted = true
            SetQueued(job.queueID, math_max(job.wanted - job.bought, 0))
            session.report[#session.report + 1] = job
        end
        session.aborted = true
        FinishRun()
        return
    end

    local job = session.jobs[session.jobIndex]
    if not job then
        FinishRun()
        return
    end

    if job.remaining <= 0 or session.calls >= MAX_BUY_CALLS then
        -- The order for this line has been attempted: clear it, per the
        -- feature's clearing contract, and move on.
        SetQueued(job.queueID, 0)
        session.report[#session.report + 1] = job
        session.jobIndex = session.jobIndex + 1
        RunStep()
        return
    end

    local batches = math_min(job.perCall, job.remaining)
    -- GetMoney() lags a purchase by a server round-trip, so trust whichever is
    -- lower: the live value, or our own running tally of what we have committed.
    local money = math_min(GetMoney() or 0, session.money or 0)
    local affordable = math_floor(money / job.price)
    if affordable < batches then batches = affordable end

    if batches <= 0 then
        -- Out of money. Spec: clear the line anyway and tell the player.
        job.short = true
        job.remaining = 0
        RunStep()
        return
    end

    session.calls = session.calls + 1
    BuyMerchantItem(job.index, batches * job.quantity)

    local cost = batches * job.price
    session.money = (session.money or 0) - cost
    job.remaining = job.remaining - batches
    job.bought = job.bought + (batches * job.quantity)
    job.spent = job.spent + cost

    Delay(BUY_INTERVAL, RunStep)
end

function FinishRun()
    if not session then return end
    local report, aborted = session.report, session.aborted
    session = nil

    local totalSpent = 0
    for _, job in ipairs(report) do
        totalSpent = totalSpent + job.spent
        if job.aborted then
            Chat(("vendor closed early -- bought %s x%d of %d, the rest is still on your list.")
                :format(job.name, job.bought, job.wanted))
        elseif job.short then
            if job.bought > 0 then
                Chat(("bought %s x%d of %d -- not enough money for the rest. Order cleared.")
                    :format(job.name, job.bought, job.wanted))
            else
                Chat(("could not buy %s x%d -- not enough money. Order cleared.")
                    :format(job.name, job.wanted))
            end
        elseif job.bought > 0 then
            Announce(("bought %s x%d for %s."):format(job.name, job.bought, GetCoinTextureString(job.spent)))
        end
    end

    if aborted and #report == 0 then
        -- Vendor closed before anything was purchased; the queue is untouched.
        return
    end

    if #report > 1 and totalSpent > 0 then
        Announce(("order complete -- %s spent."):format(GetCoinTextureString(totalSpent)))
    end

    G:UpdateList()
    G:UpdateButton()
end

-- Build the run for this vendor. Returns true once a run has started (or once
-- there is provably nothing to do), false to ask for a retry.
local function TryStartRun()
    if not Enabled() or ns.Opt("groceryAutoBuy", true) ~= true then return true end
    if not ns.API.MerchantSurfaceAvailable() then return true end
    if not MerchantOpen() then return true end

    local queued = QueuedEntries()
    if #queued == 0 then return true end

    local map, order = ScanMerchant()
    if not map then return false end   -- merchant list not populated yet

    local jobs, notes = {}, {}
    for _, entry in ipairs(queued) do
        local purchaseEntry, index
        if IsFoodCatchAll(entry) then
            purchaseEntry, index = ResolveFoodCatchAll(entry, map, order)
        else
            purchaseEntry, index = entry, map[entry.id]
        end

        if purchaseEntry and index then
            local job, reason = BuildJob(purchaseEntry, index, QueuedCount(entry.id), entry.id)
            if job then
                jobs[#jobs + 1] = job
            elseif reason == "bagspace" then
                notes[#notes + 1] = ("no bag room for %s -- %s is still on your list.")
                    :format(ItemName(purchaseEntry), ItemName(entry))
            elseif reason == "currency" then
                notes[#notes + 1] = ("%s needs an alternate currency here -- %s is still on your list.")
                    :format(ItemName(purchaseEntry), ItemName(entry))
            elseif reason == "notpurchasable" then
                notes[#notes + 1] = ("%s is not purchasable right now -- %s is still on your list.")
                    :format(ItemName(purchaseEntry), ItemName(entry))
            end
        end
    end

    for _, note in ipairs(notes) do Chat(note) end
    if #jobs == 0 then return true end

    session = { gen = generation, jobs = jobs, jobIndex = 1, calls = 0, report = {}, money = GetMoney() or 0 }
    RunStep()
    return true
end

local function BeginAutoBuy()
    CancelRun()
    local gen = generation

    local function Attempt(n)
        if gen ~= generation then return end
        if TryStartRun() then return end
        if n < MAX_MERCHANT_ATTEMPTS then
            Delay(MERCHANT_RETRY_INTERVAL, function() Attempt(n + 1) end)
        end
    end

    local function StartBuying()
        if gen ~= generation or not MerchantOpen() then return end
        Delay(0.05, function() Attempt(1) end)
    end

    -- Vendor ordering contract:
    --   1) If Inventory auto-sell is enabled, make sure its sell handshake is
    --      running and wait until ALL sell passes + the final settle window end.
    --   2) Only then start Grocery purchases.
    -- If Inventory or auto-sell is disabled, there is no barrier and Grocery
    -- remains a completely standalone module.
    local inv = ns.Inv
    if inv and inv.IsVendorAutoSellEnabled and inv:IsVendorAutoSellEnabled() then
        if inv.EnsureVendorAutoSell then inv:EnsureVendorAutoSell() end

        local function WaitForSell()
            if gen ~= generation or not MerchantOpen() then return end
            if inv.IsVendorSellBusy and inv:IsVendorSellBusy() then
                Delay(0.05, WaitForSell)
                return
            end
            StartBuying()
        end

        Delay(0.05, WaitForSell)
    else
        StartBuying()
    end
end

-- Manual trigger (options button / slash), so the player can re-run an order
-- after making bag room without closing and reopening the vendor.
function G:BuyNow()
    if not Enabled() then
        Chat("the Grocery List is disabled in the Misc options.")
        return
    end
    if not MerchantOpen() then
        Chat("open a merchant first.")
        return
    end
    if next(Queue()) == nil then
        Chat("your grocery list is empty.")
        return
    end
    -- Manual Grocery runs obey the same sell-before-buy barrier as automatic
    -- merchant opens. With auto-sell disabled, BeginAutoBuy falls straight
    -- through to buying.
    BeginAutoBuy()
end

-- =============================================================================
-- LIST WINDOW
--
-- Built on Blizzard's frame templates where Forever actually exposes them.
-- The window and inset use native panel templates, while item cells use a
-- small TurboFace-owned button assembled from stable Blizzard texture paths.
-- Forever does not expose ItemButtonTemplate as an inheritable XML node.
--
--   ButtonFrameTemplate   the window: title bar, close button, border art, Bg,
--                         TopTileStreaks and the Inset. Set up with the
--                         canonical HidePortrait + HideButtonBar + SetTitle
--                         calls. The portrait is hidden -- this is a shopping
--                         list, not an NPC panel, so the top-left circle has
--                         nothing to show and would just be a hole.
--   InsetFrameTemplate    the recessed wells behind the item grid and behind
--                         the shopping list rows.
--   Grocery item button   a plain Button with owned icon/count/border regions
--                         and Blizzard's stable quick-slot textures.
--
-- IMPORTANT: no SetAtlas anywhere. Retail atlases such as "bags-item-slot64" do
-- not exist on Classic Era -- Baganator ships its own texture for that reason.
-- Everything here is a known panel template or a plain texture path.
-- =============================================================================
local GRID_COLS, GRID_ROWS = 2, 6
local PER_PAGE = GRID_COLS * GRID_ROWS
local CELL_W, CELL_H = 170, 44
local CELL_PAD_X, CELL_PAD_Y = 8, 6
local GRID_INSET_L = 10
local LIST_W = (GRID_COLS * CELL_W) + CELL_PAD_X + 40
local LIST_H = (GRID_ROWS * (CELL_H + CELL_PAD_Y)) + 118
local QUEUE_W = 200

local listFrame, gridInset, listCells, pageText, prevBtn, nextBtn
local queuePanel, queueInset, queueRows, queueTotal, queueTab
local filterButtons = {}
local currentPage = 1
local launcher

-- Match Blizzard panel feedback: the launcher uses the same additive checked
-- highlight as the backpack/bag buttons, while the window uses the Quest Log
-- open/close sound kits. The kits themselves live in Core/Config.lua's shared table
-- so every TurboFace surface draws from one mapping.
local function SetLauncherOpenState(open)
    if not launcher or not launcher.openGlow then return end
    if open == true then
        launcher.openGlow:Show()
    else
        launcher.openGlow:Hide()
    end
end

local function PlayWindowSound(open)
    ns:PlayUISound(open and "windowOpen" or "windowClose")
end

local FILTER_OPTIONS = {
    Drink  = "groceryFilterDrink",
    Food   = "groceryFilterFood",
    Potion = "groceryFilterPotion",
    Ammo   = "groceryFilterAmmo",
}

local visibleCatalogScratch = {}

local function CatalogEntryVisible(entry, showDrink, showFood, showPotion, showAmmo, usableOnly, playerLevel)
    local category = entry.category
    if category == "Drink" and not showDrink then return false end
    if category == "Food" and not showFood then return false end
    if category == "Potion" and not showPotion then return false end
    if category == "Ammo" and not showAmmo then return false end

    if usableOnly then
        local req = ItemLevelReq(entry)
        if playerLevel and playerLevel > 0 and req > playerLevel then return false end
    end

    return true
end

local function VisibleCatalog()
    wipe(visibleCatalogScratch)

    -- These settings and the player level are invariant across one catalog
    -- build. Read them once rather than once per entry, and reuse the scratch
    -- list because callers consume it synchronously and never retain it.
    local showDrink = ns.Opt(FILTER_OPTIONS.Drink, true) == true
    local showFood = ns.Opt(FILTER_OPTIONS.Food, true) == true
    local showPotion = ns.Opt(FILTER_OPTIONS.Potion, true) == true
    local showAmmo = ns.Opt(FILTER_OPTIONS.Ammo, true) == true
    local usableOnly = ns.Opt("groceryFilterUsable", false) == true
    local playerLevel = usableOnly and UnitLevel and UnitLevel("player") or 0

    for _, entry in ipairs(CATALOG) do
        if CatalogEntryVisible(entry, showDrink, showFood, showPotion, showAmmo, usableOnly, playerLevel) then
            tinsert(visibleCatalogScratch, entry)
        end
    end
    return visibleCatalogScratch
end

local function TotalPages(visible)
    local count = visible and #visible or #VisibleCatalog()
    return math_max(math_ceil(count / PER_PAGE), 1)
end

-- ---------------------------------------------------------------------------
-- ButtonFrameTemplate corrections
--
-- Measured from a live 1.15.9 frame (388x418, scale 1.0) via /tfgrocery frames.
-- Two separate defects appear once the portrait is hidden:
--
-- 1. UNPAINTED STRIPS. TitleBg covers y -3..-20 and Bg starts at y -21, so the
--    frame paints nothing across y 0..-3 (above the title) and leaves a 1px
--    seam at y -20..-21. Both sit inside the top border art, whose centre is
--    transparent, so the world shows through. Fixed by growing TitleBg to span
--    0..-21 exactly, meeting Bg with no seam and no strip above it. Its height
--    is set explicitly because the template gives it only TOPLEFT/TOPRIGHT.
--
-- 2. DOUBLE-DRAWN BORDER. The corners are 33px tall but TopBorder is only 28,
--    so the inner edge steps 5px at BOTH junctions (x=27 and x=355). The right
--    one is almost entirely hidden behind the CloseButton, which is why only
--    the left break is obvious. The left/right geometry is asymmetric too --
--    LeftBorder is 16 wide against RightBorder's 10, giving corner overhangs of
--    17px and 24px -- so this is leftover portrait-layout art, not a symmetric
--    frame. This build also has a NineSlice spanning the whole frame, so the
--    border is drawn twice and the seam is where the two disagree.
--
--    When NineSlice has regions it is the real border and the legacy textures
--    are hidden. Baganator makes the same test before touching those textures.
--    Overridable with /tfgrocery border if the detection is wrong on a build.
-- ---------------------------------------------------------------------------
local LEGACY_BORDER_KEYS = {
    "TopLeftCorner", "TopBorder", "TopRightCorner",
    "LeftBorder", "RightBorder",
    "BotLeftCorner", "BottomBorder", "BotRightCorner",
}

local skinnedFrames = {}

local function NineSliceActive(frame)
    -- Deliberately NOT named `ns`: that is the addon namespace everywhere
    -- else in this file.
    local nineSlice = frame.NineSlice
    if not nineSlice or not nineSlice.GetRegions then return false end
    return nineSlice:GetRegions() ~= nil
end

-- TopLeftCorner and TopRightCorner are two sprites in the SAME sheet
-- (fileID 374156, 128x128), but their regions are not the same size. Measured
-- on 1.15.9 via /tfgrocery art:
--
--     TopLeftCorner   texcoords span 0.2500 -> 32x32 of source, drawn at 33x33
--     TopRightCorner  texcoords span 0.2578 -> 33x33 of source, drawn at 33x33
--
-- The template sizes BOTH at 33x33, so the left corner is stretched by about
-- 3%. The border's inner edge inside that art then lands roughly a pixel below
-- where the straight TopBorder strip puts it, and that step is the visible
-- break just in from the left end. It is a size error, not a position error,
-- which is why moving the corner never fixed it.
--
-- The right corner draws at 1:1, so it is used as the reference rather than
-- hardcoding 32: pixels-per-texcoord-unit is derived from it and the left
-- corner is resized to whatever its own texcoord region actually covers. That
-- stays correct if Blizzard repacks the sheet.
local function CorrectCornerScale(frame)
    local tl, tr = frame.TopLeftCorner, frame.TopRightCorner
    if not (tl and tr and tl.GetTexCoord and tr.GetTexCoord) then return end
    if not (tl.GetTexture and tr.GetTexture) then return end
    -- Only meaningful when both sprites come from the same sheet.
    if tl:GetTexture() ~= tr:GetTexture() then return end

    -- GetTexCoord returns ULx, ULy, LLx, LLy, URx, URy, LRx, LRy.
    local lULx, lULy, _, lLLy, lURx = tl:GetTexCoord()
    local rULx, rULy, _, rLLy, rURx = tr:GetTexCoord()
    if not (lULx and rULx) then return end

    local lU, lV = lURx - lULx, lLLy - lULy
    local rU, rV = rURx - rULx, rLLy - rULy
    if lU <= 0 or lV <= 0 or rU <= 0 or rV <= 0 then return end

    local w = math_floor(((lU * (tr:GetWidth() / rU))) + 0.5)
    local h = math_floor(((lV * (tr:GetHeight() / rV))) + 0.5)
    if w <= 0 or h <= 0 then return end

    -- Sanity clamp: only a pixel or two of correction is expected. A larger
    -- delta means the shared-sheet assumption does not hold on this build, so
    -- leave the frame untouched rather than distort it.
    if math_abs(w - tl:GetWidth()) <= 3 and math_abs(h - tl:GetHeight()) <= 3 then
        tl:SetSize(w, h)
    end
end

-- Returns true when the legacy corner/edge textures are the ones drawing.
local function ApplyBorderMode(frame)
    local mode = ns.Opt("groceryBorderMode", "auto")
    local useLegacy
    if mode == "legacy" then
        useLegacy = true
    elseif mode == "nineslice" then
        useLegacy = false
    else
        useLegacy = not NineSliceActive(frame)
    end

    for _, key in ipairs(LEGACY_BORDER_KEYS) do
        local r = frame[key]
        if r and r.SetShown then r:SetShown(useLegacy) end
    end

    if useLegacy then CorrectCornerScale(frame) end
    return useLegacy
end

local function ApplyBlizzardFrameFixes(frame)
    skinnedFrames[frame] = true

    -- Bg: Baganator re-anchors this on every ButtonFrame it skins on Classic,
    -- i.e. the template default is wrong here rather than merely different.
    if frame.Bg then
        frame.Bg:SetPoint("TOPLEFT", 2, -21)
        frame.Bg:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if frame.TopTileStreaks then
        frame.TopTileStreaks:SetPoint("TOPLEFT", 2, -21)
    end

    -- Close the two unpainted strips by making the title fill 0..-21 exactly.
    if frame.TitleBg then
        frame.TitleBg:SetPoint("TOPLEFT", 2, 0)
        frame.TitleBg:SetPoint("TOPRIGHT", -25, 0)
        frame.TitleBg:SetHeight(21)
    end

    ApplyBorderMode(frame)
end

-- Blizzard's SetItemButtonQuality is effectively inert on Classic, so the
-- quality ring is coloured directly from BAG_ITEM_QUALITY_COLORS and hidden for
-- anything below Uncommon -- the same approach Baganator uses on this client.
local function ApplyQualityBorder(button, quality)
    if not button.IconBorder then return end
    local uncommon = _G.LE_ITEM_QUALITY_UNCOMMON or 2
    local colors = _G.BAG_ITEM_QUALITY_COLORS
    local color = (quality and quality >= uncommon and colors) and colors[quality] or nil
    if color then
        button.IconBorder:SetVertexColor(color.r, color.g, color.b, 1)
        button.IconBorder:Show()
    else
        button.IconBorder:SetVertexColor(1, 1, 1, 1)
        button.IconBorder:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Item cell: a self-contained button plus a name/price label beside it.
--
-- Do not inherit ItemButtonTemplate here. Forever's modern FrameXML no longer
-- registers that legacy virtual node, and CreateFrame raises a hard error when
-- an inherited node is missing. Owning these four regions also keeps the cell
-- independent of global SetItemButton* helpers whose field expectations differ
-- between Classic and modern clients.
-- ---------------------------------------------------------------------------
local function CreateGroceryItemButton(name, parent)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(37, 37)
    button._tfGroceryOwned = true

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon = icon
    button.icon = icon

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 3)
    count:SetJustifyH("RIGHT")
    count:Hide()
    button.Count = count

    local border = button:CreateTexture(nil, "OVERLAY", nil, 4)
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:SetSize(37, 37)
    border:SetPoint("CENTER", button, "CENTER", 0, 0)
    border:Hide()
    button.IconBorder = border

    button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = button:GetNormalTexture()
    if normal then
        normal:ClearAllPoints()
        normal:SetPoint("CENTER", button, "CENTER", 0, -1)
        normal:SetSize(64, 64)
    end
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    return button
end

local function SetGroceryButtonTexture(button, texture)
    if button and button.Icon then button.Icon:SetTexture(texture) end
end

local function SetGroceryButtonCount(button, value)
    local count = button and button.Count
    if not count then return end
    value = tonumber(value) or 0
    count:SetText(value > 0 and value or "")
    count:SetShown(value > 0)
end

local function SetGroceryButtonDesaturated(button, desaturated)
    if button and button.Icon and button.Icon.SetDesaturated then
        button.Icon:SetDesaturated(desaturated == true)
    end
end

local function CellTooltip(self)
    local entry = self.entry
    if not entry or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if IsFoodCatchAll(entry) then
        GameTooltip:AddLine(entry.name, 1, 1, 1)
        GameTooltip:AddLine("Buys whichever matching vendor food is found first.", 0.8, 0.8, 0.8, true)
        if tonumber(entry.foodTier) == 5 then
            GameTooltip:AddLine("Prefers Longjaw Mud Snapper when available.", 1, 0.82, 0, true)
        end
    else
        GameTooltip:SetHyperlink(ItemLink(entry) or ("item:" .. entry.id))
    end

    local unit = BuyUnit(entry)
    GameTooltip:AddLine(" ")
    if not IsFoodCatchAll(entry) then
        local carried = CarriedCount(entry.id)
        if carried > 0 then
            GameTooltip:AddLine(("In your bags: %d"):format(carried), 0.8, 0.8, 0.8)
        end
    end
    if unit > 1 then
        GameTooltip:AddLine(("Vendors sell this %d at a time."):format(unit), 1, 0.82, 0)
    end
    GameTooltip:AddLine(("Right-click: add %d"):format(unit), 0.1, 1, 0.1)
    GameTooltip:AddLine("Alt + right-click: add a full stack", 0.1, 1, 0.1)
    GameTooltip:AddLine(("Shift + right-click: remove %d"):format(unit), 1, 0.5, 0.5)
    GameTooltip:AddLine("Ctrl + right-click: clear this line", 1, 0.5, 0.5)
    GameTooltip:Show()
end

local function CellClick(self, button)
    local entry = self.entry
    if not entry then return end

    -- Shift-clicking a link into chat is the universal convention and wins on a
    -- LEFT click; the queue shortcuts are all right-click.
    if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
        local link = ItemLink(entry)
        if link and ChatEdit_InsertLink(link) then return end
    end

    if button ~= "RightButton" then return end

    -- One right-click is one vendor PURCHASE, not one item: five for food/drink
    -- and 200 for Ammo. Alt jumps to a full bag stack, floored to whole purchases.
    local unit = BuyUnit(entry)
    local current = QueuedCount(entry.id)
    if IsControlKeyDown() then
        SetQueued(entry.id, 0)
    elseif IsShiftKeyDown() then
        SetQueued(entry.id, current - unit)
    elseif IsAltKeyDown() then
        local stack = math_floor(ItemStack(entry) / unit) * unit
        SetQueued(entry.id, current + math_max(stack, unit))
    else
        SetQueued(entry.id, current + unit)
    end

    -- Queueing the first item reveals the shopping list, which is where the
    -- order actually lives; after that the player's own toggle is respected.
    if next(Queue()) ~= nil and not ns.Opt("groceryQueueSeen", false) then
        ns.SetOpt("groceryQueueSeen", true)
        ns.SetOpt("groceryShowQueue", true)
    end

    G:UpdateWindow()
    G:UpdateButton()
end

local function AcquireCell(index)
    listCells = listCells or {}
    if listCells[index] then return listCells[index] end

    -- Row-major fill: left cell then right cell, then down a row.
    local i = index - 1
    local col, row = i % GRID_COLS, math_floor(i / GRID_COLS)

    local holder = CreateFrame("Frame", nil, gridInset)
    holder:SetSize(CELL_W, CELL_H)
    holder:SetPoint("TOPLEFT", gridInset, "TOPLEFT",
        GRID_INSET_L + (col * (CELL_W + CELL_PAD_X)),
        -8 - (row * (CELL_H + CELL_PAD_Y)))

    -- This must remain template-free: ItemButtonTemplate is absent in Forever.
    local button = CreateGroceryItemButton("TurboFaceGroceryItem" .. index, holder)
    button:SetPoint("LEFT", holder, "LEFT", 0, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", CellTooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnClick", CellClick)

    -- Queued marker: a green ring over the slot, using standard button art.
    local marker = button:CreateTexture(nil, "OVERLAY")
    marker:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    marker:SetBlendMode("ADD")
    marker:SetSize(62, 62)
    marker:SetPoint("CENTER", button, "CENTER", 0, 0)
    marker:SetVertexColor(0.1, 1, 0.1, 0.65)
    marker:Hide()
    button.QueuedMarker = marker

    local name = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", button, "TOPRIGHT", 7, -1)
    name:SetPoint("RIGHT", holder, "RIGHT", -2, 0)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("TOP")
    name:SetHeight(22)
    if name.SetMaxLines then name:SetMaxLines(2) end

    local price = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    price:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 7, 1)
    price:SetJustifyH("LEFT")

    local cell = { holder = holder, button = button, name = name, price = price }
    listCells[index] = cell
    return cell
end

-- ---------------------------------------------------------------------------
-- Shopping list popout
-- ---------------------------------------------------------------------------
local QUEUE_ROW_H = 28
-- The popout is a fixed-height panel, so it can hold only so many lines. Rows
-- beyond this are summarised on the total line rather than drawn outside the
-- inset -- which matters as the catalog grows past the current twelve items.
-- Derived from the real layout numbers so it cannot drift out of sync: panel
-- height, minus the title strip, minus the button/total block at the bottom.
local QUEUE_PANEL_H  = LIST_H - 30
local QUEUE_INSET_H  = QUEUE_PANEL_H - 26 - 76
local MAX_QUEUE_ROWS = math_max(math_floor(QUEUE_INSET_H / QUEUE_ROW_H), 1)

local function AcquireQueueRow(index)
    queueRows = queueRows or {}
    if queueRows[index] then return queueRows[index] end

    local row = CreateFrame("Button", nil, queueInset)
    row:SetSize(QUEUE_W - 40, QUEUE_ROW_H)
    row:SetPoint("TOPLEFT", queueInset, "TOPLEFT", 8, -6 - ((index - 1) * QUEUE_ROW_H))
    row:RegisterForClicks("RightButtonUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 5)
    row.text:SetPoint("RIGHT", row, "RIGHT", -32, 0)
    row.text:SetJustifyH("LEFT")
    -- Word wrap off means the engine truncates a too-long name for us, which is
    -- byte-safe on localized clients in a way that string.sub would not be.
    row.text:SetWordWrap(false)

    row.qty = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.qty:SetPoint("RIGHT", row, "RIGHT", 0, 5)
    row.qty:SetJustifyH("RIGHT")

    row.cost = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.cost:SetPoint("LEFT", row.icon, "RIGHT", 5, -7)
    row.cost:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.highlight:SetVertexColor(1, 0.3, 0.3, 0.15)

    row:SetScript("OnEnter", function(self)
        if not self.entry or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if IsFoodCatchAll(self.entry) then
            GameTooltip:AddLine(self.entry.name, 1, 1, 1)
            GameTooltip:AddLine("Resolved to an available food when a vendor opens.", 0.8, 0.8, 0.8, true)
            if tonumber(self.entry.foodTier) == 5 then
                GameTooltip:AddLine("Prefers Longjaw Mud Snapper when available.", 1, 0.82, 0, true)
            end
        else
            GameTooltip:SetHyperlink(ItemLink(self.entry) or ("item:" .. self.entry.id))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click: remove from the list", 1, 0.5, 0.5)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        SetQueued(self.entry.id, 0)
        if GameTooltip then GameTooltip:Hide() end
        G:UpdateWindow()
        G:UpdateButton()
    end)

    queueRows[index] = row
    return row
end

function G:UpdateQueuePanel()
    if not queuePanel then return end

    local show = ns.Opt("groceryShowQueue", true) == true
    queuePanel:SetShown(show)
    if queueTab then queueTab:SetText(show and ">" or "<") end
    if not show then return end

    local lines, drawn, totalCost, totalItems, known = 0, 0, 0, 0, true
    for _, entry in ipairs(CATALOG) do
        local queued = QueuedCount(entry.id)
        if queued > 0 then
            lines = lines + 1
            totalItems = totalItems + queued

            local unit
            if not IsFoodCatchAll(entry) then unit = KnownUnitPrice(entry.id) end
            if unit then
                totalCost = totalCost + (unit * queued)
            else
                known = false
            end

            if lines <= MAX_QUEUE_ROWS then
                drawn = drawn + 1
                local row = AcquireQueueRow(drawn)
                row.entry = entry
                row.icon:SetTexture(ItemIcon(entry))
                row.text:SetText(ColoredName(entry))
                row.qty:SetText(("|cffffffffx%d|r"):format(queued))
                if IsFoodCatchAll(entry) then
                    row.cost:SetText("|cff808080resolved at vendor|r")
                else
                    row.cost:SetText(unit and GetCoinTextureString(unit * queued) or "|cff808080price unknown|r")
                end
                row:Show()
            end
        end
    end

    for i = drawn + 1, #(queueRows or {}) do queueRows[i]:Hide() end

    if lines == 0 then
        queueTotal:SetText("|cff808080Nothing queued yet.|r")
    else
        local coin = GetCoinTextureString(totalCost) .. (known and "" or "+")
        local text = ("%d items  |cffffffff%s|r"):format(totalItems, coin)
        if lines > drawn then
            text = text .. ("\n|cff808080+%d more not shown|r"):format(lines - drawn)
        end
        queueTotal:SetText(text)
    end
end

-- ---------------------------------------------------------------------------
-- Grid
-- ---------------------------------------------------------------------------
function G:UpdateWindow()
    if not listFrame or not listFrame:IsShown() then return end

    -- Profiles replace TurboFaceDB wholesale, so refresh the visual state from
    -- the live options table rather than trusting a checkbutton's old state.
    if filterButtons.Food then filterButtons.Food:SetChecked(ns.Opt("groceryFilterFood", true) == true) end
    if filterButtons.Drink then filterButtons.Drink:SetChecked(ns.Opt("groceryFilterDrink", true) == true) end
    if filterButtons.Potion then filterButtons.Potion:SetChecked(ns.Opt("groceryFilterPotion", true) == true) end
    if filterButtons.Ammo then filterButtons.Ammo:SetChecked(ns.Opt("groceryFilterAmmo", true) == true) end
    if filterButtons.Usable then filterButtons.Usable:SetChecked(ns.Opt("groceryFilterUsable", false) == true) end

    local visible = VisibleCatalog()
    local pages = TotalPages(visible)
    if currentPage > pages then currentPage = pages end
    if currentPage < 1 then currentPage = 1 end

    local first = ((currentPage - 1) * PER_PAGE) + 1
    for slot = 1, PER_PAGE do
        local entry = visible[first + slot - 1]
        local cell = AcquireCell(slot)
        if not entry then
            cell.holder:Hide()
        else
            local queued = QueuedCount(entry.id)
            local unit = BuyUnit(entry)
            local button = cell.button

            button.entry = entry

            -- Owned setters avoid the client-specific region assumptions made
            -- by Blizzard's global SetItemButton* helpers.
            SetGroceryButtonTexture(button, ItemIcon(entry))
            SetGroceryButtonCount(button, unit > 1 and unit or 0)
            SetGroceryButtonDesaturated(button, false)
            local info = not IsFoodCatchAll(entry) and CatalogItemInfo(entry) or nil
            ApplyQualityBorder(button, info and info.quality or nil)

            if button.QueuedMarker then button.QueuedMarker:SetShown(queued > 0) end

            local label = ColoredName(entry)
            if queued > 0 then
                label = label .. ("  |cff40ff40(%d)|r"):format(queued)
            end
            cell.name:SetText(label)

            local unitPrice
            if not IsFoodCatchAll(entry) then unitPrice = KnownUnitPrice(entry.id) end
            if IsFoodCatchAll(entry) then
                cell.price:SetText("|cff808080Any matching vendor food|r")
            elseif unitPrice then
                cell.price:SetText(GetCoinTextureString(unitPrice * unit))
            else
                local req = ItemLevelReq(entry)
                cell.price:SetText(req > 0 and ("|cff808080Requires level %d|r"):format(req) or "|cff808080No level requirement|r")
            end

            cell.holder:Show()
        end
    end

    pageText:SetText(("Page %d"):format(currentPage))
    if currentPage > 1 then prevBtn:Enable() else prevBtn:Disable() end
    if currentPage < pages then nextBtn:Enable() else nextBtn:Disable() end

    self:UpdateQueuePanel()
end

-- Kept as the old public name so callers (purchases, events) do not care which
-- half of the window needs redrawing.
function G:UpdateList()
    self:UpdateWindow()
end

local function BuildQueuePanel(parent)
    queuePanel = CreateFrame("Frame", "TurboFaceGroceryQueue", parent, "ButtonFrameTemplate")
    queuePanel:SetSize(QUEUE_W, QUEUE_PANEL_H)
    queuePanel:SetPoint("TOPLEFT", parent, "TOPRIGHT", -4, -16)
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(queuePanel) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(queuePanel) end
    if queuePanel.SetTitle then queuePanel:SetTitle("Shopping List") end
    if queuePanel.Inset then queuePanel.Inset:Hide() end
    ApplyBlizzardFrameFixes(queuePanel)
    -- ButtonFrameTemplate brings its own close button; route it through the
    -- toggle so closing the popout persists like the tab handle does.
    if queuePanel.CloseButton then
        queuePanel.CloseButton:SetScript("OnClick", function()
            ns.SetOpt("groceryShowQueue", false)
            ns.SetOpt("groceryQueueSeen", true)
            G:UpdateQueuePanel()
        end)
    end

    queueInset = CreateFrame("Frame", nil, queuePanel, "InsetFrameTemplate")
    queueInset:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 8, -26)
    queueInset:SetPoint("BOTTOMRIGHT", queuePanel, "BOTTOMRIGHT", -8, 76)

    queueTotal = queuePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    queueTotal:SetPoint("BOTTOMLEFT", queuePanel, "BOTTOMLEFT", 10, 58)
    queueTotal:SetPoint("BOTTOMRIGHT", queuePanel, "BOTTOMRIGHT", -10, 58)
    queueTotal:SetJustifyH("CENTER")

    local buy = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    buy:SetSize(QUEUE_W - 32, 22)
    buy:SetPoint("BOTTOM", queuePanel, "BOTTOM", 0, 32)
    buy:SetText("Buy Now")
    buy:SetScript("OnClick", function() G:BuyNow() end)

    local clear = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    clear:SetSize(QUEUE_W - 32, 22)
    clear:SetPoint("BOTTOM", queuePanel, "BOTTOM", 0, 8)
    clear:SetText("Clear List")
    clear:SetScript("OnClick", function() G:ClearQueue() end)
end

local function EnsureListFrame()
    if listFrame then return listFrame end

    local f = CreateFrame("Frame", "TurboFaceGroceryFrame", UIParent, "ButtonFrameTemplate")
    listFrame = f
    f:Hide()
    f:SetSize(LIST_W, LIST_H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")

    -- Canonical ButtonFrameTemplate setup. The portrait is hidden: this window
    -- is a shopping list, not an NPC panel, so the top-left circle has nothing
    -- to show and would just leave a hole in the corner.
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.SetTitle then f:SetTitle("Grocery List") end
    if f.Inset then f.Inset:Hide() end
    ApplyBlizzardFrameFixes(f)
    -- The template's close button hides the frame directly, which would leave
    -- the GET_ITEM_INFO_RECEIVED listener registered. Route it through G:Hide.
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() G:Hide() end)
    end

    -- Position is a plain dialog memory, not a mover element.
    local point = ns.Opt("groceryFramePoint", "CENTER")
    f:SetPoint(point, UIParent, point, tonumber(ns.Opt("groceryFrameX", 0)) or 0, tonumber(ns.Opt("groceryFrameY", 0)) or 0)

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        ns.SetOpt("groceryFramePoint", p or "CENTER")
        ns.SetOpt("groceryFrameX", x or 0)
        ns.SetOpt("groceryFrameY", y or 0)
    end)

    -- Keep the launcher selected state and Blizzard-style panel audio tied to
    -- the frame itself. That covers every path that can show/hide the Grocery
    -- List (launcher, keybind, slash command, close button, and Escape).
    f:SetScript("OnShow", function()
        SetLauncherOpenState(true)
        PlayWindowSound(true)
    end)
    f:SetScript("OnHide", function()
        SetLauncherOpenState(false)
        PlayWindowSound(false)
        if G.SetItemInfoListener then G:SetItemInfoListener(false) end
    end)

    -- Catalog filters occupy the former helper-text row. Category checkmarks
    -- include that category; Usable hides only entries whose required level is
    -- above the player's current level. Defaults preserve show-all behavior:
    -- all categories on, Usable off.
    local function MakeFilter(key, label, option, x)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", x, -22)
        cb:SetChecked(ns.Opt(option, option ~= "groceryFilterUsable") == true)

        local text = cb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        text:SetText(label)
        cb.label = text

        cb:SetScript("OnClick", function(self)
            ns.SetOpt(option, self:GetChecked() and true or false)
            currentPage = 1
            G:UpdateWindow()
        end)

        filterButtons[key] = cb
        return cb
    end

    MakeFilter("Food",   "Food",    "groceryFilterFood",    12)
    MakeFilter("Drink",  "Drink",   "groceryFilterDrink",   75)
    MakeFilter("Potion", "Potions", "groceryFilterPotion", 142)
    MakeFilter("Ammo",   "Ammo",    "groceryFilterAmmo",   225)
    MakeFilter("Usable", "Usable",  "groceryFilterUsable", 290)

    gridInset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    gridInset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -44)
    gridInset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 40)

    -- Pagination, as on the merchant frame.
    prevBtn = CreateFrame("Button", nil, f)
    prevBtn:SetSize(32, 32)
    prevBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 6)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prevBtn:SetScript("OnClick", function()
        currentPage = math_max(currentPage - 1, 1)
        G:UpdateWindow()
    end)

    nextBtn = CreateFrame("Button", nil, f)
    nextBtn:SetSize(32, 32)
    nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 6)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextBtn:SetScript("OnClick", function()
        currentPage = math_min(currentPage + 1, TotalPages(VisibleCatalog()))
        G:UpdateWindow()
    end)

    pageText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pageText:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)

    BuildQueuePanel(f)

    -- Tab handle on the right edge toggles the shopping list popout.
    queueTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    queueTab:SetSize(18, 56)
    queueTab:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -48)
    queueTab:SetText(">")
    queueTab:SetScript("OnClick", function()
        ns.SetOpt("groceryShowQueue", ns.Opt("groceryShowQueue", true) ~= true)
        ns.SetOpt("groceryQueueSeen", true)
        G:UpdateQueuePanel()
    end)
    queueTab:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Toggle the shopping list")
        GameTooltip:Show()
    end)
    queueTab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Escape closes it, like any other WoW panel.
    if _G.UISpecialFrames then tinsert(_G.UISpecialFrames, "TurboFaceGroceryFrame") end

    return f
end

function G:Show()
    if not Enabled() then
        Chat("the Grocery List is disabled in the Misc options.")
        return
    end
    EnsureListFrame()
    listFrame:Show()
    self:UpdateWindow()
    self:SetItemInfoListener(true)
end

function G:Hide()
    if listFrame then listFrame:Hide() end
    if GameTooltip then GameTooltip:Hide() end
    self:SetItemInfoListener(false)
end

function G:Toggle()
    if listFrame and listFrame:IsShown() then self:Hide() else self:Show() end
end

function G:IsShown()
    return listFrame and listFrame:IsShown() and true or false
end

-- Stable Blizzard Key Bindings target. This button exists even when the Grocery
-- feature is disabled so Bindings.xml always resolves cleanly; the action itself
-- stays inert while groceryEnabled is off.
local groceryBindingButton = _G.TurboFaceToggleGroceryList
    or CreateFrame("Button", "TurboFaceToggleGroceryList", UIParent)
groceryBindingButton:SetScript("OnClick", function()
    if Enabled() then G:Toggle() end
end)
_G.BINDING_HEADER_TURBOFACE = _G.BINDING_HEADER_TURBOFACE or "TurboFace"
_G["BINDING_NAME_CLICK TurboFaceToggleGroceryList:LeftButton"] = "Toggle Grocery List"

function G:ClearQueue()
    if type(TurboFaceCharDB) == "table" then TurboFaceCharDB.grocery = {} end
    self:UpdateWindow()
    self:UpdateButton()
    Chat("grocery list cleared.")
end

function G:DumpStatus()
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    Chat(("merchant=%s available=%s open=%s items=%s queued=%s run=%s")
        :format(tostring(ns.API.MerchantInfoKind or "unknown"),
            tostring(ns.API.MerchantSurfaceAvailable()), tostring(MerchantOpen()),
            tostring(count or 0), tostring(#QueuedEntries()), tostring(session ~= nil)))
end

-- ---------------------------------------------------------------------------
-- Frame diagnostics (/tfgrocery frames)
--
-- ButtonFrameTemplate's internals differ between Classic revisions, and border
-- geometry cannot be verified without the client in front of you. This dumps
-- the real regions and their anchors so a cosmetic seam can be diagnosed from
-- actual values instead of guessed at.
-- ---------------------------------------------------------------------------
local DUMP_KEYS = {
    "Bg", "TitleBg", "TopTileStreaks", "portrait", "PortraitFrame", "NineSlice",
    "TopLeftCorner", "TopBorder", "TopRightCorner",
    "LeftBorder", "RightBorder",
    "BotLeftCorner", "BottomBorder", "BotRightCorner",
    "Inset", "CloseButton", "TitleText",
}

-- Cycle the border source live. The correct choice depends on whether this
-- build's NineSlice actually draws anything, which cannot be determined without
-- the client in front of you -- so it is switchable rather than guessed.
function G:CycleBorderMode()
    local order = { "auto", "legacy", "nineslice" }
    local current = ns.Opt("groceryBorderMode", "auto")
    local nextMode = order[1]
    for i, m in ipairs(order) do
        if m == current then
            nextMode = order[(i % #order) + 1]
            break
        end
    end
    ns.SetOpt("groceryBorderMode", nextMode)

    for frame in pairs(skinnedFrames) do
        ApplyBorderMode(frame)
    end

    -- Report from the main window specifically; pairs() order is undefined.
    local legacy = listFrame and ApplyBorderMode(listFrame)
    local detected = (listFrame and NineSliceActive(listFrame)) and "yes" or "no"
    Chat(("border mode: |cffffd100%s|r (NineSlice has regions: %s) -- now drawing the %s border.")
        :format(nextMode, detected, legacy and "legacy corner/edge" or "NineSlice"))
end

-- The general dump gives anchors and sizes; this one gives the ART, which is
-- what the corner seam turned on. It reports file, texcoords and draw layer for
-- each border piece. Dividing a piece's pixel size by its texcoord span yields
-- the source sheet's dimension -- and a piece whose result disagrees with its
-- neighbours is being drawn at the wrong scale. That is exactly how the
-- 32x32-drawn-at-33x33 stretch on TopLeftCorner was found.
function G:DumpBorderArt()
    if not listFrame then
        Chat("open the window first (/tfgrocery), then run this again.")
        return
    end

    local function Fmt(n)
        if type(n) ~= "number" then return "?" end
        return ("%.2f"):format(n)
    end

    local keys = {
        "TopLeftCorner", "TopBorder", "TopRightCorner",
        "LeftBorder", "RightBorder",
    }

    for _, key in ipairs(keys) do
        local r = listFrame[key]
        if not r then
            Chat(("  %s = nil"):format(key))
        else
            local tex = r.GetTexture and r:GetTexture()
            if type(tex) == "number" then tex = "fileID:" .. tex end
            local layer, sub = "?", "?"
            if r.GetDrawLayer then layer, sub = r:GetDrawLayer() end

            local coords = ""
            if r.GetTexCoord then
                local a, b, c, d, e, f2, g2, h = r:GetTexCoord()
                if a then
                    coords = (" tc(%s,%s %s,%s %s,%s %s,%s)"):format(
                        Fmt(a), Fmt(b), Fmt(c), Fmt(d), Fmt(e), Fmt(f2), Fmt(g2), Fmt(h))
                end
            end

            Chat(("  %s  %s  layer=%s/%s%s")
                :format(key, tostring(tex or "nil"), tostring(layer), tostring(sub), coords))
        end
    end
end


function G:DumpFrame()
    if not listFrame then
        Chat("open the window first (/tfgrocery), then run this again.")
        return
    end

    local function Fmt(n)
        if type(n) ~= "number" then return "?" end
        return ("%.1f"):format(n)
    end

    Chat(("frame %s  size %sx%s  scale %s")
        :format(listFrame:GetName() or "?", Fmt(listFrame:GetWidth()),
                Fmt(listFrame:GetHeight()), Fmt(listFrame:GetScale())))

    local nineSlice = listFrame.NineSlice
    local nsCount = 0
    if nineSlice and nineSlice.GetRegions then
        nsCount = select("#", nineSlice:GetRegions())
    end
    Chat(("  NineSlice regions: %d   border mode: %s")
        :format(nsCount, tostring(ns.Opt("groceryBorderMode", "auto"))))

    for _, key in ipairs(DUMP_KEYS) do
        local r = listFrame[key]
        if r == nil then
            Chat(("  %s = nil"):format(key))
        else
            local shown = (r.IsShown and r:IsShown()) and "shown" or "hidden"
            local size = (r.GetWidth and r.GetHeight)
                and ("%sx%s"):format(Fmt(r:GetWidth()), Fmt(r:GetHeight())) or "?"
            local pts = (r.GetNumPoints and r:GetNumPoints()) or 0
            local anchors = {}
            for i = 1, pts do
                local p, rel, relP, x, y = r:GetPoint(i)
                anchors[#anchors + 1] = ("%s->%s.%s(%s,%s)"):format(
                    tostring(p), rel and (rel.GetName and rel:GetName() or "?") or "nil",
                    tostring(relP), Fmt(x), Fmt(y))
            end
            Chat(("  %s %s %s [%s]"):format(key, shown, size, table.concat(anchors, " ")))
        end
    end
end

-- =============================================================================
-- LAUNCHER BUTTON (mover element "GroceryButton")
-- =============================================================================
local function ButtonFallbackPoint()
    return { "CENTER", UIParent, "CENTER", 0, -180 }
end

function G:GetFrame() return launcher end
function G:GetChildren() return launcher and { launcher } or {} end

function G:RegisterMover()
    if not launcher or not ns.Movers or not ns.Movers.RegisterElement then return end
    local fallback = ButtonFallbackPoint()
    ns.Movers:RegisterElement("GroceryButton", launcher, {
        label = "Grocery Button",
        overlayWidth = 32,
        overlayHeight = 32,
        fallbackPoint = fallback,
        defaultPoint = fallback,
        getChildren = function() return G:GetChildren() end,
    })
    if ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("GroceryButton") end
end

-- Badge the button with the number of queued lines so the list is visible at a
-- glance without opening the window.
function G:UpdateButton()
    if not launcher then return end
    local lines = 0
    for _, count in pairs(Queue()) do
        if (tonumber(count) or 0) > 0 then lines = lines + 1 end
    end
    if lines > 0 then
        launcher.count:SetText(lines)
        launcher.count:Show()
    else
        launcher.count:SetText("")
        launcher.count:Hide()
    end
end

local function EnsureButton()
    if launcher then return launcher end

    local b = CreateFrame("Button", "TurboFaceGroceryButton", UIParent)
    launcher = b
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local p = ButtonFallbackPoint()
    b:SetPoint(p[1], p[2], p[3], p[4], p[5])   -- Movers re-anchors from the saved point

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture(132815)                   -- Ice Cold Milk icon
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Draw the open-state art ourselves so the Ice Cold Milk icon stays visible.
    -- This is the same additive texture Blizzard uses for an open bag button,
    -- but layered above our custom icon rather than installed as a CheckButton
    -- replacement texture.
    b.openGlow = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.openGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.openGlow:SetAllPoints(b)
    b.openGlow:SetBlendMode("ADD")
    b.openGlow:SetAlpha(1.0)
    b.openGlow:Hide()

    b.border = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.border:SetSize(58, 58)
    b.border:SetPoint("CENTER", b, "CENTER", 0, -1)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, 0)
    b.count:SetTextColor(1, 0.82, 0)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    SetLauncherOpenState(G:IsShown())

    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ccffTurbo|cffffffffFace|r Grocery List")
        GameTooltip:AddLine("Left-click: open the shopping list", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: clear the list", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Queued items are bought automatically at any vendor that stocks them.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            G:ClearQueue()
        else
            G:Toggle()
        end
    end)

    return b
end

-- =============================================================================
-- EVENTS
-- =============================================================================
local evt          -- merchant runtime
local infoListener -- GET_ITEM_INFO_RECEIVED, only while the window is open

local function HandleEvent(_, event)
    if event == "MERCHANT_SHOW" then
        merchantSessionOpen = true
    elseif event == "MERCHANT_CLOSED" then
        merchantSessionOpen = false
    end
    if not Enabled() then return end
    if event == "MERCHANT_SHOW" then
        if ns.Opt("groceryAutoBuy", true) ~= true then return end
        -- Shift at the vendor skips this run, matching Plus auto-repair.
        if IsShiftKeyDown() then return end
        BeginAutoBuy()
    elseif event == "MERCHANT_CLOSED" then
        -- Close the run down through RunStep rather than dropping it: that path
        -- already credits a partially delivered line and emits the chat summary
        -- explaining what happened.
        if session then RunStep() end
        CancelRun()
        G:UpdateList()
        G:UpdateButton()
    end
end

local function SetEvents(active)
    if not evt then return end
    evt:UnregisterAllEvents()
    if not active then
        merchantSessionOpen = false
        return
    end
    ns.RegisterEvent(evt, "MERCHANT_SHOW")
    ns.RegisterEvent(evt, "MERCHANT_CLOSED")
end

-- Item names/prices/stack sizes arrive asynchronously on a cold cache. The
-- Usable filter also changes when the player levels. Listen for both only while
-- the window is actually visible so there is no idle subscription.
function G:SetItemInfoListener(active)
    if active and not infoListener then
        infoListener = CreateFrame("Frame")
        infoListener:SetScript("OnEvent", function()
            G:UpdateList()
        end)
    end
    if not infoListener then return end
    infoListener:UnregisterAllEvents()
    if active and Enabled() then
        ns.RegisterEvent(infoListener, "GET_ITEM_INFO_RECEIVED")
        ns.RegisterEvent(infoListener, "PLAYER_LEVEL_UP")
    end
end

-- =============================================================================
-- INIT / REFRESH
-- =============================================================================
function G:Init()
    if not Enabled() then return end

    if not ns.API.MerchantSurfaceAvailable() then
        Chat("merchant APIs are unavailable on this client; the list UI will work, but auto-buy is disabled.")
    end

    Queue()

    if not evt then
        evt = CreateFrame("Frame")
        evt:SetScript("OnEvent", HandleEvent)
    end
    SetEvents(true)

    -- Warm the item cache so the first window open shows real names/prices.
    for _, entry in ipairs(CATALOG) do
        if IsFoodCatchAll(entry) then
            if entry.iconItem then GetItemInfo(entry.iconItem) end
        else
            GetItemInfo(entry.id)
        end
    end

    if ButtonEnabled() then
        EnsureButton()
        self:RegisterMover()
        launcher:Show()
        self:UpdateButton()
    end
end

-- Live apply from the options panel and from Movers:RefreshDependents().
function G:Refresh()
    local active = Enabled()

    if active and not evt then
        self:Init()
        return
    end

    SetEvents(active)

    if not active then
        CancelRun()
        self:Hide()
        if launcher then launcher:Hide() end
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("GroceryButton") end
        return
    end

    if ButtonEnabled() then
        EnsureButton()
        self:RegisterMover()
        launcher:Show()
        self:UpdateButton()
    elseif launcher then
        launcher:Hide()
        if ns.Movers and ns.Movers.UpdateOverlay then ns.Movers:UpdateOverlay("GroceryButton") end
    end

    self:UpdateList()
end

-- =============================================================================
-- SLASH
-- =============================================================================
SLASH_TFGROCERY1 = "/tfgrocery"
SLASH_TFGROCERY2 = "/tfshop"
SlashCmdList["TFGROCERY"] = function(msg)
    msg = msg or ""
    local cmd, args = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    args = args or ""
    if cmd == "clear" then
        G:ClearQueue()
    elseif cmd == "buy" then
        G:BuyNow()
    elseif cmd == "frames" then
        G:DumpFrame()
    elseif cmd == "border" then
        G:CycleBorderMode()
    elseif cmd == "art" then
        G:DumpBorderArt()
    elseif cmd == "status" or cmd == "debug" then
        G:DumpStatus()
    else
        G:Toggle()
    end
end

ns.RegisterCPUProfileTarget("Inventory/Grocery:UpdateList", G.UpdateList)
