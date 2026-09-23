local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.WARRIOR = Trainer.Builtin.WARRIOR or {
    [1] = {
        [6673] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [100] = {
            cost = 100,
            rank = 1
        },
        [772] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [3127] = {
            cost = 100,
            rank = nil
        },
        [6343] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [284] = {
            cost = 200,
            rank = 2,
            requires = {284}
        },
        [1715] = {
            cost = 200,
            rank = 1
        },
    },
    [10] = {
        [2687] = {
            cost = 600,
            rank = nil
        },
        [6546] = {
            cost = 600,
            rank = 2,
            requires = {772}
        },
    },
    [12] = {
        [72] = {
            cost = 1000,
            rank = 1
        },
        [5242] = {
            cost = 1000,
            rank = 2,
            requires = {6673}
        },
        [7384] = {
            cost = 1000,
            rank = 1
        },
    },
    [14] = {
        [1160] = {
            cost = 1500,
            rank = 1
        },
        [6572] = {
            cost = 1500,
            rank = 1
        },
    },
    [16] = {
        [285] = {
            cost = 2000,
            rank = 3,
            requires = {284}
        },
        [694] = {
            cost = 2000,
            rank = 1
        },
        [2565] = {
            cost = 2000,
            rank = nil
        },
    },
    [18] = {
        [676] = {
            cost = 3000,
            rank = nil
        },
        [8198] = {
            cost = 3000,
            rank = 2,
            requires = {6343}
        },
    },
    [20] = {
        [674] = {
            cost = 4000,
            rank = nil
        },
        [845] = {
            cost = 4000,
            rank = 1
        },
        [6547] = {
            cost = 4000,
            rank = 3,
            requires = {772}
        },
        [20230] = {
            cost = 4000,
            rank = nil
        },
    },
    [22] = {
        [5246] = {
            cost = 6000,
            rank = nil
        },
        [6192] = {
            cost = 6000,
            rank = 3,
            requires = {6673}
        },
        [7405] = {
            cost = 6000,
            rank = 2
        },
    },
    [24] = {
        [1608] = {
            cost = 8000,
            rank = 4,
            requires = {284}
        },
        [5308] = {
            cost = 8000,
            rank = 1
        },
        [6190] = {
            cost = 8000,
            rank = 2
        },
        [6574] = {
            cost = 8000,
            rank = 2
        },
    },
    [26] = {
        [1161] = {
            cost = 10000,
            rank = nil
        },
        [6178] = {
            cost = 10000,
            rank = 2,
            requires = {100}
        },
        [7400] = {
            cost = 10000,
            rank = 2
        },
    },
    [28] = {
        [871] = {
            cost = 11000,
            rank = nil
        },
        [7887] = {
            cost = 11000,
            rank = 2
        },
        [8204] = {
            cost = 11000,
            rank = 3,
            requires = {6343}
        },
    },
    [30] = {
        [1464] = {
            cost = 12000,
            rank = 1
        },
        [6548] = {
            cost = 12000,
            rank = 4,
            requires = {772}
        },
        [7369] = {
            cost = 12000,
            rank = 2
        },
    },
    [32] = {
        [1671] = {
            cost = 14000,
            rank = 2
        },
        [7372] = {
            cost = 14000,
            rank = 2,
            requires = {1715}
        },
        [11549] = {
            cost = 14000,
            rank = 4,
            requires = {6673}
        },
        [11564] = {
            cost = 14000,
            rank = 5,
            requires = {284}
        },
        [18499] = {
            cost = 14000,
            rank = nil
        },
        [20658] = {
            cost = 14000,
            rank = 2
        },
    },
    [34] = {
        [7379] = {
            cost = 16000,
            rank = 3
        },
        [8380] = {
            cost = 16000,
            rank = 3
        },
        [11554] = {
            cost = 16000,
            rank = 3
        },
    },
    [36] = {
        [1680] = {
            cost = 18000,
            rank = nil
        },
        [7402] = {
            cost = 18000,
            rank = 3
        },
    },
    [38] = {
        [6552] = {
            cost = 20000,
            rank = 1
        },
        [8205] = {
            cost = 20000,
            rank = 4,
            requires = {6343}
        },
        [8820] = {
            cost = 20000,
            rank = 2
        },
    },
    [40] = {
        [750] = {
            cost = 22000,
            rank = nil
        },
        [11565] = {
            cost = 22000,
            rank = 6,
            requires = {284}
        },
        [11572] = {
            cost = 22000,
            rank = 5,
            requires = {772}
        },
        [11608] = {
            cost = 22000,
            rank = 3
        },
        [20660] = {
            cost = 22000,
            rank = 3
        },
    },
    [42] = {
        [11550] = {
            cost = 32000,
            rank = 5,
            requires = {6673}
        },
        [20616] = {
            cost = 32000,
            rank = 2
        },
    },
    [44] = {
        [11555] = {
            cost = 34000,
            rank = 4
        },
        [11584] = {
            cost = 34000,
            rank = 3
        },
        [11600] = {
            cost = 34000,
            rank = 4
        },
    },
    [46] = {
        [11578] = {
            cost = 36000,
            rank = 3,
            requires = {100}
        },
        [11596] = {
            cost = 36000,
            rank = 4
        },
        [11604] = {
            cost = 36000,
            rank = 3
        },
        [20559] = {
            cost = 36000,
            rank = 4
        },
    },
    [48] = {
        [11566] = {
            cost = 40000,
            rank = 7,
            requires = {284}
        },
        [11580] = {
            cost = 40000,
            rank = 5,
            requires = {6343}
        },
        [20661] = {
            cost = 40000,
            rank = 4
        },
        [21551] = {
            cost = 2000,
            rank = 2,
            requires = {12294}
        },
        [23892] = {
            cost = 2000,
            rank = 2,
            requires = {23881}
        },
        [23923] = {
            cost = 2000,
            rank = 2,
            requires = {23922}
        },
    },
    [50] = {
        [1719] = {
            cost = 42000,
            rank = nil
        },
        [11573] = {
            cost = 42000,
            rank = 6,
            requires = {772}
        },
        [11609] = {
            cost = 42000,
            rank = 4
        },
    },
    [52] = {
        [1672] = {
            cost = 54000,
            rank = 3
        },
        [11551] = {
            cost = 54000,
            rank = 6,
            requires = {6673}
        },
        [20617] = {
            cost = 54000,
            rank = 3
        },
    },
    [54] = {
        [7373] = {
            cost = 56000,
            rank = 3,
            requires = {1715}
        },
        [11556] = {
            cost = 56000,
            rank = 5
        },
        [11601] = {
            cost = 56000,
            rank = 5
        },
        [11605] = {
            cost = 56000,
            rank = 4
        },
        [21552] = {
            cost = 2800,
            rank = 3,
            requires = {12294}
        },
        [23893] = {
            cost = 2800,
            rank = 3,
            requires = {23881}
        },
        [23924] = {
            cost = 2800,
            rank = 3,
            requires = {23922}
        },
    },
    [56] = {
        [11567] = {
            cost = 58000,
            rank = 8,
            requires = {284}
        },
        [20560] = {
            cost = 58000,
            rank = 5
        },
        [20662] = {
            cost = 58000,
            rank = 5
        },
    },
    [58] = {
        [6554] = {
            cost = 60000,
            rank = 2
        },
        [11581] = {
            cost = 60000,
            rank = 6,
            requires = {6343}
        },
        [11597] = {
            cost = 60000,
            rank = 5
        },
    },
    [60] = {
        [11574] = {
            cost = 62000,
            rank = 7,
            requires = {772}
        },
        [11585] = {
            cost = 62000,
            rank = 4
        },
        [20569] = {
            cost = 62000,
            rank = 5
        },
        [21553] = {
            cost = 3100,
            rank = 4,
            requires = {12294}
        },
        [23894] = {
            cost = 3100,
            rank = 4,
            requires = {23881}
        },
        [23925] = {
            cost = 3100,
            rank = 4,
            requires = {23922}
        },
    },
}
end
