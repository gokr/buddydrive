import std/unittest
import std/[os, times, random]
import chronos
import ../../src/buddydrive/p2p/node
import ../../src/buddydrive/p2p/discovery
import ../testutils

proc testUuid(): string =
  randomize()
  $getTime().toUnix() & "-" & $rand(1_000_000_000)

suite "Public DHT buddy discovery":
  test "two nodes discover each other via public DHT":
    let uuid1 = testUuid()
    let uuid2 = testUuid()

    let node1 = newBuddyNode()
    waitFor node1.start()

    let node2 = newBuddyNode()
    waitFor node2.start()

    let discovery1 = newDiscovery(node1)
    let discovery2 = newDiscovery(node2)
    waitFor discovery1.start()
    waitFor discovery2.start()

    waitFor allFutures([
      discovery1.publishBuddy(uuid1),
      discovery2.publishBuddy(uuid2)
    ])

    var found = false
    for attempt in 1..3:
      let peers = waitFor discovery1.findBuddy(uuid2)
      if peers.len > 0:
        found = true
        break
      waitFor sleepAsync(chronos.seconds(5))

    waitFor discovery1.stop()
    waitFor discovery2.stop()
    waitFor node1.stop()
    waitFor node2.stop()

    if not found:
      if strictIntegration():
        fail()
      else:
        skip()
    else:
      check found
