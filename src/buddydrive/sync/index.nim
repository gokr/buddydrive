import std/[options, times, strutils]
import db_connector/db_sqlite
import ../types
import ../config

export types

type
  IndexError* = object of CatchableError
  
  FileIndex* = ref object
    db*: DbConn
    folderName*: string

proc newIndex*(folderName: string): FileIndex =
  result = FileIndex()
  result.folderName = folderName
  
  let dbPath = config.getIndexPath()
  config.ensureDataDir()
  
  let db = open(dbPath, "", "", "")
  result.db = db
  
  let createTable = """
    CREATE TABLE IF NOT EXISTS files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      folder TEXT NOT NULL,
      path TEXT NOT NULL,
      encrypted_path TEXT NOT NULL,
      size INTEGER NOT NULL,
      mtime INTEGER NOT NULL,
      hash BLOB NOT NULL,
      synced INTEGER DEFAULT 0,
      last_sync INTEGER DEFAULT 0,
      UNIQUE(folder, path)
    );
    CREATE INDEX IF NOT EXISTS idx_folder_path ON files(folder, path);
    CREATE INDEX IF NOT EXISTS idx_folder_synced ON files(folder, synced);
  """
  
  discard db.tryExec(sql(createTable))

proc close*(index: FileIndex) =
  if index.db != nil:
    index.db.close()

proc hashToString*(hash: array[32, byte]): string =
  result = ""
  for b in hash:
    result.add(b.toHex(2).toLower())

proc stringToHash*(s: string): array[32, byte] =
  result = default(array[32, byte])
  for i in 0..<min(s.len div 2, 32):
    let hex = s[i*2..min(i*2+1, s.len-1)]
    try:
      result[i] = fromHex[byte](hex)
    except:
      discard

proc addFile*(index: FileIndex, info: types.FileInfo, synced: bool = false) =
  let hashStr = hashToString(info.hash)
  let query = """
    INSERT OR REPLACE INTO files (folder, path, encrypted_path, size, mtime, hash, synced, last_sync)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """
  let lastSync = if synced: getTime().toUnix() else: 0
  discard index.db.tryExec(sql(query), index.folderName, info.path, info.encryptedPath, info.size, info.mtime, hashStr, if synced: 1 else: 0, lastSync)

proc removeFile*(index: FileIndex, path: string) =
  let query = "DELETE FROM files WHERE folder = ? AND path = ?"
  discard index.db.tryExec(sql(query), index.folderName, path)

proc getFile*(index: FileIndex, path: string): Option[types.FileInfo] =
  let query = "SELECT path, encrypted_path, size, mtime, hash FROM files WHERE folder = ? AND path = ?"
  for row in index.db.rows(sql(query), index.folderName, path):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    return some(info)
  return none(types.FileInfo)

proc getAllFiles*(index: FileIndex): seq[types.FileInfo] =
  result = @[]
  let query = "SELECT path, encrypted_path, size, mtime, hash FROM files WHERE folder = ?"
  for row in index.db.rows(sql(query), index.folderName):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    result.add(info)

proc getUnsyncedFiles*(index: FileIndex): seq[types.FileInfo] =
  result = @[]
  let query = "SELECT path, encrypted_path, size, mtime, hash FROM files WHERE folder = ? AND synced = 0"
  for row in index.db.rows(sql(query), index.folderName):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    result.add(info)

proc markSynced*(index: FileIndex, path: string) =
  let query = "UPDATE files SET synced = 1, last_sync = ? WHERE folder = ? AND path = ?"
  discard index.db.tryExec(sql(query), getTime().toUnix(), index.folderName, path)

proc markAllSynced*(index: FileIndex) =
  let query = "UPDATE files SET synced = 1, last_sync = ? WHERE folder = ?"
  discard index.db.tryExec(sql(query), getTime().toUnix(), index.folderName)

proc getSyncStatus*(index: FileIndex): tuple[total: int, synced: int, pending: int] =
  result = (0, 0, 0)
  
  let totalQuery = "SELECT COUNT(*) FROM files WHERE folder = ?"
  for row in index.db.rows(sql(totalQuery), index.folderName):
    result.total = row[0].parseInt()
  
  let syncedQuery = "SELECT COUNT(*) FROM files WHERE folder = ? AND synced = 1"
  for row in index.db.rows(sql(syncedQuery), index.folderName):
    result.synced = row[0].parseInt()
  
  result.pending = result.total - result.synced
