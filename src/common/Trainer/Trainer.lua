local _, ns = ...

-- =============================================================================
-- TRAINING -- bootstrap
--
-- TurboFace owns the runtime trainer browser, capture pipeline, queueing,
-- spellbook integration, filtering, and UI.  The bundled CLASS/PET seed catalog
-- is derived from What's Training? by Fusionpit under the MIT License; see
-- Licenses/WhatsTraining-MIT.txt. Profession trainer recipes use the embedded
-- Classic Era subset of LibProfessionDB (MIT) as a static baseline, enriched
-- with cost/status data discovered from Blizzard APIs during play. The separate
-- Recipes browser uses the same library for externally acquired recipes; see
-- Licenses/LibProfessionDB-MIT.txt and THIRD_PARTY_NOTICES.md.
--
-- SAVED VARIABLES
--
--   TurboFaceTrainerDB      account-wide discovered trainer/merchant data plus
--                           the merged MIT class/pet seed catalog. It is kept
--                           separate from profile configuration and build-cache
--                           data because trainer discovery is persistent user
--                           data.
--   TurboFaceTrainerCharDB  per-character ignores, collapsed groups, known pet
--                           spells, and training queue state.
--
-- Feature settings live as flat trainer* keys in TurboFaceDB.
-- =============================================================================

local Trainer = {}
ns.Trainer = Trainer

-- ---------------------------------------------------------------------------
-- English UI strings owned by TurboFace
-- ---------------------------------------------------------------------------
local L = {
    LID_GENERAL                  = "General",
    LID_TOTALCOST                = "Total cost",
    LID_COSTS                    = "Costs",
    LID_FREE                     = "Free",
    LID_OWNGOLD                  = "Own gold",
    LID_TRAININGQUEUE            = "Training Queue",
    LID_AVAILABLENOW             = "Available Now",
    LID_COMINGSOON               = "Coming Soon",
    LID_LVL                      = "Lvl",
    LID_NOTYETAVAILABLE          = "Not Yet Available",
    LID_MISSINGREQUIREDTALENTS   = "Missing Required Talents",
    LID_ALREADYKNOWN             = "Already Known",
    LID_NOTLEARNEDYET            = "Not learned yet",
    LID_PETTRAINING              = "Pet Training",
    LID_IGNORED                  = "Ignored",
    LID_STOPIGNORINGTHISRANK     = "Stop ignoring this rank",
    LID_IGNORINGTHISRANK         = "Ignore this rank",
    LID_STOPIGNOREINGALLRANKS    = "Stop ignoring all ranks",
    LID_IGNOREALLRANKS           = "Ignore all ranks",
    LID_STOPIGNORINGTHISRECIPE   = "Stop ignoring this recipe",
    LID_IGNORINGTHISRECIPE       = "Ignore this recipe",
    LID_STOPIGNORINGTHISSKILL    = "Stop ignoring this skill",
    LID_IGNORINGTHISSKILL        = "Ignore this skill",
    LID_QUEUEAUTOTRAIN           = "Queue for Auto-Training",
    LID_REMOVEAUTOTRAIN          = "Remove from Training Queue",
    LID_MOVEQUEUEUP              = "Move Up Queue",
    LID_MOVEQUEUEDOWN            = "Move Down Queue",
    LID_CANCEL                   = "Cancel",
    LID_NOTSCANNEDYET            = "NOT SCANNED YET, CHANGE PET",
    LID_CLASSTRAINER             = "Class Training",
    LID_SKILLS                   = "Skills",
    LID_WEAPONSKILLS             = "Weapon Skills",
    LID_PRIMARYPROFESSIONS       = "Primary Professions",
    LID_SECONDARYPROFESSIONS     = "Secondary Professions",
    LID_PROFESSIONS              = "Professions",
    LID_SKILL                    = "Skill",
    LID_TRAINING                 = "Training",
    LID_RECIPES                  = "Recipes",
    LID_SOURCE                   = "Source",
}
-- A missing key should be obvious in-game rather than rendering as a blank
-- label, which is how a typo in a string key would otherwise hide.
ns.TrainerStrings = setmetatable(L, {
    __index = function(_, k) return "?" .. tostring(k) end,
})

-- ---------------------------------------------------------------------------
-- Addon compatibility helpers
-- ---------------------------------------------------------------------------
-- C_AddOns is the current path on 1.15.x with the old global retained as a
-- compatibility fallback.
function Trainer:IsAddonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
-- Called before anything reads these tables so every Trainer consumer sees a
-- normalized storage shape regardless of the saved-variable version on disk.
function Trainer:InitSavedVariables()
    if type(TurboFaceTrainerDB) ~= "table" then TurboFaceTrainerDB = {} end
    if type(TurboFaceTrainerCharDB) ~= "table" then TurboFaceTrainerCharDB = {} end

    local db = TurboFaceTrainerDB
    -- SavedVariables can outlive several schema revisions. Treat every owned
    -- container as untrusted input so an old nil/scalar value cannot break a
    -- later migration or trainer scan. InitSavedVariables is intentionally
    -- idempotent and is also called again from Init().
    if type(db.data) ~= "table" then db.data = {} end
    if type(db.petData) ~= "table" then db.petData = {} end
    if type(db.petTrainerData) ~= "table" then db.petTrainerData = {} end
    if type(db.skillData) ~= "table" then db.skillData = {} end
    if type(db.professionData) ~= "table" then db.professionData = {} end
    if type(db.recipeData) ~= "table" then db.recipeData = {} end

    -- 0.17.75 provenance cleanup: older development builds merged a third-party
    -- profession/recipe seed database into these containers. Static profession
    -- recipes now come directly from LibProfessionDB rather than being copied
    -- into SavedVariables, so discard the old mixed cache once. Later trainer
    -- visits rebuild only the live cost/status overlay through Blizzard APIs.
    if db.provenanceProfessionResetV1 ~= true then
        db.professionData = {}
        db.recipeData = {}
        db.provenanceProfessionResetV1 = true
    end

    local cdb = TurboFaceTrainerCharDB
    if type(cdb.ignored) ~= "table" then cdb.ignored = {} end
    if type(cdb.ignoredNames) ~= "table" then cdb.ignoredNames = {} end
    if type(cdb.ignoredProfessions) ~= "table" then cdb.ignoredProfessions = {} end
    if type(cdb.character) ~= "table" then cdb.character = {} end

    local ch = cdb.character
    if type(ch.collapsedGroups) ~= "table" then ch.collapsedGroups = {} end
    if type(ch.learnedSpellsPet) ~= "table" then ch.learnedSpellsPet = {} end
    if type(ch.trainingQueue) ~= "table" then ch.trainingQueue = {} end

    -- Row height is now fixed at 20px; purge obsolete slider settings.
    ch.rowHeight = nil
    ch.professionRowHeight = nil
    if ch.showIgnoredInTrainer == nil then ch.showIgnoredInTrainer = false end
end

-- Provide provisional containers for Trainer files that load below this one.
-- The persisted SavedVariables are only authoritative once the addon's load
-- lifecycle reaches ADDON_LOADED, so Init() MUST normalize them again before
-- migrations or runtime consumers run. A legacy saved table can otherwise
-- replace this provisional table and omit fields introduced by newer builds.
Trainer:InitSavedVariables()

-- ---------------------------------------------------------------------------
-- Deferred UI construction
--
-- TurboFace requires a disabled module to build nothing at all (ARCHITECTURE
-- section 5), so each UI file registers a builder here instead of constructing
-- frames at file scope. Init() invokes them in TOC order once the gate is on.
--
-- Order matters: UI_Core's builder creates the frame that UI_ClassList,
-- UI_Skills, UI_Profession and UI_Spellbook anchor to, and they read it through
-- Trainer.ClassFrame at builder-run time rather than at file scope.
-- ---------------------------------------------------------------------------
Trainer.builders = {}

function Trainer:AddBuilder(fn)
    self.builders[#self.builders + 1] = fn
end

function Trainer:BuildUI()
    if self.uiBuilt then return end
    self.uiBuilt = true
    local builders = self.builders
    for i = 1, #builders do
        builders[i]()
    end
    -- Builders are load-time staging closures; once every UI piece exists they
    -- can never run again, so release the list and its captured references.
    self.builders = nil
end

function Trainer:SetUIRuntime(active)
    if self.SetClassListEvents then self:SetClassListEvents(active) end
    if self.SetProfessionEvents then self:SetProfessionEvents(active) end
    if self.SetTrainingQueueRuntime then self:SetTrainingQueueRuntime(active) end
    if self.RefreshSpellbookUI then self:RefreshSpellbookUI(active) end
    if self.RefreshProfessionUI then self:RefreshProfessionUI(active) end
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
--
-- Gate: trainerEnabled (dbKey gate, same style as invEnabled / groceryEnabled).
-- Starting disabled means dormant: no events, hooks, or UI construction. After a
-- live enable, irreversible hooks remain installed but are predicate-gated, while
-- detachable child events and TurboFace-owned UI are torn down on disable.
-- ---------------------------------------------------------------------------
local function Enabled()
    local db = TurboFaceDB
    local v = db and db.trainerEnabled
    if v == nil then return true end
    return v == true
end

function Trainer:Init()
    if not Enabled() then return end
    -- Re-normalize immediately before migrations/runtime setup. File-scope
    -- initialization is only provisional; this pass runs at PLAYER_LOGIN after
    -- persisted SavedVariables are authoritative and repairs older schemas.
    self:InitSavedVariables()
    self:MergeBuiltinData()
    self:MigrateLegacySkillCaptures()
    self:MigrateLegacyProfessionIgnores()
    self.tooltipActive = true
    self:BuildUI()
    if self.InstallTooltipHook then self:InstallTooltipHook() end
    self:SetEvents(true)
    self:SetUIRuntime(true)
    self.initialised = true
end

-- Live apply from the options panel.
function Trainer:Refresh()
    local active = Enabled()

    if active and not self.initialised then
        self:Init()
        return
    end

    self:SetEvents(active)
    self.tooltipActive = active
    self:SetUIRuntime(active)

    if not active then
        -- Hide whatever was built. Frames are only constructed once the gate has
        -- been on, so a player who never enabled the feature has nothing here.
        for _, name in ipairs({
            "TurboFaceTrainerFrame",
            "TurboFaceTrainerProfessionFrame",
            "TurboFaceTrainerSpellbookTab",
            "TurboFaceTrainerSkillsSpellbookTab",
            "TurboFaceTrainerProfessionBookTab",
        }) do
            local frame = _G[name]
            if frame and frame.Hide then frame:Hide() end
        end
        return
    end

    -- Re-enabled after login after starting disabled: build the UI now.
    self:BuildUI()
    self:SetUIRuntime(true)
    if self.InstallTooltipHook then self:InstallTooltipHook() end
    if self.RefreshActiveSpellbookList then self.RefreshActiveSpellbookList()
    elseif self.RefreshList then self.RefreshList() end
end
