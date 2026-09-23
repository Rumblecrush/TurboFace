local _, ns = ...
local Trainer = ns.Trainer

-- Merge the permissively licensed class/pet seed catalog into TurboFace's
-- account-wide discovery store. Profession trainer rows have a LibProfessionDB
-- baseline in the profession UI; runtime discoveries enrich that baseline.
function Trainer:MergeBuiltinData()
    local loaders = Trainer.BuiltinLoaders
    if loaders then
        for i = 1, #loaders do
            loaders[i]()
        end
        Trainer.BuiltinLoaders = nil
    end

    if Trainer.Builtin then
        for class, levels in pairs(Trainer.Builtin) do
            for level, spells in pairs(levels) do
                local bucket = Trainer:EnsurePath(class, level)
                for spellID, data in pairs(spells) do
                    local existing = bucket[spellID]
                    if existing == nil then
                        bucket[spellID] = {
                            cost = data.cost or 0,
                            rank = data.rank,
                            faction = data.faction,
                            race = data.race,
                        }
                    else
                        -- Live trainer observations own transient status. Seed
                        -- metadata only fills stable factual fields.
                        if data.cost and existing.cost == nil then existing.cost = data.cost end
                        if data.rank and existing.rank == nil then existing.rank = data.rank end
                        if data.faction and existing.faction == nil then existing.faction = data.faction end
                        if data.race and existing.race == nil then existing.race = data.race end
                    end
                end
            end
        end
    end

    if Trainer.Builtin_WarlockPet then
        for pet, levels in pairs(Trainer.Builtin_WarlockPet) do
            for level, spells in pairs(levels) do
                local bucket = Trainer:EnsurePetPath(pet, level)
                for spellID, data in pairs(spells) do
                    local existing = bucket[spellID]
                    if existing == nil then
                        bucket[spellID] = {
                            cost = data.cost or 0,
                            rank = data.rank,
                            faction = data.faction,
                        }
                    else
                        if data.cost and existing.cost == nil then existing.cost = data.cost end
                        if data.rank and existing.rank == nil then existing.rank = data.rank end
                        if data.faction and existing.faction == nil then existing.faction = data.faction end
                    end
                end
            end
        end
    end

    if Trainer.Builtin_HunterPet then
        for level, spells in pairs(Trainer.Builtin_HunterPet) do
            local bucket = Trainer:EnsurePetTrainerPath("HUNTER", level)
            for spellID, data in pairs(spells) do
                local existing = bucket[spellID]
                if existing == nil then
                    bucket[spellID] = {
                        cost = data.cost or 0,
                        rank = data.rank,
                        faction = data.faction,
                    }
                else
                    if data.cost and existing.cost == nil then existing.cost = data.cost end
                    if data.rank and existing.rank == nil then existing.rank = data.rank end
                    if data.faction and existing.faction == nil then existing.faction = data.faction end
                end
            end
        end
    end

    -- Staging tables are load-only; release them after the merge.
    Trainer.Builtin = nil
    Trainer.Builtin_WarlockPet = nil
    Trainer.Builtin_HunterPet = nil
end
