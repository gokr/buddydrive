import std/os
import std/times
import std/strutils
import std/sequtils
import std/tables
import results
import chronos
import libp2p
import libp2p/stream/connection
import libp2p/protocols/protocol
import types
import config
import p2p/node
import p2p/protocol
import p2p/messages
import p2p/pairing
import sync/scanner
import sync/index
import sync/transfer

export results

type
  SyncManagerError* = object of CatchableError
  
  SyncManager* = ref object
    config*: AppConfig
    node*: BuddyNode
    transfers*: Table[string, FileTransfer]
    syncProtocol*: SyncProtocol
    running*: bool
    lastScan*: Time

const
  SyncProtocolId* = "/buddydrive/sync/1.0.0"
  ScanInterval* = chronos.seconds(5)

proc newSyncManager*(config: AppConfig, node: BuddyNode): SyncManager =
  result = SyncManager()
  result.config = config
  result.node = node
  result.transfers = initTable[string, FileTransfer]()
  result.syncProtocol = newSyncProtocol(node)
  result.running = false
  
  for folder in config.folders:
    let transfer = newFileTransfer(folder, result.syncProtocol)
    result.transfers[folder.name] = transfer

proc close*(manager: SyncManager) =
  for name, transfer in manager.transfers:
    transfer.close()
  manager.transfers.clear()

proc scanFolders*(manager: SyncManager): seq[FileChange] =
  result = @[]
  
  for name, transfer in manager.transfers:
    let files = transfer.scanner.scanDirectory()
    let previous = transfer.index.getAllFiles()
    
    for f in files:
      let existing = transfer.index.getFile(f.path)
      if existing.isNone:
        result.add(FileChange(kind: fcAdded, info: f))
        transfer.index.addFile(f)
      elif existing.get().mtime < f.mtime:
        result.add(FileChange(kind: fcModified, info: f))
        transfer.index.addFile(f)
    
    let currentPaths = files.mapIt(it.path).toHashSet()
    for prev in previous:
      if prev.path notin currentPaths:
        result.add(FileChange(kind: fcDeleted, info: prev))
        transfer.index.removeFile(prev.path)
    
    manager.lastScan = getTime()

proc broadcastFileList*(manager: SyncManager, conn: Connection): Future[bool] {.async.} =
  for name, transfer in manager.transfers:
    if not await transfer.sendFileList(conn):
      return false
  return true

proc handleSyncRequest*(manager: SyncManager, conn: Connection, buddyId: string): Future[void] {.async.} =
  let msgOpt = await manager.syncProtocol.receiveMessage(conn)
  if msgOpt.isNone:
    return
  
  let msg = msgOpt.get()
  
  case msg.kind
  of msgFileList:
    echo "Received file list for: ", msg.folderName
    
    if buddyId in manager.transfers:
      let transfer = manager.transfers[buddyId]
      var files: seq[FileInfo] = @[]
      for entry in msg.files:
        var info: FileInfo
        info.path = entry.path
        info.encryptedPath = entry.path
        info.size = entry.size
        info.mtime = entry.mtime
        info.hash = stringToHash(entry.hash)
        files.add(info)
      
      let needed = transfer.compareWithRemote(files)
      echo "Need to sync ", needed.len, " files"
      
      for f in needed:
        if await transfer.syncFile(conn, f):
          transfer.index.markSynced(f.path)
          echo "Synced: ", f.path
  
  of msgFileRequest:
    let path = msg.requestPath
    echo "File request for: ", path
    
    for name, transfer in manager.transfers:
      let fullPath = transfer.scanner.rootPath / path
      if fileExists(fullPath):
        await transfer.sendFileData(conn, path, msg.requestOffset, msg.requestLength)
        return
    
    let ack = newFileAck(false)
    await manager.syncProtocol.sendMessage(conn, ack)
  
  of msgFileData:
    discard
  
  of msgFileAck:
    discard
  
  of msgFileDelete:
    for name, transfer in manager.transfers:
      let fullPath = transfer.scanner.rootPath / msg.deletedPath
      if fileExists(fullPath):
        try:
          removeFile(fullPath)
          transfer.index.removeFile(msg.deletedPath)
          echo "Deleted: ", msg.deletedPath
        except:
          discard
  
  of msgPing:
    let pong = newPong(msg.timestamp)
    await manager.syncProtocol.sendMessage(conn, pong)
  
  of msgPong:
    discard

proc syncWithBuddy*(manager: SyncManager, buddyId: string, conn: Connection): Future[bool] {.async.} =
  for name, transfer in manager.transfers:
    if buddyId in transfer.folder.buddies:
      let files = transfer.scanner.scanDirectory()
      let entries = files.map(proc(f: FileInfo): FileEntry =
        FileEntry(path: f.path, size: f.size, mtime: f.mtime, hash: hashToString(f.hash))
      )
      
      let msg = newFileList(name, entries)
      await manager.syncProtocol.sendMessage(conn, msg)
      
      let responseOpt = await manager.syncProtocol.receiveMessage(conn)
      if responseOpt.isNone or responseOpt.get().kind != msgFileList:
        return false
      
      let response = responseOpt.get()
      var remoteFiles: seq[FileInfo] = @[]
      for entry in response.files:
        var info: FileInfo
        info.path = entry.path
        info.encryptedPath = entry.path
        info.size = entry.size
        info.mtime = entry.mtime
        info.hash = stringToHash(entry.hash)
        remoteFiles.add(info)
      
      let needed = transfer.compareWithRemote(remoteFiles)
      
      for f in needed:
        if await transfer.syncFile(conn, f):
          transfer.index.markSynced(f.path)
      
      return true
  
  return false

proc startSyncLoop*(manager: SyncManager) {.async.} =
  manager.running = true
  
  while manager.running:
    let changes = manager.scanFolders()
    
    if changes.len > 0:
      echo "Detected ", changes.len, " file changes"
    
    await sleepAsync(ScanInterval)

proc stop*(manager: SyncManager) =
  manager.running = false
  manager.close()
