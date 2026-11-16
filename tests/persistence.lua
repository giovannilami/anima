local nornsRoot, dataDir = assert(arg[1]),assert(arg[2])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util'
norns={pmap={data={}}}
params=require('core/paramset').new()
params:add_number('tone','tone',0,100,50)
local P=dofile('lib/persistence.lua')
local tab=require 'tabutil'
local function read(path) local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local tests={}
tests['save checks file errors and preserves the default output handle']=function()
  local before=io.output()
  local path=dataDir..'/safe'
  assert(P.save({name='safe',trackSettings={}},path))
  assert(io.output()==before and io.type(io.output())=='file')
  assert(tab.load(path..'.doodle').name=='safe')
  local ok,err=P.save({name='bad'},dataDir..'/missing/doodle')
  assert(not ok and err,'unwritable save is reported')
  assert(io.output()==before)
end
tests['partial native PSET failure leaves previous files untouched']=function()
  local path=dataDir..'/previous'
  assert(P.save({name='previous',value=1},path))
  local beforeDoodle,beforeParams=read(path..'.doodle'),read(path..'.pset')
  local beforeIo=io.output()
  local original=params.write
  params.write=function(_,name)
    local file=assert(io.open(name,'w'));io.output(file)
    io.write('partial data')
    error('simulated PSET failure')
  end
  local ok,err=P.save({name='previous',value=2},path)
  params.write=original
  assert(not ok and err:find('simulated PSET failure',1,true))
  assert(read(path..'.doodle')==beforeDoodle and read(path..'.pset')==beforeParams)
  assert(io.output()==beforeIo and io.type(io.output())=='file')
end
tests['overwrites retain readable backups']=function()
  local path=dataDir..'/backup'
  assert(P.save({name='backup',value=1},path))
  assert(P.save({name='backup',value=2},path))
  assert(tab.load(path..'.doodle').value==2)
  assert(tab.load(path..'.doodle.bak').value==1)
end
tests['serialization excludes functions metatables and their virtual entries']=function()
  local called=false
  local object=setmetatable({value=5,callback=function() end},{__index=function() called=true;error('virtual access') end})
  local copy=P.plain(object)
  assert(copy.value==5 and copy.callback==nil and getmetatable(copy)==nil and not called)
end
local count=0
for name,test in pairs(tests) do test();count=count+1;print('PASS '..name) end
print(count..'/'..count..' passed')
