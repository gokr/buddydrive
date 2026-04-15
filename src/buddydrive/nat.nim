import std/options
import std/strutils
import results
import nat_traversal/miniupnpc

export options

proc isCgnatAddress(ip: string): bool =
  let parts = ip.split(".")
  if parts.len != 4:
    return false
  try:
    let first = parseInt(parts[0])
    let second = parseInt(parts[1])
    if first == 100 and second >= 64 and second <= 127:
      return true
  except ValueError:
    discard
  false

proc attemptUpnpPortMapping*(port: int): Option[string] =
  let client = newMiniupnp()
  client.discoverDelay = 3000
  
  let discRes = client.discover()
  if discRes.isErr() or discRes.get() == 0:
    return none(string)
  
  let igdRes = client.selectIGD()
  if igdRes == IGDNotFound or igdRes == NotAnIGD:
    return none(string)

  let ipRes = client.externalIPAddress()
  if ipRes.isErr():
    return none(string)
  
  let externalIp = ipRes.get()
  let internalHost = client.lanAddr
  
  if isCgnatAddress(externalIp):
    echo "UPnP detected CGNAT address ", externalIp, " — not publicly routable. Consider relay fallback or a VPN."
    return none(string)
  
  let mapRes = client.addPortMapping(
    $port, TCP, internalHost, $port, "BuddyDrive"
  )
  
  if mapRes.isErr():
    echo "UPnP port mapping failed for port ", port, ": ", mapRes.error()
    return none(string)
  
  echo "UPnP mapped port ", port, " to external IP ", externalIp
  result = some("/ip4/" & externalIp & "/tcp/" & $port)

proc removeUpnpPortMapping*(port: int) =
  let client = newMiniupnp()
  client.discoverDelay = 3000

  let discRes = client.discover()
  if discRes.isErr() or discRes.get() == 0:
    return

  let igdRes = client.selectIGD()
  if igdRes == IGDNotFound or igdRes == NotAnIGD:
    return

  discard client.deletePortMapping($port, TCP)
