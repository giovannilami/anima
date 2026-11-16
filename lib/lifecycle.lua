local L = {}
-- An old Animator hnds callback can survive a failed exit. Stop only timers
-- whose source belongs to Animator; never reset other scripts/mods' timers.
function L.stop_stale_lfos(metros)
  for id,timer in pairs(metros.metros or {}) do
    if metros.assigned and metros.assigned[id] and type(timer.event)=='function' then
      local info = debug.getinfo(timer.event,'S')
      local source = info and info.source or ''
      if source:match('/animator/lib/hnds%.lua$') or source:match('/anima/lib/hnds%.lua$') then
        pcall(metros.free,id)
      end
    end
  end
end
function L.run(steps)
  for _,step in ipairs(steps) do
    local ok,err = pcall(step[2])
    if not ok then print('Animator cleanup ('..step[1]..'): '..tostring(err)) end
  end
end
return L
