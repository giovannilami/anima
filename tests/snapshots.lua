-- Run from the repository root:
-- lua tests/snapshots.lua /path/to/norns /path/to/existing/test-data-directory
local nornsRoot, dataDir = assert(arg[1]), assert(arg[2])
package.path = nornsRoot .. '/lua/?.lua;' .. nornsRoot .. '/lua/lib/?.lua;' .. package.path
util = require 'util'
norns = {state = {data = dataDir .. '/', shortname = 'animator'}, pmap = {data = {}}}
metro = {init = function() return {} end}
package.preload.fileselect = function() return {} end
package.preload.textentry = function() return {} end
package.preload['molly_the_poly/lib/molly_the_poly_engine'] = function() return {} end

function include(path)
  path = path:gsub('^anima/', '')
  if path == 'lib/lfo' then return {} end
  return dofile(path .. '.lua')
end

local ParamSet = require 'core/paramset'
local tab = require 'tabutil'
local function setup()
  params = ParamSet.new()
  local a = include('lib/animator')
  include('lib/parameters')
  addSeqParams(a)
  a.grid = {snapshot = 0, patternManager = {patterns = {}, rebuildPatterns = function() end}}
  return a
end

local function eq(actual, expected, label)
  assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function add(a, row, rate, intersect)
  a.addNewSequence({{x=1,y=row}, {x=2,y=row}, {x=3,y=row}})
  local i = #a.sequencers
  params:set('seq' .. i .. 'rate', rate)
  params:set('seq' .. i .. 'intersect', intersect)
end

local function select(a, i, overwrite)
  a.handleSelectSnapshot{i=i, isClearHeld=overwrite}
end

local tests = {}
tests['loaded snapshots with repeated values recall correctly'] = function()
  local a = setup()
  add(a, 1, 2, 2)
  select(a, 1)
  params:set('seq1rate', 5); params:set('seq1intersect', 4)
  select(a, 2)
  a.moveSequencers('y', 1, 7)
  select(a, 3)
  select(a, 1)
  a.save('roundtrip')
  a = setup()
  a.load(dataDir .. '/roundtrip.doodle')
  for _,i in ipairs({2,3,3,1,3,2,1}) do
    select(a, i)
    eq(a.sequencers[1].rate, i == 1 and 2 or 5, 'snapshot ' .. i .. ' rate')
    eq(a.sequencers[1].intersect, i == 1 and 2 or 4, 'snapshot ' .. i .. ' intersect')
    eq(a.sequencers[1].rate, params:get('seq1rate'), 'rate display consistency')
    eq(a.sequencers[1].intersect, params:get('seq1intersect'), 'rule display consistency')
    a.sequencers[1]:regenStepMap()
  end
end

tests['deleting a line preserves the remaining settings in-session'] = function()
  local a = setup()
  add(a, 1, 2, 2); add(a, 2, 5, 4); add(a, 3, 7, 6)
  a.clearSeq(1)
  select(a, 1)
  eq(a.sequencers[1].rate, 5, 'remaining first rate')
  eq(a.sequencers[1].intersect, 4, 'remaining first rule')
  eq(a.sequencers[2].rate, 7, 'remaining second rate')
  eq(a.sequencers[2].intersect, 6, 'remaining second rule')
  params:set('seq1rate', 3); params:set('seq1intersect', 3)
  select(a, 2)
  select(a, 1)
  eq(a.sequencers[1].rate, 5, 'recalled rate after deletion')
  eq(a.sequencers[1].intersect, 4, 'recalled rule after deletion')
end

tests['nonconsecutive snapshot slots survive saving and loading'] = function()
  local a = setup()
  add(a, 1, 7, 6)
  select(a, 8)
  a.save('sparse')
  a = setup()
  a.load(dataDir .. '/sparse.doodle')
  assert(a.snapshots[8], 'snapshot 8 was lost')
  assert(not a.snapshots[1], 'unused slot 1 should remain empty')
  select(a, 8)
  eq(a.sequencers[1].rate, 7, 'sparse rate')
end

tests['normal recall and explicit overwrite remain isolated'] = function()
  local a = setup()
  add(a, 1, 2, 2)
  a.on[1] = 1
  select(a, 1)
  params:set('seq1rate', 6); params:set('seq1intersect', 5)
  a.moveSequencers('y', 1, 7)
  select(a, 2)
  select(a, 1)
  eq(a.sequencers[1].rate, 2, 'original rate')
  eq(a.sequencers[1].intersect, 2, 'original rule')
  eq(a.sequencers[1].steps[1].y, 1, 'original geometry')
  eq(a.on[1], 1, 'original notes')
  params:set('seq1rate', 7)
  select(a, 1, true)
  select(a, 2); select(a, 1)
  eq(a.sequencers[1].rate, 7, 'overwritten rate')
  eq(a.snapshots[2].rates[1], 6, 'other snapshot unchanged')
end

tests['all eight snapshots and lines preserve every rate and rule'] = function()
  local a = setup()
  for line=1,8 do add(a, (line-1)%7+1, 1, 1) end
  local expected = {}
  for slot=1,8 do
    expected[slot] = {}
    for line=1,8 do
      local rate = (math.floor((slot-1)/2)+line-1)%7+1
      local rule = (math.floor((slot-1)/2)+line-1)%6+1
      params:set('seq' .. line .. 'rate', rate)
      params:set('seq' .. line .. 'intersect', rule)
      expected[slot][line] = {rate, rule}
    end
    select(a, slot)
  end
  a.save('all-slots')
  a = setup()
  a.load(dataDir .. '/all-slots.doodle')
  for from=1,8 do
    for to=1,8 do
      select(a, from); select(a, to)
      for line=1,8 do
        eq(a.sequencers[line].rate, expected[to][line][1], 'matrix rate')
        eq(a.sequencers[line].intersect, expected[to][line][2], 'matrix rule')
        eq(params:get('seq' .. line .. 'rate'), expected[to][line][1], 'matrix rate parameter')
        eq(params:get('seq' .. line .. 'intersect'), expected[to][line][2], 'matrix rule parameter')
      end
    end
  end
end

tests['old cached values are recovered from snapshot settings'] = function()
  local a = setup()
  add(a, 1, 6, 5)
  select(a, 1)
  a.save('old-cache')
  local path = dataDir .. '/old-cache.doodle'
  local saved = tab.load(path)
  -- Older loaders overwrote these caches while leaving rates/intersects intact.
  saved.snapshots[1].sequencers[1].rate = 1
  saved.snapshots[1].sequencers[1].intersect = 1
  tab.save(saved, path)
  a.load(path)
  select(a, 1)
  eq(a.sequencers[1].rate, 6, 'recovered rate')
  eq(a.sequencers[1].intersect, 5, 'recovered rule')
  -- No-op parameter writes must not leave a stale sequencer cache behind.
  a.snapshots[1].sequencers[1].rate = 1
  a.snapshots[1].sequencers[1].intersect = 1
  select(a, 1)
  eq(a.sequencers[1].rate, 6, 'same-value rate recall')
  eq(a.sequencers[1].intersect, 5, 'same-value rule recall')
end

tests['saving live edits does not overwrite a stored snapshot'] = function()
  local a = setup()
  add(a, 1, 2, 2)
  select(a, 1)
  params:set('seq1rate', 7); params:set('seq1intersect', 6)
  a.save('live-edits')
  a = setup()
  a.load(dataDir .. '/live-edits.doodle')
  eq(a.sequencers[1].rate, 7, 'live rate after load')
  eq(a.sequencers[1].intersect, 6, 'live rule after load')
  select(a, 1)
  eq(a.sequencers[1].rate, 2, 'stored rate unchanged')
  eq(a.sequencers[1].intersect, 2, 'stored rule unchanged')
end

tests['snapshots preserve Animator 2 performance state'] = function()
  local a = setup()
  add(a, 1, 2, 1)
  local seq = a.sequencers[1]
  seq.direction = 3
  seq.muted = true
  seq.probabilityEnabled = true
  seq.ratchetEnabled = true
  params:set('seq1harmonic', 5)
  params:set('seq1rhythm', 4)
  select(a, 1)

  seq.direction = 1
  seq.muted = false
  seq.probabilityEnabled = false
  seq.ratchetEnabled = false
  params:set('seq1harmonic', 1)
  params:set('seq1rhythm', 1)
  select(a, 1)

  seq = a.sequencers[1]
  eq(seq.direction, 3, 'direction')
  eq(seq.muted, true, 'mute')
  eq(seq.probabilityEnabled, true, 'probability toggle')
  eq(seq.ratchetEnabled, true, 'ratchet toggle')
  eq(seq.harmonic, 5, 'harmonic action')
  eq(seq.rhythm, 4, 'rhythm action')
end

tests['legacy doodle divisions migrate to the new rate scale'] = function()
  local a = setup()
  local legacy = {
    name = 'legacy', showIntroText = false,
    on = a.on, enabled = a.enabled,
    sequencers = {{steps={{x=1,y=1},{x=2,y=1}}, div=8, intersect=3}},
    snapshots = {[1]={
      on=a.on, enabled=a.enabled,
      sequencers={{steps={{x=1,y=1},{x=2,y=1}}, div=3, intersect=2}},
      divs={[1]=3}, intersects={[1]=2}
    }},
    selectedSnapshot = 0, patterns = {}
  }
  tab.save(legacy, dataDir .. '/legacy.doodle')
  params:write(dataDir .. '/legacy.pset')
  a.load(dataDir .. '/legacy.doodle')
  eq(a.sequencers[1].rate, 7, 'legacy /8')
  eq(a.sequencers[1].rhythm, 2, 'legacy mute')
  select(a, 1)
  eq(a.sequencers[1].rate, 4, 'legacy /3 snapshot')
  eq(a.sequencers[1].harmonic, 2, 'legacy octave snapshot')
end

tests['routing and EDIT values survive restart recall and deletion'] = function()
  local a = setup()
  add(a,1,2,1); add(a,2,3,1)
  params:set('seq1output',4); params:set('seq1port',16); params:set('seq1channel',9)
  params:set('seq1probability',43); params:set('seq1ratchet',4)
  params:set('seq2output',6); params:set('seq2duration',450)
  params:set('seq2nb_hidden_string','test voice')
  select(a,8)
  params:set('seq1output',2);params:set('seq1port',1)
  a.save('routes')
  a=setup();a.load(dataDir..'/routes.doodle')
  eq(a.sequencers[1].output,2,'live route')
  select(a,8)
  eq(a.sequencers[1].output,4,'snapshot MIDI')
  eq(a.sequencers[1].port,16,'snapshot port')
  eq(a.sequencers[1].channel,9,'snapshot channel')
  eq(a.sequencers[1].probability,43,'snapshot probability')
  eq(a.sequencers[1].ratchet,4,'snapshot repeats')
  eq(params:get('seq1port'),16,'EDIT matches runtime')
  a.clearSeq(1)
  eq(a.sequencers[1].output,6,'crow route moves with remaining line')
  eq(params:get('seq1output'),6,'EDIT route after deletion')
  eq(params:get('seq1duration'),450,'duration after deletion')
  eq(params:get('seq1nb_hidden_string'),'test voice','NB voice follows line')
end

tests['legacy global MIDI routing imports from the adjacent pset'] = function()
  local a=setup()
  add(a,1,2,1)
  a.save('legacy-midi')
  local path=dataDir..'/legacy-midi.doodle'
  local saved=tab.load(path)
  saved.trackSettings=nil;saved.formatVersion=2
  saved.sequencers[1].output=nil;saved.sequencers[1].port=nil
  tab.save(saved,path)
  local f=assert(io.open(dataDir..'/legacy-midi.pset','w'))
  f:write('"output": 3\n"midi_out_device": 12\n"seq1channel": 6\n')
  f:close()
  a=setup();a.load(path)
  eq(a.sequencers[1].output,4,'imported MIDI destination')
  eq(a.sequencers[1].port,12,'imported MIDI device')
  eq(params:get('seq1output'),4,'imported EDIT destination')
end

tests['chord types survive restart snapshot recall and line deletion'] = function()
  local a = setup()
  add(a,1,2,1);add(a,2,3,1)
  params:set('seq1harmonic',5);params:set('seq1triadType',4)
  params:set('seq2harmonic',6);params:set('seq2seventhType',2)
  select(a,8)
  params:set('seq1triadType',2);params:set('seq2seventhType',3)
  a.save('chords')
  a=setup();a.load(dataDir..'/chords.doodle')
  eq(a.sequencers[1].triadType,2,'live triad after restart')
  eq(a.sequencers[2].seventhType,3,'live seventh after restart')
  select(a,8)
  eq(a.sequencers[1].triadType,4,'snapshot sus4')
  eq(params:get('seq1triadType'),4,'sus4 EDIT')
  eq(a.sequencers[2].harmonic,6,'snapshot seventh action')
  eq(a.sequencers[2].seventhType,2,'snapshot min7')
  a.clearSeq(1)
  eq(a.sequencers[1].seventhType,2,'min7 follows remaining line')
  eq(params:get('seq1seventhType'),2,'min7 EDIT after deletion')
end

tests['older projects retain major triads when chord types are absent'] = function()
  local a=setup()
  add(a,1,2,1);params:set('seq1harmonic',5);select(a,1)
  a.save('old-triad')
  local path=dataDir..'/old-triad.doodle'
  local data=tab.load(path)
  for _,seq in ipairs(data.sequencers) do seq.triadType=nil;seq.seventhType=nil end
  for _,settings in ipairs(data.trackSettings) do settings.triadType=nil;settings.seventhType=nil end
  for _,snap in pairs(data.snapshots) do
    for _,seq in ipairs(snap.sequencers) do seq.triadType=nil;seq.seventhType=nil end
    for _,settings in ipairs(snap.trackSettings) do settings.triadType=nil;settings.seventhType=nil end
  end
  tab.save(data,path)
  params:set('seq1triadType',3);params:set('seq1seventhType',2)
  a.load(path)
  eq(a.sequencers[1].triadType,1,'legacy major triad')
  select(a,1)
  eq(a.sequencers[1].triadType,1,'legacy major snapshot')
  eq(a.sequencers[1].seventhType,1,'default seventh type')
end

tests['combination outputs survive restart snapshot switches and deletion'] = function()
  local a=setup()
  add(a,1,2,1);add(a,2,3,1)
  params:set('seq1output',9);params:set('seq1port',16);params:set('seq1channel',7)
  params:set('seq1nb_hidden_string','layer voice')
  params:set('seq2output',10);params:set('seq2port',2);params:set('seq2channel',5)
  select(a,1)
  params:set('seq1output',4);params:set('seq2output',2)
  select(a,8)
  assert(a.save('combinations'))
  a=setup();a.load(dataDir..'/combinations.doodle')
  eq(a.sequencers[1].output,4,'live MIDI destination after restart')
  for _,slot in ipairs({1,8,1,1}) do select(a,slot) end
  eq(a.sequencers[1].output,9,'NB plus MIDI snapshot')
  eq(a.sequencers[2].output,10,'internal plus MIDI snapshot')
  eq(params:get('seq1port'),16,'NB combination MIDI port')
  eq(params:get('seq1channel'),7,'NB combination MIDI channel')
  eq(params:get('seq1nb_hidden_string'),'layer voice','NB combination voice')
  a.clearSeq(1)
  eq(a.sequencers[1].output,10,'combination follows surviving line')
  eq(params:get('seq1port'),2,'surviving line MIDI port')
  eq(params:get('seq1channel'),5,'surviving line MIDI channel')
end

tests['legacy audio plus MIDI imports to the per track combination'] = function()
  local a=setup()
  add(a,1,2,1)
  assert(a.save('legacy-audio-midi'))
  local path=dataDir..'/legacy-audio-midi.doodle'
  local data=tab.load(path)
  data.trackSettings=nil;data.formatVersion=2
  data.sequencers[1].output=nil;data.sequencers[1].port=nil
  tab.save(data,path)
  local f=assert(io.open(dataDir..'/legacy-audio-midi.pset','w'))
  f:write('"output": 2\n"midi_out_device": 3\n"seq1channel": 8\n')
  f:close()
  a=setup();a.load(path)
  eq(a.sequencers[1].output,10,'legacy audio plus MIDI')
  eq(params:get('seq1port'),3,'legacy combined MIDI device')
  eq(params:get('seq1channel'),8,'legacy combined MIDI channel')
end

tests['original Crow route survives saved snapshots and preserves fixed pair assignments'] = function()
  local a=setup()
  add(a,1,2,1);add(a,2,3,1)
  params:set('seq1output',11);params:set('seq2output',6)
  select(a,1)
  params:set('seq1output',5);params:set('seq2output',4)
  assert(a.save('crow-original'))
  a=setup();a.load(dataDir..'/crow-original.doodle')
  eq(params:get('seq1output'),5,'existing fixed pair remains fixed after restart')
  select(a,1)
  eq(params:get('seq1output'),11,'original Crow snapshot')
  eq(params:get('seq2output'),6,'fixed 3/4 snapshot')
  a.clearSeq(1)
  eq(params:get('seq1output'),6,'fixed assignment follows remaining line')
end

tests['legacy crow cv imports as original Crow instead of fixed pair'] = function()
  local a=setup()
  add(a,1,2,1)
  assert(a.save('legacy-crow'))
  local path=dataDir..'/legacy-crow.doodle'
  local data=tab.load(path)
  data.trackSettings=nil;data.formatVersion=2
  data.sequencers[1].output=nil
  tab.save(data,path)
  local f=assert(io.open(dataDir..'/legacy-crow.pset','w'))
  f:write('"output": 5\n');f:close()
  a=setup();a.load(path)
  eq(params:get('seq1output'),11,'imported original crow cv')
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
