import std/unittest
import std/[os, options]
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/recovery
import ../../src/buddydrive/sync/config_sync
import ../testutils

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

template runWithStrictFallback(body: untyped) =
  try:
    body
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "  skipping: ", e.msg

suite "Config sync e2e":
  test "sync config to relay then recover":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
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

      let synced = waitFor syncConfigToRelay(config, kvUrl)
      check synced

      let fetched = waitFor fetchConfigFromRelay(recovery.publicKeyB58, kvUrl)
      check fetched.isSome

      var recovered: AppConfig
      {.cast(gcsafe).}:
        recovered = deserializeConfigFromSync(fetched.get(), masterKey)

      check recovered.buddy.uuid == config.buddy.uuid
      check recovered.buddy.name == config.buddy.name
      check recovered.listenPort == 12345
      check recovered.relayRegion == "eu"
      check recovered.folders.len == 1
      check recovered.folders[0].name == "photos"
      check recovered.folders[0].encrypted == true
      check recovered.folders[0].appendOnly == true
      check recovered.buddies.len == 1
      check recovered.recovery.masterKey == config.recovery.masterKey

      let deleted = waitFor deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)
      check deleted

  test "wrong mnemonic fails to recover":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
      var config = newAppConfig(newBuddyId("dddddddd-4444-4444-4444-444444444444", "wrong-mnemonic-test"))
      config.recovery = recovery

      let synced = waitFor syncConfigToRelay(config, kvUrl)
      check synced

      let wrongMnemonic = safeGenerateMnemonic()
      let recoveredOpt = waitFor attemptRecovery(wrongMnemonic, kvUrl, "")
      check recoveredOpt.isNone

      discard waitFor deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)

  test "double sync works fine":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
      var config = newAppConfig(newBuddyId("eeeeeeee-5555-5555-5555-555555555555", "idempotent-test"))
      config.recovery = recovery

      let synced1 = waitFor syncConfigToRelay(config, kvUrl)
      check synced1

      let synced2 = waitFor syncConfigToRelay(config, kvUrl)
      check synced2

      let fetched = waitFor fetchConfigFromRelay(recovery.publicKeyB58, kvUrl)
      check fetched.isSome

      let masterKey = hexToBytes(recovery.masterKey)
      var recovered: AppConfig
      {.cast(gcsafe).}:
        recovered = deserializeConfigFromSync(fetched.get(), masterKey)
      check recovered.buddy.uuid == config.buddy.uuid

      discard waitFor deleteConfigFromRelay(recovery.publicKeyB58, kvUrl)
