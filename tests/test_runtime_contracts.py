from __future__ import annotations

import random
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RuntimeContractTests(unittest.TestCase):
    def test_cadence_isolates_and_evicts_failing_clients(self) -> None:
        luajit = shutil.which("luajit")
        self.assertIsNotNone(luajit, "LuaJIT is required for the cadence runtime contract")
        harness = r'''
_G.time_now = 0
function GetTime() return _G.time_now end

_G.pending_timers = {}
C_Timer = {
    NewTimer = function(delay, fn)
        local timer = { at = _G.time_now + delay, fn = fn, cancelled = false }
        timer.Cancel = function(self)
            self.cancelled = true
            for index, queued in ipairs(_G.pending_timers) do
                if queued == self then table.remove(_G.pending_timers, index) break end
            end
        end
        table.insert(_G.pending_timers, timer)
        return timer
    end,
    After = function() end,
}

_G.errors = {}
function geterrorhandler()
    return function(err) table.insert(_G.errors, tostring(err)) end
end

local noop = function() end
for _, name in ipairs({
    "UnitClass", "UnitGUID", "UnitExists", "GetSpellInfo", "SetCVar",
    "GetCVar", "InCombatLockdown", "UnitIsUnit", "GetLocale", "IsSpellKnown",
    "CombatLogGetCurrentEventInfo", "hooksecurefunc", "UnitAffectingCombat",
    "GetTimePreciseSec", "securecall", "UIParent", "PixelUtil", "LibStub",
}) do
    if _G[name] == nil then _G[name] = noop end
end
CreateFrame = function()
    local frame = {}
    setmetatable(frame, { __index = function() return function() end end })
    return frame
end

TurboFaceDB = {}
TurboFaceCacheDB = {}

local function AdvanceTo(target)
    local guard = 0
    while _G.time_now < target do
        guard = guard + 1
        if guard > 100000 then error("timer storm") end
        _G.time_now = math.min(target, _G.time_now + 0.005)
        while true do
            local due
            for index, timer in ipairs(_G.pending_timers) do
                if not timer.cancelled and timer.at <= _G.time_now then due = index break end
            end
            if not due then break end
            local timer = table.remove(_G.pending_timers, due)
            timer.fn()
        end
    end
end

local ns = {}
ns.API = setmetatable({ GetAddOnMetadata = function() return "test" end }, {
    __index = function() return function() end end,
})
assert(loadfile("src/common/Core/Config.lua"))("TurboFace", ns)

_G.good_runs = 0
ns.Cadence:Add("TurboFaceGood", 0.1, function() _G.good_runs = _G.good_runs + 1 end)
AdvanceTo(0.5)
assert(_G.good_runs > 0, "healthy cadence client did not fire")

_G.errors = {}
_G.bad_runs = 0
ns.Cadence:Add("TurboFaceBad", 0.1, function()
    _G.bad_runs = _G.bad_runs + 1
    error("simulated client failure")
end)
local good_before = _G.good_runs
AdvanceTo(1.5)
assert(_G.good_runs > good_before, "healthy cadence client stopped after peer failure")
assert(#_G.errors == 2, "failing cadence client did not use bounded reporting")
assert(_G.bad_runs == 3, "failing cadence client did not use the three-run budget")
assert(not ns.Cadence:IsActive("TurboFaceBad"), "failing cadence client was not evicted")

_G.retry_runs = 0
ns.Cadence:Add("TurboFaceBad", 0.1, function() _G.retry_runs = _G.retry_runs + 1 end)
AdvanceTo(_G.time_now + 1.0)
assert(_G.retry_runs > 0, "cadence re-registration did not receive a fresh budget")

ns.Cadence:Remove("TurboFaceGood")
ns.Cadence:Remove("TurboFaceBad")
assert(ns.Cadence:Count() == 0, "cadence scheduler did not park when empty")
'''
        result = subprocess.run(
            [luajit, "-"], input=harness, cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_classbuff_snapshot_preserves_first_matching_aura(self) -> None:
        source = (ROOT / "src" / "common" / "Combat" / "ClassBuffs.lua").read_text()
        for marker in (
            "local function RefreshBuffSnapshot()",
            "if buffIndexByName[name] == nil then",
            "index < bestIndex",
        ):
            self.assertIn(marker, source)

        def direct_scan(buffs: list[tuple[str, float]], wanted: set[str]) -> tuple[bool, float | None]:
            for name, expiration in buffs[:40]:
                if name in wanted:
                    return True, expiration - 1000 if expiration > 0 else None
            return False, None

        def indexed_scan(buffs: list[tuple[str, float]], wanted: set[str]) -> tuple[bool, float | None]:
            first: dict[str, tuple[int, float]] = {}
            for index, (name, expiration) in enumerate(buffs[:40], 1):
                first.setdefault(name, (index, expiration))
            matches = [first[name] for name in wanted if name in first]
            if not matches:
                return False, None
            _, expiration = min(matches, key=lambda item: item[0])
            return True, expiration - 1000 if expiration > 0 else None

        names = [
            "MarkOfTheWild", "GiftOfTheWild", "Thorns", "IceArmor", "MageArmor",
            "FrostArmor", "BattleShout", "Clearcasting", "LightningShield", "Unrelated",
        ]
        rng = random.Random(20260828)
        for case in range(4000):
            buffs = [
                (rng.choice(names), rng.choice([0, 0, 1005.5, 1010.0, 1000.25]))
                for _ in range(rng.randint(0, 12))
            ]
            wanted = set(rng.sample(names, rng.randint(1, 4)))
            self.assertEqual(direct_scan(buffs, wanted), indexed_scan(buffs, wanted), f"case {case}")


if __name__ == "__main__":
    unittest.main()
