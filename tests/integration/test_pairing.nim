import std/unittest
import std/times
import chronos
import uuids
import libp2p
import libp2p/multiaddress
import libp2p/stream/connection
import libp2p/protocols/protocol
import ../../src/buddydrive/types
import ../../src/buddydrive/config as buddyconfig
import ../../src/buddydrive/p2p/node
import ../../src/buddydrive/p2p/pairing
import ../testutils

proc runPairingTest(): Future[bool] {.async.} =
  let uuid1 = $genUuid()
  let uuid2 = $genUuid()

  var cfg1 = buddyconfig.newAppConfig(newBuddyId(uuid1, "test-node-1"))
  var cfg2 = buddyconfig.newAppConfig(newBuddyId(uuid2, "test-node-2"))

  cfg1.buddies.add(BuddyInfo(
    id: newBuddyId(uuid2, "test-node-2"),
    addresses: @[],
    addedAt: getTime()
  ))

  cfg2.buddies.add(BuddyInfo(
    id: newBuddyId(uuid1, "test-node-1"),
    addresses: @[],
    addedAt: getTime()
  ))

  let node1 = newBuddyNode()
  await node1.start()

  let node2 = newBuddyNode()
  await node2.start()

  var node2Addrs: seq[MultiAddress] = @[]
  for addr in node2.getAddrs():
    node2Addrs.add(addr)

  var receivedHandshake = false
  var receivedBuddyName = ""

  let pairHandler = proc(conn: Connection, proto: string): Future[void] {.closure, gcsafe, async: (raises: [CancelledError]).} =
    try:
      let bc = newBuddyConnection()
      bc.conn = conn
      let success = await bc.acceptHandshake(cfg2)
      if success:
        receivedHandshake = true
        receivedBuddyName = bc.buddyName
      await bc.close()
    except CancelledError:
      raise
    except CatchableError:
      discard

  let pairingProto = LPProtocol.new(@[PairingProtocol], pairHandler)
  await pairingProto.start()
  node2.switch.mount(pairingProto)

  let conn = await node1.switch.dial(node2.peerId, node2Addrs, PairingProtocol)

  let bc = newBuddyConnection()
  bc.conn = conn
  let success = await bc.performHandshake(cfg1)
  if not success:
    await node1.stop()
    await node2.stop()
    return false

  await bc.close()

  await sleepAsync(chronos.milliseconds(500))

  await node1.stop()
  await node2.stop()

  return receivedHandshake and receivedBuddyName == "test-node-1"

suite "Full pairing protocol over libp2p":
  test "two nodes pair via direct libp2p connection":
    runWithStrictFallback:
      check waitFor runPairingTest()
