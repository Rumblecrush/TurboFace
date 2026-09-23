local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.SHAMAN = Trainer.Builtin.SHAMAN or {
    [1] = {
        [8017] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [8042] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [332] = {
            cost = 100,
            rank = 2,
            requires = {547}
        },
        [2484] = {
            cost = 100,
            rank = nil
        },
    },
    [8] = {
        [324] = {
            cost = 100,
            rank = 1
        },
        [529] = {
            cost = 100,
            rank = 2,
            requires = {529}
        },
        [5730] = {
            cost = 100,
            rank = 1
        },
        [8018] = {
            cost = 100,
            rank = 2,
            requires = {8018}
        },
        [8044] = {
            cost = 100,
            rank = 2,
            requires = {8044}
        },
    },
    [10] = {
        [8024] = {
            cost = 400,
            rank = 1
        },
        [8050] = {
            cost = 400,
            rank = 1
        },
        [8075] = {
            cost = 400,
            rank = 1
        },
    },
    [12] = {
        [370] = {
            cost = 800,
            rank = 1
        },
        [547] = {
            cost = 800,
            rank = 3,
            requires = {547}
        },
        [1535] = {
            cost = 800,
            rank = 1
        },
        [2008] = {
            cost = 800,
            rank = 1
        },
    },
    [14] = {
        [548] = {
            cost = 900,
            rank = 3,
            requires = {529}
        },
        [8045] = {
            cost = 900,
            rank = 3,
            requires = {8044}
        },
        [8154] = {
            cost = 900,
            rank = 2,
            requires = {8071}
        },
    },
    [16] = {
        [325] = {
            cost = 1800,
            rank = 2,
            requires = {324}
        },
        [526] = {
            cost = 1800,
            rank = nil
        },
        [8019] = {
            cost = 1800,
            rank = 3,
            requires = {8018}
        },
    },
    [18] = {
        [913] = {
            cost = 2000,
            rank = 4,
            requires = {547}
        },
        [6390] = {
            cost = 2000,
            rank = 2,
            requires = {5730}
        },
        [8027] = {
            cost = 2000,
            rank = 2,
            requires = {8024}
        },
        [8052] = {
            cost = 2000,
            rank = 2,
            requires = {8050}
        },
        [8143] = {
            cost = 2000,
            rank = nil
        },
    },
    [20] = {
        [915] = {
            cost = 2200,
            rank = 4,
            requires = {529}
        },
        [2645] = {
            cost = 2200,
            rank = nil
        },
        [6363] = {
            cost = 2200,
            rank = 2,
            requires = {3599}
        },
        [8004] = {
            cost = 2200,
            rank = 1
        },
        [8033] = {
            cost = 2200,
            rank = 1
        },
        [8056] = {
            cost = 2200,
            rank = 1
        },
    },
    [22] = {
        [131] = {
            cost = 3000,
            rank = nil
        },
        [2870] = {
            cost = 3000,
            rank = nil
        },
        [8166] = {
            cost = 3000,
            rank = nil
        },
        [8498] = {
            cost = 3000,
            rank = 2,
            requires = {1535}
        },
    },
    [24] = {
        [905] = {
            cost = 3500,
            rank = 3,
            requires = {324}
        },
        [939] = {
            cost = 3500,
            rank = 5,
            requires = {547}
        },
        [8046] = {
            cost = 3500,
            rank = 4,
            requires = {8044}
        },
        [8155] = {
            cost = 3500,
            rank = 3,
            requires = {8071}
        },
        [8160] = {
            cost = 3500,
            rank = 2,
            requires = {8075}
        },
        [8181] = {
            cost = 3500,
            rank = 1
        },
        [10399] = {
            cost = 3500,
            rank = 4,
            requires = {8018}
        },
        [20609] = {
            cost = 3500,
            rank = 2
        },
    },
    [26] = {
        [943] = {
            cost = 4000,
            rank = 5,
            requires = {529}
        },
        [5675] = {
            cost = 4000,
            rank = 1
        },
        [6196] = {
            cost = 4000,
            rank = nil
        },
        [8030] = {
            cost = 4000,
            rank = 3,
            requires = {8024}
        },
        [8190] = {
            cost = 4000,
            rank = 1
        },
    },
    [28] = {
        [546] = {
            cost = 6000,
            rank = nil
        },
        [6391] = {
            cost = 6000,
            rank = 3,
            requires = {5730}
        },
        [8008] = {
            cost = 6000,
            rank = 2
        },
        [8038] = {
            cost = 6000,
            rank = 2
        },
        [8053] = {
            cost = 6000,
            rank = 3,
            requires = {8050}
        },
        [8184] = {
            cost = 6000,
            rank = 1
        },
        [8227] = {
            cost = 6000,
            rank = 1
        },
    },
    [30] = {
        [556] = {
            cost = 7000,
            rank = nil
        },
        [6364] = {
            cost = 7000,
            rank = 3,
            requires = {3599}
        },
        [6375] = {
            cost = 7000,
            rank = 2
        },
        [8177] = {
            cost = 7000,
            rank = nil
        },
        [8232] = {
            cost = 7000,
            rank = 1
        },
        [10595] = {
            cost = 7000,
            rank = 1
        },
        [20608] = {
            cost = 7000,
            rank = nil
        },
    },
    [32] = {
        [421] = {
            cost = 8000,
            rank = 1
        },
        [945] = {
            cost = 8000,
            rank = 4,
            requires = {324}
        },
        [959] = {
            cost = 8000,
            rank = 6,
            requires = {547}
        },
        [6041] = {
            cost = 8000,
            rank = 6,
            requires = {529}
        },
        [8012] = {
            cost = 8000,
            rank = 2,
            requires = {370}
        },
        [8499] = {
            cost = 8000,
            rank = 3,
            requires = {1535}
        },
        [8512] = {
            cost = 8000,
            rank = 1
        },
    },
    [34] = {
        [6495] = {
            cost = 9000,
            rank = nil
        },
        [8058] = {
            cost = 9000,
            rank = 2
        },
        [10406] = {
            cost = 9000,
            rank = 4,
            requires = {8071}
        },
        [16314] = {
            cost = 9000,
            rank = 5,
            requires = {8018}
        },
    },
    [36] = {
        [8010] = {
            cost = 10000,
            rank = 3
        },
        [10412] = {
            cost = 10000,
            rank = 5,
            requires = {8044}
        },
        [10495] = {
            cost = 10000,
            rank = 2
        },
        [10585] = {
            cost = 10000,
            rank = 2
        },
        [15107] = {
            cost = 10000,
            rank = 1
        },
        [16339] = {
            cost = 10000,
            rank = 4,
            requires = {8024}
        },
        [20610] = {
            cost = 10000,
            rank = 3
        },
    },
    [38] = {
        [6392] = {
            cost = 11000,
            rank = 4,
            requires = {5730}
        },
        [8161] = {
            cost = 11000,
            rank = 3,
            requires = {8075}
        },
        [8170] = {
            cost = 11000,
            rank = nil
        },
        [8249] = {
            cost = 11000,
            rank = 2
        },
        [10391] = {
            cost = 11000,
            rank = 7,
            requires = {529}
        },
        [10456] = {
            cost = 11000,
            rank = 3
        },
        [10478] = {
            cost = 11000,
            rank = 2
        },
    },
    [40] = {
        [930] = {
            cost = 12000,
            rank = 2
        },
        [1064] = {
            cost = 12000,
            rank = 1
        },
        [6365] = {
            cost = 12000,
            rank = 4,
            requires = {3599}
        },
        [6377] = {
            cost = 12000,
            rank = 3
        },
        [8005] = {
            cost = 12000,
            rank = 7,
            requires = {547}
        },
        [8134] = {
            cost = 12000,
            rank = 5,
            requires = {324}
        },
        [8235] = {
            cost = 12000,
            rank = 2
        },
        [8737] = {
            cost = 12000,
            rank = nil
        },
        [10447] = {
            cost = 12000,
            rank = 4,
            requires = {8050}
        },
    },
    [42] = {
        [8835] = {
            cost = 16000,
            rank = 1
        },
        [10537] = {
            cost = 16000,
            rank = 2
        },
        [10613] = {
            cost = 16000,
            rank = 2
        },
        [11314] = {
            cost = 16000,
            rank = 4,
            requires = {1535}
        },
    },
    [44] = {
        [10392] = {
            cost = 18000,
            rank = 8,
            requires = {529}
        },
        [10407] = {
            cost = 18000,
            rank = 5,
            requires = {8071}
        },
        [10466] = {
            cost = 18000,
            rank = 4
        },
        [10600] = {
            cost = 18000,
            rank = 2
        },
        [16315] = {
            cost = 18000,
            rank = 6,
            requires = {8018}
        },
    },
    [46] = {
        [10472] = {
            cost = 20000,
            rank = 3
        },
        [10496] = {
            cost = 20000,
            rank = 3
        },
        [10586] = {
            cost = 20000,
            rank = 3
        },
        [10622] = {
            cost = 20000,
            rank = 2
        },
        [15111] = {
            cost = 20000,
            rank = 2
        },
        [16341] = {
            cost = 20000,
            rank = 5,
            requires = {8024}
        },
    },
    [48] = {
        [2860] = {
            cost = 22000,
            rank = 3
        },
        [10395] = {
            cost = 22000,
            rank = 8,
            requires = {547}
        },
        [10413] = {
            cost = 22000,
            rank = 6,
            requires = {8044}
        },
        [10427] = {
            cost = 22000,
            rank = 5,
            requires = {5730}
        },
        [10431] = {
            cost = 22000,
            rank = 6,
            requires = {324}
        },
        [10526] = {
            cost = 22000,
            rank = 3
        },
        [16355] = {
            cost = 22000,
            rank = 4
        },
        [17354] = {
            cost = 1100,
            rank = 2,
            requires = {16190}
        },
        [20776] = {
            cost = 22000,
            rank = 4
        },
    },
    [50] = {
        [10437] = {
            cost = 24000,
            rank = 5,
            requires = {3599}
        },
        [10462] = {
            cost = 24000,
            rank = 4
        },
        [10486] = {
            cost = 24000,
            rank = 3
        },
        [15207] = {
            cost = 24000,
            rank = 9,
            requires = {529}
        },
        [25908] = {
            cost = 24000,
            rank = nil
        },
    },
    [52] = {
        [10442] = {
            cost = 27000,
            rank = 4,
            requires = {8075}
        },
        [10448] = {
            cost = 27000,
            rank = 5,
            requires = {8050}
        },
        [10467] = {
            cost = 27000,
            rank = 5
        },
        [10614] = {
            cost = 27000,
            rank = 3
        },
        [11315] = {
            cost = 27000,
            rank = 5,
            requires = {1535}
        },
    },
    [54] = {
        [10408] = {
            cost = 29000,
            rank = 6,
            requires = {8071}
        },
        [10479] = {
            cost = 29000,
            rank = 3
        },
        [10623] = {
            cost = 29000,
            rank = 3
        },
        [16316] = {
            cost = 29000,
            rank = 7,
            requires = {8018}
        },
    },
    [56] = {
        [10396] = {
            cost = 30000,
            rank = 9,
            requires = {547}
        },
        [10432] = {
            cost = 30000,
            rank = 7,
            requires = {324}
        },
        [10497] = {
            cost = 30000,
            rank = 4
        },
        [10587] = {
            cost = 30000,
            rank = 4
        },
        [10605] = {
            cost = 30000,
            rank = 4
        },
        [10627] = {
            cost = 30000,
            rank = 2
        },
        [15112] = {
            cost = 30000,
            rank = 3
        },
        [15208] = {
            cost = 30000,
            rank = 10,
            requires = {529}
        },
        [16342] = {
            cost = 30000,
            rank = 6,
            requires = {8024}
        },
    },
    [58] = {
        [10428] = {
            cost = 32000,
            rank = 6,
            requires = {5730}
        },
        [10473] = {
            cost = 32000,
            rank = 4
        },
        [10538] = {
            cost = 32000,
            rank = 3
        },
        [16356] = {
            cost = 32000,
            rank = 5
        },
        [16387] = {
            cost = 32000,
            rank = 4
        },
        [17359] = {
            cost = 1600,
            rank = 3,
            requires = {16190}
        },
    },
    [60] = {
        [10414] = {
            cost = 34000,
            rank = 7,
            requires = {8044}
        },
        [10438] = {
            cost = 34000,
            rank = 6,
            requires = {3599}
        },
        [10463] = {
            cost = 34000,
            rank = 5
        },
        [10468] = {
            cost = 34000,
            rank = 6
        },
        [10601] = {
            cost = 34000,
            rank = 3
        },
        [16362] = {
            cost = 34000,
            rank = 4
        },
        [20777] = {
            cost = 34000,
            rank = 5
        },
    },
}
end
