local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.ROGUE = Trainer.Builtin.ROGUE or {
    [1] = {
        [1784] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [53] = {
            cost = 100,
            rank = 1
        },
        [921] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [1757] = {
            cost = 100,
            rank = 2,
            requires = {1759}
        },
        [1776] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [5277] = {
            cost = 200,
            rank = nil
        },
        [6760] = {
            cost = 200,
            rank = 2,
            requires = {6762}
        },
    },
    [10] = {
        [674] = {
            cost = 300,
            rank = nil
        },
        [2983] = {
            cost = 300,
            rank = 1
        },
        [5171] = {
            cost = 300,
            rank = 1
        },
        [6770] = {
            cost = 300,
            rank = 1
        },
    },
    [12] = {
        [1766] = {
            cost = 800,
            rank = 1
        },
        [2589] = {
            cost = 800,
            rank = 2,
            requires = {2590}
        },
        [3127] = {
            cost = 800,
            rank = nil
        },
    },
    [14] = {
        [703] = {
            cost = 1200,
            rank = 1
        },
        [1758] = {
            cost = 1200,
            rank = 3,
            requires = {1759}
        },
        [8647] = {
            cost = 1200,
            rank = 1
        },
    },
    [16] = {
        [1804] = {
            cost = 1800,
            rank = nil
        },
        [1966] = {
            cost = 1800,
            rank = 1
        },
        [6761] = {
            cost = 1800,
            rank = 3,
            requires = {6762}
        },
    },
    [18] = {
        [1777] = {
            cost = 2900,
            rank = 2,
            requires = {1777}
        },
        [8676] = {
            cost = 2900,
            rank = 1
        },
    },
    [20] = {
        [1785] = {
            cost = 3000,
            rank = 2,
            requires = {1785}
        },
        [1943] = {
            cost = 3000,
            rank = 1
        },
        [2590] = {
            cost = 3000,
            rank = 3,
            requires = {2590}
        },
        [2842] = {
            cost = 0,
            rank = nil
        },
    },
    [22] = {
        [1725] = {
            cost = 4000,
            rank = nil
        },
        [1759] = {
            cost = 4000,
            rank = 4,
            requires = {1759}
        },
        [1856] = {
            cost = 4000,
            rank = 1,
            requires = {1785}
        },
        [8631] = {
            cost = 4000,
            rank = 2,
            requires = {8631}
        },
    },
    [24] = {
        [2836] = {
            cost = 5000,
            rank = nil
        },
        [6762] = {
            cost = 5000,
            rank = 4,
            requires = {6762}
        },
    },
    [26] = {
        [1767] = {
            cost = 6000,
            rank = 2,
            requires = {1767}
        },
        [1833] = {
            cost = 6000,
            rank = nil
        },
        [8649] = {
            cost = 6000,
            rank = 2,
            requires = {8649}
        },
        [8724] = {
            cost = 6000,
            rank = 2,
            requires = {8724}
        },
    },
    [28] = {
        [2070] = {
            cost = 8000,
            rank = 2,
            requires = {6770}
        },
        [2591] = {
            cost = 8000,
            rank = 4,
            requires = {2590}
        },
        [6768] = {
            cost = 8000,
            rank = 2,
            requires = {1966}
        },
        [8639] = {
            cost = 8000,
            rank = 2,
            requires = {1943}
        },
    },
    [30] = {
        [408] = {
            cost = 10000,
            rank = 1
        },
        [1760] = {
            cost = 10000,
            rank = 5,
            requires = {1759}
        },
        [1842] = {
            cost = 10000,
            rank = nil,
            requires = {2836}
        },
        [8632] = {
            cost = 10000,
            rank = 3,
            requires = {8631}
        },
    },
    [32] = {
        [8623] = {
            cost = 12000,
            rank = 5,
            requires = {6762}
        },
        [8629] = {
            cost = 12000,
            rank = 3,
            requires = {1777}
        },
    },
    [34] = {
        [2094] = {
            cost = 14000,
            rank = nil,
            requires = {2842}
        },
        [8696] = {
            cost = 14000,
            rank = 2,
            requires = {2983}
        },
        [8725] = {
            cost = 14000,
            rank = 3,
            requires = {8724}
        },
    },
    [36] = {
        [8640] = {
            cost = 16000,
            rank = 3,
            requires = {1943}
        },
        [8650] = {
            cost = 16000,
            rank = 3,
            requires = {8649}
        },
        [8721] = {
            cost = 16000,
            rank = 5,
            requires = {2590}
        },
    },
    [38] = {
        [8621] = {
            cost = 18000,
            rank = 6,
            requires = {1759}
        },
        [8633] = {
            cost = 18000,
            rank = 4,
            requires = {8631}
        },
    },
    [40] = {
        [1786] = {
            cost = 20000,
            rank = 3,
            requires = {1785}
        },
        [1860] = {
            cost = 20000,
            rank = nil
        },
        [8624] = {
            cost = 20000,
            rank = 6,
            requires = {6762}
        },
        [8637] = {
            cost = 20000,
            rank = 3,
            requires = {1966}
        },
    },
    [42] = {
        [1768] = {
            cost = 27000,
            rank = 3,
            requires = {1767}
        },
        [1857] = {
            cost = 27000,
            rank = 2,
            requires = {1856}
        },
        [6774] = {
            cost = 27000,
            rank = 2,
            requires = {5171}
        },
        [11267] = {
            cost = 27000,
            rank = 4,
            requires = {8724}
        },
    },
    [44] = {
        [11273] = {
            cost = 29000,
            rank = 4,
            requires = {1943}
        },
        [11279] = {
            cost = 29000,
            rank = 6,
            requires = {2590}
        },
    },
    [46] = {
        [11197] = {
            cost = 31000,
            rank = 4,
            requires = {8649}
        },
        [11285] = {
            cost = 31000,
            rank = 4,
            requires = {1777}
        },
        [11289] = {
            cost = 31000,
            rank = 5,
            requires = {8631}
        },
        [11293] = {
            cost = 31000,
            rank = 7,
            requires = {1759}
        },
        [17347] = {
            cost = 7750,
            rank = 2,
            requires = {16511}
        },
    },
    [48] = {
        [11297] = {
            cost = 33000,
            rank = 3,
            requires = {6770}
        },
        [11299] = {
            cost = 33000,
            rank = 7,
            requires = {6762}
        },
    },
    [50] = {
        [8643] = {
            cost = 35000,
            rank = 2
        },
        [11268] = {
            cost = 35000,
            rank = 5,
            requires = {8724}
        },
    },
    [52] = {
        [11274] = {
            cost = 46000,
            rank = 5,
            requires = {1943}
        },
        [11280] = {
            cost = 46000,
            rank = 7,
            requires = {2590}
        },
        [11303] = {
            cost = 46000,
            rank = 4,
            requires = {1966}
        },
    },
    [54] = {
        [11290] = {
            cost = 48000,
            rank = 6,
            requires = {8631}
        },
        [11294] = {
            cost = 48000,
            rank = 8,
            requires = {1759}
        },
    },
    [56] = {
        [11198] = {
            cost = 50000,
            rank = 5,
            requires = {8649}
        },
        [11300] = {
            cost = 50000,
            rank = 8,
            requires = {6762}
        },
    },
    [58] = {
        [1769] = {
            cost = 52000,
            rank = 4,
            requires = {1767}
        },
        [11269] = {
            cost = 52000,
            rank = 6,
            requires = {8724}
        },
        [11305] = {
            cost = 52000,
            rank = 3,
            requires = {2983}
        },
        [17348] = {
            cost = 13000,
            rank = 3,
            requires = {16511}
        },
    },
    [60] = {
        [1787] = {
            cost = 54000,
            rank = 4,
            requires = {1785}
        },
        [11275] = {
            cost = 54000,
            rank = 6,
            requires = {1943}
        },
        [11281] = {
            cost = 54000,
            rank = 8,
            requires = {2590}
        },
        [11286] = {
            cost = 54000,
            rank = 5,
            requires = {1777}
        },
    },
}
end
