import std/[strutils, times, locks]
import std/options as std_options
import debby/mysql

type
  KvStoreError* = object of CatchableError

  ConfigRecord* = object
    publicKeyB58*: string
    verifyKeyHex*: string
    encryptedConfig*: string
    version*: int64
    deleted*: bool
    updatedAt*: Time

  StoreConfigResult* = enum
    StoreConfigSuccess,
    StoreConfigVersionConflict,
    StoreConfigVerifyKeyConflict,
    StoreConfigFailure

  DeleteConfigResult* = enum
    DeleteConfigSuccess,
    DeleteConfigNotFound,
    DeleteConfigVersionConflict,
    DeleteConfigVerifyKeyConflict,
    DeleteConfigFailure

  KvStore* = ref object
    connectionStr: string
    db: Db
    connected: bool
    lock: Lock

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

proc parseVersion(raw: string): int64 =
  try:
    parseBiggestInt(raw).int64
  except ValueError:
    0'i64

proc parseDeleted(raw: string): bool =
  raw == "1" or raw.toLowerAscii() == "true"

proc migrateSchema(kv: KvStore) =
  kv.db.query("""
    CREATE TABLE IF NOT EXISTS config_store (
      public_key_b58 VARCHAR(128) PRIMARY KEY,
      verify_key_hex VARCHAR(128) NOT NULL DEFAULT '',
      encrypted_config LONGBLOB NOT NULL,
      version BIGINT NOT NULL DEFAULT 0,
      deleted TINYINT(1) NOT NULL DEFAULT 0,
      deleted_at TIMESTAMP NULL DEFAULT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  """)

  for stmt in [
    "ALTER TABLE config_store ADD COLUMN IF NOT EXISTS verify_key_hex VARCHAR(128) NOT NULL DEFAULT ''",
    "ALTER TABLE config_store ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0",
    "ALTER TABLE config_store ADD COLUMN IF NOT EXISTS deleted TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE config_store ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL DEFAULT NULL"
  ]:
    kv.db.query(stmt)

proc fetchConfigRecordLocked(kv: KvStore, pubkeyB58: string): std_options.Option[ConfigRecord] =
  let rows = kv.db.query("SELECT verify_key_hex, encrypted_config, version, deleted, updated_at FROM config_store WHERE public_key_b58 = ?", pubkeyB58)
  for row in rows:
    return std_options.some(ConfigRecord(
      publicKeyB58: pubkeyB58,
      verifyKeyHex: row[0],
      encryptedConfig: row[1],
      version: parseVersion(row[2]),
      deleted: parseDeleted(row[3]),
      updatedAt: getTime()
    ))
  std_options.none(ConfigRecord)

proc initKvStore*(connStr: string): KvStore =
  result = KvStore()
  result.connectionStr = connStr
  initLock(result.lock)

  let parsed = parseConnectionString(connStr)

  try:
    result.db = openDatabase(parsed.database, parsed.host, parsed.port, parsed.user, parsed.password)
    result.connected = true
    withLock result.lock:
      migrateSchema(result)
    echo "KV store initialized successfully"
  except Exception as e:
    raise newException(KvStoreError, "Failed to connect to database: " & e.msg)

proc close*(kv: KvStore) =
  if kv.connected:
    withLock kv.lock:
      kv.db.close()
      kv.connected = false

proc fetchConfigRecord*(kv: KvStore, pubkeyB58: string): std_options.Option[ConfigRecord] =
  if not kv.connected:
    return std_options.none(ConfigRecord)

  try:
    withLock kv.lock:
      return fetchConfigRecordLocked(kv, pubkeyB58)
  except Exception as e:
    echo "Error fetching config record: ", e.msg
    return std_options.none(ConfigRecord)

proc storeConfig*(kv: KvStore, pubkeyB58, verifyKeyHex, encryptedBlob: string, version: int64): StoreConfigResult =
  if not kv.connected:
    return StoreConfigFailure

  try:
    withLock kv.lock:
      let existing = fetchConfigRecordLocked(kv, pubkeyB58)
      if existing.isSome:
        let record = existing.get()
        if record.verifyKeyHex.len > 0 and record.verifyKeyHex != verifyKeyHex:
          return StoreConfigVerifyKeyConflict
        if version <= record.version:
          return StoreConfigVersionConflict
        kv.db.query(
          "UPDATE config_store SET verify_key_hex = ?, encrypted_config = ?, version = ?, deleted = 0, deleted_at = NULL WHERE public_key_b58 = ?",
          verifyKeyHex,
          encryptedBlob,
          $version,
          pubkeyB58
        )
      else:
        kv.db.query(
          "INSERT INTO config_store (public_key_b58, verify_key_hex, encrypted_config, version, deleted) VALUES (?, ?, ?, ?, 0)",
          pubkeyB58,
          verifyKeyHex,
          encryptedBlob,
          $version
        )
      return StoreConfigSuccess
  except Exception as e:
    echo "Error storing config: ", e.msg
    return StoreConfigFailure

proc fetchConfig*(kv: KvStore, pubkeyB58: string): std_options.Option[tuple[data: string, updatedAt: Time]] =
  if not kv.connected:
    return std_options.none(tuple[data: string, updatedAt: Time])

  try:
    withLock kv.lock:
      let record = fetchConfigRecordLocked(kv, pubkeyB58)
      if record.isSome and not record.get().deleted and record.get().encryptedConfig.len > 0:
        let item = record.get()
        return std_options.some((data: item.encryptedConfig, updatedAt: item.updatedAt))
      return std_options.none(tuple[data: string, updatedAt: Time])
  except Exception as e:
    echo "Error fetching config: ", e.msg
    return std_options.none(tuple[data: string, updatedAt: Time])

proc deleteConfig*(kv: KvStore, pubkeyB58, verifyKeyHex: string, version: int64): DeleteConfigResult =
  if not kv.connected:
    return DeleteConfigFailure

  try:
    withLock kv.lock:
      let existing = fetchConfigRecordLocked(kv, pubkeyB58)
      if existing.isNone:
        return DeleteConfigNotFound

      let record = existing.get()
      if record.verifyKeyHex.len > 0 and record.verifyKeyHex != verifyKeyHex:
        return DeleteConfigVerifyKeyConflict
      if version <= record.version:
        return DeleteConfigVersionConflict

      kv.db.query(
        "UPDATE config_store SET encrypted_config = '', version = ?, deleted = 1, deleted_at = CURRENT_TIMESTAMP WHERE public_key_b58 = ?",
        $version,
        pubkeyB58
      )
      return DeleteConfigSuccess
  except Exception as e:
    echo "Error deleting config: ", e.msg
    return DeleteConfigFailure

proc configExists*(kv: KvStore, pubkeyB58: string): bool =
  if not kv.connected:
    return false

  try:
    withLock kv.lock:
      let rows = kv.db.query("SELECT 1 FROM config_store WHERE public_key_b58 = ? AND deleted = 0 LIMIT 1", pubkeyB58)
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
    withLock kv.lock:
      let rows = kv.db.query("SELECT COUNT(*) FROM config_store WHERE deleted = 0")
      for row in rows:
        return parseInt(row[0])
      return 0
  except Exception as e:
    echo "Error getting config count: ", e.msg
    return 0
