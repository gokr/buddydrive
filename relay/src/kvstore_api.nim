import std/[strutils, options]
import mummy
import kvstore

var theKvStore: KvStore

proc handler(request: Request) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if request.path.startsWith("/kv/"):
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
      let count = getConfigCount(theKvStore)
      var h = emptyHttpHeaders()
      h["Content-Type"] = "application/json"
      request.respond(200, h, "{\"config_count\":" & $count & "}")

    else:
      var h = emptyHttpHeaders()
      h["Content-Type"] = "text/plain"
      request.respond(404, h, "Not found")

proc runKvApi*(kv: KvStore, port: int = 8080) =
  theKvStore = kv

  let server = newServer(handler)
  echo "KV API HTTP server starting on port ", port
  echo "Endpoints:"
  echo "  GET    /kv/<pubkey>   - Fetch encrypted config"
  echo "  PUT    /kv/<pubkey>   - Store encrypted config"
  echo "  DELETE /kv/<pubkey>   - Delete config"
  echo "  GET    /health        - Health check"
  echo "  GET    /stats         - Server stats"

  server.serve(Port(port), "0.0.0.0")
