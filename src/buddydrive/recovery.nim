import std/[os, strutils, sequtils, random]
import libsodium/sodium
import libsodium/sodium_sizes
import ./types

const BIP39_WORD_COUNT = 12

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = byte(c)

proc bytesToString*(bytes: seq[byte]): string =
  result = newString(bytes.len)
  for i, b in bytes:
    result[i] = char(b)

proc binaryToHex*(data: string): string =
  result = newString(data.len * 2)
  const hexChars = "0123456789abcdef"
  for i, ch in data:
    let b = byte(ch)
    result[i * 2] = hexChars[int(b shr 4)]
    result[i * 2 + 1] = hexChars[int(b and 0x0f)]

proc hexToBinary*(hex: string): string =
  if hex.len mod 2 != 0:
    raise newException(ValueError, "Invalid hex string length")

  result = newString(hex.len div 2)
  for i in 0 ..< result.len:
    let hi = hex[i * 2]
    let lo = hex[i * 2 + 1]
    var b = 0
    if hi >= 'a' and hi <= 'f':
      b = (int(hi) - int('a') + 10) shl 4
    elif hi >= 'A' and hi <= 'F':
      b = (int(hi) - int('A') + 10) shl 4
    elif hi >= '0' and hi <= '9':
      b = (int(hi) - int('0')) shl 4
    else:
      raise newException(ValueError, "Invalid hex string")
    if lo >= 'a' and lo <= 'f':
      b = b or (int(lo) - int('a') + 10)
    elif lo >= 'A' and lo <= 'F':
      b = b or (int(lo) - int('A') + 10)
    elif lo >= '0' and lo <= '9':
      b = b or (int(lo) - int('0'))
    else:
      raise newException(ValueError, "Invalid hex string")
    result[i] = char(b)

proc loadBip39Wordlist(): seq[string] =
  let wordlistPath = currentSourcePath().parentDir().parentDir().parentDir() / "wordlists" / "bip39_english.txt"
  if not fileExists(wordlistPath):
    raise newException(IOError, "BIP39 wordlist not found: " & wordlistPath)
  result = readFile(wordlistPath).strip().splitLines()

let BIP39_WORDS = loadBip39Wordlist()

proc generateMnemonic*(): string =
  randomize()
  var words: seq[string] = @[]
  for _ in 0 ..< BIP39_WORD_COUNT:
    let idx = rand(BIP39_WORDS.len - 1)
    words.add(BIP39_WORDS[idx])
  result = words.join(" ")

proc validateMnemonic*(mnemonic: string): bool =
  let words = mnemonic.strip().splitWhitespace()
  if words.len != BIP39_WORD_COUNT:
    return false
  for word in words:
    if word.toLowerAscii() notin BIP39_WORDS:
      return false
  result = true

proc mnemonicToSeed*(mnemonic: string): array[64, byte] =
  if not validateMnemonic(mnemonic):
    raise newException(ValueError, "Invalid mnemonic")
  
  let words = mnemonic.strip().splitWhitespace()
  let normalized = words.mapIt(it.toLowerAscii()).join(" ")
  
  let saltLen = int(crypto_pwhash_saltbytes())
  var salt = newSeq[byte](saltLen)
  let saltStr = "mnemonic"
  for i in 0 ..< min(saltStr.len, saltLen):
    salt[i] = byte(saltStr[i])
  for i in saltStr.len ..< saltLen:
    salt[i] = byte(i)
  
  let entropy = crypto_pwhash(
    normalized,
    salt,
    64,
    phaDefault,
    crypto_pwhash_opslimit_interactive(),
    crypto_pwhash_memlimit_interactive()
  )
  
  for i in 0 ..< min(64, entropy.len):
    result[i] = entropy[i]

proc deriveMasterKey*(seed: array[64, byte]): array[32, byte] =
  var combined = newString(64)
  for i in 0 ..< 64:
    combined[i] = char(seed[i])
  
  let hash = crypto_generichash(combined, 32)
  for i in 0 ..< 32:
    result[i] = byte(hash[i])

proc bytesToHex*(bytes: array[32, byte]): string =
  result = newString(64)
  const hexChars = "0123456789abcdef"
  for i, b in bytes:
    result[i * 2] = hexChars[int(b shr 4)]
    result[i * 2 + 1] = hexChars[int(b and 0x0f)]

proc hexToBytes*(hex: string): array[32, byte] =
  if hex.len != 64:
    raise newException(ValueError, "Invalid hex string length")
  for i in 0 ..< 32:
    let hi = hex[i * 2]
    let lo = hex[i * 2 + 1]
    var b = 0
    if hi >= 'a' and hi <= 'f':
      b = (int(hi) - int('a') + 10) shl 4
    elif hi >= 'A' and hi <= 'F':
      b = (int(hi) - int('A') + 10) shl 4
    else:
      b = (int(hi) - int('0')) shl 4
    if lo >= 'a' and lo <= 'f':
      b = b or (int(lo) - int('a') + 10)
    elif lo >= 'A' and lo <= 'F':
      b = b or (int(lo) - int('A') + 10)
    else:
      b = b or (int(lo) - int('0'))
    result[i] = byte(b)

proc base58Encode*(data: seq[byte]): string =
  const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  var num = 0'u64
  for b in data:
    num = num * 256 + uint64(b)
  
  var chars: seq[char] = @[]
  while num > 0:
    let rem = num mod 58
    num = num div 58
    chars.add(ALPHABET[int(rem)])
  
  result = ""
  for i in countdown(chars.len - 1, 0):
    result.add(chars[i])
  
  for b in data:
    if b == 0:
      result = "1" & result
    else:
      break

proc derivePublicKeyB58*(masterKey: array[32, byte]): string =
  var masterKeyStr = newString(32)
  for i in 0 ..< 32:
    masterKeyStr[i] = char(masterKey[i])
  let hash = crypto_generichash(masterKeyStr, 32)
  var hashBytes = newSeq[byte](hash.len)
  for i in 0 ..< hash.len:
    hashBytes[i] = byte(hash[i])
  base58Encode(hashBytes)

proc encryptConfigBlob*(config: string, masterKey: array[32, byte]): string =
  var masterKeyStr = newString(32)
  for i in 0 ..< 32:
    masterKeyStr[i] = char(masterKey[i])
  result = crypto_secretbox_easy(masterKeyStr, config)

proc decryptConfigBlob*(encrypted: string, masterKey: array[32, byte]): string =
  var masterKeyStr = newString(32)
  for i in 0 ..< 32:
    masterKeyStr[i] = char(masterKey[i])
  
  if encrypted.len < int(crypto_secretbox_noncebytes()) + int(crypto_secretbox_macbytes()):
    raise newException(ValueError, "Encrypted data too short")
  
  result = crypto_secretbox_open_easy(masterKeyStr, encrypted)

proc deriveSigningKeyPair*(masterKey: array[32, byte]): tuple[publicKey: string, secretKey: string] =
  var seed = newString(32)
  for i in 0 ..< 32:
    seed[i] = char(masterKey[i])
  result = crypto_sign_seed_keypair(seed)

proc deriveVerifyKeyHex*(masterKey: array[32, byte]): string =
  let (publicKey, _) = deriveSigningKeyPair(masterKey)
  binaryToHex(publicKey)

proc setupRecovery*(): tuple[mnemonic: string, recovery: RecoveryConfig] =
  result.mnemonic = generateMnemonic()
  let seed = mnemonicToSeed(result.mnemonic)
  let masterKey = deriveMasterKey(seed)
  
  result.recovery.enabled = true
  result.recovery.publicKeyB58 = derivePublicKeyB58(masterKey)
  result.recovery.masterKey = bytesToHex(masterKey)

proc recoverFromMnemonic*(mnemonic: string): RecoveryConfig =
  let seed = mnemonicToSeed(mnemonic)
  let masterKey = deriveMasterKey(seed)
  
  result.enabled = true
  result.publicKeyB58 = derivePublicKeyB58(masterKey)
  result.masterKey = bytesToHex(masterKey)

proc verifyMnemonic*(mnemonic: string, storedMasterKey: string): bool =
  let seed = mnemonicToSeed(mnemonic)
  let masterKey = deriveMasterKey(seed)
  let derivedHex = bytesToHex(masterKey)
  result = derivedHex == storedMasterKey

proc getWordForIndex*(index: int): string =
  if index < 0 or index >= BIP39_WORDS.len:
    raise newException(ValueError, "Invalid word index")
  result = BIP39_WORDS[index]

proc findWordIndex*(word: string): int =
  let lower = word.toLowerAscii()
  for i, w in BIP39_WORDS:
    if w == lower:
      return i
  return -1

proc suggestWords*(partial: string): seq[string] =
  let lower = partial.toLowerAscii()
  result = @[]
  for word in BIP39_WORDS:
    if word.startsWith(lower):
      result.add(word)
      if result.len >= 5:
        break
