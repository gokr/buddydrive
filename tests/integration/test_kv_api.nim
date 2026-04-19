import std/unittest
import std/[os, base64, strutils, httpclient, osproc, net, times]
import chronos
import curly
import webby/httpheaders
import ../../src/buddydrive/types
import ../../src/buddydrive/recovery
import ../../src/buddydrive/sync/config_sync
import ../testutils
import ../support/integration_harness

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

var localKvRelayBinaryPath {.global.}: string

proc ensureLocalKvRelayBinary(): string =
  let workspaceRoot = repoRoot().parentDir()
  let debbySrc = workspaceRoot / "debby" / "src"
  let jsonySrc = workspaceRoot / "jsony" / "src"
  let buildCmd = "nim c --path:" & quoteShell(debbySrc) & " --path:" & quoteShell(jsonySrc) & " -d:withKvStore -o:$OUT relay/src/relay.nim"
  ensureBuiltBinary(localKvRelayBinaryPath, "buddydrive_test_relay_kv", buildCmd)

suite "KV API":
  test "put then get then delete":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58
      var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "kv-test-buddy"))
      config.recovery = recovery
      let encrypted = safeSerialize(config, masterKey)
      let encoded = encode(encrypted)

      var client = newCurly()
      let putUrl = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey
      let putHeaders = buildSignedKvHeaders(recovery, "PUT", pubkey, encoded)

      let putResp = client.put(putUrl, putHeaders, encoded.toOpenArray(0, encoded.len - 1), 10)
      check putResp.code >= 200 and putResp.code < 300

      let getResp = client.get(putUrl, emptyHttpHeaders(), 10)
      check getResp.code == 200
      check decode(getResp.body) == encrypted

      let delHeaders = buildSignedKvHeaders(recovery, "DELETE", pubkey, "")
      let delResp = client.delete(putUrl, delHeaders, 10)
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
      let enc1b64 = encode(enc1)
      let put1Headers = buildSignedKvHeaders(recovery, "PUT", pubkey, enc1b64)
      discard client.put(url, put1Headers, enc1b64.toOpenArray(0, enc1b64.len - 1), 10)

      var config2 = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "version-two"))
      config2.recovery = recovery
      let enc2 = safeSerialize(config2, masterKey)
      let enc2b64 = encode(enc2)
      let put2Headers = buildSignedKvHeaders(recovery, "PUT", pubkey, enc2b64)

      let putResp = client.put(url, put2Headers, enc2b64.toOpenArray(0, enc2b64.len - 1), 10)
      check putResp.code >= 200 and putResp.code < 300

      let getResp = client.get(url, emptyHttpHeaders(), 10)
      check decode(getResp.body) == enc2

      let delHeaders = buildSignedKvHeaders(recovery, "DELETE", pubkey, "")
      discard client.delete(url, delHeaders, 10)

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

  test "PUT empty body returns 400":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl().strip(chars = {'/'})
      let (_, recovery) = safeSetupRecovery()
      let url = kvUrl & "/kv/" & recovery.publicKeyB58
      let client = newHttpClient()
      let resp = client.request(url, httpMethod = HttpPut, body = "")
      check resp.code == Http400
      check "Missing config data" in resp.body

  test "POST is not allowed":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl().strip(chars = {'/'})
      let (_, recovery) = safeSetupRecovery()
      let url = kvUrl & "/kv/" & recovery.publicKeyB58
      let client = newHttpClient()
      let resp = client.request(url, httpMethod = HttpPost, body = "")
      check resp.code == Http405
      check "Method not allowed" in resp.body

  test "/stats endpoint is not exposed":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl().strip(chars = {'/'})
      let client = newHttpClient()
      let resp = client.get(kvUrl & "/stats")
      check resp.code == Http404

  test "unsigned delete is rejected":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl()
      let (_, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58
      var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "unsigned-delete"))
      config.recovery = recovery
      let encrypted = safeSerialize(config, masterKey)
      let encoded = encode(encrypted)

      var client = newCurly()
      let url = kvUrl.strip(chars = {'/'}) & "/kv/" & pubkey
      let putHeaders = buildSignedKvHeaders(recovery, "PUT", pubkey, encoded)
      let putResp = client.put(url, putHeaders, encoded.toOpenArray(0, encoded.len - 1), 10)
      check putResp.code >= 200 and putResp.code < 300

      let delResp = client.delete(url, emptyHttpHeaders(), 10)
      check delResp.code == 401

      let cleanupHeaders = buildSignedKvHeaders(recovery, "DELETE", pubkey, "")
      discard client.delete(url, cleanupHeaders, 10)

  test "/kv/ without key returns 400":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl().strip(chars = {'/'})
      let client = newHttpClient()
      let resp = client.get(kvUrl & "/kv/")
      check resp.code == Http400
      check "Invalid public key" in resp.body

  test "unknown path returns 404":
    runWithStrictFallback:
      let kvUrl = getKvApiUrl().strip(chars = {'/'})
      let client = newHttpClient()
      let resp = client.get(kvUrl & "/definitely-missing-path")
      check resp.code == Http404
      check "Not found" in resp.body

  test "local kv relay enforces signed mutations":
    runWithStrictFallback:
      let dsn = getLocalKvConnectionString()
      if dsn.len == 0:
        raise newException(IOError, "BUDDYDRIVE_LOCAL_KV_DSN not set")

      let relayBin = ensureLocalKvRelayBinary()
      let relayPort = freePort()
      let kvPort = freePort()
      let oldDsn = getEnv("TIDB_CONNECTION_STRING", "")
      putEnv("TIDB_CONNECTION_STRING", dsn)

      var relayProc = startProcess(
        relayBin,
        workingDir = repoRoot(),
        args = @[$relayPort, $kvPort],
        options = {poStdErrToStdOut}
      )
      defer:
        putEnv("TIDB_CONNECTION_STRING", oldDsn)
        stopProcessCleanly(relayProc)

      waitForHttpReady("http://127.0.0.1:" & $kvPort & "/health")

      let kvUrl = "http://127.0.0.1:" & $kvPort
      let (_, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58
      var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "local-kv-test"))
      config.recovery = recovery
      let encrypted = safeSerialize(config, masterKey)
      let encoded = encode(encrypted)

      var client = newCurly()
      let url = kvUrl & "/kv/" & pubkey
      let putHeaders = buildSignedKvHeaders(recovery, "PUT", pubkey, encoded)
      let putResp = client.put(url, putHeaders, encoded.toOpenArray(0, encoded.len - 1), 10)
      check putResp.code == 201

      let unsignedDelete = client.delete(url, emptyHttpHeaders(), 10)
      check unsignedDelete.code == 401

      let getResp = client.get(url, emptyHttpHeaders(), 10)
      check getResp.code == 200
      check decode(getResp.body) == encrypted

      let deleteHeaders = buildSignedKvHeaders(recovery, "DELETE", pubkey, "")
      let deleteResp = client.delete(url, deleteHeaders, 10)
      check deleteResp.code == 204

  test "local kv relay can block non-EU forwarded IPs":
    runWithStrictFallback:
      let dsn = getLocalKvConnectionString()
      if dsn.len == 0:
        raise newException(IOError, "BUDDYDRIVE_LOCAL_KV_DSN not set")

      let geoRangesFile = getTempDir() / ("buddydrive_eu_ranges_" & $getTime().toUnix() & ".txt")
      writeFile(geoRangesFile, "2.16.0.0/13\n2001:67c::/32\n")

      let relayBin = ensureLocalKvRelayBinary()
      let relayPort = freePort()
      let kvPort = freePort()
      let oldDsn = getEnv("TIDB_CONNECTION_STRING", "")
      let oldEuOnly = getEnv("BUDDYDRIVE_KV_EU_ONLY", "")
      let oldGeoRanges = getEnv("BUDDYDRIVE_KV_EU_RANGES_FILE", "")
      putEnv("TIDB_CONNECTION_STRING", dsn)
      putEnv("BUDDYDRIVE_KV_EU_ONLY", "1")
      putEnv("BUDDYDRIVE_KV_EU_RANGES_FILE", geoRangesFile)

      var relayProc = startProcess(
        relayBin,
        workingDir = repoRoot(),
        args = @[$relayPort, $kvPort],
        options = {poStdErrToStdOut}
      )
      defer:
        putEnv("TIDB_CONNECTION_STRING", oldDsn)
        putEnv("BUDDYDRIVE_KV_EU_ONLY", oldEuOnly)
        putEnv("BUDDYDRIVE_KV_EU_RANGES_FILE", oldGeoRanges)
        if fileExists(geoRangesFile):
          removeFile(geoRangesFile)
        stopProcessCleanly(relayProc)

      waitForHttpReady("http://127.0.0.1:" & $kvPort & "/health")

      let kvUrl = "http://127.0.0.1:" & $kvPort
      let (_, recovery) = safeSetupRecovery()
      let masterKey = hexToBytes(recovery.masterKey)
      let pubkey = recovery.publicKeyB58
      var config = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "geo-block-test"))
      config.recovery = recovery
      let encrypted = safeSerialize(config, masterKey)
      let encoded = encode(encrypted)

      var client = newCurly()
      let url = kvUrl & "/kv/" & pubkey
      var headers = buildSignedKvHeaders(recovery, "PUT", pubkey, encoded)
      headers["X-Forwarded-For"] = "8.8.8.8"
      let putResp = client.put(url, headers, encoded.toOpenArray(0, encoded.len - 1), 10)
      check putResp.code == 403
