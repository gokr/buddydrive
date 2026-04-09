import std/os
import std/strutils
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
import ../../src/buddydrive/p2p/messages

type
  TestPairingHandler = ref object of LPProtocol
    config: types.AppConfig
    receivedHandshake: bool
    buddyId: string
    buddyName: string

method init(proto: TestPairingHandler) =
  proto.codec = PairingProtocol

method dial(proto: TestPairingHandler, conn: Connection) {.async.} =
  discard

method handle(proto: TestPairingHandler, conn: Connection) {.async.} =
  echo "Node 2: Incoming connection!"
  
  let bc = newBuddyConnection()
  bc.conn = conn
  
  let success = await bc.acceptHandshake(proto.config)
  if success:
    echo "Node 2: Handshake successful!"
    echo "  Buddy ID: ", bc.buddyId
    echo "  Buddy Name: ", bc.buddyName
    proto.receivedHandshake = true
    proto.buddyId = bc.buddyId
    proto.buddyName = bc.buddyName
  else:
    echo "Node 2: Handshake failed - buddy not in list"
  
  await bc.close()

proc testPairingProtocol() {.async.} =
  echo "=" & "=".repeat(60)
  echo "Testing Buddy Pairing Protocol"
  echo "=" & "=".repeat(60)
  echo ""
  
  let dir1 = "/tmp/buddydrive_pairing_test1"
  let dir2 = "/tmp/buddydrive_pairing_test2"
  removeDir(dir1)
  removeDir(dir2)
  createDir(dir1)
  createDir(dir2)
  
  let uuid1 = $genUuid()
  let uuid2 = $genUuid()
  
  echo "Buddy IDs:"
  echo "  Node 1: ", uuid1, " (test-node-1)"
  echo "  Node 2: ", uuid2, " (test-node-2)"
  echo ""
  
  var cfg1 = buddyconfig.newAppConfig(newBuddyId(uuid1, "test-node-1"))
  var cfg2 = buddyconfig.newAppConfig(newBuddyId(uuid2, "test-node-2"))
  
  cfg1.buddies.add(BuddyInfo(
    id: newBuddyId(uuid2, "test-node-2"),
    publicKey: "",
    addresses: @[],
    addedAt: getTime()
  ))
  
  cfg2.buddies.add(BuddyInfo(
    id: newBuddyId(uuid1, "test-node-1"),
    publicKey: "",
    addresses: @[],
    addedAt: getTime()
  ))
  
  echo "Starting Node 1..."
  let node1 = newBuddyNode()
  await node1.start()
  echo "  Peer ID: ", node1.peerIdStr()
  
  var node1Addrs: seq[MultiAddress] = @[]
  for addr in node1.getAddrs():
    node1Addrs.add(addr)
    let addrStr = multiaddress.toString(addr)
    if addrStr.isOk:
      echo "  Address: ", addrStr.get()
  
  echo ""
  echo "Starting Node 2..."
  let node2 = newBuddyNode()
  await node2.start()
  echo "  Peer ID: ", node2.peerIdStr()
  
  var node2Addrs: seq[MultiAddress] = @[]
  for addr in node2.getAddrs():
    node2Addrs.add(addr)
    let addrStr = multiaddress.toString(addr)
    if addrStr.isOk:
      echo "  Address: ", addrStr.get()
  
  echo ""
  echo "Setting up pairing handler on Node 2..."
  let handler = TestPairingHandler(config: cfg2, receivedHandshake: false)
  try:
    handler.init()
  except:
    discard
  node2.switch.mount(handler)
  
  echo ""
  echo "Testing pairing protocol..."
  echo ""
  
  echo "Node 1: Connecting to Node 2..."
  try:
    let conn = await node1.switch.dial(node2.peerId, node2Addrs, PairingProtocol)
    echo "Node 1: Connected!"
    
    let bc = newBuddyConnection()
    bc.conn = conn
    
    let success = await bc.performHandshake(cfg1)
    if success:
      echo "Node 1: Handshake successful!"
      echo "  Buddy ID: ", bc.buddyId
      echo "  Buddy Name: ", bc.buddyName
    else:
      echo "Node 1: Handshake failed - buddy not in list"
    
    await bc.close()
  except Exception as e:
    echo "Node 1: Connection error: ", e.msg
  
  await sleepAsync(chronos.milliseconds(500))
  
  echo ""
  if handler.receivedHandshake:
    echo "SUCCESS: Both nodes completed pairing!"
    echo "  Node 2 received buddy: ", handler.buddyName, " (", handler.buddyId.shortId(), ")"
  else:
    echo "ERROR: Node 2 did not receive handshake"
  
  echo ""
  echo "Stopping nodes..."
  await node1.stop()
  await node2.stop()
  
  echo ""
  echo "Test complete!"
  echo ""
  echo "Cleanup:"
  echo "  rm -rf ", dir1, " ", dir2

when isMainModule:
  waitFor testPairingProtocol()
