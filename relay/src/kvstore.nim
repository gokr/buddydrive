import std/[strutils, times]
import std/options as std_options
import debby/mysql

type Option*[T] = std_options.Option[T]

type
  KvStoreError* = object of CatchableError
  
  KvStore* = ref object
    connectionStr: string
    db: Db
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
  
  try:
    result.db = openDatabase(parsed.database, parsed.host, parsed.port, parsed.user, parsed.password)
    result.connected = true
    
    result.db.query("""
      CREATE TABLE IF NOT EXISTS config_store (
        public_key_b58 VARCHAR(128) PRIMARY KEY,
        encrypted_config LONGBLOB NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
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
    kv.db.query("DELETE FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    kv.db.query("INSERT INTO config_store (public_key_b58, encrypted_config) VALUES (?, ?)", 
               pubkeyB58, encryptedBlob)
    return true
  except Exception as e:
    echo "Error storing config: ", e.msg
    return false

proc fetchConfig*(kv: KvStore, pubkeyB58: string): Option[tuple[data: string, updatedAt: Time]] =
  if not kv.connected:
    return none(tuple[data: string, updatedAt: Time])
  
  try:
    let rows = kv.db.query("SELECT encrypted_config, updated_at FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    for row in rows:
      return some((data: row[0], updatedAt: getTime()))
    return none(tuple[data: string, updatedAt: Time])
  except Exception as e:
    echo "Error fetching config: ", e.msg
    return none(tuple[data: string, updatedAt: Time])

proc deleteConfig*(kv: KvStore, pubkeyB58: string): bool =
  if not kv.connected:
    return false
  
  try:
    kv.db.query("DELETE FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
    return true
  except Exception as e:
    echo "Error deleting config: ", e.msg
    return false

proc configExists*(kv: KvStore, pubkeyB58: string): bool =
  if not kv.connected:
    return false
  
  try:
    let rows = kv.db.query("SELECT 1 FROM config_store WHERE public_key_b58 = ? LIMIT 1", pubkeyB58)
    for _ in rows:
      return true
    return false
  except Exception as e:
    echo "Error checking config existence: ", e.msg
    return false

proc getConfigCount*(kv: KvStore): int =
  if not kv.connected:
    return 0
  
  try:
    let rows = kv.db.query("SELECT COUNT(*) FROM config_store")
    for row in rows:
      return parseInt(row[0])
    return 0
  except Exception as e:
    echo "Error getting config count: ", e.msg
    return 0
