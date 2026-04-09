import std/times
import results
import chronos
import libp2p
import libp2p/stream/connection
import node
import messages
import ../types

export results

type
  PairingError* = object of CatchableError
  
  PairingState* = enum
    psNone
    psHandshake
    psExchangingId
    psVerifying
    psReady
    psError
  
  BuddyConnection* = ref object
    buddyId*: string
    buddyName*: string
    peerId*: string
    conn*: Connection
    state*: PairingState
    lastActivity*: Time

const
  PairingProtocol* = "/buddydrive/pairing/1.0.0"
  HandshakeTimeout* = chronos.seconds(30)

proc newBuddyConnection*(): BuddyConnection =
  result = BuddyConnection()
  result.state = psNone
  result.lastActivity = getTime()

proc sendBuddyId*(bc: BuddyConnection, buddyId: string, buddyName: string): Future[void] {.async.} =
  let msg = ProtocolMessage(
    kind: msgFileList,
    folderName: "BUDDYDRIVE_PAIRING",
    files: @[FileEntry(
      path: buddyId,
      size: 0,
      mtime: getTime().toUnix(),
      hash: buddyName
    )]
  )
  let encoded = encode(msg)
  var lenBytes: array[4, byte]
  lenBytes[0] = byte(encoded.len shr 24)
  lenBytes[1] = byte(encoded.len shr 16)
  lenBytes[2] = byte(encoded.len shr 8)
  lenBytes[3] = byte(encoded.len)
  
  await bc.conn.write(@lenBytes)
  await bc.conn.write(encoded)
  bc.lastActivity = getTime()

proc receiveBuddyId*(bc: BuddyConnection): Future[Option[(string, string)]] {.async.} =
  try:
    var lenBytes: array[4, byte]
    await bc.conn.readExactly(addr lenBytes[0], 4)
    
    let msgLen = int(lenBytes[0]) shl 24 or
                 int(lenBytes[1]) shl 16 or
                 int(lenBytes[2]) shl 8 or
                 int(lenBytes[3])
    
    if msgLen > MaxMessageSize or msgLen <= 0:
      return none((string, string))
    
    var data = newSeq[byte](msgLen)
    await bc.conn.readExactly(addr data[0], msgLen)
    
    let decoded = decode(data)
    if decoded.isErr:
      return none((string, string))
    
    let msg = decoded.get()
    if msg.kind != msgFileList or msg.folderName != "BUDDYDRIVE_PAIRING":
      return none((string, string))
    
    if msg.files.len != 1:
      return none((string, string))
    
    let buddyId = msg.files[0].path
    let buddyName = msg.files[0].hash
    bc.buddyId = buddyId
    bc.buddyName = buddyName
    bc.lastActivity = getTime()
    
    return some((buddyId, buddyName))
  except:
    return none((string, string))

proc verifyBuddy*(bc: BuddyConnection, config: AppConfig): bool =
  for buddy in config.buddies:
    if buddy.id.uuid == bc.buddyId:
      bc.buddyName = buddy.id.name
      return true
  return false

proc performHandshake*(bc: BuddyConnection, config: AppConfig): Future[bool] {.async.} =
  bc.state = psHandshake
  
  try:
    await bc.sendBuddyId(config.buddy.uuid, config.buddy.name)
    
    let buddyInfoOpt = await bc.receiveBuddyId()
    if buddyInfoOpt.isNone:
      bc.state = psError
      return false
    
    let (buddyId, buddyName) = buddyInfoOpt.get()
    bc.buddyId = buddyId
    bc.buddyName = buddyName
    
    bc.state = psVerifying
    
    if not bc.verifyBuddy(config):
      bc.state = psError
      return false
    
    bc.state = psReady
    return true
  except:
    bc.state = psError
    return false

proc acceptHandshake*(bc: BuddyConnection, config: AppConfig): Future[bool] {.async.} =
  bc.state = psHandshake
  
  try:
    let buddyInfoOpt = await bc.receiveBuddyId()
    if buddyInfoOpt.isNone:
      bc.state = psError
      return false
    
    let (buddyId, buddyName) = buddyInfoOpt.get()
    bc.buddyId = buddyId
    bc.buddyName = buddyName
    
    bc.state = psVerifying
    
    if not bc.verifyBuddy(config):
      bc.state = psError
      return false
    
    await bc.sendBuddyId(config.buddy.uuid, config.buddy.name)
    
    bc.state = psReady
    return true
  except:
    bc.state = psError
    return false

proc isConnected*(bc: BuddyConnection): bool =
  bc.state == psReady and bc.conn != nil

proc close*(bc: BuddyConnection) {.async.} =
  if bc.conn != nil:
    try:
      await bc.conn.close()
    except:
      discard
  bc.state = psNone
  bc.conn = nil
