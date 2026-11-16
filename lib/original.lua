-- Original Animator import/playback. Opt-in per doodle; modern scenes are
-- unchanged. Snapshot arrays take precedence over stale cached line values.
local C=include('anima/lib/constants')
local Settings=include('anima/lib/track_settings')
local Original={}
Original.rates={2,3,4,5,8,6,9,7}
local rhythms={[3]=2,[4]=5,[5]=6,[6]=7}
local routes={2,4,10,7,11,11,2,8}
local function copy(t,seen)
 seen=seen or {};if seen[t] then return seen[t] end
 local r={};seen[t]=r
 for k,v in pairs(t or {}) do
  if k~='__index' and k~='metro' then r[k]=type(v)=='table' and copy(v,seen) or v end
 end
 return r
end
function Original.isOriginal(d)
 if d.formatVersion or d.trackSettings then return false end
 for _,s in ipairs(d.sequencers or {}) do if s.div then return true end end
 for _,s in pairs(d.snapshots or {}) do if s.divs then return true end end
 return false
end
function Original.convert(d,pset)
 d=copy(d);pset=pset or {}
 local function scene(s)
  s.originalPhase=0
  s.trackSettings={};s.rates={};s.harmonics={};s.rhythms={}
  for i=1,8 do
   local seq=s.sequencers[i] or {}
   local div=(s.divs and s.divs[i]) or seq.div or pset['seq'..i..'div'] or 1
   local rule=(s.intersects and s.intersects[i]) or seq.intersect or pset['seq'..i..'intersect'] or 1
   local settings={}
   for _,f in ipairs(Settings.fields) do settings[f.key]=f.default end
   settings.rate=Original.rates[div] or C.RATE_DEFAULT
   settings.harmonic=rule==2 and 2 or 1;settings.rhythm=rhythms[rule] or 1
   settings.output=routes[pset.output or 1];settings.port=pset.midi_out_device or 1
   settings.channel=seq.channel or pset['seq'..i..'channel'] or i
   settings.erPort=pset.ER_port or 1;settings.nbVoice='none'
   if s.sequencers[i] then
    for key,value in pairs(settings) do if key~='nbVoice' then seq[key]=value end end
    -- Two high-resolution ticks exactly equal one original pulse.
    seq.rateCount=2*(seq.divCount or 1)-1
    seq.intersect=rule;seq.div=nil;seq.divCount=nil
   end
   s.trackSettings[i]=settings;s.rates[i]=settings.rate
   s.harmonics[i]=settings.harmonic;s.rhythms[i]=settings.rhythm
  end
 end
 scene(d)
 for _,s in pairs(d.snapshots or {}) do scene(s) end
 d.originalPlayback={enabled=true,minVelocity=pset.min_velocity or 1,maxVelocity=pset.max_velocity or 127,
  minDurationCs=math.floor((pset.min_note_length or 0.1)*100),
  maxDurationCs=math.floor((pset.max_note_length or 0.1)*100),sourceOutput=pset.output or 1,sourceRoute=routes[pset.output or 1]}
 d.formatVersion=4
 return d
end
-- A snapshot can be recalled between original pulses. Preserve its original
-- counter while aligning the half-tick to the currently running clock.
function Original.alignSnapshot(a,snapshot)
 if not (a.originalPlayback and a.originalPlayback.enabled) then return end
 local delta=(a.originalPlayback.phase or 0)-(snapshot.originalPhase or 0)
 for _,seq in ipairs(a.sequencers) do
  seq.rateCount=(seq.rateCount+delta-1)%C.RATE_TICK_DIVS[seq.rate]+1
 end
end
-- Resolve an entire crossing using the original cumulative octave, shared
-- mute, channel overwrite, duplicate suppression and max-notes order.
function Original.count(a)
 a.originalPlayback.phase=((a.originalPlayback.phase or 0)+1)%2
 if a.outputs and a.outputs.begin_step then a.outputs:begin_step() end
 local play={};local solo=false
 for _,s in ipairs(a.sequencers) do if s.solo then solo=true;break end end
 for _,seq in ipairs(a.sequencers) do
  local div=C.RATE_TICK_DIVS[seq.rate]
  seq.rateCount=seq.rateCount%div+1
  if seq.rateCount==1 then
   seq:advance()
   if a.shouldResetAll then seq.index=1 end
   if seq.reset then seq.index=1;seq.reset=false end
   local step=seq.steps[seq.index];local pos=(step.y-1)*16+step.x
   if a.on[pos]>0 and seq.output~=1 and not seq.muted and (not solo or seq.solo) then
    play[pos]=play[pos] or {};play[pos][#play[pos]+1]=seq
   end
  end
 end
 if a.originalPlayback.phase==0 then a.shouldResetAll=false end
 local count,played=0,{}
 for pos,seqs in pairs(play) do
  local note=a.notes[pos];local first=seqs[1]
  local channelNotes={};channelNotes[first.channel]=note
  local owners={[first.channel]=first}
  local mute=false
  if #seqs>1 then
   for i,seq in ipairs(seqs) do
    if seq.harmonic==2 then note=note+12 end
    if seq.rhythm==2 then mute=true
    elseif seq.rhythm==5 then seq.reset=true
    elseif seq.rhythm==6 then for j,s in ipairs(seqs) do if j~=i then s.reset=true end end
    elseif seq.rhythm==7 then a.shouldResetAll=true end
    channelNotes[seq.channel]=note;owners[seq.channel]=seq
   end
  end
  for channel,pitch in pairs(channelNotes) do
   if not mute and played[pitch]~=channel then
    local owner=owners[channel];local track
    for i,s in ipairs(a.sequencers) do if s==owner then track=i;break end end
    if a.outputs then a.outputs:play_original(track,owner,pitch,a.originalPlayback,params:get('slop')) end
    played[pitch]=channel;count=count+1
    if count==params:get('max_notes') then return a.redraw() end
   end
  end
 end
 a.redraw()
end
return Original
