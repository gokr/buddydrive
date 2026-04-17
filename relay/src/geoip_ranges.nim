import std/[algorithm, net, options, os, strutils]

type
  Ipv4Range* = object
    start*: uint32
    `end`*: uint32

  Ipv6Range* = object
    startHi*: uint64
    startLo*: uint64
    endHi*: uint64
    endLo*: uint64

  GeoRangeAllowlist* = object
    ipv4*: seq[Ipv4Range]
    ipv6*: seq[Ipv6Range]

proc ipv4ToUint32(ip: IpAddress): uint32 =
  doAssert ip.family == IpAddressFamily.IPv4
  for part in ip.address_v4:
    result = (result shl 8) or uint32(part)

proc ipv6ToUint128(ip: IpAddress): tuple[hi: uint64, lo: uint64] =
  doAssert ip.family == IpAddressFamily.IPv6
  for i in 0 .. 7:
    result.hi = (result.hi shl 8) or uint64(ip.address_v6[i])
  for i in 8 .. 15:
    result.lo = (result.lo shl 8) or uint64(ip.address_v6[i])

proc compare128(aHi, aLo, bHi, bLo: uint64): int =
  if aHi < bHi:
    return -1
  if aHi > bHi:
    return 1
  if aLo < bLo:
    return -1
  if aLo > bLo:
    return 1
  0

proc parseCidrLine(line: string): Option[(IpAddress, int)] =
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed.startsWith("#"):
    return none((IpAddress, int))

  let token = trimmed.splitWhitespace()[0]
  let slash = token.find('/')
  if slash <= 0 or slash >= token.high:
    return none((IpAddress, int))

  try:
    let ip = parseIpAddress(token[0 ..< slash])
    let prefix = parseInt(token[slash + 1 .. ^1])
    return some((ip, prefix))
  except CatchableError:
    return none((IpAddress, int))

proc addCidr*(allowlist: var GeoRangeAllowlist, cidr: string) =
  let parsed = parseCidrLine(cidr)
  if parsed.isNone:
    return

  let (ip, prefix) = parsed.get()
  case ip.family
  of IpAddressFamily.IPv4:
    if prefix < 0 or prefix > 32:
      return
    let value = ipv4ToUint32(ip)
    let startValue =
      if prefix == 0: 0'u32
      elif prefix == 32: value
      else:
        let hostBits = 32 - prefix
        value and (high(uint32) shl hostBits)
    let endValue =
      if prefix == 32: value
      elif prefix == 0: high(uint32)
      else:
        let hostBits = 32 - prefix
        startValue or ((1'u32 shl hostBits) - 1)
    allowlist.ipv4.add(Ipv4Range(start: startValue, `end`: endValue))
  of IpAddressFamily.IPv6:
    if prefix < 0 or prefix > 128:
      return
    let (hi, lo) = ipv6ToUint128(ip)
    var startHi = hi
    var startLo = lo
    var endHi = hi
    var endLo = lo
    if prefix == 0:
      startHi = 0
      startLo = 0
      endHi = high(uint64)
      endLo = high(uint64)
    elif prefix < 64:
      let hostBitsHi = 64 - prefix
      startHi = hi and (high(uint64) shl hostBitsHi)
      startLo = 0
      endHi = startHi or ((1'u64 shl hostBitsHi) - 1)
      endLo = high(uint64)
    elif prefix == 64:
      startLo = 0
      endLo = high(uint64)
    elif prefix < 128:
      let hostBitsLo = 128 - prefix
      startLo = lo and (high(uint64) shl hostBitsLo)
      endLo = startLo or ((1'u64 shl hostBitsLo) - 1)
    allowlist.ipv6.add(Ipv6Range(startHi: startHi, startLo: startLo, endHi: endHi, endLo: endLo))

proc sortAndCompact*(allowlist: var GeoRangeAllowlist) =
  allowlist.ipv4.sort(proc (a, b: Ipv4Range): int =
    if a.start < b.start: -1
    elif a.start > b.start: 1
    elif a.`end` < b.`end`: -1
    elif a.`end` > b.`end`: 1
    else: 0
  )
  allowlist.ipv6.sort(proc (a, b: Ipv6Range): int =
    let startCmp = compare128(a.startHi, a.startLo, b.startHi, b.startLo)
    if startCmp != 0:
      return startCmp
    compare128(a.endHi, a.endLo, b.endHi, b.endLo)
  )

  var compactV4: seq[Ipv4Range] = @[]
  for entry in allowlist.ipv4:
    let separated =
      compactV4.len == 0 or
      (compactV4[^1].`end` != high(uint32) and entry.start > compactV4[^1].`end` + 1)
    if separated:
      compactV4.add(entry)
    else:
      compactV4[^1].`end` = max(compactV4[^1].`end`, entry.`end`)
  allowlist.ipv4 = compactV4

  var compactV6: seq[Ipv6Range] = @[]
  for entry in allowlist.ipv6:
    if compactV6.len == 0:
      compactV6.add(entry)
      continue

    let prev = compactV6[^1]
    let overlaps = compare128(entry.startHi, entry.startLo, prev.endHi, prev.endLo) <= 0
    let adjacent = prev.endHi == entry.startHi and prev.endLo != high(uint64) and prev.endLo + 1 == entry.startLo
    if overlaps or adjacent:
      if compare128(entry.endHi, entry.endLo, compactV6[^1].endHi, compactV6[^1].endLo) > 0:
        compactV6[^1].endHi = entry.endHi
        compactV6[^1].endLo = entry.endLo
    else:
      compactV6.add(entry)
  allowlist.ipv6 = compactV6

proc loadGeoRangeAllowlist*(path: string): GeoRangeAllowlist =
  if path.len == 0 or not fileExists(path):
    return

  for line in lines(path):
    result.addCidr(line)
  result.sortAndCompact()

proc contains*(allowlist: GeoRangeAllowlist, ip: IpAddress): bool =
  case ip.family
  of IpAddressFamily.IPv4:
    let value = ipv4ToUint32(ip)
    var low = 0
    var high = allowlist.ipv4.len - 1
    while low <= high:
      let mid = (low + high) shr 1
      let entry = allowlist.ipv4[mid]
      if value < entry.start:
        high = mid - 1
      elif value > entry.`end`:
        low = mid + 1
      else:
        return true
  of IpAddressFamily.IPv6:
    let (hi, lo) = ipv6ToUint128(ip)
    var low = 0
    var high = allowlist.ipv6.len - 1
    while low <= high:
      let mid = (low + high) shr 1
      let entry = allowlist.ipv6[mid]
      if compare128(hi, lo, entry.startHi, entry.startLo) < 0:
        high = mid - 1
      elif compare128(hi, lo, entry.endHi, entry.endLo) > 0:
        low = mid + 1
      else:
        return true
  false
