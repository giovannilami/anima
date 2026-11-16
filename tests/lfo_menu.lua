-- Exercise the real Norns EDIT menu, not a simulated nested-menu model.
local nornsRoot,dataDir=assert(arg[1]),assert(arg[2])
package.path=nornsRoot..'/lua/?.lua;'..nornsRoot..'/lua/lib/?.lua;'..package.path
util=require 'util';controlspec=require 'core/controlspec'
norns={state={shortname='anima',pset_last=1,data=dataDir..'/'},pmap={data={}}}
params=require('core/paramset').new()
metro={init=function() return {id=1,start=function() end,stop=function() end} end,free=function() end}
package.preload.fileselect=function() return {} end
package.preload.textentry=function() return {} end
include=function(path) return dofile(path:gsub('^anima/','')..'.lua') end
local S=include('lib/track_settings')
local a={sequencers={}}
S.add(a,nil,true)
local global=include('lib/lfo')
S.addLfoSection(a,function() global.init(a) end)
params:add_group('after','AFTER',1);params:add_number('after_value','after value',0,10,0)
local function visible(id) return params:visible(id) end
local function checkScope(scope,oscillator)
 for i=1,8 do
  assert(not params.lookup['track'..i..'lfos'],'no extra top-level track LFO group')
  for _,f in ipairs(S.fields) do
   if f.mod then
    local slot=tonumber(f.key:match('^lfo(%d)'))
    assert(visible('seq'..i..f.key)==(scope==i+1 and (not slot or slot==oscillator)),
      'unexpected visible field '..i..' '..f.key)
   end
  end
 end
 for i=1,2 do
  for _,suffix in ipairs({'lfo_target','lfo_shape','lfo_depth','offset','lfo_freq','lfo'}) do
   assert(visible(i..suffix)==(scope==1 and oscillator==i),'general visibility '..i..suffix)
  end
 end
end
checkScope(1,1)
assert(params:lookup_param('anima_lfo_section').save==false and params:lookup_param('anima_lfo_oscillator').save==false)
print('PASS one LFO group contains general and all track settings with only selected controls visible')

local texts={}
screen=setmetatable({text=function(value) texts[#texts+1]=tostring(value) end},
 {__index=function() return function() end end})
_menu={mode=true,redraw=function() end,draw_panel=function() end,
 timer={start=function() end,stop=function() end},binarystates={on={},triggered={}}}
local menu=dofile(nornsRoot..'/lua/core/menu/params.lua')
_menu.redraw=menu.redraw
menu.init();menu.key(3,1);menu.enc(2,8);menu.key(3,1)
assert(menu.group and menu.groupid==params.lookup.LFO and menu.pos==0)
menu.enc(3,1);checkScope(2,1)
menu.enc(2,1);menu.enc(3,1);checkScope(2,2)
menu.enc(2,1);menu.enc(3,1)
assert(params:get('seq1modEnabled')==2 and params:get('seq2modEnabled')==1,'edits address only selected track')
menu.enc(2,-100);menu.enc(3,7);checkScope(9,2)
menu.enc(2,1);menu.enc(3,-1);checkScope(9,1)
menu.enc(2,-100);menu.enc(3,-8);checkScope(1,1)
menu.key(2,1);menu.enc(2,1);menu.key(3,1)
assert(menu.groupid==params.lookup.after,'following EDIT groups remain accessible')
print('PASS real EDIT encoder navigation selects general, track and oscillator without leaving the LFO section')

params:set('seq8lfo2Dest1',8);params:set('seq8lfo2Dest1Min',0);params:set('seq8lfo2Dest1Max',3)
params:set('seq8ratchet',0);params:set('seq8ratchetEnabled',2)
params:set('1lfo_depth',37)
params:set('anima_lfo_section',9);params:set('anima_lfo_oscillator',2)
local writeParams=include('lib/persistence').write_params
local path=dataDir..'/lfo-menu.pset';writeParams(path)
local f=assert(io.open(path,'r'));local saved=f:read('*a');f:close()
assert(not saved:find('anima_lfo_section',1,true) and not saved:find('anima_lfo_oscillator',1,true),'UI selection is not part of saved sound')
params:set('seq8ratchet',4);params:set('seq8lfo2Dest1Min',2);params:set('1lfo_depth',100)
params:set('anima_lfo_section',1);params:set('anima_lfo_oscillator',1)
params:read(path)
assert(params:get('seq8ratchet')==0 and params:get('seq8lfo2Dest1Min')==0 and params:get('1lfo_depth')==37)
checkScope(1,1)
print('PASS hidden track and general LFO values persist while menu selection stays unchanged on PSET load')
global.cleanup()
print('3/3 real EDIT LFO menu scenarios passed')
