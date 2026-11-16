-- One bounded event queue for all outputs: no per-note metro allocation.
-- Route changes, recalls and cleanup release the original destination.
local O = {}
O.__index = O
local COMBINATIONS = {[9]={3,4}, [10]={2,4}}
function O.new(devices)
  local self = setmetatable({d=devices, queue={}, active={}, refs={}, ports={}, closed=false}, O)
  self.crowPulsePairs = {}
  self:begin_step()
  self.timer = devices.metro.init(function() self:tick() end, 0.005, -1)
  self.timer:start()
  return self
end
function O:begin_step()
  -- The original allocator restarts at 1/2 on every Animator clock tick.
  -- Delayed notes capture this table, not a future tick's allocator.
  self.crowFrame = {nextPitch=1, count=0, played={}}
end
function O:schedule(delay, track, fn)
  if self.closed then return end
  self.queue[#self.queue+1] = {at=self.d.time()+delay, track=track, fn=fn}
end
function O:tick()
  if self.closed then return end
  local pending, now = self.queue, self.d.time()
  self.queue = {}
  for _,event in ipairs(pending) do
    if event.at <= now then event.fn() else self.queue[#self.queue+1] = event end
  end
end
function O:release(token)
  if token.released then return end
  token.released = true
  local ref = self.refs[token.key]
  if not ref then return end
  ref.count = ref.count - 1
  if self.active[token.track] then self.active[token.track][token] = nil end
  if ref.count==0 then self.refs[token.key]=nil end
  if ref.count==0 or token.independentOff then
    local ok,err = pcall(token.independentOff or ref.off)
    if not ok then
      self.last_error = tostring(err)
      print('Animator note release failed (' .. token.key .. '): ' .. tostring(err))
    end
  end
end
function O:stop_track(track)
  local keep = {}
  for _,event in ipairs(self.queue) do
    if event.track ~= track then keep[#keep+1] = event end
  end
  self.queue = keep
  local active = self.active[track] or {}
  for token in pairs(active) do self:release(token) end
  self.active[track] = {}
end
function O:panic()
  for track=1,8 do self:stop_track(track) end
  for pitch in pairs(self.crowPulsePairs) do
    self.d.crow.output[pitch+1].volts = 0
  end
  self.crowPulsePairs = {}
end
function O:cleanup()
  if self.closed then return end
  self.closed = true
  self.timer:stop()
  self:panic()
  self.d.metro.free(self.timer.id)
end
function O:release_crow_pair(pitch)
  -- A physical pair has one owner. Retire old fixed gates before taking it,
  -- otherwise their queued note-offs would replace the new pulse with 0 V.
  local previous = {}
  for _,tokens in pairs(self.active) do
    for token in pairs(tokens) do
      if token.key == 'crow:' .. pitch then previous[#previous+1] = token end
    end
  end
  for _,token in ipairs(previous) do self:release(token) end
end
function O:note_destination(track, seq, note, velocity, seconds, kind, crowFrame, independent)
  local d, on, off, key = self.d
  if kind == 1 then return end
  if kind == 2 then
    key = 'internal:' .. note
    on = function() d.engine.noteOn(note, 440*2^((note-69)/12), velocity/127) end
    off = function() d.engine.noteOff(note) end
  elseif kind == 3 then
    local player = d.nb_player and d.nb_player(track)
    if not player then return end
    key = 'nb:' .. tostring(player.name or player) .. ':' .. note
    on = function() player:note_on(note, velocity/127) end
    off = function() player:note_off(note) end
  elseif kind == 4 then
    local port, channel = seq.port, seq.channel
    if not self.ports[port] then self.ports[port] = d.midi.connect(port) end
    local device = self.ports[port]
    key = 'midi:' .. port .. ':' .. channel .. ':' .. note
    on = function() device:note_on(note, velocity, channel) end
    off = function() device:note_off(note, 0, channel) end
  elseif kind == 5 or kind == 6 then
    local pitch = kind == 5 and 1 or 3
    local gate = pitch + 1
    -- A physical pitch/gate pair has one owner; the latest line takes it.
    self:release_crow_pair(pitch)
    key = 'crow:' .. pitch
    on = function()
      d.crow.output[pitch].volts = (note-60)/12
      d.crow.output[gate].volts = 5
    end
    off = function() d.crow.output[gate].volts = 0 end
  elseif kind == 7 then
    d.crow.ii.jf.play_note((note-60)/12, velocity/127*5)
    return -- JF manages the envelope itself.
  elseif kind == 8 then
    d.crow.ii.er301.cv(seq.erPort, (note-60)/12)
    d.crow.ii.er301.tr_pulse(seq.erPort)
    return
  elseif kind == 11 then
    local frame = crowFrame or self.crowFrame
    if frame.count >= 2 or frame.played[note] == seq.channel then return end
    local pitch = frame.nextPitch
    self:release_crow_pair(pitch)
    d.crow.output[pitch].volts = (note-60)/12
    -- Crow's volts setter also replaces its ASL action. Panic and fixed
    -- gates use that setter, so restore the allocated trigger on every note.
    d.crow.output[pitch+1].action = 'pulse()'
    d.crow.output[pitch+1].execute()
    self.crowPulsePairs[pitch] = true
    frame.count = frame.count + 1
    frame.nextPitch = (pitch+2)%4
    frame.played[note] = seq.channel
    return -- crow runs the original 10ms pulse; note length does not gate it.
  end
  if not key then return end
  local started,err = pcall(on)
  if not started then
    -- Some adapters can fail after starting a note. Attempt to close it
    -- before reporting the error and continuing the other destination.
    if not self.refs[key] then pcall(off) end
    error(err,0)
  end
  local ref = self.refs[key] or {count=0, off=off}
  ref.count = ref.count + 1
  self.refs[key] = ref
  local token = {track=track, key=key,independentOff=independent and off or nil}
  self.active[track] = self.active[track] or {}
  self.active[track][token] = true
  self:schedule(seconds, track, function() self:release(token) end)
end
function O:note(track, seq, note, velocity, seconds, crowFrame, independent)
  if self.closed then return end
  local kind = seq.output or 2
  if kind ~= 11 and not independent then note = math.max(0, math.min(127, math.floor(note))) end
  local function send(kind)
    local ok,err = pcall(self.note_destination,self,track,seq,note,velocity,seconds,kind,crowFrame,independent)
    if not ok then
      self.last_error = tostring(err)
      print('Animator output failed (track '..track..', destination '..kind..'): '..tostring(err))
    end
  end
  local combination = COMBINATIONS[kind]
  if combination then
    for _,destination in ipairs(combination) do send(destination) end
  else
    send(kind)
  end
end
-- Original articulation: random velocity and centisecond duration on each
-- event, no per-step cancellation and independent note-offs for overlapping notes.
function O:play_original(track,seq,note,settings,slop)
  if self.closed then return end
  local originalLayers={{2},{4},{4,2},{7},{11},{7,11},{7,11,2},{8}}
  local kinds=(seq.output==settings.sourceRoute and originalLayers[settings.sourceOutput])
    or COMBINATIONS[seq.output] or {seq.output}
  local event={};for key,value in pairs(seq) do event[key]=value end
  local frame=self.crowFrame
  local function strike()
    local audioMidi=false
    for _,kind in ipairs(kinds) do if kind==2 or kind==3 or kind==4 then audioMidi=true end end
    local velocity=audioMidi and math.random(settings.minVelocity,settings.maxVelocity) or 127
    local duration=audioMidi and math.random(settings.minDurationCs,settings.maxDurationCs)/100 or 0.1
    for _,kind in ipairs(kinds) do
      event.output=kind
      if kind==8 then
        local offset=frame.originalERCount or 0
        event.erPort=(seq.erPort or 1)+offset;frame.originalERCount=(offset+1)%8
      end
      self:note(track,event,note,velocity,duration,frame,true)
    end
  end
  if slop>0 then self:schedule(math.random(slop)/1000,track,strike) else strike() end
end
function O:play(track, seq, notes, repeats, stepSeconds, slop, probability)
  if self.closed then return end
  self:stop_track(track)
  if repeats<=0 or (probability~=nil and probability<=0) then return end
  local duration = (seq.duration or 120)/1000
  local spacing = stepSeconds/repeats
  local delay = slop > 0 and (seq.output == 11 and math.random(slop) or math.random()*slop)/1000 or 0
  local crowFrame = self.crowFrame
  local function strike(frame)
    -- One independent decision per repetition, shared by its chord and all
    -- output layers. Keep the original slots/timing even when a strike skips.
    if probability~=nil and probability<100 and (self.d.random or math.random)(100)>probability then return end
    for _,note in ipairs(notes) do
      self:note(track, seq, note, seq.velocity or 100, math.min(duration, spacing*0.9),frame)
    end
  end
  for repeatIndex=1,repeats do
    local offset = delay + (repeatIndex-1)*spacing
    -- Ratchets are new articulation events, each with its own two-voice pool.
    local frame = repeatIndex == 1 and crowFrame or {nextPitch=1,count=0,played={}}
    if offset == 0 then strike(frame) else self:schedule(offset, track, function() strike(frame) end) end
  end
end
return O
