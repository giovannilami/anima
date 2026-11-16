local constants = include('anima/lib/constants')
local helpers = include('anima/lib/helpers')
local PatternManager = include('anima/lib/PatternManager')
local GRID_LENGTH = constants.GRID_LENGTH
local GRID_HEIGHT = constants.GRID_HEIGHT
local CANVAS_HEIGHT = constants.CANVAS_HEIGHT
local NAV_ROW = constants.GRID_NAV_ROW
local GRID_LEVELS = constants.GRID_LEVELS
local SNAPSHOT_NUM = 8
local g = grid.connect()
local CLEAR_POSITION = 15
local TOGGLE_VIEW_POSITION = constants.CANVAS_LENGTH
local RATE_START = 9
local MUTE_POSITION = 1
local DIRECTION_START = 2
local RATCHET_POSITION = 6
local PROBABILITY_POSITION = 7
local PREVIEW_POSITION = 15
local LFO_POSITION = 14
local EVENT_PATTERN = constants.EVENT_PATTERN
local EVENT_SNAPSHOT = constants.EVENT_SNAPSHOT

local GRID = {}
GRID.__index = GRID

function GRID.new(animator)
  local g = {
    ownerParams=params,
    ownerScript=norns and norns.state and norns.state.shortname,
    snapshot = 0,
    held = nil,
    animator = animator,
    view = 1,
    selected = 1,
    navHeld = false,
    consumed = {},
    muteHolds = {},
    gestureHolds = {},
    editGesture=0,
    blinkOn=true,
    previewKey = nil,
    patternManager = PatternManager.new{
      callbacks = {
        [EVENT_PATTERN] = animator.redraw,
        [EVENT_SNAPSHOT] = animator.handleSelectSnapshot
      }
    }
  }
  setmetatable(g, GRID)
  setmetatable(g, {__index = GRID})

  g.viewKeyHandlers = {g.mainKeyHandler, g.linesKeyHandler, g.intersectionsKeyHandler}
  g.viewRedraws = {g.redrawMain, g.redrawLines, g.redrawIntersections}

  return g
end

function GRID:isActive()
  return not self.animator.closing and params==self.ownerParams
    and (not self.ownerScript or norns.state.shortname==self.ownerScript)
end


-- One visual timer for blink feedback and live screen readings, independent
-- of transport/BPM. Screen-only refreshes never publish a Grid frame.
function GRID:startFeedback(screenRedraw)
  self.screenRedraw=screenRedraw
  if self.feedbackTimer then return end
  local owner=params
  local script=norns and norns.state and norns.state.shortname
  local nextScreenAt=0
  self.feedbackTimer=metro.init(function()
    if self.animator.closing or params~=owner
        or (script and norns.state.shortname~=script) then self:stopFeedback();return end
    if self.animator.updating then return end
    local now=util.time()
    local phase=math.floor(now*4)%2==0 -- 2 full flashes per second.
    local blinkChanged=phase~=self.blinkOn
    self.blinkOn=phase
    if self.navHeld or self.view==constants.PAGE_CANVAS then return end
    local mod=self.animator.modulation
    if not mod then return end
    if blinkChanged then
      for row,seq in ipairs(self.animator.sequencers) do
        if seq.modEnabled and mod:frozen(row) then self:redraw();break end
      end
    end
    if self.previewKey or not self.screenRedraw or now+0.000001<nextScreenAt then return end
    nextScreenAt=now+0.1
    local seq=self.animator.sequencers[self.selected]
    if seq and seq.modEnabled then
      local held,mapped=mod:holdCounts(seq,self.selected)
      if mapped>held then self.screenRedraw() end
    end
  end,0.05,-1)
  self.feedbackTimer:start()
end
function GRID:stopFeedback()
  if not self.feedbackTimer then return end
  self.feedbackTimer:stop()
  metro.free(self.feedbackTimer.id)
  self.feedbackTimer=nil
end
function GRID:freezeLevel(enabled,frozen)
  if frozen then return self.blinkOn and GRID_LEVELS.HIGH or 0 end
  return enabled and GRID_LEVELS.HIGH or GRID_LEVELS.DIM
end

function GRID:redraw()
  if not self:isActive() or self.animator.updating then return end
  self.viewRedraws[self.view](self)
  if self.navHeld then
    for x=1,15 do g:led(x, NAV_ROW, 0) end
    for page=1,3 do g:led(12+page, NAV_ROW, self.view == page and GRID_LEVELS.HIGH or GRID_LEVELS.MED) end
    g:led(16, NAV_ROW, GRID_LEVELS.HIGH)
  end
  -- Publish the completed page and navigation overlay in one frame.
  g:refresh()
end

function GRID:redrawMain()
  g:all(0)
  drawSteps(self.animator.stepLevels)
  if not self.navHeld then self:redrawBottomRow() end
end

function GRID:redrawLines()
  g:all(0)
  for row=1,GRID_HEIGHT do
    local seq = self.animator.sequencers[row]
    if seq then
      g:led(MUTE_POSITION, row, seq.solo and GRID_LEVELS.MED or (seq.muted and GRID_LEVELS.HIGH or GRID_LEVELS.DIM))
      for direction=1,#constants.DIRECTIONS do
        g:led(DIRECTION_START + direction - 1, row,
          seq.direction == direction and GRID_LEVELS.HIGH or GRID_LEVELS.DIM)
      end
      local mod=self.animator.modulation
      g:led(RATCHET_POSITION,row,self:freezeLevel(seq.ratchetEnabled,
        mod and seq.modEnabled and mod:frozen(row,'ratchet')))
      g:led(PROBABILITY_POSITION,row,self:freezeLevel(seq.probabilityEnabled,
        mod and seq.modEnabled and mod:frozen(row,'probability')))
      for rate=1,constants.GRID_RATE_COUNT do
        g:led(RATE_START + rate - 1, row,
          seq.rate == rate and GRID_LEVELS.HIGH or GRID_LEVELS.DIM)
      end
    end
  end
  drawToggleViewPad()
end

function GRID:redrawIntersections()
  g:all(0)
  self:drawOptions(self.selected)
  drawToggleViewPad()
end

function drawToggleViewPad()
  g:led(TOGGLE_VIEW_POSITION, NAV_ROW, GRID_LEVELS.DIM)
end

function GRID:createKeyHandler()
  return function(x, y, z)
    if not self:isActive() or self.animator.updating then return end
    local key = y*16+x
    -- Handle the release before page dispatch: navigation may have changed
    -- pages since the preview began, and must never leave the screen held.
    if z == 0 and self.previewKey == key then
      self.previewKey = nil
      self.animator.redraw()
      return
    end
    if x == 16 and y == NAV_ROW then
      self.navHeld = z == 1
      if z == 1 then
        self:cancelGestureHolds()
        if self.previewKey then self.consumed[self.previewKey] = true end
        self.previewKey = nil
        for row,hold in pairs(self.muteHolds) do
          if hold.task then clock.cancel(hold.task) end
          self.consumed[row*16+1] = true
        end
        self.muteHolds = {}
      end
      self.held = nil
      self.animator.redraw()
      return
    end
    if z == 0 and self.consumed[key] then self.consumed[key] = nil; return end
    if self.navHeld then
      if z == 1 then
        self.consumed[key] = true
        if y == NAV_ROW and x >= 13 and x <= 15 then self.view = x - 12 end
        self.animator.redraw()
      end
      return
    end
    self.viewKeyHandlers[self.view](self, x, y, z)
  end
end

function GRID:mainKeyHandler(x, y, z)
  if z == 1 then
    self:mainKeyDown(x, y)
  else
    -- Keep ALT held across repeated redo/snapshot taps until ALT itself is
    -- released. Redraw also updates undo/redo availability while stopped.
    if self.held and self.held.y==NAV_ROW and self.held.x==CLEAR_POSITION
        and (x~=CLEAR_POSITION or y~=NAV_ROW) then return end
    self.held = nil
    self.animator.redraw()
  end
end

function GRID:linesKeyHandler(x, y, z)
  if (x==RATCHET_POSITION or x==PROBABILITY_POSITION) and self.animator.sequencers[y] then
    local target=x==RATCHET_POSITION and 'ratchet' or 'probability'
    self:gesture(x,y,z,function() self:linesKeyDown(x,y) end,target)
    return
  end
  if x == MUTE_POSITION and self.animator.sequencers[y] then
    if z == 1 then
      local hold = {solo=false}
      self.muteHolds[y] = hold
      self.selected = y
      hold.task = clock.run(function()
        clock.sleep(0.45)
        hold.solo = true
        local id = 'seq' .. y .. 'solo'
        params:set(id, params:get(id) == 2 and 1 or 2)
        self.animator.redraw()
      end)
    else
      local hold = self.muteHolds[y]
      if hold then
        if hold.task then clock.cancel(hold.task) end
        if not hold.solo then self:linesKeyDown(x, y) end
        self.muteHolds[y] = nil
      end
    end
  elseif z == 1 then
    self:linesKeyDown(x, y)
  end
end

function GRID:intersectionsKeyHandler(x, y, z)
  if x==LFO_POSITION and self.animator.sequencers[y] then
    self:gesture(x,y,z,function()
      local seq=self.animator.sequencers[y]
      params:set('seq'..y..'modEnabled',seq.modEnabled and 1 or 2)
    end)
    return
  end
  if x == PREVIEW_POSITION then
    if z == 1 and self.animator.sequencers[y] then
      if self.previewKey then self.consumed[self.previewKey] = true end
      self.previewKey = y*16+x
      self.selected = y
      self.animator.redraw()
    end
    return
  end
  if z == 1 then
    self:intersectionsKeyDown(x, y)
  end
end

function GRID:mainKeyDown(x, y)
  if y <= CANVAS_HEIGHT then
    if self.animator.history then
      if not self.held then self.editGesture=self.editGesture+1 end
      self.animator.history:perform('grid-'..self.editGesture,function() self:handleSequence(x,y) end,math.huge)
    else self:handleSequence(x,y) end
  elseif y == NAV_ROW then
    self:handleBottomRowSelect(x, y)
  end
end

function GRID:linesKeyDown(x, y)

  local seq = self.animator.sequencers[y]
  if not seq then return end

  if x == MUTE_POSITION then
    params:set('seq' .. y .. 'muted', seq.muted and 1 or 2)
  elseif x >= DIRECTION_START and x < DIRECTION_START + #constants.DIRECTIONS then
    params:set('seq' .. y .. 'direction', x - DIRECTION_START + 1)
  elseif x == RATCHET_POSITION then
    params:set('seq' .. y .. 'ratchetEnabled', seq.ratchetEnabled and 1 or 2)
  elseif x == PROBABILITY_POSITION then
    params:set('seq' .. y .. 'probabilityEnabled', seq.probabilityEnabled and 1 or 2)
  elseif x >= RATE_START and x < RATE_START + constants.GRID_RATE_COUNT then
    params:set('seq' .. y .. 'rate', x - RATE_START + 1)
  end

  self.selected = y
  self.animator.redraw()
end

function GRID:intersectionsKeyDown(x, y)

  if not self.animator.sequencers[y] then return end

  if x >= 1 and x <= #constants.HARMONIC_ACTIONS - 1 then
    local id, action = 'seq' .. y .. 'harmonic', x+1
    params:set(id, params:get(id) == action and 1 or action)
  elseif x >= 7 and x <= 5 + #constants.RHYTHM_ACTIONS then
    local id, action = 'seq' .. y .. 'rhythm', x-5
    params:set(id, params:get(id) == action and 1 or action)
  end

  self.selected = y
  self.animator.redraw()
end

function GRID:event(e)
  self.patternManager:event(e)
end

function GRID:handleBottomRowSelect(x, y)
  local isClearHeld = self.held and self.held.y == NAV_ROW and self.held.x == CLEAR_POSITION

  if x >= 1 and x <= SNAPSHOT_NUM then
    self:event{i=x, isClearHeld=isClearHeld, type=EVENT_SNAPSHOT}
  elseif x >= 10 and x <= 11 then
    self:event{i=x-9, isClearHeld=isClearHeld, type=EVENT_PATTERN}
  elseif x==13 then
    if self.animator.history then self.animator.history:travel(isClearHeld);self.animator.redraw() end
  elseif x == CLEAR_POSITION then
    self:setHeld(x, y)
    self.animator.redraw()
  end
end


function GRID:handleSequence(x, y)
  local held = self.held
  local findPos = helpers.findPosition
  local posHeld
  if held ~= nil then posHeld = findPos(held.x, held.y) end
  local pos = findPos(x, y)
  local enabled = self.animator.enabled

  if posHeld ~= nil then
    if enabled[posHeld] > 0 and enabled[pos] > 0 then
      local overlapIndex = self:findOverlapIndex(pos, posHeld)
      if overlapIndex then
        return self:handleOverlap(pos, posHeld, overlapIndex)
      end
    end

    self:createNewSequence(x, y)
  else
    self:toggleStepOn(x, y)
    self:setHeld(x, y)
  end
  self.animator.redraw()
end

function GRID:createNewSequence(x, y)
  local animator = self.animator
  local steps = getNewLineSteps(self.held, {x = x, y = y})
  if steps ~= nil then animator.addNewSequence(steps) end
end

function GRID:toggleStepOn(x, y)
  local animator = self.animator
  local pos = helpers.findPosition(x, y)
  if animator.on[pos] > 0 then
    animator.on[pos] = 0
  elseif animator.enabled[pos] > 0 then
    animator.on[pos] = animator.enabled[pos]
  end
end

function GRID:setHeld(x, y)
  self.held = {x = x, y = y}
end

function GRID:findOverlapIndex(posA, posB)
  for i=1,#self.animator.sequencers do
    local stepMap = self.animator.sequencers[i].stepMap
    if stepMap[posA] and stepMap[posB] then return i end
  end
end

function GRID:handleOverlap(pos, posHeld, index)
  local seq = self.animator.sequencers[index]
  local steps = seq.steps
  local first = helpers.findPosition(steps[1].x, steps[1].y)
  local last = helpers.findPosition(steps[seq.length].x, steps[seq.length].y)

  if (pos == first and posHeld == last) or (posHeld == first and pos == last) then
    self.animator.clearSeq(index)
  end
end

function GRID:drawOptions(selected)
  local function drawOption(x, y, isOn)
    g:led(x, y, isOn and GRID_LEVELS.HIGH or GRID_LEVELS.DIM)
  end

  local seqs = self.animator.sequencers

  for y=1,GRID_HEIGHT do
    local seq = seqs[y]
    if seq then
      for x=1,#constants.HARMONIC_ACTIONS-1 do drawOption(x, y, seq.harmonic == x+1) end
      for x=7,5+#constants.RHYTHM_ACTIONS do drawOption(x, y, seq.rhythm == x-5) end
      local mod=self.animator.modulation
      local level=self:freezeLevel(seq.modEnabled,mod and seq.modEnabled and mod:frozen(y))
      g:led(LFO_POSITION,y,level)
      g:led(PREVIEW_POSITION, y, selected == y and GRID_LEVELS.HIGH or GRID_LEVELS.DIM)
    end
  end
end

function GRID:redrawBottomRow()
  drawSnapshots(self)
  drawPatterns(self.patternManager.patterns)
  local history=self.animator.history
  local redo=self.held and self.held.y==NAV_ROW and self.held.x==CLEAR_POSITION
  local available=history and #(redo and history.redoStack or history.undoStack)>0
  g:led(13,NAV_ROW,available and GRID_LEVELS.MED or 0)
  g:led(CLEAR_POSITION, NAV_ROW, GRID_LEVELS.DIM)
  drawToggleViewPad()
end

function drawSnapshots(self)
  for i=1,SNAPSHOT_NUM do
    if self.snapshot == i then
      g:led(i, NAV_ROW, GRID_LEVELS.HIGH)
    elseif self.animator.snapshots[i] ~= nil then
      g:led(i, NAV_ROW, GRID_LEVELS.LOW_MED)
    else
      g:led(i, NAV_ROW, GRID_LEVELS.DIM)
    end
  end
end

function drawSteps(levels)
  local findXY = helpers.findXY
  for pos,level in pairs(levels) do
    local step = findXY(pos)
    g:led(step.x, step.y, level)
  end
end

function drawPatterns(patterns)
  local patternNum = #patterns
  for i=1,patternNum do
    local x = i+9
    if patterns[i].rec == 1 then g:led(x, NAV_ROW, GRID_LEVELS.HIGH)
    elseif patterns[i].play == 1 then g:led(x, NAV_ROW, GRID_LEVELS.MED)
    elseif patterns[i].count > 0 then g:led(x, NAV_ROW, GRID_LEVELS.LOW_MED)
    else g:led(x, NAV_ROW, GRID_LEVELS.DIM) end
  end
end

function getNewLineSteps(a, b)
  if a.x == b.x and a.y == b.y then return end
  if a.y == b.y then
    return getStepsHorizontal(a, b)
  elseif a.x == b.x then
    return getStepsVertical(a, b)
  elseif math.abs(a.x - b.x) == math.abs(a.y - b.y) then
    return getStepsDiagonal(a, b)
  end
end

function getStepsHorizontal(a, b)
  local steps = {}
  if a.x < b.x then
    for i = a.x, b.x do
      steps[#steps+1] = {x = i, y = a.y}
    end
    return steps
  else
    for i = a.x, b.x, -1 do
      steps[#steps+1] = {x = i, y = a.y}
    end
    return steps
  end
end

function getStepsVertical(a, b)
  local steps = {}
  if a.y < b.y then
    for i = a.y, b.y do
      steps[#steps+1] = {x = a.x, y = i}
    end
  else
    for i = a.y, b.y, -1 do
      steps[#steps+1] = {x = a.x, y = i}
    end
  end
  return steps
end

function getStepsDiagonal(a, b)
  local steps = {}
  local y = a.y

  local function addStep(x)
    steps[#steps+1] = {x = x, y = y}
    if a.y > b.y then
      y = y - 1
    else
      y = y + 1
    end
  end

  if a.x < b.x then
    for i = a.x,b.x do addStep(i) end
  else
    for i = a.x,b.x,-1 do addStep(i) end
  end

  return steps
end

-- Tap and long press are exclusive. Navigation cancels all pending taps.
function GRID:cancelGestureHolds()
  for row,hold in pairs(self.muteHolds) do
    if hold.task then clock.cancel(hold.task) end
    self.consumed[row*16+1]=true
  end
  self.muteHolds={}
  for key,hold in pairs(self.gestureHolds) do
    if hold.task then clock.cancel(hold.task) end
    self.consumed[key]=true
  end
  self.gestureHolds={}
end
function GRID:gesture(x,y,z,tap,target)
  local key=y*16+x
  if z==1 then
    local hold={long=false};self.gestureHolds[key]=hold;self.selected=y
    hold.task=clock.run(function()
      clock.sleep(0.45)
      hold.long=true
      local seq=self.animator.sequencers[y]
      if seq and self.animator.modulation then self.animator.modulation:freeze(seq,y,target) end
      self.animator.redraw()
    end)
    self.animator.redraw()
  else
    local hold=self.gestureHolds[key]
    if hold then
      if hold.task then clock.cancel(hold.task) end
      self.gestureHolds[key]=nil
      if not hold.long then tap() end
      self.animator.redraw()
    end
  end
end

return GRID
