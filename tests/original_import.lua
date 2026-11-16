-- Stock Animator count() is the reference, with saved snapshot arrays restored.
-- Optional args 4/5: original .doodle and converted-data directory.
local nr,oldRoot,data=assert(arg[1]),assert(arg[2]),assert(arg[3])
package.path=nr..'/lua/?.lua;'..nr..'/lua/lib/?.lua;'..package.path
util=require 'util';local tab=require 'tabutil';local PS=require 'core/paramset';local Music=require 'musicutil'
norns={state={shortname='anima',data=data..'/'},pmap={data={}}}
local function inc(p) return dofile(p:gsub('^anima/','')..'.lua') end
include=inc
local Original=inc('lib/original');local C=inc('lib/constants');local S=inc('lib/track_settings')
local O=inc('lib/outputs');local copy=inc('lib/helpers').deepcopy
package.preload.fileselect=function() return {} end
package.preload.textentry=function() return {} end
package.preload['molly_the_poly/lib/molly_the_poly_engine']=function() return {} end
local function parse(path)
 local t={};for l in io.lines(path) do local k,v=l:match('^"([%w_/]+)":%s*(.*)');if k then t[k]=tonumber(v) or v end end;return t
end
local function hardware()
 local now,id=0,0;local timers,trace={},{}
 local function event(kind,...) trace[#trace+1]={at=now,key=kind..':'..table.concat({...},':')} end
 engine={noteOn=function(n,f,v) event('on',n,string.format('%.6f',f),string.format('%.12f',v)) end,
 noteOff=function(n) event('off',n) end}
 midi={vports={},connect=function(port) return {note_on=function(_,n,v,ch) event('m-on',port,n,v,ch) end,
 note_off=function(_,n,v,ch) event('m-off',port,n,ch) end} end}
 crow={output={{},{},{},{}},ii={jf={play_note=function() end},er301={cv=function() end,tr_pulse=function() end}}}
 clock={get_beat_sec=function() return 0.5 end}
 metro={init=function(fn,time,count)
  id=id+1;local m={id=id,event=fn,time=time,count=count};timers[id]=m
  function m:start() self.running=true;self.at=now+self.time end
  function m:stop() self.running=false end
  return m
 end,free=function(n) timers[n]=nil end}
 local function flush(target)
  while true do
   local t,k=math.huge
   for key,m in pairs(timers) do if m.running and m.at<t then t,k=m.at,key end end
   if t>target+1e-10 then break end
   now=t;local m=timers[k]
   if m.count==1 then m.running=false else m.at=m.at+m.time end;m.event()
  end;now=target
 end
 return trace,flush,function(t) now=t end,function() return now end
end
local function parameters(v,original)
 params=PS.new()
 for _,k in ipairs({'slop','max_notes','scale','global_transpose','min_velocity','max_velocity','min_note_length','max_note_length','output','ER_port'}) do
  params:add_number(k,k,-1000,1000,v[k] or 0)
 end
 if original then for i=1,8 do
  params:add_number('seq'..i..'div','div',1,8,1)
  params:add_number('seq'..i..'intersect','rule',1,6,1)
  params:add_number('seq'..i..'channel','ch',1,16,i)
 end end
end
local function run(raw,v,slot,route,modern,path)
 local trace,flush,setTime,time=hardware();parameters(v,not modern);local a
 if modern then
  include=inc;a=inc('lib/animator');S.add(a)
  a.grid={snapshot=0,selected=1,patternManager={rebuildPatterns=function() end,patterns={}}}
  a.outputs=O.new{engine=engine,midi=midi,crow=crow,metro=metro,time=time}
  if not path then
   local d=Original.convert(raw,v)
   for _,scene in ipairs({d,d.snapshots[1]}) do
    for _,s in ipairs(scene.sequencers) do s.output=route end
    for _,s in ipairs(scene.trackSettings) do s.output=route end
   end
   path=data..'/original-fixture.doodle';assert(not tab.save(d,path))
  end
  a.load(path);if slot then a.handleSelectSnapshot{i=slot} end
 else
  include=function(p) return dofile(oldRoot..'/'..p:gsub('^animator/','')..'.lua') end
  a=include('lib/animator');local Seq=include('lib/Sequencer');local scene=copy(slot and raw.snapshots[slot] or raw)
  a.on=scene.on;a.enabled=scene.enabled;params:set('output',route==2 and 1 or (route==4 and 2 or 3))
  for i,s in ipairs(scene.sequencers) do
   params:set('seq'..i..'div',scene.divs and scene.divs[i] or s.div)
   params:set('seq'..i..'intersect',scene.intersects and scene.intersects[i] or s.intersect)
   params:set('seq'..i..'channel',s.channel or v['seq'..i..'channel'] or i)
   a.sequencers[i]=Seq.new(s,i)
  end
  a.midiDevice=midi.connect(v.midi_out_device or 1)
 end
 local scale=Music.generate_scale(24+(v.global_transpose or 0),v.scale or 1,6)
 a.notes={};local pointer=0
 for y=7,1,-1 do for x=1,16 do a.notes[(y-1)*16+x]=scale[pointer+x] end;pointer=pointer+3 end
 local states={};math.randomseed(9407)
 for tick=1,512 do
  local t=tick*0.125
  if modern then flush(t-0.0625);setTime(t-0.0625);a.count() end
  flush(t-1e-8);setTime(t);a.count();flush(t)
  local state={tostring(a.shouldResetAll)}
  for _,s in ipairs(a.sequencers) do state[#state+1]=table.concat({s.index,modern and math.floor((s.rateCount+1)/2) or s.divCount,tostring(s.reset)},':') end
  states[tick]=table.concat(state,'|')
 end
 flush(64.2);local random=math.random()
 if modern then a.outputs:cleanup() end;include=inc
 return trace,states,random
end
local function compare(raw,v,slot,route,path)
 local old,os,orr=run(raw,v,slot,route,false)
 local new,ns,nrr=run(raw,v,slot,route,true,path)
 for i,s in ipairs(os) do assert(ns[i]==s,'playhead/rate/reset at '..i..' expected '..s..' got '..ns[i]) end
 assert(orr==nrr,'different articulation random draws')
 local function group(trace)
  local g={};for _,e in ipairs(trace) do g[e.key]=g[e.key] or {};table.insert(g[e.key],e.at) end;return g
 end
 local expected,actual=group(old),group(new)
 assert(#old==#new,'event count '..#old..' / '..#new)
 for key,events in pairs(expected) do
  assert(actual[key] and #events==#actual[key],'note/channel/velocity: '..key)
  for i,t in ipairs(events) do assert(math.abs(t-actual[key][i])<=0.00501,'timing '..key..' '..t..' '..actual[key][i]) end
 end
 return #old
end
local on,enabled={},{};for i=1,112 do on[i]=0;enabled[i]=0 end
local lines={};for i=1,8 do
 lines[i]={steps={{x=1,y=1},{x=2,y=1}},div=i,divCount=i,index=i%2+1,channel=i,intersect=(i-1)%6+1}
end
on[1],on[2],enabled[1],enabled[2]=8,8,8,8
local raw={name='original-fixture',on=on,enabled=enabled,sequencers=lines,snapshots={},patterns={},selectedSnapshot=0}
raw.snapshots[1]={on=on,enabled=enabled,sequencers=copy(lines),divs={8,7,6,5,4,3,2,1},intersects={6,5,4,3,2,1,2,3}}
local v={output=3,midi_out_device=1,min_velocity=15,max_velocity=90,min_note_length=0.01,max_note_length=0.13,max_notes=6,slop=0,scale=1,global_transpose=0}
local d=Original.convert(raw,v)
assert(d.snapshots[1].rates[2]==9 and d.snapshots[1].rates[4]==8)
for _,scene in ipairs({d,d.snapshots[1]}) do for _,seq in ipairs(scene.sequencers) do
 assert(not seq.modEnabled and not seq.ratchetEnabled and not seq.probabilityEnabled and not seq.muted and not seq.solo)
end end
assert(C.GRID_RATE_COUNT==7 and C.RATE_TICK_DIVS[8]==10 and C.RATE_TICK_DIVS[9]==14)
print('PASS original import retains exact divisions and neutral new controls')
compare(raw,v,nil,4);print('PASS original playback matches all eight divisions and cumulative intersections')
compare(raw,v,1,2);print('PASS snapshot arrays override stale caches with matching internal synth events')
-- Recall after a half tick must not move the next original pulse by 1/8.
include=inc;parameters(v,false)
local phaseTest=inc('lib/animator');S.add(phaseTest)
phaseTest.grid={snapshot=0,selected=1,patternManager={rebuildPatterns=function() end,patterns={}}}
local phasePath=data..'/original-phase.doodle';assert(not tab.save(d,phasePath));phaseTest.load(phasePath)
phaseTest.originalPlayback.phase=1;phaseTest.handleSelectSnapshot{i=1}
for _,seq in ipairs(phaseTest.sequencers) do assert(seq.rateCount%2==0,'half-tick alignment') end
phaseTest.handleSelectSnapshot{i=2}
assert(phaseTest.snapshots[2].originalPhase==1)
phaseTest.originalPlayback.phase=0;phaseTest.handleSelectSnapshot{i=2}
for _,seq in ipairs(phaseTest.sequencers) do assert(seq.rateCount%2==1,'stored phase alignment') end
print('PASS original snapshots retain clock alignment when recalled between pulses')
if arg[4] then
 local source=arg[4];local user=assert(tab.load(source));local settings=parse(source:gsub('%.doodle$','.pset'))
 local total=0
 for _,route in ipairs({10,2}) do
  local name=route==10 and 'ANIMA_01_ORIGINAL' or 'ANIMA_01_INTERNAL'
  for slot=0,8 do
   local n=compare(user,settings,slot>0 and slot or nil,route,assert(arg[5])..'/'..name..'.doodle');total=total+n
   print('PASS '..name..' '..(slot==0 and 'live' or 'snapshot '..slot)..': '..n..' matching note events')
  end
 end
 print('Actual preset matching events: '..total)
end
