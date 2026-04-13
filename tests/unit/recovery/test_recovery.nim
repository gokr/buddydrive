import std/unittest
import std/strutils
import ../../../src/buddydrive/recovery

suite "Mnemonic generation":
  test "generateMnemonic returns 12 words":
    let mnemonic = generateMnemonic()
    let words = mnemonic.splitWhitespace()
    check words.len == 12

  test "generated mnemonic validates":
    let mnemonic = generateMnemonic()
    check validateMnemonic(mnemonic)

  test "different calls produce different mnemonics":
    let m1 = generateMnemonic()
    let m2 = generateMnemonic()
    check m1 != m2

suite "Mnemonic validation":
  test "valid BIP39 test vector passes":
    check validateMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")

  test "invalid words fail":
    check not validateMnemonic("notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword notaword")

  test "too few words fails":
    check not validateMnemonic("too few words")

  test "empty string fails":
    check not validateMnemonic("")

  test "13 words fails":
    check not validateMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon extra")

  test "case insensitive validation":
    check validateMnemonic("Abandon Abandon Abandon Abandon Abandon Abandon Abandon Abandon Abandon Abandon Abandon About")

suite "Key derivation":
  test "mnemonicToSeed is deterministic":
    let mnemonic = generateMnemonic()
    let seed1 = mnemonicToSeed(mnemonic)
    let seed2 = mnemonicToSeed(mnemonic)
    check seed1 == seed2

  test "deriveMasterKey is deterministic":
    let mnemonic = generateMnemonic()
    let seed = mnemonicToSeed(mnemonic)
    let mk1 = deriveMasterKey(seed)
    let mk2 = deriveMasterKey(seed)
    check mk1 == mk2

  test "different mnemonics produce different master keys":
    let m1 = generateMnemonic()
    let m2 = generateMnemonic()
    let mk1 = bytesToHex(deriveMasterKey(mnemonicToSeed(m1)))
    let mk2 = bytesToHex(deriveMasterKey(mnemonicToSeed(m2)))
    check mk1 != mk2

  test "master key hex is 64 chars":
    let mk = bytesToHex(deriveMasterKey(mnemonicToSeed(generateMnemonic())))
    check mk.len == 64

  test "invalid mnemonic raises on mnemonicToSeed":
    expect ValueError:
      discard mnemonicToSeed("invalid mnemonic words here")

suite "Hex round-trip":
  test "bytesToHex/hexToBytes round-trip":
    let key = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let hex = bytesToHex(key)
    let restored = hexToBytes(hex)
    check key == restored

  test "hexToBytes rejects wrong length":
    expect ValueError:
      discard hexToBytes("short")

suite "Base58 encoding":
  test "base58Encode produces valid characters":
    let data = @[byte(1), 2, 3, 4, 5]
    let encoded = base58Encode(data)
    const validChars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    for c in encoded:
      check c in validChars

  test "base58Encode of zero bytes starts with 1s":
    let data = @[byte(0), 0, 1]
    let encoded = base58Encode(data)
    check encoded.startsWith("1")

suite "Public key derivation":
  test "derivePublicKeyB58 produces non-empty string":
    let mk = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let pk = derivePublicKeyB58(mk)
    check pk.len > 0

  test "derivePublicKeyB58 is deterministic":
    let mk = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let pk1 = derivePublicKeyB58(mk)
    let pk2 = derivePublicKeyB58(mk)
    check pk1 == pk2

suite "Config encryption":
  test "encryptConfigBlob/decryptConfigBlob round-trip":
    let mk = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let original = "[buddy]\nname = \"test-buddy\"\n"
    let encrypted = encryptConfigBlob(original, mk)
    check encrypted != original
    check encrypted.len > original.len
    let decrypted = decryptConfigBlob(encrypted, mk)
    check decrypted == original

  test "decrypt with wrong key fails":
    let mk1 = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let mk2 = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    let original = "[buddy]\nname = \"test\"\n"
    let encrypted = encryptConfigBlob(original, mk1)
    try:
      discard decryptConfigBlob(encrypted, mk2)
      check false
    except CatchableError:
      check true
    except:
      check true

  test "decrypt too-short data fails":
    let mk = deriveMasterKey(mnemonicToSeed(generateMnemonic()))
    expect ValueError:
      discard decryptConfigBlob("short", mk)

suite "Recovery setup":
  test "setupRecovery returns valid recovery config":
    let (mnemonic, recovery) = setupRecovery()
    check recovery.enabled
    check recovery.masterKey.len == 64
    check recovery.publicKeyB58.len > 0

  test "verifyMnemonic with correct mnemonic":
    let (mnemonic, recovery) = setupRecovery()
    check verifyMnemonic(mnemonic, recovery.masterKey)

  test "verifyMnemonic with wrong mnemonic":
    let (_, recovery) = setupRecovery()
    let wrongMnemonic = generateMnemonic()
    check not verifyMnemonic(wrongMnemonic, recovery.masterKey)

  test "recoverFromMnemonic produces same keys":
    let (mnemonic, original) = setupRecovery()
    let recovered = recoverFromMnemonic(mnemonic)
    check recovered.masterKey == original.masterKey
    check recovered.publicKeyB58 == original.publicKeyB58

suite "Word helpers":
  test "suggestWords returns matching words":
    let suggestions = suggestWords("aband")
    check suggestions.len > 0
    check "abandon" in suggestions

  test "findWordIndex finds known word":
    let idx = findWordIndex("abandon")
    check idx >= 0
    check getWordForIndex(idx) == "abandon"

  test "findWordIndex returns -1 for unknown word":
    check findWordIndex("xyznotaword") == -1

  test "getWordForIndex raises for out of range":
    expect ValueError:
      discard getWordForIndex(-1)

  test "suggestWords is case insensitive":
    let s1 = suggestWords("Aband")
    let s2 = suggestWords("aband")
    check s1 == s2

  test "suggestWords limits to 5 results":
    let suggestions = suggestWords("a")
    check suggestions.len <= 5
