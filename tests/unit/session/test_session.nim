import std/[options, os, sequtils, strutils, unittest]
import chronos
import libp2p/stream/bridgestream
import ../../../src/buddydrive/types
import ../../../src/buddydrive/p2p/messages
import ../../../src/buddydrive/p2p/protocol
import ../../../src/buddydrive/sync/session
import ../../testutils
import ../../support/sync_fixtures

useIsolatedDataDir("session")

proc runBridgeSync(cfg1: AppConfig, cfg2: AppConfig): Future[tuple[leftOk: bool, rightOk: bool]] {.async.} =
  let (left, right) = bridgedConnections(closeTogether = false)
  defer:
    await left.close()
    await right.close()

  let fut1 = syncBuddyFolders(cfg1, cfg1.buddies[0].id.uuid, left, newSyncProtocol())
  let fut2 = syncBuddyFolders(cfg2, cfg2.buddies[0].id.uuid, right, newSyncProtocol())
  result.leftOk = await fut1
  result.rightOk = await fut2

proc syncBoth(cfg1, cfg2: AppConfig) =
  let outcome = waitFor runBridgeSync(cfg1, cfg2)
  check outcome.leftOk
  check outcome.rightOk

proc readBlobs(root: string): seq[string] =
  for path in storedFiles(root, ".blob"):
    result.add(readFile(root / path))

suite "Session sync":
  test "each buddy stores the other's folder encrypted, apart from its own":
    withTestDir("session_backup"):
      let folderA = testDir / "a"
      let folderB = testDir / "b"
      createDir(folderA / "nested")
      createDir(folderB)
      writeFile(folderA / "secret-plan.txt", "top secret\n")
      writeFile(folderA / "nested" / "notes.md", "private notes\n")
      writeFile(folderA / "empty.txt", "")
      writeFile(folderB / "b-own.txt", "belongs to B\n")

      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores",
        @[syncFolder("folder-a", folderA)])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores",
        @[syncFolder("folder-b", folderB)])

      syncBoth(cfgA, cfgB)

      # B's own docs folder is untouched by A's docs folder.
      check toSeq(walkDirRec(folderB, relative = true)) == @["b-own.txt"]
      check toSeq(walkDirRec(folderA, relative = true)).len == 3

      let storedAtB = testDir / "b-stores" / "folder-a"
      check storedFiles(storedAtB, ".blob").len == 3
      check storedFiles(storedAtB, ".meta").len == 3
      check not anyFileMentions(storedAtB, ["secret", "notes", "nested", "top secret", "private notes"])

      let storedAtA = testDir / "a-stores" / "folder-b"
      check storedFiles(storedAtA, ".blob").len == 1
      check not anyFileMentions(storedAtA, ["b-own", "belongs to B"])

  test "a second session transfers nothing new":
    withTestDir("session_idempotent"):
      let folderA = testDir / "a"
      createDir(folderA)
      createDir(testDir / "b")
      writeFile(folderA / "file.txt", "content\n")
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[syncFolder("folder-a", folderA)])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])

      syncBoth(cfgA, cfgB)
      let before = readBlobs(testDir / "b-stores" / "folder-a")
      syncBoth(cfgA, cfgB)
      # Chunks get a fresh random nonce whenever they are sent, so an unchanged
      # blob proves nothing was sent again.
      check readBlobs(testDir / "b-stores" / "folder-a") == before

  test "lost files are restored from the buddy":
    withTestDir("session_restore"):
      let folderA = testDir / "a"
      createDir(folderA / "nested")
      createDir(testDir / "b")
      writeFile(folderA / "plan.txt", "the plan\n")
      writeFile(folderA / "nested" / "deep.bin", "\x00\x01\x02binary")
      writeFile(folderA / "empty.txt", "")
      when defined(posix):
        createSymlink("plan.txt", folderA / "plan-link")

      let source = syncFolder("folder-a", folderA)
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])
      syncBoth(peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[source]), cfgB)

      # A new machine: same folder id and key, empty folder, no index.
      let restored = testDir / "restored"
      createDir(restored)
      var replacement = source
      replacement.path = restored
      syncBoth(peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[replacement]), cfgB)

      check readFile(restored / "plan.txt") == "the plan\n"
      check readFile(restored / "nested" / "deep.bin") == "\x00\x01\x02binary"
      check fileExists(restored / "empty.txt")
      check readFile(restored / "empty.txt") == ""
      when defined(posix):
        check symlinkExists(restored / "plan-link")
        check expandSymlink(restored / "plan-link") == "plan.txt"

  test "renames move the stored blob instead of sending it again":
    withTestDir("session_move"):
      let folderA = testDir / "a"
      createDir(folderA)
      createDir(testDir / "b")
      writeFile(folderA / "old-name.txt", "same content\n")
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[syncFolder("folder-a", folderA)])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])
      let storedAtB = testDir / "b-stores" / "folder-a"

      syncBoth(cfgA, cfgB)
      let before = storedFiles(storedAtB, ".blob")
      let blobBefore = readBlobs(storedAtB)

      moveFile(folderA / "old-name.txt", folderA / "new-name.txt")
      syncBoth(cfgA, cfgB)

      let after = storedFiles(storedAtB, ".blob")
      check after.len == 1
      check after != before
      check readBlobs(storedAtB) == blobBefore
      check not fileExists(folderA / "old-name.txt")

  test "edits and deletions reach the buddy's storage":
    withTestDir("session_edit_delete"):
      let folderA = testDir / "a"
      createDir(folderA)
      createDir(testDir / "b")
      writeFile(folderA / "edit.txt", "first\n")
      writeFile(folderA / "doomed.txt", "delete me\n")
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[syncFolder("folder-a", folderA)])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])
      let storedAtB = testDir / "b-stores" / "folder-a"

      syncBoth(cfgA, cfgB)
      check storedFiles(storedAtB, ".blob").len == 2
      let blobsBefore = readBlobs(storedAtB)

      writeFile(folderA / "edit.txt", "second version\n")
      removeFile(folderA / "doomed.txt")
      syncBoth(cfgA, cfgB)

      check storedFiles(storedAtB, ".blob").len == 1
      check storedFiles(storedAtB, ".meta").len == 1
      check readBlobs(storedAtB)[0] notin blobsBefore
      check not fileExists(folderA / "doomed.txt")

      syncBoth(cfgA, cfgB)
      check not fileExists(folderA / "doomed.txt")

  test "append-only folders keep deleted files at the buddy without bringing them back":
    withTestDir("session_append_only"):
      let folderA = testDir / "a"
      createDir(folderA)
      createDir(testDir / "b")
      writeFile(folderA / "keeper.txt", "keep me\n")
      let source = syncFolder("folder-a", folderA, appendOnly = true)
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[source])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])
      let storedAtB = testDir / "b-stores" / "folder-a"

      syncBoth(cfgA, cfgB)
      removeFile(folderA / "keeper.txt")
      syncBoth(cfgA, cfgB)
      syncBoth(cfgA, cfgB)

      check storedFiles(storedAtB, ".blob").len == 1
      check not fileExists(folderA / "keeper.txt")

      let restored = testDir / "restored"
      createDir(restored)
      var replacement = source
      replacement.path = restored
      syncBoth(peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[replacement]), cfgB)
      check readFile(restored / "keeper.txt") == "keep me\n"

  test "unencrypted folders are stored as plain files":
    withTestDir("session_plain"):
      let folderA = testDir / "a"
      createDir(folderA / "sub")
      createDir(testDir / "b")
      writeFile(folderA / "sub" / "shared.txt", "shared data\n")
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores",
        @[syncFolder("folder-a", folderA, name = "shared", encrypted = false)])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])

      syncBoth(cfgA, cfgB)

      check readFile(testDir / "b-stores" / "folder-a" / "sub" / "shared.txt") == "shared data\n"

  test "an encrypted folder without a key is never sent":
    withTestDir("session_no_key"):
      let folderA = testDir / "a"
      createDir(folderA)
      createDir(testDir / "b")
      writeFile(folderA / "secret.txt", "top secret\n")
      var keyless = syncFolder("folder-a", folderA)
      keyless.folderKey = ""
      let cfgA = peerConfig(BuddyOne, BuddyTwo, testDir / "a-stores", @[keyless])
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[syncFolder("folder-b", testDir / "b")])

      syncBoth(cfgA, cfgB)

      check not dirExists(testDir / "b-stores" / "folder-a")
      check not anyFileMentions(testDir / "b-stores", ["secret"])

  test "a buddy's file list cannot reach outside its storage folder":
    withTestDir("session_traversal"):
      let cfgB = peerConfig(BuddyTwo, BuddyOne, testDir / "b-stores", @[])

      proc run(cfg: AppConfig): Future[bool] {.async.} =
        let (left, right) = bridgedConnections(closeTogether = false)
        defer:
          await left.close()
          await right.close()
        let protocol = newSyncProtocol()
        let syncFut = syncBuddyFolders(cfg, BuddyOne, left, protocol)

        # Scripted owner with an unencrypted folder that tries to escape.
        let evil = FileEntry(path: "../../escaped.txt", encryptedPath: "../../escaped.txt",
          size: 4, mtime: 1, hash: "00", mode: 0o644)
        await protocol.sendMessage(right, newFileList("shared", @[evil], "../evil", encrypted = false))
        await protocol.sendMessage(right, newSyncDone())
        discard await protocol.receiveMessage(right)
        # Owner round: nothing to change, then serve whatever is asked for.
        await protocol.sendMessage(right, newListPathsRequest("../evil"))
        discard await protocol.receiveMessage(right)
        await protocol.sendMessage(right, newSyncDone())
        while true:
          let msg = await protocol.receiveMessage(right)
          if msg.isNone or msg.get().kind != msgFileRequest:
            break
          await protocol.sendMessage(right, newFileData(@[byte(1), 2, 3, 4], 0, 4, true))
          discard await protocol.receiveMessage(right)
        await protocol.sendMessage(right, newSessionEnd())
        discard await protocol.receiveMessage(right)
        result = await syncFut

      check waitFor run(cfgB)
      check not fileExists(testDir / "escaped.txt")
      check not fileExists(testDir / "b-stores" / "escaped.txt")
      for path in walkDirRec(testDir, relative = true):
        check "escaped" notin path

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
