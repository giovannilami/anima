local nornsRoot=assert(arg[1])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
local now=0
util=require 'util';util.time=function() return now end
local timers={}
metro={init=function(fn)
  local timer={id=#timers+1,event=fn,start=function() end,stop=function() end}
  timers[timer.id]=timer;return timer
end,free=function(id) timers[id]=nil end}
include=function(path) return dofile(path:gsub('^anima/','')..'.lua') end
local PM=include('anima/lib/PatternManager')
local manager=PM.new{callbacks={}}
local pattern=manager.patterns[1]
pattern:rec_start()
now=10;pattern:watch({i=1,type='snapshot'})
now=10.25;pattern:watch({i=8,type='snapshot'})
now=10.75
local saved=manager:exportPatterns()
assert(saved[1].metro==nil and saved[1].process==nil)
assert(saved[1].count==2 and saved[1].time[1]==0.25 and saved[1].time[2]==0.5)
manager:rebuildPatterns(saved)
assert(manager.patterns[1].count==2 and manager.patterns[1].event[2].i==8)
assert(manager.patterns[1].rec==0 and manager.patterns[1].play==0)
manager.patterns[2].count=9
manager:rebuildPatterns(saved)
assert(manager.patterns[2].count==0,'empty saved slots clear previous runtime pattern')
saved[3]={count=1,event={{i=4,type='snapshot'}},time={1}}
saved[4]={count=1,event={{i=5,type='snapshot'}},time={2}}
manager:rebuildPatterns(saved)
assert(#manager.patterns==2,'only two active recorders allocate timers')
local migrated=manager:exportPatterns()
assert(migrated[3].event[1].i==4 and migrated[4].event[1].i==5,'legacy hidden patterns survive import and export')
manager:cleanup()
assert(next(timers)==nil)
print('PASS real snapshot pattern recording export reload and timer cleanup')
