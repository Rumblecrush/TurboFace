from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StickyNoteTests(unittest.TestCase):
    def test_text_visibility_position_and_reload(self):
        source = r'''
local made
local enabled = true
local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.event = event end
function methods:UnregisterEvent(event) self.event = nil end
function methods:Hide()
 local was = self.shown
 self.shown = false
 if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Show() self.shown = true end
function methods:IsShown() return self.shown end
function methods:SetText(text)
 self.text = text
 if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:GetText() return self.text or '' end
function methods:SetPoint(point, parent, relative, x, y)
 if point == 'CENTER' then self.x, self.y = 500 + x, 400 + y end
end
function methods:GetCenter() return self.x or 500, self.y or 400 end
function methods:SetSize(width,height) self.width,self.height=width,height end
function methods:SetHeight(height) self.height=height end
function methods:GetHeight() return self.height end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetVerticalScroll(v) self.scroll=v end
function methods:SetFocus() self.focused=true end
function methods:ClearFocus() self.focused=false end
function methods:CreateFontString() return CreateFrame('FontString') end
function CreateFrame(kind, name, parent)
 local f = {kind=kind,name=name,parent=parent,scripts={},shown=true,focused=false,scroll=0,x=500,y=400,height=170,text=""}
 setmetatable(f, {__index=function(_,key) return methods[key] or function() end end})
 made[#made+1]=f
 return f
end
UIParent = {GetCenter=function() return 500,400 end}
SlashCmdList={}
local function load()
 made={}
 local ns={Chat=function() end, Opt=function(key,default) assert(key=="stickyNoteEnabled"); return enabled end}
 assert(loadfile('src/common/StickyNote.lua'))('TurboFace',ns)
 local event=made[#made]
 return ns.StickyNote, event
end
local note, event = load()
assert(TurboFaceCharDB == nil, 'loading must not overwrite unloaded SavedVariables')
event.scripts.OnEvent(event,'PLAYER_LOGIN')
assert(not TurboFaceCharDB.stickyNote.visible)
assert(#made==1, 'hidden unused note should be lazy')
note:Show()
local frame,edit,header,scroll
for _,f in ipairs(made) do
 if f.name=='TurboFaceStickyNote' then frame=f end
 if f.kind=='EditBox' then edit=f end
 if f.scripts.OnDragStop then header=f end
 if f.kind=='ScrollFrame' then scroll=f end
end
assert(frame:IsShown() and TurboFaceCharDB.stickyNote.visible)
assert(not edit.focused)
local text='Dungeon checklist\nBring water\nSecond line with | and Unicode: café'
edit.text=text; edit.scripts.OnTextChanged(edit,true)
assert(TurboFaceCharDB.stickyNote.text==text)
frame.x,frame.y=720,310
header.scripts.OnDragStop(header)
assert(TurboFaceCharDB.stickyNote.x==220 and TurboFaceCharDB.stickyNote.y==-90)
edit.scripts.OnCursorChanged(edit,0,-300,0,16)
assert(scroll.scroll==146)
-- Reload restores text/position and open state without keyboard focus.
note,event=load(); event.scripts.OnEvent(event,'PLAYER_LOGIN')
for _,f in ipairs(made) do
 if f.name=='TurboFaceStickyNote' then frame=f end
 if f.kind=='EditBox' then edit=f end
end
assert(frame:IsShown() and edit:GetText()==text and not edit.focused)
assert(frame.x==720 and frame.y==310)
-- Collapse preserves the header location and content, releases focus, and saves.
edit:SetFocus()
local oldTop=frame.y + frame:GetHeight()/2
note:SetCollapsed(true)
assert(frame:IsShown() and frame:GetHeight()==32)
assert(frame.y + frame:GetHeight()/2 == oldTop)
assert(not edit.focused and TurboFaceCharDB.stickyNote.collapsed)
assert(TurboFaceCharDB.stickyNote.text==text)
local collapsedY=frame.y
-- Simulate a drag while collapsed, then reload in compact mode.
frame.x,frame.y=760,collapsedY+20
for _,f in ipairs(made) do
 if f.scripts.OnDragStop then f.scripts.OnDragStop(f) end
end
note,event=load(); event.scripts.OnEvent(event,'PLAYER_LOGIN')
local collapse
for _,f in ipairs(made) do
 if f.name=='TurboFaceStickyNote' then frame=f end
 if f.name=='TurboFaceStickyNoteCollapse' then collapse=f end
 if f.kind=='EditBox' then edit=f end
 if f.kind=='ScrollFrame' then scroll=f end
end
assert(frame:IsShown() and frame:GetHeight()==32 and not scroll:IsShown())
assert(frame.x==760 and frame.y==collapsedY+20)
assert(collapse:GetText()=='+')
collapse.scripts.OnClick(collapse)
assert(frame:GetHeight()==230 and scroll:IsShown())
assert(frame.x==760 and frame.y==330 and collapse:GetText()=='-')
assert(edit:GetText()==text and not TurboFaceCharDB.stickyNote.collapsed)
note:HandleSlash('collapse')
assert(TurboFaceCharDB.stickyNote.collapsed and frame:IsShown())
note:HandleSlash('expand')
assert(not TurboFaceCharDB.stickyNote.collapsed and frame:IsShown())
note:Hide()
assert(not TurboFaceCharDB.stickyNote.visible and TurboFaceCharDB.stickyNote.text==text)
note,event=load();event.scripts.OnEvent(event,'PLAYER_LOGIN')
assert(#made==1)
note:HandleSlash('reset')
assert(TurboFaceCharDB.stickyNote.x==0 and TurboFaceCharDB.stickyNote.y==0)
assert(TurboFaceCharDB.stickyNote.text==text)
note:HandleSlash('hide')
assert(not TurboFaceCharDB.stickyNote.visible)
SlashCmdList.TURBOFACENOTE('')
assert(TurboFaceCharDB.stickyNote.visible)
-- Live disable preserves the user's open preference and note contents.
for _,f in ipairs(made) do
 if f.name=='TurboFaceStickyNote' then frame=f end
 if f.kind=='EditBox' then edit=f end
end
edit:SetFocus()
enabled=false
note:Refresh()
assert(not frame:IsShown() and not edit.focused)
assert(TurboFaceCharDB.stickyNote.visible and TurboFaceCharDB.stickyNote.text==text)
local count=#made
note:Show(); note:SetCollapsed(true); note:ResetPosition(); note:Toggle()
assert(#made==count and not frame:IsShown())
enabled=true
note:Refresh()
assert(frame:IsShown() and edit:GetText()==text)
-- Disabled startup must stay dormant even for a previously open note.
enabled=false
note,event=load(); event.scripts.OnEvent(event,'PLAYER_LOGIN')
assert(#made==1 and rawget(event,'event')==nil)
for _,command in ipairs({'show','collapse','expand','reset','hide',''}) do
 note:HandleSlash(command)
end
assert(#made==1 and TurboFaceCharDB.stickyNote.visible)
assert(TurboFaceCharDB.stickyNote.text==text)
-- A new character with the gate off gets neither a note frame nor saved data.
TurboFaceCharDB=nil
note,event=load(); event.scripts.OnEvent(event,'PLAYER_LOGIN')
note:Show();note:Hide();note:ResetPosition();note:SetCollapsed(true)
assert(TurboFaceCharDB==nil and #made==1)
'''
        luajit = shutil.which('luajit')
        self.assertIsNotNone(luajit)
        result = subprocess.run([luajit, '-'], input=source, text=True, cwd=ROOT,
                                capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
