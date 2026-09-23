local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin = Trainer.Builtin or {}
Trainer.Builtin.MAGE = Trainer.Builtin.MAGE or {
    [1] = {
        [1459] = {
            cost = 10,
            rank = 1
        },
    },
    [4] = {
        [116] = {
            cost = 100,
            rank = 1
        },
        [5504] = {
            cost = 100,
            rank = 1
        },
    },
    [6] = {
        [143] = {
            cost = 100,
            rank = 2,
            requires = {143}
        },
        [587] = {
            cost = 100,
            rank = 1
        },
        [2136] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [118] = {
            cost = 200,
            rank = 1
        },
        [205] = {
            cost = 200,
            rank = 2,
            requires = {205}
        },
        [5143] = {
            cost = 200,
            rank = 1
        },
    },
    [10] = {
        [122] = {
            cost = 400,
            rank = 1
        },
        [5505] = {
            cost = 400,
            rank = 2,
            requires = {5504}
        },
        [7300] = {
            cost = 400,
            rank = 2,
            requires = {168}
        },
    },
    [12] = {
        [130] = {
            cost = 600,
            rank = nil
        },
        [145] = {
            cost = 600,
            rank = 3,
            requires = {143}
        },
        [597] = {
            cost = 600,
            rank = 2,
            requires = {587}
        },
        [604] = {
            cost = 600,
            rank = 1
        },
    },
    [14] = {
        [837] = {
            cost = 900,
            rank = 3,
            requires = {205}
        },
        [1449] = {
            cost = 900,
            rank = 1
        },
        [1460] = {
            cost = 900,
            rank = 2,
            requires = {1459}
        },
        [2137] = {
            cost = 900,
            rank = 2,
            requires = {2136}
        },
    },
    [16] = {
        [2120] = {
            cost = 1500,
            rank = 1
        },
        [2855] = {
            cost = 1500,
            rank = nil
        },
        [5144] = {
            cost = 1500,
            rank = 2,
            requires = {5143}
        },
    },
    [18] = {
        [475] = {
            cost = 1800,
            rank = nil
        },
        [1008] = {
            cost = 1800,
            rank = 1
        },
        [3140] = {
            cost = 1800,
            rank = 4,
            requires = {143}
        },
    },
    [20] = {
        [10] = {
            cost = 2000,
            rank = 1
        },
        [543] = {
            cost = 2000,
            rank = 1
        },
        [1463] = {
            cost = 2000,
            rank = 1
        },
        [1953] = {
            cost = 2000,
            rank = nil
        },
        [5506] = {
            cost = 2000,
            rank = 3,
            requires = {5504}
        },
        [7301] = {
            cost = 2000,
            rank = 3,
            requires = {168}
        },
        [7322] = {
            cost = 2000,
            rank = 4,
            requires = {205}
        },
        [12051] = {
            cost = 2000,
            rank = nil
        },
        [12824] = {
            cost = 2000,
            rank = 2,
            requires = {118}
        },
        [3561] = {
            cost = 2000,
            rank = nil,
            faction = "Alliance"
        },
        [3562] = {
            cost = 2000,
            rank = nil,
            faction = "Alliance"
        },
        [3563] = {
            cost = 2000,
            rank = nil,
            faction = "Horde"
        },
        [3567] = {
            cost = 2000,
            rank = nil,
            faction = "Horde"
        }
    },
    [22] = {
        [990] = {
            cost = 3000,
            rank = 3,
            requires = {587}
        },
        [2138] = {
            cost = 3000,
            rank = 3,
            requires = {2136}
        },
        [2948] = {
            cost = 3000,
            rank = 1
        },
        [6143] = {
            cost = 3000,
            rank = 1
        },
        [8437] = {
            cost = 3000,
            rank = 2
        },
    },
    [24] = {
        [2121] = {
            cost = 4000,
            rank = 2
        },
        [2139] = {
            cost = 4000,
            rank = nil
        },
        [5145] = {
            cost = 4000,
            rank = 3,
            requires = {5143}
        },
        [8400] = {
            cost = 4000,
            rank = 5,
            requires = {143}
        },
        [8450] = {
            cost = 4000,
            rank = 2
        },
        [12505] = {
            cost = 200,
            rank = 2,
            requires = {11366}
        },
    },
    [26] = {
        [120] = {
            cost = 5000,
            rank = 1
        },
        [865] = {
            cost = 5000,
            rank = 2
        },
        [8406] = {
            cost = 5000,
            rank = 5,
            requires = {205}
        },
    },
    [28] = {
        [759] = {
            cost = 7000,
            rank = nil
        },
        [1461] = {
            cost = 7000,
            rank = 3,
            requires = {1459}
        },
        [6141] = {
            cost = 7000,
            rank = 2
        },
        [8444] = {
            cost = 7000,
            rank = 2
        },
        [8494] = {
            cost = 7000,
            rank = 2
        },
    },
    [30] = {
        [6127] = {
            cost = 8000,
            rank = 4,
            requires = {5504}
        },
        [7302] = {
            cost = 8000,
            rank = 1
        },
        [8401] = {
            cost = 8000,
            rank = 6,
            requires = {143}
        },
        [8412] = {
            cost = 8000,
            rank = 4,
            requires = {2136}
        },
        [8438] = {
            cost = 8000,
            rank = 3
        },
        [8455] = {
            cost = 8000,
            rank = 2
        },
        [8457] = {
            cost = 8000,
            rank = 2
        },
        [12522] = {
            cost = 400,
            rank = 3,
            requires = {11366}
        },
        [3565] = {
            cost = 8000,
            rank = nil,
            faction = "Alliance"
        },
        [3566] = {
            cost = 8000,
            rank = nil,
            faction = "Horde"
        }
    },
    [32] = {
        [6129] = {
            cost = 10000,
            rank = 4,
            requires = {587}
        },
        [8407] = {
            cost = 10000,
            rank = 6,
            requires = {205}
        },
        [8416] = {
            cost = 10000,
            rank = 4,
            requires = {5143}
        },
        [8422] = {
            cost = 10000,
            rank = 3
        },
        [8461] = {
            cost = 10000,
            rank = 2
        },
    },
    [34] = {
        [6117] = {
            cost = 13000,
            rank = 1
        },
        [8445] = {
            cost = 12000,
            rank = 3
        },
        [8492] = {
            cost = 12000,
            rank = 2
        },
    },
    [36] = {
        [8402] = {
            cost = 13000,
            rank = 7,
            requires = {143}
        },
        [8427] = {
            cost = 13000,
            rank = 3
        },
        [8451] = {
            cost = 13000,
            rank = 3
        },
        [8495] = {
            cost = 13000,
            rank = 3
        },
        [12523] = {
            cost = 650,
            rank = 4,
            requires = {11366}
        },
        [13018] = {
            cost = 650,
            rank = 2,
            requires = {11113}
        },
    },
    [38] = {
        [3552] = {
            cost = 14000,
            rank = nil
        },
        [8408] = {
            cost = 14000,
            rank = 7,
            requires = {205}
        },
        [8413] = {
            cost = 14000,
            rank = 5,
            requires = {2136}
        },
        [8439] = {
            cost = 14000,
            rank = 4
        },
    },
    [40] = {
        [6131] = {
            cost = 15000,
            rank = 3
        },
        [7320] = {
            cost = 15000,
            rank = 2
        },
        [8417] = {
            cost = 15000,
            rank = 5,
            requires = {5143}
        },
        [8423] = {
            cost = 15000,
            rank = 4
        },
        [8446] = {
            cost = 15000,
            rank = 4
        },
        [8458] = {
            cost = 15000,
            rank = 3
        },
        [10138] = {
            cost = 15000,
            rank = 5,
            requires = {5504}
        },
        [12825] = {
            cost = 15000,
            rank = 3,
            requires = {118}
        },
        [10059] = {
            cost = 15000,
            rank = nil,
            faction = "Alliance"
        },
        [11416] = {
            cost = 15000,
            rank = nil,
            faction = "Alliance"
        },
        [11417] = {
            cost = 15000,
            rank = nil,
            faction = "Horde"
        },
        [11418] = {
            cost = 15000,
            rank = nil,
            faction = "Horde"
        },
    },
    [42] = {
        [8462] = {
            cost = 18000,
            rank = 3
        },
        [10144] = {
            cost = 18000,
            rank = 5,
            requires = {587}
        },
        [10148] = {
            cost = 18000,
            rank = 8,
            requires = {143}
        },
        [10156] = {
            cost = 18000,
            rank = 4,
            requires = {1459}
        },
        [10159] = {
            cost = 18000,
            rank = 3
        },
        [10169] = {
            cost = 18000,
            rank = 3
        },
        [12524] = {
            cost = 900,
            rank = 5,
            requires = {11366}
        },
    },
    [44] = {
        [10179] = {
            cost = 23000,
            rank = 8,
            requires = {205}
        },
        [10185] = {
            cost = 23000,
            rank = 4
        },
        [10191] = {
            cost = 23000,
            rank = 4
        },
        [13019] = {
            cost = 1150,
            rank = 3,
            requires = {11113}
        },
    },
    [46] = {
        [10197] = {
            cost = 26000,
            rank = 6,
            requires = {2136}
        },
        [10201] = {
            cost = 26000,
            rank = 5
        },
        [10205] = {
            cost = 26000,
            rank = 5
        },
        [13031] = {
            cost = 1300,
            rank = 2,
            requires = {11426}
        },
        [22782] = {
            cost = 28000,
            rank = 2
        },
    },
    [48] = {
        [10053] = {
            cost = 28000,
            rank = nil
        },
        [10149] = {
            cost = 28000,
            rank = 9,
            requires = {143}
        },
        [10173] = {
            cost = 28000,
            rank = 4
        },
        [10211] = {
            cost = 28000,
            rank = 6,
            requires = {5143}
        },
        [10215] = {
            cost = 28000,
            rank = 5
        },
        [12525] = {
            cost = 1400,
            rank = 6,
            requires = {11366}
        },
    },
    [50] = {
        [10139] = {
            cost = 32000,
            rank = 6,
            requires = {5504}
        },
        [10160] = {
            cost = 32000,
            rank = 4
        },
        [10180] = {
            cost = 32000,
            rank = 9,
            requires = {205}
        },
        [10219] = {
            cost = 32000,
            rank = 3
        },
        [10223] = {
            cost = 32000,
            rank = 4
        },
        [11419] = {
            cost = 32000,
            rank = nil,
            faction = "Alliance"
        },
        [11420] = {
            cost = 32000,
            rank = nil,
            faction = "Horde"
        }
    },
    [52] = {
        [10145] = {
            cost = 35000,
            rank = 6,
            requires = {587}
        },
        [10177] = {
            cost = 35000,
            rank = 4
        },
        [10186] = {
            cost = 35000,
            rank = 5
        },
        [10192] = {
            cost = 35000,
            rank = 5
        },
        [10206] = {
            cost = 35000,
            rank = 6
        },
        [13020] = {
            cost = 1750,
            rank = 4,
            requires = {11113}
        },
        [13032] = {
            cost = 1750,
            rank = 3,
            requires = {11426}
        },
    },
    [54] = {
        [10150] = {
            cost = 36000,
            rank = 10,
            requires = {143}
        },
        [10170] = {
            cost = 36000,
            rank = 4
        },
        [10199] = {
            cost = 36000,
            rank = 7,
            requires = {2136}
        },
        [10202] = {
            cost = 36000,
            rank = 6
        },
        [10230] = {
            cost = 36000,
            rank = 4
        },
        [12526] = {
            cost = 1800,
            rank = 7,
            requires = {11366}
        },
    },
    [56] = {
        [10157] = {
            cost = 38000,
            rank = 5,
            requires = {1459}
        },
        [10181] = {
            cost = 38000,
            rank = 10,
            requires = {205}
        },
        [10212] = {
            cost = 38000,
            rank = 7,
            requires = {5143}
        },
        [10216] = {
            cost = 38000,
            rank = 6
        },
    },
    [58] = {
        [10054] = {
            cost = 40000,
            rank = nil
        },
        [10161] = {
            cost = 40000,
            rank = 5
        },
        [10207] = {
            cost = 40000,
            rank = 7
        },
        [13033] = {
            cost = 2000,
            rank = 4,
            requires = {11426}
        },
        [22783] = {
            cost = 40000,
            rank = 3
        },
    },
    [60] = {
        [10151] = {
            cost = 42000,
            rank = 11,
            requires = {143}
        },
        [10174] = {
            cost = 42000,
            rank = 5
        },
        [10187] = {
            cost = 42000,
            rank = 6
        },
        [10193] = {
            cost = 42000,
            rank = 6
        },
        [10220] = {
            cost = 42000,
            rank = 4
        },
        [10225] = {
            cost = 42000,
            rank = 5
        },
        [12826] = {
            cost = 42000,
            rank = 4,
            requires = {118}
        },
        [13021] = {
            cost = 2100,
            rank = 5,
            requires = {11113}
        },
        [18809] = {
            cost = 2100,
            rank = 8,
            requires = {11366}
        },
    },
}
end
