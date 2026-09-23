local _, ns = ...

-- =============================================================================
-- TALL-BOSS WORLDFRAME EXTENSION
-- =============================================================================
-- Blizzard owns nameplate stacking and all plate positioning. TurboFace never
-- reads or writes restricted nameplate coordinates. This file has one narrow
-- job: extend WorldFrame upward so very tall Classic models can still receive a
-- Blizzard-native nameplate when their model anchor would otherwise fall above
-- the normal screen-height WorldFrame. Enemy stacking itself is controlled only
-- through Blizzard CVars owned/released by BubbleNameplates.lua.
-- =============================================================================

local WorldFrame = WorldFrame
local UIParent = UIParent
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local CreateFrame = CreateFrame

-- How many screen-heights tall to make WorldFrame. 5 is inherited from the
-- original implementation and is comfortably clear of any Classic model.
local WORLDFRAME_HEIGHT_MULTIPLIER = 5

local screenWidth, screenHeight = 1366, 768
local initialized = false
local eventFrame

local function NameplatesEnabled()
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("nameplates")
end

-- Screen size in UI units. Do NOT scale these: WorldFrame expects UI units.
local function RefreshScreenDimensions()
    local w = GetScreenWidth and GetScreenWidth()
    local h = GetScreenHeight and GetScreenHeight()
    if not w or w <= 0 then w = (UIParent and UIParent:GetWidth()) or screenWidth end
    if not h or h <= 0 then h = (UIParent and UIParent:GetHeight()) or screenHeight end
    screenWidth, screenHeight = w, h
end

local function ApplyWorldFrameExtension()
    RefreshScreenDimensions()
    WorldFrame:ClearAllPoints()
    WorldFrame:SetWidth(screenWidth)
    WorldFrame:SetHeight(screenHeight * WORLDFRAME_HEIGHT_MULTIPLIER)
    WorldFrame:SetPoint("BOTTOM")
end

-- Resolution, windowed-mode and UI-scale changes all invalidate the sizing.
local function OnScreenChanged()
    if not NameplatesEnabled() then return end
    ApplyWorldFrameExtension()
end

-- Called once from Core.lua after the Nameplates master gate is resolved.
function ns.InitTallBossFix()
    if not NameplatesEnabled() then return end
    if initialized then return end
    initialized = true

    ApplyWorldFrameExtension()

    eventFrame = CreateFrame("Frame")
    ns.RegisterEvent(eventFrame, "UI_SCALE_CHANGED")
    ns.RegisterEvent(eventFrame, "DISPLAY_SIZE_CHANGED")
    eventFrame:SetScript("OnEvent", OnScreenChanged)
end
