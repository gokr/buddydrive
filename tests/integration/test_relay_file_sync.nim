import std/unittest
import std/os
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/crypto
import ../../src/buddydrive/p2p/rawrelay
import ../../src/buddydrive/p2p/pairing
import ../../src/buddydrive/p2p/protocol
import ../../src/buddydrive/sync/session
import ../support/test_relay
import ../testutils

useIsolatedDataDir("relay_file_sync")

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
  result.apiBaseUrl = ""
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

proc syncPeers(cfg1, cfg2: AppConfig) =
  waitFor allFutures([connectAndSync(cfg1), connectAndSync(cfg2)])

proc freshDirs(base: string, names: varargs[string]): seq[string] =
  removeDir(base)
  for name in names:
    let dir = base / name
    createDir(dir)
    result.add(dir)

suite "Relay file sync":
  var relay: TestRelay

  setup:
    relay = startTestRelay()

  teardown:
    waitFor relay.stop()

  test "forward sync (A -> B)":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync"
    let dirs = freshDirs(tempBase, "peer-a", "peer-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
    defer:
      removeDir(tempBase)

    let content = "hello from A\n"
    writeFile(folderA / "hello.txt", content)

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

    syncPeers(cfg1, cfg2)

    check fileExists(folderB / "hello.txt")
    check readFile(folderB / "hello.txt") == content
    check fileExists(folderA / "hello.txt")
    check readFile(folderA / "hello.txt") == content

  test "reverse sync (B -> A)":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-rev"
    let dirs = freshDirs(tempBase, "peer-a", "peer-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
    defer:
      removeDir(tempBase)

    let content = "data from B\n"
    writeFile(folderB / "from-b.txt", content)

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

    syncPeers(cfg1, cfg2)

    check fileExists(folderA / "from-b.txt")
    check readFile(folderA / "from-b.txt") == content
    check fileExists(folderB / "from-b.txt")

  test "both directions in one session":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-both"
    let dirs = freshDirs(tempBase, "peer-a", "peer-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
    defer:
      removeDir(tempBase)

    writeFile(folderA / "from-a.txt", "a\n")
    writeFile(folderB / "from-b.txt", "b\n")

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

    syncPeers(cfg1, cfg2)

    check fileExists(folderA / "from-b.txt")
    check fileExists(folderB / "from-a.txt")
    check readFile(folderA / "from-a.txt") == "a\n"
    check readFile(folderB / "from-b.txt") == "b\n"

  test "local deletion propagates to buddy":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-delete"
    let dirs = freshDirs(tempBase, "peer-a", "peer-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
    defer:
      removeDir(tempBase)

    writeFile(folderA / "doomed.txt", "delete me\n")

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

    syncPeers(cfg1, cfg2)
    check fileExists(folderB / "doomed.txt")

    removeFile(folderA / "doomed.txt")
    syncPeers(cfg1, cfg2)

    check not fileExists(folderA / "doomed.txt")
    check not fileExists(folderB / "doomed.txt")

  test "append-only folder preserves existing files":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-append"
    let dirs = freshDirs(tempBase, "append-a", "append-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
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

    syncPeers(cfg1, cfg2)

    check readFile(folderB / "shared.txt") == "version from B\n"

  test "append-only folder ignores a remote deletion":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-append-del"
    let dirs = freshDirs(tempBase, "append-a", "append-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
    defer:
      removeDir(tempBase)

    writeFile(folderA / "keeper.txt", "keep me\n")

    let cfg1 = makeConfig(
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "swift-eagle", folderA
    )
    let cfg2 = makeConfig(
      "22222222-2222-2222-2222-222222222222", "buddy-two",
      "11111111-1111-1111-1111-111111111111", "buddy-one",
      "swift-eagle", folderB, appendOnly = true
    )

    syncPeers(cfg1, cfg2)
    check fileExists(folderB / "keeper.txt")

    removeFile(folderA / "keeper.txt")
    syncPeers(cfg1, cfg2)

    check fileExists(folderB / "keeper.txt")
    check readFile(folderB / "keeper.txt") == "keep me\n"

    # A has forgotten the path by now, so the archive copy comes back to A on
    # the next session. Restoring from the append-only side is the point of it.
    syncPeers(cfg1, cfg2)
    check fileExists(folderA / "keeper.txt")
    check readFile(folderA / "keeper.txt") == "keep me\n"
    check fileExists(folderB / "keeper.txt")

  test "move detection renames remote file":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-move"
    let dirs = freshDirs(tempBase, "move-a", "move-b")
    let folderA = dirs[0]
    let folderB = dirs[1]
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

    syncPeers(cfg1, cfg2)

    check not fileExists(folderB / "old-name.txt")
    check fileExists(folderB / "new-name.txt")
    check readFile(folderB / "new-name.txt") == "same content\n"

  test "mixed encrypted and unencrypted folders sync":
    let tempBase = getTempDir() / "buddydrive-relay-file-sync-mixed"
    let dirs = freshDirs(tempBase, "enc-a", "enc-b", "plain-a", "plain-b")
    let encA = dirs[0]
    let encB = dirs[1]
    let plainA = dirs[2]
    let plainB = dirs[3]
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

    syncPeers(cfg1, cfg2)

    check fileExists(encB / "secret.txt")
    check readFile(encB / "secret.txt") == "top secret\n"
    check fileExists(plainB / "shared.txt")
    check readFile(plainB / "shared.txt") == "shared data\n"
