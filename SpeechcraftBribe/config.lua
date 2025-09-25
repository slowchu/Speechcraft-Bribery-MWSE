-- [SB] config.lua — v2025-09-24-R3
local this = {}
this.configPath = "Speechcraft Bribe"
this.config = mwse.loadConfig(this.configPath) or {}

this.defaults = {
  -- UI / Controls
  showMsgInDialogue = true,
  hotkey = { keyCode = tes3.scanCode.b },

  -- Attempts
  triesMax = 3,
  cooldownHours = 24,

  -- Inflation
  inflationStart = 1.0,          -- starting multiplier for each NPC
  inflationCap = 3.0,            -- hard cap
  inflationAddSuccess = 0.10,    -- +x on success
  inflationAddCritical = 0.20,   -- +x on perfect
  inflationAddOverpay = 0.05,    -- +x on overpay
  inflationDecayPerDay = 0.25,   -- linear decay per in-game day
  closeNoTry = true,             -- “close” results do not spend a try (UI currently only spends on non-success)

  -- Requirement (gold)
  baseFloor = 100,               -- base required gold before scaling
  mercantileDeltaScale = 0.02,   -- per-point effect of (P.merc - N.merc) on requirement
  mercantileMultMin = 0.75,      -- clamp min multiplier
  mercantileMultMax = 1.50,      -- clamp max multiplier

  -- Band scaling by stat delta (affects insulting/low/close/success/critical bands)
  speechcraftRangeScale = 0.010, -- per-point effect of (P.speech - N.speech)
  personalityRangeScale = 0.010, -- per-point effect of (P.personality - N.personality)
  rangeScaleMin = 0.50,
  rangeScaleMax = 2.00,

  -- Resistance (adds to floor when NPC outclasses player)
  resistWeight = 1.00,
  resistSpeechWeight = 0.50,
  resistPersonalityWeight = 0.50,

  -- Disposition deltas per outcome
  disposition = {
    insulting = -10,
    low       = -5,
    close     = 0,
    success   = 5,
    critical  = 10,
    overpay   = 10,
  },

  -- XP scales (legacy knobs kept for compatibility with any custom math)
  xpScaleSuccess  = 1.0,
  xpScaleCritical = 1.0,
  xpScaleOverpay  = 1.0,

  -- NEW: skill XP awards used by ui.lua
  xpPerSuccess = 1.0,            -- Speechcraft XP per accepted bribe (success/critical/overpay)
  xpMercantilePerAttempt = 0.5,  -- Mercantile XP per bribe attempt (any result)

  -- Wealth tuning
  wealthMidValue   = 120,  -- value at which NPC is “average wealth”
  perDecadeCost    = 0.30, -- cost multiplier per 10× wealth change
  maxCostBonus     = 0.25, -- max cost decrease for very poor NPCs (as fraction)
  maxCostPenalty   = 0.60, -- max cost increase for very rich NPCs (as fraction)

  includeInventory   = true,
  inventoryWeight    = 0.15,
  inventoryCap       = 2000,
  excludeGold        = true,  -- exclude gold item from inventory calc
  includeBaseGold    = true,  -- merchant template baseGold
  baseGoldWeight     = 1.25,

  includeWeapons     = true,  -- count equipped weapon value in wealth
  includeCarriedGold = true,  -- add currently carried gold to wealth

  -- Poor-only positive disposition boost on success
  poorDispPerDecade = 1.5,
  poorDispGamma     = 1.1,
  poorDispMax       = 3.0,

  -- Debug
  debugWealth = false,
}

-- Merge defaults into saved config (non-destructive deep merge)
local function mergeDefaults(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      if type(v) == "table" then
        local sub = {}
        mergeDefaults(sub, v)
        t[k] = sub
      else
        t[k] = v
      end
    elseif type(v) == "table" and type(t[k]) == "table" then
      mergeDefaults(t[k], v)
    end
  end
end
mergeDefaults(this.config, this.defaults)

function this.save()
  mwse.saveConfig(this.configPath, this.config)
end

return this
