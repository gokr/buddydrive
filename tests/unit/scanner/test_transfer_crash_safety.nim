import std/[options, os, unittest]
import chronos
import libp2p/stream/bufferstream
import libp2p/stream/bridgestream
import ../../../src/buddydrive/types
import ../../../src/buddydrive/p2p/messages
import ../../../src/buddydrive/p2p/protocol
import ../../../src/buddydrive/sync/transfer
import ../../../src/buddydrive/sync/scanner
import ../../testutils

proc feedMessages(
    sender: BridgeStream,
    protocol: SyncProtocol,
    msgs: seq[ProtocolMessage],
) {.async.} =
  for msg in msgs:
    await protocol.sendMessage(sender, msg)

proc newTestTransfer(rootPath: string): FileTransfer =
  let folder = newFolderConfig("docs", rootPath)
  result = newFileTransfer(folder, newSyncProtocol())

suite "transfer crash safety":
  test "interrupted receive removes temp file and does not create final file":
    withTestDir("transfer_interrupt"):
      let (sender, receiver) = bridgedConnections(closeTogether = false)
      let transfer = newTestTransfer(testDir)
      defer:
        transfer.close()

      let msg = newFileData(@[byte(1), 2, 3, 4], 0, 8, false, ckNone, 4)
      let receiveFut = transfer.receiveFileData(receiver, "nested/file.bin")
      waitFor feedMessages(sender, transfer.protocol, @[msg])
      waitFor receiver.pushEof()
      let ackFut = transfer.protocol.receiveMessage(sender)

      let ok = waitFor receiveFut
      let ackOpt = waitFor ackFut
      check not ok
      check ackOpt.isSome()
      check ackOpt.get().kind == msgFileAck
      check not ackOpt.get().success
      check not fileExists(testDir / "nested" / "file.bin")
      check not fileExists(testDir / "nested" / ("file.bin" & TempSuffix))

  test "mismatched total size fails receive and leaves no committed file":
    withTestDir("transfer_totalsize"):
      let (sender, receiver) = bridgedConnections(closeTogether = false)
      let transfer = newTestTransfer(testDir)
      defer:
        transfer.close()

      let msg1 = newFileData(@[byte(1), 2, 3, 4], 0, 8, false, ckNone, 4)
      let msg2 = newFileData(@[byte(5), 6, 7, 8], 4, 7, true, ckNone, 4)
      let receiveFut = transfer.receiveFileData(receiver, "file.bin")
      waitFor feedMessages(sender, transfer.protocol, @[msg1, msg2])
      let ackFut = transfer.protocol.receiveMessage(sender)

      let ok = waitFor receiveFut
      let ackOpt = waitFor ackFut
      check not ok
      check ackOpt.isSome()
      check ackOpt.get().kind == msgFileAck
      check not ackOpt.get().success
      check not fileExists(testDir / "file.bin")
      check not fileExists(testDir / ("file.bin" & TempSuffix))

  test "flush failure prevents rename and cleans temp file":
    withTestDir("transfer_flushfail"):
      let (sender, receiver) = bridgedConnections(closeTogether = false)
      let transfer = newTestTransfer(testDir)
      defer:
        setFlushAndCloseShouldFail(false)
        transfer.close()

      setFlushAndCloseShouldFail(true)

      let msg = newFileData(@[byte(1), 2, 3, 4], 0, 4, true, ckNone, 4)
      let receiveFut = transfer.receiveFileData(receiver, "file.bin")
      waitFor feedMessages(sender, transfer.protocol, @[msg])
      let ackFut = transfer.protocol.receiveMessage(sender)

      let ok = waitFor receiveFut
      let ackOpt = waitFor ackFut
      check not ok
      check ackOpt.isSome()
      check ackOpt.get().kind == msgFileAck
      check not ackOpt.get().success
      check not fileExists(testDir / "file.bin")
      check not fileExists(testDir / ("file.bin" & TempSuffix))

  test "successful receive commits final file":
    withTestDir("transfer_success"):
      let (sender, receiver) = bridgedConnections(closeTogether = false)
      let transfer = newTestTransfer(testDir)
      defer:
        transfer.close()

      let msg1 = newFileData(@[byte(1), 2], 0, 4, false, ckNone, 2)
      let msg2 = newFileData(@[byte(3), 4], 2, 4, true, ckNone, 2)
      let receiveFut = transfer.receiveFileData(receiver, "ok.bin")
      waitFor feedMessages(sender, transfer.protocol, @[msg1, msg2])
      let ackFut = transfer.protocol.receiveMessage(sender)

      let ok = waitFor receiveFut
      let ackOpt = waitFor ackFut
      check ok
      check ackOpt.isSome()
      check ackOpt.get().kind == msgFileAck
      check ackOpt.get().success
      check fileExists(testDir / "ok.bin")
      check not fileExists(testDir / ("ok.bin" & TempSuffix))
      let content = readFile(testDir / "ok.bin")
      check content.len == 4
      check content[0] == char(1)
      check content[3] == char(4)
