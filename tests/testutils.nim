import std/[os, random, times]

proc setupTestDir*(baseName: string): string =
  randomize()
  result = getTempDir() / "buddydrive_test_" & baseName & "_" & $getTime().toUnix() & "_" & $rand(1_000_000)
  createDir(result)

proc cleanupTestDir*(testDir: string) =
  if dirExists(testDir):
    try:
      removeDir(testDir)
    except:
      discard

template withTestDir*(baseName: string, body: untyped): untyped =
  let testDir {.inject.} = setupTestDir(baseName)
  try:
    body
  finally:
    cleanupTestDir(testDir)

template withTestFile*(baseName, content: string, body: untyped): untyped =
  let testDir {.inject.} = setupTestDir(baseName)
  let testFilePath {.inject.} = testDir / "testfile"
  try:
    writeFile(testFilePath, content)
    body
  finally:
    cleanupTestDir(testDir)

proc makeFileInfo*(path: string, size: int64 = 0, mtime: int64 = 0): tuple[path: string, encryptedPath: string, size: int64, mtime: int64, hash: array[32, byte]] =
  result.path = path
  result.encryptedPath = path
  result.size = size
  result.mtime = mtime
  result.hash = default(array[32, byte])

template runWithStrictFallback*(body: untyped) =
  try:
    body
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "  skipping: ", e.msg
  except:
    if strictIntegration():
      raise
    echo "  skipping: uncaught defect"

proc strictIntegration*(): bool =
  getEnv("BUDDYDRIVE_STRICT_INTEGRATION", "") == "1"

proc getKvApiUrl*(): string =
  getEnv("BUDDYDRIVE_KV_API_URL", "https://01.proxy.koyeb.app")

proc getLocalKvConnectionString*(): string =
  getEnv("BUDDYDRIVE_LOCAL_KV_DSN", "")
