import std/unittest
import std/[os, options, base64, strutils]
import chronos
import curly
import webby/httpheaders
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

proc safeSerialize(config: AppConfig, masterKey: array[32, byte]): string {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      result = serializeConfigForSync(config, masterKey)
    except Exception as e:
      doAssert false, "serializeConfigForSync failed: " & e.msg

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
    echo "  skipping (KV API unavailable): ", e.msg

suite "KV API":
  test "put then get then delete":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (mnemonic, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58
      var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "kv-test-buddy"))
      config.recovery = recovery
      let encrypted = safeSerialize(config, masterKey)
      let encoded = encode(encrypted)

      var client = newCurly()
      let putUrl = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey

      let putResp = client.put(putUrl, emptyHttpHeaders(), encoded.toOpenArray(0, encoded.len - 1), 10)
      check putResp.code >= 200 and putResp.code < 300

      let getResp = client.get(putUrl, emptyHttpHeaders(), 10)
      check getResp.code == 200
      check decode(getResp.body) == encrypted

      let delResp = client.delete(putUrl, emptyHttpHeaders(), 10)
      check delResp.code >= 200 and delResp.code < 300

      let getAfterDel = client.get(putUrl, emptyHttpHeaders(), 10)
      check getAfterDel.code == 404

  test "put overwrites existing":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58

      var client = newCurly()
      let url = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey

      var config1 = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "version-one"))
      config1.recovery = recovery
      let enc1 = safeSerialize(config1, masterKey)
      discard client.put(url, emptyHttpHeaders(), encode(enc1).toOpenArray(0, encode(enc1).len - 1), 10)

      var config2 = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "version-two"))
      config2.recovery = recovery
      let enc2 = safeSerialize(config2, masterKey)
      let enc2b64 = encode(enc2)

      let putResp = client.put(url, emptyHttpHeaders(), enc2b64.toOpenArray(0, enc2b64.len - 1), 10)
      check putResp.code >= 200 and putResp.code < 300

      let getResp = client.get(url, emptyHttpHeaders(), 10)
      check decode(getResp.body) == enc2

      discard client.delete(url, emptyHttpHeaders(), 10)

  test "GET missing key returns 404":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      var client = newCurly()
      let url = kvUrl.strip(chars = {'/'}) & "/kv/nonexistentkey123"
      let resp = client.get(url, emptyHttpHeaders(), 10)
      check resp.code == 404

  test "/health endpoint returns 200":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      var client = newCurly()
      let url = kvUrl.strip(chars = {'/'}) & "/health"
      let resp = client.get(url, emptyHttpHeaders(), 10)
      check resp.code == 200
      check "ok" in resp.body
