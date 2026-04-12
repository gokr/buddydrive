import std/[os, strutils, json, times, asyncdispatch]
import std/[nativesockets, parseutils]
import kvstore

type
  HttpServerState = object
    kv: KvStore
    listenFd: SocketHandle
    port: int

const HTTP_BUFFER_SIZE = 1024 * 1024
const KV_API_PORT_DEFAULT = 8080

var httpState: HttpServerState

proc parseRequest(data: string): tuple[method: string, path: string, headers: seq[(string, string)], body: string] =
  let lines = data.split("\r\n")
  if lines.len < 1:
    return ("", "", @[], "")
  
  let firstLine = lines[0].split(" ")
  if firstLine.len < 2:
    return ("", "", @[], "")
  
  result.method = firstLine[0]
  result.path = firstLine[1]
  result.headers = @[]
  result.body = ""
  
  var i = 1
  while i < lines.len:
    if lines[i].len == 0:
      break
    let colonPos = lines[i].find(":")
    if colonPos > 0:
      let key = lines[i][0 ..< colonPos].strip()
      let value = lines[i][colonPos + 1 ..^ 1].strip()
      result.headers.add((key, value))
    inc i
  
  if i + 1 < lines.len:
    result.body = lines[i + 1 ..^ 1].join("\r\n")

proc buildResponse(status: int, headers: seq[(string, string)], body: string): string =
  let statusText = case status
    of 200: "OK"
    of 201: "Created"
    of 204: "No Content"
    of 400: "Bad Request"
    of 404: "Not Found"
    of 405: "Method Not Allowed"
    of 500: "Internal Server Error"
    else: "Unknown"
  
  var response = "HTTP/1.1 " & $status & " " & statusText & "\r\n"
  for (key, value) in headers:
    response.add(key & ": " & value & "\r\n")
  response.add("Content-Length: " & $body.len & "\r\n")
  response.add("Connection: close\r\n")
  response.add("\r\n")
  response.add(body)
  result = response

proc handleRequest(fd: SocketHandle, request: tuple[method: string, path: string, headers: seq[(string, string)], body: string]): string =
  if request.path.startsWith("/kv/"):
    let pubkeyB58 = request.path[4..^1].strip(chars = {'/'})
    
    if pubkeyB58.len == 0:
      return buildResponse(400, @[("Content-Type", "text/plain")], "Missing public key")
    
    case request.method
    of "GET":
      let configOpt = fetchConfig(httpState.kv, pubkeyB58)
      if configOpt.isSome:
        let (data, _) = configOpt.get()
        return buildResponse(200, @[("Content-Type", "application/octet-stream")], data)
      else:
        return buildResponse(404, @[("Content-Type", "text/plain")], "Config not found")
    
    of "PUT", "POST":
      if request.body.len == 0:
        return buildResponse(400, @[("Content-Type", "text/plain")], "Missing config data")
      
      if storeConfig(httpState.kv, pubkeyB58, request.body):
        return buildResponse(201, @[("Content-Type", "application/json")], "{\"ok\":true}")
      else:
        return buildResponse(500, @[("Content-Type", "text/plain")], "Failed to store config")
    
    of "DELETE":
      if deleteConfig(httpState.kv, pubkeyB58):
        return buildResponse(204, @[("Content-Type", "text/plain")], "")
      else:
        return buildResponse(404, @[("Content-Type", "text/plain")], "Config not found")
    
    else:
      return buildResponse(405, @[("Content-Type", "text/plain")], "Method not allowed")
  
  elif request.path == "/health":
    return buildResponse(200, @[("Content-Type", "application/json")], "{\"status\":\"ok\"}")
  
  elif request.path == "/stats":
    let count = getConfigCount(httpState.kv)
    return buildResponse(200, @[("Content-Type", "application/json")], "{\"config_count\":" & $count & "}")
  
  else:
    return buildResponse(404, @[("Content-Type", "text/plain")], "Not found")

proc handleClient(fd: SocketHandle) {.async.} =
  var buffer = newString(HTTP_BUFFER_SIZE)
  var totalData = ""
  var contentLength = 0
  
  while true:
    let n = recv(fd, addr buffer[0], buffer.len.cint, 0)
    if n <= 0:
      break
    
    totalData.add(buffer[0 ..< n])
    
    let headerEnd = totalData.find("\r\n\r\n")
    if headerEnd >= 0:
      for line in totalData[0 ..< headerEnd].split("\r\n"):
        if line.toLowerAscii().startsWith("content-length:"):
          discard parseInt(line.split(":")[1].strip(), contentLength)
      
      let bodyStart = headerEnd + 4
      let body = if contentLength > 0: totalData[bodyStart ..< min(totalData.len, bodyStart + contentLength)] else: ""
      let headerData = totalData[0 ..< headerEnd + 4]
      
      let request = parseRequest(headerData & body)
      let response = handleRequest(fd, request)
      
      discard send(fd, response[0].addr, response.len.cint, MSG_NOSIGNAL)
      break

proc runKvApi*(kv: KvStore, port: int = KV_API_PORT_DEFAULT) =
  httpState.kv = kv
  httpState.port = port
  
  let listenFd = createNativeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if listenFd.int < 0:
    echo "Failed to create HTTP socket"
    return
  
  setSockOptInt(listenFd, SOL_SOCKET, SO_REUSEADDR, 1)
  setBlocking(listenFd, true)
  
  var addrInfo: Sockaddr_in
  addrInfo.sin_family = AF_INET.uint16
  addrInfo.sin_port = htons(port.uint16)
  addrInfo.sin_addr.s_addr = INADDR_ANY
  
  if bindAddr(listenFd, cast[ptr SockAddr](addr addrInfo), sizeof(addrInfo).SockLen) < 0:
    echo "Failed to bind HTTP to port ", port
    close(listenFd)
    return
  
  if listen(listenFd, 64) < 0:
    echo "Failed to listen on HTTP"
    close(listenFd)
    return
  
  httpState.listenFd = listenFd
  
  echo "KV API HTTP server listening on port ", port
  echo "Endpoints:"
  echo "  GET    /kv/<pubkey>   - Fetch encrypted config"
  echo "  PUT    /kv/<pubkey>   - Store encrypted config"
  echo "  DELETE /kv/<pubkey>   - Delete config"
  echo "  GET    /health        - Health check"
  echo "  GET    /stats         - Server stats"
  
  asyncCheck acceptLoop()
  poll()

proc acceptLoop() {.async.} =
  while true:
    var clientAddr: SockAddr
    var clientAddrLen = sizeof(clientAddr).SockLen
    let clientFd = accept(httpState.listenFd, addr clientAddr, addr clientAddrLen)
    
    if clientFd.int >= 0:
      asyncCheck handleClient(clientFd)
    else:
      await sleepAsync(100)
