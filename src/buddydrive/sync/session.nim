import std/[algorithm, options, tables]
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
  let localFiles = transfer.scanner.scanDirectory()

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
    if key in localByHash:
      let localFile = localByHash[key]
      if localFile.path in remoteByPath:
        result.deletes.add(remotePath)
        projectedByPath.del(remotePath)
      elif sameMoveCandidate(remoteFile, localFile):
        result.moves.add((remotePath, localFile.path, key))
        projectedByPath.del(remotePath)
        projectedByPath[localFile.path] = localFile
      else:
        result.deletes.add(remotePath)
        projectedByPath.del(remotePath)
    else:
      result.deletes.add(remotePath)
      projectedByPath.del(remotePath)

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

  true

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

  for folder in localFolders:
    if folder.name notin remoteLists:
      continue
    if not await syncFolder(config, buddyId, buddyId, folder, remoteLists[folder.name], conn, protocol):
      return false

  true
