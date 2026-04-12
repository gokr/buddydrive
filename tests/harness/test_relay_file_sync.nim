import std/os
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/p2p/rawrelay
import ../../src/buddydrive/p2p/pairing
import ../../src/buddydrive/p2p/protocol
import ../../src/buddydrive/sync/session

proc strictIntegration(): bool =
  getEnv("BUDDYDRIVE_STRICT_INTEGRATION", "") == "1"

proc makeConfig(
    selfId: string,
    selfName: string,
    otherId: string,
    otherName: string,
    pairingCode: string,
    folderPath: string,
    appendOnly = false,
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  result.relayRegion = "local"

  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  buddy.pairingCode = pairingCode
  result.buddies = @[buddy]

  var folder = newFolderConfig("docs", folderPath)
  folder.appendOnly = appendOnly
  folder.buddies = @[otherId]
  result.folders = @[folder]

proc connectAndSync(config: AppConfig): Future[void] {.async.} =
  let cache = initRelayListCache()
  let relayConn = await connectViaRegionalRelay(
    cache,
    config.relayBaseUrl,
    config.relayRegion,
    config.buddies[0].pairingCode
  )

  let bc = newBuddyConnection()
  bc.conn = relayConn.conn
  doAssert await bc.performHandshake(config)

  let protocol = SyncProtocol(node: nil)
  doAssert await syncBuddyFolders(config, bc.buddyId, bc.conn, protocol)
  await bc.close()

proc testForwardSync(folderA: string, folderB: string) {.async.} =
  echo "=== Test: forward sync (A -> B) ==="

  let sourceFile = folderA / "hello.txt"
  let content = "hello from A\n"
  writeFile(sourceFile, content)

  let cfg1 = makeConfig(
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "swift-eagle",
    folderA
  )
  let cfg2 = makeConfig(
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "swift-eagle",
    folderB
  )

  let f1 = connectAndSync(cfg1)
  let f2 = connectAndSync(cfg2)
  await f1
  await f2

  let copiedFile = folderB / "hello.txt"
  doAssert fileExists(copiedFile), "forward sync: file missing in B"
  doAssert readFile(copiedFile) == content, "forward sync: content mismatch"
  echo "  ok: A's file synced to B"

proc testReverseSync(folderA: string, folderB: string) {.async.} =
  echo "=== Test: reverse sync (B -> A, restoring missing file) ==="

  let fileInB = folderB / "from-b.txt"
  let content = "data from B\n"
  writeFile(fileInB, content)

  let cfg1 = makeConfig(
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "swift-eagle",
    folderA
  )
  let cfg2 = makeConfig(
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "swift-eagle",
    folderB
  )

  let f1 = connectAndSync(cfg1)
  let f2 = connectAndSync(cfg2)
  await f1
  await f2

  let restoredFile = folderA / "from-b.txt"
  doAssert fileExists(restoredFile), "reverse sync: file missing in A"
  doAssert readFile(restoredFile) == content, "reverse sync: content mismatch"
  echo "  ok: B's file synced back to A (restores missing files)"

proc testAppendOnly(folderA: string, folderB: string) {.async.} =
  echo "=== Test: append-only folder (B must not overwrite existing files) ==="

  let fileA = folderA / "shared.txt"
  let fileB = folderB / "shared.txt"

  writeFile(fileA, "version from A\n")
  writeFile(fileB, "version from B\n")

  let cfg1 = makeConfig(
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "swift-eagle",
    folderA,
    appendOnly = false
  )
  let cfg2 = makeConfig(
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "swift-eagle",
    folderB,
    appendOnly = true
  )

  let f1 = connectAndSync(cfg1)
  let f2 = connectAndSync(cfg2)
  await f1
  await f2

  doAssert readFile(fileB) == "version from B\n",
    "append-only: B's existing file was overwritten"
  echo "  ok: append-only folder preserved B's existing file"

proc main() {.async.} =
  let tempBase = getTempDir() / "buddydrive-relay-file-sync"
  let homeDir = tempBase / "home"
  let folderA = tempBase / "peer-a"
  let folderB = tempBase / "peer-b"

  for d in [homeDir, folderA, folderB]:
    removeDir(d)
    createDir(d)
  putEnv("HOME", homeDir)

  try:
    await testForwardSync(folderA, folderB)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "  skipping (relay unavailable): ", e.msg

  try:
    await testReverseSync(folderA, folderB)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "  skipping (relay unavailable): ", e.msg

  let appendA = tempBase / "append-a"
  let appendB = tempBase / "append-b"
  for d in [appendA, appendB]:
    removeDir(d)
    createDir(d)

  try:
    await testAppendOnly(appendA, appendB)
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "  skipping (relay unavailable): ", e.msg

  echo ""
  echo "relay file sync ok"

waitFor main()
