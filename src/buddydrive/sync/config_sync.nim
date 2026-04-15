import std/[strutils, options, base64]
import chronos
import curly
import webby/httpheaders
import ../types
import ../config
import ../recovery

type
  ConfigSyncError* = object of CatchableError

const CONFIG_SYNC_TIMEOUT = 10
const DefaultKvApiUrl* = "https://buddydrive-tankfeud-ddaec82a.koyeb.app"

proc serializeConfigForSync*(config: AppConfig, masterKey: array[32, byte]): string =
  result = encryptConfigBlob(configToToml(config), masterKey)

proc deserializeConfigFromSync*(encryptedContent: string, masterKey: array[32, byte]): AppConfig =
  result = parseConfigString(decryptConfigBlob(encryptedContent, masterKey))

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
    let encoded = encode(encryptedConfig)
    let response = client.put(url, emptyHttpHeaders(), encoded.toOpenArray(0, encoded.len - 1), CONFIG_SYNC_TIMEOUT)
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
      return some(decode(response.body))
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
  let buddy = config.buddies[buddyIndex]
  echo "Buddy config sync is not implemented yet for buddy: ", buddy.id.uuid
  return false

proc syncConfigToAllBuddies*(config: AppConfig, relayBaseUrl: string, relayRegion: string): Future[int] {.async.} =
  result = 0
  for i in 0 ..< config.buddies.len:
    if await syncConfigToBuddy(config, i, relayBaseUrl, relayRegion):
      inc result

proc fetchConfigFromBuddy*(buddyId: string, pairingCode: string, relayBaseUrl: string, relayRegion: string): Future[Option[string]] {.async.} =
  echo "Buddy config recovery is not implemented yet for buddy: ", buddyId
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
