import std/os
import std/strutils
import std/parseopt
import std/random
import std/times
import std/sequtils
import uuids
import chronos
import libp2p/multiaddress
import types
import config
import daemon
import control
import sync/policy

proc generateBuddyName*(): string
proc generateUuid*(): string
proc generatePairingCode*(): string

type
  CommandKind* = enum
    cmdNone
    cmdInit
    cmdConfig
    cmdAddFolder
    cmdRemoveFolder
    cmdListFolders
    cmdAddBuddy
    cmdRemoveBuddy
    cmdListBuddies
    cmdConnect
    cmdStart
    cmdStop
    cmdStatus
    cmdLogs
    cmdHelp
  
  CommandLine* = object
    command*: CommandKind
    folderPath*: string
    folderName*: string
    folderEncrypted*: bool
    folderAppendOnly*: bool
    buddyId*: string
    configAction*: string
    configKey*: string
    configTarget*: string
    configValue*: string
    pairingCode*: string
    peerAddr*: string
    generateCode*: bool
    daemon*: bool
    controlPort*: int
    showHelp*: bool

proc printHelp*() =
  echo """
BuddyDrive - P2P Encrypted Folder Sync

Usage: buddydrive <command> [options]

Commands:
  init                      Initialize BuddyDrive (generate identity)
  config                    Show current configuration
  config set <key> ...      Update configuration values
  add-folder <path>         Add a folder to sync
    --name <name>           Folder name (required)
    --no-encrypt            Don't encrypt files
    --append-only           Only sync new files, never updates or deletions
    --buddy <id>            Add buddy to folder
  remove-folder <name>      Remove a folder
  list-folders              List configured folders
  add-buddy                 Pair with a buddy
    --generate-code         Generate a pairing code
    --id <buddy-id>         Buddy ID to pair with
    --code <code>           Pairing code from buddy
  remove-buddy <id>         Remove a buddy
  list-buddies              List paired buddies
  connect <address>         Connect to a buddy manually
                            Address format: /ip4/127.0.0.1/tcp/PORT
  start                     Start sync daemon
    --daemon                Run in background
  stop                      Stop sync daemon
  status                    Show sync status
  logs                      Show recent logs
  help                      Show this help

Examples:
  buddydrive init
  buddydrive config set relay-base-url https://buddydrive.net/relays
  buddydrive config set relay-region eu
  buddydrive config set sync-window 01:00-06:00
  buddydrive config set buddy-relay-token abc123 swift-eagle
  buddydrive config set folder-append-only docs on
  buddydrive add-folder ~/Documents --name docs
  buddydrive add-buddy --generate-code
  buddydrive add-buddy --id abc123 --code XYZ789
  buddydrive connect /ip4/127.0.0.1/tcp/12345
  buddydrive start
  buddydrive status
"""

proc parseCli*(): CommandLine =
  var p = initOptParser()
  result = CommandLine(
    command: cmdNone,
    folderEncrypted: true,
    folderAppendOnly: false,
    configAction: "",
    configKey: "",
    configTarget: "",
    configValue: "",
    generateCode: false,
    daemon: false,
    controlPort: DefaultControlPort,
    showHelp: false
  )
  
  var args: seq[string] = @[]
  var pendingValue: string = ""
  
  for kind, key, val in p.getopt():
    if pendingValue.len > 0:
      case pendingValue
      of "name":
        result.folderName = key
      of "buddy", "id":
        result.buddyId = key
      of "code":
        result.pairingCode = key
      pendingValue = ""
      continue
    
    case kind
    of cmdArgument:
      args.add(key)
    of cmdLongOption, cmdShortOption:
      case key.toLower()
      of "name":
        if val.len > 0:
          result.folderName = val
        else:
          pendingValue = "name"
      of "no-encrypt":
        result.folderEncrypted = false
      of "append-only":
        result.folderAppendOnly = true
      of "buddy":
        if val.len > 0:
          result.buddyId = val
        else:
          pendingValue = "buddy"
      of "id":
        if val.len > 0:
          result.buddyId = val
        else:
          pendingValue = "id"
      of "code":
        if val.len > 0:
          result.pairingCode = val
        else:
          pendingValue = "code"
      of "generate-code":
        result.generateCode = true
      of "port", "p":
        if val.len > 0:
          result.controlPort = parseInt(val)
      of "daemon", "d":
        result.daemon = true
      of "help", "h":
        result.showHelp = true
      else:
        echo "Unknown option: ", key
        result.showHelp = true
    of cmdEnd:
      discard
  
  if result.showHelp or args.len == 0:
    result.command = cmdHelp
    return
  
  let cmd = args[0].toLower()
  result.command = case cmd
    of "init": cmdInit
    of "config": cmdConfig
    of "add-folder": cmdAddFolder
    of "remove-folder": cmdRemoveFolder
    of "list-folders": cmdListFolders
    of "add-buddy": cmdAddBuddy
    of "remove-buddy": cmdRemoveBuddy
    of "list-buddies": cmdListBuddies
    of "connect": cmdConnect
    of "start": cmdStart
    of "stop": cmdStop
    of "status": cmdStatus
    of "logs": cmdLogs
    of "help": cmdHelp
    else: cmdHelp
  
  if args.len > 1:
    case result.command
    of cmdConfig:
      result.configAction = args[1].toLowerAscii()
      if result.configAction == "set":
        if args.len >= 4:
          result.configKey = args[2].toLowerAscii()
          case result.configKey
          of "relay-base-url", "relay_base_url", "relay-region", "relay_region", "sync-window", "sync_window":
            result.configValue = args[3]
          of "buddy-relay-token", "buddy_relay_token", "buddy-name", "buddy_name", "folder-append-only", "folder_append_only":
            if args.len >= 5:
              result.configTarget = args[3]
              result.configValue = args[4]
            else:
              result.showHelp = true
          else:
            result.showHelp = true
        else:
          result.showHelp = true
    of cmdAddFolder:
      result.folderPath = args[1]
    of cmdRemoveFolder:
      result.folderName = args[1]
    of cmdRemoveBuddy:
      result.buddyId = args[1]
    of cmdConnect:
      result.peerAddr = args[1]
    else:
      discard

  if result.showHelp:
    result.command = cmdHelp

proc handleInit*() =
  var configExists = config.configExists()
  if configExists:
    echo "Config already exists at: ", config.getConfigPath()
    echo "Use 'buddydrive config' to view, or delete to reinitialize."
    return
  
  echo "Initializing BuddyDrive..."
  
  let name = generateBuddyName()
  let uuid = generateUuid()
  
  discard initConfig(name, uuid)
  
  echo ""
  echo "Generated buddy name: ", name
  echo "Buddy ID: ", uuid
  echo ""
  echo "Config created at: ", config.getConfigPath()
  echo ""
  echo "Network defaults:"
  echo "  Listen port: 41721"
  echo "  Announce addr: (set [network].announce_addr after forwarding this port on your router)"
  echo "  Relay base URL: (set with 'buddydrive config set relay-base-url <url>')"
  echo "  Relay region: (set with 'buddydrive config set relay-region <region>')"
  echo "  Sync window: always (set with 'buddydrive config set sync-window HH:MM-HH:MM')"
  echo ""
  echo "Next steps:"
  echo "  1. Add a folder: buddydrive add-folder <path> --name <name>"
  echo "  2. Pair with a buddy: buddydrive add-buddy --generate-code"
  echo "  3. Start syncing: buddydrive start"

proc handleConfig*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return

  if cmd.configAction == "set":
    var cfg = loadConfig()

    case cmd.configKey
    of "relay-base-url", "relay_base_url":
      cfg.relayBaseUrl = cmd.configValue
      saveConfig(cfg)
      echo "Relay base URL set to: ", cfg.relayBaseUrl
      return
    of "relay-region", "relay_region":
      cfg.relayRegion = cmd.configValue.toLowerAscii()
      saveConfig(cfg)
      echo "Relay region set to: ", cfg.relayRegion
      return
    of "sync-window", "sync_window":
      if cmd.configValue.toLowerAscii() == "off":
        cfg.syncWindowStart = ""
        cfg.syncWindowEnd = ""
      else:
        let parts = cmd.configValue.split("-", maxsplit = 1)
        if parts.len != 2 or parseClockMinutes(parts[0]) < 0 or parseClockMinutes(parts[1]) < 0:
          echo "Invalid sync window. Use HH:MM-HH:MM or 'off'."
          return
        cfg.syncWindowStart = parts[0]
        cfg.syncWindowEnd = parts[1]
      saveConfig(cfg)
      echo "Sync window set to: ", syncWindowDescription(cfg)
      return
    of "buddy-relay-token", "buddy_relay_token":
      let idx = cfg.getBuddy(cmd.configTarget)
      if idx < 0:
        echo "Buddy not found: ", cmd.configTarget.shortId()
        return
      cfg.buddies[idx].relayToken = cmd.configValue
      saveConfig(cfg)
      echo "Relay token set for buddy: ", cfg.buddies[idx].id.uuid.shortId()
      return
    of "buddy-name", "buddy_name":
      let idx = cfg.getBuddy(cmd.configTarget)
      if idx < 0:
        echo "Buddy not found: ", cmd.configTarget.shortId()
        return
      cfg.buddies[idx].id.name = cmd.configValue
      saveConfig(cfg)
      echo "Buddy name set to: ", cfg.buddies[idx].id.name
      return
    of "folder-append-only", "folder_append_only":
      let idx = cfg.getFolder(cmd.configTarget)
      if idx < 0:
        echo "Folder not found: ", cmd.configTarget
        return
      let normalized = cmd.configValue.toLowerAscii()
      if normalized in ["on", "true", "yes", "1"]:
        cfg.folders[idx].appendOnly = true
      elif normalized in ["off", "false", "no", "0"]:
        cfg.folders[idx].appendOnly = false
      else:
        echo "Invalid append-only value. Use on/off."
        return
      saveConfig(cfg)
      echo "Append-only for folder '", cfg.folders[idx].name, "' set to: ", cfg.folders[idx].appendOnly
      return
    else:
      echo "Unknown config key: ", cmd.configKey
      echo "Supported keys: relay-base-url, relay-region, sync-window, buddy-relay-token, buddy-name, folder-append-only"
      return

  let cfg = loadConfig()
  
  echo "Buddy: ", cfg.buddy.name
  echo "  ID: ", cfg.buddy.uuid
  echo "  Config: ", config.getConfigPath()
  echo "  Listen port: ", cfg.listenPort
  if cfg.announceAddr.len > 0:
    echo "  Announce addr: ", cfg.announceAddr
  else:
    echo "  Announce addr: (not set)"
  if cfg.relayBaseUrl.len > 0:
    echo "  Relay base URL: ", cfg.relayBaseUrl
  else:
    echo "  Relay base URL: (not set)"
  if cfg.relayRegion.len > 0:
    echo "  Relay region: ", cfg.relayRegion
  else:
    echo "  Relay region: (not set)"
  echo "  Sync window: ", syncWindowDescription(cfg)
  echo ""
  
  if cfg.folders.len > 0:
    echo "Folders:"
    for folder in cfg.folders:
      echo "  ", folder.name
      echo "    Path: ", folder.path
      echo "    Encrypted: ", folder.encrypted
      echo "    Append-only: ", folder.appendOnly
      if folder.buddies.len > 0:
        echo "    Buddies: ", folder.buddies.join(", ")
    echo ""
  
  if cfg.buddies.len > 0:
    echo "Buddies:"
    for buddy in cfg.buddies:
      echo "  ", buddy.id.name, " (", shortId(buddy.id.uuid), ")"
      echo "    ID: ", buddy.id.uuid
      if buddy.relayToken.len > 0:
        echo "    Relay token: ", buddy.relayToken
      echo "    Added: ", buddy.addedAt.format("yyyy-MM-dd HH:mm:ss")
  else:
    echo "No buddies paired yet."
    echo "Use 'buddydrive add-buddy --generate-code' to pair."

proc handleAddFolder*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  if cmd.folderPath.len == 0:
    echo "Error: Folder path required"
    echo "Usage: buddydrive add-folder <path> --name <name>"
    return
  
  if cmd.folderName.len == 0:
    echo "Error: Folder name required"
    echo "Usage: buddydrive add-folder <path> --name <name>"
    return
  
  let absPath = absolutePath(cmd.folderPath)
  if not dirExists(absPath):
    echo "Error: Directory does not exist: ", absPath
    return
  
  var cfg = loadConfig()
  
  if cfg.getFolder(cmd.folderName) >= 0:
    echo "Error: Folder name already exists: ", cmd.folderName
    return
  
  var folder = newFolderConfig(cmd.folderName, absPath, cmd.folderEncrypted)
  folder.appendOnly = cmd.folderAppendOnly
  
  if cmd.buddyId.len > 0:
    let buddyIdx = cfg.getBuddy(cmd.buddyId)
    if buddyIdx < 0:
      echo "Warning: Buddy not found: ", cmd.buddyId
    else:
      folder.buddies.add(cmd.buddyId)
  
  cfg.addFolder(folder)
  
  echo "Folder added: ", cmd.folderName
  echo "  Path: ", absPath
  echo "  Encrypted: ", cmd.folderEncrypted
  echo "  Append-only: ", folder.appendOnly
  if folder.buddies.len > 0:
    echo "  Buddies: ", folder.buddies.join(", ")

proc handleRemoveFolder*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  if cmd.folderName.len == 0:
    echo "Error: Folder name required"
    return
  
  var cfg = loadConfig()
  
  if cfg.removeFolder(cmd.folderName):
    echo "Folder removed: ", cmd.folderName
  else:
    echo "Folder not found: ", cmd.folderName

proc handleListFolders*() =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  let cfg = loadConfig()
  
  if cfg.folders.len == 0:
    echo "No folders configured."
    echo "Use 'buddydrive add-folder <path> --name <name>' to add one."
    return
  
  echo "Folders:"
  for folder in cfg.folders:
    echo "  ", folder.name
    echo "    Path: ", folder.path
    echo "    Encrypted: ", folder.encrypted
    echo "    Append-only: ", folder.appendOnly
    if folder.buddies.len > 0:
      echo "    Buddies: ", folder.buddies.join(", ")

proc handleAddBuddy*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  if cmd.generateCode:
    echo "Generating pairing code..."
    echo ""
    let code = generatePairingCode()
    let cfg = loadConfig()
    echo "Share this with your buddy:"
    echo "  Your Buddy ID: ", cfg.buddy.uuid
    echo "  Your Name: ", cfg.buddy.name
    echo "  Pairing Code: ", code
    echo ""
    echo "Your buddy should run:"
    echo "  buddydrive add-buddy --id ", cfg.buddy.uuid, " --code ", code
    return
  
  if cmd.buddyId.len == 0:
    echo "Error: Buddy ID required"
    echo "Usage: buddydrive add-buddy --id <buddy-id> --code <code>"
    return
  
  if cmd.pairingCode.len == 0:
    echo "Error: Pairing code required"
    echo "Usage: buddydrive add-buddy --id <buddy-id> --code <code>"
    return
  
  echo "Pairing with buddy: ", cmd.buddyId.shortId()
  echo "Pairing code: ", cmd.pairingCode
  echo ""
  
  var cfg = loadConfig()
  var buddy: BuddyInfo
  buddy.id.uuid = cmd.buddyId
  buddy.id.name = "unknown"
  buddy.publicKey = ""
  buddy.addedAt = getTime()
  
  cfg.addBuddy(buddy)
  
  echo "Buddy added: ", cmd.buddyId.shortId()
  echo "Note: P2P connection will be established when both sides start the daemon."
  echo "If using relay fallback, set a shared token with:"
  echo "  buddydrive config set buddy-relay-token ", cmd.buddyId, " <token>"

proc handleRemoveBuddy*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  if cmd.buddyId.len == 0:
    echo "Error: Buddy ID required"
    return
  
  var cfg = loadConfig()
  
  if cfg.removeBuddy(cmd.buddyId):
    echo "Buddy removed: ", cmd.buddyId.shortId()
  else:
    echo "Buddy not found: ", cmd.buddyId.shortId()

proc handleListBuddies*() =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  let cfg = loadConfig()
  
  if cfg.buddies.len == 0:
    echo "No buddies paired yet."
    echo "Use 'buddydrive add-buddy --generate-code' to pair."
    return
  
  echo "Buddies:"
  for buddy in cfg.buddies:
    echo "  ", buddy.id.name, " (", buddy.id.uuid.shortId(), ")"
    echo "    ID: ", buddy.id.uuid
    if buddy.relayToken.len > 0:
      echo "    Relay token: ", buddy.relayToken
    echo "    Added: ", buddy.addedAt.format("yyyy-MM-dd HH:mm:ss")

proc handleConnect*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  if cmd.peerAddr.len == 0:
    echo "Error: Peer address required"
    echo "Usage: buddydrive connect <peer-id> <address>"
    echo "Example: buddydrive connect 16Uiu2HAk... /ip4/127.0.0.1/tcp/12345"
    return
  
  echo "Note: Direct connection not yet implemented."
  echo "Use 'buddydrive start' to connect via DHT discovery."

proc handleStart*(cmd: CommandLine) =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  let cfg = loadConfig()
  let daemon = newDaemon(cfg)
  
  echo "Starting BuddyDrive daemon..."
  echo ""
  
  if cmd.daemon:
    echo "Background mode (daemonizing)..."
    echo ""
    echo "Note: Background daemon mode not fully implemented."
    echo "Running in foreground instead..."
    echo ""
  
  proc runDaemon() {.async.} =
    try:
      await daemon.start(cmd.controlPort)
      echo ""
      echo "BuddyDrive is running!"
      echo "Peer ID: ", daemon.node.peerIdStr()
      echo "Control API: http://127.0.0.1:", cmd.controlPort
      echo ""
      echo "Listening addresses:"
      for address in daemon.node.getAddrs():
        let addrStr = multiaddress.toString(address)
        if addrStr.isOk:
          echo "  ", addrStr.get()
        else:
          echo "  (invalid address)"
      echo ""
      echo "Advertised addresses:"
      for address in daemon.node.getAdvertisedAddrs():
        let addrStr = multiaddress.toString(address)
        if addrStr.isOk:
          echo "  ", addrStr.get()
        else:
          echo "  (invalid address)"
      echo ""
      echo "Folders:"
      for folder in cfg.folders:
        echo "  ", folder.name, " -> ", folder.path
      echo ""
      echo "Press Ctrl+C to stop..."
      
      while daemon.isRunning():
        await sleepAsync(chronos.seconds(1))
    except Exception as e:
      echo "Error: ", e.msg
    finally:
      await daemon.stop()
  
  waitFor runDaemon()

proc handleStop*() =
  echo "Stopping BuddyDrive daemon..."
  echo "Note: Daemon mode not implemented yet."

proc handleStatus*() =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  let cfg = loadConfig()
  
  echo "Buddy: ", cfg.buddy.name, " (", cfg.buddy.uuid.shortId(), ")"
  echo "Peer ID: ", "(run 'buddydrive start' to connect)"
  echo "Sync window: ", syncWindowDescription(cfg)
  echo ""
  
  if cfg.folders.len > 0:
    echo "Folders:"
    for folder in cfg.folders:
      echo "  ", folder.name
      echo "    Path: ", folder.path
      echo "    Encrypted: ", folder.encrypted
      echo "    Append-only: ", folder.appendOnly
      if folder.buddies.len > 0:
        echo "    Buddies: ", folder.buddies.mapIt(shortId(it)).join(", ")
  else:
    echo "No folders configured."
    echo "Use 'buddydrive add-folder <path> --name <name>' to add one."
  
  echo ""
  
  if cfg.buddies.len > 0:
    echo "Buddies:"
    for buddy in cfg.buddies:
      echo "  ", buddy.id.name, " (", buddy.id.uuid.shortId(), ")"
      echo "    Status: Offline"
      if buddy.relayToken.len > 0:
        echo "    Relay token: ", buddy.relayToken
      echo "    Added: ", buddy.addedAt.format("yyyy-MM-dd HH:mm:ss")
  else:
    echo "No buddies paired."
    echo "Use 'buddydrive add-buddy --generate-code' to pair."

proc handleLogs*() =
  let logPath = config.getLogPath()
  if not fileExists(logPath):
    echo "No log file found."
    return
  
  echo "Recent logs from: ", logPath
  echo "---"
  echo readFile(logPath)

proc generateBuddyName*(): string =
  let adjPath = currentSourcePath().parentDir().parentDir().parentDir() / "wordlists" / "adjectives.txt"
  let nounPath = currentSourcePath().parentDir().parentDir().parentDir() / "wordlists" / "nouns.txt"
  
  var adjectives: seq[string] = @[]
  var nouns: seq[string] = @[]
  
  if fileExists(adjPath):
    for line in lines(adjPath):
      if line.len > 0:
        adjectives.add(line.strip())
  
  if fileExists(nounPath):
    for line in lines(nounPath):
      if line.len > 0:
        nouns.add(line.strip())
  
  if adjectives.len == 0:
    adjectives = @["purple", "happy", "clever", "brave", "swift"]
  
  if nouns.len == 0:
    nouns = @["banana", "wrench", "dolphin", "falcon", "tiger"]
  
  randomize()
  let adj = adjectives[rand(adjectives.len - 1)]
  let noun = nouns[rand(nouns.len - 1)]
  
  result = adj & "-" & noun

proc generateUuid*(): string =
  let uuid = genUuid()
  result = $uuid

proc generatePairingCode*(): string =
  randomize()
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  result = ""
  for i in 0..3:
    result.add(chars[rand(chars.len - 1)])
  result.add("-")
  for i in 0..3:
    result.add(chars[rand(chars.len - 1)])
