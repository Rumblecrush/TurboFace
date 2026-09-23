local _, ns = ...
local Trainer = ns.Trainer

-- Deferred class/pet seed data. These trainer facts are derived from
-- What's Training? by Fusionpit (MIT License); see
-- Licenses/WhatsTraining-MIT.txt. TurboFace wraps the catalog in deferred
-- loaders so a disabled Training module constructs no static tables.
Trainer.BuiltinLoaders = Trainer.BuiltinLoaders or {}
Trainer.BuiltinLoaders[#Trainer.BuiltinLoaders + 1] = function()

Trainer.Builtin_HunterPet = Trainer.Builtin_HunterPet or {
    [10] = {
        [4195] = {
            cost = 10,
            rank = 1
        },
        [24547] = {
            cost = 10,
            rank = 1
        },
    },
    [12] = {
        [4196] = {
            cost = 120,
            rank = 2
        },
        [24556] = {
            cost = 120,
            rank = 2
        },
    },
    [18] = {
        [4197] = {
            cost = 400,
            rank = 3
        },
        [24557] = {
            cost = 400,
            rank = 3
        },
    },
    [20] = {
        [14923] = {
            cost = 440,
            rank = 3
        },
        [24440] = {
            cost = 440,
            rank = 1
        },
        [24475] = {
            cost = 440,
            rank = 1
        },
        [24490] = {
            cost = 440,
            rank = 1
        },
        [24494] = {
            cost = 440,
            rank = 1
        },
        [24495] = {
            cost = 440,
            rank = 1
        },
    },
    [24] = {
        [4198] = {
            cost = 1400,
            rank = 4
        },
        [24558] = {
            cost = 1400,
            rank = 4
        },
    },
    [30] = {
        [4199] = {
            cost = 1600,
            rank = 5
        },
        [14924] = {
            cost = 1600,
            rank = 4
        },
        [24441] = {
            cost = 1600,
            rank = 2,
            requires = {23992}
        },
        [24476] = {
            cost = 1600,
            rank = 2,
            requires = {24446}
        },
        [24508] = {
            cost = 1600,
            rank = 2
        },
        [24511] = {
            cost = 1600,
            rank = 2,
            requires = {24492}
        },
        [24514] = {
            cost = 1600,
            rank = 2,
            requires = {24488}
        },
        [24559] = {
            cost = 1600,
            rank = 5
        },
    },
    [36] = {
        [4200] = {
            cost = 2800,
            rank = 6
        },
        [24560] = {
            cost = 2800,
            rank = 6
        },
    },
    [40] = {
        [14925] = {
            cost = 3600,
            rank = 5
        },
        [24463] = {
            cost = 3600,
            rank = 3,
            requires = {23992}
        },
        [24477] = {
            cost = 3600,
            rank = 3,
            requires = {24446}
        },
        [24509] = {
            cost = 3600,
            rank = 3
        },
        [24512] = {
            cost = 3600,
            rank = 3,
            requires = {24492}
        },
        [24515] = {
            cost = 3600,
            rank = 3,
            requires = {24488}
        },
    },
    [42] = {
        [4201] = {
            cost = 4800,
            rank = 7
        },
        [24561] = {
            cost = 4800,
            rank = 7
        },
    },
    [48] = {
        [4202] = {
            cost = 6400,
            rank = 8
        },
        [24562] = {
            cost = 6400,
            rank = 8
        },
    },
    [50] = {
        [14926] = {
            cost = 7200,
            rank = 6
        },
        [24464] = {
            cost = 7200,
            rank = 4,
            requires = {23992}
        },
        [24478] = {
            cost = 7200,
            rank = 4,
            requires = {24446}
        },
        [24510] = {
            cost = 7200,
            rank = 4
        },
        [24513] = {
            cost = 7200,
            rank = 4,
            requires = {24492}
        },
        [24516] = {
            cost = 7200,
            rank = 4,
            requires = {24488}
        },
    },
    [54] = {
        [5048] = {
            cost = 8400,
            rank = 9
        },
        [24631] = {
            cost = 8400,
            rank = 9
        },
    },
    [60] = {
        [5049] = {
            cost = 10000,
            rank = 10
        },
        [14927] = {
            cost = 10000,
            rank = 7
        },
        [24632] = {
            cost = 10000,
            rank = 10
        },
    },
}
end
