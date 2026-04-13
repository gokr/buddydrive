import std/unittest
import std/os except FileInfo
import ../../../src/buddydrive/types
import ../../../src/buddydrive/sync/scanner
import ../../testutils

suite "FileScanner construction":
  test "newFileScanner creates scanner with folder config":
    let folder = newFolderConfig("docs", "/tmp/test-docs")
    let scanner = newFileScanner(folder)
    check scanner.folder.name == "docs"
    check scanner.rootPath == "/tmp/test-docs"

suite "scanDirectory":
  test "empty directory returns empty seq":
    withTestDir("scanempty"):
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let files = scanner.scanDirectory()
      check files.len == 0

  test "single file detected":
    withTestDir("scansingle"):
      writeFile(testDir / "hello.txt", "hello")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let files = scanner.scanDirectory()
      check files.len == 1
      check files[0].path == "hello.txt"

  test "temp files are ignored":
    withTestDir("scantemp"):
      writeFile(testDir / "good.txt", "keep me")
      writeFile(testDir / ("partial.dat" & TempSuffix), "ignore me")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let files = scanner.scanDirectory()
      check files.len == 1
      check files[0].path == "good.txt"

  test "subdirectory files detected with relative paths":
    withTestDir("scansubdir"):
      createDir(testDir / "sub")
      writeFile(testDir / "sub" / "nested.txt", "nested")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let files = scanner.scanDirectory()
      check files.len == 1
      check files[0].path == "sub/nested.txt"

  test "nonexistent directory returns empty":
    let folder = newFolderConfig("test", "/tmp/buddydrive_nonexistent_dir_12345")
    let scanner = newFileScanner(folder)
    let files = scanner.scanDirectory()
    check files.len == 0

suite "scanChanges":
  test "added file detected":
    withTestDir("changeadd"):
      writeFile(testDir / "new.txt", "new file")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let changes = scanner.scanChanges(@[])
      check changes.len == 1
      check changes[0].kind == fcAdded
      check changes[0].info.path == "new.txt"

  test "modified file detected":
    withTestDir("changemodify"):
      var prev: seq[FileInfo] = @[]
      var oldInfo: FileInfo
      oldInfo.path = "doc.txt"
      oldInfo.encryptedPath = "doc.txt"
      oldInfo.size = 5
      oldInfo.mtime = 100
      prev.add(oldInfo)
      writeFile(testDir / "doc.txt", "updated content")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let changes = scanner.scanChanges(prev)
      check changes.len == 1
      check changes[0].kind == fcModified

  test "deleted file detected":
    withTestDir("changedelete"):
      var prev: seq[FileInfo] = @[]
      var oldInfo: FileInfo
      oldInfo.path = "gone.txt"
      oldInfo.encryptedPath = "gone.txt"
      oldInfo.size = 10
      oldInfo.mtime = 100
      prev.add(oldInfo)
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let changes = scanner.scanChanges(prev)
      check changes.len == 1
      check changes[0].kind == fcDeleted

suite "Crash safety - atomic write":
  test "write chunks to temp then rename":
    withTestDir("atomicwrite"):
      let finalPath = testDir / "testfile.dat"
      let tmpPath = finalPath & TempSuffix
      let chunk1 = @[byte(1), 2, 3, 4]
      let chunk2 = @[byte(5), 6, 7, 8]
      check writeFileChunk(tmpPath, 0, chunk1)
      check writeFileChunk(tmpPath, 4, chunk2)
      check not fileExists(finalPath)
      check fileExists(tmpPath)
      flushAndClose(tmpPath)
      moveFile(tmpPath, finalPath)
      check fileExists(finalPath)
      check not fileExists(tmpPath)
      let content = readFile(finalPath)
      check content.len == 8
      check content[0] == char(1)
      check content[7] == char(8)

  test "cleanup removes temp files":
    withTestDir("cleanup"):
      createDir(testDir / "subdir")
      writeFile(testDir / "good.txt", "keep me")
      writeFile(testDir / "partial.dat" & TempSuffix, "delete me")
      writeFile(testDir / "subdir" / "nested.dat" & TempSuffix, "delete me too")
      writeFile(testDir / "subdir" / "real.txt", "keep me too")
      cleanupTempFiles(testDir)
      check fileExists(testDir / "good.txt")
      check fileExists(testDir / "subdir" / "real.txt")
      check not fileExists(testDir / "partial.dat" & TempSuffix)
      check not fileExists(testDir / "subdir" / "nested.dat" & TempSuffix)

  test "cleanup on nonexistent dir does not raise":
    cleanupTempFiles("/tmp/buddydrive_nonexistent_dir_12345")

suite "File chunk I/O":
  test "readFileChunk reads correct data":
    withTestDir("chunkread"):
      writeFile(testDir / "data.bin", "0123456789")
      let chunk = readFileChunk(testDir / "data.bin", 2, 3)
      check chunk.len == 3
      check chunk[0] == byte('2')
      check chunk[1] == byte('3')
      check chunk[2] == byte('4')

  test "readFileChunk with offset beyond file returns empty":
    withTestDir("chunkbeyond"):
      writeFile(testDir / "small.txt", "hi")
      let chunk = readFileChunk(testDir / "small.txt", 100, 10)
      check chunk.len == 0

  test "writeFileChunk and readFileChunk round-trip":
    withTestDir("chunkroundtrip"):
      let data = @[byte(10), 20, 30, 40, 50]
      check writeFileChunk(testDir / "chunk.dat", 0, data)
      let read = readFileChunk(testDir / "chunk.dat", 0, 5)
      check read == data

  test "scanFile populates file info":
    withTestDir("scanfile"):
      writeFile(testDir / "doc.txt", "some content here")
      let folder = newFolderConfig("test", testDir)
      let scanner = newFileScanner(folder)
      let info = scanner.scanFile(testDir / "doc.txt")
      check info.path == "doc.txt"
      check info.size > 0
