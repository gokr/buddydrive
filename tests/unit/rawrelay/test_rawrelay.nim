import std/[algorithm, strutils, unittest]
import ../../../src/buddydrive/p2p/rawrelay

proc sortedCopy(values: seq[string]): seq[string] =
  result = values
  result.sort()

suite "rawrelay helpers":
  test "relayAddrsForRegion falls back to builtin local relay":
    let cache = initRelayListCache()
    let relays = relayAddrsForRegion(cache, "", "local")
    check relays == @["/ip4/127.0.0.1/tcp/41722"]

  test "relayAddrsForRegion normalizes region":
    let cache = initRelayListCache()
    let relays = relayAddrsForRegion(cache, "", " EU ")
    check relays.len == 3
    check relays[0].contains("relay-eu-")

  test "relayAddrsForRegion returns empty for unknown region":
    let cache = initRelayListCache()
    check relayAddrsForRegion(cache, "", "unknown-region").len == 0

  test "orderedRelayAddrs is deterministic for same token":
    let cache = initRelayListCache()
    let ordered1 = orderedRelayAddrs(cache, "", "eu", "swift-eagle")
    let ordered2 = orderedRelayAddrs(cache, "", "eu", "swift-eagle")
    check ordered1 == ordered2

  test "orderedRelayAddrs preserves relay set":
    let cache = initRelayListCache()
    let ordered = orderedRelayAddrs(cache, "", "eu", "swift-eagle")
    let builtin = relayAddrsForRegion(cache, "", "eu")
    check sortedCopy(ordered) == sortedCopy(builtin)

  test "orderedRelayAddrs returns empty when no relays available":
    let cache = initRelayListCache()
    check orderedRelayAddrs(cache, "", "unknown-region", "token").len == 0
