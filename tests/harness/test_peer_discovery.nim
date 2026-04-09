import std/os
import std/strutils
import chronos
import uuids
import libp2p
import libp2p/multiaddress
import ../../src/buddydrive/types
import ../../src/buddydrive/config as buddyconfig
import ../../src/buddydrive/p2p/node
import ../../src/buddydrive/p2p/discovery
import ../../src/buddydrive/p2p/protocol
import ../../src/buddydrive/p2p/messages

proc testPeerDiscovery() {.async.} =
  echo "=" & "=".repeat(60)
  echo "Testing P2P Peer Discovery and Direct Connection"
  echo "=" & "=".repeat(60)
  echo ""
  
  # Clean up test dirs
  let dir1 = "/tmp/buddydrive_peer_test1"
  let dir2 = "/tmp/buddydrive_peer_test2"
  removeDir(dir1)
  removeDir(dir2)
  createDir(dir1)
  createDir(dir2)
  
  echo "Creating Node 1..."
  let uuid1 = $genUuid()
  let cfg1 = buddyconfig.newAppConfig(newBuddyId(uuid1, "test-node-1"))
  try:
    buddyconfig.saveConfig(cfg1)
  except:
    discard
  
  echo "Creating Node 2..."
  let uuid2 = $genUuid()
  let cfg2 = buddyconfig.newAppConfig(newBuddyId(uuid2, "test-node-2"))
  try:
    buddyconfig.saveConfig(cfg2)
  except:
    discard
  
  echo ""
  echo "Buddy IDs:"
  echo "  Node 1: ", uuid1
  echo "  Node 2: ", uuid2
  echo ""
  
  # Create and start nodes
  echo "Starting Node 1..."
  let node1 = newBuddyNode()
  await node1.start()
  echo "  Peer ID: ", node1.peerIdStr()
  var node1Addrs: seq[string] = @[]
  for addr in node1.getAddrs():
    let addrStr = multiaddress.toString(addr)
    if addrStr.isOk:
      node1Addrs.add(addrStr.get())
      echo "  Address: ", addrStr.get()
  
  echo ""
  echo "Starting Node 2..."
  let node2 = newBuddyNode()
  await node2.start()
  echo "  Peer ID: ", node2.peerIdStr()
  var node2Addrs: seq[string] = @[]
  for addr in node2.getAddrs():
    let addrStr = multiaddress.toString(addr)
    if addrStr.isOk:
      node2Addrs.add(addrStr.get())
      echo "  Address: ", addrStr.get()
  
  echo ""
  
  # Test direct connection (since we know the addresses)
  echo "Testing direct connection from Node 1 to Node 2..."
  
  # Parse addresses
  var peer2Addrs: seq[MultiAddress] = @[]
  for addrStr in node2Addrs:
    let maRes = MultiAddress.init(addrStr)
    if maRes.isOk:
      peer2Addrs.add(maRes.get())
  
  if peer2Addrs.len > 0:
    try:
      let conn = await node1.switch.dial(node2.peerId, peer2Addrs, "/ipfs/id/1.0.0")
      echo "Connected successfully!"
      echo "  Remote peer: ", $conn.peerId
      await conn.close()
      echo "Connection closed cleanly"
    except Exception as e:
      echo "Connection failed: ", e.msg
  else:
    echo "No valid addresses for Node 2"
  
  echo ""
  
  # Now test DHT discovery
  let discovery1 = newDiscovery(node1)
  let discovery2 = newDiscovery(node2)
  
  await discovery1.start()
  await discovery2.start()
  
  echo "Announcing Node 1 on DHT..."
  await discovery1.publishBuddy(uuid1)
  
  echo "Announcing Node 2 on DHT..."
  await discovery2.publishBuddy(uuid2)
  
  echo ""
  echo "Waiting 3 seconds for DHT propagation..."
  await sleepAsync(chronos.seconds(3))
  
  # Node 1 searches for Node 2
  echo ""
  echo "Node 1 searching for Node 2 via DHT..."
  let peers = await discovery1.findBuddy(uuid2)
  
  if peers.len > 0:
    echo "Found ", peers.len, " peer(s)!"
    for (peerId, addrs) in peers:
      echo "  Peer ID: ", $peerId
      for addr in addrs:
        let addrStr = multiaddress.toString(addr)
        if addrStr.isOk:
          echo "    Address: ", addrStr.get()
  else:
    echo "No peers found via DHT (expected for local testing without bootstrap nodes)"
  
  echo ""
  echo "Stopping nodes..."
  await discovery1.stop()
  await discovery2.stop()
  await node1.stop()
  await node2.stop()
  
  echo ""
  echo "Test complete!"
  echo ""
  echo "Cleanup:"
  echo "  rm -rf ", dir1, " ", dir2

when isMainModule:
  waitFor testPeerDiscovery()
