local addonName, ns = ...
local L = ns.L

-- TurboFace Core
-- Nameplate handling via C_NamePlateManager, NAME_PLATE_UNIT_ADDED events, C_NamePlate

-- Incompatible addons list
local IncompatibleAddOns = {
    "Kui_Nameplates",
    "TidyPlates_ThreatPlates",
    "PlateBuffs",
}

-- StaticPopup for addon conflicts
StaticPopupDialogs["TURBOFACE_ADDON_CONFLICT"] = {
    text = L.ConflictText,
    button1 = L.DisableIt,
    button2 = L.DisableTP,
    OnAccept = function(self, data)
        ns.API.DisableAddOn(data)
        ReloadUI()
    end,
    OnCancel = function()
        ns.API.DisableAddOn("TurboFace")
        ReloadUI()
    end,
    timeout = 0,
    showAlert = 1,
    whileDead = 1,
    hideOnEscape = false,
}

-- Cache frequently used globals
local UnitExists = ns.API.ReadUnitExists
local UnitIsPlayer = ns.API.ReadUnitIsPlayer
local UnitIsFriend = ns.API.ReadUnitIsFriend
local UnitIsUnit = ns.API.ReadUnitIsUnit
-- UnitIsPet does not exist in Classic Era 1.15.8; use UnitIsUnit("pet", unit)
local function UnitIsPet(unit) return UnitIsUnit and UnitIsUnit("pet", unit) or false end
local UnitPlayerControlled = ns.API.ReadUnitPlayerControlled
local UnitGUID = ns.API.ReadUnitGUID
local GetTime = GetTime
local GetCVarBool = GetCVarBool
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local wipe = wipe
local pairs = pairs
local tinsert = tinsert
local strlower = string.lower
-- GetNamePlateSize -> read nameplateWidth/nameplateHeight CVars directly in Classic Era
local C_NamePlate = C_NamePlate
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local WorldFrame = WorldFrame
local UIParent = UIParent
local RunNextFrame = RunNextFrame
local GetAddOnMetadata = ns.API.GetAddOnMetadata

local ActivateCoreNameplateEvents
local function CorePolicy(key)
    return ns.Client and ns.Client.GetCorePolicy and ns.Client:GetCorePolicy(key) == true
end

-- Native suppression exists only for explicit TurboFace presentation modes
-- (friendly identity-only / damaged-only and TurboFace aura replacement).
-- Ordinary Blizzard nameplate regions remain the baseline owner.

local _blizzHooksInstalled = false
local nativeSuppressionState = setmetatable({}, { __mode = "k" })

-- Forever nameplates remain Blizzard-owned. This is deliberately presentation
-- only: discover the live native castbar, apply media/font when writable, and
-- never call UnitCastingInfo or derive interrupt/cast state.
local function ApplyNativeNameplateCastPresentation(unitFrame)
    if not CorePolicy("styleNativeNameplateCastbar") or not unitFrame then return end
    local castBar = unitFrame.castBar or unitFrame.CastBar or unitFrame.SpellCastBar
        or unitFrame.NameplateCastBar
    if not castBar and unitFrame.CastBarsContainer then
        castBar = unitFrame.CastBarsContainer.castBar or unitFrame.CastBarsContainer.CastBar
    end
    if not castBar then return end

    local texture = ns.GetTexture and ns.GetTexture(TurboFaceDB and TurboFaceDB.texture)
    if texture and castBar.SetStatusBarTexture then
        pcall(castBar.SetStatusBarTexture, castBar, texture)
    end
    local text = castBar.Text or castBar.text or castBar.SpellName or castBar.spellName
    if text and ns.StyleFont then
        pcall(ns.StyleFont, ns, text, nil, 10, "nameplates")
    end
    unitFrame._tfNativeCastBarResolved = castBar
end
local ConfigureNativeNameplateChassis -- forward declaration used by the driver hook
local ConfigureNativeFriendlyIdentityOnly -- native friendly NPC name/title-only mode

-- Friendly NPC: Name + Title Only uses a hybrid native identity surface:
-- Blizzard keeps ownership of the NPC name glyph/text/lifecycle, while
-- TurboFace owns only the supplemental NPC-title line and a narrow anchor
-- amendment. Classic Era 1.15.9 marks native name FontStrings as restricted for
-- geometry reads, so TurboFace MUST NOT call GetPoint/GetNumPoints on uf.name.
-- Instead we mirror Blizzard's published UpdateAnchors write policy and apply
-- TurboFace's additional 10px identity offset. The
-- amendment is reasserted after Blizzard's own UnitFrame:UpdateAnchors pass and
-- released by asking Blizzard to rebuild its normal anchors.
local FRIENDLY_NATIVE_NAME_EXTRA_Y = -10
local nativeFriendlyNameLayoutState = setmetatable({}, { __mode = "k" }) -- [UnitFrame] = state

local function SetNativeFriendlyNameAnchors(nameplate, extraY)
    local uf = nameplate and nameplate.UnitFrame
    local name = uf and uf.name
    local healthContainer = uf and uf.HealthBarsContainer
    if not (uf and name and healthContainer and name.ClearAllPoints and name.SetPoint) then return false end

    extraY = extraY or 0
    local insideHealthBar = NamePlateSetupOptions and NamePlateSetupOptions.unitNameInsideHealthBar == true

    local ok = pcall(name.ClearAllPoints, name)
    if not ok then return false end
    if name.SetJustifyH then pcall(name.SetJustifyH, name, "CENTER") end

    -- Match Blizzard's IsShowOnlyName branch from NamePlateUnitFrameMixin:
    -- UpdateAnchors, but add TurboFace's identity-only Y offset. Use raw
    -- SetPoint instead of PixelUtil so no helper attempts a restricted geometry
    -- read from the native FontString.
    local ok1, ok2
    if insideHealthBar then
        ok1 = pcall(name.SetPoint, name, "LEFT", healthContainer, "LEFT", 4, extraY)
        ok2 = pcall(name.SetPoint, name, "RIGHT", healthContainer, "RIGHT", -4, extraY)
    else
        local y = 2 + extraY
        ok1 = pcall(name.SetPoint, name, "BOTTOMLEFT", healthContainer, "TOPLEFT", 4, y)
        ok2 = pcall(name.SetPoint, name, "BOTTOMRIGHT", healthContainer, "TOPRIGHT", -4, y)
    end
    return ok1 == true and ok2 == true
end

-- Static restoration fallback for the unlikely case where the live Blizzard
-- UpdateAnchors method is unavailable. This mirrors the 1.15.9 name-anchor
-- branch without reading restricted name geometry.
local function RestoreNativeFriendlyNameStatic(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    local name = uf and uf.name
    local healthContainer = uf and uf.HealthBarsContainer
    local healthBar = healthContainer and healthContainer.healthBar
    local healthBarText = healthBar and healthBar.Text
    if not (uf and name and healthContainer and name.ClearAllPoints and name.SetPoint) then return false end

    local showOnlyName = false
    if type(uf.IsShowOnlyName) == "function" and securecall then
        local ok, value = pcall(securecall, uf.IsShowOnlyName, uf)
        showOnlyName = ok and value == true
    end
    local insideHealthBar = NamePlateSetupOptions and NamePlateSetupOptions.unitNameInsideHealthBar == true

    if not pcall(name.ClearAllPoints, name) then return false end
    if showOnlyName then
        if name.SetJustifyH then pcall(name.SetJustifyH, name, "CENTER") end
        if insideHealthBar then
            local a = pcall(name.SetPoint, name, "LEFT", healthContainer, "LEFT", 4, 0)
            local b = pcall(name.SetPoint, name, "RIGHT", healthContainer, "RIGHT", -4, 0)
            return a and b
        end
        local a = pcall(name.SetPoint, name, "BOTTOMLEFT", healthContainer, "TOPLEFT", 4, 2)
        local b = pcall(name.SetPoint, name, "BOTTOMRIGHT", healthContainer, "TOPRIGHT", -4, 2)
        return a and b
    end

    if name.SetJustifyH then pcall(name.SetJustifyH, name, "LEFT") end
    if insideHealthBar then
        local a = pcall(name.SetPoint, name, "LEFT", healthContainer, "LEFT", 4, 0)
        local b
        if healthBarText then
            b = pcall(name.SetPoint, name, "RIGHT", healthBarText, "LEFT", -2, 0)
        else
            b = pcall(name.SetPoint, name, "RIGHT", healthContainer, "RIGHT", -4, 0)
        end
        return a and b
    end

    local a = pcall(name.SetPoint, name, "BOTTOMLEFT", healthContainer, "TOPLEFT", 4, 2)
    local b
    if healthBarText then
        b = pcall(name.SetPoint, name, "BOTTOMRIGHT", healthBarText, "BOTTOMLEFT", -2, 0)
    else
        b = pcall(name.SetPoint, name, "BOTTOMRIGHT", healthContainer, "TOPRIGHT", -4, 2)
    end
    return a and b
end

local function ResolveNameplateFromNativeUnitFrame(uf, fallback)
    if uf and type(uf.GetNamePlateFrame) == "function" and securecall then
        local ok, np = pcall(securecall, uf.GetNamePlateFrame, uf)
        if ok and np then return np end
    end
    return fallback
end

local function EnsureNativeFriendlyNameAnchorHook(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return nil end

    local state = nativeFriendlyNameLayoutState[uf]
    if not state then
        state = { enabled = false, syncing = false }
        nativeFriendlyNameLayoutState[uf] = state
    end
    state.nameplate = nameplate

    if not state.updateAnchorsHooked and type(uf.UpdateAnchors) == "function" and hooksecurefunc then
        local ok, err = pcall(hooksecurefunc, uf, "UpdateAnchors", function(frame)
            local current = nativeFriendlyNameLayoutState[frame]
            if not current or not current.enabled or current.syncing then return end

            local np = ResolveNameplateFromNativeUnitFrame(frame, current.nameplate)
            current.nameplate = np
            if not (np and np._tfTurboNativeIdentityOnly == true) then return end

            current.syncing = true
            SetNativeFriendlyNameAnchors(np, FRIENDLY_NATIVE_NAME_EXTRA_Y)
            current.syncing = false
        end)
        if ok then
            state.updateAnchorsHooked = true
            state.lastHookError = nil
        else
            state.lastHookError = tostring(err)
        end
    end
    return state
end

local function RestoreNativeFriendlyNamePosition(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return false end
    local state = nativeFriendlyNameLayoutState[uf]
    local wasEnabled = state and state.enabled == true
    if state then
        state.enabled = false
        state.nameplate = nameplate
    end

    -- If TurboFace never applied its identity-only name offset, there is
    -- nothing to restore. Avoid entering Blizzard's native anchor routine for
    -- ordinary nameplates entirely.
    if not wasEnabled and CorePolicy("staticFriendlyIdentityRestore") then return true end

    -- On clients with restricted native-frame measurement, Blizzard's UpdateAnchors path performs restricted frame
    -- measurements (including GetPoint). Calling that method from addon code can
    -- therefore raise FrameMeasurement failures even through securecall/pcall.
    -- Use TurboFace's write-only static restoration there instead; it mirrors
    -- Blizzard's anchor policy without reading restricted geometry. Classic Era
    -- keeps the native method first so Blizzard can restore its own live policy.
    if not CorePolicy("staticFriendlyIdentityRestore") and type(uf.UpdateAnchors) == "function" and securecall then
        local ok = pcall(securecall, uf.UpdateAnchors, uf)
        if ok then return true end
    end
    return RestoreNativeFriendlyNameStatic(nameplate)
end

local function ApplyNativeFriendlyNamePosition(nameplate)
    local state = EnsureNativeFriendlyNameAnchorHook(nameplate)
    if not state or state.syncing then return false end

    state.enabled = true
    state.nameplate = nameplate
    state.syncing = true
    local ok = SetNativeFriendlyNameAnchors(nameplate, FRIENDLY_NATIVE_NAME_EXTRA_Y)
    state.syncing = false
    if not ok then state.enabled = false end
    return ok
end

local function HideNativeFriendlyNPCTitle(nameplate)
    local title = nameplate and nameplate._tfFriendlyNPCTitle
    if title then
        title:SetText("")
        title:Hide()
    end
end

local function ForceNativeAlphaZero(region, owner)
    if not region or not region.SetAlpha then return end
    local state = nativeSuppressionState[region]
    if not state then
        state = { owner = owner }
        nativeSuppressionState[region] = state
    else
        state.owner = owner
    end
    if state.forcing then return end
    state.forcing = true
    region:SetAlpha(0)
    state.forcing = nil
end

local function NativeSuppressionAlphaHook(self, alpha)
    local current = nativeSuppressionState[self]
    local root = current and current.owner
    if current and current.suppressed == true and not current.forcing
        and root and root._tfNativeSuppressionActive then
        -- Remember Blizzard's latest intended alpha while the region is
        -- suppressed. When ownership is released, restore that live value
        -- rather than inventing alpha 1 for a native health/threat region.
        current.restoreAlpha = alpha
        if alpha ~= 0 then ForceNativeAlphaZero(self, root) end
    end
end

local function NativeSuppressionShowHook(self)
    local current = nativeSuppressionState[self]
    local root = current and current.owner
    if current and current.suppressed == true and root and root._tfNativeSuppressionActive then
        ForceNativeAlphaZero(self, root)
    end
end

local function HookNativeSuppression(region, owner)
    if not region then return end
    local state = nativeSuppressionState[region]
    if not state then
        state = { owner = owner }
        nativeSuppressionState[region] = state
    else
        state.owner = owner
    end

    if region.SetAlpha and not state.alphaHooked then
        state.alphaHooked = true
        hooksecurefunc(region, "SetAlpha", NativeSuppressionAlphaHook)
    end

    if region.HookScript and not state.showHooked then
        state.showHooked = true
        region:HookScript("OnShow", NativeSuppressionShowHook)
    elseif region.Show and not state.showMethodHooked then
        -- Texture/FontString regions do not have scripts. Hook Show directly so
        -- an ignore-parent-alpha region cannot reappear in the identity-only shell.
        state.showMethodHooked = true
        hooksecurefunc(region, "Show", NativeSuppressionShowHook)
    end
end

local function SetNativeRegionSuppressed(region, owner, suppressed)
    if not region then return end
    if suppressed ~= false then
        HookNativeSuppression(region, owner)
        local state = nativeSuppressionState[region]
        if state and state.suppressed ~= true then
            state.restoreAlpha = region.GetAlpha and region:GetAlpha() or 1
        end
        if state then state.suppressed = true end
        ForceNativeAlphaZero(region, owner)
    else
        local state = nativeSuppressionState[region]
        if not state then return end
        state.owner = owner
        local wasSuppressed = state and state.suppressed == true
        local restoreAlpha = state and state.restoreAlpha
        if state then
            state.suppressed = false
            state.restoreAlpha = nil
        end
        -- A region that was never suppressed is already entirely Blizzard-
        -- owned; preserving it must not write any native presentation state.
        if wasSuppressed and region.SetAlpha then
            region:SetAlpha(restoreAlpha ~= nil and restoreAlpha or 1)
        end
    end
end

local function SuppressNativeRegion(region, owner)
    SetNativeRegionSuppressed(region, owner, true)
end

local function PreserveNativeRegion(region, owner)
    SetNativeRegionSuppressed(region, owner, false)
end

-- Snapshot Blizzard-owned objects before TurboFace attaches augmentation to the
-- native health bar. Future suppression passes operate only on this baseline,
-- so a recycled pooled plate can never accidentally install alpha-zero hooks on
-- TurboFace's own DoT/threat/absorb/text regions.
local function GetNativeSuppressionBaseline(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return nil end
    if uf._tfTurboNativeBaseline then return uf._tfTurboNativeBaseline end

    local baseline = {
        frames = {}, regions = {}, rootRegions = {},
        frameSet = {}, regionSet = {}, rootRegionSet = {},
    }
    local seenFrames, seenRegions = {}, {}
    local function CaptureFrame(frame, depth)
        if not frame or seenFrames[frame] or (depth or 0) > 8 then return end
        seenFrames[frame] = true
        baseline.frames[#baseline.frames + 1] = frame
        baseline.frameSet[frame] = true
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if not seenRegions[region] then
                    seenRegions[region] = true
                    baseline.regions[#baseline.regions + 1] = region
                    baseline.regionSet[region] = true
                end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                CaptureFrame(child, (depth or 0) + 1)
            end
        end
    end
    CaptureFrame(uf, 0)
    if nameplate.GetRegions then
        for _, region in ipairs({ nameplate:GetRegions() }) do
            baseline.rootRegions[#baseline.rootRegions + 1] = region
            baseline.rootRegionSet[region] = true
        end
    end
    uf._tfTurboNativeBaseline = baseline
    return baseline
end

-- Builds before 0.17.87 walked the live HealthBarsContainer when entering the
-- friendly identity-only presentation. If a pooled plate already had additive
-- TurboFace textures attached, that live walk installed the native alpha-zero
-- suppression hook on them too. A later hostile/chassis rebind could set the
-- DoT texture to alpha 1 and have the stale hook immediately force it back to
-- zero. Release only suppression state that we own but that is absent from the
-- immutable pre-augmentation Blizzard baseline.
local function ReleaseNonBaselineSuppression(uf, baseline)
    if not uf or not baseline then return end
    local visited = {}
    local function Walk(frame, depth)
        if not frame or visited[frame] or (depth or 0) > 8 then return end
        visited[frame] = true

        local frameState = nativeSuppressionState[frame]
        if frameState and frameState.owner == uf and not baseline.frameSet[frame] then
            PreserveNativeRegion(frame, uf)
        end
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                local state = nativeSuppressionState[region]
                if state and state.owner == uf and not baseline.regionSet[region]
                    and not baseline.rootRegionSet[region] then
                    PreserveNativeRegion(region, uf)
                end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                Walk(child, (depth or 0) + 1)
            end
        end
    end
    Walk(uf, 0)
end


local function RestoreBaselineNativePresentation(nameplate, uf)
    local baseline = GetNativeSuppressionBaseline(nameplate)
    if not baseline then return end
    for i = 1, #baseline.frames do PreserveNativeRegion(baseline.frames[i], uf) end
    for i = 1, #baseline.regions do PreserveNativeRegion(baseline.regions[i], uf) end
    for i = 1, #baseline.rootRegions do PreserveNativeRegion(baseline.rootRegions[i], uf) end
    ReleaseNonBaselineSuppression(uf, baseline)
end

local function NativeNameplateAddedHook(_, unit)
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    local uf = np and np.UnitFrame
    if not (np and uf and uf._tfNativeSuppressionActive) then return end
    if uf._tfTurboSuppressionMode == "chassis" and ConfigureNativeNameplateChassis then
        ConfigureNativeNameplateChassis(np)
        if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(np, unit) end
    elseif uf._tfTurboSuppressionMode == "friendly-identity" and ConfigureNativeFriendlyIdentityOnly then
        ConfigureNativeFriendlyIdentityOnly(np)
        if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(np, unit) end
    else
        -- No valid TurboFace presentation mode should retain suppression. Fail
        -- open to Blizzard rather than falling back to the retired full-hide path.
        uf._tfNativeSuppressionActive = false
        uf._tfTurboSuppressionMode = nil
        RestoreBaselineNativePresentation(np, uf)
        if ns.RestoreNativeNameplateNameShadow then ns.RestoreNativeNameplateNameShadow(np) end
        if ns.RestoreNativeNameplateHealthTextPosition then
            ns.RestoreNativeNameplateHealthTextPosition(np)
        end
        if ns.RestoreNativeRarityIconPosition then ns.RestoreNativeRarityIconPosition(np) end
    end
end

local function InstallBlizzHooks()
    if _blizzHooksInstalled then return end
    _blizzHooksInstalled = true

    -- Hook NamePlateDriverFrame.OnNamePlateAdded which fires when unit assigned.
    -- 1.15.9 can independently restore alpha on nested health-bar regions, so
    -- suppress the complete native tree rather than only UnitFrame/healthBar.
    if CorePolicy("installNativeDriverAddedHook") and NamePlateDriverFrame and NamePlateDriverFrame.OnNamePlateAdded then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", NativeNameplateAddedHook)
    end

    -- Native style/size and information-display changes can replace the name
    -- FontObject and rerun Blizzard's health-text anchors. Refresh TurboFace's
    -- narrow presentation amendments only after Blizzard has completed its
    -- own option/layout pass. Native HP FontStrings are restricted in 1.15.9;
    -- the health-text amendment writes anchors only and never measures them.
    if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
            local function RefreshAfterNativeOptions()
                if ns.RefreshNativeNameShadows then ns.RefreshNativeNameShadows() end
                if ns.RefreshNativeHealthTextCentering then
                    ns.RefreshNativeHealthTextCentering()
                end
                if ns.RefreshNativeRarityIconPositions then
                    ns.RefreshNativeRarityIconPositions()
                end
                -- Blizzard can rebuild native name anchors while applying its own
                -- nameplate options. Reapply the identity-only 10px offset only
                -- after Blizzard's native pass has fully unwound.
                if ConfigureNativeFriendlyIdentityOnly and C_NamePlate and C_NamePlate.GetNamePlates then
                    for _, np in ipairs(C_NamePlate.GetNamePlates()) do
                        if np and np._tfTurboNativeIdentityOnly == true then
                            ConfigureNativeFriendlyIdentityOnly(np)
                        end
                    end
                end
            end
            if CorePolicy("deferNativeNameplateCallbacks") and RunNextFrame then
                RunNextFrame(RefreshAfterNativeOptions)
            else
                RefreshAfterNativeOptions()
            end
        end)
    end

    -- NativeHealthTextStyle.lua post-hooks UpdateAnchors on each actual pooled
    -- Blizzard unit frame. No hooks are installed on the restricted FontStrings,
    -- and no timer or polling driver is used.
end

-- Blizzard-native full-plate mode. Restore Blizzard's complete baseline, then
-- suppress only the exact presentation piece TurboFace still replaces: the
-- native aura row while TurboFace Auras is active. Blizzard owns raid-target
-- art, the unit name and
-- level presentation alongside health, cast, classification, and threat;
-- TurboFace adds only an independent glyph underlay behind native NPC names.
-- This denylist is
-- intentionally future-proof: new Blizzard widgets and indicators
-- remain native-owned without requiring TurboFace to discover and allowlist them.
ConfigureNativeNameplateChassis = function(nameplate)
    if not nameplate then return nil end
    local uf = nameplate.UnitFrame
    if not uf then return nil end
    RestoreNativeFriendlyNamePosition(nameplate)
    HideNativeFriendlyNPCTitle(nameplate)
    local healthContainer = uf.HealthBarsContainer
    local healthBar = uf.healthBar or (healthContainer and healthContainer.healthBar)
    if not healthBar then
        uf._tfNativeSuppressionActive = false
        uf._tfTurboSuppressionMode = nil
        RestoreBaselineNativePresentation(nameplate, uf)
        return nil
    end

    InstallBlizzHooks()
    uf._tfNativeSuppressionActive = true
    uf._tfTurboSuppressionMode = "chassis"
    nameplate._tfTurboNativeHealthChassis = true
    nameplate._tfTurboNativeIdentityOnly = nil

    -- Work only from the pre-augmentation Blizzard baseline. Restoring it first
    -- ensures a pooled plate that previously used full suppression cannot carry
    -- hidden native regions into chassis mode.
    local baseline = GetNativeSuppressionBaseline(nameplate)
    if baseline then
        RestoreBaselineNativePresentation(nameplate, uf)
    end

    local suppressed = {}
    local function SuppressSubtree(frame, depth)
        if not frame or suppressed[frame] or (depth or 0) > 8
            or not baseline or not baseline.frameSet[frame] then return end
        suppressed[frame] = true
        SuppressNativeRegion(frame, uf)
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if baseline.regionSet[region] then SuppressNativeRegion(region, uf) end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                SuppressSubtree(child, (depth or 0) + 1)
            end
        end
    end

    -- TurboFace replaces the native aura row only when its Aura family is
    -- actually active. If Auras is disabled, Blizzard keeps that row too; the
    -- Nameplates master must not retain ownership for a dormant child feature.
    local replaceNativeAuras = ((not ns.ModuleEnabled) or ns.ModuleEnabled("auras"))
        and not (ns.API.ShouldAurasBeSecret and ns.API.ShouldAurasBeSecret())
    if replaceNativeAuras then SuppressSubtree(uf.AurasFrame, 0) end

    if ns.ApplyNativeHealthTextCentering then
        ns.ApplyNativeHealthTextCentering(nameplate)
    end
    if ns.ApplyNativeRarityIconPosition then
        ns.ApplyNativeRarityIconPosition(nameplate)
    end
    ApplyNativeNameplateCastPresentation(uf)
    return healthBar
end

-- Friendly NPC native identity-only mode. Blizzard continues to own and render
-- the canonical NPC name, while TurboFace alpha-suppresses the non-identity
-- chassis, shifts that native name down by TurboFace's 10px identity offset,
-- and adds only the supplemental NPC-title line underneath. The title itself is
-- rendered by ApplyFriendlyNPCNativeIdentityOnly after the tooltip/cache lookup.
ConfigureNativeFriendlyIdentityOnly = function(nameplate)
    if not nameplate then return false end
    local uf = nameplate.UnitFrame
    if not uf then return false end

    InstallBlizzHooks()
    uf._tfNativeSuppressionActive = true
    uf._tfTurboSuppressionMode = "friendly-identity"
    nameplate._tfTurboNativeHealthChassis = nil
    nameplate._tfTurboNativeIdentityOnly = true

    -- Always begin from Blizzard's captured baseline. A pooled plate may have
    -- previously been fully suppressed or used the ordinary native chassis.
    local baseline = GetNativeSuppressionBaseline(nameplate)
    if baseline then RestoreBaselineNativePresentation(nameplate, uf) end

    local suppressed = {}
    local function SuppressSubtree(frame, depth)
        if not frame or suppressed[frame] or (depth or 0) > 8
            or not baseline or not baseline.frameSet[frame] then return end
        suppressed[frame] = true
        SuppressNativeRegion(frame, uf)
        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                if baseline.regionSet[region] then SuppressNativeRegion(region, uf) end
            end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                SuppressSubtree(child, (depth or 0) + 1)
            end
        end
    end

    -- Hide the health/cast/art chassis while deliberately leaving uf.name and
    -- any other unknown identity FontStrings alone. Selective suppression is
    -- safer than suppressing UnitFrame itself because native identity remains
    -- fully Blizzard-owned and can continue to update on hover/target/recycle.
    SuppressSubtree(uf.HealthBarsContainer, 0)
    SuppressSubtree(uf.castBar, 0)
    SuppressSubtree(uf.CastBarsContainer, 0)
    SuppressSubtree(uf.AurasFrame, 0)
    SuppressSubtree(uf.ClassificationFrame, 0)
    SuppressSubtree(uf.PlayerLevelDiffFrame, 0)
    SuppressSubtree(uf.LevelFrame, 0)
    SuppressSubtree(uf.WidgetContainer, 0)
    SuppressSubtree(uf.SoftTargetFrame, 0)

    -- These are root-level visual regions on modern/native nameplate layouts,
    -- not children of HealthBarsContainer. Hide them explicitly so the result
    -- is genuinely identity-only without assuming a fixed Blizzard art style.
    for _, key in ipairs({
        "behindCameraIcon", "selectionHighlight", "aggroHighlight",
        "aggroHighlightBase", "aggroHighlightAdditive", "aggroHighlightMask",
        "aggroFlash",
    }) do
        SuppressNativeRegion(uf[key], uf)
    end

    -- Defensive explicit preserve for the canonical native name region. The
    -- supplemental title is TurboFace-owned and lives outside this native tree.
    PreserveNativeRegion(uf.name, uf)
    ApplyNativeFriendlyNamePosition(nameplate)
    return uf.name ~= nil
end

-- Restore Blizzard nameplate visuals (used for the player's own plate, which
-- TurboFace no longer styles -- the personal resource bar feature was removed)
local function UnsuppressBlizzPlate(nameplate)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    RestoreNativeFriendlyNamePosition(nameplate)
    HideNativeFriendlyNPCTitle(nameplate)
    if ns.RestoreNativeNameplateNameShadow then ns.RestoreNativeNameplateNameShadow(nameplate) end
    if ns.RestoreNativeNameplateHealthTextPosition then
        ns.RestoreNativeNameplateHealthTextPosition(nameplate)
    end
    if ns.RestoreNativeRarityIconPosition then ns.RestoreNativeRarityIconPosition(nameplate) end
    uf._tfNativeSuppressionActive = false
    uf._tfTurboSuppressionMode = nil
    nameplate._tfTurboNativeHealthChassis = nil
    nameplate._tfTurboNativeIdentityOnly = nil
    if ns.CleanupNativeNameplateAugments then ns:CleanupNativeNameplateAugments(nameplate) end
    RestoreBaselineNativePresentation(nameplate, uf)
end

local function EnumerateActiveNamePlates() return C_NamePlate.GetNamePlates() end

local Core = CreateFrame("Frame")
ns.RegisterEvent(Core, "PLAYER_LOGIN")
-- PLAYER_REGEN_ENABLED is a nameplate-only subscription used to resume
-- deferred NPC-title scans after combat.


ns.unitToPlate = {}     -- [unit] = myPlate (used for fast unit->plate lookups)
ns.unitToNameplate = {} -- [unit] = Blizzard nameplate frame (used to recover missed removals)
ns.unitToNameplateGUID = {} -- [unit] = GUID captured when the nameplate was added
ns.guidToNameplateUnit = {} -- [guid] = current nameplate unit token

-- Forward declarations so callbacks can reference handlers before definition
local OnNamePlateAdded
local OnNamePlateRemoved
local nameplateWorldSettleGeneration = 0
local NAMEPLATE_WORLD_SETTLE_DELAYS = { 0, 0.5, 1.5 }

-- PLAYER_LOGIN can occur well before the initial loading screen has released
-- the world. A recovery scan timed from that event can therefore finish while
-- C_NamePlate still has nothing to enumerate, which is why a cold login could
-- miss augmentation that a /reload (with an already-live world) restored.
-- Reconcile at PLAYER_ENTERING_WORLD instead, with two bounded late passes for
-- pooled unit bindings and native StatusBar geometry that settle afterward.
local function ReconcileWorldNameplates(generation)
    if generation ~= nameplateWorldSettleGeneration then return end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return end

    local plates = EnumerateActiveNamePlates()
    if not plates then return end
    for _, nameplate in pairs(plates) do
        local unit = ns.API.GetPlateUnitToken(nameplate)
        if unit and UnitExists(unit) then
            OnNamePlateAdded(nil, unit, nameplate)
        end
    end
end

local function ScheduleWorldNameplateReconcile()
    nameplateWorldSettleGeneration = nameplateWorldSettleGeneration + 1
    local generation = nameplateWorldSettleGeneration
    for _, delay in ipairs(NAMEPLATE_WORLD_SETTLE_DELAYS) do
        if delay == 0 then
            ReconcileWorldNameplates(generation)
        else
            C_Timer.After(delay, function() ReconcileWorldNameplates(generation) end)
        end
    end
end

local function CallNamePlateRemoved(event, unit, nameplate)
    local cpu = ns.CPUProfiler
    if cpu and cpu.MeasureKillNoReturn then
        cpu:MeasureKillNoReturn("Nameplates/Core:Remove", OnNamePlateRemoved, event, unit, nameplate)
    else
        OnNamePlateRemoved(event, unit, nameplate)
    end
end

-- Title brightening: same channel-brighten pattern as the regen "+X" tick
-- popups (Power/PowerCost.lua TICK_BRIGHTEN), tuned to +100/255 for the subtitle.
-- The guild/NPC-title text mirrors the name color, then brightens each
-- channel so the smaller line reads clearly without changing its hue.
local TITLE_BRIGHTEN = 100 / 255
local function BrightenTitleColor(r, g, b)
    return math.min(1, (r or 0) + TITLE_BRIGHTEN),
           math.min(1, (g or 0) + TITLE_BRIGHTEN),
           math.min(1, (b or 0) + TITLE_BRIGHTEN)
end

local npcTitleTooltip
local npcTitleQueue = {}        -- [npcID] = unit
local npcTitleQueueGUID = {}    -- [npcID] = guid
local npcTitleQueueOrder = {}   -- [i] = npcID (FIFO)
local npcTitleQueueIndex = 1
local npcTitleQueueTimer

local function GetNPCIDForUnit(unit)
    local guid = unit and UnitGUID(unit)
    if not guid then return nil end

    -- Classic Era uses the modern GUID format:
    --   "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawnUID>"
    -- The NPC ID is the 6th dash-delimited field (decimal). The old vanilla 1.12
    -- hex-substring method (guid:sub(6,12), base 16) does NOT work here.
    local npcID = select(6, strsplit("-", guid))
    npcID = npcID and tonumber(npcID)
    if npcID and npcID > 0 then
        return npcID
    end
end
ns.GetNPCIDForUnit = GetNPCIDForUnit

local function EnsureNPCTitleTooltip()
    if npcTitleTooltip then
        return npcTitleTooltip
    end
    npcTitleTooltip = CreateFrame("GameTooltip", "TurboFaceNPCTitleScanTooltip", UIParent, "GameTooltipTemplate")
    npcTitleTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return npcTitleTooltip
end

local function ScanNPCTitle(unit)
    local tip = EnsureNPCTitleTooltip()
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetUnit(unit)

    local lineIndex = 2
    if GetCVarBool and GetCVarBool("colorblindMode") then
        lineIndex = 3
    end

    local line = _G["TurboFaceNPCTitleScanTooltipTextLeft" .. lineIndex]
    local text = line and line:GetText() or nil
    tip:Hide()

    if not text or text == "" then
        return nil
    end

    local levelToken = LEVEL and strlower(LEVEL) or "level"
    if strlower(text):find(levelToken, 1, true) then
        return nil
    end

    return text
end

local function ProcessNPCTitleQueue()
    npcTitleQueueTimer = nil

    if InCombatLockdown() then
        return
    end

    local cache = ns.c_npcTitleCache
    if not cache then
        return
    end

    local maxIndex = #npcTitleQueueOrder
    if npcTitleQueueIndex > maxIndex then
        wipe(npcTitleQueueOrder)
        npcTitleQueueIndex = 1
        return
    end

    local scansThisTick = 0
    while scansThisTick < 2 and npcTitleQueueIndex <= maxIndex do
        local npcID = npcTitleQueueOrder[npcTitleQueueIndex]
        npcTitleQueueIndex = npcTitleQueueIndex + 1
        if npcID then
            local unit = npcTitleQueue[npcID]
            local guid = npcTitleQueueGUID[npcID]
            npcTitleQueue[npcID] = nil
            npcTitleQueueGUID[npcID] = nil

            if unit and guid and not cache[npcID] and UnitExists(unit) and UnitGUID(unit) == guid and (not UnitIsPlayer(unit)) and (not UnitPlayerControlled(unit)) then
                local title = ScanNPCTitle(unit)
                if title and title ~= "" then
                    cache[npcID] = title
                    -- Re-render the plate now that the title is cached. The first
                    -- draw hid the subtitle (cache was empty) and queued this scan;
                    -- without this refresh the title never appears for an NPC you
                    -- just walked up to (nothing else re-triggers the plate).
                    if ns.RefreshPlateForUnit then ns:RefreshPlateForUnit(unit) end
                end
            end
        end
        scansThisTick = scansThisTick + 1
    end

    if npcTitleQueueIndex <= #npcTitleQueueOrder then
        npcTitleQueueTimer = true
        C_Timer.After(0.05, ProcessNPCTitleQueue)
    else
        wipe(npcTitleQueueOrder)
        npcTitleQueueIndex = 1
    end
end

local function QueueNPCTitleScan(npcID, unit)
    if not npcID or npcID == 0 then
        return
    end
    local cache = ns.c_npcTitleCache
    if cache and cache[npcID] then
        return
    end
    if npcTitleQueue[npcID] then
        return
    end

    npcTitleQueue[npcID] = unit
    npcTitleQueueGUID[npcID] = UnitGUID(unit)
    tinsert(npcTitleQueueOrder, npcID)

    if not npcTitleQueueTimer and not InCombatLockdown() then
        npcTitleQueueTimer = true
        C_Timer.After(0.05, ProcessNPCTitleQueue)
    end
end
ns.QueueNPCTitleScan = QueueNPCTitleScan

local function EnsureNativeFriendlyNPCTitle(nameplate)
    if not nameplate then return nil end
    local title = nameplate._tfFriendlyNPCTitle
    if title then return title end

    title = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetJustifyH("CENTER")
    title:SetJustifyV("TOP")
    title:SetWordWrap(false)
    title:Hide()
    nameplate._tfFriendlyNPCTitle = title
    return title
end

local function UpdateNativeFriendlyNPCTitle(nameplate, unit)
    if not (nameplate and unit and UnitExists(unit)) then
        HideNativeFriendlyNPCTitle(nameplate)
        return nil
    end

    local uf = nameplate.UnitFrame
    local nativeName = uf and uf.name
    local titleFS = EnsureNativeFriendlyNPCTitle(nameplate)
    if not (nativeName and titleFS) then
        HideNativeFriendlyNPCTitle(nameplate)
        return nil
    end

    local npcID = GetNPCIDForUnit(unit)
    local rawTitle = npcID and ns.c_npcTitleCache and ns.c_npcTitleCache[npcID] or nil
    if not rawTitle or rawTitle == "" then
        titleFS:SetText("")
        titleFS:Hide()
        if npcID then QueueNPCTitleScan(npcID, unit) end
        return nil
    end

    local size = ns.NP_TITLE_FONT_SIZE or 8
    if titleFS._lastFont ~= ns.c_font or titleFS._lastSize ~= size or titleFS._lastOutline ~= ns.c_fontOutline then
        ns:StyleFont(titleFS, ns.c_font, size, nil, ns.NP_NAME_TEXT_STYLE)
        titleFS._lastFont = ns.c_font
        titleFS._lastSize = size
        titleFS._lastOutline = ns.c_fontOutline
    end

    titleFS:ClearAllPoints()
    titleFS:SetPoint("TOP", nativeName, "BOTTOM", 0, -1)
    titleFS:SetText("<" .. rawTitle .. ">")

    if nativeName.GetTextColor then
        local ok, r, g, b = pcall(nativeName.GetTextColor, nativeName)
        if ok then
            titleFS:SetTextColor(BrightenTitleColor(r, g, b))
        else
            titleFS:SetTextColor(1, 1, 1, 1)
        end
    else
        titleFS:SetTextColor(1, 1, 1, 1)
    end

    titleFS:Show()
    return rawTitle
end

-- Helper to get formatted guild display string (cached to avoid string concatenation)
local function SafeUseNativeNameplateChassis(unit, nameplate)
    if not nameplate then nameplate = GetNamePlateForUnit(unit) end
    if not nameplate then return nil end
    return ConfigureNativeNameplateChassis(nameplate)
end

local function SafeUseNativeFriendlyIdentityOnly(unit, nameplate)
    if not nameplate then nameplate = GetNamePlateForUnit(unit) end
    if not nameplate then return false end
    return ConfigureNativeFriendlyIdentityOnly(nameplate)
end

local RunGuardedNameplateCleanup
local guardedNameplateCleanupScheduled = false
local GUARDED_NAMEPLATE_CLEANUP_INTERVAL = 0.5

local function ClearTrackedNameplate(unit, nameplate)
    if not unit then return end

    local guid = ns.unitToNameplateGUID[unit]
        or (nameplate and nameplate._turboTrackedUnit == unit and nameplate._turboTrackedGUID)
    if guid then
        if ns.guidToNameplateUnit[guid] == unit then ns.guidToNameplateUnit[guid] = nil end
    end

    if not nameplate or ns.unitToNameplate[unit] == nameplate then
        ns.unitToNameplate[unit] = nil
        ns.unitToNameplateGUID[unit] = nil
    end

    if nameplate and nameplate._turboTrackedUnit == unit then
        nameplate._turboTrackedUnit = nil
        nameplate._turboTrackedGUID = nil
    end
end

local function ClearUnitPlateLookup(unit, nameplate)
    if not unit then return end

    local myPlate = nameplate and nameplate.myPlate
    if not myPlate or ns.unitToPlate[unit] == myPlate then
        ns.unitToPlate[unit] = nil
    end
end

local function ScheduleGuardedNameplateCleanup()
    if guardedNameplateCleanupScheduled then return end
    guardedNameplateCleanupScheduled = true
    C_Timer.After(GUARDED_NAMEPLATE_CLEANUP_INTERVAL, RunGuardedNameplateCleanup)
end

local function TrackNameplate(unit, nameplate)
    if not unit or not nameplate then return end

    local oldUnit = nameplate._turboTrackedUnit
    if oldUnit and oldUnit ~= unit then
        ClearTrackedNameplate(oldUnit, nameplate)
        if ns.unitToPlate[oldUnit] == nameplate.myPlate then
            ns.unitToPlate[oldUnit] = nil
        end
    end

    local guid = UnitGUID(unit)
    nameplate._turboTrackedUnit = unit
    nameplate._turboTrackedGUID = guid
    ns.unitToNameplate[unit] = nameplate
    ns.unitToNameplateGUID[unit] = guid
    if guid then
        ns.guidToNameplateUnit[guid] = unit
    end

    ScheduleGuardedNameplateCleanup()
end

RunGuardedNameplateCleanup = function()
    guardedNameplateCleanupScheduled = false

    local unit, nameplate = next(ns.unitToNameplate)
    while unit do
        local nextUnit = next(ns.unitToNameplate, unit)
        local expectedGUID = ns.unitToNameplateGUID[unit]

        if not nameplate then
            ClearTrackedNameplate(unit)
            ClearUnitPlateLookup(unit)
        else
            local currentUnit = ns.API.GetPlateUnitToken(nameplate)

            if currentUnit == unit then
                if not UnitExists(unit) then
                    CallNamePlateRemoved(nil, unit, nameplate)
                else
                    local currentGUID = UnitGUID(unit)
                    if currentGUID and currentGUID ~= expectedGUID then
                        -- Silent same-token GUID reuse is a full pooled-nameplate
                        -- rebind, not merely a lookup-table update. The old guard
                        -- repaired only guidToNameplateUnit/unitToNameplateGUID,
                        -- leaving myPlate.cachedGUID and every GUID-sensitive
                        -- augmentation on the previous mob. Re-enter the single
                        -- native lifecycle so all consumers rebuild coherently.
                        if expectedGUID and ns.guidToNameplateUnit[expectedGUID] == unit then
                            ns.guidToNameplateUnit[expectedGUID] = nil
                        end
                        OnNamePlateAdded(nil, unit, nameplate)
                    end
                end
            elseif not currentUnit then
                CallNamePlateRemoved(nil, unit, nameplate)
            else
                -- The base frame has already been recycled for another live unit.
                ClearTrackedNameplate(unit, nameplate)
                ClearUnitPlateLookup(unit, nameplate)
            end
        end

        unit = nextUnit
        nameplate = unit and ns.unitToNameplate[unit]
    end

    if next(ns.unitToNameplate) then
        ScheduleGuardedNameplateCleanup()
    end
end

-- Note: Cached settings are stored in ns.c_* (set by Nameplates.lua:UpdateDBCache)
-- Core.lua uses the shared nameplate font caches for the TurboFace-owned NPC title supplement

Core:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ns:LoadVariables()  -- Also calls UpdateDBCache() at the end (sets ns.c_* cache)
        if ns.Compat and ns.Compat.OnLogin then ns.Compat:OnLogin() end
        local SafeCall = ns.CompatSafeCall or ns.SafeCall
        -- Quick Setup applies its saved one-shot CVar baseline before any
        -- temporary Plus/System CVar owner acquires the current value.
        if ns.QuickSetup then SafeCall("QuickSetup:Init", function() ns.QuickSetup:Init() end) end
        local nameplatesEnabled = (not ns.ModuleEnabled) or ns.ModuleEnabled("nameplates")
        local useDetachedNameplates = CorePolicy("detachedNameplateAdapter")
            and ns.ForeverNameplates ~= nil
        -- Era may still install driver/native-region hooks. Forever's adapter
        -- deliberately never hooks or mutates Blizzard CompactUnitFrame objects.
        if nameplatesEnabled and not useDetachedNameplates and NamePlateDriverFrame then
            InstallBlizzHooks()
        end
        -- Module init chain: SafeCall isolates a broken module so everything
        -- after it still initializes (error is reported once via chat).
        -- Sync persistent nameplate CVar ownership once even when the module
        -- starts disabled. This also repays any visibility/Questie ownership
        -- debt left by builds predating the 0.15.17 settings cleanup.
        if ns.BubbleNameplates and ns.BubbleNameplates.ApplyNameplateCVars then
            SafeCall("Nameplates:CVarOwnership", function() ns.BubbleNameplates:ApplyNameplateCVars() end)
        end
        if useDetachedNameplates then
            -- Core keeps only PLAYER_REGEN_ENABLED so the existing out-of-combat
            -- NPC-title scanner can resume. All plate lifecycle/render work is
            -- owned by the detached Forever adapter.
            ns.RegisterEvent(Core, "PLAYER_REGEN_ENABLED")
            SafeCall("ForeverNameplates:Init", function() ns.ForeverNameplates:Init() end)
        elseif nameplatesEnabled then
            ns.RegisterEvent(Core, "PLAYER_REGEN_ENABLED")
            ns.RegisterEvent(Core, "PLAYER_ENTERING_WORLD")
            if ActivateCoreNameplateEvents then
                SafeCall("Nameplates:CoreEvents", ActivateCoreNameplateEvents)
            end
            if ns.ActivateNameplateUnitEvents then
                SafeCall("Nameplates:UnitEvents", function() ns.ActivateNameplateUnitEvents() end)
            end
            if ns.ActivateNameplateComboDriver then
                SafeCall("Nameplates:ComboDriver", function() ns.ActivateNameplateComboDriver() end)
            end
            if ns.BubbleNameplates and ns.BubbleNameplates.ActivateRuntime then
                SafeCall("Nameplates:CVarRuntime", function() ns.BubbleNameplates:ActivateRuntime() end)
            end
        end
        -- Modules that previously self-registered while their files loaded are
        -- activated here, after LoadVariables() has normalized the module gates.
        -- This is the single startup boundary for runtime subscriptions.
        if ns.Auras then SafeCall("Auras:Init", function() ns.Auras:Init() end) end
        if ns.PartyAuras then SafeCall("PartyPetAuras:Init", function() ns.PartyAuras:Init() end) end
        if ns.ClassBuffs then SafeCall("ClassBuffs:Init", function() ns.ClassBuffs:Init() end) end
        if ns.ClassFeatures then SafeCall("ClassFeatures:Init", function() ns.ClassFeatures:Init() end) end
        if ns.UF then SafeCall("UnitFrames:Init", function() ns.UF:Init() end) end
        if ns.NanShield then SafeCall("NanShield:Init", function() ns.NanShield:Init() end) end
        if ns.DruidPowerBar then SafeCall("DruidPowerBar:Init", function() ns.DruidPowerBar:Init() end) end
        if ns.ST then SafeCall("SwingTimers:Init", function() ns.ST:Init() end) end
        if ns.Castbars then SafeCall("Castbars:Init", function() ns.Castbars:Init() end) end
        -- Movers is a dependency provider for custom free-floating widgets.
        -- Initialize it before those widgets; when Movers is disabled their
        -- effective gates remain off and none of them build runtime state.
        if ns.Movers then SafeCall("Movers:Init", function() ns.Movers:Init() end) end
        local function InitCombatMeter()
            if ns.Providers then
                SafeCall("CombatMeterProvider:Init", function() ns.Providers:Call("combatMeter", "Init") end)
            elseif ns.CombatMeter then
                SafeCall("CombatMeter:Init", function() ns.CombatMeter:Init() end)
            end
        end
        if CorePolicy("combatMeterBeforeBadge") then InitCombatMeter() end
        if ns.DPSBadge then SafeCall("DPSBadge:Init", function() ns.DPSBadge:Init() end) end
        if not CorePolicy("combatMeterBeforeBadge") then InitCombatMeter() end
        if ns.LeashTimer then SafeCall("LeashTimer:Init", function() ns.LeashTimer:Init() end) end
        if ns.Inv then SafeCall("Inventory:Init", function() ns.Inv:Init() end) end
        if ns.Bank then SafeCall("Bank:Init", function() ns.Bank:Init() end) end
        if ns.NW then SafeCall("NetWorth:Init", function() ns.NW:Init() end) end
        if ns.BagSlots then SafeCall("BagSlots:Init", function() ns.BagSlots:Init() end) end
        if ns.FPSCounter then SafeCall("FPSCounter:Init", function() ns.FPSCounter:Init() end) end
        if ns.TalentPointReminder then SafeCall("TalentPointReminder:Init", function() ns.TalentPointReminder:Init() end) end
        if ns.HS then SafeCall("Hearthstone:Init", function() ns.HS:Init() end) end
        if ns.UnstuckSkipVisual then SafeCall("UnstuckSkipsVisual:Init", function() ns.UnstuckSkipVisual:Init() end) end
        if ns.HearthBatch then SafeCall("HearthBatch:Init", function() ns.HearthBatch:Init() end) end
        if ns.Skills then SafeCall("Skills:Init", function() ns.Skills:Init() end) end
        if ns.DotPrediction then SafeCall("DotPrediction:Init", function() ns.DotPrediction:Init() end) end
        if ns.HealPrediction then SafeCall("HealPrediction:Init", function() ns.HealPrediction:Init() end) end
        -- Prediction engines exist before their Blizzard-bar consumers install
        -- optional child textures/hooks.
        if ns.UF and ns.UF.InitDotPrediction then
            SafeCall("UnitFrames:InitDotPrediction", function() ns.UF:InitDotPrediction() end)
        end
        if ns.UF and ns.UF.InitHealPrediction then
            SafeCall("UnitFrames:InitHealPrediction", function() ns.UF:InitHealPrediction() end)
        end
        if ns.Grocery then SafeCall("Grocery:Init", function() ns.Grocery:Init() end) end
        if ns.Trainer then SafeCall("Trainer:Init", function() ns.Trainer:Init() end) end
        if ns.Tracker then SafeCall("Tracker:Init", function() ns.Tracker:Init() end) end
        if ns.MinimapButton then SafeCall("MinimapButton:Init", function() ns.MinimapButton:Init() end) end
        if ns.AuraStyle then SafeCall("AuraStyle:Init", function() ns.AuraStyle:Init() end) end
        if ns.Power then SafeCall("Power:Init", function() ns.Power:Init() end) end
        if ns.Loot then SafeCall("Loot:Init", function() ns.Loot:Init() end) end
        if ns.XP then SafeCall("ExperienceBar:Init", function() ns.XP:Init() end) end
        if ns.SpeedrunSplits then SafeCall("SpeedrunSplits:Init", function() ns.SpeedrunSplits:Init() end) end
        if ns.PlusAutomation then SafeCall("PlusAutomation:Init", function() ns.PlusAutomation:Init() end) end
        if ns.PlusSocial then SafeCall("PlusSocial:Init", function() ns.PlusSocial:Init() end) end
        if ns.PlusInterface then SafeCall("PlusInterface:Init", function() ns.PlusInterface:Init() end) end
        if ns.PlusMap then SafeCall("PlusMap:Init", function() ns.PlusMap:Init() end) end
        if ns.PlusSystem then SafeCall("PlusSystem:Init", function() ns.PlusSystem:Init() end) end
        if ns.PlusChat then SafeCall("PlusChat:Init", function() ns.PlusChat:Init() end) end
        if ns.PlusFlight then SafeCall("PlusFlight:Init", function() ns.PlusFlight:Init() end) end

        -- Enable nameplate resizing so Clickable Width/Height sliders work
        -- SetEnableResizeNamePlates not available in Classic Era 1.15.8

        -- Initialize tall-boss WorldFrame extension and TurboDebuffs only after
        -- the Nameplates master gate has been resolved.
        if nameplatesEnabled and not useDetachedNameplates and ns.InitTallBossFix then
            ns.InitTallBossFix()
        end

        -- Era-only native augmentation. Forever keeps these dormant until they
        -- are ported to detached overlays/side tables.
        if nameplatesEnabled and not useDetachedNameplates and ns.InitTurboDebuffs then
            ns:InitTurboDebuffs()
        end

        if nameplatesEnabled and not useDetachedNameplates then
            C_Timer.After(3, function()
                if ns.UpdateAllQuestIcons then ns.UpdateAllQuestIcons() end
            end)
        end

        -- Check for incompatible nameplate addons only when TurboFace actually
        -- owns nameplates; an inactive module must not warn about another addon.
        -- Special case: Ascension_NamePlates is controlled by CVar, not addon list
        -- Classic Era 1.15.8: check incompatible nameplate addons
        if nameplatesEnabled then
            for _, addon in ipairs(IncompatibleAddOns) do
                -- Normalized enable-state check via the Compat boundary
                local state = ns.API.GetAddOnEnableState(addon)
                if state and state > 0 then
                    StaticPopup_Show("TURBOFACE_ADDON_CONFLICT", addon, addon, addon)
                    break
                end
            end
        end

        local version = GetAddOnMetadata(addonName, "Version") or "0.7.5"
        local boostedBy = L.BoostedBy or "TurboFace v%s loaded - /tf"
        print(boostedBy:format(version))
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleWorldNameplateReconcile()
    elseif event == "PLAYER_REGEN_ENABLED" then

        -- Resume NPC title scans (cached titles remain visible in combat)
        if not npcTitleQueueTimer and npcTitleQueueOrder[1] and not InCombatLockdown() then
            npcTitleQueueTimer = true
            C_Timer.After(0.05, ProcessNPCTitleQueue)
        end
    end
end)

-- Apply the native friendly-NPC identity-only presentation.
local function ApplyFriendlyNPCNativeIdentityOnly(nameplate, unit)
    if not (nameplate and unit and UnitExists(unit)) then return false end

    -- Keep Blizzard's name alive, suppress the non-identity chassis, and add
    -- only TurboFace's supplemental NPC title underneath the native name.

    if not SafeUseNativeFriendlyIdentityOnly(unit, nameplate) then return false end
    if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(nameplate, unit) end

    -- Title ownership is independent of the hidden augmentation host. Render it
    -- directly on the Blizzard nameplate root so the hybrid identity remains
    -- complete even if no TurboFace full-plate host has been allocated yet.
    local rawTitle = UpdateNativeFriendlyNPCTitle(nameplate, unit)

    local plate = nameplate.myPlate
    if not plate and ns.CreatePlateFrame then
        ns:CreatePlateFrame(nameplate, unit)
        plate = nameplate.myPlate
    end

    if plate then
        local entering = plate._tfNativeFriendlyIdentityOnly ~= true or plate.unit ~= unit
        if entering then
            if ns.BubbleNameplates then
                ns.BubbleNameplates:CleanupPlate(plate, plate.unit, plate.cachedGUID)
            end
            if ns.CleanupNativeNameplateAugments then
                ns:CleanupNativeNameplateAugments(nameplate)
            end
        end

        plate.unit = unit
        plate.cachedGUID = UnitGUID(unit)
        plate.isPlayer = false
        plate.isFriendly = true
        plate._tfUsesNativeIdentity = true
        plate._tfNativeFriendlyIdentityOnly = true

        -- Force a complete rebuild if this pooled host later returns to ordinary
        -- full-native mode. While identity-only, keep the augmentation host
        -- parked so no aura/cast/health/threat child can accidentally surface.
        plate._initialized = nil
        plate._lastUnit = nil
        plate:Hide()
        ns.unitToPlate[unit] = nil

        -- The title is still TurboFace-owned in this mode, but the name itself
        -- is Blizzard's native FontString. Job Icon remains an independent
        -- adjunct and can reuse the same raw title classification data.
        if ns.BubbleNameplates and ns.BubbleNameplates.UpdateJobIcon then
            ns.BubbleNameplates:UpdateJobIcon(plate, unit, rawTitle)
        elseif plate.nameplateJobIcon then
            plate.nameplateJobIcon:Hide()
        end
    end

    return true
end

local function FriendlyDamagedOnlyKind(unit)
    if not (unit and UnitExists(unit) and UnitIsFriend("player", unit)) then return nil end

    if UnitIsPlayer(unit) then
        if ns.c_nameplateFriendlyPlayerDamagedOnly and not UnitIsUnit(unit, "player") then
            return "player"
        end
        return nil
    end

    if UnitPlayerControlled(unit) or UnitIsPet(unit) then return nil end
    if ns.c_nameplateFriendlyNPCDamagedOnly then return "npc" end
    return nil
end

local function EnsureNativeFriendlyDamagedHost(nameplate, unit, kind)
    local plate = nameplate and nameplate.myPlate
    -- Friendly NPCs may still need the root-level Job Icon while the full
    -- augmentation host is parked. Friendly players need no TurboFace surface
    -- at full health, so avoid allocating one unless it already exists.
    if not plate and kind == "npc" and ns.c_nameplateJobIcon and ns.CreatePlateFrame then
        ns:CreatePlateFrame(nameplate, unit)
        plate = nameplate.myPlate
    end
    return plate
end

local function ApplyFriendlyDamagedOnlyIdentity(nameplate, unit, kind)
    if not (nameplate and unit and kind) then return false end

    if not SafeUseNativeFriendlyIdentityOnly(unit, nameplate) then return false end
    nameplate._tfFriendlyDamagedOnlyIdentity = kind
    nameplate._tfFriendlyDamagedOnlyState = "identity"
    nameplate._tfFriendlyDamagedOnlyKind = kind

    local rawTitle
    if kind == "npc" then
        if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(nameplate, unit) end
        -- When Name + Title Only is also enabled, preserve that identity
        -- contract at full health. Damaged state still wins and restores the
        -- complete Blizzard chassis.
        if ns.c_nameplateFriendlyNPCNameTitleOnly then
            rawTitle = UpdateNativeFriendlyNPCTitle(nameplate, unit)
        else
            HideNativeFriendlyNPCTitle(nameplate)
        end
    else
        HideNativeFriendlyNPCTitle(nameplate)
        if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(nameplate, unit) end
    end

    local plate = EnsureNativeFriendlyDamagedHost(nameplate, unit, kind)
    if plate then
        local guid = UnitGUID(unit)
        local enteringIdentity = plate._tfFriendlyDamagedOnlyIdentity ~= true
            or plate.unit ~= unit or plate.cachedGUID ~= guid
        if enteringIdentity then
            if ns.BubbleNameplates then
                ns.BubbleNameplates:CleanupPlate(plate, plate.unit, plate.cachedGUID)
            end
            if ns.CleanupNativeNameplateAugments then
                ns:CleanupNativeNameplateAugments(nameplate)
            end
        end

        plate.unit = unit
        plate.cachedGUID = guid
        plate.isPlayer = false
        plate.isFriendly = true
        plate._tfUsesNativeIdentity = true
        plate._tfNativeFriendlyIdentityOnly = true
        plate._tfFriendlyDamagedOnlyIdentity = true
        plate._initialized = nil
        plate._lastUnit = nil
        plate:Hide()

        if kind == "npc" and ns.BubbleNameplates and ns.BubbleNameplates.UpdateJobIcon then
            ns.BubbleNameplates:UpdateJobIcon(plate, unit, rawTitle)
        elseif plate.nameplateJobIcon then
            plate.nameplateJobIcon:Hide()
        end
    end

    -- Full-health damaged-only is a native identity surface. Do not keep the
    -- TurboFace full-plate host in the hot unit lookup; NameplateUnits performs
    -- the minimal health transition check directly before UpdateHealth.
    ns.unitToPlate[unit] = nil
    return true
end

local function ApplyFriendlyDamagedOnlyFull(nameplate, unit, kind)
    if not (nameplate and unit and kind) then return false end

    SafeUseNativeNameplateChassis(unit, nameplate)
    nameplate._tfFriendlyDamagedOnlyIdentity = nil
    nameplate._tfFriendlyDamagedOnlyState = "full"
    nameplate._tfFriendlyDamagedOnlyKind = kind
    HideNativeFriendlyNPCTitle(nameplate)

    if ns.ApplyNativeNameShadow then
        ns.ApplyNativeNameShadow(nameplate, unit)
    end

    local plate = nameplate.myPlate
    if not plate and ns.CreatePlateFrame then
        ns:CreatePlateFrame(nameplate, unit)
        plate = nameplate.myPlate
    end
    if not plate then return false end

    local wasIdentity = plate._tfFriendlyDamagedOnlyIdentity == true
        or plate._tfNativeFriendlyIdentityOnly == true
    plate._tfNativeFriendlyIdentityOnly = nil
    plate._tfFriendlyDamagedOnlyIdentity = nil
    plate.unit = unit
    plate.cachedGUID = UnitGUID(unit)
    plate:Show()
    ns.unitToPlate[unit] = plate
    if plate.cachedGUID then ns.guidToNameplateUnit[plate.cachedGUID] = unit end

    -- Transitioning out of the parked identity state needs one complete rebuild
    -- so auras/threat/prediction/job surfaces cannot retain stale hidden state.
    if wasIdentity or not plate._initialized or plate._lastUnit ~= unit then
        if ns.FullPlateUpdate then ns:FullPlateUpdate(plate, unit) end
        plate._initialized = true
        plate._lastUnit = unit
    elseif ns.RefreshNameplateAugments then
        ns:RefreshNameplateAugments(plate)
    end

    if ns.BubbleNameplates and ns.BubbleNameplates.UpdateJobIcon then
        ns.BubbleNameplates:UpdateJobIcon(plate, unit)
    end
    return true
end

local function ApplyFriendlyDamagedOnlyState(nameplate, unit, kind, current, maximum, force)
    if not (nameplate and unit and kind) then return false end
    if nameplate._tfFriendlyDamagedOnlySyncing then return true end

    if current == nil then current = ns.API.ReadUnitHealth(unit) end
    if maximum == nil then maximum = ns.API.ReadUnitHealthMax(unit) end
    -- Unknown health must not be interpreted as damaged or full. Keep the
    -- complete Blizzard chassis, which can render its own restricted values.
    if current == nil or maximum == nil then
        return ApplyFriendlyDamagedOnlyFull(nameplate, unit, kind)
    end
    local fullHealth = maximum > 0 and current >= maximum
    local desiredState = fullHealth and "identity" or "full"
    if not force and nameplate._tfFriendlyDamagedOnlyState == desiredState
        and nameplate._tfFriendlyDamagedOnlyKind == kind then
        return true
    end

    nameplate._tfFriendlyDamagedOnlySyncing = true
    local ok
    if fullHealth then
        ok = ApplyFriendlyDamagedOnlyIdentity(nameplate, unit, kind)
    else
        ok = ApplyFriendlyDamagedOnlyFull(nameplate, unit, kind)
    end
    nameplate._tfFriendlyDamagedOnlySyncing = nil
    return ok
end

-- Health-batch entry point. This intentionally works without unitToPlate so
-- full-health damaged-only plates can keep the TurboFace augmentation host
-- completely parked/dormant while still reacting immediately to damage.
function ns.UpdateFriendlyDamagedOnlyUnit(unit, current, maximum, suppliedNameplate)
    local kind = FriendlyDamagedOnlyKind(unit)
    local nameplate = suppliedNameplate or (unit and GetNamePlateForUnit(unit))

    if not kind then
        if nameplate and (nameplate._tfFriendlyDamagedOnlyIdentity
            or nameplate._tfFriendlyDamagedOnlyState) then
            nameplate._tfFriendlyDamagedOnlyIdentity = nil
            nameplate._tfFriendlyDamagedOnlyState = nil
            nameplate._tfFriendlyDamagedOnlyKind = nil
            -- A live settings/faction transition releases the identity shell
            -- through the single native lifecycle classifier.
            if ns.RefreshPlateForUnit then ns:RefreshPlateForUnit(unit) end
        end
        return false
    end
    if not nameplate then return false end

    return ApplyFriendlyDamagedOnlyState(nameplate, unit, kind, current, maximum)
end

-- Event-driven nameplate handling via NAME_PLATE_UNIT_ADDED/REMOVED standard events
-- =============================================================================
OnNamePlateAdded = function(_, unit, nameplate)
    -- Single native ownership entry point. TurboFace never replaces Blizzard's
    -- ordinary nameplate identity/health substrate; it selects between the
    -- native full chassis and the two friendly identity-only presentation modes.
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return end
    if not nameplate and unit then nameplate = GetNamePlateForUnit(unit) end
    if not unit or not nameplate then return end

    local dc = ns.DebugCounters
    if dc then dc.plateAdded = dc.plateAdded + 1 end
    TrackNameplate(unit, nameplate)

    -- The player's personal plate remains wholly Blizzard-owned.
    if ns.API.ReadUnitIsUnit(unit, "player") == true then
        UnsuppressBlizzPlate(nameplate)
        if nameplate.myPlate then nameplate.myPlate:Hide() end
        ns.unitToPlate[unit] = nil
        return
    end

    local isFriendly = ns.API.ReadUnitIsFriend("player", unit)
    local isPlayer = ns.API.ReadUnitIsPlayer(unit)
    if isFriendly == nil or isPlayer == nil then
        SafeUseNativeNameplateChassis(unit, nameplate)
        if nameplate.myPlate then nameplate.myPlate:Hide() end
        ns.unitToPlate[unit] = nil
        return
    end
    local isPet = not isPlayer and UnitIsPet(unit)
    local playerControlled = not isPlayer and ns.API.ReadUnitPlayerControlled(unit)

    local friendlyNPCNameTitleOnly = isFriendly
        and ns.c_nameplateFriendlyNPCNameTitleOnly
        and not isPlayer and not playerControlled and not isPet
    local friendlyPlayerDamagedOnly = isFriendly
        and ns.c_nameplateFriendlyPlayerDamagedOnly
        and isPlayer
    local friendlyNPCDamagedOnly = isFriendly
        and ns.c_nameplateFriendlyNPCDamagedOnly
        and not isPlayer and not playerControlled and not isPet
    local friendlyDamagedOnly = friendlyPlayerDamagedOnly or friendlyNPCDamagedOnly

    if not friendlyDamagedOnly then
        nameplate._tfFriendlyDamagedOnlyIdentity = nil
        nameplate._tfFriendlyDamagedOnlyState = nil
        nameplate._tfFriendlyDamagedOnlyKind = nil
    else
        local kind = friendlyPlayerDamagedOnly and "player" or "npc"
        local current, maximum = ns.API.ReadUnitHealth(unit), ns.API.ReadUnitHealthMax(unit)
        if current ~= nil and maximum ~= nil and maximum > 0 and current >= maximum then
            ApplyFriendlyDamagedOnlyState(nameplate, unit, kind, current, maximum, true)
            return
        end
    end

    -- Name + Title Only is a native identity shell. Damaged-only takes
    -- precedence so the Blizzard health chassis can return as soon as health
    -- is lost.
    if friendlyNPCNameTitleOnly and not friendlyNPCDamagedOnly then
        ApplyFriendlyNPCNativeIdentityOnly(nameplate, unit)
        return
    end

    SafeUseNativeNameplateChassis(unit, nameplate)
    nameplate._tfFriendlyDamagedOnlyIdentity = nil
    nameplate._tfFriendlyDamagedOnlyState = friendlyDamagedOnly and "full" or nil
    nameplate._tfFriendlyDamagedOnlyKind = friendlyPlayerDamagedOnly and "player"
        or (friendlyNPCDamagedOnly and "npc" or nil)

    if nameplate.myPlate then
        nameplate.myPlate._tfNativeFriendlyIdentityOnly = nil
        nameplate.myPlate._tfFriendlyDamagedOnlyIdentity = nil
    end
    if ns.ApplyNativeNameShadow then ns.ApplyNativeNameShadow(nameplate, unit) end

    if not nameplate.myPlate and ns.CreatePlateFrame then
        ns:CreatePlateFrame(nameplate, unit)
    end

    local myPlate = nameplate.myPlate
    if not myPlate then return end

    myPlate.unit = unit
    myPlate.cachedGUID = UnitGUID(unit)
    myPlate:Show()
    ns.unitToPlate[unit] = myPlate
    if myPlate.cachedGUID then ns.guidToNameplateUnit[myPlate.cachedGUID] = unit end

    if ns.FullPlateUpdate then ns:FullPlateUpdate(myPlate, unit) end
    if ns.DotPrediction and ns.DotPrediction.OnNameplateBound then
        ns.DotPrediction:OnNameplateBound(unit)
    end
    if ns.UpdateTurboDebuff then ns:UpdateTurboDebuff(myPlate, unit) end
    if ns.ValidateTargetPlate then ns.ValidateTargetPlate() end
end

-- Hide frames when nameplate removed (frames are reused)
OnNamePlateRemoved = function(_, unit, nameplate)
    local trackedNameplate = unit and ns.unitToNameplate[unit]
    if not nameplate and unit then
        nameplate = trackedNameplate
    end

    local removedPlate = nameplate and nameplate.myPlate or (unit and ns.unitToPlate[unit])
    local removedGUID = unit and ns.unitToNameplateGUID[unit]
        or (nameplate and nameplate._turboTrackedGUID)
        or (removedPlate and removedPlate.cachedGUID)

    if unit and nameplate and ns.API.GetPlateUnitToken(nameplate) and ns.API.GetPlateUnitToken(nameplate) ~= unit then
        -- The Blizzard frame has already been recycled to a different unit.
        -- Clean only GUID-keyed state; touching removedPlate here would reset
        -- the newly assigned unit's visuals.
        if ns.BubbleNameplates and removedGUID then
            ns.BubbleNameplates:CleanupGUID(removedGUID)
        end
        if ns.SwingTimers and removedGUID and ns.SwingTimers.CleanupNameplateState then
            ns.SwingTimers:CleanupNameplateState(removedGUID)
        end
        ClearTrackedNameplate(unit, nameplate)
        ClearUnitPlateLookup(unit, nameplate)
        return
    end

    if nameplate then
        nameplate._tfFriendlyDamagedOnlyIdentity = nil
        nameplate._tfFriendlyDamagedOnlyState = nil
        nameplate._tfFriendlyDamagedOnlyKind = nil
        nameplate._tfFriendlyDamagedOnlySyncing = nil
        RestoreNativeFriendlyNamePosition(nameplate)
        HideNativeFriendlyNPCTitle(nameplate)
    end
    if nameplate and ns.RestoreNativeNameplateNameShadow then
        ns.RestoreNativeNameplateNameShadow(nameplate)
    end
    if nameplate and ns.RestoreNativeNameplateHealthTextPosition then
        ns.RestoreNativeNameplateHealthTextPosition(nameplate)
    end
    if nameplate and ns.RestoreNativeRarityIconPosition then
        ns.RestoreNativeRarityIconPosition(nameplate)
    end
    if nameplate then
        -- A pooled base frame is no longer an active TurboFace native chassis.
        -- Clearing this before Blizzard binds the next unit prevents early
        -- native layout callbacks from inheriting stale ownership.
        nameplate._tfTurboNativeHealthChassis = nil
        nameplate._tfTurboNativeIdentityOnly = nil
    end
    if ns.BubbleNameplates and removedPlate then
        ns.BubbleNameplates:CleanupPlate(removedPlate, unit, removedGUID)
    end
    if ns.SwingTimers and removedGUID and ns.SwingTimers.CleanupNameplateState then
        ns.SwingTimers:CleanupNameplateState(removedGUID)
    end

    if unit then
        -- Clear quest retry state for this unit
        if ns.ClearQuestRetryState then
            ns.ClearQuestRetryState(unit)
        end
        ClearUnitPlateLookup(unit, nameplate)
        ClearTrackedNameplate(unit, nameplate)
    end
    if nameplate then
        if nameplate.myPlate then
            -- Clear stale plate reference before recycling (keep GUID - target still exists)
            if nameplate.myPlate == ns.currentTargetPlate then
                ns.currentTargetPlate = nil
                -- Don't clear ns.currentTargetGUID - the target unit still exists,
                -- just its plate went out of view. ValidateTargetPlate will repair
                -- the target-plate reference when the plate comes back.
            end
            -- Reset the augmentation-host scale before the pooled Blizzard plate is reused.
            -- TAINT FIX: Defer to next frame to break secure callback chain
            -- (pet nameplates removed during combat can propagate taint otherwise)
            local plate = nameplate.myPlate
            RunNextFrame(function()
                if plate then
                    -- The augmentation host always remains at unit scale and
                    -- inherits Blizzard's root transform, including selected
                    -- and distance scaling.
                    plate:SetScale(1)
                end
            end)
            -- Release auras to pool (stops OnUpdate timers on hidden frames)
            if ns.CleanupPlateAuras then
                ns:CleanupPlateAuras(nameplate.myPlate)
            end
            -- Hide TurboDebuff
            if ns.HideTurboDebuff then
                ns:HideTurboDebuff(nameplate.myPlate)
            end
            nameplate.myPlate:Hide()
            -- Reset stale player flag on recycled plates
            nameplate.myPlate.isPlayer = false
            -- Clear initialized flag so plate gets re-initialized for next unit
            nameplate.myPlate._initialized = false
            nameplate.myPlate._lastUnit = nil
            -- Clear absorb cache and hide absorb/heal textures to prevent visual artifacts
            nameplate.myPlate._lastAbsorb = nil
            nameplate.myPlate._lastAbsorbHealth = nil
            nameplate.myPlate._lastAbsorbWidth = nil
            nameplate.myPlate._lastAbsorbHeight = nil
            nameplate.myPlate._lastAbsorbFill = nil
            nameplate.myPlate._lastDotOffset = nil
            nameplate.myPlate._lastDotWidth = nil
            nameplate.myPlate._lastDotBottomInset = nil
            nameplate.myPlate._lastDotR = nil
            nameplate.myPlate._lastDotG = nil
            nameplate.myPlate._lastDotB = nil
            nameplate.myPlate._lastDotA = nil
            nameplate.myPlate._tfDotGeometryRetries = nil
            if nameplate.myPlate.hp then
                if nameplate.myPlate.hp._tfDotBar then nameplate.myPlate.hp._tfDotBar:Hide() end
                if nameplate.myPlate.hp._tfDotBarBG then nameplate.myPlate.hp._tfDotBarBG:Hide() end
                if ns.NP and ns.NP.RestoreDotRenderOrder then ns.NP.RestoreDotRenderOrder(nameplate.myPlate.hp) end
                if nameplate.myPlate.hp._tfAbsorbBar then nameplate.myPlate.hp._tfAbsorbBar:Hide() end
                if nameplate.myPlate.hp._tfAbsorbOverlay then nameplate.myPlate.hp._tfAbsorbOverlay:Hide() end
                if nameplate.myPlate.hp._tfOverAbsorbGlow then nameplate.myPlate.hp._tfOverAbsorbGlow:Hide() end
            end
        end
    end
end

-- Re-evaluate all visible native plates after settings/faction changes.
function ns:UpdateAllPlates()
    -- Settings/faction refreshes are infrequent. Reuse the single native
    -- lifecycle classifier instead of maintaining a second parallel renderer.
    for _, nameplate in pairs(EnumerateActiveNamePlates()) do
        local unit = ns.API.GetPlateUnitToken(nameplate)
        if unit and UnitExists(unit) then
            OnNamePlateAdded(nil, unit, nameplate)
        end
    end
end

-- RefreshPlateForUnit: Re-evaluates plate type when faction changes
-- Called from UNIT_FACTION when the native presentation policy may change.
function ns:RefreshPlateForUnit(unit)
    local nameplate = GetNamePlateForUnit(unit)
    if nameplate then
        -- Re-run the single native lifecycle classifier.
        OnNamePlateAdded(nil, unit, nameplate)
    end
end

local _evtFrame = CreateFrame("Frame")
_evtFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local function ApplyAddedAfterBlizzard()
            local np = GetNamePlateForUnit(unit)
            if ns.DebugPlateTrace then
                ns:Chat("Plates", ("%.2f ADDED %s -> %s"):format(GetTime() % 1000,
                    tostring(unit), np and (np:GetName() or "frame") or "|cffff5555NO FRAME|r"))
            end
            if np then OnNamePlateAdded(nil, unit, np) end
        end
        -- Forever secret values are safe inside Blizzard's native CompactUnitFrame
        -- update only while execution remains clean. Never touch the pooled native
        -- plate during the same NAME_PLATE_UNIT_ADDED dispatch; wait one frame so
        -- Blizzard finishes SetUnit/CompactUnitFrame_UpdateAll first.
        if CorePolicy("deferNativeNameplateCallbacks") and RunNextFrame then
            RunNextFrame(ApplyAddedAfterBlizzard)
        else
            ApplyAddedAfterBlizzard()
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local function RefreshNameAfterBlizzard()
            -- Blizzard owns the native name. Re-evaluate only our adjuncts that
            -- derive placement/classification from that identity (Job Icon/title).
            if unit and ns.unitToNameplate[unit] then
                ns:RefreshPlateForUnit(unit)
            end
        end
        if CorePolicy("deferNativeNameplateCallbacks") and RunNextFrame then
            RunNextFrame(RefreshNameAfterBlizzard)
        else
            RefreshNameAfterBlizzard()
        end
    end
end)
-- NAME_PLATE_UNIT_REMOVED has its own small event frame so removal cleanup
-- remains explicit and independent of the added/name-update dispatcher.
local nameplateRemovedEventFrame = CreateFrame("Frame")
nameplateRemovedEventFrame:SetScript("OnEvent", function(_, _, unit)
    local nameplate = ns.unitToNameplate[unit]
    local function ApplyRemovedAfterBlizzard()
        if ns.DebugPlateTrace then
            local live = GetNamePlateForUnit(unit)
            ns:Chat("Plates", ("%.2f REMOVED %s tracked=%s live=%s token=%s"):format(
                GetTime() % 1000, tostring(unit),
                nameplate and (nameplate:GetName() or "frame") or "nil",
                live and (live:GetName() or "frame") or "nil",
                tostring(nameplate and ns.API.GetPlateUnitToken(nameplate))))
        end
        CallNamePlateRemoved(nil, unit, nameplate)
    end
    if CorePolicy("deferNativeNameplateCallbacks") and RunNextFrame then
        RunNextFrame(ApplyRemovedAfterBlizzard)
    else
        ApplyRemovedAfterBlizzard()
    end
end)

local coreNameplateEventsActive = false
ActivateCoreNameplateEvents = function()
    if coreNameplateEventsActive then return end
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return end
    coreNameplateEventsActive = true
    ns.RegisterEvent(_evtFrame, "NAME_PLATE_UNIT_ADDED")
    ns.RegisterEvent(_evtFrame, "UNIT_NAME_UPDATE")
    ns.RegisterEvent(nameplateRemovedEventFrame, "NAME_PLATE_UNIT_REMOVED")
end

SLASH_TURBOFACE1 = "/tf"
SLASH_TURBOFACE2 = "/turboface"
SlashCmdList["TURBOFACE"] = function(msg)
    if msg and msg ~= "" then
        local cmd, args = msg:match("^(%S+)%s*(.*)$")
        cmd = cmd and cmd:lower()

        if CorePolicy("extendedDiagnostics") and cmd == "compat" then
            if ns.Compat and ns.Compat.HandleSlash then ns.Compat:HandleSlash(args) end
            return
        end

        if cmd == "debug" then
            local normalized = (args or ""):lower():match("^%s*(.-)%s*$") or ""
            normalized = normalized:gsub("%s+", " ")
            local cpuArgs = normalized:match("^cpu%s*(.*)$")
            if cpuArgs ~= nil and ns.CPUProfiler and ns.CPUProfiler.HandleSlash then
                ns.CPUProfiler:HandleSlash(cpuArgs)
            elseif ns.Debug and ns.Debug.HandleSlash then
                ns.Debug:HandleSlash(normalized)
            else
                if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("TurboFace Debug: debug module unavailable") end
            end
            return
        end

        -- Direct alias for the CPU profiler. This bypasses the general debug
        -- dispatcher completely and makes command-routing failures obvious.
        if cmd == "cpu" then
            if ns.CPUProfiler and ns.CPUProfiler.HandleSlash then
                ns.CPUProfiler:HandleSlash(args)
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace CPU: profiler module unavailable")
            end
            return
        end

        if cmd == "cvars" or cmd == "cvar" then
            if ns.CVarBrowser and ns.CVarBrowser.Toggle then
                ns.CVarBrowser:Toggle(args)
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace CVars: browser unavailable")
            end
            return
        end

        if cmd == "sound" then
            if ns.AuditionSound then
                ns:AuditionSound(args)
            end
            return
        end

        if cmd == "hearthbatch" then
            if ns.HearthBatch then
                local a = args and args:lower() or ""
                if a:match("^reset") then
                    ns.HearthBatch:ResetCalibration(a:match("all") and "all" or nil)
                else
                    ns.HearthBatch:Status()
                end
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and cmd == "questprobe" then
            if ns.PlusAutomation and ns.PlusAutomation.QuestProbe then
                ns.PlusAutomation:QuestProbe()
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace Quest: automation module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and cmd == "talentprobe" then
            if ns.TalentPointReminder and ns.TalentPointReminder.Status then
                ns.TalentPointReminder:Status()
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace Talent: reminder module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and cmd == "powerprobe" then
            if ns.Power and ns.Power.Probe then
                ns.Power:Probe()
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace PowerProbe: power module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and (cmd == "trainerstyleprobe" or cmd == "trainerstyle") then
            if ns.Debug and ns.Debug.TrainerStyleProbe then
                ns.Debug:TrainerStyleProbe((args or ""):match("^%s*(.-)%s*$"))
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace TrainerStyle: debug module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and cmd == "professionprobe" then
            if ns.Debug and ns.Debug.ProfessionProbe then
                ns.Debug:ProfessionProbe((args or ""):match("^%s*(.-)%s*$"))
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace ProfessionProbe: debug module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and cmd == "professiondataprobe" then
            if ns.Debug and ns.Debug.ProfessionDataProbe then
                ns.Debug:ProfessionDataProbe((args or ""):match("^%s*(.-)%s*$"))
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace ProfessionData: debug module unavailable")
            end
            return
        end

        if CorePolicy("extendedDiagnostics") and (cmd == "nameplateapiprobe" or cmd == "nameplateprobe") then
            if ns.Debug and ns.Debug.NameplateAPIProbe then
                ns.Debug:NameplateAPIProbe((args or ""):match("^%s*(.-)%s*$"))
            elseif DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("TurboFace NameplateAPI: debug module unavailable")
            end
            return
        end

        if cmd == "meter" then
            if ns.Providers then ns.Providers:Call("combatMeter", "HandleSlash", args)
            elseif ns.CombatMeter and ns.CombatMeter.HandleSlash then ns.CombatMeter:HandleSlash(args) end
            return
        end

        if ns.Movers and ns.Movers.HandleSlash and ns.Movers:HandleSlash(cmd, args) then
            return
        end
    end

    if ns.ToggleGUI then
        ns:ToggleGUI()
    end
end

ns.RegisterCPUProfileTarget("Core/Main:Events", Core:GetScript("OnEvent"), false)
ns.RegisterCPUProfileTarget("Nameplates/NativeSuppress:AlphaHook", NativeSuppressionAlphaHook, false)
ns.RegisterCPUProfileTarget("Nameplates/NativeSuppress:ShowHook", NativeSuppressionShowHook, false)
ns.RegisterCPUProfileTarget("Nameplates/NativeSuppress:DriverAdded", NativeNameplateAddedHook)
ns.RegisterCPUProfileTarget("Nameplates/Core:AddedCreated", _evtFrame:GetScript("OnEvent"))
ns.RegisterCPUProfileTarget("Nameplates/Core:Removed", nameplateRemovedEventFrame:GetScript("OnEvent"))
