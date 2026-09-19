## Minimal in-process stand-in for the BuddyDrive TCP relay.
##
## Speaks the client half of the protocol in p2p/rawrelay.nim: a peer sends its
## token as a line, gets "WAIT" until a second peer arrives with the same token,
## then both get "OK" and the two streams are spliced. Proof-of-work is not
## challenged, which the client treats as optional.
##
## The real relay lives in the buddydrive-relay repository; this exists so the
## integration tests can exercise real sync without an external service.

import std/tables
import chronos

const
  TestRelayPort* = 41722
  MaxTokenLen = 64

type
  TestRelay* = ref object
    server: StreamServer
    waiting: Table[string, StreamTransport]
    port*: int

proc readTokenLine(transp: StreamTransport): Future[string] {.async.} =
  var line = ""
  while line.len < MaxTokenLen:
    var ch: char
    let n = await transp.readOnce(addr ch, 1)
    if n == 0:
      return ""
    if ch == '\n':
      return line
    if ch != '\r':
      line.add(ch)
  ""

proc pump(src: StreamTransport, dst: StreamTransport) {.async.} =
  var buf = newSeq[byte](4096)
  try:
    while true:
      let n = await src.readOnce(addr buf[0], buf.len)
      if n == 0:
        break
      discard await dst.write(addr buf[0], n)
  except CatchableError:
    discard
  finally:
    await src.closeWait()
    await dst.closeWait()

proc splice(a: StreamTransport, b: StreamTransport) {.async.} =
  await allFutures(pump(a, b), pump(b, a))

proc handleClient(relay: TestRelay, transp: StreamTransport) {.async.} =
  let token = await readTokenLine(transp)
  if token.len == 0:
    await transp.closeWait()
    return

  let pending = relay.waiting.getOrDefault(token)
  if pending != nil and not pending.closed():
    relay.waiting.del(token)
    discard await pending.write("OK\n")
    discard await transp.write("OK\n")
    asyncSpawn splice(pending, transp)
    return

  relay.waiting[token] = transp
  discard await transp.write("WAIT\n")

proc startTestRelay*(port: int = TestRelayPort): TestRelay =
  ## Starts a relay on 127.0.0.1:port. Region "local" resolves here.
  let relay = TestRelay(waiting: initTable[string, StreamTransport](), port: port)

  proc onConnection(server: StreamServer, transp: StreamTransport) {.async: (raises: []).} =
    try:
      await relay.handleClient(transp)
    except CatchableError:
      try:
        await transp.closeWait()
      except CatchableError:
        discard

  relay.server = createStreamServer(initTAddress("127.0.0.1", port), onConnection, {ReuseAddr})
  relay.server.start()
  relay

proc stop*(relay: TestRelay) {.async.} =
  for _, transp in relay.waiting:
    if not transp.closed():
      await transp.closeWait()
  relay.waiting.clear()
  relay.server.stop()
  await relay.server.closeWait()
