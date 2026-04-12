import std/[os, strutils]
import ../../src/buddydrive/types
import ../../src/buddydrive/recovery
import ../../src/buddydrive/sync/config_sync

proc testMnemonicGeneration() =
  echo "  mnemonic generation..."
  let mnemonic = generateMnemonic()
  let words = mnemonic.splitWhitespace()
  doAssert words.len == 12, "expected 12 words, got " & $words.len
  doAssert validateMnemonic(mnemonic), "generated mnemonic failed validation"
  echo "    ok: 12 valid words generated"

proc testMnemonicValidation() =
  echo "  mnemonic validation..."
  doAssert validateMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
  doAssert not validateMnemonic("notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword")
  doAssert not validateMnemonic("too few words")
  doAssert not validateMnemonic("")
  echo "    ok: valid/invalid mnemonics correctly identified"

proc testKeyDerivationIsDeterministic() =
  echo "  key derivation determinism..."
  let mnemonic = generateMnemonic()
  let seed1 = mnemonicToSeed(mnemonic)
  let seed2 = mnemonicToSeed(mnemonic)
  doAssert seed1 == seed2, "same mnemonic produced different seeds"

  let masterKey1 = deriveMasterKey(seed1)
  let masterKey2 = deriveMasterKey(seed2)
  doAssert masterKey1 == masterKey2, "same seed produced different master keys"

  let hex1 = bytesToHex(masterKey1)
  let hex2 = bytesToHex(masterKey2)
  doAssert hex1 == hex2, "hex encoding not deterministic"
  doAssert hex1.len == 64, "expected 64-char hex, got " & $hex1.len
  echo "    ok: same mnemonic always produces same master key"

proc testDifferentMnemonicsProduceDifferentKeys() =
  echo "  different mnemonics produce different keys..."
  let m1 = generateMnemonic()
  let m2 = generateMnemonic()
  let mk1 = bytesToHex(deriveMasterKey(mnemonicToSeed(m1)))
  let mk2 = bytesToHex(deriveMasterKey(mnemonicToSeed(m2)))
  doAssert mk1 != mk2, "different mnemonics produced same master key"
  echo "    ok: different mnemonics produce different keys"

proc testHexRoundTrip() =
  echo "  hex round-trip..."
  let key = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
  let hex = bytesToHex(key)
  let restored = hexToBytes(hex)
  doAssert key == restored, "hex round-trip failed"
  echo "    ok: bytesToHex/hexToBytes round-trip correct"

proc testSetupRecoveryAndVerify() =
  echo "  setupRecovery + verifyMnemonic..."
  let (mnemonic, recovery) = setupRecovery()
  doAssert recovery.enabled
  doAssert recovery.masterKey.len == 64
  doAssert recovery.publicKeyB58.len > 0

  doAssert verifyMnemonic(mnemonic, recovery.masterKey), "verifyMnemonic failed for correct mnemonic"

  let wrongMnemonic = generateMnemonic()
  doAssert not verifyMnemonic(wrongMnemonic, recovery.masterKey), "verifyMnemonic passed for wrong mnemonic"
  echo "    ok: setup and verify work correctly"

proc testRecoverFromMnemonic() =
  echo "  recoverFromMnemonic..."
  let (mnemonic, original) = setupRecovery()
  let recovered = recoverFromMnemonic(mnemonic)
  doAssert recovered.enabled
  doAssert recovered.masterKey == original.masterKey, "recovered master key differs from original"
  doAssert recovered.publicKeyB58 == original.publicKeyB58, "recovered public key differs from original"
  echo "    ok: recoverFromMnemonic produces same keys"

proc testConfigEncryptDecryptRoundTrip() =
  echo "  config encrypt/decrypt round-trip..."
  let (mnemonic, recovery) = setupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)

  let originalConfig = "[buddy]\nname = \"test-buddy\"\nid = \"12345678-1234-1234-1234-123456789012\"\n\n[network]\nlisten_port = 41721\n"

  let encrypted = encryptConfigBlob(originalConfig, masterKey)
  doAssert encrypted != originalConfig, "encrypted config should differ from original"
  doAssert encrypted.len > originalConfig.len, "encrypted should be longer (nonce + mac)"

  let decrypted = decryptConfigBlob(encrypted, masterKey)
  doAssert decrypted == originalConfig, "decrypted config doesn't match original"
  echo "    ok: encrypt then decrypt returns original config"

proc testConfigDecryptWithWrongKeyFails() =
  echo "  config decrypt with wrong key fails..."
  let (mnemonic, recovery) = setupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)
  let originalConfig = "[buddy]\nname = \"test\"\n"

  let encrypted = encryptConfigBlob(originalConfig, masterKey)

  let (otherMnemonic, _) = setupRecovery()
  let wrongKey = hexToBytes(bytesToHex(deriveMasterKey(mnemonicToSeed(otherMnemonic))))

  try:
    discard decryptConfigBlob(encrypted, wrongKey)
    doAssert false, "decrypt with wrong key should have failed"
  except Exception:
    discard
  echo "    ok: wrong key fails to decrypt"

proc testFullRecoveryFlow() =
  echo "  full recovery flow simulation..."
  let (mnemonic, recovery) = setupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)

  var config = newAppConfig(newBuddyId("12345678-1234-1234-1234-123456789012", "test-buddy"))
  config.recovery = recovery
  config.folders = @[newFolderConfig("docs", "/tmp/test-docs")]
  config.buddies = @[]

  let encryptedConfig = serializeConfigForSync(config, masterKey)

  let recoveredConfig = recoverFromMnemonic(mnemonic)
  let recoveredKey = hexToBytes(recoveredConfig.masterKey)

  let decrypted = deserializeConfigFromSync(encryptedConfig, recoveredKey)

  doAssert decrypted.buddy.uuid == config.buddy.uuid, "recovered buddy UUID mismatch"
  doAssert decrypted.buddy.name == config.buddy.name, "recovered buddy name mismatch"
  doAssert decrypted.folders.len == config.folders.len, "recovered folder count mismatch"
  doAssert decrypted.folders[0].name == "docs", "recovered folder name mismatch"
  doAssert decrypted.recovery.masterKey == config.recovery.masterKey, "recovered master key mismatch"
  echo "    ok: full recovery flow works end-to-end"

proc testSuggestWords() =
  echo "  suggestWords..."
  let suggestions = suggestWords("aband")
  doAssert suggestions.len > 0, "expected suggestions for 'aband'"
  doAssert "abandon" in suggestions, "expected 'abandon' in suggestions"
  echo "    ok: word suggestions work"

proc testFindWordIndex() =
  echo "  findWordIndex..."
  let idx = findWordIndex("abandon")
  doAssert idx >= 0, "expected to find 'abandon'"
  doAssert getWordForIndex(idx) == "abandon", "getWordForIndex round-trip failed"
  doAssert findWordIndex("xyznotaword") == -1, "expected -1 for non-existent word"
  echo "    ok: word index lookup works"

proc main() =
  echo "=== BIP39 Recovery Tests ==="
  echo ""

  echo "Mnemonic:"
  testMnemonicGeneration()
  testMnemonicValidation()
  echo ""

  echo "Key derivation:"
  testKeyDerivationIsDeterministic()
  testDifferentMnemonicsProduceDifferentKeys()
  testHexRoundTrip()
  echo ""

  echo "Setup and verify:"
  testSetupRecoveryAndVerify()
  testRecoverFromMnemonic()
  echo ""

  echo "Config encryption:"
  testConfigEncryptDecryptRoundTrip()
  testConfigDecryptWithWrongKeyFails()
  echo ""

  echo "Full recovery flow:"
  testFullRecoveryFlow()
  echo ""

  echo "Word helpers:"
  testSuggestWords()
  testFindWordIndex()
  echo ""

  echo "recovery tests ok"

main()
