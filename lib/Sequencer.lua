local helpers = include('anima/lib/helpers')
local constants = include('anima/lib/constants')
local Settings = include('anima/lib/track_settings')
local Sequencer = {}
local editSerial=0
Sequencer.__index = Sequencer

function createStepMap(steps)
  local map = {}
  local findPos = helpers.findPosition
  for _,v in ipairs(steps) do
    map[findPos(v.x, v.y)] = true
  end
  return map
end

function Sequencer.new(options, position)
  local legacyDivToRate = {2, 3, 4, 5, 8, 6, 9, 7}
  local legacyRhythm = {[3]=2, [4]=5, [5]=6, [6]=7}
  local legacyIntersect = options.intersect or params:get('seq' .. position .. 'intersect')
  editSerial=math.max(editSerial+1,options.editId or 0)
  local seq = {
    editId=options.editId or editSerial,
    steps = options.steps,
    stepMap = createStepMap(options.steps),
    index = options.index or 1, -- current step index
    length = #options.steps,
    intersect = legacyIntersect,
    harmonic = options.harmonic or (legacyIntersect == 2 and 2 or params:get('seq' .. position .. 'harmonic')),
    rhythm = options.rhythm or legacyRhythm[legacyIntersect] or params:get('seq' .. position .. 'rhythm'),
    rate = options.rate or (options.div and legacyDivToRate[options.div]) or params:get('seq' .. position .. 'rate'),
    rateCount = options.rateCount or options.divCount or 1,
    directionStep = options.directionStep or 1,
    reset = options.reset or false,
  }

  for _,field in ipairs(Settings.fields) do
    if options[field.key] ~= nil then
      seq[field.key] = options[field.key]
    elseif seq[field.key] == nil then
      local value = params:get(Settings.id(position, field.key))
      if field.boolean then value = value == 2 end
      seq[field.key] = value
    end
  end
  setmetatable(seq, Sequencer)
  setmetatable(seq, {__index = Sequencer})

  return seq
end

function Sequencer:advance()
  if self.length <= 1 then self.index = 1; return end
  if self.direction == constants.DIRECTION_REVERSE then
    self.index = (self.index - 2) % self.length + 1
  elseif self.direction == constants.DIRECTION_PENDULUM then
    local nextIndex = self.index + self.directionStep
    if nextIndex > self.length or nextIndex < 1 then
      self.directionStep = self.directionStep * -1
      nextIndex = self.index + self.directionStep
    end
    self.index = nextIndex
  elseif self.direction == constants.DIRECTION_RANDOM then
    self.index = math.random(self.length)
  else
    self.index = self.index % self.length + 1
  end
end

function Sequencer:regenStepMap()
  self.stepMap = createStepMap(self.steps)
end

return Sequencer
