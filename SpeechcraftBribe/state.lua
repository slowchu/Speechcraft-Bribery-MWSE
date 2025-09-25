-- [SB] state.lua — v2025-09-24-R2
local S = {}
local cfgMod = require("speechcraftbribe.config")
local cfg = cfgMod.config

local function nowDays()
  local dp = tes3.getGlobal("daysPassed") or 0
  return tonumber(dp) or 0
end

local function decayInflation(value, daysElapsed)
  local perDay = cfg.inflationDecayPerDay or 0
  if perDay <= 0 or (daysElapsed or 0) <= 0 then
    return value or 1.0
  end
  local decayed = (value or 1.0) - perDay * daysElapsed
  if decayed < 1.0 then decayed = 1.0 end
  return decayed
end

local function ensureRoot()
  local data = tes3.player and tes3.player.data
  data.speechcraftBribe = data.speechcraftBribe or {}
  return data.speechcraftBribe
end

local function npcKey(npc)
  if npc and npc.object and npc.object.id then
    return string.lower(npc.object.id)
  end
  return "unknown"
end

function S.getEntry(npc)
  local root = ensureRoot()
  local key = npcKey(npc)
  local entry = root[key]
  if not entry then
    entry = {
      triesLeft  = cfg.triesMax or 3,
      lastDays   = nowDays(),
      inflation  = cfg.inflationStart or 1.0,
      cooldownAt = 0,
    }
    root[key] = entry
  end

  local today = nowDays()
  local last = tonumber(entry.lastDays or today) or today
  local dt   = math.max(0, today - last)

  entry.inflation = decayInflation(entry.inflation or 1.0, dt)
  entry.lastDays  = today

  if (entry.cooldownAt or 0) > 0 and today >= entry.cooldownAt then
    entry.triesLeft  = cfg.triesMax or entry.triesLeft or 3
    entry.cooldownAt = 0
  end

  return entry
end

function S.consumeTry(npc)
  local entry = S.getEntry(npc)
  entry.triesLeft = math.max(0, (entry.triesLeft or 0) - 1)
  if entry.triesLeft <= 0 then
    local hours = cfg.cooldownHours or 24
    local days  = math.max(0, hours / 24.0)
    entry.cooldownAt = nowDays() + days
  end
end

function S.bumpInflation(npc, delta)
  if not delta or delta <= 0 then return end
  local entry = S.getEntry(npc)
  local cap = cfg.inflationCap or 3.0
  entry.inflation = math.min(cap, (entry.inflation or 1.0) + delta)
end

return S
