local nornsRoot=assert(arg[1])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util'
norns={state={shortname='anima'},pmap={data={}}}
local now,beats=0,0;util.time=function() return now end
local tasks,serial={},0
clock={get_beat_sec=function() return 0.5 end,sleep=function() coroutine.yield() end,
 cancel=function(id) tasks[id]=nil end,run=function(fn)
 serial=serial+1;local id=serial;tasks[id]=coroutine.create(fn);assert(coroutine.resume(tasks[id]));return id
 end}
package.preload.pattern_time=function() return {new=function() return {count=0,rec=0,play=0,watch=function() end} end} end
local leds,frames={},0
local device={all=function() leds={} end,led=function(_,x,y,value) leds[y*100+x]=value end,refresh=function() frames=frames+1 end}
grid={connect=function() return device end}
include=function(path) return dofile(path:gsub('^anima/','')..'.lua') end
local PS=require 'core/paramset'
local S=include('lib/track_settings')
local Grid=include('lib/Grid')
local Mod=include('lib/modulation')
local function setup()
 params=PS.new();tasks={};serial=0;now=0;beats=0
 local a=include('lib/animator');S.add(a)
 params:add_number('slop','slop',0,500,0);params:add_number('max_notes','max',1,10,10)
 params:add_option('quantize','quantize',{'off','on'},1)
 a.modulation=Mod.new{time=function() return now end,beats=function() return beats end}
 a.grid=Grid.new(a);a.initHistory()
 a.redraw=function()
  if a.grid.view==1 then a.resetStepLevels() else a.setStepLevels(a.sequencers[a.grid.selected]) end
  a.grid:redraw()
 end
 a.notes={};for i=1,112 do a.notes[i]=60 end
 return a,a.grid,a.grid:createKeyHandler()
end
local function line(a,row) a.addNewSequence({{x=1,y=row},{x=2,y=row},{x=3,y=row}}) end
local function tap(key,x,y) key(x,y,1);key(x,y,0) end
local tests={}
tests['manual drawings undo and redo atomically and the new bottom row never selects a third pattern']=function()
 local a,g,key=setup()
 key(1,1,1);key(3,1,1);key(3,1,0);key(1,1,0)
 assert(#a.sequencers==1 and #a.history.undoStack==1,'one drawn line is one edit')
 tap(key,13,8);assert(#a.sequencers==0)
 key(15,8,1);tap(key,13,8);key(15,8,0);assert(#a.sequencers==1)
 local count=#a.history.undoStack
 tap(key,12,8);tap(key,14,8);assert(#a.history.undoStack==count,'blank pads do nothing')
 local selected={}
 g.patternManager.patternSelect=function(_,slot) selected[#selected+1]=slot end
 tap(key,10,8);tap(key,11,8)
 assert(#selected==2 and selected[1]==1 and selected[2]==2 and #g.patternManager.patterns==2)
 key(16,8,1);tap(key,13,8);key(16,8,0)
 assert(#a.history.undoStack==count,'page navigation cannot trigger undo')
 a.redraw();assert(leds[809]==nil and leds[812]==nil and leds[814]==nil,'canvas gaps remain dark')
end
tests['encoder edits coalesce and undo preserves later timbre and performance parameter edits']=function()
 local a=setup();line(a,1);a.history:clear()
 a.history:perform('move',function() a.moveSequence(1,'y',1,7) end,0.35)
 now=0.1;a.history:perform('move',function() a.moveSequence(1,'y',1,7) end,0.35)
 assert(#a.history.undoStack==1 and a.sequencers[1].steps[1].y==3)
 params:set('seq1velocity',55)
 for tick=1,30 do a.count() end
 assert(#a.history.undoStack==1,'playback adds no undo entries')
 a.history:travel(false)
 assert(a.sequencers[1].steps[1].y==1 and a.sequencers[1].velocity==55)
 a.history:travel(true)
 assert(a.sequencers[1].steps[1].y==3 and a.sequencers[1].velocity==55)
end
tests['undo of deletion restores line assignments without reverting the surviving line settings']=function()
 local a=setup();line(a,1);line(a,2)
 params:set('seq1output',11);params:set('seq2output',9);params:set('seq2velocity',81)
 a.history:clear();a.history:perform('delete',function() a.clearSeq(1) end)
 assert(#a.sequencers==1 and a.sequencers[1].output==9)
 params:set('seq1velocity',42)
 a.history:travel(false)
 assert(#a.sequencers==2 and a.sequencers[1].output==11 and a.sequencers[2].output==9)
 assert(a.sequencers[2].velocity==42,'surviving line keeps menu edits despite slot realignment')
 a.history:travel(true)
 assert(#a.sequencers==1 and a.sequencers[1].output==9 and a.sequencers[1].velocity==42)
end
tests['clear undo restores the selected snapshot and history is bounded and cleared on recall']=function()
 local a=setup();line(a,1);a.handleSelectSnapshot{i=1}
 a.history:perform('clear',function() a.clear(1) end)
 assert(#a.sequencers==0 and a.snapshots[1]==nil)
 a.history:travel(false);assert(#a.sequencers==1 and a.snapshots[1] and a.grid.snapshot==1)
 for i=1,30 do a.history:perform('step'..i,function() a.moveSequence(1,'y',1,7) end) end
 assert(#a.history.undoStack==16)
 a.handleSelectSnapshot{i=1};assert(#a.history.undoStack==0 and #a.history.redoStack==0)
end
tests['track eight LFO tap hold and navigation releases are independent']=function()
 local a,g,key=setup();for i=1,8 do line(a,(i-1)%7+1) end
 g.view=3
 tap(key,14,8);assert(a.sequencers[8].modEnabled,'tap enables track eight master')
 params:set('seq8lfo1Dest1',2)
 key(14,8,1);local hold=g.gestureHolds[8*16+14];assert(coroutine.resume(tasks[hold.task]))
 key(14,8,0)
 assert(a.sequencers[8].modEnabled and a.modulation:frozen(8),'long press freezes without toggling master')
 key(14,8,1);hold=g.gestureHolds[8*16+14];assert(coroutine.resume(tasks[hold.task]));key(14,8,0)
 assert(not a.modulation:frozen(8))
 key(14,8,1);key(16,8,1);tap(key,13,8);key(16,8,0);key(14,8,0)
 assert(g.view==1 and a.sequencers[8].modEnabled and next(g.gestureHolds)==nil)
 assert(g.held==nil,'cancelled LFO release does not hit canvas controls')
end
tests['probability and ratchet short taps retain their function and long holds freeze separately']=function()
 local a,g,key=setup();line(a,1);g.view=2
 params:set('seq1modEnabled',2);params:set('seq1lfo1Dest1',2);params:set('seq1lfo1Dest2',8)
 tap(key,7,1);tap(key,6,1)
 assert(a.sequencers[1].probabilityEnabled and a.sequencers[1].ratchetEnabled)
 for _,pair in ipairs({{7,'probability'},{6,'ratchet'}}) do
  key(pair[1],1,1);local hold=g.gestureHolds[16+pair[1]];assert(coroutine.resume(tasks[hold.task]));key(pair[1],1,0)
  assert(a.modulation:frozen(1,pair[2]))
 end
 assert(a.sequencers[1].probabilityEnabled and a.sequencers[1].ratchetEnabled)
 g:redraw();assert(leds[106]==15 and leds[107]==15,'frozen bright phase')
 g.blinkOn=false;g:redraw();assert(leds[106]==0 and leds[107]==0,'frozen dark phase')
 g.blinkOn=true
 g.view=3;g:redraw()
 assert(leds[101]==2 and leds[105]==2 and leds[107]==2 and leds[112]==2)
 assert(leds[106]==nil and leds[113]==nil and leds[114]==15,'separator and unused column stay dark')
 for i=1,15 do assert(leds[200+i]==nil,'empty track row stays dark') end
end
tests['ALT supports repeated redo taps and releases the correct availability indicator while stopped']=function()
 local a,g,key=setup();line(a,1);a.history:clear()
 for i=1,2 do a.history:perform('move'..i,function() a.moveSequence(1,'y',1,7) end) end
 tap(key,13,8);tap(key,13,8)
 assert(a.sequencers[1].steps[1].y==1)
 key(15,8,1);tap(key,13,8);tap(key,13,8)
 assert(a.sequencers[1].steps[1].y==3 and g.held and #a.history.redoStack==0)
 assert(leds[813]==0,'no more redo available')
 key(15,8,0);assert(g.held==nil and leds[813]==9,'undo indicator restored even without playback')
end

local count=0
for name,test in pairs(tests) do test();count=count+1;print('PASS '..name) end
print(count..'/'..count..' history and gesture scenarios passed')
