import std/os except FileInfo
import std/options
import std/tables
import std/sequtils
import results
import chronos
import lz4
import libp2p/stream/connection
import ../p2p/messages
import ../p2p/protocol
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
  result.scanner = newFileScanner(folder)
  result.index = newIndex(folder.name & "|" & folder.path)
  result.protocol = protocol
  result.throttler = newThrottler(0)

proc newFileTransfer*(folder: FolderConfig, protocol: SyncProtocol, bandwidthLimitKBps: int): FileTransfer =
  result = FileTransfer()
  result.scanner = newFileScanner(folder)
  result.index = newIndex(folder.name & "|" & folder.path)
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

proc sendFileList*(transfer: FileTransfer, conn: Connection): Future[bool] {.async.} =
  let files = transfer.scanner.scanDirectory()
  
  let entries = files.map(proc(f: FileInfo): FileEntry =
    FileEntry(path: f.path, size: f.size, mtime: f.mtime, hash: hashToString(f.hash))
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
    info.encryptedPath = entry.path
    info.size = entry.size
    info.mtime = entry.mtime
    info.hash = stringToHash(entry.hash)
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

proc receiveFileData*(transfer: FileTransfer, conn: Connection, path: string): Future[bool] {.async.} =
  let fullPath = transfer.scanner.rootPath / path
  let tmpPath = fullPath & TempSuffix

  createDir(fullPath.parentDir())

  var totalReceived: int64 = 0
  var success = true

  while true:
    let msgOpt = await transfer.protocol.receiveMessage(conn)
    if msgOpt.isNone or msgOpt.get().kind != msgFileData:
      success = false
      break

    let msg = msgOpt.get()

    var payload = msg.data
    if msg.dataCompression == ckLz4:
      try:
        payload = decompress(msg.data, msg.dataOriginalLen)
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
    discard flushAndClose(tmpPath)
    try:
      moveFile(tmpPath, fullPath)
    except:
      success = false

  if not success:
    try:
      removeFile(tmpPath)
    except:
      discard

  let ack = newFileAck(success, totalReceived)
  try:
    await transfer.protocol.sendMessage(conn, ack)
  except:
    discard

  if success and fileExists(fullPath):
    transfer.index.addFile(transfer.scanner.scanFile(fullPath), synced = true)

  return success

proc syncFile*(transfer: FileTransfer, conn: Connection, fileInfo: FileInfo): Future[bool] {.async.} =
  if not await transfer.requestFile(conn, fileInfo.path):
    return false
  
  return await transfer.receiveFileData(conn, fileInfo.path)

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
