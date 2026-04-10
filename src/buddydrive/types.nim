import std/times

const DefaultP2PPort* = 41721

type
  BuddyId* = object
    uuid*: string
    name*: string
  
  BuddyInfo* = object
    id*: BuddyId
    publicKey*: string
    addresses*: seq[string]
    relayToken*: string
    addedAt*: Time
  
  FolderConfig* = object
    name*: string
    path*: string
    encrypted*: bool
    appendOnly*: bool
    buddies*: seq[string]
  
  AppConfig* = object
    buddy*: BuddyId
    listenPort*: int
    announceAddr*: string
    relayBaseUrl*: string
    relayRegion*: string
    syncWindowStart*: string
    syncWindowEnd*: string
    bandwidthLimitKBps*: int
    folders*: seq[FolderConfig]
    buddies*: seq[BuddyInfo]
  
  FileInfo* = object
    path*: string
    encryptedPath*: string
    size*: int64
    mtime*: int64
    hash*: array[32, byte]
  
  FileChangeKind* = enum
    fcAdded
    fcModified
    fcDeleted
  
  FileChange* = object
    kind*: FileChangeKind
    info*: FileInfo
  
  ConnectionState* = enum
    csDisconnected
    csConnecting
    csConnected
    csSyncing
    csError
  
  SyncStatus* = object
    folder*: string
    totalBytes*: int64
    syncedBytes*: int64
    fileCount*: int
    syncedFiles*: int
    status*: string
  
  BuddyStatus* = object
    id*: string
    name*: string
    state*: ConnectionState
    latencyMs*: int
    lastSync*: Time

proc `$`*(id: BuddyId): string =
  if id.name.len > 0:
    result = id.name & " (" & id.uuid[0..7] & "...)"
  else:
    result = id.uuid[0..7] & "..."

proc shortId*(id: string): string =
  if id.len > 8:
    result = id[0..7] & "..."
  else:
    result = id

proc newBuddyId*(uuid: string, name: string = ""): BuddyId =
  result.uuid = uuid
  result.name = name

proc newFolderConfig*(name, path: string, encrypted = true): FolderConfig =
  result.name = name
  result.path = path
  result.encrypted = encrypted
  result.appendOnly = false
  result.buddies = @[]

proc newAppConfig*(buddy: BuddyId): AppConfig =
  result.buddy = buddy
  result.listenPort = DefaultP2PPort
  result.announceAddr = ""
  result.relayBaseUrl = ""
  result.relayRegion = ""
  result.syncWindowStart = ""
  result.syncWindowEnd = ""
  result.bandwidthLimitKBps = 0
  result.folders = @[]
  result.buddies = @[]
