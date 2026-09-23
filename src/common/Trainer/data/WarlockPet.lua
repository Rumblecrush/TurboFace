local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin_WarlockPet = Trainer.Builtin_WarlockPet or {}
Trainer.Builtin_WarlockPet.Imp = Trainer.Builtin_WarlockPet.Imp or {
    [4] = {
        [20397] = {
            cost = 100,
            rank = 1
        },
    },
    [8] = {
        [20270] = {
            cost = 100,
            rank = 2
        },
    },
    [12] = {
        [20329] = {
            cost = 600,
            rank = nil
        },
    },
    [14] = {
        [20318] = {
            cost = 900,
            rank = 2
        },
        [20322] = {
            cost = 900,
            rank = 1
        },
    },
    [18] = {
        [20312] = {
            cost = 1500,
            rank = 3
        },
    },
    [24] = {
        [20323] = {
            cost = 3000,
            rank = 2
        },
    },
    [26] = {
        [20319] = {
            cost = 4000,
            rank = 3
        },
    },
    [28] = {
        [20313] = {
            cost = 5000,
            rank = 4
        },
    },
    [34] = {
        [20324] = {
            cost = 8000,
            rank = 3
        },
    },
    [38] = {
        [20314] = {
            cost = 10000,
            rank = 5
        },
        [20320] = {
            cost = 10000,
            rank = 4
        },
    },
    [44] = {
        [20326] = {
            cost = 12000,
            rank = 4
        },
    },
    [48] = {
        [20315] = {
            cost = 14000,
            rank = 6
        },
    },
    [50] = {
        [20321] = {
            cost = 15000,
            rank = 5
        },
    },
    [54] = {
        [20327] = {
            cost = 20000,
            rank = 5
        },
    },
    [58] = {
        [20316] = {
            cost = 24000,
            rank = 7
        },
    },
}

Trainer.Builtin_WarlockPet.Voidwalker = Trainer.Builtin_WarlockPet.Voidwalker or {
    [16] = {
        [20381] = {
            cost = 1200,
            rank = 1
        },
    },
    [18] = {
        [20387] = {
            cost = 1500,
            rank = 1
        },
    },
    [20] = {
        [20317] = {
            cost = 2000,
            rank = 2
        },
    },
    [24] = {
        [20382] = {
            cost = 3000,
            rank = nil
        },
        [20393] = {
            cost = 3000,
            rank = nil
        },
    },
    [26] = {
        [20388] = {
            cost = 4000,
            rank = nil
        },
    },
    [30] = {
        [20377] = {
            cost = 6000,
            rank = nil
        },
    },
    [32] = {
        [20383] = {
            cost = 7000,
            rank = nil
        },
    },
    [34] = {
        [20389] = {
            cost = 8000,
            rank = nil
        },
    },
    [36] = {
        [20394] = {
            cost = 9000,
            rank = nil
        },
    },
    [40] = {
        [20378] = {
            cost = 11000,
            rank = nil
        },
        [20384] = {
            cost = 11000,
            rank = nil
        },
    },
    [42] = {
        [20390] = {
            cost = 11000,
            rank = nil
        },
    },
    [48] = {
        [20385] = {
            cost = 14000,
            rank = nil
        },
        [20395] = {
            cost = 14000,
            rank = nil
        },
    },
    [50] = {
        [20379] = {
            cost = 15000,
            rank = 5
        },
        [20391] = {
            cost = 15000,
            rank = 5
        },
    },
    [56] = {
        [20386] = {
            cost = 22000,
            rank = 6
        },
    },
    [58] = {
        [20392] = {
            cost = 24000,
            rank = 6
        },
    },
    [60] = {
        [20380] = {
            cost = 26000,
            rank = 6
        },
        [20396] = {
            cost = 26000,
            rank = 4
        },
    },
}

Trainer.Builtin_WarlockPet.Succubus = Trainer.Builtin_WarlockPet.Succubus or {
    [22] = {
        [20403] = {
            cost = 2500,
            rank = 1
        },
    },
    [26] = {
        [20407] = {
            cost = 4000,
            rank = nil
        },
    },
    [28] = {
        [20398] = {
            cost = 5000,
            rank = 2
        },
    },
    [32] = {
        [20408] = {
            cost = 7000,
            rank = nil
        },
    },
    [34] = {
        [20404] = {
            cost = 8000,
            rank = 2
        },
    },
    [36] = {
        [20399] = {
            cost = 9000,
            rank = 3
        },
    },
    [44] = {
        [20400] = {
            cost = 12000,
            rank = 4
        },
    },
    [46] = {
        [20405] = {
            cost = 13000,
            rank = 3
        },
    },
    [52] = {
        [20401] = {
            cost = 18000,
            rank = 5
        },
    },
    [58] = {
        [20406] = {
            cost = 24000,
            rank = 4
        },
    },
    [60] = {
        [20402] = {
            cost = 26000,
            rank = 6
        },
    },
}

Trainer.Builtin_WarlockPet.Incubus = Trainer.Builtin_WarlockPet.Incubus or {}
Trainer.Builtin_WarlockPet.Felhunter = Trainer.Builtin_WarlockPet.Felhunter or {
    [32] = {
        [20429] = {
            cost = 7000,
            rank = 1
        },
    },
    [36] = {
        [20433] = {
            cost = 9000,
            rank = 1
        },
    },
    [38] = {
        [20426] = {
            cost = 10000,
            rank = 2
        },
    },
    [40] = {
        [20430] = {
            cost = 11000,
            rank = 2
        },
    },
    [42] = {
        [20435] = {
            cost = 11000,
            rank = nil
        },
    },
    [46] = {
        [20427] = {
            cost = 13000,
            rank = 3
        },
    },
    [48] = {
        [20431] = {
            cost = 14000,
            rank = 3
        },
    },
    [52] = {
        [20434] = {
            cost = 18000,
            rank = 2
        },
    },
    [54] = {
        [20428] = {
            cost = 20000,
            rank = 4
        },
    },
    [56] = {
        [20432] = {
            cost = 22000,
            rank = 4
        },
    },
}
end
