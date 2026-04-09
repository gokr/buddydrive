import std/logging
import std/os

var logFile*: File = nil
var logPath*: string = ""

proc setupLogging*(level = lvlInfo, path: string = "") =
  var handlers: seq[Logger] = @[]
  
  handlers.add(newConsoleLogger(level, fmtStr = "$levelname: $message"))
  
  if path.len > 0:
    logPath = path
    createDir(parentDir(path))
    logFile = open(path, fmAppend)
    handlers.add(newFileLogger(logFile, level, fmtStr = "$levelname [$datetime]: $message"))
  
  for h in handlers:
    addHandler(h)
  
  setLogFilter(level)

proc closeLogging*() =
  if logFile != nil:
    logFile.close()
    logFile = nil

proc logInfo*(msg: string) =
  info(msg)

proc logError*(msg: string) =
  error(msg)

proc logDebug*(msg: string) =
  debug(msg)

proc logWarn*(msg: string) =
  warn(msg)
