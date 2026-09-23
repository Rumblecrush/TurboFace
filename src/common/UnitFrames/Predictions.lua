local _, ns = ...

-- =============================================================================
-- UNIT FRAME PREDICTION OVERLAYS
-- =============================================================================
-- Consumer-side rendering for the two prediction engines. Combat/DotPrediction.lua and
-- Combat/HealPrediction.lua own the data and are UI-independent; this file only draws
-- their output directly onto Blizzard's player/target/ToT/pet/party health bars.
-- TurboFace Unit Frames styling may be completely disabled.
--
-- Split out of UnitFrames/UnitFrames.lua, which sits near Lua 5.1's 200-local main-chunk
-- ceiling (ARCHITECTURE 12.0). Both sections were already self-contained
-- do-blocks whose only dependencies on the parent file were `UF` and
-- GetPartyHealthBar, so this move is a relocation, not a rewrite.
--
-- LOAD ORDER: must load AFTER Combat/DotPrediction.lua and Combat/HealPrediction.lua, because
-- the blocks below call RegisterConsumer at file scope, and AFTER UnitFrames/UnitFrames.lua,
-- which creates ns.UF.
-- =============================================================================

local UF = ns.UF
if not UF then return end

-- Custom prediction textures are a UnitFrame-provider capability. Classic's
-- readable renderer enables them; Forever's protected/native provider leaves
-- Blizzard's own secret-safe prediction layers authoritative.
if ns.UnitFrameProviderAllowsCustomPredictions and not ns.UnitFrameProviderAllowsCustomPredictions() then
    function UF:InitDotPrediction() end
    function UF:UpdateDotPrediction() end
    function UF:InitHealPrediction() end
    function UF:UpdateHealPrediction() end
    return
end

-- =============================================================================
-- DoT PREDICTION OVERLAY (target / ToT)
--
-- The purple region sits inside the health fill and represents health already
-- committed to damage-over-time effects. Geometry comes from
-- ns.DotPrediction:GetBarRegion so the nameplate and unit frame versions cannot
-- drift apart.
--
-- These bars are Blizzard's, so the texture is a child of the status bar and is
-- only ever positioned -- never shown or hidden via the frame itself, and never
-- re-parented. Positioning a texture we created is not a protected action.
-- =============================================================================
do
    local DOT_BARS = {
        { get = function() return TargetFrameHealthBar end, unit = "target" },
        { get = function() return TargetFrameToTHealthBar end, unit = "targettarget" },
    }

    local function EnsureDotTexture(bar)
        if not bar then return nil end
        if bar._tfDotBar then return bar._tfDotBar end
        if bar.CreateTexture then
            -- Opaque underlay, same reason as the nameplate path: without it
            -- the translucent region composites against the bar's own colour,
            -- so the purple reads differently on a yellow neutral target than
            -- on a red hostile one. Sublevel 2 sits just under the region.
            local bg = bar:CreateTexture(nil, "ARTWORK", nil, 2)
            bg:SetTexture(ns.c_texture or "Interface\\TargetingFrame\\UI-StatusBar")
            bg:SetVertexColor(0, 0, 0, 1)
            bg:Hide()
            bar._tfDotBarBG = bg

            local tex = bar:CreateTexture(nil, "ARTWORK", nil, 3)
            tex:SetTexture(ns.c_texture or "Interface\\TargetingFrame\\UI-StatusBar")
            tex:SetVertexColor(0.847, 0.706, 0.973, 0.75)
            tex:Hide()
            bar._tfDotBar = tex
            return tex
        end
        return nil
    end

    local function UpdateDotBar(bar, unit)
        local DP = ns.DotPrediction
        if not bar or not DP or not DP.GetBarRegion then return end

        if not DP:ShowOnUnitFrames(unit) then
            local tex = bar._tfDotBar
            if tex and tex:IsShown() then tex:Hide() end
            if bar._tfDotBarBG and bar._tfDotBarBG:IsShown() then bar._tfDotBarBG:Hide() end
            bar._tfDotOffset, bar._tfDotWidth = nil, nil
            return
        end

        -- Target/ToT are Blizzard-owned. If this feature is enabled for the first
        -- time during combat, defer first-time texture creation until combat ends.
        if not bar._tfDotBar and InCombatLockdown and InCombatLockdown() then return end
        local tex = EnsureDotTexture(bar)
        if not tex then return end

        if not UnitExists(unit) then
            if tex:IsShown() then tex:Hide() end
            if bar._tfDotBarBG and bar._tfDotBarBG:IsShown() then bar._tfDotBarBG:Hide() end
            return
        end

        -- Third return is the lethal flag: the projected DoT damage meets or
        -- exceeds current health, i.e. the target dies to ticks already out.
        local offset, width, lethal = DP:GetBarRegion(unit, bar:GetWidth())
        if not offset then
            if tex:IsShown() then tex:Hide() end
            if bar._tfDotBarBG and bar._tfDotBarBG:IsShown() then bar._tfDotBarBG:Hide() end
            bar._tfDotOffset, bar._tfDotWidth = nil, nil
            return
        end

        -- Color/alpha are live settings and may change while the geometry does not.
        -- Cache them independently so the normal health path does not churn
        -- SetVertexColor when neither presentation nor geometry changed.
        -- No extra cache key needed for lethality: a flip changes the colour,
        -- and the comparison below is on the colour itself.
        local r, g, b, a = DP:GetColor(lethal)
        if bar._tfDotR ~= r or bar._tfDotG ~= g or bar._tfDotB ~= b or bar._tfDotA ~= a then
            tex:SetVertexColor(r, g, b, a)
            bar._tfDotR, bar._tfDotG, bar._tfDotB, bar._tfDotA = r, g, b, a
        end
        if bar._tfDotOffset == offset and bar._tfDotWidth == width then
            if not tex:IsShown() then tex:Show() end
            local bg = bar._tfDotBarBG
            if bg and not bg:IsShown() then bg:Show() end
            return
        end
        bar._tfDotOffset, bar._tfDotWidth = offset, width

        -- Underlay tracks the region exactly; a mismatch would leave the bar
        -- colour showing along one edge.
        local bg = bar._tfDotBarBG
        if bg then
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
            bg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", offset, 0)
            bg:SetWidth(width)
            bg:Show()
        end

        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
        tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", offset, 0)
        tex:SetWidth(width)
        tex:Show()
    end

    function UF:_EnsureDotPredictionHooks()
        local DP = ns.DotPrediction
        if not DP or not DP:ShowOnUnitFrames() then return end
        if InCombatLockdown and InCombatLockdown() then return end

        -- Mark each Blizzard bar independently. This stays robust if ToT happens
        -- to be unavailable on the first pass and also avoids a permanent helper
        -- ticker just to discover it later.
        for i = 1, #DOT_BARS do
            local def = DOT_BARS[i]
            local bar = def.get()
            local unit = def.unit
            if bar and DP:ShowOnUnitFrames(unit) and bar.HookScript and not bar._tfDotPredictionHooked then
                bar:HookScript("OnValueChanged", function()
                    UpdateDotBar(bar, unit)
                end)
                bar._tfDotPredictionHooked = true
            end
        end
    end

    function UF:UpdateDotPrediction(unit)
        self:_EnsureDotPredictionHooks()
        for i = 1, #DOT_BARS do
            local def = DOT_BARS[i]
            if not unit or unit == def.unit then
                UpdateDotBar(def.get(), def.unit)
            end
        end
    end

    -- Aura changes come from the engine; health changes come from the bars'
    -- own OnValueChanged, which fires whenever Blizzard updates the fill.
    if ns.DotPrediction and ns.DotPrediction.RegisterConsumer then
        ns.DotPrediction:RegisterConsumer(function(unit)
            UF:UpdateDotPrediction(unit)
        end)
    end

    function UF:InitDotPrediction()
        -- No hooks or textures are installed while the consumer is disabled. If
        -- enabled later, the engine's RefreshAll() callback enters this path and
        -- installs the one-way health hooks at that point.
        self:UpdateDotPrediction()
    end
end


-- =============================================================================
-- HEAL PREDICTION OVERLAYS (player / target / ToT / pet / party)
--
-- Direct-heal and next-HoT-tick data comes from ns.HealPrediction. This renderer
-- only stacks colored textures from the current health edge toward the right.
-- Optional overheal may extend beyond the normal bar boundary.
-- =============================================================================
do
    local HEAL_BARS = {
        { get = function() return PlayerFrameHealthBar end, unit = "player" },
        { get = function() return TargetFrameHealthBar end, unit = "target" },
        { get = function() return TargetFrameToTHealthBar end, unit = "targettarget" },
        { get = function() return PetFrameHealthBar end, unit = "pet" },
        { get = function() return UF.GetPartyHealthBar(1) end, unit = "party1" },
        { get = function() return UF.GetPartyHealthBar(2) end, unit = "party2" },
        { get = function() return UF.GetPartyHealthBar(3) end, unit = "party3" },
        { get = function() return UF.GetPartyHealthBar(4) end, unit = "party4" },
    }

    local function HideHealPool(bar)
        local pool = bar and bar._tfHealPredictionPool
        if not pool then return end
        for i = 1, #pool do
            if pool[i]:IsShown() then pool[i]:Hide() end
        end
        bar._tfHealPredictionShown = 0
    end

    local function EnsureHealPool(bar, count)
        if not bar or not bar.CreateTexture then return nil end
        local pool = bar._tfHealPredictionPool
        if not pool then
            pool = {}
            bar._tfHealPredictionPool = pool
        end
        while #pool < count do
            if InCombatLockdown and InCombatLockdown() then break end
            local tex = bar:CreateTexture(nil, "ARTWORK", nil, 4)
            tex:SetTexture(ns.c_texture or "Interface\\TargetingFrame\\UI-StatusBar")
            tex:Hide()
            pool[#pool + 1] = tex
        end
        return pool
    end

    local function UpdateHealBar(bar, unit)
        local HP = ns.HealPrediction
        if not bar or not HP or not HP.GetSegments then return end

        if not HP:ShowOnUnit(unit) then
            HideHealPool(bar)
            return
        end

        if not UnitExists(unit) then
            HideHealPool(bar)
            return
        end

        local maxHealth = UnitHealthMax(unit) or 0
        if maxHealth <= 0 then
            HideHealPool(bar)
            return
        end

        local segments = HP:GetSegments(unit)
        local maxSegments = HP:GetMaxSegments()
        local pool = EnsureHealPool(bar, maxSegments)
        if not pool or #pool == 0 then return end

        local barWidth = bar:GetWidth() or 0
        if barWidth <= 0 then
            HideHealPool(bar)
            return
        end

        local health = UnitHealth(unit) or 0
        if health < 0 then health = 0 end
        if health > maxHealth then health = maxHealth end

        local overheal = HP:GetOverhealFraction()
        local maxAllowedWidth = barWidth * (1 + overheal)
        local drawX = barWidth * (health / maxHealth)
        local available = maxAllowedWidth - drawX
        local minAmount = maxHealth * HP:GetMinFraction()
        local shown = 0

        for i = 1, #segments do
            if shown >= maxSegments or available <= 0 then break end
            local seg = segments[i]
            local amount = seg and tonumber(seg.amount) or 0
            if amount > 0 and amount >= minAmount then
                local intendedWidth = barWidth * (amount / maxHealth)
                local actualWidth = math.min(intendedWidth, available)
                if actualWidth >= 0.5 then
                    shown = shown + 1
                    local tex = pool[shown]
                    if not tex then break end

                    local r, g, b, a = HP:GetColor(seg)
                    if tex._tfR ~= r or tex._tfG ~= g or tex._tfB ~= b or tex._tfA ~= a then
                        tex:SetVertexColor(r, g, b, a)
                        tex._tfR, tex._tfG, tex._tfB, tex._tfA = r, g, b, a
                    end

                    if tex._tfX ~= drawX or tex._tfWidth ~= actualWidth or tex._tfHeight ~= bar:GetHeight() then
                        tex:ClearAllPoints()
                        tex:SetPoint("TOPLEFT", bar, "TOPLEFT", drawX, 0)
                        tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", drawX, 0)
                        tex:SetWidth(actualWidth)
                        tex._tfX, tex._tfWidth, tex._tfHeight = drawX, actualWidth, bar:GetHeight()
                    end
                    if not tex:IsShown() then tex:Show() end
                    drawX = drawX + actualWidth
                    available = available - actualWidth
                end
            end
        end

        for i = shown + 1, #pool do
            if pool[i]:IsShown() then pool[i]:Hide() end
        end
        bar._tfHealPredictionShown = shown
    end

    function UF:_EnsureHealPredictionHooks()
        local HP = ns.HealPrediction
        if not HP then return end
        if InCombatLockdown and InCombatLockdown() then return end

        for i = 1, #HEAL_BARS do
            local def = HEAL_BARS[i]
            local bar = def.get()
            local unit = def.unit
            if bar and HP:ShowOnUnit(unit) then
                EnsureHealPool(bar, HP:GetMaxSegments())
                if bar.HookScript and not bar._tfHealPredictionHooked then
                    bar:HookScript("OnValueChanged", function()
                        UpdateHealBar(bar, unit)
                    end)
                    bar._tfHealPredictionHooked = true
                end
            end
        end
    end

    function UF:UpdateHealPrediction(unit)
        self:_EnsureHealPredictionHooks()
        for i = 1, #HEAL_BARS do
            local def = HEAL_BARS[i]
            if not unit or unit == def.unit then
                UpdateHealBar(def.get(), def.unit)
            end
        end
    end

    if ns.HealPrediction and ns.HealPrediction.RegisterConsumer then
        ns.HealPrediction:RegisterConsumer(function(unit)
            UF:UpdateHealPrediction(unit)
        end)
    end

    function UF:InitHealPrediction()
        self:UpdateHealPrediction()
    end
end
