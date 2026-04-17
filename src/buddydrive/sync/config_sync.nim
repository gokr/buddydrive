import std/[strutils, options, base64, times]
import chronos
import curly
import libsodium/sodium
import webby/httpheaders
import ../types
import ../config
import ../recovery

type
  ConfigSyncError* = object of CatchableError

const CONFIG_SYNC_TIMEOUT = 10
const DefaultKvApiUrl* = "https://buddydrive-tankfeud-ddaec82a.koyeb.app"

var lastKvMutationVersion = 0'i64

proc currentTimeMs(): int64 =
  (epochTime() * 1000).int64

proc nextKvMutationVersion(): int64 =
  let now = currentTimeMs()
  result = max(now, lastKvMutationVersion + 1)
  lastKvMutationVersion = result

proc canonicalKvMutation(httpMethod, lookupKey, verifyKeyHex, body: string, version, timestamp: int64): string =
  httpMethod.toUpperAscii() & "\n" & lookupKey & "\n" & verifyKeyHex & "\n" & $version & "\n" & $timestamp & "\n" & body

proc buildSignedKvHeaders*(recovery: RecoveryConfig, httpMethod, lookupKey, body: string): HttpHeaders =
  if recovery.masterKey.len == 0:
    raise newException(ConfigSyncError, "Missing recovery master key")

  let masterKey = hexToBytes(recovery.masterKey)
  let (verifyKey, secretKey) = deriveSigningKeyPair(masterKey)
  let verifyKeyHex = binaryToHex(verifyKey)
  let version = nextKvMutationVersion()
  let timestamp = currentTimeMs()
  let canonical = canonicalKvMutation(httpMethod, lookupKey, verifyKeyHex, body, version, timestamp)
  let signatureHex = binaryToHex(crypto_sign_detached(secretKey, canonical))

  result = emptyHttpHeaders()
  result["X-BD-Verify-Key"] = verifyKeyHex
  result["X-BD-Version"] = $version
  result["X-BD-Timestamp"] = $timestamp
  result["X-BD-Signature"] = signatureHex

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
    let headers = buildSignedKvHeaders(config.recovery, "PUT", pubkey, encoded)
    let response = client.put(url, headers, encoded.toOpenArray(0, encoded.len - 1), CONFIG_SYNC_TIMEOUT)
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

proc deleteConfigFromRelay*(recovery: RecoveryConfig, relayUrl: string): Future[bool] {.async.} =
  if not recovery.enabled or recovery.masterKey.len == 0 or recovery.publicKeyB58.len == 0:
    return false

  var client = newCurly()
  let url = relayUrl.strip(chars = {'/'}) & "/kv/" & recovery.publicKeyB58
  
  try:
    let headers = buildSignedKvHeaders(recovery, "DELETE", recovery.publicKeyB58, "")
    let response = client.delete(url, headers, CONFIG_SYNC_TIMEOUT)
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
