import std/[os, times, tables, strutils, sequtils]
import std/options
import results
import chronos
import libp2p
import libp2p/multiaddress
import libp2p/peerid
import libp2p/stream/connection
from libp2p/protocols/protocol import LPProtocol
import types
import p2p/node
import p2p/addrs
import p2p/discovery
import p2p/protocol
import p2p/pairing
import p2p/rawrelay
import sync/policy
import sync/session
import config
import logutils
import sync/scanner
import control
import nat
import recovery

export results
export node

type
  DaemonError* = object of CatchableError

  FolderMark* = object
    ## How the last session with one buddy went for one of our folders.
    status*: string
    detail*: string
    lastSynced*: Time
  
  Daemon* = ref object
    config*: AppConfig
    configMtime*: times.Time
    node*: BuddyNode
    discovery*: DiscoveryService
    syncProtocol*: SyncProtocol
    buddyConnections*: Table[string, BuddyConnection]
    activeSyncs*: Table[string, bool]
    requestedSyncs*: Table[string, bool]
    folderMarks*: Table[string, Table[string, FolderMark]]
    lastSessionAt*: Table[string, Time]
    sessions*: seq[SessionRecord]
    sessionProtocols*: Table[int, SyncProtocol]
    nextSessionId*: int
    pendingRelayFallbacks*: Table[string, bool]
    diagnostics*: Table[string, string]
    relayListCache*: RelayListCache
    discoveryLoop*: Future[void]
    statusUpdateFut*: Future[void]
    running*: bool
    startTime*: Time
    masterKey*: Option[array[32, byte]]
    upnpPort*: int  ## Non-zero if we created a UPnP mapping that needs cleanup

const
  BuddyDiscoveryInterval* = chronos.seconds(10 * 60)
  MaxSessionRecords = 30
  DirectDialAttemptCount = 2
  DirectDialAttemptTimeoutSeconds = 30
  RelayJoinDelaySeconds = 60
  RelayFallbackTimeoutSeconds = 60
  DirectDialAttemptTimeout = chronos.seconds(DirectDialAttemptTimeoutSeconds)
  RelayJoinDelay = chronos.seconds(RelayJoinDelaySeconds)
  RelayFallbackTimeout = chronos.seconds(RelayFallbackTimeoutSeconds)

proc newDaemon*(config: AppConfig): Daemon =
  result = Daemon()
  result.config = config
  result.running = false
  result.buddyConnections = initTable[string, BuddyConnection]()
  result.activeSyncs = initTable[string, bool]()
  result.requestedSyncs = initTable[string, bool]()
  result.folderMarks = initTable[string, Table[string, FolderMark]]()
  result.lastSessionAt = initTable[string, Time]()
  result.sessionProtocols = initTable[int, SyncProtocol]()
  result.pendingRelayFallbacks = initTable[string, bool]()
  result.diagnostics = initTable[string, string]()
  result.relayListCache = initRelayListCache()
  try:
    result.configMtime = getLastModificationTime(getConfigPath())
  except CatchableError:
    result.configMtime = getTime()

  if config.recovery.enabled and config.recovery.masterKey.len > 0:
    result.masterKey = some(hexToBytes(config.recovery.masterKey))

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

proc buddyDiagnosticKey(buddyId: string): string {.raises: [].}
proc statusUpdateLoop(daemon: Daemon) {.async: (raises: [CancelledError]).}
proc updateLiveStatus*(daemon: Daemon) {.gcsafe, raises: [].}
proc connectToBuddyViaRelay(daemon: Daemon, buddyId: string): Future[bool] {.async: (raises: []).}

proc buddySyncDiagnosticKey(buddyId: string): string =
  "buddy-sync-time-" & buddyId

proc buddyRelayDiagnosticKey(buddyId: string): string =
  "buddy-relay-" & buddyId

proc isPubliclyReachable(daemon: Daemon): bool =
  hasDirectReachability(daemon.node.getAdvertisedAddrs())

proc hasReadyBuddyConnection(daemon: Daemon, buddyId: string): bool =
  let bc = daemon.buddyConnections.getOrDefault(buddyId)
  bc != nil and bc.isConnected()

proc attemptRelayFallbackWithin(daemon: Daemon, buddyId: string, timeout: chronos.Duration): Future[bool] {.async: (raises: []).} =
  let relayFut = daemon.connectToBuddyViaRelay(buddyId)
  try:
    return await relayFut.wait(timeout)
  except AsyncTimeoutError:
    await cancelAndWait(relayFut)
    daemon.logDiagnostic(
      buddyRelayDiagnosticKey(buddyId),
      "Relay fallback for buddy " & buddyId.shortId() & " timed out after " & $timeout & "."
    )
    return false
  except CatchableError as e:
    daemon.logDiagnostic(
      buddyRelayDiagnosticKey(buddyId),
      "Relay fallback for buddy " & buddyId.shortId() & " failed: " & e.msg
    )
    return false

proc waitAndJoinRelay(daemon: Daemon, buddyId: string) {.async: (raises: []).} =
  daemon.pendingRelayFallbacks[buddyId] = true
  defer:
    daemon.pendingRelayFallbacks[buddyId] = false

  try:
    await chronos.sleepAsync(RelayJoinDelay)
  except CancelledError:
    return

  if not daemon.running or daemon.hasReadyBuddyConnection(buddyId) or daemon.activeSyncs.getOrDefault(buddyId, false):
    return

  discard await daemon.attemptRelayFallbackWithin(buddyId, RelayFallbackTimeout)

proc scheduleRelayJoin(daemon: Daemon, buddyId: string, remoteSyncTime: string) =
  if daemon.config.relayRegion.len == 0:
    return
  if daemon.pendingRelayFallbacks.getOrDefault(buddyId, false):
    return
  if not isWithinSyncTime(remoteSyncTime):
    return

  daemon.logDiagnostic(
    buddyRelayDiagnosticKey(buddyId),
    "Waiting " & $RelayJoinDelaySeconds & " seconds for an incoming direct connection from buddy " & buddyId.shortId() & " before joining relay fallback."
  )
  asyncSpawn daemon.waitAndJoinRelay(buddyId)

proc markFolder(daemon: Daemon, folderName: string, buddyId: string, status: string, detail = "") =
  var marks = daemon.folderMarks.getOrDefault(folderName)
  var mark = marks.getOrDefault(buddyId)
  mark.status = status
  mark.detail = detail
  if status == "synced":
    mark.lastSynced = getTime()
  marks[buddyId] = mark
  daemon.folderMarks[folderName] = marks

proc recordSession(daemon: Daemon, buddyId: string, report: SessionReport, ok: bool) =
  var reported: seq[string] = @[]
  for folder in report.folders:
    reported.add(folder.folderName)
    case folder.outcome
    of foSynced: daemon.markFolder(folder.folderName, buddyId, "synced")
    of foSkipped: daemon.markFolder(folder.folderName, buddyId, "skipped", folder.reason)
    of foRefused: daemon.markFolder(folder.folderName, buddyId, "refused", folder.reason)
  if ok:
    daemon.lastSessionAt[buddyId] = getTime()
    return
  for folder in daemon.config.folders:
    if folder.name notin reported and folderAppliesToBuddy(folder, buddyId):
      daemon.markFolder(folder.name, buddyId, "failed")

proc beginSessionRecord(daemon: Daemon, bc: BuddyConnection, dialedBy, via: string, outcome = "running"): int =
  inc daemon.nextSessionId
  let now = getTime()
  daemon.sessions.add(SessionRecord(
    id: daemon.nextSessionId,
    buddyId: bc.buddyId,
    buddyName: bc.buddyName,
    dialedBy: dialedBy,
    via: via,
    startedAt: now,
    endedAt: now,
    outcome: outcome,
  ))
  if daemon.sessions.len > MaxSessionRecords:
    daemon.sessions.delete(0)
  daemon.nextSessionId

proc copyCounters(record: var SessionRecord, protocol: SyncProtocol) =
  record.bytesSent = protocol.fileBytesSent
  record.bytesReceived = protocol.fileBytesReceived
  record.filesSent = protocol.filesSent
  record.filesReceived = protocol.filesReceived

proc finishSessionRecord(daemon: Daemon, id: int, ok: bool) =
  let protocol = daemon.sessionProtocols.getOrDefault(id)
  daemon.sessionProtocols.del(id)
  for record in daemon.sessions.mitems:
    if record.id == id:
      if protocol != nil:
        record.copyCounters(protocol)
      record.endedAt = getTime()
      record.outcome = if ok: "ok" else: "failed"

proc currentSessions*(daemon: Daemon): seq[SessionRecord] =
  ## The recent sessions, with live counts for those still running.
  result = daemon.sessions
  for record in result.mitems:
    let protocol = daemon.sessionProtocols.getOrDefault(record.id)
    if protocol != nil:
      record.copyCounters(protocol)

proc loadSessionHistory(daemon: Daemon) =
  ## A session still running when the daemon last stopped was cut off.
  {.cast(gcsafe).}:
    try:
      daemon.sessions = readSessions()
    except CatchableError as e:
      echo "Could not read the sync history: ", e.msg
  for record in daemon.sessions.mitems:
    if record.outcome == "running":
      record.outcome = "interrupted"
    daemon.nextSessionId = max(daemon.nextSessionId, record.id)

proc endSession(daemon: Daemon, bc: BuddyConnection) {.async.} =
  ## A connection carries one session. Dropping it afterwards lets the next
  ## discovery round, or a sync request, dial the buddy again.
  if daemon.buddyConnections.getOrDefault(bc.buddyId) == bc:
    daemon.buddyConnections.del(bc.buddyId)
  await bc.close()

proc runBuddySync(daemon: Daemon, bc: BuddyConnection, dialedBy: string, via: string) {.async.} =
  let diagnosticKey = "buddy-" & bc.buddyId
  if daemon.activeSyncs.getOrDefault(bc.buddyId, false):
    # Both sides dialed at once; the session already running wins.
    discard daemon.beginSessionRecord(bc, dialedBy, via, "turned away")
    await daemon.endSession(bc)
    return

  daemon.activeSyncs[bc.buddyId] = true
  defer:
    daemon.activeSyncs[bc.buddyId] = false

  let protocol = newSyncProtocol()
  let sessionId = daemon.beginSessionRecord(bc, dialedBy, via)
  daemon.sessionProtocols[sessionId] = protocol
  let report = SessionReport()
  var ok = false
  try:
    var takeover = false
    {.cast(gcsafe).}:
      takeover = bc.buddyId in pendingTakeovers()
    ok = await syncBuddyFolders(daemon.config, bc.buddyId, bc.conn, protocol, takeover = takeover, report = report)
    if ok:
      echo "Folder sync finished with: ", bc.buddyName
      if takeover:
        {.cast(gcsafe).}:
          clearTakeover(bc.buddyId)
        echo "This machine now owns its folders at buddy ", bc.buddyId.shortId()
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
  daemon.recordSession(bc.buddyId, report, ok)
  daemon.finishSessionRecord(sessionId, ok)
  await daemon.endSession(bc)

proc handleIncomingConnection*(daemon: Daemon, conn: Connection) {.async.} =
  let bc = newBuddyConnection()
  bc.conn = conn
  
  let success = await bc.acceptHandshake(daemon.config)
  if success:
    echo "Buddy connected: ", bc.buddyName, " (", bc.buddyId.shortId(), ")"
    if daemon.activeSyncs.getOrDefault(bc.buddyId, false):
      echo "Turned away ", bc.buddyName, ": a sync with this buddy is already running"
      discard daemon.beginSessionRecord(bc, "buddy", "direct", "turned away")
      await bc.close()
      return
    if daemon.buddyConnections.hasKey(bc.buddyId):
      let existing = daemon.buddyConnections[bc.buddyId]
      if existing != nil:
        await existing.close()
    daemon.buddyConnections[bc.buddyId] = bc
    # libp2p closes an incoming stream as soon as its handler returns, so the
    # session has to run to the end inside the handler.
    await daemon.runBuddySync(bc, "buddy", "direct")
  else:
    echo "Rejected connection from unknown buddy"
    await bc.close()

proc mountPairingProtocol*(daemon: Daemon) {.async.} =
  ## Accepts buddies dialing in on the started node.
  let pairingHandler = proc(conn: Connection, proto: string): Future[void] {.closure, gcsafe, async: (raises: [CancelledError]).} =
    try:
      await daemon.handleIncomingConnection(conn)
    except CancelledError:
      raise
    except CatchableError:
      discard

  let pairingProto = LPProtocol.new(@[PairingProtocol], pairingHandler)
  await pairingProto.start()
  daemon.node.switch.mount(pairingProto)

proc connectToBuddies*(daemon: Daemon) {.async: (raises: []).}

proc repairFolderIdentities(daemon: Daemon) =
  ## Folders made without an id or key get them before anything is synced.
  {.cast(gcsafe).}:
    try:
      let changes = daemon.config.ensureFolderIdentities()
      if changes.len > 0:
        saveConfig(daemon.config)
        daemon.configMtime = getLastModificationTime(getConfigPath())
        for change in changes:
          logWarn("Config repaired: " & change)
    except Exception as e:
      echo "Could not repair folder config: ", e.msg

proc reloadConfigIfChanged(daemon: Daemon) {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      let path = getConfigPath()
      let mtime = getLastModificationTime(path)
      if mtime > daemon.configMtime:
        daemon.config = loadConfig()
        daemon.configMtime = mtime
        echo "Config reloaded from disk"
        daemon.repairFolderIdentities()
    except CatchableError as e:
      echo "Config reload failed: ", e.msg

proc runDiscoveryLoop(daemon: Daemon) {.async.} =
  while daemon.running:
    try:
      daemon.reloadConfigIfChanged()
      await daemon.connectToBuddies()
    except CancelledError:
      return
    except Exception as e:
      echo "Discovery loop error: ", e.msg
    try:
      await sleepAsync(BuddyDiscoveryInterval)
    except CancelledError:
      return

proc start*(daemon: Daemon, controlPort: int = DefaultControlPort): Future[void] {.async: (raises: [CatchableError]).} =
  if daemon.running:
    return
  
  echo "Starting daemon..."
  daemon.repairFolderIdentities()
  daemon.loadSessionHistory()

  for folder in daemon.config.folders:
    cleanupTempFiles(folder.path)
  for buddy in daemon.config.buddies:
    cleanupTempFiles(daemon.config.buddyStorageRoot(buddy.id.uuid))

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
          daemon.upnpPort = daemon.config.listenPort
          echo "UPnP created port mapping, using: ", upnpAddr.get
      else:
        echo "UPnP not available (no router support or already forwarded)"

    daemon.node = newBuddyNode(daemon.config.listenPort, announceAddrs)
    await daemon.node.start()
    daemon.syncProtocol = newSyncProtocol(daemon.node)

    await daemon.mountPairingProtocol()

    echo "Node started with Peer ID: ", daemon.node.peerIdStr()
    
    for address in daemon.node.getAdvertisedAddrs():
      echo "Advertising: ", $address

    daemon.startupReachabilityDiagnostic()
    
    daemon.discovery = newDiscovery(daemon.node, daemon.config.apiBaseUrl, daemon.config.buddy.uuid)
    await daemon.discovery.start()

    if daemon.config.buddies.len > 0:
      for buddy in daemon.config.buddies:
        if buddy.pairingCode.len > 0:
          discard daemon.discovery.publishBuddy(buddy, daemon.config.relayRegion, daemon.isPubliclyReachable())
          asyncSpawn daemon.discovery.publishBuddyLoop(buddy, daemon.config.relayRegion, daemon.isPubliclyReachable())
    else:
      echo "No buddies configured. Add buddies with 'buddydrive add-buddy' to start syncing."
    
    daemon.running = true
    daemon.startTime = getTime()
    
    block:
      {.cast(gcsafe).}:
        writeRuntimeStatus(
          daemon.node.peerIdStr(),
          daemon.node.getAddrs().mapIt($it),
          daemon.startTime,
          running = true
        )
    
    # Kept, not asyncSpawn-ed: stop() cancels them, and chronos turns the
    # cancellation of a spawned task into a fatal FutureDefect.
    daemon.discoveryLoop = daemon.runDiscoveryLoop()
    daemon.statusUpdateFut = statusUpdateLoop(daemon)
    
    startControlServer(controlPort)
    
    echo "Daemon started successfully"
  except CatchableError as e:
    echo "Error starting daemon: ", e.msg
    raise e

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
      for buddy in daemon.config.buddies:
        if buddy.pairingCode.len > 0:
          discard daemon.discovery.unpublishBuddy(buddy.pairingCode)
      await daemon.discovery.stop()
    
    if daemon.node != nil:
      await daemon.node.stop()

    if daemon.upnpPort != 0:
      removeUpnpPortMapping(daemon.upnpPort)
      daemon.upnpPort = 0

    daemon.updateLiveStatus()
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
    status.lastSync = daemon.lastSessionAt.getOrDefault(buddy.id.uuid)
    result.add(status)

proc getFolderStatus*(daemon: Daemon): seq[SyncStatus] =
  ## One line per folder for the GUIs. A local problem (skipped) outranks a
  ## buddy refusing the folder, which outranks a session that broke off.
  result = @[]
  for folder in daemon.config.folders:
    var status: SyncStatus
    status.folder = folder.name
    status.status = "idle"
    let marks = daemon.folderMarks.getOrDefault(folder.name)
    var syncing, synced = false
    var skipped, refused, failed: seq[string]
    for buddy in daemon.config.buddies:
      let buddyId = buddy.id.uuid
      if not folderAppliesToBuddy(folder, buddyId):
        continue
      if daemon.activeSyncs.getOrDefault(buddyId, false):
        syncing = true
      if buddyId notin marks:
        continue
      let mark = marks[buddyId]
      if mark.lastSynced > status.lastSync:
        status.lastSync = mark.lastSynced
      case mark.status
      of "synced": synced = true
      of "skipped":
        if mark.detail notin skipped:
          skipped.add(mark.detail)
      of "refused": refused.add(buddy.id.name & " refused it: " & mark.detail)
      of "failed": failed.add("the last sync with " & buddy.id.name & " did not finish, see the log")
      else: discard
    if syncing:
      status.status = "syncing"
    elif skipped.len > 0:
      status.status = "skipped"
      status.detail = "not readable: " & skipped.join("; ")
    elif refused.len > 0:
      status.status = "refused"
      status.detail = (refused & failed).join("; ")
    elif failed.len > 0:
      status.status = "failed"
      status.detail = failed.join("; ")
    elif synced:
      status.status = "synced"
    result.add(status)

proc updateLiveStatus*(daemon: Daemon) =
  try:
    let buddyStatuses = daemon.getBuddyStatus()
    let folderStatuses = daemon.getFolderStatus()
    writeLiveStatus(buddyStatuses, folderStatuses)
    writeSessions(daemon.currentSessions())
  except:
    discard

proc handleSyncRequests*(daemon: Daemon, folderNames: seq[string]) {.gcsafe, raises: [].}

proc statusUpdateLoop(daemon: Daemon) {.async: (raises: [CancelledError]).} =
  while daemon.running:
    if takeDaemonStopRequest():
      asyncSpawn daemon.stop()
      return
    var requested: seq[string] = @[]
    try:
      requested = takeSyncRequests()
    except Exception:
      discard
    if requested.len > 0:
      daemon.handleSyncRequests(requested)
    daemon.updateLiveStatus()
    await chronos.sleepAsync(chronos.seconds(2))

proc buddyDiagnosticKey(buddyId: string): string =
  "buddy-" & buddyId

proc buddyPairingCode(config: AppConfig, buddyId: string): string =
  for buddy in config.buddies:
    if buddy.id.uuid == buddyId:
      return buddy.pairingCode

proc configuredBuddyAddrs(config: AppConfig, buddyId: string): seq[MultiAddress] =
  ## Addresses set by hand in [[buddies]] addresses, dialed before anything
  ## discovery found. Meant for buddies on the same network, whose private
  ## addresses are never published.
  for buddy in config.buddies:
    if buddy.id.uuid == buddyId:
      return parseAddrs(buddy.addresses)

proc connectToBuddyViaRelay(daemon: Daemon, buddyId: string): Future[bool] {.async: (raises: []).} =
  let pairingCode = buddyPairingCode(daemon.config, buddyId)
  if daemon.config.relayRegion.len == 0 or pairingCode.len == 0:
    return false

  try:
    echo "Attempting relay fallback for buddy ", buddyId.shortId(), " in region ", daemon.config.relayRegion
    let relayConn = await connectViaRegionalRelay(
      daemon.relayListCache,
      daemon.config.apiBaseUrl,
      daemon.config.relayRegion,
      pairingCode
    )
    let conn = relayConn.conn

    let bc = newBuddyConnection()
    bc.conn = conn

    let success = await bc.performHandshake(daemon.config)
    if success:
      echo "Relay handshake successful with: ", bc.buddyName, " via ", relayConn.relayAddr
      daemon.diagnostics.del(buddyDiagnosticKey(buddyId))
      daemon.buddyConnections[bc.buddyId] = bc
      asyncSpawn daemon.runBuddySync(bc, "us", "relay")
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
    return "buddy only advertised private addresses, and none of them is on our local network"

  "no public TCP address was found among discovered addresses"

proc connectToBuddy*(daemon: Daemon, buddyId: string, peerId: PeerID, addrs: seq[MultiAddress]): Future[bool] {.async: (raises: []).} =
  if not daemon.running:
    return false

  let directPhaseStartedAt = getTime()
  var dialAddrs = configuredBuddyAddrs(daemon.config, buddyId)
  for ma in lanDialableAddrs(addrs, daemon.node.getAddrs()) & directDialableAddrs(addrs):
    if ma notin dialAddrs:
      dialAddrs.add(ma)
  if dialAddrs.len == 0:
    let elapsedSeconds = int((getTime() - directPhaseStartedAt).inSeconds)
    if elapsedSeconds < RelayJoinDelaySeconds:
      try:
        await chronos.sleepAsync(chronos.seconds(RelayJoinDelaySeconds - elapsedSeconds))
      except CancelledError:
        return false

    if await daemon.attemptRelayFallbackWithin(buddyId, RelayFallbackTimeout):
      return true

    daemon.logDiagnostic(
      buddyDiagnosticKey(buddyId),
      "Direct connection to buddy " & buddyId.shortId() & " is not possible: " &
        explainDirectConnectivityFailure(addrs) & ". Configure a forwarded TCP port and a public announce_addr on both peers, or set [network].relay_region and ensure the buddy has a pairing_code."
    )
    return false
  
  var directFailures: seq[string] = @[]
  for attempt in 1 .. DirectDialAttemptCount:
    let dialFut = daemon.node.switch.dial(peerId, dialAddrs, PairingProtocol)
    try:
      let conn = await dialFut.wait(DirectDialAttemptTimeout)
      echo "Connected to peer: ", $peerId

      let bc = newBuddyConnection()
      bc.conn = conn

      let success = await bc.performHandshake(daemon.config)
      if success:
        echo "Handshake successful with: ", bc.buddyName
        daemon.diagnostics.del(buddyDiagnosticKey(buddyId))
        daemon.diagnostics.del(buddyRelayDiagnosticKey(buddyId))
        daemon.buddyConnections[bc.buddyId] = bc
        asyncSpawn daemon.runBuddySync(bc, "us", "direct")
        return true

      echo "Handshake failed with: ", $peerId
      await bc.close()
      return false
    except AsyncTimeoutError:
      await cancelAndWait(dialFut)
      directFailures.add("attempt " & $attempt & " timed out after 30 seconds")
    except Exception as e:
      if not dialFut.finished():
        await cancelAndWait(dialFut)
      directFailures.add("attempt " & $attempt & " failed: " & e.msg)

  let elapsedSeconds = int((getTime() - directPhaseStartedAt).inSeconds)
  if elapsedSeconds < RelayJoinDelaySeconds:
    try:
      await chronos.sleepAsync(chronos.seconds(RelayJoinDelaySeconds - elapsedSeconds))
    except CancelledError:
      return false

  if await daemon.attemptRelayFallbackWithin(buddyId, RelayFallbackTimeout):
    return true

  daemon.logDiagnostic(
    buddyDiagnosticKey(buddyId),
      "Direct connection to buddy " & buddyId.shortId() & " failed after " & $DirectDialAttemptCount & " attempts (" & directFailures.join("; ") & ") and relay fallback did not connect within " & $RelayFallbackTimeoutSeconds & " seconds."
  )
  return false

proc connectToBuddies*(daemon: Daemon) {.async: (raises: []).} =
  if not daemon.running:
    return

  if daemon.config.buddies.len == 0:
    return

  let myPubliclyReachable = daemon.isPubliclyReachable()
  
  echo "Checking ", daemon.config.buddies.len, " buddies..."
  
  for buddy in daemon.config.buddies:
    if daemon.buddyConnections.hasKey(buddy.id.uuid):
      let existing = daemon.buddyConnections.getOrDefault(buddy.id.uuid)
      if existing == nil:
        daemon.buddyConnections.del(buddy.id.uuid)
      elif not existing.isConnected():
        try:
          await existing.close()
        except CatchableError:
          discard
        daemon.buddyConnections.del(buddy.id.uuid)
      else:
        daemon.diagnostics.del(buddySyncDiagnosticKey(buddy.id.uuid))
        continue
    
    if buddy.pairingCode.len == 0:
      daemon.logDiagnostic(
        buddyDiagnosticKey(buddy.id.uuid),
        "Buddy " & buddy.id.name & " has no pairing code — cannot discover"
      )
      continue
    try:
      let record = daemon.discovery.findBuddy(buddy.pairingCode, buddy.id.uuid)
      if record.isSome:
        let rec = record.get()
        if not shouldInitiate(daemon.config.buddy.uuid, myPubliclyReachable, buddy.id.uuid, rec):
          daemon.diagnostics.del(buddySyncDiagnosticKey(buddy.id.uuid))
          daemon.scheduleRelayJoin(buddy.id.uuid, rec.syncTime)
          continue

        if not shouldAttemptBuddySync(buddy):
          daemon.logDiagnostic(
            buddySyncDiagnosticKey(buddy.id.uuid),
            "Buddy " & buddy.id.name & " is outside its sync_time (" & syncTimeDescription(buddy.syncTime) & "); postponing outgoing sync attempt."
          )
          continue

        daemon.diagnostics.del(buddySyncDiagnosticKey(buddy.id.uuid))
        writeCachedBuddyAddr(buddy.id.uuid, rec.peerId, rec.addresses, rec.relayRegion)

        var addrs: seq[MultiAddress] = @[]
        for addrStr in rec.addresses:
          let maRes = MultiAddress.init(addrStr)
          if maRes.isOk:
            addrs.add(maRes.get())

        let pidRes = PeerID.init(rec.peerId)
        if pidRes.isOk and (addrs.len > 0 or buddy.addresses.len > 0):
          discard await daemon.connectToBuddy(buddy.id.uuid, pidRes.get(), addrs)
        elif addrs.len == 0:
          if rec.relayRegion.len > 0:
            daemon.logDiagnostic(
              buddyRelayDiagnosticKey(buddy.id.uuid),
              "Buddy " & buddy.id.name & " published no direct dialable addresses; waiting " & $RelayJoinDelaySeconds & " seconds before relay fallback."
            )
            try:
              await chronos.sleepAsync(RelayJoinDelay)
            except CancelledError:
              return
            discard await daemon.attemptRelayFallbackWithin(buddy.id.uuid, RelayFallbackTimeout)
          else:
            daemon.logDiagnostic(
              buddyDiagnosticKey(buddy.id.uuid),
              "Buddy " & buddy.id.name & " published no dialable addresses and no relay region"
            )
      else:
        let cached = readCachedBuddyAddr(buddy.id.uuid)
        if cached.isSome:
          if daemon.config.buddy.uuid >= buddy.id.uuid:
            daemon.scheduleRelayJoin(buddy.id.uuid, buddy.syncTime)
            continue

          if not shouldAttemptBuddySync(buddy):
            daemon.logDiagnostic(
              buddySyncDiagnosticKey(buddy.id.uuid),
              "Buddy " & buddy.id.name & " is outside its sync_time (" & syncTimeDescription(buddy.syncTime) & "); postponing outgoing sync attempt."
            )
            continue

          daemon.diagnostics.del(buddySyncDiagnosticKey(buddy.id.uuid))
          var addrs: seq[MultiAddress] = @[]
          for addrStr in cached.get().addresses:
            let maRes = MultiAddress.init(addrStr)
            if maRes.isOk:
              addrs.add(maRes.get())

          let pidRes = PeerID.init(cached.get().peerId)
          if pidRes.isOk and (addrs.len > 0 or buddy.addresses.len > 0):
            discard await daemon.connectToBuddy(buddy.id.uuid, pidRes.get(), addrs)
          elif cached.get().relayRegion.len > 0:
            daemon.logDiagnostic(
              buddyRelayDiagnosticKey(buddy.id.uuid),
              "Cached buddy info for " & buddy.id.name & " has no direct dialable addresses; waiting 60 seconds before relay fallback."
            )
            try:
              await chronos.sleepAsync(RelayJoinDelay)
            except CancelledError:
              return
            discard await daemon.attemptRelayFallbackWithin(buddy.id.uuid, RelayFallbackTimeout)
        else:
          daemon.logDiagnostic(
            buddyDiagnosticKey(buddy.id.uuid),
            "Buddy " & buddy.id.name & " (" & buddy.id.uuid.shortId() & ") not found on relay yet"
          )
    except Exception as e:
      daemon.logDiagnostic(
        buddyDiagnosticKey(buddy.id.uuid),
        "Discovery lookup failed for buddy " & buddy.id.name & ": " & e.msg
      )

proc syncBuddyNow(daemon: Daemon, buddy: BuddyInfo) {.async: (raises: []).} =
  ## A sync asked for from a GUI: dial the buddy now, whatever its sync_time
  ## and whichever side would normally initiate. A buddy that can only be
  ## reached the other way round is synced when it next dials us.
  let buddyId = buddy.id.uuid
  if daemon.activeSyncs.getOrDefault(buddyId, false) or daemon.requestedSyncs.getOrDefault(buddyId, false):
    return
  daemon.requestedSyncs[buddyId] = true
  defer:
    daemon.requestedSyncs[buddyId] = false

  var peerId = ""
  var addresses: seq[string] = @[]
  try:
    let record =
      if buddy.pairingCode.len > 0 and daemon.discovery != nil: daemon.discovery.findBuddy(buddy.pairingCode, buddyId)
      else: none(BuddyRecord)
    if record.isSome:
      peerId = record.get().peerId
      addresses = record.get().addresses
      writeCachedBuddyAddr(buddyId, peerId, addresses, record.get().relayRegion)
    else:
      let cached = readCachedBuddyAddr(buddyId)
      if cached.isSome:
        peerId = cached.get().peerId
        addresses = cached.get().addresses
  except Exception as e:
    echo "Sync request for ", buddy.id.name, ": discovery lookup failed: ", e.msg

  let pidRes = PeerID.init(peerId)
  if pidRes.isErr:
    echo "Sync request for ", buddy.id.name, ": the buddy has not been found yet"
    return
  echo "Sync requested with ", buddy.id.name
  discard await daemon.connectToBuddy(buddyId, pidRes.get(), parseAddrs(addresses))

proc handleSyncRequests*(daemon: Daemon, folderNames: seq[string]) =
  var buddyIds: seq[string] = @[]
  for folder in daemon.config.folders:
    if folder.name notin folderNames:
      continue
    for buddy in daemon.config.buddies:
      if folderAppliesToBuddy(folder, buddy.id.uuid) and buddy.id.uuid notin buddyIds:
        buddyIds.add(buddy.id.uuid)
  for buddy in daemon.config.buddies:
    if buddy.id.uuid in buddyIds:
      asyncSpawn daemon.syncBuddyNow(buddy)
