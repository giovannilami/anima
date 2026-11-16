-- End-to-end init with real norns ParamSet and scheduled clock/metro mocks.
local nornsRoot, dataDir, mode = assert(arg[1]), assert(arg[2]), arg[3]
package.path = nornsRoot .. '/lua/?.lua;' .. nornsRoot .. '/lua/lib/?.lua;' .. package.path
util = require 'util'
util.time = function() return 0 end
controlspec = require 'core/controlspec'
tab = require 'tabutil'
norns = {state={data=dataDir..'/',shortname='anima'},pmap={data={}}}
params = require('core/paramset').new()
local audioLog={}
engine = {noteOn=function(note) audioLog[#audioLog+1]=note end,noteOff=function() end}
local loadCallback
package.preload.fileselect = function() return {enter=function(_,callback) loadCallback=callback end} end
local saveCallback
package.preload.textentry = function() return {enter=function(callback) saveCallback=callback end} end
package.preload['molly_the_poly/lib/molly_the_poly_engine'] = function()
  return {add_params=function()
    for _,id in ipairs({'env_2_decay','env_2_sustain','env_2_release','osc_wave_shape','noise_level','chorus_mix'}) do
      params:add_number(id,id,0,100,0)
    end
    for i=1,41 do params:add_number('synth_test_'..i,'synth',0,100,0) end
  end}
end
local tasks, timers = {}, {}
clock = {transport={},get_beat_sec=function() return 0.5 end,
  sleep=function() coroutine.yield() end,sync=function() coroutine.yield() end,
  cancel=function(id) tasks[id]=nil end,
  run=function(fn)
    local id=#tasks+1;tasks[id]=coroutine.create(fn)
    assert(coroutine.resume(tasks[id]));return id
  end}
metro = {init=function(fn,time,count)
  local id=#timers+1
  local m={id=id,event=fn,time=time,count=count,start=function() end,stop=function() end}
  timers[id]=m;return m
end,free=function(id) timers[id]=nil end}
local midiLog, nbLog = {}, {}
midi = {vports={},connect=function(port) return {
  note_on=function(_,note,vel,ch) midiLog[#midiLog+1]={port,ch,note} end,
  note_off=function() end
} end}
crow = {ii={pullup=function() end,jf={mode=function() end,play_note=function() end}},output={{},{},{},{}}}
local gridFrames,gridLeds,gridFrame=0,{},{}
local gridDevice = {
 all=function() gridLeds={} end,
 led=function(_,x,y,v)
   assert(x%1==0 and x>=1 and x<=16 and y%1==0 and y>=1 and y<=8,'Grid coordinate outside 16x8')
   assert(v%1==0 and v>=0 and v<=15,'invalid Grid brightness')
   gridLeds[(y-1)*16+x]=v
 end,
 refresh=function()
   gridFrames=gridFrames+1;gridFrame={}
   for k,v in pairs(gridLeds) do gridFrame[k]=v end
 end}
grid = {connect=function() return gridDevice end}
local screenTexts,screenRects={},{}
screen = setmetatable({
  clear=function() screenTexts={};screenRects={} end,
  text=function(value) screenTexts[#screenTexts+1]=value end,
  rect=function(x,y,w,h) screenRects[#screenRects+1]={x,y,w,h} end,
}, {__index=function() return function() end end})
local nbInit, nbParams = 0,0
local fakeNb = {
 init=function() nbInit=nbInit+1 end,
 add_param=function(_,id,label)
   nbParams=nbParams+1
   params:add_option(id,label,{'none','voice A','voice B'},1)
   params:add_text(id..'_hidden_string','saved','none');params:hide(id..'_hidden_string')
   local parameter=params:lookup_param(id)
   function parameter:get_player()
     local name=params:get(id..'_hidden_string')
     return {name=name,note_on=function(_,note) nbLog[#nbLog+1]={id,name,note} end,note_off=function() end}
   end
   params:set_action(id,function(v) params:set(id..'_hidden_string',parameter.options[v]) end)
   params:set_action(id..'_hidden_string',function(name)
     for index,value in ipairs(parameter.options) do if name==value then params:set(id,index,true) end end
   end)
 end,
 add_player_params=function() params:add_separator('nb_test_voices','NB TEST VOICES') end,
}
package.preload['nbout/lib/nb/lib/nb']=function()
  if mode~='nb' then error('NB absent in this test') end
  engine.name=nil
  return fakeNb
end
package.preload['nb/lib/nb']=function() error('standalone NB absent') end
include=function(path) return dofile(path:gsub('^anima/','')..'.lua') end
dofile('anima.lua')
init()
-- SAVE/LOAD exposes native save/load plus the public upstream importer.
local saveLoadIndex=params.lookup['SAVE/LOAD']
assert(saveLoadIndex,'SAVE/LOAD group exists')
assert(params.params[saveLoadIndex].n==3,'SAVE/LOAD contains exactly three actions')
for offset,id in ipairs({'save','load','import_animator'}) do
  assert(params.params[saveLoadIndex+offset].id==id,'unexpected SAVE/LOAD action')
end
assert(params.params[saveLoadIndex+4].name=='COMPOSITION','next group remains separate')
print('PASS SAVE/LOAD keeps save, load and original Animator import NB '..(mode or 'absent'))
assert(engine.name=='MollyThePoly','engine preserved after NB require')
assert(not params.lookup.output,'no global output in EDIT')
for i=1,8 do
 assert(params.lookup['track'..i] and not params.hidden[params.lookup['track'..i]],'track EDIT group visible')
 assert(params.lookup['seq'..i..'output'],'output per track')
end
-- Verify actual group boundaries; malformed counts can swallow whole EDIT groups.
for _,p in ipairs(params.params) do
 if p.t==params.tGROUP then
   local position=params.lookup[p.id]
   for n=position+1,position+p.n do
     assert(params.params[n] and params.params[n].t~=params.tGROUP,'bad group boundary '..p.id)
   end
 end
end
-- Draw two real lines and sound the same pitch on separate destinations.
gridDevice.key(1,1,1);gridDevice.key(3,1,1);gridDevice.key(3,1,0);gridDevice.key(1,1,0)
gridDevice.key(1,2,1);gridDevice.key(3,2,1);gridDevice.key(3,2,0);gridDevice.key(1,2,0)
params:set('seq1output',4);params:set('seq1port',16);params:set('seq1channel',7)
params:set('seq1rate',1);params:set('seq2rate',1)
if mode=='nb' then
 assert(nbInit==1 and nbParams==8,'eight NB selectors initialized')
 params:set('seq2output',3);params:set('seq2nb',3)
else
 assert(nbInit==0,'NB absent gracefully')
 params:set('seq2output',5)
end
-- Enable all points via Canvas.
for y=1,2 do for x=1,3 do gridDevice.key(x,y,1);gridDevice.key(x,y,0) end end
assert(coroutine.resume(tasks[1])) -- next clock tick
assert(#midiLog>0 and midiLog[1][1]==16 and midiLog[1][2]==7,'per-track MIDI route reaches playback')
if mode=='nb' then assert(#nbLog>0 and nbLog[1][1]=='seq2nb' and nbLog[1][2]=='voice B','per-track NB player reaches playback') end
-- Full playback routes the new combinations using their per-track settings.
params:set('seq1output',10)
params:set('seq2output',9);params:set('seq2port',2);params:set('seq2channel',5)
midiLog={};nbLog={};audioLog={}
assert(coroutine.resume(tasks[1]))
assert(#audioLog==1,'internal combination emits audio')
local firstMidi,secondMidi=false,false
for _,event in ipairs(midiLog) do
  if event[1]==16 and event[2]==7 then firstMidi=true end
  if event[1]==2 and event[2]==5 then secondMidi=true end
end
assert(firstMidi and secondMidi,'both combinations emit independent MIDI routes')
if mode=='nb' then assert(#nbLog==1 and nbLog[1][1]=='seq2nb','NB combination emits its selected player') end
-- The held preview restores the original single-track drawing on Norns,
-- while Grid intersection controls and clock playback remain usable.
gridDevice.key(16,8,1);gridDevice.key(15,8,1);gridDevice.key(15,8,0);gridDevice.key(16,8,0)
gridDevice.key(15,2,1)
assert(screenTexts[1]=='TRACK 2' and #screenRects==3,'preview shows only the three steps of track two')
for _,rect in ipairs(screenRects) do assert(rect[2]==16,'no track-one points in the drawing') end
gridDevice.key(4,2,1);gridDevice.key(4,2,0)
assert(params:get('seq2harmonic')==5 and screenTexts[1]=='TRACK 2','can edit intersections while viewing track')
assert(coroutine.resume(tasks[1]))
assert(screenTexts[1]=='TRACK 2' and #screenRects==3,'clock redraw retains held preview')
enc(2,1)
for _,rect in ipairs(screenRects) do assert(rect[2]==21,'encoder moves only the selected track in preview') end
gridDevice.key(15,2,0)
assert(screenTexts[1]=='INTERSECTIONS  2' and #screenRects==0,'release restores intersection parameters')
-- Direct page selector and the row-8 controls coexist.
gridDevice.key(16,8,1);gridDevice.key(14,8,1);gridDevice.key(14,8,0);gridDevice.key(16,8,0)
gridDevice.key(6,1,1);gridDevice.key(6,1,0)
assert(params:get('seq1ratchetEnabled')==2,'ratchet toggle synced with EDIT')
gridDevice.key(7,1,1);gridDevice.key(7,1,0)
assert(params:get('seq1probabilityEnabled')==2,'probability synced with EDIT')
-- Short mute tap vs deliberate long solo press.
gridDevice.key(1,1,1);gridDevice.key(1,1,0)
assert(params:get('seq1muted')==2,'short mute tap')
gridDevice.key(1,1,1)
local holdTask
for id,task in pairs(tasks) do if id>2 and coroutine.status(task)=='suspended' then holdTask=id end end
assert(holdTask and coroutine.resume(tasks[holdTask]))
gridDevice.key(1,1,0)
assert(params:get('seq1solo')==2 and params:get('seq1muted')==2,'long press toggles solo without changing mute')
local ioBefore = io.output()
params:lookup_param('save'):bang()
assert(saveCallback,'save action opens text entry')
local saved,saveError=saveCallback('runtime-' .. (mode or 'absent'))
assert(saved,saveError)
assert(io.output()==ioBefore and io.type(io.output())=='file','save preserves default output')
local savedDoodle=assert(tab.load(dataDir..'/runtime-' .. (mode or 'absent') .. '.doodle'))
assert(savedDoodle.patterns[1].metro==nil,'live timer absent from saved pattern')
params:set('seq1output',2)
params:lookup_param('load'):bang()
loadCallback(dataDir..'/runtime-' .. (mode or 'absent') .. '.doodle')
assert(params:get('seq1output')==10 and params:get('seq1port')==16,'full runtime save reloads combo routing')
assert(params:get('seq2output')==9 and params:get('seq2port')==2,'NB combination reloads independently')
-- Full init path: genuine legacy-format import, persistence and return to
-- native mode must not leave original playback enabled for another doodle.
local legacy=assert(tab.load(dataDir..'/runtime-'..(mode or 'absent')..'.doodle'))
legacy.formatVersion=nil;legacy.trackSettings=nil;legacy.originalPlayback=nil;legacy.snapshots={}
for i,seq in ipairs(legacy.sequencers) do seq.div=i==1 and 5 or 7;seq.divCount=1;seq.intersect=2 end
local legacyPath=dataDir..'/legacy-runtime.doodle'
assert(not tab.save(legacy,legacyPath))
local legacyFile=assert(io.open(dataDir..'/legacy-runtime.pset','w'))
legacyFile:write('"output": 3\n"min_velocity": 15\n"max_velocity": 90\n"min_note_length": 0.01\n"max_note_length": 0.13\n');legacyFile:close()
params:lookup_param('import_animator'):bang();loadCallback(legacyPath)
assert(params:get('animator_playback')==2 and params:get('seq1rate')==8 and params:get('seq2rate')==9)
assert(params:get('seq1output')==10 and params:get('seq1modEnabled')==1,'original audio+MIDI and neutral new controls')
params:lookup_param('save'):bang();saveCallback('legacy-full-roundtrip')
local legacySaved=assert(tab.load(dataDir..'/legacy-full-roundtrip.doodle'))
assert(legacySaved.originalPlayback.enabled and legacySaved.originalPlayback.minDurationCs==1)
assert(legacySaved.originalPlayback.maxDurationCs==13 and legacySaved.originalPlayback.maxVelocity==90)
params:set('animator_playback',1)
params:lookup_param('load'):bang();loadCallback(dataDir..'/legacy-full-roundtrip.doodle')
assert(params:get('animator_playback')==2,'saved original behaviour restores')
params:lookup_param('load'):bang();loadCallback(dataDir..'/runtime-'..(mode or 'absent')..'.doodle')
assert(params:get('animator_playback')==1,'native doodle cannot inherit original mode')
print('PASS full runtime original import save reload and return to native mode NB '..(mode or 'absent'))

-- PSET actions must never stream intermediate frames to the USB device.
-- Reproduce a read that changes hundreds of parameters on eight tracks.
local helpers=include('anima/lib/helpers')
local Settings=include('anima/lib/track_settings')
local stress=helpers.deepcopy(savedDoodle)
for i=1,8 do
 stress.sequencers[i]=helpers.deepcopy(savedDoodle.sequencers[1])
 stress.trackSettings[i]=helpers.deepcopy(savedDoodle.trackSettings[1])
 for _,step in ipairs(stress.sequencers[i].steps) do step.y=(i-1)%7+1 end
end
local function scene()
 local s={on=helpers.deepcopy(stress.on),enabled=helpers.deepcopy(stress.enabled),
   sequencers=helpers.deepcopy(stress.sequencers),trackSettings=helpers.deepcopy(stress.trackSettings),
   rates={},intersects={},harmonics={},rhythms={}}
 for i=1,8 do s.rates[i]=s.sequencers[i].rate;s.intersects[i]=s.sequencers[i].intersect
   s.harmonics[i]=s.sequencers[i].harmonic;s.rhythms[i]=s.sequencers[i].rhythm end
 return s
end
stress.snapshots={[1]=scene(),[8]=scene()}
for i=1,8 do
 stress.snapshots[8].rates[i]=7;stress.snapshots[8].trackSettings[i].rate=7
 stress.snapshots[8].harmonics[i]=6;stress.snapshots[8].trackSettings[i].harmonic=6
 stress.snapshots[8].rhythms[i]=7;stress.snapshots[8].trackSettings[i].rhythm=7
end
local stressPath=dataDir..'/grid-stress-'..(mode or 'absent')
assert(not tab.save(stress,stressPath..'.doodle'))
local source=assert(io.open(dataDir..'/runtime-'..(mode or 'absent')..'.pset','r'))
local sourceText=source:read('*a');source:close()
local target=assert(io.open(stressPath..'.pset','w'));target:write(sourceText);target:close()
local nativeRead=params.read
params.read=function(self,...)
 local before=gridFrames
 local result=nativeRead(self,...)
 redraw() -- A concurrent request must also be suppressed during the batch.
 assert(gridFrames==before,'intermediate Grid frames escaped PSET read')
 return result
end
local function changeEveryTrack()
 for i=1,8 do for _,f in ipairs(Settings.fields) do
   local value=f.boolean and 2 or (f.options and #f.options or f.max)
   if value then params:set(Settings.id(i,f.key),value,true) end
 end end
end
for pass=1,40 do
 changeEveryTrack()
 local before=gridFrames
 loadCallback(stressPath..'.doodle')
 assert(gridFrames==before+1,'doodle read must publish exactly one final Grid frame')
 assert(params:get('seq8rate')==stress.trackSettings[8].rate,'last track restored before drawing')
end
params.read=nativeRead
print('PASS eight-track repeated doodle loads publish one complete Grid frame NB '..(mode or 'absent'))

gridDevice.key(16,8,1);gridDevice.key(13,8,1);gridDevice.key(13,8,0);gridDevice.key(16,8,0)
params:set('quantize',1)
for pass=1,40 do
 local slot=pass%2==0 and 1 or 8
 local before=gridFrames
 gridDevice.key(slot,8,1)
 assert(gridFrames==before+1,'snapshot press must publish exactly one complete frame')
 assert(gridFrame[112+slot]==15,'selected snapshot must be in that same frame')
 assert(params:get('seq8rate')==(slot==8 and 7 or stress.trackSettings[8].rate))
 gridDevice.key(slot,8,0)
end
print('PASS eight-track fast snapshot recalls keep frame and selection consistent NB '..(mode or 'absent'))

-- Exiting must close all script timers and remain safe if called twice.
local retiredKey=gridDevice.key
cleanup()
cleanup()
assert(gridDevice.key==nil,'Grid key callback detached on exit')
local framesAfterExit=gridFrames
retiredKey(16,8,1);retiredKey(1,1,1);redraw()
assert(gridFrames==framesAfterExit,'retired callbacks cannot draw over another script')
print('PASS retired Grid callbacks cannot emit frames after cleanup NB '..(mode or 'absent'))
assert(next(timers)==nil,'all output, LFO and pattern timers freed')
print('PASS full script init, EDIT groups, playback, NB '..(mode=='nb' and 'present' or 'absent')..', navigation and controls')
