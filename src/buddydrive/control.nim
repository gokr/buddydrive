import std/[json, net, os, random, strutils, tables, times]
import db_connector/db_sqlite
import types
import config

const
  DefaultControlPort* = 17521

var controlStarted = false
var controlThread: Thread[int]

proc getStateDb(): DbConn =
  let path = config.getConfigDir() / "state.db"
  result = open(path, "", "", "")
  result.exec(sql"""
    CREATE TABLE IF NOT EXISTS runtime_status (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      peer_id TEXT,
      addresses TEXT,
      running INTEGER,
      started_at INTEGER
    )
  """)
  result.exec(sql"""
    CREATE TABLE IF NOT EXISTS buddy_state (
      id TEXT PRIMARY KEY,
      name TEXT,
      state TEXT,
      latency_ms INTEGER,
      last_activity TEXT
    )
  """)
  result.exec(sql"""
    CREATE TABLE IF NOT EXISTS folder_state (
      name TEXT PRIMARY KEY,
      total_bytes INTEGER,
      synced_bytes INTEGER,
      file_count INTEGER,
      synced_files INTEGER,
      status TEXT
    )
  """)

proc writeRuntimeStatus*(cfg: AppConfig, peerId: string, addresses: seq[string], startTime: Time, running = true) =
  config.ensureConfigDir()
  let db = getStateDb()
  try:
    db.exec(sql"DELETE FROM runtime_status")
    db.exec(sql"""
      INSERT INTO runtime_status (id, peer_id, addresses, running, started_at)
      VALUES (1, ?, ?, ?, ?)
    """, peerId, addresses.join(","), if running: 1 else: 0, startTime.toUnix())
  finally:
    db.close()

proc writeLiveStatus*(buddyStatuses: seq[BuddyStatus], folderStatuses: seq[SyncStatus]) =
  config.ensureConfigDir()
  let db = getStateDb()
  try:
    db.exec(sql"DELETE FROM buddy_state")
    for b in buddyStatuses:
      db.exec(sql"""
        INSERT INTO buddy_state (id, name, state, latency_ms, last_activity)
        VALUES (?, ?, ?, ?, ?)
      """, b.id, b.name, $b.state, b.latencyMs, b.lastSync.format("yyyy-MM-dd'T'HH:mm:ss'Z'"))
    
    db.exec(sql"DELETE FROM folder_state")
    for f in folderStatuses:
      db.exec(sql"""
        INSERT INTO folder_state (name, total_bytes, synced_bytes, file_count, synced_files, status)
        VALUES (?, ?, ?, ?, ?, ?)
      """, f.folder, f.totalBytes, f.syncedBytes, f.fileCount, f.syncedFiles, f.status)
  finally:
    db.close()

proc markControlStopped*() =
  if not config.configExists():
    return
  let cfg = config.loadConfig()
  writeRuntimeStatus(cfg, "", @[], getTime(), running = false)

proc jsonResponse(status: int, node: JsonNode): string =
  let body = $node
  let statusText = case status
  of 200: "OK"
  of 400: "Bad Request"
  of 404: "Not Found"
  of 500: "Internal Server Error"
  else: "OK"
  result = "HTTP/1.1 " & $status & " " & statusText & "\r\n"
  result.add("Content-Type: application/json\r\n")
  result.add("Content-Length: " & $body.len & "\r\n")
  result.add("Connection: close\r\n\r\n")
  result.add(body)

proc parseRequest(raw: string): tuple[httpMethod: string, path: string, body: string] =
  let parts = raw.split("\r\n\r\n", 1)
  let head = parts[0].splitLines()
  if head.len == 0:
    return
  let requestLine = head[0].split(" ")
  if requestLine.len >= 2:
    result.httpMethod = requestLine[0]
    result.path = requestLine[1]
  if parts.len > 1:
    result.body = parts[1]

proc statusJson(): JsonNode =
  let statePath = config.getConfigDir() / "state.db"
  if fileExists(statePath):
    let db = getStateDb()
    try:
      let row = db.getRow(sql"SELECT peer_id, addresses, running, started_at FROM runtime_status WHERE id = 1")
      if row.len > 0 and row[0].len > 0:
        let peerId = row[0]
        let addresses = if row[1].len > 0: row[1].split(",") else: @[]
        let running = row[2] == "1"
        let startedAt = row[3].parseInt()
        let uptime = if running: max(0, getTime().toUnix() - startedAt) else: 0
        
        let cfg = config.loadConfig()
        return %*{
          "buddy": {
            "name": cfg.buddy.name,
            "id": cfg.buddy.uuid
          },
          "running": running,
          "uptime": uptime,
          "peerId": peerId,
          "addresses": addresses
        }
    finally:
      db.close()
  
  if config.configExists():
    let cfg = config.loadConfig()
    return %*{
      "buddy": {
        "name": cfg.buddy.name,
        "id": cfg.buddy.uuid
      },
      "running": false,
      "uptime": 0,
      "peerId": "",
      "addresses": []
    }
  %*{
    "buddy": {"name": "Unknown", "id": ""},
    "running": false,
    "uptime": 0,
    "peerId": "",
    "addresses": []
  }

proc buddiesJson(): JsonNode =
  let statePath = config.getConfigDir() / "state.db"
  if fileExists(statePath):
    let db = getStateDb()
    try:
      var buddies: seq[JsonNode] = @[]
      for row in db.rows(sql"SELECT id, name, state, latency_ms, last_activity FROM buddy_state"):
        buddies.add(%*{
          "id": row[0],
          "name": row[1],
          "state": row[2],
          "latencyMs": row[3].parseInt(),
          "lastSync": row[4]
        })
      if buddies.len > 0:
        return %*{"buddies": buddies}
    finally:
      db.close()
  
  if not config.configExists():
    return %*{"buddies": []}
  let cfg = config.loadConfig()
  var buddies: seq[JsonNode] = @[]
  for buddy in cfg.buddies:
    buddies.add(%*{
      "id": buddy.id.uuid,
      "name": buddy.id.name,
      "state": "disconnected",
      "latencyMs": -1,
      "lastSync": buddy.addedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    })
  %*{"buddies": buddies}

proc foldersJson(): JsonNode =
  var liveFolders: Table[string, JsonNode] = initTable[string, JsonNode]()
  
  let statePath = config.getConfigDir() / "state.db"
  if fileExists(statePath):
    let db = getStateDb()
    try:
      for row in db.rows(sql"SELECT name, total_bytes, synced_bytes, file_count, synced_files, status FROM folder_state"):
        liveFolders[row[0]] = %*{
          "totalBytes": row[1].parseInt(),
          "syncedBytes": row[2].parseInt(),
          "fileCount": row[3].parseInt(),
          "syncedFiles": row[4].parseInt(),
          "status": row[5]
        }
    finally:
      db.close()
  
  if not config.configExists():
    return %*{"folders": []}
  let cfg = config.loadConfig()
  var folders: seq[JsonNode] = @[]
  for folder in cfg.folders:
    var folderJson = %*{
      "name": folder.name,
      "path": folder.path,
      "encrypted": folder.encrypted,
      "buddies": folder.buddies,
      "status": {
        "totalBytes": 0,
        "syncedBytes": 0,
        "fileCount": 0,
        "syncedFiles": 0,
        "status": "idle"
      }
    }
    if liveFolders.hasKey(folder.name):
      folderJson["status"] = liveFolders[folder.name]
    folders.add(folderJson)
  %*{"folders": folders}

proc configJson(): JsonNode =
  if not config.configExists():
    return %*{"buddy": {}, "folders": [], "buddies": []}
  let cfg = config.loadConfig()
  var folders: seq[JsonNode] = @[]
  var buddies: seq[JsonNode] = @[]
  for folder in cfg.folders:
    folders.add(%*{
      "name": folder.name,
      "path": folder.path,
      "encrypted": folder.encrypted,
      "buddies": folder.buddies
    })
  for buddy in cfg.buddies:
    buddies.add(%*{
      "id": buddy.id.uuid,
      "name": buddy.id.name,
      "publicKey": buddy.publicKey,
      "addedAt": buddy.addedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    })
  %*{
    "buddy": {
      "name": cfg.buddy.name,
      "id": cfg.buddy.uuid
    },
    "folders": folders,
    "buddies": buddies
  }

proc logsJson(): JsonNode =
  let logPath = config.getLogPath()
  if not fileExists(logPath):
    return %*{"logs": []}
  let lines = readFile(logPath).splitLines()
  let start = max(0, lines.len - 100)
  var logs: seq[JsonNode] = @[]
  for i in start ..< lines.len:
    if lines[i].len > 0:
      logs.add(%*{"raw": lines[i]})
  %*{"logs": logs}

proc pairingCodeJson(): JsonNode =
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  randomize()
  var code = ""
  for _ in 0 .. 3:
    code.add(chars[rand(chars.high)])
  code.add('-')
  for _ in 0 .. 3:
    code.add(chars[rand(chars.high)])
  let cfg = config.loadConfig()
  %*{
    "buddyId": cfg.buddy.uuid,
    "buddyName": cfg.buddy.name,
    "pairingCode": code,
    "expiresAt": (getTime() + initDuration(minutes = 5)).format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  }

proc addFolderFromBody(body: string): tuple[status: int, response: JsonNode] =
  let parsed = parseJson(body)
  var cfg = config.loadConfig()
  var folder = newFolderConfig(parsed{"name"}.getStr(""), parsed{"path"}.getStr(""), parsed{"encrypted"}.getBool(true))
  if folder.name.len == 0 or folder.path.len == 0:
    return (400, %*{"error": "name and path are required", "code": "INVALID_REQUEST"})
  if parsed.hasKey("buddies"):
    for item in parsed["buddies"]:
      folder.buddies.add(item.getStr())
  cfg.addFolder(folder)
  (200, %*{"ok": true})

proc removeFolderByName(name: string): tuple[status: int, response: JsonNode] =
  var cfg = config.loadConfig()
  if not cfg.removeFolder(name):
    return (404, %*{"error": "Folder not found", "code": "FOLDER_NOT_FOUND"})
  (200, %*{"ok": true})

proc removeBuddyById(uuid: string): tuple[status: int, response: JsonNode] =
  var cfg = config.loadConfig()
  if not cfg.removeBuddy(uuid):
    return (404, %*{"error": "Buddy not found", "code": "BUDDY_NOT_FOUND"})
  (200, %*{"ok": true})

proc updateConfigFromBody(body: string): tuple[status: int, response: JsonNode] =
  let parsed = parseJson(body)
  var cfg = config.loadConfig()
  
  if parsed.hasKey("buddy"):
    let buddy = parsed["buddy"]
    if buddy.hasKey("name"):
      cfg.buddy.name = buddy["name"].getStr(cfg.buddy.name)
  
  if parsed.hasKey("network"):
    let net = parsed["network"]
    if net.hasKey("listen_port"):
      cfg.listenPort = net["listen_port"].getInt(cfg.listenPort)
    if net.hasKey("announce_addr"):
      cfg.announceAddr = net["announce_addr"].getStr(cfg.announceAddr)
    if net.hasKey("relay_base_url"):
      cfg.relayBaseUrl = net["relay_base_url"].getStr(cfg.relayBaseUrl)
    if net.hasKey("relay_region"):
      cfg.relayRegion = net["relay_region"].getStr(cfg.relayRegion)
    if net.hasKey("sync_window_start"):
      cfg.syncWindowStart = net["sync_window_start"].getStr(cfg.syncWindowStart)
    if net.hasKey("sync_window_end"):
      cfg.syncWindowEnd = net["sync_window_end"].getStr(cfg.syncWindowEnd)
  
  config.saveConfig(cfg)
  (200, %*{"ok": true})

proc pairBuddyFromBody(body: string): tuple[status: int, response: JsonNode] =
  let parsed = parseJson(body)
  let buddyId = parsed{"buddyId"}.getStr("")
  let buddyName = parsed{"buddyName"}.getStr("")
  let code = parsed{"code"}.getStr("")
  
  if buddyId.len == 0 or code.len == 0:
    return (400, %*{"error": "buddyId and code are required", "code": "INVALID_REQUEST"})
  
  var cfg = config.loadConfig()
  var buddy: BuddyInfo
  buddy.id = newBuddyId(buddyId, buddyName)
  buddy.addedAt = getTime()
  cfg.addBuddy(buddy)
  (200, %*{"ok": true, "message": "Buddy paired successfully"})

proc handleRequest(raw: string): string =
  let req = parseRequest(raw)
  try:
    case req.httpMethod
    of "GET":
      case req.path
      of "/status": jsonResponse(200, statusJson())
      of "/buddies": jsonResponse(200, buddiesJson())
      of "/folders": jsonResponse(200, foldersJson())
      of "/config": jsonResponse(200, configJson())
      of "/logs": jsonResponse(200, logsJson())
      else: jsonResponse(404, %*{"error": "Not found", "code": "NOT_FOUND"})
    of "POST":
      case req.path
      of "/buddies/pairing-code": jsonResponse(200, pairingCodeJson())
      of "/buddies/pair":
        let resp = pairBuddyFromBody(req.body)
        jsonResponse(resp.status, resp.response)
      of "/config":
        let resp = updateConfigFromBody(req.body)
        jsonResponse(resp.status, resp.response)
      of "/config/reload":
        discard config.loadConfig()
        jsonResponse(200, %*{"ok": true})
      of "/folders":
        let resp = addFolderFromBody(req.body)
        jsonResponse(resp.status, resp.response)
      else:
        if req.path.startsWith("/sync/"):
          jsonResponse(200, %*{"ok": true, "message": "Sync started", "folder": req.path[6 .. ^1]})
        else:
          jsonResponse(404, %*{"error": "Not found", "code": "NOT_FOUND"})
    of "DELETE":
      if req.path.startsWith("/folders/"):
        let resp = removeFolderByName(req.path[9 .. ^1])
        jsonResponse(resp.status, resp.response)
      elif req.path.startsWith("/buddies/"):
        let resp = removeBuddyById(req.path[9 .. ^1])
        jsonResponse(resp.status, resp.response)
      else:
        jsonResponse(404, %*{"error": "Not found", "code": "NOT_FOUND"})
    else:
      jsonResponse(400, %*{"error": "Unsupported method", "code": "BAD_METHOD"})
  except CatchableError as e:
    jsonResponse(500, %*{"error": e.msg, "code": "INTERNAL_ERROR"})

proc controlServerMain(port: int) {.thread.} =
  let socket = newSocket(buffered = false)
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(port), "127.0.0.1")
  socket.listen()
  echo "Control server started on port ", port
  while true:
    var client: owned(Socket)
    socket.accept(client)
    try:
      let raw = client.recv(64 * 1024)
      if raw.len > 0:
        let response = block:
          {.cast(gcsafe).}:
            handleRequest(raw)
        client.send(response)
    except CatchableError:
      discard
    finally:
      client.close()

proc startControlServer*(port: int = DefaultControlPort) =
  if controlStarted:
    return
  config.ensureConfigDir()
  writeFile(config.getConfigDir() / "port", $port)
  controlStarted = true
  createThread(controlThread, controlServerMain, port)

proc stopControlServer*() =
  markControlStopped()
  let portPath = config.getConfigDir() / "port"
  if fileExists(portPath):
    removeFile(portPath)
