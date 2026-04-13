import std/sets
import results
import chronos
import libp2p
import libp2p/switch
import libp2p/peerid
import libp2p/peerinfo
import libp2p/multiaddress
import libp2p/multihash
import libp2p/protocols/kademlia
import libp2p/protocols/kademlia/types
import libp2p/protocols/kademlia/provider
import node

export results

type
  DiscoveryError* = object of CatchableError
  
  DiscoveryService* = ref object
    node*: BuddyNode
    started*: bool

const
  BuddyDriveNamespace* = "/buddydrive"
  DhtAnnounceTimeout* = chronos.seconds(120)
  DhtLookupTimeout* = chronos.seconds(120)
  AnnounceRetryInterval* = chronos.seconds(300)

proc buddyIdToKey(buddyId: string): Key =
  var data = newSeq[byte](buddyId.len)
  for i, ch in buddyId:
    data[i] = byte(ord(ch))
  result = MultiHash.digest("sha2-256", data).get().toKey()

proc newDiscovery*(node: BuddyNode): DiscoveryService =
  result = DiscoveryService()
  result.node = node
  result.started = false

proc start*(discovery: DiscoveryService) {.async.} =
  if discovery.started:
    return
  
  discovery.started = true

proc stop*(discovery: DiscoveryService) {.async.} =
  discovery.started = false

proc announce*(discovery: DiscoveryService, buddyId: string) {.async.} =
  if not discovery.started:
    raise newException(DiscoveryError, "Discovery not started")

  if discovery.node.dht == nil:
    echo "DHT not available for announcement"
    return

  let key = buddyIdToKey(buddyId)
  echo "Announcing buddy ID on DHT: ", buddyId

  try:
    let fut = discovery.node.dht.addProvider(key)
    if not await fut.withTimeout(DhtAnnounceTimeout):
      echo "DHT announcement timed out"
      return
    echo "Successfully announced on DHT"
  except Exception as e:
    echo "Error announcing on DHT: ", e.msg

proc findBuddy*(discovery: DiscoveryService, buddyId: string): Future[seq[(PeerID, seq[MultiAddress])]] {.async.} =
  result = @[]

  if not discovery.started:
    return result

  if discovery.node.dht == nil:
    echo "DHT not available for discovery"
    return result

  let key = buddyIdToKey(buddyId)
  echo "Searching DHT for buddy: ", buddyId

  try:
    let providers = await discovery.node.dht.getProviders(key).wait(DhtLookupTimeout)
    if providers.len == 0:
      echo "DHT lookup returned no providers"
      return result
    for provider in providers:
      let pidRes = PeerID.init(provider.id)
      if pidRes.isOk:
        result.add((pidRes.get(), provider.addrs))
    echo "Found ", result.len, " peer record(s)"
  except Exception as e:
    echo "Error finding buddy on DHT: ", e.msg

proc publishBuddy*(discovery: DiscoveryService, buddyId: string) {.async.} =
  await discovery.announce(buddyId)

proc publishBuddyLoop*(discovery: DiscoveryService, buddyId: string) {.async.} =
  ## Announce on the DHT and re-announce periodically.
  ## Provider records expire (default 30 min), so continuous
  ## re-announcement is required to stay discoverable.
  while discovery.started:
    await discovery.announce(buddyId)
    await sleepAsync(AnnounceRetryInterval)
