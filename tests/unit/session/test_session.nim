import std/[os, unittest]
import chronos
import libp2p/stream/bridgestream
import ../../../src/buddydrive/types
import ../../../src/buddydrive/p2p/protocol
import ../../../src/buddydrive/sync/session
import ../../testutils

proc makeConfig(
    selfId: string,
    selfName: string,
    otherId: string,
    otherName: string,
    folderPath: string,
    folderName = "docs",
    encrypted = false,
    folderKey = "",
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  result.buddies = @[buddy]
  var folder = newFolderConfig(folderName, folderPath)
  folder.encrypted = encrypted
  folder.folderKey = folderKey
  folder.buddies = @[otherId]
  result.folders = @[folder]

proc runBridgeSync(cfg1: AppConfig, cfg2: AppConfig): Future[tuple[leftOk: bool, rightOk: bool]] {.async.} =
  let (left, right) = bridgedConnections(closeTogether = false)
  defer:
    await left.close()
    await right.close()

  let fut1 = syncBuddyFolders(cfg1, cfg1.buddies[0].id.uuid, left, newSyncProtocol())
  let fut2 = syncBuddyFolders(cfg2, cfg2.buddies[0].id.uuid, right, newSyncProtocol())
  result.leftOk = await fut1
  result.rightOk = await fut2

suite "Session sync":
  test "move detection renames remote file":
    withTestDir("session_move_a"):
      let folderA = testDir / "a"
      let folderB = testDir / "b"
      createDir(folderA)
      createDir(folderB)

      writeFile(folderA / "new-name.txt", "same content\n")
      writeFile(folderB / "old-name.txt", "same content\n")

      let cfg1 = makeConfig(
        "11111111-1111-1111-1111-111111111111", "buddy-one",
        "22222222-2222-2222-2222-222222222222", "buddy-two",
        folderA,
      )
      let cfg2 = makeConfig(
        "22222222-2222-2222-2222-222222222222", "buddy-two",
        "11111111-1111-1111-1111-111111111111", "buddy-one",
        folderB,
      )

      let syncResult = waitFor runBridgeSync(cfg1, cfg2)
      check syncResult.leftOk
      check syncResult.rightOk
      check fileExists(folderB / "new-name.txt")
      check not fileExists(folderB / "old-name.txt")
      check readFile(folderB / "new-name.txt") == "same content\n"
