import std/os
import std/times
import results
import chronos
import config
import types
import logutils
import p2p/node
import p2p/discovery
import p2p/protocol

export results
export node

type
  DaemonError* = object of CatchableError
  
  Daemon* = ref object
    config*: AppConfig
    node*: BuddyNode
    discovery*: DiscoveryService
    syncProtocol*: SyncProtocol
    running*: bool
    startTime*: Time

proc newDaemon*(config: AppConfig): Daemon =
  result = Daemon()
  result.config = config
  result.running = false

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
