local _, ns = ...
local Trainer = ns.Trainer

-- Live-verified Forever trainer teachings that do not exist in the embedded
-- Classic Era profession database. Keep this deliberately evidence-driven:
-- rows enter the seed only after `/tf professiondataprobe capture trainer`
-- records their spell identity, skill gate, price, and icon on the target
-- client. Later live trainer observations still override these static values.
Trainer.ForeverProfessionTrainingData = {
    Blacksmithing = {
        {
            spellID = 1252231,
            name = "Glowing Copper Boots",
            skillReq = 35,
            cost = 95,
            icon = 132535,
        },
        {
            spellID = 1252230,
            name = "Strange Copper Boots",
            skillReq = 35,
            cost = 95,
            icon = 132582,
        },
    },
}
