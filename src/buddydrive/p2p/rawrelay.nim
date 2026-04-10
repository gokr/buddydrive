import std/[json, strutils, tables, times]
import chronos
import curly
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
      "/dns4/relay-eu-1.buddydrive.net/tcp/41722",
      "/dns4/relay-eu-2.buddydrive.net/tcp/41722",
      "/dns4/relay-eu-3.buddydrive.net/tcp/41722"
    ]
  of "us":
    @[
      "/dns4/relay-us-1.buddydrive.net/tcp/41722",
      "/dns4/relay-us-2.buddydrive.net/tcp/41722",
      "/dns4/relay-us-3.buddydrive.net/tcp/41722"
    ]
  of "asia":
    @[
      "/dns4/relay-asia-1.buddydrive.net/tcp/41722",
      "/dns4/relay-asia-2.buddydrive.net/tcp/41722",
      "/dns4/relay-asia-3.buddydrive.net/tcp/41722"
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

  let url = trimmedBase.strip(chars = {'/'}) & "/" & normalizeRelayRegion(region)

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
    relayBaseUrl: string,
    relayRegion: string,
): seq[string] {.raises: [].} =
  let region = normalizeRelayRegion(relayRegion)
  if region.len == 0:
    return @[]

  let key = relayCacheKey(relayBaseUrl, region)
  let cached = cache.entries.getOrDefault(key)
  if cached.relays.len > 0 and cached.expiresAt > getTime():
    return cached.relays

  let fetched = fetchRelayList(relayBaseUrl, region)
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
    relayBaseUrl: string,
    relayRegion: string,
    relayToken: string,
): seq[string] {.raises: [].} =
  let relays = relayAddrsForRegion(cache, relayBaseUrl, relayRegion)
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

proc connectViaRelay*(relayAddr: string, relayToken: string): Future[Connection] {.async.} =
  let maRes = MultiAddress.init(relayAddr)
  if maRes.isErr:
    raise newException(RelayError, "invalid relay address: " & relayAddr)

  let transp = await connect(maRes.get())

  try:
    discard await transp.write(toBytes(relayToken & "\n"))

    while true:
      let line = await readRelayLine(transp)
      case line
      of "WAIT":
        continue
      of "OK":
        return Connection(
          ChronosStream.init(
            transp,
            Direction.Out,
            observedAddr = Opt.none(MultiAddress),
            localAddr = Opt.none(MultiAddress)
          )
        )
      else:
        raise newException(RelayError, "unexpected relay response: " & line)
  except CatchableError as exc:
    await transp.closeWait()
    raise exc

proc connectViaRegionalRelay*(
    cache: RelayListCache,
    relayBaseUrl: string,
    relayRegion: string,
    relayToken: string,
): Future[tuple[conn: Connection, relayAddr: string]] {.async.} =
  var relayAddrs: seq[string]
  try:
    relayAddrs = orderedRelayAddrs(cache, relayBaseUrl, relayRegion, relayToken)
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
