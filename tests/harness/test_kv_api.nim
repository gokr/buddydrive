import std/[os, strutils, options]
import chronos
import curly
import webby/httpheaders
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

proc safeSerialize(config: AppConfig, masterKey: array[32, byte]): string {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      result = serializeConfigForSync(config, masterKey)
    except Exception as e:
      doAssert false, "serializeConfigForSync failed: " & e.msg

proc testKvApiPutGetDelete(kvUrl: string) {.async.} =
  echo "  PUT then GET then DELETE..."
  let (mnemonic, recovery) = safeSetupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)
  let pubkey = recovery.publicKeyB58

  var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "kv-test-buddy"))
  config.recovery = recovery
  let encrypted = safeSerialize(config, masterKey)

  var client = newCurly()
  let putUrl = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey

  let putResp = client.put(putUrl, emptyHttpHeaders(), encrypted.toOpenArray(0, encrypted.len - 1), 10)
  doAssert putResp.code >= 200 and putResp.code < 300, "PUT failed: " & $putResp.code
  echo "    ok: PUT succeeded"

  let getResp = client.get(putUrl, emptyHttpHeaders(), 10)
  doAssert getResp.code == 200, "GET failed: " & $getResp.code
  doAssert getResp.body == encrypted, "GET body doesn't match PUT data"
  echo "    ok: GET returned same data"

  let delResp = client.delete(putUrl, emptyHttpHeaders(), 10)
  doAssert delResp.code >= 200 and delResp.code < 300, "DELETE failed: " & $delResp.code
  echo "    ok: DELETE succeeded"

  let getAfterDel = client.get(putUrl, emptyHttpHeaders(), 10)
  doAssert getAfterDel.code == 404, "GET after DELETE should return 404, got " & $getAfterDel.code
  echo "    ok: GET after DELETE returns 404"

proc testKvApiOverwrite(kvUrl: string) {.async.} =
  echo "  PUT overwrites existing..."
  let (mnemonic, recovery) = safeSetupRecovery()
  let masterKey = hexToBytes(recovery.masterKey)
  let pubkey = recovery.publicKeyB58

  var client = newCurly()
  let url = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey

  var config1 = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "version-one"))
  config1.recovery = recovery
  let enc1 = safeSerialize(config1, masterKey)

  discard client.put(url, emptyHttpHeaders(), enc1.toOpenArray(0, enc1.len - 1), 10)

  var config2 = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "version-two"))
  config2.recovery = recovery
  let enc2 = safeSerialize(config2, masterKey)

  let putResp = client.put(url, emptyHttpHeaders(), enc2.toOpenArray(0, enc2.len - 1), 10)
  doAssert putResp.code >= 200 and putResp.code < 300, "overwrite PUT failed"

  let getResp = client.get(url, emptyHttpHeaders(), 10)
  doAssert getResp.body == enc2, "GET after overwrite doesn't return latest data"

  discard client.delete(url, emptyHttpHeaders(), 10)
  echo "    ok: overwrite works"

proc testKvApiMissingKey(kvUrl: string) {.async.} =
  echo "  GET missing key returns 404..."
  var client = newCurly()
  let url = kvUrl.strip(chars = {'/'}) & "/kv/nonexistentkey123"

  let resp = client.get(url, emptyHttpHeaders(), 10)
  doAssert resp.code == 404, "expected 404 for missing key, got " & $resp.code
  echo "    ok: missing key returns 404"

proc testKvApiHealth(kvUrl: string) {.async.} =
  echo "  /health endpoint..."
  var client = newCurly()
  let url = kvUrl.strip(chars = {'/'}) & "/health"

  let resp = client.get(url, emptyHttpHeaders(), 10)
  doAssert resp.code == 200, "/health returned " & $resp.code
  doAssert "ok" in resp.body, "/health body doesn't contain 'ok'"
  echo "    ok: /health returns 200"

proc main() {.async.} =
  let kvUrl = getKvApiUrl()

  echo "=== KV API Tests ==="
  echo "  Using URL: ", kvUrl
  echo ""

  try:
    await testKvApiPutGetDelete(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testKvApiOverwrite(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testKvApiMissingKey(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  try:
    await testKvApiHealth(kvUrl)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "    skipping (KV API unavailable): ", e.msg

  echo ""
  echo "kv api tests ok"

waitFor main()
