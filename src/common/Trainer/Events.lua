local _, ns = ...
local Trainer = ns.Trainer
-- Event ownership is demand-driven: a disabled Training module stays dormant,
-- so registration and the event frame itself live behind SetEvents().
local f
local TrainerEventHandler

local function EnsureEventFrame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetScript("OnEvent", TrainerEventHandler)
    return f
end

local function RegisterOptionalEvent(frame, event)
    -- Some client flavors retain the trainer API without exposing every modern
    -- companion event. Unknown events are therefore optional capabilities,
    -- not a reason to fail Trainer initialization on the other client.
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end

function Trainer:SetEvents(active)
    if not active then
        if f then f:UnregisterAllEvents() end
        return
    end
    local frame = EnsureEventFrame()
    frame:UnregisterAllEvents()
    frame:RegisterEvent("TRAINER_SHOW")
    frame:RegisterEvent("TRAINER_UPDATE")
    RegisterOptionalEvent(frame, "TRAINER_CLOSED")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_UPDATE")
    ns.RegisterUnitEvent(frame, "UNIT_PET", "player")
    frame:RegisterEvent("SPELLS_CHANGED")
    if C_Spell and type(C_Spell.RequestLoadSpellData) == "function" then
        RegisterOptionalEvent(frame, "SPELL_DATA_LOAD_RESULT")
    end
end
local captureScheduled = false
local merchantCaptureScheduled = false
local petSyncScheduled = false
local spellDataScheduled = false
TrainerEventHandler = function(self, event, arg1, arg2)
    if event == "TRAINER_CLOSED" then
        Trainer.trainerWindowOpen = false
        if Trainer.EndTrainingQueueVisit then Trainer:EndTrainingQueueVisit() end
        return
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        Trainer.trainerWindowOpen = true
        if event == "TRAINER_SHOW" and Trainer.BeginTrainingQueueVisit then Trainer:BeginTrainingQueueVisit() end
        if event == "TRAINER_UPDATE" and Trainer.TrainingQueueTrainerUpdated then Trainer:TrainingQueueTrainerUpdated() end
        Trainer:EnsureTrainerUpdateOverrideInstalled()
        Trainer:EnsureTrainerFilterHookInstalled()
        if C_Timer then
            if not captureScheduled then
                captureScheduled = true
                C_Timer.After(0.1, function()
                    captureScheduled = false
                    if not Trainer.tooltipActive or not Trainer.trainerWindowOpen then return end
                    Trainer:CaptureTrainer()
                    Trainer:CaptureTrainerRequirements()
                    if Trainer.ProcessTrainingQueue then Trainer:ProcessTrainingQueue() end
                end)
            end
        else
            Trainer:CaptureTrainer()
            Trainer:CaptureTrainerRequirements()
            if Trainer.ProcessTrainingQueue then Trainer:ProcessTrainingQueue() end
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        if C_Timer then
            if not merchantCaptureScheduled then
                merchantCaptureScheduled = true
                C_Timer.After(0.1, function()
                    merchantCaptureScheduled = false
                    if not Trainer.tooltipActive then return end
                    Trainer:CaptureMerchant()
                end)
            end
        else
            Trainer:CaptureMerchant()
        end
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if not Trainer.trainerWindowOpen then return end
        -- C_Spell metadata can arrive after the trainer snapshot. Whether the
        -- event reports full success or partial data, retry once: GetSpellInfo
        -- can become usable even when description data remains incomplete.
        if C_Timer then
            if not spellDataScheduled then
                spellDataScheduled = true
                C_Timer.After(0.05, function()
                    spellDataScheduled = false
                    if not Trainer.tooltipActive or not Trainer.trainerWindowOpen then return end
                    if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() end
                    if Trainer.CaptureTrainer then Trainer:CaptureTrainer() end
                    if Trainer.ProcessTrainingQueue then Trainer:ProcessTrainingQueue() end
                end)
            end
        else
            if Trainer.RefreshActiveSpellbookList then Trainer.RefreshActiveSpellbookList() end
            if Trainer.CaptureTrainer then Trainer:CaptureTrainer() end
            if Trainer.ProcessTrainingQueue then Trainer:ProcessTrainingQueue() end
        end
    elseif event == "SPELLS_CHANGED" or (event == "UNIT_PET" and arg1 == "player") then
        if C_Timer then
            if not petSyncScheduled then
                petSyncScheduled = true
                C_Timer.After(1, function()
                    petSyncScheduled = false
                    if not Trainer.tooltipActive then return end
                    Trainer:SyncKnownPetSpellsForActivePet()
                end)
            end
        else
            Trainer:SyncKnownPetSpellsForActivePet()
        end
    end
end
