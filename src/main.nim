import
  slippi,
  gccstate,
  dolphincontroller

var
  botController = GCCState()
  dolphin = initDolphinController(1, "")
  stream = initSlippiStream()

stream.connect()

proc updateBotController() =
  botController.update()
  botController.aButton.isPressed = stream.gameState.playerStates[0].actionState == Fall

proc writeToDolphin() =
  for button in GCCButton:
    dolphin.setButton(button, botController[button].isPressed)

  for axis in GCCAxis:
    dolphin.setAxis(axis, botController[axis].value)

  for slider in GCCSlider:
    dolphin.setSlider(slider, botController[slider].value)

  dolphin.writeControllerState()

while true:
  if stream.poll():
    updateBotController()
    writeToDolphin()