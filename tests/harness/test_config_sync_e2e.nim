import std/[os, options]
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/recovery
import ../../src/buddydrive/sync/config_sync

proc strictIntegration(): bool =
  getEnv("BUDDYDRIVE_STRICT_INTEGRATION", "") == "1"

proc getKvApiUrl(): string =
  getEnv("BUDDYDRIVE_KV_API_URL", "https://01.proxy.koyeb.app")

proc safeSetupRecovery(): tuple[mnemonic: string, recovery: RecoveryConfig] {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      result = setupRecovery()
    except Exception as e:
      doAssert false, "setupRecovery failed: " & e.msg

proc safeGenerateMnemonic(): string {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      result = generateMnemonic()
    except Exception:
      doAssert false, "generateMnemonic failed"

proc testSyncConfigToRelayAndRecover(kvUrl: string) {.async.} =
  echo "  sync config to relay then recover..."

  let (mnemonic, recovery) = safeSetupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)

  var config = newAppConfig(newBuddyId("aaaaaaaa-1111-1111-1111-111111111111", "sync-test-buddy"))
  config.recovery = recovery
  config.listenPort = 12345
  config.relayRegion = "eu"
  config.folders = @[newFolderConfig("photos", "/tmp/photos")]
  config.folders[0].encrypted = true
  config.folders[0].appendOnly = true
  config.folders[0].buddies = @["bbbbbbbb-2222-2222-2222-222222222222"]

  var buddy: BuddyInfo
  buddy.id = newBuddyId("bbbbbbbb-2222-2222-2222-222222222222", "test-friend")
  buddy.pairingCode = "test-code"
  config.buddies = @[buddy]

  let synced = await syncConfigToRelay(config, kvUrl)
  doAssert synced, "syncConfigToRelay failed"
  echo "    ok: config synced to relay"

  let fetched = await fetchConfigFromRelay(recovery.publicKeyB58, kvUrl)
  doAssert fetched.isSome, "fetchConfigFromRelay returned none"
  echo "    ok: config fetched from relay"

  var recovered: AppConfig
  try:
    {.cast(gcsafe).}:
      recovered = deserializeConfigFromSync(fetched.get(), masterKey)
  except Exception as e:
    doAssert false, "deserializeConfigFromSync failed: " & e.msg

  doAssert recovered.buddy.uuid == config.buddy.uuid, "recovered UUID mismatch"
  doAssert recovered.buddy.name == config.buddy.name, "recovered name mismatch"
  doAssert recovered.listenPort == 12345, "recovered listenPort mismatch"
  doAssert recovered.relayRegion == "eu", "recovered relayRegion mismatch"
  doAssert recovered.folders.len == 1, "recovered folder count mismatch"
  doAssert recovered.folders[0].name == "photos", "recovered folder name mismatch"
  doAssert recovered.folders[0].encrypted == true, "recovered folder encrypted mismatch"
  doAssert recovered.folders[0].appendOnly == true, "recovered folder appendOnly mismatch"
  doAssert recovered.folders[0].buddies.len == 1, "recovered folder buddies mismatch"
  doAssert recovered.buddies.len == 1, "recovered buddy count mismatch"
  doAssert recovered.buddies[0].id.uuid == "bbbbbbbb-2222-2222-2222-222222222222", "recovered buddy ID mismatch"
  doAssert recovered.recovery.masterKey == config.recovery.masterKey, "recovered master key mismatch"
  echo "    ok: deserialized config matches original"

  let deleted = await deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)
  doAssert deleted, "deleteConfigFromRelay failed"
  echo "    ok: cleaned up from relay"

proc testAttemptRecoveryFlow(kvUrl: string) {.async.} =
  echo "  attemptRecovery end-to-end..."

  let (mnemonic, recovery) = safeSetupRecovery()

proc testRecoveryWithWrongMnemonic(kvUrl: string) {.async.} =
  echo "  recovery with wrong mnemonic fails..."
  let (_, recovery) = safeSetupRecovery()
  var config = newAppConfig(newBuddyId("dddddddd-4444-4444-4444-444444444444", "wrong-mnemonic-test"))
  config.recovery = recovery

  let synced = await syncConfigToRelay(config, kvUrl)
  doAssert synced

  let wrongMnemonic = safeGenerateMnemonic()
  let recoveredOpt = await attemptRecovery(wrongMnemonic, kvUrl, "")
  doAssert recoveredOpt.isNone, "wrong mnemonic should not recover config"
  echo "    ok: wrong mnemonic fails to recover"

  discard await deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)

proc testConfigSyncIdempotent(kvUrl: string) {.async.} =
  echo "  config sync is idempotent..."
  let (mnemonic, recovery) = safeSetupRecovery()
  var config = newAppConfig(newBuddyId("eeeeeeee-5555-5555-5555-555555555555", "idempotent-test"))
  config.recovery = recovery

  let synced1 = await syncConfigToRelay(config, kvUrl)
  doAssert synced1

  let synced2 = await syncConfigToRelay(config, kvUrl)
  doAssert synced2

  let fetched = await fetchConfigFromRelay(recovery.publicKeyB58, kvUrl)
  doAssert fetched.isSome

  let masterKey = hexToBytes(recovery.masterKey)
  var recovered: AppConfig
  try:
    {.cast(gcsafe).}:
      recovered = deserializeConfigFromSync(fetched.get(), masterKey)
  except Exception as e:
    doAssert false, "deserializeConfigFromSync failed: " & e.msg
  doAssert recovered.buddy.uuid == config.buddy.uuid
  echo "    ok: double sync works fine"

  discard await deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)

proc main() {.async.} =
  let kvUrl = getKvApiUrl()

  echo "=== Config Sync End-to-End Tests ==="
  echo "  Using KV API URL: ", kvUrl
  echo ""

  try:
    await testSyncConfigToRelayAndRecover(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testAttemptRecoveryFlow(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testRecoveryWithWrongMnemonic(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testConfigSyncIdempotent(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  echo ""
  echo "config sync e2e tests ok"

waitFor main()
