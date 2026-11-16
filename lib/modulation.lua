-- Two oscillators per line, sampled without allocating clocks or metros.
-- Modulation never writes the musical base parameters.
local M = {}; M.__index=M
M.targets={'none','probability','velocity','duration','rate','octave','transpose','ratchet'}
M.names={'none','probability %','velocity','note length ms','rate','octave','transpose semitones','ratchet repeats'}
M.shapes={'sine','triangle','ramp up','ramp down','square','sample & hold'}
M.beats={1/16,1/8,1/4,1/2,1,2,3,4,6,8,12,16,24,32,64}
M.beatNames={'1/16','1/8','1/4','1/2','1','2','3','4','6','8','12','16','24','32','64'}
M.ranges={{0,100,0,100},{0,100,0,100},{1,127,40,120},{5,4000,30,400},{1,7,2,7},{-4,4,-1,1},{-48,48,-12,12},{0,4,0,4}}
function M.fields()
  local out={{key='modEnabled',name='LFO master',boolean=true,default=false,mod=true}}
  local function add(f) f.mod=true;out[#out+1]=f end
  for l=1,2 do
    local p='lfo'..l; local name='LFO '..l..' '
    add{key=p..'Enabled',name=name..'enabled',boolean=true,default=l==1}
    add{key=p..'Shape',name=name..'shape',options=M.shapes,default=1}
    add{key=p..'Mode',name=name..'time',options={'clock beats','free seconds'},default=1}
    add{key=p..'Cycle',name=name..'cycle beats',options=M.beatNames,default=10}
    add{key=p..'Seconds',name=name..'cycle seconds',spec={0.1,120,'exp',0.1,8},default=8}
    for d=1,2 do
      local route=p..'Dest'..d
      add{key=route,name=name..'target '..d,options=M.names,default=1,target=true}
      for _,edge in ipairs({'Min','Max'}) do
        add{key=route..edge,name=name..d..' '..edge:lower(),min=0,max=100,default=edge=='Min' and 0 or 100,
          formatter=function(param)
            local target=params:get(param.id:gsub(edge..'$',''))
            if target==5 then return ({'x2','x1','/2','/3','/4','/6','/8'})[math.floor(param:get())] end
            return tostring(param:get())
          end}
      end
    end
  end
  return out
end
-- Reconfigure numeric ranges without invoking unrelated param actions.
function M.configure(track,key,target,reset)
  local r=M.ranges[target] or M.ranges[1]
  for n,edge in ipairs({'Min','Max'}) do
    local id='seq'..track..key..edge
    if params.lookup[id] then
      local p=params:lookup_param(id)
      p.min,p.max,p.range=r[1],r[2],r[2]-r[1]+1
      params:set(id,reset and r[n+2] or p:get(),true)
    end
  end
end
function M.new(devices)
  -- An independent seed keeps visual sampling away from the musical RNG.
  local seed=devices.seed or (devices.random and math.floor(devices.random()*2147483647))
    or math.floor(devices.time()*1000)%2147483647
  return setmetatable({d=devices,seed=seed,state={},last={},applied={}},M)
end
function M:newState(track)
  return {held={},slots={{seed=(self.seed+track*1009+9176)%2147483647},
    {seed=(self.seed+track*1009+18352)%2147483647}}}
end
function M:reset(track)
  if track then self.state[track]=nil;self.last[track]=nil;self.applied[track]=nil else self.state={};self.last={};self.applied={} end
end
function M:wave(shape,phase,cycle,slot)
  if shape==1 then return (math.sin(phase*2*math.pi)+1)/2 end
  if shape==2 then return 1-math.abs(phase*2-1) end
  if shape==3 then return phase end
  if shape==4 then return 1-phase end
  if shape==5 then return phase<0.5 and 0 or 1 end
  -- The value belongs to the cycle, not to how often a screen gets drawn.
  if slot.cycle~=cycle then
    local n=(slot.seed+cycle*48271)%2147483647
    n=(n~(n<<13))&0x7fffffff
    n=(n~(n>>17))&0x7fffffff
    n=(n~(n<<5))&0x7fffffff
    slot.cycle=cycle;slot.random=n/2147483647
  end
  return slot.random
end
function M:evaluate(seq,track,preview)
  local result={};for key,value in pairs(seq) do result[key]=value end
  result.octave=0
  if not seq.modEnabled then
    if not preview then self.last[track]=result end
    return result
  end
  local state=self.state[track] or self:newState(track)
  if preview then
    local slots={}
    for l=1,2 do
      slots[l]={};for key,value in pairs(state.slots[l]) do slots[l][key]=value end
    end
    state={slots=slots,held=state.held}
  else
    self.state[track]=state;self:prune(seq,track)
  end
  -- Oscillators keep advancing behind value holds, including sample & hold.
  for l=1,2 do
    local p='lfo'..l
    if seq[p..'Enabled'] then
      local position
      if seq[p..'Mode']==2 then position=self.d.time()/math.max(0.1,seq[p..'Seconds'] or 8)
      else position=self.d.beats()/(M.beats[seq[p..'Cycle'] or 10]) end
      local cycle=math.floor(position)
      local wave=self:wave(seq[p..'Shape'] or 1,position-cycle,cycle,state.slots[l])
      for d=1,2 do
        local route=p..'Dest'..d
        local target=seq[route] or 1
        if target>1 then
          local r=M.ranges[target];local low=seq[route..'Min'] or r[3];local high=seq[route..'Max'] or r[4]
          local value=math.floor(low+(high-low)*wave+0.5)
          result[M.targets[target]]=math.max(r[1],math.min(r[2],value))
        end
      end
    end
  end
  for key,value in pairs(state.held) do
    if self:mapped(seq,key) then result[key]=value end
  end
  if not preview then self.last[track]=result end
  return result
end
function M:effective(seq,track) return self:evaluate(seq,track,false) end
-- Read-only live values: no parameter, playback cache, random draw or state change.
function M:preview(seq,track) return self:evaluate(seq,track,true) end
function M:mapped(seq,target)
  if not seq.modEnabled then return false end
  for l=1,2 do
    if seq['lfo'..l..'Enabled'] then
      for d=1,2 do
        if M.targets[seq['lfo'..l..'Dest'..d] or 1]==target then return true end
      end
    end
  end
  return false
end
-- A single hold per destination, regardless of which pad created it.
-- Removing a destination releases its hold immediately, even while stopped.
function M:prune(seq,track)
  local state=self.state[track]
  if not state then return end
  for key in pairs(state.held) do
    if not self:mapped(seq,key) then state.held[key]=nil end
  end
end
function M:holdCounts(seq,track)
  self:prune(seq,track)
  local held,mapped=0,0
  for index=2,#M.targets do
    local key=M.targets[index]
    if self:mapped(seq,key) then
      mapped=mapped+1
      if self:frozen(track,key) then held=held+1 end
    end
  end
  return held,mapped
end
function M:freeze(seq,track,target)
  if not seq.modEnabled then return false end
  local current=self:effective(seq,track);local state=self.state[track]
  -- Latch what the last step actually used, not a later point on the wave.
  current=self.applied[track] or current
  if target then
    if state.held[target]~=nil then state.held[target]=nil;return false end
    if not self:mapped(seq,target) then return false end
    state.held[target]=current[target];return true
  end
  local held,mapped=self:holdCounts(seq,track)
  if mapped==0 then return false end
  if held==mapped then state.held={};return false end
  for index=2,#M.targets do
    local key=M.targets[index]
    -- Preserve any target already held locally; only add the remaining ones.
    if self:mapped(seq,key) and state.held[key]==nil then state.held[key]=current[key] end
  end
  return true
end
function M:frozen(track,target)
  local state=self.state[track]
  if not state then return false end
  if target then return state.held[target]~=nil end
  return next(state.held)~=nil
end
return M
