import std/unittest
import std/os
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/crypto
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
    folderName = "docs",
    encrypted = false,
    folderKey = "",
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  result.relayRegion = "local"
  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  buddy.pairingCode = pairingCode
  result.buddies = @[buddy]
  var folder = newFolderConfig(folderName, folderPath)
  folder.appendOnly = appendOnly
  folder.encrypted = encrypted
  folder.folderKey = folderKey
  folder.buddies = @[otherId]
  result.folders = @[folder]

proc connectAndSync(config: AppConfig): Future[void] {.async.} =
  let cache = initRelayListCache()
  let relayConn = await connectViaRegionalRelay(
    cache,
    config.apiBaseUrl,
    config.relayRegion,
    config.buddies[0].pairingCode
  )
  let bc = newBuddyConnection()
  bc.conn = relayConn.conn
  doAssert await bc.performHandshake(config)
  let protocol = newSyncProtocol()
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

  test "move detection renames remote file":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-move"
    let folderA = tempBase / "move-a"
    let folderB = tempBase / "move-b"
    for d in [folderA, folderB]:
      removeDir(d)
      createDir(d)
    defer:
      removeDir(tempBase)

    writeFile(folderA / "new-name.txt", "same content\n")
    writeFile(folderB / "old-name.txt", "same content\n")

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
      check not fileExists(folderB / "old-name.txt")
      check fileExists(folderB / "new-name.txt")
      check readFile(folderB / "new-name.txt") == "same content\n"
    except CatchableError as e:
      if strictIntegration():
        raise
      skip()

  test "mixed encrypted and unencrypted folders sync":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-mixed"
    let encA = tempBase / "enc-a"
    let encB = tempBase / "enc-b"
    let plainA = tempBase / "plain-a"
    let plainB = tempBase / "plain-b"
    for d in [encA, encB, plainA, plainB]:
      removeDir(d)
      createDir(d)
    defer:
      removeDir(tempBase)

    let sharedFolderKey = generateKey()
    writeFile(encA / "secret.txt", "top secret\n")
    writeFile(plainA / "shared.txt", "shared data\n")

    var cfg1 = makeConfig(
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "swift-eagle", encA,
      folderName = "encrypted-docs",
      encrypted = true,
      folderKey = sharedFolderKey,
    )
    var plainFolder1 = newFolderConfig("shared-docs", plainA)
    plainFolder1.buddies = @["22222222-2222-2222-2222-222222222222"]
    cfg1.folders.add(plainFolder1)

    var cfg2 = makeConfig(
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "swift-eagle", encB,
      folderName = "encrypted-docs",
      encrypted = true,
      folderKey = sharedFolderKey,
    )
    var plainFolder2 = newFolderConfig("shared-docs", plainB)
    plainFolder2.buddies = @["11111111-1111-1111-1111-111111111111"]
    cfg2.folders.add(plainFolder2)

    try:
      waitFor allFutures([connectAndSync(cfg1), connectAndSync(cfg2)])
      check fileExists(encB / "secret.txt")
      check readFile(encB / "secret.txt") == "top secret\n"
      check fileExists(plainB / "shared.txt")
      check readFile(plainB / "shared.txt") == "shared data\n"
    except CatchableError as e:
      if strictIntegration():
        raise
      skip()
