import std/[algorithm, options, tables]
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
        info.encryptedPath = entry.path
        info.size = entry.size
        info.mtime = entry.mtime
        info.hash = stringToHash(entry.hash)
        files.add(info)
      result[msg.folderName] = files
    of msgSyncDone:
      return
    else:
      raise newException(CatchableError, "unexpected message while receiving folder lists")

proc requestPhase(
    transfer: FileTransfer,
    conn: Connection,
    filesNeeded: seq[FileInfo],
): Future[bool] {.async.} =
  for fileInfo in filesNeeded:
    if not await transfer.syncFile(conn, fileInfo):
      return false

  try:
    await transfer.protocol.sendMessage(conn, newSyncDone())
    true
  except CatchableError:
    false

proc servePhase(transfer: FileTransfer, conn: Connection): Future[bool] {.async.} =
  while true:
    let msgOpt = await transfer.protocol.receiveMessage(conn)
    if msgOpt.isNone():
      return false

    let msg = msgOpt.get()
    case msg.kind
    of msgSyncDone:
      return true
    of msgFileRequest:
      if not await transfer.sendFileData(conn, msg.requestPath, msg.requestOffset, msg.requestLength):
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
  let transfer = newFileTransfer(folder, protocol, config.bandwidthLimitKBps)
  defer: transfer.close()

  let filesNeeded = transfer.compareWithRemote(remoteFiles)
  let requestFirst = config.buddy.uuid < remoteBuddyId

  if requestFirst:
    if not await requestPhase(transfer, conn, filesNeeded):
      return false
    if not await servePhase(transfer, conn):
      return false
  else:
    if not await servePhase(transfer, conn):
      return false
    if not await requestPhase(transfer, conn, filesNeeded):
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
