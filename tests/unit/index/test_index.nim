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
      info.encryptedPath = "enc_doc.txt"
      info.size = 1024
      info.mtime = 1000
      info.mode = 0o644
      info.symlinkTarget = ""
      for i in 0..<32: info.hash[i] = byte(i)
      idx.addFile(info)
      let retrieved = idx.getFile("doc.txt")
      check retrieved.isSome
      check retrieved.get().path == "doc.txt"
      check retrieved.get().encryptedPath == "enc_doc.txt"
      check retrieved.get().size == 1024
      check retrieved.get().mtime == 1000
      check retrieved.get().hash == info.hash
      check retrieved.get().mode == 0o644
      check retrieved.get().symlinkTarget == ""

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
      info.encryptedPath = "enc_to-remove.txt"
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
      info1.encryptedPath = "enc_update1.txt"
      info1.size = 50
      info1.mtime = 100
      info1.mode = 0o644
      idx.addFile(info1)
      var info2: types.FileInfo
      info2.path = "update.txt"
      info2.encryptedPath = "enc_update2.txt"
      info2.size = 200
      info2.mtime = 300
      info2.mode = 0o755
      info2.symlinkTarget = "target.txt"
      idx.addFile(info2)
      let retrieved = idx.getFile("update.txt")
      check retrieved.get().encryptedPath == "enc_update2.txt"
      check retrieved.get().size == 200
      check retrieved.get().mtime == 300
      check retrieved.get().mode == 0o755
      check retrieved.get().symlinkTarget == "target.txt"

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
        info.encryptedPath = "enc_" & info.path
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
      info1.encryptedPath = "enc_synced.txt"
      idx.addFile(info1, synced = true)
      var info2: types.FileInfo
      info2.path = "pending.txt"
      info2.encryptedPath = "enc_pending.txt"
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
      info.encryptedPath = "enc_tosync.txt"
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
        info.encryptedPath = "enc_" & info.path
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
      info1.encryptedPath = "enc_a.txt"
      idx.addFile(info1, synced = true)
      var info2: types.FileInfo
      info2.path = "b.txt"
      info2.encryptedPath = "enc_b.txt"
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

suite "FileIndex getFileByHash":
  test "getFileByHash finds file by content hash":
    withTestDir("idxbyhash"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f11")
      defer: idx.close()
      var info: types.FileInfo
      info.path = "photos/vacation.jpg"
      info.encryptedPath = "enc_vacation.jpg"
      info.size = 5000
      info.mtime = 2000
      for i in 0..<32: info.hash[i] = byte(i + 10)
      idx.addFile(info)
      let found = idx.getFileByHash(info.hash)
      check found.isSome
      check found.get().path == "photos/vacation.jpg"

  test "getFileByHash returns none for unknown hash":
    withTestDir("idxbyhashmiss"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f12")
      defer: idx.close()
      var h: array[32, byte]
      for i in 0..<32: h[i] = byte(255)
      check idx.getFileByHash(h).isNone

  test "getFileByHash supports move detection — same hash at new path":
    withTestDir("idxmovedetect"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f13")
      defer: idx.close()
      var h: array[32, byte]
      for i in 0..<32: h[i] = byte(i)
      var info1: types.FileInfo
      info1.path = "old/name.txt"
      info1.encryptedPath = "enc_old_name.txt"
      info1.size = 100
      info1.mtime = 1000
      info1.hash = h
      idx.addFile(info1)
      idx.removeFile("old/name.txt")
      var info2: types.FileInfo
      info2.path = "new/name.txt"
      info2.encryptedPath = "enc_new_name.txt"
      info2.size = 100
      info2.mtime = 1000
      info2.hash = h
      idx.addFile(info2)
      let found = idx.getFileByHash(h)
      check found.isSome
      check found.get().path == "new/name.txt"

suite "FileIndex getFileByEncryptedPath":
  test "getFileByEncryptedPath finds file":
    withTestDir("idxbyencpath"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f14")
      defer: idx.close()
      var info: types.FileInfo
      info.path = "secret.txt"
      info.encryptedPath = "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
      info.size = 42
      info.mtime = 3000
      for i in 0..<32: info.hash[i] = byte(i)
      idx.addFile(info)
      let found = idx.getFileByEncryptedPath("aBcDeFgHiJkLmNoPqRsTuVwXyZ012345")
      check found.isSome
      check found.get().path == "secret.txt"

  test "getFileByEncryptedPath returns none for unknown":
    withTestDir("idxbyencpathmiss"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f15")
      defer: idx.close()
      check idx.getFileByEncryptedPath("nonexistent").isNone

suite "Storage index operations":
  test "addStorageFile and getStorageFile round-trip":
    withTestDir("idxstorageadd"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f16")
      defer: idx.close()
      var info: types.StorageFileInfo
      info.encryptedPath = "enc_photo.jpg"
      for i in 0..<32: info.contentHash[i] = byte(i + 5)
      info.size = 2048
      info.mode = 0o600
      info.symlinkTarget = ""
      info.ownerBuddy = "buddy-abc"
      idx.addStorageFile(info)
      let retrieved = idx.getStorageFile("enc_photo.jpg", "buddy-abc")
      check retrieved.isSome
      check retrieved.get().encryptedPath == "enc_photo.jpg"
      check retrieved.get().contentHash == info.contentHash
      check retrieved.get().size == 2048
      check retrieved.get().mode == 0o600
      check retrieved.get().symlinkTarget == ""
      check retrieved.get().ownerBuddy == "buddy-abc"

  test "getStorageFile returns none for missing file":
    withTestDir("idxstoragemiss"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f17")
      defer: idx.close()
      check idx.getStorageFile("nope", "buddy-xyz").isNone

  test "removeStorageFile removes entry":
    withTestDir("idxstoragerm"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f18")
      defer: idx.close()
      var info: types.StorageFileInfo
      info.encryptedPath = "to-rm.dat"
      for i in 0..<32: info.contentHash[i] = byte(i)
      info.size = 100
      info.ownerBuddy = "buddy-rm"
      idx.addStorageFile(info)
      check idx.getStorageFile("to-rm.dat", "buddy-rm").isSome
      idx.removeStorageFile("to-rm.dat", "buddy-rm")
      check idx.getStorageFile("to-rm.dat", "buddy-rm").isNone

  test "listByOwner returns all files for a buddy":
    withTestDir("idxlistbyowner"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f19")
      defer: idx.close()
      for i in 0..<3:
        var info: types.StorageFileInfo
        info.encryptedPath = "file" & $i & ".enc"
        for j in 0..<32: info.contentHash[j] = byte(i * 32 + j)
        info.size = int64(i * 100)
        info.ownerBuddy = "buddy-list"
        idx.addStorageFile(info)
      var otherInfo: types.StorageFileInfo
      otherInfo.encryptedPath = "other.enc"
      for j in 0..<32: otherInfo.contentHash[j] = byte(j)
      otherInfo.size = 999
      otherInfo.ownerBuddy = "buddy-other"
      idx.addStorageFile(otherInfo)
      let files = idx.listByOwner("buddy-list")
      check files.len == 3
      let otherFiles = idx.listByOwner("buddy-other")
      check otherFiles.len == 1

  test "updateStoragePath renames encrypted path":
    withTestDir("idxstorageupdate"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx = newIndex("f20")
      defer: idx.close()
      var info: types.StorageFileInfo
      info.encryptedPath = "old_path.enc"
      for i in 0..<32: info.contentHash[i] = byte(i)
      info.size = 500
      info.mode = 0o777
      info.symlinkTarget = "dir/target"
      info.ownerBuddy = "buddy-move"
      idx.addStorageFile(info)
      idx.updateStoragePath("old_path.enc", "new_path.enc", "buddy-move")
      check idx.getStorageFile("old_path.enc", "buddy-move").isNone
      let moved = idx.getStorageFile("new_path.enc", "buddy-move")
      check moved.isSome
      check moved.get().contentHash == info.contentHash
      check moved.get().size == 500
      check moved.get().mode == 0o777
      check moved.get().symlinkTarget == "dir/target"

suite "Schema migration":
  test "opening existing DB runs migration to v3":
    withTestDir("idxmigration"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx1 = newIndex("f-mig")
      idx1.close()
      let idx2 = newIndex("f-mig")
      defer: idx2.close()
      var sinfo: types.StorageFileInfo
      sinfo.encryptedPath = "mig_test.enc"
      for i in 0..<32: sinfo.contentHash[i] = byte(i)
      sinfo.size = 100
      sinfo.ownerBuddy = "buddy-mig"
      idx2.addStorageFile(sinfo)
      check idx2.getStorageFile("mig_test.enc", "buddy-mig").isSome

suite "Folder isolation":
  test "different folderNames in same DB are isolated":
    withTestDir("idxfolderisol"):
      putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
      putEnv("BUDDYDRIVE_DATA_DIR", testDir)
      defer:
        delEnv("BUDDYDRIVE_CONFIG_DIR")
        delEnv("BUDDYDRIVE_DATA_DIR")
      let idx1 = newIndex("folder-a")
      defer: idx1.close()
      let idx2 = newIndex("folder-b")
      defer: idx2.close()
      var info1: types.FileInfo
      info1.path = "same.txt"
      info1.encryptedPath = "enc_a.txt"
      info1.size = 10
      info1.mtime = 1
      for i in 0..<32: info1.hash[i] = byte(1)
      idx1.addFile(info1)
      var info2: types.FileInfo
      info2.path = "same.txt"
      info2.encryptedPath = "enc_b.txt"
      info2.size = 20
      info2.mtime = 2
      for i in 0..<32: info2.hash[i] = byte(2)
      idx2.addFile(info2)
      let r1 = idx1.getFile("same.txt")
      check r1.isSome
      check r1.get().size == 10
      let r2 = idx2.getFile("same.txt")
      check r2.isSome
      check r2.get().size == 20
