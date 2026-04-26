import std/[json, strutils, tables, times]
import chronos
import chronos/transports/common as chronosTransport
import curly
import libsodium/sodium
import libp2p/multiaddress
import libp2p/wire
import libp2p/stream/connection
import libp2p/stream/chronosstream

type
  RelayError* = object of CatchableError

  CachedRelayList = object
    relays: seq[string]
    expiresAt: Time

  RelayListCache* = ref object
    entries: Table[string, CachedRelayList]

let relayHttp = newCurly()

proc initRelayListCache*(): RelayListCache {.raises: [].} =
  RelayListCache(entries: initTable[string, CachedRelayList]())

proc toBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, ch in s:
    result[i] = byte(ch)

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for i, b in data:
    result[i] = char(b)

proc cryptoGenerichashRaw(hashOut: cptr, hashOutLen: csize_t, msg: cptr, msgLen: culonglong, key: cptr, keyLen: csize_t): cint {.importc: "crypto_generichash", dynlib: libsodium_fn.}

proc bytesToHex(data: string): string =
  result = newString(data.len * 2)
  const hexChars = "0123456789abcdef"
  for i, ch in data:
    let b = byte(ch)
    result[i * 2] = hexChars[int(b shr 4)]
    result[i * 2 + 1] = hexChars[int(b and 0x0f)]

proc powHashHex(payload: string): string =
  result = newString(32)
  let msgPtr = if payload.len == 0: nil else: cast[cptr](payload[0].unsafeAddr)
  let rc = cryptoGenerichashRaw(
    cast[cptr](result[0].addr),
    result.len.csize_t,
    msgPtr,
    payload.len.culonglong,
    nil,
    0
  )
  if rc != 0:
    return ""
  result = bytesToHex(result)

proc hasLeadingZeroBits(hashHex: string, requiredBits: int): bool =
  var bitsLeft = requiredBits
  for ch in hashHex:
    if bitsLeft <= 0:
      return true
    let nibble =
      if ch >= '0' and ch <= '9': int(ch) - int('0')
      else: int(toLowerAscii(ch)) - int('a') + 10
    if bitsLeft >= 4:
      if nibble != 0:
        return false
      bitsLeft -= 4
    else:
      return nibble < (1 shl (4 - bitsLeft))
  bitsLeft <= 0

proc solveRelayPow(relayToken, nonce: string, difficultyBits: int): string {.raises: [].} =
  var counter = 0'u64
  while true:
    let attempt = $counter
    let hash = powHashHex(relayToken & "\n" & nonce & "\n" & attempt)
    if hash.len == 0:
      return ""
    if hasLeadingZeroBits(hash, difficultyBits):
      return attempt
    inc counter

proc normalizeRelayRegion(region: string): string {.raises: [].} =
  region.strip().toLowerAscii()

proc relayCacheKey(baseUrl: string, region: string): string {.raises: [].} =
  baseUrl.strip() & "|" & normalizeRelayRegion(region)

proc builtinRelayAddrs(region: string): seq[string] {.raises: [].} =
  case normalizeRelayRegion(region)
  of "local":
    @[
      "/ip4/127.0.0.1/tcp/41722"
    ]
  of "eu":
    @[
      "/dns4/relay-eu.buddydrive.org/tcp/41722"
    ]
  of "us":
    @[
      "/dns4/relay-us.buddydrive.org/tcp/41722"
    ]
  of "asia":
    @[
      "/dns4/relay-asia.buddydrive.org/tcp/41722"
    ]
  else:
    @[]

proc parseRelayList(body: string): tuple[relays: seq[string], ttlSeconds: int] =
  let node = parseJson(body)
  result.ttlSeconds = 3600

  case node.kind
  of JObject:
    if "ttl_seconds" in node and node["ttl_seconds"].kind == JInt:
      result.ttlSeconds = max(node["ttl_seconds"].getInt(), 60)
    if "relays" in node and node["relays"].kind == JArray:
      for relayNode in node["relays"].items:
        if relayNode.kind == JString:
          let relay = relayNode.getStr().strip()
          if relay.len > 0:
            result.relays.add(relay)
  of JArray:
    for relayNode in node.items:
      if relayNode.kind == JString:
        let relay = relayNode.getStr().strip()
        if relay.len > 0:
          result.relays.add(relay)
  else:
    discard

proc fetchRelayList(baseUrl: string, region: string): CachedRelayList {.raises: [].} =
  let trimmedBase = baseUrl.strip()
  if trimmedBase.len == 0:
    return

  let url = trimmedBase.strip(chars = {'/'}) & "/relays/" & normalizeRelayRegion(region)

  try:
    let response = relayHttp.get(url, timeout = 3)
    if response.code < 200 or response.code >= 300:
      return

    let parsed = parseRelayList(response.body)
    if parsed.relays.len == 0:
      return

    result.relays = parsed.relays
    result.expiresAt = getTime() + initDuration(seconds = parsed.ttlSeconds)
  except Exception:
    discard

proc relayAddrsForRegion*(
    cache: RelayListCache,
    apiBaseUrl: string,
    relayRegion: string,
): seq[string] {.raises: [].} =
  let region = normalizeRelayRegion(relayRegion)
  if region.len == 0:
    return @[]

  let key = relayCacheKey(apiBaseUrl, region)
  let cached = cache.entries.getOrDefault(key)
  if cached.relays.len > 0 and cached.expiresAt > getTime():
    return cached.relays

  let fetched = fetchRelayList(apiBaseUrl, region)
  if fetched.relays.len > 0:
    cache.entries[key] = fetched
    return fetched.relays

  let staleCached = cache.entries.getOrDefault(key)
  if staleCached.relays.len > 0:
    return staleCached.relays

  builtinRelayAddrs(region)

proc stableRelayIndex(relayToken: string, relayCount: int): int {.raises: [].} =
  var hash = 14695981039346656037'u64
  for ch in relayToken:
    hash = hash xor uint64(byte(ch))
    hash = hash * 1099511628211'u64
  int(hash mod uint64(relayCount))

proc orderedRelayAddrs*(
    cache: RelayListCache,
    apiBaseUrl: string,
    relayRegion: string,
    relayToken: string,
): seq[string] {.raises: [].} =
  let relays = relayAddrsForRegion(cache, apiBaseUrl, relayRegion)
  if relays.len == 0:
    return @[]

  let start = stableRelayIndex(relayToken, relays.len)
  result = newSeqOfCap[string](relays.len)
  for offset in 0 ..< relays.len:
    result.add(relays[(start + offset) mod relays.len])

proc readRelayLine(transp: StreamTransport): Future[string] {.async.} =
  var line: seq[byte] = @[]

  while line.len < 64:
    let chunk = await transp.read(1)
    if chunk.len == 0:
      raise newException(RelayError, "relay closed connection before completing handshake")

    let ch = chunk[0]
    if ch == byte('\n'):
      return bytesToString(line)
    if ch != byte('\r'):
      line.add(ch)

  raise newException(RelayError, "relay handshake line too long")

proc resolveRelayAddr(relayAddr: string): seq[string] =
  if not relayAddr.startsWith("/dns4/") and not relayAddr.startsWith("/dns6/"):
    return @[relayAddr]

  let parts = relayAddr.split("/")
  if parts.len < 5:
    return @[relayAddr]

  let hostname = parts[2]
  let portStr = parts[4]
  let port = try:
    parseInt(portStr).Port
  except ValueError:
    return @[relayAddr]

  let domain = if relayAddr.startsWith("/dns4/"): Domain.AF_INET else: Domain.AF_INET6

  try:
    let resolved = resolveTAddress(hostname, port, domain)
    result = @[]
    for ta in resolved:
      let maStr = case ta.family
        of AddressFamily.IPv4:
          let ip = $IpAddress(family: IpAddressFamily.IPv4, address_v4: ta.address_v4)
          "/ip4/" & ip & "/tcp/" & portStr
        of AddressFamily.IPv6:
          let ip = $IpAddress(family: IpAddressFamily.IPv6, address_v6: ta.address_v6)
          "/ip6/" & ip & "/tcp/" & portStr
        else:
          continue
      result.add(maStr)
    if result.len == 0:
      result = @[relayAddr]
  except CatchableError:
    result = @[relayAddr]

proc connectViaRelay*(relayAddr: string, relayToken: string): Future[Connection] {.async.} =
  let candidates = resolveRelayAddr(relayAddr)

  var lastErr: string = ""
  for candidate in candidates:
    let maRes = MultiAddress.init(candidate)
    if maRes.isErr:
      lastErr = "invalid relay address: " & candidate
      continue

    let transp = await connect(maRes.get())

    try:
      discard await transp.write(toBytes(relayToken & "\n"))

      while true:
        let line = await readRelayLine(transp)
        if line == "WAIT":
          continue
        elif line == "OK":
          return Connection(
            ChronosStream.init(
              transp,
              Direction.Out,
              observedAddr = Opt.none(MultiAddress),
              localAddr = Opt.none(MultiAddress)
            )
          )
        elif line.startsWith("POW "):
          let parts = line.splitWhitespace()
          if parts.len != 3:
            raise newException(RelayError, "invalid relay proof-of-work challenge")

          let difficultyBits = try:
            parseInt(parts[2])
          except ValueError:
            raise newException(RelayError, "invalid relay proof-of-work difficulty")

          let solution = solveRelayPow(relayToken, parts[1], difficultyBits)
          if solution.len == 0:
            raise newException(RelayError, "failed to solve relay proof-of-work")
          discard await transp.write(toBytes("POW " & solution & "\n"))
        else:
          raise newException(RelayError, "unexpected relay response: " & line)
    except CatchableError as exc:
      await transp.closeWait()
      lastErr = candidate & ": " & exc.msg
      continue

  raise newException(RelayError, "all relay address candidates failed for " & relayAddr & ": " & lastErr)

proc connectViaRegionalRelay*(
    cache: RelayListCache,
    apiBaseUrl: string,
    relayRegion: string,
    relayToken: string,
): Future[tuple[conn: Connection, relayAddr: string]] {.async.} =
  var relayAddrs: seq[string]
  try:
    relayAddrs = orderedRelayAddrs(cache, apiBaseUrl, relayRegion, relayToken)
  except CatchableError as exc:
    raise newException(RelayError, "failed to resolve relay list: " & exc.msg)

  if relayAddrs.len == 0:
    raise newException(RelayError, "no relay addresses available for region: " & relayRegion)

  var failures: seq[string] = @[]
  for relayAddr in relayAddrs:
    try:
      let conn = await connectViaRelay(relayAddr, relayToken)
      return (conn, relayAddr)
    except CatchableError as exc:
      failures.add(relayAddr & ": " & exc.msg)

  raise newException(
    RelayError,
    "all relay attempts failed for region " & normalizeRelayRegion(relayRegion) & ": " & failures.join("; ")
  )
