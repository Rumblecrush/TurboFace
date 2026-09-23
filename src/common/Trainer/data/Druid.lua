local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.DRUID = Trainer.Builtin.DRUID or {
    [1] = {
        [1126] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [774] = {
            cost = 100,
            rank = 1
        },
        [8921] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [467] = {
            cost = 100,
            rank = 1
        },
        [5177] = {
            cost = 100,
            rank = 2,
            requires = {5179}
        },
    },
    [8] = {
        [339] = {
            cost = 200,
            rank = 1
        },
        [5186] = {
            cost = 200,
            rank = 2,
            requires = {5189}
        },
    },
    [10] = {
        [99] = {
            cost = 300,
            rank = 1,
            requires = {5487}
        },
        [1058] = {
            cost = 300,
            rank = 2,
            requires = {2091}
        },
        [5232] = {
            cost = 300,
            rank = 2,
            requires = {6756}
        },
        [8924] = {
            cost = 300,
            rank = 2,
            requires = {8927}
        },
    },
    [12] = {
        [5229] = {
            cost = 800,
            rank = nil,
            requires = {5487}
        },
        [8936] = {
            cost = 800,
            rank = 1
        },
    },
    [14] = {
        [782] = {
            cost = 900,
            rank = 2,
            requires = {1075}
        },
        [5178] = {
            cost = 900,
            rank = 3,
            requires = {5179}
        },
        [5187] = {
            cost = 900,
            rank = 3,
            requires = {5189}
        },
        [5211] = {
            cost = 900,
            rank = 1,
            requires = {5487}
        },
    },
    [16] = {
        [779] = {
            cost = 1800,
            rank = 1,
            requires = {5487}
        },
        [1430] = {
            cost = 1800,
            rank = 3,
            requires = {2091}
        },
        [8925] = {
            cost = 1800,
            rank = 3,
            requires = {8927}
        },
    },
    [18] = {
        [770] = {
            cost = 1900,
            rank = 1
        },
        [1062] = {
            cost = 1900,
            rank = 2,
            requires = {1062}
        },
        [2637] = {
            cost = 1900,
            rank = 1
        },
        [6808] = {
            cost = 1900,
            rank = 2,
            requires = {6809}
        },
        [8938] = {
            cost = 1900,
            rank = 2,
            requires = {8939}
        },
        [16810] = {
            cost = 95,
            rank = 2,
            requires = {16689, 1062}
        },
    },
    [20] = {
        [768] = {
            cost = 2000,
            rank = nil
        },
        [1079] = {
            cost = 2000,
            rank = 1,
            requires = {768}
        },
        [1082] = {
            cost = 2000,
            rank = 1,
            requires = {768}
        },
        [1735] = {
            cost = 2000,
            rank = 2,
            requires = {1735}
        },
        [2912] = {
            cost = 2000,
            rank = 1
        },
        [5188] = {
            cost = 2000,
            rank = 4,
            requires = {5189}
        },
        [5215] = {
            cost = 2000,
            rank = 1,
            requires = {768}
        },
        [6756] = {
            cost = 2000,
            rank = 3,
            requires = {6756}
        },
        [20484] = {
            cost = 2000,
            rank = 1
        },
    },
    [22] = {
        [2090] = {
            cost = 3000,
            rank = 4,
            requires = {2091}
        },
        [2908] = {
            cost = 3000,
            rank = 1
        },
        [5179] = {
            cost = 3000,
            rank = 4,
            requires = {5179}
        },
        [5221] = {
            cost = 3000,
            rank = 1,
            requires = {768}
        },
        [8926] = {
            cost = 3000,
            rank = 4,
            requires = {8927}
        },
    },
    [24] = {
        [780] = {
            cost = 4000,
            rank = 2,
            requires = {780}
        },
        [1075] = {
            cost = 4000,
            rank = 3,
            requires = {1075}
        },
        [1822] = {
            cost = 4000,
            rank = 1,
            requires = {768}
        },
        [2782] = {
            cost = 4000,
            rank = nil
        },
        [5217] = {
            cost = 4000,
            rank = 1,
            requires = {768}
        },
        [8939] = {
            cost = 4000,
            rank = 3,
            requires = {8939}
        },
    },
    [26] = {
        [1850] = {
            cost = 4500,
            rank = 1,
            requires = {768}
        },
        [2893] = {
            cost = 4500,
            rank = nil
        },
        [5189] = {
            cost = 4500,
            rank = 5,
            requires = {5189}
        },
        [6809] = {
            cost = 4500,
            rank = 3,
            requires = {6809}
        },
        [8949] = {
            cost = 4500,
            rank = 2,
            requires = {2912}
        },
    },
    [28] = {
        [2091] = {
            cost = 5000,
            rank = 5,
            requires = {2091}
        },
        [3029] = {
            cost = 5000,
            rank = 2,
            requires = {3029}
        },
        [5195] = {
            cost = 5000,
            rank = 3,
            requires = {1062}
        },
        [5209] = {
            cost = 5000,
            rank = nil,
            requires = {5487}
        },
        [8927] = {
            cost = 5000,
            rank = 5,
            requires = {8927}
        },
        [8998] = {
            cost = 5000,
            rank = 1,
            requires = {768}
        },
        [9492] = {
            cost = 5000,
            rank = 2,
            requires = {9492}
        },
        [16811] = {
            cost = 250,
            rank = 3,
            requires = {16689, 1062}
        },
    },
    [30] = {
        [740] = {
            cost = 6000,
            rank = 1
        },
        [778] = {
            cost = 6000,
            rank = 2,
            requires = {770}
        },
        [783] = {
            cost = 6000,
            rank = nil
        },
        [5180] = {
            cost = 6000,
            rank = 5,
            requires = {5179}
        },
        [5234] = {
            cost = 6000,
            rank = 4,
            requires = {6756}
        },
        [6798] = {
            cost = 6000,
            rank = 2,
            requires = {5211}
        },
        [6800] = {
            cost = 6000,
            rank = 2,
            requires = {5221}
        },
        [8940] = {
            cost = 6000,
            rank = 4,
            requires = {8939}
        },
        [17390] = {
            cost = 300,
            rank = 2,
            requires = {16857}
        },
        [20739] = {
            cost = 6000,
            rank = 2
        },
        [24974] = {
            cost = 300,
            rank = 2,
            requires = {5570}
        },
    },
    [32] = {
        [5225] = {
            cost = 8000,
            rank = nil,
            requires = {768}
        },
        [6778] = {
            cost = 8000,
            rank = 6,
            requires = {5189}
        },
        [6785] = {
            cost = 8000,
            rank = 1,
            requires = {768}
        },
        [9490] = {
            cost = 8000,
            rank = 3,
            requires = {1735}
        },
        [22568] = {
            cost = 8000,
            rank = 1,
            requires = {768}
        },
    },
    [34] = {
        [769] = {
            cost = 10000,
            rank = 3,
            requires = {780}
        },
        [1823] = {
            cost = 10000,
            rank = 2,
            requires = {1822}
        },
        [3627] = {
            cost = 10000,
            rank = 6,
            requires = {2091}
        },
        [8914] = {
            cost = 10000,
            rank = 4,
            requires = {1075}
        },
        [8928] = {
            cost = 10000,
            rank = 6,
            requires = {8927}
        },
        [8950] = {
            cost = 10000,
            rank = 3,
            requires = {2912}
        },
        [8972] = {
            cost = 10000,
            rank = 4,
            requires = {6809}
        },
    },
    [36] = {
        [6793] = {
            cost = 11000,
            rank = 2,
            requires = {5217}
        },
        [8941] = {
            cost = 11000,
            rank = 5,
            requires = {8939}
        },
        [9005] = {
            cost = 11000,
            rank = 1,
            requires = {768}
        },
        [9493] = {
            cost = 11000,
            rank = 3,
            requires = {9492}
        },
        [22842] = {
            cost = 11000,
            rank = 1,
            requires = {5487}
        },
    },
    [38] = {
        [5196] = {
            cost = 12000,
            rank = 4,
            requires = {1062}
        },
        [5201] = {
            cost = 12000,
            rank = 3,
            requires = {3029}
        },
        [6780] = {
            cost = 12000,
            rank = 6,
            requires = {5179}
        },
        [8903] = {
            cost = 12000,
            rank = 7,
            requires = {5189}
        },
        [8955] = {
            cost = 12000,
            rank = 2,
            requires = {2908}
        },
        [8992] = {
            cost = 12000,
            rank = 3,
            requires = {5221}
        },
        [16812] = {
            cost = 600,
            rank = 4,
            requires = {16689, 1062}
        },
        [18657] = {
            cost = 12000,
            rank = 2,
            requires = {2637}
        },
    },
    [40] = {
        [6783] = {
            cost = 14000,
            rank = 2,
            requires = {5215}
        },
        [8907] = {
            cost = 14000,
            rank = 5,
            requires = {6756}
        },
        [8910] = {
            cost = 14000,
            rank = 7,
            requires = {2091}
        },
        [8918] = {
            cost = 14000,
            rank = 2
        },
        [8929] = {
            cost = 14000,
            rank = 7,
            requires = {8927}
        },
        [9000] = {
            cost = 14000,
            rank = 2,
            requires = {8998}
        },
        [9634] = {
            cost = 14000,
            rank = nil,
            requires = {5487}
        },
        [16914] = {
            cost = 14000,
            rank = 1
        },
        [20719] = {
            cost = 14000,
            rank = nil,
            requires = {768}
        },
        [20742] = {
            cost = 14000,
            rank = 3
        },
        [22827] = {
            cost = 14000,
            rank = 2
        },
        [24975] = {
            cost = 700,
            rank = 3,
            requires = {5570}
        },
        [29166] = {
            cost = 14000,
            rank = 1
        },
    },
    [42] = {
        [6787] = {
            cost = 16000,
            rank = 2
        },
        [8951] = {
            cost = 16000,
            rank = 4,
            requires = {2912}
        },
        [9745] = {
            cost = 16000,
            rank = 5,
            requires = {6809}
        },
        [9747] = {
            cost = 16000,
            rank = 4,
            requires = {1735}
        },
        [9749] = {
            cost = 16000,
            rank = 3,
            requires = {770}
        },
        [9750] = {
            cost = 16000,
            rank = 6,
            requires = {8939}
        },
        [17391] = {
            cost = 800,
            rank = 3,
            requires = {16857}
        },
    },
    [44] = {
        [1824] = {
            cost = 18000,
            rank = 3,
            requires = {1822}
        },
        [9752] = {
            cost = 18000,
            rank = 4,
            requires = {9492}
        },
        [9754] = {
            cost = 18000,
            rank = 4,
            requires = {780}
        },
        [9756] = {
            cost = 18000,
            rank = 5,
            requires = {1075}
        },
        [9758] = {
            cost = 18000,
            rank = 8,
            requires = {5189}
        },
        [22812] = {
            cost = 18000,
            rank = nil
        },
    },
    [46] = {
        [8905] = {
            cost = 20000,
            rank = 7,
            requires = {5179}
        },
        [8983] = {
            cost = 20000,
            rank = 3,
            requires = {5211}
        },
        [9821] = {
            cost = 20000,
            rank = 2,
            requires = {1850}
        },
        [9823] = {
            cost = 20000,
            rank = 2
        },
        [9829] = {
            cost = 20000,
            rank = 4,
            requires = {5221}
        },
        [9833] = {
            cost = 20000,
            rank = 8,
            requires = {8927}
        },
        [9839] = {
            cost = 20000,
            rank = 8,
            requires = {2091}
        },
        [22895] = {
            cost = 20000,
            rank = 2
        },
    },
    [48] = {
        [9845] = {
            cost = 22000,
            rank = 3,
            requires = {5217}
        },
        [9849] = {
            cost = 22000,
            rank = 4,
            requires = {3029}
        },
        [9852] = {
            cost = 22000,
            rank = 5,
            requires = {1062}
        },
        [9856] = {
            cost = 22000,
            rank = 7,
            requires = {8939}
        },
        [16813] = {
            cost = 1100,
            rank = 5,
            requires = {16689, 1062}
        },
        [22828] = {
            cost = 22000,
            rank = 3
        },
    },
    [50] = {
        [9862] = {
            cost = 23000,
            rank = 3
        },
        [9866] = {
            cost = 23000,
            rank = 3
        },
        [9875] = {
            cost = 23000,
            rank = 5,
            requires = {2912}
        },
        [9880] = {
            cost = 23000,
            rank = 6,
            requires = {6809}
        },
        [9884] = {
            cost = 23000,
            rank = 6,
            requires = {6756}
        },
        [9888] = {
            cost = 23000,
            rank = 9,
            requires = {5189}
        },
        [17401] = {
            cost = 23000,
            rank = 2
        },
        [20747] = {
            cost = 23000,
            rank = 4
        },
        [24976] = {
            cost = 1150,
            rank = 4,
            requires = {5570}
        },
    },
    [52] = {
        [9834] = {
            cost = 26000,
            rank = 9,
            requires = {8927}
        },
        [9840] = {
            cost = 26000,
            rank = 9,
            requires = {2091}
        },
        [9892] = {
            cost = 26000,
            rank = 3,
            requires = {8998}
        },
        [9894] = {
            cost = 26000,
            rank = 5,
            requires = {9492}
        },
        [9898] = {
            cost = 26000,
            rank = 5,
            requires = {1735}
        },
    },
    [54] = {
        [9830] = {
            cost = 28000,
            rank = 5,
            requires = {5221}
        },
        [9857] = {
            cost = 28000,
            rank = 8,
            requires = {8939}
        },
        [9901] = {
            cost = 28000,
            rank = 3,
            requires = {2908}
        },
        [9904] = {
            cost = 28000,
            rank = 4,
            requires = {1822}
        },
        [9907] = {
            cost = 28000,
            rank = 4,
            requires = {770}
        },
        [9908] = {
            cost = 28000,
            rank = 5,
            requires = {780}
        },
        [9910] = {
            cost = 28000,
            rank = 6,
            requires = {1075}
        },
        [9912] = {
            cost = 28000,
            rank = 8,
            requires = {5179}
        },
        [17392] = {
            cost = 1400,
            rank = 4,
            requires = {16857}
        },
    },
    [56] = {
        [9827] = {
            cost = 30000,
            rank = 3
        },
        [9889] = {
            cost = 30000,
            rank = 10,
            requires = {5189}
        },
        [22829] = {
            cost = 30000,
            rank = 4
        },
        [22896] = {
            cost = 30000,
            rank = 3
        },
    },
    [58] = {
        [9835] = {
            cost = 32000,
            rank = 10,
            requires = {8927}
        },
        [9841] = {
            cost = 32000,
            rank = 10,
            requires = {2091}
        },
        [9850] = {
            cost = 32000,
            rank = 5,
            requires = {3029}
        },
        [9853] = {
            cost = 32000,
            rank = 6,
            requires = {1062}
        },
        [9867] = {
            cost = 32000,
            rank = 4
        },
        [9876] = {
            cost = 32000,
            rank = 6,
            requires = {2912}
        },
        [9881] = {
            cost = 32000,
            rank = 7,
            requires = {6809}
        },
        [17329] = {
            cost = 1600,
            rank = 6,
            requires = {16689, 1062}
        },
        [18658] = {
            cost = 32000,
            rank = 3,
            requires = {2637}
        },
    },
    [60] = {
        [9846] = {
            cost = 34000,
            rank = 4,
            requires = {5217}
        },
        [9858] = {
            cost = 34000,
            rank = 9,
            requires = {8939}
        },
        [9863] = {
            cost = 34000,
            rank = 4
        },
        [9885] = {
            cost = 34000,
            rank = 7,
            requires = {6756}
        },
        [9896] = {
            cost = 34000,
            rank = 6,
            requires = {9492}
        },
        [9913] = {
            cost = 34000,
            rank = 3,
            requires = {5215}
        },
        [17402] = {
            cost = 34000,
            rank = 3
        },
        [20748] = {
            cost = 34000,
            rank = 5
        },
        [24977] = {
            cost = 1700,
            rank = 5,
            requires = {5570}
        },
    },
}
end
