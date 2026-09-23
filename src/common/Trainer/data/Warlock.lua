local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.WARLOCK = Trainer.Builtin.WARLOCK or {
    [1] = {
        [348] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [172] = {
            cost = 100,
            rank = 1
        },
        [702] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [695] = {
            cost = 100,
            rank = 2,
            requires = {1088}
        },
        [1454] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [980] = {
            cost = 200,
            rank = 1
        },
        [5782] = {
            cost = 200,
            rank = 1
        },
    },
    [10] = {
        [696] = {
            cost = 300,
            rank = 2,
            requires = {696}
        },
        [707] = {
            cost = 300,
            rank = 2,
            requires = {1094}
        },
        [1120] = {
            cost = 300,
            rank = 1
        },
        [6201] = {
            cost = 300,
            rank = nil,
            requires = {1120}
        },
    },
    [12] = {
        [705] = {
            cost = 600,
            rank = 3,
            requires = {1088}
        },
        [755] = {
            cost = 600,
            rank = 1
        },
        [1108] = {
            cost = 600,
            rank = 2,
            requires = {702}
        },
    },
    [14] = {
        [689] = {
            cost = 900,
            rank = 1
        },
        [704] = {
            cost = 900,
            rank = 1
        },
        [6222] = {
            cost = 900,
            rank = 2,
            requires = {6222}
        },
    },
    [16] = {
        [1455] = {
            cost = 1200,
            rank = 2,
            requires = {1455}
        },
        [5697] = {
            cost = 1200,
            rank = nil
        },
    },
    [18] = {
        [693] = {
            cost = 1500,
            rank = nil,
            requires = {1120}
        },
        [1014] = {
            cost = 1500,
            rank = 2,
            requires = {1014}
        },
        [5676] = {
            cost = 1500,
            rank = 1
        },
    },
    [20] = {
        [698] = {
            cost = 2000,
            rank = nil
        },
        [706] = {
            cost = 2000,
            rank = 1
        },
        [1088] = {
            cost = 2000,
            rank = 4,
            requires = {1088}
        },
        [1094] = {
            cost = 2000,
            rank = 3,
            requires = {1094}
        },
        [3698] = {
            cost = 2000,
            rank = 2,
            requires = {3698}
        },
        [5740] = {
            cost = 2000,
            rank = 1
        },
    },
    [22] = {
        [126] = {
            cost = 2500,
            rank = nil
        },
        [699] = {
            cost = 2500,
            rank = 2,
            requires = {689}
        },
        [6202] = {
            cost = 2500,
            rank = nil,
            requires = {6201}
        },
        [6205] = {
            cost = 2500,
            rank = 3,
            requires = {702}
        },
    },
    [24] = {
        [5138] = {
            cost = 3000,
            rank = 1
        },
        [5500] = {
            cost = 3000,
            rank = nil
        },
        [6223] = {
            cost = 3000,
            rank = 3,
            requires = {6222}
        },
        [8288] = {
            cost = 3000,
            rank = 2,
            requires = {1120}
        },
        [18867] = {
            cost = 150,
            rank = 2,
            requires = {17877}
        },
    },
    [26] = {
        [132] = {
            cost = 4000,
            rank = nil
        },
        [1456] = {
            cost = 4000,
            rank = 3,
            requires = {1455}
        },
        [1714] = {
            cost = 4000,
            rank = 1
        },
        [17919] = {
            cost = 4000,
            rank = 2,
            requires = {5676}
        },
    },
    [28] = {
        [710] = {
            cost = 5000,
            rank = 1
        },
        [1106] = {
            cost = 5000,
            rank = 5,
            requires = {1088}
        },
        [3699] = {
            cost = 5000,
            rank = 3,
            requires = {3698}
        },
        [6217] = {
            cost = 5000,
            rank = 3,
            requires = {1014}
        },
        [6366] = {
            cost = 5000,
            rank = nil
        },
        [7658] = {
            cost = 5000,
            rank = 2
        },
    },
    [30] = {
        [709] = {
            cost = 6000,
            rank = 3,
            requires = {689}
        },
        [1086] = {
            cost = 6000,
            rank = 2,
            requires = {706}
        },
        [1098] = {
            cost = 6000,
            rank = 1
        },
        [1949] = {
            cost = 6000,
            rank = 1
        },
        [2941] = {
            cost = 6000,
            rank = 4,
            requires = {1094}
        },
        [20752] = {
            cost = 6000,
            rank = nil
        },
    },
    [32] = {
        [1490] = {
            cost = 7000,
            rank = 1
        },
        [6213] = {
            cost = 7000,
            rank = 2,
            requires = {5782}
        },
        [6229] = {
            cost = 7000,
            rank = 1
        },
        [7646] = {
            cost = 7000,
            rank = 4,
            requires = {702}
        },
        [18868] = {
            cost = 350,
            rank = 3,
            requires = {17877}
        },
    },
    [34] = {
        [5699] = {
            cost = 8000,
            rank = nil
        },
        [6219] = {
            cost = 8000,
            rank = 2,
            requires = {5740}
        },
        [6226] = {
            cost = 8000,
            rank = 2
        },
        [7648] = {
            cost = 8000,
            rank = 4,
            requires = {6222}
        },
        [17920] = {
            cost = 8000,
            rank = 3,
            requires = {5676}
        },
    },
    [36] = {
        [2362] = {
            cost = 9000,
            rank = nil,
            requires = {1120}
        },
        [3700] = {
            cost = 9000,
            rank = 4,
            requires = {3698}
        },
        [7641] = {
            cost = 9000,
            rank = 6,
            requires = {1088}
        },
        [11687] = {
            cost = 9000,
            rank = 4,
            requires = {1455}
        },
        [17951] = {
            cost = 9000,
            rank = nil
        },
    },
    [38] = {
        [2970] = {
            cost = 10000,
            rank = nil
        },
        [7651] = {
            cost = 10000,
            rank = 4,
            requires = {689}
        },
        [8289] = {
            cost = 10000,
            rank = 3,
            requires = {1120}
        },
        [11711] = {
            cost = 10000,
            rank = 4,
            requires = {1014}
        },
        [18879] = {
            cost = 500,
            rank = 2,
            requires = {18265}
        },
    },
    [40] = {
        [5484] = {
            cost = 11000,
            rank = 1
        },
        [11665] = {
            cost = 11000,
            rank = 5,
            requires = {1094}
        },
        [11733] = {
            cost = 11000,
            rank = 3,
            requires = {706}
        },
        [18869] = {
            cost = 550,
            rank = 4,
            requires = {17877}
        },
        [20755] = {
            cost = 11000,
            rank = nil
        },
    },
    [42] = {
        [6789] = {
            cost = 11000,
            rank = 1
        },
        [7659] = {
            cost = 11000,
            rank = 3
        },
        [11683] = {
            cost = 11000,
            rank = 2
        },
        [11707] = {
            cost = 11000,
            rank = 5,
            requires = {702}
        },
        [11739] = {
            cost = 11000,
            rank = 2
        },
        [17921] = {
            cost = 11000,
            rank = 4,
            requires = {5676}
        },
    },
    [44] = {
        [11659] = {
            cost = 12000,
            rank = 7,
            requires = {1088}
        },
        [11671] = {
            cost = 12000,
            rank = 5,
            requires = {6222}
        },
        [11693] = {
            cost = 12000,
            rank = 5,
            requires = {3698}
        },
        [11703] = {
            cost = 12000,
            rank = 3
        },
        [11725] = {
            cost = 12000,
            rank = 2
        },
        [17862] = {
            cost = 12000,
            rank = 1
        },
    },
    [46] = {
        [11677] = {
            cost = 13000,
            rank = 3,
            requires = {5740}
        },
        [11688] = {
            cost = 13000,
            rank = 5,
            requires = {1455}
        },
        [11699] = {
            cost = 13000,
            rank = 5,
            requires = {689}
        },
        [11721] = {
            cost = 13000,
            rank = 2
        },
        [11729] = {
            cost = 13000,
            rank = nil
        },
        [17952] = {
            cost = 13000,
            rank = nil
        },
    },
    [48] = {
        [6353] = {
            cost = 14000,
            rank = 1
        },
        [11712] = {
            cost = 14000,
            rank = 5,
            requires = {1014}
        },
        [17727] = {
            cost = 14000,
            rank = nil
        },
        [18647] = {
            cost = 14000,
            rank = 2
        },
        [18870] = {
            cost = 700,
            rank = 5,
            requires = {17877}
        },
        [18880] = {
            cost = 700,
            rank = 3,
            requires = {18265}
        },
        [18930] = {
            cost = 700,
            rank = 2,
            requires = {17962}
        },
    },
    [50] = {
        [11667] = {
            cost = 15000,
            rank = 6,
            requires = {1094}
        },
        [11719] = {
            cost = 15000,
            rank = 2
        },
        [11734] = {
            cost = 15000,
            rank = 4,
            requires = {706}
        },
        [11743] = {
            cost = 15000,
            rank = nil
        },
        [17922] = {
            cost = 15000,
            rank = 5,
            requires = {5676}
        },
        [17925] = {
            cost = 15000,
            rank = 2
        },
        [18937] = {
            cost = 750,
            rank = 2,
            requires = {18220}
        },
        [20756] = {
            cost = 15000,
            rank = nil
        },
    },
    [52] = {
        [11660] = {
            cost = 18000,
            rank = 8,
            requires = {1088}
        },
        [11675] = {
            cost = 18000,
            rank = 4,
            requires = {1120}
        },
        [11694] = {
            cost = 18000,
            rank = 6,
            requires = {3698}
        },
        [11708] = {
            cost = 18000,
            rank = 6,
            requires = {702}
        },
        [11740] = {
            cost = 18000,
            rank = 3
        },
    },
    [54] = {
        [11672] = {
            cost = 20000,
            rank = 6,
            requires = {6222}
        },
        [11684] = {
            cost = 20000,
            rank = 3
        },
        [11700] = {
            cost = 20000,
            rank = 6,
            requires = {689}
        },
        [11704] = {
            cost = 20000,
            rank = 4
        },
        [17928] = {
            cost = 20000,
            rank = 2
        },
        [18931] = {
            cost = 1000,
            rank = 3,
            requires = {17962}
        },
    },
    [56] = {
        [6215] = {
            cost = 22000,
            rank = 3,
            requires = {5782}
        },
        [11689] = {
            cost = 22000,
            rank = 6,
            requires = {1455}
        },
        [11717] = {
            cost = 22000,
            rank = 4
        },
        [17924] = {
            cost = 22000,
            rank = 2
        },
        [17937] = {
            cost = 22000,
            rank = 2
        },
        [17953] = {
            cost = 22000,
            rank = nil
        },
        [18871] = {
            cost = 1100,
            rank = 6,
            requires = {17877}
        },
    },
    [58] = {
        [11678] = {
            cost = 24000,
            rank = 4,
            requires = {5740}
        },
        [11713] = {
            cost = 24000,
            rank = 6,
            requires = {1014}
        },
        [11726] = {
            cost = 24000,
            rank = 3
        },
        [11730] = {
            cost = 24000,
            rank = nil
        },
        [17923] = {
            cost = 24000,
            rank = 6,
            requires = {5676}
        },
        [17926] = {
            cost = 24000,
            rank = 3
        },
        [18881] = {
            cost = 1200,
            rank = 4,
            requires = {18265}
        },
    },
    [60] = {
        [603] = {
            cost = 26000,
            rank = nil
        },
        [11661] = {
            cost = 26000,
            rank = 9,
            requires = {1088}
        },
        [11668] = {
            cost = 26000,
            rank = 7,
            requires = {1094}
        },
        [11695] = {
            cost = 26000,
            rank = 7,
            requires = {3698}
        },
        [11722] = {
            cost = 26000,
            rank = 3
        },
        [11735] = {
            cost = 26000,
            rank = 5,
            requires = {706}
        },
        [17728] = {
            cost = 26000,
            rank = nil
        },
        [18932] = {
            cost = 1300,
            rank = 4,
            requires = {17962}
        },
        [18938] = {
            cost = 1300,
            rank = 3,
            requires = {18220}
        },
        [20757] = {
            cost = 26000,
            rank = nil
        },
    },
}
end
