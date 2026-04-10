import std/[os, times, random]
import chronos
import ../../src/buddydrive/p2p/node
import ../../src/buddydrive/p2p/discovery

proc strictIntegration(): bool =
  getEnv("BUDDYDRIVE_STRICT_INTEGRATION", "") == "1"

proc testUuid(): string =
  randomize()
  $getTime().toUnix() & "-" & $rand(1_000_000_000)

proc testPeerDiscovery() {.async.} =
  echo "============================================================"
  echo "Testing public-DHT buddy discovery"
  echo "============================================================"
  echo ""
  echo "This test does not exchange listen addresses directly."
  echo "Both peers announce and discover only through the DHT."
  echo ""

  let uuid1 = testUuid()
  let uuid2 = testUuid()

  echo "Creating Node 1..."
  let node1 = newBuddyNode()
  await node1.start()
  echo "  Peer ID: ", node1.peerIdStr()

  echo "Creating Node 2..."
  let node2 = newBuddyNode()
  await node2.start()
  echo "  Peer ID: ", node2.peerIdStr()

  let discovery1 = newDiscovery(node1)
  let discovery2 = newDiscovery(node2)
  await discovery1.start()
  await discovery2.start()

  echo ""
  echo "Node 1 buddy ID: ", uuid1
  echo "Node 2 buddy ID: ", uuid2
  echo ""
  echo "Announcing both peers on DHT..."

  await allFutures([
    discovery1.publishBuddy(uuid1),
    discovery2.publishBuddy(uuid2)
  ])

  var found = false
  for attempt in 1..6:
    echo ""
    echo "Lookup attempt ", attempt, "/6..."
    let peers = await discovery1.findBuddy(uuid2)
    if peers.len > 0:
      echo "Found ", peers.len, " provider(s) for node 2"
      for (peerId, addrs) in peers:
        echo "  Peer ID: ", $peerId
        for addr in addrs:
          let addrStr = $addr
          echo "    Address: ", addrStr
      found = true
      break
    echo "No providers yet, waiting 10 seconds..."
    await sleepAsync(chronos.seconds(10))

  echo ""
  echo "Stopping nodes..."
  await discovery1.stop()
  await discovery2.stop()
  await node1.stop()
  await node2.stop()

  if not found:
    let message = "Public DHT discovery did not find the peer; skipping in non-strict mode"
    if strictIntegration():
      quit message, QuitFailure
    echo message
    return

  echo ""
  echo "Public DHT discovery succeeded"

when isMainModule:
  waitFor testPeerDiscovery()
