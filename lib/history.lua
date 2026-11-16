-- Bounded, session-only edit history. No clock or LFO event is recorded.
local H={};H.__index=H
local function equal(a,b)
  if a==b then return true end
  if type(a)~='table' or type(b)~='table' then return false end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
function H.new(capture,restore,time)
  return setmetatable({capture=capture,restore=restore,time=time,undoStack={},redoStack={}},H)
end
function H:clear() self.undoStack={};self.redoStack={};self.key=nil end
function H:perform(key,fn,window)
  if self.busy then return fn() end
  local before=self.capture();self.busy=true
  local ok,value=pcall(fn);self.busy=false
  if not ok then error(value,0) end
  if not equal(before,self.capture()) then
    local now=self.time()
    if not (window and self.key==key and now-(self.at or 0)<=window) then
      self.undoStack[#self.undoStack+1]=before
      if #self.undoStack>16 then table.remove(self.undoStack,1) end
    end
    self.redoStack={};self.key=key;self.at=now
  end
  return value
end
function H:travel(redo)
  local from=redo and self.redoStack or self.undoStack
  local to=redo and self.undoStack or self.redoStack
  if #from==0 then return false end
  to[#to+1]=self.capture()
  local state=table.remove(from)
  self.busy=true
  local ok,err=pcall(self.restore,state)
  self.busy=false;self.key=nil
  if not ok then error(err,0) end
  return true
end
return H
