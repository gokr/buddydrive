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
  if discRes.isErr():
    echo "UPnP discovery failed: ", discRes.error()
    return none(string)
  
  if discRes.get() == 0:
    echo "UPnP found no devices"
    return none(string)
  
  echo "UPnP discovered ", discRes.get(), " device(s)"
  
  let igdRes = client.selectIGD()
  echo "UPnP IGD status: ", $igdRes, " (lan: ", client.lanAddr, ", wan: ", client.wanAddr, ")"
  
  if igdRes == IGDNotFound or igdRes == NotAnIGD:
    echo "UPnP did not find a valid Internet Gateway Device"
    return none(string)
  
  if igdRes == IGDNotConnected:
    echo "UPnP IGD reports disconnected WAN - trying port mapping anyway..."
  
  let ipRes = client.externalIPAddress()
  if ipRes.isErr():
    echo "UPnP failed to get external IP: ", ipRes.error()
    return none(string)
  
  let externalIp = ipRes.get()
  let internalHost = client.lanAddr
  
  if isCgnatAddress(externalIp):
    echo "UPnP got CGNAT address ", externalIp, " - not publicly routable (ISP-level NAT)"
    echo "Your ISP is using Carrier-Grade NAT. UPnP cannot help here."
    echo "You may need to: request a public IP from your ISP, or use a VPN/relay service."
    return none(string)
  
  echo "UPnP attempting port mapping: ", internalHost, ":", $port, " -> ", externalIp, ":", $port
  
  let mapRes = client.addPortMapping(
    $port, TCP, internalHost, $port, "BuddyDrive"
  )
  
  if mapRes.isErr():
    echo "UPnP failed to add port mapping for port ", port, ": ", mapRes.error()
    return none(string)
  
  echo "UPnP port mapping successful: external IP ", externalIp, " port ", port
  result = some("/ip4/" & externalIp & "/tcp/" & $port)
