import
  std/asyncdispatch,
  std/times,
  kbdinput,
  slippi,
  dolphincontroller,
  digitalmeleecontroller

var
  isEnabled = true
  onOffToggle = false
  onOffTogglePrevious = false
  userController = GCCState()
  botController = GCCState()
  dolphin = initDolphinController(1, "")
  stream = initSlippiStream()

stream.connect()

setAllKeysBlocked(true)

proc updateUserController() =
  userController.update()

  if keyIsPressed(Key.Key7):
    userController.lButton.isPressed = true
    userController.rButton.isPressed = true
    userController.aButton.isPressed = true
    userController.startButton.isPressed = true

  else:
    userController.xAxis.setValueFromStates(keyIsPressed(Key.A), keyIsPressed(Key.D))
    userController.yAxis.setValueFromStates(keyIsPressed(Key.S), keyIsPressed(Key.W))
    userController.aButton.isPressed = keyIsPressed(Key.E)
    userController.bButton.isPressed = keyIsPressed(Key.Q)
    userController.lButton.isPressed = false
    userController.rButton.isPressed = false
    userController.startButton.isPressed = keyIsPressed(Key.Key5)

var
  buttonChangeTime = cpuTime()
  buttonState = false

proc updateBotController() =
  botController.update()
  if cpuTime() - buttonChangeTime > 0.5:
    buttonState = not buttonState
    buttonChangeTime = cpuTime()
    botController.aButton.isPressed = buttonState

proc writeToDolphin() =
  var useUserController = stream.isPausedOrFrozen or not stream.isInGame

  for key in Key:
    if keyIsPressed(key):
      useUserController = true

  let controller =
    if useUserController: userController
    else: botController

  for button in GCCButton: dolphin.setButton(button, controller[button].isPressed)
  for axis in GCCAxis: dolphin.setAxis(axis, controller[axis].value)
  for slider in GCCSlider: dolphin.setSlider(slider, controller[slider].value)

  dolphin.writeControllerState()

proc main() {.async.} =
  while true:
    onOffToggle = keyIsPressed(Key.Key8)

    if onOffToggle and not onOffTogglePrevious:
      isEnabled = not isEnabled
      setAllKeysBlocked(isEnabled)

    onOffTogglePrevious = onOffToggle

    let frameEnded = stream.poll()

    if isEnabled:
      updateUserController()

      if stream.isInGame and frameEnded:
        updateBotController()

      writeToDolphin()

    await sleepAsync(1)

asyncCheck runHook()
waitFor main()