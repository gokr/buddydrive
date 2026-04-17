import std/[strutils, options, times, tables, locks, os]
import libsodium/[sodium, sodium_sizes]
import mummy
import kvstore
import geoip_policy

const
  MaxPubKeyLen = 128
  MaxKvBodyBytes = 128 * 1024
  MaxKvHeaderBytes = 8 * 1024
  MaxMutationSkewMs = 15 * 60 * 1000'i64
  MaxInflightRequests = 64
  ReadBurst = 20.0
  ReadTokensPerSecond = 1.0
  MutationBurst = 5.0
  MutationTokensPerSecond = 10.0 / 60.0
  PerKeyMutationBurst = 6.0
  PerKeyMutationTokensPerSecond = 6.0 / 3600.0
  LimiterExpirySeconds = 3600.0

type
  RateBucket = object
    tokens: float64
    lastRefill: float64
    lastSeen: float64

var
  theKvStore: KvStore
  limiterLock: Lock
  mutationLock: Lock
  inflightLock: Lock
  requestBuckets: Table[string, RateBucket]
  keyMutationBuckets: Table[string, RateBucket]
  limiterTouches: int
  inflightRequests: int
  geoPolicyEnabled: bool

proc cryptoSignVerifyDetachedRaw(sig: cptr, msg: cptr, mlen: culonglong, pk: cptr): cint {.importc: "crypto_sign_verify_detached", dynlib: sodium.libsodium_fn.}

proc currentTimeMs(): int64 =
  (epochTime() * 1000).int64

proc nowSeconds(): float64 =
  epochTime()

proc hexDigitValue(ch: char): int =
  case ch
  of '0'..'9':
    int(ch) - int('0')
  of 'a'..'f':
    int(ch) - int('a') + 10
  of 'A'..'F':
    int(ch) - int('A') + 10
  else:
    -1

proc hexToBinary(hex: string): Option[string] =
  if hex.len mod 2 != 0:
    return none(string)

  var binary = newString(hex.len div 2)
  for i in 0 ..< binary.len:
    let hi = hexDigitValue(hex[i * 2])
    let lo = hexDigitValue(hex[i * 2 + 1])
    if hi < 0 or lo < 0:
      return none(string)
    binary[i] = char((hi shl 4) or lo)
  some(binary)

proc canonicalKvMutation(httpMethod, lookupKey, verifyKeyHex, body: string, version, timestamp: int64): string {.raises: [].} =
  httpMethod.toUpperAscii() & "\n" & lookupKey & "\n" & verifyKeyHex & "\n" & $version & "\n" & $timestamp & "\n" & body

proc respondText(request: Request, status: int, body: string) =
  var h = emptyHttpHeaders()
  h["Content-Type"] = "text/plain"
  request.respond(status, h, body)

proc respondJson(request: Request, status: int, body: string) =
  var h = emptyHttpHeaders()
  h["Content-Type"] = "application/json"
  request.respond(status, h, body)

proc trustedClientIp(request: Request): string =
  if "X-Forwarded-For" in request.headers:
    let forwardedFor = request.headers["X-Forwarded-For"]
    let parts = forwardedFor.split(',')
    for i in countdown(parts.high, 0):
      let ip = parts[i].strip()
      if ip.len > 0:
        return ip
  request.remoteAddress

proc allowGeoAccess(ip: string): bool =
  allowEuGeoAccess(ip, geoPolicyEnabled)

proc isValidPubkey(pubkeyB58: string): bool =
  if pubkeyB58.len == 0 or pubkeyB58.len > MaxPubKeyLen:
    return false

  for ch in pubkeyB58:
    if ch notin {'1'..'9', 'A'..'H', 'J'..'N', 'P'..'Z', 'a'..'k', 'm'..'z'}:
      return false
  true

proc parseInt64(raw: string): Option[int64] =
  try:
    some(parseBiggestInt(raw).int64)
  except ValueError:
    none(int64)

proc allowRateLimit(table: var Table[string, RateBucket], key: string, capacity, refillPerSecond, now: float64): bool =
  var bucket = table.getOrDefault(key)
  if bucket.lastRefill == 0:
    bucket.tokens = capacity
    bucket.lastRefill = now

  let elapsed = max(0.0, now - bucket.lastRefill)
  bucket.tokens = min(capacity, bucket.tokens + elapsed * refillPerSecond)
  bucket.lastRefill = now
  bucket.lastSeen = now

  if bucket.tokens < 1.0:
    table[key] = bucket
    return false

  bucket.tokens -= 1.0
  table[key] = bucket
  true

proc purgeLimiters(now: float64) =
  var expiredRequestBuckets: seq[string] = @[]
  for key, bucket in requestBuckets.pairs:
    if now - bucket.lastSeen > LimiterExpirySeconds:
      expiredRequestBuckets.add(key)
  for key in expiredRequestBuckets:
    requestBuckets.del(key)

  var expiredMutationBuckets: seq[string] = @[]
  for key, bucket in keyMutationBuckets.pairs:
    if now - bucket.lastSeen > LimiterExpirySeconds:
      expiredMutationBuckets.add(key)
  for key in expiredMutationBuckets:
    keyMutationBuckets.del(key)

proc allowRequest(ip: string, isMutation: bool, key: string): bool =
  let now = nowSeconds()
  var allowed = true
  withLock limiterLock:
    inc limiterTouches
    if limiterTouches mod 256 == 0:
      purgeLimiters(now)

    let requestBucketKey = ip & "|" & (if isMutation: "mut" else: "read")
    let requestAllowed =
      if isMutation:
        allowRateLimit(requestBuckets, requestBucketKey, MutationBurst, MutationTokensPerSecond, now)
      else:
        allowRateLimit(requestBuckets, requestBucketKey, ReadBurst, ReadTokensPerSecond, now)

    if not requestAllowed:
      allowed = false
    elif isMutation:
      allowed = allowRateLimit(keyMutationBuckets, key, PerKeyMutationBurst, PerKeyMutationTokensPerSecond, now)
  allowed

proc tryEnterRequest(): bool =
  var entered = false
  withLock inflightLock:
    if inflightRequests >= MaxInflightRequests:
      entered = false
    else:
      inc inflightRequests
      entered = true
  entered

proc leaveRequest() =
  withLock inflightLock:
    if inflightRequests > 0:
      dec inflightRequests

proc verifyMutation(request: Request, lookupKey, body: string, verifyKeyHex: var string, version: var int64, errorStatus: var int, errorBody: var string): bool {.raises: [].} =
  if "X-BD-Verify-Key" notin request.headers or "X-BD-Version" notin request.headers or "X-BD-Timestamp" notin request.headers or "X-BD-Signature" notin request.headers:
    errorStatus = 401
    errorBody = "Missing mutation signature headers"
    return false

  verifyKeyHex = request.headers["X-BD-Verify-Key"].strip()
  let versionOpt = parseInt64(request.headers["X-BD-Version"].strip())
  let timestampOpt = parseInt64(request.headers["X-BD-Timestamp"].strip())
  let signatureHex = request.headers["X-BD-Signature"].strip()
  if versionOpt.isNone or timestampOpt.isNone:
    errorStatus = 400
    errorBody = "Invalid mutation version or timestamp"
    return false

  version = versionOpt.get()
  let timestamp = timestampOpt.get()
  if abs(currentTimeMs() - timestamp) > MaxMutationSkewMs:
    errorStatus = 401
    errorBody = "Mutation timestamp is outside the allowed window"
    return false

  let verifyKeyOpt = hexToBinary(verifyKeyHex)
  let signatureOpt = hexToBinary(signatureHex)
  if verifyKeyOpt.isNone or signatureOpt.isNone:
    errorStatus = 400
    errorBody = "Invalid mutation key or signature encoding"
    return false

  let verifyKey = verifyKeyOpt.get()
  let signature = signatureOpt.get()
  if verifyKey.len != crypto_sign_publickeybytes().int or signature.len != crypto_sign_bytes().int:
    errorStatus = 400
    errorBody = "Invalid mutation key or signature length"
    return false

  let canonical = canonicalKvMutation(request.httpMethod, lookupKey, verifyKeyHex, body, version, timestamp)
  if canonical.len == 0:
    errorStatus = 500
    errorBody = "Failed to hash mutation payload"
    return false

  let rc = cryptoSignVerifyDetachedRaw(
    cast[cptr](signature[0].unsafeAddr),
    cast[cptr](canonical[0].unsafeAddr),
    canonical.len.culonglong,
    cast[cptr](verifyKey[0].unsafeAddr)
  )
  if rc != 0:
    errorStatus = 401
    errorBody = "Invalid mutation signature"
    return false

  true

proc handleMutation(request: Request, pubkeyB58: string) {.raises: [].} =
  let isPut = request.httpMethod == "PUT"
  let ip = trustedClientIp(request)
  if not allowRequest(ip, true, pubkeyB58):
    respondText(request, 429, "Rate limit exceeded")
    return

  if isPut and request.body.len == 0:
    respondText(request, 400, "Missing config data")
    return

  if request.body.len > MaxKvBodyBytes:
    respondText(request, 413, "Config data too large")
    return

  var verifyKeyHex = ""
  var version = 0'i64
  var errorStatus = 0
  var errorBody = ""
  let body = if isPut: request.body else: ""
  if not verifyMutation(request, pubkeyB58, body, verifyKeyHex, version, errorStatus, errorBody):
    respondText(request, errorStatus, errorBody)
    return

  var status = 500
  var responseBody = ""
  var jsonBody = false

  withLock mutationLock:
    let existing = fetchConfigRecord(theKvStore, pubkeyB58)
    if request.httpMethod == "DELETE" and existing.isSome and existing.get().verifyKeyHex.len == 0:
      status = 409
      responseBody = "Legacy config must be re-synced before it can be deleted"
    elif existing.isSome and existing.get().verifyKeyHex.len > 0 and existing.get().verifyKeyHex != verifyKeyHex:
      status = 403
      responseBody = "Verify key does not match stored config owner"
    elif isPut:
      case storeConfig(theKvStore, pubkeyB58, verifyKeyHex, request.body, version)
      of StoreConfigSuccess:
        status = 201
        jsonBody = true
        responseBody = "{\"ok\":true}"
      of StoreConfigVersionConflict:
        status = 409
        responseBody = "Mutation version is not newer than the stored version"
      of StoreConfigVerifyKeyConflict:
        status = 403
        responseBody = "Verify key does not match stored config owner"
      of StoreConfigFailure:
        status = 500
        responseBody = "Failed to store config"
    else:
      case deleteConfig(theKvStore, pubkeyB58, verifyKeyHex, version)
      of DeleteConfigSuccess:
        status = 204
      of DeleteConfigNotFound:
        status = 404
        responseBody = "Config not found"
      of DeleteConfigVersionConflict:
        status = 409
        responseBody = "Mutation version is not newer than the stored version"
      of DeleteConfigVerifyKeyConflict:
        status = 403
        responseBody = "Verify key does not match stored config owner"
      of DeleteConfigFailure:
        status = 500
        responseBody = "Failed to delete config"

  if status == 204:
    request.respond(204)
  elif jsonBody:
    respondJson(request, status, responseBody)
  else:
    respondText(request, status, responseBody)

proc handler(request: Request) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if not tryEnterRequest():
      respondText(request, 503, "Server is busy")
      return

    defer:
      leaveRequest()

    if request.path.startsWith("/discovery/"):
      let clientIp = trustedClientIp(request)
      if not allowGeoAccess(clientIp):
        respondText(request, 403, "Region not allowed")
        return

      let key = request.path[12..^1].strip(chars = {'/'})
      if key.len == 0:
        respondText(request, 400, "Missing discovery key")
        return

      case request.httpMethod
      of "GET":
        if not allowRequest(clientIp, false, key):
          respondText(request, 429, "Rate limit exceeded")
          return

        let recordOpt = fetchDiscovery(theKvStore, key)
        if recordOpt.isSome:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/json"
          request.respond(200, h, recordOpt.get())
        else:
          respondText(request, 404, "Discovery record not found or expired")

      of "PUT", "POST":
        if not allowRequest(clientIp, true, key):
          respondText(request, 429, "Rate limit exceeded")
          return
        if request.body.len == 0:
          respondText(request, 400, "Missing record body")
          return
        if request.body.len > MaxKvBodyBytes:
          respondText(request, 413, "Discovery record too large")
          return
        if "X-HMAC" notin request.headers or request.headers["X-HMAC"].strip().len == 0:
          respondText(request, 400, "Missing X-HMAC header")
          return

        if storeDiscovery(theKvStore, key, request.body, request.headers["X-HMAC"].strip()):
          respondJson(request, 201, "{\"ok\":true}")
        else:
          respondText(request, 401, "HMAC mismatch or store error")

      of "DELETE":
        if not allowRequest(clientIp, true, key):
          respondText(request, 429, "Rate limit exceeded")
          return
        if "X-HMAC" notin request.headers or request.headers["X-HMAC"].strip().len == 0:
          respondText(request, 400, "Missing X-HMAC header")
          return

        if deleteDiscovery(theKvStore, key, request.headers["X-HMAC"].strip()):
          request.respond(204)
        else:
          respondText(request, 404, "Discovery record not found or HMAC mismatch")

      else:
        respondText(request, 405, "Method not allowed")

    elif request.path.startsWith("/kv/"):
      let clientIp = trustedClientIp(request)
      if not allowGeoAccess(clientIp):
        respondText(request, 403, "Region not allowed")
        return

      let pubkeyB58 = request.path[4..^1].strip(chars = {'/'})
      if not isValidPubkey(pubkeyB58):
        respondText(request, 400, "Invalid public key")
        return

      case request.httpMethod
      of "GET":
        if not allowRequest(clientIp, false, pubkeyB58):
          respondText(request, 429, "Rate limit exceeded")
          return

        let configOpt = fetchConfig(theKvStore, pubkeyB58)
        if configOpt.isSome:
          let (data, _) = configOpt.get()
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/octet-stream"
          request.respond(200, h, data)
        else:
          respondText(request, 404, "Config not found")

      of "PUT", "DELETE":
        try:
          handleMutation(request, pubkeyB58)
        except CatchableError:
          respondText(request, 401, "Invalid mutation signature")

      else:
        respondText(request, 405, "Method not allowed")

    elif request.path == "/health":
      respondJson(request, 200, "{\"status\":\"ok\"}")

    else:
      respondText(request, 404, "Not found")

proc runKvApi*(kv: KvStore, port: int = 8080) =
  theKvStore = kv
  requestBuckets = initTable[string, RateBucket]()
  keyMutationBuckets = initTable[string, RateBucket]()
  initLock(limiterLock)
  initLock(mutationLock)
  initLock(inflightLock)
  let geoRangePath = getEnv("BUDDYDRIVE_KV_EU_RANGES_FILE", getEnv("BUDDYDRIVE_RELAY_EU_RANGES_FILE", "")).strip()
  let geoStatus = configureEuGeoPolicy(getEnv("BUDDYDRIVE_KV_EU_ONLY", "") == "1", geoRangePath, "KV API")
  geoPolicyEnabled = geoStatus.active

  let server = newServer(
    handler,
    workerThreads = 4,
    maxHeadersLen = MaxKvHeaderBytes,
    maxBodyLen = MaxKvBodyBytes
  )
  echo "KV API HTTP server starting on port ", port
  echo "Endpoints:"
  echo "  GET    /discovery/<key> - Fetch buddy address record"
  echo "  PUT    /discovery/<key> - Store buddy address record"
  echo "  DELETE /discovery/<key> - Delete buddy address record"
  echo "  GET    /kv/<pubkey>   - Fetch encrypted config"
  echo "  PUT    /kv/<pubkey>   - Store encrypted config"
  echo "  DELETE /kv/<pubkey>   - Delete config"
  echo "  GET    /health        - Health check"
  if geoStatus.message.len > 0:
    echo geoStatus.message

  server.serve(Port(port), "0.0.0.0")
