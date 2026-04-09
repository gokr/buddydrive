import buddydrive/cli
import buddydrive/logutils
import buddydrive/config

when isMainModule:
  setupLogging(path = config.getLogPath())
  
  let cmd = parseCli()
  
  case cmd.command
  of cmdInit:
    handleInit()
  of cmdConfig:
    handleConfig()
  of cmdAddFolder:
    handleAddFolder(cmd)
  of cmdRemoveFolder:
    handleRemoveFolder(cmd)
  of cmdListFolders:
    handleListFolders()
  of cmdAddBuddy:
    handleAddBuddy(cmd)
  of cmdRemoveBuddy:
    handleRemoveBuddy(cmd)
  of cmdListBuddies:
    handleListBuddies()
  of cmdConnect:
    handleConnect(cmd)
  of cmdStart:
    handleStart(cmd)
  of cmdStop:
    handleStop()
  of cmdStatus:
    handleStatus()
  of cmdLogs:
    handleLogs()
  of cmdHelp, cmdNone:
    printHelp()
  
  closeLogging()
