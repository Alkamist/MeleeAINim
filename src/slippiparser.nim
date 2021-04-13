import
  std/math,
  std/options,
  std/tables,
  melee

export
  math,
  options,
  tables,
  melee

type
  CommandKind* {.pure.} = enum
    Unknown = 0x10,
    EventPayloads = 0x35,
    GameStart = 0x36,
    PreFrameUpdate = 0x37,
    PostFrameUpdate = 0x38,
    GameEnd = 0x39,
    FrameStart = 0x3a,
    ItemUpdate = 0x3b,
    FrameBookend = 0x3c,
    GeckoList = 0x3d,

  SlippiParser* = object
    gameState*: GameState
    command*: CommandKind
    data*: string
    readOffset: int
    numberOfCommands: int
    commandLengths: Table[CommandKind, int]
    extractionCodeVersion: string

proc initSlippiParser*(): SlippiParser =
  result

proc swap(value: uint8): uint8 {.inline.} =
  value

proc swap(value: uint16): uint16 {.inline.} =
  let tmp = cast[array[2, uint8]](value)
  (tmp[0].uint16 shl 8) or tmp[1].uint16

proc swap(value: uint32): uint32 {.inline.} =
  let tmp = cast[array[2, uint16]](value)
  (swap(tmp[0]).uint32 shl 16) or swap(tmp[1])

proc swap(value: uint64): uint64 {.inline.} =
  let tmp = cast[array[2, uint32]](value)
  (swap(tmp[0]).uint64 shl 32) or swap(tmp[1])

proc swap(value: int16): int16 {.inline.} =
  cast[int16](cast[uint16](value).swap())

proc swap(value: int32): int32 {.inline.} =
  cast[int32](cast[uint32](value).swap())

proc swap(value: int64): int64 {.inline.} =
  cast[int64](cast[uint64](value).swap())

proc maybeSwap[T](value: T, enable: bool): T {.inline.} =
  if enable:
    value.swap()
  else:
    value

proc readUint8(slippi: SlippiParser, location: int): uint8 {.inline.} =
  slippi.data[slippi.readOffset + location].uint8

proc readUint16(slippi: SlippiParser, location: int): uint16 {.inline.} =
  cast[ptr uint16](slippi.data[slippi.readOffset + location].unsafeAddr)[].maybeSwap(cpuEndian == littleEndian)

proc readUint32(slippi: SlippiParser, location: int): uint32 {.inline.} =
  cast[ptr uint32](slippi.data[slippi.readOffset + location].unsafeAddr)[].maybeSwap(cpuEndian == littleEndian)

proc readUint64(slippi: SlippiParser, location: int): uint64 {.inline.} =
  cast[ptr uint64](slippi.data[slippi.readOffset + location].unsafeAddr)[].maybeSwap(cpuEndian == littleEndian)

proc readInt8(slippi: SlippiParser, location: int): int8 {.inline.} =
  cast[int8](slippi.readUint8(location))

proc readInt16(slippi: SlippiParser, location: int): int16 {.inline.} =
  cast[int16](slippi.readUint16(location))

proc readInt32(slippi: SlippiParser, location: int): int32 {.inline.} =
  cast[int32](slippi.readUint32(location))

proc readInt64(slippi: SlippiParser, location: int): int64 {.inline.} =
  cast[int64](slippi.readUint64(location))

proc readFloat32(slippi: SlippiParser, location: int): float32 {.inline.} =
  cast[float32](slippi.readUint32(location))

proc readFloat64(slippi: SlippiParser, location: int): float64 {.inline.} =
  cast[float64](slippi.readUint64(location))

proc shiftReadOffsetToNextEvent(slippi: var SlippiParser) {.inline.} =
  slippi.readOffset += slippi.commandLengths[slippi.command] + 1

proc readEventPayloads(slippi: var SlippiParser) =
  let payloadSize = slippi.readUint8(0x1)
  slippi.numberOfCommands = (payloadSize - 1).floorDiv(3).int

  var location = 0x2
  for _ in 0..<slippi.numberOfCommands:
    let commandKind = CommandKind(slippi.readUint8(location))
    slippi.commandLengths[commandKind] = slippi.readUint16(location + 0x1).int
    location += 0x3

  slippi.readOffset += (payloadSize + 1).int

proc readGameStart(slippi: var SlippiParser) =
  slippi.gameState = GameState()

  let
    versionMajor = slippi.readUint8(0x1)
    versionMinor = slippi.readUint8(0x2)
    versionBuild = slippi.readUint8(0x3)

  slippi.extractionCodeVersion = $versionMajor & "." & $versionMinor & "." & $versionBuild

  slippi.gameState.isOnline = GameNetworkKind(slippi.readUint8(0x1a4)) == GameNetworkKind.Online

  template setPlayerAndFollowerStateField(fieldName: untyped, value: untyped): untyped =
    slippi.gameState.playerStates[playerIndex].fieldName = value
    slippi.gameState.followerStates[playerIndex].fieldName = value

  for playerIndex in 0..<4:
    setPlayerAndFollowerStateField(playerKind, PlayerKind(slippi.readUint8(0x66 + (0x24 * playerIndex))))
    setPlayerAndFollowerStateField(costumeId, slippi.readUint8(0x68 + (0x24 * playerIndex)).int)
    setPlayerAndFollowerStateField(cpuLevel, slippi.readUint8(0x74 + (0x24 * playerIndex)).int)

proc readFrameStart(slippi: var SlippiParser) =
  slippi.gameState.frameCount = slippi.readInt32(0x1).int
  slippi.gameState.randomSeed = slippi.readUint32(0x5)

proc readPreFrameUpdate(slippi: var SlippiParser) =
  let
    playerIndex = slippi.readUint8(0x5).int
    isFollower = slippi.readUint8(0x6).bool

  template readPlayerState(state: untyped): untyped =
    state.playerIndex = playerIndex
    state.isFollower = isFollower
    state.frameCount = slippi.readInt32(0x1)
    state.gccState.xAxis.value = slippi.readFloat32(0x19)
    state.gccState.yAxis.value = slippi.readFloat32(0x1d)
    state.gccState.cXAxis.value = slippi.readFloat32(0x21)
    state.gccState.cYAxis.value = slippi.readFloat32(0x25)
    state.gccState.lSlider.value = slippi.readFloat32(0x29)

    let buttonsBitfield = slippi.readUint32(0x2d)
    state.gccState.dLeftButton.isPressed = (0x1 and buttonsBitfield).bool
    state.gccState.dRightButton.isPressed = (0x2 and buttonsBitfield).bool
    state.gccState.dDownButton.isPressed = (0x4 and buttonsBitfield).bool
    state.gccState.dUpButton.isPressed = (0x8 and buttonsBitfield).bool
    state.gccState.zButton.isPressed = (0x10 and buttonsBitfield).bool
    state.gccState.rButton.isPressed = (0x20 and buttonsBitfield).bool
    state.gccState.lButton.isPressed = (0x40 and buttonsBitfield).bool
    state.gccState.aButton.isPressed = (0x100 and buttonsBitfield).bool
    state.gccState.bButton.isPressed = (0x200 and buttonsBitfield).bool
    state.gccState.xButton.isPressed = (0x400 and buttonsBitfield).bool
    state.gccState.yButton.isPressed = (0x800 and buttonsBitfield).bool
    state.gccState.startButton.isPressed = (0x1000 and buttonsBitfield).bool

  if isFollower:
    readPlayerState(slippi.gameState.followerStates[playerIndex])
  else:
    readPlayerState(slippi.gameState.playerStates[playerIndex])

proc readPostFrameUpdate(slippi: var SlippiParser) =
  let
    playerIndex = slippi.readUint8(0x5).int
    isFollower = slippi.readUint8(0x6).bool

  template readPlayerState(state: untyped): untyped =
    state.playerIndex = playerIndex
    state.isFollower = isFollower
    state.frameCount = slippi.readInt32(0x1)
    state.character = Character(slippi.readUint8(0x7))
    state.actionState = ActionState(slippi.readUint16(0x8))
    state.xPosition = slippi.readFloat32(0xa)
    state.yPosition = slippi.readFloat32(0xe)
    state.isFacingRight = slippi.readFloat32(0x12) >= 0.0
    state.percent = slippi.readFloat32(0x16)
    state.shieldSize = slippi.readFloat32(0x1a)
    state.lastHittingAttack = Attack(slippi.readUint8(0x1e))
    state.currentComboCount = slippi.readUint8(0x1f).int
    state.lastHitBy = slippi.readUint8(0x20).int
    state.stocksRemaining = slippi.readUint8(0x21).int
    state.actionFrame = slippi.readFloat32(0x22)
    state.currentComboCount = slippi.readUint8(0x1f).int

    # State bit flags:
    let
      stateBitFlags1 = slippi.readUint8(0x26)
      stateBitFlags2 = slippi.readUint8(0x27)
      stateBitFlags3 = slippi.readUint8(0x28)
      stateBitFlags4 = slippi.readUint8(0x29)
      stateBitFlags5 = slippi.readUint8(0x2a)

    state.reflectIsActive = (0x10 and stateBitFlags1).bool
    state.isInvincible = (0x04 and stateBitFlags2).bool
    state.isFastFalling = (0x08 and stateBitFlags2).bool
    state.isInHitlag = (0x20 and stateBitFlags2).bool
    state.isShielding = (0x80 and stateBitFlags3).bool
    state.isInHitstun = (0x02 and stateBitFlags4).bool
    state.detectionHitboxIsTouchingShield = (0x04 and stateBitFlags4).bool
    state.isPowershielding = (0x20 and stateBitFlags4).bool
    state.isSleeping = (0x10 and stateBitFlags5).bool
    state.isDead = (0x40 and stateBitFlags5).bool
    state.isOffscreen = (0x80 and stateBitFlags5).bool

    state.hitstunRemaining = slippi.readFloat32(0x2b)
    state.isAirborne = slippi.readUint8(0x2f).bool
    state.lastGroundId = slippi.readUint16(0x30).int
    state.jumpsRemaining = slippi.readUint8(0x32).int
    state.lCancelStatus = LCancelStatus(slippi.readUint8(0x33))
    state.hurtboxCollisionState = HurtboxCollisionState(slippi.readUint8(0x34))
    state.selfInducedAirXSpeed = slippi.readFloat32(0x35)
    state.selfInducedYSpeed = slippi.readFloat32(0x39)
    state.attackBasedXSpeed = slippi.readFloat32(0x3d)
    state.attackBasedYSpeed = slippi.readFloat32(0x41)
    state.selfInducedGroundXSpeed = slippi.readFloat32(0x45)
    state.hitlagFramesRemaining = slippi.readFloat32(0x49)

  if isFollower:
    readPlayerState(slippi.gameState.followerStates[playerIndex])
  else:
    readPlayerState(slippi.gameState.playerStates[playerIndex])

proc readGameEnd(slippi: var SlippiParser) =
  slippi.gameState.gameEndMethod = some(GameEndMethod(slippi.readUint8(0x1)))
  slippi.gameState.lrasInitiator = slippi.readInt8(0x2).int

proc checkRawHeader(slippi: var SlippiParser) =
  for i in 1..10:
    let value = slippi.readUint8(i)

    var problem =
      case i:
      of 1: value.char != 'U'
      of 2: value != 3
      of 3: value.char != 'r'
      of 4: value.char != 'a'
      of 5: value.char != 'w'
      of 6: value.char != '['
      of 7: value.char != '$'
      of 8: value.char != 'U'
      of 9: value.char != '#'
      of 10: value.char != 'l'
      else: false

    if problem:
     raise newException(OSError, "Failed to parse raw header.")

proc parseCommand*(slippi: var SlippiParser) =
  slippi.command = CommandKind(slippi.readUint8(0x0))

  case slippi.command:
  of CommandKind.Unknown: discard
  of CommandKind.EventPayloads: slippi.readEventPayloads()
  of CommandKind.GameStart: slippi.readGameStart()
  of CommandKind.PreFrameUpdate: slippi.readPreFrameUpdate()
  of CommandKind.PostFrameUpdate: slippi.readPostFrameUpdate()
  of CommandKind.GameEnd: slippi.readGameEnd()
  of CommandKind.FrameStart: slippi.readFrameStart()
  of CommandKind.ItemUpdate: discard
  of CommandKind.FrameBookend: discard
  of CommandKind.GeckoList: discard

  if slippi.command != CommandKind.EventPayloads:
    slippi.shiftReadOffsetToNextEvent()

template parsePacket*(slippi: var SlippiParser, packet: string, onCommand: untyped): untyped =
  slippi.readOffset = 0x0
  slippi.data = packet

  let dataLength = slippi.data.len

  while slippi.readOffset < dataLength:
    slippi.parseCommand()
    onCommand

template parseFile*(slippi: var SlippiParser, fileName: string, onCommand: untyped): untyped =
  slippi.data = readFile(fileName)
  slippi.checkRawHeader()

  let
    rawHeaderEnd = 15
    rawDataLength = slippi.readInt32(11)
    metaDataLocation = rawHeaderEnd + rawDataLength

  slippi.readOffset = rawHeaderEnd

  while slippi.readOffset < metaDataLocation:
    slippi.parseCommand()
    onCommand

when isMainModule:
  var slippi = initSlippiParser()

  slippi.parseFile("Game_20210405T153836.slp"):
    if slippi.command == CommandKind.FrameBookend:
      echo slippi.gameState.playerStates[0].xPosition