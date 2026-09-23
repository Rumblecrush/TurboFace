local _, ns = ...

-- =============================================================================
-- TurboFace portable schema + client revision contract
--
-- dbVersion describes the client-independent settings shape that may travel in
-- TF1 profiles between Classic and Forever.  Client-only migrations live on a
-- second axis under __clientRevisions and are deliberately excluded from
-- profile snapshots/exports.
-- =============================================================================

local Schema = {}
ns.Schema = Schema

Schema.PORTABLE_VERSION = 79
Schema.LEGACY_FOREVER_DB_MAX = 81
Schema.INTERNAL_REVISION_KEY = "__clientRevisions"

local clientRevisions = {}
local clientMigrations = {}
local defaultsAdapters = {}
local postLoadAdapters = {}
local presetAdapters = {}

local function Flavor()
    return ns.Client and ns.Client.flavor or "classic"
end

local function RevisionTable(db, create)
    if type(db) ~= "table" then return nil end
    local key = Schema.INTERNAL_REVISION_KEY
    local revisions = db[key]
    if type(revisions) ~= "table" then
        if not create then return nil end
        revisions = {}
        db[key] = revisions
    end
    return revisions
end

function Schema:RegisterClient(flavor, revision, migrations, callbacks)
    if type(flavor) ~= "string" or flavor == "" then return false end
    clientRevisions[flavor] = math.max(0, math.floor(tonumber(revision) or 0))
    clientMigrations[flavor] = type(migrations) == "table" and migrations or {}
    callbacks = type(callbacks) == "table" and callbacks or {}
    defaultsAdapters[flavor] = callbacks.ApplyDefaults
    postLoadAdapters[flavor] = callbacks.PostLoad
    presetAdapters[flavor] = callbacks.AdjustPresets
    return true
end

function Schema:GetClientRevision(flavor)
    return clientRevisions[flavor or Flavor()] or 0
end

function Schema:GetStoredClientRevision(db, flavor)
    local revisions = RevisionTable(db, false)
    local value = revisions and revisions[flavor or Flavor()]
    value = tonumber(value)
    if not value or value < 0 or value % 1 ~= 0 then return 0 end
    return math.floor(value)
end

function Schema:SetStoredClientRevision(db, revision, flavor)
    local revisions = RevisionTable(db, true)
    if not revisions then return end
    revisions[flavor or Flavor()] = math.max(0, math.floor(tonumber(revision) or 0))
end

-- Prep127 and earlier encoded Forever-only changes by advancing dbVersion to
-- 80/81.  Adopt those saves without replaying their already-completed steps,
-- then return dbVersion to the portable schema axis.
function Schema:AdoptLegacyVersion(db)
    if type(db) ~= "table" then return end
    local version = tonumber(db.dbVersion)
    if not version or version % 1 ~= 0 then return end

    if version > self.PORTABLE_VERSION and version <= self.LEGACY_FOREVER_DB_MAX then
        if Flavor() == "forever" then
            local legacyRevision = version - self.PORTABLE_VERSION
            if legacyRevision > self:GetStoredClientRevision(db, "forever") then
                self:SetStoredClientRevision(db, legacyRevision, "forever")
            end
        end
        db.dbVersion = self.PORTABLE_VERSION
    end
end

function Schema:RunClientMigrations(db)
    if type(db) ~= "table" then return end
    local flavor = Flavor()
    local target = self:GetClientRevision(flavor)
    if target <= 0 then return end
    local current = self:GetStoredClientRevision(db, flavor)
    if current > target then current = target end
    local migrations = clientMigrations[flavor] or {}
    while current < target do
        local step = migrations[current]
        if type(step) == "function" then step(db) end
        current = current + 1
    end
    self:SetStoredClientRevision(db, target, flavor)
end

function Schema:ApplyClientDefaults(defaults)
    local fn = defaultsAdapters[Flavor()]
    if type(fn) == "function" then fn(defaults) end
end

function Schema:PostLoad(db)
    local fn = postLoadAdapters[Flavor()]
    if type(fn) == "function" then fn(db) end
end

function Schema:AdjustBuiltInPresets(presets)
    local fn = presetAdapters[Flavor()]
    if type(fn) == "function" then fn(presets) end
end

function Schema:IsImportVersionSupported(version)
    if version == nil then return true end
    if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then return false end
    if version <= self.PORTABLE_VERSION then return true end
    -- Transitional compatibility for TF1 exports created by Forever Prep127
    -- and earlier before the portable/client schema split.
    return version <= self.LEGACY_FOREVER_DB_MAX
end

function Schema:PrepareImportedProfile(profile)
    if type(profile) ~= "table" then return profile end
    profile[self.INTERNAL_REVISION_KEY] = nil
    profile.__foreverSettingsRevision = nil
    self:AdoptLegacyVersion(profile)
    return profile
end
