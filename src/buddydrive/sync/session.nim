import std/[algorithm, options, sets, tables]
import std/os except FileInfo
import chronos
import libp2p/stream/connection
import ../types
import ../p2p/messages
import ../p2p/protocol
import transfer

proc folderAppliesToBuddy(folder: FolderConfig, buddyId: string): bool =
  folder.buddies.len == 0 or buddyId in folder.buddies

proc applicableFolders(config: AppConfig, buddyId: string): seq[FolderConfig] =
  for folder in config.folders:
    if folderAppliesToBuddy(folder, buddyId):
      result.add(folder)

proc incomingFolderForBuddy(config: AppConfig, buddyId: string, folder: FolderConfig): FolderConfig =
  result = folder
  if config.storageBasePath.len > 0:
    result.path = config.storageBasePath / buddyId / folder.name

proc sendLocalFolderLists(
    config: AppConfig,
    buddyId: string,
    conn: Connection,
    protocol: SyncProtocol,
): Future[bool] {.async.} =
  for folder in applicableFolders(config, buddyId):
    let transfer = newFileTransfer(folder, protocol, config.bandwidthLimitKBps)
    defer: transfer.close()
    if not await transfer.sendFileList(conn):
      return false

  try:
    await protocol.sendMessage(conn, newSyncDone())
    true
  except CatchableError:
    false

proc receiveRemoteFolderLists(
    conn: Connection,
    protocol: SyncProtocol,
): Future[Table[string, seq[FileInfo]]] {.async.} =
  result = initTable[string, seq[FileInfo]]()

  while true:
    let msgOpt = await protocol.receiveMessage(conn)
    if msgOpt.isNone():
      raise newException(CatchableError, "failed to receive remote folder list")

    let msg = msgOpt.get()
    case msg.kind
    of msgFileList:
      var files: seq[FileInfo] = @[]
      for entry in msg.files:
        var info: FileInfo
        info.path = entry.path
        info.encryptedPath = entry.encryptedPath
        info.size = entry.size
        info.mtime = entry.mtime
        info.hash = stringToHash(entry.hash)
        info.mode = entry.mode
        info.symlinkTarget = entry.symlinkTarget
        files.add(info)
      result[msg.folderName] = files
    of msgSyncDone:
      return
    else:
      raise newException(CatchableError, "unexpected message while receiving folder lists")

const
  SessionEndTimeout = chronos.seconds(10)
  SessionEndLingerTimeout = chronos.seconds(2)

type
  MoveInstruction = tuple[oldPath: string, newPath: string, hash: string]

proc sameMoveCandidate(remote: FileInfo, local: FileInfo): bool =
  remote.hash == local.hash and
  remote.size == local.size and
  remote.mode == local.mode and
  remote.symlinkTarget == local.symlinkTarget

proc computeOutboundDelta(
    transfer: FileTransfer,
    remoteFiles: seq[FileInfo],
): tuple[moves: seq[MoveInstruction], deletes: seq[string], projectedRemote: seq[FileInfo]] =
  ## Works out what the remote should change to match us, and what is left for
  ## us to pull. A remote path we do not have is only deleted when the index
  ## shows we used to hold it; otherwise it is a file we have never seen and
  ## belongs in projectedRemote so it gets fetched.
  let localFiles = transfer.scanner.scanDirectory()
  let knownPaths = transfer.knownIndexPaths()

  var localByPath = initTable[string, FileInfo]()
  var remoteByPath = initTable[string, FileInfo]()
  var localByHash = initTable[string, FileInfo]()
  var projectedByPath = initTable[string, FileInfo]()

  for fileInfo in localFiles:
    localByPath[fileInfo.path] = fileInfo
    let key = hashToString(fileInfo.hash)
    if key notin localByHash:
      localByHash[key] = fileInfo

  for fileInfo in remoteFiles:
    remoteByPath[fileInfo.path] = fileInfo
    projectedByPath[fileInfo.path] = fileInfo

  var remotePaths: seq[string] = @[]
  for path in remoteByPath.keys:
    remotePaths.add(path)
  remotePaths.sort(cmp)

  for remotePath in remotePaths:
    let remoteFile = remoteByPath[remotePath]
    if remotePath in localByPath:
      continue

    let key = hashToString(remoteFile.hash)
    let wasHeldLocally = remotePath in knownPaths

    if key in localByHash and not (localByHash[key].path in remoteByPath) and
        sameMoveCandidate(remoteFile, localByHash[key]):
      # Same content sits at a different path here and the remote does not have
      # that path yet: a rename, not a deletion.
      let localFile = localByHash[key]
      result.moves.add((remotePath, localFile.path, key))
      projectedByPath.del(remotePath)
      projectedByPath[localFile.path] = localFile
    elif wasHeldLocally:
      result.deletes.add(remotePath)
      projectedByPath.del(remotePath)
    else:
      # Never seen here — leave it in the projection so we pull it.
      discard

  for path in projectedByPath.keys:
    result.projectedRemote.add(projectedByPath[path])

  result.projectedRemote.sort(proc(a, b: FileInfo): int = cmp(a.path, b.path))
  result.moves.sort(proc(a, b: MoveInstruction): int = cmp((a.oldPath, a.newPath), (b.oldPath, b.newPath)))
  result.deletes.sort(cmp)

proc sendDeltaPhase(
    sendTransfer: FileTransfer,
    receiveTransfer: FileTransfer,
    conn: Connection,
    remoteFiles: seq[FileInfo],
): Future[bool] {.async.} =
  let localReceiveFiles = receiveTransfer.scanner.scanDirectory()
  var effectiveRemoteFiles = remoteFiles
  if localReceiveFiles.len == 0 and remoteFiles.len > 0:
    let refreshed = await receiveTransfer.requestListPaths(conn)
    if refreshed.isSome:
      effectiveRemoteFiles = refreshed.get()

  let delta = sendTransfer.computeOutboundDelta(effectiveRemoteFiles)
  let filesNeeded = receiveTransfer.compareWithRemote(delta.projectedRemote)

  for move in delta.moves:
    if move.oldPath == move.newPath:
      continue
    try:
      await sendTransfer.protocol.sendMessage(conn, newMoveFile(move.oldPath, move.newPath, move.hash))
    except CatchableError:
      return false

  for path in delta.deletes:
    try:
      await sendTransfer.protocol.sendMessage(conn, newFileDelete(path))
    except CatchableError:
      return false

  for fileInfo in filesNeeded:
    if not await receiveTransfer.syncFile(conn, fileInfo):
      return false

  try:
    await sendTransfer.protocol.sendMessage(conn, newSyncDone())
    true
  except CatchableError:
    false

proc servePhase(sendTransfer: FileTransfer, receiveTransfer: FileTransfer, conn: Connection): Future[bool] {.async.} =
  while true:
    let msgOpt = await sendTransfer.protocol.receiveMessage(conn)
    if msgOpt.isNone():
      return false

    let msg = msgOpt.get()
    case msg.kind
    of msgSyncDone:
      return true
    of msgSessionEnd:
      # Buddy ended the session early; nothing more will come.
      return false
    of msgFileRequest:
      if not await sendTransfer.sendFileData(conn, msg.requestPath, msg.requestOffset, msg.requestLength):
        return false
    of msgFileDelete:
      if not receiveTransfer.deleteLocalFile(msg.deletedPath):
        return false
    of msgMoveFile:
      if not receiveTransfer.moveLocalFile(msg.oldPath, msg.newPath):
        return false
    of msgListPathsRequest:
      if not await receiveTransfer.sendListPathsResponse(conn):
        return false
    else:
      return false

proc syncFolder(
    config: AppConfig,
    buddyId: string,
    remoteBuddyId: string,
    folder: FolderConfig,
    remoteFiles: seq[FileInfo],
    conn: Connection,
    protocol: SyncProtocol,
): Future[bool] {.async.} =
  let sendTransfer = newFileTransfer(folder, protocol, config.bandwidthLimitKBps)
  let receiveFolder = incomingFolderForBuddy(config, buddyId, folder)
  let receiveTransfer = newFileTransfer(receiveFolder, protocol, config.bandwidthLimitKBps)
  defer:
    sendTransfer.close()
    receiveTransfer.close()

  sendTransfer.rebuildIndexFromDisk()
  receiveTransfer.rebuildIndexFromDisk()

  let requestFirst = config.buddy.uuid < remoteBuddyId

  if requestFirst:
    if not await sendDeltaPhase(sendTransfer, receiveTransfer, conn, remoteFiles):
      return false
    if not await servePhase(sendTransfer, receiveTransfer, conn):
      return false
  else:
    if not await servePhase(sendTransfer, receiveTransfer, conn):
      return false
    if not await sendDeltaPhase(sendTransfer, receiveTransfer, conn, remoteFiles):
      return false

  # Deletions have been propagated by now, so stale index rows can go. On a
  # failed session they are kept, which at worst resurrects a deleted file
  # next time instead of losing a live one.
  sendTransfer.pruneIndexOfMissingFiles()
  receiveTransfer.pruneIndexOfMissingFiles()

  true

proc receiveSessionEnd(conn: Connection, protocol: SyncProtocol, timeout: Duration): Future[bool] {.async.} =
  ## Reads until the buddy's session-end marker, the connection closes, or we
  ## give up. Anything else on the wire at this point is ignored rather than
  ## treated as an error: the session itself is already decided.
  let deadline = Moment.now() + timeout
  while true:
    let remaining = deadline - Moment.now()
    if remaining <= ZeroDuration:
      return false
    let msgOpt =
      try:
        await protocol.receiveMessage(conn).wait(remaining)
      except CatchableError:
        return false
    if msgOpt.isNone():
      return false
    if msgOpt.get().kind == msgSessionEnd:
      return true

proc awaitSessionEnd(conn: Connection, protocol: SyncProtocol, endsFirst: bool) {.async.} =
  ## Closes the session down in a fixed order, so neither side hangs up while
  ## the other still has bytes in flight.
  ##
  ## Whichever side finished its phases first used to close immediately, while
  ## the other was still waiting for a file ack and the final sync-done. A relay
  ## tears down both halves when one closes and drops whatever it still had
  ## buffered, so the slower side saw a truncated stream and reported failure on
  ## a sync that had in fact transferred everything. On loopback the bytes are
  ## always flushed already, which is why this only showed up over a real link.
  ##
  ## The same UUID comparison that orders the delta phases decides who speaks
  ## first here, keeping the conversation strictly alternating — a simultaneous
  ## exchange deadlocks on an unbuffered transport. The responder then waits for
  ## the initiator to hang up, so the last marker cannot be cut off either.
  ##
  ## Never fails the session: a buddy that predates this message just leaves us
  ## waiting for the timeout.
  if endsFirst:
    try:
      await protocol.sendMessage(conn, newSessionEnd())
    except CatchableError:
      return
    discard await receiveSessionEnd(conn, protocol, SessionEndTimeout)
  else:
    discard await receiveSessionEnd(conn, protocol, SessionEndTimeout)
    try:
      await protocol.sendMessage(conn, newSessionEnd())
    except CatchableError:
      return
    # Wait for the initiator to hang up before we do.
    discard await receiveSessionEnd(conn, protocol, SessionEndLingerTimeout)

proc syncBuddyFolders*(
    config: AppConfig,
    buddyId: string,
    conn: Connection,
    protocol: SyncProtocol,
): Future[bool] {.async.} =
  let sendListsFut = sendLocalFolderLists(config, buddyId, conn, protocol)
  let remoteLists = await receiveRemoteFolderLists(conn, protocol)
  if not await sendListsFut:
    return false

  var localFolders = applicableFolders(config, buddyId)
  localFolders.sort(proc(a, b: FolderConfig): int = cmp(a.name, b.name))

  var allOk = true
  for folder in localFolders:
    if folder.name notin remoteLists:
      continue
    if not await syncFolder(config, buddyId, buddyId, folder, remoteLists[folder.name], conn, protocol):
      allOk = false
      break

  await awaitSessionEnd(conn, protocol, config.buddy.uuid < buddyId)
  allOk
