import std/os
import ../../src/buddydrive/sync/scanner

proc testWriteToTempThenRename() =
  let tmpDir = getTempDir() / "buddydrive_test_atomic"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  let finalPath = tmpDir / "testfile.dat"
  let tmpPath = finalPath & TempSuffix

  # Write chunks to temp file
  let chunk1 = @[byte(1), 2, 3, 4]
  let chunk2 = @[byte(5), 6, 7, 8]
  doAssert writeFileChunk(tmpPath, 0, chunk1)
  doAssert writeFileChunk(tmpPath, 4, chunk2)

  # Final path should not exist yet
  doAssert not fileExists(finalPath)
  doAssert fileExists(tmpPath)

  # Fsync + rename
  flushAndClose(tmpPath)
  moveFile(tmpPath, finalPath)

  doAssert fileExists(finalPath)
  doAssert not fileExists(tmpPath)

  # Verify content
  let content = readFile(finalPath)
  doAssert content.len == 8
  doAssert content[0] == char(1)
  doAssert content[7] == char(8)

proc testCleanupRemovesTempFiles() =
  let tmpDir = getTempDir() / "buddydrive_test_cleanup"
  createDir(tmpDir)
  createDir(tmpDir / "subdir")
  defer: removeDir(tmpDir)

  # Create temp files and regular files
  writeFile(tmpDir / "good.txt", "keep me")
  writeFile(tmpDir / "partial.dat" & TempSuffix, "delete me")
  writeFile(tmpDir / "subdir" / "nested.dat" & TempSuffix, "delete me too")
  writeFile(tmpDir / "subdir" / "real.txt", "keep me too")

  cleanupTempFiles(tmpDir)

  doAssert fileExists(tmpDir / "good.txt")
  doAssert fileExists(tmpDir / "subdir" / "real.txt")
  doAssert not fileExists(tmpDir / "partial.dat" & TempSuffix)
  doAssert not fileExists(tmpDir / "subdir" / "nested.dat" & TempSuffix)

proc testCleanupOnNonexistentDir() =
  # Should not raise
  cleanupTempFiles("/tmp/buddydrive_nonexistent_dir_12345")

proc testScanDirectoryIgnoresTempFiles() =
  let tmpDir = getTempDir() / "buddydrive_test_scan_ignore"
  createDir(tmpDir)
  defer: removeDir(tmpDir)

  writeFile(tmpDir / "good.txt", "keep me")
  writeFile(tmpDir / ("partial.txt" & TempSuffix), "ignore me")

  var folder = newFolderConfig("docs", tmpDir)
  let scanner = newFileScanner(folder)
  let files = scanner.scanDirectory()

  doAssert files.len == 1
  doAssert files[0].path == "good.txt"

when isMainModule:
  testWriteToTempThenRename()
  testCleanupRemovesTempFiles()
  testCleanupOnNonexistentDir()
  testScanDirectoryIgnoresTempFiles()
  echo "crash safety ok"
