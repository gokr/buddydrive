import std/[locks, net, os, strutils]
import geoip_ranges

type
  GeoPolicyStatus* = object
    enabled*: bool
    active*: bool
    path*: string
    cidrCount*: int
    message*: string

var geoPolicyLock: Lock
var geoPolicyLockInitialized = false
var cachedPath = ""
var cachedAllowlist: GeoRangeAllowlist
var cachedCidrCount = 0
var cachedLoaded = false

proc ensureGeoPolicyLock() =
  if not geoPolicyLockInitialized:
    initLock(geoPolicyLock)
    geoPolicyLockInitialized = true

proc normalizedClientIp*(ip: string): string =
  result = ip.strip()
  if result.len == 0:
    return
  if result.startsWith("["):
    let closing = result.find(']')
    if closing > 1:
      return result[1 ..< closing]
  let colon = result.rfind(':')
  if colon > 0 and result.find('.') >= 0:
    return result[0 ..< colon]

proc isPrivateOrLoopbackIp*(ip: string): bool =
  let normalized = ip.toLowerAscii()
  if normalized.len == 0:
    return true
  if normalized == "::1" or normalized == "localhost" or normalized.startsWith("127."):
    return true
  if normalized.startsWith("10.") or normalized.startsWith("192.168.") or normalized.startsWith("169.254."):
    return true
  if normalized.startsWith("172."):
    let parts = normalized.split('.')
    if parts.len >= 2:
      try:
        let secondOctet = parseInt(parts[1])
        if secondOctet >= 16 and secondOctet <= 31:
          return true
      except ValueError:
        discard
  if normalized.startsWith("fc") or normalized.startsWith("fd") or normalized.startsWith("fe80:"):
    return true
  false

proc countCidrEntries(path: string): int =
  if path.len == 0 or not fileExists(path):
    return 0
  for line in lines(path):
    let trimmed = line.strip()
    if trimmed.len > 0 and not trimmed.startsWith("#"):
      inc result

proc ensureAllowlistLoaded(path: string) =
  ensureGeoPolicyLock()
  withLock geoPolicyLock:
    if path.len == 0 or not fileExists(path):
      cachedPath = path
      cachedAllowlist = GeoRangeAllowlist()
      cachedCidrCount = 0
      cachedLoaded = false
      return

    if cachedLoaded and cachedPath == path:
      return

    cachedAllowlist = loadGeoRangeAllowlist(path)
    cachedCidrCount = countCidrEntries(path)
    cachedPath = path
    cachedLoaded = true

proc configureEuGeoPolicy*(enabled: bool, path, label: string): GeoPolicyStatus =
  result.enabled = enabled
  result.path = path
  if not enabled:
    return

  ensureAllowlistLoaded(path)
  withLock geoPolicyLock:
    result.active = cachedLoaded and cachedPath == path
    result.cidrCount = cachedCidrCount

  if result.active:
    result.message = "  EU-only " & label & " access enabled from " & path & " (" & $result.cidrCount & " CIDRs loaded)"
  else:
    result.message = "  EU-only " & label & " access requested but range file is unavailable"

proc allowEuGeoAccess*(ip: string, enabled: bool): bool =
  if not enabled:
    return true

  let normalizedIp = normalizedClientIp(ip)
  if normalizedIp.len == 0 or isPrivateOrLoopbackIp(normalizedIp):
    return true

  try:
    let parsedIp = parseIpAddress(normalizedIp)
    ensureGeoPolicyLock()
    var allowed = false
    withLock geoPolicyLock:
      allowed = cachedLoaded and cachedAllowlist.contains(parsedIp)
    allowed
  except CatchableError:
    false
