import std/[options, times, strutils]
import db_connector/db_sqlite
import ../types
import ../config

export types

const SchemaVersion = 3

type
  IndexError* = object of CatchableError
  
  FileIndex* = ref object
    db*: DbConn
    folderName*: string

proc migrate(index: FileIndex) =
  var currentVersion = 0
  for row in index.db.rows(sql"PRAGMA user_version"):
    currentVersion = row[0].parseInt()
  
  if currentVersion < 1:
    let createOwner = """
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
    discard index.db.tryExec(sql(createOwner))
  
  if currentVersion < 2:
    discard index.db.tryExec(sql"CREATE INDEX IF NOT EXISTS idx_folder_content_hash ON files(folder, hash)")
    discard index.db.tryExec(sql"CREATE INDEX IF NOT EXISTS idx_folder_encrypted_path ON files(folder, encrypted_path)")
    
    let createStorage = """
      CREATE TABLE IF NOT EXISTS storage_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        encrypted_path TEXT NOT NULL,
        content_hash BLOB NOT NULL,
        size INTEGER NOT NULL,
        owner_buddy TEXT NOT NULL,
        UNIQUE(encrypted_path, owner_buddy)
      );
      CREATE INDEX IF NOT EXISTS idx_storage_content_hash ON storage_files(content_hash, owner_buddy);
    """
    discard index.db.tryExec(sql(createStorage))

  if currentVersion < 3:
    discard index.db.tryExec(sql"ALTER TABLE files ADD COLUMN mode INTEGER NOT NULL DEFAULT 0")
    discard index.db.tryExec(sql"ALTER TABLE files ADD COLUMN symlink_target TEXT NOT NULL DEFAULT ''")
    discard index.db.tryExec(sql"ALTER TABLE storage_files ADD COLUMN mode INTEGER NOT NULL DEFAULT 0")
    discard index.db.tryExec(sql"ALTER TABLE storage_files ADD COLUMN symlink_target TEXT NOT NULL DEFAULT ''")
  
  discard index.db.tryExec(sql("PRAGMA user_version = " & $SchemaVersion))

proc newIndex*(folderName: string): FileIndex =
  result = FileIndex()
  result.folderName = folderName
  
  let dbPath = config.getIndexPath()
  config.ensureDataDir()
  
  let db = open(dbPath, "", "", "")
  result.db = db
  
  result.migrate()

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
    INSERT OR REPLACE INTO files (folder, path, encrypted_path, size, mtime, hash, mode, symlink_target, synced, last_sync)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """
  let lastSync = if synced: getTime().toUnix() else: 0
  discard index.db.tryExec(sql(query), index.folderName, info.path, info.encryptedPath, info.size, info.mtime, hashStr, info.mode, info.symlinkTarget, if synced: 1 else: 0, lastSync)

proc cacheScannedFile*(index: FileIndex, info: types.FileInfo) =
  let hashStr = hashToString(info.hash)
  let query = """
    INSERT INTO files (folder, path, encrypted_path, size, mtime, hash, mode, symlink_target)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(folder, path) DO UPDATE SET
      encrypted_path = excluded.encrypted_path,
      size = excluded.size,
      mtime = excluded.mtime,
      hash = excluded.hash,
      mode = excluded.mode,
      symlink_target = excluded.symlink_target
  """
  discard index.db.tryExec(sql(query), index.folderName, info.path, info.encryptedPath, info.size, info.mtime, hashStr, info.mode, info.symlinkTarget)

proc removeFile*(index: FileIndex, path: string) =
  let query = "DELETE FROM files WHERE folder = ? AND path = ?"
  discard index.db.tryExec(sql(query), index.folderName, path)

proc getFile*(index: FileIndex, path: string): Option[types.FileInfo] =
  let query = "SELECT path, encrypted_path, size, mtime, hash, mode, symlink_target FROM files WHERE folder = ? AND path = ?"
  for row in index.db.rows(sql(query), index.folderName, path):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    info.mode = row[5].parseInt()
    info.symlinkTarget = row[6]
    return some(info)
  return none(types.FileInfo)

proc getFileByHash*(index: FileIndex, contentHash: array[32, byte]): Option[types.FileInfo] =
  let hashStr = hashToString(contentHash)
  let query = "SELECT path, encrypted_path, size, mtime, hash, mode, symlink_target FROM files WHERE folder = ? AND hash = ? LIMIT 1"
  for row in index.db.rows(sql(query), index.folderName, hashStr):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    info.mode = row[5].parseInt()
    info.symlinkTarget = row[6]
    return some(info)
  return none(types.FileInfo)

proc getFileByEncryptedPath*(index: FileIndex, encryptedPath: string): Option[types.FileInfo] =
  let query = "SELECT path, encrypted_path, size, mtime, hash, mode, symlink_target FROM files WHERE folder = ? AND encrypted_path = ? LIMIT 1"
  for row in index.db.rows(sql(query), index.folderName, encryptedPath):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    info.mode = row[5].parseInt()
    info.symlinkTarget = row[6]
    return some(info)
  return none(types.FileInfo)

proc getAllFiles*(index: FileIndex): seq[types.FileInfo] =
  result = @[]
  let query = "SELECT path, encrypted_path, size, mtime, hash, mode, symlink_target FROM files WHERE folder = ?"
  for row in index.db.rows(sql(query), index.folderName):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    info.mode = row[5].parseInt()
    info.symlinkTarget = row[6]
    result.add(info)

proc getUnsyncedFiles*(index: FileIndex): seq[types.FileInfo] =
  result = @[]
  let query = "SELECT path, encrypted_path, size, mtime, hash, mode, symlink_target FROM files WHERE folder = ? AND synced = 0"
  for row in index.db.rows(sql(query), index.folderName):
    var info: types.FileInfo
    info.path = row[0]
    info.encryptedPath = row[1]
    info.size = row[2].parseInt()
    info.mtime = row[3].parseInt()
    info.hash = stringToHash(row[4])
    info.mode = row[5].parseInt()
    info.symlinkTarget = row[6]
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

proc addStorageFile*(index: FileIndex, info: types.StorageFileInfo) =
  let hashStr = hashToString(info.contentHash)
  let query = """
    INSERT OR REPLACE INTO storage_files (encrypted_path, content_hash, size, mode, symlink_target, owner_buddy)
    VALUES (?, ?, ?, ?, ?, ?)
  """
  discard index.db.tryExec(sql(query), info.encryptedPath, hashStr, info.size, info.mode, info.symlinkTarget, info.ownerBuddy)

proc removeStorageFile*(index: FileIndex, encryptedPath: string, ownerBuddy: string) =
  let query = "DELETE FROM storage_files WHERE encrypted_path = ? AND owner_buddy = ?"
  discard index.db.tryExec(sql(query), encryptedPath, ownerBuddy)

proc getStorageFile*(index: FileIndex, encryptedPath: string, ownerBuddy: string): Option[types.StorageFileInfo] =
  let query = "SELECT encrypted_path, content_hash, size, mode, symlink_target, owner_buddy FROM storage_files WHERE encrypted_path = ? AND owner_buddy = ?"
  for row in index.db.rows(sql(query), encryptedPath, ownerBuddy):
    var info: types.StorageFileInfo
    info.encryptedPath = row[0]
    info.contentHash = stringToHash(row[1])
    info.size = row[2].parseInt()
    info.mode = row[3].parseInt()
    info.symlinkTarget = row[4]
    info.ownerBuddy = row[5]
    return some(info)
  return none(types.StorageFileInfo)

proc listByOwner*(index: FileIndex, ownerBuddy: string): seq[types.StorageFileInfo] =
  result = @[]
  let query = "SELECT encrypted_path, content_hash, size, mode, symlink_target, owner_buddy FROM storage_files WHERE owner_buddy = ?"
  for row in index.db.rows(sql(query), ownerBuddy):
    var info: types.StorageFileInfo
    info.encryptedPath = row[0]
    info.contentHash = stringToHash(row[1])
    info.size = row[2].parseInt()
    info.mode = row[3].parseInt()
    info.symlinkTarget = row[4]
    info.ownerBuddy = row[5]
    result.add(info)

proc updateStoragePath*(index: FileIndex, oldEncPath: string, newEncPath: string, ownerBuddy: string) =
  let query = "UPDATE storage_files SET encrypted_path = ? WHERE encrypted_path = ? AND owner_buddy = ?"
  discard index.db.tryExec(sql(query), newEncPath, oldEncPath, ownerBuddy)
