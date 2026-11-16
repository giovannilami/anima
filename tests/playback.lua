-- Run from the repository root:
-- lua tests/playback.lua /path/to/norns /path/to/existing/test-data-directory
local nornsRoot, dataDir = assert(arg[1]), assert(arg[2])
package.path = nornsRoot .. '/lua/?.lua;' .. nornsRoot .. '/lua/lib/?.lua;' .. package.path
util = require 'util'
norns = {state = {data = dataDir .. '/', shortname = 'anima'}, pmap = {data = {}}}
package.preload.fileselect = function() return {} end
package.preload.textentry = function() return {} end
package.preload['molly_the_poly/lib/molly_the_poly_engine'] = function() return {} end

local played = {}
engine = {
  noteOn=function(note) played[#played+1] = note end,
  noteOff=function() end
}
clock = {get_beat_sec=function() return 0.5 end}
crow = {
  ii={jf={play_note=function() end}, er301={cv=function() end, tr_pulse=function() end}},
  output=setmetatable({}, {__index=function(t, k)
    local out = {execute=function() end}
    rawset(t, k, out)
    return out
  end})
}
metro = {
  init=function()
    local m = {id=1, count=1}
    function m:start()
      for stage=1,self.count do if self.event then self.event(stage) end end
    end
    return m
  end,
  free=function() end
}

function include(path)
  path = path:gsub('^anima/', '')
  if path == 'lib/lfo' then return {} end
  return dofile(path .. '.lua')
end

local ParamSet = require 'core/paramset'
local constants = include('lib/constants')
local function setup()
  params = ParamSet.new()
  local animator = include('lib/animator')
  include('lib/parameters')
  addSeqParams(animator)
  params:add_number('slop', '', 0, 500, 0)
  params:add_number('min_velocity', '', 1, 127, 100)
  params:add_number('max_velocity', '', 1, 127, 100)
  params:add_number('min_note_length', '', 1, 100, 1)
  params:add_number('max_note_length', '', 1, 100, 1)
  params:add_number('max_notes', '', 1, 10, 10)
  animator.notes = {}
  for pos=1,112 do animator.notes[pos] = 59 + pos end
  animator.grid = {snapshot=0, selected=1, patternManager={patterns={}, rebuildPatterns=function() end}}
  animator.redraw = function() end
  animator.outputs = {
    stop_track=function() end,
    play=function(_, track, seq, notes, repeats)
      for _,note in ipairs(notes) do
        for i=1,repeats do engine.noteOn(note) end
      end
    end,
  }
  played = {}
  return animator
end

local function eq(actual, expected, label)
  assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local tests = {}
tests['x1 advances every second high-resolution tick'] = function()
  local a = setup()
  a.addNewSequence({{x=1,y=1}, {x=2,y=1}})
  a.on[1], a.on[2] = 1, 1
  a.count(); eq(#played, 0, 'first tick')
  a.count(); eq(#played, 1, 'second tick')
  eq(a.sequencers[1].index, 2, 'advanced step')
end

tests['mute and probability switches affect playback'] = function()
  local a = setup()
  a.addNewSequence({{x=1,y=1}})
  a.on[1] = 1
  local seq = a.sequencers[1]
  seq.rate = 1
  seq.muted = true
  a.count(); eq(#played, 0, 'muted')
  seq.muted = false
  seq.probabilityEnabled = true
  seq.probability = 100
  a.count(); eq(#played, 1, 'probability 100')
end

tests['ratchet and harmonic collision are audible behaviors'] = function()
  local a = setup()
  a.addNewSequence({{x=1,y=1}})
  a.addNewSequence({{x=1,y=1}})
  a.on[1] = 2
  local first, second = a.sequencers[1], a.sequencers[2]
  first.rate, second.rate = 1, 1
  first.harmonic = 4
  first.ratchetEnabled = true
  first.ratchet = 3
  second.rhythm = 2
  a.count()
  eq(#played, 6, 'two notes repeated three times')
  eq(played[1], 60, 'root')
  eq(played[4], 67, 'fifth')
end

tests['identical collision notes reach both track outputs'] = function()
  local a = setup()
  a.addNewSequence({{x=1,y=1}});a.addNewSequence({{x=1,y=1}})
  a.on[1]=2
  a.sequencers[1].rate=1;a.sequencers[2].rate=1
  a.sequencers[1].output=3;a.sequencers[2].output=4
  local events={}
  a.outputs.play=function(_,track,seq,notes) events[#events+1]={track,seq.output,notes[1]} end
  a.count()
  assert(#events==2,'same pitch must not suppress a separate destination')
  assert(events[1][2]~=events[2][2] and events[1][3]==events[2][3])
end

tests['all triad and seventh types use the configured chord intervals'] = function()
  local cases = {
    {5,1,{60,64,67}}, {5,2,{60,63,67}},
    {5,3,{60,63,66}}, {5,4,{60,65,67}},
    {6,1,{60,64,67,71}}, {6,2,{60,63,67,70}},
    {6,3,{60,64,67,70}},
  }
  for _,case in ipairs(cases) do
    local a = setup()
    a.addNewSequence({{x=1,y=1}}); a.addNewSequence({{x=1,y=1}})
    a.on[1] = 2
    params:set('seq1rate',1); params:set('seq2rate',1)
    params:set('seq2rhythm',2)
    params:set('seq1harmonic',case[1])
    params:set('seq1' .. (case[1] == 5 and 'triadType' or 'seventhType'), case[2])
    a.count()
    eq(#played,#case[3],'chord voice count')
    for i,note in ipairs(case[3]) do eq(played[i],note,'chord note ' .. i) end
  end
end

tests['chord triggers only at intersections and follows track transposition'] = function()
  local a = setup()
  a.addNewSequence({{x=1,y=1}})
  a.on[1] = 1
  params:set('seq1rate',1); params:set('seq1harmonic',6)
  params:set('seq1seventhType',2); params:set('seq1transpose',2)
  a.count()
  eq(#played,1,'no chord without collision')
  eq(played[1],62,'transposed root')
  a.addNewSequence({{x=1,y=1}})
  params:set('seq2rate',1);params:set('seq2rhythm',2)
  played = {}
  a.count()
  for i,note in ipairs({62,65,69,72}) do eq(played[i],note,'transposed seventh') end
end

tests['ratchet zero is a rest when enabled and a normal note when disabled']=function()
  local a=setup();a.addNewSequence({{x=1,y=1},{x=2,y=1}});a.on[1],a.on[2]=1,1
  local seq=a.sequencers[1];seq.rate=1
  params:set('seq1ratchet',0);params:set('seq1ratchetEnabled',2)
  a.count();eq(#played,0,'enabled zero is silent');eq(seq.index,2,'silent step still advances')
  params:set('seq1ratchetEnabled',1)
  a.count();eq(#played,1,'disabled ratchet keeps normal trigger');eq(seq.index,1,'playhead keeps moving')
  params:set('seq1ratchetEnabled',2);params:set('seq1ratchet',1)
  a.count();eq(#played,2,'one retrig means one note')
end

tests['retrigger zero at an intersection leaves note budget and original Crow allocation for the other line']=function()
  for _,output in ipairs({2,11}) do
    local a=setup()
    a.addNewSequence({{x=1,y=1}});a.addNewSequence({{x=1,y=1}});a.on[1]=2
    local first,second=a.sequencers[1],a.sequencers[2]
    first.rate,second.rate=1,1;first.output,second.output=output,output
    first.ratchet=0;first.rhythm=3
    params:set('max_notes',1)
    a.count();eq(#played,1,'second line survives silent retrigger and max-notes cap')
  end
end

tests['zero chance on ratchet does not consume the other line note or original Crow budget']=function()
  for _,output in ipairs({2,11}) do
    local a=setup();a.addNewSequence({{x=1,y=1}});a.addNewSequence({{x=1,y=1}});a.on[1]=2
    local first,second=a.sequencers[1],a.sequencers[2]
    first.rate,second.rate=1,1;first.output,second.output=output,output
    first.ratchetEnabled=true;first.ratchet=4;first.probabilityEnabled=true;first.probability=0
    params:set('max_notes',1);a.count()
    eq(#played,1,'second line survives zero chance and max-notes cap')
  end
end

local failed, total = 0, 0
for name,test in pairs(tests) do
  total = total + 1
  local ok, err = pcall(test)
  print((ok and 'PASS ' or 'FAIL ') .. name)
  if not ok then failed = failed + 1; print(err) end
end
print(string.format('%d/%d passed', total-failed, total))
os.exit(failed == 0 and 0 or 1)
