import std/os
import std/times
import std/strutils
import std/sequtils
import std/hashes
import ../types

export types

type
  ScannerError* = object of CatchableError
  
  FileScanner* = ref object
    folder*: FolderConfig
    rootPath*: string

proc hashFile(path: string): array[32, byte] =
  result = default(array[32, byte])
  try:
    let content = readFile(path)
    let h = hashes.hash(content)
    for i in 0..<8:
      result[i] = byte(h shr (i * 8))
  except:
    discard

proc newFileScanner*(folder: FolderConfig): FileScanner =
  result = FileScanner()
  result.folder = folder
  result.rootPath = folder.path

proc scanFile*(scanner: FileScanner, path: string): FileInfo =
  let relativePath = path[scanner.rootPath.len..^1]
  if relativePath.startsWith("/") or relativePath.startsWith("\\"):
    result.path = relativePath[1..^1]
  else:
    result.path = relativePath
  
  result.encryptedPath = result.path
  
  try:
    let info = getFileInfo(path)
    result.size = info.size
    result.mtime = info.lastWriteTime.toUnix()
    result.hash = hashFile(path)
  except:
    result.size = 0
    result.mtime = 0

proc scanDirectory*(scanner: FileScanner): seq[FileInfo] =
  result = @[]
  
  if not dirExists(scanner.rootPath):
    return result
  
  for path in walkDirRec(scanner.rootPath, relative = false):
    if path.fileExists():
      result.add(scanner.scanFile(path))

proc scanChanges*(scanner: FileScanner, previous: seq[FileInfo]): seq[FileChange] =
  result = @[]
  
  let current = scanner.scanDirectory()
  
  var currentMap: Table[string, FileInfo]
  for f in current:
    currentMap[f.path] = f
  
  var previousMap: Table[string, FileInfo]
  for f in previous:
    previousMap[f.path] = f
  
  for path, info in currentMap:
    if path notin previousMap:
      result.add(FileChange(kind: fcAdded, info: info))
    else:
      let prev = previousMap[path]
      if info.mtime > prev.mtime or info.size != prev.size:
        result.add(FileChange(kind: fcModified, info: info))
  
  for path, info in previousMap:
    if path notin currentMap:
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
      f = open(path, fmReadWrite)
    else:
      createDir(path.parentDir())
      f = open(path, fmReadWrite)
    
    defer: f.close()
    
    f.setFilePos(offset)
    f.writeBytes(data, 0, data.len)
    result = true
  except:
    result = false
