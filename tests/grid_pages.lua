-- Run from the repository root:
-- lua tests/grid_pages.lua /path/to/norns /path/to/existing/test-data-directory
local nornsRoot, dataDir = assert(arg[1]), assert(arg[2])
package.path = nornsRoot .. '/lua/?.lua;' .. nornsRoot .. '/lua/lib/?.lua;' .. package.path
util = require 'util'
norns = {state = {data = dataDir .. '/', shortname = 'anima'}, pmap = {data = {}}}
metro = {init = function() return {} end}
package.preload.fileselect = function() return {} end
package.preload.textentry = function() return {} end
package.preload['molly_the_poly/lib/molly_the_poly_engine'] = function() return {} end
package.preload.pattern_time = function()
  return {new = function()
    return {count=0, rec=0, play=0, watch=function() end}
  end}
end

local leds, frames = {}, {}
grid = {connect = function()
  return {
    all=function() leds = {} end,
    led=function(_, x, y, level) leds[y * 100 + x] = level end,
    refresh=function()
      local frame={}
      for key,value in pairs(leds) do frame[key]=value end
      frames[#frames+1]=frame
    end
  }
end}

function include(path)
  path = path:gsub('^anima/', '')
  if path == 'lib/lfo' then return {} end
  return dofile(path .. '.lua')
end

local ParamSet = require 'core/paramset'
local function setup()
  params = ParamSet.new()
  local animator = include('lib/animator')
  include('lib/parameters')
  addSeqParams(animator)
  local Grid = include('lib/Grid')
  local controller = Grid.new(animator)
  animator.grid = controller
  animator.redraw = function() end
  animator.addNewSequence({{x=1,y=1}, {x=2,y=1}, {x=3,y=1}})
  return animator, controller
end

local function eq(actual, expected, label)
  assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local tests = {}
tests['hold corner selects any page without editing the bottom row'] = function()
  local animator, controller = setup()
  local key = controller:createKeyHandler()
  animator.redraw = function() controller:redraw() end
  eq(controller.view, 1, 'initial')
  key(16,8,1)
  eq(controller.view, 1, 'press corner does not cycle')
  eq(leds[813], 15, 'canvas selector lit')
  key(15,8,1); eq(controller.view, 3, 'direct intersections')
  key(16,8,0); key(15,8,0)
  key(16,8,1); key(13,8,1); key(13,8,0); key(16,8,0)
  eq(controller.view, 1, 'direct canvas')
  key(16,8,1); key(14,8,1); key(14,8,0); key(16,8,0)
  eq(controller.view, 2, 'direct lines')
  eq(animator.sequencers[1].rate, 2, 'navigation did not change rate')
  assert(not next(animator.snapshots), 'navigation must not record a snapshot')
end

tests['lines page exposes only live controls'] = function()
  local animator, controller = setup()
  local seq = animator.sequencers[1]
  controller:linesKeyDown(1, 1)
  eq(seq.muted, true, 'mute')
  controller:linesKeyDown(3, 1)
  eq(seq.direction, 2, 'reverse')
  controller:linesKeyDown(6, 1)
  eq(seq.ratchetEnabled, true, 'ratchet')
  controller:linesKeyDown(7, 1)
  eq(seq.probabilityEnabled, true, 'probability')
  controller:linesKeyDown(9, 1)
  eq(seq.rate, 1, 'x2')
  controller:linesKeyDown(10, 1)
  eq(seq.rate, 2, 'x1')
  controller:linesKeyDown(15, 1)
  eq(seq.rate, 7, '/8')
  eq(params:get('seq1rate'), 7, 'rate parameter')
end

tests['directions advance predictably'] = function()
  local animator = setup()
  local seq = animator.sequencers[1]
  seq.index = 1; seq.direction = 1; seq:advance(); eq(seq.index, 2, 'forward')
  seq.direction = 2; seq:advance(); eq(seq.index, 1, 'reverse')
  seq.direction = 3; seq.directionStep = 1
  seq.index = 3; seq:advance(); eq(seq.index, 2, 'pendulum turn')
  seq:advance(); eq(seq.index, 1, 'pendulum down')
  seq:advance(); eq(seq.index, 2, 'pendulum return')
end

tests['intersections keep harmonic and rhythm actions separate'] = function()
  local animator, controller = setup()
  local seq = animator.sequencers[1]
  controller:intersectionsKeyDown(3, 1)
  controller:intersectionsKeyDown(9, 1)
  eq(seq.harmonic, 4, 'fifth')
  eq(seq.rhythm, 4, 'reverse')
  eq(params:get('seq1harmonic'), 4, 'harmonic parameter')
  eq(params:get('seq1rhythm'), 4, 'rhythm parameter')
end

tests['intersection actions toggle off with no none pads'] = function()
  local animator, controller = setup()
  controller:intersectionsKeyDown(1,1)
  eq(animator.sequencers[1].harmonic, 2, 'column one is octave up')
  controller:intersectionsKeyDown(1,1)
  eq(animator.sequencers[1].harmonic, 1, 'octave off')
  controller:intersectionsKeyDown(7,1)
  eq(animator.sequencers[1].rhythm, 2, 'rhythm mute')
  controller:intersectionsKeyDown(7,1)
  eq(animator.sequencers[1].rhythm, 1, 'mute off')
  controller:redrawIntersections()
  eq(leds[101], 2, 'available harmonic pad stays dim')
  eq(leds[107], 2, 'available rhythm pad stays dim')
end

tests['triad and seventh pads are exclusive toggleable with one separator'] = function()
  local a,controller = setup()
  controller:intersectionsKeyDown(4,1)
  eq(a.sequencers[1].harmonic,5,'triad')
  controller:intersectionsKeyDown(5,1)
  eq(a.sequencers[1].harmonic,6,'seventh')
  controller:redrawIntersections()
  eq(leds[104],2,'triad available and dim')
  eq(leds[105],15,'seventh lit')
  eq(leds[106],nil,'single blank separator')
  controller:intersectionsKeyDown(6,1)
  eq(a.sequencers[1].harmonic,6,'separator does nothing')
  controller:intersectionsKeyDown(5,1)
  eq(a.sequencers[1].harmonic,1,'seventh off')
end

tests['navigation emits one final frame per redraw with a stable bottom row'] = function()
  local a,controller=setup()
  a.snapshots[1]={};a.snapshots[8]={};controller.snapshot=1
  a.stepLevels={[1]=15,[2]=5}
  local key=controller:createKeyHandler()
  a.redraw=function() controller:redraw() end
  key(16,8,1)
  for page=1,3 do
    key(12+page,8,1);key(12+page,8,0)
    for tick=1,12 do
      a.stepLevels[1]=(tick%2==0) and 15 or 2
      frames={}
      controller:redraw()
      eq(#frames,1,'one transmitted frame, page '..page)
      for x=1,12 do eq(frames[1][800+x] or 0,0,'hidden bottom row pad '..x) end
      for selector=1,3 do
        eq(frames[1][812+selector],page==selector and 15 or 9,'stable selector '..selector)
      end
      eq(frames[1][816],15,'held navigation pad')
    end
  end
  controller.view=1
  frames={}
  key(16,8,0)
  eq(#frames,1,'release sends one frame')
  eq(frames[1][801],15,'current snapshot restored')
  eq(frames[1][808],5,'occupied snapshot restored')
end

tests['page three holds a track preview without changing intersections'] = function()
  local a,controller=setup()
  local key=controller:createKeyHandler()
  controller.view=3
  local seq=a.sequencers[1]
  key(15,1,1)
  eq(controller.selected,1,'preview selects track')
  eq(controller.view,3,'grid stays on intersections')
  assert(controller.previewKey,'preview active while held')
  eq(seq.harmonic,1,'preview does not change harmony')
  eq(seq.rhythm,1,'preview does not change rhythm')
  key(4,1,1);key(4,1,0)
  eq(seq.harmonic,5,'harmonic controls remain usable during preview')
  assert(controller.previewKey,'other pad release keeps preview active')
  key(15,1,0)
  eq(controller.previewKey,nil,'release restores parameter screen')
  key(15,8,1)
  eq(controller.previewKey,nil,'empty track does not open preview')
end

tests['track eight preview and page selection never edit snapshots'] = function()
  local a,controller=setup()
  for i=2,8 do a.addNewSequence({{x=4,y=1},{x=5,y=1}}) end
  local key=controller:createKeyHandler()
  controller.view=3
  key(15,8,1)
  eq(controller.selected,8,'track eight available')
  assert(controller.previewKey,'track eight preview')
  key(16,8,1)
  eq(controller.previewKey,nil,'navigation cancels preview')
  key(13,8,1);key(13,8,0);key(16,8,0)
  key(15,8,0)
  eq(controller.view,1,'direct navigation to Canvas')
  eq(controller.held,nil,'old preview release does not press Canvas ALT')
  eq(controller.previewKey,nil,'screen not stuck after release order change')
  assert(not next(a.snapshots),'preview never records snapshots')
  key(16,8,1);key(15,8,1);key(16,8,0);key(15,8,0)
  eq(controller.view,3,'page three selector')
  eq(controller.previewKey,nil,'navigation selector does not start track eight preview')
end

tests['releasing an older preview key leaves the latest preview held'] = function()
  local a,controller=setup()
  a.addNewSequence({{x=4,y=2},{x=5,y=2}})
  local key=controller:createKeyHandler()
  controller.view=3
  key(15,1,1);key(15,2,1);key(15,1,0)
  eq(controller.selected,2,'latest preview selects second track')
  assert(controller.previewKey,'older release cannot close latest preview')
  key(15,2,0)
  eq(controller.previewKey,nil,'latest release closes preview')
end

tests['nested parameter batches suppress frames and unlock after an error'] = function()
  local a,controller=setup()
  frames={}
  local ok,err=pcall(function()
    a.withUpdate(function()
      assert(a.updating)
      controller:redraw()
      a.withUpdate(function() controller:redraw() end)
      assert(a.updating,'inner batch cannot release outer suppression')
      error('simulated parameter action failure')
    end)
  end)
  assert(not ok and err:find('simulated parameter action failure',1,true))
  assert(not a.updating,'failed action must not leave rendering disabled')
  eq(#frames,0,'no intermediate frames')
  controller:redraw()
  eq(#frames,1,'rendering works after the failure')
end

tests['a retired Grid controller cannot overwrite the next script'] = function()
  local a,controller=setup()
  local key=controller:createKeyHandler()
  norns.state.shortname='another-script'
  frames={}
  controller:redraw();key(16,8,1)
  eq(#frames,0,'no stale device writes')
  eq(controller.navHeld,false,'no stale gestures')
  norns.state.shortname='anima'
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
