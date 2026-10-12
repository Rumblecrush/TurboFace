from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SwingSecretGUIDTests(unittest.TestCase):
    def test_secret_target_switch_and_cache_boundaries(self):
        compat = (ROOT / 'src/forever/Core/Compat.lua').read_text()
        begin = compat.index('function API.ReadableGUID(')
        end = compat.index('-- Class Training needs', begin)
        shared = (ROOT / 'src/common/Combat/SwingTimers.lua').read_text()
        cache = shared[shared.index('local function RecordTargetSwing('):shared.index('local function LatestResetAt(')]
        change = shared[shared.index('swingEventHandlers.PLAYER_TARGET_CHANGED ='):shared.index('swingEventHandlers.UPDATE_SHAPESHIFT_FORM =')]
        harness = r'''
local SECRET = 'opaque-guid'
local API = {CanAccessValue=function(v) return v ~= SECRET end}
local rawGUID = SECRET
function UnitGUID() return rawGUID end
COMPAT
assert(API.GetUnitGUID('target') == nil)
rawGUID = 'Creature-A'
assert(API.GetUnitGUID('target') == 'Creature-A')
local ns = {API=API, SwingTimerProviderCanReadTargetAttackSpeed=function() return false end,
 SwingTimerProviderResetTargetCombat=function(guid) assert(guid ~= SECRET) end}
local UnitGUID = API.GetUnitGUID
local target = {guid='Creature-A', main_speed=2, off_speed=2, main_timer=1, off_timer=1, has_offhand=true}
local store = {}
local targetSwingStates = setmetatable({}, {
 __index=function(_,key) assert(key ~= SECRET, 'secret cache read'); return store[key] end,
 __newindex=function(_,key,value) assert(key ~= SECRET, 'secret cache write'); store[key]=value end,
})
local now = 10
function GetTime() return now end
CACHE
RecordTargetSwing('Creature-A',false,2)
RecordTargetSwing('Creature-A',true,2)
RecordTargetSwing(SECRET,false,2)
now=11
RestoreTargetSwing('Creature-A')
assert(target.main_timer == 1 and target.off_timer == 1)
RestoreTargetSwing(SECRET)
assert(target.main_timer == 0 and target.off_timer == 0)
target.guid=SECRET
SaveCurrentTargetSwing()
assert(target.guid == nil)
local swingEventHandlers = {}
local in_combat=false
local function UpdateTargetSpeeds() end
local function RefreshQueuedSpell() end
function UnitExists() return true end
CHANGE
rawGUID=SECRET
target.guid='Creature-A'
target.main_timer=1; target.off_timer=1
swingEventHandlers.PLAYER_TARGET_CHANGED()
assert(target.guid==nil and target.main_timer==0 and target.off_timer==0)
rawGUID='Creature-A'
swingEventHandlers.PLAYER_TARGET_CHANGED()
assert(target.guid=='Creature-A' and target.main_timer==1 and target.off_timer==1)
rawGUID=nil
swingEventHandlers.PLAYER_TARGET_CHANGED()
assert(target.guid==nil and target.main_timer==0)
'''.replace('COMPAT', compat[begin:end]).replace('CACHE', cache).replace('\nCHANGE\n', '\n' + change + '\n')
        luajit = shutil.which('luajit')
        self.assertIsNotNone(luajit)
        result = subprocess.run([luajit, '-'], input=harness, cwd=ROOT,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('local UnitGUID = ns.API.GetUnitGUID', shared)
        for signature in ('GetNameplateState(guid)', 'PrimeNameplateState(guid, unit)',
                          'CleanupNameplateState(guid)', 'RecordNameplateSwing(guid, duration, now)'):
            self.assertIn('function SwingTimers:' + signature + '\n    guid = ns.API.ReadableGUID(guid)', shared)
