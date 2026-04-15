import std/times
import std/options
import results
import chronos
import libp2p
import libp2p/stream/connection
import messages

export results

type
  ProtocolError* = object of CatchableError

  SyncProtocol* = ref object

const
  ReadTimeout* = chronos.seconds(30)
  WriteTimeout* = chronos.seconds(30)

proc newSyncProtocol*(): SyncProtocol =
  result = SyncProtocol()

proc newSyncProtocol*[T](node: T): SyncProtocol =
  discard node
  result = SyncProtocol()

proc sendFramedMessage*(conn: Connection, msg: ProtocolMessage): Future[void] {.async.} =
  let encoded = encode(msg)
  var lenBytes: array[4, byte]
  lenBytes[0] = byte(encoded.len shr 24)
  lenBytes[1] = byte(encoded.len shr 16)
  lenBytes[2] = byte(encoded.len shr 8)
  lenBytes[3] = byte(encoded.len)

  await conn.write(@lenBytes)
  await conn.write(encoded)

proc receiveFramedMessage*(conn: Connection): Future[Option[ProtocolMessage]] {.async.} =
  try:
    var lenBytes: array[4, byte]
    await conn.readExactly(addr lenBytes[0], 4)

    let msgLen = int(lenBytes[0]) shl 24 or
                 int(lenBytes[1]) shl 16 or
                 int(lenBytes[2]) shl 8 or
                 int(lenBytes[3])

    if msgLen > MaxMessageSize or msgLen <= 0:
      return none(ProtocolMessage)

    var data = newSeq[byte](msgLen)
    await conn.readExactly(addr data[0], msgLen)

    let decoded = decode(data)
    if decoded.isErr:
      return none(ProtocolMessage)

    return some(decoded.get())
  except:
    return none(ProtocolMessage)

proc sendMessage*(protocol: SyncProtocol, conn: Connection, msg: ProtocolMessage): Future[void] {.async.} =
  discard protocol
  await sendFramedMessage(conn, msg)

proc receiveMessage*(protocol: SyncProtocol, conn: Connection): Future[Option[ProtocolMessage]] {.async.} =
  discard protocol
  return await receiveFramedMessage(conn)

proc sendPing*(protocol: SyncProtocol, conn: Connection): Future[int64] {.async.} =
  let ping = newPing()
  await protocol.sendMessage(conn, ping)
  
  let pongOpt = await protocol.receiveMessage(conn)
  if pongOpt.isNone or pongOpt.get().kind != msgPong:
    raise newException(ProtocolError, "Did not receive pong")
  
  let now = getTime().toUnix()
  result = now - pongOpt.get().pingTimestamp
