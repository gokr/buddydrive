import std/[os, strutils]

const
  forbiddenResponse* = "HTTP/1.1 403 Forbidden\r\n" &
    "Content-Type: text/plain\r\n" &
    "Content-Length: 9\r\n" &
    "Connection: close\r\n\r\n" &
    "Forbidden"

proc httpResponse(body: string, contentType: string): string =
  "HTTP/1.1 200 OK\r\n" &
    "Content-Type: " & contentType & "\r\n" &
    "Content-Length: " & $body.len & "\r\n" &
    "Connection: close\r\n\r\n" &
    body

proc webDir(): string =
  ## Locates the web/ directory relative to the executable.
  getAppDir() / ".." / "src" / "web"

proc serveFile(filename: string, contentType: string): string =
  let path = webDir() / filename
  if not fileExists(path):
    return ""
  httpResponse(readFile(path), contentType)

proc isLocalhost*(address: string): bool =
  address.startsWith("127.") or address == "::1"

proc webSecret*(buddyUuid: string): string =
  ## Derives an 8-char secret from the buddy UUID (lowercase, no hyphens).
  buddyUuid.replace("-", "").toLowerAscii()[0 ..< 8]

proc extractPath(raw: string): string =
  ## Quickly extracts the request path from a raw HTTP request.
  let lineEnd = raw.find('\r')
  let requestLine = if lineEnd > 0: raw[0 ..< lineEnd] else: raw
  let parts = requestLine.split(' ')
  if parts.len >= 2: parts[1] else: ""

proc stripSecretPrefix(path: string, secret: string): string =
  ## If path starts with /w/<secret>/, returns the remainder (with leading /).
  ## Returns "" if the secret doesn't match.
  let prefix = "/w/" & secret & "/"
  if path.startsWith(prefix):
    return path[prefix.len - 1 .. ^1]  # keep the leading /
  let prefixNoTrail = "/w/" & secret
  if path == prefixNoTrail:
    return "/"
  ""

proc rewriteLanRequest*(raw: string, buddyUuid: string): string =
  ## Validates the /w/<secret>/ prefix and returns the request with path rewritten.
  ## Returns "" if the secret is missing or wrong.
  let secret = webSecret(buddyUuid)
  let path = extractPath(raw)
  let stripped = stripSecretPrefix(path, secret)
  if stripped.len == 0:
    return ""
  raw.replace(" " & path & " ", " " & stripped & " ")

proc serveWebRequest*(raw: string): string =
  ## Tries to serve a web asset from the raw request. Returns "" if not a web path.
  let path = extractPath(raw)
  case path
  of "/", "/index.html": serveFile("index.html", "text/html; charset=utf-8")
  of "/style.css": serveFile("style.css", "text/css; charset=utf-8")
  of "/app.js": serveFile("app.js", "application/javascript; charset=utf-8")
  else: ""
