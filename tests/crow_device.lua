-- Run the actual norns serial bridge against Crow's actual output.lua.
-- Only native ASL/voltage generation is simulated; firmware setters are real.
-- lua tests/crow_device.lua /path/to/norns /path/to/crow/lua/output.lua
local nornsRoot,firmwarePath=assert(arg[1]),assert(arg[2])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
local Outputs=dofile(arg[3] or 'lib/outputs.lua')
local function setup()
  local pulses,actions,commands={},{},{}
  local device=setmetatable({},{__index=_G})
  device.input=setmetatable({},{__index=function() error('must preserve Crow clock input') end})
  device.pulse=function() return {kind='pulse',time=0.01,level=5} end
  device.to=function(volts) return {kind='constant',level=volts} end
  device.asl={new=function(channel)
    return {describe=function(_,action) actions[channel]=action end,
      action=function()
        local action=assert(actions[channel],'no action configured')
        if action.kind=='pulse' then
          pulses[#pulses+1]={channel=channel,time=action.time,level=action.level}
        end
      end}
  end}
  -- Firmware resolves ASL strings with load(); keep them in its own VM.
  device.load=function(chunk) return load(chunk,'crow ASL','t',device) end
  local Output=assert(loadfile(firmwarePath,'t',device))()
  device.output={}
  for channel=1,4 do device.output[channel]=Output.new(channel) end
  norns={}
  _norns={crow_send=function(_,command)
    commands[#commands+1]=command
    assert(load(command,'norns -> crow','t',device))()
  end}
  local bridge=dofile(nornsRoot..'/lua/core/crow.lua')
  norns.crow.dev=1
  local now=0
  local router=Outputs.new{crow=bridge,time=function() return now end,
    metro={init=function() return {start=function() end,stop=function() end} end,free=function() end}}
  local function advance(seconds) now=now+seconds;router:tick() end
  return router,pulses,actions,advance,commands,device
end
local function seq(output) return {output=output,channel=1,duration=100,velocity=100} end
local function strike(router,track,output,notes)
  router:play(track,seq(output),notes or {60,64},1,1,0)
end
local function assertPulses(pulses,count)
  assert(#pulses==count,'expected '..count..' hardware pulses, got '..#pulses)
  for _,pulse in ipairs(pulses) do
    assert(pulse.time==0.01 and pulse.level==5,'original 10ms +5V pulse')
  end
end

do
  local router,pulses,actions=setup()
  for cycle=1,4 do
    router:begin_step();strike(router,1,11)
    assertPulses(pulses,cycle*2)
    router:panic()
    assert(actions[2].kind=='constant' and actions[4].kind=='constant',
      'actual firmware must replace ASL when panic writes volts')
  end
  print('PASS real Crow firmware: pulses survive repeated panic and resume')
end
do
  local router,pulses,actions,advance=setup()
  strike(router,1,11)
  strike(router,1,5,{67});strike(router,2,6,{72})
  router:begin_step();strike(router,3,11)
  assertPulses(pulses,4)
  advance(0.11)
  assert(actions[2].kind=='pulse' and actions[4].kind=='pulse','no stale fixed gate releases')
  print('PASS real Crow firmware: fixed gates cannot silence original triggers')
end
do
  local router,pulses,actions,_,commands,device=setup()
  strike(router,1,11)
  -- A reconnect/reset loses Crow's ASL even if the host router survives.
  device.output[2].volts=0;device.output[4].volts=0
  router:begin_step();strike(router,1,11)
  assertPulses(pulses,4)
  for _,command in ipairs(commands) do
    assert(not command:find('input',1,true),'leave the external clock input alone')
  end
  print('PASS real Crow firmware: pulses restore after remote action reset')
end
print('3/3 real Crow firmware checks passed')
