import std/strutils
import libsodium/sodium
import libsodium/sodium_sizes

type
  CryptoError* = object of CatchableError
  
  EncryptedData* = object
    nonce*: string
    ciphertext*: string
  
  KeyPair* = object
    publicKey*: string
    secretKey*: string

const
  KeySize* = 32
  NonceSize* = 24
  MacSize* = 16

proc initCrypto*(): bool =
  sodium.sodium_init() >= 0

proc generateKey*(): string =
  crypto_secretbox_keygen()

proc generateNonce*(): string =
  randombytes(crypto_secretbox_noncebytes())

proc generateKeyPair*(): KeyPair =
  let (pk, sk) = crypto_box_keypair()
  result.publicKey = pk
  result.secretKey = sk

proc encrypt*(data: string, key: string): EncryptedData =
  if key.len != crypto_secretbox_keybytes():
    raise newException(CryptoError, "Invalid key size: " & $key.len & " != " & $crypto_secretbox_keybytes())
  
  result.nonce = generateNonce()
  result.ciphertext = crypto_secretbox_easy(key, data)

proc decrypt*(encData: EncryptedData, key: string): string =
  if key.len != crypto_secretbox_keybytes():
    raise newException(CryptoError, "Invalid key size")
  
  let fullCiphertext = encData.nonce & encData.ciphertext
  result = crypto_secretbox_open_easy(key, fullCiphertext)

proc encryptFile*(path: string, key: string): EncryptedData =
  let data = readFile(path)
  result = encrypt(data, key)

proc decryptToFile*(encData: EncryptedData, key: string, path: string) =
  let data = decrypt(encData, key)
  writeFile(path, data)

proc encryptFilename*(filename: string, key: string): string =
  let enc = encrypt(filename, key)
  result = enc.nonce.toHex() & ":" & enc.ciphertext.toHex()

proc decryptFilename*(encrypted: string, key: string): string =
  let parts = encrypted.split(":")
  if parts.len != 2:
    raise newException(CryptoError, "Invalid encrypted filename format")
  
  var encData: EncryptedData
  
  let nonceHex = parts[0]
  if nonceHex.len != crypto_secretbox_noncebytes() * 2:
    raise newException(CryptoError, "Invalid nonce length")
  
  encData.nonce = parseHexStr(nonceHex)
  encData.ciphertext = parseHexStr(parts[1])
  
  result = decrypt(encData, key)

proc deriveKey*(password: string, salt: string): string =
  var saltBytes = newSeq[byte](salt.len)
  for i, c in salt:
    saltBytes[i] = byte(c)
  let derived = crypto_pwhash(password, saltBytes, crypto_secretbox_keybytes())
  result = newString(derived.len)
  for i, b in derived:
    result[i] = char(b)

proc generateSalt*(): string =
  randombytes(int(crypto_pwhash_saltbytes()))

proc hashPassword*(password: string): string =
  crypto_pwhash_str(password)

proc verifyPassword*(hash: string, password: string): bool =
  crypto_pwhash_str_verify(hash, password)
