import std/[times, random]
import chronos
import libp2p
import libp2p/builders
import libp2p/switch
import libp2p/protocols/kademlia
import libp2p/protocols/kademlia/types
import libp2p/protocols/kademlia/find
import ../../src/buddydrive/p2p/node
import ../../src/buddydrive/p2p/discovery

proc testUuid(): string =
  randomize()
  $getTime().toUnix() & "-" & $rand(1_000_000_000)

proc createDhtServer(): Future[(Switch, KadDHT)] {.async.} =
  ## Create a standalone DHT server node that acts as the local
  ## bootstrap / storage node (replaces public IPFS bootstrap peers).
  let switch = SwitchBuilder.new()
    .withRng(newRng())
    .withAddresses(@[MultiAddress.init("/ip4/0.0.0.0/tcp/0").tryGet()])
    .withTcpTransport()
    .withNoise()
    .withYamux()
    .build()

  let kad = KadDHT.new(switch, client = false)
  switch.mount(kad)
  await switch.start()
  return (switch, kad)

proc testPeerDiscovery() {.async.} =
  echo "============================================================"
  echo "Testing DHT buddy discovery (local)"
  echo "============================================================"
  echo ""
  echo "A local DHT server stores provider records."
  echo "Two client nodes announce and discover through it."
  echo ""

  # 1. Start a local DHT server that replaces the public IPFS DHT.
  echo "Creating DHT server..."
  let (serverSwitch, serverDht) = await createDhtServer()
  let serverPeerId = serverSwitch.peerInfo.peerId
  let serverAddrs = serverSwitch.peerInfo.addrs
  let serverBootstrap = @[(serverPeerId, serverAddrs)]
  echo "  DHT server Peer ID: ", serverPeerId
  echo "  DHT server addrs:   ", serverAddrs

  # 2. Create two buddy nodes as DHT clients, bootstrapping from the
  #    local server instead of public IPFS nodes.
  echo ""
  echo "Creating Node 1..."
  let node1 = newBuddyNode(listenPort = 0)
  await node1.start(dhtClient = true, bootstrapPeers = serverBootstrap)
  echo "  Peer ID: ", node1.peerIdStr()

  echo "Creating Node 2..."
  let node2 = newBuddyNode(listenPort = 0)
  await node2.start(dhtClient = true, bootstrapPeers = serverBootstrap)
  echo "  Peer ID: ", node2.peerIdStr()

  # Make sure the server knows about both clients so iterative lookups
  # can discover them.
  serverDht.updatePeers(@[
    (node1.peerId, node1.peerInfo.addrs),
    (node2.peerId, node2.peerInfo.addrs),
  ])

  # Wait for the client-side DHT bootstrap to connect to the server.
  echo ""
  echo "Waiting for DHT bootstrap..."
  await allFutures([
    node1.bootstrapDht(),
    node2.bootstrapDht(),
  ])

  let uuid1 = testUuid()
  let uuid2 = testUuid()

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
    discovery2.publishBuddy(uuid2),
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
          echo "    Address: ", $addr
      found = true
      break
    echo "No providers yet, waiting 2 seconds..."
    await sleepAsync(chronos.seconds(2))

  echo ""
  echo "Stopping nodes..."
  await discovery1.stop()
  await discovery2.stop()
  await node1.stop()
  await node2.stop()
  await serverSwitch.stop()

  if not found:
    quit "DHT discovery did not find the peer", QuitFailure

  echo ""
  echo "DHT discovery succeeded"

when isMainModule:
  waitFor testPeerDiscovery()
