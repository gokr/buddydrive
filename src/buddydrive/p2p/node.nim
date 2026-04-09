import std/times
import results
import chronos
import libp2p
import libp2p/builders
import libp2p/switch
import libp2p/peerid
import libp2p/peerinfo
import libp2p/multiaddress
import libp2p/crypto/crypto
import libp2p/protocols/kademlia
import libp2p/protocols/kademlia/types

export results

type
  BuddyNodeError* = object of CatchableError
  
  BuddyNode* = ref object
    peerId*: PeerID
    peerInfo*: peerinfo.PeerInfo
    switch*: Switch
    dht*: KadDHT
    privKey*: PrivateKey
    pubKey*: PublicKey
    started*: bool
    startTime*: Time

const BuddyDriveProtocol* = "/buddydrive/1.0.0"

proc generateKeyPair*(): (PublicKey, PrivateKey) =
  var rng = newRng()
  let privKey = PrivateKey.random(PKScheme.Secp256k1, rng[]).tryGet()
  let pubKey = privKey.getPublicKey().tryGet()
  result = (pubKey, privKey)

proc newBuddyNode*(privKey: PrivateKey): BuddyNode =
  result = BuddyNode()
  result.started = false
  
  result.pubKey = privKey.getPublicKey().tryGet()
  result.privKey = privKey
  
  let peerId = PeerID.init(result.pubKey).tryGet()
  result.peerId = peerId
  result.peerInfo = PeerInfo.new(privKey)

proc newBuddyNode*(): BuddyNode =
  let (pubKey, privKey) = generateKeyPair()
  result = newBuddyNode(privKey)

proc start*(node: BuddyNode): Future[void] {.async.} =
  if node.started:
    return
  
  var listenAddrs: seq[MultiAddress] = @[]
  try:
    listenAddrs.add(MultiAddress.init("/ip4/0.0.0.0/tcp/0").tryGet())
  except:
    discard
  
  # Build switch with Kademlia DHT
  let switch = SwitchBuilder.new()
    .withRng(newRng())
    .withPrivateKey(node.privKey)
    .withAddresses(listenAddrs)
    .withNoise()
    .withYamux()
    .withTcpTransport()
    .withKademlia()
    .build()
  
  # Start switch (DHT is auto-started by withKademlia)
  await switch.start()
  
  node.switch = switch
  node.peerInfo = switch.peerInfo
  node.peerId = switch.peerInfo.peerId
  
  # Create a DHT reference for our use
  # Note: The DHT is already running, we just create a reference for the API
  node.dht = KadDHT.new(switch, client = true)
  
  node.started = true
  node.startTime = getTime()

proc stop*(node: BuddyNode): Future[void] {.async.} =
  if not node.started:
    return
  
  await node.switch.stop()
  node.started = false

proc getAddrs*(node: BuddyNode): seq[MultiAddress] =
  if not node.started:
    return @[]
  result = node.peerInfo.addrs

proc peerIdStr*(node: BuddyNode): string =
  $node.peerId

proc isRunning*(node: BuddyNode): bool =
  node.started
