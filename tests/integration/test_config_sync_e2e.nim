import std/unittest
import std/options
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/recovery
import ../../src/buddydrive/sync/config_sync
import ../support/kv_stub
import ../support/integration_harness
import ../testutils

useIsolatedDataDir("config_sync_e2e")

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

suite "Config sync e2e":
  var stub: KvStub
  var kvUrl: string

  setup:
    let configured = getKvApiUrl()
    if configured.len > 0:
      # Point BUDDYDRIVE_KV_API_URL at a real deployment to test against it.
      stub = nil
      kvUrl = configured
    else:
      stub = startKvStub(freePort())
      kvUrl = stub.url()

  teardown:
    if stub != nil:
      stub.stop()

  test "sync config to relay then recover":
    let (mnemonic, recovery) = safeSetupRecovery()

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

    check waitFor syncConfigToRelay(config, kvUrl)
    # A second push must be accepted: the version header increases.
    check waitFor syncConfigToRelay(config, kvUrl)

    let recoveredOpt = waitFor attemptRecovery(mnemonic, kvUrl, "")
    check recoveredOpt.isSome

    let recovered = recoveredOpt.get()
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

    check waitFor deleteConfigFromRelay(recovery, kvUrl)

    # Once deleted there is nothing left to recover.
    check (waitFor attemptRecovery(mnemonic, kvUrl, "")).isNone

  test "wrong mnemonic fails to recover":
    let (_, recovery) = safeSetupRecovery()
    var config = newAppConfig(newBuddyId("dddddddd-4444-4444-4444-444444444444", "wrong-mnemonic-test"))
    config.recovery = recovery

    check waitFor syncConfigToRelay(config, kvUrl)

    let wrongMnemonic = safeGenerateMnemonic()
    check (waitFor attemptRecovery(wrongMnemonic, kvUrl, "")).isNone

    discard waitFor deleteConfigFromRelay(recovery, kvUrl)

  test "an unreachable service is not reported as a missing config":
    # Recovery must distinguish "nothing stored" from "could not ask". The
    # relay answered 404 for both until a database outage made someone
    # rebuilding a machine believe their backup was gone.
    let (_, recovery) = safeSetupRecovery()

    let missing = waitFor fetchConfigFromRelayChecked(recovery.publicKeyB58, kvUrl)
    check missing.outcome == fcMissing

    # Nothing is listening on this port.
    let deadUrl = "http://127.0.0.1:" & $freePort()
    let unreachable = waitFor fetchConfigFromRelayChecked(recovery.publicKeyB58, deadUrl)
    check unreachable.outcome == fcUnavailable

    var config = newAppConfig(newBuddyId("eeeeeeee-5555-5555-5555-555555555555", "outcome-test"))
    config.recovery = recovery
    check waitFor syncConfigToRelay(config, kvUrl)

    let found = waitFor fetchConfigFromRelayChecked(recovery.publicKeyB58, kvUrl)
    check found.outcome == fcFound

    discard waitFor deleteConfigFromRelay(recovery, kvUrl)
