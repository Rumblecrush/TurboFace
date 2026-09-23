local _, ns = ...
local Trainer = ns.Trainer
local L = ns.TrainerStrings
local GetItemInfo = ns.API.GetItemInfo
local GetSpellInfo = ns.API.GetSpellInfo
local GetSpellSubtext = ns.API.GetSpellSubtext
local function DetectPetFromTooltip(tooltip)
    for i = 1, tooltip:NumLines() do
        local fs = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        local petWord = text and text:match("Teaches%s+(%S+)")
        if petWord then
            for _, pet in pairs(Trainer.PetNames) do
                if petWord:lower() == pet:lower() then return pet end
            end
        end
    end
end

local function CaptureMerchantInner()
    if not GetMerchantNumItems then return end
    local numItems = GetMerchantNumItems()
    local neu = 0
    local scanTooltip = Trainer:GetScanTooltip()
    for i = 1, numItems do
        local itemLink = GetMerchantItemLink(i)
        if itemLink then
            local itemName, _, _, _, itemMinLevel = GetItemInfo(itemLink)
            if itemMinLevel then
                scanTooltip:ClearLines()
                scanTooltip:SetMerchantItem(i)
                local pet = DetectPetFromTooltip(scanTooltip)
                if pet then
                    local _, spellID = scanTooltip:GetSpell()
                    if Trainer:IsSaneSpellID(spellID) then
                        local _, _, price = GetMerchantItemInfo(i)
                        local rankNum = itemName and tonumber(itemName:match("%(.-(%d+)%)"))
                        local bucket = Trainer:EnsurePetPath(pet, itemMinLevel)
                        if bucket[spellID] == nil then neu = neu + 1 end
                        bucket[spellID] = {
                            cost = price or 0,
                            rank = rankNum,
                        }
                    end
                end
            end
        end
    end

    if neu > 0 then ns:Chat("Trainer", ("recorded %d new pet ability(s)."):format(neu)) end
end

function Trainer:CaptureMerchant()
    local ok, err = pcall(CaptureMerchantInner)
    if not ok then ns:Chat("Trainer", "|cffff5555Capture error:|r " .. tostring(err)) end
end

function Trainer:IsPetSpellKnown(spellID, pet)
    if spellID == nil then return nil end
    spellID = tonumber(spellID)
    if pet and TurboFaceTrainerCharDB.character and TurboFaceTrainerCharDB.character.learnedSpellsPet and TurboFaceTrainerCharDB.character.learnedSpellsPet[pet] and TurboFaceTrainerCharDB.character.learnedSpellsPet[pet][spellID] ~= nil then return TurboFaceTrainerCharDB.character.learnedSpellsPet[pet][spellID] end
    if TurboFaceTrainerCharDB.character and TurboFaceTrainerCharDB.character.learnedSpellsPet then
        for i, data in pairs(TurboFaceTrainerCharDB.character.learnedSpellsPet) do
            if data[spellID] ~= nil then return data[spellID] end
        end
    end
    return nil
end

local function FindPetSpellIDByNameAndRank(pet, spellName, rankNum)
    if not spellName then return nil end
    local levels = TurboFaceTrainerDB.petData and TurboFaceTrainerDB.petData[pet]
    if not levels then return nil end
    for _, spells in pairs(levels) do
        for spellID, data in pairs(spells) do
            local name = GetSpellInfo(spellID)
            local rank = GetSpellSubtext(spellID)
            local dbRankNum = rank and tonumber(rank:match("%d+"))
            if name == spellName then
                if dbRankNum and rankNum then
                    if dbRankNum == rankNum then return spellID end
                else
                    return spellID
                end
            end
        end
    end
end

-- Installed from Init, not at file scope. A HookScript can never be removed
-- once applied, so hooking Blizzard's tooltip at load would leave a permanent
-- trace of a module the player has switched off. Installing on enable means a
-- never-enabled module leaves the tooltip untouched; the guard inside covers
-- the one case a hook cannot: being disabled again after it was installed.
function Trainer:InstallTooltipHook()
    if self.tooltipHooked then return end
    self.tooltipHooked = true

    local function OnTrainerPetItemTooltip(tooltip, tooltipData)
        if tooltip ~= GameTooltip or not Trainer.tooltipActive then return end
        local pet = DetectPetFromTooltip(tooltip)
        local family = UnitCreatureFamily("pet")
        if not pet then return end

        local itemID = tooltipData and tooltipData.id
        if ns.API.CanAccessValue and not ns.API.CanAccessValue(itemID) then itemID = nil end

        local itemName, itemLink
        if itemID ~= nil then
            itemName, itemLink = GetItemInfo(itemID)
        elseif tooltip.GetItem then
            local ok, name, link = pcall(tooltip.GetItem, tooltip)
            if ok then itemName, itemLink = name, link end
        end

        local rankNum = itemName and tonumber(itemName:match("%(.-(%d+)%)"))
        local itemInfo = itemID or itemLink
        local spellName = itemInfo and C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(itemInfo)
        local spellID = FindPetSpellIDByNameAndRank(pet, spellName, rankNum)
        if not spellID then return end
        local isPetSpellKnown = Trainer:IsPetSpellKnown(spellID, family)
        if isPetSpellKnown == true then
            if pet ~= family then tooltip:AddLine(L.LID_ALREADYKNOWN, 0.9, 0.2, 0.2) end
        elseif isPetSpellKnown == false then
            tooltip:AddLine(L.LID_NOTLEARNEDYET, 0.2, 0.9, 0.2)
        else
            tooltip:AddLine(L.LID_NOTSCANNEDYET, 0.9, 0.9, 0.2)
        end

        tooltip:Show()
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTrainerPetItemTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetItem", OnTrainerPetItemTooltip)
    end
end

local function MarkKnownPetSpells(pet, dataTable)
    local petHealth = ns.API.ReadUnitHealth("pet")
    if ns.API.ReadUnitExists("pet") ~= true or petHealth == nil or petHealth <= 0 then return end
    local petSpells = {}
    local i = 1
    while true do
        local name, rank = GetSpellBookItemName(i, BOOKTYPE_PET)
        if not name then break end
        local rankNum = rank and tonumber(rank:match("%d+"))
        petSpells[name] = math.max(petSpells[name] or 0, rankNum or 1)
        i = i + 1
    end

    TurboFaceTrainerCharDB.character.learnedSpellsPet[pet] = TurboFaceTrainerCharDB.character.learnedSpellsPet[pet] or {}
    local changed = false
    for _, spells in pairs(dataTable) do
        for spellID, data in pairs(spells) do
            spellID = tonumber(spellID)
            local info = C_Spell.GetSpellInfo(spellID)
            local name = info and info.name
            local rankNum = type(data) == "table" and tonumber(data.rank)
            local maxKnown = name and petSpells[name]
            if not maxKnown then
                TurboFaceTrainerCharDB.character.learnedSpellsPet[pet][spellID] = false
                changed = true
            elseif rankNum then
                TurboFaceTrainerCharDB.character.learnedSpellsPet[pet][spellID] = rankNum <= maxKnown
                changed = true
            end
        end
    end
    return changed
end

function Trainer:SyncKnownPetSpellsForActivePet()
    if not GetSpellInfo or not UnitCreatureFamily then return end
    local family = UnitCreatureFamily("pet")
    local petData = family and TurboFaceTrainerDB.petData[family]
    if not petData then return end
    local changed = MarkKnownPetSpells(family, petData)
    if changed then
        if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList()
        elseif Trainer.RefreshList then Trainer.RefreshList() end
    end
end