import
  std/asyncdispatch,
  kbdinput,
  slippi,
  dolphincontroller,
  digitalmeleecontroller

var
  isEnabled = true
  onOffToggle = false
  onOffTogglePrevious = false
  controller = initDigitalMeleeController()
  dolphinCtrl = initDolphinController(1, "")
  stream = initSlippiStream()

stream.connect()

setAllKeysBlocked(true)

proc updateController() =
  controller.setActionState(Action.Left, keyIsPressed(Key.A))
  controller.setActionState(Action.Right, keyIsPressed(Key.D))
  controller.setActionState(Action.Down, keyIsPressed(Key.S))
  controller.setActionState(Action.Up, keyIsPressed(Key.W))
  controller.setActionState(Action.A, keyIsPressed(Key.RightWindows))
  controller.setActionState(Action.B, keyIsPressed(Key.RightAlt))
  controller.setActionState(Action.ShortHop, keyIsPressed(Key.LeftBracket))
  controller.setActionState(Action.FullHop, keyIsPressed(Key.Minus))
  controller.setActionState(Action.Z, keyIsPressed(Key.RightBracket))
  controller.setActionState(Action.L, keyIsPressed(Key.BackSlash))
  controller.setActionState(Action.R, keyIsPressed(Key.SemiColon))
  controller.setActionState(Action.Start, keyIsPressed(Key.Key5))
  controller.update()

proc writeControllerToDolphin() =
  for button in GCCButton: dolphinCtrl.setButton(button, controller.state[button].isPressed)
  for axis in GCCAxis: dolphinCtrl.setAxis(axis, controller.state[axis].value)
  for slider in GCCSlider: dolphinCtrl.setSlider(slider, controller.state[slider].value)
  dolphinCtrl.writeControllerState()

proc main() {.async.} =
  while true:
    onOffToggle = keyIsPressed(Key.Key8)

    if onOffToggle and not onOffTogglePrevious:
      isEnabled = not isEnabled
      setAllKeysBlocked(isEnabled)

    onOffTogglePrevious = onOffToggle

    let frameEnded = stream.poll()

    if isEnabled:
      if stream.isInGame and frameEnded or not stream.isInGame:
        controller.playerState = stream.gameState.playerStates[0]
        updateController()
        writeControllerToDolphin()

    await sleepAsync(1)

asyncCheck runHook()
waitFor main()