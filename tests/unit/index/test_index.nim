import std/unittest
import std/[os, options]
import ../../../src/buddydrive/types
import ../../../src/buddydrive/sync/index
import ../../../src/buddydrive/config as buddyconfig
import ../../testutils

suite "FileIndex construction":
  test "newIndex creates index with table":
    withTestDir("idxcreate"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("test-folder")
      defer: idx.close()
      check idx.folderName == "test-folder"
      check idx.db != nil

suite "FileIndex add/get/remove":
  test "addFile and getFile round-trip":
    withTestDir("idxaddget"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f1")
      defer: idx.close()
      var info: types.FileInfo
      info.path = "doc.txt"
      info.encryptedPath = "doc.txt"
      info.size = 1024
      info.mtime = 1000
      for i in 0..<32: info.hash[i] = byte(i)
      idx.addFile(info)
      let retrieved = idx.getFile("doc.txt")
      check retrieved.isSome
      check retrieved.get().path == "doc.txt"
      check retrieved.get().size == 1024
      check retrieved.get().mtime == 1000

  test "getFile returns none for missing file":
    withTestDir("idxgetmiss"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f2")
      defer: idx.close()
      check idx.getFile("nonexistent.txt").isNone

  test "removeFile removes entry":
    withTestDir("idxremove"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f3")
      defer: idx.close()
      var info: types.FileInfo
      info.path = "to-remove.txt"
      info.encryptedPath = "to-remove.txt"
      info.size = 100
      info.mtime = 500
      idx.addFile(info)
      check idx.getFile("to-remove.txt").isSome
      idx.removeFile("to-remove.txt")
      check idx.getFile("to-remove.txt").isNone

  test "addFile updates existing entry":
    withTestDir("idxupdate"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f4")
      defer: idx.close()
      var info1: types.FileInfo
      info1.path = "update.txt"
      info1.encryptedPath = "update.txt"
      info1.size = 50
      info1.mtime = 100
      idx.addFile(info1)
      var info2: types.FileInfo
      info2.path = "update.txt"
      info2.encryptedPath = "update.txt"
      info2.size = 200
      info2.mtime = 300
      idx.addFile(info2)
      let retrieved = idx.getFile("update.txt")
      check retrieved.get().size == 200
      check retrieved.get().mtime == 300

suite "FileIndex getAllFiles":
  test "getAllFiles returns all files":
    withTestDir("idxgetall"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f5")
      defer: idx.close()
      for i in 0..<5:
        var info: types.FileInfo
        info.path = "file" & $i & ".txt"
        info.encryptedPath = info.path
        info.size = int64(i * 100)
        info.mtime = int64(i * 10)
        idx.addFile(info)
      let all = idx.getAllFiles()
      check all.len == 5

suite "FileIndex sync status":
  test "getUnsyncedFiles returns unsynced":
    withTestDir("idxunsynced"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f6")
      defer: idx.close()
      var info1: types.FileInfo
      info1.path = "synced.txt"
      info1.encryptedPath = "synced.txt"
      idx.addFile(info1, synced = true)
      var info2: types.FileInfo
      info2.path = "pending.txt"
      info2.encryptedPath = "pending.txt"
      idx.addFile(info2, synced = false)
      let unsynced = idx.getUnsyncedFiles()
      check unsynced.len == 1
      check unsynced[0].path == "pending.txt"

  test "markSynced marks single file":
    withTestDir("idxmarksynced"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f7")
      defer: idx.close()
      var info: types.FileInfo
      info.path = "tosync.txt"
      info.encryptedPath = "tosync.txt"
      idx.addFile(info, synced = false)
      check idx.getUnsyncedFiles().len == 1
      idx.markSynced("tosync.txt")
      check idx.getUnsyncedFiles().len == 0

  test "markAllSynced marks all files":
    withTestDir("idxmarkall"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f8")
      defer: idx.close()
      for i in 0..<3:
        var info: types.FileInfo
        info.path = "file" & $i & ".txt"
        info.encryptedPath = info.path
        idx.addFile(info, synced = false)
      check idx.getUnsyncedFiles().len == 3
      idx.markAllSynced()
      check idx.getUnsyncedFiles().len == 0

  test "getSyncStatus returns correct counts":
    withTestDir("idxsyncstatus"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f9")
      defer: idx.close()
      var info1: types.FileInfo
      info1.path = "a.txt"
      info1.encryptedPath = "a.txt"
      idx.addFile(info1, synced = true)
      var info2: types.FileInfo
      info2.path = "b.txt"
      info2.encryptedPath = "b.txt"
      idx.addFile(info2, synced = false)
      let status = idx.getSyncStatus()
      check status.total == 2
      check status.synced == 1
      check status.pending == 1

suite "Hash conversion":
  test "hashToString/stringToHash round-trip":
    withTestDir("idxhash"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f10")
      defer: idx.close()
      var h: array[32, byte]
      for i in 0..<32: h[i] = byte(i)
      let str = hashToString(h)
      check str.len == 64
      let restored = stringToHash(str)
      check h == restored
