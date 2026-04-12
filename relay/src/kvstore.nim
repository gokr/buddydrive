import std/[strutils, times, options]
import db_connector/db_mysql

type
  KvStoreError* = object of CatchableError
  
  KvStore* = ref object
    connectionStr: string
    db: DbConn
    connected: bool

proc parseConnectionString(connStr: string): tuple[host: string, port: int, user: string, password: string, database: string] =
  var conn = connStr
  if conn.startsWith("mysql://"):
    conn = conn[8..^1]
  
  let parts = conn.split("@")
  if parts.len != 2:
    raise newException(KvStoreError, "Invalid connection string format")
  
  let auth = parts[0].split(":")
  if auth.len != 2:
    raise newException(KvStoreError, "Invalid connection string format")
  
  result.user = auth[0]
  result.password = auth[1]
  
  let hostParts = parts[1].split("/")
  if hostParts.len != 2:
    raise newException(KvStoreError, "Invalid connection string format")
  
  let hostPort = hostParts[0].split(":")
  if hostPort.len != 2:
    raise newException(KvStoreError, "Invalid connection string format")
  
  result.host = hostPort[0]
  result.port = parseInt(hostPort[1])
  result.database = hostParts[1]

proc initKvStore*(connStr: string): KvStore =
  result = KvStore()
  result.connectionStr = connStr
  
  let parsed = parseConnectionString(connStr)
  let connection = parsed.host & ":" & $parsed.port
  
  try:
    result.db = open(connection, parsed.user, parsed.password, parsed.database)
    result.connected = true
    
    result.db.exec(sql"""
      CREATE TABLE IF NOT EXISTS config_store (
        public_key_b58 VARCHAR(128) PRIMARY KEY,
        encrypted_config LONGBLOB NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_updated (updated_at)
      )
    """)
    
    echo "KV store initialized successfully"
  except Exception as e:
    raise newException(KvStoreError, "Failed to connect to database: " & e.msg)

proc close*(kv: KvStore) =
  if kv.connected:
    kv.db.close()
    kv.connected = false

proc storeConfig*(kv: KvStore, pubkeyB58: string, encryptedBlob: string): bool =
  if not kv.connected:
    return false
  
  try:
    kv.db.exec(sql"DELETE FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    kv.db.exec(sql"INSERT INTO config_store (public_key_b58, encrypted_config) VALUES (?, ?)", 
               pubkeyB58, encryptedBlob)
    return true
  except Exception as e:
    echo "Error storing config: ", e.msg
    return false

proc fetchConfig*(kv: KvStore, pubkeyB58: string): Option[tuple[data: string, updatedAt: Time]] =
  if not kv.connected:
    return none(tuple[data: string, updatedAt: Time])
  
  try:
    let rows = kv.db.getAllRows(sql"SELECT encrypted_config, updated_at FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    if rows.len > 0:
      let data = rows[0][0]
      let timestampStr = rows[0][1]
      let timestamp = parseTime(timestampStr, "yyyy-MM-dd HH:mm:ss", utc())
      return some((data: data, updatedAt: timestamp))
    else:
      return none(tuple[data: string, updatedAt: Time])
  except Exception as e:
    echo "Error fetching config: ", e.msg
    return none(tuple[data: string, updatedAt: Time])

proc deleteConfig*(kv: KvStore, pubkeyB58: string): bool =
  if not kv.connected:
    return false
  
  try:
    let rowsAffected = kv.db.execAffectedRows(sql"DELETE FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    return rowsAffected > 0
  except Exception as e:
    echo "Error deleting config: ", e.msg
    return false

proc configExists*(kv: KvStore, pubkeyB58: string): bool =
  if not kv.connected:
    return false
  
  try:
    let rows = kv.db.getAllRows(sql"SELECT 1 FROM config_store WHERE public_key_b58 = ? LIMIT 1", pubkeyB58)
    return rows.len > 0
  except Exception as e:
    echo "Error checking config existence: ", e.msg
    return false

proc listConfigs*(kv: KvStore, limit: int = 100): seq[tuple[pubkeyB58: string, updatedAt: Time]] =
  if not kv.connected:
    return @[]
  
  try:
    let rows = kv.db.getAllRows(sql"SELECT public_key_b58, updated_at FROM config_store ORDER BY updated_at DESC LIMIT ?", $limit)
    result = @[]
    for row in rows:
      let pubkey = row[0]
      let timestampStr = row[1]
      let timestamp = parseTime(timestampStr, "yyyy-MM-dd HH:mm:ss", utc())
      result.add((pubkeyB58: pubkey, updatedAt: timestamp))
  except Exception as e:
    echo "Error listing configs: ", e.msg
    return @[]

proc cleanupOldConfigs*(kv: KvStore, daysOld: int = 365): int =
  if not kv.connected:
    return 0
  
  try:
    let rowsAffected = kv.db.execAffectedRows(
      sql"DELETE FROM config_store WHERE updated_at < DATE_SUB(NOW(), INTERVAL ? DAY)", 
      $daysOld
    )
    return int(rowsAffected)
  except Exception as e:
    echo "Error cleaning up old configs: ", e.msg
    return 0

proc getConfigCount*(kv: KvStore): int =
  if not kv.connected:
    return 0
  
  try:
    let rows = kv.db.getAllRows(sql"SELECT COUNT(*) FROM config_store")
    if rows.len > 0:
      return parseInt(rows[0][0])
    return 0
  except Exception as e:
    echo "Error getting config count: ", e.msg
    return 0
