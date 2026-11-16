-- Virtual instrument: real Animator, Grid, modulation, ParamSet, outputs and UI.
-- Hardware, timers and time are simulated; actual queued strikes are counted.
local root=assert(arg[1])
package.path=root..'/lua/?.lua;'..root..'/lua/lib/?.lua;'..package.path
util=require 'util'
norns={state={shortname='anima'},pmap={data={}}}
package.preload.pattern_time=function() return {new=function() return {count=0,rec=0,play=0} end} end
include=function(path) return dofile(path:gsub('^anima/','')..'.lua') end
local PS=require 'core/paramset'
local Settings=include('lib/track_settings')
local Mod=include('lib/modulation')
local now,bpm,tasks,timers,serial,playing,nextTick,a,key
local leds,frames,texts,notes,bursts,drawn,screenUpdates
local device={all=function() leds={} end,led=function(_,x,y,value) leds[y*100+x]=value end,
 refresh=function()
  local copy={};for k,v in pairs(leds) do copy[k]=v end
  frames[#frames+1]={at=now,leds=copy}
 end}
grid={connect=function() return device end}
local cursorY,screenLevel=0,15
screen=setmetatable({clear=function() texts={};drawn={} end,
 level=function(level) screenLevel=level end,move=function(x,y) cursorY=y end,
 text_extents=function(value) return #value*4 end,
 update=function() screenUpdates=screenUpdates+1 end,
 text=function(value) texts[#texts+1]=value;drawn[cursorY]={text=value,level=screenLevel} end},
 {__index=function() return function() end end})
local Grid=include('lib/Grid')
local Outputs=include('lib/outputs')
local UI=include('lib/ui')
util.time=function() return now end
local function resume(id)
 local task=tasks[id];local ok,delay=coroutine.resume(task.co);assert(ok,delay)
 if coroutine.status(task.co)=='dead' then tasks[id]=nil else task.at=now+delay end
end
clock={get_beat_sec=function() return 60/bpm end,sleep=function(seconds) coroutine.yield(seconds) end,
 cancel=function(id) tasks[id]=nil end,run=function(fn)
  serial=serial+1;local id=serial;tasks[id]={co=coroutine.create(fn)};resume(id);return id
 end}
metro={init=function(fn,interval,count)
 serial=serial+1;local id=serial
 local m={id=id,event=fn,time=interval,count=count,running=false}
 function m:start() self.running=true;self.at=now+self.time end
 function m:stop() self.running=false end
 timers[id]=m;return m
 end,free=function(id) timers[id]=nil end}
local function advance(seconds)
 local stop=now+seconds
 while true do
  local at,kind,id=stop+1
  if playing and nextTick<at then at,kind=nextTick,'tick' end
  for k,v in pairs(tasks) do if v.at<at then at,kind,id=v.at,'task',k end end
  for k,v in pairs(timers) do if v.running and v.at<at then at,kind,id=v.at,'timer',k end end
  if at>stop+1e-9 then break end
  now=at
  if kind=='tick' then nextTick=nextTick+clock.get_beat_sec()/8;a.count()
  elseif kind=='task' then resume(id)
  else local m=timers[id];m.at=m.at+m.time;m.event() end
 end
 now=stop
end
local function setup(tempo,rate,shape,free)
 now,bpm,tasks,timers,serial,playing=0,tempo,{},{},0,true
 leds,frames,texts,notes,bursts,drawn,screenUpdates={},{},{},{},{},{},0
 params=PS.new();a=include('lib/animator');Settings.add(a)
 params:add_number('slop','slop',0,500,0);params:add_number('max_notes','max',1,10,10)
 params:add_option('quantize','quantize',{'off','on'},1)
 a.modulation=Mod.new{time=function() return now end,beats=function() return now/clock.get_beat_sec() end,
  random=function() return (math.floor(now*37)%13)/12 end}
 a.grid=Grid.new(a);a.grid.view=2
 a.redraw=function() a.grid:redraw();UI.redraw(a.stepLevels,a.grid,false) end
 key=a.grid:createKeyHandler();a.grid:startFeedback(function() UI.redraw(a.stepLevels,a.grid,false) end)
 a.notes={};for i=1,112 do a.notes[i]=60 end
 a.addNewSequence({{x=1,y=1},{x=2,y=1},{x=3,y=1}})
 for i=1,3 do a.on[i]=1 end
 local function set(k,v) params:set('seq1'..k,v) end
 set('rate',rate);set('ratchetEnabled',2);set('ratchet',2);set('modEnabled',2)
 set('lfo1Shape',shape);set('lfo1Cycle',5);set('lfo1Mode',free and 2 or 1);set('lfo1Seconds',0.7)
 set('lfo1Dest1',8);set('lfo1Dest1Min',0);set('lfo1Dest1Max',4)
 set('lfo1Dest2',3);set('lfo1Dest2Min',20);set('lfo1Dest2Max',120)
 a.outputs=Outputs.new{metro=metro,time=function() return now end,
  engine={noteOn=function(note,hz,velocity) notes[#notes+1]={at=now,note=note,velocity=velocity} end,noteOff=function() end}}
 local play=a.outputs.play
 a.outputs.play=function(self,track,seq,n,repeats,seconds,slop,probability)
  bursts[#bursts+1]={at=now,track=track,ratchet=seq.ratchet,repeats=repeats,velocity=seq.velocity,seconds=seconds}
  return play(self,track,seq,n,repeats,seconds,slop,probability)
 end
 nextTick=clock.get_beat_sec()/8
 return a.sequencers[1],set
end
local function hold(x,row) key(x,row,1);advance(0.451);key(x,row,0) end
local function tap(x,row) key(x,row,1);advance(0.05);key(x,row,0) end
local function stop() playing=false;a.outputs:panic() end
local function finish()
 a.grid:stopFeedback();a.outputs:cleanup();assert(next(timers)==nil,'visual/output timers retired')
end
local tests={}
tests['72 timed cases hold sampled ratchet across six waves three BPMs two rates and both time modes']=function()
 local cases=0
 for _,tempo in ipairs({45,120,240}) do for _,rate in ipairs({1,2}) do for shape=1,6 do
  for _,free in ipairs({false,true}) do
   local seq=setup(tempo,rate,shape,free)
   advance(0.17);key(6,1,1);advance(0.451)
   local captured=a.modulation.applied[1].ratchet
   assert(a.modulation:frozen(1,'ratchet') and seq.ratchetEnabled)
   key(6,1,0);local from=#bursts+1;advance(2.1)
   for i=from,#bursts do assert(bursts[i].ratchet==captured and bursts[i].repeats==captured) end
   assert(a.modulation.applied[1].ratchet==captured,'zero rests also stay held')
   assert(seq.ratchet==2,'freeze does not overwrite EDIT base')
   hold(6,1);assert(not a.modulation:frozen(1,'ratchet') and seq.ratchetEnabled)
   advance(1.4);assert(a.modulation.applied[1].ratchet>=0 and a.modulation.applied[1].ratchet<=4)
   finish();cases=cases+1
  end
 end end end
 assert(cases==72)
end
tests['slow step freeze captures audible value rather than instantaneous oscillator']=function()
 local seq=setup(120,7,3,false)
 advance(1.02);local audible=a.modulation.applied[1].ratchet
 key(6,1,1);advance(0.451)
 local live=math.floor(((now/0.5)%1)*4+0.5)
 assert(audible~=live,'distinguish sampled step from instantaneous wave')
 assert(a.modulation.state[1].held.ratchet==audible)
 key(6,1,0);advance(3.2);assert(a.modulation.applied[1].ratchet==audible)
 assert(a.modulation:freeze(seq,1),'global hold adds velocity');finish()
end
tests['global and local controls interoperate while unrelated destinations keep moving']=function()
 setup(120,1,3,false);advance(0.1);hold(6,1)
 local held=a.modulation.state[1].held.ratchet;local values={}
 for i=1,10 do advance(0.07);values[a.modulation.applied[1].velocity]=true end
 local count=0;for _ in pairs(values) do count=count+1 end
 assert(count>2 and a.modulation.applied[1].ratchet==held)
 a.grid.view=3;hold(14,1);assert(a.modulation:frozen(1,'velocity'))
 local velocity=a.modulation.state[1].held.velocity
 a.grid.view=2;hold(6,1);assert(not a.modulation:frozen(1,'ratchet'))
 assert(not a.modulation:frozen(1,'probability'),'unmapped probability does not freeze')
 values={};for i=1,15 do advance(0.09);values[a.modulation.applied[1].ratchet]=true end
 count=0;for _ in pairs(values) do count=count+1 end
 assert(count>2 and a.modulation.applied[1].velocity==velocity)
 a.grid.view=3;hold(14,1);assert(a.modulation.state[1].held.velocity==velocity)
 hold(14,1);assert(not a.modulation:frozen(1));finish()
end
tests['ratchet gate manual base and intersection retrigger remain distinct']=function()
 local seq,set=setup(120,1,5,false)
 set('lfo1Dest1Min',4);set('lfo1Dest1Max',4);tap(6,1)
 assert(not seq.ratchetEnabled);local first=#bursts+1;advance(0.3)
 for i=first,#bursts do assert(bursts[i].repeats==1 and bursts[i].ratchet==4) end
 tap(6,1);first=#bursts+1;advance(0.3)
 for i=first,#bursts do assert(bursts[i].repeats==4) end
 set('ratchet',3);first=#bursts+1;advance(0.3)
 for i=first,#bursts do assert(bursts[i].repeats==4,'LFO replaces base; never adds it') end
 set('modEnabled',1);first=#bursts+1;advance(0.3)
 for i=first,#bursts do assert(bursts[i].repeats==3,'master off returns manual base') end
 set('modEnabled',2);tap(6,1)
 a.addNewSequence({{x=1,y=1},{x=2,y=1},{x=3,y=1}})
 params:set('seq2rate',1);params:set('seq2rhythm',2)
 for i=1,3 do a.on[i]=2 end
 set('rhythm',3);first=#bursts+1;advance(0.3);assert(#bursts>=first)
 for i=first,#bursts do assert(bursts[i].repeats==4,'intersection retrigger ignores continuous gate') end
 set('rhythm',1);first=#bursts+1;advance(0.3)
 for i=first,#bursts do assert(bursts[i].repeats==1) end
 finish()
end
tests['two LFOs on ratchet use last mapping and freeze the resulting output']=function()
 local seq,set=setup(90,2,3,false)
 set('lfo2Enabled',2);set('lfo2Shape',4);set('lfo2Cycle',5);set('lfo2Dest1',8)
 set('lfo2Dest1Min',1);set('lfo2Dest1Max',4)
 advance(0.8);hold(6,1);local held=a.modulation.state[1].held.ratchet
 local first=#bursts+1;advance(1.5)
 for i=first,#bursts do assert(bursts[i].repeats==held) end
 hold(6,1);advance(0.5)
 local applied=a.modulation.applied[1];local beat=bursts[#bursts].at/clock.get_beat_sec()
 assert(applied.ratchet==math.floor(1+3*(1-beat%1)+0.5));finish()
end
tests['queued output emits exactly the held number of strikes per complete burst']=function()
 local seq,set=setup(120,3,3,false)
 set('lfo1Dest1Min',3);set('lfo1Dest1Max',3);advance(0.8);hold(6,1)
 local from=#bursts+1;advance(2.2);local complete=0
 for i=from,#bursts-1 do
  local b,nextBurst=bursts[i],bursts[i+1];local strikes=0
  for _,note in ipairs(notes) do if note.at>=b.at-1e-8 and note.at<nextBurst.at-1e-8 then strikes=strikes+1 end end
  assert(strikes==3,'actual output queue stays locked');complete=complete+1
 end
 assert(complete>=6);finish()
end
tests['blink stays 2 Hz in stop or play and steady active pads have normal brightness']=function()
 for _,tempo in ipairs({45,240}) do
  local seq,set=setup(tempo,1,3,false);set('lfo1Dest1Min',2);set('lfo1Dest1Max',2)
  a.redraw();assert(leds[106]==15 and leds[102]==15)
  hold(6,1);frames={};advance(1.1)
  local transitions=0;local previous
  for _,frame in ipairs(frames) do
   local level=frame.leds[106];assert(level==0 or level==15)
   if previous~=nil and level~=previous then transitions=transitions+1 end;previous=level
  end
  assert(transitions>=3 and transitions<=5,'flash rate independent of BPM')
  stop();frames={};advance(1.1)
  local on,off=false,false
  for _,frame in ipairs(frames) do on=on or frame.leds[106]==15;off=off or frame.leds[106]==0 end
  assert(on and off,'flashes with stopped transport')
  a.grid.view=3;a.redraw();assert(leds[114]==(a.grid.blinkOn and 15 or 0))
  a.grid.view=1;frames={};advance(0.7);assert(#frames==0,'no canvas redraw')
  a.grid.view=2;a.grid.navHeld=true;frames={};advance(0.7);assert(#frames==0,'no navigation redraw')
  a.grid.navHeld=false;hold(6,1);a.redraw();assert(leds[106]==15)
  tap(6,1);a.redraw();assert(leds[106]==2)
  hold(6,1);frames={};advance(0.7);on,off=false,false
  for _,frame in ipairs(frames) do on=on or frame.leds[106]==15;off=off or frame.leds[106]==0 end
  assert(on and off and not seq.ratchetEnabled,'held-but-disabled is also visibly frozen')
  finish()
 end
end
tests['screen distinguishes actual values BASE LFO HOLD off and intersection-only use']=function()
 local seq,set=setup(120,1,3,false);advance(0.2);hold(6,1)
 local held=a.modulation.state[1].held.ratchet;a.redraw()
 assert(table.concat(texts,'|'):find('ratchet '..held..' HOLD',1,true))
 assert(drawn[32].text=='internal synth' and drawn[63].text:find('V',1,true))
 tap(6,1);a.redraw();assert(table.concat(texts,'|'):find('HOLD off',1,true))
 set('rhythm',3);a.redraw();assert(table.concat(texts,'|'):find('HOLD INT',1,true))
 a.grid.view=3;a.redraw();local info=table.concat(texts,'|')
 assert(info:find('HOLD 1/2',1,true))
 assert(info:find('x2  Poff  R'..held..' int',1,true),'intersection readout shows effective values and gates')
 assert(not info:find('pad 14',1,true) and not info:find('hold 15',1,true),'no shortcut hints in status rows')
 a.grid.view=2;hold(6,1);a.redraw();assert(table.concat(texts,'|'):find(' LFO INT',1,true))
 set('modEnabled',1);a.redraw();assert(table.concat(texts,'|'):find('ratchet 2 BASE INT',1,true));finish()
end
tests['navigation cancels pending holds and ownership change retires feedback timer only']=function()
 setup(120,1,3,false);stop();key(6,1,1);advance(0.2)
 key(16,8,1);advance(0.5);key(16,8,0);key(6,1,0)
 assert(not a.modulation:frozen(1) and a.sequencers[1].ratchetEnabled)
 local outputTimer=a.outputs.timer.id
 params=PS.new();advance(0.1)
 assert(a.grid.feedbackTimer==nil and timers[outputTimer])
 a.outputs:cleanup();assert(next(timers)==nil)
end
tests['probability freeze holds a percentage while draws remain random and its off gate bypasses them']=function()
 local seq,set=setup(120,1,3,false)
 set('ratchetEnabled',1);set('lfo1Dest1',2);set('lfo1Dest1Min',50);set('lfo1Dest1Max',50)
 local originalRandom=math.random;local draws=0
 math.random=function(max) assert(max==100);draws=draws+1;return draws%2==0 and 75 or 25 end
 tap(7,1);hold(7,1);local from=#bursts
 advance(1);local chanceBursts=#bursts-from
 assert(a.modulation:frozen(1,'probability') and a.modulation.applied[1].probability==50)
 assert(chanceBursts==8,'frozen percentage still draws a fresh decision each step')
 tap(7,1);from=#bursts;advance(1)
 assert(#bursts-from==16 and not seq.probabilityEnabled,'off bypasses probability, even if held')
 math.random=originalRandom;finish()
end
tests['long press without a mapping never signals a freeze or accidentally performs a short tap']=function()
 local seq,set=setup(120,1,3,false);stop()
 set('lfo1Dest1',1);set('lfo1Dest2',1)
 hold(6,1);assert(not a.modulation:frozen(1) and seq.ratchetEnabled)
 a.grid.view=3;hold(14,1);assert(not a.modulation:frozen(1) and seq.modEnabled)
 a.redraw();assert(leds[114]==15 and table.concat(texts,'|'):find('no targets',1,true))
 a.grid.view=2;key(6,1,1);advance(0.44);key(6,1,0)
 assert(not seq.ratchetEnabled,'release below threshold is a tap')
 set('lfo1Dest1',8);hold(6,1)
 assert(a.modulation:frozen(1,'ratchet') and not seq.ratchetEnabled,'freeze does not enable gate')
 finish()
end

tests['Lines has movement flags output probability ratchet and a grey row of mapped extras']=function()
 local seq,set=setup(120,1,3,false);stop()
 set('muted',2);set('solo',2);set('direction',3)
 set('lfo1Dest1',6);set('lfo1Dest1Min',-4);set('lfo1Dest1Max',4)
 set('lfo1Dest2',7);set('lfo1Dest2Min',-48);set('lfo1Dest2Max',48)
 set('lfo2Enabled',2);set('lfo2Dest1',4);set('lfo2Dest1Min',5);set('lfo2Dest1Max',4000)
 set('lfo2Dest2',3);set('lfo2Dest2Min',1);set('lfo2Dest2Max',127)
 a.redraw()
 assert(drawn[21].text=='pendulum x2 MUTE SOLO')
 assert(drawn[32].text=='internal synth')
 assert(drawn[43].text=='prob 75% BASE off')
 assert(drawn[54].text=='ratchet 2 BASE')
 local footer=drawn[63].text
 for _,label in ipairs({'O','T','L','V'}) do assert(footer:find(label,1,true)) end
 assert(drawn[63].level==5,'footer remains grey')
 set('muted',1);set('solo',1);a.redraw();assert(drawn[21].text=='pendulum x2')
 params:lookup_param('seq1nb').options[1]='fluid 1'
 set('output',3);assert(drawn[32].text=='n.b.: fluid 1')
 set('output',9);assert(drawn[32].text=='n.b. + MIDI: fluid 1')
 params:lookup_param('seq1nb').options[1]=string.rep('long voice name ',6)
 a.redraw();assert(#drawn[32].text<=30 and drawn[32].text:sub(-3)=='...','long voice names fit')
 set('output',10);assert(drawn[32].text=='internal synth + MIDI')
 set('lfo1Dest1',1);set('lfo1Dest2',1);set('lfo2Dest1',1);set('lfo2Dest2',1)
 assert(drawn[63].text=='','no unrelated base values in LFO footer')
 finish()
end
tests['live LFO readings refresh both pages while stopped without extra Grid frames']=function()
 local seq,set=setup(120,7,3,false)
 set('probabilityEnabled',2);set('probability',100)
 advance(1.02);stop();local applied=a.modulation.applied[1]
 a.grid.view=2;a.redraw();local first=drawn[63].text
 frames={};screenUpdates=0;advance(0.2)
 assert(drawn[63].text~=first,'velocity changes without new steps or encoder gestures')
 assert(#frames==0 and a.modulation.applied[1]==applied)
 assert(screenUpdates>=1 and screenUpdates<=3)
 set('lfo1Dest2',2);set('lfo1Dest2Min',0);set('lfo1Dest2Max',100)
 a.grid.view=3;a.redraw();first=drawn[63].text;advance(0.2)
 assert(drawn[63].text~=first,'Intersections shows live probability and ratchet')
 a.grid.previewKey=31;screenUpdates=0;advance(0.3)
 assert(screenUpdates==0,'live readouts do not replace a held track drawing')
 a.grid.previewKey=nil;a.grid.navHeld=true;advance(0.3);assert(screenUpdates==0)
 a.grid.navHeld=false;a.grid.view=1;advance(0.3);assert(screenUpdates==0)
 finish()
end
tests['frozen readings stay fixed while other destinations move and freeze captures the audible step']=function()
 local seq,set=setup(120,7,3,false);advance(1.02)
 local audible=a.modulation.applied[1].ratchet;stop();a.redraw()
 local before=drawn[54].text
 advance(0.2);assert(drawn[54].text~=before,'live ratchet moves between slow steps')
 hold(6,1);assert(a.modulation.state[1].held.ratchet==audible)
 local heldText=drawn[54].text;local moving=drawn[63].text
 advance(0.2);assert(drawn[54].text==heldText and drawn[63].text~=moving)
 a.grid.view=3;hold(14,1);local allHeld=drawn[63].text
 advance(0.7);a.redraw();assert(drawn[63].text==allHeld)
 assert(a.modulation.applied[1].ratchet==audible,'display never resamples the audible step')
 finish()
end
tests['opening live readouts cannot change note traces or random decisions including sample and hold']=function()
 local function trace(shape,free,visible)
  local seq,set=setup(120,2,shape,free);a.modulation.seed=991
  set('probabilityEnabled',2);set('probability',50)
  a.grid.view=visible and 2 or 1
  assert(next(a.modulation.state)==nil,'drawing before first note creates no LFO state')
  math.randomseed(781);advance(3)
  local rows={}
  for _,n in ipairs(notes) do rows[#rows+1]=string.format('%.5f:%d:%.5f',n.at,n.note,n.velocity) end
  rows[#rows+1]=tostring(math.random())
  local result=table.concat(rows,'|');finish();return result
 end
 for shape=1,6 do for _,free in ipairs({false,true}) do
  assert(trace(shape,free,false)==trace(shape,free,true),'display does not affect sound or chance random stream')
 end end
end

tests['chance can skip the first ratchet then play later slots at their original times']=function()
 local seq,set=setup(120,7,3,false);set('modEnabled',1)
 set('ratchet',4);set('probabilityEnabled',2);set('probability',50)
 local draws={};a.outputs.d.random=function(max)
  assert(max==100);draws[#draws+1]=now;return #draws%2==1 and 75 or 25
 end
 advance(1.92)
 assert(#bursts==1 and #draws==4 and #notes==2,'no whole-step gate before per-strike decisions')
 local start=bursts[1].at
 for i=1,4 do assert(math.abs(draws[i]-(start+(i-1)*0.25))<0.0051) end
 assert(math.abs(notes[1].at-(start+0.25))<0.0051)
 assert(math.abs(notes[2].at-(start+0.75))<0.0051)
 finish()
end
tests['LFO chance freeze and later menu edits retain the sampled percentage for an existing burst']=function()
 local seq,set=setup(120,7,3,false)
 set('ratchet',4);set('lfo1Dest1',2);set('lfo1Dest1Min',40);set('lfo1Dest1Max',40)
 set('probabilityEnabled',2);local draws=0
 a.outputs.d.random=function() draws=draws+1;return 50 end
 advance(1.02);hold(7,1)
 assert(a.modulation.state[1].held.probability==40)
 set('lfo1Dest1Min',100);set('lfo1Dest1Max',100);set('probability',100)
 assert(a.modulation:preview(seq,1).probability==40,'held percentage survives range/base edits')
 set('modEnabled',1);advance(0.44)
 assert(draws==4 and #notes==0,'existing slots still use sampled 40 percent')
 advance(0.1);assert(#notes==1,'next step takes new manual 100 percent')
 finish()
end
tests['intersection retrigger applies per-strike chance even with the continuous ratchet off']=function()
 local seq,set=setup(120,7,3,false);set('modEnabled',1)
 set('ratchetEnabled',1);set('ratchet',4);set('rhythm',3);set('harmonic',5)
 set('probabilityEnabled',2);set('probability',50)
 a.addNewSequence({{x=1,y=1},{x=2,y=1},{x=3,y=1}})
 params:set('seq2rate',7);params:set('seq2rhythm',2)
 for i=1,3 do a.on[i]=2 end
 local draws=0;a.outputs.d.random=function() draws=draws+1;return draws%2==1 and 75 or 25 end
 advance(1.92)
 assert(not seq.ratchetEnabled and #bursts==1 and bursts[1].repeats==4)
 assert(draws==4 and #notes==6,'two complete triad attacks pass, two skip')
 for i=1,3 do assert(notes[i].at==notes[1].at and notes[i+3].at==notes[4].at) end
 finish()
end

local count=0
for name,test in pairs(tests) do test();count=count+1;print('PASS '..name) end
print(count..'/'..count..' scheduled freeze simulation scenarios passed')
