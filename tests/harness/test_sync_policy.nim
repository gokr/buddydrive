import std/times
import ../../src/buddydrive/types
import ../../src/buddydrive/sync/policy

proc testSyncWindow() =
  var cfg = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "buddy"))

  doAssert syncWindowDescription(cfg) == "always"
  doAssert isWithinSyncWindow(cfg)

  cfg.syncWindowStart = "01:00"
  cfg.syncWindowEnd = "06:00"
  doAssert not isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 0, 30, 0, 0, local()))
  doAssert isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 1, 30, 0, 0, local()))
  doAssert not isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 6, 30, 0, 0, local()))

  cfg.syncWindowStart = "22:00"
  cfg.syncWindowEnd = "03:00"
  doAssert isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 22, 30, 0, 0, local()))
  doAssert isWithinSyncWindow(cfg, dateTime(2026, mApr, 11, 1, 30, 0, 0, local()))
  doAssert not isWithinSyncWindow(cfg, dateTime(2026, mApr, 11, 12, 0, 0, 0, local()))

proc testAppendOnly() =
  var folder = newFolderConfig("docs", "/tmp/docs")
  folder.appendOnly = true

  var localFile: FileInfo
  localFile.path = "existing.txt"
  localFile.encryptedPath = localFile.path
  localFile.size = 10
  localFile.mtime = 100

  var remoteNew: FileInfo
  remoteNew.path = "new.txt"
  remoteNew.encryptedPath = remoteNew.path
  remoteNew.size = 20
  remoteNew.mtime = 200

  var remoteUpdated: FileInfo
  remoteUpdated.path = "existing.txt"
  remoteUpdated.encryptedPath = remoteUpdated.path
  remoteUpdated.size = 99
  remoteUpdated.mtime = 300

  doAssert shouldSyncRemoteFile(folder, remoteNew, false)
  doAssert not shouldSyncRemoteFile(folder, remoteUpdated, true, localFile)

  folder.appendOnly = false
  doAssert shouldSyncRemoteFile(folder, remoteUpdated, true, localFile)

when isMainModule:
  testSyncWindow()
  testAppendOnly()
  echo "sync policy ok"
