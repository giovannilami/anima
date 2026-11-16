local nornsRoot=assert(arg[1])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util'
controlspec=require 'core/controlspec'
local starts,stops={},{}
_norns={metro_start=function(id) starts[id]=true end,
  metro_stop=function(id) stops[id]=true end,metro_set_time=function() end}
metro=require 'core/metro'
local L=dofile('lib/lifecycle.lua')
local oldFn=assert(load('return function() error("stale Animator LFO fired") end',
  '@/home/we/dust/code/animator/lib/hnds.lua'))()
local old=metro.init(oldFn);old:start()
local other=metro.init(function() end);other:start()
L.stop_stale_lfos(metro)
assert(not metro.assigned[old.id] and stops[old.id],'old Animator LFO stopped before new engine loads')
assert(metro.assigned[other.id] and not stops[other.id],'unrelated mod timer preserved')
print('PASS old Animator LFO retired without touching mod timers')
norns={state={shortname='anima'},pmap={data={}}}
params=require('core/paramset').new()
local hnds=dofile('lib/hnds.lua')
hnds.init()
local lfoTimer
for id,timer in pairs(metro.metros) do
 if metro.assigned[id] and timer~=other then lfoTimer=timer end
end
assert(lfoTimer)
params:clear()
assert(pcall(lfoTimer.event),'timer does not read removed parameters during script change')
assert(stops[lfoTimer.id],'guard stops invalid LFO callback')
hnds.cleanup();hnds.cleanup()
assert(not metro.assigned[lfoTimer.id],'explicit LFO cleanup is idempotent')
print('PASS real norns metro and LFO cleanup after parameter reset')
local steps=0
L.run{{'broken',function() error('simulated cleanup failure') end},
  {'next resource',function() steps=steps+1 end}}
assert(steps==1,'one failure cannot skip remaining cleanup steps')
print('PASS remaining cleanup steps run after an error')
