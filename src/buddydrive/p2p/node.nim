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
import libp2p/protocols/kademlia/find
import synchsandler
import ../types

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
    listenPort*: int
    announceAddrs*: seq[MultiAddress]
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

proc newBuddyNode*(
    privKey: PrivateKey,
    listenPort: int = DefaultP2PPort,
    announceAddrs: seq[MultiAddress] = @[]
): BuddyNode =
  result = BuddyNode()
  result.started = false
  
  result.pubKey = privKey.getPublicKey().tryGet()
  result.privKey = privKey
  result.listenPort = listenPort
  result.announceAddrs = announceAddrs
  
  let peerId = PeerID.init(result.pubKey).tryGet()
  result.peerId = peerId
  result.peerInfo = PeerInfo.new(privKey)

proc newBuddyNode*(): BuddyNode =
  let (_, privKey) = generateKeyPair()
  result = newBuddyNode(privKey)

proc newBuddyNode*(listenPort: int, announceAddrs: seq[MultiAddress] = @[]): BuddyNode =
  let (_, privKey) = generateKeyPair()
  result = newBuddyNode(privKey, listenPort, announceAddrs)

proc bootstrapDht*(node: BuddyNode): Future[void] {.async.}

proc start*(node: BuddyNode, dhtClient: bool = true,
            bootstrapPeers: seq[(PeerID, seq[MultiAddress])] = @[]): Future[void] {.async.} =
  if node.started:
    return

  var listenAddrs: seq[MultiAddress] = @[]
  try:
    listenAddrs.add(MultiAddress.init("/ip4/0.0.0.0/tcp/" & $node.listenPort).tryGet())
  except:
    discard

  let bootstrapNodes = if bootstrapPeers.len > 0: bootstrapPeers
                        else: getBootstrapNodes()

  let switch = SwitchBuilder.new()
    .withRng(newRng())
    .withPrivateKey(node.privKey)
    .withAddresses(listenAddrs)
    .withNoise()
    .withYamux()
    .withTcpTransport()
    .build()

  # Mount the sync protocol handler
  let syncHandler = newSyncHandler()
  switch.mount(syncHandler)

  # Create and optionally mount the DHT before starting the switch
  node.dht = KadDHT.new(switch, bootstrapNodes = bootstrapNodes, client = dhtClient)
  if not dhtClient:
    switch.mount(node.dht)

  # Start switch (also starts mounted protocols)
  await switch.start()

  node.switch = switch
  node.peerInfo = switch.peerInfo
  node.peerId = switch.peerInfo.peerId

  node.dht.updatePeers(bootstrapNodes)

  node.started = true
  node.startTime = getTime()
  if dhtClient:
    asyncSpawn node.bootstrapDht()

proc bootstrapDht*(node: BuddyNode): Future[void] {.async.} =
  if node.dht == nil:
    return

  try:
    let fut = node.dht.bootstrap()
    if not await fut.withTimeout(chronos.seconds(45)):
      echo "DHT bootstrap timed out"
      return
    echo "DHT bootstrap completed"
  except Exception as e:
    echo "DHT bootstrap failed: ", e.msg

proc stop*(node: BuddyNode): Future[void] {.async.} =
  if not node.started:
    return
  
  await node.switch.stop()
  node.started = false

proc getAddrs*(node: BuddyNode): seq[MultiAddress] =
  if not node.started:
    return @[]
  result = node.peerInfo.addrs

proc getAdvertisedAddrs*(node: BuddyNode): seq[MultiAddress] =
  if node.announceAddrs.len > 0:
    return node.announceAddrs
  node.getAddrs()

proc peerIdStr*(node: BuddyNode): string =
  $node.peerId

proc isRunning*(node: BuddyNode): bool =
  node.started
