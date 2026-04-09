import std/os
import std/times
import std/sequtils
import parsetoml
import types
import logutils

const CONFIG_DIR* = ".buddydrive"
const CONFIG_FILE* = "config.toml"
const INDEX_FILE* = "index.db"
const LOG_FILE* = "buddydrive.log"

proc getConfigDir*(): string =
  result = getHomeDir() / CONFIG_DIR

proc getConfigPath*(): string =
  result = getConfigDir() / CONFIG_FILE

proc getIndexPath*(): string =
  result = getConfigDir() / INDEX_FILE

proc getLogPath*(): string =
  result = getConfigDir() / LOG_FILE

proc ensureConfigDir*() =
  let dir = getConfigDir()
  if not dir.dirExists():
    createDir(dir)

proc loadConfig*(): AppConfig =
  let path = getConfigPath()
  if not fileExists(path):
    logError("Config file not found: " & path)
    raise newException(IOError, "Config file not found. Run 'buddydrive init' first.")
  
  let toml = parseFile(path)
  
  result.buddy.uuid = toml["buddy"]["id"].getStr()
  result.buddy.name = toml["buddy"]["name"].getStr("")
  
  result.folders = @[]
  if "folders" in toml:
    for folderTbl in toml["folders"].getElems():
      var folder: FolderConfig
      folder.name = folderTbl["name"].getStr()
      folder.path = folderTbl["path"].getStr()
      folder.encrypted = folderTbl{"encrypted"}.getBool(true)
      folder.buddies = @[]
      if "buddies" in folderTbl:
        for buddy in folderTbl["buddies"].getElems():
          folder.buddies.add(buddy.getStr())
      result.folders.add(folder)
  
  result.buddies = @[]
  if "buddies" in toml:
    for buddyTbl in toml["buddies"].getElems():
      var buddy: PeerInfo
      buddy.id.uuid = buddyTbl["id"].getStr()
      buddy.id.name = buddyTbl{"name"}.getStr("")
      buddy.publicKey = buddyTbl{"public_key"}.getStr("")
      buddy.addedAt = parseTime(buddyTbl{"added_at"}.getStr("1970-01-01T00:00:00Z"), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
      result.buddies.add(buddy)

proc saveConfig*(config: AppConfig) =
  ensureConfigDir()
  let path = getConfigPath()
  let tempPath = path & ".tmp"
  
  var content = ""
  
  content.add("# BuddyDrive Configuration\n")
  content.add("# Generated: " & now().format("yyyy-MM-dd HH:mm:ss") & "\n\n")
  
  content.add("[buddy]\n")
  content.add("name = \"" & config.buddy.name & "\"\n")
  content.add("id = \"" & config.buddy.uuid & "\"\n")
  content.add("public_key = \"\"\n\n")
  
  if config.folders.len > 0:
    content.add("[[folders]]\n")
    for i, folder in config.folders:
      if i > 0:
        content.add("\n[[folders]]\n")
      content.add("name = \"" & folder.name & "\"\n")
      content.add("path = \"" & folder.path & "\"\n")
      content.add("encrypted = " & $folder.encrypted & "\n")
      if folder.buddies.len > 0:
        content.add("buddies = [")
        for j, buddy in folder.buddies:
          if j > 0:
            content.add(", ")
          content.add("\"" & buddy & "\"")
        content.add("]\n")
  
  if config.buddies.len > 0:
    content.add("\n[[buddies]]\n")
    for i, buddy in config.buddies:
      if i > 0:
        content.add("\n[[buddies]]\n")
      content.add("id = \"" & buddy.id.uuid & "\"\n")
      content.add("name = \"" & buddy.id.name & "\"\n")
      content.add("public_key = \"" & buddy.publicKey & "\"\n")
      content.add("added_at = \"" & buddy.addedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'") & "\"\n")
  
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

proc addBuddy*(config: var AppConfig, buddy: PeerInfo) =
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
