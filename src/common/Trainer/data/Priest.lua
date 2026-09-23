local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.PRIEST = Trainer.Builtin.PRIEST or {
    [1] = {
        [1243] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [589] = {
            cost = 100,
            rank = 1
        },
        [2052] = {
            cost = 100,
            rank = 2,
            requires = {2050}
        },
    },
    [6] = {
        [17] = {
            cost = 100,
            rank = 1
        },
        [591] = {
            cost = 100,
            rank = 2,
            requires = {585}
        },
    },
    [8] = {
        [139] = {
            cost = 200,
            rank = 1
        },
        [586] = {
            cost = 200,
            rank = 1
        },
    },
    [10] = {
        [594] = {
            cost = 300,
            rank = 2
        },
        [2006] = {
            cost = 300,
            rank = 1
        },
        [2053] = {
            cost = 300,
            rank = 3,
            requires = {2050}
        },
        [8092] = {
            cost = 300,
            rank = 1
        },
        [13908] = {
            cost = 15,
            rank = 1,
            race = {"Dwarf", "Human"}
        },
        [10797] = {
            cost = 15,
            rank = 1,
            race = "NightElf"
        },
        [2652] = {
            cost = 15,
            rank = 1,
            race = "Scourge"
        },
        [9035] = {
            cost = 15,
            rank = 1,
            race = "Troll"
        },
    },
    [12] = {
        [588] = {
            cost = 800,
            rank = 1
        },
        [592] = {
            cost = 800,
            rank = 2
        },
        [1244] = {
            cost = 800,
            rank = 2
        },
    },
    [14] = {
        [528] = {
            cost = 1200,
            rank = nil
        },
        [598] = {
            cost = 1200,
            rank = 3,
            requires = {585}
        },
        [6074] = {
            cost = 1200,
            rank = 2
        },
        [8122] = {
            cost = 1200,
            rank = 1
        },
    },
    [16] = {
        [2054] = {
            cost = 1600,
            rank = 1
        },
        [8102] = {
            cost = 1600,
            rank = 2
        },
    },
    [18] = {
        [527] = {
            cost = 2000,
            rank = 1
        },
        [600] = {
            cost = 2000,
            rank = 3
        },
        [970] = {
            cost = 2000,
            rank = 3
        },
        [19236] = {
            cost = 100,
            rank = 2,
            race = {"Dwarf", "Human"}
        },
        [19296] = {
            cost = 100,
            rank = 2,
            race = "NightElf"
        },
    },
    [20] = {
        [453] = {
            cost = 3000,
            rank = 1
        },
        [2061] = {
            cost = 3000,
            rank = 1
        },
        [6075] = {
            cost = 3000,
            rank = 3
        },
        [7128] = {
            cost = 3000,
            rank = 2
        },
        [9484] = {
            cost = 3000,
            rank = 1
        },
        [9578] = {
            cost = 3000,
            rank = 2
        },
        [14914] = {
            cost = 3000,
            rank = 1
        },
        [6346] = {
            cost = 150,
            rank = 1,
            race = "Dwarf"
        },
        [13896] = {
            cost = 150,
            rank = 1,
            race = "Human"
        },
        [2651] = {
            cost = 150,
            rank = 1,
            race = "NightElf"
        },
        [19261] = {
            cost = 150,
            rank = 2,
            race = "Scourge"
        },
        [2944] = {
            cost = 150,
            rank = 1,
            race = "Scourge"
        },
        [19281] = {
            cost = 150,
            rank = 2,
            race = "Troll"
        },
        [18137] = {
            cost = 150,
            rank = 1,
            race = "Troll"
        },
    },
    [22] = {
        [984] = {
            cost = 4000,
            rank = 4,
            requires = {585}
        },
        [2010] = {
            cost = 4000,
            rank = 2
        },
        [2055] = {
            cost = 4000,
            rank = 2
        },
        [2096] = {
            cost = 4000,
            rank = 1
        },
        [8103] = {
            cost = 4000,
            rank = 3
        },
    },
    [24] = {
        [1245] = {
            cost = 5000,
            rank = 3
        },
        [3747] = {
            cost = 5000,
            rank = 4
        },
        [8129] = {
            cost = 5000,
            rank = 1
        },
        [15262] = {
            cost = 5000,
            rank = 2
        },
    },
    [26] = {
        [992] = {
            cost = 6000,
            rank = 4
        },
        [6076] = {
            cost = 6000,
            rank = 4
        },
        [9472] = {
            cost = 6000,
            rank = 2
        },
        [19238] = {
            cost = 300,
            rank = 3,
            race = {"Dwarf", "Human"}
        },
        [19299] = {
            cost = 300,
            rank = 3,
            race = "NightElf"
        },
    },
    [28] = {
        [6063] = {
            cost = 8000,
            rank = 3
        },
        [8104] = {
            cost = 8000,
            rank = 4
        },
        [8124] = {
            cost = 8000,
            rank = 2
        },
        [15430] = {
            cost = 400,
            rank = 2,
            requires = {15237}
        },
        [17311] = {
            cost = 400,
            rank = 2,
            requires = {15407}
        },
        [19276] = {
            cost = 400,
            rank = 2,
            race = "Scourge"
        },
        [19308] = {
            cost = 400,
            rank = 2,
            race = "Troll"
        },
    },
    [30] = {
        [596] = {
            cost = 10000,
            rank = 1
        },
        [602] = {
            cost = 10000,
            rank = 3
        },
        [605] = {
            cost = 10000,
            rank = 1
        },
        [976] = {
            cost = 10000,
            rank = 1
        },
        [1004] = {
            cost = 10000,
            rank = 5,
            requires = {585}
        },
        [6065] = {
            cost = 10000,
            rank = 5
        },
        [9579] = {
            cost = 10000,
            rank = 3
        },
        [15263] = {
            cost = 10000,
            rank = 3
        },
        [19271] = {
            cost = 500,
            rank = 2,
            race = "Human"
        },
        [19262] = {
            cost = 500,
            rank = 3,
            race = "Scourge"
        },
        [19282] = {
            cost = 500,
            rank = 3,
            race = "Troll"
        },
    },
    [32] = {
        [552] = {
            cost = 11000,
            rank = nil
        },
        [6077] = {
            cost = 11000,
            rank = 5
        },
        [8131] = {
            cost = 11000,
            rank = 2
        },
        [9473] = {
            cost = 11000,
            rank = 3
        },
    },
    [34] = {
        [1706] = {
            cost = 12000,
            rank = nil
        },
        [2767] = {
            cost = 12000,
            rank = 5
        },
        [6064] = {
            cost = 12000,
            rank = 4
        },
        [8105] = {
            cost = 12000,
            rank = 5
        },
        [10880] = {
            cost = 12000,
            rank = 3
        },
        [19240] = {
            cost = 600,
            rank = 4,
            race = {"Dwarf", "Human"}
        },
        [19302] = {
            cost = 600,
            rank = 4,
            race = "NightElf"
        },
    },
    [36] = {
        [988] = {
            cost = 14000,
            rank = 2
        },
        [2791] = {
            cost = 14000,
            rank = 4
        },
        [6066] = {
            cost = 14000,
            rank = 6
        },
        [8192] = {
            cost = 14000,
            rank = 2
        },
        [15264] = {
            cost = 14000,
            rank = 4
        },
        [15431] = {
            cost = 700,
            rank = 3,
            requires = {15237}
        },
        [17312] = {
            cost = 700,
            rank = 3,
            requires = {15407}
        },
        [19277] = {
            cost = 700,
            rank = 3,
            race = "Scourge"
        },
        [19309] = {
            cost = 700,
            rank = 3,
            race = "Troll"
        },
    },
    [38] = {
        [6060] = {
            cost = 16000,
            rank = 6,
            requires = {585}
        },
        [6078] = {
            cost = 16000,
            rank = 6
        },
        [9474] = {
            cost = 16000,
            rank = 4
        },
    },
    [40] = {
        [996] = {
            cost = 18000,
            rank = 2
        },
        [1006] = {
            cost = 18000,
            rank = 4
        },
        [2060] = {
            cost = 18000,
            rank = 1
        },
        [8106] = {
            cost = 18000,
            rank = 6
        },
        [9485] = {
            cost = 18000,
            rank = 2
        },
        [9592] = {
            cost = 18000,
            rank = 4
        },
        [10874] = {
            cost = 18000,
            rank = 3
        },
        [14818] = {
            cost = 900,
            rank = 2,
            requires = {14752}
        },
        [19273] = {
            cost = 900,
            rank = 3,
            race = "Human"
        },
        [19264] = {
            cost = 900,
            rank = 4,
            race = "Scourge"
        },
        [19283] = {
            cost = 900,
            rank = 4,
            race = "Troll"
        },
    },
    [42] = {
        [10888] = {
            cost = 22000,
            rank = 3
        },
        [10892] = {
            cost = 22000,
            rank = 6
        },
        [10898] = {
            cost = 22000,
            rank = 7
        },
        [10957] = {
            cost = 22000,
            rank = 2
        },
        [15265] = {
            cost = 22000,
            rank = 5
        },
        [19241] = {
            cost = 1100,
            rank = 5,
            race = {"Dwarf", "Human"}
        },
        [19303] = {
            cost = 1100,
            rank = 5,
            race = "NightElf"
        },
    },
    [44] = {
        [10909] = {
            cost = 24000,
            rank = 2
        },
        [10911] = {
            cost = 24000,
            rank = 2
        },
        [10915] = {
            cost = 24000,
            rank = 5
        },
        [10927] = {
            cost = 24000,
            rank = 7
        },
        [17313] = {
            cost = 1200,
            rank = 4,
            requires = {15407}
        },
        [27799] = {
            cost = 1200,
            rank = 4,
            requires = {15237}
        },
        [19278] = {
            cost = 1200,
            rank = 4,
            race = "Scourge"
        },
        [19310] = {
            cost = 1200,
            rank = 4,
            race = "Troll"
        },
    },
    [46] = {
        [10881] = {
            cost = 26000,
            rank = 4
        },
        [10933] = {
            cost = 26000,
            rank = 7,
            requires = {585}
        },
        [10945] = {
            cost = 26000,
            rank = 7
        },
        [10963] = {
            cost = 26000,
            rank = 2
        },
    },
    [48] = {
        [10875] = {
            cost = 28000,
            rank = 4
        },
        [10899] = {
            cost = 28000,
            rank = 8
        },
        [10937] = {
            cost = 28000,
            rank = 5
        },
        [15266] = {
            cost = 28000,
            rank = 6
        },
    },
    [50] = {
        [10893] = {
            cost = 30000,
            rank = 7
        },
        [10916] = {
            cost = 30000,
            rank = 6
        },
        [10928] = {
            cost = 30000,
            rank = 8
        },
        [10941] = {
            cost = 30000,
            rank = 5
        },
        [10951] = {
            cost = 30000,
            rank = 5
        },
        [10960] = {
            cost = 30000,
            rank = 3
        },
        [14819] = {
            cost = 1500,
            rank = 3,
            requires = {14752}
        },
        [19242] = {
            cost = 1500,
            rank = 6,
            race = {"Dwarf", "Human"}
        },
        [19304] = {
            cost = 1500,
            rank = 6,
            race = "NightElf"
        },
        [19274] = {
            cost = 1500,
            rank = 4,
            race = "Human"
        },
        [19265] = {
            cost = 1500,
            rank = 5,
            race = "Scourge"
        },
        [19284] = {
            cost = 1500,
            rank = 5,
            race = "Troll"
        },
        [27870] = {
            cost = 1200,
            rank = 2,
            requires = {724}
        },
    },
    [52] = {
        [10946] = {
            cost = 38000,
            rank = 8
        },
        [10953] = {
            cost = 38000,
            rank = 3
        },
        [10964] = {
            cost = 38000,
            rank = 3
        },
        [17314] = {
            cost = 1900,
            rank = 5,
            requires = {15407}
        },
        [27800] = {
            cost = 1900,
            rank = 5,
            requires = {15237}
        },
        [19279] = {
            cost = 1900,
            rank = 5,
            race = "Scourge"
        },
        [19311] = {
            cost = 1900,
            rank = 5,
            race = "Troll"
        },
    },
    [54] = {
        [10900] = {
            cost = 40000,
            rank = 9
        },
        [10934] = {
            cost = 40000,
            rank = 8,
            requires = {585}
        },
        [15267] = {
            cost = 40000,
            rank = 7
        },
    },
    [56] = {
        [10876] = {
            cost = 42000,
            rank = 5
        },
        [10890] = {
            cost = 42000,
            rank = 4
        },
        [10917] = {
            cost = 42000,
            rank = 7
        },
        [10929] = {
            cost = 42000,
            rank = 9
        },
        [10958] = {
            cost = 42000,
            rank = 3
        },
    },
    [58] = {
        [10894] = {
            cost = 44000,
            rank = 8
        },
        [10912] = {
            cost = 44000,
            rank = 3
        },
        [10947] = {
            cost = 44000,
            rank = 9
        },
        [10965] = {
            cost = 44000,
            rank = 4
        },
        [19243] = {
            cost = 2200,
            rank = 7,
            race = {"Dwarf", "Human"}
        },
        [19305] = {
            cost = 2200,
            rank = 7,
            race = "NightElf"
        },
        [20770] = {
            cost = 44000,
            rank = 5
        },
    },
    [60] = {
        [10901] = {
            cost = 46000,
            rank = 10
        },
        [10938] = {
            cost = 46000,
            rank = 6
        },
        [10942] = {
            cost = 46000,
            rank = 6
        },
        [10952] = {
            cost = 46000,
            rank = 6
        },
        [10955] = {
            cost = 46000,
            rank = 3
        },
        [10961] = {
            cost = 46000,
            rank = 4
        },
        [15261] = {
            cost = 46000,
            rank = 8
        },
        [18807] = {
            cost = 2300,
            rank = 6,
            requires = {15407}
        },
        [19275] = {
            cost = 2300,
            rank = 5,
            race = "Human"
        },
        [19266] = {
            cost = 2300,
            rank = 6,
            race = "Scourge"
        },
        [19280] = {
            cost = 2300,
            rank = 6,
            race = "Scourge"
        },
        [19285] = {
            cost = 2300,
            rank = 6,
            race = "Troll"
        },
        [19312] = {
            cost = 2300,
            rank = 6,
            race = "Troll"
        },
        [27681] = {
            cost = 2300,
            rank = 1,
            requires = {14752}
        },
        [27801] = {
            cost = 2300,
            rank = 6,
            requires = {15237}
        },
        [27841] = {
            cost = 2300,
            rank = 4,
            requires = {14752}
        },
        [27871] = {
            cost = 1500,
            rank = 3,
            requires = {724}
        },
    },
}
end
