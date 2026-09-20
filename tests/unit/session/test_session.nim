import std/[options, os, unittest]
import chronos
import libp2p/stream/bridgestream
import ../../../src/buddydrive/types
import ../../../src/buddydrive/p2p/messages
import ../../../src/buddydrive/p2p/protocol
import ../../../src/buddydrive/sync/session
import ../../testutils

useIsolatedDataDir("session")

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

suite "Session end":
  test "waits for the buddy before finishing":
    # The side that finishes first used to close straight away, cutting off a
    # buddy that was still reading the tail of a transfer through a relay. It
    # must now announce the end and wait for the buddy to do the same.
    withTestDir("session_end"):
      var cfg = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "buddy-one"))
      var buddy: BuddyInfo
      buddy.id = newBuddyId("22222222-2222-2222-2222-222222222222", "buddy-two")
      cfg.buddies = @[buddy]

      proc run(cfg: AppConfig): Future[tuple[sawSessionEnd: bool, waitedForUs: bool, ok: bool]] {.async.} =
        let (left, right) = bridgedConnections(closeTogether = false)
        defer:
          await left.close()
          await right.close()

        let protocol = newSyncProtocol()
        let syncFut = syncBuddyFolders(cfg, cfg.buddies[0].id.uuid, left, protocol)

        # Scripted buddy: no folders either, so the conversation is just the
        # empty folder-list exchange followed by the session end.
        let listDone = await protocol.receiveMessage(right)
        if listDone.isNone or listDone.get().kind != msgSyncDone:
          return (false, false, false)
        await protocol.sendMessage(right, newSyncDone())

        let ending = await protocol.receiveMessage(right)
        result.sawSessionEnd = ending.isSome and ending.get().kind == msgSessionEnd

        await sleepAsync(chronos.milliseconds(200))
        result.waitedForUs = not syncFut.finished

        await protocol.sendMessage(right, newSessionEnd())
        result.ok = await syncFut

      let outcome = waitFor run(cfg)
      check outcome.sawSessionEnd
      check outcome.waitedForUs
      check outcome.ok

  test "finishes when the buddy never sends session end":
    # An older buddy does not know the message; the session must still succeed.
    withTestDir("session_end_old_peer"):
      var cfg = newAppConfig(newBuddyId("11111111-1111-1111-1111-111111111111", "buddy-one"))
      var buddy: BuddyInfo
      buddy.id = newBuddyId("22222222-2222-2222-2222-222222222222", "buddy-two")
      cfg.buddies = @[buddy]

      proc run(cfg: AppConfig): Future[bool] {.async.} =
        let (left, right) = bridgedConnections(closeTogether = false)
        let protocol = newSyncProtocol()
        let syncFut = syncBuddyFolders(cfg, cfg.buddies[0].id.uuid, left, protocol)

        let listDone = await protocol.receiveMessage(right)
        if listDone.isNone or listDone.get().kind != msgSyncDone:
          return false
        await protocol.sendMessage(right, newSyncDone())

        # Buddy hangs up without a session end, as an older build would.
        await right.close()
        result = await syncFut
        await left.close()

      check waitFor run(cfg)
