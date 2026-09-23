local _, ns = ...

-- Forever native-UI ownership provider. The modern WorldMap MapCanvas owns its
-- protected zoom/pan/provider state; TurboFace may retain only the safe movable
-- window amendment implemented by shared Plus/MapTweaks.lua.
local Forever = {}

function Forever:IsSupported()
    return ns.Client and ns.Client:IsForever() or false
end

function Forever:OwnsNativeMapCanvas()
    return true
end

function Forever:SupportsVendorPriceTooltip()
    return false
end

if ns.Providers and ns.Providers.Register then
    ns.Providers:Register("plusUI", "forever-native-ui", Forever, 100)
end