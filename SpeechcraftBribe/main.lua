-- [SB] main.lua — v2025-09-24-R2
local okCfg, configMod = pcall(require, "speechcraftbribe.config")
if not okCfg then
  mwse.log("[SB] config load error: %s", tostring(configMod))
  configMod = { config = { hotkey = { keyCode = tes3.scanCode.b } }, configPath = "Speechcraft Bribe" }
end

pcall(require, "speechcraftbribe.mcm")

event.register(tes3.event.initialized, function()
  local okUI, UIorErr = pcall(require, "speechcraftbribe.ui")
  if not okUI then
    mwse.log("[SB] ui load error: %s", tostring(UIorErr))
    return
  end
  local UI = UIorErr

  local function onKeyDown(e)
    if not e or not e.keyCode then return end
    if e.keyCode == tes3.scanCode.f10 then
      if UI.debugDump then UI.debugDump() end
      return
    elseif e.keyCode == tes3.scanCode.f11 then
      if UI.forceTargetFromCrosshair then UI.forceTargetFromCrosshair() end
      return
    elseif e.keyCode == tes3.scanCode.f9 then
      if UI.probeScan then UI.probeScan() end
      return
    end

    local hk = (configMod.config and configMod.config.hotkey) or { keyCode = tes3.scanCode.b }
    if e.keyCode ~= (hk.keyCode or -1) then return end
    if hk.isControlDown and not e.isControlDown then return end
    if hk.isAltDown     and not e.isAltDown     then return end
    if hk.isShiftDown   and not e.isShiftDown   then return end

    mwse.log("[SB] Hotkey pressed; invoking UI.open()")
    UI.open()
  end

  event.register(tes3.event.keyDown, onKeyDown, { priority = 10 })
  mwse.log("[SB] initialized; hotkey keyCode=%s (F10: debug, F11: force target from crosshair, F9: probe)",
    tostring((configMod.config.hotkey or {}).keyCode))
end)
