local nornsRoot,dataDir=assert(arg[1]),assert(arg[2])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util';tab=require 'tabutil'
norns={state={data=dataDir..'/',shortname='anima'},pmap={data={}}}
local now,beats=0,0
util.time=function() return now end
clock={get_beat_sec=function() return 0.5 end}
package.preload.fileselect=function() return {} end
package.preload.textentry=function() return {} end
package.preload['molly_the_poly/lib/molly_the_poly_engine']=function() return {} end
include=function(path)
 path=path:gsub('^anima/','')
 if path=='lib/lfo' then return {} end
 return dofile(path..'.lua')
end
local PS=require 'core/paramset'
local Mod=include('lib/modulation')
local S=include('lib/track_settings')
local function setup()
 params=PS.new();now=0;beats=0
 local a=include('lib/animator');S.add(a)
 params:add_number('slop','slop',0,500,0);params:add_number('max_notes','max',1,10,10)
 a.grid={snapshot=0,selected=1,patternManager={patterns={},rebuildPatterns=function() end}}
 a.notes={};for i=1,112 do a.notes[i]=60 end
 a.addNewSequence({{x=1,y=1},{x=2,y=1},{x=3,y=1}})
 for i=1,3 do a.on[i]=1 end
 a.modulation=Mod.new{time=function() return now end,beats=function() return beats end,random=function() return 0.25 end}
 return a,a.sequencers[1]
end
local function set(key,value) params:set('seq1'..key,value) end
local function route(slot,dest,target,low,high)
 set('lfo'..slot..'Dest'..dest,target)
 if low then set('lfo'..slot..'Dest'..dest..'Min',low) end
 if high then set('lfo'..slot..'Dest'..dest..'Max',high) end
end
local tests={}
tests['four mappings are bounded and leave all base values untouched']=function()
 local a,seq=setup();set('modEnabled',2);set('lfo1Shape',3);set('lfo1Cycle',5)
 set('lfo2Enabled',2);set('lfo2Shape',5);set('lfo2Cycle',5)
 route(1,1,5,2,7);route(1,2,6,-1,1);route(2,1,2,20,80);route(2,2,8,1,4)
 local bases={rate=seq.rate,transpose=seq.transpose,ratchet=seq.ratchet,probability=seq.probability}
 for _,beat in ipairs({0,0.25,0.5,0.75,1,12.25}) do
  beats=beat;local e=a.modulation:effective(seq,1)
  assert(e.rate>=2 and e.rate<=7 and e.octave>=-1 and e.octave<=1)
  assert(e.ratchet>=1 and e.ratchet<=4 and e.probability>=20 and e.probability<=80)
  for key,value in pairs(bases) do assert(seq[key]==value and params:get('seq1'..key)==value) end
 end
 set('modEnabled',1);local e=a.modulation:effective(seq,1)
 for key,value in pairs(bases) do assert(e[key]==value) end
end
tests['target freeze holds only its mapped value and global freeze holds all mapped values']=function()
 local a,seq=setup();set('modEnabled',2);set('lfo1Shape',3);set('lfo1Cycle',5)
 route(1,1,2,0,100);route(1,2,8,1,4)
 beats=0.25;local initial=a.modulation:effective(seq,1)
 assert(a.modulation:freeze(seq,1,'probability'))
 beats=0.75;local nextValue=a.modulation:effective(seq,1)
 assert(nextValue.probability==initial.probability and nextValue.ratchet~=initial.ratchet)
 assert(a.modulation:freeze(seq,1));local held=a.modulation:effective(seq,1)
 set('velocity',50);beats=1.1;local other=a.modulation:effective(seq,1)
 assert(other.ratchet==held.ratchet and other.velocity==50,'unmapped manual values remain editable')
 assert(not a.modulation:freeze(seq,1));assert(not a.modulation:frozen(1,'probability'))
 local resumed=a.modulation:effective(seq,1)
 assert(resumed.probability~=initial.probability)
end
tests['free seconds and all waveforms sample independently of clock']=function()
 local a,seq=setup();set('modEnabled',2);route(1,1,3,1,127);set('lfo1Mode',2);set('lfo1Seconds',1)
 for shape=1,6 do
  set('lfo1Shape',shape)
  for _,time in ipairs({0,0.25,0.5,0.99,1,2.5}) do
   now=time;beats=100
   local e=a.modulation:effective(seq,1);assert(e.velocity>=1 and e.velocity<=127)
  end
 end
 set('lfo1Shape',3);now=0;local first=a.modulation:effective(seq,1).velocity
 now=0.5;assert(a.modulation:effective(seq,1).velocity>first)
end
tests['snapshot and restart restore oscillator settings and target ranges but not frozen values']=function()
 local a,seq=setup();set('modEnabled',2);route(1,1,6,-2,3);route(2,1,4,10,1700)
 set('lfo2Enabled',2);set('lfo2Seconds',7.5)
 a.handleSelectSnapshot{i=1};a.modulation:freeze(seq,1)
 route(1,1,8,1,4);a.handleSelectSnapshot{i=2}
 a.handleSelectSnapshot{i=1};seq=a.sequencers[1]
 assert(seq.lfo1Dest1==6 and seq.lfo1Dest1Min==-2 and seq.lfo1Dest1Max==3)
 assert(not a.modulation:frozen(1))
 assert(a.save('anima-mod'))
 a=setup();a.load(dataDir..'/anima-mod.doodle');a.handleSelectSnapshot{i=1}
 seq=a.sequencers[1]
 assert(seq.modEnabled and seq.lfo2Enabled and seq.lfo2Seconds==7.5)
 assert(seq.lfo1Dest1Min==-2 and seq.lfo1Dest1Max==3)
 params:lookup_param('seq1lfo1Dest1'):bang()
 assert(params:get('seq1lfo1Dest1Min')==-2,'same-target bang must preserve the saved range')
end
tests['rate changes latch at boundaries and each ratchet burst keeps its sampled articulation']=function()
 local a,seq=setup();set('rate',2);set('modEnabled',2);set('lfo1Shape',5);set('lfo1Cycle',5)
 route(1,1,5,2,7);route(1,2,8,1,4);set('ratchetEnabled',2)
 local emitted={}
 a.outputs={stop_track=function() end,play=function(_,track,e,notes,repeats,seconds)
  emitted[#emitted+1]={e=e,repeats=repeats,seconds=seconds}
 end}
 a.count();a.count();assert(#emitted==1 and emitted[1].repeats==1)
 beats=0.75;a.count();assert(#emitted==1,'new rate cannot advance in the middle of a step')
 a.count();assert(#emitted==2 and emitted[2].repeats==4 and emitted[2].e.rate==7)
 assert(emitted[1].repeats==1 and emitted[1].e.rate==2,'queued strike keeps original values')
 for i=1,15 do a.count() end
 assert(#emitted==2);a.count();assert(#emitted==3,'slow rate lasts its complete 16-tick interval')
end
tests['old Animator 2 snapshots import with modulation off even after using new LFOs']=function()
 local a,seq=setup();a.handleSelectSnapshot{i=1};assert(a.save('old-anima-import'))
 local file=dataDir..'/old-anima-import.doodle'
 local old=assert(tab.load(file));old.formatVersion=3
 local function strip(value)
  if type(value)~='table' then return end
  for key,child in pairs(value) do
   if type(key)=='string' and (key:match('^lfo%d') or key=='modEnabled' or key=='editId') then value[key]=nil
   else strip(child) end
  end
 end
 strip(old);assert(not tab.save(old,file))
 local pset=dataDir..'/old-anima-import.pset'
 local f=assert(io.open(pset,'r'));local lines={}
 for line in f:lines() do
  if not line:match('^"seq%d+lfo') and not line:match('^"seq%d+modEnabled') then lines[#lines+1]=line end
 end
 f:close();f=assert(io.open(pset,'w'));f:write(table.concat(lines,'\n'));f:close()
 set('modEnabled',2);route(1,1,5,1,7)
 a.load(file);assert(not a.sequencers[1].modEnabled)
 a.handleSelectSnapshot{i=1};assert(not a.sequencers[1].modEnabled)
 assert(a.sequencers[1].lfo1Dest1==1 and a.sequencers[1].rate==2)
end

tests['eight tracks and sixteen oscillators keep bounded state over long playback']=function()
 local a=setup()
 for i=2,8 do a.addNewSequence({{x=1,y=i%7+1},{x=2,y=i%7+1}}) end
 for track=1,8 do
  for _,pair in ipairs({{'modEnabled',2},{'lfo1Shape',6},{'lfo2Enabled',2},{'lfo2Shape',3},
   {'lfo1Dest1',5},{'lfo1Dest2',6},{'lfo2Dest1',2},{'lfo2Dest2',8},{'ratchetEnabled',2}}) do
   params:set('seq'..track..pair[1],pair[2])
  end
 end
 for pos=1,112 do if a.enabled[pos]>0 then a.on[pos]=a.enabled[pos] end end
 local count=0;a.outputs={stop_track=function() end,play=function(_,track,e,notes,repeats)
  assert(e.rate>=1 and e.rate<=7 and repeats>=1 and repeats<=4);count=count+1
 end}
 for tick=1,6000 do beats=tick/8;now=beats*0.5;a.count() end
 assert(count>1000,'all lines continue sounding')
 local states=0;for _ in pairs(a.modulation.state) do states=states+1 end
 assert(states==8,'oscillator state stays bounded by track count')
end

tests['LFO ratchet reaches zero rests then resumes and freeze can hold zero']=function()
 local a,seq=setup();set('rate',1);set('ratchet',2);set('ratchetEnabled',2)
 set('modEnabled',2);set('lfo1Shape',5);set('lfo1Cycle',5);route(1,1,8,0,4)
 local bursts={};a.outputs={panic=function() end,stop_track=function() end,play=function(_,track,e,notes,repeats)
  bursts[#bursts+1]=repeats
 end}
 beats=0;a.count();assert(#bursts==0 and a.modulation.applied[1].ratchet==0)
 assert(a.modulation:freeze(seq,1,'ratchet'))
 beats=0.75;a.count();assert(#bursts==0,'frozen zero remains silent')
 assert(not a.modulation:freeze(seq,1,'ratchet'))
 a.count();assert(#bursts==1 and bursts[1]==4,'unfreezing resumes positive retrigger count')
 a.handleSelectSnapshot{i=1};set('ratchet',0);a.handleSelectSnapshot{i=2}
 assert(a.save('ratchet-zero'))
 a=setup();a.load(dataDir..'/ratchet-zero.doodle');a.handleSelectSnapshot{i=2}
 assert(a.sequencers[1].ratchet==0 and a.sequencers[1].lfo1Dest1Min==0,'snapshot persists zero and LFO range')
end

tests['global and local freeze share destinations and report only actual mappings']=function()
 local a,seq=setup();set('modEnabled',2);set('lfo1Shape',3);set('lfo1Cycle',5)
 route(1,1,8,0,4);route(1,2,3,20,120)
 beats=0.25;assert(a.modulation:freeze(seq,1))
 assert(not a.modulation:frozen(1,'probability'),'unmapped probability must not flash')
 assert(a.modulation:frozen(1),'any target hold must report globally')
 local old=a.modulation:effective(seq,1)
 assert(not a.modulation:freeze(seq,1,'ratchet'),'local hold releases global ratchet')
 beats=0.9;local nextValue=a.modulation:effective(seq,1)
 assert(nextValue.ratchet~=old.ratchet and nextValue.velocity==old.velocity)
 local held,mapped=a.modulation:holdCounts(seq,1);assert(held==1 and mapped==2)
 assert(a.modulation:freeze(seq,1),'global hold completes a partial freeze')
 assert(a.modulation:effective(seq,1).velocity==old.velocity,'already held target stays unchanged')
 assert(not a.modulation:freeze(seq,1) and not a.modulation:frozen(1),'next global hold releases all')
end
tests['unmapped and disabled oscillators cannot leave phantom freezes while stopped']=function()
 local a,seq=setup();set('modEnabled',2)
 assert(not a.modulation:freeze(seq,1) and not a.modulation:frozen(1))
 route(1,1,8,0,4);assert(a.modulation:freeze(seq,1,'ratchet'))
 route(1,1,3,20,120);assert(not a.modulation:frozen(1,'ratchet'))
 route(1,1,8,0,4);assert(not a.modulation:frozen(1),'reassignment does not revive an old hold')
 assert(a.modulation:freeze(seq,1));set('lfo1Enabled',1)
 assert(not a.modulation:frozen(1),'disabling last mapped oscillator clears its holds')
end

local count=0
for name,test in pairs(tests) do test();count=count+1;print('PASS '..name) end
print(count..'/'..count..' modulation scenarios passed')
