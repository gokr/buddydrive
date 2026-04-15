import std/unittest
import std/times
import chronos
import ../../../src/buddydrive/types
import ../../../src/buddydrive/recovery
import ../../../src/buddydrive/sync/config_sync

suite "serializeConfigForSync / deserializeConfigFromSync":
  test "round-trip preserves buddy":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("12345678-1234-1234-1234-123456789012", "test-buddy"))
    cfg.recovery = recovery
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)
    check decrypted.buddy.uuid == cfg.buddy.uuid
    check decrypted.buddy.name == cfg.buddy.name

  test "round-trip preserves network settings":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery = recovery
    cfg.listenPort = 12345
    cfg.relayRegion = "eu"
    cfg.announceAddr = "/ip4/1.2.3.4/tcp/12345"
    cfg.bandwidthLimitKBps = 500
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)
    check decrypted.listenPort == 12345
    check decrypted.relayRegion == "eu"
    check decrypted.announceAddr == "/ip4/1.2.3.4/tcp/12345"
    check decrypted.bandwidthLimitKBps == 500

  test "round-trip preserves folders":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery = recovery
    cfg.folders = @[newFolderConfig("photos", "/tmp/photos")]
    cfg.folders[0].encrypted = true
    cfg.folders[0].appendOnly = true
    cfg.folders[0].buddies = @["buddy-uuid-1"]
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)
    check decrypted.folders.len == 1
    check decrypted.folders[0].name == "photos"
    check decrypted.folders[0].encrypted == true
    check decrypted.folders[0].appendOnly == true
    check decrypted.folders[0].buddies.len == 1

  test "round-trip preserves buddies":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery = recovery
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-uuid-1", "test-friend")
    buddy.pairingCode = "swift-eagle"
    buddy.addedAt = parseTime("2026-01-01T00:00:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
    cfg.buddies = @[buddy]
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)
    check decrypted.buddies.len == 1
    check decrypted.buddies[0].id.uuid == "buddy-uuid-1"
    check decrypted.buddies[0].id.name == "test-friend"

  test "round-trip preserves recovery":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery = recovery
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)
    check decrypted.recovery.enabled == true
    check decrypted.recovery.masterKey == recovery.masterKey
    check decrypted.recovery.publicKeyB58 == recovery.publicKeyB58

  test "round-trip preserves special characters in strings":
    let (_, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid-with-quotes", "buddy \"name\""))
    cfg.recovery = recovery
    cfg.announceAddr = "/ip4/1.2.3.4/tcp/12345\nnext"
    cfg.folders = @[newFolderConfig("docs\tname", "/tmp/quote\"dir")]
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-uuid-1", "friend \"quoted\"")
    buddy.pairingCode = "swift\teagle"
    buddy.addedAt = parseTime("2026-01-01T00:00:00Z", "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
    cfg.buddies = @[buddy]

    let encrypted = serializeConfigForSync(cfg, masterKey)
    let decrypted = deserializeConfigFromSync(encrypted, masterKey)

    check decrypted.buddy.name == cfg.buddy.name
    check decrypted.announceAddr == cfg.announceAddr
    check decrypted.folders[0].name == cfg.folders[0].name
    check decrypted.folders[0].path == cfg.folders[0].path
    check decrypted.buddies[0].id.name == cfg.buddies[0].id.name
    check decrypted.buddies[0].pairingCode == cfg.buddies[0].pairingCode

  test "deserialize with wrong key fails":
    let (mnemonic, recovery) = setupRecovery()
    let masterKey = hexToBytes(recovery.masterKey)
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery = recovery
    let encrypted = serializeConfigForSync(cfg, masterKey)
    let (_, otherRecovery) = setupRecovery()
    let wrongKey = hexToBytes(otherRecovery.masterKey)
    try:
      discard deserializeConfigFromSync(encrypted, wrongKey)
      check false
    except CatchableError:
      check true
    except:
      check true

suite "syncConfigToRelay without recovery":
  test "syncConfigToRelay returns false when recovery disabled":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    let result = waitFor syncConfigToRelay(cfg, "https://example.com")
    check not result

  test "syncConfigToRelay returns false when masterKey empty":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.recovery.enabled = true
    cfg.recovery.masterKey = ""
    let result = waitFor syncConfigToRelay(cfg, "https://example.com")
    check not result
