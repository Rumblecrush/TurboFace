local _, ns = ...

local compat = ns.Compat
if not (compat and compat.IS_TARGET_FOREVER_BUILD == true) then return end

-- =============================================================================
-- Forever Swing Timer substrate
--
-- The shared SwingTimers engine owns timer policy and rendering. Forever owns
-- the sanctioned PLAYER_SWING clock, opaque hostile attack-speed restrictions,
-- and Character/PaperDoll damage-row capture used by standalone weapon text.
-- =============================================================================

local Forever = {}

function Forever:IsSupported()
    return true
end

function Forever:UsesPlayerSwingEvent()
    return true
end

function Forever:CanReadTargetAttackSpeed()
    return false
end

function Forever:CanReadNameplateAttackSpeed()
    return false
end

function Forever:UsesThreatSituationEngagement()
    return false
end

function Forever:UsesCharacterDamageCapture()
    return true
end

function Forever:Attach(ST)
    if type(ST) ~= "table" or ST._foreverSwingTimerCaptureAttached then return end
    ST._foreverSwingTimerCaptureAttached = true

    -- Forever/Mainline's Character stat sheet already owns the display formatting
    -- for the Damage row. Prefer the formatted text argument Blizzard passes to
    -- PaperDollFrame_SetLabelAndText(DAMAGE, value, ...); this intercepts the exact
    -- visible range before it is written into the pooled FontString and avoids
    -- depending on FontString:GetText() being readable under secret-value rules.
    -- A post-PaperDollFrame_SetDamage read remains as a fallback/probe. Hooks are
    -- installed lazily because Blizzard_UIPanels_Game may not exist at startup.
    function ST:CapturePaperDollDamageText(text, source)
        self.paperDollDamageCaptureAttempts = (self.paperDollDamageCaptureAttempts or 0) + 1
        self.paperDollDamageTextSecret = ns.API.IsSecretValue and ns.API.IsSecretValue(text) or false
        if self.paperDollDamageTextSecret then
            self.paperDollDamageReject = "text-secret"
            return false
        end
        if ns.API.CanAccessValue and not ns.API.CanAccessValue(text) then
            self.paperDollDamageReject = "text-inaccessible"
            return false
        end
        if type(text) ~= "string" then
            self.paperDollDamageReject = "text-not-string"
            return false
        end
        if text == "" then
            self.paperDollDamageReject = "text-empty"
            return false
        end

        -- PaperDollFrame may color the range green/red for temporary modifiers.
        -- The swing bar owns its own font color, so cache the visible range only.
        local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if clean == "" then
            self.paperDollDamageReject = "clean-empty"
            return false
        end

        self.paperDollDamageText = clean
        self.paperDollDamageAt = GetTime and GetTime() or 0
        self.paperDollDamageCaptureSource = source or "unknown"
        self.paperDollDamageReject = nil
        self.damageTextSource = "paperdoll"
        if self._SetCapturedMainDamageText then
            self:_SetCapturedMainDamageText(clean)
        end
        return true
    end

    function ST:CapturePaperDollDamage(statFrame, unit)
        self.paperDollDamageSetDamageCalls = (self.paperDollDamageSetDamageCalls or 0) + 1
        if ns.API.IsSecretValue and ns.API.IsSecretValue(unit) then
            self.paperDollPostRead = "unit-secret"
            return
        end
        if unit and unit ~= "player" then
            self.paperDollPostRead = "non-player"
            return
        end
        local value = statFrame and statFrame.Value
        if not value or type(value.GetText) ~= "function" then
            self.paperDollPostRead = "missing-value"
            return
        end

        local ok, text = pcall(value.GetText, value)
        if not ok then
            self.paperDollPostRead = "gettext-error"
            return
        end
        if ns.API.IsSecretValue and ns.API.IsSecretValue(text) then
            self.paperDollPostRead = "text-secret"
            return
        end
        if ns.API.CanAccessValue and not ns.API.CanAccessValue(text) then
            self.paperDollPostRead = "text-inaccessible"
            return
        end
        self.paperDollPostRead = "readable"
        self:CapturePaperDollDamageText(text, "value-gettext")
    end

    function ST:InstallPaperDollDamageCapture()
        if type(hooksecurefunc) ~= "function" then return false end

        if not self._paperDollLabelHooked and type(_G.PaperDollFrame_SetLabelAndText) == "function" then
            hooksecurefunc("PaperDollFrame_SetLabelAndText", function(_, label, text)
                if ns.API.IsSecretValue and ns.API.IsSecretValue(label) then return end
                if label ~= _G.DAMAGE then return end
                ST.paperDollDamageLabelCalls = (ST.paperDollDamageLabelCalls or 0) + 1
                ST:CapturePaperDollDamageText(text, "label-arg")
            end)
            self._paperDollLabelHooked = true
        end

        if not self._paperDollDamageHooked and type(_G.PaperDollFrame_SetDamage) == "function" then
            hooksecurefunc("PaperDollFrame_SetDamage", function(statFrame, unit)
                ST:CapturePaperDollDamage(statFrame, unit)
            end)
            self._paperDollDamageHooked = true
        end

        return self._paperDollLabelHooked == true or self._paperDollDamageHooked == true
    end


    -- Forever build 69913 exposes the old Mainline PaperDoll globals, but its live
    -- Character sheet does not actually route stat rendering through those globals.
    -- Resolve the visible stat row directly instead.  This is intentionally a
    -- one-shot/tree-scan operation used on CharacterFrame show and diagnostics, not
    -- a cadence/per-frame path.
    function ST:ScanCharacterStatsDamage(verbose)
        self.paperDollPaneScans = (self.paperDollPaneScans or 0) + 1
        self.paperDollPaneStatus = nil
        self.paperDollPaneDamageRow = nil
        self.paperDollPaneCandidateCount = 0
        self.paperDollPaneDebugRows = {}

        local root = _G.CharacterStatsPane
        if not root and _G.PaperDollFrame then
            root = _G.PaperDollFrame.CharacterStatsPane or _G.PaperDollFrame.StatsPane
        end
        if not root then
            self.paperDollPaneStatus = "missing-pane"
            return false
        end

        local function ReadText(obj)
            if not obj or type(obj.GetText) ~= "function" then return nil, "no-gettext" end
            local ok, text = pcall(obj.GetText, obj)
            if not ok then return nil, "gettext-error" end
            if ns.API.IsSecretValue and ns.API.IsSecretValue(text) then return nil, "text-secret" end
            if ns.API.CanAccessValue and not ns.API.CanAccessValue(text) then return nil, "text-inaccessible" end
            if type(text) ~= "string" then return nil, "not-string" end
            return text, nil
        end

        local function CleanText(text)
            if type(text) ~= "string" then return nil end
            return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        end

        local function IsDamageLabel(text)
            text = CleanText(text)
            if not text or text == "" then return false end
            local localized = _G.DAMAGE
            if type(localized) == "string" and text == localized then return true end
            return text:lower():gsub(":$", "") == "damage"
        end

        local function LooksLikeRange(text)
            text = CleanText(text)
            if not text or text == "" then return false end
            -- Character-sheet ranges can contain commas/decimals depending on
            -- locale/modifiers.  We only use this after finding a Damage-labelled
            -- row, so a deliberately broad numeric-range shape is appropriate.
            return text:match("[%d%.,]+%s*%-%s*[%d%.,]+") ~= nil
        end

        local function TryCaptureRow(frame, path)
            if not frame then return false end
            local ok, labelObj, valueObj = pcall(function()
                return frame.Label or frame.label or frame.Name or frame.name,
                       frame.Value or frame.value or frame.ValueText or frame.valueText
            end)
            if ok and labelObj and valueObj then
                local labelText, labelErr = ReadText(labelObj)
                local valueText, valueErr = ReadText(valueObj)
                if verbose and labelText and #self.paperDollPaneDebugRows < 30 then
                    self.paperDollPaneDebugRows[#self.paperDollPaneDebugRows + 1] = {
                        path = path, label = CleanText(labelText), value = CleanText(valueText or ("<" .. tostring(valueErr or "nil") .. ">")),
                    }
                end
                if IsDamageLabel(labelText) then
                    self.paperDollPaneDamageRow = path
                    if valueText and valueText ~= "" then
                        if self:CapturePaperDollDamageText(valueText, "stats-pane-row") then
                            self.paperDollPaneStatus = "captured-row"
                            return true
                        end
                    end
                    self.paperDollPaneStatus = "damage-row-" .. tostring(valueErr or labelErr or "empty")
                end
            end

            if type(frame.GetRegions) == "function" then
                local rok, regions = pcall(function() return { frame:GetRegions() } end)
                if rok and regions then
                    local texts = {}
                    local hasDamage = false
                    for i = 1, #regions do
                        local region = regions[i]
                        if region and type(region.GetText) == "function" then
                            local text = ReadText(region)
                            if text then
                                texts[#texts + 1] = text
                                if IsDamageLabel(text) then hasDamage = true end
                            end
                        end
                    end
                    if hasDamage then
                        self.paperDollPaneDamageRow = path
                        for i = 1, #texts do
                            if LooksLikeRange(texts[i]) and self:CapturePaperDollDamageText(texts[i], "stats-pane-regions") then
                                self.paperDollPaneStatus = "captured-regions"
                                return true
                            end
                        end
                        if not self.paperDollPaneStatus then self.paperDollPaneStatus = "damage-regions-no-range" end
                    end
                end
            end
            return false
        end

        -- Current Mainline CharacterStatsPane uses a pooled set of stat-row frames.
        -- Prefer the active pool directly when Forever exposes it; pooled widgets
        -- can be reparented/managed in ways that make a descendant-only walk less
        -- reliable. ObjectPoolMixin:EnumerateActive() has existed since 7.2.
        local pool = root.statsFramePool
        if pool and type(pool.EnumerateActive) == "function" then
            self.paperDollPanePool = true
            local ok, iterator = pcall(pool.EnumerateActive, pool)
            if ok and type(iterator) == "function" then
                local index = 0
                for frame in iterator do
                    index = index + 1
                    self.paperDollPaneCandidateCount = self.paperDollPaneCandidateCount + 1
                    if TryCaptureRow(frame, "CharacterStatsPane.statsFramePool[" .. index .. "]") then return true end
                end
            end
        else
            self.paperDollPanePool = false
        end

        local queue = { { frame = root, path = "CharacterStatsPane", depth = 0 } }
        local seen = {}
        local head = 1
        local maxNodes = 500
        while head <= #queue and head <= maxNodes do
            local entry = queue[head]
            head = head + 1
            local frame = entry.frame
            if frame and not seen[frame] then
                seen[frame] = true
                self.paperDollPaneCandidateCount = self.paperDollPaneCandidateCount + 1
                if TryCaptureRow(frame, entry.path) then return true end

                if entry.depth < 8 and type(frame.GetChildren) == "function" then
                    local ok, children = pcall(function() return { frame:GetChildren() } end)
                    if ok and children then
                        for i = 1, #children do
                            local child = children[i]
                            if child and not seen[child] then
                                local name = nil
                                if type(child.GetName) == "function" then
                                    local nok, n = pcall(child.GetName, child)
                                    if nok and type(n) == "string" and n ~= "" then name = n end
                                end
                                queue[#queue + 1] = {
                                    frame = child,
                                    path = entry.path .. "/" .. (name or ("child" .. i)),
                                    depth = entry.depth + 1,
                                }
                            end
                        end
                    end
                end
            end
        end

        if not self.paperDollPaneStatus then self.paperDollPaneStatus = "no-damage-row" end
        if verbose then
            print("|cff00ccffTFSwing PaperDollProbe|r status=", tostring(self.paperDollPaneStatus),
                  "| scanned=", tostring(self.paperDollPaneCandidateCount),
                  "| pool=", tostring(self.paperDollPanePool == true),
                  "| row=", tostring(self.paperDollPaneDamageRow),
                  "| captured=", tostring(self.paperDollDamageText))
            for i = 1, #(self.paperDollPaneDebugRows or {}) do
                local row = self.paperDollPaneDebugRows[i]
                print("  PDR[" .. i .. "]", tostring(row.label), "=", tostring(row.value), "@", tostring(row.path))
            end
        end
        return self.paperDollDamageText ~= nil
    end


    -- Forever build 69913 can render Character-sheet combat stats outside the
    -- legacy CharacterStatsPane row pool.  As a second-stage probe/capture, walk
    -- the visible CharacterFrame tree and inspect readable text regions.  Pair a
    -- localized Damage label with the nearest visible numeric range on the same
    -- visual row.  This runs only when the Character panel is shown or when the
    -- user explicitly invokes /tfswing paperdollprobe; it is never a cadence path.
    function ST:ScanCharacterFrameDamage(verbose)
        self.paperDollFrameScans = (self.paperDollFrameScans or 0) + 1
        self.paperDollFrameStatus = nil
        self.paperDollFrameNodeCount = 0
        self.paperDollFrameTextCount = 0
        self.paperDollFrameDamageLabel = nil
        self.paperDollFrameRange = nil
        self.paperDollFrameDebugTexts = {}

        local root = _G.CharacterFrame
        if not root then
            self.paperDollFrameStatus = "missing-character-frame"
            return false
        end

        local function ReadText(obj)
            if not obj or type(obj.GetText) ~= "function" then return nil, "no-gettext" end
            local ok, text = pcall(obj.GetText, obj)
            if not ok then return nil, "gettext-error" end
            if ns.API.IsSecretValue and ns.API.IsSecretValue(text) then return nil, "text-secret" end
            if ns.API.CanAccessValue and not ns.API.CanAccessValue(text) then return nil, "text-inaccessible" end
            if type(text) ~= "string" then return nil, "not-string" end
            return text, nil
        end

        local function CleanText(text)
            if type(text) ~= "string" then return nil end
            return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        end

        local function IsDamageLabel(text)
            text = CleanText(text)
            if not text or text == "" then return false end
            local localized = _G.DAMAGE
            if type(localized) == "string" and text:gsub(":$", "") == localized:gsub(":$", "") then return true end
            return text:lower():gsub(":$", "") == "damage"
        end

        local function ExtractRange(text)
            text = CleanText(text)
            if not text or text == "" then return nil end
            return text:match("([%d%.,]+%s*%-%s*[%d%.,]+)")
        end

        local function GetCenterSafe(obj)
            if not obj or type(obj.GetCenter) ~= "function" then return nil, nil end
            local ok, x, y = pcall(obj.GetCenter, obj)
            if not ok then return nil, nil end
            if ns.API.CanAccessValue then
                if x ~= nil and not ns.API.CanAccessValue(x) then x = nil end
                if y ~= nil and not ns.API.CanAccessValue(y) then y = nil end
            end
            if type(x) ~= "number" then x = nil end
            if type(y) ~= "number" then y = nil end
            return x, y
        end

        local texts, seenTextObjects = {}, {}
        local function AddTextObject(obj, path, parentPath)
            if not obj or seenTextObjects[obj] then return end
            seenTextObjects[obj] = true
            local text, err = ReadText(obj)
            text = CleanText(text)
            if not text or text == "" then return end
            local x, y = GetCenterSafe(obj)
            local entry = { obj=obj, text=text, path=path, parentPath=parentPath, x=x, y=y, err=err }
            texts[#texts + 1] = entry
            self.paperDollFrameTextCount = self.paperDollFrameTextCount + 1

            local inlineRange = ExtractRange(text)
            if IsDamageLabel(text) and inlineRange then
                self.paperDollFrameDamageLabel = path
                self.paperDollFrameRange = path
                if self:CapturePaperDollDamageText(inlineRange, "character-frame-inline") then
                    self.paperDollFrameStatus = "captured-inline"
                end
            end
        end

        local queue = { { frame=root, path="CharacterFrame", depth=0 } }
        local seenFrames = {}
        local head, maxNodes = 1, 1600
        while head <= #queue and self.paperDollFrameNodeCount < maxNodes do
            local entry = queue[head]
            head = head + 1
            local frame = entry.frame
            if frame and not seenFrames[frame] then
                seenFrames[frame] = true
                self.paperDollFrameNodeCount = self.paperDollFrameNodeCount + 1

                AddTextObject(frame, entry.path, entry.path)

                if type(frame.GetRegions) == "function" then
                    local ok, regions = pcall(function() return { frame:GetRegions() } end)
                    if ok and regions then
                        for i = 1, #regions do
                            local region = regions[i]
                            if region then
                                local rname
                                if type(region.GetName) == "function" then
                                    local nok, name = pcall(region.GetName, region)
                                    if nok and type(name) == "string" and name ~= "" then rname = name end
                                end
                                AddTextObject(region, entry.path .. "/" .. (rname or ("region" .. i)), entry.path)
                            end
                        end
                    end
                end

                if entry.depth < 12 and type(frame.GetChildren) == "function" then
                    local ok, children = pcall(function() return { frame:GetChildren() } end)
                    if ok and children then
                        for i = 1, #children do
                            local child = children[i]
                            if child and not seenFrames[child] then
                                local cname
                                if type(child.GetName) == "function" then
                                    local nok, name = pcall(child.GetName, child)
                                    if nok and type(name) == "string" and name ~= "" then cname = name end
                                end
                                queue[#queue + 1] = {
                                    frame=child,
                                    path=entry.path .. "/" .. (cname or ("child" .. i)),
                                    depth=entry.depth + 1,
                                }
                            end
                        end
                    end
                end
            end
        end

        if self.paperDollFrameStatus == "captured-inline" then
            return true
        end

        local labels, ranges = {}, {}
        for i = 1, #texts do
            local t = texts[i]
            if IsDamageLabel(t.text) then labels[#labels + 1] = t end
            local range = ExtractRange(t.text)
            if range then
                local copy = {}
                for k, v in pairs(t) do copy[k] = v end
                copy.range = range
                ranges[#ranges + 1] = copy
            end
        end

        local bestLabel, bestRange, bestScore
        for i = 1, #labels do
            local label = labels[i]
            for j = 1, #ranges do
                local range = ranges[j]
                local score
                if label.parentPath == range.parentPath then
                    score = 0
                elseif label.x and label.y and range.x and range.y then
                    local dy, dx = math.abs(label.y - range.y), math.abs(label.x - range.x)
                    -- Damage labels and values are normally horizontally separated
                    -- but vertically aligned. Reject unrelated ranges far away.
                    if dy <= 24 and dx <= 420 then score = dy * 20 + dx end
                end
                if score and (not bestScore or score < bestScore) then
                    bestLabel, bestRange, bestScore = label, range, score
                end
            end
        end

        if bestLabel and bestRange then
            self.paperDollFrameDamageLabel = bestLabel.path
            self.paperDollFrameRange = bestRange.path
            if self:CapturePaperDollDamageText(bestRange.range, "character-frame-nearest") then
                self.paperDollFrameStatus = "captured-nearest"
                return true
            end
        end

        -- Forever 69913's compact Character sheet can omit the readable "Damage"
        -- label entirely while still rendering the value inside the dedicated
        -- CharacterStatsPaneScrollBox.  Only accept this unlabeled layout when the
        -- stats scroll box contains exactly one numeric range.  That keeps the
        -- fallback tied to a Blizzard-owned stats surface without hard-coding the
        -- observed child/region indices or guessing among multiple range values.
        local statsRanges = {}
        for i = 1, #ranges do
            local range = ranges[i]
            if type(range.path) == "string"
                and range.path:find("/CharacterStatsPaneScrollBox/", 1, true)
            then
                statsRanges[#statsRanges + 1] = range
            end
        end
        if #labels == 0 and #statsRanges == 1 then
            local range = statsRanges[1]
            self.paperDollFrameRange = range.path
            if self:CapturePaperDollDamageText(range.range, "character-frame-single-stats-range") then
                self.paperDollFrameStatus = "captured-single-stats-range"
                return true
            end
        end

        self.paperDollFrameStatus = (#labels > 0) and "damage-label-no-readable-range" or "no-damage-label"

        if verbose then
            -- Print focused candidates first: Damage-like text and numeric ranges.
            local focused = {}
            for i = 1, #texts do
                local t = texts[i]
                if t.text:lower():find("damage", 1, true) or ExtractRange(t.text) then
                    focused[#focused + 1] = t
                end
            end
            local source = (#focused > 0) and focused or texts
            local limit = math.min(#source, 80)
            print("|cff00ccffTFSwing CharacterFrameProbe|r status=", tostring(self.paperDollFrameStatus),
                  "| nodes=", tostring(self.paperDollFrameNodeCount),
                  "| texts=", tostring(self.paperDollFrameTextCount),
                  "| labels=", tostring(#labels), "| ranges=", tostring(#ranges))
            for i = 1, limit do
                local t = source[i]
                print("  CFR[" .. i .. "]", tostring(t.text), "@", tostring(t.path),
                      "xy=", tostring(t.x), tostring(t.y))
            end
        end
        return false
    end

    function ST:InstallCharacterStatsPaneCapture()
        if self._characterStatsPaneHooked then return true end
        local frame = _G.CharacterFrame
        if not frame or type(frame.HookScript) ~= "function" then return false end
        frame:HookScript("OnShow", function()
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, function() if not ST:ScanCharacterStatsDamage(false) then ST:ScanCharacterFrameDamage(false) end end)
            else
                if not ST:ScanCharacterStatsDamage(false) then ST:ScanCharacterFrameDamage(false) end
            end
        end)
        self._characterStatsPaneHooked = true
        if type(frame.IsShown) == "function" and frame:IsShown() then
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(0, function() if not ST:ScanCharacterStatsDamage(false) then ST:ScanCharacterFrameDamage(false) end end)
            else
                if not ST:ScanCharacterStatsDamage(false) then ST:ScanCharacterFrameDamage(false) end
            end
        end
        return true
    end
end

function Forever:InstallCharacterDamageCapture(ST, eventFrame)
    self:Attach(ST)
    if type(ST) ~= "table" then return false end
    if eventFrame and type(eventFrame.RegisterEvent) == "function" then
        ns.API.RegisterEvent(eventFrame, "ADDON_LOADED")
    end
    ST:InstallPaperDollDamageCapture()
    ST:InstallCharacterStatsPaneCapture()
    if eventFrame and ST._paperDollDamageHooked and ST._paperDollLabelHooked and ST._characterStatsPaneHooked then
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
    return true
end

function Forever:RefreshCharacterDamageCapture(ST, eventFrame)
    return self:InstallCharacterDamageCapture(ST, eventFrame)
end

function Forever:RunCharacterDamageProbe(ST, msg)
    self:Attach(ST)
    if type(ST) ~= "table" then return false end
    local shouldProbe = (_G.CharacterFrame and _G.CharacterFrame:IsShown()) or msg == "paperdollprobe" or msg == "probe"
    if not shouldProbe then return false end
    ST:InstallCharacterStatsPaneCapture()
    local verboseProbe = msg == "paperdollprobe" or msg == "probe"
    local paneCaptured = ST:ScanCharacterStatsDamage(verboseProbe)
    if not paneCaptured then ST:ScanCharacterFrameDamage(verboseProbe) end
    return true
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("swingTimers", "forever-player-swing", Forever, 100)
end