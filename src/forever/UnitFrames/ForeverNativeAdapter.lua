local _, ns = ...

local UF = ns.UF
if not UF then return end

local compat = ns.Compat
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true) then return end

-- =============================================================================
-- WoW Forever native UnitFrame adapter
-- =============================================================================
-- Forever's Player/Target/Pet/Party/ToT frames are protected Blizzard frames and
-- several of their gameplay values become secret during combat.  The Era
-- UnitFrames implementation is intentionally NOT reused here: it stores addon
-- state on Blizzard bars, parents TurboFace regions to those bars, and hooks bar
-- layout/value methods.  Those patterns are safe on Era but are exactly the kind
-- of ownership that can taint modern Blizzard frame execution.
--
-- Forever therefore uses a deliberately narrow ownership model:
--   * Blizzard keeps every secure unit button and StatusBar.
--   * TurboFace may reposition protected Blizzard bars only OUT OF COMBAT and
--     anchors protected frames only to other Frames (never Texture/FontString).
--   * TurboFace artwork is rendered in UIParent-owned, mouse-disabled overlays.
--   * Runtime state lives only in external weak tables, never `_tf*` fields on
--     Blizzard objects.
--   * No StatusBar value hooks, no custom health/power arithmetic, no child
--     textures on Blizzard bars, and no secret gameplay value inspection.
--
-- This is the stable baseline.  Cosmetics can be added later only if they keep
-- those ownership boundaries intact.
-- =============================================================================

local FOREVER = {
    initialized = false,
    scheduled = false,
    pendingCombat = false,
    hooksInstalled = false,
    eventsRegistered = 0,
    lastReason = "startup",
    lastError = nil,
    refreshCount = 0,
    surfaces = setmetatable({}, { __mode = "k" }),
}
UF._foreverNative = FOREVER

local PLAYER_ART_BASE = "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\"
local ART = {
    player = PLAYER_ART_BASE .. "UI-Player-Portrait.tga",
    playerDruid = PLAYER_ART_BASE .. "UI-Player-Portrait-Druid.tga",
    target = PLAYER_ART_BASE .. "UI-Target-Portrait.tga",
    targetElite = PLAYER_ART_BASE .. "UI-EliteTarget-Portrait.tga",
    targetRare = PLAYER_ART_BASE .. "UI-RareTarget-Portrait.tga",
    targetRareElite = PLAYER_ART_BASE .. "UI-RareEliteTarget-Portrait.tga",
    party = PLAYER_ART_BASE .. "UI-Party-Portrait.tga",
    tot = PLAYER_ART_BASE .. "UI-ToT-Portrait.tga",
    pet = PLAYER_ART_BASE .. "UI-Pet-Portrait.tga",
}

local PLAYER_ART_X, PLAYER_ART_Y = -9, -3
local TARGET_ART_X, TARGET_ART_Y = 10, -3
local PLAYER = {
    nameX=115, nameY=30, nameW=112, nameH=16,
    healthX=113, healthY=47, healthW=116, healthH=15,
    powerX=113, powerY=63, powerW=116, powerH=15,
    portraitX=47, portraitY=31, portraitW=60, portraitH=60,
    reserveX=109, reserveY=81, reserveW=121, reserveH=14,
}
local PLAYER_DRUID = {
    nameX=115, nameY=30, nameW=112, nameH=16,
    healthX=113, healthY=47, healthW=116, healthH=15,
    powerX=113, powerY=63, powerW=116, powerH=15,
    druidX=111, druidY=81, druidW=118, druidH=15,
    portraitX=47, portraitY=31, portraitW=60, portraitH=60,
    reserveX=109, reserveY=97, reserveW=121, reserveH=14,
}
local TARGET = {
    nameX=30, nameY=32, nameW=112, nameH=16,
    healthX=27, healthY=49, healthW=118, healthH=15,
    powerX=27, powerY=65, powerW=118, powerH=15,
    portraitX=149, portraitY=31, portraitW=60, portraitH=60,
    reserveX=26, reserveY=81, reserveW=121, reserveH=14,
}
local PARTY = {
    artX=0, artY=0, artW=119, artH=48,
    portraitX=5, portraitY=6, portraitW=37, portraitH=37,
    nameX=45, nameY=6, nameW=70, nameH=10,
    healthX=45, healthY=18, healthW=70, healthH=10,
    powerX=45, powerY=31, powerW=70, powerH=10,
}
local TOT = {
    artX=0, artY=0, artW=98, artH=48,
    portraitX=5, portraitY=6, portraitW=37, portraitH=37,
    nameX=45, nameAboveY=2, nameBelowY=38, nameW=49, nameH=13,
    healthX=45, healthY=17, healthW=49, healthH=8,
    powerX=45, powerY=28, powerW=49, powerH=8,
}
local PET = {
    artX=0, artY=0, artW=119, artH=48,
    portraitX=5, portraitY=6, portraitW=37, portraitH=37,
    nameX=45, nameW=70, nameH=10, nameBelowY=37,
    healthX=45, healthY=8, healthW=70, healthH=13,
    powerX=45, powerY=22, powerW=70, powerH=13,
}

local function Gate(element)
    return ns.ModuleEnabled("unitframes", element)
end

local function DB()
    if type(TurboFaceDB) ~= "table" then TurboFaceDB = {} end
    if type(TurboFaceDB.unitframes) ~= "table" then TurboFaceDB.unitframes = {} end
    local db = TurboFaceDB.unitframes
    local defaults = ns.defaults and ns.defaults.unitframes or {}
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for k2, v2 in pairs(v) do copy[k2] = v2 end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    return db
end

local function SafeCall(label, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        FOREVER.lastError = label .. ": " .. tostring(a)
        return false
    end
    return true, a, b, c
end

local function SafeScale(frame, scale)
    if not frame or not frame.SetScale then return end
    if InCombatLockdown and InCombatLockdown() then
        FOREVER.pendingCombat = true
        return
    end
    pcall(frame.SetScale, frame, tonumber(scale) or 1)
end

local function FrameScaleRatio(frame)
    if not frame or not UIParent then return 1 end
    local ok1, a = pcall(frame.GetEffectiveScale, frame)
    local ok2, b = pcall(UIParent.GetEffectiveScale, UIParent)
    if ok1 and ok2 and type(a) == "number" and type(b) == "number" and b ~= 0 then
        return a / b
    end
    return 1
end

local function State(owner)
    if not owner then return nil end
    local st = FOREVER.surfaces[owner]
    if not st then
        st = {}
        FOREVER.surfaces[owner] = st
    end
    return st
end

local function EnsureArt(owner, key)
    if not owner or not UIParent then return nil end
    local st = State(owner)
    local art = st and st[key]
    if not art then
        art = CreateFrame("Frame", nil, UIParent)
        art:EnableMouse(false)
        art.texture = art:CreateTexture(nil, "ARTWORK")
        art.texture:SetAllPoints(art)
        st[key] = art
    end
    local strata = owner.GetFrameStrata and owner:GetFrameStrata() or "MEDIUM"
    local level = owner.GetFrameLevel and owner:GetFrameLevel() or 0
    art:SetFrameStrata(strata)
    art:SetFrameLevel(level + 20)
    art:SetScale(FrameScaleRatio(owner))
    return art
end

local function HideArt(owner, key)
    local st = owner and FOREVER.surfaces[owner]
    local art = st and st[key]
    if art then art:Hide() end
end

local function SetArtCentered(owner, key, texture, x, y, w, h)
    local art = EnsureArt(owner, key)
    if not art then return end
    art:ClearAllPoints()
    art:SetPoint("CENTER", owner, "CENTER", x, y)
    art:SetSize(w, h)
    art.texture:SetTexture(texture)
    art.texture:SetTexCoord(0, 1, 0, 1)
    art.texture:SetVertexColor(1, 1, 1, 1)
    art:Show()
end

local function SetArtTopLeft(owner, key, texture, x, y, w, h, u2, v2)
    local art = EnsureArt(owner, key)
    if not art then return end
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", owner, "TOPLEFT", x, -y)
    art:SetSize(w, h)
    art.texture:SetTexture(texture)
    art.texture:SetTexCoord(0, u2 or 1, 0, v2 or 1)
    art.texture:SetVertexColor(1, 1, 1, 1)
    art:Show()
end

local function SetProtectedBarPoint(bar, relativeFrame, relativePoint, x, y, w, h)
    if not bar or not relativeFrame then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", relativeFrame, relativePoint or "TOPLEFT", x, y)
    if bar.SetSize then bar:SetSize(w, h) end
end

local function SetRegionPoint(region, relativeFrame, relativePoint, x, y, w, h)
    if not region or not relativeFrame then return end
    if region.ClearAllPoints then region:ClearAllPoints() end
    if region.SetPoint then region:SetPoint("TOPLEFT", relativeFrame, relativePoint or "TOPLEFT", x, y) end
    if w and h and region.SetSize then region:SetSize(w, h) end
end

local function PlayerObjects()
    local pf = _G.PlayerFrame
    local container = pf and pf.PlayerFrameContainer
    local content = pf and pf.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local hc = main and main.HealthBarsContainer
    local manaArea = main and main.ManaBarArea
    local hb = _G.PlayerFrameHealthBar
        or (type(_G.PlayerFrame_GetHealthBar) == "function" and _G.PlayerFrame_GetHealthBar())
        or (hc and hc.HealthBar)
    local mb = _G.PlayerFrameManaBar
        or (type(_G.PlayerFrame_GetManaBar) == "function" and _G.PlayerFrame_GetManaBar())
        or (manaArea and manaArea.ManaBar)
    local portrait = _G.PlayerPortrait or (container and container.PlayerPortrait)
    local mask = _G.PlayerPortraitMask or (container and container.PlayerPortraitMask)
    local name = _G.PlayerName or (main and (main.Name or main.PlayerName))
    return pf, hc, hb, mb, portrait, mask, name
end

local function TargetObjects()
    local tf = _G.TargetFrame
    local container = tf and tf.TargetFrameContainer
    local content = tf and tf.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local hc = main and main.HealthBarsContainer
    local hb = _G.TargetFrameHealthBar or (hc and hc.HealthBar)
    local mb = _G.TargetFrameManaBar or (main and main.ManaBar)
    local portrait = _G.TargetFramePortrait or (container and container.Portrait) or (tf and tf.portrait)
    local name = _G.TargetFrameTextureFrameName or (main and main.Name) or (tf and tf.name)
    return tf, hb, mb, portrait, name
end

local function TotObjects()
    local f = _G.TargetFrameToT
    if not f then return end
    local hb = _G.TargetFrameToTHealthBar or f.HealthBar or f.healthBar or f.healthbar
    local mb = _G.TargetFrameToTManaBar or f.ManaBar or f.manaBar or f.manabar
    local portrait = _G.TargetFrameToTPortrait or f.Portrait or f.portrait
    local name = _G.TargetFrameToTTextureFrameName or _G.TargetFrameToTName or f.Name or f.name
    return f, hb, mb, portrait, name
end

local function PetObjects()
    local f = _G.PetFrame
    if not f then return end
    local hb = _G.PetFrameHealthBar or f.HealthBar or f.healthBar or f.healthbar
    local mb = _G.PetFrameManaBar or f.ManaBar or f.manaBar or f.manabar
    local portrait = _G.PetPortrait or _G.PetFramePortrait or f.Portrait or f.portrait
    local name = _G.PetName or f.Name or f.name
    return f, hb, mb, portrait, name
end

local function PartyFrameAt(index)
    if UF.GetPartyMemberFrame then return UF.GetPartyMemberFrame(index) end
    return _G["PartyMemberFrame" .. index]
end

local function PartyObjects(index)
    local f = PartyFrameAt(index)
    if not f then return nil end
    local hb = (UF.GetPartyHealthBar and UF.GetPartyHealthBar(index, f))
        or f.HealthBar or f.healthBar or _G["PartyMemberFrame" .. index .. "HealthBar"]
    local mb = f.ManaBar or f.manaBar or _G["PartyMemberFrame" .. index .. "ManaBar"]
    local portrait = f.Portrait or f.portrait or _G["PartyMemberFrame" .. index .. "Portrait"]
    local name = (f.PartyMemberOverlay and f.PartyMemberOverlay.Name)
        or f.Name or f.name or _G["PartyMemberFrame" .. index .. "Name"]
    return f, hb, mb, portrait, name
end

-- Register the modern/native UnitFrame ownership model behind the shared
-- provider contract. Supporting features can now ask the provider whether a
-- custom renderer is safe instead of branching on the client themselves.
function FOREVER:IsSupported()
    return ns.Client and ns.Client:IsForever() or false
end

function FOREVER:UsesDetachedRenderer()
    return true
end

function FOREVER:AllowCustomPredictions()
    return false
end

function FOREVER:AllowNanShield()
    return false
end

function FOREVER:AllowDruidPowerBar()
    return false
end

function FOREVER:GetPlayerHealthBar()
    local _, _, hb = PlayerObjects()
    return hb
end

function FOREVER:GetPlayerManaBar()
    local _, _, _, mb = PlayerObjects()
    return mb
end

-- The shared primary UnitFrames implementation deliberately retains Era's
-- readable renderer and geometry. Forever's adapter is authoritative for the
-- modern hierarchy, so publish the small set of object/geometry methods used
-- by other shared systems here instead of duplicating modern branches in
-- UnitFrames.lua.
function UF.GetPlayerHealthBar()
    local _, _, hb = PlayerObjects()
    return hb
end

function UF.GetPlayerManaBar()
    local _, _, _, mb = PlayerObjects()
    return mb
end

function UF.GetTargetHealthBar()
    local _, hb = TargetObjects()
    return hb
end

function UF.GetTargetManaBar()
    local _, _, mb = TargetObjects()
    return mb
end

function UF.GetToTHealthBar()
    local _, hb = TotObjects()
    return hb
end

function UF.GetToTManaBar()
    local _, _, mb = TotObjects()
    return mb
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("unitframes", "forever-native-safe", FOREVER, 100)
end

local function DruidArtActive()
    if UF.UsingDruidArt then
        local ok, result = pcall(UF.UsingDruidArt, UF)
        return ok and result == true
    end
    return false
end

local function PlayerLayout()
    return DruidArtActive() and PLAYER_DRUID or PLAYER
end

function UF:GetPlayerArtLayout()
    return PlayerLayout()
end

function UF:GetDruidPowerGeometry()
    return PLAYER_DRUID.druidX, PLAYER_DRUID.druidY, PLAYER_DRUID.druidW, PLAYER_DRUID.druidH
end

function UF:GetPlayerReserveGeometry()
    local g = PlayerLayout()
    return g.reserveX, g.reserveY, g.reserveW, g.reserveH
end

function UF:GetTargetReserveGeometry()
    return TARGET.reserveX, TARGET.reserveY, TARGET.reserveW, TARGET.reserveH
end

-- Keep the existing public helpers explicit on the modern adapter. Both
-- current player/target art sheets draw no built-in attack strip.
function UF:PlayerArtHasBuiltinAttackSlot()
    return false
end

function UF:TargetArtHasBuiltinAttackSlot()
    return false
end

-- Preserve the target tag-name amendment without invoking the Era renderer.
-- The value queried here is a public boolean on the validated Forever client;
-- all frame discovery stays inside the modern adapter.
function UF.ApplyTargetTagState()
    if not Gate("target") or not UnitExists("target") then return end
    local _, _, _, _, name = TargetObjects()
    if not name then return end
    local tagged = UnitIsTapDenied and UnitIsTapDenied("target") or false
    if tagged then
        local color = ns.BAR_BORDER_TAGGED
        if color then name:SetTextColor(color[1], color[2], color[3]) end
    else
        local db = DB()
        local color = db.targetNameColor
        if color then name:SetTextColor(ns:Color(color, 1, 1, 1)) end
    end
end
ns.UF_ApplyTargetTagState = UF.ApplyTargetTagState

local function SafeTargetArt()
    if not UnitExists("target") then return ART.target end
    local ok, classification = pcall(UnitClassification, "target")
    if not ok or (ns.API and ns.API.CanAccessValue and not ns.API.CanAccessValue(classification)) then
        return ART.target
    end
    if classification == "elite" or classification == "worldboss" then return ART.targetElite end
    if classification == "rare" then return ART.targetRare end
    if classification == "rareelite" then return ART.targetRareElite end
    return ART.target
end

local function ApplyPlayer(db)
    local pf, hc, hb, mb, portrait, mask, name = PlayerObjects()
    if not pf then return false end
    if not Gate("player") then HideArt(pf, "playerArt"); return true end

    SafeScale(pf, db.playerScale)
    SetArtCentered(pf, "playerArt", DruidArtActive() and ART.playerDruid or ART.player,
        PLAYER_ART_X, PLAYER_ART_Y, 256, 128)

    -- Geometry is translated from the 256x128 source sheet onto PlayerFrame.
    -- HealthBarsContainer stays intact so Blizzard's native loss/absorb/heal
    -- prediction children move with the native health bar.
    if hc and hb and hb.GetParent and hb:GetParent() == hc then
        SetProtectedBarPoint(hc, pf, "CENTER",
            PLAYER_ART_X - 128 + PLAYER.healthX,
            PLAYER_ART_Y + 64 - PLAYER.healthY,
            PLAYER.healthW, PLAYER.healthH)
        SetProtectedBarPoint(hb, hc, "TOPLEFT", 0, 0, PLAYER.healthW, PLAYER.healthH)
    elseif hb then
        SetProtectedBarPoint(hb, pf, "CENTER",
            PLAYER_ART_X - 128 + PLAYER.healthX,
            PLAYER_ART_Y + 64 - PLAYER.healthY,
            PLAYER.healthW, PLAYER.healthH)
    end
    if mb then
        SetProtectedBarPoint(mb, pf, "CENTER",
            PLAYER_ART_X - 128 + PLAYER.powerX,
            PLAYER_ART_Y + 64 - PLAYER.powerY,
            PLAYER.powerW, PLAYER.powerH)
    end
    SetRegionPoint(portrait, pf, "CENTER",
        PLAYER_ART_X - 128 + PLAYER.portraitX,
        PLAYER_ART_Y + 64 - PLAYER.portraitY,
        PLAYER.portraitW, PLAYER.portraitH)
    SetRegionPoint(mask, pf, "CENTER",
        PLAYER_ART_X - 128 + PLAYER.portraitX,
        PLAYER_ART_Y + 64 - PLAYER.portraitY,
        PLAYER.portraitW, PLAYER.portraitH)
    SetRegionPoint(name, pf, "CENTER",
        PLAYER_ART_X - 128 + PLAYER.nameX,
        PLAYER_ART_Y + 64 - PLAYER.nameY,
        PLAYER.nameW, PLAYER.nameH)
    return true
end

local function ApplyTarget(db)
    local tf, hb, mb, portrait, name = TargetObjects()
    if not tf then return false end
    if not Gate("target") then HideArt(tf, "targetArt"); return true end

    SafeScale(tf, db.targetScale)
    SetArtCentered(tf, "targetArt", SafeTargetArt(), TARGET_ART_X, TARGET_ART_Y, 256, 128)
    if hb then
        SetProtectedBarPoint(hb, tf, "CENTER",
            TARGET_ART_X - 128 + TARGET.healthX,
            TARGET_ART_Y + 64 - TARGET.healthY,
            TARGET.healthW, TARGET.healthH)
    end
    if mb then
        SetProtectedBarPoint(mb, tf, "CENTER",
            TARGET_ART_X - 128 + TARGET.powerX,
            TARGET_ART_Y + 64 - TARGET.powerY,
            TARGET.powerW, TARGET.powerH)
    end
    SetRegionPoint(portrait, tf, "CENTER",
        TARGET_ART_X - 128 + TARGET.portraitX,
        TARGET_ART_Y + 64 - TARGET.portraitY,
        TARGET.portraitW, TARGET.portraitH)
    SetRegionPoint(name, tf, "CENTER",
        TARGET_ART_X - 128 + TARGET.nameX,
        TARGET_ART_Y + 64 - TARGET.nameY,
        TARGET.nameW, TARGET.nameH)
    if name and name.SetShown then name:SetShown(db.showTargetName ~= false) end
    return true
end

local function ApplyToT(db)
    local f, hb, mb, portrait, name = TotObjects()
    if not f then return false end
    if not Gate("tot") then HideArt(f, "totArt"); return true end

    SetArtTopLeft(f, "totArt", ART.tot, TOT.artX, TOT.artY, TOT.artW, TOT.artH, 98/128, 48/64)
    if hb then SetProtectedBarPoint(hb, f, "TOPLEFT", TOT.artX + TOT.healthX, -(TOT.artY + TOT.healthY), TOT.healthW, TOT.healthH) end
    if mb then SetProtectedBarPoint(mb, f, "TOPLEFT", TOT.artX + TOT.powerX, -(TOT.artY + TOT.powerY), TOT.powerW, TOT.powerH) end
    SetRegionPoint(portrait, f, "TOPLEFT", TOT.artX + TOT.portraitX, -(TOT.artY + TOT.portraitY), TOT.portraitW, TOT.portraitH)
    local nameY = db.totNameAboveBars and TOT.nameAboveY or TOT.nameBelowY
    SetRegionPoint(name, f, "TOPLEFT", TOT.artX + TOT.nameX, -(TOT.artY + nameY), TOT.nameW, TOT.nameH)
    return true
end

local function ApplyPet(db)
    local f, hb, mb, portrait, name = PetObjects()
    if not f then return false end
    if not Gate("pet") then HideArt(f, "petArt"); return true end

    SafeScale(f, db.petScale)
    SetArtTopLeft(f, "petArt", ART.pet, PET.artX, PET.artY, PET.artW, PET.artH, 119/128, 48/64)
    if hb then SetProtectedBarPoint(hb, f, "TOPLEFT", PET.artX + PET.healthX, -(PET.artY + PET.healthY), PET.healthW, PET.healthH) end
    if mb then SetProtectedBarPoint(mb, f, "TOPLEFT", PET.artX + PET.powerX, -(PET.artY + PET.powerY), PET.powerW, PET.powerH) end
    SetRegionPoint(portrait, f, "TOPLEFT", PET.artX + PET.portraitX, -(PET.artY + PET.portraitY), PET.portraitW, PET.portraitH)
    local nameY = db.petNameAboveBars and -2 or -(PET.artY + PET.nameBelowY)
    if name then
        name:ClearAllPoints()
        if db.petNameAboveBars then
            name:SetPoint("BOTTOM", f, "TOPLEFT", PET.artX + PET.nameX + PET.nameW * .5, 2)
        else
            name:SetPoint("TOPLEFT", f, "TOPLEFT", PET.artX + PET.nameX, nameY)
        end
        if name.SetSize then name:SetSize(PET.nameW, PET.nameH) end
        if name.SetShown then name:SetShown(db.showPetName ~= false) end
    end
    return true
end

local function ApplyParty(db)
    local count = 0
    for i = 1, 4 do
        local f, hb, mb, portrait, name = PartyObjects(i)
        if f then
            count = count + 1
            if Gate("party") then
                SafeScale(f, db.partyScale)
                SetArtTopLeft(f, "partyArt", ART.party, PARTY.artX, PARTY.artY, PARTY.artW, PARTY.artH, 119/128, 48/64)
                if hb then SetProtectedBarPoint(hb, f, "TOPLEFT", PARTY.artX + PARTY.healthX, -(PARTY.artY + PARTY.healthY), PARTY.healthW, PARTY.healthH) end
                if mb then SetProtectedBarPoint(mb, f, "TOPLEFT", PARTY.artX + PARTY.powerX, -(PARTY.artY + PARTY.powerY), PARTY.powerW, PARTY.powerH) end
                SetRegionPoint(portrait, f, "TOPLEFT", PARTY.artX + PARTY.portraitX, -(PARTY.artY + PARTY.portraitY), PARTY.portraitW, PARTY.portraitH)
                SetRegionPoint(name, f, "TOPLEFT", PARTY.artX + PARTY.nameX, -(PARTY.artY + PARTY.nameY), PARTY.nameW, PARTY.nameH)
                if name and name.SetShown then name:SetShown(db.showPartyNames ~= false) end
            else
                HideArt(f, "partyArt")
            end
        end
    end
    FOREVER.partyFrames = count
    return true
end

local function ApplyAll(reason)
    FOREVER.lastReason = reason or FOREVER.lastReason
    if not Gate(nil) then
        for owner, st in pairs(FOREVER.surfaces) do
            if st.playerArt then st.playerArt:Hide() end
            if st.targetArt then st.targetArt:Hide() end
            if st.totArt then st.totArt:Hide() end
            if st.petArt then st.petArt:Hide() end
            if st.partyArt then st.partyArt:Hide() end
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        FOREVER.pendingCombat = true
        return
    end
    FOREVER.pendingCombat = false
    local db = DB()
    local ok = true
    ok = SafeCall("player", ApplyPlayer, db) and ok
    ok = SafeCall("target", ApplyTarget, db) and ok
    ok = SafeCall("tot", ApplyToT, db) and ok
    ok = SafeCall("pet", ApplyPet, db) and ok
    ok = SafeCall("party", ApplyParty, db) and ok
    if ok then FOREVER.lastError = nil end
    FOREVER.refreshCount = FOREVER.refreshCount + 1

    -- Keep standalone timer rows aligned to the new native geometry. DruidPowerBar
    -- owns its own refresh lifecycle; calling it here would recurse through its
    -- RefreshPlayerBackdrop callback.
    if ns.ST and ns.ST.ReanchorPlayer then pcall(ns.ST.ReanchorPlayer) end
end

local function Schedule(reason)
    FOREVER.lastReason = reason or FOREVER.lastReason
    if InCombatLockdown and InCombatLockdown() then
        FOREVER.pendingCombat = true
        return
    end
    if FOREVER.scheduled then return end
    FOREVER.scheduled = true
    local function run()
        FOREVER.scheduled = false
        ApplyAll(FOREVER.lastReason)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end
UF.ScheduleForeverNativeRefresh = Schedule

local eventFrame
local function RegisterEvent(event)
    if not eventFrame then return false end
    local ok = ns.RegisterEvent and ns.RegisterEvent(eventFrame, event)
    if ok then FOREVER.eventsRegistered = FOREVER.eventsRegistered + 1 end
    return ok
end

local function RegisterUnitEvent(event, u1, u2)
    if not eventFrame then return false end
    local ok = ns.RegisterUnitEvent and ns.RegisterUnitEvent(eventFrame, event, u1, u2)
    if ok then FOREVER.eventsRegistered = FOREVER.eventsRegistered + 1 end
    return ok
end

local function EnsureEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            if FOREVER.pendingCombat then Schedule("combat-end") end
            return
        end
        if event == "UNIT_NAME_UPDATE" and unit then
            if unit ~= "player" and unit ~= "target" and unit ~= "pet" and not unit:match("^party[1-4]$") then return end
        end
        Schedule(event)
    end)

    RegisterEvent("PLAYER_ENTERING_WORLD")
    RegisterEvent("PLAYER_REGEN_ENABLED")
    RegisterEvent("PLAYER_TARGET_CHANGED")
    RegisterEvent("GROUP_ROSTER_UPDATE")
    RegisterEvent("PARTY_LEADER_CHANGED")
    RegisterEvent("UNIT_PET")
    RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    RegisterEvent("UNIT_NAME_UPDATE")
    RegisterEvent("UNIT_FACTION")
    RegisterUnitEvent("UNIT_TARGET", "target")
    RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target")
    -- Modern Edit Mode can rebuild internal anchors without moving the outer
    -- unit button. Register opportunistically; the compatibility wrapper skips
    -- unknown events rather than aborting UnitFrames init.
    RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
end

-- Replace only the runtime entry points.  All Era functions remain in
-- UnitFrames.lua and are untouched for Classic Era clients.
function UF:Init()
    if FOREVER.initialized then return end
    FOREVER.initialized = true
    DB()
    EnsureEvents()
    Schedule("init")
end

function UF:Refresh()
    Schedule("options-refresh")
end

function UF:RefreshPlayerBackdrop()
    -- Forever intentionally leaves Blizzard's native bar backgrounds/prediction
    -- layers intact. The detached artwork is the only TurboFace backdrop layer.
    Schedule("player-backdrop-refresh")
end

function UF:RefreshForeverPlayerVisualAdapter()
    Schedule("player-visual-refresh")
end

function UF:GetDiagnostics()
    local pf, _, ph, pm = PlayerObjects()
    local tf, th, tm = TargetObjects()
    local tot, toh, tom = TotObjects()
    local pet, peh, pem = PetObjects()
    local function Protected(frame)
        if not frame or not frame.IsProtected then return nil end
        local ok, v = pcall(frame.IsProtected, frame)
        return ok and v or nil
    end
    return {
        mode = "forever-native-safe",
        initialized = FOREVER.initialized,
        scheduled = FOREVER.scheduled,
        pendingCombat = FOREVER.pendingCombat,
        events = FOREVER.eventsRegistered,
        refreshCount = FOREVER.refreshCount,
        reason = FOREVER.lastReason,
        lastError = FOREVER.lastError,
        player = pf ~= nil,
        playerHealth = ph ~= nil,
        playerPower = pm ~= nil,
        playerProtected = Protected(pf),
        target = tf ~= nil,
        targetHealth = th ~= nil,
        targetPower = tm ~= nil,
        targetProtected = Protected(tf),
        tot = tot ~= nil,
        totHealth = toh ~= nil,
        totPower = tom ~= nil,
        pet = pet ~= nil,
        petHealth = peh ~= nil,
        petPower = pem ~= nil,
        partyFrames = FOREVER.partyFrames or 0,
        nativeValues = true,
        customPredictions = false,
        nanShield = false,
    }
end

-- Apply once after every file-level initializer has had a chance to finish.
Schedule("file-load")
