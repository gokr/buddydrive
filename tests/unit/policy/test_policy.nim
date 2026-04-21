import std/unittest
import std/times
import ../../../src/buddydrive/types
import ../../../src/buddydrive/sync/policy

suite "parseClockMinutes":
  test "valid HH:MM":
    check parseClockMinutes("01:30") == 90
    check parseClockMinutes("00:00") == 0
    check parseClockMinutes("23:59") == 23 * 60 + 59
    check parseClockMinutes("12:00") == 720

  test "invalid format returns -1":
    check parseClockMinutes("invalid") == -1
    check parseClockMinutes("25:00") == -1
    check parseClockMinutes("12:60") == -1
    check parseClockMinutes("") == -1

suite "hasSyncWindow":
  test "no sync window set":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    check not hasSyncWindow(cfg)

  test "both start and end set":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "01:00"
    cfg.syncWindowEnd = "06:00"
    check hasSyncWindow(cfg)

  test "only start set":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "01:00"
    check not hasSyncWindow(cfg)

  test "only end set":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowEnd = "06:00"
    check not hasSyncWindow(cfg)

suite "syncWindowDescription":
  test "always when no window":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    check syncWindowDescription(cfg) == "always"

  test "shows range when window set":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "01:00"
    cfg.syncWindowEnd = "06:00"
    check syncWindowDescription(cfg) == "01:00-06:00"

suite "isWithinSyncWindow":
  test "always within when no window":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    check isWithinSyncWindow(cfg)

  test "normal daytime window":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "01:00"
    cfg.syncWindowEnd = "06:00"
    check not isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 0, 30, 0, 0, local()))
    check isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 1, 30, 0, 0, local()))
    check not isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 6, 30, 0, 0, local()))

  test "overnight window crossing midnight":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "22:00"
    cfg.syncWindowEnd = "03:00"
    check isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 22, 30, 0, 0, local()))
    check isWithinSyncWindow(cfg, dateTime(2026, mApr, 11, 1, 30, 0, 0, local()))
    check not isWithinSyncWindow(cfg, dateTime(2026, mApr, 11, 12, 0, 0, 0, local()))

  test "start equals end means always":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "12:00"
    cfg.syncWindowEnd = "12:00"
    check isWithinSyncWindow(cfg, dateTime(2026, mApr, 10, 12, 0, 0, 0, local()))

  test "invalid window format falls through to true":
    var cfg = newAppConfig(newBuddyId("uuid", "test"))
    cfg.syncWindowStart = "bad"
    cfg.syncWindowEnd = "06:00"
    check isWithinSyncWindow(cfg)

suite "shouldInitiateBuddySync":
  test "always when sync time is empty":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = ""
    check shouldInitiateBuddySync(buddy, dateTime(2026, mApr, 10, 12, 0, 0, 0, local()))

  test "within tolerance around scheduled time":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = "03:00"
    check shouldInitiateBuddySync(buddy, dateTime(2026, mApr, 10, 2, 50, 0, 0, local()))
    check shouldInitiateBuddySync(buddy, dateTime(2026, mApr, 10, 3, 10, 0, 0, local()))
    check not shouldInitiateBuddySync(buddy, dateTime(2026, mApr, 10, 3, 30, 0, 0, local()))

  test "invalid sync time falls through to always":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = "bad"
    check shouldInitiateBuddySync(buddy)

suite "shouldSyncRemoteFile":
  test "new file always synced":
    var folder = newFolderConfig("docs", "/tmp/docs")
    var remote: FileInfo
    remote.path = "new.txt"
    remote.encryptedPath = "new.txt"
    remote.size = 20
    remote.mtime = 200
    check shouldSyncRemoteFile(folder, remote, false)

  test "modified file synced when not append-only":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = false
    var local: FileInfo
    local.path = "existing.txt"
    local.encryptedPath = "existing.txt"
    local.size = 10
    local.mtime = 100
    var remote: FileInfo
    remote.path = "existing.txt"
    remote.encryptedPath = "existing.txt"
    remote.size = 99
    remote.mtime = 300
    check shouldSyncRemoteFile(folder, remote, true, local)

  test "append-only preserves existing local file":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = true
    var local: FileInfo
    local.path = "existing.txt"
    local.encryptedPath = "existing.txt"
    local.size = 10
    local.mtime = 100
    for i in 0..<32: local.hash[i] = byte(i)
    var remote: FileInfo
    remote.path = "existing.txt"
    remote.encryptedPath = "existing.txt"
    remote.size = 99
    remote.mtime = 300
    check not shouldSyncRemoteFile(folder, remote, true, local)

  test "append-only still syncs new files":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = true
    var remote: FileInfo
    remote.path = "new.txt"
    remote.encryptedPath = "new.txt"
    remote.size = 20
    remote.mtime = 200
    check shouldSyncRemoteFile(folder, remote, false)

  test "same mtime and size not synced":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = false
    var local: FileInfo
    local.path = "file.txt"
    local.encryptedPath = "file.txt"
    local.size = 50
    local.mtime = 100
    var remote: FileInfo
    remote.path = "file.txt"
    remote.encryptedPath = "file.txt"
    remote.size = 50
    remote.mtime = 100
    check not shouldSyncRemoteFile(folder, remote, true, local)

  test "different size triggers sync even with same mtime":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = false
    var local: FileInfo
    local.path = "file.txt"
    local.encryptedPath = "file.txt"
    local.size = 50
    local.mtime = 100
    var remote: FileInfo
    remote.path = "file.txt"
    remote.encryptedPath = "file.txt"
    remote.size = 100
    remote.mtime = 100
    check shouldSyncRemoteFile(folder, remote, true, local)
