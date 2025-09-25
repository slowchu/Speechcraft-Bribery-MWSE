-- [SB] core.lua — v2025-09-24-R2
local C = {}
local cfg = require("speechcraftbribe.config").config

local function clamp(x, lo, hi) if x < lo then return lo end if x > hi then return hi end return x end
local function round(x) return math.floor(x + 0.5) end

local function thresholdsFor(pstats, nstats)
  local t = cfg.thresholds or {}
  local ds = (pstats.speechcraft or 0) - (nstats.speechcraft or 0)
  local dp = (pstats.personality or 0) - (nstats.personality or 0)
  local scale = 1 - (cfg.speechcraftRangeScale or 0) * ds - (cfg.personalityRangeScale or 0) * dp
  scale = clamp(scale, cfg.rangeScaleMin or 0.5, cfg.rangeScaleMax or 2.0)
  return {
    insulting = (t.insulting or 0.25) * scale,
    low       = (t.low       or 0.75) * scale,
    close     = (t.close     or 0.95) * scale,
    success   = (t.success   or 1.05) * scale,
    critical  = (t.critical  or 1.35) * scale,
  }
end

local function classifyRatio(r, th)
  if r < th.insulting then return "insulting" end
  if r < th.low       then return "low"       end
  if r < th.close     then return "close"     end
  if r < th.success   then return "success"   end
  if r < th.critical  then return "critical"  end
  return "overpay"
end

local function mercantileMult(pMerc, nMerc)
  local d = (pMerc or 0) - (nMerc or 0)
  local mult = 1 - (cfg.mercantileDeltaScale or 0.01) * d
  return clamp(mult, cfg.mercantileMultMin or 0.5, cfg.mercantileMultMax or 1.5)
end

local function resistanceAdd(pstats, nstats)
  local speechDis = math.max(0, (nstats.speechcraft or 0) - (pstats.speechcraft or 0))
  local persoDis  = math.max(0, (nstats.personality or 0) - (pstats.personality or 0))
  return (cfg.resistSpeechWeight or 0.5) * speechDis
       + (cfg.resistPersonalityWeight or 0.5) * persoDis
end

local function requiredGold(inflationMult, pstats, nstats, wealthCostMult)
  local base = (cfg.baseFloor or 25)
  base = base + (cfg.resistWeight or 0.5) * resistanceAdd(pstats, nstats)
  local mMult = mercantileMult(pstats.mercantile, nstats.mercantile)
  local wMult = wealthCostMult or 1.0
  local req = base * (inflationMult or 1.0) * mMult * wMult
  return math.max(1, round(req))
end

function C.evaluateAttempt(args)
  args = args or {}
  local offer       = math.max(0, math.floor(args.offer or 0))
  local inflation   = args.inflation or (cfg.inflationStart or 1.0)
  local pstats      = args.playerStats or {}
  local nstats      = args.npcStats or {}
  local wealthCostMult = args.wealthCostMult or 1.0

  local requirement = requiredGold(inflation, pstats, nstats, wealthCostMult)
  local ratio = (requirement > 0) and (offer / requirement) or 0.0
  local th = thresholdsFor(pstats, nstats)
  local zone = classifyRatio(ratio, th)

  local disp = cfg.disposition or {}
  local dispDelta =
      (zone == "insulting" and (disp.insulting or -1))
   or (zone == "low"       and (disp.low       or  0))
   or (zone == "close"     and (disp.close     or -1))
   or (zone == "success"   and (disp.success   or 10))
   or (zone == "critical"  and (disp.critical  or 15))
   or (zone == "overpay"   and (disp.overpay   or  6))
   or 0

  local accepted = (zone == "success" or zone == "critical" or zone == "overpay")
  local goldTaken = accepted and offer or 0

  local triesConsumed = true
  if zone == "close" and cfg.closeNoTry then
    triesConsumed = false
  end

  local inflationDelta = 0.0
  if accepted then
    if zone == "critical" then
      inflationDelta = cfg.inflationAddCritical or 0.20
    elseif zone == "overpay" then
      inflationDelta = cfg.inflationAddOverpay or 0.15
    else
      inflationDelta = cfg.inflationAddSuccess or 0.10
    end
  end

  return {
    requirement    = requirement,
    ratio          = ratio,
    zone           = zone,
    goldTaken      = goldTaken,
    dispDelta      = dispDelta,
    triesConsumed  = triesConsumed,
    inflationDelta = inflationDelta,
  }
end

function C.formatZoneMessage(zone)
  if zone == "insulting" then return "Insulting offer." end
  if zone == "low"       then return "Too low." end
  if zone == "close"     then return "Close... you're almost there." end
  if zone == "success"   then return "Success!" end
  if zone == "critical"  then return "Perfect offer!" end
  return "Overpaying... generosity noted."
end

return C
