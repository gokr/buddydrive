import std/sequtils
import std/strutils
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
  DhtAnnounceTimeout* = chronos.seconds(45)
  DhtLookupTimeout* = chronos.seconds(45)

proc buddyIdToKey(buddyId: string): Key =
  var data = newSeq[byte](buddyId.len)
  for i, ch in buddyId:
    data[i] = byte(ord(ch))
  result = MultiHash.digest("sha2-256", data).get().toKey()

proc encodePeerRecord(discovery: DiscoveryService): seq[byte] =
  var lines = @[$discovery.node.peerId]
  for addr in discovery.node.getAdvertisedAddrs():
    lines.add($addr)
  let text = lines.join("\n")
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ord(ch))

proc decodePeerRecord(data: seq[byte]): seq[(PeerID, seq[MultiAddress])] =
  var text = newString(data.len)
  for i, b in data:
    text[i] = char(b)
  let lines = text.splitLines().filterIt(it.len > 0)
  if lines.len == 0:
    return @[]

  let peerIdRes = PeerID.init(lines[0])
  if peerIdRes.isErr:
    return @[]

  var addrs: seq[MultiAddress] = @[]
  for line in lines[1..^1]:
    let addrRes = MultiAddress.init(line)
    if addrRes.isOk:
      addrs.add(addrRes.get())

  @[(peerIdRes.get(), addrs)]

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
    let fut = discovery.node.dht.putValue(key, discovery.encodePeerRecord())
    if not await fut.withTimeout(DhtAnnounceTimeout):
      echo "DHT announcement timed out"
      return
    let putRes = await fut
    if putRes.isErr:
      echo "DHT announcement failed: ", putRes.error
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
    let getRes = await discovery.node.dht.getValue(key, quorumOverride = Opt.some(1)).wait(DhtLookupTimeout)
    if getRes.isErr:
      echo "DHT lookup returned no value: ", getRes.error
      return result
    result = decodePeerRecord(getRes.get().value)
    echo "Found ", result.len, " peer record(s)"
  except Exception as e:
    echo "Error finding buddy on DHT: ", e.msg

proc publishBuddy*(discovery: DiscoveryService, buddyId: string) {.async.} =
  await discovery.announce(buddyId)
