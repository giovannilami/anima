-- Compare emitted CV/action commands against an unmodified Animator checkout.
-- lua tests/crow_compat.lua /path/to/norns /path/to/original/animator
local nornsRoot,originalRoot=assert(arg[1]),assert(arg[2])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util'
local ParamSet=require 'core/paramset'
local function hardware()
  local trace,now={},0
  crow={ii={jf={play_note=function() end},er301={cv=function() end,tr_pulse=function() end}},
    input=setmetatable({},{__index=function() error('clock input must not be accessed') end}),output={}}
  for i=1,4 do
    local index=i
    local state={}
    local output={execute=function()
      trace[#trace+1]=string.format('%.4f pulse %d %s',now,index,tostring(state.action))
    end}
    setmetatable(output,{__index=state,__newindex=function(_,key,value)
      state[key]=value
      if key=='volts' then trace[#trace+1]=string.format('%.4f cv %d %.12f',now,index,value) end
    end})
    crow.output[i]=output
  end
  engine={noteOn=function() end,noteOff=function() end}
  metro={init=function() return {start=function() end,stop=function() end} end,free=function() end}
  clock={get_beat_sec=function() return 0.5 end}
  return trace,function(seconds) now=seconds end
end
local function commonParams(outputs)
  params=ParamSet.new()
  params:add_number('slop','slop',0,500,0)
  params:add_number('max_notes','max notes',1,10,6)
  if outputs then
    params:add_option('output','output',outputs,5)
    for _,id in ipairs({'min_velocity','max_velocity'}) do params:add_number(id,id,1,127,100) end
    for _,id in ipairs({'min_note_length','max_note_length'}) do params:add_number(id,id,0,1,0.1) end
    params:add_number('ER_port','ER301',1,100,1)
  end
end
local function prepare(a,fixture)
  a.notes={}
  for pos=1,112 do a.notes[pos]=fixture.samePitch and 60 or 48+(pos%24) end
  a.redraw=function() end
  for i,line in ipairs(fixture.lines) do
    if fixture.original then
      params:set('seq'..i..'div',line.div or 1)
      params:set('seq'..i..'channel',line.channel or 1)
    end
    a.addNewSequence(line.steps)
    if not fixture.original then
      params:set('seq'..i..'output',11)
      params:set('seq'..i..'rate',({2,3,4,5})[line.div or 1])
      params:set('seq'..i..'channel',line.channel or 1)
    end
    for _,point in ipairs(line.steps) do a.on[(point.y-1)*16+point.x]=1 end
  end
end
local function original(fixture)
  local trace,time=hardware()
  include=function(path) return dofile(originalRoot..'/'..path:gsub('^animator/','')..'.lua') end
  local constants=include('lib/constants')
  commonParams(constants.OUTPUTS)
  for i=1,8 do
    params:add_number('seq'..i..'div','div',1,8,1)
    params:add_option('seq'..i..'intersect','rule',constants.INTERSECT_OPS,1)
    params:add_number('seq'..i..'channel','channel',1,16,1)
  end
  local a=include('lib/animator')
  crow.output[2].action='pulse()';crow.output[4].action='pulse()'
  fixture.original=true;prepare(a,fixture)
  for tick=1,12 do time(tick/8);a.count() end
  return trace
end
local function current(fixture)
  local trace,time=hardware()
  include=function(path)
    path=path:gsub('^anima/','')
    if path=='lib/lfo' then return {} end
    return dofile(path..'.lua')
  end
  commonParams()
  local a=include('lib/animator')
  include('lib/track_settings').add(a)
  local Outputs=include('lib/outputs')
  a.outputs=Outputs.new{crow=crow,engine=engine,metro=metro,time=function() return 0 end}
  fixture.original=false;prepare(a,fixture)
  for tick=1,24 do time(tick/16);a.count() end
  return trace
end
local function line(row,div,channel)
  return {steps={{x=1,y=row},{x=2,y=row},{x=3,y=row}},div=div,channel=channel}
end
local fixtures={
 {name='one line uses 1/2 every time',lines={line(1)}},
 {name='two lines share both pairs',lines={line(1),line(2)}},
 {name='third simultaneous note is ignored',lines={line(1),line(2),line(3)}},
 {name='duplicate pitches on one channel collapse',samePitch=true,lines={line(1),line(2),line(3)}},
 {name='same pitch on different channels uses both pairs',samePitch=true,lines={line(1,1,1),line(2,1,2)}},
 {name='coincident neutral lines make one trigger',lines={line(1),line(1)}},
 {name='slower rates preserve allocation and phase',lines={line(1,1),line(2,3),line(3,2)}},
}
norns={state={shortname='anima'},pmap={data={}}}
for _,fixture in ipairs(fixtures) do
  local expected,actual=original(fixture),current(fixture)
  assert(#actual==#expected,fixture.name..': different command count '..#actual..' / '..#expected)
  for i,entry in ipairs(expected) do assert(actual[i]==entry,fixture.name..': command '..i..'\nexpected '..entry..'\ngot '..tostring(actual[i])) end
  print('PASS original Crow trace matches: '..fixture.name)
end
print(#fixtures..'/'..#fixtures..' original Crow trace comparisons passed')
