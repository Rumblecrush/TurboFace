local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.PALADIN = Trainer.Builtin.PALADIN or {
    [1] = {
        [465] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [19740] = {
            cost = 100,
            rank = 1
        },
        [20271] = {
            cost = 100,
            rank = nil
        },
    },
    [6] = {
        [498] = {
            cost = 100,
            rank = 1
        },
        [639] = {
            cost = 100,
            rank = 2,
            requires = {639}
        },
        [21082] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [853] = {
            cost = 100,
            rank = 1
        },
        [1152] = {
            cost = 100,
            rank = nil
        },
        [3127] = {
            cost = 100,
            rank = nil
        },
    },
    [10] = {
        [633] = {
            cost = 300,
            rank = 1
        },
        [1022] = {
            cost = 300,
            rank = 1
        },
        [10290] = {
            cost = 300,
            rank = 2,
            requires = {10290}
        },
        [20287] = {
            cost = 300,
            rank = 2,
            requires = {20287}
        },
    },
    [12] = {
        [19834] = {
            cost = 1000,
            rank = 2,
            requires = {19740}
        },
        [20162] = {
            cost = 1000,
            rank = 2,
            requires = {21082}
        },
    },
    [14] = {
        [647] = {
            cost = 2000,
            rank = 3,
            requires = {639}
        },
        [19742] = {
            cost = 2000,
            rank = 1
        },
    },
    [16] = {
        [7294] = {
            cost = 3000,
            rank = 1
        },
        [25780] = {
            cost = 3000,
            rank = nil
        },
    },
    [18] = {
        [1044] = {
            cost = 3500,
            rank = nil
        },
        [5573] = {
            cost = 3500,
            rank = 2,
            requires = {498}
        },
        [20288] = {
            cost = 3500,
            rank = 3,
            requires = {20287}
        },
    },
    [20] = {
        [643] = {
            cost = 4000,
            rank = 3,
            requires = {10290}
        },
        [879] = {
            cost = 4000,
            rank = 1
        },
        [19750] = {
            cost = 4000,
            rank = 1
        },
    },
    [22] = {
        [1026] = {
            cost = 4000,
            rank = 4,
            requires = {639}
        },
        [19746] = {
            cost = 4000,
            rank = nil
        },
        [19835] = {
            cost = 4000,
            rank = 3,
            requires = {19740}
        },
        [20164] = {
            cost = 4000,
            rank = nil
        },
        [20305] = {
            cost = 4000,
            rank = 3,
            requires = {21082}
        },
    },
    [24] = {
        [2878] = {
            cost = 5000,
            rank = 1
        },
        [5588] = {
            cost = 5000,
            rank = 2,
            requires = {853}
        },
        [5599] = {
            cost = 5000,
            rank = 2,
            requires = {1022}
        },
        [10322] = {
            cost = 5000,
            rank = 2
        },
        [19850] = {
            cost = 5000,
            rank = 2
        },
    },
    [26] = {
        [1038] = {
            cost = 6000,
            rank = nil
        },
        [10298] = {
            cost = 6000,
            rank = 2
        },
        [19939] = {
            cost = 6000,
            rank = 2
        },
        [20289] = {
            cost = 6000,
            rank = 4,
            requires = {20287}
        },
    },
    [28] = {
        [5614] = {
            cost = 9000,
            rank = 2
        },
        [19876] = {
            cost = 9000,
            rank = 1
        },
    },
    [30] = {
        [1042] = {
            cost = 11000,
            rank = 5,
            requires = {639}
        },
        [2800] = {
            cost = 11000,
            rank = 2,
            requires = {633}
        },
        [10291] = {
            cost = 11000,
            rank = 4,
            requires = {10290}
        },
        [19752] = {
            cost = 11000,
            rank = nil
        },
        [20116] = {
            cost = 200,
            rank = 2,
            requires = {26573}
        },
        [20165] = {
            cost = 11000,
            rank = 1
        },
        [20915] = {
            cost = 550,
            rank = 2,
            requires = {20375}
        },
    },
    [32] = {
        [19836] = {
            cost = 12000,
            rank = 4,
            requires = {19740}
        },
        [19888] = {
            cost = 12000,
            rank = 1
        },
        [20306] = {
            cost = 12000,
            rank = 4,
            requires = {21082}
        },
    },
    [34] = {
        [642] = {
            cost = 13000,
            rank = 1
        },
        [19852] = {
            cost = 13000,
            rank = 3
        },
        [19940] = {
            cost = 13000,
            rank = 3
        },
        [20290] = {
            cost = 13000,
            rank = 5,
            requires = {20287}
        },
    },
    [36] = {
        [5615] = {
            cost = 14000,
            rank = 3
        },
        [10299] = {
            cost = 14000,
            rank = 3
        },
        [10324] = {
            cost = 14000,
            rank = 3
        },
        [19891] = {
            cost = 14000,
            rank = 1
        },
    },
    [38] = {
        [3472] = {
            cost = 16000,
            rank = 6,
            requires = {639}
        },
        [5627] = {
            cost = 16000,
            rank = 2
        },
        [10278] = {
            cost = 16000,
            rank = 3,
            requires = {1022}
        },
        [20166] = {
            cost = 16000,
            rank = 1
        },
    },
    [40] = {
        [750] = {
            cost = 20000,
            rank = nil
        },
        [1032] = {
            cost = 20000,
            rank = 5,
            requires = {10290}
        },
        [5589] = {
            cost = 20000,
            rank = 3,
            requires = {853}
        },
        [19895] = {
            cost = 20000,
            rank = 2
        },
        [19977] = {
            cost = 20000,
            rank = 1
        },
        [20347] = {
            cost = 20000,
            rank = 2
        },
        [20912] = {
            cost = 1000,
            rank = 2,
            requires = {20911}
        },
        [20918] = {
            cost = 1000,
            rank = 3,
            requires = {20375}
        },
        [20922] = {
            cost = 1000,
            rank = 3,
            requires = {26573}
        },
    },
    [42] = {
        [4987] = {
            cost = 21000,
            rank = nil
        },
        [19837] = {
            cost = 21000,
            rank = 5,
            requires = {19740}
        },
        [19941] = {
            cost = 21000,
            rank = 4
        },
        [20291] = {
            cost = 21000,
            rank = 6,
            requires = {20287}
        },
        [20307] = {
            cost = 21000,
            rank = 5,
            requires = {21082}
        },
    },
    [44] = {
        [10312] = {
            cost = 22000,
            rank = 4
        },
        [19853] = {
            cost = 22000,
            rank = 4
        },
        [19897] = {
            cost = 22000,
            rank = 2
        },
        [24275] = {
            cost = 22000,
            rank = 1
        },
    },
    [46] = {
        [6940] = {
            cost = 24000,
            rank = 1
        },
        [10300] = {
            cost = 24000,
            rank = 4
        },
        [10328] = {
            cost = 24000,
            rank = 7,
            requires = {639}
        },
    },
    [48] = {
        [19899] = {
            cost = 26000,
            rank = 2
        },
        [20356] = {
            cost = 26000,
            rank = 2
        },
        [20772] = {
            cost = 26000,
            rank = 4
        },
        [20929] = {
            cost = 1300,
            rank = 2,
            requires = {20473}
        },
    },
    [50] = {
        [1020] = {
            cost = 28000,
            rank = 2
        },
        [2812] = {
            cost = 28000,
            rank = 1
        },
        [10292] = {
            cost = 28000,
            rank = 6,
            requires = {10290}
        },
        [10310] = {
            cost = 28000,
            rank = 3,
            requires = {633}
        },
        [19942] = {
            cost = 28000,
            rank = 5
        },
        [19978] = {
            cost = 28000,
            rank = 2
        },
        [20292] = {
            cost = 28000,
            rank = 7,
            requires = {20287}
        },
        [20348] = {
            cost = 28000,
            rank = 3
        },
        [20913] = {
            cost = 1400,
            rank = 3,
            requires = {20911}
        },
        [20919] = {
            cost = 1400,
            rank = 4,
            requires = {20375}
        },
        [20923] = {
            cost = 1400,
            rank = 4,
            requires = {26573}
        },
        [20927] = {
            cost = 1400,
            rank = 2,
            requires = {20925}
        },
    },
    [52] = {
        [10313] = {
            cost = 34000,
            rank = 5
        },
        [10326] = {
            cost = 34000,
            rank = 3
        },
        [19838] = {
            cost = 34000,
            rank = 6,
            requires = {19740}
        },
        [19896] = {
            cost = 34000,
            rank = 3
        },
        [20308] = {
            cost = 34000,
            rank = 6,
            requires = {21082}
        },
        [24274] = {
            cost = 34000,
            rank = 2
        },
        [25782] = {
            cost = 46000,
            rank = 1,
            requires = {19740}
        },
    },
    [54] = {
        [10308] = {
            cost = 40000,
            rank = 4,
            requires = {853}
        },
        [10329] = {
            cost = 40000,
            rank = 8,
            requires = {639}
        },
        [19854] = {
            cost = 40000,
            rank = 5
        },
        [20729] = {
            cost = 40000,
            rank = 2
        },
        [25894] = {
            cost = 46000,
            rank = 1
        },
    },
    [56] = {
        [10301] = {
            cost = 42000,
            rank = 5
        },
        [19898] = {
            cost = 42000,
            rank = 3
        },
        [20930] = {
            cost = 2100,
            rank = 3,
            requires = {20473}
        },
    },
    [58] = {
        [19943] = {
            cost = 44000,
            rank = 6
        },
        [20293] = {
            cost = 44000,
            rank = 8,
            requires = {20287}
        },
        [20357] = {
            cost = 44000,
            rank = 3
        },
    },
    [60] = {
        [10293] = {
            cost = 46000,
            rank = 7,
            requires = {10290}
        },
        [10314] = {
            cost = 46000,
            rank = 6
        },
        [10318] = {
            cost = 46000,
            rank = 2
        },
        [19900] = {
            cost = 46000,
            rank = 3
        },
        [19979] = {
            cost = 46000,
            rank = 3
        },
        [20349] = {
            cost = 46000,
            rank = 4
        },
        [20773] = {
            cost = 46000,
            rank = 5
        },
        [20914] = {
            cost = 2300,
            rank = 4,
            requires = {20911}
        },
        [20920] = {
            cost = 2300,
            rank = 5,
            requires = {20375}
        },
        [20924] = {
            cost = 2300,
            rank = 5,
            requires = {26573}
        },
        [20928] = {
            cost = 2300,
            rank = 3,
            requires = {20925}
        },
        [24239] = {
            cost = 46000,
            rank = 3
        },
        [25890] = {
            cost = 46000,
            rank = 1
        },
        [25895] = {
            cost = 46000,
            rank = nil
        },
        [25898] = {
            cost = 2300,
            rank = nil,
            requires = {20217}
        },
        [25899] = {
            cost = 2300,
            rank = 1,
            requires = {20911}
        },
        [25916] = {
            cost = 46000,
            rank = 2,
            requires = {19740}
        },
        [25918] = {
            cost = 46000,
            rank = 2
        },
    },
}
end
