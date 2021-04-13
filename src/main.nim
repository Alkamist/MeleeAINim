import
  slippistream,
  gccstate,
  dolphincontroller

var
  botController = GCCState()
  dolphin = initDolphinController(1, "")
  slippi = initSlippiStream()

slippi.connect()

proc updateBotController() =
  botController.update()
  botController.aButton.isPressed = slippi.gameState.playerStates[0].actionState == Fall

proc writeToDolphin() =
  for button in GCCButton:
    dolphin.setButton(button, botController[button].isPressed)

  for axis in GCCAxis:
    dolphin.setAxis(axis, botController[axis].value)

  for slider in GCCSlider:
    dolphin.setSlider(slider, botController[slider].value)

  dolphin.writeControllerState()

while true:
  slippi.poll:
    updateBotController()
    writeToDolphin()