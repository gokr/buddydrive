import std/unittest
import std/options
import ../../../src/buddydrive/p2p/discovery
import ../../../src/buddydrive/recovery
import ../../../src/buddydrive/crypto

suite "Discovery key derivation":
  test "deriveDiscoveryKey produces consistent Base58 output":
    let key1 = deriveDiscoveryKey("swift-eagle")
    let key2 = deriveDiscoveryKey("swift-eagle")
    check key1 == key2
    check key1.len > 0

  test "different pairing codes produce different discovery keys":
    let key1 = deriveDiscoveryKey("swift-eagle")
    let key2 = deriveDiscoveryKey("brave-tiger")
    check key1 != key2

  test "deriveAuthKey produces consistent 32-byte key":
    let authKey1 = deriveAuthKey("swift-eagle")
    let authKey2 = deriveAuthKey("swift-eagle")
    check authKey1 == authKey2
    check authKey1.len == 32

  test "different pairing codes produce different auth keys":
    let authKey1 = deriveAuthKey("swift-eagle")
    let authKey2 = deriveAuthKey("brave-tiger")
    check authKey1 != authKey2

  test "discovery key and auth key differ for same pairing code":
    let discoveryKey = deriveDiscoveryKey("swift-eagle")
    let authKey = deriveAuthKey("swift-eagle")
    check discoveryKey != authKey

suite "Discovery HMAC":
  test "computeHmac produces consistent output":
    let authKey = deriveAuthKey("swift-eagle")
    let hmac1 = computeHmac(authKey, "test data")
    let hmac2 = computeHmac(authKey, "test data")
    check hmac1 == hmac2

  test "different data produces different HMAC":
    let authKey = deriveAuthKey("swift-eagle")
    let hmac1 = computeHmac(authKey, "data one")
    let hmac2 = computeHmac(authKey, "data two")
    check hmac1 != hmac2

  test "different auth keys produce different HMAC for same data":
    let authKey1 = deriveAuthKey("swift-eagle")
    let authKey2 = deriveAuthKey("brave-tiger")
    let hmac1 = computeHmac(authKey1, "test data")
    let hmac2 = computeHmac(authKey2, "test data")
    check hmac1 != hmac2

suite "Deterministic initiator":
  test "non-public side initiates against public buddy":
    let record = BuddyRecord(isPubliclyReachable: true)
    check shouldInitiate("bbbb", false, "aaaa", record)

  test "public side does not initiate against non-public buddy":
    let record = BuddyRecord(isPubliclyReachable: false)
    check not shouldInitiate("aaaa", true, "bbbb", record)

  test "lower uuid initiates when both are public":
    let record = BuddyRecord(isPubliclyReachable: true)
    check shouldInitiate("aaaa", true, "bbbb", record)
    check not shouldInitiate("cccc", true, "bbbb", record)

  test "lower uuid initiates when neither is public":
    let record = BuddyRecord(isPubliclyReachable: false)
    check shouldInitiate("aaaa", false, "bbbb", record)
    check not shouldInitiate("cccc", false, "bbbb", record)
