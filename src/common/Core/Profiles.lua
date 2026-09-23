local _, ns = ...

-- =============================================================================
-- TurboFace Profiles.lua — profiles, import/export, presets
--
-- Storage: TurboFaceProfilesDB (account-wide SavedVariable, separate from
-- TurboFaceDB so Reset / profile loads can never destroy the profile library).
--
-- Applying a settings profile/preset/import replaces TurboFaceDB and reloads
-- the UI -- modules cache settings aggressively, so a reload is the only
-- reliable way to reapply everything. XP session history is per-character and
-- transfers separately through TFXP1. Settings snapshots keep their dbVersion,
-- so loading a profile saved by an older TurboFace runs normal migrations.
-- =============================================================================

local Profiles = {}
ns.Profiles = Profiles

local function PDB()
    if type(TurboFaceProfilesDB) ~= "table" then TurboFaceProfilesDB = {} end
    if type(TurboFaceProfilesDB.profiles) ~= "table" then TurboFaceProfilesDB.profiles = {} end
    return TurboFaceProfilesDB
end

-- Keys never included in snapshots/exports (internal bookkeeping)
local SNAPSHOT_SKIP = {
    __migrations = true,
    __clientRevisions = true,
    __foreverSettingsRevision = true, -- legacy Prep127-and-earlier internal marker
}

local function SnapshotCopy(src)
    local copy = {}
    for k, v in pairs(src) do
        if not SNAPSHOT_SKIP[k] then
            copy[k] = ns.DeepCopy(v)
            -- XP run/session history is per-character state with its own
            -- TFXP1 import/export path. Never let settings profiles carry it,
            -- including profiles saved before the storage split.
            if k == "experienceBar" and type(copy[k]) == "table" then
                copy[k].session = nil
            end
        end
    end
    return copy
end

-- =============================================================================
-- SERIALIZER (Lua-literal). Deserialization uses a strict data-only parser;
-- imported text is never compiled or executed.
-- =============================================================================

local EXPORT_PREFIX = "TF1:"

local function SerializeValue(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = string.format("%.17g", v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number")
            and (vt == "number" or vt == "boolean" or vt == "string" or vt == "table") then
                if kt == "string" then
                    out[#out + 1] = "[" .. string.format("%q", k) .. "]="
                else
                    out[#out + 1] = "[" .. string.format("%.17g", k) .. "]="
                end
                SerializeValue(val, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    end
end

function Profiles.Serialize(tbl)
    local out = {}
    SerializeValue(tbl, out)
    return table.concat(out)
end

local MAX_IMPORT_BYTES = 512 * 1024
local MAX_IMPORT_DEPTH = 32
local MAX_IMPORT_NODES = 25000

local ESCAPES = {
    a = "\a", b = "\b", f = "\f", n = "\n",
    r = "\r", t = "\t", v = "\v",
    ["\\"] = "\\", ["\""] = "\"", ["'"] = "'",
}

local function ParseError(parser, message)
    return nil, ("not a valid TurboFace export (%s at character %d)"):format(message, parser.pos or 1)
end

local function SkipSpace(parser)
    local s, len, pos = parser.str, parser.len, parser.pos
    while pos <= len and s:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    parser.pos = pos
end

local function Consume(parser, expected)
    SkipSpace(parser)
    if parser.str:sub(parser.pos, parser.pos + #expected - 1) ~= expected then
        return ParseError(parser, "expected " .. expected)
    end
    parser.pos = parser.pos + #expected
    return true
end

local function CountNode(parser)
    parser.nodes = parser.nodes + 1
    if parser.nodes > MAX_IMPORT_NODES then
        return ParseError(parser, "too many values")
    end
    return true
end

local function ParseString(parser)
    SkipSpace(parser)
    local s, len, pos = parser.str, parser.len, parser.pos
    local quote = s:sub(pos, pos)
    if quote ~= '"' and quote ~= "'" then
        return ParseError(parser, "expected quoted string")
    end
    pos = pos + 1
    local out, outN = {}, 0

    while pos <= len do
        local ch = s:sub(pos, pos)
        if ch == quote then
            parser.pos = pos + 1
            return table.concat(out)
        elseif ch == "\\" then
            pos = pos + 1
            if pos > len then return ParseError(parser, "unfinished string escape") end
            local esc = s:sub(pos, pos)
            local mapped = ESCAPES[esc]
            if mapped then
                outN = outN + 1
                out[outN] = mapped
                pos = pos + 1
            elseif esc:match("%d") then
                local first = pos
                local count = 0
                while pos <= len and count < 3 and s:sub(pos, pos):match("%d") do
                    pos = pos + 1
                    count = count + 1
                end
                local byte = tonumber(s:sub(first, pos - 1))
                if not byte or byte > 255 then return ParseError(parser, "invalid numeric escape") end
                outN = outN + 1
                out[outN] = string.char(byte)
            elseif esc == "\n" then
                outN = outN + 1
                out[outN] = "\n"
                pos = pos + 1
            elseif esc == "\r" then
                outN = outN + 1
                out[outN] = "\n"
                pos = pos + 1
                if s:sub(pos, pos) == "\n" then pos = pos + 1 end
            else
                return ParseError(parser, "unsupported string escape")
            end
        elseif ch == "\n" or ch == "\r" then
            return ParseError(parser, "unterminated string")
        else
            outN = outN + 1
            out[outN] = ch
            pos = pos + 1
        end
    end
    return ParseError(parser, "unterminated string")
end

local function ParseNumber(parser)
    SkipSpace(parser)
    local s, len, pos = parser.str, parser.len, parser.pos
    local first = pos
    while pos <= len do
        local ch = s:sub(pos, pos)
        if not ch:match("[0-9eE+%.%-]") then break end
        pos = pos + 1
    end
    if pos == first then return ParseError(parser, "expected number") end
    local token = s:sub(first, pos - 1)
    local value = tonumber(token)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return ParseError(parser, "invalid number")
    end
    parser.pos = pos
    return value
end

local ParseValue

local function ParseKey(parser)
    SkipSpace(parser)
    local ch = parser.str:sub(parser.pos, parser.pos)
    if ch == '"' or ch == "'" then
        return ParseString(parser)
    end
    return ParseNumber(parser)
end

local function ParseTable(parser, depth)
    if depth > MAX_IMPORT_DEPTH then
        return ParseError(parser, "table nesting is too deep")
    end
    local ok, err = CountNode(parser)
    if not ok then return nil, err end
    ok, err = Consume(parser, "{")
    if not ok then return nil, err end

    local result = {}
    SkipSpace(parser)
    if parser.str:sub(parser.pos, parser.pos) == "}" then
        parser.pos = parser.pos + 1
        return result
    end

    while true do
        ok, err = Consume(parser, "[")
        if not ok then return nil, err end
        local key
        key, err = ParseKey(parser)
        if key == nil then return nil, err end
        ok, err = Consume(parser, "]")
        if not ok then return nil, err end
        ok, err = Consume(parser, "=")
        if not ok then return nil, err end

        local value
        value, err = ParseValue(parser, depth + 1)
        if value == nil then return nil, err end
        if result[key] ~= nil then return ParseError(parser, "duplicate table key") end
        result[key] = value

        SkipSpace(parser)
        local ch = parser.str:sub(parser.pos, parser.pos)
        if ch == "," then
            parser.pos = parser.pos + 1
            SkipSpace(parser)
            if parser.str:sub(parser.pos, parser.pos) == "}" then
                parser.pos = parser.pos + 1
                return result
            end
        elseif ch == "}" then
            parser.pos = parser.pos + 1
            return result
        else
            return ParseError(parser, "expected comma or closing brace")
        end
    end
end

ParseValue = function(parser, depth)
    SkipSpace(parser)
    local ch = parser.str:sub(parser.pos, parser.pos)
    if ch == "{" then
        return ParseTable(parser, depth)
    elseif ch == '"' or ch == "'" then
        local ok, err = CountNode(parser)
        if not ok then return nil, err end
        return ParseString(parser)
    elseif parser.str:sub(parser.pos, parser.pos + 3) == "true" then
        local ok, err = CountNode(parser)
        if not ok then return nil, err end
        parser.pos = parser.pos + 4
        return true
    elseif parser.str:sub(parser.pos, parser.pos + 4) == "false" then
        local ok, err = CountNode(parser)
        if not ok then return nil, err end
        parser.pos = parser.pos + 5
        return false
    else
        local ok, err = CountNode(parser)
        if not ok then return nil, err end
        return ParseNumber(parser)
    end
end

function Profiles.Deserialize(str)
    if type(str) ~= "string" or str == "" then return nil, "empty string" end
    if #str > MAX_IMPORT_BYTES then
        return nil, ("TurboFace import is too large (maximum %d KB)"):format(MAX_IMPORT_BYTES / 1024)
    end

    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        str = str:sub(#EXPORT_PREFIX + 1)
    end
    if #str > MAX_IMPORT_BYTES then
        return nil, ("TurboFace import is too large (maximum %d KB)"):format(MAX_IMPORT_BYTES / 1024)
    end

    local parser = { str = str, len = #str, pos = 1, nodes = 0 }
    local result, err = ParseValue(parser, 1)
    if result == nil then return nil, err end
    SkipSpace(parser)
    if parser.pos <= parser.len then return ParseError(parser, "unexpected trailing data") end
    if type(result) ~= "table" then return nil, "not a valid TurboFace export (not a table)" end

    local version = result.dbVersion
    if version ~= nil then
        if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
            return nil, "not a valid TurboFace export (invalid database version)"
        end
        if ns.Schema and ns.Schema.IsImportVersionSupported then
            if not ns.Schema:IsImportVersionSupported(version) then
                return nil, "this profile was created by a newer TurboFace version"
            end
        elseif ns.DB_VERSION and version > ns.DB_VERSION then
            return nil, "this profile was created by a newer TurboFace version"
        end
    end
    return result
end

-- =============================================================================
-- PROFILES
-- =============================================================================

function Profiles:List()
    local names = {}
    for name in pairs(PDB().profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Profiles:Exists(name)
    return name and PDB().profiles[name] ~= nil
end

function Profiles:Save(name)
    if type(name) ~= "string" or name:gsub("%s", "") == "" then
        ns:Chat("Profiles", "enter a profile name first")
        return false
    end
    local existed = self:Exists(name)
    PDB().profiles[name] = SnapshotCopy(TurboFaceDB or {})
    ns:Chat("Profiles", (existed and "updated" or "saved") .. " profile |cff00ccff" .. name .. "|r")
    return true
end

-- Replaces settings and reloads. Callers confirm via StaticPopup first.
function Profiles:Load(name)
    local snap = PDB().profiles[name]
    if snap == nil then
        ns:Chat("Profiles", "no such profile: " .. tostring(name))
        return false
    end
    if type(snap) ~= "table" then
        ns:Chat("Profiles", "profile data is invalid: " .. tostring(name))
        return false
    end
    TurboFaceDB = SnapshotCopy(snap)
    ReloadUI()
    return true
end

function Profiles:Delete(name)
    if not self:Exists(name) then return false end
    PDB().profiles[name] = nil
    ns:Chat("Profiles", "deleted profile |cff00ccff" .. tostring(name) .. "|r")
    return true
end

-- =============================================================================
-- IMPORT / EXPORT
-- =============================================================================

function Profiles:Export()
    return EXPORT_PREFIX .. self.Serialize(SnapshotCopy(TurboFaceDB or {}))
end

-- Validates only; returns parsed table or nil+error
function Profiles:ValidateImport(str)
    return self.Deserialize(str)
end

-- Replaces settings and reloads. Callers confirm via StaticPopup first.
function Profiles:ImportApply(parsed)
    if type(parsed) ~= "table" then return false end
    local clean = SnapshotCopy(parsed)
    clean.__migrations = nil
    if ns.Schema and ns.Schema.PrepareImportedProfile then
        clean = ns.Schema:PrepareImportedProfile(clean)
    end
    TurboFaceDB = clean
    ReloadUI()
end

-- XP session transfers are deliberately distinct from TF1 settings profiles.
-- The strict TF1 data parser still performs all parsing; the unique prefix and
-- exact field allowlist prevent either format from being accepted in the wrong
-- import surface.
local XP_EXPORT_PREFIX = "TFXP1:"
local XP_SESSION_VERSION = 1
local XP_SESSION_FIELDS = {
    gainedXP = true,
    lastXP = true,
    maxXP = true,
    startTime = true,
    realTotalTime = true,
    realLevelTime = true,
    lastTimePlayedRequest = true,
}

local function CopyXPSession(session)
    local out = {}
    if type(session) ~= "table" then return out end
    for key in pairs(XP_SESSION_FIELDS) do
        local value = tonumber(session[key])
        if value and value >= 0 and value < math.huge then
            out[key] = math.floor(value + 0.5)
        end
    end
    return out
end

function Profiles:ExportXPSession()
    local session = ns.XP and ns.XP.GetSessionSnapshot and ns.XP:GetSessionSnapshot() or {}
    return XP_EXPORT_PREFIX .. self.Serialize({
        version = XP_SESSION_VERSION,
        session = CopyXPSession(session),
    })
end

function Profiles:ValidateXPSessionImport(str)
    if type(str) ~= "string" then return nil, "empty string" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str:sub(1, #XP_EXPORT_PREFIX) ~= XP_EXPORT_PREFIX then
        return nil, "not a valid XP session export (expected TFXP1 prefix)"
    end
    local parsed, err = self.Deserialize(str:sub(#XP_EXPORT_PREFIX + 1))
    if not parsed then return nil, err end
    if parsed.version ~= XP_SESSION_VERSION or type(parsed.session) ~= "table" then
        return nil, "not a valid XP session export (unsupported version or missing session)"
    end
    for key, value in pairs(parsed.session) do
        if not XP_SESSION_FIELDS[key] then
            return nil, "not a valid XP session export (unknown session field)"
        end
        if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
            return nil, "not a valid XP session export (invalid session value)"
        end
    end
    for key in pairs(XP_SESSION_FIELDS) do
        if type(parsed.session[key]) ~= "number" then
            return nil, "not a valid XP session export (missing session field)"
        end
    end
    return CopyXPSession(parsed.session)
end

function Profiles:ImportXPSession(session)
    if type(session) ~= "table" or not (ns.XP and ns.XP.ImportSession) then return false end
    ns.XP:ImportSession(CopyXPSession(session))
    return true
end

-- =============================================================================
-- PRESETS — one-click configurations.
--
-- A preset's `data` is applied on top of FACTORY DEFAULTS (not current
-- settings), so the result is always predictable. Only list the keys that
-- differ from defaults. `schemaVersion` identifies the database shape represented
-- by a dated preset; normal startup migrations upgrade it before the defaults
-- merge. Factory Defaults is the exception: its data is intentionally empty, so
-- it always declares the live `ns.DB_VERSION` and lands directly on current defaults.
-- Omit schemaVersion only for legacy/v1 preset data.
--
-- TO ADD A PRESET: append an entry here. That's it — the Profile tab renders
-- one row per entry automatically.
-- =============================================================================

Profiles.Presets = {
    {
        name = "Factory Defaults",
        desc = "Everything back to TurboFace's shipped defaults.",
        schemaVersion = ns.DB_VERSION,
        data = {},
    },
    -- NOTE: the "Performance Focused" and "Everything On" presets were
    -- removed (untested against the current feature set); re-add here when
    -- there is time to validate them.
    {
        name = "Rumblecrush's Preset",
        desc = "2026-09-15",
        schemaVersion = 79,
        data = {
                ["bagSlotsEnabled"]=true,
                ["auraTargetBuffScale"]=1.299999952316284,
                ["auraTargetDebuffScale"]=1.299999952316284,
                ["barBorderColor"]={
                    ["b"]=0.51764708757400513,
                    ["g"]=0.63921570777893066,
                    ["r"]=0.70980393886566162,
                },
                ["bubbleNameplates"]={
                    ["friendlyNPCDamagedOnly"]=true,
                    ["friendlyNPCNameTitleOnly"]=true,
                    ["friendlyPlayerDamagedOnly"]=true,
                    ["notSelectedAlpha"]=1,
                    ["powerBarHeightPct"]=0.29999998211860662,
                    ["powerBarOverlap"]=true,
                    ["rarityIconRight"]=true,
                    ["threatNumber"]=true,
                    ["threatTextFontSize"]=14,
                },
                ["classBuffFearWard"]=true,
                ["classBuffGrowth"]="DOWN",
                ["classBuffIconSize"]=36,
                ["classBuffShadowProtection"]=true,
                ["classTextStyle"]="OUTLINE",
                ["castBarsTextStyle"]="OUTLINE",
                ["combatMeterEnabled"]=true,
                ["combatMeterTextStyle"]="OUTLINE",
                ["combatMeterWidth"]=230,
                ["dotPredictionEnabled"]=true,
                ["dotPredictionIncludeParty"]=true,
                ["druidPowerBarStatusText"]=true,
                ["druidPowerBarTextFormat"]="current",
                ["druidPowerBarTexture"]="Clean",
                ["experienceBar"]={
                    ["enabled"]=true,
                    ["textStyle"]="OUTLINE",
                    ["colorXP"]={
                        ["b"]=0.92156869173049927,
                        ["g"]=0.062745101749897003,
                        ["r"]=0.77647066116333008,
                    },
                    ["showIncompleteQuestBar"]=false,
                    ["showInsideLevelText"]=false,
                    ["showInsidePercentText"]=false,
                    ["showLevelTimeText"]=false,
                    ["showSessionTimeText"]=false,
                    ["textBlockAbove"]=true,
                    ["texture"]="Blizzard Raid Bar",
                    ["width"]=235,
                },
                ["fpsCounterEnabled"]=true,
                ["groceryBorderMode"]="legacy",
                ["groceryEnabled"]=true,
                ["groceryFramePoint"]="TOPRIGHT",
                ["groceryFrameX"]=-242.15289306640631,
                ["groceryFrameY"]=-11.83949184417725,
                ["groceryShowQueue"]=false,
                ["healPredictionEnabled"]=true,
                ["hearthBatchEnabled"]=true,
                ["hearthEnabled"]=true,
                ["hearthTextStyle"]="OUTLINE",
                ["invMarkMouseShortcut"]="CTRL-RIGHT",
                ["leashTimerEnabled"]=true,
                ["leashTimerTextStyle"]="OUTLINE",
                ["lootFrame"]={
                    ["textStyle"]="OUTLINE",
                    ["rowHeight"]=32,
                    ["spacing"]=2,
                    ["width"]=180,
                },
                ["map"]={
                    ["point"]="TOP",
                    ["relPoint"]="TOP",
                    ["x"]=6.6889853477478027,
                    ["y"]=-40.533355712890632,
                },
                ["minimapButtonAngle"]=1.117070212969338,
                -- Module/category gates are stored separately from their child
                -- settings. Keep the preset's exact enabled state here so a
                -- sparse preset cannot restore configured children underneath
                -- disabled parents.
                ["modules"]={
                    ["unitframes"]={
                        ["enabled"]=true,
                        ["player"]=true,
                        ["target"]=true,
                        ["tot"]=true,
                        ["party"]=true,
                        ["pet"]=true,
                    },
                    ["nameplates"]={
                        ["enabled"]=true,
                    },
                    ["auras"]={
                        ["enabled"]=true,
                        ["tot"]=true,
                        ["party"]=true,
                        ["pet"]=true,
                    },
                    ["hotbarPower"]={
                        ["enabled"]=true,
                    },
                    ["playerTicks"]={
                        ["enabled"]=true,
                    },
                    ["swingTimers"]={
                        ["enabled"]=true,
                    },
                    ["castBars"]={
                        ["enabled"]=true,
                    },
                    ["class"]={
                        ["enabled"]=true,
                    },
                    ["plus"]={
                        ["enabled"]=true,
                        ["automation"]=true,
                        ["social"]=true,
                        ["interface"]=true,
                        ["minimap"]=true,
                        ["chat"]=true,
                        ["system"]=true,
                        ["flightBar"]=true,
                        ["map"]=true,
                    },
                },
                ["movers"]={
                    ["activeElement"]="CombatMeter",
                    ["aura"]={
                        ["spacingX"]=6,
                        ["spacingY"]=6,
                        ["targetDebuffGrowth"]="RIGHT_UP",
                        ["targetPerRow"]=6,
                    },
                    ["elements"]={
                        ["BagSlots"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=410,
                            ["y"]=-380,
                        },
                        ["BlizzardLootFrame"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=340,
                            ["y"]=295,
                        },
                        ["ClassBuffBar"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=0,
                            ["y"]=-210,
                        },
                        ["CombatMeter"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=642,
                            ["y"]=-100,
                        },
                        ["ExperienceBar"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-640,
                            ["y"]=-166,
                        },
                        ["FlightBar"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-5,
                            ["y"]=270,
                        },
                        ["FPSCounter"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-300,
                            ["y"]=-370,
                        },
                        ["GameTooltip"]={
                            ["enabled"]=true,
                            ["maxWidth"]=120,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=630,
                            ["y"]=-100,
                        },
                        ["GroceryButton"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=410,
                            ["y"]=-408,
                        },
                        ["GroupLootRolls"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=0,
                            ["y"]=120,
                        },
                        ["Hearthstone"]={
                            ["clickThrough"]=false,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-640,
                            ["y"]=-140,
                        },
                        ["LatencyBar"]={
                            ["clickThrough"]=true,
                            ["enabled"]=true,
                            ["hidden"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-415,
                            ["y"]=310,
                        },
                        ["LeashTimer"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=400,
                            ["y"]=-95,
                        },
                        ["LootFrame"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=355,
                            ["y"]=0,
                        },
                        ["MinimapClock"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-640,
                            ["y"]=-410,
                        },
                        ["MinimapLFG"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-495,
                            ["y"]=-405,
                        },
                        ["MinimapMail"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-543,
                            ["y"]=-214,
                        },
                        ["NetWorth"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=300,
                            ["y"]=-370,
                        },
                        ["QuestTracker"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=635,
                            ["y"]=130,
                        },
                        ["SkillTracker"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-475,
                            ["y"]=-305,
                        },
                        ["SpeedrunSplits"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-620,
                            ["y"]=305,
                        },
                        ["TargetBuffs"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=314,
                            ["y"]=-199,
                        },
                        ["TargetDebuffs"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=105,
                            ["y"]=-160,
                        },
                        ["TargetFrameToT"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=275,
                            ["y"]=-150,
                        },
                        ["ToTDebuffs"]={
                            ["enabled"]=true,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=290,
                            ["y"]=-120,
                        },
                        ["TrackingIcon"]={
                            ["clickThrough"]=false,
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-545,
                            ["y"]=-405,
                        },
                        ["UnstuckSkips"]={
                            ["point"]="CENTER",
                            ["relativePoint"]="CENTER",
                            ["x"]=-582,
                            ["y"]=415,
                        },
                    },
                    ["gridSize"]=10,
                },
                ["netWorthColor"]={
                    ["b"]=1,
                    ["g"]=0.98823535442352295,
                    ["r"]=0.96862751245498657,
                },
                ["netWorthEnabled"]=true,
                ["netWorthFontSize"]=12,
                ["plus"]={
                    ["acceptResNoCombat"]=false,
                    ["autoQuestAccept"]=true,
                    ["autoQuestTurnIn"]=true,
                    ["automateGossip"]=true,
                    ["automateSpiritHealer"]=true,
                    ["autoRepairSummary"]=false,
                    ["chatTextOutline"]=true,
                    ["fasterLooting"]=true,
                    ["hideMacroText"]=true,
                    ["hideMiniDayNight"]=true,
                    ["hideMiniLFG"]=true,
                    ["hideMiniZoomBtns"]=true,
                    ["mapEnhancedZoom"]=true,
                    ["mapMovable"]=true,
                    ["maxCameraZoom"]=true,
                    ["minimapBorderOffset"]=-1,
                    ["minimapBorderTexture"]="Blizzard Dialog",
                    ["minimapBorderWidth"]=11,
                    ["minimapShape"]="square",
                    ["minimapSize"]=235,
                    ["minimapZoneTextSize"]=16,
                    ["noChatButtons"]=true,
                    ["showVendorPrice"]=true,
                    ["unclampChat"]=true,
                },
                ["power"]={
                    ["textStyle"]="OUTLINE",
                    ["tickTextStyle"]="OUTLINE",
                    ["counterColor"]={
                        ["a"]=1,
                        ["b"]=0.26274511218070978,
                        ["g"]=0.82352948188781738,
                    },
                    ["decimals"]=0,
                    ["fontSize"]=13,
                    ["healthTickAmount"]=true,
                    ["overlayAlpha"]=1,
                    ["overlayColor"]={
                        ["a"]=0.39797025918960571,
                        ["b"]=1,
                        ["g"]=0.30196079611778259,
                        ["r"]=0.30196079611778259,
                    },
                    ["powerTickAmount"]=true,
                    ["textOffsetX"]=-11,
                    ["textOffsetY"]=11,
                    ["tickAmountOffsetX"]=27,
                    ["tickAmountSize"]=12,
                    ["useCustomCounterColor"]=true,
                    ["useCustomOverlayColor"]=true,
                },
                ["quickSetup"]={
                    ["enabled"]=true,
                },
                ["skillTrackerEnabled"]=true,
                ["swingTimersTextStyle"]="OUTLINE",
                ["unstuckSkipTextStyle"]="OUTLINE",
                ["skillTrackerEquippedWeaponsOnly"]=true,
                ["speedrunSplits"]={
                    ["textStyle"]="OUTLINE",
                    ["enabled"]=true,
                    ["showPartials"]=false,
                },
                ["taggedIndicatorColor"]={
                    ["b"]=0.14901961386203769,
                    ["g"]=0.14901961386203769,
                    ["r"]=0.14901961386203769,
                },
                ["trackerEnabled"]=true,
                ["unitframes"]={
                    ["barFontSize"]=11,
                    ["embedCombatTimers"]=true,
                    ["enemyColor"]={
                        ["b"]=0.1215686351060867,
                        ["g"]=0.2000000178813934,
                        ["r"]=1,
                    },
                    ["friendlyColor"]={
                        ["b"]=0,
                        ["g"]=0.4666666984558106,
                        ["r"]=0,
                    },
                    ["nanShieldFontSize"]=10,
                    ["nanShieldHeight"]=18,
                    ["nanShieldPerSection"]=true,
                    ["partyHealthFormat"]="current-max",
                    ["partyPowerFormat"]="current",
                    ["petHealthFormat"]="current",
                    ["petPowerFormat"]="current",
                    ["playerHealthColor"]={
                        ["b"]=0.20392158627510071,
                        ["g"]=0.88627457618713379,
                        ["r"]=0.20392158627510071,
                    },
                    ["playerHealthFormat"]="current",
                    ["playerPowerFormat"]="current",
                    ["targetHealthFormat"]="current",
                    ["targetPowerFormat"]="current",
                    ["targetXPColor"]={
                        ["b"]=0.73725491762161255,
                        ["g"]=0,
                        ["r"]=0.7725490927696228,
                    },
                    ["targetXPPerHP"]=true,
                    ["totHealthFormat"]="current",
                    ["totNameFontSize"]=9,
                    ["totPowerFormat"]="current",
                },
                ["unstuckSkipVisualEnabled"]=true,
            }
    },
}

if ns.Schema and ns.Schema.AdjustBuiltInPresets then
    ns.Schema:AdjustBuiltInPresets(Profiles.Presets)
end

function Profiles:GetPreset(name)
    for _, p in ipairs(self.Presets) do
        if p.name == name then return p end
    end
end

-- Replaces settings and reloads. Callers confirm via StaticPopup first.
function Profiles:ApplyPreset(name)
    local preset = self:GetPreset(name)
    if not preset then return false end
    TurboFaceDB = ns.DeepCopy(preset.data)
    -- Never claim a preset is newer than its serialized shape. LoadVariables
    -- runs the exact same ordered migrations used for saved profiles.
    TurboFaceDB.dbVersion = tonumber(preset.schemaVersion) or 1
    ReloadUI()
end