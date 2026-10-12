from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLASSES = ('Druid', 'Hunter', 'Mage', 'Paladin', 'Priest', 'Rogue', 'Shaman', 'Warlock', 'Warrior')


class ClassLearnedRankTests(unittest.TestCase):
    def run_lua(self, source):
        luajit = shutil.which('luajit')
        self.assertIsNotNone(luajit)
        result = subprocess.run([luajit, '-'], input=source, text=True,
                                cwd=ROOT, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_modern_adapters_use_explicit_player_bank_and_ignore_legacy_aliases(self):
        for flavor in ('classic', 'forever'):
            source = (ROOT / 'src' / flavor / 'Core/Compat.lua').read_text()
            start = source.index('function API.IsClassSpellIDKnown(')
            adapter = source[start:source.index('\nend', start) + 4]
            harness = r'''
local opaque = {}
local API = { CanAccessValue = function(v) return v ~= opaque end }
Enum = { SpellBookSpellBank = { Player = 7 } }
IsSpellKnown = function() error('legacy query must not be consulted') end
IsPlayerSpell = IsSpellKnown
local learned = {}
C_SpellBook = {
 IsSpellInSpellBook = function(id, bank, overrides)
  assert(bank == 7 and overrides == false)
  return learned[id] or false
 end,
 IsSpellKnown = function(id, bank)
  assert(bank == 7)
  return learned[id] or false
 end,
}
ADAPTER
assert(API.IsClassSpellIDKnown(284) == false)
learned[78] = true
assert(API.IsClassSpellIDKnown(284) == false)
learned[284] = true
assert(API.IsClassSpellIDKnown(284) == true)
C_SpellBook.IsSpellInSpellBook = function() return false end
assert(API.IsClassSpellIDKnown(284) == true)
C_SpellBook.IsSpellKnown = function() error('temporarily unavailable') end
assert(API.IsClassSpellIDKnown(284) == false)
C_SpellBook.IsSpellInSpellBook = function() return true end
assert(API.IsClassSpellIDKnown(284) == true)
C_SpellBook.IsSpellInSpellBook = function() return opaque end
C_SpellBook.IsSpellKnown = function() return opaque end
assert(API.IsClassSpellIDKnown(284) == false)
C_SpellBook = nil
assert(API.IsClassSpellIDKnown(284) == MISSING)
'''.replace('ADAPTER', adapter).replace('MISSING', 'nil' if flavor == 'classic' else 'false')
            with self.subTest(flavor=flavor):
                self.run_lua(harness)

    def test_every_class_rank_two_list_queue_training_and_reload(self):
        for flavor in ('classic', 'forever'):
            for class_name in CLASSES:
                harness = r'''
function wipe(t) for k in pairs(t) do t[k] = nil end end
local level = 60
function UnitLevel() return level end
function UnitClass() return 'CLASS', 'CLASS_TOKEN' end
local learned = {}
local function createTrainer()
 local ns = {Trainer = {}, API = {
  GetSpellInfo = function(id) return 'Spell ' .. id end,
  -- A legacy family predicate and slot alias both lie about untrained ranks.
  IsKnownSpellID = function() return true end,
  IsClassSpellIDKnown = function(id) return learned[id] or false end,
  GetNumSpellTabs = function() error('modern rank decision used slot metadata') end,
 }}
 local t = ns.Trainer
 t.AddBuilder = function(_, fn) fn() end
 t.GetPlayerFaction = function() return nil end
 t.GetPlayerRace = function() return nil end
 t.IsPetSpellKnown = function() return nil end
 assert(loadfile('src/common/Trainer/data/CLASS.lua'))('TurboFace', ns)
 for _, loader in ipairs(t.BuiltinLoaders) do loader() end
 assert(loadfile('src/FLAVOR/Trainer/FLAVOR_TITLE' .. 'RankChains.lua'))('TurboFace', ns)
 assert(loadfile('src/common/Trainer/SkillData.lua'))('TurboFace', ns)
 assert(loadfile('src/common/Trainer/UI_ClassData.lua'))('TurboFace', ns)
 local f = assert(io.open('src/common/Trainer/TrainingQueue.lua'))
 local text = f:read('*a'); f:close()
 local predicate = assert(text:match('(local function IsQueueRecordKnown%(record%).-)\nlocal function IsQueueRecordUnavailable'))
 local queueKnown = assert(loadstring('local Trainer, ns = ...\n' .. predicate .. '\nreturn IsQueueRecordKnown'))(t, ns)
 return t, queueKnown
end
local t, queueKnown = createTrainer()
local data = t.Builtin.CLASS_TOKEN
local tested = 0
for reqLevel, spells in pairs(data) do
 for id, entry in pairs(spells) do
  if entry.rank == 2 then
   tested = tested + 1
   learned = {}
   local chain = t:GetClassSpellRankChain(id)
   if chain then learned[chain[1]] = true end
   local record = {scope='class',spellID=id,name='Spell '..id,rankNum=2,hasRealRank=true}
   local function listKnown()
    for _, row in ipairs(t:BuildEntriesFromData(data)) do
     if row.spellID == id then return row.directlyKnown == true end
    end
    error('rank missing from generated list')
   end
   for _, playerLevel in ipairs({1, reqLevel, 60}) do
    level = playerLevel
    assert(not t:IsClassSpellKnown(id, record.name, 2, true), 'eligible is not learned: '..id)
    assert(not listKnown(), 'list hides untrained rank: '..id)
    assert(not queueKnown(record), 'queue removes untrained rank: '..id)
   end
   learned[id] = true
   assert(t:IsClassSpellKnown(id, record.name, 2, true))
   assert(listKnown())
   assert(queueKnown(record))
   local reloaded, reloadedQueueKnown = createTrainer()
   assert(reloaded:IsClassSpellKnown(id, record.name, 2, true))
   assert(reloadedQueueKnown(record))
   -- A different character sharing the same catalog has no learned state.
   learned = {}
   assert(not reloaded:IsClassSpellKnown(id, record.name, 2, true))
   assert(not reloadedQueueKnown(record))
  end
 end
end
assert(tested > 0)
-- All replacement chains: knowing a later member covers earlier IDs only.
local seen = {}
for _, spells in pairs(data) do
 for id in pairs(spells) do
  local chain = t:GetClassSpellRankChain(id)
  if chain and not seen[chain] then
   seen[chain] = true
   for knownIndex, knownID in ipairs(chain) do
    learned = {[knownID] = true}
    for index, spellID in ipairs(chain) do
     assert(t:IsClassSpellKnown(spellID, 'Spell '..spellID, index, true) == (index <= knownIndex),
      'replacement chain mismatch: '..spellID)
    end
   end
  end
 end
end
-- Unranked spells also require exact evidence on modern clients.
learned = {}
assert(not t:IsClassSpellKnown(999999, 'Unranked', 1, false))
learned[999999] = true
assert(t:IsClassSpellKnown(999999, 'Unranked', 1, false))
'''.replace('CLASS_TOKEN', class_name.upper()).replace('CLASS', class_name).replace('FLAVOR_TITLE', flavor.title()).replace('FLAVOR', flavor)
                with self.subTest(flavor=flavor, class_name=class_name):
                    self.run_lua(harness)

    def test_trainer_visits_preserve_every_class_rank_two(self):
        for class_name in CLASSES:
            with self.subTest(class_name=class_name):
                self.run_lua(r'''
function wipe(t) for k in pairs(t) do t[k] = nil end end
function UnitClass() return 'CLASS', 'CLASS_TOKEN' end
local serviceID, serviceLevel, serviceName, serviceStatus
local starter = 1999999
local ns = {Trainer={}, API={
 GetSpellInfo=function(id)
  if id == serviceID or id == starter then return serviceName end
  return 'Spell '..id
 end,
 IsClassSpellIDKnown=function(id) return id == starter end,
}}
function ns:Chat(_, message) error(message) end
local t = ns.Trainer
assert(loadfile('src/common/Trainer/data/CLASS.lua'))('TurboFace',ns)
for _,loader in ipairs(t.BuiltinLoaders) do loader() end
local seed = t.Builtin.CLASS_TOKEN
assert(loadfile('src/common/Trainer/Init.lua'))('TurboFace',ns)
-- Repair the rank-less saved records produced by earlier trainer visits.
TurboFaceTrainerDB={data={CLASS_TOKEN={}}}
for level,spells in pairs(seed) do
 for id in pairs(spells) do t:EnsurePath('CLASS_TOKEN',level)[id]={cost=123} end
end
assert(loadfile('src/common/Trainer/BuiltinMerge.lua'))('TurboFace',ns)
t:MergeBuiltinData()
for level,spells in pairs(seed) do
 for id,data in pairs(spells) do
  assert(TurboFaceTrainerDB.data.CLASS_TOKEN[level][id].rank==data.rank)
 end
end
assert(loadfile('src/common/Trainer/TrainerCapture.lua'))('TurboFace',ns)
assert(loadfile('src/common/Trainer/SkillData.lua'))('TurboFace',ns)
t.AddBuilder=function(_,fn) fn() end
t.GetPlayerFaction=function() return nil end
t.GetPlayerRace=function() return nil end
t.IsPetSpellKnown=function() return nil end
assert(loadfile('src/common/Trainer/UI_ClassData.lua'))('TurboFace',ns)
t.InitSavedVariables=function() end
t.ResolveGeneralSkillSpellID=function() return nil end
GetNumTrainerServices=function() return 1 end
GetTrainerServiceInfo=function() return serviceName, serviceStatus end
GetTrainerServiceLevelReq=function() return serviceLevel end
GetTrainerServiceCost=function() return 123 end
-- Tooltip reports a *learned lower rank* with the same name.
C_TooltipInfo={GetTrainerService=function() return {id=starter} end}
local count=0
for level,spells in pairs(seed) do
 for id,data in pairs(spells) do
  if data.rank == 2 then
   count=count+1
   serviceID,serviceLevel,serviceName=id,level,'Family '..id
   TurboFaceTrainerDB={data={CLASS_TOKEN={
    [0]={[starter]={rank=1,cost=0}},
    [level]={[id]={rank=2,cost=200}},
   }}}
   for _,status in ipairs({'available','unavailable','used'}) do
    serviceStatus=status
    assert(t:GetSpellIDForService(1)==id, 'tooltip aliased service to starter: '..id)
    t:CaptureTrainer()
    local row=TurboFaceTrainerDB.data.CLASS_TOKEN[level][id]
    assert(row.rank==2, 'capture erased rank: '..id)
    assert(row.cost==123)
    assert(row.status==nil, 'account catalog stored learned status')
    assert(TurboFaceTrainerDB.data.CLASS_TOKEN[level][starter]==nil)
    for _,entry in ipairs(t:BuildEntriesFromData(TurboFaceTrainerDB.data.CLASS_TOKEN)) do
     if entry.spellID==id then
      assert(entry.hasRealRank and entry.rankNum==2)
      assert(not entry.directlyKnown)
     end
    end
   end
   -- With no rank or level to disambiguate, do not accept the tooltip alias.
   serviceLevel=0
   assert(t:GetSpellIDForService(1)==nil)
  end
 end
end
assert(count>0)
'''.replace('CLASS_TOKEN', class_name.upper()).replace('CLASS', class_name))
