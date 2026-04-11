import std/[os, strutils]
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
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  result.relayRegion = "local"

  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  buddy.pairingCode = pairingCode
  result.buddies = @[buddy]

  var folder = newFolderConfig("docs", folderPath)
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

proc main() {.async.} =
  let tempBase = getTempDir() / "buddydrive-relay-file-sync"
  let homeDir = tempBase / "home"
  let folderA = tempBase / "peer-a"
  let folderB = tempBase / "peer-b"

  createDir(homeDir)
  createDir(folderA)
  createDir(folderB)
  putEnv("HOME", homeDir)

  let sourceFile = folderA / "hello.txt"
  let content = repeat("compressible hello line\n", 4096)
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

  try:
    let f1 = connectAndSync(cfg1)
    let f2 = connectAndSync(cfg2)
    await f1
    await f2
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "relay file sync unavailable; skipping in non-strict mode: ", e.msg
    return

  let copiedFile = folderB / "hello.txt"
  doAssert fileExists(copiedFile)
  doAssert readFile(copiedFile) == content
  echo "relay file sync ok"

waitFor main()
