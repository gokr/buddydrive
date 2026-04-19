import std/os
import std/times
import std/strutils
import std/sequtils
import parsetoml
import types
import logutils

export newAppConfig
export newBuddyId

const CONFIG_DIR* = ".buddydrive"
const CONFIG_FILE* = "config.toml"
const STATE_FILE* = "state.db"
const INDEX_FILE* = "index.db"
const LOG_FILE* = "buddydrive.log"

proc getConfigDir*(): string =
  result = getEnv("BUDDYDRIVE_CONFIG_DIR")
  if result.len == 0:
    result = getHomeDir() / CONFIG_DIR

proc getDataDir*(): string =
  result = getEnv("BUDDYDRIVE_DATA_DIR")
  if result.len == 0:
    result = getConfigDir()

proc getConfigPath*(): string =
  result = getConfigDir() / CONFIG_FILE

proc getStatePath*(): string =
  result = getDataDir() / STATE_FILE

proc getIndexPath*(): string =
  result = getDataDir() / INDEX_FILE

proc getLogPath*(): string =
  result = getDataDir() / LOG_FILE

proc ensureConfigDir*() =
  let dir = getConfigDir()
  if not dir.dirExists():
    createDir(dir)

proc ensureDataDir*() =
  let dir = getDataDir()
  if not dir.dirExists():
    createDir(dir)

proc escapeToml*(s: string): string =
  result = s.replace("\\", "\\\\")
  result = result.replace("\"", "\\\"")
  result = result.replace("\n", "\\n")
  result = result.replace("\r", "\\r")
  result = result.replace("\t", "\\t")

proc configToToml*(config: AppConfig, includeHeader = false): string =
  if includeHeader:
    result.add("# BuddyDrive Configuration\n")
    result.add("# Generated: " & now().format("yyyy-MM-dd HH:mm:ss") & "\n\n")

  result.add("[buddy]\n")
  result.add("name = \"" & escapeToml(config.buddy.name) & "\"\n")
  result.add("id = \"" & escapeToml(config.buddy.uuid) & "\"\n\n")

  if config.recovery.enabled:
    result.add("[recovery]\n")
    result.add("enabled = true\n")
    result.add("public_key = \"" & escapeToml(config.recovery.publicKeyB58) & "\"\n")
    result.add("master_key = \"" & escapeToml(config.recovery.masterKey) & "\"\n\n")

  result.add("[network]\n")
  result.add("listen_port = " & $config.listenPort & "\n")
  result.add("announce_addr = \"" & escapeToml(config.announceAddr) & "\"\n")
  result.add("relay_base_url = \"" & escapeToml(config.relayBaseUrl) & "\"\n")
  result.add("relay_region = \"" & escapeToml(config.relayRegion) & "\"\n")
  result.add("sync_window_start = \"" & escapeToml(config.syncWindowStart) & "\"\n")
  result.add("sync_window_end = \"" & escapeToml(config.syncWindowEnd) & "\"\n")
  result.add("bandwidth_limit_kbps = " & $config.bandwidthLimitKBps & "\n\n")

  if config.folders.len > 0:
    result.add("[[folders]]\n")
    for i, folder in config.folders:
      if i > 0:
        result.add("\n[[folders]]\n")
      if folder.id.len > 0:
        result.add("id = \"" & escapeToml(folder.id) & "\"\n")
      result.add("name = \"" & escapeToml(folder.name) & "\"\n")
      result.add("path = \"" & escapeToml(folder.path) & "\"\n")
      result.add("encrypted = " & $folder.encrypted & "\n")
      result.add("append_only = " & $folder.appendOnly & "\n")
      if folder.folderKey.len > 0:
        result.add("folder_key = \"" & escapeToml(folder.folderKey) & "\"\n")
      if folder.buddies.len > 0:
        result.add("buddies = [")
        for j, buddy in folder.buddies:
          if j > 0:
            result.add(", ")
          result.add("\"" & escapeToml(buddy) & "\"")
        result.add("]\n")

  if config.buddies.len > 0:
    result.add("\n[[buddies]]\n")
    for i, buddy in config.buddies:
      if i > 0:
        result.add("\n[[buddies]]\n")
      result.add("id = \"" & escapeToml(buddy.id.uuid) & "\"\n")
      result.add("name = \"" & escapeToml(buddy.id.name) & "\"\n")
      result.add("pairing_code = \"" & escapeToml(buddy.pairingCode) & "\"\n")
      if buddy.syncTime.len > 0:
        result.add("sync_time = \"" & escapeToml(buddy.syncTime) & "\"\n")
      result.add("added_at = \"" & buddy.addedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'") & "\"\n")

proc parseConfigToml*(toml: TomlValueRef): AppConfig =
  result.buddy.uuid = toml["buddy"]["id"].getStr()
  result.buddy.name = toml["buddy"]["name"].getStr("")
  result.recovery.enabled = false
  result.recovery.publicKeyB58 = ""
  result.recovery.masterKey = ""
  result.listenPort = DefaultP2PPort
  result.announceAddr = ""
  result.relayBaseUrl = ""
  result.relayRegion = ""
  result.syncWindowStart = ""
  result.syncWindowEnd = ""
  result.bandwidthLimitKBps = 0

  if "recovery" in toml:
    result.recovery.enabled = toml["recovery"]{"enabled"}.getBool(false)
    result.recovery.publicKeyB58 = toml["recovery"]{"public_key"}.getStr("")
    result.recovery.masterKey = toml["recovery"]{"master_key"}.getStr("")

  if "network" in toml:
    result.listenPort = toml["network"]{"listen_port"}.getInt(DefaultP2PPort)
    result.announceAddr = toml["network"]{"announce_addr"}.getStr("")
    result.relayBaseUrl = toml["network"]{"relay_base_url"}.getStr("")
    result.relayRegion = toml["network"]{"relay_region"}.getStr("")
    result.syncWindowStart = toml["network"]{"sync_window_start"}.getStr("")
    result.syncWindowEnd = toml["network"]{"sync_window_end"}.getStr("")
    result.bandwidthLimitKBps = toml["network"]{"bandwidth_limit_kbps"}.getInt(0)

  result.folders = @[]
  if "folders" in toml:
    for folderTbl in toml["folders"].getElems():
      var folder: FolderConfig
      folder.id = folderTbl{"id"}.getStr("")
      folder.name = folderTbl["name"].getStr()
      folder.path = folderTbl["path"].getStr()
      folder.encrypted = folderTbl{"encrypted"}.getBool(true)
      folder.appendOnly = folderTbl{"append_only"}.getBool(false)
      folder.folderKey = folderTbl{"folder_key"}.getStr("")
      folder.buddies = @[]
      if "buddies" in folderTbl:
        for buddy in folderTbl["buddies"].getElems():
          folder.buddies.add(buddy.getStr())
      result.folders.add(folder)

  result.buddies = @[]
  if "buddies" in toml:
    for buddyTbl in toml["buddies"].getElems():
      var buddy: BuddyInfo
      buddy.id.uuid = buddyTbl["id"].getStr()
      buddy.id.name = buddyTbl{"name"}.getStr("")
      buddy.pairingCode = buddyTbl{"pairing_code"}.getStr("")
      buddy.syncTime = buddyTbl{"sync_time"}.getStr("")
      buddy.addedAt = parseTime(buddyTbl{"added_at"}.getStr("1970-01-01T00:00:00Z"), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
      result.buddies.add(buddy)

proc parseConfigString*(content: string): AppConfig =
  parseConfigToml(parseString(content))

proc loadConfig*(): AppConfig =
  let path = getConfigPath()
  if not fileExists(path):
    logError("Config file not found: " & path)
    raise newException(IOError, "Config file not found. Run 'buddydrive init' first.")

  result = parseConfigToml(parseFile(path))

proc saveConfig*(config: AppConfig) =
  ensureConfigDir()
  let path = getConfigPath()
  let tempPath = path & ".tmp"
  let content = configToToml(config, includeHeader = true)
  writeFile(tempPath, content)
  moveFile(tempPath, path)
  logInfo("Config saved to: " & path)

proc initConfig*(name: string, uuid: string): AppConfig =
  ensureConfigDir()
  result = newAppConfig(newBuddyId(uuid, name))
  saveConfig(result)
  logInfo("Initialized config at: " & getConfigPath())

proc configExists*(): bool =
  result = fileExists(getConfigPath())

proc addFolder*(config: var AppConfig, folder: FolderConfig) =
  config.folders.add(folder)
  saveConfig(config)

proc removeFolder*(config: var AppConfig, name: string): bool =
  let idx = config.folders.mapIt(it.name).find(name)
  if idx >= 0:
    config.folders.delete(idx)
    saveConfig(config)
    result = true
  else:
    result = false

proc addBuddy*(config: var AppConfig, buddy: BuddyInfo) =
  let idx = config.buddies.mapIt(it.id.uuid).find(buddy.id.uuid)
  if idx >= 0:
    config.buddies[idx] = buddy
  else:
    config.buddies.add(buddy)
  saveConfig(config)

proc removeBuddy*(config: var AppConfig, uuid: string): bool =
  let idx = config.buddies.mapIt(it.id.uuid).find(uuid)
  if idx >= 0:
    config.buddies.delete(idx)
    for i in 0..<config.folders.len:
      config.folders[i].buddies = config.folders[i].buddies.filterIt(it != uuid)
    saveConfig(config)
    result = true
  else:
    result = false

proc getFolder*(config: AppConfig, name: string): int =
  for i, folder in config.folders:
    if folder.name == name:
      return i
  return -1

proc getBuddy*(config: AppConfig, uuid: string): int =
  for i, buddy in config.buddies:
    if buddy.id.uuid == uuid:
      return i
  return -1
