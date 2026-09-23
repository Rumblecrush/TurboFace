local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.HUNTER = Trainer.Builtin.HUNTER or {
    [1] = {
        [1494] = {
            cost = 10,
            rank = nil
        },
    },
    [4] = {
        [1978] = {
            cost = 100,
            rank = 1
        },
        [13163] = {
            cost = 100,
            rank = nil
        },
    },
    [6] = {
        [1130] = {
            cost = 100,
            rank = 1
        },
        [3044] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [3127] = {
            cost = 200,
            rank = nil
        },
        [5116] = {
            cost = 200,
            rank = nil
        },
        [14260] = {
            cost = 200,
            rank = 2
        },
    },
    [10] = {
        [13165] = {
            cost = 400,
            rank = 1
        },
        [13549] = {
            cost = 400,
            rank = 2,
            requires = {13550}
        },
        [19883] = {
            cost = 400,
            rank = nil
        },
    },
    [12] = {
        [136] = {
            cost = 600,
            rank = 1,
            requires = {1515}
        },
        [2974] = {
            cost = 600,
            rank = 1
        },
        [14281] = {
            cost = 600,
            rank = 2,
            requires = {14282}
        },
        [20736] = {
            cost = 600,
            rank = 1
        },
    },
    [14] = {
        [1002] = {
            cost = 1200,
            rank = nil
        },
        [1513] = {
            cost = 1200,
            rank = 1
        },
        [6197] = {
            cost = 1200,
            rank = nil
        },
    },
    [16] = {
        [1495] = {
            cost = 1800,
            rank = 1
        },
        [13795] = {
            cost = 1800,
            rank = 1
        },
        [14261] = {
            cost = 1800,
            rank = 3,
            requires = {14261}
        },
    },
    [18] = {
        [2643] = {
            cost = 2000,
            rank = 1
        },
        [13550] = {
            cost = 2000,
            rank = 3,
            requires = {13550}
        },
        [14318] = {
            cost = 2000,
            rank = 2,
            requires = {14318}
        },
        [19884] = {
            cost = 2000,
            rank = nil
        },
    },
    [20] = {
        [674] = {
            cost = 2200,
            rank = nil
        },
        [781] = {
            cost = 2200,
            rank = 1
        },
        [1499] = {
            cost = 2200,
            rank = 1
        },
        [3111] = {
            cost = 2200,
            rank = 2,
            requires = {3111}
        },
        [5118] = {
            cost = 2200,
            rank = nil
        },
        [14274] = {
            cost = 2200,
            rank = 2,
            requires = {14274}
        },
        [14282] = {
            cost = 2200,
            rank = 3,
            requires = {14282}
        },
    },
    [22] = {
        [3043] = {
            cost = 6000,
            rank = 1
        },
        [14323] = {
            cost = 6000,
            rank = 2,
            requires = {14323}
        },
    },
    [24] = {
        [1462] = {
            cost = 7000,
            rank = nil
        },
        [14262] = {
            cost = 7000,
            rank = 4,
            requires = {14261}
        },
        [19885] = {
            cost = 7000,
            rank = nil
        },
    },
    [26] = {
        [3045] = {
            cost = 7000,
            rank = nil
        },
        [13551] = {
            cost = 7000,
            rank = 4,
            requires = {13550}
        },
        [14302] = {
            cost = 7000,
            rank = 2,
            requires = {13795}
        },
        [19880] = {
            cost = 7000,
            rank = nil
        },
    },
    [28] = {
        [3661] = {
            cost = 8000,
            rank = 3,
            requires = {3111}
        },
        [13809] = {
            cost = 8000,
            rank = nil
        },
        [14283] = {
            cost = 8000,
            rank = 4,
            requires = {14282}
        },
        [14319] = {
            cost = 8000,
            rank = 3,
            requires = {14318}
        },
        [20900] = {
            cost = 400,
            rank = 2,
            requires = {19434}
        },
    },
    [30] = {
        [5384] = {
            cost = 8000,
            rank = nil
        },
        [13161] = {
            cost = 8000,
            rank = nil
        },
        [14269] = {
            cost = 8000,
            rank = 2,
            requires = {1495}
        },
        [14288] = {
            cost = 8000,
            rank = 2,
            requires = {2643}
        },
        [14326] = {
            cost = 8000,
            rank = 2,
            requires = {1513}
        },
        [15629] = {
            cost = 8000,
            rank = 3,
            requires = {14274}
        },
    },
    [32] = {
        [1543] = {
            cost = 10000,
            rank = nil
        },
        [14263] = {
            cost = 10000,
            rank = 5,
            requires = {14261}
        },
        [14275] = {
            cost = 10000,
            rank = 2,
            requires = {3043}
        },
        [19878] = {
            cost = 10000,
            rank = nil
        },
    },
    [34] = {
        [13552] = {
            cost = 12000,
            rank = 5,
            requires = {13550}
        },
        [13813] = {
            cost = 12000,
            rank = 1
        },
        [14272] = {
            cost = 12000,
            rank = 2,
            requires = {781}
        },
    },
    [36] = {
        [3034] = {
            cost = 14000,
            rank = 1
        },
        [3662] = {
            cost = 14000,
            rank = 4,
            requires = {3111}
        },
        [14284] = {
            cost = 14000,
            rank = 5,
            requires = {14282}
        },
        [14303] = {
            cost = 14000,
            rank = 3,
            requires = {13795}
        },
        [20901] = {
            cost = 700,
            rank = 3,
            requires = {19434}
        },
    },
    [38] = {
        [14267] = {
            cost = 16000,
            rank = 2,
            requires = {2974}
        },
        [14320] = {
            cost = 16000,
            rank = 4,
            requires = {14318}
        },
    },
    [40] = {
        [1510] = {
            cost = 18000,
            rank = 1
        },
        [8737] = {
            cost = 18000,
            rank = nil
        },
        [13159] = {
            cost = 18000,
            rank = nil
        },
        [14264] = {
            cost = 18000,
            rank = 6,
            requires = {14261}
        },
        [14310] = {
            cost = 18000,
            rank = 2,
            requires = {1499}
        },
        [14324] = {
            cost = 18000,
            rank = 3,
            requires = {14323}
        },
        [15630] = {
            cost = 18000,
            rank = 4,
            requires = {14274}
        },
        [19882] = {
            cost = 18000,
            rank = nil
        },
    },
    [42] = {
        [13553] = {
            cost = 24000,
            rank = 6,
            requires = {13550}
        },
        [14276] = {
            cost = 24000,
            rank = 3,
            requires = {3043}
        },
        [14289] = {
            cost = 24000,
            rank = 3,
            requires = {2643}
        },
        [20909] = {
            cost = 1200,
            rank = 2,
            requires = {19306}
        },
    },
    [44] = {
        [13542] = {
            cost = 26000,
            rank = 5,
            requires = {3111}
        },
        [14270] = {
            cost = 26000,
            rank = 3,
            requires = {1495}
        },
        [14285] = {
            cost = 26000,
            rank = 6,
            requires = {14282}
        },
        [14316] = {
            cost = 26000,
            rank = 2
        },
        [20902] = {
            cost = 1300,
            rank = 4,
            requires = {19434}
        },
    },
    [46] = {
        [14279] = {
            cost = 28000,
            rank = 2
        },
        [14304] = {
            cost = 28000,
            rank = 4,
            requires = {13795}
        },
        [14327] = {
            cost = 28000,
            rank = 3,
            requires = {1513}
        },
        [20043] = {
            cost = 28000,
            rank = 1
        },
    },
    [48] = {
        [14265] = {
            cost = 32000,
            rank = 7,
            requires = {14261}
        },
        [14273] = {
            cost = 32000,
            rank = 3,
            requires = {781}
        },
        [14321] = {
            cost = 32000,
            rank = 5,
            requires = {14318}
        },
    },
    [50] = {
        [13554] = {
            cost = 36000,
            rank = 7,
            requires = {13550}
        },
        [14294] = {
            cost = 36000,
            rank = 2
        },
        [15631] = {
            cost = 36000,
            rank = 5,
            requires = {14274}
        },
        [19879] = {
            cost = 36000,
            rank = nil
        },
        [20905] = {
            cost = 1800,
            rank = 2,
            requires = {19506}
        },
        [24132] = {
            cost = 1800,
            rank = 2,
            requires = {19386}
        },
    },
    [52] = {
        [13543] = {
            cost = 40000,
            rank = 6,
            requires = {3111}
        },
        [14277] = {
            cost = 40000,
            rank = 4,
            requires = {3043}
        },
        [14286] = {
            cost = 40000,
            rank = 7,
            requires = {14282}
        },
        [20903] = {
            cost = 2000,
            rank = 5,
            requires = {19434}
        },
    },
    [54] = {
        [14290] = {
            cost = 42000,
            rank = 4,
            requires = {2643}
        },
        [14317] = {
            cost = 42000,
            rank = 3
        },
        [20910] = {
            cost = 2100,
            rank = 3,
            requires = {19306}
        },
    },
    [56] = {
        [14266] = {
            cost = 46000,
            rank = 8,
            requires = {14261}
        },
        [14280] = {
            cost = 46000,
            rank = 3
        },
        [14305] = {
            cost = 46000,
            rank = 5,
            requires = {13795}
        },
        [20190] = {
            cost = 46000,
            rank = 2
        },
    },
    [58] = {
        [13555] = {
            cost = 48000,
            rank = 8,
            requires = {13550}
        },
        [14271] = {
            cost = 48000,
            rank = 4,
            requires = {1495}
        },
        [14295] = {
            cost = 48000,
            rank = 3
        },
        [14322] = {
            cost = 48000,
            rank = 6,
            requires = {14318}
        },
        [14325] = {
            cost = 48000,
            rank = 4,
            requires = {14323}
        },
    },
    [60] = {
        [13544] = {
            cost = 50000,
            rank = 7,
            requires = {3111}
        },
        [14268] = {
            cost = 50000,
            rank = 3,
            requires = {2974}
        },
        [14287] = {
            cost = 50000,
            rank = 8,
            requires = {14282}
        },
        [14311] = {
            cost = 50000,
            rank = 3,
            requires = {1499}
        },
        [15632] = {
            cost = 50000,
            rank = 6,
            requires = {14274}
        },
        [20904] = {
            cost = 2500,
            rank = 6,
            requires = {19434}
        },
        [20906] = {
            cost = 2500,
            rank = 3,
            requires = {19506}
        },
        [24133] = {
            cost = 2500,
            rank = 3,
            requires = {19386}
        },
    },
}
end
