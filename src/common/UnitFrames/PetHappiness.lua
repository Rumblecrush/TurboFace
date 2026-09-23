local _, ns = ...

-- Public happiness data is deliberately handled as a simple state, not a
-- countdown. Classic exposes only the three mood tiers, so query it once per
-- second and let ClassBuffs render its normal Feed Pet reminder when needed.
local PetHappiness = {}
ns.PetHappiness = PetHappiness

local _, PLAYER_CLASS = UnitClass("player")
local cadenceToken = {}
local active = false
local needsFeed = false

function PetHappiness.NeedsFeed()
    return needsFeed
end

function PetHappiness.Refresh()
    local happiness = active and GetPetHappiness and GetPetHappiness() or nil
    local nextNeedsFeed = happiness ~= nil and happiness < 3
    if nextNeedsFeed == needsFeed then return end
    needsFeed = nextNeedsFeed
    if ns.ClassBuffs and ns.ClassBuffs.RefreshPetHappinessReminder then
        ns.ClassBuffs:RefreshPetHappinessReminder()
    end
end

function PetHappiness.SetActive(enabled)
    enabled = enabled == true and PLAYER_CLASS == "HUNTER"
    if active == enabled then return end
    active = enabled
    if active then
        PetHappiness.Refresh()
        ns.Cadence:Add(cadenceToken, 1.0, PetHappiness.Refresh)
    else
        ns.Cadence:Remove(cadenceToken)
        needsFeed = false
    end
end
