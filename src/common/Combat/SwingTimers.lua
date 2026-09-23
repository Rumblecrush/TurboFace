local _, ns = ...

-- API boundary: all changed-in-retail APIs resolve through Compat.lua
local GetItemInfoInstant = ns.API.GetItemInfoInstant
local GetItemIcon = ns.API.GetItemIcon
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellTexture = ns.API.GetSpellTexture
local IsCurrentSpell = ns.API.IsCurrentSpell
local IsReadableNumber = ns.API.IsReadableNumber or function(v) return type(v) == "number" end
local UnitAttackSpeed = UnitAttackSpeed

-- The active Swing Timer provider decides whether the client exposes an
-- authoritative PLAYER_SWING clock. When unavailable, the shared engine falls
-- back to Classic's CLEU/spellcast reconstruction paths.
local playerSwingEventActive = false
local lastPlayerSwingType, lastPlayerSwingDuration, lastPlayerSwingAt
local PLAYER_SWING_SLOT_BY_TYPE = { [0] = "main", [1] = "off", [2] = "ranged" }

local function PlayerSwingSlot(swingType)
    if ns.API.IsSecretValue and ns.API.IsSecretValue(swingType) then return nil end
    local E = Enum and Enum.PlayerSwingType
    if E then
        if swingType == E.MainHand then return "main" end
        if swingType == E.OffHand then return "off" end
        if swingType == E.Ranged then return "ranged" end
    end
    return PLAYER_SWING_SLOT_BY_TYPE[swingType]
end

-- =============================================================================
-- TurboFace SwingTimers.lua
-- TurboFace-owned hybrid swing tracking engine.
--
-- Modern swing tracking with two presentation consumers:
--   * baked mode keeps TurboFace's current compact UnitFrame timer stack;
--   * standalone mode uses the legacy tooltip-bordered MH/OH/ranged/target rows,
--     each independently movable. The tracking engine is presentation-agnostic.
-- =============================================================================

local ST = {}
ns.ST = ST
if ns.SwingTimerProviderAttach then ns.SwingTimerProviderAttach(ST) end

local PLAYER_CLASS = select(2, UnitClass("player"))
local PLAYER_GUID  = UnitGUID("player")

-- =============================================================================
-- CLASSIC ERA SPELL-INTERACTION DATA
-- See SwingTimerSpellData.lua.  The data file is deliberately separate from the
-- event engine so individual 1.15.9 interactions can be corrected as tested.
-- =============================================================================

local SWING_SPELL_DATA = ns.SwingTimerSpellData or {}
-- Keep the spell-interaction API behind one table reference. SwingTimerOnEvent is
-- intentionally a large dispatcher and sits close to Classic Lua's upvalue
-- warning threshold; capturing one interface table avoids multiplying closure
-- upvalues as the behavior model evolves.
SWING_SPELL_DATA.ResetsMeleeOnSuccess = SWING_SPELL_DATA.ResetsMeleeOnSuccess or function() return false end
SWING_SPELL_DATA.SuppressHardCastReset = SWING_SPELL_DATA.SuppressHardCastReset or function() return false end
SWING_SPELL_DATA.IsNextMelee = SWING_SPELL_DATA.IsNextMelee or function() return false end
SWING_SPELL_DATA.GetActiveNextMeleeSpell = SWING_SPELL_DATA.GetActiveNextMeleeSpell or function() return nil end
SWING_SPELL_DATA.AnyNextMeleeQueued = SWING_SPELL_DATA.AnyNextMeleeQueued or function() return false end
SWING_SPELL_DATA.ResetsMeleeOnItemEffect = SWING_SPELL_DATA.ResetsMeleeOnItemEffect or function() return false end

local QUEUED_COLOR = { 1.0, 0.5, 0.0 }  -- orange, distinct from default blue/red

-- Visual frames are forward-declared before queued-color helpers so those
-- helpers close over the locals rather than similarly named globals.
local playerFrame, enemyFrame, rangedFrame
local standaloneMainFrame, standaloneOffFrame, standaloneRangedFrame, standaloneTargetFrame

-- Queued spell color management
local function ApplyQueuedColor(frame)
    if frame and frame.main_bar then
        frame.main_bar:SetVertexColor(QUEUED_COLOR[1], QUEUED_COLOR[2], QUEUED_COLOR[3])
    end
    if frame == playerFrame and standaloneMainFrame and standaloneMainFrame.main_bar then
        standaloneMainFrame.main_bar:SetVertexColor(QUEUED_COLOR[1], QUEUED_COLOR[2], QUEUED_COLOR[3])
    end
end

local function ResetBarColor(frame, color)
    if frame and frame.main_bar then
        frame.main_bar:SetVertexColor(color[1], color[2], color[3])
    end
    if frame == playerFrame and standaloneMainFrame and standaloneMainFrame.main_bar then
        standaloneMainFrame.main_bar:SetVertexColor(color[1], color[2], color[3])
    end
end

-- UI error messages that indicate a swing failed (out of range/facing)
local SWING_ERROR_MESSAGES = {
    [ERR_BADATTACKFACING] = true,
    [ERR_BADATTACKPOS]    = true,
}

-- =============================================================================
-- STATE
-- =============================================================================

local in_combat = false
-- A real player melee reset may still have time remaining when combat drops.
-- Let that already-visible swing reach ready instead of tearing the row down at
-- the combat boundary. This state never starts a new out-of-combat swing.
local playerSwingFinishingOutOfCombat = false

-- Classes with a Classic ranged auto-attack. Hunter Auto Shot is the primary
-- combat attack; the other classes opt into a secondary Shoot/Throw repeat.
local RANGED_CLASSES = {
    HUNTER=true, MAGE=true, PRIEST=true, ROGUE=true, WARLOCK=true, WARRIOR=true,
}
local IS_RANGED_CLASS = RANGED_CLASSES[PLAYER_CLASS] or false
local SECONDARY_RANGED_CLASSES = {
    MAGE=true, PRIEST=true, ROGUE=true, WARLOCK=true, WARRIOR=true,
}
local IS_SECONDARY_RANGED_CLASS = SECONDARY_RANGED_CLASSES[PLAYER_CLASS] or false

-- Wand users: the wand is a SECONDARY auto-attack (cast via "Shoot"), unlike a
-- Hunter's bow/gun which is the PRIMARY auto-attack. So their ranged swing bar
-- must only appear while actually wanding, never just because melee combat began.
local WAND_CLASSES = { MAGE=true, PRIEST=true, WARLOCK=true }
local IS_WAND_CLASS = WAND_CLASSES[PLAYER_CLASS] or false

-- Ranged spell IDs. Physical shots and wand Shoot share the ranged clock.
-- Era keeps its historical spellcast interaction model; on Forever the explicit
-- PLAYER_SWING(Ranged) event owns the ranged clock and never mutates MH/OH.
local PHYSICAL_RANGED_SHOT_IDS = {
    [75]   = true, -- Auto Shot
    [2480] = true, -- Shoot Bow
    [2764] = true, -- Throw
    [7918] = true, -- Shoot Gun
    [7919] = true, -- Shoot Crossbow
}
local WAND_SHOT_IDS = {[5019]=true} -- Shoot (wand)
local AUTO_SHOT_NAME = GetSpellInfo and GetSpellInfo(75) or nil
local SHOOT_NAME = GetSpellInfo and GetSpellInfo(5019) or nil
local PHYSICAL_RANGED_SHOT_NAMES = {}

local function RefreshRangedShotNames()
    -- Spell data should normally be available at file load, but resolve lazily
    -- too so early cache timing can never turn the name fallback off forever.
    if GetSpellInfo then
        AUTO_SHOT_NAME = AUTO_SHOT_NAME or GetSpellInfo(75)
        SHOOT_NAME = SHOOT_NAME or GetSpellInfo(5019)
        for id in pairs(PHYSICAL_RANGED_SHOT_IDS) do
            local name = GetSpellInfo(id)
            if name then PHYSICAL_RANGED_SHOT_NAMES[name] = true end
        end
    end
    return AUTO_SHOT_NAME, SHOOT_NAME
end

local function ClassifyRangedShotName(spellName)
    if not spellName then return nil end
    local autoShotName, shootName = RefreshRangedShotNames()
    if autoShotName and spellName == autoShotName then return "physical" end
    if shootName and spellName == shootName then
        -- The localized Shoot label is not a safe weapon-type discriminator.
        -- These caster classes use it for wands; physical ranged classes do not.
        return IS_WAND_CLASS and "wand" or "physical"
    end
    if PHYSICAL_RANGED_SHOT_NAMES[spellName] then return "physical" end
    return nil
end

-- Ranged weapon swings have their own clock. Classic may surface them through
-- the ordinary UNIT_SPELLCAST_* stream, so classify the shot before applying
-- generic completed-hard-cast behavior.
--
-- Do not rely on spellID alone. 1.15.9 can expose the wand cast through a
-- UNIT_SPELLCAST payload that does not line up cleanly with the canonical 5019
-- ID. Resolve the localized spell name as a second identity check, and pair it
-- with the equipped weapon/class when the localized Shoot name is ambiguous.
-- The returned kind is pinned to the cast GUID below for the entire lifecycle.
local function ClassifyRangedShotSpell(spellID)
    if spellID and WAND_SHOT_IDS[spellID] then return "wand" end
    if spellID and PHYSICAL_RANGED_SHOT_IDS[spellID] then return "physical" end
    if not spellID or not GetSpellInfo then return nil end
    return ClassifyRangedShotName(GetSpellInfo(spellID))
end

local function ActivePlayerRangedShotKind(spellID)
    local shotKind = ClassifyRangedShotSpell(spellID)
    if shotKind then return shotKind end

    local castName
    if UnitCastingInfo then castName = UnitCastingInfo("player") end
    if not castName and UnitChannelInfo then castName = UnitChannelInfo("player") end
    return ClassifyRangedShotName(castName)
end

-- Bar frames are predeclared here because queued-spell helpers need to update
-- playerFrame before the constructors appear later in the file.
playerFrame = nil
enemyFrame  = nil
rangedFrame = nil
-- Standalone presentation frames are separate visual consumers of the same
-- modern swing engine. They exist only so each legacy-style row can have its
-- own mover; embedded mode continues to use the compact frames above.
standaloneMainFrame   = nil
standaloneOffFrame    = nil
standaloneRangedFrame = nil
standaloneTargetFrame = nil
local eventFrame  = nil

local BAR_COLOR_PLAYER_MAIN = { 255/255, 229/255, 180/255 }  -- peach (queued spells still flip it orange)
local BAR_COLOR_PLAYER_OFF  = { 255/255, 229/255, 180/255 }
local BAR_COLOR_ENEMY_MAIN  = { 0.8, 0.1, 0.1 }  -- red target-swing presentation

-- Queued spell visual state
local queued_spell_id = nil  -- currently queued on-next-swing spell, nil if none

-- Forward declaration for the idle-gated update driver.
local WakeDriver

local function ClearQueuedSpell()
    queued_spell_id = nil
    ResetBarColor(playerFrame, BAR_COLOR_PLAYER_MAIN)
    if WakeDriver then WakeDriver() end
end

local function SetQueuedSpell(spellID)
    queued_spell_id = spellID
    ApplyQueuedColor(playerFrame)
    if WakeDriver then WakeDriver() end
end

-- Authoritative queue state, read from the client rather than inferred from a
-- cast event.
--
-- UNIT_SPELLCAST_SENT is kept below as a fast path, but it cannot be the only
-- signal: on-next-swing abilities are TOGGLES, so pressing Maul or Heroic
-- Strike a second time cancels the queue without sending anything, and the
-- queue is also dropped on form and target changes the addon never sees a cast
-- for. IsCurrentSpell is the state the client actually holds -- the same API
-- the UNIT_SPELLCAST_FAILED path further down already falls back to.
--
-- Driven from CURRENT_SPELL_CAST_CHANGED, which fires precisely when the
-- pending spell changes, so this stays off the hot path.
local function RefreshQueuedSpell()
    local found = SWING_SPELL_DATA.GetActiveNextMeleeSpell()
    if found then
        if not queued_spell_id then SetQueuedSpell(found) end
    elseif queued_spell_id then
        ClearQueuedSpell()
    end
end

-- Queued spell colors (bar changes color when spell is queued)
-- Ranged swing state (Hunter / wand users)
local ranged = {
    shooting      = false,
    timer         = 0.52,
    speed         = 3.0,    -- current hasted speed (from UnitRangedDamage)
    base_speed    = 3.0,    -- unhasted base speed (from tooltip scan)
    cast_time     = 0.52,   -- ~0.52s cast window, scales with haste
    last_shot_time = 0,
    ready         = false,
    casting       = false,
    has_moved     = false,
}

local function ReadRangedSpeed()
    local speed = select(1, UnitRangedDamage("player"))
    if IsReadableNumber(speed) and speed > 0 then return speed end
    return nil
end

-- UNIT_INVENTORY_CHANGED is broader than "weapon changed". In Classic it can
-- fire for inventory/equipment churn related to ranged attacks. Keep explicit
-- equipped-weapon identities so only a real MH/OH swap is allowed to reset the
-- melee clocks, while a ranged weapon change only restarts the ranged clock.
local equippedMainID, equippedOffID, equippedRangedID

local function ReadEquippedWeaponIDs()
    return GetInventoryItemID("player", INVSLOT_MAINHAND or 16),
           GetInventoryItemID("player", INVSLOT_OFFHAND or 17),
           GetInventoryItemID("player", INVSLOT_RANGED or 18)
end

local function SnapshotEquippedWeaponIDs()
    equippedMainID, equippedOffID, equippedRangedID = ReadEquippedWeaponIDs()
end

-- Ranged base-speed tooltip scanner. Classic exposes current ranged speed but
-- not a stable unhasted base value, so cache the equipped weapon tooltip value.
local _rangedTooltip = nil
local _rangedSpeedCache = {}

local function GetRangedBaseSpeed()
    local weapon_id = GetInventoryItemID("player", INVSLOT_RANGED)
    if not weapon_id then return 1 end
    if _rangedSpeedCache[weapon_id] then return _rangedSpeedCache[weapon_id] end
    if not _rangedTooltip then
        _rangedTooltip = CreateFrame("GameTooltip", "TurboFaceRangedTip", nil, "GameTooltipTemplate")
        _rangedTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    _rangedTooltip:ClearLines()
    _rangedTooltip:SetItemByID(weapon_id)
    local speed = 1
    local pattern = SPEED .. " (%d%.%d%d)"
    for i = 1, _rangedTooltip:NumLines() do
        local fs = _G["TurboFaceRangedTipTextRight" .. i]
        if fs then
            local text = fs:GetText()
            if text then
                local m = text:match(pattern)
                if m then speed = tonumber(m) or 1 break end
            end
        end
    end
    _rangedSpeedCache[weapon_id] = speed
    return speed
end

-- Player swing state
local player = {
    main_timer    = 0.00001,
    off_timer     = 0.00001,
    main_speed    = 2,
    off_speed     = 2,
    has_offhand   = false,
    has_shield    = false,
    is_attacking  = false,
    swing_error   = false,
    delay_offhand = false,
}

-- Out-of-combat reset timestamps are forward-declared here because the CLEU
-- helpers are defined before the event-frame section that consumes them.
local pending_hard_cast_reset_at
local pending_player_main_reset_at
local pending_player_off_reset_at

-- Auto Attack can briefly report inactive while the player changes targets.
-- Keep a tiny grace window so that transient state does not park the off-hand
-- timer at its idle threshold or stop the update driver mid-swap.
local last_attack_active_at = 0
local target_change_attack_grace_until = 0

-- Target swing state
local target = {
    main_timer    = 0.00001,
    off_timer     = 0.00001,
    main_speed    = 2,
    off_speed     = 2,
    has_offhand   = false,
    guid          = nil,
}

-- Lightweight visible-enemy swing state used by the independent Nameplate Swing Timer.
-- The shared CLEU dispatcher is still decoded once; this table stores only an
-- absolute ready time and weapon duration, so it requires no second timer loop.
local nameplateSwingStates = {}
local nameplateRuntimeFrame = nil
local nameplateRuntimeActivated = false
local nameplateInCombat = false

local function NameplateSwingGateOn()
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    local root = TurboFaceDB or ns.defaults
    local bubble = root and root.bubbleNameplates
    return not bubble or bubble.swingTimer ~= false
end

-- Per-GUID enemy swing snapshots keep the target attack row stable when the
-- player swaps away from a mob and then targets it again during the same combat.
-- Unlike the nameplate feature state, this cache is not tied to plate visibility.
local targetSwingStates = {}

local SwingTimers = {}
ns.SwingTimers = SwingTimers

function SwingTimers:GetNameplateState(guid)
    return guid and nameplateSwingStates[guid] or nil
end

-- A hostile already engaged when its nameplate swing presentation first wakes
-- has not necessarily produced a CLEU swing yet. In that pre-observation state
-- the only defensible information is that no cooldown has been observed, so the
-- attack is presented as ready. Do not invent a synthetic duration countdown.
-- The first real SWING_DAMAGE/SWING_MISSED immediately overwrites this seed with
-- the authoritative speed-derived reset below.
function SwingTimers:PrimeNameplateState(guid, unit)
    if not guid then return nil end
    local state = nameplateSwingStates[guid]
    if state then return state end
    if not nameplateInCombat or not unit or not UnitExists(unit) or not UnitCanAttack("player", unit) then
        return nil
    end

    local engaged
    if UnitAffectingCombat then
        local ok, value = pcall(UnitAffectingCombat, unit)
        if ok and (not ns.API or not ns.API.CanAccessValue or ns.API.CanAccessValue(value)) then
            engaged = value == true
        end
    end
    -- Classic Era can use threat presence as an additional engagement signal.
    -- Clients whose threat state can be secret disable that fallback in the
    -- Swing Timer provider.
    if not engaged and ns.SwingTimerProviderUsesThreatSituationEngagement() and UnitThreatSituation then
        engaged = UnitThreatSituation("player", unit) ~= nil
    end
    if not engaged then return nil end

    state = { readyAt = GetTime() }
    nameplateSwingStates[guid] = state
    return state
end

local function PrimeVisibleNameplateStates()
    if not ns.guidToNameplateUnit then return end
    for guid, unit in pairs(ns.guidToNameplateUnit) do
        local state = SwingTimers:PrimeNameplateState(guid, unit)
        if state and ns.BubbleNameplates then
            ns.BubbleNameplates:OnEnemySwing(guid)
        end
    end
end

function SwingTimers:CleanupNameplateState(guid)
    if guid then nameplateSwingStates[guid] = nil end
end

function SwingTimers:ClearNameplateStates()
    wipe(nameplateSwingStates)
end

-- =============================================================================
-- BAR FRAMES
-- =============================================================================

-- playerFrame/enemyFrame/rangedFrame are predeclared in STATE so queued-spell
-- helpers and bar update code all close over the same locals.

-- Shared compact timer presentation used only by baked mode. Player melee and
-- target attack rows use the reserve openings in TurboFace unit-frame artwork.
-- Standalone mode is rendered by the separate legacy-style frames below.
local COMPACT_BAR_ART = "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\CastBar.tga"
-- Castbar.tga v2 (0.11.4): 121x14, was 104x12. Interior opening measured
-- at x4..115, y3..8. Insets stay at 2 so the fill deliberately runs a
-- little under the border, matching the previous look.
local COMPACT_BAR_W, COMPACT_BAR_H = 121, 14
local COMPACT_INSET_X, COMPACT_INSET_Y = 2, 2
local COMPACT_FILL_OFFSET_Y = 2
local COMPACT_FILL_W = COMPACT_BAR_W - COMPACT_INSET_X * 2
local COMPACT_RANGED_BG_W = COMPACT_FILL_W - 2
local COMPACT_FILL_H = COMPACT_BAR_H - COMPACT_INSET_Y * 2
local COMPACT_MELEE_TRIM_BOTTOM = 2
local COMPACT_ROW_SLOTS = 3
local COMPACT_ROW_ART_OVERLAP = 3

-- Parking anchors for the compact renderer when it is not baked into a TurboFace
-- UnitFrame. The compact rows remain hidden in standalone mode; these anchors keep
-- their internal stack ownership independent from Blizzard protected frames.
local standaloneAnchors = {}
local STANDALONE_DEFAULTS = {
    -- Match the older standalone TurboFace behavior: begin immediately below
    -- Blizzard's own player/target power bars. Movers converts a user drag into
    -- screen-relative placement, so this is only the untouched default.
    player = { "TOP", PlayerFrameManaBar or PlayerFrame or UIParent, "BOTTOM", 0, -2 },
    target = { "TOP", TargetFrameManaBar or TargetFrame or UIParent, "BOTTOM", 0, -2 },
}

local function UseEmbeddedTimerStack(stackKey)
    local u = TurboFaceDB and TurboFaceDB.unitframes
    if u and u.embedCombatTimers == false then return false end
    if not ns.ModuleEnabled then return true end
    local child = (stackKey == "target") and "target" or "player"
    return ns.ModuleEnabled("unitframes", child)
end

local embeddedPlayerTimers = true
local embeddedTargetTimers = true
local function RefreshTimerPresentationMode()
    embeddedPlayerTimers = UseEmbeddedTimerStack("player")
    embeddedTargetTimers = UseEmbeddedTimerStack("target")
end

local function EnsureStandaloneTimerAnchor(stackKey)
    local anchor = standaloneAnchors[stackKey]
    if anchor then return anchor end
    local name = (stackKey == "target") and "TurboFaceTargetCombatTimerAnchor" or "TurboFacePlayerCombatTimerAnchor"
    anchor = CreateFrame("Frame", name, UIParent)
    anchor:SetSize(COMPACT_BAR_W, COMPACT_BAR_H * COMPACT_ROW_SLOTS - COMPACT_ROW_ART_OVERLAP * (COMPACT_ROW_SLOTS - 1))
    local point = STANDALONE_DEFAULTS[stackKey] or STANDALONE_DEFAULTS.player
    anchor:SetPoint(point[1], point[2], point[3], point[4], point[5])
    standaloneAnchors[stackKey] = anchor
    return anchor
end

local function TimerStackPlacement(stackKey)
    if UseEmbeddedTimerStack(stackKey) then
        local x, y, w, h
        if stackKey == "target" then
            if ns.UF and ns.UF.GetTargetReserveGeometry then x, y, w, h = ns.UF:GetTargetReserveGeometry() end
            if x == nil then x, y, w, h = 26, 81, 121, 14 end
            return TargetFrameTextureFrameTexture or TargetFrameTexture or TargetFrame, x, y, w, h
        end
        if ns.UF and ns.UF.GetPlayerReserveGeometry then x, y, w, h = ns.UF:GetPlayerReserveGeometry() end
        if x == nil then x, y, w, h = 109, 81, 121, 14 end
        return PlayerFrameTexture or PlayerFrame, x, y, w, h
    end
    return EnsureStandaloneTimerAnchor(stackKey), 0, 0, COMPACT_BAR_W, COMPACT_BAR_H
end
-- Horizontal insets for the PLAYER melee row's CONTENTS only -- background and
-- the main/offhand fill bars. The frame and its CastBar.tga border keep the
-- full reserve width, so the art still renders at native 121px and is not
-- squashed; only what sits inside the border moves in.
-- The target attack row (LayoutCompactTargetAttack) is deliberately not inset.
local COMPACT_MELEE_INSET_LEFT  = 2
local COMPACT_MELEE_INSET_RIGHT = 3
-- Target rows are the mirror image, so the insets swap sides. The total (5) is
-- unchanged, which keeps the fill width identical between the two stacks.
local COMPACT_TARGET_INSET_LEFT  = COMPACT_MELEE_INSET_RIGHT
local COMPACT_TARGET_INSET_RIGHT = COMPACT_MELEE_INSET_LEFT
local COMPACT_TARGET_BAR_ART =
    "Interface\\AddOns\\TurboFace\\Textures\\UnitFrames\\TargetCastBar.tga"
-- Vertical nudge for the compact timer text. Positive is UP.
-- Raised 0.5 in 0.11.12 to sit better against the v5 castbar art. This value
-- also drives the dual-wield LEFT/RIGHT labels at the top of LayoutCompactMelee
-- so main/offhand text stays on the same baseline as the centered variant.
local COMPACT_TIMER_TEXT_Y = 1.5
local COMPACT_RANGED_TIMER_TEXT_Y = 2.5

-- Resolve the configured attack-bar fill texture.
local function GetAttackTexture()
    local u = TurboFaceDB and TurboFaceDB.unitframes
    -- Kept at the legacy unitframes path for profile compatibility; the option
    -- is now presented globally because standalone timers use it too.
    local name = (u and u.attackTexture) or "Blizzard"
    return ns.GetTexture(name)
end


-- -----------------------------------------------------------------------------
-- Legacy standalone presentation (visual only)
-- -----------------------------------------------------------------------------
-- The uploaded pre-compact TurboFace build is the presentation contract for
-- standalone mode: tooltip-style border, cropped weapon icon on the left,
-- damage range centered, countdown on the right. The engine above remains the
-- current event/CLEU/cadence implementation.
local STANDALONE_DEFAULT_H = 12
local STANDALONE_GAP = 2
local STANDALONE_DEFAULT_W = 150

local function StandaloneSwingWidth()
    local v = TurboFaceDB and tonumber(TurboFaceDB.swingTimersStandaloneWidth)
    return math.max(80, math.min(300, v or STANDALONE_DEFAULT_W))
end

local function StandaloneSwingHeight()
    local v = TurboFaceDB and tonumber(TurboFaceDB.swingTimersStandaloneHeight)
    return math.max(8, math.min(30, v or STANDALONE_DEFAULT_H))
end

local function StandaloneMoverOwnsPoint(id)
    if not (ns.MoversEnabled and ns.MoversEnabled()) then return false end
    local movers = TurboFaceDB and TurboFaceDB.movers
    local elements = movers and movers.elements
    local db = elements and elements[id]
    return db and db.enabled ~= false and db.point ~= nil
end

local function StandalonePlayerBase()
    local dpb = ns.DruidPowerBar
    local druidBar = dpb and dpb.GetBar and dpb:GetBar()
    if druidBar and druidBar:IsShown()
            and dpb.IsStandaloneMode and dpb:IsStandaloneMode() then
        return druidBar
    end
    return PlayerFrameManaBar or PlayerFrame or UIParent
end

local function AnchorStandalonePlayerRows()
    local base = StandalonePlayerBase()
    local stride = StandaloneSwingHeight() + STANDALONE_GAP
    if standaloneMainFrame and not StandaloneMoverOwnsPoint("PlayerMainSwingTimer") then
        standaloneMainFrame:ClearAllPoints()
        standaloneMainFrame:SetPoint("TOP", base, "BOTTOM", 0, -STANDALONE_GAP)
    end
    if standaloneOffFrame and not StandaloneMoverOwnsPoint("PlayerOffhandSwingTimer") then
        standaloneOffFrame:ClearAllPoints()
        standaloneOffFrame:SetPoint("TOP", base, "BOTTOM", 0, -(STANDALONE_GAP + stride))
    end
    if standaloneRangedFrame and not StandaloneMoverOwnsPoint("PlayerRangedSwingTimer") then
        standaloneRangedFrame:ClearAllPoints()
        standaloneRangedFrame:SetPoint("TOP", base, "BOTTOM", 0, -(STANDALONE_GAP + stride * 2))
    end
end

local cachedMHText, cachedOHText, cachedRangedText
local cachedIconMH, cachedIconOH, cachedIconRanged
local cachedDruidFormIcon

local DRUID_MELEE_FORMS = {
    [5487] = true, -- Bear Form
    [9634] = true, -- Dire Bear Form
    [768]  = true, -- Cat Form
}

local function GetDruidMeleeFormAuraIcon()
    if not UnitBuff then return nil end
    for i = 1, 40 do
        local name, icon, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
        if not name then break end
        if spellID and DRUID_MELEE_FORMS[spellID] then return icon end
    end
end

local function GetActiveDruidMeleeFormIcon()
    if PLAYER_CLASS ~= "DRUID" or not GetShapeshiftForm then return nil end
    local formIndex = GetShapeshiftForm()
    if not formIndex or formIndex <= 0 then return nil end
    local _, active, _, spellID = GetShapeshiftFormInfo(formIndex)
    if not active then return nil end
    if spellID and DRUID_MELEE_FORMS[spellID] then
        local icon = GetSpellTexture and GetSpellTexture(spellID)
        if icon then return icon end
    end
    return GetDruidMeleeFormAuraIcon()
end

local function InvalidateDamageText()
    cachedMHText, cachedOHText, cachedRangedText = nil, nil, nil
end

-- Client-owned damage-capture adapters use this narrow setter to refresh the
-- shared standalone MH label without reaching into the engine's local cache.
function ST:_SetCapturedMainDamageText(text)
    cachedMHText = text
end

local function InvalidateWeaponIcons()
    cachedIconMH, cachedIconOH, cachedIconRanged = nil, nil, nil
    cachedDruidFormIcon = nil
    -- A weapon/form identity change invalidates Blizzard's last rendered damage
    -- row too. Until PaperDollFrame renders a fresh value, fall back to the
    -- readable UnitDamage path instead of displaying a stale weapon range.
    ST.paperDollDamageText = nil
    ST.paperDollDamageAt = nil
    ST.damageTextSource = nil
    InvalidateDamageText()
end

-- Character/PaperDoll damage capture is client-owned. The active Swing Timer
-- provider may attach ST.paperDollDamageText and diagnostics without putting
-- protected/secret Character-frame traversal in the shared timer engine.

local function GetWeaponDamageText(isOffhand)
    -- Main-hand standalone text prefers Blizzard's exact Character-sheet value
    -- once that row has been rendered at least once this weapon/form identity.
    if not isOffhand and ST.paperDollDamageText then
        ST.damageTextSource = "paperdoll"
        return ST.paperDollDamageText
    end

    local lo, hi, offLo, offHi = UnitDamage("player")
    if isOffhand then
        if IsReadableNumber(offLo) and IsReadableNumber(offHi) and offHi > 0 then
            return math.floor(offLo) .. " - " .. math.floor(offHi)
        end
        return ""
    end
    if IsReadableNumber(lo) and IsReadableNumber(hi) then
        ST.damageTextSource = "unit"
        return math.floor(lo) .. " - " .. math.floor(hi)
    end
    ST.damageTextSource = "none"
    return ""
end

local function GetRangedDamageText()
    local _, lo, hi = UnitRangedDamage("player")
    if IsReadableNumber(lo) and IsReadableNumber(hi) and hi > 0 then
        return math.floor(lo) .. " - " .. math.floor(hi)
    end
    return ""
end

local function GetWeaponIcon(slot)
    local itemID = GetInventoryItemID("player", slot)
    if itemID and GetItemIcon then return GetItemIcon(itemID) end
    return "Interface\\Icons\\INV_Gauntlets_04"
end

local function CreateStandaloneSwingFrame(name, color, showIcon)
    local f = CreateFrame("Frame", name, UIParent)
    f._standaloneSwing = true
    f:SetSize(StandaloneSwingWidth(), StandaloneSwingHeight())
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.5)
    f.bg = bg

    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetHeight(StandaloneSwingHeight())
    fill:SetWidth(1)
    fill:SetTexture(GetAttackTexture())
    fill:SetVertexColor(color[1], color[2], color[3])
    f.main_bar = fill

    local border = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    if ns.AttachBarBorder then ns:AttachBarBorder(border, f) end
    f.standaloneBorder = border

    local dmgText = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(dmgText, 9, "swingTimersFont", "swingTimersTextStyle")
    dmgText:SetPoint("CENTER", f, "CENTER", 0, 0)
    dmgText:SetTextColor(1, 1, 1)
    f.main_label = dmgText

    local timerText = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(timerText, 9, "swingTimersFont", "swingTimersTextStyle")
    timerText:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    timerText:SetTextColor(1, 1, 1)
    f.main_text = timerText

    if showIcon then
        local icon = f:CreateTexture(nil, "OVERLAY")
        local h = StandaloneSwingHeight()
        icon:SetSize(math.max(h - 4, 1), math.max(h - 4, 1))
        icon:SetPoint("LEFT", f, "LEFT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.main_icon = icon
    end
    return f
end

local function SizeStandaloneSwingFrame(f, unit)
    if not f then return end
    local w = StandaloneSwingWidth()
    local h = StandaloneSwingHeight()
    f:SetSize(w, h)
    if f.main_bar then f.main_bar:SetHeight(h) end
    if f.main_icon then f.main_icon:SetSize(math.max(h - 4, 1), math.max(h - 4, 1)) end
    if f.standaloneBorder and ns.AttachBarBorder then ns:AttachBarBorder(f.standaloneBorder, f) end
end

local function HideStandaloneSwingRows()
    if standaloneMainFrame then standaloneMainFrame:Hide() end
    if standaloneOffFrame then standaloneOffFrame:Hide() end
    if standaloneRangedFrame then standaloneRangedFrame:Hide() end
    if standaloneTargetFrame then standaloneTargetFrame:Hide() end
end

-- Only draw our own border when the artwork does not already supply one.
local function UpdateCompactMeleeBorder(f, isTarget)
    if not f or not f.compactBorder then return end
    local stackKey = isTarget and "target" or "player"
    local builtin = false
    if UseEmbeddedTimerStack(stackKey) then
        if isTarget then
            builtin = ns.UF and ns.UF.TargetArtHasBuiltinAttackSlot
                and ns.UF:TargetArtHasBuiltinAttackSlot()
        else
            builtin = ns.UF and ns.UF.PlayerArtHasBuiltinAttackSlot
                and ns.UF:PlayerArtHasBuiltinAttackSlot()
        end
    end
    f.compactBorder:SetTexture(COMPACT_BAR_ART)
    f.compactBorder:SetShown(not builtin)
end

local function PositionCompactMeleeFrame(f)
    if not f then return end
    UpdateCompactMeleeBorder(f)

    local art, x, y, w, h = TimerStackPlacement("player")
    local levelAnchor = UseEmbeddedTimerStack("player") and PlayerFrameHealthBar or art
    if levelAnchor and levelAnchor.GetFrameLevel then
        f:SetFrameLevel(levelAnchor:GetFrameLevel() or 1)
        if f._textLift then f._textLift:SetFrameLevel((f:GetFrameLevel() or 1) + 3) end
    end
    if f._anchorArt == art and f._anchorX == x and f._anchorY == y
        and f._anchorW == w and f._anchorH == h then
        return
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", art, "TOPLEFT", x, -y)
    f:SetSize(w, h)
    -- Fill spans the inset content area, not the whole frame.
    f._fillWidth = math.max(w - COMPACT_MELEE_INSET_LEFT - COMPACT_MELEE_INSET_RIGHT, 1)
    f._compactHeight = h
    f._anchorArt, f._anchorX, f._anchorY = art, x, y
    f._anchorW, f._anchorH = w, h
end

local function LayoutCompactMelee(f, hasOffhand)
    if not f then return end
    local h = f._compactHeight or f:GetHeight() or 11
    local contentH = math.max(h - COMPACT_MELEE_TRIM_BOTTOM, 1)
    local texture = GetAttackTexture()
    if f._layoutHasOffhand == hasOffhand and f._layoutHeight == h
        and f._layoutTexture == texture then
        return
    end

    f.main_bar:ClearAllPoints()
    f.off_bar:ClearAllPoints()
    f.main_bar:SetTexture(texture)
    f.off_bar:SetTexture(texture)

    f.bg:ClearAllPoints()
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_MELEE_INSET_LEFT, 0)
    f.bg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -COMPACT_MELEE_INSET_RIGHT, 0)
    f.bg:SetHeight(contentH)

    f.main_text:ClearAllPoints()
    f.off_text:ClearAllPoints()
    f.main_text._lastTenths = nil
    f.main_text._lastLabel = nil
    f.off_text._lastTenths = nil
    f.off_text._lastLabel = nil

    if hasOffhand then
        local topH = math.ceil(contentH * 0.5)
        local bottomH = math.max(contentH - topH, 1)
        f.main_bar:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_MELEE_INSET_LEFT, 0)
        f.main_bar:SetHeight(topH)
        f.off_bar:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_MELEE_INSET_LEFT, -topH)
        f.off_bar:SetHeight(bottomH)
        f.off_bar:Show()

        f.main_text:SetPoint("LEFT", f, "LEFT", 3, COMPACT_TIMER_TEXT_Y)
        f.main_text:SetJustifyH("LEFT")
        f.off_text:SetPoint("RIGHT", f, "RIGHT", -3, COMPACT_TIMER_TEXT_Y)
        f.off_text:SetJustifyH("RIGHT")
        f.off_text:Show()
    else
        f.main_bar:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_MELEE_INSET_LEFT, 0)
        f.main_bar:SetHeight(contentH)
        f.off_bar:Hide()
        f.off_text:Hide()

        f.main_text:SetPoint("CENTER", f, "CENTER", 0, COMPACT_TIMER_TEXT_Y)
        f.main_text:SetJustifyH("CENTER")
    end

    f._layoutHasOffhand = hasOffhand
    f._layoutHeight = h
    f._layoutTexture = texture
end

local function CreateCompactMeleeFrame()
    local f = CreateFrame("Frame", "TurboFacePlayerSwingFrame", UIParent)
    f._compactMelee = true
    if PlayerFrameHealthBar and PlayerFrameHealthBar.GetFrameLevel then
        f:SetFrameLevel(PlayerFrameHealthBar:GetFrameLevel() or 1)
    end
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.50)
    f.bg = bg

    local main = f:CreateTexture(nil, "ARTWORK")
    main:SetPoint("TOPLEFT")
    main:SetTexture(GetAttackTexture())
    main:SetVertexColor(BAR_COLOR_PLAYER_MAIN[1], BAR_COLOR_PLAYER_MAIN[2], BAR_COLOR_PLAYER_MAIN[3])
    f.main_bar = main

    local off = f:CreateTexture(nil, "ARTWORK")
    off:SetPoint("BOTTOMLEFT")
    off:SetTexture(GetAttackTexture())
    off:SetVertexColor(BAR_COLOR_PLAYER_OFF[1], BAR_COLOR_PLAYER_OFF[2], BAR_COLOR_PLAYER_OFF[3])
    off:Hide()
    f.off_bar = off

    -- The v5 player sheet dropped its built-in attack/cast strip, so this row
    -- now draws its own frame art -- the same CastBar.tga the ranged row uses.
    -- OVERLAY so it sits above the main/off fills, matching the ranged frame.
    -- Visibility is decided in UpdateCompactMeleeBorder: the druid sheet is
    -- still on the old artwork and already has a strip, so it must not stack a
    -- second border on top.
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture(COMPACT_BAR_ART)
    f.compactBorder = border

    local textLift = CreateFrame("Frame", nil, f)
    textLift:SetAllPoints(f)
    textLift:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
    f._textLift = textLift

    local mainText = textLift:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(mainText, 8, "swingTimersFont", "swingTimersTextStyle")
    mainText:SetTextColor(1, 1, 1)
    f.main_text = mainText

    local offText = textLift:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(offText, 8, "swingTimersFont", "swingTimersTextStyle")
    offText:SetTextColor(1, 1, 1)
    offText:Hide()
    f.off_text = offText

    PositionCompactMeleeFrame(f)
    LayoutCompactMelee(f, false)
    f.main_bar:Hide()
    f.off_bar:Hide()
    f.main_text:Hide()
    f.off_text:Hide()
    f:Show()
    return f
end

local FRAME_STRATA_BELOW = {
    TOOLTIP = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "FULLSCREEN",
    FULLSCREEN = "DIALOG",
    DIALOG = "HIGH",
    HIGH = "MEDIUM",
    MEDIUM = "LOW",
    LOW = "BACKGROUND",
    BACKGROUND = "BACKGROUND",
}

local function TargetTimerStrata()
    local tot = TargetFrameToT
    local strata = tot and tot.GetFrameStrata and tot:GetFrameStrata() or "MEDIUM"
    return FRAME_STRATA_BELOW[strata] or "LOW"
end

local function PositionCompactTargetFrame(f)
    if not f then return end

    local art, x, y, w, h = TimerStackPlacement("target")
    local levelAnchor = UseEmbeddedTimerStack("target") and TargetFrameHealthBar or art
    if UseEmbeddedTimerStack("target") and f.SetFrameStrata then
        -- The baked target attack/cast stack sits one strata below ToT so the
        -- ToT frame/art always wins regardless of frame-level arithmetic.
        f:SetFrameStrata(TargetTimerStrata())
    end
    if levelAnchor and levelAnchor.GetFrameLevel then
        f:SetFrameLevel(levelAnchor:GetFrameLevel() or 1)
        if f._textLift then f._textLift:SetFrameLevel((f:GetFrameLevel() or 1) + 3) end
    end
    if f._anchorArt == art and f._anchorX == x and f._anchorY == y
        and f._anchorW == w and f._anchorH == h then
        return
    end

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", art, "TOPLEFT", x, -y)
    f:SetSize(w, h)
    -- Must exclude the insets, or the fill overruns the mirrored border by the
    -- inset total when it reaches full width.
    f._fillWidth = math.max(w - COMPACT_TARGET_INSET_LEFT - COMPACT_TARGET_INSET_RIGHT, 1)
    f._compactHeight = h
    f._anchorArt, f._anchorX, f._anchorY = art, x, y
    f._anchorW, f._anchorH = w, h
end

local function LayoutCompactTargetAttack(f)
    if not f then return end
    local h = f._compactHeight or f:GetHeight() or 11
    local contentH = math.max(h - COMPACT_MELEE_TRIM_BOTTOM, 1)
    local texture = GetAttackTexture()
    if f._layoutHeight == h and f._layoutTexture == texture then return end

    UpdateCompactMeleeBorder(f, true)

    f.bg:ClearAllPoints()
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", COMPACT_TARGET_INSET_LEFT, 0)
    f.bg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -COMPACT_TARGET_INSET_RIGHT, 0)
    f.bg:SetHeight(contentH)

    -- Mirrored fill: anchored to the RIGHT so it drains toward the portrait,
    -- the mirror image of the player row growing from its left edge.
    f.main_bar:ClearAllPoints()
    f.main_bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -COMPACT_TARGET_INSET_RIGHT, 0)
    f.main_bar:SetHeight(contentH)
    f.main_bar:SetTexture(texture)

    f.main_text:ClearAllPoints()
    f.main_text:SetPoint("CENTER", f, "CENTER", 0, COMPACT_TIMER_TEXT_Y)
    f.main_text:SetJustifyH("CENTER")
    f.main_text._lastTenths = nil

    f._layoutHeight = h
    f._layoutTexture = texture
end

local function CreateCompactTargetAttackFrame()
    local f = CreateFrame("Frame", "TurboFaceEnemySwingFrame", UIParent)
    f._compactTarget = true
    if TargetFrameHealthBar and TargetFrameHealthBar.GetFrameLevel then
        f:SetFrameLevel(TargetFrameHealthBar:GetFrameLevel() or 1)
    end
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.50)
    f.bg = bg

    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPRIGHT")
    fill:SetTexture(GetAttackTexture())
    fill:SetVertexColor(BAR_COLOR_ENEMY_MAIN[1], BAR_COLOR_ENEMY_MAIN[2], BAR_COLOR_ENEMY_MAIN[3])
    f.main_bar = fill

    -- The v2 target sheet dropped its built-in attack strip, so this row draws
    -- its own mirrored frame art, exactly as the player melee row does.
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture(COMPACT_TARGET_BAR_ART)
    f.compactBorder = border

    local textLift = CreateFrame("Frame", nil, f)
    textLift:SetAllPoints(f)
    textLift:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
    f._textLift = textLift

    local timerText = textLift:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(timerText, 8, "swingTimersFont", "swingTimersTextStyle")
    timerText:SetTextColor(1, 1, 1)
    f.main_text = timerText

    PositionCompactTargetFrame(f)
    LayoutCompactTargetAttack(f)
    -- Construction is presentation-neutral. The target row is claimed only by
    -- the normal combat + hostile-target update path; showing it here produces
    -- a blank baked-in border on login/reload before target state is evaluated.
    f.main_bar:Hide()
    f.main_text:Hide()
    f:Hide()
    return f
end

local function CreateCompactTimerFrame(name, color)
    local f = CreateFrame("Frame", name, UIParent)
    f._compactTimer = true
    f:SetSize(COMPACT_BAR_W, COMPACT_BAR_H)
    f._fillWidth = COMPACT_FILL_W
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint(
        "TOPLEFT",
        f,
        "TOPLEFT",
        COMPACT_INSET_X,
        -COMPACT_INSET_Y + COMPACT_FILL_OFFSET_Y
    )
    bg:SetSize(COMPACT_RANGED_BG_W, COMPACT_FILL_H)
    bg:SetColorTexture(0, 0, 0, 0.50)
    f.bg = bg

    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
    fill:SetHeight(COMPACT_FILL_H)
    fill:SetTexture(GetAttackTexture())
    fill:SetVertexColor(color[1], color[2], color[3])
    f.main_bar = fill

    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture(COMPACT_BAR_ART)
    f.compactBorder = border

    local timerText = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFeatureFont(timerText, 8, "swingTimersFont", "swingTimersTextStyle")
    timerText:SetPoint("CENTER", f, "CENTER", 0, COMPACT_RANGED_TIMER_TEXT_Y)
    timerText:SetTextColor(1, 1, 1)
    f.main_text = timerText

    return f
end

local function UpdateBarVisual(bar_tex, timer, speed, frame_width)
    if speed <= 0 then speed = 2 end
    local pct = 1 - math.min(timer / speed, 1)
    local w = math.max(pct * frame_width, 0.001)
    bar_tex:SetWidth(w)
end

-- =============================================================================
-- PLAYER SPEED UPDATES
-- =============================================================================

local function UpdatePlayerSpeeds()
    local mainSpeed, offSpeed = UnitAttackSpeed("player")
    if IsReadableNumber(mainSpeed) and mainSpeed > 0 then
        player.main_speed = mainSpeed
    elseif not IsReadableNumber(player.main_speed) or player.main_speed <= 0 then
        player.main_speed = 2
    end
    if IsReadableNumber(offSpeed) and offSpeed > 0 then
        player.off_speed = offSpeed
    elseif not IsReadableNumber(player.off_speed) or player.off_speed <= 0 then
        player.off_speed = 2
    end

    -- Off-hand detection: show the off-hand swing bar ONLY when an actual off-hand
    -- WEAPON is equipped. UnitAttackSpeed's off-hand speed was unreliable as the
    -- gate -- on a fresh login it can report a phantom off-hand speed with nothing
    -- in the slot, which latched has_offhand = true and drew a ghost off-hand bar
    -- (with the fallback fist icon) that persisted. GetItemInfoInstant resolves the
    -- equip location synchronously, so it's correct even before item data streams in
    -- and never false-positives on an empty slot.
    local OFFHAND_SLOT = 17
    local ohID = GetInventoryItemID("player", OFFHAND_SLOT)
    local equipLoc
    if ohID and GetItemInfoInstant then
        local _, _, _, loc = GetItemInfoInstant(ohID)
        equipLoc = loc
    end

    player.has_shield  = (equipLoc == "INVTYPE_SHIELD")
    -- INVTYPE_WEAPON = one-hand (either hand); INVTYPE_WEAPONOFFHAND = off-hand only.
    -- Shields and holdables (INVTYPE_HOLDABLE) do not swing, so they are not off-hand.
    player.has_offhand = (equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND")

end

local function UpdateTargetSpeeds()
    if not UnitExists("target") then return end
    local mainSpeed, offSpeed = UnitAttackSpeed("target")
    if IsReadableNumber(mainSpeed) and mainSpeed > 0 then
        target.main_speed = mainSpeed
    elseif not IsReadableNumber(target.main_speed) or target.main_speed <= 0 then
        target.main_speed = 2
    end
    if IsReadableNumber(offSpeed) and offSpeed > 0 then
        target.off_speed = offSpeed
        target.has_offhand = true
    elseif ns.SwingTimerProviderCanReadTargetAttackSpeed() then
        target.off_speed = 2
        target.has_offhand = false
    else
        -- Forever can hide target attack speed. Never carry an off-hand flag
        -- from the previously selected target; observed CLEU state can restore it.
        target.has_offhand = false
        if not IsReadableNumber(target.off_speed) or target.off_speed <= 0 then
            target.off_speed = 2
        end
    end
end

-- =============================================================================
-- SWING RESETS
-- =============================================================================

local function ResetPlayerMain(carry)
    player.main_timer = player.main_speed - (carry or 0)
    if player.main_timer < 0 then player.main_timer = 0 end
    player.swing_error = false
    if WakeDriver then WakeDriver() end
end

local function ResetPlayerOff(carry)
    if player.has_offhand then
        player.off_timer = player.off_speed - (carry or 0)
        if player.off_timer < 0 then player.off_timer = 0 end
        if WakeDriver then WakeDriver() end
    end
end

local function DelayPlayerOff()
    -- After MH swing with a shield equipped, delay OH by MH_speed + OH_speed/2
    if player.has_offhand then
        player.off_timer = player.main_speed + player.off_speed / 2
        if WakeDriver then WakeDriver() end
    end
end

local function ResetTargetMain()
    if UnitExists("target") then
        target.main_timer = target.main_speed
        if WakeDriver then WakeDriver() end
    end
end

local function ResetTargetOff()
    if target.has_offhand and UnitExists("target") then
        target.off_timer = target.off_speed
        if WakeDriver then WakeDriver() end
    end
end

local function RecordPendingPlayerReset(isOffHand)
    if in_combat then return end
    local now = GetTime() or 0
    if isOffHand then
        pending_player_off_reset_at = now
    else
        pending_player_main_reset_at = now
    end
end

local function RecordTargetSwing(guid, isOffHand, speed)
    if not guid or not speed or speed <= 0 then return end
    local state = targetSwingStates[guid]
    if not state then
        state = {}
        targetSwingStates[guid] = state
    end
    local now = GetTime() or 0
    if isOffHand then
        state.offReadyAt = now + speed
        state.offDuration = speed
    else
        state.mainReadyAt = now + speed
        state.mainDuration = speed
    end
    state.lastSeen = now
end

local function RestoreTargetSwing(guid)
    local state = guid and targetSwingStates[guid]
    local now = GetTime() or 0

    if state and state.mainReadyAt and state.mainReadyAt > now then
        target.main_speed = (state.mainDuration and state.mainDuration > 0) and state.mainDuration or target.main_speed
        target.main_timer = state.mainReadyAt - now
    else
        target.main_timer = 0
    end

    local canInferOffhand = target.has_offhand or not ns.SwingTimerProviderCanReadTargetAttackSpeed()
    if canInferOffhand and state and state.offReadyAt and state.offReadyAt > now then
        if not ns.SwingTimerProviderCanReadTargetAttackSpeed() then
            target.has_offhand = true
        end
        target.off_speed = (state.offDuration and state.offDuration > 0) and state.offDuration or target.off_speed
        target.off_timer = state.offReadyAt - now
    else
        target.off_timer = 0
    end
end

local function SaveCurrentTargetSwing()
    if not target.guid then return end
    local state = targetSwingStates[target.guid]
    if not state then
        state = {}
        targetSwingStates[target.guid] = state
    end
    local now = GetTime() or 0
    if target.main_timer > 0 then
        state.mainReadyAt = now + target.main_timer
        state.mainDuration = target.main_speed
    else
        state.mainReadyAt = nil
        state.mainDuration = nil
    end
    if target.has_offhand and target.off_timer > 0 then
        state.offReadyAt = now + target.off_timer
        state.offDuration = target.off_speed
    else
        state.offReadyAt = nil
        state.offDuration = nil
    end
    state.lastSeen = now
end

local function LatestResetAt(a, b)
    if a and b then return math.max(a, b) end
    return a or b
end

local function RemainingFromReset(resetAt, speed, now)
    if not resetAt then return 0 end
    return math.max((speed or 0) - math.max(now - resetAt, 0), 0)
end

-- =============================================================================
-- COMBAT LOG HANDLING
-- =============================================================================

-- Nameplate swing tracking is a separate lightweight consumer. It wakes only
-- for the Nameplate Swing Timer feature and does not require the Global Swing
-- Timers presentation/runtime to be enabled.
local function OnNameplateCombatLog(combatInfo)
    local subevent = combatInfo[2]
    if subevent ~= "SWING_DAMAGE" and subevent ~= "SWING_MISSED" then return end

    local sourceGUID = combatInfo[4]
    local unit = sourceGUID and ns.guidToNameplateUnit and ns.guidToNameplateUnit[sourceGUID]
    -- This owner tracks hostile attackable nameplates only. Friendly plates can
    -- also emit SWING_* while visible (duels, guards/NPC interactions, etc.);
    -- reject them before allocating per-GUID timing state.
    if not unit or not UnitExists(unit) or not UnitCanAttack("player", unit) then return end

    local state = nameplateSwingStates[sourceGUID]
    if not state then
        state = {}
        nameplateSwingStates[sourceGUID] = state
    end

    local now = GetTime()
    local speed
    if not ns.SwingTimerProviderCanReadNameplateAttackSpeed() then
        -- Some modern clients restrict UnitAttackSpeed(nameplateN).
        -- Infer cadence from observed CLEU swings instead. The first observed
        -- swing gets the conservative historical 2s fallback; subsequent swings
        -- learn the visible mob's cadence without touching secret unit stats.
        if state.lastSwingAt then
            speed = now - state.lastSwingAt
            if speed < 0.4 or speed > 6 then speed = state.duration end
        end
        speed = tonumber(speed) or tonumber(state.duration) or 2
        state.lastSwingAt = now
    else
        local isOffHand = subevent == "SWING_DAMAGE" and combatInfo[21] or combatInfo[13]
        local mainSpeed, offSpeed = UnitAttackSpeed(unit)
        speed = (isOffHand and offSpeed) or mainSpeed or offSpeed or 2
        if speed <= 0 then speed = 2 end
    end
    state.readyAt = now + speed
    state.duration = speed
    if ns.BubbleNameplates then ns.BubbleNameplates:OnEnemySwing(sourceGUID) end
end

-- Combat-log payload is decoded once by ns.CLEU and passed in as `combatInfo`.
local function OnCombatLog(combatInfo)
    if not PLAYER_GUID then PLAYER_GUID = UnitGUID("player") end

    local subevent     = combatInfo[2]
    local sourceGUID   = combatInfo[4]
    local destGUID     = combatInfo[8]

    -- ── Player as SOURCE ─────────────────────────────────────────────────────
    if sourceGUID == PLAYER_GUID then
        if not playerSwingEventActive and subevent == "SWING_DAMAGE" then
            local isOffHand = combatInfo[21]
            player.swing_error = false
            if isOffHand then
                player.delay_offhand = false
                RecordPendingPlayerReset(true)
                ResetPlayerOff()
            else
                RecordPendingPlayerReset(false)
                ResetPlayerMain()
                if player.has_shield then
                    player.delay_offhand = true
                end
                -- Main-hand swing fired: queued spell consumed
                if queued_spell_id then
                    ClearQueuedSpell()
                end
            end

        elseif not playerSwingEventActive and subevent == "SWING_MISSED" then
            local isOffHand = combatInfo[13]
            player.swing_error = false
            if isOffHand then
                player.delay_offhand = false
                RecordPendingPlayerReset(true)
                ResetPlayerOff()
            else
                RecordPendingPlayerReset(false)
                ResetPlayerMain()
                if player.has_shield then
                    player.delay_offhand = true
                end
            end

        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
            local spellID = combatInfo[12]
            if SWING_SPELL_DATA.IsNextMelee(spellID) then
                if not playerSwingEventActive then
                    -- Era fallback: queued yellow hit replaced the white MH swing.
                    RecordPendingPlayerReset(false)
                    ResetPlayerMain()
                    if player.has_shield then player.delay_offhand = true end
                end
                if queued_spell_id then ClearQueuedSpell() end
            elseif SWING_SPELL_DATA.ResetsMeleeOnItemEffect(spellID) then
                ResetPlayerMain()
                ResetPlayerOff()
            end
        end
    end

    -- ── Player as DESTINATION ────────────────────────────────────────────────
    if destGUID == PLAYER_GUID then
        local missType
        if subevent == "SWING_MISSED"  then missType = combatInfo[12]
        elseif subevent == "SPELL_MISSED" then missType = combatInfo[15]
        end

        if missType == "PARRY" then
            -- Parry haste: reduce MH timer by 40% of weapon speed, min 20%
            local min_time = player.main_speed * 0.2
            if player.main_timer > min_time then
                player.main_timer = math.max(player.main_timer - player.main_speed * 0.4, min_time)
                if WakeDriver then WakeDriver() end
            end
        end
    end

    -- ── Target as SOURCE ─────────────────────────────────────────────────────
    if target.guid and sourceGUID == target.guid then
        if subevent == "SWING_DAMAGE" then
            local isOffHand = combatInfo[21]
            if isOffHand then
                if not ns.SwingTimerProviderCanReadTargetAttackSpeed() then target.has_offhand = true end
                ResetTargetOff()
                RecordTargetSwing(sourceGUID, true, target.off_speed)
            else
                ResetTargetMain()
                RecordTargetSwing(sourceGUID, false, target.main_speed)
            end

        elseif subevent == "SWING_MISSED" then
            local isOffHand = combatInfo[13]
            if isOffHand then
                if not ns.SwingTimerProviderCanReadTargetAttackSpeed() then target.has_offhand = true end
                ResetTargetOff()
                RecordTargetSwing(sourceGUID, true, target.off_speed)
            else
                ResetTargetMain()
                RecordTargetSwing(sourceGUID, false, target.main_speed)
            end

        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
            local spellID   = combatInfo[12]
            -- Check if target class uses queued spells
            if SWING_SPELL_DATA.IsNextMelee(spellID) then
                ResetTargetMain()
                RecordTargetSwing(sourceGUID, false, target.main_speed)
            end
        end
    end

    -- ── Target as DESTINATION ────────────────────────────────────────────────
    if target.guid and destGUID == target.guid then
        local missType
        if subevent == "SWING_MISSED"  then missType = combatInfo[12]
        elseif subevent == "SPELL_MISSED" then missType = combatInfo[15]
        end

        if missType == "PARRY" then
            local min_time = target.main_speed * 0.2
            if target.main_timer > min_time then
                target.main_timer = math.max(target.main_timer - target.main_speed * 0.4, min_time)
                SaveCurrentTargetSwing()
                if WakeDriver then WakeDriver() end
            end
        end
    end
end

-- =============================================================================
-- IDLE-GATED UPDATE DRIVER
-- =============================================================================

local UPDATE_THROTTLE = 0.033  -- ~30fps is plenty while a timer is animating
local TIMER_EPSILON = 0.0005
local driverRunning = false
local StopDriver

local function SetTimerText(fontString, timer)
    if not fontString then return end
    local tenths = math.floor(math.max(timer or 0, 0) * 10 + 0.5)
    if fontString._lastTenths ~= tenths then
        fontString._lastTenths = tenths
        fontString:SetFormattedText("%.1f", tenths / 10)
    end
end

local function SetLabeledTimerText(fontString, label, timer)
    if not fontString then return end
    local tenths = math.floor(math.max(timer or 0, 0) * 10 + 0.5)
    if fontString._lastTenths ~= tenths or fontString._lastLabel ~= label then
        fontString._lastTenths = tenths
        fontString._lastLabel = label
        fontString:SetFormattedText("%s %.1f", label, tenths / 10)
    end
end

local function HasRangedWeapon()
    return IS_RANGED_CLASS and GetInventoryItemID("player", INVSLOT_RANGED) ~= nil
end

local function DriverNeeded()
    -- Player melee bars can remain visibly parked at 0.0 while combat continues;
    -- no frame loop is needed until a reset/event starts a new countdown.
    if in_combat then
        if player.main_timer > TIMER_EPSILON then return true end
        if player.has_offhand and player.is_attacking and player.off_timer > TIMER_EPSILON then return true end

        if UnitExists("target") and UnitCanAttack("player", "target") then
            if target.main_timer > TIMER_EPSILON then return true end
            if target.has_offhand and target.off_timer > TIMER_EPSILON then return true end
        end
    end

    if playerSwingFinishingOutOfCombat then
        if player.main_timer > TIMER_EPSILON then return true end
        if player.has_offhand and player.off_timer > TIMER_EPSILON then return true end
    end

    if HasRangedWeapon() then
        -- Auto-repeat needs movement/cast-window polling. Hunters that entered
        -- combat without auto-repeat only need the driver until their initial
        -- ready-state countdown reaches the cast window.
        if ranged.shooting then return true end
        if in_combat and not IS_SECONDARY_RANGED_CLASS and ranged.timer > (ranged.cast_time + TIMER_EPSILON) then
            return true
        end
    end

    return false
end

-- MODULE MASTER GATE for the swing rows. Hides the frames rather than merely
-- skipping their update: an early return alone would freeze whatever was last
-- drawn on screen. The rows release their slot on hide via the OnHide hook, so
-- the remaining rows compact automatically.
local function SwingGateOff()
    if not ns.ModuleEnabled then return false end
    return not ns.ModuleEnabled("swingTimers")
end

local function HideAllSwingRows()
    if playerFrame then playerFrame:Hide() end
    if enemyFrame then enemyFrame:Hide() end
    if rangedFrame then rangedFrame:Hide() end
    HideStandaloneSwingRows()
end

local function OnUpdate(self, elapsed)
    if SwingGateOff() then
        HideAllSwingRows()
        StopDriver()
        return
    end
    local dt = elapsed

    -- ── Player timers ────────────────────────────────────────────────────────
    local now = GetTime() or 0
    local attackActive = IsCurrentSpell(6603)  -- "Attack" spell ID
    if attackActive then
        last_attack_active_at = now
        target_change_attack_grace_until = 0
    elseif now < target_change_attack_grace_until and (now - last_attack_active_at) < 0.5 then
        attackActive = true
    elseif target_change_attack_grace_until > 0 and now >= target_change_attack_grace_until then
        target_change_attack_grace_until = 0
    end
    player.is_attacking = attackActive

    if (in_combat or playerSwingFinishingOutOfCombat) and playerFrame then
        -- Count down
        if player.main_timer > 0 then
            player.main_timer = math.max(player.main_timer - dt, 0)
        end
        if player.has_offhand and player.off_timer > 0 then
            player.off_timer = math.max(player.off_timer - dt, 0)
        end

        -- Offhand idle limit: don't let it sit below 55% when not attacking.
        -- Once parked there, DriverNeeded() can stop the frame loop.
        if in_combat and not player.is_attacking and player.has_offhand and player.off_timer > TIMER_EPSILON then
            local limit = player.off_speed * 0.55
            if player.off_timer < limit then player.off_timer = limit end
        end

        local embeddedPlayer = embeddedPlayerTimers
        if embeddedPlayer then
            if standaloneMainFrame then standaloneMainFrame:Hide() end
            if standaloneOffFrame then standaloneOffFrame:Hide() end

            -- Current baked-in presentation: one compact row, split into
            -- main/off tracks while dual-wielding.
            if playerFrame._layoutHasOffhand ~= player.has_offhand then
                LayoutCompactMelee(playerFrame, player.has_offhand)
            end
            if not playerFrame:IsShown() then playerFrame:Show() end
            playerFrame.main_bar:Show()
            playerFrame.main_text:Show()
            if player.has_offhand then
                playerFrame.off_bar:Show()
                playerFrame.off_text:Show()
            else
                playerFrame.off_bar:Hide()
                playerFrame.off_text:Hide()
            end

            local playerW = playerFrame._fillWidth or playerFrame:GetWidth()
            UpdateBarVisual(playerFrame.main_bar, player.main_timer, player.main_speed, playerW)
            if player.has_offhand then
                UpdateBarVisual(playerFrame.off_bar, player.off_timer, player.off_speed, playerW)
                SetLabeledTimerText(playerFrame.main_text, "MH", player.main_timer)
                SetLabeledTimerText(playerFrame.off_text, "OH", player.off_timer)
            else
                SetTimerText(playerFrame.main_text, player.main_timer)
            end
        else
            -- Legacy standalone presentation, but driven by the modern engine.
            playerFrame:Hide()
            if not standaloneMainFrame:IsShown() then standaloneMainFrame:Show() end
            local sw = standaloneMainFrame:GetWidth()
            UpdateBarVisual(standaloneMainFrame.main_bar, player.main_timer, player.main_speed, sw)
            SetTimerText(standaloneMainFrame.main_text, player.main_timer)

            if not cachedMHText then cachedMHText = GetWeaponDamageText(false) end
            if standaloneMainFrame.main_label._lastText ~= cachedMHText then
                standaloneMainFrame.main_label:SetText(cachedMHText)
                standaloneMainFrame.main_label._lastText = cachedMHText
            end

            local mhIcon
            if queued_spell_id and GetSpellTexture then mhIcon = GetSpellTexture(queued_spell_id) end
            if not mhIcon and PLAYER_CLASS == "DRUID" then
                if cachedDruidFormIcon == nil then cachedDruidFormIcon = GetActiveDruidMeleeFormIcon() or false end
                mhIcon = cachedDruidFormIcon or nil
            end
            if not mhIcon then
                if cachedIconMH == nil then cachedIconMH = GetWeaponIcon(INVSLOT_MAINHAND or 16) or false end
                mhIcon = cachedIconMH or nil
            end
            if standaloneMainFrame.main_icon and standaloneMainFrame.main_icon._lastTexture ~= mhIcon then
                standaloneMainFrame.main_icon:SetTexture(mhIcon)
                standaloneMainFrame.main_icon._lastTexture = mhIcon
            end

            if player.has_offhand then
                if not standaloneOffFrame:IsShown() then standaloneOffFrame:Show() end
                UpdateBarVisual(standaloneOffFrame.main_bar, player.off_timer, player.off_speed, standaloneOffFrame:GetWidth())
                SetTimerText(standaloneOffFrame.main_text, player.off_timer)
                if not cachedOHText then cachedOHText = GetWeaponDamageText(true) end
                if standaloneOffFrame.main_label._lastText ~= cachedOHText then
                    standaloneOffFrame.main_label:SetText(cachedOHText)
                    standaloneOffFrame.main_label._lastText = cachedOHText
                end
                if cachedIconOH == nil then cachedIconOH = GetWeaponIcon(INVSLOT_OFFHAND or 17) or false end
                local ohIcon = cachedIconOH or nil
                if standaloneOffFrame.main_icon and standaloneOffFrame.main_icon._lastTexture ~= ohIcon then
                    standaloneOffFrame.main_icon:SetTexture(ohIcon)
                    standaloneOffFrame.main_icon._lastTexture = ohIcon
                end
            elseif standaloneOffFrame then
                standaloneOffFrame:Hide()
            end
        end

        if not in_combat and playerSwingFinishingOutOfCombat
            and player.main_timer <= TIMER_EPSILON
            and (not player.has_offhand or player.off_timer <= TIMER_EPSILON) then
            playerSwingFinishingOutOfCombat = false
            playerFrame.main_bar:Hide()
            playerFrame.off_bar:Hide()
            playerFrame.main_text:Hide()
            playerFrame.off_text:Hide()
            playerFrame:Hide()
            if standaloneMainFrame then standaloneMainFrame:Hide() end
            if standaloneOffFrame then standaloneOffFrame:Hide() end
        end
    else
        if playerFrame then
            -- No swing running: release the row entirely rather than leaving an
            -- empty border sitting in a slot.
            playerFrame.main_bar:Hide()
            playerFrame.off_bar:Hide()
            playerFrame.main_text:Hide()
            playerFrame.off_text:Hide()
            playerFrame:Hide()
        end
        if standaloneMainFrame then standaloneMainFrame:Hide() end
        if standaloneOffFrame then standaloneOffFrame:Hide() end
    end

    -- ── Target attack timer ───────────────────────────────────────────────────
    -- The target presentation intentionally uses one embedded row only. Enemy
    -- off-hand state is still tracked for timing accuracy elsewhere, but it is
    -- not presented as a second MH/OH row on the target unit frame.
    if in_combat and enemyFrame and UnitExists("target") and UnitCanAttack("player","target") then
        if target.main_timer > 0 then
            target.main_timer = math.max(target.main_timer - dt, 0)
        end
        if target.has_offhand and target.off_timer > 0 then
            target.off_timer = math.max(target.off_timer - dt, 0)
        end

        if embeddedTargetTimers then
            if standaloneTargetFrame then standaloneTargetFrame:Hide() end
            if not enemyFrame:IsShown() then enemyFrame:Show() end
            enemyFrame.main_bar:Show()
            enemyFrame.main_text:Show()
            local targetBarW = enemyFrame._fillWidth or enemyFrame:GetWidth()
            UpdateBarVisual(enemyFrame.main_bar, target.main_timer, target.main_speed, targetBarW)
            SetTimerText(enemyFrame.main_text, target.main_timer)
        else
            enemyFrame:Hide()
            if not standaloneTargetFrame:IsShown() then standaloneTargetFrame:Show() end
            UpdateBarVisual(standaloneTargetFrame.main_bar, target.main_timer, target.main_speed, standaloneTargetFrame:GetWidth())
            SetTimerText(standaloneTargetFrame.main_text, target.main_timer)
        end
    elseif enemyFrame then
        -- No hostile swing running: release both possible presentation surfaces.
        enemyFrame.main_bar:Hide()
        enemyFrame.main_text:Hide()
        enemyFrame:Hide()
        if standaloneTargetFrame then standaloneTargetFrame:Hide() end
    end

    -- ── Ranged timer ─────────────────────────────────────────────────────────
    if IS_RANGED_CLASS and rangedFrame then
        -- Only show when a ranged weapon is equipped. Wand users show the bar ONLY
        -- while actively wanding (ranged.shooting); showing it on plain in-combat
        -- drew a phantom bar under the melee swing timer. Hunters keep the in-combat
        -- behavior because their ranged weapon is the primary auto-attack.
        local hasRanged = HasRangedWeapon()
        if hasRanged and (ranged.shooting or (in_combat and not IS_SECONDARY_RANGED_CLASS)) then
            ranged.has_moved = (GetUnitSpeed("player") > 0)

            -- Count down
            ranged.timer = ranged.timer - dt
            if ranged.timer < 0 then ranged.timer = 0 end

            -- Determine if auto cast window (ready to fire)
            if ranged.timer <= ranged.cast_time then
                ranged.ready = true
                if not ranged.shooting then
                    -- Not shooting — reset to cast_time
                    ranged.timer = ranged.cast_time
                end
            else
                ranged.ready = false
            end

            -- If moved or casting non-auto spell, clamp timer
            if ranged.has_moved or ranged.casting then
                if ranged.timer <= ranged.cast_time then
                    ranged.timer = ranged.cast_time
                end
            end

            if embeddedPlayerTimers then
                if standaloneRangedFrame then standaloneRangedFrame:Hide() end
                local wasShown = rangedFrame:IsShown()
                if not wasShown then rangedFrame:Show() end
                local pct = 1 - math.min(ranged.timer / math.max(ranged.speed, 0.1), 1)
                local rBarW = math.max(pct * COMPACT_FILL_W, 0.001)
                rangedFrame.main_bar:SetWidth(rBarW)
                if ranged.ready then
                    rangedFrame.main_bar:SetVertexColor(0.8, 0.0, 0.0, 1)
                else
                    rangedFrame.main_bar:SetVertexColor(0.95, 0.95, 0.95, 1)
                end
                SetTimerText(rangedFrame.main_text, ranged.timer)
                if not wasShown and ST.ReanchorPlayer then ST:ReanchorPlayer() end
            else
                rangedFrame:Hide()
                if not standaloneRangedFrame:IsShown() then standaloneRangedFrame:Show() end
                local pct = 1 - math.min(ranged.timer / math.max(ranged.speed, 0.1), 1)
                standaloneRangedFrame.main_bar:SetWidth(math.max(pct * standaloneRangedFrame:GetWidth(), 0.001))
                if ranged.ready then
                    standaloneRangedFrame.main_bar:SetVertexColor(0.8, 0.0, 0.0, 1)
                else
                    standaloneRangedFrame.main_bar:SetVertexColor(0.95, 0.95, 0.95, 1)
                end
                SetTimerText(standaloneRangedFrame.main_text, ranged.timer)
                if not cachedRangedText then cachedRangedText = GetRangedDamageText() end
                if standaloneRangedFrame.main_label._lastText ~= cachedRangedText then
                    standaloneRangedFrame.main_label:SetText(cachedRangedText)
                    standaloneRangedFrame.main_label._lastText = cachedRangedText
                end
                if cachedIconRanged == nil then cachedIconRanged = GetWeaponIcon(INVSLOT_RANGED) or false end
                local rIcon = cachedIconRanged or nil
                if standaloneRangedFrame.main_icon and standaloneRangedFrame.main_icon._lastTexture ~= rIcon then
                    standaloneRangedFrame.main_icon:SetTexture(rIcon)
                    standaloneRangedFrame.main_icon._lastTexture = rIcon
                end
            end
        else
            if rangedFrame:IsShown() then
                rangedFrame:Hide()
                if ST.ReanchorPlayer then ST:ReanchorPlayer() end
            end
            if standaloneRangedFrame then standaloneRangedFrame:Hide() end
        end
    end

    if not DriverNeeded() then
        StopDriver()
    end
end

StopDriver = function()
    if not driverRunning then return end
    driverRunning = false
    if ns.Cadence then ns.Cadence:Remove(ST) end
end

WakeDriver = function()
    if driverRunning or not eventFrame then return end
    driverRunning = true
    if ns.Cadence then ns.Cadence:Add(ST, UPDATE_THROTTLE, OnUpdate, true) end
end

local function NameplateRuntimeOnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        nameplateInCombat = true
        PrimeVisibleNameplateStates()
    elseif event == "PLAYER_REGEN_ENABLED" then
        nameplateInCombat = false
        SwingTimers:ClearNameplateStates()
        if ns.BubbleNameplates and ns.BubbleNameplates.RefreshSwingFeature then
            ns.BubbleNameplates:RefreshSwingFeature()
        end
    end
end

local function ActivateNameplateRuntime()
    if nameplateRuntimeActivated or not NameplateSwingGateOn() then return end
    nameplateRuntimeActivated = true
    if not nameplateRuntimeFrame then
        nameplateRuntimeFrame = CreateFrame("Frame")
        nameplateRuntimeFrame:SetScript("OnEvent", NameplateRuntimeOnEvent)
    end
    nameplateRuntimeFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    nameplateRuntimeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if ns.CLEU then
        ns.CLEU:Register(OnNameplateCombatLog, { SWING_DAMAGE = true, SWING_MISSED = true })
    end
    nameplateInCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
    if nameplateInCombat then PrimeVisibleNameplateStates() end
end

local function DeactivateNameplateRuntime()
    if not nameplateRuntimeActivated then return end
    nameplateRuntimeActivated = false
    nameplateInCombat = false
    if nameplateRuntimeFrame then nameplateRuntimeFrame:UnregisterAllEvents() end
    if ns.CLEU then ns.CLEU:Unregister(OnNameplateCombatLog) end
    SwingTimers:ClearNameplateStates()
end

function SwingTimers:RefreshNameplateRuntime()
    if NameplateSwingGateOn() then
        ActivateNameplateRuntime()
    else
        DeactivateNameplateRuntime()
    end
end

-- =============================================================================
-- EVENT FRAME
-- =============================================================================

-- Vanilla rule: completing a HARD cast (a spell with a cast time) resets both
-- melee swing timers -- a 3.1 speed staff counts the full 3.1s again after the
-- cast lands. Instants and channels never fire UNIT_SPELLCAST_START, so they
-- never set this and fall through untouched. Tracked by cast GUID so button
-- spam mid-cast (which fires FAILED_QUIET for the OTHER spell) can't clear it.
local player_cast_guid
local player_ranged_cast_guid
local player_ranged_cast_kind

-- A hostile cast-time opener can report UNIT_SPELLCAST_SUCCEEDED before
-- PLAYER_REGEN_DISABLED (for example, a projectile spell enters combat when it
-- lands). Preserve the cast completion time while out of combat so combat entry
-- can restore only the still-unelapsed portion of the legitimate swing reset
-- instead of replacing it with the generic ready state.

-- The opening melee CLEU event can arrive just before PLAYER_REGEN_DISABLED.
-- Preserve those real reset timestamps so combat entry cannot erase the first
-- swing. Main-hand and off-hand are tracked independently for dual wield.

-- The event frame exists at file load but is deliberately inert. Runtime
-- subscriptions are activated only from ST:Init(), after saved variables have
-- been normalized and the swingTimers module gate is known. This keeps a
-- disabled Swing Timers module completely off the shared CLEU dispatcher and
-- out of WoW's event dispatch path.
eventFrame = CreateFrame("Frame")
local runtimeActivated = false

local function ActivateRuntime()
    if runtimeActivated then return end
    runtimeActivated = true

    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- Use a sanctioned player-swing clock when the active client provider
    -- exposes one; otherwise the CLEU/spellcast fallback remains authoritative.
    playerSwingEventActive = ns.SwingTimerProviderUsesPlayerSwingEvent()
        and ns.API.RegisterEvent(eventFrame, "PLAYER_SWING") or false
    -- player-only: every unit branch in OnEvent tests `unit == "player"`.
    ns.RegisterUnitEvent(eventFrame, "UNIT_ATTACK_SPEED", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_INVENTORY_CHANGED", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_DAMAGE", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_RANGEDDAMAGE", "player")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")  -- wake when Attack toggles
    eventFrame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")  -- on-next-swing queue
    eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if ns.SwingTimerProviderUsesCharacterDamageCapture() then
        ns.SwingTimerProviderInstallCharacterDamageCapture(ST, eventFrame)
    end
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_SENT", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_FAILED_QUIET", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_START", "player")  -- hard-cast swing reset
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_STOP", "player")
    ns.RegisterUnitEvent(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player")
    if PLAYER_CLASS == "DRUID" then
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    end
    if IS_RANGED_CLASS then
        eventFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
        eventFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    end

    -- Combat-log events come from the shared dispatcher (decoded once), not our
    -- own CLEU subscription.
    if ns.CLEU then ns.CLEU:Register(OnCombatLog, { SWING_DAMAGE = true, SWING_MISSED = true, SPELL_DAMAGE = true, SPELL_MISSED = true }) end
end

-- Teardown counterpart to ActivateRuntime. Swing Timers are reload-oriented
-- (ARCHITECTURE 4.5) and Init() already refuses to activate while the gate is
-- off, so this is not needed for a clean login. It exists so this file matches
-- every other ns.CLEU consumer -- ClassFeatures, CombatMeter, HealPrediction,
-- nanShield and DotPrediction all unregister -- and so a live gate change
-- stops the swing runtime instead of leaving a CLEU handler and a dozen events
-- subscribed until the user reloads.
local function DeactivateRuntime()
    if not runtimeActivated then return end
    runtimeActivated = false
    playerSwingEventActive = false
    eventFrame:UnregisterAllEvents()
    if ns.CLEU then ns.CLEU:Unregister(OnCombatLog) end
    playerSwingFinishingOutOfCombat = false
    StopDriver()
end

local swingEventHandlers = {}

swingEventHandlers.PLAYER_REGEN_DISABLED = function()
    local carriedMain = playerSwingFinishingOutOfCombat
        and player.main_timer > TIMER_EPSILON and player.main_timer or nil
    local carriedOff = playerSwingFinishingOutOfCombat and player.has_offhand
        and player.off_timer > TIMER_EPSILON and player.off_timer or nil
    playerSwingFinishingOutOfCombat = false
    in_combat = true
    UpdatePlayerSpeeds()
    -- Entering combat alone does not mean the player has already swung.
    -- However, Classic may report either an opening melee swing or a completed
    -- cast-time opener immediately before PLAYER_REGEN_DISABLED. Carry only
    -- the unelapsed portion of those real resets into combat; otherwise start
    -- each weapon row ready.
    local now = GetTime() or 0
    local hardCastAt = pending_hard_cast_reset_at
    local mainResetAt = LatestResetAt(hardCastAt, pending_player_main_reset_at)
    local offResetAt  = LatestResetAt(hardCastAt, pending_player_off_reset_at)
    pending_hard_cast_reset_at = nil
    pending_player_main_reset_at = nil
    pending_player_off_reset_at = nil

    player.main_timer = mainResetAt
        and RemainingFromReset(mainResetAt, player.main_speed, now) or (carriedMain or 0)
    if player.has_offhand then
        player.off_timer = offResetAt
            and RemainingFromReset(offResetAt, player.off_speed, now) or (carriedOff or 0)
    else
        player.off_timer = 0
    end
    player.swing_error = false
    player.delay_offhand = false
    target_change_attack_grace_until = 0
    if UnitExists("target") and UnitCanAttack("player", "target") then
        target.guid = UnitGUID("target")
        UpdateTargetSpeeds()
        RestoreTargetSwing(target.guid)
    end
    WakeDriver()
end

swingEventHandlers.PLAYER_REGEN_ENABLED = function()
    in_combat = false
    -- Preserve only a timer that was genuinely still counting down at the
    -- combat boundary. The cadence driver finishes it out of combat, hides
    -- the row at ready, and can carry the remainder into an immediate next
    -- pull. No new idle swing is fabricated.
    playerSwingFinishingOutOfCombat = player.main_timer > TIMER_EPSILON
        or (player.has_offhand and player.off_timer > TIMER_EPSILON)
    player.swing_error = false
    player.delay_offhand = false
    last_attack_active_at = 0
    target_change_attack_grace_until = 0
    pending_hard_cast_reset_at = nil
    pending_player_main_reset_at = nil
    pending_player_off_reset_at = nil
    player_cast_guid = nil
    player_ranged_cast_guid = nil
    player_ranged_cast_kind = nil
    wipe(targetSwingStates)
    if playerFrame and not playerSwingFinishingOutOfCombat then
        -- No swing running: release the row entirely rather than leaving an
        -- empty border sitting in a slot.
        playerFrame.main_bar:Hide()
        playerFrame.off_bar:Hide()
        playerFrame.main_text:Hide()
        playerFrame.off_text:Hide()
        playerFrame:Hide()
    end
    if enemyFrame then
        enemyFrame.main_bar:Hide()
        enemyFrame.main_text:Hide()
        enemyFrame:Hide()
    end
    if standaloneMainFrame and not playerSwingFinishingOutOfCombat then standaloneMainFrame:Hide() end
    if standaloneOffFrame and not playerSwingFinishingOutOfCombat then standaloneOffFrame:Hide() end
    if standaloneTargetFrame then standaloneTargetFrame:Hide() end
    if not (IS_RANGED_CLASS and ranged.shooting) then
        if rangedFrame then rangedFrame:Hide() end
        if standaloneRangedFrame then standaloneRangedFrame:Hide() end
        if playerSwingFinishingOutOfCombat then WakeDriver() else StopDriver() end
    else
        WakeDriver()
    end
end

swingEventHandlers.PLAYER_SWING = function(duration, swingType)
    if not IsReadableNumber(duration) or duration <= 0 then return end
    local slot = PlayerSwingSlot(swingType)
    if not slot then return end

    local now = GetTime() or 0
    lastPlayerSwingType = ns.API.SafeToString and ns.API.SafeToString(swingType, "?") or tostring(swingType)
    lastPlayerSwingDuration = duration
    lastPlayerSwingAt = now
    player.swing_error = false

    if slot == "main" then
        player.main_speed = duration
        player.main_timer = duration
        pending_player_main_reset_at = (not in_combat) and now or nil
        if queued_spell_id then ClearQueuedSpell() end
    elseif slot == "off" then
        player.has_offhand = true
        player.off_speed = duration
        player.off_timer = duration
        player.delay_offhand = false
        pending_player_off_reset_at = (not in_combat) and now or nil
    elseif slot == "ranged" then
        ranged.speed = duration
        ranged.timer = duration
        ranged.last_shot_time = now
        ranged.ready = false
        ranged.casting = false
        if ranged.base_speed and ranged.base_speed > 0 then
            ranged.cast_time = 0.52 * (duration / ranged.base_speed)
        end
    end
    WakeDriver()
end

swingEventHandlers.PLAYER_TARGET_CHANGED = function()
    local now = GetTime() or 0
    if in_combat and (player.is_attacking or (now - last_attack_active_at) < 0.25) then
        target_change_attack_grace_until = now + 0.35
    end
    -- PLAYER_TARGET_CHANGED fires after the unit token switches, but target.guid
    -- still identifies our outgoing target here. Snapshot its current phase
    -- before loading the newly selected target's cached phase.
    SaveCurrentTargetSwing()
    if UnitExists("target") then
        target.guid = UnitGUID("target")
        UpdateTargetSpeeds()
        RestoreTargetSwing(target.guid)
    else
        target.guid = nil
        target.main_timer = 0
        target.off_timer = 0
    end
    -- Player weapon cadence is target-independent. Do not clamp or reset
    -- either player timer merely because the selected target changed.
    -- Target changes do not justify inferred queue state. Ask the client:
    -- Classic may retain the on-next-swing queue, and CURRENT_SPELL_CAST_CHANGED
    -- remains authoritative if it actually drops it.
    RefreshQueuedSpell()
    if in_combat then
        WakeDriver()
    elseif enemyFrame then
        enemyFrame.main_bar:Hide()
        enemyFrame.main_text:Hide()
        enemyFrame:Hide()
        if standaloneTargetFrame then standaloneTargetFrame:Hide() end
    end
end

swingEventHandlers.UPDATE_SHAPESHIFT_FORM = function()
    UpdatePlayerSpeeds()
    InvalidateWeaponIcons()
    RefreshQueuedSpell()
    WakeDriver()
end

swingEventHandlers.UNIT_ATTACK_SPEED = function(unit)
    if unit == "player" then
        local old_main = player.main_speed
        local old_off  = player.off_speed
        UpdatePlayerSpeeds()
        -- Scale remaining timers proportionally
        if old_main > 0 then
            player.main_timer = player.main_timer * (player.main_speed / old_main)
        end
        if player.has_offhand and old_off > 0 then
            player.off_timer = player.off_timer * (player.off_speed / old_off)
        end
        -- Also update ranged speed — UnitRangedDamage returns hasted speed
        if IS_RANGED_CLASS then
            local new_ranged_spd = ReadRangedSpeed()
            if new_ranged_spd and new_ranged_spd ~= ranged.speed then
                -- Scale remaining timer proportionally
                if ranged.speed > 0 and not ranged.ready then
                    ranged.timer = ranged.timer * (new_ranged_spd / ranged.speed)
                end
                ranged.speed = new_ranged_spd
            end
        end
        WakeDriver()
    elseif unit == "target" then
        local old_main = target.main_speed
        local old_off  = target.off_speed
        UpdateTargetSpeeds()
        if old_main > 0 then
            target.main_timer = target.main_timer * (target.main_speed / old_main)
        end
        if target.has_offhand and old_off > 0 then
            target.off_timer = target.off_timer * (target.off_speed / old_off)
        end
        SaveCurrentTargetSwing()
        WakeDriver()
    end
end

swingEventHandlers.UNIT_INVENTORY_CHANGED = function(unit)
    if unit == "player" then
        local mainID, offID, rangedID = ReadEquippedWeaponIDs()
        local meleeWeaponChanged = (mainID ~= equippedMainID) or (offID ~= equippedOffID)
        local rangedWeaponChanged = (rangedID ~= equippedRangedID)

        -- Update the identities first so any nested inventory notification
        -- generated by item-info/UI work sees the new stable snapshot.
        equippedMainID, equippedOffID, equippedRangedID = mainID, offID, rangedID

        if meleeWeaponChanged then
            UpdatePlayerSpeeds()
            InvalidateWeaponIcons()
            InvalidateDamageText()
            -- Preserve the established weapon-swap behavior, but only for
            -- an actual MH/OH identity change. Ranged/ammo churn is separate.
            ResetPlayerMain()
            if player.delay_offhand then
                DelayPlayerOff()
            else
                ResetPlayerOff()
            end
        end

        if IS_RANGED_CLASS and rangedWeaponChanged then
            cachedIconRanged = nil
            cachedRangedText = nil
            wipe(_rangedSpeedCache)
            ranged.base_speed = GetRangedBaseSpeed()
            local hasted_spd = ReadRangedSpeed()
            ranged.speed = hasted_spd or ranged.base_speed
            ranged.timer = ranged.speed
            ranged.ready = false
            if ranged.base_speed > 0 then
                ranged.cast_time = 0.52 * (ranged.speed / ranged.base_speed)
            end
            WakeDriver()
        end
    elseif unit == "target" then
        UpdateTargetSpeeds()
        ResetTargetMain()
        ResetTargetOff()
    end
end

swingEventHandlers.UI_ERROR_MESSAGE = function(_, msg)
    if SWING_ERROR_MESSAGES[msg] then
        player.swing_error = true
    end
end

swingEventHandlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
    if unit ~= "player" then return end

    -- Classic melee-reset model:
    --   * ordinary completed hard casts reset unless explicitly exempt;
    --   * selected instant/special spells reset from the maintained data
    --     table even though they never establish player_cast_guid.
    -- The explicit list also catches a normally cast-time Druid spell
    -- when another effect makes it instant.
    local rangedShotKind = ClassifyRangedShotSpell(spellID)
    if not rangedShotKind and castGUID and castGUID == player_ranged_cast_guid then
        rangedShotKind = player_ranged_cast_kind
    end
    local completedHardCast = (not rangedShotKind)
        and player_cast_guid and castGUID == player_cast_guid

    -- Consume whichever cast tracker owns this GUID. Preserve the shot
    -- kind through this decision so Era can retain its historical ranged
    -- interaction model; clients with PLAYER_SWING keep ranged swings isolated from MH/OH.
    if castGUID and castGUID == player_ranged_cast_guid then
        player_ranged_cast_guid = nil
        player_ranged_cast_kind = nil
    end
    if castGUID and castGUID == player_cast_guid then
        player_cast_guid = nil
    end

    local shouldResetMelee = ((not playerSwingEventActive) and rangedShotKind == "wand")
        or ((not rangedShotKind) and (
            SWING_SPELL_DATA.ResetsMeleeOnSuccess(spellID)
            or (completedHardCast and not SWING_SPELL_DATA.SuppressHardCastReset(spellID))
        ))

    if shouldResetMelee then
        if not in_combat then
            -- Preserve opener timing across PLAYER_REGEN_DISABLED so a
            -- spell-triggered combat entry cannot overwrite the reset.
            pending_hard_cast_reset_at = GetTime()
        end
        ResetPlayerMain()
        ResetPlayerOff()
    end
    -- Ranged: track auto shot / shoot resets
    if IS_RANGED_CLASS and rangedShotKind then
        ranged.casting = false
        if not playerSwingEventActive then
            -- Era fallback: reconstruct the ranged cycle from spell success.
            -- When active, PLAYER_SWING owns this reset authoritatively.
            ranged.last_shot_time = GetTime()
            local newSpd = ReadRangedSpeed() or ranged.speed
            if newSpd and newSpd > 0 then
                ranged.speed = newSpd
                if ranged.base_speed and ranged.base_speed > 0 then
                    ranged.cast_time = 0.52 * (newSpd / ranged.base_speed)
                end
            end
            ranged.timer = ranged.speed
            ranged.ready = false
        end
        WakeDriver()
    end
    -- Queued spell fired — dequeue
    if queued_spell_id and SWING_SPELL_DATA.IsNextMelee(spellID) then
        ClearQueuedSpell()
    end
end

swingEventHandlers.UNIT_SPELLCAST_SENT = function(unit, _, castGUID, spellID)
    if unit ~= "player" then return end
    -- SENT gives us the cast GUID before START/SUCCEEDED. Capture both
    -- ranged identity and kind here so an ambiguous later payload cannot
    -- turn a physical shot into a melee reset or suppress a wand reset.
    local rangedShotKind = ClassifyRangedShotSpell(spellID)
    if rangedShotKind and castGUID then
        player_ranged_cast_guid = castGUID
        player_ranged_cast_kind = rangedShotKind
        if castGUID == player_cast_guid then player_cast_guid = nil end
    end
    if SWING_SPELL_DATA.IsNextMelee(spellID) then
        -- Player queued an on-next-swing ability
        SetQueuedSpell(spellID)
    end
end

swingEventHandlers.UNIT_SPELLCAST_FAILED = function(unit, castGUID, spellID)
    if unit ~= "player" then return end
    -- A failed HARD cast doesn't reset swings. GUID-matched: button
    -- spam mid-cast fires FAILED_QUIET for the OTHER spell and must
    -- not clear the in-progress cast's tracking.
    if castGUID and castGUID == player_cast_guid then
        player_cast_guid = nil
    end
    if castGUID and castGUID == player_ranged_cast_guid then
        player_ranged_cast_guid = nil
        player_ranged_cast_kind = nil
    end
    if queued_spell_id and SWING_SPELL_DATA.IsNextMelee(spellID) then
        -- A failed/cancelled queue action can be a toggle-off. Re-read
        -- the client's authoritative pending-spell state after the
        -- action has settled instead of inferring it from this event.
        C_Timer.After(0.1, function()
            if queued_spell_id and not SWING_SPELL_DATA.AnyNextMeleeQueued() then
                ClearQueuedSpell()
            end
        end)
    end
    -- Ranged cast failed
    if IS_RANGED_CLASS and ClassifyRangedShotSpell(spellID) then
        ranged.casting = false
        WakeDriver()
    end
end

swingEventHandlers.UNIT_SPELLCAST_START = function(unit, castGUID, spellID)
    if unit ~= "player" then return end
    -- Ranged attacks own the ranged clock. Classify from both the event
    -- payload and active cast, then pin both GUID and kind so Classic's
    -- ambiguous wand payload still resets MH/OH while physical shots do not.
    local rangedShotKind = ActivePlayerRangedShotKind(spellID)
    if rangedShotKind then
        player_ranged_cast_guid = castGUID or player_ranged_cast_guid
        player_ranged_cast_kind = rangedShotKind
        if castGUID and castGUID == player_cast_guid then
            player_cast_guid = nil
        end
    else
        player_cast_guid = castGUID
    end
end

swingEventHandlers.UNIT_SPELLCAST_STOP = function(unit, castGUID)
    -- Cast ended without completing (cancel/interrupt/pushback-kill): no
    -- swing reset. GUID-matched so the STOP that follows a SUCCEEDED (by
    -- then already cleared) and unrelated casts are ignored safely.
    if unit == "player" and castGUID then
        if castGUID == player_cast_guid then player_cast_guid = nil end
        if castGUID == player_ranged_cast_guid then
            player_ranged_cast_guid = nil
            player_ranged_cast_kind = nil
        end
    end
end

swingEventHandlers.PLAYER_ENTERING_WORLD = function()
    PLAYER_GUID = UnitGUID("player") or PLAYER_GUID
    playerSwingFinishingOutOfCombat = false
    last_attack_active_at = 0
    target_change_attack_grace_until = 0
    pending_player_main_reset_at = nil
    pending_player_off_reset_at = nil
    player_cast_guid = nil
    player_ranged_cast_guid = nil
    player_ranged_cast_kind = nil
    UpdatePlayerSpeeds()
    SnapshotEquippedWeaponIDs()
    if IS_RANGED_CLASS then
        wipe(_rangedSpeedCache)
        ranged.base_speed = GetRangedBaseSpeed()
        local hasted_spd = ReadRangedSpeed()
        ranged.speed = hasted_spd or ranged.base_speed
        ranged.timer = ranged.speed
        if ranged.base_speed > 0 then
            ranged.cast_time = 0.52 * (ranged.speed / ranged.base_speed)
        end
    end
    if ST.ReanchorPlayer then ST:ReanchorPlayer() end
    if enemyFrame then
        PositionCompactTargetFrame(enemyFrame)
        LayoutCompactTargetAttack(enemyFrame)
    end
    if DriverNeeded() then WakeDriver() end
end

swingEventHandlers.UPDATE_SHAPESHIFT_FORMS = swingEventHandlers.UPDATE_SHAPESHIFT_FORM
swingEventHandlers.CURRENT_SPELL_CAST_CHANGED = RefreshQueuedSpell
swingEventHandlers.ACTIONBAR_UPDATE_STATE = WakeDriver
swingEventHandlers.UNIT_DAMAGE = function(unit)
    if unit == "player" then InvalidateDamageText() end
end
swingEventHandlers.UNIT_RANGEDDAMAGE = function(unit)
    if unit == "player" then cachedRangedText = nil end
end
swingEventHandlers.UNIT_SPELLCAST_FAILED_QUIET = swingEventHandlers.UNIT_SPELLCAST_FAILED
swingEventHandlers.UNIT_SPELLCAST_INTERRUPTED = swingEventHandlers.UNIT_SPELLCAST_STOP
swingEventHandlers.START_AUTOREPEAT_SPELL = function()
    ranged.shooting = true
    WakeDriver()
end
swingEventHandlers.STOP_AUTOREPEAT_SPELL = function()
    ranged.shooting = false
    WakeDriver()
end
swingEventHandlers.PLAYER_LOGIN = swingEventHandlers.PLAYER_ENTERING_WORLD
swingEventHandlers.ADDON_LOADED = function()
    ns.SwingTimerProviderRefreshCharacterDamageCapture(ST, eventFrame)
end

local function SwingTimerOnEvent(_, event, ...)
    local handler = swingEventHandlers[event]
    if handler then
        return handler(...)
    end
end
-- Kill-traced: PLAYER_REGEN_ENABLED tears down combat swing state and re-lays
-- out the compact rows, which is post-kill work.
eventFrame:SetScript("OnEvent", function(self, event, ...)
    ns.KillTrace("Combat/SwingTimers:", event, SwingTimerOnEvent, self, event, ...)
end)

-- =============================================================================
-- PUBLIC
-- =============================================================================

-- Compact player and target timer rows are fixed to the unit-frame artwork.
local function ApplySwingGeometry()
    RefreshTimerPresentationMode()
    local tex = GetAttackTexture()

    if playerFrame then
        playerFrame._layoutTexture = nil
        PositionCompactMeleeFrame(playerFrame)
        playerFrame.main_bar:SetTexture(tex)
        playerFrame.off_bar:SetTexture(tex)
        LayoutCompactMelee(playerFrame, player.has_offhand)
    end

    if enemyFrame then
        enemyFrame._layoutTexture = nil
        PositionCompactTargetFrame(enemyFrame)
        enemyFrame.main_bar:SetTexture(tex)
        LayoutCompactTargetAttack(enemyFrame)
    end

    if rangedFrame then
        rangedFrame:SetSize(COMPACT_BAR_W, COMPACT_BAR_H)
        rangedFrame._fillWidth = COMPACT_FILL_W
        if rangedFrame.bg then rangedFrame.bg:SetSize(COMPACT_RANGED_BG_W, COMPACT_FILL_H) end
        rangedFrame.main_bar:SetHeight(COMPACT_FILL_H)
        rangedFrame.main_bar:SetTexture(tex)
        if rangedFrame.compactBorder then rangedFrame.compactBorder:SetTexture(COMPACT_BAR_ART) end
    end

    SizeStandaloneSwingFrame(standaloneMainFrame, "player")
    SizeStandaloneSwingFrame(standaloneOffFrame, "player")
    SizeStandaloneSwingFrame(standaloneRangedFrame, "player")
    SizeStandaloneSwingFrame(standaloneTargetFrame, "target")
    AnchorStandalonePlayerRows()
    if standaloneMainFrame and standaloneMainFrame.main_bar then standaloneMainFrame.main_bar:SetTexture(tex) end
    if standaloneOffFrame and standaloneOffFrame.main_bar then standaloneOffFrame.main_bar:SetTexture(tex) end
    if standaloneRangedFrame and standaloneRangedFrame.main_bar then standaloneRangedFrame.main_bar:SetTexture(tex) end
    if standaloneTargetFrame and standaloneTargetFrame.main_bar then standaloneTargetFrame.main_bar:SetTexture(tex) end
end

local function RaiseCompactTimerAboveAnchor(timerFrame, anchor)
    if not timerFrame or not anchor then return end

    if anchor.GetFrameStrata and timerFrame.SetFrameStrata then
        timerFrame:SetFrameStrata(anchor:GetFrameStrata() or "MEDIUM")
    end
    if anchor.GetFrameLevel and timerFrame.SetFrameLevel then
        -- Match the castbar treatment: raise the entire compact row above the
        -- row it overlaps so background, fill, border, and text all render in
        -- front. The anchor may be either the melee row or the visible castbar.
        timerFrame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 5)
    end
end

-- =============================================================================
-- COMPACT ROW SLOTS (melee / cast / ranged)
--
-- There is no dedicated row per timer. Rows are ordered by WHEN THEY APPEARED
-- and always occupy contiguous positions from the top:
--   * a new row is appended, so it never displaces one already on screen;
--   * a row that hides is removed and everything below it moves UP one.
-- Relative order is preserved; gaps are not. A single visible bar is always in
-- the top position, never floating in the second or third with a hole above it.
--
-- So: open with a cast and the cast bar sits top. Cast ends, melee starts, and
-- melee takes top. Start healing mid-swing and the cast bar drops into the
-- second position under melee. Chain-cast with autoattack running and, when the
-- cast finally ends, the melee row rises into the vacated top position.
--
-- Ownership is tracked by OnShow/OnHide hooks rather than at each Show()/Hide()
-- call site: the three frames are shown and hidden from a dozen places across
-- two files, and a hook cannot be bypassed by a path we forgot to update.
-- =============================================================================
-- Two independent stacks, player and target, with identical rules. Each row is
-- an interchangeable CELL: its art, background, fill, and text are all fixed
-- relative to its own frame, and the ordering logic controls exactly one thing
-- -- which grid position the cell occupies. No per-row offsets, ever; that is
-- what made spacing depend on row order the first time around.
local rowStackOf = {}   -- [frame] = stack table
local compactStacks = {
    player = { order = {}, key = "player" },
    target = { order = {}, key = "target" },
}

-- The baked player timer cells share screen space with the DPS/HPS badge.
-- The badge owns a UIParent-level MEDIUM/100 surface (Combat/DPSBadge.lua), while
-- baked rows remain on the UnitFrame-art strata. This keeps the badge above the
-- baked rows without allowing it to escape above Blizzard's HIGH/DIALOG menus.
--
-- Reassert the row's art strata whenever it is placed.  If a future Blizzard
-- layout happens to put that art on the same MEDIUM strata as the badge, retain a
-- level ceiling as a fallback.  The MH/OH text-lift child follows the row's
-- strata and internal +3 level so its text cannot escape above the badge.
-- Standalone legacy rows and all target rows are intentionally excluded.
local function KeepPlayerCompactRowBehindDPSBadge(timerFrame)
    if not timerFrame or not UseEmbeddedTimerStack("player") then return end
    local stack = rowStackOf[timerFrame]
    if not stack or stack.key ~= "player" then return end

    local badgeOwner = ns.DPSBadge
    local badge = badgeOwner and badgeOwner.GetFrame and badgeOwner:GetFrame()
    if not badge then return end

    local art = TimerStackPlacement("player")
    local rowStrata = art and art.GetFrameStrata and art:GetFrameStrata()
        or (timerFrame.GetFrameStrata and timerFrame:GetFrameStrata())
        or "MEDIUM"
    if timerFrame.SetFrameStrata then timerFrame:SetFrameStrata(rowStrata) end

    local rowLevel = timerFrame.GetFrameLevel and timerFrame:GetFrameLevel() or 1
    local badgeStrata = badge.GetFrameStrata and badge:GetFrameStrata() or nil
    local badgeLevel = badge.GetFrameLevel and badge:GetFrameLevel() or nil
    if badgeStrata == rowStrata and badgeLevel and rowLevel >= badgeLevel and timerFrame.SetFrameLevel then
        rowLevel = math.max(badgeLevel - 1, 0)
        timerFrame:SetFrameLevel(rowLevel)
    end

    local lift = timerFrame._textLift
    if lift then
        if lift.SetFrameStrata then lift:SetFrameStrata(rowStrata) end
        if lift.SetFrameLevel then
            local wanted = rowLevel + 3
            if badgeStrata == rowStrata and badgeLevel then wanted = math.min(wanted, math.max(badgeLevel - 1, 0)) end
            lift:SetFrameLevel(wanted)
        end
    end
end

local function StackGeometry(stack)
    return TimerStackPlacement(stack.key)
end

local function RowIndex(stack, f)
    for i = 1, #stack.order do
        if stack.order[i] == f then return i end
    end
    return nil
end

local function PlaceCompactRow(f)
    if not f then return end
    local stack = rowStackOf[f]
    if not stack then return end
    local slot = RowIndex(stack, f)
    local art, x, y, w, h = StackGeometry(stack)
    if not slot or not art then return end
    local stride = h - COMPACT_ROW_ART_OVERLAP
    -- Compact rows are UIParent-owned so their lifecycle does not depend on a
    -- protected Blizzard frame. Match the chosen baked anchor's effective scale
    -- explicitly so scaled TurboFace Player/Target frames preserve the current
    -- compact presentation exactly.
    if f.SetScale and art.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
        local parentScale = UIParent:GetEffectiveScale() or 1
        local artScale = art:GetEffectiveScale() or parentScale
        if parentScale > 0 then
            local wanted = artScale / parentScale
            if not f.GetScale or math.abs((f:GetScale() or 1) - wanted) > 0.0001 then f:SetScale(wanted) end
        end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", art, "TOPLEFT", x, -(y + (slot - 1) * stride))
    if f == playerFrame or f == enemyFrame then
        f:SetSize(w, h)
        f._fillWidth = math.max(w - COMPACT_MELEE_INSET_LEFT - COMPACT_MELEE_INSET_RIGHT, 1)
        f._compactHeight = h
    end
    RaiseCompactTimerAboveAnchor(f, art)
    KeepPlayerCompactRowBehindDPSBadge(f)
end

local function PlaceAllCompactRows(stack)
    if stack then
        for i = 1, #stack.order do PlaceCompactRow(stack.order[i]) end
    else
        for _, st in pairs(compactStacks) do
            for i = 1, #st.order do PlaceCompactRow(st.order[i]) end
        end
    end
end

local function ClaimCompactSlot(f)
    local stack = rowStackOf[f]
    if not stack or RowIndex(stack, f) then return end
    if #stack.order >= COMPACT_ROW_SLOTS then return end
    -- Appended: the first row to appear sits topmost, and a row appearing later
    -- never displaces one already on screen.
    stack.order[#stack.order + 1] = f
end

-- Removing a row COMPACTS its stack: everything below moves up one, preserving
-- relative order. Leaving a hole would strand a lone bar below empty space.
local function ReleaseCompactSlot(f)
    local stack = rowStackOf[f]
    if not stack then return end
    local i = RowIndex(stack, f)
    if not i then return end
    table.remove(stack.order, i)
    PlaceAllCompactRows(stack)
end

local function EnsureRowHooked(f, stackKey)
    if not f or f._tfRowHooked then return end
    f._tfRowHooked = true
    rowStackOf[f] = compactStacks[stackKey or "player"]
    f:HookScript("OnShow", function(self)
        ClaimCompactSlot(self)
        PlaceAllCompactRows(rowStackOf[self])
    end)
    f:HookScript("OnHide", function(self)
        ReleaseCompactSlot(self)
    end)
    if f:IsShown() then
        ClaimCompactSlot(f)
        PlaceCompactRow(f)
    end
end

local function AnchorCompactPlayerStack()
    EnsureRowHooked(playerFrame, "player")
    EnsureRowHooked(rangedFrame, "player")
    EnsureRowHooked(_G.TurboFacePlayerCastbar, "player")
    EnsureRowHooked(enemyFrame, "target")
    EnsureRowHooked(_G.TurboFaceTargetCastbar, "target")

    -- Reposition every visible row (art/geometry may have moved, e.g. a druid
    -- shifting into cat or bear).
    PlaceAllCompactRows()
end

-- Exposed for Combat/Castbars.lua, which owns the cast frame lifecycle.
function ST:RegisterCompactRow(f, stackKey) EnsureRowHooked(f, stackKey) end
function ST:PlaceCompactRow(f) PlaceCompactRow(f) end
function ST:UsesEmbeddedStack(stackKey) return UseEmbeddedTimerStack(stackKey or "player") end
function ST:GetTimerStackAnchor(stackKey)
    local art = TimerStackPlacement(stackKey or "player")
    return art
end

function ST:RegisterTimerMovers(movers)
    if not movers or not movers.RegisterElement then return end
    local swingAvailable = function(stackKey)
        if UseEmbeddedTimerStack(stackKey) then return false end
        if not ns.ModuleEnabled then return true end
        return ns.ModuleEnabled("swingTimers")
    end

    local function register(id, frame, label, stackKey, availableExtra)
        if not frame then return end
        movers:RegisterElement(id, frame, {
            label = label,
            overlayWidth = frame:GetWidth(), overlayHeight = frame:GetHeight(),
            defaultPoint = { frame:GetPoint(1) },
            isAvailable = function()
                if availableExtra and not availableExtra() then return false end
                return swingAvailable(stackKey)
            end,
        })
    end

    register("PlayerMainSwingTimer", standaloneMainFrame, "Player Main-Hand Swing", "player")
    register("PlayerOffhandSwingTimer", standaloneOffFrame, "Player Off-Hand Swing", "player")
    register("PlayerRangedSwingTimer", standaloneRangedFrame, "Player Ranged Swing", "player", function() return IS_RANGED_CLASS end)
    register("TargetSwingTimer", standaloneTargetFrame, "Target Swing Timer", "target")
end

function ST:Init()
    -- Nameplate enemy swing timing is an independent demand path. It owns only
    -- a two-event combat boundary frame plus a SWING-only shared-CLEU consumer.
    SwingTimers:RefreshNameplateRuntime()

    -- Global Swing Timers still owns the player/target rows and their broader
    -- event engine. Disabling those rows does not disable the nameplate feature.
    if SwingGateOff() then return end
    ActivateRuntime()
    RefreshTimerPresentationMode()
    playerFrame = CreateCompactMeleeFrame()

    enemyFrame = CreateCompactTargetAttackFrame()

    rangedFrame = CreateCompactTimerFrame(
        "TurboFaceRangedSwingFrame",
        {0.95, 0.95, 0.95}
    )
    rangedFrame:Hide()

    standaloneMainFrame = CreateStandaloneSwingFrame(
        "TurboFaceStandalonePlayerMainSwingFrame", BAR_COLOR_PLAYER_MAIN, true)

    standaloneOffFrame = CreateStandaloneSwingFrame(
        "TurboFaceStandalonePlayerOffSwingFrame", BAR_COLOR_PLAYER_OFF, true)

    standaloneRangedFrame = CreateStandaloneSwingFrame(
        "TurboFaceStandaloneRangedSwingFrame", {0.95, 0.95, 0.95}, true)

    -- Default standalone rows stack immediately below the Class-owned Druid
    -- Power Bar while it is visible; otherwise they begin under Blizzard's
    -- normal player power bar. Explicit mover positions always win.
    AnchorStandalonePlayerRows()

    standaloneTargetFrame = CreateStandaloneSwingFrame(
        "TurboFaceStandaloneTargetSwingFrame", BAR_COLOR_ENEMY_MAIN, false)
    standaloneTargetFrame:SetPoint("TOP", TargetFrameManaBar or TargetFrame or UIParent, "BOTTOM", 0, -STANDALONE_GAP)
    standaloneTargetFrame.main_label:SetText("")

    SizeStandaloneSwingFrame(standaloneMainFrame, "player")
    SizeStandaloneSwingFrame(standaloneOffFrame, "player")
    SizeStandaloneSwingFrame(standaloneRangedFrame, "player")
    SizeStandaloneSwingFrame(standaloneTargetFrame, "target")

    if IS_RANGED_CLASS then
        ranged.base_speed = GetRangedBaseSpeed()
        local hasted_spd = ReadRangedSpeed()
        ranged.speed = hasted_spd or ranged.base_speed
        ranged.timer = ranged.speed
        if ranged.base_speed > 0 then
            ranged.cast_time = 0.52 * (ranged.speed / ranged.base_speed)
        end
    end

    UpdatePlayerSpeeds()
    SnapshotEquippedWeaponIDs()
    -- Start with every row hidden and no slot held; each claims one on show.
    -- Keep both compact swing surfaces explicitly hidden even if their creator
    -- implementation changes later. Initial visibility must be earned by the
    -- runtime state machine, never by construction order.
    playerFrame:Hide()
    enemyFrame.main_bar:Hide()
    enemyFrame.main_text:Hide()
    enemyFrame:Hide()
    standaloneTargetFrame:Hide()
    target.guid = nil
    target.main_timer = 0
    target.off_timer = 0
    AnchorCompactPlayerStack()
    StopDriver()
end

function ST:Refresh()
    -- Profile/import/global refreshes can change the independent nameplate gate
    -- without visiting the Nameplates tab, so always reconcile that lightweight
    -- runtime before handling the Global Swing Timers presentation gate.
    SwingTimers:RefreshNameplateRuntime()
    if SwingGateOff() then
        HideAllSwingRows()
        DeactivateRuntime()
        return
    end
    -- Deliberately NOT re-activating here. Init() both activates the runtime and
    -- builds playerFrame/enemyFrame/rangedFrame; bringing events back up without
    -- those frames would leave handlers firing against a half-built module.
    -- Module masters are reload-oriented (ARCHITECTURE 4.5), so turning Swing
    -- Timers back on goes through the reload prompt and a fresh Init().
    ApplySwingGeometry()
    AnchorCompactPlayerStack()
    self:RefreshFonts()
    if in_combat or playerSwingFinishingOutOfCombat or ranged.shooting then WakeDriver() end
end

function ST:ReanchorPlayer()
    AnchorCompactPlayerStack()
    AnchorStandalonePlayerRows()
end

function ST:ReanchorTarget()
    PositionCompactTargetFrame(enemyFrame)
    LayoutCompactTargetAttack(enemyFrame)
end

function ST:RefreshFonts()
    local function styleFrame(f)
        if not f then return end
        local size = (f._compactMelee or f._compactTarget or f._compactTimer) and 8 or 9
        if f.main_text  then ns:StyleFeatureFont(f.main_text, size, "swingTimersFont", "swingTimersTextStyle") end
        if f.off_text   then ns:StyleFeatureFont(f.off_text, size, "swingTimersFont", "swingTimersTextStyle") end
        if f.main_label then ns:StyleFeatureFont(f.main_label, 9, "swingTimersFont", "swingTimersTextStyle") end
        if f.off_label  then ns:StyleFeatureFont(f.off_label, 9, "swingTimersFont", "swingTimersTextStyle") end
    end
    styleFrame(playerFrame)
    styleFrame(enemyFrame)
    styleFrame(rangedFrame)
    styleFrame(standaloneMainFrame)
    styleFrame(standaloneOffFrame)
    styleFrame(standaloneRangedFrame)
    styleFrame(standaloneTargetFrame)
end

ns.ST = ST

-- Diagnostic: run WHILE the phantom off-hand bar is visible (i.e. in combat).
-- Dumps every swing frame so we can see exactly which one is drawing it.
SLASH_TFSWING1 = "/tfswing"
SlashCmdList["TFSWING"] = function(msg)
    msg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""
    ns.SwingTimerProviderRunCharacterDamageProbe(ST, msg)
    local id  = GetInventoryItemID("player", 17)
    local loc = id and GetItemInfoInstant and select(4, GetItemInfoInstant(id)) or nil
    print("|cff00ccffTFSwing|r combat=", tostring(in_combat),
          "| P.has_off=", tostring(player.has_offhand),
          "| OHid=", tostring(id), "| loc=", tostring(loc),
          "| queued=", tostring(queued_spell_id),
          "| PLAYER_SWING=", tostring(playerSwingEventActive),
          "| lastType=", tostring(lastPlayerSwingType),
          "| lastDur=", tostring(lastPlayerSwingDuration),
          "| lastAt=", tostring(lastPlayerSwingAt),
          "| paperdollDamage=", tostring(ST.paperDollDamageText),
          "| damageSource=", tostring(ST.damageTextSource),
          "| paperdollHook=", tostring(ST._paperDollDamageHooked == true),
          "| labelHook=", tostring(ST._paperDollLabelHooked == true),
          "| labelCalls=", tostring(ST.paperDollDamageLabelCalls or 0),
          "| damageCalls=", tostring(ST.paperDollDamageSetDamageCalls or 0),
          "| captureSource=", tostring(ST.paperDollDamageCaptureSource),
          "| reject=", tostring(ST.paperDollDamageReject),
          "| postRead=", tostring(ST.paperDollPostRead),
          "| textSecret=", tostring(ST.paperDollDamageTextSecret == true),
          "| paneHook=", tostring(ST._characterStatsPaneHooked == true),
          "| paneScans=", tostring(ST.paperDollPaneScans or 0),
          "| paneStatus=", tostring(ST.paperDollPaneStatus),
          "| paneNodes=", tostring(ST.paperDollPaneCandidateCount or 0),
          "| panePool=", tostring(ST.paperDollPanePool == true),
          "| paneRow=", tostring(ST.paperDollPaneDamageRow),
          "| frameScans=", tostring(ST.paperDollFrameScans or 0),
          "| frameStatus=", tostring(ST.paperDollFrameStatus),
          "| frameNodes=", tostring(ST.paperDollFrameNodeCount or 0),
          "| frameTexts=", tostring(ST.paperDollFrameTextCount or 0),
          "| frameLabel=", tostring(ST.paperDollFrameDamageLabel),
          "| frameRange=", tostring(ST.paperDollFrameRange))
    if playerFrame then
        print("  player: shown=", tostring(playerFrame:IsShown()),
              "off_track=", tostring(playerFrame.off_bar and playerFrame.off_bar:IsShown()),
              "H=", string.format("%.0f", playerFrame:GetHeight() or 0))
    end
    if enemyFrame then
        print("  enemy: T.has_off=", tostring(target.has_offhand),
              "shown=", tostring(enemyFrame:IsShown()),
              "off_bar=", tostring(enemyFrame.off_bar and enemyFrame.off_bar:IsShown()))
    end
    if rangedFrame then
        print("  ranged: shown=", tostring(rangedFrame:IsShown()))
    end
end

ns.RegisterCPUProfileTarget("Combat/SwingTimers:CLEU", OnCombatLog)
ns.RegisterCPUProfileTarget("Combat/SwingTimers:Tick", OnUpdate)
ns.RegisterCPUProfileTarget("Combat/SwingTimers:Events", eventFrame and eventFrame:GetScript("OnEvent"))