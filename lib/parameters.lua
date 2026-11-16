local fileselect = require 'fileselect'
local textentry = require 'textentry'
local constants = include('anima/lib/constants')
local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
local MusicUtil = require "musicutil"
local lfo = include('anima/lib/lfo')

local parameters = {}

local H,L = constants.CANVAS_HEIGHT, constants.CANVAS_LENGTH
local STEP_NUM = H*L

function mapGridNotes(scale, transpose)
  local notes = {}
  local pointer = 0
  local intervals = MusicUtil.generate_scale(24 + transpose, scale, 6)
  local startPos = STEP_NUM - L + 1
  local pos = startPos
  for i=1,H do
    for j=1,L do
      notes[pos] = intervals[pointer+j]
      pos = pos + 1
    end
    startPos = startPos - L
    pos = startPos
    pointer = pointer + 3
  end
  return notes
end

function getScaleNames()
  local names = {}
  local scales = MusicUtil.SCALES
  for i=1,#scales do
    names[#names+1] = scales[i].name
  end
  return names
end

local Settings = include('anima/lib/track_settings')
function addSeqParams(animator, nb, deferLfoSection)
  Settings.add(animator, nb, deferLfoSection)
end

function parameters.init(animator)
  params:add_separator('ANIMATOR')
  params:add_group('SAVE/LOAD', 4)
  params:add_trigger('save', 'save doodle')
  params:set_action('save', function(x) textentry.enter(animator.save, animator.name) end)
  params:add_trigger('load', 'load doodle')
  params:set_action('load', function() fileselect.enter(norns.state.data, animator.load) end)

  params:add_trigger('import_animator2','load Animator 2 doodle')
  params:set_action('import_animator2',function()
    local folder=(_path and _path.data and _path.data..'animator2/')
      or norns.state.data:gsub('anima/$','animator2/')
    fileselect.enter(folder,animator.load)
  end)

  params:add_trigger('import_animator','load Animator original')
  params:set_action('import_animator',function()
    local folder=(_path and _path.data and _path.data..'animator/')
      or norns.state.data:gsub('anima/$','animator/')
    fileselect.enter(folder,animator.load)
  end)

  params:add_group('COMPOSITION', 8)
  params:add_option('animator_playback','playback',{'anima','Animator original'},1)
  params:set_action('animator_playback',function(v)
    animator.originalPlayback=animator.originalPlayback or {
      minVelocity=1,maxVelocity=127,minDurationCs=10,maxDurationCs=10}
    animator.originalPlayback.enabled=v==2
    if animator.outputs then animator.outputs:panic() end
    if animator.modulation then animator.modulation:reset() end
  end)
  params:add_option('scale', 'scale', getScaleNames(), 1)
  params:set_action('scale', function(scale)
    animator.notes = mapGridNotes(scale, params:get('global_transpose'))
  end)
  params:add_number('global_transpose', 'global transpose', -12, 12, 0)
  params:set_action('global_transpose', function(v)
    animator.notes = mapGridNotes(params:get('scale'), v)
  end)
  params:add_option('quantize', 'pattern quantize', {'off', 'on'}, 2)
  params:add_number('quant_div', 'quantization div', 1, 8, 1)
  params:add_number('slop', 'slop', 0, 500, 0)
  params:add_number('max_notes', 'max notes', 1, 10, 6)
  params:add_trigger('panic', 'all notes off')
  params:set_action('panic', function() if animator.outputs then animator.outputs:panic() end end)

  addSeqParams(animator, animator.nb, true)
  Settings.addLfoSection(animator,function() lfo.init(animator) end)

  local hasMoveTarget = {[2] = true, [3] = true}

  for i=1,constants.LFO_NUM do
    params:set_action(i .. 'lfo',
      function(v)
        if v == 1 then
          local hasMove = false
          for j=1,constants.LFO_NUM do
            if j ~= i and hasMoveTarget[params:get(j .. 'lfo_target')] and params:get(j .. 'lfo') == 2 then
              hasMove = true
            end
          end

          if not hasMove then animator.original = {} end
        end
      end
    )
  end

  params:add_group('SYNTH', 'INTERNAL SYNTH (shared)', 47)

  MollyThePoly.add_params()
  params:set('env_2_decay', 0.2)
  params:set('env_2_sustain', 0)
  params:set('env_2_release', 0.1)
  params:set('osc_wave_shape', 1)
  params:set('noise_level', 0)
  params:set('chorus_mix', 0)

  animator.notes = mapGridNotes(params:get('scale'), params:get('global_transpose'))

  params:add_separator()

  if animator.nb then
    params:add_separator('nb_sound', 'N.B. SOUND')
    animator.nb:add_player_params()
  end
end

function parameters.cleanup() lfo.cleanup() end

return parameters
