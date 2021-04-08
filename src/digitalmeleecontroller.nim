import button
import analogaxis
import analogslider
import gccstate
import melee

export gccstate


type
  Action* {.pure.} = enum
    Left,
    Right,
    Down,
    Up,
    A,
    B,
    ShortHop,
    FullHop,
    Z,
    L,
    R,
    Start,

  DigitalMeleeController* = object
    actions*: array[Action, Button]
    state*: GCCState
    playerState*: PlayerState
    shortHopStartingFrame: int
    isShortHopping: bool

proc initDigitalMeleeController*(): DigitalMeleeController =
  result

proc updateActions(controller: var DigitalMeleeController) =
  for action in controller.actions.mitems:
    action.update()

proc setActionState*(controller: var DigitalMeleeController, action: Action, state: bool) =
  controller.actions[action].isPressed = state

proc processAutoLCancel(controller: var DigitalMeleeController) =
  let action = controller.playerState.actionState

  if action == ActionState.ForwardAir or
     action == ActionState.BackAir or
     action == ActionState.DownAir or
     action == ActionState.UpAir or
     action == ActionState.NeutralAir:
    let frameAlternator = controller.playerState.frameCount mod 2 == 0

    if frameAlternator:
      controller.state.lSlider.value = 122.0 / 255.0
    else:
      controller.state.lSlider.value = 0

proc executeShortHop(controller: var DigitalMeleeController) =
  controller.isShortHopping = true
  controller.shortHopStartingFrame = controller.playerState.frameCount

proc processShortHop(controller: var DigitalMeleeController) =
  if controller.isShortHopping:
    let frameCount = controller.playerState.frameCount - controller.shortHopStartingFrame

    controller.state.yButton.isPressed = true

    if frameCount >= 2:
      controller.state.yButton.isPressed = false
      controller.isShortHopping = false

proc update*(controller: var DigitalMeleeController) =
  controller.state.xAxis.setValueFromStates(controller.actions[Action.Left].isPressed,
                                            controller.actions[Action.Right].isPressed)
  controller.state.yAxis.setValueFromStates(controller.actions[Action.Down].isPressed,
                                            controller.actions[Action.Up].isPressed)

  controller.state.lSlider.value = 0
  controller.state.yButton.isPressed = false

  controller.state.aButton.isPressed = controller.actions[Action.A].isPressed
  controller.state.bButton.isPressed = controller.actions[Action.B].isPressed
  controller.state.zButton.isPressed = controller.actions[Action.Z].isPressed
  controller.state.lButton.isPressed = controller.actions[Action.L].isPressed
  controller.state.rButton.isPressed = controller.actions[Action.R].isPressed
  controller.state.startButton.isPressed = controller.actions[Action.Start].isPressed

  if controller.actions[Action.ShortHop].justPressed: controller.executeShortHop()
  controller.processShortHop()
  controller.processAutoLCancel()

  controller.updateActions()