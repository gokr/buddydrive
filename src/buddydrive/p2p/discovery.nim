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
import node

export results

type
  DiscoveryError* = object of CatchableError
  
  DiscoveryService* = ref object
    node*: BuddyNode
    started*: bool

const 
  BuddyDriveNamespace* = "/buddydrive"

proc buddyIdToKey(buddyId: string): Key =
  let hash = sha256.digest(buddyId)
  result = @[]
  for b in hash.data:
    result.add(b)

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
    await discovery.node.dht.addProvider(key)
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
    let providers = await discovery.node.dht.getProviders(key)
    echo "Found ", providers.len, " providers"
    
    for provider in providers:
      let peerIdRes = PeerID.init(provider.id)
      if peerIdRes.isOk:
        let peerId = peerIdRes.get()
        var addrs: seq[MultiAddress] = @[]
        for addr in provider.addrs:
          addrs.add(addr)
        result.add((peerId, addrs))
  except Exception as e:
    echo "Error finding buddy on DHT: ", e.msg

proc publishBuddy*(discovery: DiscoveryService, buddyId: string) {.async.} =
  await discovery.announce(buddyId)
