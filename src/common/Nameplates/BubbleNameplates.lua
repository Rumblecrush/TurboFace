local _, ns = ...

-- TurboFace additive nameplate augmentation on Blizzard's native 1.15.9
-- name/health/cast/classification/stacking chassis. The historical filename
-- remains for compatibility; no Bubble-era baseline renderer survives here.

local BNP = {}
ns.BubbleNameplates = BNP

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitExists = ns.API.ReadUnitExists
local UnitGUID = ns.API.ReadUnitGUID
local UnitIsUnit = ns.API.ReadUnitIsUnit
local UnitIsPlayer = ns.API.ReadUnitIsPlayer
local UnitIsFriend = ns.API.ReadUnitIsFriend
local UnitPlayerControlled = ns.API.ReadUnitPlayerControlled
local UnitCanAttack = ns.API.ReadUnitCanAttack
local UnitHealth = ns.API.ReadUnitHealth
local UnitHealthMax = ns.API.ReadUnitHealthMax
local UnitPower = ns.API.ReadUnitPower
local UnitPowerMax = ns.API.ReadUnitPowerMax
local UnitPowerType = UnitPowerType
local UnitGetIncomingHeals = ns.API.ReadUnitIncomingHeals
local UnitDetailedThreatSituation = ns.API.ReadUnitDetailedThreatSituation
local UnitThreatSituation = ns.API.ReadUnitThreatSituation
local UnitIsDead = ns.API.ReadUnitIsDead
local UnitAffectingCombat = UnitAffectingCombat
local UnitName = ns.API.ReadUnitName
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local PlaySoundFile = PlaySoundFile
local floor = math.floor
local max = math.max
local min = math.min
local sin = math.sin
local pi = math.pi
local lower = string.lower
local find = string.find
local C_Timer_After = C_Timer.After

local ROOT = "Interface\\AddOns\\TurboFace\\Textures\\BubbleNameplates\\"
local SOUND_ROOT = "Interface\\AddOns\\TurboFace\\Sounds\\BubbleNameplates\\"

-- TurboFace-owned additive textures.
local TEX_ATTACK_READY = ROOT .. "Nameplate-AttackIndicator.tga"
local TEX_WHITE = "Interface\\Buttons\\WHITE8X8"

local SOUND_GAIN = SOUND_ROOT .. "GainAggro.mp3"
local SOUND_LOSS = SOUND_ROOT .. "LoseAggro.mp3"

local STATUS_TEXTURE_INSET = 2 / 256
local THREAT_TEXT_WIDTH = 32
local THREAT_TEXT_HEIGHT = 18
local THREAT_TEXT_GAP = 5
local JOB_ICON_GAP = 4
local RESOURCE_EMBED_MIN_HEIGHT = 2
local HEALTH_EFFECT_DURATION = 0.95
local MANA_EFFECT_DURATION = 0.45
local SWING_UPDATE_RATE = 1 / 30
-- Enemy nameplate swing presentation follows the live health-bar geometry.
-- Two mirrored additive strips grow from the outside edges toward center, then
-- hand off to the existing ready glyph for the final 5% / ready state. Fixed
-- presentation dimensions stay inline below to avoid spending scarce Lua 5.1
-- chunk locals on implementation-only constants.

-- NPC service classification has two layers:
--   1. Broad legacy fallback words may match either the NPC name or title.
--   2. Manually indexed entries preserve the field the user observed. Titles
--      are exact title matches; only entries explicitly marked as NPC names are
--      exact name matches. This prevents generic words such as "master" or
--      "cook" from stealing unrelated services.
local REPAIR_WORDS = {
    "repair", "armorer", "armourer", "armor merchant", "weapon merchant",
    "weaponsmith", "bowyer", "ammo merchant", "ammunition merchant",
    "gun vendor", "guns vendor",
}
local REPAIR_TITLE_MATCHES = {
    "weapons merchant", "bow & arrow merchant", "bow and arrow merchant",
    "bow & gun merchant", "bow and gun merchant", "blade merchant",
    "shield merchant", "guns vendor", "axe merchant", "robe vendor",
    "staff & mace merchant", "staff and mace merchant", "wand merchant",
    "staves merchant", "blacksmithing supplier", "clothier",
    "gun and ammo merchant", "guns and ammo merchant",
    "gun and ammunition merchant", "guns and ammunition merchant",
    "war harness maker", "bow merchant",
    "weapon vendor", "two-handed weapons merchant",
    "mace & staves vendor", "mace and staves vendor", "staff merchant",
    "gunsmith", "blacksmithing supplies", "guns merchant",
    "sword and dagger merchant", "mace & staff merchant",
    "mace and staff merchant", "war harness vendor",
    "thrown weapons merchant", "wand vendor", "gun merchant",
    "macecrafter", "cloth armor and accessories",
}
local REPAIR_NAME_EXCLUDES = {
    "borgosh corebender",
}
local VENDOR_WORDS = {
    "vendor", "merchant", "shopkeeper", "provisioner", "goods", "supplies",
    "supplier", "reagent", "tradesman",
}
local VENDOR_TITLE_MATCHES = {
    "bags & sacks", "bags and sacks", "baker", "butcher", "trade supplier",
    "apprentice of cheese", "mistress of cheese", "florist",
    "herbalism supplier", "accessories quartermaster", "shady dealer",
    "poison supplier", "cooking supplier", "master of cooking recipes",
    "cobbler", "engineering supplier", "fishing supplier",
    "merlot connoisseur", "basket weaver", "book dealer",
    "lost and found", "food and drink", "superior fisherman",
}
local VENDOR_NAME_MATCHES = {
    "multon sheaf", "adair gilroy", "jarel moor", "joachim brenlow",
    "zor lonetree", "alessandro luca", "joanna whitehall",
    "montarr", "kilxx", "zizzek", "kelsey yance", "old man heming",
}
local VENDOR_TITLE_EXCLUDES = {
    "blacksmithing supplies",
}
local TRAINER_WORDS = {
    "trainer", "apprentice", "journeyman", "expert", "artisan", "master",
}
local TRAINER_TITLE_MATCHES = {
    "physician", "skinner", "cook", "miner", "fisherman",
    "superior herbalist",
}
local TRAINER_TITLE_EXCLUDES = {
    "apprentice of cheese", "master of cheese", "accessories quartermaster",
    "master of cooking recipes", "alliance cloth quartermaster",
    "horde cloth quartermaster", "shipmaster",
}
local TRAINER_NAME_EXCLUDES = {
    "master wood", "connor rivers", "master apothecary faranell",
    "elu", "wharfmaster dizzywig", "wharfmaster lozgil", "fleet master seahorn",
}
local GUARD_WORDS = {
    "guard", "grunt", "sentinel", "guardian", "brave", "mountaineer",
}
local GUARD_NAME_MATCHES = {
    "stormwind city patroller", "bluffwatcher",
}
local GUARD_TITLE_EXCLUDES = {
    "stormwind city guard",
}
local GUARD_NAME_EXCLUDES = {
    "stormwind royal guard", "horde guard", "honor guard",
    "royal dreadguard", "freewind brave",
}
local FLIGHT_MASTER_WORDS = {
    "flight master", "wind rider master", "gryphon master",
    "hippogryph master", "bat handler", "dragonhawk master",
}
local STABLE_MASTER_WORDS = {
    "stable master", "stablemaster",
}
local BATTLEMASTER_TITLE_WORDS = { "battlemaster" }
local BANKER_WORDS = { "banker" }
local GUILD_MASTER_WORDS = { "guild master", "guildmaster" }
local INNKEEPER_WORDS = { "innkeeper" }

local jobIconCache = {}
local aggroState = {}
local activeSwingFrames = {}
local activeSwingCount = 0
local swingRemovalBuffer = {}
local SwingTick
local activeSpendBars = {}
local activeSpendCount = 0
local SpendDriverTick

local function Enabled()
    if ns.ModuleEnabled and not ns.ModuleEnabled("nameplates") then return false end
    return ns.c_nameplatesEnabled == true
end

local function ContainsAny(text, words)
    if not text or text == "" then return false end
    text = lower(text)
    for i = 1, #words do
        if find(text, words[i], 1, true) then return true end
    end
    return false
end

local function ExactAny(text, words)
    if not text or text == "" then return false end
    text = lower(text):gsub("^%s+", ""):gsub("%s+$", "")
    for i = 1, #words do
        if text == words[i] then return true end
    end
    return false
end

local function ApplyBubbleStatusTexture(bar)
    if not bar then return end
    local path = "Interface\\TargetingFrame\\UI-StatusBar"
    if bar._bubbleStatusTexturePath ~= path then
        bar:SetStatusBarTexture(path)
        bar._bubbleStatusTexturePath = path
        -- SetStatusBarTexture may replace the backing Texture object. Force the
        -- one-time texture-property setup below to follow that replacement.
        bar._bubbleStatusTextureObject = nil
    end
    local texture = bar:GetStatusBarTexture()
    if texture and bar._bubbleStatusTextureObject ~= texture then
        bar._bubbleStatusTextureObject = texture
        texture:SetHorizTile(false)
        texture:SetVertTile(false)
        -- Trim the source texture's outermost texel so the colored portion,
        -- rather than its dark edge, reaches the right side at maximum value.
        texture:SetTexCoord(STATUS_TEXTURE_INSET, 1 - STATUS_TEXTURE_INSET, 0, 1)
    end
end

local function NPCID(unit)
    if ns.GetNPCIDForUnit then return ns.GetNPCIDForUnit(unit) end
    local guid = unit and UnitGUID(unit)
    if not guid then return nil end
    local id = select(6, strsplit("-", guid))
    return id and tonumber(id) or nil
end

local function GetSubtitle(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return nil end
    local id = NPCID(unit)
    if not id then return nil end
    local title = ns.c_npcTitleCache and ns.c_npcTitleCache[id]
    if title and title ~= "" then return "<" .. title .. ">", title end
    if ns.QueueNPCTitleScan then ns.QueueNPCTitleScan(id, unit) end
    return nil
end

local function ResolveJob(unit, title)
    if not ns.c_nameplateJobIcon or not unit or not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return nil end
    local guid = UnitGUID(unit)
    local cache = guid and jobIconCache[guid]
    if cache and cache.title == title then return cache.kind end

    local name = UnitName(unit) or ""
    local npcTitle = title or ""
    local combined = npcTitle .. " " .. name
    local kind

    local guardExcluded = ExactAny(npcTitle, GUARD_TITLE_EXCLUDES)
        or ExactAny(name, GUARD_NAME_EXCLUDES)
    local trainerExcluded = ExactAny(npcTitle, TRAINER_TITLE_EXCLUDES)
        or ExactAny(name, TRAINER_NAME_EXCLUDES)
    local vendorExcluded = ExactAny(npcTitle, VENDOR_TITLE_EXCLUDES)
    local repairExcluded = ExactAny(name, REPAIR_NAME_EXCLUDES)

    -- Keep manually indexed rules separate from broad keyword fallbacks. An
    -- exact indexed service must always beat a generic word such as
    -- "merchant", "vendor", or "master" from another category.
    local indexedGuard = ExactAny(name, GUARD_NAME_MATCHES)
    local indexedTrainer = ExactAny(npcTitle, TRAINER_TITLE_MATCHES)
    local indexedRepair = ExactAny(npcTitle, REPAIR_TITLE_MATCHES)
    local indexedVendor = ExactAny(npcTitle, VENDOR_TITLE_MATCHES)
        or ExactAny(name, VENDOR_NAME_MATCHES)

    local broadGuard = ContainsAny(combined, GUARD_WORDS)
    local broadTrainer = ContainsAny(combined, TRAINER_WORDS)
    local broadRepair = ContainsAny(combined, REPAIR_WORDS)
    local broadVendor = ContainsAny(combined, VENDOR_WORDS)

    -- Priority:
    --   1. Title-authoritative/special Blizzard services.
    --   2. Exact manually indexed includes (repair before vendor).
    --   3. Broad legacy keyword fallbacks.
    -- Category exclusions suppress only that category so another legitimate
    -- service can still be selected.
    if ContainsAny(npcTitle, BATTLEMASTER_TITLE_WORDS) then
        kind = "battlemaster"
    elseif ContainsAny(combined, BANKER_WORDS) then
        kind = "banker"
    elseif ContainsAny(combined, GUILD_MASTER_WORDS) then
        kind = "guildmaster"
    elseif ContainsAny(combined, FLIGHT_MASTER_WORDS) then
        kind = "flightmaster"
    elseif ContainsAny(combined, STABLE_MASTER_WORDS) then
        kind = "stablemaster"
    elseif indexedGuard and not guardExcluded then
        kind = "guard"
    elseif indexedTrainer and not trainerExcluded then
        kind = "trainer"
    elseif indexedRepair and not repairExcluded then
        kind = "repair"
    elseif indexedVendor and not vendorExcluded then
        kind = "vendor"
    elseif broadGuard and not guardExcluded then
        kind = "guard"
    elseif broadTrainer and not trainerExcluded then
        kind = "trainer"
    elseif broadRepair and not repairExcluded then
        kind = "repair"
    elseif broadVendor and not vendorExcluded then
        kind = "vendor"
    elseif ContainsAny(combined, INNKEEPER_WORDS) then
        kind = "innkeeper"
    end
    if guid then jobIconCache[guid] = { title = title, kind = kind } end
    return kind
end

local function SetJobTexture(tex, kind)
    if not tex then return end
    if kind == "battlemaster" then
        -- Blizzard's player-combat state artwork is the crossed-swords region
        -- in UI-StateIcon rather than a standalone square icon texture.
        tex:SetSize(10, 10)
        tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        tex:SetTexCoord(0.58, 0.90, 0.08, 0.41)
        return
    end

    if kind == "banker" then
        -- Shared Blizzard Banker tracking art also marks Inventory's Bank state.
        -- Use the complete square texture and a small size exception.
        tex:SetSize(12, 12)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetTexture(ns.BANK_ICON_TEXTURE)
        return
    end

    tex:SetSize(10, 10)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if kind == "guildmaster" then
        tex:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
    elseif kind == "flightmaster" then
        tex:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    elseif kind == "stablemaster" then
        tex:SetTexture("Interface\\Minimap\\Tracking\\StableMaster")
    elseif kind == "repair" then
        tex:SetTexture("Interface\\Minimap\\Tracking\\Repair")
    elseif kind == "trainer" then
        tex:SetTexture("Interface\\GossipFrame\\TrainerGossipIcon")
    elseif kind == "vendor" then
        tex:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")
    elseif kind == "guard" then
        tex:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
    elseif kind == "innkeeper" then
        tex:SetTexture("Interface\\Minimap\\Tracking\\Innkeeper")
    else
        tex:SetTexture(nil)
    end
end

-- Forever's detached nameplate adapter reuses only the pure NPC-service
-- classification/texture helpers. It never calls the legacy frame-mutating
-- Bubble renderer. Exporting these two helpers keeps the service taxonomy in
-- one place across Era and Forever without duplicating the large match tables.
BNP.ResolveJob = ResolveJob
BNP.SetJobTexture = SetJobTexture

local function AnchorThreatNumber(frame, plate)
    local hp = plate and plate.hp
    if not frame or not hp then return end
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", hp, "LEFT", -THREAT_TEXT_GAP, 0)
    frame:SetSize(THREAT_TEXT_WIDTH, THREAT_TEXT_HEIGHT)
end

local function EnsureThreatNumber(plate)
    local size = ns.c_nameplateThreatFontSize or 6
    if plate.threatNumber then
        local f = plate.threatNumber
        AnchorThreatNumber(f, plate)
        if f._fontSize ~= size then
            -- Classic renders the native shadow reliably when it belongs to the
            -- assigned FontObject. Use the same proven 2,-2 FontObject path as
            -- TurboFace's normal Shadow style instead of a duplicate glyph.
            ns:StyleFont(f.text, ns.c_font, size, nil, "NAMEPLATE_SHADOW")
            f._fontSize = size
        end
        return f
    end
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameLevel((plate:GetFrameLevel() or 1) + 32)
    f:SetSize(THREAT_TEXT_WIDTH, THREAT_TEXT_HEIGHT)
    f:EnableMouse(false)
    f:Hide()

    -- One colored glyph with a native FontObject-owned black 2,-2 shadow.
    -- This is the same Classic-safe rendering path proven by the configurable
    -- typography system and the Blizzard-owned nameplate-name shadow setting.
    f.text = f:CreateFontString(nil, "OVERLAY")
    ns:StyleFont(f.text, ns.c_font, size, nil, "NAMEPLATE_SHADOW")
    f._fontSize = size
    f.text:SetAllPoints()
    f.text:SetJustifyH("RIGHT")
    f.text:SetJustifyV("MIDDLE")

    plate.threatNumber = f
    AnchorThreatNumber(f, plate)
    return f
end

local function MeasureNativeJobNameHalfWidth(plate, unit, nameAnchor)
    if not (plate and unit and nameAnchor) then return nil end
    local text = UnitName(unit)
    if not text or text == "" then return nil end

    -- Friendly identity-only names are centered inside a chassis-wide Blizzard
    -- FontString. Its LEFT point is therefore the chassis edge, not the visible
    -- glyph edge. Measure the text on a TurboFace-owned hidden FontString so we
    -- can place the icon from the native name CENTER without reading any
    -- restricted native geometry (GetPoint/GetLeft/GetStringWidth, etc.).
    local root = plate.parentPlate or plate
    local measure = plate._tfJobNameMeasure
    if not measure and root and root.CreateFontString then
        measure = root:CreateFontString(nil, "ARTWORK")
        measure:Hide()
        plate._tfJobNameMeasure = measure
    end
    if not measure then return nil end

    local fontOK, path, size, flags = false, nil, nil, nil
    if nameAnchor.GetFont then
        local ok, a, b, c = pcall(nameAnchor.GetFont, nameAnchor)
        if ok then
            path, size, flags = a, b, c
            if path and size then
                flags = flags or ""
                flags = flags:gsub("SLUG", "")
                flags = flags:gsub("%s*,%s*,+", ",")
                flags = flags:gsub("^%s*,%s*", ""):gsub("%s*,%s*$", "")
                flags = flags:gsub("^%s+", ""):gsub("%s+$", "")
                local setOK, result = pcall(measure.SetFont, measure, path, size, flags)
                fontOK = setOK and result ~= false
                if not fontOK then
                    setOK, result = pcall(measure.SetFont, measure, path, size)
                    fontOK = setOK and result ~= false
                end
            end
        end
    end
    if not fontOK then
        ns:StyleFont(measure, ns.c_font, ns.NP_NATIVE_NAME_FALLBACK_SIZE or 10, nil, "")
    end

    measure:SetText(text)
    local ok, width = pcall(measure.GetStringWidth, measure)
    if ok and width and width > 0 then return width * 0.5 end
    return nil
end

local function AnchorJobIndicator(frame, plate, unit)
    if not frame or not plate then return end
    -- Job Icon is an identity adjunct, not a health-bar adjunct. Native full
    -- plates therefore use Blizzard's name FontString as their identity anchor.
    -- Identity-only mode is special: TurboFace intentionally makes Blizzard's
    -- name center-justified across the whole chassis, so the FontString LEFT is
    -- not the visible text edge. Compute that edge from the text width instead.
    local nameAnchor = ns.GetNameplateNameAnchor and ns.GetNameplateNameAnchor(plate, false)
    frame:ClearAllPoints()
    if plate._tfNativeFriendlyIdentityOnly and nameAnchor then
        local halfWidth = MeasureNativeJobNameHalfWidth(plate, unit, nameAnchor)
        if halfWidth then
            frame:SetPoint("RIGHT", nameAnchor, "CENTER", -(halfWidth + JOB_ICON_GAP), 0)
            return
        end
    end

    local anchor = nameAnchor or plate.hp or plate
    frame:SetPoint("RIGHT", anchor, "LEFT", -JOB_ICON_GAP, 0)
end

local function EnsureJobIndicator(plate)
    -- Native Job Icon is a true sibling augmentation of Blizzard identity, not
    -- a child of TurboFace's full augmentation host. Parenting it to the native
    -- nameplate root lets it remain visible in Friendly NPC identity-only mode
    -- even while myPlate itself is parked/hidden.
    local desiredParent = (plate._tfUsesNativeIdentity and plate.parentPlate) or plate
    if plate.nameplateJobIcon then
        local existing = plate.nameplateJobIcon
        if desiredParent and existing:GetParent() ~= desiredParent then
            existing:SetParent(desiredParent)
            existing:SetFrameLevel((desiredParent:GetFrameLevel() or 1) + 32)
        end
        AnchorJobIndicator(existing, plate, plate.unit)
        return existing
    end
    local f = CreateFrame("Frame", nil, desiredParent or plate)
    f:SetFrameLevel(((desiredParent or plate):GetFrameLevel() or 1) + 32)
    f:SetSize(12, 12)
    f:EnableMouse(false)
    f:Hide()

    f.job = f:CreateTexture(nil, "OVERLAY", nil, 6)
    f.job:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.job:SetSize(10, 10)
    f.job:Hide()

    plate.nameplateJobIcon = f
    AnchorJobIndicator(f, plate, plate.unit)
    return f
end

function BNP:_AnchorSwingFrame(frame, plate)
    local hp = plate and plate.hp
    if not frame or not hp then return false end

    -- Blizzard's HealthBarsContainer is the native horizontal chassis. The
    -- health StatusBar itself can be narrower than the surrounding artwork.
    local unitFrame = plate.nativeUnitFrame
        or (plate.parentPlate and plate.parentPlate.UnitFrame)
    local healthBarsContainer = unitFrame and unitFrame.HealthBarsContainer
    local anchor = healthBarsContainer or hp

    if frame._anchorChassis ~= anchor then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
        frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -1)
        frame:SetHeight(4)
        frame._anchorChassis = anchor
    end
    return true
end

function BNP:_EnsureSwing(plate)
    local existing = plate and plate.nameplateSwing
    if existing then
        self:_AnchorSwingFrame(existing, plate)
        return existing
    end
    if not plate or not plate.hp then return nil end

    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameLevel((plate:GetFrameLevel() or 1) + 45)
    f:EnableMouse(false)
    f:Hide()
    self:_AnchorSwingFrame(f, plate)

    -- Tapered red additive glow. The texture's alpha ramps from faint at the
    -- outer chassis edge to strongest at the inward-moving lead; the right
    -- half flips the same texture so both sides fade away toward the plate ends.
    f.leftGlow = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.leftGlow:SetTexture(ROOT .. "Nameplate-SwingGlow.tga")
    f.leftGlow:SetBlendMode("ADD")
    f.leftGlow:SetVertexColor(1.0, 0.10, 0.06, 0.55)
    f.leftGlow:SetHeight(4)
    f.leftGlow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 1.5)
    f.leftGlow:Hide()

    f.rightGlow = f:CreateTexture(nil, "OVERLAY", nil, 1)
    f.rightGlow:SetTexture(ROOT .. "Nameplate-SwingGlow.tga")
    f.rightGlow:SetTexCoord(1, 0, 0, 1)
    f.rightGlow:SetBlendMode("ADD")
    f.rightGlow:SetVertexColor(1.0, 0.10, 0.06, 0.55)
    f.rightGlow:SetHeight(4)
    f.rightGlow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 1.5)
    f.rightGlow:Hide()

    f.leftCore = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.leftCore:SetTexture(ROOT .. "Nameplate-SwingGlow.tga")
    f.leftCore:SetBlendMode("ADD")
    f.leftCore:SetVertexColor(1.0, 0.06, 0.03, 0.80)
    f.leftCore:SetHeight(1)
    f.leftCore:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0.5)
    f.leftCore:Hide()

    f.rightCore = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.rightCore:SetTexture(ROOT .. "Nameplate-SwingGlow.tga")
    f.rightCore:SetTexCoord(1, 0, 0, 1)
    f.rightCore:SetBlendMode("ADD")
    f.rightCore:SetVertexColor(1.0, 0.06, 0.03, 0.80)
    f.rightCore:SetHeight(1)
    f.rightCore:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0.5)
    f.rightCore:Hide()

    -- Ready state: keep the tiny attack glyph crisp and opaque. The source
    -- texture already contains the intended bright orange artwork, so render
    -- it neutrally at its native 4x6 size without an additive halo.
    f.ready = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.ready:SetTexture(TEX_ATTACK_READY)
    f.ready:SetBlendMode("BLEND")
    f.ready:SetVertexColor(1.0, 1.0, 1.0)
    f.ready:SetAlpha(1.0)
    f.ready:SetSize(4, 6)
    f.ready:SetPoint("CENTER", f, "TOP", 0, -1)
    f.ready:Hide()

    plate.nameplateSwing = f
    return f
end

function BNP:_HideSwingProgress(frame)
    if not frame then return end
    frame.leftGlow:Hide()
    frame.rightGlow:Hide()
    frame.leftCore:Hide()
    frame.rightCore:Hide()
end

function BNP:_SetSwingReady(frame, shown)
    if not frame then return end
    if shown then
        frame.ready:Show()
    else
        frame.ready:Hide()
    end
end

function BNP:_ShowSwingProgress(frame, progress)
    if not frame then return false end
    local width = frame:GetWidth() or 0
    if width <= 0 then
        self:_HideSwingProgress(frame)
        return false
    end

    -- Preserve the old renderer's 5% lead-in and 95% ready handoff while
    -- remapping that visible interval to the full edge-to-center distance.
    local visualProgress = (progress - 0.05)
        / (0.95 - 0.05)
    visualProgress = max(0, min(1, visualProgress))
    local segmentWidth = max(0.01, (width * 0.5) * visualProgress)

    frame.leftGlow:SetWidth(segmentWidth)
    frame.rightGlow:SetWidth(segmentWidth)
    frame.leftCore:SetWidth(segmentWidth)
    frame.rightCore:SetWidth(segmentWidth)
    frame.leftGlow:Show()
    frame.rightGlow:Show()
    frame.leftCore:Show()
    frame.rightCore:Show()
    return true
end


local function EnsureResource(plate)
    if plate.bubbleResource then return plate.bubbleResource end
    local bar = CreateFrame("StatusBar", nil, plate)
    ApplyBubbleStatusTexture(bar)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:EnableMouse(false)
    bar:Hide()

    plate.bubbleResource = bar
    return bar
end

local function EnsureHealthEffects(plate)
    local hp = plate and plate.hp
    if not hp or hp._tfBubbleSpend then return end

    hp._tfBubbleSpend = hp:CreateTexture(nil, "OVERLAY", nil, 4)
    hp._tfBubbleSpend:SetTexture(TEX_WHITE)
    hp._tfBubbleSpend:SetVertexColor(1.0, 0.38, 0.38, 0.78)
    hp._tfBubbleSpend:Hide()

    hp._tfBubbleArc = hp:CreateTexture(nil, "OVERLAY", nil, 5)
    hp._tfBubbleArc:SetTexture(TEX_WHITE)
    hp._tfBubbleArc:SetSize(3, 3)
    hp._tfBubbleArc:SetVertexColor(1.0, 0.46, 0.46, 0.95)
    hp._tfBubbleArc:Hide()

    hp._tfBubbleIncoming = hp:CreateTexture(nil, "ARTWORK", nil, 4)
    hp._tfBubbleIncoming:SetTexture(TEX_WHITE)
    hp._tfBubbleIncoming:SetVertexColor(0.58, 1.0, 0.64, 0.55)
    hp._tfBubbleIncoming:Hide()

    hp._tfBubbleIncomingText = hp:CreateFontString(nil, "OVERLAY")
    ns:StyleFont(hp._tfBubbleIncomingText, ns.c_font, 7, nil, "OUTLINE")
    hp._tfBubbleIncomingText:SetPoint("RIGHT", hp, "RIGHT", -1, 0)
    hp._tfBubbleIncomingText:SetJustifyH("RIGHT")
    hp._tfBubbleIncomingText:SetTextColor(0.58, 1.0, 0.64, 0.95)
    hp._tfBubbleIncomingText:Hide()
    hp._tfBubbleSpendDuration = HEALTH_EFFECT_DURATION
end

local function StopSpend(bar)
    if not bar then return end
    bar._bubbleSpendActive = nil
    if activeSpendBars[bar] then
        activeSpendBars[bar] = nil
        activeSpendCount = max(0, activeSpendCount - 1)
        if activeSpendCount == 0 and ns.Cadence then ns.Cadence:Remove(activeSpendBars) end
    end
    if bar._tfBubbleSpend then bar._tfBubbleSpend:Hide() end
    if bar._tfBubbleArc then bar._tfBubbleArc:Hide() end
end

local function SpendOnUpdate(self, elapsed)
    local state = self._bubbleSpendState
    if not state or not self._bubbleSpendActive then
        StopSpend(self)
        return
    end
    state.elapsed = state.elapsed + elapsed
    local t = min(1, state.elapsed / (state.duration or MANA_EFFECT_DURATION))
    local overlay = self._tfBubbleSpend
    local arc = self._tfBubbleArc
    if overlay then
        overlay:SetWidth(max(1, state.width * (1 - 0.88 * t)))
        overlay:SetAlpha(0.75 * (1 - t))
    end
    if arc then
        arc:ClearAllPoints()
        arc:SetPoint("CENTER", self, "CENTER", state.arcX + 8 * t, 12 * sin(t * pi) + 3 * t)
        local arcSize = max(1, 3 - (t * 1.4))
        arc:SetSize(arcSize, arcSize)
        arc:SetAlpha(0.95 * (1 - t))
    end
    if t >= 1 then StopSpend(self) end
end

SpendDriverTick = function(_, elapsed)
    for bar in pairs(activeSpendBars) do
        SpendOnUpdate(bar, elapsed)
    end
end

local function TriggerSpend(bar, oldValue, newValue, maxValue)
    if not bar or not maxValue or maxValue <= 0 or oldValue <= newValue then return end
    local width = bar:GetWidth() or 1
    local oldX = width * min(1, oldValue / maxValue)
    local newX = width * min(1, newValue / maxValue)
    local spentW = max(1, oldX - newX)
    local overlay = bar._tfBubbleSpend
    local arc = bar._tfBubbleArc
    if not overlay or not arc then return end

    overlay:ClearAllPoints()
    overlay:SetPoint("LEFT", bar, "LEFT", newX, 0)
    overlay:SetHeight(bar:GetHeight())
    overlay:SetWidth(spentW)
    overlay:SetAlpha(0.75)
    overlay:Show()

    local arcX = -width * 0.5 + newX + spentW
    arc:ClearAllPoints()
    arc:SetPoint("CENTER", bar, "CENTER", arcX, 0)
    arc:SetSize(3, 3)
    arc:SetAlpha(0.95)
    arc:Show()

    bar._bubbleSpendState = bar._bubbleSpendState or {}
    bar._bubbleSpendState.elapsed = 0
    bar._bubbleSpendState.duration = bar._tfBubbleSpendDuration or MANA_EFFECT_DURATION
    bar._bubbleSpendState.width = spentW
    bar._bubbleSpendState.arcX = arcX
    bar._bubbleSpendActive = true
    if not activeSpendBars[bar] then
        activeSpendBars[bar] = true
        activeSpendCount = activeSpendCount + 1
    end
    if ns.Cadence then ns.Cadence:Add(activeSpendBars, 1 / 60, SpendDriverTick) end
end


local function NativeResourceHeightForPlate(plate)
    local hp = plate and plate.hp
    local hpHeight = hp and hp.GetHeight and hp:GetHeight() or 0
    if not hpHeight or hpHeight <= 0 then hpHeight = 9 end
    local fraction = tonumber(ns.c_nameplatePowerBarHeightPct) or 0.30
    if fraction < 0.10 then fraction = 0.10 elseif fraction > 0.40 then fraction = 0.40 end
    return max(RESOURCE_EMBED_MIN_HEIGHT, floor((hpHeight * fraction) + 0.5))
end

local function ApplyResourceGeometry(plate, bar)
    if not plate or not bar or not plate.hp then return end
    local hp = plate.hp
    local width = max(1, hp:GetWidth() or 1)
    local height = NativeResourceHeightForPlate(plate)

    if bar._tfResourceGeometryAnchor == hp
        and bar._tfResourceGeometryWidth == width
        and bar._tfResourceGeometryHeight == height then
        return
    end
    bar._tfResourceGeometryAnchor = hp
    bar._tfResourceGeometryWidth = width
    bar._tfResourceGeometryHeight = height

    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", 0, 0)
    bar:SetSize(width, height)
    bar:SetAlpha(0)
end

function BNP:GetEmbeddedResourceHeight(plate)
    if not plate or not plate.hp or ns.c_nameplatePowerBarOverlap ~= true then return 0 end
    return NativeResourceHeightForPlate(plate)
end

local function UpdateEmbeddedResourceVisual(plate, shown, current, maximum, r, g, b)
    local hp = plate and plate.hp
    if not hp then return end

    local fill = hp._tfBubbleEmbeddedPower
    if not shown or ns.c_nameplatePowerBarOverlap ~= true then
        if fill then fill:Hide() end
        return
    end

    if not fill then
        -- Classic 1.15.9 renders the native HP StatusBar fill in ARTWORK:0 and
        -- its Nameplate-Border in ARTWORK:1. Keep the embedded resource in the
        -- same fill pass, created after Blizzard's intrinsic fill, so it sits
        -- above health while the untouched Blizzard border remains above us.
        -- There is intentionally no dark/background strip: only the live power
        -- amount overlays the HP bar.
        fill = hp:CreateTexture(nil, "ARTWORK", nil, 0)
        fill:Hide()
        hp._tfBubbleEmbeddedPower = fill
    end

    local source = hp.GetStatusBarTexture and hp:GetStatusBarTexture()
    local atlas = source and source.GetAtlas and source:GetAtlas()
    local path = source and source.GetTexture and source:GetTexture()
    if not path and not atlas then path = "Interface\\TargetingFrame\\UI-StatusBar" end

    if hp._tfBubbleEmbeddedPowerSource ~= source
        or hp._tfBubbleEmbeddedPowerAtlas ~= atlas
        or hp._tfBubbleEmbeddedPowerPath ~= path then
        hp._tfBubbleEmbeddedPowerSource = source
        hp._tfBubbleEmbeddedPowerAtlas = atlas
        hp._tfBubbleEmbeddedPowerPath = path
        if atlas and fill.SetAtlas then
            fill:SetAtlas(atlas, false)
        else
            fill:SetTexture(path)
        end
    end

    if source and source.GetTexCoord and fill.SetTexCoord then
        local a, b1, c, d, e, f, g1, h = source:GetTexCoord()
        if h ~= nil then
            fill:SetTexCoord(a, b1, c, d, e, f, g1, h)
        elseif d ~= nil then
            fill:SetTexCoord(a, b1, c, d)
        end
    end

    local width = max(1, hp:GetWidth() or 1)
    local height = NativeResourceHeightForPlate(plate)
    local pct = 0
    if maximum and maximum > 0 then pct = min(1, max(0, (current or 0) / maximum)) end
    fill:ClearAllPoints()
    fill:SetPoint("BOTTOMLEFT", hp, "BOTTOMLEFT", 0, 0)
    fill:SetHeight(height)
    fill:SetVertexColor(r or 0.2, g or 0.4, b or 1, 1)
    if pct > 0 then
        fill:SetWidth(max(1, width * pct))
        fill:Show()
    else
        fill:Hide()
    end
end

local nativeGeometryRefreshPending = false
local function RefreshNativeGeometry()
    if nativeGeometryRefreshPending then return end
    nativeGeometryRefreshPending = true
    C_Timer_After(0, function()
        nativeGeometryRefreshPending = false
        if ns.UpdateAllPlates then ns:UpdateAllPlates() end
        -- UpdateAllPlates intentionally avoids a full unit rebuild for an
        -- already-bound plate. A native style/size change is different: every
        -- augmentation must immediately remeasure the live native substrate,
        -- including DoT and absorb geometry, even when health itself did not
        -- change. This path runs only for the two native geometry CVars.
        if ns.unitToPlate then
            for unit, plate in pairs(ns.unitToPlate) do
                if plate and plate.hp and not plate._tfNativeFriendlyIdentityOnly and UnitExists(unit) then
                    if plate.hp then plate.hp._tfOverlaySubstrateDirty = true end
                    if BNP.OnFullUpdate then BNP:OnFullUpdate(plate, unit) end
                    if ns.NP and ns.NP.UpdateHealth then ns.NP.UpdateHealth(unit) end
                end
            end
        end
    end)
end

local function Layout(plate)
    if not Enabled() or not plate or not plate.hp then return end
    plate._bubbleApplied = true
    EnsureHealthEffects(plate)

    if plate.threatNumber then AnchorThreatNumber(plate.threatNumber, plate) end
    if plate.nameplateJobIcon then AnchorJobIndicator(plate.nameplateJobIcon, plate, plate.unit) end
    if plate.nameplateSwing then BNP:_AnchorSwingFrame(plate.nameplateSwing, plate) end

    if plate.guildText then
        plate.guildText:ClearAllPoints()
        local unitFrame = plate.nativeUnitFrame or (plate.parentPlate and plate.parentPlate.UnitFrame)
        local chassis = unitFrame and unitFrame.HealthBarsContainer or plate.hp
        plate.guildText:SetPoint("TOPLEFT", chassis, "BOTTOMLEFT", 0, -2)
        plate.guildText:SetPoint("TOPRIGHT", chassis, "BOTTOMRIGHT", 0, -2)
        plate.guildText:SetJustifyH("CENTER")
        plate.guildText:SetAlpha(1)
        ns:StyleFont(plate.guildText, ns.c_font, ns.NP_TITLE_FONT_SIZE or 8, nil, ns.NP_NAME_TEXT_STYLE)
    end

    if ns.c_nameplatePowerBarOverlap == true
        and plate.bubbleResource and plate.bubbleResource:IsShown() then
        ApplyBubbleStatusTexture(plate.bubbleResource)
        ApplyResourceGeometry(plate, plate.bubbleResource)
        UpdateEmbeddedResourceVisual(plate, true,
            plate.bubbleResource._bubblePower, plate.bubbleResource._bubblePowerMax,
            plate.bubbleResource._r, plate.bubbleResource._g, plate.bubbleResource._b)
    elseif plate.bubbleResource then
        plate.bubbleResource:Hide()
        UpdateEmbeddedResourceVisual(plate, false)
    end
    if ns.UpdateAuraPositions then ns:UpdateAuraPositions(plate) end
end

local function Restore(plate, skipNativeStyle)
    if not plate then return end
    if plate.threatNumber then plate.threatNumber:Hide() end
    if plate.nameplateJobIcon then plate.nameplateJobIcon:Hide() end
    if plate.nameplateSwing then plate.nameplateSwing:Hide() end
    if plate.bubbleResource then plate.bubbleResource:Hide() end
    UpdateEmbeddedResourceVisual(plate, false)
    if plate.hp then
        StopSpend(plate.hp)
        if plate.hp._tfBubbleIncoming then plate.hp._tfBubbleIncoming:Hide() end
        if plate.hp._tfBubbleIncomingText then plate.hp._tfBubbleIncomingText:Hide() end
    end

    if plate._bubbleApplied then
        plate._bubbleApplied = nil
        if not skipNativeStyle and ns.RefreshNameplateAugments and plate.hp and not plate._tfNativeFriendlyIdentityOnly then
            ns:RefreshNameplateAugments(plate)
        end
    end
end

function BNP:UpdateSubtitle(plate, unit)
    if not plate or not plate.guildText then return end
    local formatted, raw = GetSubtitle(unit)
    if formatted then
        if plate.guildText._bubbleText ~= formatted then
            plate.guildText:SetText(formatted)
            plate.guildText._bubbleText = formatted
        end
        local source = ns.GetNameplateNameAnchor(plate, true)
        local r, g, b = 1, 1, 1
        if source and source.GetTextColor then
            r, g, b = source:GetTextColor()
        end
        plate.guildText:SetTextColor(r, g, b)
        plate.guildText:Show()
    else
        plate.guildText._bubbleText = nil
        plate.guildText:Hide()
    end
    return raw
end

function BNP:OnFullUpdate(plate, unit)
    if not plate then return end
    if plate._tfNativeFriendlyIdentityOnly then
        Restore(plate, true)
        self:UpdateJobIcon(plate, unit)
        return
    end
    if not Enabled() or plate.isPlayer or not plate.hp then
        Restore(plate)
        return
    end
    Layout(plate)
    local rawTitle = self:UpdateSubtitle(plate, unit)
    self:OnHealthUpdate(plate, unit, true)
    self:OnPowerUpdate(plate, unit, true)
    self:UpdateJobIcon(plate, unit, rawTitle)
    self:OnThreatUpdate(plate, unit)
    self:UpdateSwingMembership(plate, unit)
end

function BNP:OnHealthUpdate(plate, unit, force)
    if not Enabled() or not plate or not plate.hp or not unit or not UnitExists(unit) then return end
    EnsureHealthEffects(plate)
    local hp = plate.hp
    local current, maximum = ns.API.ReadUnitHealth(unit), ns.API.ReadUnitHealthMax(unit)
    if current == nil or maximum == nil then
        hp._tfBubbleIncoming:Hide()
        hp._tfBubbleIncomingText:Hide()
        return
    end
    local old, oldMax = hp._tfBubbleHealth, hp._tfBubbleHealthMax
    if not force and old and oldMax == maximum and current < old then
        TriggerSpend(hp, old, current, maximum)
    end
    hp._tfBubbleHealth, hp._tfBubbleHealthMax = current, maximum

    if UnitCanAttack and UnitCanAttack("player", unit) and maximum > 0 then
        local incoming = (ns.caps and ns.caps.healPrediction and UnitGetIncomingHeals and UnitGetIncomingHeals(unit)) or 0
        incoming = min(incoming, max(0, maximum - current))
        if incoming > 0 then
            local width = (hp:GetWidth() or 1) * incoming / maximum
            hp._tfBubbleIncoming:ClearAllPoints()
            hp._tfBubbleIncoming:SetPoint("TOPLEFT", hp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            hp._tfBubbleIncoming:SetPoint("BOTTOMLEFT", hp:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            hp._tfBubbleIncoming:SetWidth(max(1, width))
            hp._tfBubbleIncoming:Show()
            local text = "+" .. floor(incoming + 0.5)
            if hp._tfBubbleIncomingText._last ~= text then
                hp._tfBubbleIncomingText:SetText(text)
                hp._tfBubbleIncomingText._last = text
            end
            hp._tfBubbleIncomingText:Show()
        else
            hp._tfBubbleIncoming:Hide()
            hp._tfBubbleIncomingText:Hide()
        end
    else
        hp._tfBubbleIncoming:Hide()
        hp._tfBubbleIncomingText:Hide()
    end
end

function BNP:OnPowerUpdate(plate, unit, force)
    if ns.c_nameplatePowerBarOverlap ~= true then
        if plate and plate.bubbleResource then plate.bubbleResource:Hide() end
        if plate then UpdateEmbeddedResourceVisual(plate, false) end
        return
    end
    if not Enabled() or not plate or not plate.hp or not unit or not UnitExists(unit) then
        if plate and plate.bubbleResource then plate.bubbleResource:Hide() end
        if plate then UpdateEmbeddedResourceVisual(plate, false) end
        return
    end
    local maximum = ns.API.ReadUnitPowerMax(unit)
    if maximum == nil or maximum <= 0 then
        if plate.bubbleResource then plate.bubbleResource:Hide() end
        UpdateEmbeddedResourceVisual(plate, false)
        return
    end

    local bar = EnsureResource(plate)
    local current = ns.API.ReadUnitPower(unit)
    if current == nil then
        if plate.bubbleResource then plate.bubbleResource:Hide() end
        UpdateEmbeddedResourceVisual(plate, false)
        return
    end
    local powerType, token = UnitPowerType(unit)
    bar._bubblePower, bar._bubblePowerMax = current, maximum
    if bar._lastMax ~= maximum then bar:SetMinMaxValues(0, maximum); bar._lastMax = maximum end
    if bar._lastValue ~= current then bar:SetValue(current); bar._lastValue = current end
    ApplyBubbleStatusTexture(bar)

    local color = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType])
    local r, g, b = 0.2, 0.4, 1
    if color then r, g, b = color.r or r, color.g or g, color.b or b end
    if bar._r ~= r or bar._g ~= g or bar._b ~= b then
        bar:SetStatusBarColor(r, g, b)
        bar._r, bar._g, bar._b = r, g, b
    end
    ApplyResourceGeometry(plate, bar)
    bar:Show()
    UpdateEmbeddedResourceVisual(plate, true, current, maximum, r, g, b)
end

local function HasDetailedThreat(actor, unit)
    if not actor or not UnitExists(actor) then return false end
    local tanking, status, scaled, raw, value = UnitDetailedThreatSituation(actor, unit)
    return tanking ~= nil or status ~= nil or scaled ~= nil or raw ~= nil or value ~= nil
end

-- Phase 2 threat eligibility is TurboFace-owned.  We deliberately do not use
-- Blizzard's aggroHighlight/ShouldAggroHighlightBeShown state because 1.15.9
-- suppresses that presentation in valid solo threat situations.  A hostile
-- plate becomes threat-relevant when the player, pet, or group can be tied
-- to the unit's live combat relationship.
local function ThreatRelevant(unit)
    if not unit or not UnitExists(unit) or UnitIsDead(unit) then return false end
    if not UnitAffectingCombat(unit) then return false end

    if HasDetailedThreat("player", unit) then return true end
    if UnitExists("pet") and HasDetailedThreat("pet", unit) then return true end

    local victim = unit .. "target"
    if UnitExists(victim) then
        if UnitIsUnit(victim, "player") then return true end
        if UnitExists("pet") and UnitIsUnit(victim, "pet") then return true end

        if IsInRaid and IsInRaid() then
            for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
                local other = "raid" .. i
                if UnitExists(other) and UnitIsUnit(victim, other) then return true end
            end
        elseif IsInGroup and IsInGroup() then
            for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
                local other = "party" .. i
                if UnitExists(other) and UnitIsUnit(victim, other) then return true end
            end
        end

    end

    -- A group member can establish relevance even before the player personally
    -- appears on the unit's threat table.
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local other = "raid" .. i
            if UnitExists(other) and UnitThreatSituation(other, unit) ~= nil then return true end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
            local other = "party" .. i
            if UnitExists(other) and UnitThreatSituation(other, unit) ~= nil then return true end
        end
    end

    return false
end

local function ThreatForUnit(unit, scanOtherTank)
    local isTanking, status, scaled = UnitDetailedThreatSituation("player", unit)
    if scaled == nil then
        if status and status > 0 then scaled = status / 3 * 100 else scaled = 0 end
    end
    scaled = max(0, min(100, scaled or 0))
    if not isTanking and (status or 0) < 2 and not scanOtherTank then
        return scaled, false, status or 0, false
    end

    local highest = 0
    local otherTanking = false
    if UnitExists("pet") then
        local tank, s, p = UnitDetailedThreatSituation("pet", unit)
        if tank or (s or 0) >= 2 then otherTanking = true end
        if not p and s and s > 0 then p = s / 3 * 100 end
        if p and p > highest then highest = p end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local other = "raid" .. i
            if UnitExists(other) and not UnitIsUnit(other, "player") then
                local tank, s, p = UnitDetailedThreatSituation(other, unit)
                if tank or (s or 0) >= 2 then otherTanking = true end
                if not p and s and s > 0 then p = s / 3 * 100 end
                if p and p > highest then highest = p end
            end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
            local other = "party" .. i
            if UnitExists(other) then
                local tank, s, p = UnitDetailedThreatSituation(other, unit)
                if tank or (s or 0) >= 2 then otherTanking = true end
                if not p and s and s > 0 then p = s / 3 * 100 end
                if p and p > highest then highest = p end
            end
        end
    end
    if not isTanking and (status or 0) < 2 then
        return scaled, false, status or 0, otherTanking
    end
    if highest <= 0 then return 100, true, status or 3, otherTanking end
    return max(100, min(200, 200 - highest)), true, status or 3, otherTanking
end

local function SetThreatNumberColor(frame, value)
    if not frame or not frame.text then return end
    -- Color the same rounded integer that the player can actually see. Without
    -- this, e.g. 100.2 displayed as "100" but entered the >100 orange band.
    local display = min(200, max(0, floor((value or 0) + 0.5)))

    -- Preserve the exact information hierarchy formerly communicated by the
    -- Bubble fill. At 101+ the old overcap fill became the active leading
    -- color, so the text follows those same orange/blue/purple bands.
    local r, g, b = 0.2, 1, 0.2
    if display > 180 then
        r, g, b = 0.65, 0.2, 1
    elseif display > 145 then
        r, g, b = 0.2, 0.45, 1
    elseif display > 100 then
        r, g, b = 1, 0.55, 0.1
    elseif display >= 100 then
        r, g, b = 1, 0, 0
    elseif display >= 71 then
        r, g, b = 1, 0.55, 0.1
    elseif display >= 31 then
        r, g, b = 1, 0.95, 0.2
    end
    frame.text:SetTextColor(r, g, b, 1)
end

local function PlayAggro(gained)
    if not ns.c_nameplateAggroSounds or not (IsInGroup() or IsInRaid()) then return end
    local volume = gained and ns.c_nameplateAggroGainVolume or ns.c_nameplateAggroLossVolume
    if not volume or volume <= 0 then return end
    local played, handle = PlaySoundFile(gained and SOUND_GAIN or SOUND_LOSS, "Master")
    if played and handle and C_Sound and C_Sound.SetSoundVolume then C_Sound.SetSoundVolume(handle, volume) end
end

local function ThreatNumberEligible(unit)
    -- Threat Number is an NPC threat-table aid. Hostile players (and their
    -- player-controlled pets/guardians) can still enter the shared threat-event
    -- refresh path, but must never receive this NPC-only presentation.
    return unit and UnitExists(unit)
        and not UnitIsPlayer(unit)
        and not UnitPlayerControlled(unit)
end

function BNP:UpdateJobIcon(plate, unit, knownTitle)
    if not Enabled() or not ns.c_nameplateJobIcon or not plate or not unit or not UnitExists(unit)
        or UnitIsPlayer(unit) or UnitPlayerControlled(unit)
        or (not UnitIsFriend("player", unit) and UnitCanAttack("player", unit)) then
        if plate and plate.nameplateJobIcon then plate.nameplateJobIcon:Hide() end
        return
    end

    local title = knownTitle
    if title == nil then
        local _, raw = GetSubtitle(unit)
        title = raw
    end
    local kind = ResolveJob(unit, title)
    local f = kind and EnsureJobIndicator(plate) or plate.nameplateJobIcon
    if not f then return end
    if kind then
        SetJobTexture(f.job, kind)
        AnchorJobIndicator(f, plate, unit)
        f.job:Show()
        f:Show()
    else
        f.job:Hide()
        f:Hide()
    end
end

function BNP:OnThreatUpdate(plate, unit)
    if not Enabled() or not plate or not unit or not UnitExists(unit) then
        if plate and plate.threatNumber then plate.threatNumber:Hide() end
        self:RemoveSwingFrame(plate)
        return
    end

    local friendly = UnitIsFriend("player", unit) or not UnitCanAttack("player", unit)
    if friendly then
        if plate.threatNumber then plate.threatNumber:Hide() end
        self:RemoveSwingFrame(plate)
        return
    end

    -- Nameplate swing timing is independently gated. Threat relevance and
    -- quantitative-threat presentation must never decide whether it can run.
    self:UpdateSwingMembership(plate, unit)

    -- Quantitative threat and Aggro Audio remain independent. The text surface
    -- exists only while its dedicated presentation toggle is enabled. Audio
    -- needs threat state only for the current target while it is actually
    -- enabled in a group, so do not run threat API work for every hostile plate
    -- when neither consumer has demand.
    local showThreatNumber = ns.c_nameplateThreatNumber ~= false and ThreatNumberEligible(unit)
    local f = showThreatNumber and EnsureThreatNumber(plate) or plate.threatNumber
    local isTarget = UnitExists("target") and UnitIsUnit(unit, "target")
    local wantsAggroAudio = isTarget and ns.c_nameplateAggroSounds and (IsInGroup() or IsInRaid())

    if not showThreatNumber and not wantsAggroAudio then
        if f then f:Hide() end
        if isTarget then
            local guid = UnitGUID(unit)
            if guid then aggroState[guid] = nil end
        end
        return
    end

    if not ThreatRelevant(unit) then
        if f then f:Hide() end
        if isTarget then
            local guid = UnitGUID(unit)
            if guid then aggroState[guid] = nil end
        end
        return
    end

    local value, tanking, status, other = 0, false, 0, false
    if not UnitIsDead(unit) then value, tanking, status, other = ThreatForUnit(unit, isTarget) end

    if f then
        if showThreatNumber then
            local rounded = floor(value + 0.5)
            if f._text ~= rounded then
                f.text:SetText(rounded)
                f._text = rounded
            end
            SetThreatNumberColor(f, value)
            f:Show()
        else
            f:Hide()
        end
    end

    if isTarget then
        local guid = UnitGUID(unit)
        if wantsAggroAudio then
            local state = guid and aggroState[guid]
            if not state then state = {}; aggroState[guid] = state end
            if state.tanking ~= nil and state.tanking ~= tanking then
                if tanking and state.other then PlayAggro(true)
                elseif not tanking and other then PlayAggro(false) end
            end
            state.tanking, state.other = tanking, other
        elseif guid then
            -- Audio disabled/out of group: discard transition memory so turning
            -- it back on cannot replay a gain/loss that happened while muted.
            aggroState[guid] = nil
        end
    end
end

function BNP:UpdateSwingMembership(plate, unit)
    if not Enabled() or not ns.c_nameplateSwingTimer or not plate or not unit or not UnitCanAttack("player", unit) then
        self:RemoveSwingFrame(plate)
        return
    end
    local guid = UnitGUID(unit)
    local state = guid and ns.SwingTimers and ns.SwingTimers:GetNameplateState(guid)
    -- Before the first observed swing, an engaged hostile should be treated as
    -- ready rather than fabricating a cooldown from combat entry. The swing
    -- state owner seeds this only while the unit is genuinely engaged; the
    -- first real SWING_DAMAGE/SWING_MISSED then replaces it with authoritative
    -- readyAt/duration timing.
    if not state and guid and ns.SwingTimers and ns.SwingTimers.PrimeNameplateState then
        state = ns.SwingTimers:PrimeNameplateState(guid, unit)
    end
    if state and state.readyAt then
        if not activeSwingFrames[plate] then
            activeSwingFrames[plate] = guid
            activeSwingCount = activeSwingCount + 1
        end
        activeSwingFrames[plate] = guid
        local swing = self:_EnsureSwing(plate)
        if swing then self:_AnchorSwingFrame(swing, plate) end
        self:WakeSwingDriver()
    else
        self:RemoveSwingFrame(plate)
    end
end

function BNP:RemoveSwingFrame(plate)
    if activeSwingFrames[plate] then
        activeSwingFrames[plate] = nil
        activeSwingCount = max(0, activeSwingCount - 1)
    end
    local f = plate and plate.nameplateSwing
    if f then
        self:_HideSwingProgress(f)
        self:_SetSwingReady(f, false)
        f:Hide()
    end
    if activeSwingCount == 0 then self:ParkSwingDriver() end
end

function BNP:RefreshSwingFeature()
    if not Enabled() or not ns.c_nameplateSwingTimer then
        local removalCount = 0
        for plate in pairs(activeSwingFrames) do
            removalCount = removalCount + 1
            swingRemovalBuffer[removalCount] = plate
        end
        for i = 1, removalCount do
            self:RemoveSwingFrame(swingRemovalBuffer[i])
            swingRemovalBuffer[i] = nil
        end
        return
    end

    if ns.unitToPlate then
        for unit, plate in pairs(ns.unitToPlate) do
            if plate and plate:IsShown() then self:UpdateSwingMembership(plate, unit) end
        end
    end
end

SwingTick = function(_, elapsed)
    BNP:OnSwingUpdate(elapsed)
end

function BNP:WakeSwingDriver()
    if activeSwingCount <= 0 or not Enabled() or not ns.c_nameplateSwingTimer then return end
    if ns.Cadence then ns.Cadence:Add(activeSwingFrames, SWING_UPDATE_RATE, SwingTick, true) end
end

function BNP:ParkSwingDriver()
    if ns.Cadence then ns.Cadence:Remove(activeSwingFrames) end
end

function BNP:OnSwingUpdate(elapsed)
    local now = GetTime()
    -- One player-combat query per 30 Hz tick, not once per tracked nameplate.
    local playerInCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    local removalCount = 0
    for plate, guid in pairs(activeSwingFrames) do
        local unit = plate and plate.unit
        local state = guid and ns.SwingTimers and ns.SwingTimers:GetNameplateState(guid)
        if not plate or not plate:IsShown() or not unit or UnitGUID(unit) ~= guid or not state or not state.readyAt then
            removalCount = removalCount + 1
            swingRemovalBuffer[removalCount] = plate
        else
            local s = self:_EnsureSwing(plate)
            if not s or not self:_AnchorSwingFrame(s, plate) then
                removalCount = removalCount + 1
                swingRemovalBuffer[removalCount] = plate
            else
                local remaining = state.readyAt - now
                local duration = max(0.1, state.duration or 2)
                if remaining > 0 then
                    local progress = 1 - min(1, remaining / duration)
                    if progress > 0.05 and progress < 0.95 then
                        if self:_ShowSwingProgress(s, progress) then
                            self:_SetSwingReady(s, false)
                            s:Show()
                        else
                            s:Hide()
                        end
                    elseif progress >= 0.95 and playerInCombat then
                        self:_HideSwingProgress(s)
                        self:_SetSwingReady(s, true)
                        s:Show()
                    else
                        self:_HideSwingProgress(s)
                        self:_SetSwingReady(s, false)
                        s:Hide()
                    end
                elseif playerInCombat then
                    self:_HideSwingProgress(s)
                    self:_SetSwingReady(s, true)
                    s:Show()
                else
                    removalCount = removalCount + 1
                    swingRemovalBuffer[removalCount] = plate
                end
            end
        end
    end
    for i = 1, removalCount do
        self:RemoveSwingFrame(swingRemovalBuffer[i])
        swingRemovalBuffer[i] = nil
    end
end

function BNP:OnEnemySwing(guid)
    local unit = guid and ns.guidToNameplateUnit and ns.guidToNameplateUnit[guid]
    local plate = unit and ns.unitToPlate and ns.unitToPlate[unit]
    if plate then self:UpdateSwingMembership(plate, unit) end
end

function BNP:OnTargetChanged(previousPlate, currentPlate)
    if not Enabled() then return end
    if previousPlate and previousPlate:IsShown() and previousPlate.unit then
        self:OnThreatUpdate(previousPlate, previousPlate.unit)
    end
    if currentPlate and currentPlate ~= previousPlate and currentPlate:IsShown() and currentPlate.unit then
        self:OnThreatUpdate(currentPlate, currentPlate.unit)
    end
end

function BNP:CleanupGUID(guid)
    if not guid then return end
    aggroState[guid] = nil
    jobIconCache[guid] = nil
end

function BNP:CleanupPlate(plate, unit, guid)
    if not plate then return end
    self:RemoveSwingFrame(plate)
    Restore(plate, true)
    guid = guid or (unit and UnitGUID(unit)) or plate.cachedGUID
    self:CleanupGUID(guid)
    if plate.hp then
        plate.hp._tfBubbleHealth = nil
        plate.hp._tfBubbleHealthMax = nil
        plate.hp._tfOverlaySubstrateDirty = true
        if ns.NP and ns.NP.RestoreDotRenderOrder then ns.NP.RestoreDotRenderOrder(plate.hp) end
        if plate.hp._tfBubbleIncomingText then plate.hp._tfBubbleIncomingText._last = nil end
    end
    plate._lastAbsorb = nil
    plate._lastAbsorbHealth = nil
    plate._lastAbsorbWidth = nil
    plate._lastAbsorbHeight = nil
    plate._lastAbsorbFill = nil
    plate._lastDotOffset = nil
    plate._lastDotWidth = nil
    plate._lastDotBottomInset = nil
    if plate.bubbleResource then
        plate.bubbleResource._bubblePower = nil
        plate.bubbleResource._bubblePowerMax = nil
    end
end

-- User-configurable nameplate CVars are SET from the live option cache rather
-- than floored against the current CVar. Reading back TurboFace's previous write
-- would otherwise pin a slider in one direction. These are reversibly owned
-- CVars (ARCHITECTURE 8.2), so module release restores the captured user values.
local DEFAULT_OVERLAP_V = 1.00
local DEFAULT_OVERLAP_H = 1.35
local DEFAULT_SELECTED_SCALE = 1
local DEFAULT_SELECTED_ALPHA = 1
local DEFAULT_NOT_SELECTED_ALPHA = 0.80

local STACK_TYPE = Enum and Enum.NamePlateStackType
local ENEMY_STACK_BIT = STACK_TYPE and STACK_TYPE.Enemy or 1
local NAMEPLATE_CVAR_STACKING = {
    nameplateStackingTypes = {
        [ENEMY_STACK_BIT] = true,
    },
}
local NAMEPLATE_CVAR_GEOMETRY = {
    nameplateMaxDistance = "41",
    nameplateOverlapH = tostring(DEFAULT_OVERLAP_H),
    nameplateOverlapV = tostring(DEFAULT_OVERLAP_V),
    nameplateSelectedScale = tostring(DEFAULT_SELECTED_SCALE),
    nameplateSelectedAlpha = tostring(DEFAULT_SELECTED_ALPHA),
    nameplateNotSelectedAlpha = tostring(DEFAULT_NOT_SELECTED_ALPHA),
}

-- 0.15.17 removes the old visibility lock and Questie-offset features. These
-- helpers exist only to repay ownership debt captured by an older build. They
-- never take new ownership and become inert as soon as the saved snapshot is
-- restored and cleared.
local function ReleaseLegacyVisibilityOwnership()
    if ns.ReleaseOwnedCVars then
        return ns.ReleaseOwnedCVars("nameplates.visibility")
    elseif ns.ApplyOwnedCVars then
        return ns.ApplyOwnedCVars("nameplates.visibility", false, {})
    end
    return true
end

local function LegacyQuestieOwnershipPending()
    local owners = type(TurboFaceCacheDB) == "table" and TurboFaceCacheDB.questieOwners
    return type(owners) == "table" and owners.nameplateXCaptured == true
end

local function ReleaseLegacyQuestieCompatibility()
    if not LegacyQuestieOwnershipPending() then
        if type(TurboFaceCacheDB) == "table"
            and type(TurboFaceCacheDB.questieOwners) == "table"
            and next(TurboFaceCacheDB.questieOwners) == nil
        then
            TurboFaceCacheDB.questieOwners = nil
        end
        return true
    end
    if not (Questie and Questie.db and type(Questie.db.profile) == "table") then
        return false
    end

    local owners = TurboFaceCacheDB.questieOwners
    Questie.db.profile.nameplateX = owners.nameplateX
    owners.nameplateX = nil
    owners.nameplateXCaptured = nil
    if next(owners) == nil then TurboFaceCacheDB.questieOwners = nil end

    if QuestieLoader and QuestieLoader.ImportModule then
        local questieNameplate = QuestieLoader:ImportModule("QuestieNameplate")
        if questieNameplate and questieNameplate.RedrawIcons then
            questieNameplate:RedrawIcons()
        end
    end
    return true
end

local function RefreshLegacyQuestieReleaseEvent()
    local frame = BNP.cvarFrame
    if not frame then return end
    if LegacyQuestieOwnershipPending() then
        ns.RegisterEvent(frame, "ADDON_LOADED")
    else
        frame:UnregisterEvent("ADDON_LOADED")
    end
end

function BNP:ApplyNameplateCVars()
    -- CVar ownership is persistent across reloads via TurboFaceCacheDB. A
    -- disabled Nameplates module therefore restores values TurboFace captured
    -- before it first took ownership instead of merely ceasing to write them.
    ReleaseLegacyVisibilityOwnership()
    ReleaseLegacyQuestieCompatibility()
    RefreshLegacyQuestieReleaseEvent()

    local enabled = Enabled()
    if not enabled then
        if ns.ApplyOwnedCVars then
            ns.ApplyOwnedCVars("nameplates.geometry", false, NAMEPLATE_CVAR_GEOMETRY)
        end
        if ns.ApplyOwnedCVarBits then
            ns.ApplyOwnedCVarBits("nameplates.stacking", false, NAMEPLATE_CVAR_STACKING)
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        if not self._cvarRetryPending then
            self._cvarRetryPending = true
            C_Timer_After(0.5, function()
                self._cvarRetryPending = nil
                self:ApplyNameplateCVars()
            end)
        end
        return
    end

    if ns.ApplyOwnedCVars then
        -- Preserve a user value above TurboFace's distance minimum. The other
        -- geometry/selection values are explicit Nameplates preferences. The
        -- ownership snapshot is captured before any write occurs.
        local distance = tonumber(GetCVar and GetCVar("nameplateMaxDistance") or "") or 0
        NAMEPLATE_CVAR_GEOMETRY.nameplateMaxDistance = tostring(max(distance, 41))
        NAMEPLATE_CVAR_GEOMETRY.nameplateOverlapH =
            tostring(ns.c_nameplateOverlapH or DEFAULT_OVERLAP_H)
        NAMEPLATE_CVAR_GEOMETRY.nameplateOverlapV =
            tostring(ns.c_nameplateOverlapV or DEFAULT_OVERLAP_V)
        NAMEPLATE_CVAR_GEOMETRY.nameplateSelectedScale =
            tostring(ns.c_nameplateSelectedScale or DEFAULT_SELECTED_SCALE)
        NAMEPLATE_CVAR_GEOMETRY.nameplateSelectedAlpha =
            tostring(ns.c_nameplateSelectedAlpha or DEFAULT_SELECTED_ALPHA)
        NAMEPLATE_CVAR_GEOMETRY.nameplateNotSelectedAlpha =
            tostring(ns.c_nameplateNotSelectedAlpha or DEFAULT_NOT_SELECTED_ALPHA)
        ns.ApplyOwnedCVars("nameplates.geometry", true, NAMEPLATE_CVAR_GEOMETRY)
    end
    if ns.ApplyOwnedCVarBits then
        ns.ApplyOwnedCVarBits("nameplates.stacking", true, NAMEPLATE_CVAR_STACKING)
    end
end

-- Reapply TurboFace's narrow nameplate CVar contract when the client or another addon
-- changes the relevant values. This frame is event-only and has no idle driver.
BNP.cvarFrame = BNP.cvarFrame or CreateFrame("Frame")
BNP.cvarFrame:SetScript("OnEvent", function(frame, event, name)
    if event == "CVAR_UPDATE" then
        if name == "nameplateSize" or name == "nameplateStyle" then
            -- Let Blizzard rebuild its style/size first, then measure the live
            -- substrate again for TurboFace text and augmentation anchors.
            RefreshNativeGeometry()
            return
        end

        local geometryChanged = name == "nameplateMaxDistance"
            or name == "nameplateOverlapH"
            or name == "nameplateOverlapV"
            or name == "nameplateSelectedScale"
            or name == "nameplateSelectedAlpha"
            or name == "nameplateNotSelectedAlpha"
            or name == "nameplateStackingTypes"
        if not geometryChanged then return end
    elseif event == "ADDON_LOADED" then
        if name ~= "Questie" then return end
        ReleaseLegacyQuestieCompatibility()
        RefreshLegacyQuestieReleaseEvent()
        return
    end
    BNP:ApplyNameplateCVars()
end)

local cvarRuntimeActive = false
function BNP:ActivateRuntime()
    if cvarRuntimeActive or not Enabled() then return end
    cvarRuntimeActive = true
    ns.RegisterEvent(BNP.cvarFrame, "PLAYER_REGEN_ENABLED")
    ns.RegisterEvent(BNP.cvarFrame, "CVAR_UPDATE")
    -- Activation happens during Core's PLAYER_LOGIN handler, so apply the CVar
    -- contract directly rather than subscribing to an event already in flight.
    self:ApplyNameplateCVars()
end

-- Opt-in subsystem CPU targets; inert unless /tf debug cpu start is running.
ns.RegisterCPUProfileTarget("Nameplates/Bubble:SpendDriver", SpendDriverTick, false)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:SpendPerBar", SpendOnUpdate)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:SwingTick", BNP.OnSwingUpdate)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:CVarEvents", BNP.cvarFrame:GetScript("OnEvent"))
ns.RegisterCPUProfileTarget("Nameplates/Bubble:FullUpdate", BNP.OnFullUpdate)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:HealthUpdate", BNP.OnHealthUpdate)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:PowerUpdate", BNP.OnPowerUpdate)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:JobIcon", BNP.UpdateJobIcon)
ns.RegisterCPUProfileTarget("Nameplates/Bubble:ThreatUpdate", BNP.OnThreatUpdate)
