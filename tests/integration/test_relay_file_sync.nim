import std/unittest
import std/os
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/p2p/rawrelay
import ../../src/buddydrive/p2p/pairing
import ../../src/buddydrive/p2p/protocol
import ../../src/buddydrive/sync/session
import ../testutils

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

suite "Relay file sync":
  test "forward sync (A -> B)":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync"
    let folderA = tempBase / "peer-a"
    let folderB = tempBase / "peer-b"
    for d in [folderA, folderB]:
      removeDir(d)
      createDir(d)
    defer:
      removeDir(tempBase)

    let sourceFile = folderA / "hello.txt"
    let content = "hello from A\n"
    writeFile(sourceFile, content)

    let cfg1 = makeConfig(
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "swift-eagle", folderA
    )
    let cfg2 = makeConfig(
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "swift-eagle", folderB
    )

    try:
      waitFor allFutures([connectAndSync(cfg1), connectAndSync(cfg2)])
      let copiedFile = folderB / "hello.txt"
      check fileExists(copiedFile)
      check readFile(copiedFile) == content
    except CatchableError as e:
      if strictIntegration():
        raise
      skip()

  test "reverse sync (B -> A)":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-rev"
    let folderA = tempBase / "peer-a"
    let folderB = tempBase / "peer-b"
    for d in [folderA, folderB]:
      removeDir(d)
      createDir(d)
    defer:
      removeDir(tempBase)

    let fileInB = folderB / "from-b.txt"
    let content = "data from B\n"
    writeFile(fileInB, content)

    let cfg1 = makeConfig(
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "swift-eagle", folderA
    )
    let cfg2 = makeConfig(
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "swift-eagle", folderB
    )

    try:
      waitFor allFutures([connectAndSync(cfg1), connectAndSync(cfg2)])
      let restoredFile = folderA / "from-b.txt"
      check fileExists(restoredFile)
      check readFile(restoredFile) == content
    except CatchableError as e:
      if strictIntegration():
        raise
      skip()

  test "append-only folder preserves existing files":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-append"
    let folderA = tempBase / "append-a"
    let folderB = tempBase / "append-b"
    for d in [folderA, folderB]:
      removeDir(d)
      createDir(d)
    defer:
      removeDir(tempBase)

    writeFile(folderA / "shared.txt", "version from A\n")
    writeFile(folderB / "shared.txt", "version from B\n")

    let cfg1 = makeConfig(
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "swift-eagle", folderA, appendOnly = false
    )
    let cfg2 = makeConfig(
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "swift-eagle", folderB, appendOnly = true
    )

    try:
      waitFor allFutures([connectAndSync(cfg1), connectAndSync(cfg2)])
      check readFile(folderB / "shared.txt") == "version from B\n"
    except CatchableError as e:
      if strictIntegration():
        raise
      skip()
