import std/[times, tables, strutils, sequtils]
import results
import chronos
import libp2p
import libp2p/multiaddress
import libp2p/stream/connection
from libp2p/protocols/protocol import LPProtocol
import types
import p2p/node
import p2p/discovery
import p2p/protocol
import p2p/pairing
import p2p/rawrelay
import sync/policy
import sync/session
import control
import nat

export results
export node

type
  DaemonError* = object of CatchableError
  
  Daemon* = ref object
    config*: AppConfig
    node*: BuddyNode
    discovery*: DiscoveryService
    syncProtocol*: SyncProtocol
    buddyConnections*: Table[string, BuddyConnection]
    diagnostics*: Table[string, string]
    relayListCache*: RelayListCache
    discoveryLoop*: Future[void]
    statusUpdateFut*: Future[void]
    running*: bool
    startTime*: Time

const BuddyDiscoveryInterval* = chronos.seconds(15)

proc newDaemon*(config: AppConfig): Daemon =
  result = Daemon()
  result.config = config
  result.running = false
  result.buddyConnections = initTable[string, BuddyConnection]()
  result.diagnostics = initTable[string, string]()
  result.relayListCache = initRelayListCache()

proc isPrivateOrLoopback(ma: MultiAddress): bool =
  let s = $ma
  if s.contains("/p2p-circuit"):
    return true
  if s.startsWith("/ip4/127.") or s.startsWith("/ip4/10.") or
      s.startsWith("/ip4/192.168.") or s.startsWith("/ip4/169.254."):
    return true
  if s.startsWith("/ip4/172."):
    let parts = s.split("/")
    if parts.len > 2:
      let octets = parts[2].split(".")
      if octets.len > 1:
        try:
          let second = parseInt(octets[1])
          return second >= 16 and second <= 31
        except ValueError:
          discard
  if s.startsWith("/ip4/100."):
    let parts = s.split("/")
    if parts.len > 2:
      let octets = parts[2].split(".")
      if octets.len > 1:
        try:
          let second = parseInt(octets[1])
          return second >= 64 and second <= 127
        except ValueError:
          discard
  if s.startsWith("/ip6/::1") or s.startsWith("/ip6/fc") or
      s.startsWith("/ip6/fd") or s.startsWith("/ip6/fe80"):
    return true
  false

proc isRelayAddress(ma: MultiAddress): bool =
  ($ma).contains("/p2p-circuit")

proc directDialableAddrs(addrs: seq[MultiAddress]): seq[MultiAddress] =
  for ma in addrs:
    let s = $ma
    if isRelayAddress(ma):
      continue
    if isPrivateOrLoopback(ma):
      continue
    if s.contains("/tcp/"):
      result.add(ma)

proc hasDirectReachability(addrs: seq[MultiAddress]): bool =
  directDialableAddrs(addrs).len > 0

proc logDiagnostic(daemon: Daemon, key: string, message: string) =
  if daemon.diagnostics.getOrDefault(key) == message:
    return
  daemon.diagnostics[key] = message
  echo message

proc startupReachabilityDiagnostic(daemon: Daemon) =
  let addrs = daemon.node.getAdvertisedAddrs()
  if hasDirectReachability(addrs):
    return

  daemon.logDiagnostic(
    "startup-reachability",
    "Direct-only mode: no public TCP address is being advertised. " &
      "Forward TCP port " & $daemon.config.listenPort &
      " on your router and set [network].announce_addr in ~/.buddydrive/config.toml to your public multiaddr, " &
      "for example /ip4/<public-ip>/tcp/" & $daemon.config.listenPort & "."
  )

proc syncWindowDiagnosticKey(): string =
  "sync-window"

proc buddyDiagnosticKey(buddyId: string): string {.raises: [].}
proc statusUpdateLoop(daemon: Daemon) {.async: (raises: [CancelledError]).}

proc runBuddySync(daemon: Daemon, bc: BuddyConnection) {.async.} =
  let diagnosticKey = "buddy-" & bc.buddyId
  try:
    if await syncBuddyFolders(daemon.config, bc.buddyId, bc.conn, daemon.syncProtocol):
      echo "Folder sync finished with: ", bc.buddyName
    else:
      daemon.logDiagnostic(
        diagnosticKey,
        "Folder sync failed for buddy " & bc.buddyId.shortId()
      )
  except CatchableError as e:
    daemon.logDiagnostic(
      diagnosticKey,
      "Folder sync errored for buddy " & bc.buddyId.shortId() & ": " & e.msg
    )

proc handleIncomingConnection*(daemon: Daemon, conn: Connection) {.async.} =
  if not isWithinSyncWindow(daemon.config):
    daemon.logDiagnostic(
      syncWindowDiagnosticKey(),
      "Sync window is closed (" & syncWindowDescription(daemon.config) & "); rejecting incoming sync connections until the window opens."
    )
    await conn.close()
    return

  let bc = newBuddyConnection()
  bc.conn = conn
  
  let success = await bc.acceptHandshake(daemon.config)
  if success:
    echo "Buddy connected: ", bc.buddyName, " (", bc.buddyId.shortId(), ")"
    daemon.buddyConnections[bc.buddyId] = bc
    asyncSpawn daemon.runBuddySync(bc)
  else:
    echo "Rejected connection from unknown buddy"
    await bc.close()

proc connectToBuddies*(daemon: Daemon) {.async: (raises: []).}

proc runDiscoveryLoop(daemon: Daemon) {.async.} =
  while daemon.running:
    try:
      await daemon.connectToBuddies()
    except CancelledError:
      return
    except Exception as e:
      echo "Discovery loop error: ", e.msg
    try:
      await sleepAsync(BuddyDiscoveryInterval)
    except CancelledError:
      return

proc start*(daemon: Daemon, controlPort: int = DefaultControlPort): Future[void] {.async: (raises: []).} =
  if daemon.running:
    return
  
  echo "Starting daemon..."
  
  try:
    var announceAddrs: seq[MultiAddress] = @[]
    
    if daemon.config.announceAddr.len > 0:
      let maRes = MultiAddress.init(daemon.config.announceAddr)
      if maRes.isOk:
        announceAddrs.add(maRes.get())
      else:
        daemon.logDiagnostic(
          "startup-announce-addr",
          "Configured announce_addr is invalid and will be ignored: " & daemon.config.announceAddr
        )
    
    if announceAddrs.len == 0:
      echo "Attempting UPnP port mapping for port ", daemon.config.listenPort, "..."
      let upnpAddr = attemptUpnpPortMapping(daemon.config.listenPort)
      if upnpAddr.isSome:
        let maRes = MultiAddress.init(upnpAddr.get)
        if maRes.isOk:
          announceAddrs.add(maRes.get())
          echo "UPnP created port mapping, using: ", upnpAddr.get
      else:
        echo "UPnP not available (no router support or already forwarded)"

    daemon.node = newBuddyNode(daemon.config.listenPort, announceAddrs)
    await daemon.node.start()
    daemon.syncProtocol = newSyncProtocol(daemon.node)

    let pairingHandler = proc(conn: Connection, proto: string): Future[void] {.closure, gcsafe, async: (raises: [CancelledError]).} =
      try:
        await daemon.handleIncomingConnection(conn)
      except CancelledError:
        raise
      except CatchableError:
        discard

    daemon.node.switch.mount(LPProtocol.new(@[PairingProtocol], pairingHandler))

    echo "Node started with Peer ID: ", daemon.node.peerIdStr()
    
    for address in daemon.node.getAddrs():
      echo "Listening on: ", $address
    for address in daemon.node.getAdvertisedAddrs():
      echo "Advertising: ", $address

    daemon.startupReachabilityDiagnostic()
    
    daemon.discovery = newDiscovery(daemon.node)
    await daemon.discovery.start()
    
    echo "DHT discovery started"
    
    asyncSpawn daemon.discovery.publishBuddy(daemon.config.buddy.uuid)
    echo "Started buddy announcement on DHT: ", daemon.config.buddy.uuid
    
    daemon.running = true
    daemon.startTime = getTime()
    
    block:
      {.cast(gcsafe).}:
        writeRuntimeStatus(
          daemon.config,
          daemon.node.peerIdStr(),
          daemon.node.getAddrs().mapIt($it),
          daemon.startTime,
          running = true
        )
    
    daemon.discoveryLoop = daemon.runDiscoveryLoop()
    asyncSpawn daemon.discoveryLoop
    
    daemon.statusUpdateFut = statusUpdateLoop(daemon)
    asyncSpawn daemon.statusUpdateFut
    
    startControlServer(controlPort)
    echo "Control server started on port ", controlPort
    
    echo "Daemon started successfully"
  except Exception as e:
    echo "Error starting daemon: ", e.msg

proc stop*(daemon: Daemon): Future[void] {.async: (raises: []).} =
  if not daemon.running:
    return
  
  echo "Stopping daemon..."
  
  try:
    block:
      {.cast(gcsafe).}:
        stopControlServer()
        markControlStopped()

    if daemon.statusUpdateFut != nil:
      daemon.statusUpdateFut.cancelSoon()
      try:
        await daemon.statusUpdateFut
      except:
        discard

    if daemon.discoveryLoop != nil:
      daemon.discoveryLoop.cancelSoon()
      try:
        await daemon.discoveryLoop
      except:
        discard
    
    for buddyId, bc in daemon.buddyConnections:
      await bc.close()
    daemon.buddyConnections.clear()
    
    if daemon.discovery != nil:
      await daemon.discovery.stop()
    
    if daemon.node != nil:
      await daemon.node.stop()
    
    daemon.running = false
    echo "Daemon stopped"
  except Exception as e:
    echo "Error stopping daemon: ", e.msg

proc isRunning*(daemon: Daemon): bool =
  daemon.running

proc uptime*(daemon: Daemon): times.Duration =
  if daemon.running:
    result = getTime() - daemon.startTime

proc getBuddyStatus*(daemon: Daemon): seq[BuddyStatus] =
  result = @[]
  for buddy in daemon.config.buddies:
    var status: BuddyStatus
    status.id = buddy.id.uuid
    status.name = buddy.id.name
    
    if daemon.buddyConnections.hasKey(buddy.id.uuid):
      let bc = daemon.buddyConnections[buddy.id.uuid]
      if bc.isConnected():
        status.state = csConnected
        status.latencyMs = int((getTime() - bc.lastActivity).inMilliseconds)
      else:
        status.state = csDisconnected
    else:
      status.state = csDisconnected
    
    status.latencyMs = -1
    status.lastSync = buddy.addedAt
    result.add(status)

proc getFolderStatus*(daemon: Daemon): seq[SyncStatus] =
  result = @[]
  for folder in daemon.config.folders:
    var status: SyncStatus
    status.folder = folder.name
    status.totalBytes = 0
    status.syncedBytes = 0
    status.fileCount = 0
    status.syncedFiles = 0
    status.status = "idle"
    result.add(status)

proc updateLiveStatus*(daemon: Daemon) =
  try:
    let buddyStatuses = daemon.getBuddyStatus()
    let folderStatuses = daemon.getFolderStatus()
    writeLiveStatus(buddyStatuses, folderStatuses)
  except:
    discard

proc statusUpdateLoop(daemon: Daemon) {.async: (raises: [CancelledError]).} =
  while daemon.running:
    daemon.updateLiveStatus()
    await chronos.sleepAsync(chronos.seconds(2))

proc buddyDiagnosticKey(buddyId: string): string =
  "buddy-" & buddyId

proc buddyRelayToken(config: AppConfig, buddyId: string): string =
  for buddy in config.buddies:
    if buddy.id.uuid == buddyId:
      return buddy.relayToken

proc connectToBuddyViaRelay(daemon: Daemon, buddyId: string): Future[bool] {.async: (raises: []).} =
  let relayToken = buddyRelayToken(daemon.config, buddyId)
  if daemon.config.relayRegion.len == 0 or relayToken.len == 0:
    return false

  try:
    echo "Attempting relay fallback for buddy ", buddyId.shortId(), " in region ", daemon.config.relayRegion
    let relayConn = await connectViaRegionalRelay(
      daemon.relayListCache,
      daemon.config.relayBaseUrl,
      daemon.config.relayRegion,
      relayToken
    )
    let conn = relayConn.conn

    let bc = newBuddyConnection()
    bc.conn = conn

    let success = await bc.performHandshake(daemon.config)
    if success:
      echo "Relay handshake successful with: ", bc.buddyName, " via ", relayConn.relayAddr
      daemon.diagnostics.del(buddyDiagnosticKey(buddyId))
      daemon.buddyConnections[bc.buddyId] = bc
      asyncSpawn daemon.runBuddySync(bc)
      return true

    echo "Relay handshake failed for buddy: ", buddyId.shortId()
    await bc.close()
  except Exception as e:
    daemon.logDiagnostic(
      buddyDiagnosticKey(buddyId),
      "Relay fallback in region " & daemon.config.relayRegion & " for buddy " & buddyId.shortId() & " failed: " & e.msg
    )

  false

proc explainDirectConnectivityFailure(addrs: seq[MultiAddress]): string =
  if addrs.len == 0:
    return "buddy published no addresses"

  let relayOnly = addrs.allIt(isRelayAddress(it))
  if relayOnly:
    return "buddy is only reachable via relay addresses, and relay fallback is disabled"

  let privateOnly = addrs.allIt(isPrivateOrLoopback(it))
  if privateOnly:
    return "buddy only advertised private or loopback addresses"

  "no public TCP address was found among discovered addresses"

proc connectToBuddy*(daemon: Daemon, buddyId: string, peerId: PeerID, addrs: seq[MultiAddress]): Future[bool] {.async: (raises: []).} =
  if not daemon.running:
    return false
  
  let dialAddrs = directDialableAddrs(addrs)
  if dialAddrs.len == 0:
    if await daemon.connectToBuddyViaRelay(buddyId):
      return true

    daemon.logDiagnostic(
      buddyDiagnosticKey(buddyId),
      "Direct connection to buddy " & buddyId.shortId() & " is not possible: " &
        explainDirectConnectivityFailure(addrs) & ". Configure a forwarded TCP port and a public announce_addr on both peers, or set [network].relay_region and the buddy relay_token."
    )
    return false
  
  try:
    let conn = await daemon.node.switch.dial(peerId, dialAddrs, PairingProtocol)
    echo "Connected to peer: ", $peerId
    
    let bc = newBuddyConnection()
    bc.conn = conn
    
    let success = await bc.performHandshake(daemon.config)
    if success:
      echo "Handshake successful with: ", bc.buddyName
      daemon.diagnostics.del(buddyDiagnosticKey(buddyId))
      daemon.buddyConnections[bc.buddyId] = bc
      asyncSpawn daemon.runBuddySync(bc)
      return true
    else:
      echo "Handshake failed with: ", $peerId
      await bc.close()
      return false
  except Exception as e:
    if await daemon.connectToBuddyViaRelay(buddyId):
      return true

    daemon.logDiagnostic(
      buddyDiagnosticKey(buddyId),
      "Direct connection to buddy " & buddyId.shortId() & " failed after discovery: " & e.msg &
        ". Verify that both peers are advertising public TCP addresses and that router port forwarding is configured, or configure relay fallback with relay_region."
    )
    return false

proc connectToBuddies*(daemon: Daemon) {.async: (raises: []).} =
  if not daemon.running:
    return

  if not isWithinSyncWindow(daemon.config):
    daemon.logDiagnostic(
      syncWindowDiagnosticKey(),
      "Sync window is closed (" & syncWindowDescription(daemon.config) & "); postponing buddy sync attempts."
    )
    return

  daemon.diagnostics.del(syncWindowDiagnosticKey())
  
  echo "Checking ", daemon.config.buddies.len, " buddies..."
  
  for buddy in daemon.config.buddies:
    if daemon.buddyConnections.hasKey(buddy.id.uuid):
      continue
    
    echo "Buddy: ", buddy.id.name
    echo "  Searching DHT for: ", buddy.id.uuid
    
    try:
      let peers = await daemon.discovery.findBuddy(buddy.id.uuid)
      if peers.len > 0:
        let (peerId, addrs) = peers[0]
        discard await daemon.connectToBuddy(buddy.id.uuid, peerId, addrs)
      else:
        echo "  Not found on DHT yet"
    except Exception as e:
      echo "  DHT lookup failed: ", e.msg
