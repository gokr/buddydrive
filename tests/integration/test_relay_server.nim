import std/[net, os, osproc, times, unittest]
import ../testutils

var relayBinaryPath {.global.}: string

proc repoRoot(): string =
  currentSourcePath().parentDir().parentDir().parentDir()

proc ensureRelayBinary(): string =
  if relayBinaryPath.len == 0:
    relayBinaryPath = getTempDir() / ("buddydrive_test_relay_" & $getTime().toUnix())
    let build = execCmdEx(
      "nim c -o:" & quoteShell(relayBinaryPath) & " relay/src/relay.nim",
      workingDir = repoRoot()
    )
    doAssert build.exitCode == 0, build.output
  relayBinaryPath

proc freePort(): int =
  let sock = newSocket()
  defer: sock.close()
  sock.bindAddr(Port(0))
  let (_, port) = sock.getLocalAddr()
  int(port)

proc waitForRelayReady(port: int) =
  for _ in 0 ..< 40:
    try:
      let sock = newSocket(buffered = true)
      defer: sock.close()
      sock.connect("127.0.0.1", Port(port))
      return
    except OSError:
      sleep(100)
  doAssert false, "relay server did not become ready"

proc readLineTimeout(sock: Socket, timeoutMs = 1000): string =
  sock.readLine(result, timeout = timeoutMs)

suite "relay server":
  test "pairs clients and relays bytes for matching token":
    withTestDir("relay_server"):
      let relayBin = ensureRelayBinary()
      let port = freePort()
      var relayProc = startProcess(
        relayBin,
        workingDir = repoRoot(),
        args = [$port],
        options = {poStdErrToStdOut}
      )
      defer:
        if peekExitCode(relayProc) == -1:
          terminate(relayProc)
          discard waitForExit(relayProc, 5000)
        close(relayProc)

      waitForRelayReady(port)

      let clientA = newSocket(buffered = true)
      let clientB = newSocket(buffered = true)
      defer:
        clientA.close()
        clientB.close()

      clientA.connect("127.0.0.1", Port(port))
      clientA.send("shared-token\n")
      check readLineTimeout(clientA) == "WAIT"

      clientB.connect("127.0.0.1", Port(port))
      clientB.send("shared-token\n")
      check readLineTimeout(clientB) == "OK"
      check readLineTimeout(clientA) == "OK"

      clientA.send("ping")
      check clientB.recv(4, timeout = 1000) == "ping"

      clientB.send("pong")
      check clientA.recv(4, timeout = 1000) == "pong"
