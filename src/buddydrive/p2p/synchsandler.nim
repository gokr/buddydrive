import results
import chronos
import libp2p/protocols/protocol
import libp2p/stream/connection
import messages

export results

const SyncCodec* = "/buddydrive/sync/1.0.0"

proc handleSyncImpl(conn: Connection, proto: string): Future[void] {.gcsafe, async: (raises: [CancelledError]).} =
  try:
    var lenBytes: array[4, byte]
    await conn.readExactly(addr lenBytes[0], 4)

    let msgLen = int(lenBytes[0]) shl 24 or
                 int(lenBytes[1]) shl 16 or
                 int(lenBytes[2]) shl 8 or
                 int(lenBytes[3])

    if msgLen <= 0 or msgLen > MaxMessageSize:
      await conn.close()
      return

    var data = newSeq[byte](msgLen)
    await conn.readExactly(addr data[0], msgLen)

    let decoded = decode(data)
    if decoded.isErr:
      await conn.close()
      return

    let msg = decoded.get()
    if msg.kind == msgPing:
      let pong = newPong(msg.timestamp)
      let encoded = encode(pong)
      var pongLen: array[4, byte]
      pongLen[0] = byte(encoded.len shr 24)
      pongLen[1] = byte(encoded.len shr 16)
      pongLen[2] = byte(encoded.len shr 8)
      pongLen[3] = byte(encoded.len)
      await conn.write(@pongLen)
      await conn.write(encoded)

    await conn.close()
  except:
    try:
      await conn.close()
    except:
      discard

proc newSyncHandler*(): LPProtocol =
  let handler = proc (conn: Connection, proto: string): Future[void] {.closure, gcsafe, async: (raises: [CancelledError]).} =
    await handleSyncImpl(conn, proto)
  LPProtocol.new(@[SyncCodec], handler)
