import std/unittest
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
import ../testutils

proc testUuid(): string =
  randomize()
  $getTime().toUnix() & "-" & $rand(1_000_000_000)

proc createDhtServer(): Future[(Switch, KadDHT)] {.async.} =
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

suite "DHT buddy discovery (local DHT)":
  test "two nodes discover each other via local DHT server":
    let (serverSwitch, serverDht) = waitFor createDhtServer()
    let serverPeerId = serverSwitch.peerInfo.peerId
    let serverAddrs = serverSwitch.peerInfo.addrs
    let serverBootstrap = @[(serverPeerId, serverAddrs)]

    let node1 = newBuddyNode(listenPort = 0)
    waitFor node1.start(dhtClient = true, bootstrapPeers = serverBootstrap)

    let node2 = newBuddyNode(listenPort = 0)
    waitFor node2.start(dhtClient = true, bootstrapPeers = serverBootstrap)

    serverDht.updatePeers(@[
      (node1.peerId, node1.peerInfo.addrs),
      (node2.peerId, node2.peerInfo.addrs),
    ])

    waitFor allFutures([
      node1.bootstrapDht(),
      node2.bootstrapDht(),
    ])

    let uuid1 = testUuid()
    let uuid2 = testUuid()

    let discovery1 = newDiscovery(node1)
    let discovery2 = newDiscovery(node2)
    waitFor discovery1.start()
    waitFor discovery2.start()

    waitFor allFutures([
      discovery1.publishBuddy(uuid1),
      discovery2.publishBuddy(uuid2),
    ])

    var found = false
    for attempt in 1..6:
      let peers = waitFor discovery1.findBuddy(uuid2)
      if peers.len > 0:
        found = true
        break
      waitFor sleepAsync(chronos.seconds(2))

    waitFor discovery1.stop()
    waitFor discovery2.stop()
    waitFor node1.stop()
    waitFor node2.stop()
    waitFor serverSwitch.stop()

    check found
