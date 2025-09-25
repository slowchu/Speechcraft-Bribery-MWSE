-- [SB] wealth.lua — v2025-09-24-R2
local W = {}
local cfg = require("speechcraftbribe.config").config

local function clamp(x, lo, hi) if x < lo then return lo end if x > hi then return hi end return x end

local function safeValueForStack(stack)
  if not stack or not stack.object then return 0 end
  local val = tes3.getValue({ item = stack.object, itemData = stack.itemData })
  return val or (stack.object.value or 0)
end

function W.clothingModifier(ref)
  if not (ref and ref.object and ref.object.equipment) then return 0 end
  local sum = 0
  for _, stack in pairs(ref.object.equipment) do
    if stack and stack.object then
      local t = stack.object.objectType
      local isArm = (t == tes3.objectType.armor)
      local isClo = (t == tes3.objectType.clothing)
      local isWea = (t == tes3.objectType.weapon)
      if isArm or isClo or (cfg.includeWeapons and isWea) then
        sum = sum + safeValueForStack(stack)
      end
    end
  end
  if cfg.includeCarriedGold and ref.object and ref.object.inventory then
    local count = ref.object.inventory:getItemCount("gold_001") or 0
    sum = sum + count
  end
  return sum
end

function W.inventoryValue(ref)
  if not (ref and ref.object and ref.object.inventory) then return 0 end
  local sum = 0
  for _, stack in pairs(ref.object.inventory) do
    if stack and stack.object then
      if not stack.isEquipped then
        if cfg.excludeGold and stack.object.id == "gold_001" then
          -- skip
        else
          sum = sum + (safeValueForStack(stack) * (stack.count or 1))
        end
      end
    end
  end
  return math.max(0, sum)
end

function W.totalWealth(ref)
  if not (ref and ref.object) then return 0 end
  local wear   = W.clothingModifier(ref)
  local invRaw = cfg.includeInventory and W.inventoryValue(ref) or 0
  local invTerm = math.min((cfg.inventoryWeight or 0.15) * invRaw, cfg.inventoryCap or 2000)

  local baseGoldTerm = 0
  if cfg.includeBaseGold and ref.baseObject and ref.baseObject.objectType == tes3.objectType.npc then
    local rec = ref.baseObject
    local bg = (rec and rec.baseGold) or 0
    baseGoldTerm = (cfg.baseGoldWeight or 1.25) * bg
  end

  return wear + invTerm + baseGoldTerm
end

function W.multipliers(ref)
  local raw = W.totalWealth(ref)
  local mid = math.max(0, cfg.wealthMidValue or 120)
  local decades = math.log((raw + 1) / (mid + 1), 10)
  local cost = 1 + (cfg.perDecadeCost or 0.30) * decades
  cost = clamp(cost, 1 - (cfg.maxCostBonus or 0.25), 1 + (cfg.maxCostPenalty or 0.60))
  local disp = 1 / math.sqrt(cost)
  if cfg.debugWealth then
    mwse.log(string.format("[Wealth] raw=%.1f mid=%.1f decades=%.3f cost=%.3f disp=%.3f", raw, mid, decades, cost, disp))
  end
  return { costMult = cost, dispMult = disp, raw = raw, mid = mid }
end

function W.poorDispositionMultiplier(ref)
  local raw = W.totalWealth(ref)
  local mid = math.max(0, cfg.wealthMidValue or 120)
  local decadesPoor = math.max(0, math.log((mid + 1) / (raw + 1), 10))
  local mult = 1 + (cfg.poorDispPerDecade or 1.5) * decadesPoor
  mult = math.pow(mult, cfg.poorDispGamma or 1.1)
  mult = clamp(mult, 1.0, cfg.poorDispMax or 3.0)
  if cfg.debugWealth then
    mwse.log(string.format("[WealthPoor] raw=%.1f mid=%.1f decades=%.3f poorMult=%.3f", raw, mid, decadesPoor, mult))
  end
  return mult
end

return W
