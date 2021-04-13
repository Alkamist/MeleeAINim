import
  std/json,
  std/options,
  std/exitprocs,
  std/base64,
  std/times,
  enet,
  melee,
  slippiparser

export
  json,
  options,
  slippiparser,
  melee

type
  SlippiStream* = object
    isConnected*: bool
    isInGame*: bool
    isPausedOrFrozen*: bool
    nickName*: string
    dolphinVersion*: string
    extractionCodeVersion*: string
    cursor*: int
    parser: SlippiParser
    host: ptr ENetHost
    peer: ptr ENetPeer
    address: ENetAddress
    numberOfCommands: int
    lastFrameTime: Option[float]

proc initSlippiStream*(address = "127.0.0.1",
                       port = 51441): SlippiStream =
  if enet_initialize() != 0:
    echo "Could not initialize ENet."
    quit(QuitFailure)

  addExitProc(proc() = enet_deinitialize())

  discard enet_address_set_host(result.address.addr, address)
  result.address.port = port.cushort
  result.host = enet_host_create(nil, 1, 0, 0, 0)
  result.peer = enet_host_connect(result.host, result.address.addr, 1, 0)

  if result.peer == nil:
    echo "Could not create enet peer."
    quit(QuitFailure)

proc `gameState`*(slippi: SlippiStream): GameState {.inline.} =
  slippi.parser.gameState

proc `command`*(slippi: SlippiStream): CommandKind {.inline.} =
  slippi.parser.command

proc `=destroy`(slippi: var SlippiStream) =
  enet_peer_disconnect(slippi.peer, 0)
  enet_host_destroy(slippi.host)

proc disconnect*(slippi: var SlippiStream) =
  enet_peer_disconnect(slippi.peer, 0)
  slippi.isConnected = false
  slippi.lastFrameTime = none(float)

template poll*(slippi: var SlippiStream, onCommand: untyped): untyped =
  if slippi.lastFrameTime.isSome and cpuTime() - slippi.lastFrameTime.get > 0.05:
    slippi.isPausedOrFrozen = true

  var event: ENetEvent
  discard enet_host_service(slippi.host, event.addr, 0)

  if event.`type` == ENetEventType.Receive:
    let packetData = parseJson(($event.packet.data)[0..<event.packet.dataLength])
    enet_packet_destroy(event.packet)

    if packetData["type"].getStr == "game_event":
      let decodedPacket = decode(packetData["payload"].getStr)
      slippi.parser.parsePacket(decodedPacket):
        case slippi.command:
        of CommandKind.GameStart:
          slippi.isInGame = true
        of CommandKind.FrameStart:
          slippi.isPausedOrFrozen = false
          slippi.lastFrameTime = some(cpuTime())
        of CommandKind.GameEnd:
          slippi.isInGame = false
          slippi.isPausedOrFrozen = false
          slippi.lastFrameTime = none(float)
        else: discard

        onCommand

proc skipToRealTime(slippi: var SlippiStream) =
  let startTime = cpuTime()
  while true:
    slippi.poll(): discard

    if slippi.lastFrameTime.isSome and cpuTime() - slippi.lastFrameTime.get > 0.014:
      echo "Skipped to realtime."
      slippi.isInGame = true
      return

    if cpuTime() - startTime > 1.0 and not slippi.isInGame:
      echo "There is no game in progress."
      slippi.isInGame = false
      return

proc connect*(slippi: var SlippiStream, cursor = none(int)) =
  let
    shouldSkipToRealTime = cursor.isNone
    handshake = $ %* {"type": "connect_request", "cursor": cursor.get(0)}

  var event: ENetEvent

  if (enet_host_service(slippi.host, event.addr, 5000) > 0 and event.`type` == ENetEventType.Connect):
    echo "Slippi stream connected."
    let packet = enet_packet_create(handshake.cstring, (handshake.len + 1).csize_t, ENetPacketFlag.Reliable.cuint)
    discard enet_peer_send(slippi.peer, 0.cuchar, packet)

    discard enet_host_service(slippi.host, event.addr, 5000)

    if event.`type` == ENetEventType.Receive:
      let packetData = parseJson(($event.packet.data)[0..<event.packet.dataLength])
      enet_packet_destroy(event.packet)

      slippi.isConnected = true
      slippi.nickName = packetData["nick"].getStr
      slippi.dolphinVersion = packetData["version"].getStr
      slippi.cursor = packetData["cursor"].getInt

      if shouldSkipToRealTime:
        slippi.skipToRealTime()

    return

  echo "Slippi stream connection failed."
  enet_peer_reset(slippi.peer)

when isMainModule:
  var slippi = initSlippiStream()

  slippi.connect()

  while true:
    slippi.poll:
      if slippi.command == CommandKind.FrameBookend:
        echo slippi.gameState.playerStates[0].xPosition