local helpers = include('anima/lib/helpers')
local C = include('anima/lib/constants')
local Settings = include('anima/lib/track_settings')
local ui = {}
local function text(x,y,value,level)
  screen.level(level or 15); screen.move(x,y); screen.text(value)
end
local function drawSteps(levels)
  for pos,val in pairs(levels) do
    local step = helpers.findXY(pos)
    screen.level(val)
    screen.rect(step.x*5+22, step.y*5+6,3,3)
    screen.fill()
  end
end
-- Visual readings follow the current wave; note events keep their own step
-- sampling. A held destination takes precedence in the modulation preview.
local function readout(seq,track,mod)
  local actual=mod and mod:preview(seq,track) or seq
  local function value(key) return actual[key] end
  local function source(key)
    if mod and seq.modEnabled then
      if mod:frozen(track,key) then return 'HOLD' end
      if mod:mapped(seq,key) then return 'LFO' end
    end
    return 'BASE'
  end
  return value,source
end
local function outputName(seq,track)
  local name=Settings.routeNames[seq.output]
  if seq.output==3 or seq.output==9 then
    local id=Settings.id(track,'nb')
    if params.lookup[id] then
      local voice=params:string(id)
      if voice and voice~='' and voice~='none' and voice~='unavailable' then name=name..': '..voice end
    end
  end
  return name
end
local extraTargets={{'octave','O'},{'transpose','T'},{'duration','L'},{'velocity','V'}}
local function extraValues(seq,track,mod,value)
  local parts={}
  if not mod then return '' end
  for _,pair in ipairs(extraTargets) do
    local key,label=pair[1],pair[2]
    if mod:mapped(seq,key) then
      local number=value(key)
      if key=='octave' or key=='transpose' then number=string.format('%+d',number) end
      parts[#parts+1]=label..number..(mod:frozen(track,key) and '*' or '')
    end
  end
  return table.concat(parts,' ')
end
local function fittedText(x,y,value,level)
  -- Long third-party voice names must not run off the 128-pixel display.
  if screen.text_extents then
    local width=screen.text_extents(value)
    if width and width>124-x then
      local short=value
      repeat short=short:sub(1,-2);width=screen.text_extents(short..'...') until width<=124-x or #short==0
      value=short..'...'
    end
  end
  text(x,y,value,level)
end
function ui.redraw(levels, grid, showIntroText)
  screen.clear()
  screen.font_size(8)
  if grid.navHeld then
    text(4,12,'SELECT PAGE')
    text(4,28,'13 canvas   14 lines')
    text(4,40,'15 intersections')
    text(4,58,'hold corner + press page',5)
  elseif grid.previewKey then
    text(4,7,'TRACK ' .. grid.selected,5)
    drawSteps(levels)
    text(4,60,'release 15: parameters',5)
  elseif grid.view == C.PAGE_CANVAS then
    if showIntroText then
      text(4,22,'Hold 2 pads to draw')
      text(4,35,'a straight line: -- | /')
    else
      drawSteps(levels)
    end
    text(4,7,'anima / CANVAS',5)
    local status = grid.animator.saveStatus
    text(4,60,status and status.text or 'K2 reset   K3 clear',status and 15 or 5)
  else
    local seq = grid.animator.sequencers[grid.selected]
    local original=grid.animator.originalPlayback and grid.animator.originalPlayback.enabled
    text(4,9,(grid.view == 2 and 'LINES  ' or 'INTERSECTIONS  ') .. grid.selected .. (original and ' ORIG' or ''))
    if not seq then
      text(4,30,'empty track',5)
    elseif grid.view == C.PAGE_LINES then
      local mod=grid.animator.modulation
      local value,source=readout(seq,grid.selected,mod)
      local movement=C.DIRECTIONS[seq.direction]..' '..C.RATE_LABELS[value('rate')]
      if seq.muted then movement=movement..' MUTE' end
      if seq.solo then movement=movement..' SOLO' end
      text(4,21,movement)
      fittedText(4,32,outputName(seq,grid.selected))
      text(4,43,'prob ' .. value('probability') .. '% ' .. source('probability') .. (seq.probabilityEnabled and '' or ' off'))
      local gate=seq.ratchetEnabled and '' or (seq.rhythm==3 and ' INT' or ' off')
      text(4,54,'ratchet ' .. value('ratchet') .. ' ' .. source('ratchet') .. gate)
      text(4,63,extraValues(seq,grid.selected,mod,value),5)
    else
      local harmony = C.HARMONIC_ACTIONS[seq.harmonic]
      if seq.harmonic == 5 then
        harmony = 'triad: ' .. C.TRIAD_TYPES[seq.triadType or 1]
      elseif seq.harmonic == 6 then
        harmony = 'seventh: ' .. C.SEVENTH_TYPES[seq.seventhType or 1]
      end
      text(4,24,harmony)
      text(4,37,C.RHYTHM_ACTIONS[seq.rhythm])
      local mod=grid.animator.modulation
      local held,mapped=0,0
      if mod then held,mapped=mod:holdCounts(seq,grid.selected) end
      local status=not seq.modEnabled and 'off' or (mapped==0 and 'ON no targets' or
        (held>0 and ('HOLD '..held..'/'..mapped) or 'ON'))
      text(4,49,'LFO '..status)
      local value=readout(seq,grid.selected,mod)
      local chance=seq.probabilityEnabled and ('P'..value('probability')..'%') or 'Poff'
      local ratchet=seq.ratchetEnabled and ('R'..value('ratchet')) or
        (seq.rhythm==3 and ('R'..value('ratchet')..' int') or 'Roff')
      text(4,63,C.RATE_LABELS[value('rate')]..'  '..chance..'  '..ratchet,5)

    end
  end
  screen.update()
end
return ui
