-- Anima 0.5.6
--
-- -- | /
--
-- 2D Polyphonic Sequencer
-- .....................................................
--
-- based on Animator by @crim
--
-- Hold 2 pads to draw a
-- horizontal, vertical or
-- diagonal sequence
--
-- Hold bottom-right, then bottom row
-- 13: Canvas, 14: Lines, 15: Intersections.
-- Intersections: hold column 15 to preview a track on screen.
--
-- E2 / E3 : move sequencers
-- K2 / K3 : reset / clear

local Lifecycle = include('anima/lib/lifecycle')
Lifecycle.stop_stale_lfos(metro)
local constants = include('anima/lib/constants')
local parameters = include('anima/lib/parameters')
local animator = include('anima/lib/animator')
local ui = include('anima/lib/ui')
local GRID = include('anima/lib/Grid')
local Outputs = include('anima/lib/outputs')
local Modulation=include('anima/lib/modulation')
local nbAvailable, nb = pcall(require, 'nbout/lib/nb/lib/nb')
if not nbAvailable then nbAvailable, nb = pcall(require, 'nb/lib/nb') end
local g = grid.connect()
local playing = true
local pulseTask, patternTask
local gridKeyHandler
engine.name = 'MollyThePoly'

function pulse()
  while true do
    -- x1 keeps Animator's legacy quarter-beat pulse; x2 advances on each tick.
    clock.sync(1/8)
    if playing then animator.count() end
  end
end

function init()
  crow.ii.pullup(true)
  crow.ii.jf.mode(1)
  if nbAvailable then nb:init(); animator.nb = nb end
  animator.outputs = Outputs.new{
    engine=engine, midi=midi, crow=crow, metro=metro, time=util.time,
    nb_player=nbAvailable and function(track)
      return params:lookup_param('seq' .. track .. 'nb'):get_player()
    end or nil
  }
  math.randomseed(os.time())
  parameters.init(animator)
  animator.modulation=Modulation.new{time=util.time,beats=function()
    if clock.get_beats then return clock.get_beats() end
    return util.time()/clock.get_beat_sec()
  end}
  animator.grid = GRID.new(animator)
  animator.grid:startFeedback(redraw)
  animator.initHistory()
  gridKeyHandler = animator.grid:createKeyHandler()
  g.key = gridKeyHandler
  pulseTask = clock.run(pulse)
  patternTask = clock.run(function() animator.grid.patternManager:pulse() end)
  clock.transport.stop = function() playing = false; animator.outputs:panic() end
  clock.transport.start = function() animator.reset(1); playing = true end
  animator.redraw()
end

function animator.redraw()
  if animator.closing or animator.updating or not animator.grid then return end
  if animator.grid.view == 1 then
    animator.resetStepLevels()
    animator.grid:redraw()
    redraw()
  else
    animator.setStepLevels(animator.sequencers[animator.grid.selected])
    animator.grid:redraw()
    redraw()
  end
end

function redraw()
  if animator.closing or animator.updating then return end
  ui.redraw(animator.stepLevels, animator.grid, animator.showIntroText)
end

function key(n, z)
  if z == 1 then
    if n == 2 then
      animator.reset(animator.grid.view)
      animator.redraw()
    elseif n == 3 then
      animator.history:perform('clear',function() animator.clear(animator.grid.view) end)
      animator.redraw()
    end
  end
end

function enc(n, delta)
  local selectedOnly = animator.grid.view ~= constants.PAGE_CANVAS
  if n == 1 and selectedOnly then
    animator.grid.selected = util.clamp(animator.grid.selected + delta, 1, 8)
    animator.redraw()
  elseif n == 2 then
    if selectedOnly then
      animator.history:perform('move-y-'..animator.grid.selected,function()
        animator.moveSequence(animator.grid.selected, 'y', delta, constants.CANVAS_HEIGHT) end,0.35)
    else
      animator.history:perform('move-y-all',function()
        animator.moveSequencers('y', delta, constants.CANVAS_HEIGHT) end,0.35)
    end
    animator.redraw()
  elseif n == 3 then
    if selectedOnly then
      animator.history:perform('move-x-'..animator.grid.selected,function()
        animator.moveSequence(animator.grid.selected, 'x', delta, constants.CANVAS_LENGTH) end,0.35)
    else
      animator.history:perform('move-x-all',function()
        animator.moveSequencers('x', delta, constants.CANVAS_LENGTH) end,0.35)
    end
    animator.redraw()
  end
end

function cleanup()
  if animator.closing then return end
  animator.closing = true
  playing = false
  Lifecycle.run{
    {'clock', function()
      if pulseTask then clock.cancel(pulseTask) end
      if patternTask then clock.cancel(patternTask) end
    end},
    {'outputs', function() if animator.outputs then animator.outputs:cleanup() end end},
    {'LFO', parameters.cleanup},
    {'patterns', function()
      if animator.grid then animator.grid.patternManager:cleanup() end
    end},
    {'grid feedback', function() if animator.grid then animator.grid:stopFeedback() end end},
    {'grid holds', function()
      if animator.grid then
        animator.grid:cancelGestureHolds()
        for _,hold in pairs(animator.grid.muteHolds) do
          if hold.task then clock.cancel(hold.task) end
        end
      end
    end},
    {'grid connection', function()
      -- Retire only our own callback. Never blank a newer script's Grid.
      if g.key==gridKeyHandler then
        g.key=nil
        g:all(0)
        g:refresh()
      end
    end},
    {'n.b. players', function()
      if not nbAvailable then return end
      for i=1,8 do
        local id = 'seq' .. i .. 'nb'
        if params.lookup[id] then
          local parameter = params:lookup_param(id)
          local player = parameter.player
          parameter.player = nil
          if player and player.count_down then
            local ok,err = pcall(function() player:count_down() end)
            if not ok then print('Animator n.b. release ('..i..'): '..tostring(err)) end
          end
        end
      end
    end},
  }
end
