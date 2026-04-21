import std/os except FileInfo
import std/options
import std/[times, strutils, tables, sets, syncio]
when defined(posix):
  import std/posix_utils
import ../types
import ../crypto
import index

export types

const
  TempSuffix* = ".buddytmp"

type
  ScannerError* = object of CatchableError
  
  FileScanner* = ref object
    folder*: FolderConfig
    rootPath*: string
    index*: FileIndex

when defined(testing):
  var flushAndCloseShouldFail* {.threadvar.}: bool

  proc setFlushAndCloseShouldFail*(shouldFail: bool) =
    flushAndCloseShouldFail = shouldFail

proc hashKey(h: array[32, byte]): string =
  for b in h:
    result.add(b.toHex(2).toLower())

proc permissionsToMode(perms: set[FilePermission]): int =
  if fpUserRead in perms:
    result = result or 0o400
  if fpUserWrite in perms:
    result = result or 0o200
  if fpUserExec in perms:
    result = result or 0o100
  if fpGroupRead in perms:
    result = result or 0o040
  if fpGroupWrite in perms:
    result = result or 0o020
  if fpGroupExec in perms:
    result = result or 0o010
  if fpOthersRead in perms:
    result = result or 0o004
  if fpOthersWrite in perms:
    result = result or 0o002
  if fpOthersExec in perms:
    result = result or 0o001

proc stringToBytes(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for i, c in value:
    result[i] = byte(c)

proc newFileScanner*(folder: FolderConfig, index: FileIndex = nil): FileScanner =
  result = FileScanner()
  result.folder = folder
  result.rootPath = folder.path
  result.index = index

proc sameCachedRegularFile(current: types.FileInfo, cached: types.FileInfo): bool =
  current.mtime == cached.mtime and
  current.size == cached.size and
  current.mode == cached.mode and
  cached.symlinkTarget.len == 0

proc sameCachedSymlink(current: types.FileInfo, cached: types.FileInfo): bool =
  current.mtime == cached.mtime and
  current.size == cached.size and
  current.mode == cached.mode and
  current.symlinkTarget == cached.symlinkTarget

proc scanFileUsingCache(scanner: FileScanner, path: string): types.FileInfo =
  let relativePath = path[scanner.rootPath.len..^1]
  if relativePath.startsWith("/") or relativePath.startsWith("\\"):
    result.path = relativePath[1..^1]
  else:
    result.path = relativePath

  try:
    if scanner.folder.encrypted and scanner.folder.folderKey.len == KeySize:
      result.encryptedPath = encryptPath(result.path, scanner.folder.folderKey)
    else:
      result.encryptedPath = result.path

    let info = getFileInfo(path, followSymlink = false)
    result.mode = permissionsToMode(info.permissions)
    result.mtime = info.lastWriteTime.toUnix()

    let cached = if scanner.index != nil: scanner.index.getFile(result.path) else: none(types.FileInfo)
    if symlinkExists(path):
      result.symlinkTarget = expandSymlink(path)
      result.size = result.symlinkTarget.len.int64
      if cached.isSome and sameCachedSymlink(result, cached.get()):
        result.hash = cached.get().hash
      else:
        result.hash = hashBytes(stringToBytes(result.symlinkTarget))
    else:
      result.size = info.size
      if cached.isSome and sameCachedRegularFile(result, cached.get()):
        result.hash = cached.get().hash
      else:
        result.hash = hashFileStream(path)

    if scanner.index != nil:
      scanner.index.cacheScannedFile(result)
  except:
    result.encryptedPath = result.path
    result.size = 0
    result.mtime = 0

proc scanFile*(scanner: FileScanner, path: string): types.FileInfo =
  let relativePath = path[scanner.rootPath.len..^1]
  if relativePath.startsWith("/") or relativePath.startsWith("\\"):
    result.path = relativePath[1..^1]
  else:
    result.path = relativePath
  
  try:
    if scanner.folder.encrypted and scanner.folder.folderKey.len == KeySize:
      result.encryptedPath = encryptPath(result.path, scanner.folder.folderKey)
    else:
      result.encryptedPath = result.path
    
    let info = getFileInfo(path, followSymlink = false)
    result.mode = permissionsToMode(info.permissions)
    result.mtime = info.lastWriteTime.toUnix()

    if symlinkExists(path):
      result.symlinkTarget = expandSymlink(path)
      result.size = result.symlinkTarget.len.int64
      result.hash = hashBytes(stringToBytes(result.symlinkTarget))
    else:
      result.size = info.size
      result.hash = hashFileStream(path)
  except:
    result.encryptedPath = result.path
    result.size = 0
    result.mtime = 0

proc walkDirNoFollow(root: string, results: var seq[string]) =
  var stack = @[root]
  while stack.len > 0:
    let current = stack.pop()
    for kind, path in walkDir(current, relative = false, checkDir = true):
      if path.endsWith(TempSuffix):
        continue
      case kind
      of pcFile:
        results.add(path)
      of pcLinkToFile:
        results.add(path)
      of pcLinkToDir:
        results.add(path)
      of pcDir:
        if not symlinkExists(path):
          stack.add(path)

proc scanDirectory*(scanner: FileScanner): seq[types.FileInfo] =
  result = @[]
  
  if not dirExists(scanner.rootPath):
    return result
  
  var paths: seq[string] = @[]
  walkDirNoFollow(scanner.rootPath, paths)
  for path in paths:
    result.add(scanner.scanFileUsingCache(path))

proc scanChanges*(scanner: FileScanner, previous: seq[types.FileInfo]): seq[FileChange] =
  result = @[]
  
  let current = scanner.scanDirectory()
  
  var currentMap: Table[string, types.FileInfo]
  for f in current:
    currentMap[f.path] = f
  
  var previousMap: Table[string, types.FileInfo]
  for f in previous:
    previousMap[f.path] = f
  
  var hashToCurrentPath: Table[string, string]
  for path, info in currentMap:
    let h = hashKey(info.hash)
    hashToCurrentPath[h] = path
  
  var movedPaths: HashSet[string]
  init(movedPaths)
  
  for path, prevInfo in previousMap:
    if path notin currentMap:
      let h = hashKey(prevInfo.hash)
      if h in hashToCurrentPath:
        let newPath = hashToCurrentPath[h]
        if newPath notin previousMap:
          movedPaths.incl(newPath)
          result.add(FileChange(kind: fcMoved, info: currentMap[newPath], oldPath: path))
  
  for path, info in currentMap:
    if path in movedPaths:
      continue
    if path notin previousMap:
      result.add(FileChange(kind: fcAdded, info: info))
    else:
      let prev = previousMap[path]
      if info.mtime != prev.mtime or info.size != prev.size:
        if info.hash != prev.hash:
          result.add(FileChange(kind: fcModified, info: info))
      elif info.mode != prev.mode or info.symlinkTarget != prev.symlinkTarget:
        result.add(FileChange(kind: fcModified, info: info))
  
  for path, info in previousMap:
    if path notin currentMap:
      let h = hashKey(info.hash)
      if h notin hashToCurrentPath or hashToCurrentPath[h] in previousMap:
        result.add(FileChange(kind: fcDeleted, info: info))

proc readFileChunk*(path: string, offset: int64, length: int): seq[byte] =
  result = @[]
  try:
    let f = open(path, fmRead)
    defer: f.close()
    
    f.setFilePos(offset)
    
    let actualLength = min(length, f.getFileSize() - offset)
    if actualLength <= 0:
      return result
    
    result = newSeq[byte](actualLength)
    discard f.readBytes(result, 0, actualLength.int)
  except:
    result = @[]

proc writeFileChunk*(path: string, offset: int64, data: seq[byte]): bool =
  try:
    var f: File
    if fileExists(path):
      f = open(path, fmReadWriteExisting)
    else:
      createDir(path.parentDir())
      if offset == 0:
        f = open(path, fmWrite)
      else:
        let createFile = open(path, fmWrite)
        createFile.close()
        f = open(path, fmReadWriteExisting)

    defer: f.close()

    f.setFilePos(offset)
    result = f.writeBytes(data, 0, data.len) == data.len
  except:
    result = false

proc flushAndClose*(path: string) =
  when defined(testing):
    if flushAndCloseShouldFail:
      raise newException(IOError, "simulated flush failure")
  let f = open(path, fmReadWriteExisting)
  defer: f.close()
  when defined(posix):
    fsync(int(getFileHandle(f)))
  else:
    flushFile(f)

proc cleanupTempFiles*(rootPath: string) =
  if not dirExists(rootPath):
    return
  for path in walkDirRec(rootPath, relative = false):
    if path.endsWith(TempSuffix):
      try:
        removeFile(path)
      except:
        discard
