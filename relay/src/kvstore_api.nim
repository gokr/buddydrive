import std/[strutils, options]
import mummy
import kvstore

var theKvStore: KvStore

proc handler(request: Request) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if request.path.startsWith("/discovery/"):
      let key = request.path[12..^1].strip(chars = {'/'})

      if key.len == 0:
        var h = emptyHttpHeaders()
        h["Content-Type"] = "text/plain"
        request.respond(400, h, "Missing discovery key")
        return

      case request.httpMethod
      of "GET":
        let recordOpt = fetchDiscovery(theKvStore, key)
        if recordOpt.isSome:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/json"
          request.respond(200, h, recordOpt.get())
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(404, h, "Discovery record not found or expired")

      of "PUT", "POST":
        let hmacHeader = request.headers.getOrDefault("X-HMAC")
        if hmacHeader.len == 0:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(400, h, "Missing X-HMAC header")
          return

        if request.body.len == 0:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(400, h, "Missing record body")
          return

        if storeDiscovery(theKvStore, key, request.body, hmacHeader):
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/json"
          request.respond(201, h, "{\"ok\":true}")
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(401, h, "HMAC mismatch or store error")

      of "DELETE":
        let hmacHeader = request.headers.getOrDefault("X-HMAC")
        if hmacHeader.len == 0:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(400, h, "Missing X-HMAC header")
          return

        if deleteDiscovery(theKvStore, key, hmacHeader):
          request.respond(204)
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(404, h, "Discovery record not found or HMAC mismatch")

      else:
        var h = emptyHttpHeaders()
        h["Content-Type"] = "text/plain"
        request.respond(405, h, "Method not allowed")

    elif request.path.startsWith("/kv/"):
      let pubkeyB58 = request.path[4..^1].strip(chars = {'/'})

      if pubkeyB58.len == 0:
        var h = emptyHttpHeaders()
        h["Content-Type"] = "text/plain"
        request.respond(400, h, "Missing public key")
        return

      case request.httpMethod
      of "GET":
        let configOpt = fetchConfig(theKvStore, pubkeyB58)
        if configOpt.isSome:
          let (data, _) = configOpt.get()
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/octet-stream"
          request.respond(200, h, data)
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(404, h, "Config not found")

      of "PUT", "POST":
        if request.body.len == 0:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(400, h, "Missing config data")
          return

        if storeConfig(theKvStore, pubkeyB58, request.body):
          var h = emptyHttpHeaders()
          h["Content-Type"] = "application/json"
          request.respond(201, h, "{\"ok\":true}")
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(500, h, "Failed to store config")

      of "DELETE":
        if deleteConfig(theKvStore, pubkeyB58):
          request.respond(204)
        else:
          var h = emptyHttpHeaders()
          h["Content-Type"] = "text/plain"
          request.respond(404, h, "Config not found")

      else:
        var h = emptyHttpHeaders()
        h["Content-Type"] = "text/plain"
        request.respond(405, h, "Method not allowed")

    elif request.path == "/health":
      var h = emptyHttpHeaders()
      h["Content-Type"] = "application/json"
      request.respond(200, h, "{\"status\":\"ok\"}")

    elif request.path == "/stats":
      let configCount = getConfigCount(theKvStore)
      let discoveryCount = getDiscoveryCount(theKvStore)
      var h = emptyHttpHeaders()
      h["Content-Type"] = "application/json"
      request.respond(200, h, "{\"config_count\":" & $configCount & ",\"discovery_count\":" & $discoveryCount & "}")

    else:
      var h = emptyHttpHeaders()
      h["Content-Type"] = "text/plain"
      request.respond(404, h, "Not found")

proc runKvApi*(kv: KvStore, port: int = 8080) =
  theKvStore = kv

  let server = newServer(handler)
  echo "KV API HTTP server starting on port ", port
  echo "Endpoints:"
  echo "  GET    /discovery/<key>  - Fetch buddy address record"
  echo "  PUT    /discovery/<key>  - Store buddy address record (X-HMAC header required)"
  echo "  DELETE /discovery/<key>  - Delete address record (X-HMAC header required)"
  echo "  GET    /kv/<pubkey>      - Fetch encrypted config"
  echo "  PUT    /kv/<pubkey>      - Store encrypted config"
  echo "  DELETE /kv/<pubkey>      - Delete config"
  echo "  GET    /health           - Health check"
  echo "  GET    /stats            - Server stats"

  server.serve(Port(port), "0.0.0.0")
