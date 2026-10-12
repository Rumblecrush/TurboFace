from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WeaponStoneTests(unittest.TestCase):
    def test_bag_level_weapon_enchant_and_runtime_gates(self):
        source = (ROOT / 'src/common/Combat/ClassBuffs.lua').read_text()
        helper = source[source.index('local STONE_ITEMS ='):source.index('local function ShouldRemind(')]
        lua = r'''
local combat, dead, readable, mh, oh = false, false, true, false, false
local level, missing = 11, false
local bags, weapons = {}, {[16]=7}
local ns = {API={}}
function InCombatLockdown() return combat end
function UnitIsDeadOrGhost() return dead end
function UnitLevel() return level end
function GetInventoryItemID(_,slot) return weapons[slot] end
function ns.API.ReadWeaponEnchantInfo() return readable,mh,0,0,0,oh end
function ns.API.GetItemInfoInstant(id) return id,nil,nil,nil,nil,id==99 and 4 or 2,id end
function ns.API.GetItemCount(id,bank,uses,reagents)
 assert(not bank and not uses and not reagents)
 return bags[id] or 0
end
function ns.API.GetItemInfo(id)
 if missing then return nil end
 return 'stone',nil,nil,nil,id==12404 and 35 or 1,nil,nil,nil,nil,id+100
end
''' + helper + r'''
assert(FindBaggedWeaponStone()==nil)
bags[2678]=1
assert(FindBaggedWeaponStone()==2678)
bags[12404]=1
assert(FindBaggedWeaponStone()==2678, 'higher level stone must be skipped')
level=60
assert(FindBaggedWeaponStone()==12404)
bags={[12404]=1};level=11
assert(FindBaggedWeaponStone()==nil)
bags={[2678]=1};mh=true
assert(FindBaggedWeaponStone()==nil, 'all temporary enchants satisfy the reminder')
weapons[17]=15
assert(FindBaggedWeaponStone()==2678, 'uncoated offhand remains eligible')
oh=true
assert(FindBaggedWeaponStone()==nil)
mh=false;oh=false;weapons[17]=nil
for _,subclass in ipairs({0,1,6,7,8,15}) do
 weapons[16]=subclass;assert(FindBaggedWeaponStone()==2678)
end
for _,subclass in ipairs({4,5,10,13}) do
 weapons[16]=subclass;assert(FindBaggedWeaponStone()==nil)
 bags[3239]=1;assert(FindBaggedWeaponStone()==3239);bags[3239]=nil
end
for _,subclass in ipairs({2,3,16,18,19,20,99}) do
 weapons[16]=subclass;assert(FindBaggedWeaponStone()==nil)
end
weapons={};assert(FindBaggedWeaponStone()==nil)
weapons[16]=7
combat=true;assert(FindBaggedWeaponStone()==nil);combat=false
dead=true;assert(FindBaggedWeaponStone()==nil);dead=false
readable=false;assert(FindBaggedWeaponStone()==nil);readable=true
missing=true;assert(FindBaggedWeaponStone()==nil);missing=false
assert(FindBaggedWeaponStone()==2678)
'''
        result = subprocess.run([shutil.which('luajit'), '-'], input=lua, text=True,
                                cwd=ROOT, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('if e.type == "weaponStones" then', source)
        self.assertIn('local itemID, texture = FindBaggedWeaponStone()', source)
        self.assertIn('if ns.Opt(e.dbKey, true) == false then return false end', source)
