-- [SB] mcm.lua — v2025-09-24-R3
local cfgMod = require("speechcraftbribe.config")
local config = cfgMod.config

local function registerMCM()
  local t = mwse.mcm.createTemplate({ name = "Speechcraft Bribe" })
  t:saveOnClose(cfgMod.configPath, config)

  -- ========== Controls ==========
  local controls = t:createSideBarPage{
    label = "Controls",
    description = "Open the bribe panel during dialogue with the bound hotkey (default: B). Messages can optionally appear inside the dialogue window."
  }
  controls:createKeyBinder{
    label = "Bribe hotkey",
    description = "Press during dialogue to open the bribe panel.",
    allowCombinations = true,
    variable = mwse.mcm.createTableVariable{ id = "hotkey", table = config },
  }
  controls:createYesNoButton{
    label = "Show messages inside dialogue",
    variable = mwse.mcm.createTableVariable{ id = "showMsgInDialogue", table = config },
  }

  -- small helper for sliders
  local function s(page, label, min, max, step, id, tbl)
    page:createSlider{
      label = label, min = min, max = max, step = step,
      variable = mwse.mcm.createTableVariable{ id = id, table = tbl or config }
    }
  end

  -- ========== Attempts ==========
  local attempts = t:createSideBarPage{
    label = "Attempts",
    description = "Per-NPC tries with a cooldown; inflation rises on accepted bribes and decays per day."
  }
  s(attempts, "Max tries per NPC", 1, 10, 1, "triesMax")
  s(attempts, "Cooldown (hours)", 0, 168, 1, "cooldownHours")

  attempts:createCategory("Inflation")
  s(attempts, "Start (x)", 0.50, 5.00, 0.01, "inflationStart")
  s(attempts, "Cap (x)",   1.00, 10.00, 0.01, "inflationCap")
  s(attempts, "Add on Success (x)",  0.00, 1.00, 0.01, "inflationAddSuccess")
  s(attempts, "Add on Perfect (x)",  0.00, 1.00, 0.01, "inflationAddCritical")
  s(attempts, "Add on Overpay (x)",  0.00, 1.00, 0.01, "inflationAddOverpay")
  s(attempts, "Decay per day (linear)", 0.00, 5.00, 0.05, "inflationDecayPerDay")
  attempts:createYesNoButton{
    label = "'Close' does not consume a try",
    variable = mwse.mcm.createTableVariable{ id = "closeNoTry", table = config }
  }

  attempts:createCategory("Rewards")
  attempts:createSlider{
    label = "Speechcraft XP per accepted bribe",
    description = "XP added to Speechcraft when an offer is accepted (success/critical/overpay). Set to 0 to disable.",
    min = 0.0, max = 10.0, step = 0.1,
    variable = mwse.mcm.createTableVariable{ id = "xpPerSuccess", table = config }
  }
  attempts:createSlider{
    label = "Mercantile XP per attempt",
    description = "XP added to Mercantile for every bribe attempt (success or failure). Set to 0 to disable.",
    min = 0.0, max = 10.0, step = 0.1,
    variable = mwse.mcm.createTableVariable{ id = "xpMercantilePerAttempt", table = config }
  }

  -- ========== Tuning ==========
  local tuning = t:createSideBarPage{
    label = "Tuning",
    description = "Requirement and band-scaling knobs (Preset-like defaults)."
  }

  tuning:createCategory("Requirement")
  s(tuning, "Base floor (gold)", 1, 500, 1, "baseFloor")
  s(tuning, "Mercantile effect per point", 0.00, 0.20, 0.001, "mercantileDeltaScale")
  s(tuning, "Mercantile multiplier min", 0.10, 1.00, 0.01, "mercantileMultMin")
  s(tuning, "Mercantile multiplier max", 1.00, 3.00, 0.01, "mercantileMultMax")

  tuning:createCategory("Band scaling (by stat delta)")
  s(tuning, "Range scale - Speechcraft", 0.00, 0.05, 0.001, "speechcraftRangeScale")
  s(tuning, "Range scale - Personality", 0.00, 0.05, 0.001, "personalityRangeScale")
  s(tuning, "Range scale min", 0.10, 1.00, 0.01, "rangeScaleMin")
  s(tuning, "Range scale max", 1.00, 3.00, 0.01, "rangeScaleMax")

  tuning:createCategory("Resistance (adds to floor when outclassed)")
  s(tuning, "Resist weight (overall)", 0.0, 3.0, 0.05, "resistWeight")
  s(tuning, "Resist: speechcraft share", 0.0, 1.0, 0.01, "resistSpeechWeight")
  s(tuning, "Resist: personality share", 0.0, 1.0, 0.01, "resistPersonalityWeight")

  -- ========== Disposition ==========
  local disp = t:createSideBarPage{
    label = "Disposition",
    description = "Disposition changes per outcome (poor-NPC boost only affects positive gains)."
  }
  s(disp, "Insulting", -20, 0, 1, "insulting", config.disposition)
  s(disp, "Too low",  -20, 0, 1, "low",       config.disposition)
  s(disp, "Close",    -10, 10, 1, "close",     config.disposition)
  s(disp, "Success",    0,  20, 1, "success",  config.disposition)
  s(disp, "Perfect",    0,  30, 1, "critical", config.disposition)
  s(disp, "Overpay",    0,  30, 1, "overpay",  config.disposition)

  -- ========== XP (legacy) ==========
  local xp = t:createSideBarPage{
    label = "XP",
    description = "Legacy multipliers used by some formulas. The actual skill awards are configured under Attempts ▸ Rewards."
  }
  s(xp, "Success XP scale",  0.0, 5.0, 0.05, "xpScaleSuccess")
  s(xp, "Perfect XP scale",  0.0, 5.0, 0.05, "xpScaleCritical")
  s(xp, "Overpay XP scale",  0.0, 5.0, 0.05, "xpScaleOverpay")

  -- ========== Wealth ==========
  local wealth = t:createSideBarPage{
    label = "Wealth",
    description = "Wealth affects required gold; poor-only extra disposition on positive outcomes."
  }
  s(wealth, "Wealth midpoint (value)", 0, 5000, 10, "wealthMidValue")
  s(wealth, "Cost per decade (+/-)", 0.00, 1.00, 0.01, "perDecadeCost")
  s(wealth, "Max cost bonus (poor)", 0.00, 1.00, 0.01, "maxCostBonus")
  s(wealth, "Max cost penalty (rich)", 0.00, 1.00, 0.01, "maxCostPenalty")

  wealth:createYesNoButton{
    label="Include inventory (weighted & capped)",
    variable = mwse.mcm.createTableVariable{ id="includeInventory", table = config }
  }
  s(wealth, "Inventory weight", 0.00, 1.00, 0.01, "inventoryWeight")
  s(wealth, "Inventory cap", 0, 10000, 10, "inventoryCap")

  wealth:createYesNoButton{
    label="Exclude gold item from inventory",
    variable = mwse.mcm.createTableVariable{ id="excludeGold", table = config }
  }
  wealth:createYesNoButton{
    label="Include baseGold (merchant template)",
    variable = mwse.mcm.createTableVariable{ id="includeBaseGold", table = config }
  }
  s(wealth, "baseGold weight", 0.0, 3.0, 0.05, "baseGoldWeight")

  wealth:createYesNoButton{
    label="Include weapons (equipped) in wealth",
    variable = mwse.mcm.createTableVariable{ id="includeWeapons", table = config }
  }
  wealth:createYesNoButton{
    label="Include carried gold",
    variable = mwse.mcm.createTableVariable{ id="includeCarriedGold", table = config }
  }

  wealth:createCategory("Poor-only disposition boost")
  s(wealth, "Per-decade boost", 0.0, 5.0, 0.05, "poorDispPerDecade")
  s(wealth, "Gamma (curve)",    0.5, 3.0, 0.05, "poorDispGamma")
  s(wealth, "Max boost (x)",    1.0, 5.0, 0.05, "poorDispMax")

  wealth:createYesNoButton{
    label="Log wealth calculations (MWSE.log)",
    variable = mwse.mcm.createTableVariable{ id="debugWealth", table = config }
  }

  mwse.mcm.register(t)
end

event.register(tes3.event.modConfigReady, registerMCM)
