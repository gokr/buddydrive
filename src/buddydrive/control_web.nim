import std/[base64, strutils]

const
  webIndex = staticRead("../web/index.html")
  webStyle = staticRead("../web/style.css")
  webApp = staticRead("../web/app.js")

  unauthorizedResponse = "HTTP/1.1 401 Unauthorized\r\n" &
    "WWW-Authenticate: Basic realm=\"BuddyDrive\"\r\n" &
    "Content-Type: text/plain\r\n" &
    "Content-Length: 12\r\n" &
    "Connection: close\r\n\r\n" &
    "Unauthorized"

proc staticHttpResponse(body: string, contentType: string): string {.compileTime.} =
  "HTTP/1.1 200 OK\r\n" &
    "Content-Type: " & contentType & "\r\n" &
    "Content-Length: " & $body.len & "\r\n" &
    "Connection: close\r\n\r\n" &
    body

const
  responseIndex = staticHttpResponse(webIndex, "text/html; charset=utf-8")
  responseStyle = staticHttpResponse(webStyle, "text/css; charset=utf-8")
  responseApp = staticHttpResponse(webApp, "application/javascript; charset=utf-8")

proc isLocalhost(address: string): bool =
  address.startsWith("127.") or address == "::1"

proc checkBasicAuth(authorization: string, password: string): bool =
  ## Validates Basic auth where any username is accepted and password must match.
  if not authorization.startsWith("Basic "):
    return false
  try:
    let decoded = base64.decode(authorization[6 .. ^1])
    let colonPos = decoded.find(':')
    if colonPos < 0:
      return false
    let providedPass = decoded[colonPos + 1 .. ^1]
    return providedPass == password
  except:
    return false

proc authenticateRequest*(raw: string, peerAddress: string, password: string): string =
  ## Returns unauthorizedResponse if auth fails for non-localhost, or "" if OK.
  if isLocalhost(peerAddress):
    return ""
  if password.len == 0:
    return unauthorizedResponse
  let head = raw.split("\r\n\r\n", 1)[0]
  var authorization = ""
  for line in head.splitLines():
    if line.toLowerAscii().startsWith("authorization:"):
      authorization = line[14 .. ^1].strip()
      break
  if not checkBasicAuth(authorization, password):
    return unauthorizedResponse
  ""

proc extractPath(raw: string): string =
  ## Quickly extracts the request path from a raw HTTP request.
  let lineEnd = raw.find('\r')
  let requestLine = if lineEnd > 0: raw[0 ..< lineEnd] else: raw
  let parts = requestLine.split(' ')
  if parts.len >= 2: parts[1] else: ""

proc serveWebRequest*(raw: string): string =
  ## Tries to serve a web asset from the raw request. Returns "" if not a web path.
  let path = extractPath(raw)
  case path
  of "/", "/index.html": responseIndex
  of "/style.css": responseStyle
  of "/app.js": responseApp
  else: ""
