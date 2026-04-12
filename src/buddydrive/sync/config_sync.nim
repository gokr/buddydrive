import std/[times, strutils, options, hashes]
import chronos
import curly
import webby/httpheaders
import parsetoml
import ../types
import ../recovery

type
  ConfigSyncError* = object of CatchableError
  
  ConfigSyncStatus* = object
    lastSyncTime*: Time
    lastSyncHash*: string
    relayAvailable*: bool

const CONFIG_SYNC_TIMEOUT = 10

proc hashConfig*(config: AppConfig): string =
  let content = $config.buddy.uuid & $config.buddy.name & $config.folders.len & $config.buddies.len
  result = $hash(content)

proc shouldSyncConfig*(lastSyncHash: string, currentConfig: AppConfig): bool =
  let currentHash = hashConfig(currentConfig)
  result = currentHash != lastSyncHash

proc serializeConfigForSync*(config: AppConfig, masterKey: array[32, byte]): string =
  var content = ""
  content.add("[buddy]\n")
  content.add("name = \"" & config.buddy.name & "\"\n")
  content.add("id = \"" & config.buddy.uuid & "\"\n\n")
  
  content.add("[network]\n")
  content.add("listen_port = " & $config.listenPort & "\n")
  content.add("announce_addr = \"" & config.announceAddr & "\"\n")
  content.add("relay_base_url = \"" & config.relayBaseUrl & "\"\n")
  content.add("relay_region = \"" & config.relayRegion & "\"\n")
  content.add("sync_window_start = \"" & config.syncWindowStart & "\"\n")
  content.add("sync_window_end = \"" & config.syncWindowEnd & "\"\n")
  content.add("bandwidth_limit_kbps = " & $config.bandwidthLimitKBps & "\n\n")
  
  if config.folders.len > 0:
    content.add("[[folders]]\n")
    for i, folder in config.folders:
      if i > 0:
        content.add("\n[[folders]]\n")
      content.add("name = \"" & folder.name & "\"\n")
      content.add("path = \"" & folder.path & "\"\n")
      content.add("encrypted = " & $folder.encrypted & "\n")
      content.add("append_only = " & $folder.appendOnly & "\n")
      if folder.buddies.len > 0:
        content.add("buddies = [")
        for j, buddy in folder.buddies:
          if j > 0:
            content.add(", ")
          content.add("\"" & buddy & "\"")
        content.add("]\n")
  
  if config.buddies.len > 0:
    content.add("\n[[buddies]]\n")
    for i, buddy in config.buddies:
      if i > 0:
        content.add("\n[[buddies]]\n")
      content.add("id = \"" & buddy.id.uuid & "\"\n")
      content.add("name = \"" & buddy.id.name & "\"\n")
      content.add("pairing_code = \"" & buddy.pairingCode & "\"\n")
      content.add("added_at = \"" & buddy.addedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'") & "\"\n")
  
  content.add("\n[recovery]\n")
  content.add("enabled = " & $config.recovery.enabled & "\n")
  content.add("public_key = \"" & config.recovery.publicKeyB58 & "\"\n")
  content.add("master_key = \"" & config.recovery.masterKey & "\"\n")
  
  result = encryptConfigBlob(content, masterKey)

proc deserializeConfigFromSync*(encryptedContent: string, masterKey: array[32, byte]): AppConfig =
  let content = decryptConfigBlob(encryptedContent, masterKey)
  let toml = parseString(content)
  
  result.buddy.uuid = toml["buddy"]["id"].getStr()
  result.buddy.name = toml["buddy"]["name"].getStr("")
  result.recovery.enabled = false
  result.recovery.publicKeyB58 = ""
  result.recovery.masterKey = ""
  result.listenPort = DefaultP2PPort
  result.announceAddr = ""
  result.relayBaseUrl = ""
  result.relayRegion = ""
  result.syncWindowStart = ""
  result.syncWindowEnd = ""
  result.bandwidthLimitKBps = 0

  if "recovery" in toml:
    result.recovery.enabled = toml["recovery"]{"enabled"}.getBool(false)
    result.recovery.publicKeyB58 = toml["recovery"]{"public_key"}.getStr("")
    result.recovery.masterKey = toml["recovery"]{"master_key"}.getStr("")

  if "network" in toml:
    result.listenPort = toml["network"]{"listen_port"}.getInt(DefaultP2PPort)
    result.announceAddr = toml["network"]{"announce_addr"}.getStr("")
    result.relayBaseUrl = toml["network"]{"relay_base_url"}.getStr("")
    result.relayRegion = toml["network"]{"relay_region"}.getStr("")
    result.syncWindowStart = toml["network"]{"sync_window_start"}.getStr("")
    result.syncWindowEnd = toml["network"]{"sync_window_end"}.getStr("")
    result.bandwidthLimitKBps = toml["network"]{"bandwidth_limit_kbps"}.getInt(0)
  
  result.folders = @[]
  if "folders" in toml:
    for folderTbl in toml["folders"].getElems():
      var folder: FolderConfig
      folder.name = folderTbl["name"].getStr()
      folder.path = folderTbl["path"].getStr()
      folder.encrypted = folderTbl{"encrypted"}.getBool(true)
      folder.appendOnly = folderTbl{"append_only"}.getBool(false)
      folder.buddies = @[]
      if "buddies" in folderTbl:
        for buddy in folderTbl["buddies"].getElems():
          folder.buddies.add(buddy.getStr())
      result.folders.add(folder)
  
  result.buddies = @[]
  if "buddies" in toml:
    for buddyTbl in toml["buddies"].getElems():
      var buddy: BuddyInfo
      buddy.id.uuid = buddyTbl["id"].getStr()
      buddy.id.name = buddyTbl{"name"}.getStr("")
      buddy.pairingCode = buddyTbl{"pairing_code"}.getStr("")
      buddy.addedAt = parseTime(buddyTbl{"added_at"}.getStr("1970-01-01T00:00:00Z"), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
      result.buddies.add(buddy)

proc syncConfigToRelay*(config: AppConfig, relayUrl: string): Future[bool] {.async.} =
  if not config.recovery.enabled:
    return false
  
  if config.recovery.masterKey.len == 0:
    return false
  
  let masterKey = hexToBytes(config.recovery.masterKey)
  
  var encryptedConfig: string
  try:
    encryptedConfig = serializeConfigForSync(config, masterKey)
  except Exception as e:
    echo "Error encrypting config: ", e.msg
    return false
  
  let pubkey = config.recovery.publicKeyB58
  
  var client = newCurly()
  let url = relayUrl.strip(chars = {'/'}) & "/kv/" & pubkey
  
  try:
    let response = client.put(url, emptyHttpHeaders(), encryptedConfig.toOpenArray(0, encryptedConfig.len - 1), CONFIG_SYNC_TIMEOUT)
    if response.code >= 200 and response.code < 300:
      return true
    else:
      echo "Failed to sync config to relay: HTTP ", response.code
      return false
  except Exception as e:
    echo "Error syncing config to relay: ", e.msg
    return false

proc fetchConfigFromRelay*(publicKeyB58: string, relayUrl: string): Future[Option[string]] {.async.} =
  var client = newCurly()
  let url = relayUrl.strip(chars = {'/'}) & "/kv/" & publicKeyB58
  
  try:
    let response = client.get(url, emptyHttpHeaders(), CONFIG_SYNC_TIMEOUT)
    if response.code == 200:
      return some(response.body)
    else:
      return none(string)
  except Exception as e:
    echo "Error fetching config from relay: ", e.msg
    return none(string)

proc deleteConfigFromRelay*(publicKeyB58: string, relayUrl: string): Future[bool] {.async.} =
  var client = newCurly()
  let url = relayUrl.strip(chars = {'/'}) & "/kv/" & publicKeyB58
  
  try:
    let response = client.delete(url, emptyHttpHeaders(), CONFIG_SYNC_TIMEOUT)
    return response.code >= 200 and response.code < 300
  except Exception as e:
    echo "Error deleting config from relay: ", e.msg
    return false

proc syncConfigToBuddy*(config: AppConfig, buddyIndex: int, relayBaseUrl: string, relayRegion: string): Future[bool] {.async.} =
  if buddyIndex >= config.buddies.len:
    return false
  
  if not config.recovery.enabled or config.recovery.masterKey.len == 0:
    return false
  
  let buddy = config.buddies[buddyIndex]
  let masterKey = hexToBytes(config.recovery.masterKey)
  
  var encryptedConfig: string
  try:
    encryptedConfig = serializeConfigForSync(config, masterKey)
  except Exception as e:
    echo "Error encrypting config: ", e.msg
    return false
  
  let configFileName = "config." & config.buddy.uuid & ".enc"
  
  return true

proc syncConfigToAllBuddies*(config: AppConfig, relayBaseUrl: string, relayRegion: string): Future[int] {.async.} =
  result = 0
  for i in 0 ..< config.buddies.len:
    if await syncConfigToBuddy(config, i, relayBaseUrl, relayRegion):
      inc result

proc fetchConfigFromBuddy*(buddyId: string, pairingCode: string, relayBaseUrl: string, relayRegion: string): Future[Option[string]] {.async.} =
  return none(string)

proc attemptRecovery*(mnemonic: string, relayBaseUrl: string, relayRegion: string): Future[Option[AppConfig]] {.async.} =
  var recovery: RecoveryConfig
  var masterKey: array[32, byte]
  try:
    {.cast(gcsafe).}:
      recovery = recoverFromMnemonic(mnemonic)
    masterKey = hexToBytes(recovery.masterKey)
  except Exception as e:
    echo "Error deriving keys from mnemonic: ", e.msg
    return none(AppConfig)
  
  let relayResult = await fetchConfigFromRelay(recovery.publicKeyB58, relayBaseUrl)
  if relayResult.isSome:
    try:
      var config: AppConfig
      {.cast(gcsafe).}:
        config = deserializeConfigFromSync(relayResult.get(), masterKey)
      return some(config)
    except Exception as e:
      echo "Failed to decrypt config from relay: ", e.msg
  
  return none(AppConfig)

proc attemptRecoveryFromBuddy*(mnemonic: string, buddyId: string, pairingCode: string, relayBaseUrl: string, relayRegion: string): Future[Option[AppConfig]] {.async.} =
  var recovery: RecoveryConfig
  var masterKey: array[32, byte]
  try:
    {.cast(gcsafe).}:
      recovery = recoverFromMnemonic(mnemonic)
    masterKey = hexToBytes(recovery.masterKey)
  except Exception as e:
    echo "Error deriving keys from mnemonic: ", e.msg
    return none(AppConfig)
  
  let buddyResult = await fetchConfigFromBuddy(buddyId, pairingCode, relayBaseUrl, relayRegion)
  if buddyResult.isSome:
    try:
      var config: AppConfig
      {.cast(gcsafe).}:
        config = deserializeConfigFromSync(buddyResult.get(), masterKey)
      return some(config)
    except Exception as e:
      echo "Failed to decrypt config from buddy: ", e.msg
  
  return none(AppConfig)
