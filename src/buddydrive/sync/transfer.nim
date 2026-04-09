import std/os
import std/times
import std/strutils
import std/sequtils
import results
import chronos
import libp2p/stream/connection
import ../p2p/messages
import ../p2p/protocol
import ../types
import scanner
import index

export results
export scanner
export index

type
  TransferError* = object of CatchableError
  
  FileTransfer* = ref object
    index*: FileIndex
    scanner*: FileScanner
    protocol*: SyncProtocol

const
  TransferChunkSize* = 64 * 1024

proc newFileTransfer*(folder: FolderConfig, protocol: SyncProtocol): FileTransfer =
  result = FileTransfer()
  result.scanner = newFileScanner(folder)
  result.index = newIndex(folder.name)
  result.protocol = protocol

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
    let msg = newFileData(data, currentOffset, fileSize, isDone)
    
    try:
      await transfer.protocol.sendMessage(conn, msg)
    except:
      return false
    
    currentOffset += chunkSize
    remaining -= chunkSize
  
  return true

proc receiveFileData*(transfer: FileTransfer, conn: Connection, path: string): Future[bool] {.async.} =
  let fullPath = transfer.scanner.rootPath / path
  
  createDir(fullPath.parentDir())
  
  var totalReceived: int64 = 0
  var success = true
  
  while true:
    let msgOpt = await transfer.protocol.receiveMessage(conn)
    if msgOpt.isNone or msgOpt.get().kind != msgFileData:
      success = false
      break
    
    let msg = msgOpt.get()
    
    if not writeFileChunk(fullPath, msg.dataOffset, msg.data):
      success = false
      break
    
    totalReceived += msg.data.len
    
    if msg.done:
      break
  
  let ack = newFileAck(success, totalReceived)
  try:
    await transfer.protocol.sendMessage(conn, ack)
  except:
    discard
  
  return success

proc syncFile*(transfer: FileTransfer, conn: Connection, fileInfo: FileInfo): Future[bool] {.async.} =
  if not await transfer.requestFile(conn, fileInfo.path):
    return false
  
  return await transfer.receiveFileData(conn, fileInfo.path)

proc compareWithRemote*(transfer: FileTransfer, remoteFiles: seq[FileInfo]): seq[FileInfo] =
  result = @[]
  
  let localFiles = transfer.index.getAllFiles()
  
  var localMap: Table[string, FileInfo]
  for f in localFiles:
    localMap[f.path] = f
  
  for remote in remoteFiles:
    if remote.path notin localMap:
      result.add(remote)
    else:
      let local = localMap[remote.path]
      if remote.mtime > local.mtime or remote.size != local.size:
        result.add(remote)
