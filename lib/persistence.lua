-- Stage both files before replacing the last good save. Native params:write
-- changes Lua's default output handle; always restore it, even on an error.
local P = {}
local tab = require 'tabutil'
local function plain(value, seen)
  local kind = type(value)
  if kind ~= 'table' then
    if kind == 'number' or kind == 'string' or kind == 'boolean' then return value end
    return nil
  end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}; seen[value] = copy
  for k,v in next,value do
    if type(k)=='number' or type(k)=='string' or type(k)=='boolean' then copy[k] = plain(v, seen) end
  end
  return copy
end
local function read(path)
  local f = io.open(path,'rb')
  if not f then return nil end
  local data = f:read('*a'); f:close(); return data
end
local function write(path, data)
  local f,err = io.open(path,'wb'); assert(f,err)
  local ok,message = f:write(data)
  local closed,closeErr = f:close()
  assert(ok,message); assert(closed,closeErr)
end
function P.write_params(path)
  local original = io.output()
  if io.type(original) ~= 'file' then original = io.stdout end
  local ok,err = pcall(function() params:write(path) end)
  local changed = io.output()
  io.output(original)
  if changed ~= original and io.type(changed) == 'file' then pcall(io.close,changed) end
  assert(ok,err)
  local data = read(path)
  assert(data and #data > 0, 'parameter file was not written: ' .. path)
end
function P.save(doodle, path)
  local stagedDoodle,stagedParams = path .. '.pending.doodle',path .. '.pending.pset'
  os.remove(stagedDoodle); os.remove(stagedParams)
  local ok,err = pcall(function()
    local saveError = tab.save(plain(doodle),stagedDoodle)
    assert(not saveError,saveError)
    local loaded,loadError = tab.load(stagedDoodle)
    assert(loaded and loaded.name == doodle.name,loadError or 'doodle verification failed')
    P.write_params(stagedParams)
    local oldDoodle,oldParams = read(path..'.doodle'),read(path..'.pset')
    -- Keep an independently readable previous version alongside the new save.
    if oldDoodle then write(path..'.doodle.bak',oldDoodle) end
    if oldParams then write(path..'.pset.bak',oldParams) end
    local renamed,renameError = os.rename(stagedParams,path..'.pset')
    assert(renamed,renameError)
    renamed,renameError = os.rename(stagedDoodle,path..'.doodle')
    if not renamed then
      if oldParams then write(path..'.pset',oldParams) else os.remove(path..'.pset') end
      error(renameError)
    end
  end)
  os.remove(stagedDoodle); os.remove(stagedParams)
  return ok,err
end
P.plain = plain
return P
