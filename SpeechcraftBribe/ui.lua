-- [SB] ui.lua — v2025-09-24-R14
-- Embedded bribe panel inside MenuDialog. Text input + Enter submit. MWSE-only APIs.

local UI = {}

-- Deps
local cfg    = require("speechcraftbribe.config").config
local core   = require("speechcraftbribe.core")
local state  = require("speechcraftbribe.state")
local wealth = require("speechcraftbribe.wealth")

-- UI IDs
local PANEL_ID = tes3ui.registerID("SpeechcraftBribe:Panel")
local INFL_ID  = tes3ui.registerID("SpeechcraftBribe:Inflation")
local TRIES_ID = tes3ui.registerID("SpeechcraftBribe:TriesLeft")

-- Runtime
local lastSpeaker
local pendingSpeaker
local pollActive     = false
local retryScheduled = false
local dialogueActive = false

-- ========= Utils =========
local function has(fn) return type(fn) == "function" end

local function msg(text)
  if not text or text == "" then return end
  local inDialog = tes3ui.findMenu("MenuDialog") ~= nil
  tes3.messageBox({ message = text, showInDialog = inDialog or cfg.showMsgInDialogue })
  mwse.log("[SB] %s", text)
end

-- "fargoth00000000" -> "fargoth"
local function splitRefId(id)
  if type(id) ~= "string" then return nil, nil end
  local base, suffix = id:match("^(.-)([%x][%x][%x][%x][%x][%x][%x][%x])$")
  if base and suffix then return base, suffix end
  return id, nil
end

local function forEachActiveCell(doCell)
  local active = tes3.getActiveCells and tes3.getActiveCells() or nil
  local seen = {}
  if type(active) == "table" then
    for _, c in ipairs(active) do if c and not seen[c] then seen[c] = true; doCell(c) end end
    for _, c in pairs(active)  do if c and not seen[c] then seen[c] = true; doCell(c) end end
    return true
  end
  return false
end

local function iterateNPCsInCell(cell, yield)
  if not (cell and cell.iterateReferences) then return end
  for ref in cell:iterateReferences(tes3.objectType.npc) do yield(ref) end
end

local function iterateActiveNPCs(yield)
  if forEachActiveCell(function(c) iterateNPCsInCell(c, yield) end) then return end
  iterateNPCsInCell(tes3.getPlayerCell and tes3.getPlayerCell() or nil, yield)
end

local function findRefByBaseIdNearPlayer(baseId)
  if not baseId or baseId == "" then return nil end
  local best, bestD2
  local ppos = tes3.player and tes3.player.position or nil
  local baseLower = string.lower(baseId)
  iterateActiveNPCs(function(ref)
    local id = ref and ref.object and ref.object.id
    if id and string.lower(id) == baseLower then
      if ppos and ref.position then
        local dx, dy, dz = ppos.x - ref.position.x, ppos.y - ref.position.y, ppos.z - ref.position.z
        local d2 = dx*dx + dy*dy + dz*dz
        if not best or d2 < bestD2 then best, bestD2 = ref, d2 end
      else
        best = ref
      end
    end
  end)
  return best
end

local function isReferenceLike(a)
  if a == nil then return false end
  local okObj, obj = pcall(function() return a.object end)
  local okVal, _   = pcall(function() return a.valid end)
  return okObj and obj ~= nil and okVal
end

local function normalizeToRef(a, why)
  if not a then return nil end
  if isReferenceLike(a) then return a end
  if type(a) == "table" and a.reference then return a.reference end
  if type(a) == "string" then
    local id = a
    local ref = (tes3.getReference and tes3.getReference(id)) or (tes3.getReference and tes3.getReference(string.lower(id)))
    if ref then return ref end
    local baseId = splitRefId(id)
    if baseId and baseId ~= "" then
      return findRefByBaseIdNearPlayer(baseId)
    end
    return nil
  end
  local asStr = tostring(a)
  if asStr and asStr ~= "" and asStr ~= "userdata: NULL" then
    return normalizeToRef(asStr, (why or "?") .. " tostring()")
  end
  return nil
end

local function validNPCRef(ref)
  return ref and ref.object and ref.object.objectType == tes3.objectType.npc
end

local function cacheSpeaker(actor, why)
  local ref = normalizeToRef(actor, why)
  if validNPCRef(ref) then
    lastSpeaker = ref
    mwse.log("[SB] Cached dialogue actor (%s): %s", why or "unknown", ref.object and ref.object.id or "<no id>")
    pollActive = false
  end
end

local function isDialogueOpen()
  if tes3ui.findMenu("MenuDialog") ~= nil then return true end
  if validNPCRef(lastSpeaker) or validNPCRef(pendingSpeaker) then return true end
  if has(tes3ui.getDialogueTarget) and validNPCRef(normalizeToRef(tes3ui.getDialogueTarget(), "isDialogueOpen/dt")) then return true end
  if has(tes3ui.getServiceActor)   and validNPCRef(normalizeToRef(tes3ui.getServiceActor(),   "isDialogueOpen/sa")) then return true end
  return false
end

-- ========= Hooks =========
event.register("dialogueEnvironmentCreated", function(e)
  local env = e and e.environment
  if env and env.reference then cacheSpeaker(env.reference, "dialogueEnvironmentCreated") end
end)

event.register("infoResponse", function(e)
  local ref = e and e.reference
  if ref then cacheSpeaker(ref, "infoResponse") end
end)

-- Keep pending speaker warm for the duration of dialogue; expire otherwise.
local function armPendingExpiry()
  timer.start{
    type = timer.simulate, duration = 2.0, iterations = 1,
    callback = function()
      if dialogueActive then
        armPendingExpiry()
      else
        pendingSpeaker = nil
        mwse.log("[SB] Pending speaker expired.")
      end
    end
  }
end

event.register(tes3.event.activate, function(e)
  if e.activator ~= tes3.player then return end
  local ref = normalizeToRef(e.target, "activate")
  if validNPCRef(ref) then
    pendingSpeaker = ref
    mwse.log("[SB] Pending speaker captured from activate: %s", ref.object and ref.object.id or "<no id>")
    armPendingExpiry()
  end
end)

-- MenuDialog lifecycle
event.register(tes3.event.uiActivated, function(e)
  if not e.newlyCreated then return end
  dialogueActive = true
  mwse.log("[SB] MenuDialog activated.")
  if has(tes3ui.getDialogueTarget) then cacheSpeaker(tes3ui.getDialogueTarget(), "getDialogueTarget (now)") end
  if not validNPCRef(lastSpeaker) and has(tes3ui.getServiceActor) then cacheSpeaker(tes3ui.getServiceActor(), "getServiceActor (now)") end
  if not validNPCRef(lastSpeaker) and validNPCRef(pendingSpeaker) then cacheSpeaker(pendingSpeaker, "pendingSpeaker (now)") end

  -- short poll to catch late wiring
  pollActive = true
  local tries = 0
  timer.start{
    type = timer.simulate, duration = 0.05, iterations = 80,
    callback = function()
      if not pollActive then return end
      tries = tries + 1
      if validNPCRef(lastSpeaker) or not isDialogueOpen() then pollActive = false; return end
      local a
      if has(tes3ui.getDialogueTarget) then a = normalizeToRef(tes3ui.getDialogueTarget(), "poll/dt") end
      if not validNPCRef(a) and has(tes3ui.getServiceActor) then a = normalizeToRef(tes3ui.getServiceActor(), "poll/sa") end
      if not validNPCRef(a) and validNPCRef(pendingSpeaker) then a = pendingSpeaker end
      if validNPCRef(a) then cacheSpeaker(a, "poll") end
    end
  }
end, { filter = "MenuDialog" })

event.register(tes3.event.uiActivated, function(e)
  if e.newlyCreated then return end
  if e.element and e.element.name == "MenuDialog" then
    dialogueActive = false
    pollActive = false
  end
  if not isDialogueOpen() then
    pollActive = false
    pendingSpeaker = nil
    UI.close()
  end
end)

-- ========= Target getter =========
local function getDialogueTarget()
  if validNPCRef(pendingSpeaker) then mwse.log("[SB] Using pendingSpeaker."); return pendingSpeaker end
  if validNPCRef(lastSpeaker)    then mwse.log("[SB] Using lastSpeaker.");    return lastSpeaker    end
  if has(tes3ui.getDialogueTarget) then
    local a = normalizeToRef(tes3ui.getDialogueTarget(), "resolver/dt")
    if validNPCRef(a) then mwse.log("[SB] Using getDialogueTarget()."); return a end
  end
  if has(tes3ui.getServiceActor) then
    local a = normalizeToRef(tes3ui.getServiceActor(), "resolver/sa")
    if validNPCRef(a) then mwse.log("[SB] Using getServiceActor()."); return a end
  end
  local cross = normalizeToRef(tes3.getPlayerTarget and tes3.getPlayerTarget() or nil, "resolver/crosshair")
  if validNPCRef(cross) then mwse.log("[SB] Using crosshair target."); return cross end
  return nil
end

-- ========= Actions =========
local function playerGoldCount()
  return tes3.getItemCount{ reference = tes3.player, item = "gold_001" } or 0
end

local function removeGold(count)
  if count <= 0 then return true end
  local removed = tes3.removeItem{
    reference = tes3.player, item = "gold_001", count = count, updateGUI = true, playSound = false
  }
  return (removed or 0) >= count
end

local function getStats(mobile)
  local s = {
    speechcraft = mobile.speechcraft.current,
    personality = mobile.personality.current,
    mercantile  = mobile.mercantile.current,
  }
  return s
end

local function formatInflationText(mult)
  local m = tonumber(mult) or 1.0
  if m < 0 then m = 0 end
  local pct = (m - 1.0) * 100.0
  return string.format("Inflation: %.2fx (%.0f%%)", m, pct)
end

local function formatTriesLeftText(n)
  local t = tonumber(n) or 0
  if t < 0 then t = 0 end
  return string.format("Tries left: %d", t)
end

local function wasAccepted(zone)
  return zone == "success" or zone == "critical" or zone == "overpay"
end

local function doSubmit(panel, npc, field)
  local offer = tonumber(field.text) or 0
  offer = math.max(0, math.floor(offer))
  if offer <= 0 then msg("Enter a gold amount greater than 0."); return end
  if playerGoldCount() < offer then msg("Not enough gold."); return end

  local entry = state.getEntry(npc)
  if entry.triesLeft <= 0 then
    msg(string.format("You're out of tries. Come back after %d hours.", cfg.cooldownHours or 24))
    return
  end

  local pstats = getStats(tes3.mobilePlayer)
  local nstats = getStats(npc.mobile)
  local w  = wealth.multipliers(npc)
  local wm = (w and w.costMult) or 1.0

  local res = core.evaluateAttempt{
    offer = offer,
    inflation = entry.inflation or (cfg.inflationStart or 1.0),
    playerStats = pstats,
    npcStats = nstats,
    wealthCostMult = wm,
  }

  if res.goldTaken and res.goldTaken > 0 then
    if not removeGold(res.goldTaken) then msg("Not enough gold."); return end
    tes3.playSound{ sound = "Item Gold Down" }
  end

  local baseDelta = res.dispDelta or 0
  local delta = baseDelta
  if baseDelta > 0 then
    local pm = wealth.poorDispositionMultiplier(npc) or 1.0
    delta = math.floor(baseDelta * pm)
  end
  if delta ~= 0 then
    tes3.modDisposition{ reference = npc, value = delta }
  end

  -- Consume a try ONLY if the offer was not accepted
  if not wasAccepted(res.zone) then
    state.consumeTry(npc)
  end

  -- Speechcraft XP only on accepted offers
  if wasAccepted(res.zone) then
    local xp = cfg.xpPerSuccess or 1.0
    if xp ~= 0 then
      tes3.mobilePlayer:exerciseSkill(tes3.skill.speechcraft, xp)
    end
  end

  -- Mercantile XP on every attempt
  do
    local mxp = cfg.xpMercantilePerAttempt or 0.5
    if mxp ~= 0 then
      tes3.mobilePlayer:exerciseSkill(tes3.skill.mercantile, mxp)
    end
  end

  state.bumpInflation(npc, res.inflationDelta)
  msg(core.formatZoneMessage(res.zone))

  -- Refresh inflation + tries labels after result
  local dialog = tes3ui.findMenu("MenuDialog")
  if dialog then
    local label = dialog:findChild(INFL_ID)
    local tries = dialog:findChild(TRIES_ID)
    local entryNow = state.getEntry(npc)
    if label and entryNow then label.text = formatInflationText(entryNow.inflation) end
    if tries and entryNow then tries.text = formatTriesLeftText(entryNow.triesLeft) end
    dialog:updateLayout()
  end
end

-- ========= Panel UI (inside MenuDialog) =========
function UI.close()
  local dialog = tes3ui.findMenu("MenuDialog")
  if not dialog then return end
  local panel = dialog:findChild(PANEL_ID)
  if panel then panel:destroy(); dialog:updateLayout() end
end

local function buildPanel(dialog, npc)
  UI.close()

  local panel = dialog:createBlock{ id = PANEL_ID }
  panel.flowDirection      = "top_to_bottom"
  panel.autoWidth          = true
  panel.autoHeight         = true
  panel.paddingAllSides    = 8
  panel.borderAllSides     = 6
  panel.absolutePosAlignX  = 0.5
  panel.absolutePosAlignY  = 0.15

  -- Title
  local title = panel:createBlock{}
  title.flowDirection = "left_to_right"
  title.autoWidth, title.autoHeight = true, true
  title.borderBottom = 6
  title:createLabel{ text = string.format("Bribe: %s", (npc.object and npc.object.name) or npc.id) }

  -- Inflation line (current, per NPC)
  local inflBlock = panel:createBlock{}
  inflBlock.flowDirection = "left_to_right"
  inflBlock.autoWidth, inflBlock.autoHeight = true, true
  inflBlock.borderBottom = 2
  local entry = state.getEntry(npc)
  inflBlock:createLabel{
    id = INFL_ID,
    text = formatInflationText(entry and entry.inflation or (cfg.inflationStart or 1.0))
  }

  -- Tries left line
  local triesBlock = panel:createBlock{}
  triesBlock.flowDirection = "left_to_right"
  triesBlock.autoWidth, triesBlock.autoHeight = true, true
  triesBlock.borderBottom = 6
  triesBlock:createLabel{
    id = TRIES_ID,
    text = formatTriesLeftText(entry and entry.triesLeft or 0)
  }

  -- Input row
  local row = panel:createBlock{}
  row.flowDirection = "left_to_right"
  row.autoWidth, row.autoHeight = true, true
  row:createLabel{ text = "Offer (gold):" }
  local field = row:createTextInput{ text = tostring(cfg.baseFloor or 100) }
  field.width = 120
  if tes3ui.acquireTextInput then tes3ui.acquireTextInput(field) end

  -- Submit on Enter / NumpadEnter
  field:register(tes3.uiEvent.keyDown, function(e)
    local enter     = tes3.scanCode.enter or tes3.scanCode["return"]
    local numEnter  = tes3.scanCode.numpadEnter or tes3.scanCode.keypadEnter
    if e.keyCode == enter or e.keyCode == numEnter then
      doSubmit(panel, npc, field)
    end
  end)

  -- Buttons
  local brow = panel:createBlock{}
  brow.flowDirection = "left_to_right"
  brow.autoWidth, brow.autoHeight = true, true
  local bribe = brow:createButton{ text = "Bribe" }
  bribe:register(tes3.uiEvent.mouseClick, function() doSubmit(panel, npc, field) end)
  local close = brow:createButton{ text = "Close" }
  close:register(tes3.uiEvent.mouseClick, function() UI.close() end)

  panel:updateLayout()
  dialog:updateLayout()
  return panel
end

function UI.open()
  UI.close()

  local npc = getDialogueTarget()
  if not npc then
    local sa = has(tes3ui.getServiceActor) and tes3ui.getServiceActor() or nil
    local canResolve = validNPCRef(normalizeToRef(sa, "open/sa"))
    if (tes3ui.findMenu("MenuDialog") ~= nil) and (sa ~= nil) and not canResolve and not retryScheduled then
      retryScheduled = true
      mwse.log("[SB] Actor unresolved; scheduling one-shot retry for UI.open() (type=%s tostring=%s)", type(sa), tostring(sa))
      timer.start{ type = timer.simulate, duration = 0.10, iterations = 1, callback = function()
        retryScheduled = false
        UI.open()
      end }
      return
    end
    if isDialogueOpen() then msg("Could not resolve the dialogue NPC.") else msg("You can only bribe during dialogue.") end
    return
  end

  local dialog = tes3ui.findMenu("MenuDialog")
  if not dialog then msg("Dialogue menu not available."); return end

  local ok, err = pcall(function() buildPanel(dialog, npc) end)
  if not ok then
    mwse.log("[SB][ui] Panel build failed: %s", tostring(err))
    UI.close()
  else
    mwse.log("[SB][ui] Panel created in MenuDialog.")
  end
end

-- ========= Debug =========
local function _idOfAny(a)
  if not a then return "nil" end
  local ref = normalizeToRef(a, "debug")
  if validNPCRef(ref) and ref.object and ref.object.id then return ref.object.id end
  return tostring(a)
end

function UI.debugDump()
  local dt = has(tes3ui.getDialogueTarget) and tes3ui.getDialogueTarget() or nil
  local sa = has(tes3ui.getServiceActor)   and tes3ui.getServiceActor()   or nil
  local cross = tes3.getPlayerTarget and tes3.getPlayerTarget() or nil
  local lines = {
    ("MenuDialog present: %s"):format(tostring(tes3ui.findMenu("MenuDialog") ~= nil)),
    ("has tes3ui.getDialogueTarget: %s"):format(tostring(has(tes3ui.getDialogueTarget))),
    ("has tes3ui.getServiceActor: %s"):format(tostring(has(tes3ui.getServiceActor))),
    ("pendingSpeaker: %s"):format(_idOfAny(pendingSpeaker)),
    ("lastSpeaker: %s"):format(_idOfAny(lastSpeaker)),
    "getDialogueTarget(): " .. _idOfAny(dt),
    "getServiceActor(): "   .. _idOfAny(sa),
    "crosshair: "           .. _idOfAny(cross),
  }
  for _, s in ipairs(lines) do mwse.log("[SB][debug] %s", s) end
  tes3.messageBox({ message = "Speechcraft Bribe: wrote debug to MWSE.log.", showInDialog = true })
end

function UI.forceTargetFromCrosshair()
  local cross = normalizeToRef(tes3.getPlayerTarget and tes3.getPlayerTarget() or nil, "force/crosshair")
  if validNPCRef(cross) then
    cacheSpeaker(cross, "forced (F11 from crosshair)")
    tes3.messageBox({ message = string.format("Target set: %s", (cross.object and cross.object.name) or (cross.object and cross.object.id) or "NPC"), showInDialog = true })
  else
    tes3.messageBox({ message = "Crosshair target is not an NPC.", showInDialog = true })
  end
end

return UI
