local Outputs = dofile('lib/outputs.lua')
local function setup()
  local now, log = 0, {}
  local function emit(...) log[#log+1] = table.concat({...}, ':') end
  local devices = {
    time=function() return now end,
    metro={init=function(fn) return {id=1,start=function() end,stop=function() end} end, free=function() end},
    engine={noteOn=function(n) emit('audio-on',n) end,noteOff=function(n) emit('audio-off',n) end},
    midi={connect=function(port)
      return {note_on=function(_,n,v,ch) emit('midi-on',port,ch,n) end,
              note_off=function(_,n,v,ch) emit('midi-off',port,ch,n) end}
    end},
    crow={output={{},{},{},{}},ii={jf={play_note=function(n) emit('jf',n) end},
      er301={cv=function(port) emit('er-cv',port) end,tr_pulse=function(port) emit('er-tr',port) end}}},
    nb_player=function(track) return {name='voice'..track,
      note_on=function(_,n) emit('nb-on',track,n) end,
      note_off=function(_,n) emit('nb-off',track,n) end} end,
  }
  -- Crow's volts setter replaces its ASL action, including after panic or
  -- fixed-pair gates. A plain Lua table would hide a stale pulse action.
  for output=1,4 do
    local state={}
    devices.crow.output[output]=setmetatable({}, {
      __index=state,
      __newindex=function(_,key,value)
        state[key]=value
        if key=='volts' then state.action='constant' end
      end,
    })
  end
  for gate=2,4,2 do
    local index=gate
    devices.crow.output[index].execute=function()
      if devices.crow.output[index].action=='pulse()' then
        emit('crow-pulse',index,devices.crow.output[index-1].volts,devices.crow.output[index].action)
      end
    end
  end
  local out = Outputs.new(devices)
  local function advance(seconds) now=now+seconds; out:tick() end
  return out, log, advance, devices
end
local function seq(kind, port, channel)
  return {output=kind, port=port or 1, channel=channel or 1, erPort=23, duration=100, velocity=100}
end
local function has(log, value)
  for _,entry in ipairs(log) do if entry==value then return true end end
  return false
end
local tests={}
tests['concurrent audio MIDI NB and crow routes remain independent']=function()
  local o,l,advance,d=setup()
  o:play(1,seq(2),{60},1,0.25,0)
  o:play(2,seq(4,3,7),{60},1,0.25,0)
  o:play(3,seq(3),{60},1,0.25,0)
  o:play(4,seq(5),{60},1,0.25,0)
  o:play(5,seq(6),{72},1,0.25,0)
  assert(has(l,'audio-on:60') and has(l,'midi-on:3:7:60') and has(l,'nb-on:3:60'))
  assert(d.crow.output[2].volts==5 and d.crow.output[4].volts==5)
  o:stop_track(2)
  assert(has(l,'midi-off:3:7:60') and not has(l,'audio-off:60') and not has(l,'nb-off:3:60'))
  advance(0.11)
  assert(has(l,'audio-off:60') and has(l,'nb-off:3:60'))
  assert(d.crow.output[2].volts==0 and d.crow.output[4].volts==0)
end
tests['each MIDI track uses its own port and channel']=function()
  local o,l=setup()
  o:play(1,seq(4,2,4),{60},1,0.25,0)
  o:play(2,seq(4,16,9),{60},1,0.25,0)
  assert(has(l,'midi-on:2:4:60') and has(l,'midi-on:16:9:60'))
end
tests['pending ratchets and slop are canceled before routing changes']=function()
  local o,l,advance=setup()
  o:play(1,seq(4,2,4),{60},4,0.5,0)
  o:stop_track(1)
  o:play(1,seq(3),{65},1,0.5,0)
  advance(1)
  tests['zero retrig cancels pending strikes and releases active notes on every destination']=function()
  for kind=2,11 do
    local o,l,advance,d=setup()
    o:play(1,seq(kind),{60},4,1,0)
    local function starts()
      local count=0
      for _,entry in ipairs(l) do
        if entry:find('-on:',1,true) or entry:find('crow-pulse:',1,true)
            or entry:find('jf:',1,true) or entry:find('er-tr:',1,true) then count=count+1 end
      end
      return count
    end
    local before=starts()
    o:play(1,seq(kind),{72},0,1,0)
    assert(#o.queue==0 and next(o.refs)==nil,'rest clears pending notes, destination '..kind)
    advance(2)
    assert(starts()==before,'rest cannot emit another note, destination '..kind)
    if kind==5 then assert(d.crow.output[2].volts==0) end
    if kind==6 then assert(d.crow.output[4].volts==0) end
    o:cleanup()
  end
end

local count=0
  for _,entry in ipairs(l) do if entry=='midi-on:2:4:60' then count=count+1 end end
  assert(count==1 and has(l,'midi-off:2:4:60') and has(l,'nb-on:1:65'))
  o:play(2,seq(4,3,7),{70},2,0.25,200)
  o:stop_track(2); advance(1)
  assert(not has(l,'midi-on:3:7:70'))
end
tests['shared MIDI pitch is not released by a different track']=function()
  local o,l=setup()
  o:play(1,seq(4),{60},1,0.25,0)
  o:play(2,seq(4),{60},1,0.25,0)
  o:stop_track(1)
  assert(not has(l,'midi-off:1:1:60'))
  o:stop_track(2)
  assert(has(l,'midi-off:1:1:60'))
end
tests['crow gates respect the last owner of each physical pair']=function()
  local o,l,advance,d=setup()
  local first=seq(5);first.duration=30
  local second=seq(5);second.duration=200
  o:play(1,first,{60},1,0.5,0)
  o:play(2,second,{72},1,0.5,0)
  advance(0.04)
  assert(d.crow.output[1].volts==1 and d.crow.output[2].volts==5)
  advance(0.2)
  assert(d.crow.output[2].volts==0)
end
tests['ratchets are distributed within the track step and cleanup releases notes']=function()
  local o,l,advance=setup()
  o:play(1,seq(3),{60},4,1,0)
  advance(0.24)
  local count=0;for _,s in ipairs(l) do if s=='nb-on:1:60' then count=count+1 end end
  assert(count==1)
  advance(0.01)
  count=0;for _,s in ipairs(l) do if s=='nb-on:1:60' then count=count+1 end end
  assert(count==2)
  o:cleanup()
  local before=#l;advance(2);assert(#l==before and next(o.refs)==nil)
end
tests['JF and ER301 use their assigned routes']=function()
  local o,l=setup()
  o:play(1,seq(7),{60},1,0.5,0)
  o:play(2,seq(8),{60},1,0.5,0)
  assert(has(l,'jf:0.0') or has(l,'jf:0'))
  assert(has(l,'er-cv:23') and has(l,'er-tr:23'))
end
tests['cleanup releases other destinations even if one NB note off fails']=function()
  local o,l,advance,d=setup()
  d.nb_player=function() return {name='faulty',note_on=function() end,
    note_off=function() error('simulated NB note_off failure') end} end
  o:play(1,seq(3),{60},4,1,0)
  o:play(2,seq(4,3,7),{65},1,1,0)
  o:play(3,seq(5),{72},1,1,0)
  o:cleanup();o:cleanup()
  assert(has(l,'midi-off:3:7:65'))
  assert(d.crow.output[2].volts==0 and next(o.refs)==nil and #o.queue==0)
  assert(o.last_error:find('simulated NB note_off failure',1,true))
  local before=#l
  advance(2);o:play(2,seq(4),{60},1,1,0)
  assert(#l==before,'closed router never emits after cleanup')
end

tests['NB plus MIDI emits both destinations with matching velocity and release time']=function()
  local o,l,advance,d=setup()
  local sent={}
  d.nb_player=function() return {name='layer voice',
    note_on=function(_,note,velocity) sent.nb={note,velocity} end,
    note_off=function(_,note) sent.nbOff=note end} end
  d.midi.connect=function(port) return {
    note_on=function(_,note,velocity,channel) sent.midi={note,velocity,port,channel} end,
    note_off=function(_,note,_,channel) sent.midiOff={note,channel} end} end
  local track=seq(9,16,7);track.velocity=81
  o:play(1,track,{64},1,0.5,0)
  assert(sent.nb[1]==64 and sent.nb[2]==81/127)
  assert(sent.midi[1]==64 and sent.midi[2]==81 and sent.midi[3]==16 and sent.midi[4]==7)
  advance(0.09);assert(not sent.nbOff and not sent.midiOff)
  advance(0.02);assert(sent.nbOff==64 and sent.midiOff[1]==64 and sent.midiOff[2]==7)
end
tests['internal synth plus MIDI sends a chord to both destinations']=function()
  local o,l,advance=setup()
  o:play(1,seq(10,3,5),{60,64,67,71},1,0.5,0)
  for _,note in ipairs({60,64,67,71}) do
    assert(has(l,'audio-on:'..note) and has(l,'midi-on:3:5:'..note))
  end
  advance(0.11)
  for _,note in ipairs({60,64,67,71}) do
    assert(has(l,'audio-off:'..note) and has(l,'midi-off:3:5:'..note))
  end
end
tests['ratchet chords repeat equally on both combination destinations']=function()
  for _,kind in ipairs({9,10}) do
    local o,l,advance=setup()
    o:play(1,seq(kind,3,7),{60,64,67},4,0.5,0)
    for repeatIndex=1,4 do advance(0.125) end
    local midiOn,otherOn,midiOff,otherOff=0,0,0,0
    local label=kind==9 and 'nb' or 'audio'
    for _,entry in ipairs(l) do
      if entry:match('^midi%-on:') then midiOn=midiOn+1 end
      if entry:match('^'..label..'%-on:') then otherOn=otherOn+1 end
      if entry:match('^midi%-off:') then midiOff=midiOff+1 end
      if entry:match('^'..label..'%-off:') then otherOff=otherOff+1 end
    end
    assert(midiOn==12 and otherOn==12 and midiOff==12 and otherOff==12)
  end
end
tests['changing away from a combination cancels both legs and queued repeats']=function()
  local o,l,advance=setup()
  o:play(1,seq(9,3,7),{60},4,1,0)
  o:play(2,seq(4,4,8),{72},1,1,0)
  o:stop_track(1)
  assert(has(l,'nb-off:1:60') and has(l,'midi-off:3:7:60'))
  assert(not has(l,'midi-off:4:8:72'),'other track stays held')
  o:play(1,seq(10,6,9),{65},1,1,0)
  advance(2)
  local oldNb,oldMidi=0,0
  for _,entry in ipairs(l) do
    if entry=='nb-on:1:60' then oldNb=oldNb+1 end
    if entry=='midi-on:3:7:60' then oldMidi=oldMidi+1 end
  end
  assert(oldNb==1 and oldMidi==1)
  assert(has(l,'audio-on:65') and has(l,'midi-on:6:9:65'))
end
tests['a failing or absent NB player does not block the MIDI leg']=function()
  for _,failure in ipairs({'absent','note_on','note_off'}) do
    local o,l,advance,d=setup()
    d.nb_player=function() return {name='faulty',
      note_on=function() if failure=='note_on' then error('test NB start failure') end end,
      note_off=function() if failure=='note_off' then error('test NB release failure') end end} end
    if failure=='absent' then d.nb_player=nil end
    o:play(1,seq(9,3,7),{60},2,0.5,0)
    assert(has(l,'midi-on:3:7:60'))
    o:cleanup()
    assert(has(l,'midi-off:3:7:60') and next(o.refs)==nil and #o.queue==0)
  end
end
tests['shared MIDI pitch survives releasing a combination on another track']=function()
  local o,l=setup()
  o:play(1,seq(9,1,1),{60},1,0.5,0)
  o:play(2,seq(4,1,1),{60},1,0.5,0)
  o:stop_track(1)
  assert(has(l,'nb-off:1:60') and not has(l,'midi-off:1:1:60'))
  o:stop_track(2)
  assert(has(l,'midi-off:1:1:60'))
end

tests['a failed NB layer does not release the same pitch owned by another track']=function()
  local o,l,advance,d=setup()
  local fail=false
  d.nb_player=function() return {name='shared',
    note_on=function() if fail then error('shared voice start failed') end end,
    note_off=function() l[#l+1]='shared-off' end} end
  o:play(1,seq(3),{60},1,0.5,0)
  fail=true
  o:play(2,seq(9,3,7),{60},1,0.5,0)
  assert(not has(l,'shared-off'),'failure cannot cut the other track')
  assert(has(l,'midi-on:3:7:60'))
  o:stop_track(1)
  assert(has(l,'shared-off'))
  o:cleanup()
end

tests['original Crow uses hardware pulses and ignores note length'] = function()
  local o,l,advance,d=setup()
  local track=seq(11);track.duration=4000
  o:play(1,track,{60},1,1,0)
  assert(d.crow.output[2].action=='pulse()')
  assert(d.crow.output[1].volts==0 and #o.queue==0,'crow controls pulse timing')
  assert(#l==1 and l[1]:match('^crow%-pulse:2:'))
  advance(5)
  assert(d.crow.output[1].volts==0 and #l==1,'pitch remains held between notes')
  o:panic();assert(d.crow.output[2].volts==0,'panic closes the owned trigger')
end
tests['original Crow has a two voice budget shared across tracks per step'] = function()
  local o,l,advance,d=setup()
  o:play(1,seq(11),{60},1,1,0)
  o:play(2,seq(11),{64},1,1,0)
  o:play(3,seq(11),{67},1,1,0)
  assert(#l==2 and d.crow.output[1].volts==0 and d.crow.output[3].volts==4/12)
  o:begin_step()
  o:play(3,seq(11),{72},1,1,0)
  assert(#l==3 and d.crow.output[1].volts==1,'first note of next step returns to 1/2')
end
tests['delayed original Crow events retain the allocator of their own step'] = function()
  local o,l,advance,d=setup()
  local originalRandom=math.random
  math.random=function() return 50 end
  o:play(1,seq(11),{60},1,1,100)
  o:play(2,seq(11),{64},1,1,100)
  o:begin_step()
  o:play(3,seq(11),{67},1,1,100)
  o:play(4,seq(11),{72},1,1,100)
  math.random=originalRandom
  advance(0.06)
  assert(#l==4,'each originating step retains two voices despite overlapping delays')
end
tests['new ratchets retrigger the original hardware pulse'] = function()
  local o,l,advance=setup()
  o:play(1,seq(11),{60,64,67},3,0.75,0)
  advance(0.25);advance(0.25)
  assert(#l==6,'two hardware voices on each of three ratchets')
end
tests['original Crow preserves voltage conversion outside the MIDI note range'] = function()
  local o,l,advance,d=setup()
  o:play(1,seq(11),{-1,139},1,1,0)
  assert(d.crow.output[1].volts==(-1-60)/12)
  assert(d.crow.output[3].volts==(139-60)/12)
end

tests['original Crow restores pulses after repeated transport and snapshot panics'] = function()
  local o,l=setup()
  for cycle=1,4 do
    o:begin_step()
    o:play(1,seq(11),{60,64},1,1,0)
    assert(#l==cycle*2,'both pairs must pulse again after panic')
    o:panic()
  end
end

tests['original Crow restores each pulse after a fixed gate used the pair'] = function()
  local o,l,advance,d=setup()
  o:play(1,seq(11),{60,64},1,1,0)
  o:play(1,seq(5),{67},1,1,0)
  o:play(2,seq(6),{72},1,1,0)
  advance(0.11)
  o:begin_step()
  o:play(1,seq(11),{62,65},1,1,0)
  assert(#l==4,'fixed voltage writes must not leave either trigger muted')
end

tests['fixed gate releases cannot interrupt a new original pulse on the same pair'] = function()
  local o,l,advance,d=setup()
  o:play(1,seq(5),{60},1,1,0)
  o:play(2,seq(6),{64},1,1,0)
  o:play(3,seq(11),{67,72},1,1,0)
  advance(0.11)
  assert(#l==2 and next(o.refs)==nil,'new owner retires both old fixed gates')
  assert(d.crow.output[2].action=='pulse()' and d.crow.output[4].action=='pulse()',
    'stale software note offs must not overwrite the new pulses')
end

tests['original Crow prepares only its allocated pair beside independent routes'] = function()
  local o,l,advance,d=setup()
  o:play(1,seq(6),{72},1,1,0)
  o:play(2,seq(11),{60},1,1,0)
  o:play(3,seq(9),{64},1,1,0)
  assert(d.crow.output[4].volts==5 and d.crow.output[4].action=='constant',
    'preparing pair 1/2 must leave the fixed gate on 3/4 alone')
  assert(has(l,'nb-on:3:64') and has(l,'midi-on:1:1:64'))
  advance(0.11)
  assert(d.crow.output[4].volts==0 and d.crow.output[2].action=='pulse()')
end

tests['zero retrig cancels pending strikes and releases active notes on every destination']=function()
  for kind=2,11 do
    local o,l,advance,d=setup()
    o:play(1,seq(kind),{60},4,1,0)
    local function starts()
      local count=0
      for _,entry in ipairs(l) do
        if entry:find('-on:',1,true) or entry:find('crow-pulse:',1,true)
            or entry:find('jf:',1,true) or entry:find('er-tr:',1,true) then count=count+1 end
      end
      return count
    end
    local before=starts()
    o:play(1,seq(kind),{72},0,1,0)
    assert(#o.queue==0 and next(o.refs)==nil,'rest clears pending notes, destination '..kind)
    advance(2)
    assert(starts()==before,'rest cannot emit another note, destination '..kind)
    if kind==5 then assert(d.crow.output[2].volts==0) end
    if kind==6 then assert(d.crow.output[4].volts==0) end
    o:cleanup()
  end
end

tests['each ratchet strike draws chance independently across every output route']=function()
  for kind=2,11 do
    local o,l,advance,d=setup();local draws=0;local sent=0
    d.random=function(max) assert(max==100);draws=draws+1;return draws%2==1 and 75 or 25 end
    local send=o.note_destination
    o.note_destination=function(self,...) sent=sent+1;return send(self,...) end
    o:play(1,seq(kind),{60},4,1,0,50)
    assert(draws==1 and sent==0,'failed first strike cannot play or discard later slots')
    advance(0.25);assert(draws==2)
    local layers=(kind==9 or kind==10) and 2 or 1
    assert(sent==layers,'second slot passes')
    if kind==5 or kind==6 then assert(d.crow.output[kind==5 and 2 or 4].volts==5) end
    advance(0.11);advance(0.14)
    assert(draws==3 and sent==layers,'third slot skips')
    if kind==5 or kind==6 then assert(d.crow.output[kind==5 and 2 or 4].volts==0) end
    advance(0.25);assert(draws==4 and sent==2*layers,'fourth slot passes')
    advance(0.3);assert(next(o.refs)==nil);o:cleanup()
  end
end
tests['chord and combination outputs share one chance decision per ratchet attack']=function()
  for _,kind in ipairs({9,10}) do
    local o,l,advance,d=setup();local draws=0
    d.random=function() draws=draws+1;return draws%2==1 and 75 or 25 end
    o:play(1,seq(kind,3,7),{60,64,67},4,1,0,50)
    for i=1,4 do advance(0.25) end
    local midi,other=0,0;local label=kind==9 and 'nb' or 'audio'
    for _,entry in ipairs(l) do
      if entry:match('^midi%-on:') then midi=midi+1 end
      if entry:match('^'..label..'%-on:') then other=other+1 end
    end
    assert(draws==4 and midi==6 and other==6,'two complete three-note chords on both layers')
    o:cleanup()
  end
end
tests['zero full and bypassed chance preserve rests and normal ratchet playback']=function()
  local o,l,advance,d=setup()
  d.random=function() error('extreme or disabled chance must not draw') end
  o:play(1,seq(4),{60},4,1,0,0)
  assert(#o.queue==0 and #l==0 and next(o.refs)==nil,'zero chance reserves no events')
  o:play(1,seq(4),{60},4,1,0,100)
  for i=1,4 do advance(0.25) end
  local count=0;for _,entry in ipairs(l) do if entry=='midi-on:1:1:60' then count=count+1 end end
  assert(count==4,'100 percent plays every slot')
  o:play(1,seq(4),{64},4,1,0)
  o:play(1,seq(4),{67},4,1,0,0)
  assert(#o.queue==0 and next(o.refs)==nil,'zero chance also retires prior notes and queued strikes')
  o:play(1,seq(4),{72},4,1,0)
  for i=1,4 do advance(0.25) end
  count=0;for _,entry in ipairs(l) do if entry=='midi-on:1:1:72' then count=count+1 end end
  assert(count==4,'bypassed chance plays every slot');o:cleanup()
end
tests['cancelling a ratchet also cancels future chance decisions']=function()
  for _,cancel in ipairs({'track','panic','cleanup'}) do
    local o,l,advance,d=setup();local draws=0
    d.random=function() draws=draws+1;return 75 end
    o:play(1,seq(4),{60},4,1,0,50)
    assert(draws==1 and #l==0)
    if cancel=='track' then o:stop_track(1) elseif cancel=='panic' then o:panic() else o:cleanup() end
    advance(2);assert(draws==1 and #l==0 and #o.queue==0,'no decisions or sound after cancellation')
    o:cleanup()
  end
end

local count=0
for name,test in pairs(tests) do test();count=count+1;print('PASS '..name) end
print(count..'/'..count..' passed')
