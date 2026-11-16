-- One definition for EDIT, runtime state, snapshots and line deletion.
local C = include('anima/lib/constants')
local Mod = include('anima/lib/modulation')
local ControlSpec = require 'core/controlspec'
local S = {}
-- Append destinations: existing doodles store these option indices.
S.routes = {'off', 'internal', 'nb', 'midi', 'crow12', 'crow34', 'jf', 'er301', 'nb_midi', 'internal_midi', 'crow_original'}
S.routeNames = {'off', 'internal synth', 'n.b.', 'MIDI', 'crow 1/2', 'crow 3/4', 'Just Friends', 'ER-301', 'n.b. + MIDI', 'internal synth + MIDI', 'crow cv (original)'}
S.fields = {
  {key='output', name='output', options=S.routeNames, default=2, routing=true},
  {key='port', name='MIDI device', min=1, max=16, default=1, routing=true},
  {key='channel', name='MIDI channel', min=1, max=16, default=1, routing=true},
  {key='erPort', name='ER-301 port', min=1, max=100, default=1, routing=true},
  {key='rate', name='rate', options=C.RATE_LABELS, default=C.RATE_DEFAULT},
  {key='direction', name='direction', options=C.DIRECTIONS, default=1},
  {key='muted', name='mute', boolean=true, default=false},
  {key='solo', name='solo', boolean=true, default=false},
  {key='probabilityEnabled', name='probability enabled', boolean=true, default=false},
  {key='probability', name='probability %', min=0, max=100, default=75},
  {key='ratchetEnabled', name='ratchet enabled', boolean=true, default=false},
  {key='ratchet', name='ratchet repeats', min=0, max=4, default=2},
  {key='velocity', name='velocity', min=1, max=127, default=100},
  {key='duration', name='note length ms', min=5, max=4000, default=120},
  {key='transpose', name='transpose semitones', min=-48, max=48, default=0},
  {key='harmonic', name='intersection harmony', options=C.HARMONIC_ACTIONS, default=1},
  {key='triadType', name='triad type', options=C.TRIAD_TYPES, default=1},
  {key='seventhType', name='seventh type', options=C.SEVENTH_TYPES, default=1},
  {key='rhythm', name='intersection rhythm', options=C.RHYTHM_ACTIONS, default=1},
}
local baseCount=#S.fields
for _,field in ipairs(Mod.fields()) do S.fields[#S.fields+1]=field end
function S.id(track, key) return 'seq' .. track .. key end
function S.exists(id) return params.lookup[id] ~= nil end
function S.capture(track, seq)
  local result = {}
  for _,f in ipairs(S.fields) do
    local value = seq and seq[f.key]
    if value == nil then
      if seq and f.mod then value=f.default
      else
        value = params:get(S.id(track, f.key))
        if f.boolean then value = value == 2 end
      end
    end
    result[f.key] = value
  end
  result.nbVoice = params:get(S.id(track, 'nb_hidden_string'))
  return result
end
function S.apply(track, settings, seq)
  for _,f in ipairs(S.fields) do
    local value = settings and settings[f.key]
    if value == nil then value = f.default end
    local paramValue = f.boolean and (value and 2 or 1) or value
    if f.target then Mod.configure(track,f.key,value,false) end
    params:set(S.id(track, f.key), paramValue, true)
    if seq then seq[f.key] = value end
  end
  params:set(S.id(track, 'nb_hidden_string'), settings and settings.nbVoice or 'none')
end
local function addField(animator,i,field)
  local f = field
  local id = S.id(i, f.key)
  if f.boolean then
    params:add_option(id, f.name, {'off', 'on'}, f.default and 2 or 1)
  elseif f.spec then
    params:add_control(id,f.name,ControlSpec.new(table.unpack(f.spec)))
  elseif f.options then
    params:add_option(id, f.name, f.options, f.default)
  else
    params:add_number(id, f.name, f.min, f.max, f.default, f.formatter)
  end
  local lastTarget=f.default
  params:set_action(id, function(v)
    if animator.outputs and (f.routing or (f.key == 'muted' and v == 2)) then
      animator.outputs:stop_track(i)
    end
    if f.key == 'solo' and animator.outputs then animator.outputs:panic() end
    if f.key=='modEnabled' and animator.modulation then animator.modulation:reset(i) end
    if f.target then
      local current=animator.sequencers[i]
      Mod.configure(i,f.key,v,(current and current[f.key]~=v) or (not current and lastTarget~=v))
      lastTarget=v
      local seq=animator.sequencers[i]
      if seq then
        for _,edge in ipairs({'Min','Max'}) do seq[f.key..edge]=params:get(S.id(i,f.key..edge)) end
      end
    end
    local seq = animator.sequencers[i]
    if seq then
      if f.boolean then seq[f.key] = v == 2 else seq[f.key] = v end
      if f.key == 'direction' then seq.directionStep = 1 end
      if f.mod and animator.modulation then animator.modulation:prune(seq,i) end
    end
    if animator.grid then animator.redraw() end
  end)
end

function S.add(animator, nb, deferLfoSection)
  -- The old intersection enum is retained solely for importing old doodles.
  params:add_group('legacy', 'legacy import', 8)
  params:hide('legacy')
  for track=1,8 do
    local i = track
    local id = S.id(i, 'intersect')
    params:add_option(id, 'legacy intersection', C.INTERSECT_OPS, 1)
    params:set_action(id, function(v)
      if animator.sequencers[i] then animator.sequencers[i].intersect = v end
    end)
  end
  for track=1,8 do
    local i = track
    params:add_group('track' .. i, 'TRACK ' .. i, baseCount + 2)
    for _,field in ipairs(S.fields) do if not field.mod then addField(animator,i,field) end end
    if nb then
      nb:add_param(S.id(i, 'nb'), 'n.b. voice')
      for _,key in ipairs({'nb', 'nb_hidden_string'}) do
        local id = S.id(i, key)
        local parameter = params:lookup_param(id)
        local originalAction = parameter.action
        params:set_action(id, function(value)
          if animator.outputs then animator.outputs:stop_track(i) end
          if originalAction then originalAction(value) end
        end)
      end
    else
      params:add_option(S.id(i, 'nb'), 'n.b. (install nb/nbout)', {'unavailable'}, 1)
      params:add_text(S.id(i, 'nb_hidden_string'), 'n.b. saved voice', 'none')
      params:hide(S.id(i, 'nb_hidden_string'))
    end
  end
  if not deferLfoSection then S.addLfoSection(animator) end
end

-- One EDIT group; its selectors only change which real controls are visible.
-- Parameter IDs and actions stay independent for every oscillator and track.
function S.addLfoSection(animator, generalInit)
  local scopes={'general LFO'}
  for track=1,8 do scopes[#scopes+1]='track '..track end
  local modCount=#S.fields-baseCount
  params:add_group('LFO','LFO',2+(generalInit and 14 or 0)+8*modCount)
  params:add_option('anima_lfo_section','section',scopes,1,false)
  params:add_option('anima_lfo_oscillator','oscillator',{'LFO 1','LFO 2'},1,false)
  params:set_save('anima_lfo_section',false)
  params:set_save('anima_lfo_oscillator',false)
  local general={}
  if generalInit then
    local first=params.count+1
    generalInit()
    assert(params.count-first+1==14,'unexpected general LFO parameter count')
    for index=first,params.count do
      general[#general+1]={index=index,oscillator=math.floor((index-first)/7)+1}
    end
  end
  for track=1,8 do
    for _,field in ipairs(S.fields) do if field.mod then addField(animator,track,field) end end
  end
  local function visible(id,show)
    if show then params:show(id) else params:hide(id) end
  end
  local function refresh()
    local scope=params:get('anima_lfo_section')
    local oscillator=params:get('anima_lfo_oscillator')
    for _,entry in ipairs(general) do
      visible(entry.index,scope==1 and entry.oscillator==oscillator)
    end
    for track=1,8 do
      for _,field in ipairs(S.fields) do
        if field.mod then
          local slot=tonumber(field.key:match('^lfo(%d)'))
          visible(S.id(track,field.key),scope==track+1 and (not slot or slot==oscillator))
        end
      end
    end
    if _menu and _menu.rebuild_params then _menu.rebuild_params() end
  end
  params:set_action('anima_lfo_section',refresh)
  params:set_action('anima_lfo_oscillator',refresh)
  refresh()
end
return S
