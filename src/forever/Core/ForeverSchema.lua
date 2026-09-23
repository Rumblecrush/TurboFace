local _, ns = ...

local Schema = ns.Schema
if not Schema then return end

local function EnsureMover(db)
    if type(db.movers) ~= "table" then db.movers = {} end
    if type(db.movers.elements) ~= "table" then db.movers.elements = {} end
    if type(db.movers.elements.SpendTalentPoint) ~= "table" then
        db.movers.elements.SpendTalentPoint = {
            enabled = true, hidden = false, clickThrough = true,
            point = "CENTER", relativePoint = "CENTER", x = 0, y = -120,
        }
    end
end

local MIGRATIONS = {
    -- Forever revision 0 -> 1 (formerly portable DB v79 -> v80): move the
    -- unspent-talent reminder out of ClassBuffs into the standalone HUD.
    [0] = function(db)
        if db.talentReminderEnabled == nil then
            db.talentReminderEnabled = db.classBuffTalentPoints ~= false
        end
        db.classBuffTalentPoints = nil
        EnsureMover(db)
    end,

    -- Forever revision 1 -> 2 (formerly DB v80 -> v81): opt-in movable
    -- Blizzard combined bag. The saved anchor remains runtime layout state.
    [1] = function(db)
        if type(db.plus) ~= "table" then db.plus = {} end
        if db.plus.combinedBagMovable == nil then
            db.plus.combinedBagMovable = false
        end
    end,
}

local function ApplyDefaults(defaults)
    defaults.talentReminderEnabled = true
    defaults.talentReminderFont = "Blizzard Default"
    defaults.talentReminderTextStyle = "OUTLINE"
    defaults.talentReminderFontSize = 18
    defaults.classBuffTalentPoints = nil

    if type(defaults.movers) == "table" and type(defaults.movers.elements) == "table" then
        defaults.movers.elements.SpendTalentPoint = {
            enabled = true, hidden = false, clickThrough = true,
            point = "CENTER", relativePoint = "CENTER", x = 0, y = -120,
        }
    end

    if type(defaults.plus) == "table" then
        defaults.plus.enhanceQuestLevels = nil
        defaults.plus.combinedBagMovable = false
        defaults.plus.showVendorPrice = nil
    end
end

local function PostLoad(db)
    -- Same-version/hand-edited imports must not resurrect the retired
    -- ClassBuffs talent icon on Forever.
    db.classBuffTalentPoints = nil
end

local function AdjustPresets(presets)
    if type(presets) ~= "table" then return end
    for _, preset in pairs(presets) do
        local data = type(preset) == "table" and preset.data or nil
        if type(data) == "table" and type(data.plus) == "table" then
            data.plus.showVendorPrice = nil
        end
    end
end

Schema:RegisterClient("forever", 2, MIGRATIONS, {
    ApplyDefaults = ApplyDefaults,
    PostLoad = PostLoad,
    AdjustPresets = AdjustPresets,
})
