local tab = require 'tabutil'
local constants = include('anima/lib/constants')
local STEP_NUM = constants.CANVAS_HEIGHT*constants.CANVAS_LENGTH
local GRID_LEVELS = constants.GRID_LEVELS
local helpers = include('anima/lib/helpers')
local findPosition = helpers.findPosition
local copyTable = helpers.copyTable
local deepcopy = helpers.deepcopy
local Sequencer = include('anima/lib/Sequencer')
local Settings = include('anima/lib/track_settings')
local Persistence = include('anima/lib/persistence')
local Original=include('anima/lib/original')
local MAX_SEQ_NUM = 8
local LEGACY_DIV_TO_RATE = {2, 3, 4, 5, 8, 6, 9, 7}

function initStepState()
  local steps = {}
  for i=1,STEP_NUM do steps[i] = 0 end
  return steps
end

local animator = {}
local performance = {}

animator.original = {}
animator.stepLevels = {}
animator.redraw = function() end
animator.on = initStepState()
animator.enabled = initStepState()
animator.sequencers = {}
animator.snapshots = {}
animator.shouldResetAll = false
animator.lastReplaced = 0
animator.showIntroText = true
animator.name = 'untilted'

-- Parameter actions run synchronously during a read/recall. Keep their
-- musical actions, but publish no intermediate Grid or screen frames.
-- Restore the outer state even if an action fails (nested recalls are safe).
function animator.withUpdate(fn)
  local previous=animator.updating
  animator.updating=true
  local result=table.pack(pcall(fn))
  animator.updating=previous
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end

function updateEnabled(steps)
  for i=1,#steps do
    local step = steps[i]
    local pos = findPosition(step.x, step.y)
    animator.enabled[pos] = animator.enabled[pos] + 1
  end
end

function updateOnState(steps)
  for i=1,#steps do
    local step = steps[i]
    local pos = findPosition(step.x, step.y)
    if animator.on[pos] > 0 then
      animator.on[pos] = animator.enabled[pos]
    end
  end
end

function animator.addNewSequence(steps)
  local index
  if #animator.sequencers == MAX_SEQ_NUM then
    animator.lastReplaced = animator.lastReplaced % MAX_SEQ_NUM + 1
    index = animator.lastReplaced
    resetSeqParams(index)
  else
    index = #animator.sequencers+1
  end
  if animator.showIntroText then animator.showIntroText = false end
  if animator.modulation then animator.modulation:reset(index) end
  animator.sequencers[index] = Sequencer.new({steps = steps}, index)
  if animator.originalPlayback and animator.originalPlayback.enabled then
    animator.sequencers[index].rateCount=1+(animator.originalPlayback.phase or 0)
  end
  updateEnabled(steps)
  updateOnState(steps)
end

local Snapshot = {}
function Snapshot.new(animator)
  local snapshot = {
    sequencers = deepcopy(animator.sequencers),
    on = copyTable(animator.on),
    enabled = copyTable(animator.enabled),
    rates = {},
    intersects = {},
    harmonics = {},
    rhythms = {},
    trackSettings = {},
    originalPhase=animator.originalPlayback and animator.originalPlayback.phase or 0
  }
  for i=1,MAX_SEQ_NUM do
    local seq = animator.sequencers[i]
    snapshot.rates[i] = seq and seq.rate or params:get('seq' .. i .. 'rate')
    snapshot.intersects[i] = seq and seq.intersect or params:get('seq' .. i .. 'intersect')
    snapshot.harmonics[i] = seq and seq.harmonic or params:get('seq' .. i .. 'harmonic')
    snapshot.rhythms[i] = seq and seq.rhythm or params:get('seq' .. i .. 'rhythm')
    snapshot.trackSettings[i] = Settings.capture(i, seq)
  end

  return snapshot
end

function animator.count()
  if animator.closing or animator.updating then return end
  if animator.originalPlayback and animator.originalPlayback.enabled then return Original.count(animator) end
  if animator.outputs and animator.outputs.begin_step then animator.outputs:begin_step() end
  local play = {}
  local findPos = findPosition
  local slop = params:get('slop')
  local hasSolo = false
  for i=1,#animator.sequencers do
    if animator.sequencers[i].solo then hasSolo = true break end
  end

  for i=1,#animator.sequencers do
    local seq = animator.sequencers[i]
    local state=performance[i]
    if not state or state.source~=seq then state={source=seq};performance[i]=state end
    local initial=animator.modulation and animator.modulation:effective(seq,i) or seq
    if not state.div or (not seq.modEnabled and not state.modulated) then state.div=constants.RATE_TICK_DIVS[initial.rate] end
    local tickDiv=state.div or constants.RATE_TICK_DIVS[constants.RATE_DEFAULT]
    seq.rateCount = seq.rateCount % tickDiv + 1
    if seq.rateCount == 1 then
      state.effective=animator.modulation and animator.modulation:effective(seq,i) or seq
      state.div=constants.RATE_TICK_DIVS[state.effective.rate]
      state.modulated=seq.modEnabled
      if animator.modulation then animator.modulation.applied[i]=state.effective end
      local effective=state.effective
      seq:advance()
      if animator.shouldResetAll then
        seq.index = 1
      end
      if seq.reset then
        seq.index = 1
        seq.reset = false
      end
      local currentStep = seq.steps[seq.index]
      local pos = findPos(currentStep.x, currentStep.y)
      local canSound = seq.output ~= 1 and not seq.muted and (not hasSolo or seq.solo)
      -- Ratchets draw chance at each strike, so a failed first note must not
      -- discard the whole burst. Intersection retrigger uses the same rule.
      state.strikeProbability=nil
      if seq.probabilityEnabled and (seq.ratchetEnabled or seq.rhythm==3) then
        state.strikeProbability=effective.probability
      end
      local passesProbability
      if state.strikeProbability~=nil then
        passesProbability=state.strikeProbability>0
      else
        passesProbability=not seq.probabilityEnabled or math.random(100)<=effective.probability
      end
      if animator.outputs then animator.outputs:stop_track(i) end
      if animator.on[pos] > 0 and canSound and passesProbability then
        if play[pos] == nil then
          play[pos] = {seq}
        else
          play[pos][#play[pos]+1] = seq
        end
      end
    end
  end

  if animator.shouldResetAll then animator.shouldResetAll = false end

  local maxNotes = params:get('max_notes')
  local noteCount = 0
  local originalCrowNotes = {}

  for pos,seqs in pairs(play) do
    local seqNum = #seqs
    local collision = seqNum > 1

    for i=1,seqNum do
      local seq = seqs[i]
      local track
      for n,candidate in ipairs(animator.sequencers) do if candidate == seq then track = n; break end end
      local effective=performance[track].effective or seq
      local notes = {animator.notes[pos] + effective.transpose + (effective.octave or 0)*12}
      local mute = false
      local repeats = seq.ratchetEnabled and effective.ratchet or 1

      if collision then
        if seq.harmonic == 2 then
          notes[1] = notes[1] + 12
        elseif seq.harmonic == 3 then
          notes[1] = notes[1] - 12
        elseif seq.harmonic == 4 then
          notes[2] = notes[1] + 7
        elseif seq.harmonic == 5 or seq.harmonic == 6 then
          local root = notes[1]
          local intervals = seq.harmonic == 5
            and constants.TRIAD_INTERVALS[seq.triadType or 1]
            or constants.SEVENTH_INTERVALS[seq.seventhType or 1]
          notes = {}
          for _,interval in ipairs(intervals) do notes[#notes+1] = root + interval end
        end

        if seq.rhythm == 2 then
          mute = true
        elseif seq.rhythm == 3 then
          repeats = effective.ratchet
        elseif seq.rhythm == 4 then
          if seq.direction == constants.DIRECTION_FORWARD then
            seq.direction = constants.DIRECTION_REVERSE
            params:set('seq' .. track .. 'direction', seq.direction, true)
          elseif seq.direction == constants.DIRECTION_REVERSE then
            seq.direction = constants.DIRECTION_FORWARD
            params:set('seq' .. track .. 'direction', seq.direction, true)
          elseif seq.direction == constants.DIRECTION_PENDULUM then
            seq.directionStep = seq.directionStep * -1
          end
        elseif seq.rhythm == 5 then
          seq.reset = true
        elseif seq.rhythm == 6 then
          for j=1,seqNum do if j~=i then seqs[j].reset = true end end
        elseif seq.rhythm == 7 then
          animator.shouldResetAll = true
        end
      end

      if not mute and repeats > 0 and animator.outputs then
        if seq.output == 11 then
          local unique = {}
          for _,note in ipairs(notes) do
            if originalCrowNotes[note] ~= seq.channel then
              unique[#unique+1] = note
              originalCrowNotes[note] = seq.channel
            end
          end
          notes = unique
        end
        local available = maxNotes - noteCount
        while #notes > available do table.remove(notes) end
        if #notes > 0 then
          local stepSeconds = clock.get_beat_sec() * constants.RATE_TICK_DIVS[effective.rate]/8
          animator.outputs:play(track, effective, notes, repeats, stepSeconds, slop,performance[track].strikeProbability)
          noteCount = noteCount + #notes
        end
      end
    end
  end

  animator.redraw()
end

function moveSteps(steps, axis, delta, wrap)
  clearStepState(steps)
  local newOn = {}

  for i=1,#steps do
    local step = steps[i]
    local pos = findPosition(step.x, step.y)
    step[axis] = (step[axis] + delta - 1) % wrap + 1
    if animator.on[pos] > 0 then
      newOn[findPosition(step.x, step.y)] = 1
    end
  end

  updateEnabled(steps)
  return newOn
end

function moveStepsPos(index, axis, val, wrap)
  local steps = animator.sequencers[index].steps
  clearStepState(steps)
  local newOn = {}

  local original = animator.original
  if not original[index] then original[index] = deepcopy(steps) end
  local originalSteps = original[index]
  local findPos = findPosition

  for i=1,#steps do
    local step = steps[i]
    local pos = findPos(step.x, step.y)
    step[axis] = (originalSteps[i][axis] + val - 1) % wrap + 1
    if animator.on[pos] > 0 then
      newOn[findPosition(step.x, step.y)] = 1
    end
  end

  updateEnabled(steps)
  return newOn
end

function animator.moveSequencers(axis, delta, wrap)
  local newOn = {}
  for i=1,#animator.sequencers do
    local resp = moveSteps(animator.sequencers[i].steps, axis, delta, wrap)
    animator.sequencers[i]:regenStepMap()
    for pos,n in pairs(resp) do newOn[pos] = n end
  end
  animator.setOnToNew(newOn)
end

function animator.moveSequence(index, axis, delta, wrap)
  local seq = animator.sequencers[index]
  if not seq then return end
  local movedOn = moveSteps(seq.steps, axis, delta, wrap)
  seq:regenStepMap()
  local newOn = {}
  for pos,value in pairs(animator.on) do
    if value > 0 and animator.enabled[pos] > 0 then newOn[pos] = 1 end
  end
  for pos,_ in pairs(movedOn) do newOn[pos] = 1 end
  animator.setOnToNew(newOn)
end

function animator.moveSequencersPos(axis, val, wrap)
  local newOn = {}
  for i=1,#animator.sequencers do
    local resp = moveStepsPos(i, axis, val, wrap)
    animator.sequencers[i]:regenStepMap()
    for pos,n in pairs(resp) do newOn[pos] = n end
  end
  animator.setOnToNew(newOn)
end

function animator.setOnToNew(newOn)
  for pos,_ in pairs(animator.on) do
    if newOn[pos] ~= nil then
      animator.on[pos] = animator.enabled[pos]
    else
      animator.on[pos] = 0
    end
  end
end

function animator.handleSelectSnapshot(e)
  animator.withUpdate(function()
    if animator.snapshots[e.i] == nil or e.isClearHeld then
      animator.snapshots[e.i] = Snapshot.new(animator)
    end
    setToSnapshot(animator.snapshots[e.i])
    animator.grid.snapshot = e.i
  end)
  animator.redraw()
end

local function applySnapshot(snapshot)
  if animator.history then animator.history:clear() end
  if animator.grid and animator.grid.cancelGestureHolds then animator.grid:cancelGestureHolds() end
  if animator.modulation then animator.modulation:reset() end
  performance={}
  if animator.outputs then animator.outputs:panic() end
  animator.original = {}
  animator.on = copyTable(snapshot.on)
  animator.enabled = copyTable(snapshot.enabled)
  animator.sequencers = deepcopy(snapshot.sequencers)

  for i=1,MAX_SEQ_NUM do
    local savedSeq = snapshot.sequencers[i]
    params:set('seq' .. i .. 'intersect',
      snapshot.intersects and snapshot.intersects[i] or savedSeq and savedSeq.intersect or 1)
    local rate = snapshot.rates and snapshot.rates[i]
      or (snapshot.divs and LEGACY_DIV_TO_RATE[snapshot.divs[i]])
      or constants.RATE_DEFAULT
    params:set('seq' .. i .. 'rate', rate)
    params:set('seq' .. i .. 'harmonic',
      snapshot.harmonics and snapshot.harmonics[i] or savedSeq and savedSeq.harmonic or 1)
    params:set('seq' .. i .. 'rhythm',
      snapshot.rhythms and snapshot.rhythms[i] or savedSeq and savedSeq.rhythm or 1)
    local captured = snapshot.trackSettings and snapshot.trackSettings[i]
    if captured then
      Settings.apply(i, captured, animator.sequencers[i])
    elseif savedSeq then
      -- Preserve per-line performance fields in earlier Animator 2 prototypes.
      Settings.apply(i, Settings.capture(i, savedSeq), animator.sequencers[i])
    end
    -- norns only runs parameter actions when the value changes. A newly
    -- restored sequencer must also be updated when consecutive snapshots
    -- share a value (including doodles saved by older Animator versions).
    local seq = animator.sequencers[i]
    if seq then
      seq.intersect = params:get('seq' .. i .. 'intersect')
      seq.rate = params:get('seq' .. i .. 'rate')
      seq.harmonic = params:get('seq' .. i .. 'harmonic')
      seq.rhythm = params:get('seq' .. i .. 'rhythm')
    end
  end
  Original.alignSnapshot(animator,snapshot)
end

function setToSnapshot(snapshot)
  return animator.withUpdate(function() return applySnapshot(snapshot) end)
end

function animator.clearSeq(index)
  if animator.modulation then animator.modulation:reset() end
  performance={}
  if not animator.sequencers[index] then return end
  local saved = {}
  for i=1,8 do saved[i] = Settings.capture(i, animator.sequencers[i]) end
  if animator.outputs then animator.outputs:panic() end
  clearStepState(animator.sequencers[index].steps)
  clearOnState(animator.sequencers[index].steps)
  local lastIndex = #animator.sequencers
  table.remove(animator.sequencers, index)
  for i=index,#animator.sequencers do
    Settings.apply(i, saved[i+1], animator.sequencers[i])
    params:set('seq' .. i .. 'intersect', animator.sequencers[i].intersect, true)
  end
  resetSeqParams(lastIndex)
  animator.original = {}
  animator.redraw()
end

function resetSeqParams(index)
  Settings.apply(index, nil, animator.sequencers[index])
  params:set('seq' .. index .. 'intersect', 1)
end

function animator.clear(view)
  if animator.modulation then animator.modulation:reset() end
  performance={}
  if animator.outputs then animator.outputs:panic() end
  if view == 1 then
    for i=1,#animator.sequencers do
      resetSeqParams(i)
    end
    animator.sequencers = {}
    if animator.grid.snapshot > 0 then
      animator.snapshots[animator.grid.snapshot] = nil
      animator.grid.snapshot = 0
    end
    animator.original = {}
    animator.on = initStepState()
    animator.enabled = initStepState()
  else
    animator.clearSeq(animator.grid.selected)
  end
end

function animator.reset(view)
  if view == 1 then
    for i=1,#animator.sequencers do
      animator.sequencers[i].rateCount = 1
      animator.sequencers[i].index = 1
    end
  else
    local seq = animator.sequencers[animator.grid.selected]
    if seq then seq.reset = true end
  end
end

function animator.resetStepLevels()
  animator.stepLevels = getStepLevels()
end

function animator.setStepLevels(seq)
  animator.stepLevels = seq and reduceStepLevels(seq) or {}
end

function animator.save(txt)
  if txt then
    if txt:match('^%s*$') or txt:find('[/\\%z]') or txt == '.' or txt == '..' then
      animator.saveStatus = {ok=false, text='invalid doodle name'}
      print('Animator save failed: invalid doodle name')
      animator.redraw()
      return false, 'invalid doodle name'
    end
    local path = norns.state.data .. txt
    local doodle = {
      formatVersion = 4,
      originalPlayback = animator.originalPlayback,
      trackSettings = {},
      name = txt,
      on = animator.on,
      enabled = animator.enabled,
      sequencers = animator.sequencers,
      snapshots = animator.snapshots,
      selectedSnapshot = animator.grid.snapshot,
      showIntroText = animator.showIntroText,
      patterns = animator.grid.patternManager.exportPatterns
        and animator.grid.patternManager:exportPatterns() or {}
    }
    for i=1,8 do doodle.trackSettings[i] = Settings.capture(i, animator.sequencers[i]) end
    local ok,err = Persistence.save(doodle,path)
    animator.saveStatus = {ok=ok, text=ok and 'doodle saved' or 'SAVE FAILED', detail=err}
    if ok then animator.name = doodle.name else print('Animator save failed: ' .. tostring(err)) end
    animator.redraw()
    return ok,err
  else
    print('save canceled')
  end
end

local function legacySettings(path)
  local settings = {}
  local file = io.open(path, 'r')
  if not file then return settings end
  for line in file:lines() do
    local id,value = line:match('^"([%w_]+)"%s*:%s*([%+%-]?[%d%.eE%+%-]+)')
    if id then settings[id] = tonumber(value) end
  end
  file:close()
  return settings
end

local function loadDoodle(path)
  if string.find(path, 'doodle') ~= nil then
    local doodle = tab.load(path)
    if doodle ~= nil then
      if animator.history then animator.history:clear() end
      if animator.grid and animator.grid.cancelGestureHolds then animator.grid:cancelGestureHolds() end
      if animator.modulation then animator.modulation:reset() end
      performance={}
      if animator.outputs then animator.outputs:panic() end
      animator.original = {}
      local psetPath = path:gsub('%.doodle$', '.pset')
      local legacy = not doodle.trackSettings and legacySettings(psetPath) or {}
      if Original.isOriginal(doodle) then doodle=Original.convert(doodle,legacy) end
      animator.originalPlayback=doodle.originalPlayback and deepcopy(doodle.originalPlayback) or nil
      params:read(psetPath)
      if params.lookup.animator_playback then
        params:set('animator_playback',animator.originalPlayback and animator.originalPlayback.enabled and 2 or 1)
      end

      animator.name = doodle.name
      animator.showIntroText = doodle.showIntroText
      animator.on = doodle.on
      animator.enabled = doodle.enabled

      animator.sequencers = {}
      for i=1,#doodle.sequencers do
        local seq = deepcopy(doodle.sequencers[i])
        seq.triadType = seq.triadType or 1
        seq.seventhType = seq.seventhType or 1
        if not doodle.trackSettings then
          -- Pre-format-3 Animator 2 prototypes used this output order.
          -- Genuine original Animator files are converted above.
          local routes = {2,10,4,7,11,11,2,8}
          seq.output = seq.output or routes[legacy.output] or params:get('seq' .. i .. 'output')
          seq.port = seq.port or legacy.midi_out_device
          if legacy.output then seq.channel = legacy['seq'..i..'channel'] or seq.channel end
          seq.probability = seq.probability or legacy.line_probability
          seq.ratchet = seq.ratchet or legacy.line_ratchet
        end
        animator.sequencers[i] = Sequencer.new(seq, i)
        params:set('seq' .. i .. 'rate', animator.sequencers[i].rate)
        params:set('seq' .. i .. 'intersect', animator.sequencers[i].intersect)
        params:set('seq' .. i .. 'harmonic', animator.sequencers[i].harmonic)
        params:set('seq' .. i .. 'rhythm', animator.sequencers[i].rhythm)
        Settings.apply(i, doodle.trackSettings and doodle.trackSettings[i]
          or Settings.capture(i, animator.sequencers[i]), animator.sequencers[i])
      end

      if doodle.trackSettings then
        for i=#doodle.sequencers+1,8 do Settings.apply(i, doodle.trackSettings[i]) end
      end
      animator.snapshots = {}
      -- Snapshot slots can contain gaps; # is not a count for sparse tables.
      for i,snap in pairs(doodle.snapshots) do
        local newSnap = deepcopy(snap)

        for j=1,#snap.sequencers do
          local seq = newSnap.sequencers[j]
          seq.triadType = seq.triadType or 1
          seq.seventhType = seq.seventhType or 1
          -- These arrays are the settings captured by the snapshot, even if
          -- an older loader has replaced the sequencer's cached values.
          if snap.rates then
            seq.rate = snap.rates[j]
          elseif snap.divs then
            seq.rate = LEGACY_DIV_TO_RATE[snap.divs[j]]
          end
          if snap.harmonics then seq.harmonic = snap.harmonics[j] end
          if snap.rhythms then seq.rhythm = snap.rhythms[j] end
          seq.intersect = snap.intersects and snap.intersects[j] or seq.intersect
          newSnap.sequencers[j] = Sequencer.new(seq, j)
        end
        animator.snapshots[i] = newSnap
      end

      animator.grid.snapshot = doodle.selectedSnapshot

      animator.grid.patternManager:rebuildPatterns(doodle.patterns)
      return true
    else
      print('you have no doodles')
    end
  end
  return false
end

function animator.load(path)
  if animator.closing or type(path)~='string' then return false end
  local loaded=animator.withUpdate(function() return loadDoodle(path) end)
  if loaded then animator.redraw() end
  return loaded
end

function reduceStepLevels(seq, levels)
  levels = levels or {}
  local steps = seq.steps
  local findPos = findPosition
  local max = math.max
  for i=1,#steps do
    local step = steps[i]
    local pos = findPos(step.x, step.y)
    -- step activated
    if animator.on[pos] > 0 then
      if i == seq.index then
        levels[pos] = GRID_LEVELS.HIGH
      else
        levels[pos] = levels[pos] == nil
                and GRID_LEVELS.MED
                or max(levels[pos], GRID_LEVELS.MED)
      end
      -- step highlighted but not activated
    elseif i == seq.index then
      levels[pos] = levels[pos] == nil
              and GRID_LEVELS.LOW_MED
              or max(levels[pos], GRID_LEVELS.LOW_MED)
      -- step not highlighted or activated
    else
      levels[pos] = levels[pos] == nil
              and GRID_LEVELS.DIM
              or max(levels[pos], GRID_LEVELS.DIM)
    end
  end

  return levels
end

function getStepLevels()
  local levels = {}
  for i=1,#animator.sequencers do
    reduceStepLevels(animator.sequencers[i], levels)
  end
  return levels
end

function clearStepState(steps)
  for i=1,#steps do
    local step = steps[i]
    local pos = findPosition(step.x, step.y)
    animator.enabled[pos] = animator.enabled[pos] - 1
  end
end

function clearOnState(steps)
  for i=1,#steps do
    local step = steps[i]
    local pos = findPosition(step.x, step.y)
    if animator.on[pos] > 0 then
      animator.on[pos] = animator.enabled[pos]
    end
  end
end

function animator.initHistory()
  local History=include('anima/lib/history')
  local function capture()
    local state={lines={},on=deepcopy(animator.on),enabled=deepcopy(animator.enabled),
      settings={},intro=animator.showIntroText,lastReplaced=animator.lastReplaced,
      snapshot=animator.grid.snapshot,selected=animator.grid.selected}
    state.storedSnapshot=animator.snapshots[state.snapshot]
    for i=1,8 do state.settings[i]=Settings.capture(i,animator.sequencers[i]) end
    for i,seq in ipairs(animator.sequencers) do
      state.lines[i]={id=seq.editId,steps=deepcopy(seq.steps)}
    end
    return state
  end
  local function restore(state)
    if animator.outputs then animator.outputs:panic() end
    local current={}
    for i,seq in ipairs(animator.sequencers) do current[seq.editId]=Settings.capture(i,seq) end
    animator.sequencers={}
    for i,line in ipairs(state.lines) do
      local settings=current[line.id] or state.settings[i]
      Settings.apply(i,settings)
      animator.sequencers[i]=Sequencer.new({steps=deepcopy(line.steps),editId=line.id},i)
    end
    for i=#state.lines+1,8 do Settings.apply(i,state.settings[i]) end
    animator.on=deepcopy(state.on);animator.enabled=deepcopy(state.enabled)
    animator.showIntroText=state.intro;animator.lastReplaced=state.lastReplaced
    animator.grid.snapshot=state.snapshot;animator.grid.selected=state.selected
    animator.snapshots[state.snapshot]=state.storedSnapshot
    animator.original={};performance={}
    if animator.modulation then animator.modulation:reset() end
  end
  animator.history=History.new(capture,restore,util.time)
end

return animator
