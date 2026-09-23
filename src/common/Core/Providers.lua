local _, ns = ...

-- =============================================================================
-- TurboFace client-provider registry
--
-- Shared feature code should depend on a provider contract rather than choose a
-- client implementation itself.  Providers register under a named surface with
-- a priority; the highest-priority supported provider wins.  This keeps client
-- selection out of shared renderers/controllers while retaining explicit,
-- inspectable ownership.
-- =============================================================================

local Providers = {}
ns.Providers = Providers

local groups = {}
local activeCache = {}

local function Supported(provider)
    if type(provider) ~= "table" then return false end
    if type(provider.IsSupported) ~= "function" then return true end
    local ok, supported = pcall(provider.IsSupported, provider)
    return ok and supported ~= false
end

function Providers:Register(group, name, provider, priority)
    if type(group) ~= "string" or group == "" then return false end
    if type(name) ~= "string" or name == "" then return false end
    if type(provider) ~= "table" then return false end

    local bucket = groups[group]
    if not bucket then
        bucket = {}
        groups[group] = bucket
    end

    bucket[name] = {
        name = name,
        provider = provider,
        priority = tonumber(priority) or 0,
    }
    activeCache[group] = nil
    return true
end

function Providers:Get(group)
    local cached = activeCache[group]
    if cached ~= nil then return cached ~= false and cached or nil end

    local bucket = groups[group]
    local best, bestName, bestPriority
    if bucket then
        for name, entry in pairs(bucket) do
            if Supported(entry.provider) and (best == nil
                or entry.priority > bestPriority
                or (entry.priority == bestPriority and name < bestName)) then
                best = entry.provider
                bestName = name
                bestPriority = entry.priority
            end
        end
    end

    activeCache[group] = best or false
    return best
end

function Providers:IsActive(group, provider)
    return provider ~= nil and self:Get(group) == provider
end

function Providers:Invalidate(group)
    if group then
        activeCache[group] = nil
    else
        for key in pairs(activeCache) do activeCache[key] = nil end
    end
end

function Providers:Call(group, method, ...)
    local provider = self:Get(group)
    local fn = provider and provider[method]
    if type(fn) ~= "function" then return nil end
    return fn(provider, ...)
end

function Providers:GetName(group)
    local provider = self:Get(group)
    if not provider then return nil end
    local bucket = groups[group]
    if not bucket then return nil end
    for name, entry in pairs(bucket) do
        if entry.provider == provider then return name end
    end
    return nil
end
