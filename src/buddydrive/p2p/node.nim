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
import synchsandler

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

proc getBootstrapNodes(): seq[(PeerID, seq[MultiAddress])] =
  result = @[]
  
  # These are IPFS public bootstrap nodes (TCP only)
  let bootstrapAddrs = [
    ("/ip4/104.131.131.82/tcp/4001", "QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ"),
    ("/ip4/104.236.179.241/tcp/4001", "QmSoLPppuBtQSGwKDZT2M73ULpjvq3sZkgcjNjh3SGwVRy"),
    ("/ip4/128.199.219.111/tcp/4001", "QmSoLnSGccFuZ4JkRN1HD9HXhfBOc8u4BXzAdXbjnpWJ7n"),
    ("/ip4/104.236.76.40/tcp/4001", "QmSoLV4Bbm51jM9C4gDkQW2WWwPz9RwQhcLx9Wz5yLoJhF"),
  ]
  
  for (addrStr, peerIdStr) in bootstrapAddrs:
    try:
      let maRes = MultiAddress.init(addrStr)
      if maRes.isOk:
        let pidRes = PeerID.init(peerIdStr)
        if pidRes.isOk:
          result.add((pidRes.get(), @[maRes.get()]))
    except:
      discard

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
  
  # Build switch with DHT (no bootstrap nodes - peers connect directly)
  # DHT works locally for peer discovery once connected
  let switch = SwitchBuilder.new()
    .withRng(newRng())
    .withPrivateKey(node.privKey)
    .withAddresses(listenAddrs)
    .withNoise()
    .withYamux()
    .withTcpTransport()
    .withKademlia(@[])
    .build()
  
  # Mount the sync protocol handler
  let syncHandler = newSyncHandler()
  switch.mount(syncHandler)
  
  # Start switch
  await switch.start()
  
  node.switch = switch
  node.peerInfo = switch.peerInfo
  node.peerId = switch.peerInfo.peerId
  
  # Find DHT in multistream handlers
  for holder in switch.ms.handlers:
    if holder.protocol of KadDHT:
      node.dht = KadDHT(holder.protocol)
      break
  
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
