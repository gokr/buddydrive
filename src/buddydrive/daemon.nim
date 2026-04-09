import std/times
import std/tables
import results
import chronos
import libp2p
import libp2p/multiaddress
import libp2p/stream/connection
import types
import p2p/node
import p2p/discovery
import p2p/protocol
import p2p/pairing

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
    running*: bool
    startTime*: Time

proc newDaemon*(config: AppConfig): Daemon =
  result = Daemon()
  result.config = config
  result.running = false
  result.buddyConnections = initTable[string, BuddyConnection]()

proc handleIncomingConnection*(daemon: Daemon, conn: Connection) {.async.} =
  let bc = newBuddyConnection()
  bc.conn = conn
  
  let success = await bc.acceptHandshake(daemon.config)
  if success:
    echo "Buddy connected: ", bc.buddyName, " (", bc.buddyId.shortId(), ")"
    daemon.buddyConnections[bc.buddyId] = bc
  else:
    echo "Rejected connection from unknown buddy"
    await bc.close()

proc start*(daemon: Daemon): Future[void] {.async: (raises: []).} =
  if daemon.running:
    return
  
  echo "Starting daemon..."
  
  try:
    daemon.node = newBuddyNode()
    await daemon.node.start()
    
    echo "Node started with Peer ID: ", daemon.node.peerIdStr()
    
    for address in daemon.node.getAddrs():
      echo "Listening on: ", $address
    
    daemon.discovery = newDiscovery(daemon.node)
    await daemon.discovery.start()
    
    echo "DHT discovery started"
    
    await daemon.discovery.publishBuddy(daemon.config.buddy.uuid)
    echo "Announced buddy ID on DHT: ", daemon.config.buddy.uuid
    
    daemon.syncProtocol = newSyncProtocol(daemon.node)
    daemon.running = true
    daemon.startTime = getTime()
    
    echo "Daemon started successfully"
  except Exception as e:
    echo "Error starting daemon: ", e.msg

proc stop*(daemon: Daemon): Future[void] {.async: (raises: []).} =
  if not daemon.running:
    return
  
  echo "Stopping daemon..."
  
  try:
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

proc connectToBuddy*(daemon: Daemon, buddyId: string, peerId: PeerID, addrs: seq[MultiAddress]): Future[bool] {.async: (raises: []).} =
  if not daemon.running:
    return false
  
  if addrs.len == 0:
    return false
  
  try:
    let conn = await daemon.node.switch.dial(peerId, addrs, PairingProtocol)
    echo "Connected to peer: ", $peerId
    
    let bc = newBuddyConnection()
    bc.conn = conn
    
    let success = await bc.performHandshake(daemon.config)
    if success:
      echo "Handshake successful with: ", bc.buddyName
      daemon.buddyConnections[bc.buddyId] = bc
      return true
    else:
      echo "Handshake failed with: ", $peerId
      await bc.close()
      return false
  except Exception as e:
    echo "Connection failed: ", e.msg
    return false

proc connectToBuddies*(daemon: Daemon) {.async: (raises: []).} =
  if not daemon.running:
    return
  
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
