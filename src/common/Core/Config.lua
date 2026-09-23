local addonName, ns = ...

-- TurboFace Config
-- Defaults, shared helpers, and the central CLEU dispatcher.

local version = ns.API.GetAddOnMetadata(addonName, "Version") or "0.8.0"

-- Minimal runtime strings only (no GUI labels needed)
ns.L = {
    Title        = "TurboFace v" .. version,
    BoostedBy    = "|cff00ccffTurbo|cffffffffFace|r v%s loaded  /tf for config",
    ConflictText = "|cff00ccffTurboFace|r has detected an incompatible nameplate addon: |cffff6666%s|r\n\nOnly one nameplate addon can be active at a time.",
    DisableIt    = "Disable It",
    DisableTP    = "Disable TurboFace",
}

-- =============================================================================
-- OPT-IN CPU PROFILER TARGET REGISTRY
-- =============================================================================
-- Modules register their externally-driven entry points here (OnEvent, cadence
-- ticks, CLEU consumers, deferred batch callbacks). Registration itself is only a
-- retained function reference; no timing wrapper runs during normal play.
-- Core/CPUProfiler.lua samples these functions only while /tf debug cpu start is active
-- and Blizzard script profiling has explicitly been enabled by the user.
ns.CPUProfileTargets = ns.CPUProfileTargets or {}
function ns.RegisterCPUProfileTarget(tag, fn, includeSubroutines)
    if type(tag) ~= "string" or tag == "" or type(fn) ~= "function" then return end
    ns.CPUProfileTargets[tag] = {
        fn = fn,
        -- Exclusive/self CPU is the safe default for attribution. Inclusive
        -- subroutine timing may be requested explicitly for a one-off aggregate
        -- target, but defaulting to it double-counts parent/child targets.
        includeSubroutines = includeSubroutines == true,
    }
end

-- =============================================================================
-- FONT & TEXTURE TABLES
-- =============================================================================

-- TurboFace does not ship font files. Public font choices are aliases for
-- Blizzard-owned FontObjects so the client chooses the correct localized font
-- file for the active alphabet/locale. The raw fallback is only used if a
-- FontObject is unexpectedly unavailable during very early loading.
ns.DEFAULT_FONT_PATH = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
ns.DEFAULT_FONT_NAME = "Blizzard Default"
ns.DEFAULT_TEXT_STYLE = "SHADOW"   -- "OUTLINE" | "SHADOW" | "NONE"

ns.Fonts = {
    { name = "Blizzard Default", fontObjects = { "GameFontNormal", "SystemFont_Shadow_Med1" } },
    { name = "Blizzard Narrow",  fontObjects = { "NumberFontNormalSmall", "NumberFontNormal", "PriceFont" } },
    { name = "Blizzard Quest",   fontObjects = { "QuestFont_Large", "QuestFont_Shadow_Small", "QuestFont" } },
    { name = "Blizzard Combat",  fontObjects = { "NumberFont_Outline_Huge", "CombatTextFont", "DamageTextFont" } },
}

local FONT_ALIASES = {
    ["Friz Quadrata"]     = "Blizzard Default",
    ["Friz Quadrata TT"]  = "Blizzard Default",
    ["Arial Narrow"]      = "Blizzard Narrow",
    ["Morpheus"]          = "Blizzard Quest",
    ["Skurri"]            = "Blizzard Combat",
    ["Blizzard Default"]  = "Blizzard Default",
    ["Blizzard Narrow"]   = "Blizzard Narrow",
    ["Blizzard Quest"]    = "Blizzard Quest",
    ["Blizzard Combat"]   = "Blizzard Combat",
}

-- Typography is intentionally closed over TurboFace's four Blizzard-owned
-- choices. Unknown names (including media registered by other addons) collapse
-- to Blizzard Default so a public profile never depends on another addon's font.
function ns:NormalizeFontName(name)
    if type(name) ~= "string" or name == "" or name == "INHERIT" then
        return self.DEFAULT_FONT_NAME
    end
    return FONT_ALIASES[name] or self.DEFAULT_FONT_NAME
end

function ns:GetBlizzardFontPath(name)
    name = self:NormalizeFontName(name)
    for i = 1, #self.Fonts do
        local entry = self.Fonts[i]
        if entry.name == name then
            local candidates = entry.fontObjects or {}
            for j = 1, #candidates do
                local fontObject = _G[candidates[j]]
                if fontObject and fontObject.GetFont then
                    local path = fontObject:GetFont()
                    if path and path ~= "" then return path end
                end
            end
            return self.DEFAULT_FONT_PATH
        end
    end
    return self.DEFAULT_FONT_PATH
end

-- Font resolution is fully Blizzard-native and independent of LibSharedMedia.
-- Keep both dot- and colon-style helpers because existing feature code uses both.
function ns.GetFont(name)
    return ns:GetBlizzardFontPath(name)
end

function ns:GetFontPath(name)
    return self:GetBlizzardFontPath(name)
end

function ns.GetFontOptions()
    local options = {}
    for i, entry in ipairs(ns.Fonts or {}) do
        options[i] = { name = entry.name, value = entry.name }
    end
    return options
end

-- Feature-local resolver. There is intentionally no addon-wide font/style
-- preference anymore. Nested feature tables may expose `font` / `textStyle`;
-- otherwise callers receive deterministic TurboFace defaults.
function ns:ResolveFont(moduleKey)
    local db = TurboFaceDB
    if db and moduleKey then
        local m = db[moduleKey]
        if type(m) == "table" and m.font and m.font ~= "INHERIT" then
            return self:NormalizeFontName(m.font)
        end
    end
    return self.DEFAULT_FONT_NAME
end

function ns:ResolveTextStyle(moduleKey)
    local db = TurboFaceDB
    if db and moduleKey then
        local m = db[moduleKey]
        if type(m) == "table" and m.textStyle and m.textStyle ~= "INHERIT" then
            return m.textStyle
        end
    end
    return self.DEFAULT_TEXT_STYLE
end

-- TurboFace-owned supplemental nameplate text (currently NPC titles) uses
-- a fixed heavier drop shadow. Blizzard-owned unit names use the independent
-- FontObject shadow amendment in Nameplates/NativeNameStyle.lua instead.
ns.NP_NAME_TEXT_STYLE = "NAMEPLATE_SHADOW"
ns.NP_TITLE_FONT_SIZE = 8
ns.NP_NATIVE_NAME_FALLBACK_SIZE = 10

-- Classic Era's native Blizzard text establishes shadow styling through the
-- FontObject inheritance chain (for example PlayerName -> GameFontNormalSmall
-- -> SystemFont_Shadow_Small). Direct SetShadow* calls on arbitrary FontStrings
-- can report the requested values without producing the expected visible
-- result. TurboFace therefore mirrors Blizzard's ownership model: each unique
-- face/size/style combination gets a cached runtime FontObject, and FontStrings
-- receive that complete presentation through SetFontObject().
local styledFontObjects = {}
local styledFontObjectSerial = 0

local function StyledFontKey(path, size, style)
    return tostring(path or "") .. "\031" .. tostring(size or "") .. "\031" .. tostring(style or "")
end

local function ConfigureStyledFontObject(obj, path, size, style)
    if not obj then return false end

    local flag = (style == "OUTLINE" and "OUTLINE")
              or (style == "THICKOUTLINE" and "THICKOUTLINE")
              or ""
    local ok = obj.SetFont and obj:SetFont(path or ns.DEFAULT_FONT_PATH, size, flag)
    if ok == false and obj.SetFont then
        ok = obj:SetFont(ns.DEFAULT_FONT_PATH, size, flag)
    end
    if ok == false then return false end

    if style == "SHADOW" then
        -- Use Blizzard's native FontObject shadow mechanism with TurboFace's
        -- slightly stronger 2,-2 geometry. SystemFont_Shadow_Small itself
        -- uses 1,-1; only the offset is intentionally stronger here.
        if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 1) end
        if obj.SetShadowOffset then obj:SetShadowOffset(2, -2) end
    elseif style == "NAMEPLATE_SHADOW" then
        if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 1) end
        if obj.SetShadowOffset then obj:SetShadowOffset(2, -2) end
    else
        if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 0) end
        if obj.SetShadowOffset then obj:SetShadowOffset(0, 0) end
    end
    return true
end

local function GetStyledFontObject(path, size, style)
    if not CreateFont then return nil end
    path = path or ns.DEFAULT_FONT_PATH
    style = style or ns.DEFAULT_TEXT_STYLE
    local key = StyledFontKey(path, size, style)
    local obj = styledFontObjects[key]
    if obj then return obj end

    styledFontObjectSerial = styledFontObjectSerial + 1
    obj = CreateFont("TurboFaceStyledFont" .. styledFontObjectSerial)
    if not ConfigureStyledFontObject(obj, path, size, style) then return nil end
    styledFontObjects[key] = obj
    return obj
end

-- SetFontObject can carry inherited FontObject attributes beyond face/size.
-- Preserve the per-FontString presentation properties that TurboFace features
-- may already own so switching typography never changes their color/alignment.
local function ApplyStyledFontObject(fontString, fontObject)
    if not (fontString and fontObject and fontString.SetFontObject) then return false end

    local r, g, b, a
    if fontString.GetTextColor and fontString.SetTextColor then
        r, g, b, a = fontString:GetTextColor()
    end
    local justifyH = fontString.GetJustifyH and fontString:GetJustifyH() or nil
    local justifyV = fontString.GetJustifyV and fontString:GetJustifyV() or nil
    local spacing = fontString.GetSpacing and fontString:GetSpacing() or nil

    fontString:SetFontObject(fontObject)

    if r ~= nil then fontString:SetTextColor(r, g, b, a) end
    if justifyH and fontString.SetJustifyH then fontString:SetJustifyH(justifyH) end
    if justifyV and fontString.SetJustifyV then fontString:SetJustifyV(justifyV) end
    if spacing ~= nil and fontString.SetSpacing then fontString:SetSpacing(spacing) end
    return true
end

-- Apply face/size + local text style in one call. `moduleKey` is only a lookup
-- convenience for nested feature tables; callers with flat settings may pass
-- an explicit font path and styleOverride instead.
function ns:StyleFont(fontString, fontPath, size, moduleKey, styleOverride)
    if not fontString then return end
    if not fontPath then
        fontPath = self:GetFontPath(self:ResolveFont(moduleKey))
    end
    fontPath = fontPath or self.DEFAULT_FONT_PATH
    local style = styleOverride or self:ResolveTextStyle(moduleKey)

    local fontObject = GetStyledFontObject(fontPath, size, style)
    if fontObject and ApplyStyledFontObject(fontString, fontObject) then
        return
    end

    -- Defensive fallback for a branch that cannot create/assign FontObjects.
    -- The public Classic Era path should normally use the FontObject route.
    local flag = (style == "OUTLINE" and "OUTLINE")
              or (style == "THICKOUTLINE" and "THICKOUTLINE")
              or ""
    fontString:SetFont(fontPath, size, flag)
    if not fontString:GetFont() then
        fontString:SetFont(self.DEFAULT_FONT_PATH, size, flag)
    end
    if style == "SHADOW" then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(2, -2) end
    elseif style == "NAMEPLATE_SHADOW" then
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 1) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(2, -2) end
    else
        if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 0) end
        if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
    end
end

-- Flat feature settings use explicit root keys rather than a nested config
-- table. This helper keeps those call sites concise while preserving the same
-- renderer and fallback rules as StyleFont().
function ns:StyleFeatureFont(fontString, size, fontKey, styleKey)
    local db = TurboFaceDB or {}
    local fontName = self:NormalizeFontName(db[fontKey])
    local style = db[styleKey] or self.DEFAULT_TEXT_STYLE
    self:StyleFont(fontString, self:GetFontPath(fontName), size, nil, style)
end

ns.Textures = {
    { name = "Flat",       path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Blizzard",   path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Minimalist", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { name = "Clean",      path = "Interface\\AddOns\\TurboFace\\Textures\\Statusbar_Clean.blp" },
    { name = "Smooth",     path = "Interface\\AddOns\\TurboFace\\Textures\\Smooth.tga" },
    { name = "Hyanda",     path = "Interface\\AddOns\\TurboFace\\Textures\\bar_hyanda.tga" },
    { name = "Serenity",   path = "Interface\\AddOns\\TurboFace\\Textures\\bar_serenity.tga" },
    { name = "Skyline",    path = "Interface\\AddOns\\TurboFace\\Textures\\bar_skyline.tga" },
    { name = "Stripes",    path = "Interface\\AddOns\\TurboFace\\Textures\\Statusbar_Stripes.blp" },
}

-- Backdrop EDGE textures, a different media type from the statusbar fills
-- above: these must be 8-segment edge strips, so an arbitrary statusbar
-- texture cannot be substituted here. Every path is one already proven present
-- on this client by existing TurboFace code, rather than a plausible-looking
-- guess -- a missing Blizzard texture renders as nothing and checks.py only
-- validates Interface\AddOns\TurboFace paths.
--
-- `inset` is where the VISIBLE art sits inside the edge strip, as a fraction of
-- edgeSize. It is not decoration: an edge texture is drawn inward from the
-- frame boundary across the full edgeSize, but ornate strips are largely
-- transparent, so the line the eye reads is well inside that band. Expanding
-- the border frame outward by inset * edgeSize puts that line back on the
-- minimap edge. The solid textures are 1.0 (art fills the strip); the ratios
-- for the ornate ones follow the insets Blizzard uses with them in FrameXML
-- (Tooltip 4/16, DialogBox 11/32).
ns.Borders = {
    { name = "Blizzard Dark",    inset = 1.00, path = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { name = "Blizzard Tooltip", inset = 0.25, path = "Interface\\Tooltips\\UI-Tooltip-Border" },
    { name = "Blizzard Dialog",  inset = 0.34, path = "Interface\\DialogFrame\\UI-DialogBox-Border" },
    { name = "Solid",            inset = 1.00, path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Glow",             inset = 0.50, path = "Interface\\AddOns\\TurboFace\\Textures\\GlowTex.tga" },
}

local function GetBorder(name)
    local fallback = ns.Borders[1].path
    if not name then return fallback end
    for _, b in ipairs(ns.Borders) do
        if b.name == name then return b.path end
    end
    return fallback
end

-- Unknown names are borders another addon registered with LSM, whose art we
-- cannot measure. 1.0 treats them as solid, which is the safe guess: it errs
-- toward the border sitting outside the minimap rather than overlapping it.
function ns:GetBorderInset(name)
    if name then
        for _, b in ipairs(self.Borders) do
            if b.name == name then return b.inset or 1 end
        end
    end
    return 1
end

-- =============================================================================
-- SHARED HELPERS  (copy/default merging, timers, chat, colour resolution, bar backdrop, combat-log dispatcher)
-- =============================================================================

-- Flat top-level setting accessors. Several feature modules keep their options
-- as flat TurboFaceDB keys rather than a nested block; these were four
-- byte-identical local copies (Grocery, InventoryManager, MinimapButton,
-- MinimapTracker) before being consolidated here.
--
-- Note these read the DB directly and are NOT a module gate: use
-- ns.ModuleEnabled() for that (ARCHITECTURE 4).
function ns.Opt(key, default)
    local db = TurboFaceDB
    local v = db and db[key]
    if v == nil then return default end
    return v
end

function ns.SetOpt(key, value)
    if TurboFaceDB then TurboFaceDB[key] = value end
end

-- The saved-variable root, guaranteed non-nil. Eight modules kept an identical
-- `local function DB() return TurboFaceDB or {} end`. Consumers alias it as
-- `local DB = ns.DB` so call sites keep their upvalue lookup and read the same.
--
-- This does NOT create or merge a nested settings block. Modules that own one
-- (ExperienceBar, LootFrame, Movers, PowerCost) keep their own DB(), because
-- theirs also ensures the sub-table exists and merges defaults into it.
function ns.DB()
    return TurboFaceDB or {}
end

-- =============================================================================
-- NATIVE CADENCE SCHEDULER
-- =============================================================================
-- High-refresh clients can render hundreds of frames per second. A throttled
-- Frame:OnUpdate still crosses the C->Lua boundary once per rendered frame just
-- to discover that its accumulator has not reached the requested interval.
--
-- Cadence uses ONE dynamic native clock for all periodic TurboFace work. The
-- clock runs at the fastest interval currently requested by any client (never
-- faster than 60 Hz); slower clients accumulate elapsed time and execute only
-- when their own cadence is due. This is intentionally different from a
-- per-client deadline scheduler: ten independently-phased clients must not
-- create ten separate native wake streams whose frequencies add together.
--
-- The scheduler is completely parked when it has no clients. A 1 Hz-only UI
-- therefore wakes about once per second; 60 Hz exists only while a real 60 Hz
-- animation client is active.
-- Mutating/removing existing entries while iterating is safe; new registrations
-- made from inside a callback are staged until the next pulse.
--
-- KEYS ARE ONE ADDON-WIDE NAMESPACE. Every client shares cadenceEntries, so a
-- key collision silently replaces another module's driver. Use the owning frame
-- or module table as the key (the common case, and unique by construction), or
-- a "TurboFace"-prefixed string literal. Never a bare descriptive string.
--
-- ERROR ISOLATION IS LOAD-BEARING. Centralizing every periodic job onto one
-- clock also centralizes their failure modes: an error escaping this pulse
-- would skip the trailing reschedule, strand cadenceTicking at true, and park
-- every periodic subsystem in the addon -- regen markers, castbars, combo dots,
-- swing timers, aura countdowns via ns.Timers -- until /reload, behind a single
-- Lua error. Client callbacks are therefore pcall-isolated, a client that keeps
-- erroring is evicted rather than re-run every pulse, and CadenceTicking()
-- recovers from a stale flag if anything unwinds the pulse anyway. This is the
-- runtime counterpart to ns.SafeCall at the init boundary.
local Cadence = {}
ns.Cadence = Cadence

local CADENCE_MIN_INTERVAL = 1 / 60
local CADENCE_EPSILON = 0.0005
local CADENCE_MAX_ERRORS = 3      -- consecutive client failures before eviction
local CADENCE_STALE_PULSE = 2.0   -- seconds; a "running" pulse older than this unwound
local cadenceEntries = {}
local cadencePending = {}
local cadenceErrors = {}
local cadenceCount = 0
local cadenceTimer = nil
local cadenceWakeAt = nil
local cadenceFallbackFrame = nil
local cadenceTicking = false
local cadencePulseStart = nil
local cadenceLastPulse = nil
local cadenceImmediatePending = false
local CadencePulse
local ScheduleCadenceClock

-- True while a pulse is legitimately walking the entry table. If the flag is
-- stale -- a pulse unwound through an error raised outside the per-client pcall
-- -- clear it here rather than letting Add/Remove/Schedule park forever.
local function CadenceTicking()
    if not cadenceTicking then return false end
    if cadencePulseStart and (GetTime() or 0) - cadencePulseStart >= CADENCE_STALE_PULSE then
        cadenceTicking = false
        cadencePulseStart = nil
        return false
    end
    return true
end

local function ReportCadenceError(err)
    if ns.Compat and ns.Compat.RecordIncident then ns.Compat:RecordIncident("cadence-error", "Cadence", err) end
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function StopCadenceClock()
    if cadenceTimer then
        if cadenceTimer.Cancel then cadenceTimer:Cancel() end
        cadenceTimer = nil
    end
    cadenceWakeAt = nil
    cadenceLastPulse = nil
    cadencePulseStart = nil
    cadenceImmediatePending = false
    if cadenceFallbackFrame then cadenceFallbackFrame:Hide() end
end

local function ApplyCadencePending(now)
    if not next(cadencePending) then return end
    for key, pending in pairs(cadencePending) do
        if pending then
            if cadenceEntries[key] == nil then cadenceCount = cadenceCount + 1 end
            cadenceEntries[key] = {
                interval = pending.interval,
                fn = pending.fn,
                accum = pending.immediate and pending.interval or 0,
                lastRun = now,
            }
            if pending.immediate then cadenceImmediatePending = true end
        end
        cadencePending[key] = nil
    end
end

local function FastestCadenceInterval()
    local fastest
    for _, entry in pairs(cadenceEntries) do
        local interval = entry.interval or CADENCE_MIN_INTERVAL
        if not fastest or interval < fastest then fastest = interval end
    end
    return fastest
end

local function CadenceHasDueClient()
    if cadenceImmediatePending then return true end
    for _, entry in pairs(cadenceEntries) do
        if (entry.accum or 0) + CADENCE_EPSILON >= (entry.interval or CADENCE_MIN_INTERVAL) then
            return true
        end
    end
    return false
end

ScheduleCadenceClock = function()
    -- A live pulse reschedules itself when it finishes; a stale flag does not.
    if CadenceTicking() then return end
    if cadenceCount <= 0 and not next(cadencePending) then
        StopCadenceClock()
        return
    end

    local now = GetTime() or 0
    ApplyCadencePending(now)
    if cadenceCount <= 0 then
        StopCadenceClock()
        return
    end

    local fastest = FastestCadenceInterval()
    if not fastest then
        StopCadenceClock()
        return
    end

    if not cadenceLastPulse then cadenceLastPulse = now end

    -- A newly-added immediate client gets one zero-delay pulse. Otherwise the
    -- single master clock wakes at the fastest active client cadence. Slower
    -- clients are serviced from accumulated elapsed time inside that pulse.
    local delay = CadenceHasDueClient() and 0 or fastest
    local desiredWake = now + delay

    -- Keep an existing wake that is already no later than the desired one.
    if cadenceTimer and cadenceWakeAt and cadenceWakeAt <= desiredWake + 0.0001 then return end

    if cadenceTimer and cadenceTimer.Cancel then cadenceTimer:Cancel() end
    cadenceTimer = nil
    cadenceWakeAt = desiredWake

    if C_Timer and C_Timer.NewTimer then
        cadenceTimer = C_Timer.NewTimer(delay, CadencePulse)
        return
    end

    -- Compatibility fallback for stripped test harnesses/very old clients.
    -- Classic Era 1.15.9 has C_Timer.NewTimer, so normal gameplay never pays a
    -- frame-rate-dependent OnUpdate for the scheduler itself.
    cadenceFallbackFrame = cadenceFallbackFrame or CreateFrame("Frame")
    cadenceFallbackFrame:SetScript("OnUpdate", function(self)
        if cadenceWakeAt and (GetTime() or 0) + 0.0001 >= cadenceWakeAt then
            CadencePulse()
        end
    end)
    cadenceFallbackFrame:Show()
end

function Cadence:Add(key, interval, fn, immediate)
    if key == nil or type(fn) ~= "function" then return end
    interval = math.max(tonumber(interval) or CADENCE_MIN_INTERVAL, CADENCE_MIN_INTERVAL)
    cadenceErrors[key] = nil
    if CadenceTicking() and cadenceEntries[key] == nil then
        cadencePending[key] = { interval = interval, fn = fn, immediate = immediate == true }
        return
    end

    local now = GetTime() or 0
    local entry = cadenceEntries[key]
    if not entry then
        cadenceCount = cadenceCount + 1
        entry = {
            interval = interval,
            fn = fn,
            accum = immediate and interval or 0,
            lastRun = now,
        }
        cadenceEntries[key] = entry
        if immediate then cadenceImmediatePending = true end
    else
        -- Preserve accumulated phase for an already-active client. Clamp it to
        -- the new interval if the requested cadence becomes faster so it can be
        -- serviced promptly without generating a private wake stream.
        entry.interval = interval
        entry.fn = fn
        if (entry.accum or 0) > interval then entry.accum = interval end
    end
    cadencePending[key] = nil
    if not CadenceTicking() then ScheduleCadenceClock() end
end

function Cadence:Remove(key)
    if key == nil then return end
    cadencePending[key] = nil
    cadenceErrors[key] = nil
    if cadenceEntries[key] ~= nil then
        cadenceEntries[key] = nil
        cadenceCount = cadenceCount - 1
        if cadenceCount < 0 then cadenceCount = 0 end
    end
    if not CadenceTicking() then ScheduleCadenceClock() end
end

function Cadence:Count()
    return cadenceCount
end

function Cadence:FastestHz()
    local interval = FastestCadenceInterval()
    return interval and (1 / interval) or 0
end

function Cadence:IsActive(key)
    return cadenceEntries[key] ~= nil or cadencePending[key] ~= nil
end

CadencePulse = function()
    cadenceTimer = nil
    cadenceWakeAt = nil
    if cadenceFallbackFrame then cadenceFallbackFrame:Hide() end

    local now = GetTime() or 0
    ApplyCadencePending(now)
    if cadenceCount <= 0 then return end

    local dt
    if cadenceLastPulse then
        dt = math.max(0, now - cadenceLastPulse)
    else
        -- First pulse after parking: immediate clients already carry one full
        -- interval in accum; non-immediate clients begin accumulating here.
        dt = 0
    end
    cadenceLastPulse = now
    cadenceImmediatePending = false

    cadenceTicking = true
    cadencePulseStart = now
    for key, entry in pairs(cadenceEntries) do
        local interval = entry.interval or CADENCE_MIN_INTERVAL
        local accum = (entry.accum or 0) + dt
        entry.accum = accum
        if accum + CADENCE_EPSILON >= interval then
            local elapsed = now - (entry.lastRun or now)
            entry.lastRun = now
            -- Preserve average cadence without catch-up bursts. If a long frame
            -- skipped several periods, execute once and retain only the phase
            -- remainder rather than invoking the client multiple times.
            --
            -- The remainder must clear the SAME epsilon the due test above uses.
            -- A pulse landing within CADENCE_EPSILON early fires with accum just
            -- under interval, and `accum % interval` returns it unchanged -- so
            -- the entry reads as due again, CadenceHasDueClient() arms a
            -- zero-delay pulse, and the client runs twice for one period. A live
            -- client's next dt breaks the tie, making it one wasted wake rather
            -- than a stall, but the fix is free and removes the spin entirely.
            local remainder = accum % interval
            if remainder + CADENCE_EPSILON >= interval then remainder = 0 end
            entry.accum = remainder

            -- One client's error must not take the master clock down with it.
            local ok, err = pcall(entry.fn, key, elapsed)
            if ok then
                cadenceErrors[key] = nil
            else
                local n = (cadenceErrors[key] or 0) + 1
                cadenceErrors[key] = n
                -- Surface the first failure, then stop spamming: a 60 Hz client
                -- erroring every pulse would otherwise flood the error handler.
                if n == 1 then ReportCadenceError(err) end
                if n >= CADENCE_MAX_ERRORS and cadenceEntries[key] ~= nil then
                    cadenceEntries[key] = nil
                    cadenceCount = cadenceCount - 1
                    if cadenceCount < 0 then cadenceCount = 0 end
                    cadenceErrors[key] = nil
                    ReportCadenceError(
                        "TurboFace: cadence client evicted after "
                        .. CADENCE_MAX_ERRORS .. " consecutive errors; "
                        .. "its periodic work has stopped. Last error: " .. tostring(err))
                end
            end
        end
    end
    cadenceTicking = false
    cadencePulseStart = nil

    -- Callbacks may have staged new clients while the table was being walked.
    now = GetTime() or now
    ApplyCadencePending(now)
    ScheduleCadenceClock()
end

ns.RegisterCPUProfileTarget("Core/CadenceScheduler:Pulse", CadencePulse, false)

-- =============================================================================
-- SHARED TIMER BUS
-- =============================================================================
-- Aura/debuff duration text shares one 20 Hz client on the cadence scheduler.
-- The individual widget callbacks remain plain Lua calls, so a pull with dozens
-- of timed icons still costs only one native scheduler wake instead of one
-- frame script per icon (or one shared frame script per rendered frame).
local Timers = {}
ns.Timers = Timers

local timerTargets = {}
local timerCount = 0
local timerPending = {}
local timerErrors = {}
local timerTicking = false
local SHARED_TIMER_INTERVAL = 0.05 -- 20 Hz; fastest aura text cadence is 20 Hz

local function SharedTimerPulse(_, elapsed)
    if next(timerPending) then
        for widget, fn in pairs(timerPending) do
            if timerTargets[widget] == nil then timerCount = timerCount + 1 end
            timerTargets[widget] = fn
            timerPending[widget] = nil
        end
    end

    if not next(timerTargets) then
        Cadence:Remove(Timers)
        return
    end

    -- Same contract as the cadence pulse above: this whole bus is a single
    -- cadence client, so an unhandled error here would strand timerTicking and
    -- silently kill every aura/debuff countdown in the addon.
    timerTicking = true
    for widget, fn in pairs(timerTargets) do
        if widget.IsVisible and widget:IsVisible() then
            local ok, err = pcall(fn, widget, elapsed)
            if ok then
                timerErrors[widget] = nil
            else
                local n = (timerErrors[widget] or 0) + 1
                timerErrors[widget] = n
                if n == 1 then ReportCadenceError(err) end
                if n >= CADENCE_MAX_ERRORS and timerTargets[widget] ~= nil then
                    timerTargets[widget] = nil
                    timerCount = timerCount - 1
                    if timerCount < 0 then timerCount = 0 end
                    timerErrors[widget] = nil
                end
            end
        end
    end
    timerTicking = false

    if timerCount <= 0 and not next(timerPending) then Cadence:Remove(Timers) end
end

function Timers:Add(widget, fn)
    if not widget or type(fn) ~= "function" then return end
    timerErrors[widget] = nil
    if timerTicking and timerTargets[widget] == nil then
        timerPending[widget] = fn
    else
        if timerTargets[widget] == nil then timerCount = timerCount + 1 end
        timerTargets[widget] = fn
    end
    Cadence:Add(Timers, SHARED_TIMER_INTERVAL, SharedTimerPulse)
end

function Timers:Remove(widget)
    if widget == nil then return end
    timerPending[widget] = nil
    timerErrors[widget] = nil
    if timerTargets[widget] ~= nil then
        timerTargets[widget] = nil
        timerCount = timerCount - 1
        if timerCount < 0 then timerCount = 0 end
    end
    if timerCount <= 0 and not next(timerPending) then Cadence:Remove(Timers) end
end

function Timers:Count()
    return timerCount
end

ns.RegisterCPUProfileTarget("Core/SharedTimers:Pulse", SharedTimerPulse)

-- Nameplate unit tokens are "nameplate1".."nameplateN".
local strsub = string.sub
function ns.IsNameplateUnit(unit)
    return unit and strsub(unit, 1, 9) == "nameplate"
end

-- Border resolution keeps the existing catalog/inset policy. Font and statusbar
-- resolution live in SharedMedia.lua, which loads before all feature consumers.
local LSM_statusbar = LibStub and LibStub("LibSharedMedia-3.0", true)
-- For backdrop edge textures, an LSM name registered by
-- any addon resolves first, then TurboFace's own catalog as the fallback.
function ns.ResolveBorderTexture(name)
    if LSM_statusbar and name then
        local path = LSM_statusbar:Fetch("border", name)
        if path then return path end
    end
    return GetBorder(name)
end


-- Deep-copy plain Lua tables used by saved-variable defaults. Kept central so
-- modules do not need their own recursive copy helpers.
function ns.DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = ns.DeepCopy(v)
    end
    return copy
end

-- Merge missing defaults into an existing saved-variable table. If a default is
-- a table but the saved value is malformed, replace it with a clean copy.
function ns.MergeDefaults(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = ns.DeepCopy(v)
            else
                ns.MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- =============================================================================
-- MODULE MASTER TOGGLES -- read/write boundary
--
-- ns.ModuleEnabled("unitframes")          -> family switch
-- ns.ModuleEnabled("unitframes", "party") -> family AND element switch
--
-- FAIL-OPEN by design: a missing, malformed, or not-yet-migrated flag reads as
-- ENABLED. A user who has never touched these options, or whose DB predates the
-- schema, must get the full addon -- never a silently gutted one. Only an
-- explicit `false` disables anything.
-- =============================================================================
-- Families whose GUI lives under another family's master toggle. Turning the
-- parent off must turn the child off too, or the child keeps running with its
-- control hidden and no way to reach it.
-- No current feature family is hard-parented to Unit Frames. Player tick
-- markers, swing timers, and cast bars can all augment Blizzard's stock frames
-- when TurboFace Unit Frames is disabled. Keep this table for future true
-- parent/child runtime relationships; GUI placement alone is not a parent.
local MODULE_PARENT = {}

-- =============================================================================
-- PLUS SECTION GATING
--
-- The visible QoL tab has no master toggle; each SECTION has its own checkbox in its
-- collapsible header, matching the Speedrun tab. Rather than gating each of the six
-- Plus files (sections do not map 1:1 to files -- Interface and Minimap share
-- InterfaceTweaks), gating happens at
-- the SETTINGS READ: every plus key is mapped to its section, and a disabled
-- section's keys read as nil.
--
-- That means each feature takes its own disabled branch and Refresh tears it
-- down normally -- the same reason the old whole-module Refresh gate was wrong.
--
-- This map is generated from the section layout in OptionsGUI's QoL tab. If a
-- setting is added to a section there, add it here too, or it will ignore its
-- section's checkbox.
-- =============================================================================
ns.PLUS_SECTION = {
    -- Automation
    acceptRes = "automation",
    acceptResNoCombat = "automation",
    acceptSummon = "automation",
    autoRepair = "automation",
    autoRepairSummary = "automation",
    automateGossip = "automation",
    autoQuestAccept = "automation",
    autoQuestTurnIn = "automation",
    automateSpiritHealer = "automation",
    releaseDelay = "automation",
    releaseNoAlterac = "automation",
    releasePvP = "automation",
    -- Social
    acceptPartyFriends = "social",
    blockDuels = "social",
    blockFriendRequests = "social",
    blockPartyInvites = "social",
    blockSharedQuests = "social",
    friendlyGuild = "social",
    inviteFriendsOnly = "social",
    inviteFromWhisper = "social",
    inviteKeyword = "social",
    -- Interface
    enhanceQuestDifficulty = "interface",
    hideHitIndicators = "interface",
    hideKeybindText = "interface",
    hideMacroText = "interface",
    hideRaidGroupLabels = "interface",
    hideZoneText = "interface",
    showRaidToggle = "interface",
    combinedBagMovable = "interface",
    -- Minimap
    hideMiniClock = "minimap",
    hideMiniDayNight = "minimap",
    hideMiniLFG = "minimap",
    hideMiniZoneText = "minimap",
    hideMiniZoomBtns = "minimap",
    minimapBorderOffset = "minimap",
    minimapBorderTexture = "minimap",
    minimapBorderWidth = "minimap",
    minimapSize = "minimap",
    minimapShape = "minimap",
    minimapZoneBanner = "minimap",
    minimapZoneTextSize = "minimap",
    -- Map
    mapEnhancedZoom = "map",
    mapMovable = "map",
    mapRememberZoom = "map",
    mapZoomMax = "map",
    -- Chat
    chatTextOutline = "chat",
    noChatButtons = "chat",
    noChatFade = "chat",
    noCombatLogTab = "chat",
    unclampChat = "chat",
    -- System
    fasterLooting = "system",
    keepAudioSynced = "system",
    maxCameraZoom = "system",
    noBagAutomation = "system",
    noConfirmLoot = "system",
    noRestedEmotes = "system",
    noScreenEffects = "system",
    noScreenGlow = "system",
    setWeatherDensity = "system",
    weatherLevel = "system",
    -- Flight Bar
    flightBarScale = "flightBar",
    flightBarWidth = "flightBar",
}

-- Read-only proxy over TurboFaceDB.plus. Plus modules never write through their
-- P() accessor, so a metatable view is safe. Keep exactly ONE proxy for the
-- addon lifetime: profile/import operations replace TurboFaceDB wholesale, so
-- __index resolves the current table on every read instead of capturing a stale
-- db pointer. This removes the old table + metatable + closure allocation from
-- every P() call while remaining profile-safe.
local PLUS_SETTINGS_PROXY = setmetatable({}, {
    __index = function(_, k)
        local section = ns.PLUS_SECTION[k]
        if section and ns.ModuleEnabled and not ns.ModuleEnabled("plus", section) then
            return nil
        end
        local db = type(TurboFaceDB) == "table" and TurboFaceDB.plus
        if type(db) ~= "table" then return nil end
        return db[k]
    end,
    __newindex = function()
        error("TurboFace PlusSettings is read-only", 2)
    end,
})

function ns.PlusSettings()
    return PLUS_SETTINGS_PROXY
end

function ns.PlusSectionEnabled(section)
    return (not ns.ModuleEnabled) or ns.ModuleEnabled("plus", section)
end

-- PLUS_SECTION is intentionally explicit because TurboFaceDB.plus remains flat
-- for profile compatibility. Validate it against defaults at login so a newly
-- added Plus option cannot silently bypass its section master.
function ns.ValidatePlusSectionMap()
    local defaults = ns.defaults and ns.defaults.plus
    if type(defaults) ~= "table" then return true end
    local missing, extra = {}, {}
    for key in pairs(defaults) do
        if ns.PLUS_SECTION[key] == nil then missing[#missing + 1] = key end
    end
    for key in pairs(ns.PLUS_SECTION) do
        if defaults[key] == nil then extra[#extra + 1] = key end
    end
    if #missing == 0 and #extra == 0 then return true end
    table.sort(missing)
    table.sort(extra)
    if ns.Chat then
        local parts = {}
        if #missing > 0 then parts[#parts + 1] = "unmapped: " .. table.concat(missing, ", ") end
        if #extra > 0 then parts[#parts + 1] = "stale: " .. table.concat(extra, ", ") end
        ns:Chat("Config", "Plus section map mismatch (" .. table.concat(parts, "; ") .. ")")
    end
    return false
end

function ns.ModuleEnabled(family, element)
    -- Client capability is an effective-state boundary, not a saved setting.
    -- Preserve the user's portable preference in TurboFaceDB even when the
    -- selected client cannot safely implement that feature family.
    if ns.FeatureAvailable and ns.FeatureAvailable(family, true) == false then
        return false
    end

    -- Forever 1.60.1.69913: Blizzard nameplates are pooled CompactUnitFrames whose
    -- health/max-health values become secret in combat. Any TurboFace mutation of
    -- those native frames/regions (including merely attaching addon fields/children)
    -- can taint Blizzard's later CompactUnitFrame_UpdateHealPrediction pass.
    --
    -- Preserve the user's profile checkbox, but fail CLOSED at runtime until the
    -- nameplate port is rebuilt around detached TurboFace-owned overlay frames and
    -- external side tables. This is a capability/safety block, not a second staging
    -- system: all other modules remain governed solely by their Options gates.
    if family == "nameplates" then
        -- Some clients require a detached nameplate adapter before the family
        -- can safely run. That requirement is client policy; Config only
        -- consumes the policy and never branches on client/build identity.
        local requireAdapter = ns.Client and ns.Client.GetOptionPolicy
            and ns.Client:GetOptionPolicy("requireDetachedNameplateAdapter")
        if requireAdapter and not ns.ForeverNameplates then
            return false
        end
    end

    local root = type(TurboFaceDB) == "table" and TurboFaceDB.modules
    if type(root) ~= "table" then return true end
    local parent = MODULE_PARENT[family]
    if parent then
        local pf = root[parent]
        if type(pf) == "table" and pf.enabled == false then return false end
    end
    local fam = root[family]
    if type(fam) ~= "table" then return true end
    if fam.enabled == false then return false end
    if element == nil then return true end
    return fam[element] ~= false
end

-- Some TurboFace-owned widgets have no sensible fixed Blizzard anchor and are
-- intentionally coupled to the Movers framework. Keep the user's feature
-- preference intact, but make the EFFECTIVE feature state depend on Movers so
-- disabling Movers cannot leave an unpositionable custom widget running.
function ns.MoversEnabled()
    local db = type(TurboFaceDB) == "table" and TurboFaceDB.movers
    if type(db) ~= "table" then return true end
    return db.enabled ~= false
end

-- CALLERS MUST PASS A REAL BOOLEAN. Only an explicit `false` disables, because
-- a missing/not-yet-migrated preference must fail OPEN like every other gate
-- (see the fail-open contract in ARCHITECTURE.md 4.1). That makes `nil` read as
-- ENABLED, which is correct for a module gate and wrong for anything that can
-- legitimately be nil -- above all ns.PlusSettings(), whose proxy returns nil
-- for a key in a DISABLED section. Passing that straight through would turn a
-- disabled section into an enabled feature: the exact failure this gate exists
-- to prevent. Coerce first (`~= false`, `== true`, or `and true or false`),
-- then call. Every current call site does.
function ns.MoverDependentEnabled(localEnabled)
    if localEnabled == false then return false end
    return ns.MoversEnabled()
end

-- Unit-event registration filtered in C. A plain RegisterEvent("UNIT_AURA")
-- wakes Lua for every unit the client tracks -- player, party, raid, pet,
-- target, focus and all ~40 nameplate units -- even when the consumer only
-- cares about "player". RegisterUnitEvent pushes that filter below the Lua
-- boundary, so the handler is never entered for units it would discard.
--
-- Blizzard's API accepts at most TWO unit tokens; anything needing more (group
-- rosters, nameplates) must keep the unfiltered registration.
--
-- Callers must keep their existing unit checks: the fallback path below is
-- unfiltered, so the handler still has to be correct without C-side filtering.
function ns.RegisterUnitEvent(frame, event, unit1, unit2)
    return ns.API.RegisterUnitEvent(frame, event, unit1, unit2)
end

function ns.RegisterEvent(frame, event)
    return ns.API.RegisterEvent(frame, event)
end

-- Persistent ownership for client CVars that TurboFace temporarily overrides.
-- TurboFaceCacheDB is intentionally outside profile/import snapshots, and its
-- ownership subtrees are preserved when ordinary build-specific caches reset.
-- An owner captures each CVar exactly once, can enforce it across reloads/
-- sessions, and restores the exact pre-TurboFace value when disabled.
--
-- Scalar and bitfield ownership are deliberately separate. A scalar snapshot
-- owns the whole CVar. A bitfield snapshot owns only the requested indexes, so
-- restoring enemy stacking can never roll back a friendly-stacking choice the
-- user made while TurboFace was active.
local function OwnedCVarStore(key)
    if type(TurboFaceCacheDB) ~= "table" then TurboFaceCacheDB = {} end
    if type(TurboFaceCacheDB[key]) ~= "table" then
        TurboFaceCacheDB[key] = {}
    end
    return TurboFaceCacheDB[key]
end

local function TableIsEmpty(value)
    return type(value) ~= "table" or next(value) == nil
end

local function ScalarCVarAPI()
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    return get, set
end

local function ReadScalarCVar(get, name)
    if type(get) ~= "function" or type(name) ~= "string" or name == "" then return nil end
    local ok, value = pcall(get, name)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function WriteScalarCVar(get, set, name, wanted)
    local current = ReadScalarCVar(get, name)
    if current == nil then return false, false end -- unknown/unregistered CVar
    wanted = tostring(wanted)
    if current == wanted then return true, true end
    if type(set) ~= "function" then return true, false end
    pcall(set, name, wanted)
    return true, ReadScalarCVar(get, name) == wanted
end

function ns.ApplyOwnedCVars(owner, active, values)
    if type(owner) ~= "string" or owner == "" or type(values) ~= "table" then return false end
    local get, set = ScalarCVarAPI()
    if type(get) ~= "function" or type(set) ~= "function" then return false end

    local store = OwnedCVarStore("cvarOwners")
    local snapshot = store[owner]
    local allApplied = true

    if active then
        if type(snapshot) ~= "table" then
            snapshot = {}
            store[owner] = snapshot
        end
        for cvar, value in pairs(values) do
            local previous = ReadScalarCVar(get, cvar)
            if previous == nil then
                -- Do not create ownership debt for removed or misspelled CVars.
                snapshot[cvar] = nil
                allApplied = false
            else
                if snapshot[cvar] == nil or snapshot[cvar] == false then
                    snapshot[cvar] = previous
                end
                local _, applied = WriteScalarCVar(get, set, cvar, value)
                if not applied then allApplied = false end
            end
        end
        if TableIsEmpty(snapshot) then store[owner] = nil end
        return allApplied
    end

    if type(snapshot) ~= "table" then return true end
    for cvar, previous in pairs(snapshot) do
        if previous == false or ReadScalarCVar(get, cvar) == nil then
            -- A legacy sentinel or a CVar removed by the client has nothing to
            -- restore and must not strand the owner record forever.
            snapshot[cvar] = nil
        else
            local _, restored = WriteScalarCVar(get, set, cvar, previous)
            if restored then
                snapshot[cvar] = nil
            else
                allApplied = false
            end
        end
    end
    if TableIsEmpty(snapshot) then store[owner] = nil end
    return allApplied
end

function ns.ReleaseOwnedCVars(owner)
    return ns.ApplyOwnedCVars(owner, false, {})
end

-- Replace the user's persistent baseline without fighting a currently active
-- TurboFace CVar owner. Quick Setup uses this for reload-free profile applies:
-- unowned CVars change immediately, while owned CVars keep their temporary
-- override and restore to the newly supplied baseline when that owner releases.
function ns.ApplyCVarBaseline(values)
    if type(values) ~= "table" then return 0 end
    local get, set = ScalarCVarAPI()
    if type(get) ~= "function" or type(set) ~= "function" then return 0 end

    local owners = OwnedCVarStore("cvarOwners")
    local applied = 0
    for cvar, wanted in pairs(values) do
        if type(cvar) == "string" and cvar ~= "" and ReadScalarCVar(get, cvar) ~= nil then
            wanted = tostring(wanted)
            local owned = false
            for _, snapshot in pairs(owners) do
                if type(snapshot) == "table" and snapshot[cvar] ~= nil and snapshot[cvar] ~= false then
                    snapshot[cvar] = wanted
                    owned = true
                end
            end
            if owned then
                applied = applied + 1
            else
                local _, written = WriteScalarCVar(get, set, cvar, wanted)
                if written then applied = applied + 1 end
            end
        end
    end
    return applied
end

local function ReadCVarBit(name, index)
    if not (C_CVar and type(C_CVar.GetCVarBitfield) == "function") then return nil end
    if ReadScalarCVar(C_CVar.GetCVar, name) == nil then return nil end
    local ok, value = pcall(C_CVar.GetCVarBitfield, name, index)
    if not ok or value == nil then return nil end
    return value == true
end

local function WriteCVarBit(name, index, wanted)
    local current = ReadCVarBit(name, index)
    if current == nil then return false, false end
    wanted = wanted == true
    if current == wanted then return true, true end
    if not (C_CVar and type(C_CVar.SetCVarBitfield) == "function") then return true, false end
    pcall(C_CVar.SetCVarBitfield, name, index, wanted)
    return true, ReadCVarBit(name, index) == wanted
end

-- values = { [cvarName] = { [bitIndex] = boolean, ... }, ... }
function ns.ApplyOwnedCVarBits(owner, active, values)
    if type(owner) ~= "string" or owner == "" or type(values) ~= "table" then return false end
    if not (C_CVar and type(C_CVar.GetCVarBitfield) == "function"
        and type(C_CVar.SetCVarBitfield) == "function") then
        return false
    end

    local store = OwnedCVarStore("cvarBitOwners")
    local snapshot = store[owner]
    local allApplied = true

    if active then
        if type(snapshot) ~= "table" then
            snapshot = {}
            store[owner] = snapshot
        end
        for cvar, requestedBits in pairs(values) do
            if type(requestedBits) == "table" then
                local savedBits = snapshot[cvar]
                if type(savedBits) ~= "table" then
                    savedBits = {}
                    snapshot[cvar] = savedBits
                end
                for index, wanted in pairs(requestedBits) do
                    local previous = ReadCVarBit(cvar, index)
                    if previous == nil then
                        savedBits[index] = nil
                        allApplied = false
                    else
                        if savedBits[index] == nil then savedBits[index] = previous end
                        local _, applied = WriteCVarBit(cvar, index, wanted)
                        if not applied then allApplied = false end
                    end
                end
                if TableIsEmpty(savedBits) then snapshot[cvar] = nil end
            end
        end
        if TableIsEmpty(snapshot) then store[owner] = nil end
        return allApplied
    end

    if type(snapshot) ~= "table" then return true end
    for cvar, savedBits in pairs(snapshot) do
        if type(savedBits) ~= "table" then
            snapshot[cvar] = nil
        else
            for index, previous in pairs(savedBits) do
                if ReadCVarBit(cvar, index) == nil then
                    savedBits[index] = nil
                else
                    local _, restored = WriteCVarBit(cvar, index, previous)
                    if restored then
                        savedBits[index] = nil
                    else
                        allApplied = false
                    end
                end
            end
            if TableIsEmpty(savedBits) then snapshot[cvar] = nil end
        end
    end
    if TableIsEmpty(snapshot) then store[owner] = nil end
    return allApplied
end


-- Writes a gate and returns true if the stored value actually changed, so the
-- caller can decide whether a reload prompt is warranted.
function ns.SetModuleEnabled(family, element, value)
    if type(TurboFaceDB) ~= "table" then return false end
    if type(TurboFaceDB.modules) ~= "table" then TurboFaceDB.modules = {} end
    local root = TurboFaceDB.modules
    if type(root[family]) ~= "table" then root[family] = { enabled = true } end
    local key = element or "enabled"
    local new = (value == true)
    local changed = (root[family][key] ~= new)
    root[family][key] = new
    return changed
end

-- Normalize the types of every known configuration key before defaults merge.
-- Unknown keys are preserved for forward compatibility and dynamic tables, but
-- malformed known values cannot reach runtime modules after an import/edit.
function ns.NormalizeKnownConfigTypes(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
    for k, defaultValue in pairs(defaults) do
        local value = dst[k]
        if value ~= nil then
            if type(defaultValue) == "table" then
                if type(value) ~= "table" then
                    dst[k] = ns.DeepCopy(defaultValue)
                else
                    ns.NormalizeKnownConfigTypes(value, defaultValue)
                end
            elseif type(value) ~= type(defaultValue) then
                dst[k] = defaultValue
            end
        end
    end
    return dst
end

-- C_Timer.After wrapper with immediate fallback for early load/test contexts.
function ns.After(delay, fn)
    if type(fn) ~= "function" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, fn)
    else
        fn()
    end
end

-- Consistent module-scoped chat output. Use ns:Chat("Movers", msg) or
-- ns:Chat(msg) for a generic TurboFace prefix.
function ns:Chat(scope, msg)
    if msg == nil then
        msg = scope
        scope = nil
    end
    local prefix = "|cff00ccffTurbo|cffffffffFace" .. (scope and (" " .. tostring(scope)) or "") .. ":|r "
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
    elseif print then
        print("TurboFace" .. (scope and (" " .. tostring(scope)) or "") .. ": " .. tostring(msg))
    end
end

-- =============================================================================
-- SHARED UI SOUND KITS
--
-- Audio feedback should match whatever Blizzard plays for the equivalent
-- native action, so TurboFace panels feel like part of the game rather than an
-- addon bolted on. Call sites name the ACTION ("panelOpen", "tab", ...) rather
-- than a sound kit, so the mapping stays in one place and can be corrected
-- without touching every module.
--
--   panelOpen / panelClose  the game menu (Esc) open and close sounds
--   tab                     the tab click used across Blizzard's panelled UI
--   checkOn / checkOff      the options-panel checkbox toggle pair
--   option                  a non-checkbox options control being committed
--   windowOpen / windowClose  the quest-log style open/close, for feature
--                           windows that are not the config panel
--
-- Symbolic SOUNDKIT constants with numeric fallbacks, matching the pattern in
-- Grocery.lua: the constant is authoritative and the number only matters on a
-- build where SOUNDKIT has not exposed that name.
-- =============================================================================
-- Values may be a single kit or an ORDERED LIST of candidates. PlaySound
-- reports whether the client actually queued anything, so a list lets the first
-- audible candidate win. This exists because IG_MAINMENU_OPTION turned out to
-- be silent on this client and failed quietly -- a mapping that self-heals
-- beats one that needs a bug report to discover it is broken.
local SK = _G.SOUNDKIT or {}
local UI_SOUNDS = {
    panelOpen    = SK.IG_MAINMENU_OPEN                or 850,
    panelClose   = SK.IG_MAINMENU_CLOSE               or 851,
    tab          = SK.IG_CHARACTER_INFO_TAB           or 841,
    checkOn      = SK.IG_MAINMENU_OPTION_CHECKBOX_ON  or 856,
    checkOff     = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,
    -- Dropdown selections and colour swatches. IG_MAINMENU_OPTION was tried
    -- first and turned out inaudible here, so this reuses the checkbox-on kit,
    -- which is confirmed working. It is defensible on its own terms too:
    -- committing a dropdown choice IS clicking an option.
    option       = SK.IG_MAINMENU_OPTION_CHECKBOX_ON  or 856,
    -- The spellbook page-turn, used by Blizzard for its own skill-line tabs and
    -- the next/previous page buttons. Falls back to the tab kit.
    pageTurn     = { SK.IG_ABILITY_PAGE_TURN or 834,
                     SK.IG_CHARACTER_INFO_TAB or 841 },
    -- Opening/closing a dropdown. Blizzard's own dropdowns use the chat scroll
    -- click here; the checkbox kit is the fallback since it is known audible.
    dropdownOpen = { SK.U_CHAT_SCROLL_BUTTON or 1115,
                     SK.IG_MAINMENU_OPTION_CHECKBOX_ON or 856 },
    windowOpen   = SK.IG_QUEST_LOG_OPEN               or 844,
    windowClose  = SK.IG_QUEST_LOG_CLOSE              or 845,
}

-- Audition a sound kit so a mapping that turns out silent can be replaced from
-- evidence rather than guesswork. PlaySound's first return says whether the
-- client actually played anything, which distinguishes "wrong ID" from "right
-- ID, wrong sound for the job".
--
--   /tf sound              list the current action mapping
--   /tf sound 856          play kit 856
--   /tf sound IG_MAINMENU_OPTION   play a kit by SOUNDKIT name
--   /tf sound option       play whatever an action is currently mapped to
function ns:AuditionSound(arg)
    arg = tostring(arg or ""):match("^%s*(.-)%s*$")

    if arg == "" then
        ns:Chat("Sound", "current UI sound mapping:")
        local names = {}
        for action in pairs(UI_SOUNDS) do names[#names + 1] = action end
        table.sort(names)
        for _, action in ipairs(names) do
            local entry = UI_SOUNDS[action]
            if type(entry) == "table" then
                local parts = {}
                for _, kit in ipairs(entry) do parts[#parts + 1] = tostring(kit) end
                ns:Chat("Sound", ("  %s = %s (first audible wins)")
                    :format(action, table.concat(parts, " -> ")))
            else
                ns:Chat("Sound", ("  %s = %d"):format(action, entry))
            end
        end
        ns:Chat("Sound", "usage: /tf sound <kitID | SOUNDKIT_NAME | action>")
        return
    end

    -- An action name plays through the normal path, candidate list and all.
    if UI_SOUNDS[arg] then
        local played = ns:PlayUISound(arg)
        ns:Chat("Sound", ("action '%s' -> %s"):format(arg,
            played and "|cff40ff40played|r" or "|cffff4040silent (no candidate queued)|r"))
        return
    end

    local kit = tonumber(arg) or (_G.SOUNDKIT and _G.SOUNDKIT[arg])
    if not kit then
        ns:Chat("Sound", ("unknown sound '%s'."):format(arg))
        return
    end

    local willPlay = PlaySound and PlaySound(kit)
    ns:Chat("Sound", ("kit %d -> %s"):format(kit,
        willPlay and "|cff40ff40played|r" or "|cffff4040silent (nothing queued)|r"))
end

function ns:PlayUISound(action)
    local entry = UI_SOUNDS[action]
    if not entry or not PlaySound then return false end

    if type(entry) ~= "table" then
        return PlaySound(entry) and true or false
    end

    -- Ordered candidates: take the first one the client will actually play.
    for _, kit in ipairs(entry) do
        if PlaySound(kit) then return true end
    end
    return false
end

-- Convenience for CheckButtons: plays the on/off member of the pair that
-- matches the button's NEW state. Call from OnClick, after the state flipped.
function ns:PlayCheckSound(button)
    local checked = button and button.GetChecked and button:GetChecked()
    ns:PlayUISound((checked == true or checked == 1) and "checkOn" or "checkOff")
end

-- Read an {r,g,b} *or* {[1],[2],[3]} colour table (the ColorPicker writes the
-- former, defaults use the latter). Returns r,g,b, falling back to dr,dg,db.
function ns:Color(t, dr, dg, db)
    if type(t) ~= "table" then return dr, dg, db end
    return (t.r or t[1] or dr), (t.g or t[2] or dg), (t.b or t[3] or db)
end

-- Shared bar border colors. BAR_BORDER_COLOR tints the border ring art;
-- BAR_BORDER_TAGGED (55,55,55) greys the target NAME/LEVEL text when the
-- target is tap-denied (tagged by someone else) -- border recoloring was
-- removed with the locked Blizzard Tooltip art (not color-coded). See
-- UnitFrames/UnitFrames.lua ApplyTargetTagState.
ns.BAR_BORDER_COLOR  = { 200/255, 200/255, 200/255, 0.9 }
ns.BAR_BORDER_TAGGED = {  55/255,  55/255,  55/255, 0.9 }

-- Refresh the shared color tables from saved settings. Mutates the tables IN
-- PLACE so every module holding a reference sees the new values immediately.
function ns:UpdateSharedColors()
    local db = TurboFaceDB
    if not db then return end
    local b = db.barBorderColor
    if type(b) == "table" then
        ns.BAR_BORDER_COLOR[1] = b.r or ns.BAR_BORDER_COLOR[1]
        ns.BAR_BORDER_COLOR[2] = b.g or ns.BAR_BORDER_COLOR[2]
        ns.BAR_BORDER_COLOR[3] = b.b or ns.BAR_BORDER_COLOR[3]
    end
    local t = db.taggedIndicatorColor
    if type(t) == "table" then
        ns.BAR_BORDER_TAGGED[1] = t.r or ns.BAR_BORDER_TAGGED[1]
        ns.BAR_BORDER_TAGGED[2] = t.g or ns.BAR_BORDER_TAGGED[2]
        ns.BAR_BORDER_TAGGED[3] = t.b or ns.BAR_BORDER_TAGGED[3]
    end
end

-- TurboFace's LOCKED bar-border style: Blizzard Tooltip at edge size 9,
-- with bar spacing forced to 2 (see
-- LoadVariables). Frozen after in-game tuning as the addon's visual identity;
-- the former barBorderTexture/barBorderSize/Bar Spacing/ToT Border Size
-- options were removed.
-- Returns: edgeFile, edgeSize, backdrop inset.
local BAR_BORDER_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local BAR_BORDER_SIZE = 9
function ns:GetBarBorderStyle()
    return BAR_BORDER_EDGE, BAR_BORDER_SIZE,
        math.floor(BAR_BORDER_SIZE / 4 + 0.5)
end

-- How far a textured border ring extends OUTSIDE the bar it frames. Border
-- art draws its visible ridge about a QUARTER of the edge size inside the
-- ring frame's rect, so an outset of size/4 lands the ridge exactly ON the
-- bar's fill edge: the fill reads as reaching the border with no dark rim,
-- and nothing spills outside the line. Because every ridge is pinned to its
-- own bar edge, two adjacent bars' ridges sit exactly `barSpacing` apart --
-- at spacing 0 the bars touch and both ridges land on the SAME line, merging
-- into one shared classic divider. Do not clamp this by the bar gap: that
-- shrinks the outset at low spacing and re-opens the rim the outset exists
-- to close. 0 in Pixel/None mode, where borders sit exactly on the frame rect.
function ns:GetBarBorderOutset()
    local edge, size = ns:GetBarBorderStyle()
    if edge and size > 1 then
        return math.max(1, math.floor(size / 4 + 0.5))
    end
    return 0
end


local ApplyBarBorderOnly

-- Anchor `border` around `target` with the current outset and paint the
-- configured edge on it. The edge size is clamped against the framed bar's
-- height so corner pieces on short bars (party power, absorb) cannot overlap
-- and glitch. This is the one path that produces the per-bar Blizz-like ring;
-- adjacent bars' rings meeting in the bar gap form the HP/power divider.
-- `sizeOverride` (> 0) replaces the global edge size for this one border;
-- the outset scales with it.
-- `outsetOverride` (> 0) replaces the derived outset while keeping the edge
-- size: the art draws at the normal weight but hugs the bar tighter, pulling
-- the ridge inward toward/over the fill edge (nameplate castbar uses 1).
function ns:AttachBarBorder(border, target, sizeOverride, outsetOverride)
    if not border or not target or not border.SetBackdrop then return end
    local edge, size = ns:GetBarBorderStyle()
    if sizeOverride and sizeOverride > 0 then size = sizeOverride end
    local o = (edge and size > 1) and math.max(1, math.floor(size / 4 + 0.5)) or 0
    if outsetOverride and outsetOverride > 0 and o > 0 then o = outsetOverride end
    -- An explicit sizeOverride is EXACT: the caller has chosen the size
    -- deliberately (e.g. the nameplate castbar matching the HP bar's ring),
    -- so the height clamp below must not shrink it again.
    local skipClamp = sizeOverride and sizeOverride > 0
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT",     target, "TOPLEFT",     -o,  o)
    border:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT",  o, -o)
    if edge and size > 1 and not skipClamp then
        local h = (target.GetHeight and target:GetHeight() or 0) + 2 * o
        if h > 0 then
            size = math.min(size, math.max(4, math.floor(h / 2)))
        end
    end
    ApplyBarBorderOnly(border, size)
    border:Show()
end

-- Re-apply every live bar border after a settings change (border style and
-- colors are painted at creation, so changes must be pushed to existing
-- frames). Re-runs the full backdrop so edge texture/size changes take too.
function ns:ReapplySharedBorders()
    for _, fname in ipairs({"PlayerFrame","TargetFrame","TargetFrameToT","PetFrame",
                            "PartyMemberFrame1","PartyMemberFrame2","PartyMemberFrame3","PartyMemberFrame4"}) do
        local f = _G[fname]
        local bd = f and f._srBackdrop
        if bd then ns:ApplyStackBackdrop(bd) end
    end
    if ns.UF_ReapplyBarRings then ns.UF_ReapplyBarRings() end
    if ns.NanShield_ReapplyBorder then ns.NanShield_ReapplyBorder() end
    if ns.DruidPowerBar and ns.DruidPowerBar.RefreshBorder then ns.DruidPowerBar:RefreshBorder() end
    -- Re-assert tagged state on top (target may be tapped right now)
    if ns.UF_ApplyTargetTagState then ns.UF_ApplyTargetTagState() end
end

-- The standard TurboFace bar backdrop: dark fill + the configured shared
-- border. Used by the player/target/pet/party unit-frame bars and the
-- nanShield absorb bar so they all stay visually identical from one place.
-- In textured mode the backdrop is FILL-ONLY: each bar carries its own
-- AttachBarBorder ring, and an outer edge here would double-border the stack.
function ns:ApplyBarBackdrop(frame)
    if not frame or not frame.SetBackdrop then return end
    local bc = ns.BAR_BORDER_COLOR
    local edge, size, inset = ns:GetBarBorderStyle()
    if edge and size > 1 then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = edge, edgeSize = size,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
end

-- Stack-wrapper variant for the unit-frame _srBackdrop frames. In ring mode
-- every bar paints its OWN dark background (UnitFrames ApplyBarRing), so the
-- shared stack fill is blanked -- otherwise it bleeds dark through the gap
-- between the HP and power bars. Pixel/None mode keeps the shared fill.
function ns:ApplyStackBackdrop(frame)
    ns:ApplyBarBackdrop(frame)
    if ns:GetBarBorderOutset() > 0 and frame and frame.SetBackdropColor then
        frame:SetBackdropColor(0, 0, 0, 0)
    end
end

-- Edge-only variant for bars that paint their own background/fill textures
-- (swing timer rows, unit castbars, per-bar rings): applies just the
-- configured border to the bar's overlay border frame. `sizeOverride` lets
-- AttachBarBorder pass a height-clamped edge size for short bars.
ApplyBarBorderOnly = function(frame, sizeOverride)
    if not frame or not frame.SetBackdrop then return end
    local edge, size = ns:GetBarBorderStyle()
    if edge then
        local bc = ns.BAR_BORDER_COLOR
        frame:SetBackdrop({ edgeFile = edge, edgeSize = sizeOverride or size })
        frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
    else
        frame:SetBackdrop(nil)
    end
end

-- Central COMBAT_LOG_EVENT_UNFILTERED dispatcher. One frame decodes
-- CombatLogGetCurrentEventInfo() a single time per event. Consumers may provide
-- a set of subevents they care about; filtered consumers are only called for
-- matching traffic instead of every CLEU event. This keeps the shared decoder
-- cheap even as more lightweight systems subscribe to it. The WoW event itself
-- is only subscribed while at least one handler is registered.
do
    -- C_CombatLogInternal is a Blizzard-private implementation detail, not an
    -- addon contract. Forever intentionally withholds combat interpretation;
    -- only the public Classic API/event pair is eligible here.
    local CLGI = type(CombatLogGetCurrentEventInfo) == "function"
        and CombatLogGetCurrentEventInfo or nil
    local CLEU_EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
    local frame = CreateFrame("Frame")
    local wildcardHandlers = {}
    local bySubevent = {}
    local registrations = {}
    local count = 0
    ns.CLEU = {}
    ns.CLEU.Available = CLGI ~= nil and ns.API.IsEventValid(CLEU_EVENT)

    -- subevents is optional. When supplied it is a set-like table:
    -- { SPELL_DAMAGE=true, SWING_DAMAGE=true }. Existing callers that omit it
    -- retain the old receive-everything behavior.
    function ns.CLEU:Register(fn, subevents)
        if not fn or registrations[fn] ~= nil then return end

        if type(subevents) == "table" then
            registrations[fn] = subevents
            for subevent, enabled in pairs(subevents) do
                if enabled then
                    local bucket = bySubevent[subevent]
                    if not bucket then
                        bucket = {}
                        bySubevent[subevent] = bucket
                    end
                    bucket[fn] = true
                end
            end
        else
            registrations[fn] = false
            wildcardHandlers[fn] = true
        end

        count = count + 1
        if count == 1 and ns.CLEU.Available then ns.RegisterEvent(frame, CLEU_EVENT) end
    end

    function ns.CLEU:Unregister(fn)
        if not fn then return end
        local registration = registrations[fn]
        if registration == nil then return end

        if registration == false then
            wildcardHandlers[fn] = nil
        else
            for subevent, enabled in pairs(registration) do
                if enabled then
                    local bucket = bySubevent[subevent]
                    if bucket then
                        bucket[fn] = nil
                        if not next(bucket) then bySubevent[subevent] = nil end
                    end
                end
            end
        end
        registrations[fn] = nil

        count = count - 1
        if count <= 0 then
            count = 0
            if ns.CLEU.Available then frame:UnregisterEvent(CLEU_EVENT) end
        end
    end

    -- Reusable payload table: one table for the addon's lifetime instead of a
    -- fresh allocation per combat log event. CONTRACT: handlers consume it
    -- synchronously and never retain it across frames.
    local e = {}
    local function SharedCLEUOnEvent()
        if not CLGI then return end
        e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10],
        e[11], e[12], e[13], e[14], e[15], e[16], e[17], e[18], e[19], e[20],
        e[21], e[22], e[23], e[24], e[25], e[26] = CLGI()
        local dc = ns.DebugCounters
        if dc then dc.cleu = dc.cleu + 1 end

        local killStart
        if (e[2] == "UNIT_DIED" or e[2] == "UNIT_DESTROYED")
            and ns.CPUProfiler and ns.CPUProfiler.RecordKillDuration
            and ns.CPUProfiler.IsKillTraceWindowActive and ns.CPUProfiler:IsKillTraceWindowActive()
            and debugprofilestop then
            killStart = debugprofilestop()
        end

        for fn in pairs(wildcardHandlers) do
            if dc then dc.cleuHandlers = (dc.cleuHandlers or 0) + 1 end
            fn(e)
        end
        local bucket = bySubevent[e[2]]
        if bucket then
            for fn in pairs(bucket) do
                if dc then dc.cleuHandlers = (dc.cleuHandlers or 0) + 1 end
                fn(e)
            end
        end
        if killStart and debugprofilestop then
            ns.CPUProfiler:RecordKillDuration("Core/CLEU:DeathDispatch", debugprofilestop() - killStart)
        end
    end
    frame:SetScript("OnEvent", SharedCLEUOnEvent)
    -- Child CPU is excluded here; CLEU consumers are profiled separately so
    -- dispatcher overhead stays visible without double-counting subsystem work.
    ns.RegisterCPUProfileTarget("Core/CLEU:Dispatch", SharedCLEUOnEvent, false)
end

-- Defaults and saved-variable migrations live in Core/Defaults.lua and Core/Migrations.lua.
