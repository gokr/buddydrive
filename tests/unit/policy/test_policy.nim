import std/unittest
import std/times
import ../../../src/buddydrive/types
import ../../../src/buddydrive/sync/policy
import ../../../src/buddydrive/crypto

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

suite "syncTimeDescription":
  test "always when sync time empty":
    check syncTimeDescription("") == "always"

  test "shows time when set":
    check syncTimeDescription("03:00") == "03:00"

suite "isWithinSyncTime":
  test "always within when sync time empty":
    check isWithinSyncTime("")

  test "within 15 minute window around target":
    check isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 2, 45, 0, 0, local()))
    check isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 3, 15, 0, 0, local()))
    check not isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 3, 16, 0, 0, local()))

  test "window wraps midnight":
    check isWithinSyncTime("00:05", dateTime(2026, mApr, 10, 23, 55, 0, 0, local()))
    check isWithinSyncTime("23:55", dateTime(2026, mApr, 11, 0, 5, 0, 0, local()))

  test "invalid sync time falls through to true":
    check isWithinSyncTime("bad")

suite "shouldAttemptBuddySync":
  test "empty sync time means always":
    var buddy: BuddyInfo
    check shouldAttemptBuddySync(buddy)

  test "buddy sync time uses scheduled window":
    var buddy: BuddyInfo
    buddy.syncTime = "03:00"
    check shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 3, 5, 0, 0, local()))
    check not shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 4, 0, 0, 0, local()))

suite "shouldSyncRemoteFile":
  test "new file always synced":
    var folder = newFolderConfig("docs", "/tmp/docs")
    var remote: FileInfo
    remote.path = "new.txt"
    remote.encryptedPath = "new.txt"
    check shouldSyncRemoteFile(folder, remote, false)

  test "different hash triggers sync even with same mtime/size":
    discard initCrypto()
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = false
    var local: FileInfo
    local.path = "existing.txt"
    local.encryptedPath = "existing.txt"
    local.size = 50
    local.mtime = 100
    for i in 0..<32: local.hash[i] = byte(i)
    var remote: FileInfo
    remote.path = "existing.txt"
    remote.encryptedPath = "existing.txt"
    remote.size = 50
    remote.mtime = 100
    for i in 0..<32: remote.hash[i] = byte(i + 1)
    check shouldSyncRemoteFile(folder, remote, true, local)

  test "same mtime/size and hash not synced":
    discard initCrypto()
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = false
    var local: FileInfo
    local.path = "file.txt"
    local.encryptedPath = "file.txt"
    local.size = 50
    local.mtime = 100
    for i in 0..<32: local.hash[i] = byte(i)
    var remote: FileInfo
    remote.path = "file.txt"
    remote.encryptedPath = "file.txt"
    remote.size = 50
    remote.mtime = 100
    remote.hash = local.hash
    check not shouldSyncRemoteFile(folder, remote, true, local)

  test "different mtime triggers sync via quick check":
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
    remote.mtime = 200
    check shouldSyncRemoteFile(folder, remote, true, local)

  test "different size triggers sync via quick check":
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

  test "append-only preserves existing local file even with different hash":
    discard initCrypto()
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = true
    var local: FileInfo
    local.path = "existing.txt"
    local.encryptedPath = "existing.txt"
    for i in 0..<32: local.hash[i] = byte(i)
    var remote: FileInfo
    remote.path = "existing.txt"
    remote.encryptedPath = "existing.txt"
    for i in 0..<32: remote.hash[i] = byte(i + 1)
    check not shouldSyncRemoteFile(folder, remote, true, local)

  test "append-only still syncs new files":
    var folder = newFolderConfig("docs", "/tmp/docs")
    folder.appendOnly = true
    var remote: FileInfo
    remote.path = "new.txt"
    remote.encryptedPath = "new.txt"
    check shouldSyncRemoteFile(folder, remote, false)

  test "metadata difference triggers sync":
    var folder = newFolderConfig("docs", "/tmp/docs")
    var local: FileInfo
    local.path = "file.txt"
    local.encryptedPath = "file.txt"
    local.size = 10
    local.mtime = 100
    local.mode = 0o644
    var remote: FileInfo
    remote.path = "file.txt"
    remote.encryptedPath = "file.txt"
    remote.size = 10
    remote.mtime = 100
    remote.mode = 0o755
    check shouldSyncRemoteFile(folder, remote, true, local)
