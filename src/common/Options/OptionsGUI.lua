local _, ns = ...

-- =============================================================================
-- TurboFace Options/OptionsGUI.lua
-- Tabbed panel registered with Blizzard InterfaceOptions
-- Tabs: Movers | Global | Nameplates | Unit Frames | Class | QoL | Speedrun | Profile
-- Open via /tf or Escape → Interface → AddOns → TurboFace
-- =============================================================================

-- (No module table here. OptionsGUI publishes nothing on ns: its only entry
-- point is the slash/minimap toggle below, and the old `ns.GUI` handle had
-- no readers.)

-- Tab content frames (one per tab, shown/hidden on tab click)
local tabs = {}
local activeTab = nil
local panelFrame = nil

local TAB_R, TAB_G, TAB_B = 0, 0.8, 1  -- cyan accent
local MergeDefaults = ns.MergeDefaults
local Client = ns.Client

local function ClientOptionPolicy(key, fallback)
    if Client and Client.GetOptionPolicy then
        local value = Client:GetOptionPolicy(key)
        if value ~= nil then return value end
    end
    return fallback
end

local function ClientFeatureAvailable(key, fallback)
    if Client and Client.IsFeatureAvailable then
        return Client:IsFeatureAvailable(key, fallback)
    end
    if fallback == nil then return true end
    return fallback == true
end

local function SettingDevelopmentRestriction(path)
    return Client and Client.GetSettingDevelopmentRestriction
        and Client:GetSettingDevelopmentRestriction(path) or nil
end

local function GateDevelopmentRestriction(family)
    return Client and Client.GetGateDevelopmentRestriction
        and Client:GetGateDevelopmentRestriction(family) or nil
end

local function DevelopmentRestrictionActive(key)
    return Client and Client.IsDevelopmentRestrictionActive
        and Client:IsDevelopmentRestrictionActive(key) or false
end

-- Only one custom options dropdown may be open at a time.  Keeping this
-- manager local to the GUI avoids coupling these lightweight menus to
-- Blizzard's dropdown implementation.
local activeDropdownPopup
local activeDropdownOwner

local function IsFrameOrDescendant(frame, ancestor)
    while frame do
        if frame == ancestor then return true end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return false
end

-- Detect mouse-down transitions without placing an invisible click-catcher over
-- the options panel.  This lets the original click continue to its target, so
-- clicking another dropdown both closes the first menu and opens the second.
local dropdownClickWatcher
local dropdownMouseWasDown = false

local function EnsureDropdownClickWatcher()
    if dropdownClickWatcher then return dropdownClickWatcher end
    dropdownClickWatcher = CreateFrame("Frame")
    dropdownClickWatcher:Hide()
    dropdownClickWatcher:SetScript("OnUpdate", function()
        local mouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if mouseDown and not dropdownMouseWasDown and activeDropdownPopup then
            local focus
            if GetMouseFoci then
                -- GetMouseFoci returns an ARRAY of frames (topmost first), not a
                -- frame. Unwrap it: treating the array itself as the focus frame
                -- made every inside-click look like an outside click.
                local foci = GetMouseFoci()
                if type(foci) == "table" then
                    focus = foci.GetParent and foci or foci[1]
                end
            elseif GetMouseFocus then
                focus = GetMouseFocus()
            end

            if not IsFrameOrDescendant(focus, activeDropdownPopup)
                and not IsFrameOrDescendant(focus, activeDropdownOwner) then
                activeDropdownPopup:Hide()
            end
        end
        dropdownMouseWasDown = mouseDown
    end)
    return dropdownClickWatcher
end

local function RegisterDropdownPopup(popup)
    popup:HookScript("OnHide", function(self)
        if activeDropdownPopup == self then
            activeDropdownPopup = nil
            activeDropdownOwner = nil
            dropdownMouseWasDown = false
            if dropdownClickWatcher then dropdownClickWatcher:Hide() end
        end
    end)
    return popup
end

local function ShowDropdownPopup(popup, owner)
    if activeDropdownPopup and activeDropdownPopup ~= popup then
        activeDropdownPopup:Hide()
    end
    activeDropdownPopup = popup
    activeDropdownOwner = owner
    -- Start from the current button state so the click that opened this popup is
    -- not mistaken for an outside-click transition on the following frame.
    dropdownMouseWasDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
    EnsureDropdownClickWatcher():Show()
    popup:Show()
end

local function ToggleDropdownPopup(popup, owner, openFunc)
    -- Sound lives here rather than at the four call sites so every dropdown in
    -- the panel behaves the same, and both opening and closing click.
    ns:PlayUISound("dropdownOpen")
    if popup:IsShown() then
        popup:Hide()
        return
    end
    if openFunc then openFunc() end
    ShowDropdownPopup(popup, owner)
end

local debounceTokens = {}
local function Debounce(key, delay, fn)
    key = tostring(key or "default")
    debounceTokens[key] = (debounceTokens[key] or 0) + 1
    local token = debounceTokens[key]
    local runner = function()
        if debounceTokens[key] ~= token then return end
        fn()
    end
    if ns.After then ns.After(delay or 0.10, runner) else runner() end
end

-- =============================================================================
-- OPTION DATABASE ACCESS
-- Widget keys may be top-level ("width") or nested paths
-- ("unitframes.playerHealthFormat"). This keeps one canonical saved-variable
-- location instead of maintaining shadow copies for the options interface.
-- =============================================================================

local function GetPathValue(root, path)
    if type(root) ~= "table" or type(path) ~= "string" then return nil end
    local node = root
    local from = 1
    while true do
        local dot = string.find(path, ".", from, true)
        local key = dot and string.sub(path, from, dot - 1) or string.sub(path, from)
        if type(node) ~= "table" then return nil end
        node = node[key]
        if not dot then return node end
        from = dot + 1
    end
end

local function SetPathValue(root, path, value)
    if type(root) ~= "table" or type(path) ~= "string" then return end
    local node = root
    local from = 1
    while true do
        local dot = string.find(path, ".", from, true)
        local key = dot and string.sub(path, from, dot - 1) or string.sub(path, from)
        if not dot then
            node[key] = value
            return
        end
        if type(node[key]) ~= "table" then node[key] = {} end
        node = node[key]
        from = dot + 1
    end
end

local function GetOptionValue(path)
    return GetPathValue(TurboFaceDB, path)
end

local function SetOptionValue(path, value)
    SetPathValue(TurboFaceDB, path, value)
end

local function GetOptionDefault(path)
    return GetPathValue(ns.defaults, path)
end

local function RefreshNameplateOptions()
    if ns.UpdateDBCache  then ns:UpdateDBCache()  end
    -- Forever owns nameplate presentation through the detached native-safe
    -- adapter. Never fall through to the Era callbacks below: several of them
    -- deliberately reanchor/hook Blizzard CompactUnitFrame regions.
    if ns.ForeverNameplates and ClientOptionPolicy("detachedNameplates", false) then
        if ns.SwingTimers and ns.SwingTimers.RefreshNameplateRuntime then
            ns.SwingTimers:RefreshNameplateRuntime()
        end
        ns.ForeverNameplates:Refresh()
        if ns.ClassFeatures then ns.ClassFeatures:Refresh() end
        return
    end
    if ns.RefreshNameplateThreatEvents then ns.RefreshNameplateThreatEvents() end
    if ns.RefreshNameplatePowerEvents then ns.RefreshNameplatePowerEvents() end
    if ns.RefreshNameplateComboDriver then ns.RefreshNameplateComboDriver() end
    -- Health-text centering is an anchor-only amendment on Blizzard's native
    -- restricted FontStrings. Refresh it explicitly so both the enable toggle
    -- and center-target toggle apply immediately to already pooled plates.
    if ns.RefreshNativeHealthTextCentering then ns.RefreshNativeHealthTextCentering() end
    -- Blizzard still owns rarity visibility and atlas selection; this refresh
    -- only swaps the existing PvE icon between its native and right-side anchor.
    if ns.RefreshNativeRarityIconPositions then ns.RefreshNativeRarityIconPositions() end
    -- The native-name shadow is a private FontObject amendment for Blizzard
    -- NPC and player names. Refresh explicitly so disabling it immediately
    -- restores Blizzard's FontObject on already pooled plates.
    if ns.RefreshNativeNameShadows then ns.RefreshNativeNameShadows() end
    if ns.BubbleNameplates and ns.BubbleNameplates.ApplyNameplateCVars then
        ns.BubbleNameplates:ApplyNameplateCVars()
    end
    if ns.SwingTimers and ns.SwingTimers.RefreshNameplateRuntime then
        ns.SwingTimers:RefreshNameplateRuntime()
    end
    if ns.UpdateAllPlates then ns:UpdateAllPlates() end
    if ns.BubbleNameplates and ns.BubbleNameplates.RefreshSwingFeature then
        ns.BubbleNameplates:RefreshSwingFeature()
    end
    if ns.ClassFeatures then ns.ClassFeatures:Refresh() end
end

local function RefreshUnitFrameOptions()
    if ns.UF  then ns.UF:Refresh()  end
    if ns.ST  then ns.ST:Refresh()  end
    if ns.Castbars then ns.Castbars:Refresh() end
end

local function RefreshAuraOptions()
    if ns.UpdateDBCache  then ns:UpdateDBCache()  end
    if ns.ForeverNameplates and ClientOptionPolicy("detachedNameplates", false) then
        ns.ForeverNameplates:Refresh()
    end
    if ns.UpdateAllPlates then ns:UpdateAllPlates() end
    if ns.AuraStyle      then ns.AuraStyle:Refresh() end
    if ns.PartyAuras     then ns.PartyAuras:Refresh() end
    if ns.ClassBuffs     then ns.ClassBuffs:Refresh() end
    if ns.Movers         then ns.Movers:Refresh() end
end

-- Capture one owner per lazy-built section. Resolve the namespace at click
-- time so a late-initialized owner is still respected; unrelated owners never
-- receive this local setting change. Cross-owner dependencies stay explicit.
local function RefreshOwner(name)
    return function()
        local owner = ns[name]
        if owner and owner.Refresh then owner:Refresh() end
    end
end

-- Standalone attack-row height also determines where the standalone cast row
-- begins, so geometry changes for Swing Timers refresh both owners. Width is
-- harmless to Castbars, but sharing one callback keeps the dimension controls
-- simple and deterministic.
local function RefreshStandaloneAttackGeometry()
    if ns.ST and ns.ST.Refresh then ns.ST:Refresh() end
    if ns.Castbars and ns.Castbars.Refresh then ns.Castbars:Refresh() end
end

local function RefreshClassOptions()
    if ns.UpdateDBCache  then ns:UpdateDBCache()  end   -- warrior overpower cache
    if ns.UpdateAllPlates then ns:UpdateAllPlates() end  -- overpower nameplate visual
    if ns.ClassFeatures then ns.ClassFeatures:Refresh() end
    if ns.ClassBuffs    then ns.ClassBuffs:Refresh()    end
    if ns.DruidPowerBar then ns.DruidPowerBar:Refresh() end
end

local function RefreshPlusOptions()
    -- Live-appliable Plus features re-sync from their :Refresh(); hook-based
    -- features (flagged reload-required in the tab) install once at Init.
    if ns.PlusAutomation then ns.PlusAutomation:Refresh() end
    if ns.PlusSocial     then ns.PlusSocial:Refresh()     end
    if ns.PlusInterface  then ns.PlusInterface:Refresh()  end
    if ns.PlusMap        then ns.PlusMap:Refresh()        end
    if ns.PlusSystem     then ns.PlusSystem:Refresh()     end
end

local function ApplySettings()
    if ns.UpdateDBCache  then ns:UpdateDBCache()  end
    if ns.UpdateAllPlates then ns:UpdateAllPlates() end
    if ns.UF             then ns.UF:Refresh()      end
    if ns.ST             then ns.ST:Refresh()      end
    if ns.Castbars            then ns.Castbars:Refresh()     end
    if ns.NW             then ns.NW:Refresh()      end
    if ns.FPSCounter     then ns.FPSCounter:Refresh() end
    if ns.HS             then ns.HS:Refresh()      end
    if ns.UnstuckSkipVisual then ns.UnstuckSkipVisual:Refresh() end
    if ns.HearthBatch    then ns.HearthBatch:Refresh() end
    if ns.Skills         then ns.Skills:Refresh() end
    if ns.DotPrediction  then ns.DotPrediction:Refresh() end
    if ns.HealPrediction then ns.HealPrediction:Refresh() end
    if ns.Providers then ns.Providers:Call("combatMeter", "Refresh")
    elseif ns.CombatMeter then ns.CombatMeter:Refresh() end
    if ns.LeashTimer    then ns.LeashTimer:Refresh() end
    if ns.SpeedrunSplits then ns.SpeedrunSplits:Refresh() end
    if ns.DPSBadge      then ns.DPSBadge:Refresh() end
    if ns.Tracker        then ns.Tracker:Refresh() end
    if ns.MinimapButton  then ns.MinimapButton:Refresh() end
    if ns.AuraStyle      then ns.AuraStyle:Refresh() end
    if ns.PartyAuras    then ns.PartyAuras:Refresh() end
    if ns.ClassBuffs    then ns.ClassBuffs:Refresh() end
    if ns.DruidPowerBar then ns.DruidPowerBar:Refresh() end
    if ns.Power          then ns.Power:Refresh()   end
    if ns.XP             then ns.XP:Refresh()      end
    if ns.Loot           then ns.Loot:Refresh()    end
    if ns.Movers         then ns.Movers:Refresh()  end
    if ns.ClassFeatures then ns.ClassFeatures:Refresh() end
end

local function ResolveApply(parent, applyFn)
    if type(applyFn) == "function" then return applyFn end
    local inherited = parent and parent._tfApply
    if type(inherited) == "function" then return inherited end
    return ApplySettings
end

-- =============================================================================
-- WIDGET HELPERS
-- =============================================================================

local function Backdrop(frame, r, g, b, a, br, bg_, bb)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
        frame:SetBackdropColor(r or 0.05, g or 0.05, b or 0.05, a or 0.92)
        frame:SetBackdropBorderColor(br or 0.15, bg_ or 0.15, bb or 0.15, 1)
    end
end

-- =============================================================================
-- MODULE MASTER TOGGLES (opt-out gates)
--
-- Two levels, both backed by TurboFaceDB.modules and read through
-- ns.ModuleEnabled so an unmigrated DB fails OPEN (everything enabled):
--
--   TAB GATE      MasterToggle() normally sits at the top of a tab. While
--                 unchecked, every ordinary section on that tab is hidden and
--                 contributes no height. Explicit ignoreMaster sections remain
--                 visible; Unit Frames uses that exception for Player Bar Tick
--                 Markers, which intentionally appears above its master toggle.
--   SECTION GATE  Header(..., family, element) puts a checkbox in the section
--                 header. While unchecked the section collapses to its header
--                 row and cannot be expanded.
--
-- RELOAD: TurboFace restyles PROTECTED Blizzard frames in place, so a gate that
-- has already applied artwork/hooks this session cannot be cleanly reversed at
-- runtime. Every gate therefore routes through GateChanged(), which offers a
-- reload -- the same full-reinitialization boundary profiles already use.
-- =============================================================================

-- A gate is either a MODULE gate (family[, element] -> TurboFaceDB.modules) or a
-- plain DB-KEY gate, passed as { dbKey = "invEnabled" }, which drives an
-- existing top-level setting. The Speedrun sections use the latter: their enable
-- flags predate the module system and are read directly by their own modules,
-- so they stay where they are and simply move into the header.
local function GateIsDBKey(family) return type(family) == "table" and family.dbKey ~= nil end

local function GateEnabled(family, element)
    if not family then return true end
    if Client and Client.IsGateDevelopmentRestricted
        and Client:IsGateDevelopmentRestricted(family) then
        return false
    end
    if GateIsDBKey(family) then
        local v = GetOptionValue(family.dbKey)
        return v == true or v == 1
    end
    if ns.ModuleEnabled then return ns.ModuleEnabled(family, element) end
    return true
end

local function GateWrite(family, element, value)
    if GateIsDBKey(family) then
        local on = value == true
        local before = GateEnabled(family)
        local changed = before ~= on
        SetOptionValue(family.dbKey, on)

        -- Optional DB-key dependencies keep closely-coupled live features in a
        -- valid state without inventing a second mirror setting. Enabling a
        -- dependent can auto-enable its requirement; disabling the requirement
        -- can turn off the dependent that cannot run without it.
        if on and family.requiresDbKey then
            local required = GetOptionValue(family.requiresDbKey)
            if required ~= true and required ~= 1 then
                SetOptionValue(family.requiresDbKey, true)
                changed = true
            end
        elseif not on and family.disablesDbKey then
            local dependent = GetOptionValue(family.disablesDbKey)
            if dependent == true or dependent == 1 then
                SetOptionValue(family.disablesDbKey, false)
                changed = true
            end
        end
        return changed
    end
    if ns.SetModuleEnabled then return ns.SetModuleEnabled(family, element, value) end
    return false
end

-- There is deliberately NO gate->legacy mirror here any more. It only ever ran
-- from the checkbox handler, so a profile apply or import (which replaces
-- TurboFaceDB wholesale) left the gate and its mirror free to disagree.
--
--   * unitframes.partyEnabled was folded into modules.unitframes.party by
--     migration 27->28 and no longer exists.
--   * power.actionOverlayEnabled stays, because it has its own checkbox and
--     PowerCost.OverlayEnabled already ANDs it with the gate. Mirroring it was
--     redundant and actively destructive: turning the module master back on
--     wrote `true` over whatever the user had chosen there.
--
-- If a future gate needs a derived value, derive it at read time or in
-- LoadVariables -- not in a GUI callback that import never runs.

local function GateChanged(family, element, changed, applyFn, parent)
    if GateIsDBKey(family) then
        -- These drive live settings, not module activation: run the tab's apply
        -- path instead of asking for a reload.
        if changed then ResolveApply(parent, applyFn)() end
        return
    end
    if not changed then return end

    -- Forever's detached Nameplate, Aura, and Hotbar Power adapters own their complete
    -- lifecycle and can safely activate/deactivate from their refresh paths.
    -- Do not send these two gates through the legacy reload prompt: the beta's
    -- SavedVariables loader may restore an older snapshot during /reload and
    -- undo the user's just-selected test state.
    if ClientOptionPolicy("liveAdapterFamilies", false)
        and (family == "nameplates" or family == "auras" or family == "hotbarPower")
    then
        ResolveApply(parent, applyFn)()
        return
    end

    -- Plus sections contain several live/dynamic runtimes. Re-sync them before
    -- offering the reload so disabling a section immediately unregisters its
    -- events and restores any CVar overrides owned by that section. One-way
    -- hooks still rely on the reload boundary, exactly as before.
    if family == "plus" then
        ResolveApply(parent, applyFn)()
    end

    if StaticPopup_Show then StaticPopup_Show("TURBOFACE_GATE_RELOAD") end
end

if StaticPopupDialogs and not StaticPopupDialogs["TURBOFACE_GATE_RELOAD"] then
    StaticPopupDialogs["TURBOFACE_GATE_RELOAD"] = {
        text = "TurboFace: enabling or disabling a feature needs a UI reload to apply cleanly.\n\nReload now?",
        button1 = RELOADUI or "Reload UI",
        button2 = LATER or "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- =============================================================================
-- COLLAPSIBLE SECTIONS
-- Header() starts a section: a container frame chained to the previous
-- section's bottom. Widget helpers route their widgets into the current
-- section's content frame (SectionParent), so clicking a header to collapse
-- hides that section's rows and the anchor chain pulls everything below up.
-- Default is expanded; state is remembered for the session.
-- =============================================================================
local SECTION_HEADER_H = 22
local CATEGORY_TOOLTIP_MAX_WIDTH = 320
local sectionCollapsed = {}   -- ["TabName:Header text"] = true

-- Redirect (parent, y) into the current section's content frame. The content
-- frame is anchored so BUILDER-ABSOLUTE y offsets land at the right spot
-- inside it, so y is returned UNCHANGED -- helpers keep returning absolute
-- layout positions to the builders. Idempotent for composed helpers.
local function SectionParent(parent, y)
    if parent._tfSectionContent then return parent, y end
    local sec = parent._tfCurSection
    if sec then
        return sec.content, y
    end
    return parent, y
end

-- Apply collapsed/expanded heights down the chain + resize the scroll child
-- A section hidden by its tab's master gate must contribute NO height, or the
-- anchor chain leaves a stack of empty header-sized gaps. Frames cannot take a
-- literal 0 height, so collapse to an epsilon instead.
local GATE_HIDDEN_H = 0.001

local function UpdateSectionLayout(c)
    local total = c._tfPreambleH or 0
    local masterOn = (not c._tfMasterGate) or GateEnabled(c._tfMasterGate)
    for _, sec in ipairs(c._tfSections or {}) do
        if sec.gateCheck then sec.gateCheck:SetChecked(GateEnabled(sec.gateFamily, sec.gateElement)) end
        -- A master-toggle block can sit inside the anchor chain when an
        -- independent section precedes it. It is always visible and has a
        -- fixed height; only the ordinary sections after it follow the master.
        if sec.isMasterBlock then
            sec.frame:Show()
            sec.frame:SetHeight(sec.fullH or SECTION_HEADER_H)
            total = total + (sec.fullH or SECTION_HEADER_H)
        elseif sec.isFlatMasterContent then
            -- A headerless settings surface still participates in the master
            -- gate and measured anchor chain; it simply has no category chrome
            -- or user-collapse state of its own.
            if not masterOn then
                sec.frame:Hide()
                sec.frame:SetHeight(GATE_HIDDEN_H)
                sec.content:Hide()
            else
                local h = sec.fullH or GATE_HIDDEN_H
                sec.frame:Show()
                sec.frame:SetHeight(h)
                sec.content:Show()
                total = total + h
            end
        else
            -- Most sections follow the tab master. A deliberately independent
            -- section (currently Unit Frames -> Player Bar Tick Markers) stays
            -- reachable because its runtime can augment stock Blizzard frames.
            local sectionMasterOn = masterOn or sec.ignoreMaster == true
            if not sectionMasterOn then
                sec.frame:Hide()
                sec.frame:SetHeight(GATE_HIDDEN_H)
                sec.content:Hide()
            else
                sec.frame:Show()
                local gateOn = GateEnabled(sec.gateFamily, sec.gateElement)
                local collapsed = sectionCollapsed[sec.key] or (not gateOn)
                local h = collapsed and SECTION_HEADER_H or (sec.fullH or SECTION_HEADER_H)
                sec.frame:SetHeight(h)
                sec.content:SetShown(not collapsed)
                if sec.gateCheck then sec.gateCheck:SetChecked(gateOn) end
                sec.toggle:SetText((not gateOn) and "" or (collapsed and "+" or "-"))
                if sec.label then
                    if gateOn then sec.label:SetTextColor(TAB_R, TAB_G, TAB_B)
                    else sec.label:SetTextColor(0.45, 0.45, 0.45) end
                end
                total = total + h
            end
        end
    end
    local contentHeight
    if #(c._tfSections or {}) > 0 then
        contentHeight = total + 40
    elseif c._tfBuildEndH then
        contentHeight = c._tfBuildEndH
    end
    if contentHeight then
        c:SetHeight(contentHeight)

        -- Classic can retain the scroll child's old rectangle after a lazy
        -- build or a collapse that shortens the tab. Refresh it explicitly and
        -- keep an old scroll offset from sitting below the new real bottom.
        local sf = c._tfScrollFrame
        if sf and sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
        if sf and sf.GetVerticalScrollRange and sf.GetVerticalScroll and sf.SetVerticalScroll then
            local range = tonumber(sf:GetVerticalScrollRange()) or 0
            if sf:GetVerticalScroll() > range then sf:SetVerticalScroll(range) end
        end
    end
end

local developmentRestrictedControls = {}

local function RefreshDevelopmentRestrictedControl(entry)
    local restricted = DevelopmentRestrictionActive(entry.restrictionKey)
    if restricted then
        entry.control:SetChecked(false)
        entry.control:Disable()
        entry.control:SetAlpha(0.4)
        if entry.label then entry.label:SetTextColor(0.45, 0.45, 0.45) end
        if entry.developmentHoverShield then entry.developmentHoverShield:Show() end
    else
        if entry.developmentHoverShield then entry.developmentHoverShield:Hide() end
        entry.control:Enable()
        entry.control:SetAlpha(1)
        if entry.readChecked then entry.control:SetChecked(entry.readChecked()) end
        if entry.label and entry.enabledColor then
            -- Forever's FontString:GetTextColor() may return a ColorMixin rather
            -- than separate RGB numbers.  Keep known numeric colors instead of
            -- round-tripping that client-specific return value.
            entry.label:SetTextColor(
                entry.enabledColor[1],
                entry.enabledColor[2],
                entry.enabledColor[3]
            )
        end
    end
end

local function RegisterDevelopmentRestrictedControl(control, label, restrictionKey, readChecked, enabledColor, hoverWidth)
    if not control or not restrictionKey then return end
    local entry = {
        control = control,
        label = label,
        restrictionKey = restrictionKey,
        readChecked = readChecked,
        enabledColor = label and (enabledColor or {0.85, 0.85, 0.85}) or nil,
    }

    -- A disabled CheckButton does not receive reliable mouse events.  Use a
    -- transparent sibling above the whole option row so the restriction
    -- tooltip works over both the checkbox and its label, and so clicks cannot
    -- leak through while the option is locked.
    local hover = CreateFrame("Button", nil, control:GetParent())
    hover:SetPoint("LEFT", control, "LEFT", 0, 0)
    hover:SetSize(hoverWidth or 164, 24)
    hover:SetFrameLevel(control:GetFrameLevel() + 10)
    hover:EnableMouse(true)
    hover:SetScript("OnClick", function() end)
    hover:SetScript("OnEnter", function(self)
        if not DevelopmentRestrictionActive(restrictionKey) or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(Client.DEVELOPMENT_DISABLED_TOOLTIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == self) then
            GameTooltip:Hide()
        end
    end)
    hover:Hide()
    entry.developmentHoverShield = hover

    developmentRestrictedControls[#developmentRestrictedControls + 1] = entry
    RefreshDevelopmentRestrictedControl(entry)
end

function ns.RefreshDevelopmentRestrictedOptions()
    for _, entry in ipairs(developmentRestrictedControls) do
        RefreshDevelopmentRestrictedControl(entry)
    end
    for _, tab in pairs(tabs) do
        if tab._tfSections then UpdateSectionLayout(tab) end
    end
end

local function FinalizeSection(c, y)
    local sec = c._tfCurSection
    if sec and not sec.fullH then
        sec.fullH = sec.startY - y   -- builder y runs negative-down
    end
end

-- Called at the end of every tab build (replaces the old c:SetHeight lines)
local function FinalizeSections(c, y)
    FinalizeSection(c, y)
    c._tfCurSection = nil
    c._tfBuildEndH = math.abs(y) + 40
    UpdateSectionLayout(c)
end

-- Options chrome normally inherits Blizzard GameFont* FontObjects directly.
-- Category/title accents intentionally use OUTLINE, but route that override
-- through TurboFace's cached FontObject renderer too so the options panel
-- never falls back to per-FontString SetFont(..., "OUTLINE") mutation.
local function StyleOptionsOutline(fontString, size)
    if not fontString then return end
    local path = fontString.GetFont and fontString:GetFont() or nil
    ns:StyleFont(fontString, path, size, nil, "OUTLINE")
end

-- Header(parent, y, text[, gateFamily, gateElement, gateApplyFn, tooltipText])
-- Passing a gate renders a checkbox in the header row; the section's rows stay
-- hidden and un-expandable while it is unchecked. tooltipText moves compact
-- feature guidance onto the category header without consuming panel height.
local function Header(parent, y, text, gateFamily, gateElement, gateApplyFn, tooltipText)
    local c = parent
    if not c._tfSections then
        -- Legacy render (parent not section-enabled)
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
        line:SetColorTexture(TAB_R, TAB_G, TAB_B, 0.35)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - 4)
        lbl:SetTextColor(TAB_R, TAB_G, TAB_B)
        lbl:SetText(text:upper())
        StyleOptionsOutline(lbl, 11)
        return y - 22
    end

    FinalizeSection(c, y)
    local prev = c._tfSections[#c._tfSections]
    if not prev then c._tfPreambleH = -y end

    local sec = {
        key = (c._tfTabName or "?") .. ":" .. text,
        startY = y,
        gateFamily = gateFamily,
        gateElement = gateElement,
    }

    sec.frame = CreateFrame("Frame", nil, c)
    if prev then
        sec.frame:SetPoint("TOPLEFT", prev.frame, "BOTTOMLEFT", 0, 0)
    else
        sec.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    end
    sec.frame:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    sec.frame:SetHeight(SECTION_HEADER_H)

    local hdr = CreateFrame("Button", nil, sec.frame)
    hdr:SetHeight(SECTION_HEADER_H)
    hdr:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", sec.frame, "TOPRIGHT", 0, 0)

    local line = hdr:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  hdr, "TOPLEFT",  0, 0)
    line:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", 0, 0)
    line:SetColorTexture(TAB_R, TAB_G, TAB_B, 0.35)

    local textX = 12

    local gateControl
    if gateFamily then
        -- The gate checkbox is a child of the header BUTTON but must swallow its
        -- own clicks, otherwise ticking the box would also toggle the collapse.
        local gate = CreateFrame("CheckButton", nil, hdr, "UICheckButtonTemplate")
        gate:SetSize(18, 18)
        gate:SetPoint("TOPLEFT", hdr, "TOPLEFT", -2, -2)
        gate:SetChecked(GateEnabled(gateFamily, gateElement))
        gate:SetScript("OnClick", function(self)
            if DevelopmentRestrictionActive(GateDevelopmentRestriction(gateFamily)) then return end
            ns:PlayCheckSound(self)
            local on = self:GetChecked() == true or self:GetChecked() == 1
            local changed = GateWrite(gateFamily, gateElement, on)
            -- Re-expand on enable so the newly available rows are visible
            -- immediately instead of hiding behind a stale collapsed state.
            if on then sectionCollapsed[sec.key] = nil end
            UpdateSectionLayout(c)
            GateChanged(gateFamily, gateElement, changed, gateApplyFn, c)
        end)
        sec.gateCheck = gate
        gateControl = gate
        textX = 34
    end

    local toggle = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggle:SetPoint("TOPLEFT", hdr, "TOPLEFT", textX - 12, -4)
    toggle:SetTextColor(TAB_R, TAB_G, TAB_B)
    StyleOptionsOutline(toggle, 11)
    sec.toggle = toggle

    local lbl = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", hdr, "TOPLEFT", textX, -4)
    lbl:SetTextColor(TAB_R, TAB_G, TAB_B)
    lbl:SetText(text:upper())
    StyleOptionsOutline(lbl, 11)
    sec.label = lbl

    if gateControl then
        RegisterDevelopmentRestrictedControl(gateControl, lbl,
            GateDevelopmentRestriction(gateFamily),
            function() return GateEnabled(gateFamily, gateElement) end,
            {TAB_R, TAB_G, TAB_B}, 300)
    end

    hdr:SetScript("OnEnter", function(self)
        if GateEnabled(sec.gateFamily, sec.gateElement) then lbl:SetTextColor(1, 1, 1) end
        if tooltipText and tooltipText ~= "" and GameTooltip then
            -- Anchor where the pointer enters the category instead of at the
            -- panel edge. A wrapped AddLine respects the tooltip width cap and
            -- is supported by Classic's legacy tooltip API.
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:SetWidth(CATEGORY_TOOLTIP_MAX_WIDTH)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    hdr:SetScript("OnLeave", function(self)
        if GateEnabled(sec.gateFamily, sec.gateElement) then
            lbl:SetTextColor(TAB_R, TAB_G, TAB_B)
        else
            lbl:SetTextColor(0.45, 0.45, 0.45)
        end
        if GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == self) then
            GameTooltip:Hide()
        end
    end)
    hdr:SetScript("OnClick", function()
        -- A gated-off section has nothing to show; ignore collapse clicks so the
        -- header cannot be expanded into an empty box.
        if not GateEnabled(sec.gateFamily, sec.gateElement) then return end
        -- Sound goes AFTER the gate check: a click that is deliberately ignored
        -- should stay silent rather than imply something happened.
        ns:PlayUISound("tab")
        sectionCollapsed[sec.key] = not sectionCollapsed[sec.key] or nil
        UpdateSectionLayout(c)
    end)

    -- Content holder. Anchored ABOVE the frame top by |startY| so that rows
    -- positioned with builder-absolute y offsets (which include everything
    -- laid out before this section) land exactly below this section's header.
    sec.content = CreateFrame("Frame", nil, sec.frame)
    sec.content:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 0, -sec.startY)
    sec.content:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    sec.content:SetHeight(1)
    sec.content._tfSectionContent = true
    sec.content._tfApply = c._tfApply

    c._tfSections[#c._tfSections + 1] = sec
    c._tfCurSection = sec
    return y - SECTION_HEADER_H
end

-- A section may live on a tab for organizational reasons without sharing the
-- tab's runtime master. This keeps its controls visible when the parent styling
-- family is disabled.
local function IndependentHeader(parent, y, text, gateFamily, gateElement, gateApplyFn, tooltipText)
    local nextY = Header(parent, y, text, gateFamily, gateElement, gateApplyFn, tooltipText)
    if parent._tfCurSection then parent._tfCurSection.ignoreMaster = true end
    return nextY
end

-- Begin one master-gated settings surface without rendering category chrome.
-- Used by flat tabs whose parent master is the only desired visual heading.
local function FlatMasterContent(c, y)
    FinalizeSection(c, y)
    local prev = c._tfSections and c._tfSections[#c._tfSections] or nil
    if not c._tfSections then c._tfSections = {} end
    if not prev then c._tfPreambleH = -y end

    local sec = {
        key = (c._tfTabName or "?") .. ":FlatMasterContent",
        startY = y,
        isFlatMasterContent = true,
    }
    sec.frame = CreateFrame("Frame", nil, c)
    if prev then
        sec.frame:SetPoint("TOPLEFT", prev.frame, "BOTTOMLEFT", 0, 0)
    else
        sec.frame:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
    end
    sec.frame:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    sec.frame:SetHeight(GATE_HIDDEN_H)

    sec.content = CreateFrame("Frame", nil, sec.frame)
    sec.content:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 0, -sec.startY)
    sec.content:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    sec.content:SetHeight(1)
    sec.content._tfSectionContent = true
    sec.content._tfApply = c._tfApply

    c._tfSections[#c._tfSections + 1] = sec
    c._tfCurSection = sec
    return y
end

-- Shared three-column content grid.  The scroll child is 504px wide; three
-- 164px controls plus two 6px gutters fill it exactly to the scrollbar-side
-- edge of the scroll child.  Row helpers that intentionally contain only
-- two related controls still align to the first two grid columns.
local GRID_COL_W = 164
local GRID_COL2_X = 170
local GRID_COL3_X = 340

local function Checkbox(parent, y, x, label, dbKey, applyFn)
    parent, y = SectionParent(parent, y)
    if label == "" then return y - 26 end
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
    local v = GetOptionValue(dbKey)
    cb:SetChecked(v == true or v == 1)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    cb:SetScript("OnClick", function(self)
        if DevelopmentRestrictionActive(SettingDevelopmentRestriction(dbKey)) then return end
        ns:PlayCheckSound(self)
        SetOptionValue(dbKey, self:GetChecked() == 1 or self:GetChecked() == true)
        ResolveApply(parent, applyFn)()
    end)
    RegisterDevelopmentRestrictedControl(cb, lbl, SettingDevelopmentRestriction(dbKey), function()
        local current = GetOptionValue(dbKey)
        return current == true or current == 1
    end, {0.85, 0.85, 0.85}, 164)
    -- Returns the frame and label as well so a caller can build a dependent
    -- sub-option. Existing `y = Checkbox(...)` call sites ignore the extras.
    return y - 26, cb, lbl
end

-- Grey out a sub-option whose parent toggle is off. Enable/Disable rather than
-- SetEnabled for Classic compatibility; the label is dimmed separately because
-- disabling a CheckButton does not touch a FontString that is merely anchored
-- to it.
local function SetSubOptionEnabled(cb, lbl, on)
    if not cb then return end
    if DevelopmentRestrictionActive(cb._tfDevelopmentRestrictionKey) then on = false end
    if on then cb:Enable() else cb:Disable() end
    cb:SetAlpha(on and 1 or 0.4)
    if lbl then
        local v = on and 0.85 or 0.45
        lbl:SetTextColor(v, v, v)
    end
end

local function CheckboxRow(parent, y, label1, key1, label2, key2, applyFn)
    local _, first = Checkbox(parent, y, 0, label1, key1, applyFn)
    local second, secondLabel
    if label2 and label2 ~= "" then
        _, second, secondLabel = Checkbox(parent, y, GRID_COL2_X, label2, key2, applyFn)
    end
    -- Existing callers consume only the first return. The widget returns let a
    -- row opt into a dependent second control without changing other layouts.
    return y - 28, first, second, secondLabel
end

-- Non-interactive third-column guidance that aligns with checkbox text on the
-- same grid row. Kept separate from CheckboxRow so ordinary two-control rows
-- retain their existing ownership and return values.
local function CheckboxRowNote(parent, y, text)
    parent, y = SectionParent(parent, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", GRID_COL3_X, y - 2)
    fs:SetWidth(GRID_COL_W)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(0.5, 0.5, 0.5)
    return fs
end

local SUBOPTION_INDENT = 16

-- A true dependency belongs UNDER its parent, not beside it.  Keep both in the
-- same grid column, indent the child, and disable/dim it while the parent is off.
-- Independent controls should continue to use Checkbox/CheckboxRow and can fill
-- the other grid columns normally.
local function DependentCheckboxColumn(parent, y, x, parentLabel, parentKey, childLabel, childKey, applyFn)
    local _, parentCB = Checkbox(parent, y, x, parentLabel, parentKey, applyFn)
    local _, childCB, childLabelFS = Checkbox(parent, y - 26, x + SUBOPTION_INDENT, childLabel, childKey, applyFn)

    local function RefreshChild()
        local v = GetOptionValue(parentKey)
        SetSubOptionEnabled(childCB, childLabelFS, v == true or v == 1)
    end
    if parentCB and parentCB.HookScript then parentCB:HookScript("OnClick", RefreshChild) end
    RefreshChild()
    return y - 54, parentCB, childCB, childLabelFS
end

-- Compact module-child gate for a section that is already inside its family
-- header. Party/Pet aura surfaces use this so both toggles can live together
-- under Global -> Auras while still getting the normal reload-oriented module
-- gate semantics required by one-way Blizzard-frame suppression hooks.
local function ModuleGateCheckbox(parent, y, x, label, family, element, applyFn)
    parent, y = SectionParent(parent, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
    cb:SetChecked(GateEnabled(family, element))
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    cb:SetScript("OnClick", function(self)
        ns:PlayCheckSound(self)
        local on = self:GetChecked() == true or self:GetChecked() == 1
        local changed = GateWrite(family, element, on)
        GateChanged(family, element, changed, applyFn, parent)
    end)
    return y - 26
end

local function ModuleGateCheckboxRow(parent, y, label1, family1, element1, label2, family2, element2, applyFn)
    ModuleGateCheckbox(parent, y, 0, label1, family1, element1, applyFn)
    if label2 and family2 and element2 then
        ModuleGateCheckbox(parent, y, GRID_COL2_X, label2, family2, element2, applyFn)
    end
    return y - 28
end

-- Tab-level master gate. Call this FIRST in a tab builder, before any Header.
-- It opens an always-visible section holding the big toggle plus a one-line
-- explanation, and registers the gate so UpdateSectionLayout hides every later
-- section on the tab while it is off.
-- Tab-level master gate. Call this FIRST in a tab builder, before any Header.
--
-- It is deliberately NOT a collapsible section: the widgets are drawn straight
-- onto the tab's content frame, so the toggle sits at the very top with no
-- header bar and nothing to expand or collapse. Everything drawn before the
-- first Header becomes the tab's preamble (Header records `_tfPreambleH` from
-- the y it receives), so the section stack lays out beneath it automatically.
--
-- Because the toggle no longer lives in a section, UpdateSectionLayout can hide
-- EVERY section when the gate is off without hiding the control that turns it
-- back on -- which is why the old `alwaysShow` exemption is gone.
local function MasterToggle(c, y, label, family, description, applyFn)
    c._tfMasterGate = family

    -- Most tabs put their master first, where it is normal preamble content.
    -- Unit Frames intentionally has the independent Player Bar Tick Markers
    -- section above its master. In that case, make the master a fixed-height
    -- anchor-chain block so collapsing the independent section pulls the master
    -- (and all following sections) upward instead of leaving an empty gap.
    if c._tfSections and #c._tfSections > 0 then
        FinalizeSection(c, y)
        c._tfCurSection = nil

        local prev = c._tfSections[#c._tfSections]
        local blockH = 30 + (description and 36 or 0) + 6
        local block = {
            key = (c._tfTabName or "?") .. ":MasterToggle:" .. tostring(family),
            fullH = blockH,
            isMasterBlock = true,
            ignoreMaster = true,
        }
        block.frame = CreateFrame("Frame", nil, c)
        block.frame:SetPoint("TOPLEFT", prev.frame, "BOTTOMLEFT", 0, 0)
        block.frame:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        block.frame:SetHeight(blockH)

        local cb = CreateFrame("CheckButton", nil, block.frame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", block.frame, "TOPLEFT", -2, 0)
        cb:SetChecked(GateEnabled(family))
        local lbl = block.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        lbl:SetText("Enable " .. label)
        lbl:SetTextColor(1, 0.82, 0)
        cb:SetScript("OnClick", function(self)
            if DevelopmentRestrictionActive(GateDevelopmentRestriction(family)) then return end
            ns:PlayCheckSound(self)
            local on = self:GetChecked() == true or self:GetChecked() == 1
            local changed = GateWrite(family, nil, on)
            UpdateSectionLayout(c)
            GateChanged(family, nil, changed, applyFn, c)
        end)
        RegisterDevelopmentRestrictedControl(cb, lbl, GateDevelopmentRestriction(family),
            function() return GateEnabled(family) end,
            {1, 0.82, 0}, 360)

        if description then
            local info = block.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            info:SetPoint("TOPLEFT", block.frame, "TOPLEFT", 0, -30)
            info:SetWidth(410)
            info:SetJustifyH("LEFT")
            info:SetText(description)
            info:SetTextColor(0.5, 0.5, 0.5)
        end

        c._tfSections[#c._tfSections + 1] = block
        return y - blockH
    end

    local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", c, "TOPLEFT", -2, y)
    cb:SetChecked(GateEnabled(family))
    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    lbl:SetText("Enable " .. label)
    lbl:SetTextColor(1, 0.82, 0)
    cb:SetScript("OnClick", function(self)
        if DevelopmentRestrictionActive(GateDevelopmentRestriction(family)) then return end
        ns:PlayCheckSound(self)
        local on = self:GetChecked() == true or self:GetChecked() == 1
        local changed = GateWrite(family, nil, on)
        UpdateSectionLayout(c)
        GateChanged(family, nil, changed, applyFn, c)
    end)
    RegisterDevelopmentRestrictedControl(cb, lbl, GateDevelopmentRestriction(family),
        function() return GateEnabled(family) end,
        {1, 0.82, 0}, 360)
    y = y - 30

    if description then
        local info = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
        info:SetWidth(410)
        info:SetJustifyH("LEFT")
        info:SetText(description)
        info:SetTextColor(0.5, 0.5, 0.5)
        y = y - 36
    end
    return y - 6
end

-- =============================================================================
-- THREE-COLUMN FLOW (sliders and dropdowns)
--
-- The options scroll child is 504px wide.  Standard controls use the shared
-- 164px grid above, so sliders/dropdowns can fill LEFT -> MIDDLE -> RIGHT
-- before advancing to the next row.  Existing builders still pass x = 0; the
-- placement decision therefore remains centralized here instead of being
-- duplicated across ~95 call sites.
--
-- A pending row remembers both its rendered top and the deepest next-y reached
-- by any control in that row.  Mixed 44/46px controls therefore remain aligned
-- and the tallest control decides where the next row begins.  Anything that
-- changes y between flow-capable controls naturally starts a new row.
--
-- Controls wider than GRID_COL_W (for example the intentional 300px Plus
-- controls) keep their requested width and own a full row.
-- =============================================================================
local function FlowPlace(parent, y, x, w, rowH)
    if x ~= 0 or (tonumber(w) or 0) > GRID_COL_W then
        parent._tfFlowState = nil
        return y, x, y - rowH
    end

    local state = parent._tfFlowState
    if state and state.nextY == y then
        local rowY = state.rowY
        local nextY = math.min(state.nextY, rowY - rowH)
        local col = state.nextCol or 2
        local drawX = (col == 2) and GRID_COL2_X or GRID_COL3_X

        if col >= 3 then
            parent._tfFlowState = nil
        else
            state.nextCol = col + 1
            state.nextY = nextY
        end
        return rowY, drawX, nextY
    end

    local nextY = y - rowH
    parent._tfFlowState = { rowY = y, nextY = nextY, nextCol = 2 }
    return y, 0, nextY
end

local SLIDER_VALUE_W = 46

local function SliderStepDecimals(step, isPct)
    local displayStep = (tonumber(step) or 1) * (isPct and 100 or 1)
    local text = string.format("%.6f", math.abs(displayStep))
    text = text:gsub("0+$", ""):gsub("%.$", "")
    local dot = text:find("%.")
    return dot and (#text - dot) or 0
end

local function FormatSliderValue(value, step, isPct)
    local display = (tonumber(value) or 0) * (isPct and 100 or 1)
    local decimals = SliderStepDecimals(step, isPct)
    local text = string.format("%." .. decimals .. "f", display)
    if decimals > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    if isPct then text = text .. "%" end
    return text
end

local function QuantizeSliderValue(value, minVal, maxVal, step)
    value = tonumber(value)
    minVal = tonumber(minVal) or 0
    maxVal = tonumber(maxVal) or minVal
    step = tonumber(step) or 0
    if not value or value ~= value then return nil end

    -- Direct-entry values outside the slider range clamp to the nearest endpoint
    -- instead of being rejected.  Preserve the configured endpoint exactly even
    -- when it is not an integer number of steps from the opposite endpoint.
    if value <= minVal then return minVal end
    if value >= maxVal then return maxVal end

    if step > 0 then
        value = minVal + math.floor(((value - minVal) / step) + 0.5) * step
    end
    if value < minVal then value = minVal end
    if value > maxVal then value = maxVal end
    -- Collapse harmless floating-point tails produced by fractional slider steps.
    return tonumber(string.format("%.10f", value)) or value
end

-- Cyan slider values double as direct-entry fields.  The edit box always shows
-- the slider's DISPLAY units (percent sliders therefore accept e.g. "75" or
-- "75%", not 0.75).  Non-numeric input restores the last valid slider value;
-- numeric input clamps to min/max and in-range values snap to the slider step.
local function SliderValueBox(parent, x, y, w, slider, minVal, maxVal, step, isPct)
    local box = CreateFrame("EditBox", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetSize(SLIDER_VALUE_W, 18)
    box:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y + 2)
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    -- OptionsSliderTemplate has a generous mouse hit region around its track/thumb.
    -- Keep the direct-entry field above that region so clicks anywhere in the box
    -- focus the EditBox instead of moving the underlying slider.
    box:SetFrameLevel((slider:GetFrameLevel() or 0) + 10)
    box:SetMaxLetters(12)
    box:SetJustifyH("CENTER")
    box:SetFontObject(GameFontHighlightSmall)
    box:SetTextInsets(3, 3, 0, 0)
    box:SetTextColor(0, 0.8, 1)
    Backdrop(box, 0.04, 0.04, 0.04, 0.82, 0.25, 0.25, 0.25)

    local function SetBorder(focused)
        if box.SetBackdropBorderColor then
            if focused then box:SetBackdropBorderColor(0, 0.8, 1, 1)
            else box:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end
        end
    end

    local function Refresh(value)
        box:SetText(FormatSliderValue(value, step, isPct))
    end

    local busy = false
    local function Revert(clearFocus)
        if busy then return end
        busy = true
        Refresh(slider:GetValue())
        box:HighlightText(0, 0)
        if clearFocus then box:ClearFocus() end
        busy = false
    end

    local function Commit(clearFocus)
        if busy then return end
        busy = true
        local raw = tostring(box:GetText() or "")
        raw = raw:match("^%s*(.-)%s*$") or raw
        if isPct then raw = raw:gsub("%%%s*$", "") end
        local displayValue = tonumber(raw)
        local value = displayValue and (displayValue / (isPct and 100 or 1)) or nil
        value = QuantizeSliderValue(value, minVal, maxVal, step)
        if value == nil then
            Refresh(slider:GetValue())
        else
            slider:SetValue(value)
            -- SetValue does not guarantee OnValueChanged when the value is
            -- unchanged, so always normalize the edit-box text here too.
            Refresh(slider:GetValue())
        end
        box:HighlightText(0, 0)
        if clearFocus then box:ClearFocus() end
        busy = false
    end

    box:SetScript("OnEditFocusGained", function(self)
        SetBorder(true)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function()
        SetBorder(false)
        Commit(false)
    end)
    box:SetScript("OnEnterPressed", function() Commit(true) end)
    box:SetScript("OnEscapePressed", function() Revert(true) end)

    Refresh(slider:GetValue())
    return box, Refresh
end

local function Slider(parent, y, x, w, label, dbKey, minVal, maxVal, step, isPct, applyFn)
    parent, y = SectionParent(parent, y)
    local nextY
    y, x, nextY = FlowPlace(parent, y, x, w, 46)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":")
    lbl:SetWidth(w - SLIDER_VALUE_W - 6) lbl:SetJustifyH("LEFT") lbl:SetWordWrap(false)
    lbl:SetTextColor(0.85, 0.85, 0.85)

    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetWidth(w) sl:SetHeight(14)
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    local initVal = GetOptionValue(dbKey)
    if initVal == nil then initVal = GetOptionDefault(dbKey) or minVal end
    sl:SetValue(initVal)
    if sl.Low  then sl.Low:SetText("")  end
    if sl.High then sl.High:SetText("") end
    if sl.Text then sl.Text:SetText("") end

    local valueBox, RefreshValue = SliderValueBox(parent, x, y, w, sl, minVal, maxVal, step, isPct)
    sl:SetScript("OnValueChanged", function(self, v)
        RefreshValue(v)
        SetOptionValue(dbKey, v)
        ResolveApply(parent, applyFn)()
    end)
    return nextY
end

local function Dropdown(parent, y, x, w, label, dbKey, options, applyFn)
    parent, y = SectionParent(parent, y)
    local nextY
    y, x, nextY = FlowPlace(parent, y, x, w, 44)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":")
    lbl:SetWidth(w) lbl:SetJustifyH("LEFT") lbl:SetWordWrap(false)
    lbl:SetTextColor(0.85, 0.85, 0.85)

    local btn = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    btn:SetSize(w, 20)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    Backdrop(btn, 0.1, 0.1, 0.1, 0.9, 0.3, 0.3, 0.3)

    local cur = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cur:SetPoint("LEFT", btn, "LEFT", 6, 0)
    cur:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    cur:SetJustifyH("LEFT") cur:SetTextColor(1, 1, 1)

    local arr = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arr:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arr:SetText("v") arr:SetTextColor(0.6, 0.6, 0.6)

    local function UpdateCur()
        local val = GetOptionValue(dbKey)
        for _, o in ipairs(options) do
            if o.value == val then cur:SetText(o.name) return end
        end
        cur:SetText(options[1] and options[1].name or "")
    end
    UpdateCur()

    local popup = RegisterDropdownPopup(CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate"))
    popup:SetFrameStrata("TOOLTIP") popup:SetWidth(w) popup:Hide()
    Backdrop(popup, 0.08, 0.08, 0.08, 0.98, 0.25, 0.25, 0.25)
    popup:SetHeight(#options * 18 + 4)
    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, popup)
        item:SetHeight(18)
        item:SetPoint("TOPLEFT",  popup, "TOPLEFT",  1, -(i-1)*18 - 2)
        item:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i-1)*18 - 2)
        local itxt = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itxt:SetPoint("LEFT", item, "LEFT", 6, 0)
        itxt:SetText(opt.name) itxt:SetTextColor(0.85, 0.85, 0.85)
        local hl = item:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints() hl:SetColorTexture(0, 0.8, 1, 0.12) hl:Hide()
        item:SetScript("OnEnter", function() hl:Show() itxt:SetTextColor(1,1,1) end)
        item:SetScript("OnLeave", function() hl:Hide() itxt:SetTextColor(0.85,0.85,0.85) end)
        item:SetScript("OnClick", function()
            ns:PlayUISound("option")
            SetOptionValue(dbKey, opt.value) UpdateCur() popup:Hide() ResolveApply(parent, applyFn)()
        end)
    end
    btn:EnableMouse(true)
    btn:SetScript("OnMouseDown", function()
        ToggleDropdownPopup(popup, btn, function()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:SetFrameLevel(btn:GetFrameLevel() + 20)
        end)
    end)
    return nextY
end

local function ColorPicker(parent, y, x, label, dbKey, applyFn)
    parent, y = SectionParent(parent, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":") lbl:SetTextColor(0.85, 0.85, 0.85)

    local sw = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    sw:SetSize(44, 18)
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
    if sw.SetBackdrop then
        sw:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
        sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end

    local function Refresh()
        local c = GetOptionValue(dbKey)
        if not c then return end
        local r, g, b = ns:Color(c, 1, 1, 1)
        if sw.SetBackdropColor then sw:SetBackdropColor(r, g, b, 1) end
    end
    Refresh()

    sw:SetScript("OnClick", function()
        ns:PlayUISound("option")
        local c = GetOptionValue(dbKey) or {r=1,g=1,b=1}
        local r0, g0, b0 = ns:Color(c, 1, 1, 1)
        ColorPickerFrame.swatchFunc = function()
            local r,g,b = ColorPickerFrame:GetColorRGB()
            SetOptionValue(dbKey, {r=r,g=g,b=b}) Refresh() ResolveApply(parent, applyFn)()
        end
        ColorPickerFrame.cancelFunc = function(prev)
            SetOptionValue(dbKey, {r=prev.r,g=prev.g,b=prev.b}) Refresh() ResolveApply(parent, applyFn)()
        end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacity = nil
        ColorPickerFrame:SetColorRGB(r0, g0, b0)
        ColorPickerFrame.previousValues = {r=r0,g=g0,b=b0}
        ColorPickerFrame:Hide() ColorPickerFrame:Show()
    end)
    return y - 44
end

local function ColorRow(parent, y, label1, key1, label2, key2, applyFn)
    ColorPicker(parent, y, 0,   label1, key1, applyFn)
    if label2 and label2 ~= "" then ColorPicker(parent, y, GRID_COL2_X, label2, key2, applyFn) end
    return y - 46
end

-- =============================================================================
-- SCROLLABLE TAB CONTENT
-- =============================================================================

local function MakeScrollTab(parent, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0,   0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 0)
    local c = CreateFrame("Frame", nil, sf)
    -- The builder assigns the real height. Starting at 2000 could be retained
    -- by Classic's scroll-child rectangle and leave a large blank tail.
    c:SetSize(w - 20, 1)
    c._tfScrollFrame = sf
    sf:SetScrollChild(c)
    return sf, c
end

-- =============================================================================
-- TAB CONTENT BUILDERS
-- =============================================================================

local W = GRID_COL_W

-- Font dropdowns expose only Blizzard-owned, locale-safe choices. Typography
-- is intentionally independent of LibSharedMedia.
local function FontOptions()
    local opts = (ns.GetFontOptions and ns.GetFontOptions()) or {}
    if #opts == 0 then
        for _, f in ipairs(ns.Fonts or {}) do opts[#opts + 1] = { name = f.name, value = f.name } end
    end
    return opts
end

local STYLE_OPTS = { {name="Shadow",value="SHADOW"}, {name="Outline",value="OUTLINE"}, {name="None",value="NONE"} }
local MINIMAP_SHAPES = {
    {name="Round (Blizzard)", value="round"},
    {name="Square",           value="square"},
}

-- Forward declaration: defined near the end of the file, rendered inside Global

-- =============================================================================
-- IMPORT/EXPORT DIALOG (shared, created on demand)
-- =============================================================================
local ioFrame
local function ClassDisplayName(token)
    if type(token) ~= "string" or token == "" then return "Unknown" end
    return token:sub(1, 1) .. token:sub(2):lower()
end

local function ShowIOFrame(mode)  -- settings, XP session, or Lvl1 Quick Setup transfer
    if not ioFrame then
        local f = CreateFrame("Frame", "TurboFaceIOFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
        f:SetSize(420, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        Backdrop(f, 0.05, 0.05, 0.05, 0.98, 0, 0.8, 1)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10)

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        f.classLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.classLabel:SetPoint("TOPLEFT", 12, -34)
        f.classLabel:SetText("Class Profile:")
        f.classLabel:Hide()

        f.classButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.classButton:SetSize(140, 20)
        f.classButton:SetPoint("TOPLEFT", 94, -29)
        f.classButton:Hide()

        f.classPopup = RegisterDropdownPopup(CreateFrame("Frame", nil, UIParent,
            BackdropTemplateMixin and "BackdropTemplate"))
        f.classPopup:SetFrameStrata("TOOLTIP")
        f.classPopup:SetWidth(140)
        f.classPopup:Hide()
        Backdrop(f.classPopup, 0.08, 0.08, 0.08, 0.98, 0.25, 0.25, 0.25)
        f.classItems = {}

        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", -30, 44)
        f.scrollFrame = sf

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetMaxLetters(0)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(370)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        f.editBox = eb

        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.hint:SetPoint("BOTTOMLEFT", 12, 26)
        f.hint:SetTextColor(0.5, 0.5, 0.5)

        f.actionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.actionBtn:SetSize(120, 22)
        f.actionBtn:SetPoint("BOTTOMRIGHT", -12, 8)

        f.classButton:SetScript("OnClick", function()
            if not f._l1qsTokens or #f._l1qsTokens == 0 then return end
            local popup = f.classPopup
            for i = 1, 9 do
                local item = f.classItems[i]
                if not item then
                    item = CreateFrame("Button", nil, popup)
                    item:SetHeight(18)
                    item:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i - 1) * 18 - 2)
                    item:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i - 1) * 18 - 2)
                    item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
                    local hl = item:CreateTexture(nil, "BACKGROUND")
                    hl:SetAllPoints()
                    hl:SetColorTexture(0, 0.8, 1, 0.12)
                    hl:Hide()
                    item:SetScript("OnEnter", function() hl:Show() end)
                    item:SetScript("OnLeave", function() hl:Hide() end)
                    item:SetScript("OnClick", function(self)
                        ns:PlayUISound("option")
                        f.exportClassToken = self.token
                        f.classButton:SetText(ClassDisplayName(self.token))
                        popup:Hide()
                        if f.RefreshL1QSExport then f:RefreshL1QSExport() end
                    end)
                    f.classItems[i] = item
                end
                local token = f._l1qsTokens[i]
                if token then
                    item.token = token
                    item.text:SetText(ClassDisplayName(token))
                    item:Show()
                else
                    item.token = nil
                    item:Hide()
                end
            end
            popup:SetHeight(#f._l1qsTokens * 18 + 4)
            ToggleDropdownPopup(popup, f.classButton, function()
                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", f.classButton, "BOTTOMLEFT", 0, -2)
                popup:SetFrameLevel(f:GetFrameLevel() + 30)
            end)
        end)

        function f:SetL1QSSelectorVisible(visible)
            self.classLabel:SetShown(visible)
            self.classButton:SetShown(visible)
            self.classPopup:Hide()
            self.scrollFrame:ClearAllPoints()
            self.scrollFrame:SetPoint("TOPLEFT", 12, visible and -58 or -34)
            self.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 44)
        end

        function f:RefreshL1QSExport()
            local str, err = ns.QuickSetup and ns.QuickSetup:ExportClassProfile(self.exportClassToken)
            self.editBox:SetText(str or "")
            if str then
                self.hint:SetText("Ctrl+C to copy (text is pre-selected).")
                self.editBox:SetFocus()
                self.editBox:HighlightText()
            else
                self.hint:SetText(err or "No stored class profile is available to export.")
            end
        end

        ioFrame = f
    end

    ioFrame.mode = mode
    ioFrame.importParsed = nil
    local xpSession = mode == "xp-export" or mode == "xp-import"
    local l1qs = mode == "l1qs-export" or mode == "l1qs-import"
    local exporting = mode == "export" or mode == "xp-export" or mode == "l1qs-export"
    ioFrame:SetL1QSSelectorVisible(mode == "l1qs-export")

    if exporting then
        if mode == "l1qs-export" then
            ioFrame.title:SetText("|cff00ccffTurbo|cffffffffFace|r  Export Lvl1QuickSetup")
            ioFrame._l1qsTokens = ns.QuickSetup and ns.QuickSetup:GetStoredClassTokens() or {}
            local current = ns.QuickSetup and ns.QuickSetup:GetCurrentClassToken()
            local selected
            for _, token in ipairs(ioFrame._l1qsTokens) do
                if token == current then selected = token break end
            end
            ioFrame.exportClassToken = selected or ioFrame._l1qsTokens[1]
            ioFrame.classButton:SetText(ioFrame.exportClassToken and ClassDisplayName(ioFrame.exportClassToken) or "No profiles")
            ioFrame.actionBtn:SetText("Reselect")
            ioFrame.actionBtn:SetScript("OnClick", function()
                ioFrame.editBox:SetFocus()
                ioFrame.editBox:HighlightText()
            end)
            ioFrame:RefreshL1QSExport()
        else
            ioFrame.title:SetText(xpSession
                and "|cff00ccffTurbo|cffffffffFace|r  Export XP Splits"
                or "|cff00ccffTurbo|cffffffffFace|r  Export Settings")
            ioFrame.hint:SetText("Ctrl+C to copy (text is pre-selected).")
            ioFrame.actionBtn:SetText("Reselect")
            ioFrame.actionBtn:SetScript("OnClick", function()
                ioFrame.editBox:SetFocus()
                ioFrame.editBox:HighlightText()
            end)
            local str = ""
            if ns.Profiles then str = xpSession and ns.Profiles:ExportXPSession() or ns.Profiles:Export() end
            ioFrame.editBox:SetText(str)
            ioFrame.editBox:SetFocus()
            ioFrame.editBox:HighlightText()
        end
    else
        if mode == "l1qs-import" then
            ioFrame.title:SetText("|cff00ccffTurbo|cffffffffFace|r  Import Lvl1QuickSetup")
            ioFrame.hint:SetText("Paste a TFL1QS1 export, then click Import. Replaces only that stored class profile.")
        else
            ioFrame.title:SetText(xpSession
                and "|cff00ccffTurbo|cffffffffFace|r  Import XP Splits"
                or "|cff00ccffTurbo|cffffffffFace|r  Import Settings")
            ioFrame.hint:SetText(xpSession
                and "Paste a TFXP1 export, then click Import. Replaces only this character's XP session."
                or "Paste an export string, then click Import. Applies and reloads the UI.")
        end
        ioFrame.actionBtn:SetText("Import")
        ioFrame.actionBtn:SetScript("OnClick", function()
            local parsed, err
            if l1qs then
                parsed, err = ns.QuickSetup and ns.QuickSetup:ValidateImport(ioFrame.editBox:GetText())
            elseif xpSession then
                parsed, err = ns.Profiles:ValidateXPSessionImport(ioFrame.editBox:GetText())
            else
                parsed, err = ns.Profiles:ValidateImport(ioFrame.editBox:GetText())
            end
            if not parsed then
                ns:Chat(l1qs and "Quick Setup" or "Profiles", "|cffff5555import failed:|r " .. tostring(err))
                return
            end
            ioFrame.importParsed = parsed
            if l1qs then
                StaticPopup_Show("TURBOFACE_L1QS_IMPORT_CONFIRM", ClassDisplayName(parsed.class))
            else
                StaticPopup_Show(xpSession and "TURBOFACE_XP_SESSION_IMPORT_CONFIRM" or "TURBOFACE_IMPORT_CONFIRM")
            end
        end)
        ioFrame.editBox:SetText("")
        ioFrame.editBox:SetFocus()
    end
    ioFrame:Show()
end

StaticPopupDialogs["TURBOFACE_IMPORT_CONFIRM"] = {
    text = "Replace ALL current TurboFace settings with the imported ones?\n\nThis will reload your UI.",
    button1 = "Import", button2 = "Cancel",
    OnAccept = function()
        if ioFrame and ioFrame.importParsed then
            ns.Profiles:ImportApply(ioFrame.importParsed)
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

StaticPopupDialogs["TURBOFACE_XP_SESSION_IMPORT_CONFIRM"] = {
    text = "Replace this character's current XP session with the imported session?\n\nTurboFace settings are not changed.",
    button1 = "Import", button2 = "Cancel",
    OnAccept = function()
        if ioFrame and ioFrame.importParsed and ns.Profiles:ImportXPSession(ioFrame.importParsed) then
            ns:Chat("XP Bar", "XP session imported")
            ioFrame.importParsed = nil
            ioFrame:Hide()
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

StaticPopupDialogs["TURBOFACE_L1QS_IMPORT_CONFIRM"] = {
    text = "Import %s Lvl1QuickSetup profile?\n\nThis replaces only the stored class Quick Setup profile. The active character is not changed.",
    button1 = "Import", button2 = "Cancel",
    OnAccept = function()
        if ioFrame and ioFrame.importParsed and ns.QuickSetup
            and ns.QuickSetup:ImportClassProfile(ioFrame.importParsed) then
            ioFrame.importParsed = nil
            ioFrame:Hide()
        end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

StaticPopupDialogs["TURBOFACE_PROFILE_LOAD"] = {
    text = "Load profile \"%s\"?\n\nThis replaces ALL current settings and reloads your UI.",
    button1 = "Load", button2 = "Cancel",
    OnAccept = function(self, data) ns.Profiles:Load(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

StaticPopupDialogs["TURBOFACE_PROFILE_DELETE"] = {
    text = "Delete profile \"%s\"?",
    button1 = "Delete", button2 = "Cancel",
    OnAccept = function(self, data) ns.Profiles:Delete(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = true,
}

StaticPopupDialogs["TURBOFACE_PRESET_APPLY"] = {
    text = "Apply preset \"%s\"?\n\nThis replaces ALL current settings (preset on top of factory defaults) and reloads your UI. Save a profile first if you want to keep your current setup.",
    button1 = "Apply", button2 = "Cancel",
    OnAccept = function(self, data) ns.Profiles:ApplyPreset(data) end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

-- The panel readout registers itself here rather than the button hooking the
-- popup's OnHide: StaticPopup frames are shared and recycled, so a per-click
-- HookScript would stack a closure on every press and never release them.
local hearthBatchRefresh

StaticPopupDialogs["TURBOFACE_HEARTHBATCH_CLEAR"] = {
    text = "Clear Hearthstone batch timing data for %s?\n\nThe calibrated lead and all measured samples for this realm are discarded. TurboFace starts from defaults and re-learns over your next several batches.",
    button1 = "Clear", button2 = "Cancel",
    OnAccept = function()
        if ns.HearthBatch then ns.HearthBatch:ResetCalibration() end
        if hearthBatchRefresh then hearthBatchRefresh() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = true, showAlert = 1,
}

-- =============================================================================
-- POWER WIDGET HELPERS (file scope)
-- Shared by Global -> Hotbar Power Overlay and Unit Frames -> Player Bar Tick
-- Markers. PowerCost still owns runtime behavior and TurboFaceDB.power storage;
-- tab placement is organizational only.
-- =============================================================================
local POWER_DEFAULTS = (ns.defaults and ns.defaults.power) or {}
local function PDB()
    if type(TurboFaceDB.power) ~= "table" then TurboFaceDB.power = {} end
    local db = TurboFaceDB.power
    MergeDefaults(db, POWER_DEFAULTS)
    return db
end
local function RefreshPower(mode)
    if not ns.Power then return end
    if mode == "render" and ns.Power.RenderOnly then
        ns.Power:RenderOnly()
    else
        ns.Power:Refresh()
    end
end
local function QueuePowerRefresh(mode)
    Debounce("power:" .. tostring(mode or "full"), 0.08, function()
        RefreshPower(mode)
    end)
end
local function PowerCheckbox(parent, y, x, label, field)
    parent, y = SectionParent(parent, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
    cb:SetChecked(PDB()[field] == true)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(label)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    cb:SetScript("OnClick", function(self)
        ns:PlayCheckSound(self)
        PDB()[field] = self:GetChecked() == true or self:GetChecked() == 1
        if field == "enabled" or field == "actionOverlayEnabled" then RefreshPower() else RefreshPower("render") end
    end)
    return y - 26, cb, lbl
end
local function PowerCheckboxRow(parent, y, label1, field1, label2, field2)
    PowerCheckbox(parent, y, 0, label1, field1)
    if label2 and field2 then PowerCheckbox(parent, y, GRID_COL2_X, label2, field2) end
    return y - 28
end

local function PowerDependentCheckboxColumn(parent, y, x, parentLabel, parentField, childLabel, childField)
    local _, parentCB = PowerCheckbox(parent, y, x, parentLabel, parentField)
    local _, childCB, childLabelFS = PowerCheckbox(parent, y - 26, x + SUBOPTION_INDENT, childLabel, childField)
    local function RefreshChild()
        SetSubOptionEnabled(childCB, childLabelFS, PDB()[parentField] == true)
    end
    if parentCB and parentCB.HookScript then parentCB:HookScript("OnClick", RefreshChild) end
    RefreshChild()
    return y - 54
end
local function PowerSlider(parent, y, x, w, label, field, minVal, maxVal, step, isPct)
    parent, y = SectionParent(parent, y)
    local nextY
    y, x, nextY = FlowPlace(parent, y, x, w, 44)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":")
    lbl:SetWidth(w - SLIDER_VALUE_W - 6) lbl:SetJustifyH("LEFT") lbl:SetWordWrap(false)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetWidth(w); sl:SetHeight(14)
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(PDB()[field] or minVal)
    if sl.Low then sl.Low:SetText("") end
    if sl.High then sl.High:SetText("") end
    if sl.Text then sl.Text:SetText("") end
    local valueBox, RefreshValue = SliderValueBox(parent, x, y, w, sl, minVal, maxVal, step, isPct)
    sl:SetScript("OnValueChanged", function(_, v)
        if step >= 1 then v = math.floor(v + 0.5) end
        PDB()[field] = v
        RefreshValue(v)
        QueuePowerRefresh("render")
    end)
    return nextY
end

local function PowerDropdown(parent, y, x, w, label, field, options)
    parent, y = SectionParent(parent, y)
    local nextY
    y, x, nextY = FlowPlace(parent, y, x, w, 44)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":")
    lbl:SetWidth(w) lbl:SetJustifyH("LEFT") lbl:SetWordWrap(false)
    lbl:SetTextColor(0.85, 0.85, 0.85)
    local btn = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    btn:SetSize(w, 20)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    Backdrop(btn, 0.1, 0.1, 0.1, 0.9, 0.3, 0.3, 0.3)
    local cur = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cur:SetPoint("LEFT", btn, "LEFT", 6, 0)
    cur:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    cur:SetJustifyH("LEFT"); cur:SetTextColor(1, 1, 1)
    local arr = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arr:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arr:SetText("v"); arr:SetTextColor(0.6, 0.6, 0.6)
    local function UpdateCur()
        local val = PDB()[field]
        for _, o in ipairs(options) do if o.value == val then cur:SetText(o.name); return end end
        cur:SetText(options[1] and options[1].name or "")
    end
    UpdateCur()
    local popup = RegisterDropdownPopup(CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate"))
    popup:SetFrameStrata("TOOLTIP"); popup:SetWidth(w); popup:Hide()
    Backdrop(popup, 0.08, 0.08, 0.08, 0.98, 0.25, 0.25, 0.25)
    popup:SetHeight(#options * 18 + 4)
    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, popup)
        item:SetHeight(18)
        item:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i - 1) * 18 - 2)
        item:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i - 1) * 18 - 2)
        local itxt = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itxt:SetPoint("LEFT", item, "LEFT", 6, 0)
        itxt:SetText(opt.name); itxt:SetTextColor(0.85, 0.85, 0.85)
        item:SetScript("OnClick", function()
            ns:PlayUISound("option")
            PDB()[field] = opt.value
            UpdateCur()
            popup:Hide()
            RefreshPower("render")
        end)
    end
    btn:EnableMouse(true)
    btn:SetScript("OnMouseDown", function()
        ToggleDropdownPopup(popup, btn, function()
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            popup:SetFrameLevel(btn:GetFrameLevel() + 20)
        end)
    end)
    return nextY
end
local function PowerColor(parent, y, x, label, field)
    parent, y = SectionParent(parent, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(label .. ":"); lbl:SetTextColor(0.85, 0.85, 0.85)
    local sw = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    sw:SetSize(44, 18)
    sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
    if sw.SetBackdrop then
        sw:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
        sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
    local function ColorAlpha(color, fallback)
        if type(color) ~= "table" then return fallback or 1 end
        local a = color.a or color[4]
        if a == nil then a = fallback or 1 end
        a = tonumber(a) or fallback or 1
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        return a
    end
    local function PickerAlpha(fallback)
        -- Classic Era exposes the legacy OpacitySliderFrame even when the
        -- retail-derived ColorPickerFrame also has GetColorAlpha. The legacy
        -- value is TRANSPARENCY (0 = fully opaque), not alpha; trusting the
        -- newer-looking method first can therefore save full opacity as a=0.
        -- Prefer the client-native Classic slider and invert it exactly once.
        if OpacitySliderFrame and OpacitySliderFrame.GetValue then
            local opacity = OpacitySliderFrame:GetValue()
            if opacity ~= nil then
                return ColorAlpha({ a = 1 - opacity }, fallback)
            end
        end
        if ColorPickerFrame.opacity ~= nil then
            return ColorAlpha({ a = 1 - ColorPickerFrame.opacity }, fallback)
        end
        -- Fallback for clients with the modern picker and no legacy opacity
        -- surface. GetColorAlpha is direct alpha on that API.
        if ColorPickerFrame.GetColorAlpha then
            local a = ColorPickerFrame:GetColorAlpha()
            if a ~= nil then return ColorAlpha({ a = a }, fallback) end
        end
        return ColorAlpha(nil, fallback)
    end
    local function Refresh()
        local color = PDB()[field]
        local r, g, b = ns:Color(color, 1, 1, 1)
        local a = ColorAlpha(color, 1)
        if sw.SetBackdropColor then sw:SetBackdropColor(r, g, b, a) end
    end
    Refresh()
    sw:SetScript("OnClick", function()
        ns:PlayUISound("option")
        local db = PDB()
        local color = db[field] or {r=1,g=1,b=1,a=1}
        local r0, g0, b0 = ns:Color(color, 1, 1, 1)
        local a0 = ColorAlpha(color, 1)
        local oldOverlayCustom = db.useCustomOverlayColor
        local oldCounterCustom = db.useCustomCounterColor
        local function MarkCustom()
            local pdb = PDB()
            if field == "overlayColor" then pdb.useCustomOverlayColor = true end
            if field == "counterColor" then pdb.useCustomCounterColor = true end
        end
        local function ApplyPickerColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = PickerAlpha(a0)
            MarkCustom()
            PDB()[field] = {r=r, g=g, b=b, a=a}
            Refresh(); QueuePowerRefresh("render")
        end
        ColorPickerFrame.swatchFunc = ApplyPickerColor
        ColorPickerFrame.opacityFunc = ApplyPickerColor
        ColorPickerFrame.cancelFunc = function(prev)
            local pdb = PDB()
            prev = prev or {}
            local pa = prev.a or prev[4] or (prev.opacity and (1 - prev.opacity)) or a0
            pdb[field] = {
                r = prev.r or prev[1] or r0,
                g = prev.g or prev[2] or g0,
                b = prev.b or prev[3] or b0,
                a = ColorAlpha({ a = pa }, a0),
            }
            pdb.useCustomOverlayColor = oldOverlayCustom
            pdb.useCustomCounterColor = oldCounterCustom
            Refresh(); QueuePowerRefresh("render")
        end
        MarkCustom()
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a0
        ColorPickerFrame:SetColorRGB(r0, g0, b0)
        ColorPickerFrame.previousValues = {r=r0, g=g0, b=b0, a=a0, opacity=1 - a0}
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end)
    return y - 44
end

local function PowerColorRow(parent, y, label1, field1, label2, field2)
    PowerColor(parent, y, 0, label1, field1)
    if label2 and field2 then PowerColor(parent, y, GRID_COL2_X, label2, field2) end
    return y - 46
end

local function BuildProfileTab(c)
    c._tfApply = ApplySettings
    local y = -6
    -- =========================================================================
    -- PROFILES
    -- =========================================================================
    y = Header(c, y, "Profiles")
    do
        local p, py = SectionParent(c, y)

        local nameLbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 4)
        nameLbl:SetText("Name:")
        nameLbl:SetTextColor(0.85, 0.85, 0.85)

        local nameBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        nameBox:SetSize(150, 20)
        nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 48, py)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(40)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local saveBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        saveBtn:SetSize(110, 22)
        saveBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 210, py + 1)
        saveBtn:SetText("Save Current")
        saveBtn:SetScript("OnClick", function()
            if ns.Profiles:Save(nameBox:GetText()) then
                nameBox:ClearFocus()
            end
        end)
        y = y - 30

        -- Saved-profile selector (items regenerate on every open, so the list
        -- is always current after saves/deletes -- no tab rebuild needed)
        local selected
        local selLbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 34)
        selLbl:SetText("Saved:")
        selLbl:SetTextColor(0.85, 0.85, 0.85)

        local selBtn = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate")
        selBtn:SetSize(150, 20)
        selBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 48, py - 30)
        Backdrop(selBtn, 0.1, 0.1, 0.1, 0.9, 0.3, 0.3, 0.3)
        local selCur = selBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selCur:SetPoint("LEFT", selBtn, "LEFT", 6, 0)
        selCur:SetPoint("RIGHT", selBtn, "RIGHT", -16, 0)
        selCur:SetJustifyH("LEFT")
        selCur:SetText("(select profile)")
        local selArr = selBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selArr:SetPoint("RIGHT", selBtn, "RIGHT", -4, 0)
        selArr:SetText("v")
        selArr:SetTextColor(0.6, 0.6, 0.6)

        local menu = RegisterDropdownPopup(CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate"))
        menu:SetFrameStrata("TOOLTIP")
        menu:SetWidth(150)
        menu:Hide()
        Backdrop(menu, 0.08, 0.08, 0.08, 0.98, 0.3, 0.3, 0.3)
        local items = {}
        local function OpenMenu()
            local names = ns.Profiles:List()
            if #names == 0 then
                ns:Chat("Profiles", "no saved profiles yet")
                return
            end
            for i, name in ipairs(names) do
                local item = items[i]
                if not item then
                    item = CreateFrame("Button", nil, menu)
                    item:SetHeight(18)
                    item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * 18)
                    item:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
                    item.txt = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    item.txt:SetPoint("LEFT", 4, 0)
                    item:SetScript("OnEnter", function(self) self.txt:SetTextColor(0, 0.8, 1) end)
                    item:SetScript("OnLeave", function(self) self.txt:SetTextColor(1, 1, 1) end)
                    items[i] = item
                end
                item.txt:SetText(name)
                item.txt:SetTextColor(1, 1, 1)
                item:SetScript("OnClick", function()
                    selected = name
                    selCur:SetText(name)
                    menu:Hide()
                end)
                item:Show()
            end
            for i = #names + 1, #items do items[i]:Hide() end
            menu:SetHeight(#names * 18 + 4)
            menu:ClearAllPoints()
            menu:SetPoint("TOPLEFT", selBtn, "BOTTOMLEFT", 0, -2)
            return true
        end
        selBtn:EnableMouse(true)
        selBtn:SetScript("OnMouseDown", function()
            if menu:IsShown() then
                menu:Hide()
            elseif OpenMenu() then
                ShowDropdownPopup(menu, selBtn)
            end
        end)

        local loadBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        loadBtn:SetSize(60, 22)
        loadBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 210, py - 29)
        loadBtn:SetText("Load")
        loadBtn:SetScript("OnClick", function()
            if not selected or not ns.Profiles:Exists(selected) then
                ns:Chat("Profiles", "select a saved profile first")
                return
            end
            local dlg = StaticPopup_Show("TURBOFACE_PROFILE_LOAD", selected)
            if dlg then dlg.data = selected end
        end)

        local delBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        delBtn:SetSize(60, 22)
        delBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 274, py - 29)
        delBtn:SetText("Delete")
        delBtn:SetScript("OnClick", function()
            if not selected or not ns.Profiles:Exists(selected) then
                ns:Chat("Profiles", "select a saved profile first")
                return
            end
            local dlg = StaticPopup_Show("TURBOFACE_PROFILE_DELETE", selected)
            if dlg then dlg.data = selected end
            selCur:SetText("(select profile)")
            selected = nil
        end)
        y = y - 34

        local pinfo = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        pinfo:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 64)
        pinfo:SetWidth(380)
        pinfo:SetJustifyH("LEFT")
        pinfo:SetText("Profiles are account-wide and survive Reset to Defaults. Loading a profile replaces all current settings and reloads the UI.")
        pinfo:SetTextColor(0.5, 0.5, 0.5)
        y = y - 34
    end
    y = y - 6

    -- =========================================================================
    -- IMPORT / EXPORT
    -- =========================================================================
    y = Header(c, y, "Import / Export")
    do
        local p, py = SectionParent(c, y)
        local exBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        exBtn:SetSize(150, 22)
        exBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 4)
        exBtn:SetText("Export Settings")
        exBtn:SetScript("OnClick", function() ShowIOFrame("export") end)

        local imBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        imBtn:SetSize(150, 22)
        imBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 160, py - 4)
        imBtn:SetText("Import Settings")
        imBtn:SetScript("OnClick", function() ShowIOFrame("import") end)

        local xpExBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        xpExBtn:SetSize(150, 22)
        xpExBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 34)
        xpExBtn:SetText("Export XP Splits")
        xpExBtn:SetScript("OnClick", function() ShowIOFrame("xp-export") end)

        local xpImBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        xpImBtn:SetSize(150, 22)
        xpImBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 160, py - 34)
        xpImBtn:SetText("Import XP Splits")
        xpImBtn:SetScript("OnClick", function() ShowIOFrame("xp-import") end)

        local l1ExBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        l1ExBtn:SetSize(150, 22)
        l1ExBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 64)
        l1ExBtn:SetText("Export Lvl1QuickSetup")
        l1ExBtn:SetScript("OnClick", function() ShowIOFrame("l1qs-export") end)

        local l1ImBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        l1ImBtn:SetSize(150, 22)
        l1ImBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 160, py - 64)
        l1ImBtn:SetText("Import Lvl1QuickSetup")
        l1ImBtn:SetScript("OnClick", function() ShowIOFrame("l1qs-import") end)
        y = y - 100
    end
    y = y - 6

    -- =========================================================================
    -- PRESETS (rows render from ns.Profiles.Presets -- add entries there)
    -- =========================================================================
    y = Header(c, y, "Presets")
    for _, preset in ipairs((ns.Profiles and ns.Profiles.Presets) or {}) do
        local p, py = SectionParent(c, y)
        local nameFS = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 4)
        nameFS:SetText("|cffffffff" .. preset.name .. "|r  -  " .. preset.desc)
        nameFS:SetWidth(330)
        nameFS:SetJustifyH("LEFT")
        local applyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        applyBtn:SetSize(60, 20)
        applyBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 340, py)
        applyBtn:SetText("Apply")
        local presetName = preset.name
        applyBtn:SetScript("OnClick", function()
            local dlg = StaticPopup_Show("TURBOFACE_PRESET_APPLY", presetName)
            if dlg then dlg.data = presetName end
        end)
        y = y - 30
    end
    y = y - 10

    y = y - 10

    y = Header(c, y, "Reset")
    local rbP, rbY = SectionParent(c, y)
    local resetBtn = CreateFrame("Button", nil, rbP, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", rbP, "TOPLEFT", 0, rbY - 8)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["TURBOFACE_RESET"] = {
            text = "Reset ALL TurboFace settings to defaults?\n\nThis will reload your UI.",
            button1 = "Yes", button2 = "No",
            OnAccept = function() TurboFaceDB = nil ReloadUI() end,
            timeout=0, whileDead=1, hideOnEscape=true,
        }
        StaticPopup_Show("TURBOFACE_RESET")
    end)
    y = y - 44

    FinalizeSections(c, y)
end

local function BuildGlobalTab(c)
    c._tfApply = ApplySettings
    local RefreshDotOptions = RefreshOwner("DotPrediction")
    local RefreshHealOptions = RefreshOwner("HealPrediction")
    local function RefreshMeterOptions()
        if ns.Providers then ns.Providers:Call("combatMeter", "Refresh")
        elseif ns.CombatMeter then ns.CombatMeter:Refresh() end
    end
    local RefreshBadgeOptions = RefreshOwner("DPSBadge")
    local function UsesNativeCombatMeter()
        return not ClientFeatureAvailable("combat.localMeterWindow", true)
    end
    local function RefreshBadgeRuntime()
        RefreshMeterOptions()
        RefreshBadgeOptions()
    end
    local y = -6

    -- =========================================================================
    -- HOTBAR POWER OVERLAY
    -- Cross-surface action-button utility: Global owns its presentation in the
    -- options UI, while Power/PowerCost.lua retains runtime/storage ownership.
    -- =========================================================================
    PDB()
    y = Header(c, y, "Hotbar Power Overlay", "hotbarPower", nil, RefreshPower,
        "TurboFace-native MissingPower features")
    PowerCheckbox(c, y, 0, "Enable power features", "enabled")
    PowerDependentCheckboxColumn(c, y, GRID_COL2_X,
        "Action button overlay", "actionOverlayEnabled",
        "Use custom overlay color", "useCustomOverlayColor")
    PowerDependentCheckboxColumn(c, y, GRID_COL3_X,
        "Show cast counter", "showActionCounter",
        "Use custom counter color", "useCustomCounterColor")
    y = y - 54
    y = PowerDropdown(c, y, 0, W, "Counter Anchor", "textAnchor", {
        {name="Center",value="CENTER"},{name="Top Left",value="TOPLEFT"},{name="Top",value="TOP"},{name="Top Right",value="TOPRIGHT"},
        {name="Right",value="RIGHT"},{name="Bottom Right",value="BOTTOMRIGHT"},{name="Bottom",value="BOTTOM"},{name="Bottom Left",value="BOTTOMLEFT"},{name="Left",value="LEFT"},
    })
    y = PowerSlider(c, y, 0, W, "Overlay Opacity", "overlayAlpha", 0, 1, 0.05, true)
    y = PowerDropdown(c, y, 0, W, "Counter Font", "font", FontOptions())
    y = PowerDropdown(c, y, 0, W, "Counter Text Style", "textStyle", STYLE_OPTS)
    y = PowerSlider(c, y, 0, W, "Counter Font Size", "fontSize", 6, 28, 1, false)
    y = PowerSlider(c, y, 0, W, "Counter Decimals", "decimals", 0, 3, 1, false)
    y = PowerSlider(c, y, 0, W, "Show Counter Below", "displayIfLowerThan", 0, 100, 1, false)
    y = PowerSlider(c, y, 0, W, "Counter X Offset", "textOffsetX", -40, 40, 1, false)
    y = PowerSlider(c, y, 0, W, "Counter Y Offset", "textOffsetY", -40, 40, 1, false)
    y = PowerColorRow(c, y, "Overlay Color", "overlayColor", "Counter Color", "counterColor")
    y = y - 10

    -- =========================================================================
    -- DOT PREDICTION
    -- Lives in Global rather than Nameplates or Unit Frames because one engine
    -- feeds both, and splitting the toggle across two tabs would imply two
    -- independent features.
    -- =========================================================================
    y = Header(c, y, "DoT Prediction", { dbKey = "dotPredictionEnabled" }, nil, RefreshDotOptions,
        "Shades part of health bar with damage-over-time effects. Tick damage is learned from combat log.")

    y = Checkbox(c, y, 0, "Show on nameplates", "dotPredictionNameplates", RefreshDotOptions)
    y = Checkbox(c, y, 0, "Show on target / target-of-target frames", "dotPredictionUnitFrames", RefreshDotOptions)
    y = ColorPicker(c, y, 0, "Region Color", "dotPredictionColor", RefreshDotOptions)
    y = Checkbox(c, y, 0, "Include party members' DoTs", "dotPredictionIncludeParty", RefreshDotOptions)
    y = ColorPicker(c, y, 0, "Region Color (Lethal)", "dotPredictionLethalColor", RefreshDotOptions)
    y = Slider(c, y, 0, W, "Region Opacity", "dotPredictionAlpha", 0.1, 1, 0.05, true, RefreshDotOptions)

    y = y - 10

    -- =========================================================================
    -- HEAL PREDICTION
    -- Direct casts use Blizzard's native incoming-heal API. HoTs deliberately
    -- contribute ONLY their next tick rather than their full remaining duration.
    -- =========================================================================
    y = Header(c, y, "Heal Prediction", { dbKey = "healPredictionEnabled" }, nil, RefreshHealOptions,
        "TurboFace-native HealBarsClassic heal prediction")

    y = CheckboxRow(c, y, "Player frame", "healPredictionPlayer", "Target frame", "healPredictionTarget", RefreshHealOptions)
    y = CheckboxRow(c, y, "Target-of-Target", "healPredictionToT", "Pet frame", "healPredictionPet", RefreshHealOptions)
    y = Checkbox(c, y, 0, "Party frames", "healPredictionParty", RefreshHealOptions)
    y = Checkbox(c, y, 0, "Include next heal-over-time tick", "healPredictionHots", RefreshHealOptions)
    y = CheckboxRow(c, y, "Separate color for my heals", "healPredictionSeparateOwn", "Separate HoT color", "healPredictionSeparateHots", RefreshHealOptions)
    y = Checkbox(c, y, 0, "Tint other players' heals by caster class", "healPredictionCasterTint", RefreshHealOptions)

    y = ColorRow(c, y, "Direct Heal", "healPredictionColor", "My Direct Heal", "healPredictionOwnColor", RefreshHealOptions)
    y = ColorRow(c, y, "HoT Next Tick", "healPredictionHotColor", "My HoT Tick", "healPredictionOwnHotColor", RefreshHealOptions)
    y = Slider(c, y, 0, W, "Prediction Opacity", "healPredictionAlpha", 0.1, 1, 0.05, true, RefreshHealOptions)
    y = Slider(c, y, 0, W, "Visible Overheal Extension", "healPredictionOverheal", 0, 1, 0.05, true, RefreshHealOptions)
    y = Slider(c, y, 0, W, "Maximum Visible Segments", "healPredictionMaxSegments", 1, 10, 1, false, RefreshHealOptions)
    y = Slider(c, y, 0, W, "Ignore Heals Smaller Than % HP", "healPredictionMinPercent", 0, 10, 0.5, false, RefreshHealOptions)

    y = y - 10

    -- =========================================================================
    -- COMBAT METER
    -- Forever/Mainline already ships Blizzard's meter. Keep TurboFace's legacy
    -- window only on clients without C_DamageMeter; the independent badge below
    -- consumes Blizzard's public aggregated data when available.
    -- =========================================================================
    if not UsesNativeCombatMeter() then
        y = Header(c, y, "Combat Meter", { dbKey = "combatMeterEnabled" }, nil, RefreshMeterOptions,
            "Lightweight local damage/healing meter for leveling and party/dungeon play. Tracks current and overall damage/healing")

        y = Dropdown(c, y, 0, W, "Font", "combatMeterFont", FontOptions(), RefreshMeterOptions)
        y = Dropdown(c, y, 0, W, "Text Style", "combatMeterTextStyle", STYLE_OPTS, RefreshMeterOptions)
        y = Slider(c, y, 0, W, "Meter Width", "combatMeterWidth", 160, 380, 5, false, RefreshMeterOptions)
        y = Slider(c, y, 0, W, "Bar Opacity", "combatMeterBarAlpha", 0.1, 0.9, 0.05, true, RefreshMeterOptions)
        y = Slider(c, y, 0, W, "Merge Nearby Pulls", "combatMeterMergeWindow", 0.25, 4, 0.25, false, RefreshMeterOptions)
        y = y - 10
    end

    -- Independent Blizzard-PlayerFrame combat-rate badge.  The historical
    -- unitframes.* storage paths are retained for profile compatibility, but
    -- neither this section nor its runtime inherits the Unit Frames module gate.
    y = Header(c, y, "Player DPS / HPS Badge", { dbKey = "unitframes.showPlayerDPS" }, nil, RefreshBadgeRuntime,
        UsesNativeCombatMeter()
            and "Shows Current/Overall DPS/HPS from Blizzard's built-in Damage Meter on the Player UnitFrame"
            or "Shows your selected Current/Overall DPS/HPS on Player UnitFrame")
    y = Slider(c, y, 0, W, "Badge Font Size", "playerDPSBadgeFontSize", 6, 16, 1, false, RefreshBadgeOptions)
    y = ColorRow(c, y, "DPS Text Color", "unitframes.playerDPSColor", "HPS Text Color", "unitframes.playerHPSColor", RefreshBadgeOptions)
    y = y - 10

    y = Header(c, y, "Auras", "auras", nil, RefreshAuraOptions,
        "TurboFace Aura presentation for Nameplates, Player, Target, ToT, Pet, and Party UnitFrames")

    do
        local p, py = SectionParent(c, y)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 2)
        lbl:SetText("TARGET / TARGET-OF-TARGET LAYOUT")
        lbl:SetTextColor(0, 0.8, 1)
        y = y - 22
    end
    y = Slider(c, y, 0, W, "Target Icons Per Row", "movers.aura.targetPerRow", 1, 16, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Horizontal Spacing", "movers.aura.spacingX", 0, 24, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Vertical Spacing", "movers.aura.spacingY", 0, 32, 1, false, RefreshAuraOptions)
    local auraGrowthOptions = {
        { name = "Left then Down",  value = "LEFT_DOWN"  },
        { name = "Right then Down", value = "RIGHT_DOWN" },
        { name = "Left then Up",    value = "LEFT_UP"    },
        { name = "Right then Up",   value = "RIGHT_UP"   },
    }
    y = Dropdown(c, y, 0, W, "Target Buff Growth", "movers.aura.targetBuffGrowth", auraGrowthOptions, RefreshAuraOptions)
    y = Dropdown(c, y, 0, W, "Target Debuff Growth", "movers.aura.targetDebuffGrowth", auraGrowthOptions, RefreshAuraOptions)
    y = Dropdown(c, y, 0, W, "ToT Debuff Growth", "movers.aura.totDebuffGrowth", auraGrowthOptions, RefreshAuraOptions)
    y = y - 10

    do
        local p, py = SectionParent(c, y)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 2)
        lbl:SetText("NAMEPLATE AURAS & DEBUFFS")
        lbl:SetTextColor(0, 0.8, 1)
        y = y - 22
    end
    y = CheckboxRow(c, y, "Show Debuffs",         "auras.showDebuffs",       "Show Buffs",         "auras.showBuffs")
    y = Slider  (c, y, 0, W, "Max Debuffs",       "auras.maxDebuffs",        1, 12, 1, false)
    y = Slider  (c, y, 0, W, "Debuff Icon Size",  "auras.debuffIconWidth",   10, 40, 1, false)
    y = Slider  (c, y, 0, W, "Debuff Y Offset (+Up / -Down)", "auras.debuffYOffset", -50, 50, 1, false)
    y = Slider  (c, y, 0, W, "Max Buffs",         "auras.maxBuffs",          1, 8,  1, false)
    y = Slider  (c, y, 0, W, "Buff Icon Size",    "auras.buffIconWidth",     10, 40, 1, false)
    y = Slider  (c, y, 0, W, "Debuff Text Size",  "auras.debuffFontSize",    6, 20, 1, false)
    y = Slider  (c, y, 0, W, "Buff Text Size",    "auras.buffFontSize",      6, 20, 1, false)
    y = Dropdown(c, y, 0, W, "Debuff Border",     "auras.borderStyle",
        {{name="Blizzard (rounded)",value="BLIZZARD"},{name="Pixel (square)",value="PIXEL"}})
    y = Dropdown(c, y, 0, W, "Buff Filter",       "auras.buffFilterMode",
        {{name="Only Dispellable",value="ONLY_DISPELLABLE"},{name="Whitelist + Dispel",value="WHITELIST_DISPELLABLE"},
         {name="Whitelist Only",value="WHITELIST_ONLY"},{name="All",value="ALL"},{name="Disabled",value="DISABLED"}})
    y = y - 6

    -- Player/target buff & debuff styling (AuraStyle) -------------------------
    do
        local p, py = SectionParent(c, y)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 2)
        lbl:SetText("BUFFS & DEBUFFS (SWIPE + TIMER)")
        lbl:SetTextColor(0, 0.8, 1)
        y = y - 22
    end
    y = Checkbox(c, y, 0, "Enable aura styling (swipe + timer text)", "auraEnabled")
    y = CheckboxRow(c, y, "Show cooldown swipe", "auraShowSwipe", "Show timer text", "auraShowTimer")
    y = y - 4
    y = Dropdown(c, y, 0, W, "Aura Font", "auras.font", FontOptions(), RefreshAuraOptions)
    y = Dropdown(c, y, 0, W, "Aura Text Style", "auras.textStyle", STYLE_OPTS, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Timer Font Size", "auraTimerSize", 8, 24, 1, false, RefreshAuraOptions)
    y = y - 4
    y = Slider(c, y, 0, W, "Target Buff Size",   "auraTargetBuffScale",   0.5, 2.0, 0.05, true)
    y = Slider(c, y, 0, W, "Target Debuff Size", "auraTargetDebuffScale", 0.5, 2.0, 0.05, true)
    y = y - 10

    do
        local p, py = SectionParent(c, y)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 2)
        lbl:SetText("TARGET-OF-TARGET DEBUFFS")
        lbl:SetTextColor(0, 0.8, 1)
        y = y - 22
    end
    y = ModuleGateCheckbox(c, y, 0, "Style Target-of-Target Debuffs", "auras", "tot", RefreshAuraOptions)
    y = Slider(c, y, 0, W, "ToT Debuff Size", "auras.totDebuffScale", 0.5, 2.0, 0.05, true, RefreshAuraOptions)
    y = y - 6

    do
        local p, py = SectionParent(c, y)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 2)
        lbl:SetText("PARTY & PET AURAS")
        lbl:SetTextColor(0, 0.8, 1)
        y = y - 22
    end
    y = ModuleGateCheckboxRow(c, y,
        "Style Party Auras", "auras", "party",
        "Style Pet Auras", "auras", "pet", RefreshAuraOptions)
    y = CheckboxRow(c, y, "Always Show Helpful Buffs", "auras.partyBuffsEnabled",
        "Party Class-Only Buffs", "auras.partyClassRemindersEnabled", RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Aura Icon Size", "auras.partyBuffIconSize", 10, 32, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Party Class Buff Icon Size", "auras.partyClassBuffIconSize", 20, 48, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Class Buff Warn Before Expiry", "auras.partyClassBuffWarnSeconds", 0, 120, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Max Helpful Buffs", "auras.partyBuffMax", 1, 16, 1, false, RefreshAuraOptions)
    y = Slider(c, y, 0, W, "Auras Per Row", "auras.partyBuffsPerRow", 1, 8, 1, false, RefreshAuraOptions)
    y = y - 6


    -- =========================================================================
    -- COMBAT TIMERS
    -- Swing/cast runtime is independent of Unit Frames. The Unit Frames tab
    -- only chooses whether these standalone-capable stacks bake into its art.
    -- =========================================================================
    local timerTextures = ns.GetLSMTextures and ns.GetLSMTextures() or ns.Textures
    y = Header(c, y, "Swing Timers", "swingTimers", nil, nil,
        "Main-hand, off-hand, ranged, and target attack timers")
    Slider(c, y, 0, W, "Standalone Width", "swingTimersStandaloneWidth", 80, 300, 1, false, RefreshStandaloneAttackGeometry)
    Slider(c, y, GRID_COL2_X, W, "Standalone Height", "swingTimersStandaloneHeight", 8, 30, 1, false, RefreshStandaloneAttackGeometry)
    y = y - 46
    y = Dropdown(c, y, 0, W, "Font", "swingTimersFont", FontOptions(), RefreshOwner("ST"))
    y = Dropdown(c, y, 0, W, "Text Style", "swingTimersTextStyle", STYLE_OPTS, RefreshOwner("ST"))
    y = Dropdown(c, y, 0, W, "Attack Texture", "unitframes.attackTexture", timerTextures)
    y = y - 10

    y = Header(c, y, "Cast Bars", "castBars", nil, nil,
        "Player and Target Cast Bars")
    Slider(c, y, 0, W, "Standalone Width", "castBarsStandaloneWidth", 80, 300, 1, false, RefreshOwner("Castbars"))
    Slider(c, y, GRID_COL2_X, W, "Standalone Height", "castBarsStandaloneHeight", 8, 30, 1, false, RefreshOwner("Castbars"))
    y = y - 46
    y = Dropdown(c, y, 0, W, "Font", "castBarsFont", FontOptions(), RefreshOwner("Castbars"))
    y = Dropdown(c, y, 0, W, "Text Style", "castBarsTextStyle", STYLE_OPTS, RefreshOwner("Castbars"))
    y = Dropdown(c, y, 0, W, "Cast Texture", "unitframes.castTexture", timerTextures)
    y = Checkbox(c, y, 0, "Hide Blizzard Player Castbar", "unitframes.hideBlizzardPlayerCastbar")
    y = y - 10

    FinalizeSections(c, y)
end

local function BuildNameplatesTab(c)
    c._tfApply = RefreshNameplateOptions
    local y = -6

    y = MasterToggle(c, y, "TurboFace Nameplate Enhancements", "nameplates")
    y = FlatMasterContent(c, y)

    Slider(c, y, 0, W, "Overlap Vertical", "bubbleNameplates.overlapV", 0.5, 2.0, 0.05, false)
    Slider(c, y, GRID_COL2_X, W, "Overlap Horizontal", "bubbleNameplates.overlapH", 0.5, 2.0, 0.05, false)
    Slider(c, y, GRID_COL3_X, W, "Selected Scale", "bubbleNameplates.selectedScale", 0.5, 2.0, 0.05, false)
    y = y - 46
    Slider(c, y, 0, W, "Selected Alpha", "bubbleNameplates.selectedAlpha", 0, 1, 0.05, true)
    Slider(c, y, GRID_COL2_X, W, "Not Selected Alpha", "bubbleNameplates.notSelectedAlpha", 0, 1, 0.05, true)
    y = y - 46

    Checkbox(c, y, 0, "Show Combo Points", "showComboPoints")
    Checkbox(c, y, GRID_COL2_X, "Move Rarity Icon Right", "bubbleNameplates.rarityIconRight")
    if ClientFeatureAvailable("nameplates.nameTextShadow", true) then
        Checkbox(c, y, GRID_COL3_X, "Name Text Shadow", "bubbleNameplates.nameTextShadow")
    end
    y = y - 28
    Checkbox(c, y, 0, "Friendly NPC: Name + Title", "bubbleNameplates.friendlyNPCNameTitleOnly")
    Checkbox(c, y, GRID_COL2_X, "Friendly Player: Damaged Only", "bubbleNameplates.friendlyPlayerDamagedOnly")
    Checkbox(c, y, GRID_COL3_X, "Friendly NPC: Damaged Only", "bubbleNameplates.friendlyNPCDamagedOnly")
    y = y - 28
    local centerHealthLabel = ClientOptionPolicy("centerHealthLabel", "Center Blizzard Health Text")
    DependentCheckboxColumn(c, y, 0,
        centerHealthLabel, "bubbleNameplates.centerHealthText",
        "Center Across Entire Nameplate", "bubbleNameplates.centerHealthTextOnNameplate")
    Checkbox(c, y, GRID_COL2_X, "Show Friendly NPC Job Icon", "bubbleNameplates.jobIcon")
    Checkbox(c, y, GRID_COL3_X, "Show Nameplate Swing Timer", "bubbleNameplates.swingTimer")
    y = y - 54

    Checkbox(c, y, 0, "Overlap Power Bar", "bubbleNameplates.powerBarOverlap")
    Slider(c, y, GRID_COL2_X, W, "Power Bar Height", "bubbleNameplates.powerBarHeightPct", 0.10, 0.40, 0.01, true)
    y = y - 46

    Checkbox(c, y, 0, "Show Threat Number", "bubbleNameplates.threatNumber")
    Slider(c, y, GRID_COL2_X, W, "Threat Text Font Size", "bubbleNameplates.threatTextFontSize", 6, 16, 1, false)
    y = y - 46

    Checkbox(c, y, 0, "Mute Aggro Sounds", "bubbleNameplates.muteAggroSounds")
    Slider(c, y, GRID_COL2_X, W, "Gain Sound Volume", "bubbleNameplates.gainVolume", 0, 1, 0.05, true)
    Slider(c, y, GRID_COL3_X, W, "Loss Sound Volume", "bubbleNameplates.lossVolume", 0, 1, 0.05, true)
    y = y - 46

    FinalizeSections(c, y)
end

local function BuildUnitFramesTab(c)
    c._tfApply = RefreshUnitFrameOptions
    local y = -6
    -- Player Bar Tick Markers are independent of TurboFace Unit Frames and are
    -- intentionally presented before the Unit Frames master so stock-Blizzard
    -- frame users can reach them without enabling the restyle subsystem.
    y = IndependentHeader(c, y, "Player Bar Tick Markers", "playerTicks", nil, nil,
        "Shows mana, energy, rage decay, health regeneration, and five-second-rule timing markers on the Player health and power bars.")
    PowerDependentCheckboxColumn(c, y, 0,
        "Mana tick marker", "manaTick", "Mana marker border", "manaTickBackground")
    PowerDependentCheckboxColumn(c, y, GRID_COL2_X,
        "Mana 5-second rule", "fiveSecondRule", "5SR marker border", "fiveSecondRuleBackground")
    PowerDependentCheckboxColumn(c, y, GRID_COL3_X,
        "Energy tick marker", "energyTick", "Energy marker border", "energyTickBackground")
    y = y - 54
    PowerDependentCheckboxColumn(c, y, 0,
        "Health regen marker", "healthRegen", "Health marker border", "healthRegenBackground")
    PowerDependentCheckboxColumn(c, y, GRID_COL2_X,
        "Rage decay marker", "rageDecay", "Rage marker border", "rageDecayBackground")
    y = y - 54
    y = PowerSlider(c, y, 0, W, "Marker Width", "tickWidth", 1, 6, 1, false)
    y = PowerSlider(c, y, 0, W, "Border Width", "tickBorderWidth", 1, 8, 1, false)
    y = PowerColorRow(c, y, "Mana Tick", "tickColor", "Mana Border", "tickBorderColor")
    y = PowerColorRow(c, y, "5-Second Rule", "fiveSecondRuleColor", "5SR Border", "fiveSecondRuleBorderColor")
    y = PowerColorRow(c, y, "Energy Tick", "energyTickColor", "Energy Border", "energyTickBorderColor")
    y = PowerColorRow(c, y, "Rage Decay", "rageDecayColor", "Rage Border", "rageDecayBorderColor")
    y = PowerColorRow(c, y, "Health Regen", "healthRegenColor", "Health Border", "healthRegenBorderColor")
    PowerCheckbox(c, y, 0, "Show HP tick amount (+X)", "healthTickAmount")
    PowerCheckbox(c, y, GRID_COL2_X, "Show power tick amount (+X)", "powerTickAmount")
    y = y - 28
    y = PowerDropdown(c, y, 0, W, "Tick Amount Font", "tickFont", FontOptions())
    y = PowerDropdown(c, y, 0, W, "Tick Amount Text Style", "tickTextStyle", STYLE_OPTS)
    y = PowerSlider(c, y, 0, W, "Tick Amount Text Size", "tickAmountSize", 8, 40, 1, false)
    y = PowerSlider(c, y, 0, W, "Tick Amount Offset X", "tickAmountOffsetX", -100, 100, 1, false)
    y = PowerSlider(c, y, 0, W, "Tick Amount Offset Y", "tickAmountOffsetY", -100, 100, 1, false)
    y = y - 8


    y = MasterToggle(c, y, "TurboFace Unit Frames", "unitframes",
        "Restyles player, target, ToT, pet, and party frames with TurboFace's fixed Classic-style artwork")

    y = Header(c, y, "General")
    local TEX = ns.GetLSMTextures and ns.GetLSMTextures() or ns.Textures
    y = Dropdown(c, y, 0, W, "Health Texture",    "unitframes.healthTexture", TEX)
    y = Dropdown(c, y, 0, W, "Mana Texture",      "unitframes.manaTexture",   TEX)
    y = Checkbox(c, y, 0, "Bake Swing / Cast Timers into TurboFace frames", "unitframes.embedCombatTimers", ApplySettings)
    -- NOTE: the bar border (Blizzard Tooltip, size 9; ToT size 4) and bar
    -- spacing (2) are LOCKED in Core/Config.lua/UnitFrames/UnitFrames.lua as the addon's
    -- visual identity -- no options here.
    y = Dropdown(c, y, 0, W, "Name Font", "unitframes.nameFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Name Text Style", "unitframes.nameTextStyle", STYLE_OPTS)
    y = Slider  (c, y, 0, W, "Player / Target Name Text Size", "unitframes.nameFontSize", 6, 18, 1, false)
    y = Dropdown(c, y, 0, W, "Bar Font", "unitframes.barFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Bar Text Style", "unitframes.barTextStyle", STYLE_OPTS)
    y = Slider  (c, y, 0, W, "Player / Target Bar Text Size", "unitframes.barFontSize", 6, 16, 1, false)
    y = ColorRow(c, y, "Bar Border Color", "barBorderColor", "", "", function()
        ns:UpdateSharedColors()
        ns:ReapplySharedBorders()
        if ns.UpdateDBCache then ns:UpdateDBCache() end
        if ns.UpdateAllPlates then ns:UpdateAllPlates() end
    end)
    -- These policies apply to every non-player health bar (Target, Pet, and
    -- Party), so they remain General rather than implying Target-only scope.
    y = CheckboxRow(c, y, "Class Colored Health", "unitframes.classColored",  "Color by HP %",   "unitframes.colorBasedOnCurrentHealth")
    y = ColorRow(c, y, "Friendly Health", "unitframes.friendlyColor", "Enemy Health", "unitframes.enemyColor")
    y = y - 6

    local VALUE_FORMATS = {
        {name="Percent",value="percent"},
        {name="Percent Current (Blizzard)",value="percent-current-blizzard"},
        {name="Current",value="current"},
        {name="Current / Max",value="current-max"},
        {name="Current / Max (Percent)",value="current-max-pct"},
        {name="Current (Percent)",value="current-pct"},
        {name="None",value="none"},
    }

    y = Header(c, y, "Shield Bars", { dbKey = "unitframes.nanShieldEnabled" }, nil, RefreshUnitFrameOptions,
        "TurboFace absorb/shield bar for Player shields and direct-cast Priest Party Power Word: Shield")
    y = CheckboxRow(c, y, "Show Absorb Text", "unitframes.nanShieldShowText",
        "Per-School Amounts", "unitframes.nanShieldPerSection")
    y = Dropdown(c, y, 0, W, "Text Font", "unitframes.nanShieldFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "unitframes.nanShieldTextStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Text Size", "unitframes.nanShieldFontSize", 4, 20, 1, false)
    y = y - 6

    y = Header(c, y, "Player — Fixed Classic Artwork", "unitframes", "player")
    y = Dropdown(c, y, 0, W, "Health Text", "unitframes.playerHealthFormat", VALUE_FORMATS)
    y = Dropdown(c, y, 0, W, "Power Text",  "unitframes.playerPowerFormat",  VALUE_FORMATS)
    y = ColorRow(c, y, "Health Color", "unitframes.playerHealthColor", "", "")
    y = Slider  (c, y, 0, W, "Scale",             "unitframes.playerScale",   0.5, 2, 0.05, false)
    y = Checkbox(c, y, 0, "Show Hit Indicator", "unitframes.showHitIndicator")
    y = y - 6

    y = Header(c, y, "Target — Fixed Classic Artwork", "unitframes", "target")
    y = Dropdown(c, y, 0, W, "Health Text", "unitframes.targetHealthFormat", VALUE_FORMATS)
    y = Dropdown(c, y, 0, W, "Power Text",  "unitframes.targetPowerFormat",  VALUE_FORMATS)
    y = ColorRow(c, y, "Tagged Mob Grey", "taggedIndicatorColor", "", "", function()
        ns:UpdateSharedColors()
        ns:ReapplySharedBorders()
        if ns.UpdateDBCache then ns:UpdateDBCache() end
        if ns.UpdateAllPlates then ns:UpdateAllPlates() end
    end)
    y = Slider  (c, y, 0, W, "Scale",             "unitframes.targetScale",   0.5, 2, 0.05, false)
    y = Checkbox(c, y, 0, "Show Name",            "unitframes.showTargetName")
    y = CheckboxRow(c, y, "Reverse HP Bar",       "unitframes.reverseTargetHP","Show Kill XP", "unitframes.showTargetXP")
    y = Checkbox(c, y, 0, "XP per HP",          "unitframes.targetXPPerHP")
    y = ColorRow(c, y, "XP Text Color",           "unitframes.targetXPColor", "", "")
    y = y - 6

    y = Header(c, y, "Target of Target — Fixed Classic Artwork", "unitframes", "tot")
    y = Dropdown(c, y, 0, W, "Health Text", "unitframes.totHealthFormat", VALUE_FORMATS)
    y = Dropdown(c, y, 0, W, "Power Text",  "unitframes.totPowerFormat",  VALUE_FORMATS)
    y = Checkbox(c, y, 0, "Show Target of Target", "unitframes.showToT")
    y = Checkbox(c, y, 0, "Name Above Bars", "unitframes.totNameAboveBars")
    y = Slider  (c, y, 0, W, "ToT Bar Text Size", "unitframes.totBarFontSize", 5,   16,  1,    false)
    y = Slider  (c, y, 0, W, "ToT Name Text Size", "unitframes.totNameFontSize", 5,   20,  1,    false)
    y = y - 6

    y = Header(c, y, "Pet", "unitframes", "pet")
    y = Dropdown(c, y, 0, W, "Health Text", "unitframes.petHealthFormat", VALUE_FORMATS)
    y = Dropdown(c, y, 0, W, "Power Text",  "unitframes.petPowerFormat",  VALUE_FORMATS)
    y = Checkbox(c, y, 0, "Name Above Bars", "unitframes.petNameAboveBars")
    y = Slider  (c, y, 0, W, "Pet Name Text Size", "unitframes.petNameFontSize", 5, 18, 1, false)
    y = Slider  (c, y, 0, W, "Pet Bar Text Size", "unitframes.petBarFontSize", 5, 16, 1, false)
    y = y - 6

    y = Header(c, y, "Party", "unitframes", "party")
    y = Dropdown(c, y, 0, W, "Health Text", "unitframes.partyHealthFormat", VALUE_FORMATS)
    y = Dropdown(c, y, 0, W, "Power Text",  "unitframes.partyPowerFormat",  VALUE_FORMATS)
    y = Checkbox(c, y, 0, "Show Names", "unitframes.showPartyNames")
    y = Slider  (c, y, 0, W, "Scale",             "unitframes.partyScale",          0.5, 2,   0.05, false)
    y = Slider  (c, y, 0, W, "Party Name Text Size", "unitframes.partyNameFontSize", 5, 18, 1, false)
    y = Slider  (c, y, 0, W, "Party Bar Text Size", "unitframes.partyBarFontSize", 5, 16, 1, false)
    y = ColorRow(c, y, "Name Color",              "unitframes.partyNameColor", "", "")
    y = y - 6

    FinalizeSections(c, y)
end

local function BuildExperienceSection(c, y)
    local XP_DEFAULTS = (ns.defaults and ns.defaults.experienceBar) or {}
    local function XDB()
        if type(TurboFaceDB.experienceBar) ~= "table" then TurboFaceDB.experienceBar = {} end
        MergeDefaults(TurboFaceDB.experienceBar, XP_DEFAULTS)
        return TurboFaceDB.experienceBar
    end
    local function RefreshXP()
        if ns.XP then ns.XP:Refresh() end
        if ns.Movers then ns.Movers:Refresh() end
    end
    local function XPCheckbox(parent, y, x, label, field)
        parent, y = SectionParent(parent, y)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
        cb:SetChecked(XDB()[field] == true)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(label)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        cb:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            XDB()[field] = self:GetChecked() == true or self:GetChecked() == 1
            RefreshXP()
        end)
        return y - 26
    end
    local function XPCheckboxRow(parent, y, label1, field1, label2, field2)
        XPCheckbox(parent, y, 0, label1, field1)
        if label2 and field2 then XPCheckbox(parent, y, GRID_COL2_X, label2, field2) end
        return y - 28
    end
    local function XPSlider(parent, y, x, w, label, field, minVal, maxVal, step, isPct)
        parent, y = SectionParent(parent, y)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lbl:SetText(label .. ":")
        lbl:SetWidth(w - SLIDER_VALUE_W - 6); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        sl:SetWidth(w); sl:SetHeight(14)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
        sl:SetMinMaxValues(minVal, maxVal)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        sl:SetValue(XDB()[field] or minVal)
        if sl.Low then sl.Low:SetText("") end
        if sl.High then sl.High:SetText("") end
        if sl.Text then sl.Text:SetText("") end
        local valueBox, RefreshValue = SliderValueBox(parent, x, y, w, sl, minVal, maxVal, step, isPct)
        sl:SetScript("OnValueChanged", function(_, v)
            if step >= 1 then v = math.floor(v + 0.5) end
            XDB()[field] = v
            RefreshValue(v)
            RefreshXP()
        end)
        return y - 44
    end

    local function XPDropdown(parent, y, x, w, label, field, options)
        parent, y = SectionParent(parent, y)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lbl:SetText(label .. ":")
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local btn = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
        btn:SetSize(w, 20)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
        Backdrop(btn, 0.1, 0.1, 0.1, 0.9, 0.3, 0.3, 0.3)
        local cur = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cur:SetPoint("LEFT", btn, "LEFT", 6, 0)
        cur:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
        cur:SetJustifyH("LEFT"); cur:SetTextColor(1, 1, 1)
        local arr = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arr:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        arr:SetText("v"); arr:SetTextColor(0.6, 0.6, 0.6)
        local function UpdateCur()
            local val = XDB()[field]
            for _, o in ipairs(options) do if o.value == val then cur:SetText(o.name); return end end
            cur:SetText(options[1] and options[1].name or "")
        end
        UpdateCur()
        local popup = RegisterDropdownPopup(CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate"))
        popup:SetFrameStrata("TOOLTIP"); popup:SetWidth(w); popup:Hide()
        Backdrop(popup, 0.08, 0.08, 0.08, 0.98, 0.25, 0.25, 0.25)
        popup:SetHeight(#options * 18 + 4)
        for i, opt in ipairs(options) do
            local item = CreateFrame("Button", nil, popup)
            item:SetHeight(18)
            item:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i - 1) * 18 - 2)
            item:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i - 1) * 18 - 2)
            local itxt = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itxt:SetPoint("LEFT", item, "LEFT", 6, 0)
            itxt:SetText(opt.name); itxt:SetTextColor(0.85, 0.85, 0.85)
            item:SetScript("OnClick", function()
                ns:PlayUISound("option")
                XDB()[field] = opt.value
                UpdateCur()
                popup:Hide()
                RefreshXP()
            end)
        end
        btn:EnableMouse(true)
        btn:SetScript("OnMouseDown", function()
            ToggleDropdownPopup(popup, btn, function()
                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
                popup:SetFrameLevel(btn:GetFrameLevel() + 20)
            end)
        end)
        return y - 44
    end
    local function XPColor(parent, y, x, label, field)
        parent, y = SectionParent(parent, y)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lbl:SetText(label .. ":"); lbl:SetTextColor(0.85, 0.85, 0.85)
        local sw = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
        sw:SetSize(44, 18)
        sw:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
        if sw.SetBackdrop then
            sw:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
            sw:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
        local function Refresh()
            local c = XDB()[field]
            local r, g, b = ns:Color(c, 1, 1, 1)
            if sw.SetBackdropColor then sw:SetBackdropColor(r, g, b, 1) end
        end
        Refresh()
        sw:SetScript("OnClick", function()
            ns:PlayUISound("option")
            local c = XDB()[field] or {r=1,g=1,b=1}
            local r0, g0, b0 = ns:Color(c, 1, 1, 1)
            ColorPickerFrame.swatchFunc = function()
                local r,g,b = ColorPickerFrame:GetColorRGB()
                XDB()[field] = {r=r,g=g,b=b}
                Refresh(); RefreshXP()
            end
            ColorPickerFrame.cancelFunc = function(prev)
                XDB()[field] = {r=prev.r,g=prev.g,b=prev.b}
                Refresh(); RefreshXP()
            end
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.opacity = nil
            ColorPickerFrame:SetColorRGB(r0, g0, b0)
            ColorPickerFrame.previousValues = {r=r0,g=g0,b=b0}
            ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end)
        return y - 44
    end
    local function XPColorRow(parent, y, label1, field1, label2, field2)
        XPColor(parent, y, 0, label1, field1)
        if label2 and field2 then XPColor(parent, y, GRID_COL2_X, label2, field2) end
        return y - 46
    end

    XDB()
    y = Header(c, y, "Luxthos-like XP Bar", { dbKey = "experienceBar.enabled" }, nil, RefreshXP,
        "Luxthos-like XP Bar showing current XP, current quest XP, Rested XP, XP/hr, time-to-level.")
    y = XPCheckbox(c, y, 0, "Hide Blizzard XP bar", "hideBlizzardXPBar")
    y = XPCheckboxRow(c, y, "Show at max level", "showAtMaxLevel", "Reset session on reload", "resetSessionOnReload")
    y = XPCheckboxRow(c, y, "Show level-in / XP-hour text", "showXPPerHourText", "Show complete/rested % text", "showQuestRestedText")
    y = XPCheckboxRow(c, y, "Show level time", "showLevelTimeText", "Show session time", "showSessionTimeText")
    y = XPCheckboxRow(c, y, "Text block above bar", "textBlockAbove", "Show incomplete quest overlay", "showIncompleteQuestBar")
    y = XPCheckboxRow(c, y, "Show inside player level", "showInsideLevelText", "Show inside level percent", "showInsidePercentText")
    y = y - 6

    y = y - 6
    y = XPDropdown(c, y, 0, W, "Bar Texture", "texture", ns.GetLSMTextures and ns.GetLSMTextures() or ns.Textures)
    y = XPSlider(c, y, 0, W, "Width", "width", 120, 800, 1, false)
    y = XPSlider(c, y, 0, W, "Bar Height", "height", 6, 36, 1, false)
    y = XPSlider(c, y, 0, W, "Scale", "scale", 0.5, 2.5, 0.05, true)
    y = XPDropdown(c, y, 0, W, "Font", "font", FontOptions())
    y = XPDropdown(c, y, 0, W, "Text Style", "textStyle", STYLE_OPTS)
    y = XPSlider(c, y, 0, W, "Font Size", "fontSize", 6, 18, 1, false)
    y = y - 6

    y = y - 6
    y = XPColorRow(c, y, "Current XP", "colorXP", "Complete Quest", "colorComplete")
    y = XPColorRow(c, y, "Incomplete Quest", "colorIncomplete", "Rested XP", "colorRested")
    y = y - 8

    local infoP, infoY = SectionParent(c, y)
    local info = infoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", infoP, "TOPLEFT", 0, infoY)
    info:SetWidth(410)
    info:SetJustifyH("LEFT")
    info:SetText("|cffffd100Requires TurboFace Movers|r")
    info:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24
    return y
end

local function BuildLootSection(c, y)
    local LOOT_DEFAULTS = (ns.defaults and ns.defaults.lootFrame) or {}
    local function LDB()
        if type(TurboFaceDB.lootFrame) ~= "table" then TurboFaceDB.lootFrame = {} end
        MergeDefaults(TurboFaceDB.lootFrame, LOOT_DEFAULTS)
        return TurboFaceDB.lootFrame
    end
    local function RefreshLoot()
        if ns.Loot then ns.Loot:Refresh() end
        if ns.Movers then ns.Movers:Refresh() end
    end
    local function LootCheckbox(parent, y, x, label, field)
        parent, y = SectionParent(parent, y)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
        cb:SetChecked(LDB()[field] == true)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(label)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        cb:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            LDB()[field] = (self:GetChecked() == 1 or self:GetChecked() == true)
            RefreshLoot()
        end)
        return y - 26
    end
    local function LootCheckboxRow(parent, y, label1, field1, label2, field2)
        LootCheckbox(parent, y, 0, label1, field1)
        if label2 and field2 then LootCheckbox(parent, y, GRID_COL2_X, label2, field2) end
        return y - 28
    end
    local function LootSlider(parent, y, x, w, label, field, minVal, maxVal, step, isPct)
        parent, y = SectionParent(parent, y)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lbl:SetText(label .. ":")
        lbl:SetWidth(w - SLIDER_VALUE_W - 6); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        sl:SetWidth(w); sl:SetHeight(14)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
        sl:SetMinMaxValues(minVal, maxVal)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        sl:SetValue(LDB()[field] or minVal)
        if sl.Low then sl.Low:SetText("") end
        if sl.High then sl.High:SetText("") end
        if sl.Text then sl.Text:SetText("") end
        local valueBox, RefreshValue = SliderValueBox(parent, x, y, w, sl, minVal, maxVal, step, isPct)
        sl:SetScript("OnValueChanged", function(_, v)
            v = QuantizeSliderValue(v, minVal, maxVal, step) or v
            LDB()[field] = v
            RefreshValue(v)
            RefreshLoot()
        end)
        return y - 44
    end

    local function Button(parent, y, x, w, label, fn)
        parent, y = SectionParent(parent, y)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 6)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end

    LDB()
    y = Header(c, y, "Loot Frame", { dbKey = "lootFrame.enabled" }, nil, RefreshLoot,
        "Loot notifications for items, money, and vendor sell values")
    y = LootCheckboxRow(c, y, "Show money looted", "showMoney", "Show vendor value", "showVendorValue")
    y = LootCheckboxRow(c, y, "Combine duplicate items", "combineDuplicates", "Show stack count", "showStackCount")
    Button(c, y, 0, 120, "Test Loot", function() if ns.Loot then ns.Loot:Test() end end)
    Button(c, y, 130, 120, "Clear Loot", function() if ns.Loot then ns.Loot:Clear() end end)
    y = y - 42

    y = y - 6
    LootSlider(c, y, 0, W, "Width", "width", 120, 600, 1, false)
    LootSlider(c, y, GRID_COL2_X, W, "Row Height", "rowHeight", 18, 80, 1, false)
    LootSlider(c, y, GRID_COL3_X, W, "Spacing", "spacing", 0, 24, 1, false)
    y = y - 44

    LootSlider(c, y, 0, W, "Scale", "scale", 0.5, 2.5, 0.05, true)
    LootSlider(c, y, GRID_COL2_X, W, "Font Size", "fontSize", 6, 24, 1, false)
    LootSlider(c, y, GRID_COL3_X, W, "Background Alpha", "backgroundAlpha", 0, 1, 0.05, true)
    y = y - 44

    LootSlider(c, y, 0, W, "Visible Duration", "duration", 1, 30, 1, false)
    LootSlider(c, y, GRID_COL2_X, W, "Max Visible Items", "maxItems", 1, 12, 1, false)
    y = y - 44

    y = Dropdown(c, y, 0, W, "Font", "lootFrame.font", FontOptions(), RefreshLoot)
    y = Dropdown(c, y, 0, W, "Text Style", "lootFrame.textStyle", STYLE_OPTS, RefreshLoot)
    y = y - 6
    y = y - 8

    local infoP, infoY = SectionParent(c, y)
    local info = infoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", infoP, "TOPLEFT", 0, infoY)
    info:SetWidth(410)
    info:SetJustifyH("LEFT")
    info:SetText("|cffffd100Requires TurboFace Movers|r")
    info:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24
    return y
end

local function BuildMoversTab(c)
    local function MDB()
        if not TurboFaceDB.movers then TurboFaceDB.movers = {} end
        local db = TurboFaceDB.movers
        if db.enabled == nil then db.enabled = true end
        if db.locked == nil then db.locked = true end
        if db.snapToGrid == nil then db.snapToGrid = true end
        if db.snapSize == nil then db.snapSize = 5 end
        if db.showGrid == nil then db.showGrid = true end
        if db.gridSize == nil then db.gridSize = 32 end
        if db.gridAlpha == nil then db.gridAlpha = 0.14 end
        if db.showCoordinates == nil then db.showCoordinates = true end
        if db.showNudgeControls == nil then db.showNudgeControls = true end
        if db.nudgeStep == nil then db.nudgeStep = 1 end
        if db.auraLayout == nil then db.auraLayout = true end
        if type(db.elements) ~= "table" then db.elements = {} end
        if type(db.aura) ~= "table" then db.aura = {} end
        local a = db.aura
        if a.spacingX == nil then a.spacingX = 4 end
        if a.spacingY == nil then a.spacingY = 10 end
        if a.targetPerRow == nil then a.targetPerRow = 8 end
        if a.targetBuffGrowth == nil then a.targetBuffGrowth = "RIGHT_DOWN" end
        if a.targetDebuffGrowth == nil then a.targetDebuffGrowth = "RIGHT_DOWN" end
        return db
    end
    local function DefaultElementEnabled(key)
        if TurboFaceDB and TurboFaceDB.actionbars and TurboFaceDB.actionbars.bars and TurboFaceDB.actionbars.bars[key] then
            return TurboFaceDB.actionbars.bars[key].enabled ~= false
        end
        return true
    end
    local function EDB(key)
        local db = MDB()
        if type(db.elements[key]) ~= "table" then db.elements[key] = {} end
        local defaults = ns.defaults and ns.defaults.movers and ns.defaults.movers.elements and ns.defaults.movers.elements[key]
        if db.elements[key].enabled == nil then
            if defaults and defaults.enabled ~= nil then
                db.elements[key].enabled = defaults.enabled
            else
                db.elements[key].enabled = DefaultElementEnabled(key)
            end
        end
        if db.elements[key].hidden == nil then db.elements[key].hidden = (defaults and defaults.hidden == true) or false end
        if db.elements[key].clickThrough == nil then
            db.elements[key].clickThrough = (defaults and defaults.clickThrough == true) or false
        end
        return db.elements[key]
    end
    local function RefreshMovers()
        if ns.Movers then ns.Movers:Refresh() end
    end
    local function TopCheckbox(parent, y, x, label, field)
        parent, y = SectionParent(parent, y)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
        cb:SetChecked(MDB()[field] == true)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(label)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        cb:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            MDB()[field] = (self:GetChecked() == 1 or self:GetChecked() == true)
            RefreshMovers()
        end)
        return y - 26
    end
    local function ElementCheckbox(parent, y, x, label, key)
        parent, y = SectionParent(parent, y)
        local edb = EDB(key)

        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y + 2)
        cb:SetChecked(edb.enabled ~= false)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetWidth(72)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        cb:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            EDB(key).enabled = (self:GetChecked() == 1 or self:GetChecked() == true)
            RefreshMovers()
        end)

        local h = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        h:SetSize(18, 18)
        h:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 92, y + 1)
        h:SetChecked(edb.hidden == true)
        local hLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hLbl:SetPoint("LEFT", h, "RIGHT", 1, 0)
        hLbl:SetText("H")
        hLbl:SetTextColor(0.7, 0.7, 0.7)
        h:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            local checked = (self:GetChecked() == 1 or self:GetChecked() == true)
            EDB(key).hidden = checked
            if ns.Movers and ns.Movers.SetElementHidden then ns.Movers:SetElementHidden(key, checked) else RefreshMovers() end
        end)

        local ct = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        ct:SetSize(18, 18)
        ct:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 132, y + 1)
        ct:SetChecked(edb.clickThrough == true)
        local ctLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ctLbl:SetPoint("LEFT", ct, "RIGHT", 1, 0)
        ctLbl:SetText("CT")
        ctLbl:SetTextColor(0.7, 0.7, 0.7)
        ct:SetScript("OnClick", function(self)
            ns:PlayCheckSound(self)
            local checked = (self:GetChecked() == 1 or self:GetChecked() == true)
            EDB(key).clickThrough = checked
            if ns.Movers and ns.Movers.SetElementClickThrough then ns.Movers:SetElementClickThrough(key, checked) else RefreshMovers() end
        end)

        return y - 26
    end
    local function TopSlider(parent, y, x, w, label, field, minVal, maxVal, step)
        parent, y = SectionParent(parent, y)
        local nextY
        y, x, nextY = FlowPlace(parent, y, x, w, 46)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        lbl:SetText(label .. ":")
        lbl:SetWidth(w - SLIDER_VALUE_W - 6); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        sl:SetWidth(w); sl:SetHeight(14)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
        sl:SetMinMaxValues(minVal, maxVal)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        sl:SetValue(MDB()[field] or minVal)
        if sl.Low then sl.Low:SetText("") end
        if sl.High then sl.High:SetText("") end
        if sl.Text then sl.Text:SetText("") end
        local valueBox, RefreshValue = SliderValueBox(parent, x, y, w, sl, minVal, maxVal, step, false)
        sl:SetScript("OnValueChanged", function(_, v)
            if step >= 1 then v = math.floor(v + 0.5) end
            MDB()[field] = v
            RefreshValue(v)
            RefreshMovers()
        end)
        return nextY
    end

    local function Button(parent, y, x, w, label, fn)
        parent, y = SectionParent(parent, y)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 6)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end

    local function ElementRows(parent, y, rows)
        for i, entry in ipairs(rows) do
            local col = (i - 1) % 3
            local x = (col == 0) and 0 or ((col == 1) and GRID_COL2_X or GRID_COL3_X)
            ElementCheckbox(parent, y, x, entry[1], entry[2])
            if col == 2 or i == #rows then y = y - 26 end
        end
        return y
    end

    local y = -6
    local _, playerClass = UnitClass("player")
    y = MasterToggle(c, y, "TurboFace Movers", { dbKey = "movers.enabled" },
        "Use |cff00ccff/tf move|r to show cyan mover boxes and the alignment grid. Drag to move; X-/X+/Y-/Y+ nudge exactly. H hides a selected element; CT makes it click-through. In the lists below, H = Hide and CT = Click-through.",
        function() if ns.Movers and ns.Movers.Refresh then ns.Movers:Refresh() end end)

    y = Header(c, y, "Mover Mode")
    y = TopCheckbox(c, y, 0, "Enable TurboFace movers", "enabled")
    y = TopCheckbox(c, y, 0, "Lock movers", "locked")
    y = TopCheckbox(c, y, 0, "Snap movement to grid", "snapToGrid")
    y = TopCheckbox(c, y, 0, "Show alignment grid", "showGrid")
    y = TopCheckbox(c, y, 0, "Show coordinates on movers", "showCoordinates")
    y = TopCheckbox(c, y, 0, "Show nudge buttons", "showNudgeControls")
    y = TopCheckbox(c, y, 0, "Control player/target aura layout", "auraLayout")
    y = TopSlider(c, y, 0, W, "Snap Size", "snapSize", 1, 20, 1)
    y = TopSlider(c, y, 0, W, "Grid Size", "gridSize", 4, 128, 1)
    y = TopSlider(c, y, 0, W, "Nudge Step", "nudgeStep", 1, 20, 1)
    Button(c, y, 0, 120, "Unlock", function() if ns.Movers then ns.Movers:Unlock() end end)
    Button(c, y, 130, 120, "Lock", function() if ns.Movers then ns.Movers:Lock() end end)
    y = y - 34
    Button(c, y, 0, 160, "Reset All Movers", function() if ns.Movers then ns.Movers:ResetAll() end end)
    y = y - 44

    y = Header(c, y, "Blizzard Movers")
    local blizzardMovers = {
        { "Target of Target", "TargetFrameToT" },
        { "Minimap Clock", "MinimapClock" },
        { "Loot Roll Frames", "GroupLootRolls" },
        { "Minimap Icon", "MinimapMail" },
        { "Looking For Group Tracker", "MinimapLFG" },
        { "Latency Bar", "LatencyBar" },
        { "Tooltip", "GameTooltip" },
        { "Blizzard Loot Window", "BlizzardLootFrame" },
        { "Target Buffs", "TargetBuffs" },
        { "Target Debuffs", "TargetDebuffs" },
        { "Target of Target Debuffs", "ToTDebuffs" },
    }
    if ClientFeatureAvailable("movers.questTracker", true) then
        table.insert(blizzardMovers, 2, { "Quest Tracker", "QuestTracker" })
    end
    y = ElementRows(c, y, blizzardMovers)
    y = y - 6

    y = Header(c, y, "TurboFace Movers")
    local turboFaceMovers = {
        { "Player Main-Hand Swing", "PlayerMainSwingTimer" },
        { "Player Off-Hand Swing", "PlayerOffhandSwingTimer" },
        { "Player Ranged Swing", "PlayerRangedSwingTimer" },
        { "Player Cast Bar", "PlayerCastBar" },
        { "Target Swing Timer", "TargetSwingTimer" },
        { "Target Cast Bar", "TargetCastBar" },
        { "Leash Timer", "LeashTimer" },
        { "Speedrun Splits", "SpeedrunSplits" },
        { "Luxthos-like XP", "ExperienceBar" },
        { "FPS Counter", "FPSCounter" },
        { "TurboFace Loot Frame", "LootFrame" },
        { "Net Worth", "NetWorth" },
        { "Hearthstone", "Hearthstone" },
        { "Tracking Icon", "TrackingIcon" },
        { "Skill Tracker", "SkillTracker" },
        { "Class Buffs", "ClassBuffBar" },
        { "Flight Bar", "FlightBar" },
        { "UnstuckSkips", "UnstuckSkips" },
        { "Grocery Button", "GroceryButton" },
        { "Free Bag Slots", "BagSlots" },
    }
    if ClientFeatureAvailable("hud.spendTalentPoint", false) then
        table.insert(turboFaceMovers, 11, { "Spend Talent Point", "SpendTalentPoint" })
    end
    if ClientFeatureAvailable("combat.localMeterWindow", true) then
        table.insert(turboFaceMovers, { "Combat Meter", "CombatMeter" })
    end
    if playerClass == "DRUID" then
        table.insert(turboFaceMovers, 1, { "Druid Power Bar", "DruidPowerBar" })
    end
    y = ElementRows(c, y, turboFaceMovers)
    y = y - 6

    FinalizeSections(c, y)
end

local function BuildClassTab(c)
    c._tfApply = RefreshClassOptions
    local y = -6
    local _, playerClass = UnitClass("player")

    y = MasterToggle(c, y, "TurboFace Class Features", "class")

    y = Header(c, y, "Class Text")
    y = Dropdown(c, y, 0, W, "Font", "classFont", FontOptions(), RefreshClassOptions)
    y = Dropdown(c, y, 0, W, "Text Style", "classTextStyle", STYLE_OPTS, RefreshClassOptions)

    local function Button(parent, py, x, w, label, fn)
        parent, py = SectionParent(parent, py)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, py - 6)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end

    -- ------------------------------------------------------------------
    -- Missing-buff reminders
    -- ------------------------------------------------------------------
    y = Header(c, y, "Buff Reminders")

    -- Every Classic class has at least one class-owned reminder catalog entry.
    -- The unspent talent-point reminder is now a separate Speedrun text HUD.
    local hasReminders = true
    if hasReminders then
        y = Checkbox(c, y, 0, "Enable missing-buff reminders", "classBuffEnabled")
        y = Checkbox(c, y, 0, "Only show while in combat", "classBuffOnlyInCombat")
        y = y - 4

        if playerClass == "WARRIOR" then
            y = Checkbox(c, y, 0, "Show Revenge Window", "classBuffRevenge")
            y = Checkbox(c, y, 0, "Track Battle Shout", "classBuffBattleShout")
        elseif playerClass == "SHAMAN" then
            y = Checkbox(c, y, 0, "Track Lightning Shield",        "classBuffLightningShield")
            y = Checkbox(c, y, 0, "Track Weapon Imbue (main hand)", "classBuffWeaponMH")
            y = Checkbox(c, y, 0, "Show Clearcasting Proc (Elemental Focus)", "classBuffClearcasting")
        elseif playerClass == "DRUID" then
            y = Checkbox(c, y, 0, "Track Mark of the Wild", "classBuffMarkOfTheWild")
            y = Checkbox(c, y, 0, "Track Thorns",           "classBuffThorns")
        elseif playerClass == "PALADIN" then
            local cbSeal, lblSeal, cbSealCombat, lblSealCombat
            y, cbSeal, lblSeal = Checkbox(c, y, 0, "Track Seals (any Seal satisfies)", "classBuffSeal")
            -- Indented sub-option: only meaningful while seals are tracked, so
            -- it greys out with its parent instead of silently doing nothing.
            y, cbSealCombat, lblSealCombat =
                Checkbox(c, y, 16, "Track Seals only when in combat", "classBuffSealOnlyInCombat")
            local function SyncSealSub()
                SetSubOptionEnabled(cbSealCombat, lblSealCombat,
                    GetOptionValue("classBuffSeal") == true)
            end
            if cbSeal then cbSeal:HookScript("OnClick", SyncSealSub) end
            SyncSealSub()
            y = Checkbox(c, y, 0, "Track Blessings (any Blessing satisfies)", "classBuffBlessing")
            y = Checkbox(c, y, 0, "Track Auras (any Aura satisfies)", "classBuffAura")
        elseif playerClass == "WARLOCK" then
            y = Checkbox(c, y, 0, "Track Demon Skin / Demon Armor", "classBuffDemonArmor")
        elseif playerClass == "ROGUE" then
            y = Checkbox(c, y, 0, "Show Riposte Window", "classBuffRiposte")
        elseif playerClass == "HUNTER" then
            y = Checkbox(c, y, 0, "Show Mongoose Bite Window", "classBuffMongooseBite")
            y = Checkbox(c, y, 0, "Remind to Feed Pet", "classBuffFeedPet")
            y = Checkbox(c, y, 0, "Track Aspects (any Aspect satisfies)", "classBuffAspect")
            y = Checkbox(c, y, 0, "Track Trueshot Aura",                 "classBuffTrueshotAura")
        elseif playerClass == "PRIEST" then
            y = Checkbox(c, y, 0, "Track Power Word: Fortitude", "classBuffFortitude")
            y = Checkbox(c, y, 0, "Track Inner Fire",            "classBuffInnerFire")
            y = Checkbox(c, y, 0, "Track Divine Spirit",         "classBuffDivineSpirit")
            y = Checkbox(c, y, 0, "Track Fear Ward (dwarf)",     "classBuffFearWard")
            y = Checkbox(c, y, 0, "Track Shadow Protection",     "classBuffShadowProtection")
        elseif playerClass == "MAGE" then
            y = Checkbox(c, y, 0, "Show Clearcasting Proc (Arcane Concentration)", "classBuffMageClearcasting")
            y = Checkbox(c, y, 0, "Track Arcane Intellect",           "classBuffArcaneIntellect")
            y = Checkbox(c, y, 0, "Track Armor (Frost/Ice/Mage Armor)", "classBuffMageArmor")
        end
        if ClientFeatureAvailable("combat.classBuffTalentReminder", true) then
            y = Checkbox(c, y, 0, "Track Unspent Talent Points", "classBuffTalentPoints")
        end
        y = y - 6

        y = Slider(c, y, 0, W, "Icon Size", "classBuffIconSize", 20, 80, 1, false)
        y = Slider(c, y, 0, W, "Spacing",   "classBuffSpacing",  0,  24, 1, false)
        y = Slider(c, y, 0, W, "Warn Before Expiry (sec)", "classBuffWarnSeconds", 0, 60, 1, false)
        y = Dropdown(c, y, 0, W, "Growth Direction", "classBuffGrowth",
            {{name="Right",value="RIGHT"},{name="Left",value="LEFT"},{name="Up",value="UP"},{name="Down",value="DOWN"}})
        y = Checkbox(c, y, 0, "Pulse effect", "classBuffPulse")
        y = y - 4

        Button(c, y, 0, 160, "Test / Position Icons", function()
            if ns.ClassBuffs then ns.ClassBuffs:Test() end
        end)
        y = y - 40

    end

    -- ------------------------------------------------------------------
    -- Warrior: Overpower nameplate indicator (moved here from Nameplates)
    -- ------------------------------------------------------------------
    if playerClass == "WARRIOR" then
        y = Header(c, y, "Overpower Indicator (nameplate)")
        y = CheckboxRow(c, y, "Overpower Indicator", "warriorOverpowerIndicator", "", "")
        y = Dropdown(c, y, 0, W, "Indicator Position", "warriorOverpowerPosition",
            {{name="Left",value="LEFT"},{name="Right",value="RIGHT"},{name="Top",value="TOP"},{name="Bottom",value="BOTTOM"}})
        y = Slider(c, y, 0, W, "Indicator Size",     "warriorOverpowerSize",     12, 48, 1, false)
        y = Slider(c, y, 0, W, "Indicator Duration", "warriorOverpowerDuration", 1,  8,  0.5, false)
        y = CheckboxRow(c, y, "Show Timer", "warriorOverpowerShowTimer", "Cooldown Swipe", "warriorOverpowerSwipe")
        y = Slider(c, y, 0, W, "Indicator Margin",   "warriorOverpowerMargin",   0,  24, 1, false)
        y = Slider(c, y, 0, W, "Indicator X Offset", "warriorOverpowerOffsetX",  -40, 40, 1, false)
        y = Slider(c, y, 0, W, "Indicator Y Offset", "warriorOverpowerOffsetY",  -40, 40, 1, false)
        y = y - 6
    elseif playerClass == "HUNTER" then
        y = Header(c, y, "Counterattack Indicator (nameplate)")
        y = CheckboxRow(c, y, "Counterattack Indicator", "hunterCounterattackIndicator", "", "")
        y = Dropdown(c, y, 0, W, "Indicator Position", "hunterCounterattackPosition",
            {{name="Left",value="LEFT"},{name="Right",value="RIGHT"},{name="Top",value="TOP"},{name="Bottom",value="BOTTOM"}})
        y = Slider(c, y, 0, W, "Indicator Size",     "hunterCounterattackSize",     12, 48, 1, false)
        y = Slider(c, y, 0, W, "Indicator Duration", "hunterCounterattackDuration", 1,  8,  0.5, false)
        y = CheckboxRow(c, y, "Show Timer", "hunterCounterattackShowTimer", "Cooldown Swipe", "hunterCounterattackSwipe")
        y = Slider(c, y, 0, W, "Indicator Margin",   "hunterCounterattackMargin",   0,  24, 1, false)
        y = Slider(c, y, 0, W, "Indicator X Offset", "hunterCounterattackOffsetX",  -40, 40, 1, false)
        y = Slider(c, y, 0, W, "Indicator Y Offset", "hunterCounterattackOffsetY",  -40, 40, 1, false)
        y = y - 6
    end

    -- ------------------------------------------------------------------
    -- Druid: extra mana bar under the player power bar (Bear/Cat form)
    -- ------------------------------------------------------------------
    if playerClass == "DRUID" then
        y = Header(c, y, "Druid Power Bar")
        y = DependentCheckboxColumn(c, y, 0,
            "Show druid power bar", "druidPowerBarEnabled",
            "Show status text", "druidPowerBarStatusText")
        y = Dropdown(c, y, 0, W, "Text Font", "druidPowerBarFont", FontOptions(), RefreshClassOptions)
        y = Dropdown(c, y, 0, W, "Text Style", "druidPowerBarTextStyle", STYLE_OPTS, RefreshClassOptions)
        y = Slider(c, y, 0, W, "Text Size", "druidPowerBarTextSize", 6, 18, 1, false, RefreshClassOptions)
        y = Dropdown(c, y, 0, W, "Text Format", "druidPowerBarTextFormat",
            {{name="Percent",value="percent"},
             {name="Percent Current (Blizzard)",value="percent-current-blizzard"},
             {name="Current",value="current"},
             {name="Current / Max",value="current-max"},
             {name="Current / Max (Percent)",value="current-max-pct"},
             {name="Current (Percent)",value="current-pct"},
             {name="None",value="none"}}, RefreshClassOptions)
        y = Dropdown(c, y, 0, W, "Standalone Bar Texture", "druidPowerBarTexture",
            ns.GetLSMTextures and ns.GetLSMTextures() or ns.Textures, RefreshClassOptions)
        y = y - 4

    end

    FinalizeSections(c, y)
end

local function BuildSpeedrunTab(c)
    local y = -6

    local function RefreshFPSAndBatch()
        if ns.FPSCounter and ns.FPSCounter.Refresh then ns.FPSCounter:Refresh()
        elseif ns.Movers and ns.Movers.Refresh then ns.Movers:Refresh() end
        if ns.HearthBatch and ns.HearthBatch.Refresh then ns.HearthBatch:Refresh() end
    end

    local function Button(parent, py, x, w, label, fn)
        parent, py = SectionParent(parent, py)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, py - 6)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end

    -- ------------------------------------------------------------------
    -- Lvl1 Quick Setup: portable class-owned fresh-character bootstrap.
    -- Profiles live in TurboFaceProfilesDB, not ordinary settings profiles.
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("QuickSetup")
    y = Header(c, y, "Lvl1 Quick Setup", nil, nil, nil,
        "Cinematic Skips. Allows saving of Macros, Bindings, Action, and Edit Mode Profile and can automatically bind them on fresh character.")
    y = Checkbox(c, y, 0, "Auto-skip Level 1 cinematic", "quickSetup.autoSkipCinematic")
    y = Checkbox(c, y, 0, "Enable Automatic Lvl1 Quick Setup", "quickSetup.enabled")
    y = y - 4

    local quickSetupStatusP, quickSetupStatusY = SectionParent(c, y)
    local quickSetupStatus = quickSetupStatusP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    quickSetupStatus:SetPoint("TOPLEFT", quickSetupStatusP, "TOPLEFT", 0, quickSetupStatusY)
    quickSetupStatus:SetWidth(410)
    quickSetupStatus:SetJustifyH("LEFT")
    quickSetupStatus:SetTextColor(0.65, 0.65, 0.65)
    local function RefreshQuickSetupStatus()
        quickSetupStatus:SetText(ns.QuickSetup and ns.QuickSetup:GetStatusText() or "Quick Setup is unavailable")
    end
    RefreshQuickSetupStatus()
    y = y - 26

    Button(c, y, 0, 130, "Save Class Profile", function()
        if ns.QuickSetup then ns.QuickSetup:SaveCurrentClassProfile() end
        RefreshQuickSetupStatus()
    end)
    Button(c, y, 140, 130, "Apply Stored Profile", function()
        if ns.QuickSetup then ns.QuickSetup:ApplyCurrentClassProfile() end
        RefreshQuickSetupStatus()
    end)
    Button(c, y, 280, 120, "Reset Char Record", function()
        if ns.QuickSetup then ns.QuickSetup:ResetCharacterRecord() end
        RefreshQuickSetupStatus()
    end)
    y = y - 42

    -- ------------------------------------------------------------------
    -- Native cumulative /played splits, including 10% partial levels
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("SpeedrunSplits")
    y = Header(c, y, "Speedrun Splits", { dbKey = "speedrunSplits.enabled" }, nil, c._tfApply,
        "Tracks /played checkpoints for every full level and each 10% XP checkpoint. Compares the current run with account-wide race/class PBs, and records best individual segments.")
    y = CheckboxRow(c, y, "Show partial levels (12.1–12.9)", "speedrunSplits.showPartials",
        "Show next checkpoint", "speedrunSplits.showNext")
    y = CheckboxRow(c, y, "Show PB delta", "speedrunSplits.showDelta",
        "Color comparisons", "speedrunSplits.colorComparisons")
    y = Checkbox(c, y, 0, "Show days in long timers", "speedrunSplits.showDays")
    y = Slider(c, y, 0, W, "Visible Split Rows", "speedrunSplits.visibleRows", 3, 40, 1, false)
    y = Slider(c, y, 0, W, "Automatic PB Save Level", "speedrunSplits.autoSaveLevel", 2, 60, 1, false)
    y = Dropdown(c, y, 0, W, "Font", "speedrunSplits.font", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "speedrunSplits.textStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Font Size", "speedrunSplits.fontSize", 8, 20, 1, false)
    y = Slider(c, y, 0, W, "Scale", "speedrunSplits.scale", 0.5, 2, 0.05, true)
    y = y - 4

    Button(c, y, 0, 125, "Save Current PB", function()
        if ns.SpeedrunSplits then ns.SpeedrunSplits:SaveCurrentRun() end
    end)
    Button(c, y, 135, 125, "Reset Current Run", function()
        if ns.SpeedrunSplits then ns.SpeedrunSplits:ResetCurrentRun() end
    end)
    Button(c, y, 270, 125, "Import Old Splits", function()
        if ns.SpeedrunSplits then ns.SpeedrunSplits:ImportLegacy() end
    end)
    y = y - 42

    -- ------------------------------------------------------------------
    -- Spend Talent Point reminder
    -- ------------------------------------------------------------------
    if ClientFeatureAvailable("hud.spendTalentPoint", false) then
        c._tfApply = RefreshOwner("TalentPointReminder")
        y = Header(c, y, "Spend Talent Point Reminder", { dbKey = "talentReminderEnabled" }, nil, c._tfApply,
            "Shows SPEND TALENT POINT while the character has an unspent talent point.")
        y = Dropdown(c, y, 0, W, "Font", "talentReminderFont", FontOptions())
        y = Dropdown(c, y, 0, W, "Text Style", "talentReminderTextStyle", STYLE_OPTS)
        y = Slider(c, y, 0, W, "Font Size", "talentReminderFontSize", 10, 32, 1, false)
        y = y - 4
    end

    -- ------------------------------------------------------------------
    -- Loot Frame
    -- ------------------------------------------------------------------
    y = BuildLootSection(c, y)

    -- ------------------------------------------------------------------
    -- Net Worth display
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("NW")
    y = Header(c, y, "Net Worth", { dbKey = "netWorthEnabled" }, nil, c._tfApply,
        "Shows your money plus junk value.")

    y = Checkbox(c, y, 0, "Show \"NW:\" label", "netWorthLabel")
    y = y - 6

    y = Dropdown(c, y, 0, W, "Font", "netWorthFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "netWorthTextStyle", STYLE_OPTS)
    y = Slider  (c, y, 0, W, "Font Size", "netWorthFontSize", 8, 24, 1, false)
    y = ColorPicker(c, y, 0, "Label Color", "netWorthColor")
    y = y - 10

    local infoP, infoY = SectionParent(c, y)
    local info = infoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", infoP, "TOPLEFT", 0, infoY)
    info:SetWidth(380)
    info:SetJustifyH("LEFT")
    info:SetText("|cffffd100Requires TurboFace Movers|r")
    info:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24

    -- ------------------------------------------------------------------
    -- Junk / inventory manager
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("Inv")
    y = Header(c, y, "Junk & Inventory", { dbKey = "invEnabled" }, nil, c._tfApply,
        "Automatically marks grey items junk. Cycles itemID through Junk, Useful, and Bank marks. Junk items will auto-sell at next vendor. Bank-marked items will auto-deposit on next banker interaction.")
    y = Checkbox(c, y, 0, "Auto-sell junk at vendors", "invAutoSell")
    y = Checkbox(c, y, 0, "Show Junk / Bank icons on items", "invShowJunkIcon")
    y = Dropdown(c, y, 0, W, "Cycle Junk / Useful / Bank Mouse Shortcut", "invMarkMouseShortcut", {
        {name="None",                         value="NONE"},
        {name="Ctrl + Right Click",           value="CTRL-RIGHT"},
        {name="Shift + Right Click",          value="SHIFT-RIGHT"},
        {name="Alt + Right Click",            value="ALT-RIGHT"},
        {name="Ctrl + Shift + Right Click",   value="CTRL-SHIFT-RIGHT"},
        {name="Ctrl + Alt + Right Click",     value="CTRL-ALT-RIGHT"},
        {name="Shift + Alt + Right Click",    value="SHIFT-ALT-RIGHT"},
        {name="Ctrl + Shift + Alt + Right Click", value="CTRL-SHIFT-ALT-RIGHT"},
    })
    y = Checkbox(c, y, 0, "Ctrl + Right Click bank item withdraws all matching stacks", "invBankWithdrawAll")
    y = y - 4

    y = Checkbox(c, y, 0, "Enable Delete Hovered Item", "invDeleteHoveredEnabled")

    y = Dropdown(c, y, 0, W, "Delete Hovered Backup Mouse Shortcut", "invDeleteHoveredMouseShortcut", {
        {name="None",                         value="NONE"},
        {name="Ctrl + Right Click",           value="CTRL-RIGHT"},
        {name="Shift + Right Click",          value="SHIFT-RIGHT"},
        {name="Alt + Right Click",            value="ALT-RIGHT"},
        {name="Ctrl + Shift + Right Click",   value="CTRL-SHIFT-RIGHT"},
        {name="Ctrl + Alt + Right Click",     value="CTRL-ALT-RIGHT"},
        {name="Shift + Alt + Right Click",    value="SHIFT-ALT-RIGHT"},
        {name="Ctrl + Shift + Alt + Right Click", value="CTRL-SHIFT-ALT-RIGHT"},
    })
    y = y - 4

    Button(c, y, 0,   130, "Sell Junk Now", function() if ns.Inv then ns.Inv:SellNow() end end)
    Button(c, y, 140, 150, "Clear Item Marks", function() if ns.Inv then ns.Inv:ResetMarks() end end)
    y = y - 42

    local jinfoP, jinfoY = SectionParent(c, y)
    local jinfo = jinfoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    jinfo:SetPoint("TOPLEFT", jinfoP, "TOPLEFT", 0, jinfoY)
    jinfo:SetWidth(410)
    jinfo:SetJustifyH("LEFT")
    jinfo:SetText("|cffff5555Delete Hovered Bag Item does nothing unless its safety checkbox is enabled, and then it can destroy ANY carried bag item under the mouse without confirmation.|r")
    jinfo:SetTextColor(0.5, 0.5, 0.5)
    y = y - 42

    -- ------------------------------------------------------------------
    -- Free bag slots display
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("BagSlots")
    y = Header(c, y, "Free Bag Slot Counter", { dbKey = "bagSlotsEnabled" }, nil, c._tfApply,
        "Shows number of empty bag slots")


    -- ------------------------------------------------------------------
    -- Grocery list (queued vendor consumables)
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("Grocery")
    y = Header(c, y, "Grocery List", { dbKey = "groceryEnabled" }, nil, c._tfApply,
        "Shopping Menu for vendor food, drink, potions, and ammo.")

    y = Checkbox(c, y, 0, "Auto-buy queued items at vendors", "groceryAutoBuy")
    y = Checkbox(c, y, 0, "Announce purchases in chat", "groceryChatSummary")
    y = Checkbox(c, y, 0, "Show the floating grocery button", "groceryShowButton")
    y = y - 4

    Button(c, y, 0,   130, "Open Grocery List", function() if ns.Grocery then ns.Grocery:Show() end end)
    Button(c, y, 140, 150, "Clear Grocery List", function() if ns.Grocery then ns.Grocery:ClearQueue() end end)
    y = y - 42

    local ginfoP, ginfoY = SectionParent(c, y)
    local ginfo = ginfoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ginfo:SetPoint("TOPLEFT", ginfoP, "TOPLEFT", 0, ginfoY)
    ginfo:SetWidth(410)
    ginfo:SetJustifyH("LEFT")
    ginfo:SetText("|cffffd100The floating button requires TurboFace Movers|r")
    ginfo:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24

    -- ------------------------------------------------------------------
    -- Trainer spells
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("Trainer")
    y = Header(c, y, "Trainer Spells", { dbKey = "trainerEnabled" }, nil, c._tfApply,
        "TurboFace Training adds Class Training and Skills tabs to the spellbook, plus Training and Recipes views beside profession windows. Classic Era class/pet and profession recipe reference data is bundled; trainer visits add live prices and availability. Queueable entries can be prioritized for auto-training on the next matching trainer visit.")


    -- ------------------------------------------------------------------
    -- Luxthos-like XP Bar
    -- ------------------------------------------------------------------
    y = BuildExperienceSection(c, y)

    -- ------------------------------------------------------------------
    -- Hearthstone bind location
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("HS")
    y = Header(c, y, "Hearthstone Tracker", { dbKey = "hearthEnabled" }, nil, c._tfApply,
        "Shows what destination hearthstone set to. Displays Hearthstone timer. Checkbox will auto-bind hearthstone at next innkeeper")

    y = Checkbox(c, y, 0, "Show Hearthstone cooldown timer", "hearthTimerEnabled")
    y = Checkbox(c, y, 0, "Enable one-shot innkeeper auto-bind", "hearthAutoBindEnabled")
    y = Dropdown(c, y, 0, W, "Font", "hearthFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "hearthTextStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Font Size", "hearthFontSize", 8, 24, 1, false)
    y = y - 4

    local hsP, hsY = SectionParent(c, y)
    local hsText = hsP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hsText:SetPoint("TOPLEFT", hsP, "TOPLEFT", 0, hsY)
    hsText:SetWidth(380)
    hsText:SetJustifyH("LEFT")
    hsText:SetText("|cffffd100Requires TurboFace Movers|r")
    hsText:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24

    -- ------------------------------------------------------------------
    -- Hearthstone batching
    -- ------------------------------------------------------------------
    c._tfApply = RefreshFPSAndBatch
    y = Header(c, y, "Hearthstone Batching",
        { dbKey = "hearthBatchEnabled", requiresDbKey = "fpsCounterEnabled" }, nil, c._tfApply)

    local hbReqP, hbReqY = SectionParent(c, y)
    local hbReqText = hbReqP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hbReqText:SetPoint("TOPLEFT", hbReqP, "TOPLEFT", 0, hbReqY)
    hbReqText:SetWidth(380)
    hbReqText:SetJustifyH("LEFT")
    hbReqText:SetText("|cffffd100Requires FPS Counter|r")
    hbReqText:SetTextColor(0.5, 0.5, 0.5)
    y = y - 20

    y = Slider(c, y, 0, W, "Minimum Frame Rate During Cast", "hearthBatchFPS", 60, 500, 10, false)
    y = Checkbox(c, y, 0, "Report hits, misses and calibration", "hearthBatchVerbose")
    y = Checkbox(c, y, 0, "Show success estimate on the FPS counter", "hearthBatchOnFPS")
    y = y - 4

    local hbEst = SectionParent(c, y)
    local hbEstText = hbEst:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hbEstText:SetPoint("TOPLEFT", hbEst, "TOPLEFT", 0, y)
    hbEstText:SetWidth(380)
    hbEstText:SetJustifyH("LEFT")

    local function UpdateBatchEstimate()
        if not ns.HearthBatch or not ns.HearthBatch.SuccessChance then
            hbEstText:SetText("")
            return
        end
        local ok, blended, modelP, hits, attempts =
            pcall(ns.HearthBatch.SuccessChance, ns.HearthBatch)
        if not ok or type(blended) ~= "number" then hbEstText:SetText("") return end
        local _, d, sigma, pairCount, _, tier = ns.HearthBatch:Estimate()
        local scope = (tier == "realm") and "this realm"
            or (tier == "account") and "all realms" or "assumed"
        hbEstText:SetText(string.format(
            "Success chance: |cff00ccff%.0f%%|r  (model %.0f%%, record %d/%d, frame %.1fms, jitter %.1fms from %d pairs, %s)",
            blended * 100, (modelP or 0) * 100, hits or 0, attempts or 0,
            (d or 0) * 1000, (sigma or 0) * 1000, pairCount or 0, scope))
    end
    UpdateBatchEstimate()
    hearthBatchRefresh = UpdateBatchEstimate
    c:HookScript("OnShow", UpdateBatchEstimate)
    y = y - 20

    -- Clearing the pool. Timing data describes a connection path, so it goes
    -- stale when the path changes rather than when the character does -- and
    -- stale samples are worse than none, because a confident wrong number does
    -- not announce itself.
    local hbClrP, hbClrY = SectionParent(c, y)
    local hbClrText = hbClrP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hbClrText:SetPoint("TOPLEFT", hbClrP, "TOPLEFT", 0, hbClrY)
    hbClrText:SetWidth(380)
    hbClrText:SetJustifyH("LEFT")
    hbClrText:SetTextColor(0.5, 0.5, 0.5)
    hbClrText:SetText("Timing data is shared by every character on this realm and measures your connection, "
        .. "not your character. Clear it if anything about that path has changed -- a new router, PC or GPU, "
        .. "moving between wifi and ethernet, an ISP or plan change, or a house move. "
        .. "|cffffd100Stale samples produce a confident but wrong success estimate and a lead calibrated for "
        .. "conditions you no longer have.|r Otherwise leave it: it only gets better with more batches.")
    y = y - 58

    local hbClrBtn = CreateFrame("Button", nil, hbClrP, "UIPanelButtonTemplate")
    hbClrBtn:SetSize(200, 22)
    hbClrBtn:SetPoint("TOPLEFT", hbClrP, "TOPLEFT", 0, y)
    hbClrBtn:SetText("Clear Batch Timing Data")
    hbClrBtn:SetScript("OnClick", function()
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
            or (GetRealmName and GetRealmName()) or "this realm"
        StaticPopup_Show("TURBOFACE_HEARTHBATCH_CLEAR", realm)
    end)
    y = y - 32

    local hbP, hbY = SectionParent(c, y)
    local hbText = hbP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hbText:SetPoint("TOPLEFT", hbP, "TOPLEFT", 0, hbY)
    hbText:SetWidth(380)
    hbText:SetJustifyH("LEFT")
    hbText:SetTextColor(0.5, 0.5, 0.5)
    hbText:SetText("Open an innkeeper's bind confirmation, then use your Hearthstone without answering it: "
        .. "you teleport to your old home and bind to the new innkeeper. Success needs the confirmation to reach "
        .. "the server in the same ~10ms batch as the cast finishing, so a low frame cap is temporarily lifted "
        .. "during the cast and restored after. This only ever raises your cap -- if you are already uncapped or "
        .. "faster than this value, nothing is changed. |cffffd100Unreliable below ~150fps -- disable vsync for best results.|r "
        .. "Timing self-calibrates per character; /tf hearthbatch shows the current lead and hit rate.")
    -- This paragraph wraps taller than the old 66px reservation at Classic's
    -- options-panel width. Keep enough vertical room before the next category.
    y = y - 90

    -- ------------------------------------------------------------------
    -- FPS counter HUD
    -- ------------------------------------------------------------------
    c._tfApply = RefreshFPSAndBatch
    y = Header(c, y, "FPS Counter",
        { dbKey = "fpsCounterEnabled", disablesDbKey = "hearthBatchEnabled" }, nil, c._tfApply,
        "Shows current frames per second. Hearthstone Batching uses this counter for its live success estimate.")

    -- ------------------------------------------------------------------
    -- Optional UnstuckSkips notifier presentation hook
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("UnstuckSkipVisual")
    y = Header(c, y, "UnstuckSkips Notifier", { dbKey = "unstuckSkipVisualEnabled" }, nil, c._tfApply,
        "Replaces notifier visual. Check the box after using Blizzard's Unstuck service to start four hour real-time estimate.")
    y = Dropdown(c, y, 0, W, "Font", "unstuckSkipFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "unstuckSkipTextStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Font Size", "unstuckSkipFontSize", 8, 24, 1, false)
    y = y - 4

    local usP, usY = SectionParent(c, y)
    local usText = usP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    usText:SetPoint("TOPLEFT", usP, "TOPLEFT", 0, usY)
    usText:SetWidth(390)
    usText:SetJustifyH("LEFT")
    usText:SetText("|cffffd100Requires UnstuckSkips addon, TurboFace Movers|r")
    usText:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24

    -- ------------------------------------------------------------------
    -- Skill tracker HUD
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("Skills")
    y = Header(c, y, "Skill Tracker", { dbKey = "skillTrackerEnabled" }, nil, c._tfApply,
        "Column of Current/Max Value of your skills.")

    Checkbox(c, y, 0, "Professions", "skillTrackerProfessions")
    Checkbox(c, y, GRID_COL2_X, "Secondary skills", "skillTrackerSecondary")
    DependentCheckboxColumn(c, y, GRID_COL3_X,
        "Weapon skills", "skillTrackerWeapons",
        "Equipped weapons only", "skillTrackerEquippedWeaponsOnly")
    y = y - 54
    y = Dropdown(c, y, 0, W, "Font", "skillTrackerFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "skillTrackerTextStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Font Size", "skillTrackerFontSize", 8, 20, 1, false)
    y = Slider(c, y, 0, W, "Icon Size", "skillTrackerIconSize", 8, 28, 1, false)
    y = Slider(c, y, 0, W, "Row Spacing", "skillTrackerSpacing", 0, 10, 1, false)


    -- ------------------------------------------------------------------
    -- Enemy leash timer
    -- ------------------------------------------------------------------
    c._tfApply = RefreshOwner("LeashTimer")
    y = Header(c, y, "Enemy Leash Timer", { dbKey = "leashTimerEnabled" }, nil, c._tfApply,
        "Shows ESTIMATED per-enemy leash countdown. BETA feature.")

    y = Dropdown(c, y, 0, W, "Font", "leashTimerFont", FontOptions())
    y = Dropdown(c, y, 0, W, "Text Style", "leashTimerTextStyle", STYLE_OPTS)
    y = Slider(c, y, 0, W, "Font Size", "leashTimerFontSize", 8, 20, 1, false)
    y = y - 4

    local ltinfoP, ltinfoY = SectionParent(c, y)
    local ltinfo = ltinfoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ltinfo:SetPoint("TOPLEFT", ltinfoP, "TOPLEFT", 0, ltinfoY)
    ltinfo:SetWidth(400)
    ltinfo:SetJustifyH("LEFT")
    ltinfo:SetText("|cffffd100This is still in BETA. Requires TurboFace Movers|r")
    ltinfo:SetTextColor(0.5, 0.5, 0.5)
    y = y - 24

    FinalizeSections(c, y)
end

-- =============================================================================
-- QOL TAB (internal `plus` keys retained for profile compatibility)
-- =============================================================================

local function BuildPlusTab(c)
    c._tfApply = RefreshPlusOptions
    local P = "plus."
    local y = -6

    -- Small grey note routed through SectionParent so collapsed layout stays
    -- correct. Used to flag reload-required sections.
    local function Note(text)
        local p, py = SectionParent(c, y)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py)
        fs:SetWidth(410)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.5, 0.5, 0.5)
        y = y - 30
    end

    -- Local button helper: the other tabs each define their own and none is in
    -- scope here. Routed through SectionParent like Note so a collapsed
    -- section still lays out correctly.
    local function Button(label, w, fn)
        local p, py = SectionParent(c, y)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 0, py - 6)
        b:SetText(label)
        b:SetScript("OnClick", fn)
        y = y - 32
    end

    -- ------------------------------------------------------------------
    -- Automation
    -- ------------------------------------------------------------------
    local function BuildAutomation()
    y = Header(c, y, "Automation", "plus", "automation")
    local questAutomationRowY = y
    y = CheckboxRow(c, y,
        "Auto Quest Accept", P.."autoQuestAccept",
        "Auto Quest Turn-in", P.."autoQuestTurnIn")
    CheckboxRowNote(c, questAutomationRowY, "Shift to bypass")
    y = Checkbox(c, y, 0, "Automate single-option gossip (quests excluded)", P.."automateGossip")
    y = Checkbox(c, y, 0, "Accept summons (10s grace, not in combat)", P.."acceptSummon")
    y = Checkbox(c, y, 0, "Auto-resurrect at spirit healers (shift cancels)", P.."automateSpiritHealer")
    DependentCheckboxColumn(c, y, 0,
        "Accept resurrection", P.."acceptRes",
        "Not from combat casters", P.."acceptResNoCombat")
    DependentCheckboxColumn(c, y, GRID_COL2_X,
        "Auto-release in battlegrounds", P.."releasePvP",
        "Except Alterac Valley", P.."releaseNoAlterac")
    DependentCheckboxColumn(c, y, GRID_COL3_X,
        "Auto-repair at merchants", P.."autoRepair",
        "Show repair cost in chat", P.."autoRepairSummary")
    y = y - 54
    y = Slider(c, y, 0, 300, "Release delay (ms, shift cancels)", P.."releaseDelay", 200, 3000, 100)
    y = y - 4
    end

    -- ------------------------------------------------------------------
    -- Social
    -- ------------------------------------------------------------------
    local function BuildSocial()
    y = Header(c, y, "Social", "plus", "social")
    y = CheckboxRow(c, y, "Block duels (unless friend)", P.."blockDuels", "Block party invites (unless friend)", P.."blockPartyInvites")
    y = CheckboxRow(c, y, "Block Battle.net friend requests", P.."blockFriendRequests", "Block shared quests (unless friend)", P.."blockSharedQuests")
    y = CheckboxRow(c, y, "Auto-accept party from friends", P.."acceptPartyFriends", "Count guild members as friends", P.."friendlyGuild")
    y = DependentCheckboxColumn(c, y, 0,
        "Invite players who whisper the keyword", P.."inviteFromWhisper",
        "Only from friends", P.."inviteFriendsOnly")

    -- Invite keyword editbox
    do
        local p, py = SectionParent(c, y)
        local kLbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        kLbl:SetPoint("TOPLEFT", p, "TOPLEFT", 20, py - 4)
        kLbl:SetText("Invite keyword:")
        kLbl:SetTextColor(0.85, 0.85, 0.85)

        local kBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        kBox:SetSize(120, 20)
        kBox:SetPoint("TOPLEFT", p, "TOPLEFT", 120, py)
        kBox:SetAutoFocus(false)
        kBox:SetMaxLetters(20)
        kBox:SetText(GetOptionValue(P.."inviteKeyword") or "inv")
        local function SaveKeyword(self)
            local txt = strtrim(self:GetText() or "")
            if txt == "" then txt = "inv" end
            SetOptionValue(P.."inviteKeyword", txt)
            RefreshPlusOptions()
        end
        kBox:SetScript("OnEnterPressed", function(self) SaveKeyword(self) self:ClearFocus() end)
        kBox:SetScript("OnEscapePressed", function(self)
            self:SetText(GetOptionValue(P.."inviteKeyword") or "inv") self:ClearFocus()
        end)
        kBox:SetScript("OnEditFocusLost", SaveKeyword)
        y = y - 30
    end
    y = y - 4
    end

    -- ------------------------------------------------------------------
    -- Interface
    -- ------------------------------------------------------------------
    local function BuildInterface()
    y = Header(c, y, "Interface", "plus", "interface")
    Note("Changes below apply after |cff00ccff/reload|r.")
    y = CheckboxRow(c, y, "Hide portrait hit numbers", P.."hideHitIndicators", "Hide zone text popups", P.."hideZoneText")
    y = CheckboxRow(c, y, "Hide action bar keybind text", P.."hideKeybindText", "Hide action bar macro names", P.."hideMacroText")
    y = Checkbox(c, y, 0, "Hide raid group labels", P.."hideRaidGroupLabels")
    y = Checkbox(c, y, 0, "Show raid frame toggle button", P.."showRaidToggle")
    if ClientFeatureAvailable("plus.questLevels", true) then
        y = DependentCheckboxColumn(c, y, 0,
            "Show quest levels in quest log", P.."enhanceQuestLevels",
            "With difficulty tags (D/R/+/P)", P.."enhanceQuestDifficulty")
    else
        y = Checkbox(c, y, 0, "Show quest difficulty tags (D/R/+/P)", P.."enhanceQuestDifficulty")
    end
    if ClientFeatureAvailable("plus.combinedBagMovable", false) then
        y = Checkbox(c, y, 0, "Allow dragging Blizzard's combined bag", P.."combinedBagMovable")
        Note("Drag the combined bag by its title or empty background. Individual bag windows are unchanged.")
    end
    y = y - 4
    end

    -- ------------------------------------------------------------------
    -- Minimap (Interface, but grouped for clarity)
    -- ------------------------------------------------------------------
    local function BuildMinimap()
    c._tfApply = RefreshOwner("PlusInterface")
    y = Header(c, y, "Minimap", "plus", "minimap")
    Note("Size and border controls apply live. Enabling minimap hide controls also applies live; restoring Blizzard-owned elements after turning a hide option back off may require |cff00ccff/reload|r. Border options affect the Square shape only.")
    y = Dropdown(c, y, 0, 300, "Minimap shape", P.."minimapShape", MINIMAP_SHAPES)
    y = Slider(c, y, 0, 300, "Minimap size", P.."minimapSize", 140, 560, 1)
    y = Dropdown(c, y, 0, 300, "Minimap border", P.."minimapBorderTexture",
        ns.GetLSMBorders and ns.GetLSMBorders() or ns.Borders)
    y = Slider(c, y, 0, 300, "Minimap border width", P.."minimapBorderWidth", 1, 24, 1)
    y = Slider(c, y, 0, 300, "Minimap border offset", P.."minimapBorderOffset", -12, 12, 1)
    y = Checkbox(c, y, 0, "Zone text banner above the minimap", P.."minimapZoneBanner")
    y = Slider(c, y, 0, 300, "Zone text size", P.."minimapZoneTextSize", 8, 28, 1)
    y = CheckboxRow(c, y, "Hide zoom buttons", P.."hideMiniZoomBtns", "Hide clock", P.."hideMiniClock")
    y = CheckboxRow(c, y, "Hide day/night indicator", P.."hideMiniDayNight", "Hide zone text bar", P.."hideMiniZoneText")
    y = Checkbox(c, y, 0, "Hide Looking for Group button", P.."hideMiniLFG")
    y = y - 4
    c._tfApply = RefreshPlusOptions
    end

    -- ------------------------------------------------------------------
    -- Minimap tracking icon
    -- ------------------------------------------------------------------
    local function BuildMinimapTrackingIcon()
    c._tfApply = RefreshOwner("Tracker")
    y = Header(c, y, "Minimap Tracking Icon", { dbKey = "trackerEnabled" }, nil, c._tfApply)

    y = Checkbox(c, y, 0, "Hide Blizzard's minimap tracking icon", "trackerHideBlizzard")
    y = Checkbox(c, y, 0, "Show dimmed icon when nothing is tracked", "trackerShowInactive")
    y = Checkbox(c, y, 0, "Border and background", "trackerBorder")
    y = y - 4

    y = Slider(c, y, 0, W, "Icon Size", "trackerSize", 12, 48, 1, false)
    y = Slider(c, y, 0, W, "Opacity",   "trackerAlpha", 0.1, 1.0, 0.05, true)
    y = y - 6

    local tinfoP, tinfoY = SectionParent(c, y)
    local tinfo = tinfoP:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tinfo:SetPoint("TOPLEFT", tinfoP, "TOPLEFT", 0, tinfoY)
    tinfo:SetWidth(380)
    tinfo:SetJustifyH("LEFT")
    tinfo:SetText("TurboFace's own tracking indicator: shows what you're tracking " ..
        "(Find Herbs, Find Minerals, hunter tracking). The dimmed icon reminds you " ..
        "tracking dropped after a death. |cffffd100Requires TurboFace Movers to be enabled.|r Move it with /tfmove (Tracking Icon); hide " ..
        "and click-through are controlled in the Movers tab.")
    tinfo:SetTextColor(0.5, 0.5, 0.5)
    y = y - 70   -- reserve the full height of the wrapped info paragraph

    -- Restore Plus ownership for the remaining Plus sections.
    c._tfApply = RefreshPlusOptions
    end

    -- ------------------------------------------------------------------
    -- Map
    -- ------------------------------------------------------------------
    local function BuildMap()
    c._tfApply = RefreshOwner("PlusMap")
    y = Header(c, y, "Map", "plus", "map")
    local mapEnhancedZoomAvailable = ClientFeatureAvailable("plus.mapEnhancedZoom", true)
    local mapRememberZoomAvailable = ClientFeatureAvailable("plus.mapRememberZoom", true)
    if not mapEnhancedZoomAvailable or not mapRememberZoomAvailable then
        Note("The draggable windowed map remains available. Enhanced zoom and remembered pan/zoom are disabled on Forever because its protected quest-pin pool requires Blizzard-exclusive ownership of MapCanvas.")
    else
        Note("Applies after |cff00ccff/reload|r; the zoom ceiling applies live. Affects the windowed map only. Blizzard's own right-click Reset entry is broken on 1.15.9, so use the button below.")
    end
    y = Checkbox(c, y, 0, "Allow moving the windowed map (drag the title bar)", P.."mapMovable")
    if mapEnhancedZoomAvailable then
        y = Checkbox(c, y, 0, "Zoom toward the cursor with the mouse wheel", P.."mapEnhancedZoom")
        y = Slider(c, y, 0, 300, "Maximum zoom", P.."mapZoomMax", 1, 6, 0.5, false, RefreshOwner("PlusMap"))
    end
    if mapRememberZoomAvailable then
        y = Checkbox(c, y, 0, "Remember zoom and pan when reopening the map", P.."mapRememberZoom")
    end
    Button("Reset Map Position", 160, function()
        if ns.PlusMap then ns.PlusMap:ResetPosition() end
    end)
    y = y - 4
    c._tfApply = RefreshPlusOptions
    end

    -- ------------------------------------------------------------------
    -- Chat
    -- ------------------------------------------------------------------
    local function BuildChat()
    y = Header(c, y, "Chat", "plus", "chat")
    Note("Applies after |cff00ccff/reload|r.")
    y = Checkbox(c, y, 0, "Text outline", P.."chatTextOutline")
    y = CheckboxRow(c, y, "Unclamp chat frame (drag to edge)", P.."unclampChat", "Disable chat fade", P.."noChatFade")
    y = CheckboxRow(c, y, "Hide chat buttons", P.."noChatButtons", "Hide combat log tab", P.."noCombatLogTab")
    y = y - 4
    end

    -- ------------------------------------------------------------------
    -- System
    -- ------------------------------------------------------------------
    local function BuildSystem()
    y = Header(c, y, "System", "plus", "system")
    Note("Sound, loot and bag options apply after |cff00ccff/reload|r.")
    y = CheckboxRow(c, y, "Disable screen glow", P.."noScreenGlow", "Disable screen effects (death/nether)", P.."noScreenEffects")
    y = CheckboxRow(c, y, "Max camera zoom", P.."maxCameraZoom", "Silence rested emote sounds", P.."noRestedEmotes")
    y = Checkbox(c, y, 0, "Set weather density", P.."setWeatherDensity")
    y = Slider(c, y, 0, 300, "Weather density (0=Very Low, 3=High)", P.."weatherLevel", 0, 3, 1)
    y = Checkbox(c, y, 0, "Faster auto loot", P.."fasterLooting")
    y = CheckboxRow(c, y, "Disable loot warnings", P.."noConfirmLoot", "Disable auto bag opening", P.."noBagAutomation")
    if ClientFeatureAvailable("plus.vendorPrice", true) then
        y = CheckboxRow(c, y, "Show vendor price in tooltips", P.."showVendorPrice", "Keep audio synced (device changes)", P.."keepAudioSynced")
    else
        y = Checkbox(c, y, 0, "Keep audio synced (device changes)", P.."keepAudioSynced")
    end
    y = y - 4
    end

    -- ------------------------------------------------------------------
    -- Flight bar
    -- ------------------------------------------------------------------
    local function BuildFlightBar()
    y = Header(c, y, "Flight Bar", "plus", "flightBar")
    Note("Taxi times are learned account-wide from completed flights. A route is recorded on its first trip; later trips show the destination, countdown, and fill-forward progress. |cffffd100Requires TurboFace Movers.|r Position with |cff00ccff/tfmove|r (Flight Bar).")
    y = Slider(c, y, 0, 300, "Bar width", P.."flightBarWidth", 120, 400, 10)
    y = Slider(c, y, 0, 300, "Bar scale", P.."flightBarScale", 0.5, 2.0, 0.05, true)
    y = y - 4
    end

    BuildMap()
    BuildFlightBar()
    BuildAutomation()
    BuildSocial()
    BuildInterface()
    BuildChat()
    BuildSystem()
    BuildMinimap()
    BuildMinimapTrackingIcon()

    FinalizeSections(c, y)
end

-- =============================================================================
-- TAB BAR
-- =============================================================================

local TAB_DEFS = {
    { name = "Movers",     build = BuildMoversTab     },
    { name = "Global",     build = BuildGlobalTab     },
    { name = "Nameplates", build = BuildNameplatesTab },
    { name = "Unit Frames",build = BuildUnitFramesTab },
    { name = "Class",      build = BuildClassTab      },
    { name = "QoL",        build = BuildPlusTab       },
    { name = "Speedrun",   build = BuildSpeedrunTab   },
    { name = "Profile",    build = BuildProfileTab    },
}

local function EnsureTabBuilt(idx)
    local tab = tabs[idx]
    if not tab or tab.built then return end
    if tab.build and tab.scrollChild then
        local c = tab.scrollChild
        c._tfSections = {}
        c._tfTabName = tab.name or ("tab" .. idx)
        c._tfCurSection = nil
        c._tfPreambleH = 0
        tab.build(c)
        tab.built = true
    end
end

local function SelectTab(idx)
    EnsureTabBuilt(idx)
    for i, tab in ipairs(tabs) do
        if i == idx then
            tab.content:Show()
            tab.btn:SetBackdropColor(0, 0.8, 1, 0.18)
            tab.btn.lbl:SetTextColor(1, 1, 1)
            activeTab = i
        else
            tab.content:Hide()
            tab.btn:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
            tab.btn.lbl:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

-- =============================================================================
-- BUILD
-- =============================================================================

local function Build()
    local PANEL_W = 540
    local PANEL_H = 560
    local TAB_H   = 28
    local CONTENT_TOP = -TAB_H - 38  -- below title bar and tab bar

    -- Main frame
    local frame = CreateFrame("Frame", "TurboFaceOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(PANEL_W, PANEL_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    Backdrop(frame, 0.05, 0.05, 0.05, 0.97)
    panelFrame = frame

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    Backdrop(titleBar, 0, 0.8, 1, 0.10, 0, 0.8, 1)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    title:SetText("|cff00ccffTurbo|cffffffffFace|r  Config")
    StyleOptionsOutline(title, 13)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
    tabBar:SetHeight(TAB_H)
    tabBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -32)
    tabBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -32)
    Backdrop(tabBar, 0.03, 0.03, 0.03, 1, 0, 0.8, 1)

    local tabBtnW = PANEL_W / #TAB_DEFS
    for i, def in ipairs(TAB_DEFS) do
        local btn = CreateFrame("Button", nil, tabBar, BackdropTemplateMixin and "BackdropTemplate")
        btn:SetHeight(TAB_H)
        btn:SetWidth(tabBtnW)
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (i-1)*tabBtnW, 0)
        Backdrop(btn, 0.08, 0.08, 0.08, 0.9, 0.12, 0.12, 0.12)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(def.name)
        lbl:SetTextColor(0.6, 0.6, 0.6)
        btn.lbl = lbl

        -- Content area for this tab
        local contentArea = CreateFrame("Frame", nil, frame)
        contentArea:SetPoint("TOPLEFT",     frame, "TOPLEFT",     8,   CONTENT_TOP)
        contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8,  8)
        contentArea:Hide()

        local sf, c = MakeScrollTab(contentArea, PANEL_W - 16, PANEL_H + CONTENT_TOP - 8)

        tabs[i] = { btn = btn, content = contentArea, sf = sf, scrollChild = c, build = def.build, built = false, name = def.name }

        local idx = i
        -- Sound lives here rather than in SelectTab so that the SelectTab(1)
        -- performed while building the panel is silent.
        btn:SetScript("OnClick", function()
            ns:PlayUISound("tab")
            SelectTab(idx)
        end)
    end

    -- Register with UISpecialFrames so Escape closes the panel
    tinsert(UISpecialFrames, "TurboFaceOptions")

    -- Show first tab by default
    SelectTab(1)
    frame:Hide()  -- hidden until opened

    -- Sound hooks are attached AFTER the initial Hide on purpose. A frame is
    -- visible from creation, so hooking earlier would fire OnHide on this very
    -- line and the first open would play close-then-open. Hooking the frame
    -- rather than ToggleGUI means every route makes the same sound: the slash
    -- command, the close button, Escape via UISpecialFrames, and the Blizzard
    -- options stub button.
    frame:SetScript("OnShow", function() ns:PlayUISound("panelOpen") end)
    frame:SetScript("OnHide", function() ns:PlayUISound("panelClose") end)
end

-- =============================================================================
-- BLIZZARD INTERFACE OPTIONS STUB
-- Registers a simple redirect panel in Escape -> Interface -> AddOns
-- so players can discover TurboFace there without us duplicating the whole UI
-- =============================================================================

local function RegisterBlizzardStub()
    local stub = CreateFrame("Frame", "TurboFaceBlizzOptions")

    local title = stub:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff00ccffTurbo|cffffffffFace|r")

    local desc = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Type |cff00ccff/tf|r to open the TurboFace config panel.")
    desc:SetTextColor(0.8, 0.8, 0.8)

    local btn = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    btn:SetSize(160, 24)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    btn:SetText("Open TurboFace Config")
    btn:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel or InterfaceOptionsFrame)
        ns:ToggleGUI()
    end)

    -- Classic Era 1.15.8 uses Settings API (not the old InterfaceOptions_AddCategory)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(stub, "TurboFace")
        Settings.RegisterAddOnCategory(category)
    end
end

-- Register at file load time
RegisterBlizzardStub()

-- =============================================================================
-- PUBLIC TOGGLE
-- Opens/closes the config panel, building it lazily on first use.
-- =============================================================================

function ns:ToggleGUI()
    if not panelFrame then Build() end
    if not panelFrame then return end
    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        panelFrame:Show()
    end
end
