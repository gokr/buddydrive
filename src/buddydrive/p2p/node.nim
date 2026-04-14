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
import libp2p/nameresolving/dnsresolver
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

  let bootstrapAddrs = [
    ("/dns4/sg1.bootstrap.libp2p.io/tcp/4001", "QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt"),
    ("/dns4/am6.bootstrap.libp2p.io/tcp/4001", "QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb"),
    ("/dns4/sv15.bootstrap.libp2p.io/tcp/4001", "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"),
    ("/dns4/ny5.bootstrap.libp2p.io/tcp/4001", "QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa"),
    ("/ip4/15.235.144.210/tcp/4001", "QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt"),
    ("/ip4/54.38.47.166/tcp/4001", "QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb"),
    ("/ip4/147.135.44.132/tcp/4001", "QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"),
    ("/ip4/51.81.93.51/tcp/4001", "QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa"),
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
    .withNameResolver(DnsResolver.new(@[initTAddress("8.8.8.8", 53.Port), initTAddress("1.1.1.1", 53.Port)]))
    .build()

  node.dht = KadDHT.new(switch, bootstrapNodes = bootstrapNodes, client = dhtClient)
  if not dhtClient:
    switch.mount(node.dht)

  let syncHandler = newSyncHandler()
  switch.mount(syncHandler)

  await switch.start()

  node.switch = switch
  node.peerInfo = switch.peerInfo
  node.peerId = switch.peerInfo.peerId

  node.dht.updatePeers(bootstrapNodes)

  node.started = true
  node.startTime = getTime()
  if dhtClient:
    asyncSpawn bootstrapDht(node)

proc stop*(node: BuddyNode): Future[void] {.async.} =
  if not node.started:
    return
  
  if node.dht != nil:
    await node.dht.stop()

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
