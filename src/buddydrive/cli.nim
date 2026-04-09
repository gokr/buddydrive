import std/os
import std/strutils
import std/parseopt
import std/random
import std/times
import std/sequtils
import uuids
import chronos
import types
import config
import daemon

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
    buddyId*: string
    pairingCode*: string
    generateCode*: bool
    daemon*: bool
    showHelp*: bool

proc printHelp*() =
  echo """
BuddyDrive - P2P Encrypted Folder Sync

Usage: buddydrive <command> [options]

Commands:
  init                      Initialize BuddyDrive (generate identity)
  config                    Show current configuration
  add-folder <path>         Add a folder to sync
    --name <name>           Folder name (required)
    --no-encrypt            Don't encrypt files
    --buddy <id>            Add buddy to folder
  remove-folder <name>      Remove a folder
  list-folders              List configured folders
  add-buddy                 Pair with a buddy
    --generate-code         Generate a pairing code
    --id <buddy-id>         Buddy ID to pair with
    --code <code>           Pairing code from buddy
  remove-buddy <id>         Remove a buddy
  list-buddies              List paired buddies
  start                     Start sync daemon
    --daemon                Run in background
  stop                      Stop sync daemon
  status                    Show sync status
  logs                      Show recent logs
  help                      Show this help

Examples:
  buddydrive init
  buddydrive add-folder ~/Documents --name docs
  buddydrive add-buddy --generate-code
  buddydrive add-buddy --id abc123 --code XYZ789
  buddydrive start
  buddydrive status
"""

proc parseCli*(): CommandLine =
  var p = initOptParser()
  result = CommandLine(
    command: cmdNone,
    folderEncrypted: true,
    generateCode: false,
    daemon: false,
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
    of "start": cmdStart
    of "stop": cmdStop
    of "status": cmdStatus
    of "logs": cmdLogs
    of "help": cmdHelp
    else: cmdHelp
  
  if args.len > 1:
    case result.command
    of cmdAddFolder:
      result.folderPath = args[1]
    of cmdRemoveFolder:
      result.folderName = args[1]
    of cmdRemoveBuddy:
      result.buddyId = args[1]
    else:
      discard

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
  echo "Next steps:"
  echo "  1. Add a folder: buddydrive add-folder <path> --name <name>"
  echo "  2. Pair with a buddy: buddydrive add-buddy --generate-code"
  echo "  3. Start syncing: buddydrive start"

proc handleConfig*() =
  if not config.configExists():
    echo "No config found. Run 'buddydrive init' first."
    return
  
  let cfg = loadConfig()
  
  echo "Buddy: ", cfg.buddy.name
  echo "  ID: ", cfg.buddy.uuid
  echo "  Config: ", config.getConfigPath()
  echo ""
  
  if cfg.folders.len > 0:
    echo "Folders:"
    for folder in cfg.folders:
      echo "  ", folder.name
      echo "    Path: ", folder.path
      echo "    Encrypted: ", folder.encrypted
      if folder.buddies.len > 0:
        echo "    Buddies: ", folder.buddies.join(", ")
    echo ""
  
  if cfg.buddies.len > 0:
    echo "Buddies:"
    for buddy in cfg.buddies:
      echo "  ", buddy.id.name, " (", shortId(buddy.id.uuid), ")"
      echo "    ID: ", buddy.id.uuid
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
    echo "    Added: ", buddy.addedAt.format("yyyy-MM-dd HH:mm:ss")

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
      await daemon.start()
      echo ""
      echo "BuddyDrive is running!"
      echo "Peer ID: ", daemon.node.peerIdStr()
      echo ""
      echo "Listening addresses:"
      for address in daemon.node.getAddrs():
        echo "  ", $address
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
  echo ""
  
  if cfg.folders.len > 0:
    echo "Folders:"
    for folder in cfg.folders:
      echo "  ", folder.name
      echo "    Path: ", folder.path
      echo "    Encrypted: ", folder.encrypted
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
