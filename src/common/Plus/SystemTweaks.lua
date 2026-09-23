local _, ns = ...

-- TurboFace Plus: system-level convenience toggles implemented directly from
-- Blizzard CVars, events, loot APIs and tooltip APIs.

local M = {}
ns.PlusSystem = M

local function Settings()
    return ns.PlusSettings()
end

local function SectionEnabled()
    return not ns.PlusSectionEnabled or ns.PlusSectionEnabled("system")
end

local frames = {}
local function SetEvents(key, enabled, handler, ...)
    local frame = frames[key]
    if enabled then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", handler)
            frames[key] = frame
        end
        frame:UnregisterAllEvents()
        for i = 1, select("#", ...) do
            local event = select(i, ...)
            if event then
                if ns.API and ns.API.RegisterEvent then
                    ns.API.RegisterEvent(frame, event)
                else
                    frame:RegisterEvent(event)
                end
            end
        end
    elseif frame then
        frame:UnregisterAllEvents()
    end
end

local function OwnCVars(owner, active, values)
    if ns.ApplyOwnedCVars then
        ns.ApplyOwnedCVars("plus.system." .. owner, active, values)
    end
end

local SCREEN_GLOW = { ffxGlow = "0" }
local SCREEN_EFFECTS = { ffxDeath = "0", ffxNether = "0" }
local CAMERA_DISTANCE = { cameraDistanceMaxZoomFactor = "4.0" }
local WEATHER = { WeatherDensity = "3", RAIDweatherDensity = "3" }
local EMOTE_SOUND = { Sound_EnableEmoteSounds = "0" }
local AUDIO_DRIVER = { Sound_OutputDriverIndex = "0" }

local weatherHooked = false
local function InstallWeatherReassertion()
    if weatherHooked or type(hooksecurefunc) ~= "function" then return end
    weatherHooked = true
    hooksecurefunc("SetCVar", function(name)
        if name ~= "graphicsParticleDensity" and name ~= "raidGraphicsParticleDensity" then return end
        if not (SectionEnabled() and Settings().setWeatherDensity) then return end
        C_Timer.After(0.1, function()
            if not (SectionEnabled() and Settings().setWeatherDensity) then return end
            local level = tostring(tonumber(Settings().weatherLevel) or 3)
            if GetCVar("WeatherDensity") ~= level then SetCVar("WeatherDensity", level) end
            if GetCVar("RAIDweatherDensity") ~= level then SetCVar("RAIDweatherDensity", level) end
        end)
    end)
end

function M:ApplyCVars()
    local p = Settings()
    local active = SectionEnabled()

    OwnCVars("screenGlow", active and p.noScreenGlow == true, SCREEN_GLOW)
    OwnCVars("screenEffects", active and p.noScreenEffects == true, SCREEN_EFFECTS)
    OwnCVars("cameraZoom", active and p.maxCameraZoom == true, CAMERA_DISTANCE)

    local weatherActive = active and p.setWeatherDensity == true
    local level = tostring(tonumber(p.weatherLevel) or 3)
    WEATHER.WeatherDensity = level
    WEATHER.RAIDweatherDensity = level
    if weatherActive then InstallWeatherReassertion() end
    OwnCVars("weather", weatherActive, WEATHER)
end

-- ---------------------------------------------------------------------------
-- Rested emote sounds
-- ---------------------------------------------------------------------------

local function UpdateRestedSound()
    local active = SectionEnabled() and Settings().noRestedEmotes == true
    local inMutedArea = active and (IsResting() or GetSubZoneText() == "The Grim Guzzler")
    OwnCVars("restedEmotes", inMutedArea, EMOTE_SOUND)
end

function M:RefreshRestedEmotes()
    local active = SectionEnabled() and Settings().noRestedEmotes == true
    SetEvents("rested", active, UpdateRestedSound,
        "PLAYER_UPDATE_RESTING", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA")
    UpdateRestedSound()
end

-- ---------------------------------------------------------------------------
-- Audio output resynchronization
-- ---------------------------------------------------------------------------

local function ResyncAudio()
    if not (SectionEnabled() and Settings().keepAudioSynced) then return end
    OwnCVars("audioOutput", true, AUDIO_DRIVER)
    if CinematicFrame and CinematicFrame:IsShown() then return end
    if MovieFrame and MovieFrame:IsShown() then return end
    if Sound_GameSystem_RestartSoundSystem then Sound_GameSystem_RestartSoundSystem() end
end

function M:RefreshAudioSync()
    local active = SectionEnabled() and Settings().keepAudioSynced == true
    OwnCVars("audioOutput", active, AUDIO_DRIVER)
    SetEvents("audio", active, ResyncAudio, "VOICE_CHAT_OUTPUT_DEVICES_UPDATED")
end

-- ---------------------------------------------------------------------------
-- Bag auto-open suppression
-- ---------------------------------------------------------------------------

local bagHooked = false
local function InstallBagSuppression()
    if bagHooked or type(hooksecurefunc) ~= "function" or type(OpenAllBags) ~= "function" then return end
    bagHooked = true
    hooksecurefunc("OpenAllBags", function()
        if SectionEnabled() and Settings().noBagAutomation and CloseAllBags then
            CloseAllBags()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Confirmation suppression
-- ---------------------------------------------------------------------------

local function OnLootConfirmation(_, event, arg1, arg2)
    if not (SectionEnabled() and Settings().noConfirmLoot) then return end
    if event == "CONFIRM_LOOT_ROLL" then
        if ConfirmLootRoll then ConfirmLootRoll(arg1, arg2) end
        if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
    elseif event == "LOOT_BIND_CONFIRM" then
        if ConfirmLootSlot then ConfirmLootSlot(arg1, arg2) end
        if StaticPopup_Hide then StaticPopup_Hide("LOOT_BIND") end
    elseif event == "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL" then
        if SellCursorItem then SellCursorItem() end
    elseif event == "MAIL_LOCK_SEND_ITEMS" then
        if RespondMailLockSendItem then RespondMailLockSendItem(arg1, true) end
    end
end

function M:RefreshLootWarnings()
    local active = SectionEnabled() and Settings().noConfirmLoot == true
    SetEvents("lootConfirm", active, OnLootConfirmation,
        "CONFIRM_LOOT_ROLL", "LOOT_BIND_CONFIRM", "MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL", "MAIL_LOCK_SEND_ITEMS")
end

-- ---------------------------------------------------------------------------
-- Faster auto-loot
-- ---------------------------------------------------------------------------

local lastFastLoot = 0
local fastLootLastSlots = 0
local fastLootLastSkippedLocked = 0

local function CurrentLootMethod()
    if C_PartyInfo and type(C_PartyInfo.GetLootMethod) == "function" then
        local ok, method = pcall(C_PartyInfo.GetLootMethod)
        if ok then return method end
    end
    if type(GetLootMethod) == "function" then
        local ok, method = pcall(GetLootMethod)
        if ok then return method end
    end
end

local function IsMasterLoot(method)
    if type(method) == "number" then
        local enumValue = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
        return method == (enumValue or 2)
    end
    return method == "master" or method == "masterlooter"
end

local function OnLootReady()
    if not (SectionEnabled() and Settings().fasterLooting) then return end
    if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return end
    local now = GetTime()
    if now - lastFastLoot < 0.30 then return end

    -- Match Blizzard's auto-loot modifier semantics. If this loot was opened
    -- in manual-loot mode, TurboFace does nothing.
    if type(GetCVarBool) == "function" and type(IsModifiedClick) == "function"
        and GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then
        return
    end

    local method = CurrentLootMethod()
    local threshold = type(GetLootThreshold) == "function" and GetLootThreshold()
    local count = tonumber(GetNumLootItems()) or 0
    local looted, skippedLocked = 0, 0
    for slot = count, 1, -1 do
        local shouldLoot = true
        local locked = false
        if type(GetLootSlotInfo) == "function" then
            local _, _, _, _, quality, isLocked = GetLootSlotInfo(slot)
            locked = isLocked == true
            if IsMasterLoot(method) and threshold then
                shouldLoot = quality ~= nil and quality < threshold
            end
        end
        if locked then
            shouldLoot = false
            skippedLocked = skippedLocked + 1
        end
        if shouldLoot then
            LootSlot(slot)
            looted = looted + 1
        end
    end
    fastLootLastSlots = looted
    fastLootLastSkippedLocked = skippedLocked
    lastFastLoot = now
end

local function InstallFastLoot()
    local active = SectionEnabled() and Settings().fasterLooting == true
    SetEvents("fastLoot", active, OnLootReady, "LOOT_READY")
end

function M:GetFastLootDiagnostics()
    local validEvent = true
    if ns.API and ns.API.IsEventValid then validEvent = ns.API.IsEventValid("LOOT_READY") end
    local methodAPI = C_PartyInfo and type(C_PartyInfo.GetLootMethod) == "function" and "C_PartyInfo"
        or (type(GetLootMethod) == "function" and "legacy" or "missing")
    return {
        enabled = SectionEnabled() and Settings().fasterLooting == true,
        eventValid = validEvent,
        lootAPI = type(GetNumLootItems) == "function" and type(LootSlot) == "function",
        lootInfoAPI = type(GetLootSlotInfo) == "function",
        methodAPI = methodAPI,
        lastLooted = fastLootLastSlots,
        lastSkippedLocked = fastLootLastSkippedLocked,
    }
end

-- ---------------------------------------------------------------------------
-- Vendor value on item tooltips
--
-- Era does not provide the native vendor-value presentation TurboFace expects,
-- so the Classic Plus provider explicitly owns this augmentation. Forever's
-- provider yields the surface to Blizzard and this code remains dormant even
-- if an old profile still contains showVendorPrice=true.
-- ---------------------------------------------------------------------------

local vendorHooked = false

local function VendorTooltipEnabled()
    return SectionEnabled()
        and Settings().showVendorPrice == true
        and ns.PlusProviderSupportsVendorPriceTooltip
        and ns.PlusProviderSupportsVendorPriceTooltip()
end

local function StackCountUnderMouse()
    local focus
    if GetMouseFoci then
        local list = GetMouseFoci()
        focus = type(list) == "table" and list[1] or nil
    elseif GetMouseFocus then
        focus = GetMouseFocus()
    end
    local count = focus and tonumber(focus.count)
    return math.max(1, count or 1)
end

local function AddVendorValue(tip)
    if not VendorTooltipEnabled() then return end
    if not tip or tip.shownMoneyFrames then return end
    local _, link = tip:GetItem()
    if not link then return end

    local sellPrice, classID = select(11, ns.API.GetItemInfo(link))
    sellPrice = tonumber(sellPrice)
    if not sellPrice or sellPrice <= 0 then return end

    local count = classID == 11 and 1 or StackCountUnderMouse()
    SetTooltipMoney(tip, sellPrice * count, "STATIC", SELL_PRICE .. ":")
    if tip == ItemRefTooltip then tip:Show() end
end

local function InstallVendorHook()
    if vendorHooked or not VendorTooltipEnabled() then return end
    vendorHooked = true

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
            if tip == GameTooltip or tip == ItemRefTooltip then AddVendorValue(tip) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", AddVendorValue)
    end

    if ItemRefTooltip and type(hooksecurefunc) == "function" then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(tip) AddVendorValue(tip) end)
    end
end


function M:Refresh()
    self:ApplyCVars()
    self:RefreshRestedEmotes()
    self:RefreshAudioSync()
    self:RefreshLootWarnings()
    InstallFastLoot()
    if SectionEnabled() and Settings().noBagAutomation then InstallBagSuppression() end
    InstallVendorHook()
end

function M:Init()
    self:Refresh()
end
