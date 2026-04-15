import std/options
import results
import chronos
import libp2p/protocols/protocol
import libp2p/stream/connection
import messages
import protocol

export results

const SyncCodec* = "/buddydrive/sync/1.0.0"

proc handleSyncImpl(conn: Connection, proto: string): Future[void] {.gcsafe, async: (raises: [CancelledError]).} =
  discard proto
  try:
    let msgOpt = await receiveFramedMessage(conn)
    if msgOpt.isNone():
      await conn.close()
      return

    let msg = msgOpt.get()
    if msg.kind == msgPing:
      let pong = newPong(msg.timestamp)
      await sendFramedMessage(conn, pong)

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
