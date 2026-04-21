import std/os except FileInfo
import std/options
import std/tables
import std/sequtils
import std/times
import results
import chronos
import lz4
import libp2p/stream/connection
import ../p2p/messages
import ../p2p/protocol
import ../crypto
import ../types
import scanner
import index
import policy

export results
export scanner
export index

type
  TransferError* = object of CatchableError
  
  Throttler* = ref object
    bytesPerSecond*: int
    lastTime*: Moment
    bytesSent*: int64
  
  FileTransfer* = ref object
    index*: FileIndex
    scanner*: FileScanner
    protocol*: SyncProtocol
    throttler*: Throttler

const
  TransferChunkSize* = 64 * 1024

proc newThrottler*(bytesPerSecond: int): Throttler =
  result = Throttler()
  result.bytesPerSecond = bytesPerSecond
  result.lastTime = Moment.now()
  result.bytesSent = 0

proc newFileTransfer*(folder: FolderConfig, protocol: SyncProtocol): FileTransfer =
  result = FileTransfer()
  result.index = newIndex(folder.name & "|" & folder.path)
  result.scanner = newFileScanner(folder, result.index)
  result.protocol = protocol
  result.throttler = newThrottler(0)

proc newFileTransfer*(folder: FolderConfig, protocol: SyncProtocol, bandwidthLimitKBps: int): FileTransfer =
  result = FileTransfer()
  result.index = newIndex(folder.name & "|" & folder.path)
  result.scanner = newFileScanner(folder, result.index)
  result.protocol = protocol
  result.throttler = newThrottler(bandwidthLimitKBps * 1024)

proc throttle*(t: Throttler, bytes: int) {.async.} =
  if t.bytesPerSecond <= 0:
    return
  
  let now = Moment.now()
  let elapsed = (now - t.lastTime).nanoseconds
  
  if elapsed >= 1_000_000_000:
    t.lastTime = now
    t.bytesSent = 0
  else:
    t.bytesSent += bytes
    let allowedBytes = (elapsed.int64 * t.bytesPerSecond.int64) div 1_000_000_000
    if t.bytesSent > allowedBytes:
      let excessBytes = t.bytesSent - allowedBytes
      let sleepNanos = (excessBytes * 1_000_000_000) div t.bytesPerSecond.int64
      if sleepNanos > 0:
        await sleepAsync(chronos.nanoseconds(sleepNanos))

proc close*(transfer: FileTransfer) =
  if transfer.index != nil:
    transfer.index.close()

proc hasExpectedHash(fileInfo: FileInfo): bool =
  for b in fileInfo.hash:
    if b != 0:
      return true
  false

proc rebuildIndexFromDisk*(transfer: FileTransfer) =
  var onDisk: Table[string, FileInfo]
  for fileInfo in transfer.scanner.scanDirectory():
    onDisk[fileInfo.path] = fileInfo
    transfer.index.addFile(fileInfo, synced = true)

  for existing in transfer.index.getAllFiles():
    if existing.path notin onDisk:
      transfer.index.removeFile(existing.path)

proc verifyRestoredFile(transfer: FileTransfer, path: string, expected: FileInfo): bool =
  if not fileExists(path) and not symlinkExists(path):
    return false

  let actual = transfer.scanner.scanFile(path)
  if hasExpectedHash(expected) and actual.hash != expected.hash:
    return false
  if expected.symlinkTarget.len > 0 and actual.symlinkTarget != expected.symlinkTarget:
    return false
  if expected.mode != 0 and actual.mode != expected.mode:
    return false
  true

proc useEncryptedChunks(transfer: FileTransfer): bool =
  transfer.scanner.folder.encrypted and transfer.scanner.folder.folderKey.len == KeySize

proc modeToPermissions(mode: int): set[FilePermission] =
  if (mode and 0o400) != 0:
    result.incl(fpUserRead)
  if (mode and 0o200) != 0:
    result.incl(fpUserWrite)
  if (mode and 0o100) != 0:
    result.incl(fpUserExec)
  if (mode and 0o040) != 0:
    result.incl(fpGroupRead)
  if (mode and 0o020) != 0:
    result.incl(fpGroupWrite)
  if (mode and 0o010) != 0:
    result.incl(fpGroupExec)
  if (mode and 0o004) != 0:
    result.incl(fpOthersRead)
  if (mode and 0o002) != 0:
    result.incl(fpOthersWrite)
  if (mode and 0o001) != 0:
    result.incl(fpOthersExec)

proc applyFileMetadata(path: string, fileInfo: FileInfo) {.raises: [].} =
  if fileInfo.symlinkTarget.len == 0 and fileInfo.mode != 0:
    try:
      setFilePermissions(path, modeToPermissions(fileInfo.mode))
    except:
      discard

  if fileInfo.mtime > 0:
    try:
      setLastModificationTime(path, fromUnix(fileInfo.mtime))
    except:
      discard

proc createSymlinkFile(path: string, fileInfo: FileInfo): bool {.raises: [].} =
  if fileInfo.symlinkTarget.len == 0:
    return false

  try:
    createDir(path.parentDir())
    if symlinkExists(path) or fileExists(path):
      removeFile(path)
    createSymlink(fileInfo.symlinkTarget, path)
    applyFileMetadata(path, fileInfo)
    true
  except:
    false

proc sendFileList*(transfer: FileTransfer, conn: Connection): Future[bool] {.async.} =
  let files = transfer.scanner.scanDirectory()
  
  let entries = files.map(proc(f: FileInfo): FileEntry =
    FileEntry(
      path: f.path,
      encryptedPath: f.encryptedPath,
      size: f.size,
      mtime: f.mtime,
      hash: hashToString(f.hash),
      mode: f.mode,
      symlinkTarget: f.symlinkTarget,
    )
  )
  
  let msg = newFileList(transfer.scanner.folder.name, entries)
  
  try:
    await transfer.protocol.sendMessage(conn, msg)
    return true
  except:
    return false

proc receiveFileList*(transfer: FileTransfer, conn: Connection): Future[Option[seq[FileInfo]]] {.async.} =
  let msgOpt = await transfer.protocol.receiveMessage(conn)
  if msgOpt.isNone or msgOpt.get().kind != msgFileList:
    return none(seq[FileInfo])
  
  let msg = msgOpt.get()
  
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
  
  return some(files)

proc requestFile*(transfer: FileTransfer, conn: Connection, path: string, offset: int64 = 0, length: int = -1): Future[bool] {.async.} =
  let msg = newFileRequest(path, offset, length)
  
  try:
    await transfer.protocol.sendMessage(conn, msg)
    return true
  except:
    return false

proc receiveFileRequest*(transfer: FileTransfer, conn: Connection): Future[Option[tuple[path: string, offset: int64, length: int]]] {.async.} =
  let msgOpt = await transfer.protocol.receiveMessage(conn)
  if msgOpt.isNone or msgOpt.get().kind != msgFileRequest:
    return none((string, int64, int))
  
  let msg = msgOpt.get()
  return some((msg.requestPath, msg.requestOffset, msg.requestLength))

proc requestListPaths*(transfer: FileTransfer, conn: Connection): Future[Option[seq[FileInfo]]] {.async.} =
  try:
    await transfer.protocol.sendMessage(conn, newListPathsRequest(transfer.scanner.folder.name))
  except CatchableError:
    return none(seq[FileInfo])

  let msgOpt = await transfer.protocol.receiveMessage(conn)
  if msgOpt.isNone or msgOpt.get().kind != msgListPathsResponse:
    return none(seq[FileInfo])

  let msg = msgOpt.get()
  if msg.listResponseFolderName != transfer.scanner.folder.name:
    return none(seq[FileInfo])

  var files: seq[FileInfo] = @[]
  for entry in msg.listFiles:
    var info: FileInfo
    info.path = entry.path
    info.encryptedPath = entry.encryptedPath
    info.size = entry.size
    info.mtime = entry.mtime
    info.hash = stringToHash(entry.hash)
    info.mode = entry.mode
    info.symlinkTarget = entry.symlinkTarget
    files.add(info)

  return some(files)

proc sendListPathsResponse*(transfer: FileTransfer, conn: Connection): Future[bool] {.async.} =
  let files = transfer.scanner.scanDirectory()
  let entries = files.map(proc(f: FileInfo): FileEntry =
    FileEntry(
      path: f.path,
      encryptedPath: f.encryptedPath,
      size: f.size,
      mtime: f.mtime,
      hash: hashToString(f.hash),
      mode: f.mode,
      symlinkTarget: f.symlinkTarget,
    )
  )

  try:
    await transfer.protocol.sendMessage(conn, newListPathsResponse(transfer.scanner.folder.name, entries))
    return true
  except CatchableError:
    return false

proc sendFileData*(transfer: FileTransfer, conn: Connection, path: string, offset: int64, length: int): Future[bool] {.async.} =
  let fullPath = transfer.scanner.rootPath / path
  
  if not fileExists(fullPath):
    let ack = newFileAck(false)
    await transfer.protocol.sendMessage(conn, ack)
    return false
  
  let fileSize = getFileSize(fullPath)
  let actualLength = if length < 0: int(fileSize - offset) else: min(length, int(fileSize - offset))
  
  if actualLength <= 0:
    let ack = newFileAck(false)
    await transfer.protocol.sendMessage(conn, ack)
    return false
  
  var currentOffset = offset
  var remaining = actualLength
  
  while remaining > 0:
    let chunkSize = min(remaining, TransferChunkSize)
    let data = readFileChunk(fullPath, currentOffset, chunkSize)
    
    if data.len == 0:
      let ack = newFileAck(false)
      await transfer.protocol.sendMessage(conn, ack)
      return false
    
    let isDone = remaining <= chunkSize
    var payload = data
    var compression = ckNone
    try:
      let compressed = compress(data)
      if compressed.len > 0 and compressed.len < data.len:
        payload = compressed
        compression = ckLz4
    except CatchableError:
      discard

    if transfer.useEncryptedChunks():
      try:
        payload = encryptChunk(payload, transfer.scanner.folder.folderKey)
      except CatchableError:
        let ack = newFileAck(false)
        await transfer.protocol.sendMessage(conn, ack)
        return false

    let msg = newFileData(payload, currentOffset, fileSize, isDone, compression, data.len)
    
    try:
      await transfer.protocol.sendMessage(conn, msg)
      await transfer.throttler.throttle(data.len)
    except:
      return false
    
    currentOffset += chunkSize
    remaining -= chunkSize

  let ackOpt = await transfer.protocol.receiveMessage(conn)
  if ackOpt.isNone or ackOpt.get().kind != msgFileAck:
    return false

  ackOpt.get().success

proc receiveFileData*(transfer: FileTransfer, conn: Connection, fileInfo: FileInfo): Future[bool] {.async.} =
  let fullPath = transfer.scanner.rootPath / fileInfo.path
  let tmpPath = fullPath & TempSuffix

  createDir(fullPath.parentDir())

  var totalReceived: int64 = 0
  var expectedSize = int64(-1)
  var success = true

  while true:
    let msgOpt = await transfer.protocol.receiveMessage(conn)
    if msgOpt.isNone or msgOpt.get().kind != msgFileData:
      success = false
      break

    let msg = msgOpt.get()

    if msg.dataOffset != totalReceived:
      success = false
      break

    if expectedSize < 0:
      expectedSize = msg.totalSize
    elif msg.totalSize != expectedSize:
      success = false
      break

    var payload = msg.data
    if transfer.useEncryptedChunks():
      try:
        payload = decryptChunk(payload, transfer.scanner.folder.folderKey)
      except CatchableError:
        success = false
        break

    if msg.dataCompression == ckLz4:
      try:
        payload = decompress(payload, msg.dataOriginalLen)
      except CatchableError:
        success = false
        break

    if not writeFileChunk(tmpPath, msg.dataOffset, payload):
      success = false
      break

    totalReceived += payload.len

    if msg.done:
      break

  if success:
    if expectedSize >= 0 and totalReceived != expectedSize:
      success = false

  if success:
    try:
      flushAndClose(tmpPath)
      moveFile(tmpPath, fullPath)
      applyFileMetadata(fullPath, fileInfo)
    except:
      success = false

  if not success:
    try:
      removeFile(tmpPath)
    except:
      discard

  if success and (fileExists(fullPath) or symlinkExists(fullPath)):
    if transfer.verifyRestoredFile(fullPath, fileInfo):
      transfer.index.addFile(transfer.scanner.scanFile(fullPath), synced = true)
    else:
      success = false
      try:
        removeFile(fullPath)
      except:
        discard

  let ack = newFileAck(success, totalReceived)
  try:
    await transfer.protocol.sendMessage(conn, ack)
  except:
    discard

  return success

proc receiveFileData*(transfer: FileTransfer, conn: Connection, path: string): Future[bool] {.async.} =
  var fileInfo: FileInfo
  fileInfo.path = path
  return await transfer.receiveFileData(conn, fileInfo)

proc syncFile*(transfer: FileTransfer, conn: Connection, fileInfo: FileInfo): Future[bool] {.async.} =
  let fullPath = transfer.scanner.rootPath / fileInfo.path

  if fileInfo.symlinkTarget.len > 0:
    if not createSymlinkFile(fullPath, fileInfo):
      return false
    if symlinkExists(fullPath):
      if transfer.verifyRestoredFile(fullPath, fileInfo):
        transfer.index.addFile(transfer.scanner.scanFile(fullPath), synced = true)
        return true
      try:
        removeFile(fullPath)
      except:
        discard
    return false

  if not await transfer.requestFile(conn, fileInfo.path):
    return false
  
  return await transfer.receiveFileData(conn, fileInfo)

proc deleteLocalFile*(transfer: FileTransfer, path: string): bool {.raises: [].} =
  let fullPath = transfer.scanner.rootPath / path

  try:
    if symlinkExists(fullPath) or fileExists(fullPath):
      removeFile(fullPath)
    transfer.index.removeFile(path)
    return true
  except:
    return false

proc moveLocalFile*(transfer: FileTransfer, oldPath: string, newPath: string): bool {.raises: [].} =
  let oldFullPath = transfer.scanner.rootPath / oldPath
  let newFullPath = transfer.scanner.rootPath / newPath

  try:
    createDir(newFullPath.parentDir())
    moveFile(oldFullPath, newFullPath)
    transfer.index.removeFile(oldPath)
    transfer.index.addFile(transfer.scanner.scanFile(newFullPath), synced = true)
    return true
  except:
    return false

proc compareWithRemote*(transfer: FileTransfer, remoteFiles: seq[FileInfo]): seq[FileInfo] =
  result = @[]
  
  let localFiles = transfer.scanner.scanDirectory()
  
  var localMap: Table[string, FileInfo]
  for f in localFiles:
    localMap[f.path] = f
  
  for remote in remoteFiles:
    if remote.path notin localMap:
      result.add(remote)
    elif shouldSyncRemoteFile(transfer.scanner.folder, remote, true, localMap[remote.path]):
      result.add(remote)
