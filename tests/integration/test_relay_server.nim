import std/[net, os, osproc, times, unittest, strutils]
import libsodium/sodium
import ../testutils
import ../support/integration_harness

var relayBinaryPath {.global.}: string

proc ensureRelayBinary(): string =
  ensureBuiltBinary(relayBinaryPath, "buddydrive_test_relay", "nim c --nimcache:$CACHE -o:$OUT relay/src/relay.nim")

proc readLineTimeout(sock: Socket, timeoutMs = 1000): string =
  sock.readLine(result, timeout = timeoutMs)

proc cryptoGenerichashRaw(hashOut: cptr, hashOutLen: csize_t, msg: cptr, msgLen: culonglong, key: cptr, keyLen: csize_t): cint {.importc: "crypto_generichash", dynlib: libsodium_fn.}

proc bytesToHex(data: string): string =
  result = newString(data.len * 2)
  const hexChars = "0123456789abcdef"
  for i, ch in data:
    let b = byte(ch)
    result[i * 2] = hexChars[int(b shr 4)]
    result[i * 2 + 1] = hexChars[int(b and 0x0f)]

proc powHashHex(payload: string): string =
  result = newString(32)
  let msgPtr = if payload.len == 0: nil else: cast[cptr](payload[0].unsafeAddr)
  let rc = cryptoGenerichashRaw(
    cast[cptr](result[0].addr),
    result.len.csize_t,
    msgPtr,
    payload.len.culonglong,
    nil,
    0
  )
  if rc != 0:
    return ""
  result = bytesToHex(result)

proc hasLeadingZeroBits(hashHex: string, requiredBits: int): bool =
  var bitsLeft = requiredBits
  for ch in hashHex:
    if bitsLeft <= 0:
      return true
    let nibble =
      if ch >= '0' and ch <= '9': int(ch) - int('0')
      else: int(toLowerAscii(ch)) - int('a') + 10
    if bitsLeft >= 4:
      if nibble != 0:
        return false
      bitsLeft -= 4
    else:
      return nibble < (1 shl (4 - bitsLeft))
  bitsLeft <= 0

proc solveRelayPow(token, nonce: string, difficultyBits: int): string =
  var counter = 0'u64
  while true:
    let attempt = $counter
    let hash = powHashHex(token & "\n" & nonce & "\n" & attempt)
    if hash.len == 0:
      return ""
    if hasLeadingZeroBits(hash, difficultyBits):
      return attempt
    inc counter

proc completePowHandshake(sock: Socket, token: string) =
  sock.send(token & "\n")
  let challenge = readLineTimeout(sock)
  check challenge.startsWith("POW ")
  let parts = challenge.splitWhitespace()
  check parts.len == 3
  let solution = solveRelayPow(token, parts[1], parseInt(parts[2]))
  sock.send("POW " & solution & "\n")

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
        stopProcessCleanly(relayProc)

      waitForTcpReady("127.0.0.1", port)

      let clientA = newSocket(buffered = true)
      let clientB = newSocket(buffered = true)
      defer:
        clientA.close()
        clientB.close()

      clientA.connect("127.0.0.1", Port(port))
      completePowHandshake(clientA, "shared-token")
      check readLineTimeout(clientA) == "WAIT"

      clientB.connect("127.0.0.1", Port(port))
      completePowHandshake(clientB, "shared-token")
      check readLineTimeout(clientB) == "OK"
      check readLineTimeout(clientA) == "OK"

      clientA.send("ping")
      check clientB.recv(4, timeout = 1000) == "ping"

      clientB.send("pong")
      check clientA.recv(4, timeout = 1000) == "pong"
