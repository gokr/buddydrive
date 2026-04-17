import std/[os, strutils, selectors, tables, sets, locks, nativesockets, times, random]
import libsodium/sodium
import geoip_policy

when defined(withKvStore):
  import kvstore
  import kvstore_api
  import std/typedthreads

when defined(withKvStore):
  var kvStoreRef: KvStore
  var kvApiPort: int

  proc kvApiThread {.thread.} =
    {.cast(gcsafe).}:
      runKvApi(kvStoreRef, kvApiPort)

const
  DefaultPort = 41722
  MaxTokenLen = 64
  MaxProofLineLen = 96
  BufferSize = 64 * 1024
  IdleTimeoutMs = 300000
  WaitingTimeoutMs = 60000
  ProofTimeoutMs = 30000
  MaxClients = 256
  MaxWaitingClients = 128
  MaxPendingBufferBytes = 256 * 1024
  MaxSessionBytes = 64 * 1024 * 1024
  MaxSessionDurationMs = 30 * 60 * 1000
  DefaultPowDifficultyBits = 16

type
  ConnectionState = enum
    AwaitingToken,
    AwaitingProof,
    WaitingForPeer,
    Relaying

  ClientData = ref object
    token: string
    state: ConnectionState
    peerFd: int
    sendBuffer: string
    recvBuffer: string
    proofNonce: string
    proofIssuedAt: int64
    relayedBytes: int64
    relayingStartedAt: int64
    lastActivity: int64

  RelayServer = object
    selector: Selector[ClientData]
    waitingClients: Table[string, int]
    clientFds: HashSet[int]
    lock: Lock
    powDifficultyBits: int
    geoPolicyEnabled: bool

proc nowMs(): int64 =
  (epochTime() * 1000).int64

proc clampPowDifficulty(bits: int): int =
  min(max(bits, 8), 24)

proc relayPowDifficultyBits(): int =
  try:
    clampPowDifficulty(parseInt(getEnv("BUDDYDRIVE_RELAY_POW_BITS", $DefaultPowDifficultyBits)))
  except ValueError:
    DefaultPowDifficultyBits

proc newRelayServer(powDifficultyBits: int, geoPolicyEnabled: bool): RelayServer =
  result.selector = newSelector[ClientData]()
  result.waitingClients = initTable[string, int]()
  result.clientFds = initHashSet[int]()
  result.powDifficultyBits = powDifficultyBits
  result.geoPolicyEnabled = geoPolicyEnabled
  initLock(result.lock)

proc bytesToString(buf: openArray[char], n: int): string =
  result = newString(n)
  if n > 0:
    copyMem(result[0].addr, unsafeAddr buf[0], n)

proc randomHex(len: int): string =
  const hexChars = "0123456789abcdef"
  result = newString(len)
  for i in 0 ..< len:
    result[i] = hexChars[rand(hexChars.high)]

proc cryptoGenerichashRaw(hashOut: cptr, hashOutLen: csize_t, msg: cptr, msgLen: culonglong, key: cptr, keyLen: csize_t): cint {.importc: "crypto_generichash", dynlib: sodium.libsodium_fn.}

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

proc extractLine(buffer: var string): tuple[found: bool, line: string] =
  let newlinePos = buffer.find('\n')
  if newlinePos < 0:
    return

  result.found = true
  result.line = buffer[0 ..< newlinePos].strip()
  if newlinePos + 1 < buffer.len:
    buffer = buffer[newlinePos + 1 ..^ 1]
  else:
    buffer = ""

proc isValidRelayToken(token: string): bool =
  if token.len == 0 or token.len > MaxTokenLen:
    return false
  for ch in token:
    if ch notin {'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.'}:
      return false
  true

proc generatePowNonce(fd: int): string =
  discard fd
  randomHex(32)

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

proc verifyPow(token, nonce, counter: string, difficultyBits: int): bool =
  let hash = powHashHex(token & "\n" & nonce & "\n" & counter)
  hash.len > 0 and hasLeadingZeroBits(hash, difficultyBits)

proc closeClient(server: var RelayServer, fd: int, closePeer = true) =
  let data = server.selector.getData(fd)
  if data == nil:
    return

  let peerFd = data.peerFd
  data.peerFd = 0
  if closePeer and peerFd != 0:
    server.closeClient(peerFd, false)

  withLock server.lock:
    if data.token.len > 0 and server.waitingClients.getOrDefault(data.token) == fd:
      server.waitingClients.del(data.token)
    server.clientFds.excl(fd)

  server.selector.unregister(fd.SocketHandle)
  close(fd.SocketHandle)

proc pairOrQueueClient(server: var RelayServer, fd: int, data: ClientData) =
  var shouldBusyClose = false
  withLock server.lock:
    if data.token in server.waitingClients:
      let peerFd = server.waitingClients[data.token]
      server.waitingClients.del(data.token)

      let peerData = server.selector.getData(peerFd)
      if peerData != nil and peerData.state == WaitingForPeer:
        let startedAt = nowMs()
        data.peerFd = peerFd
        peerData.peerFd = fd
        data.state = Relaying
        peerData.state = Relaying
        data.relayingStartedAt = startedAt
        peerData.relayingStartedAt = startedAt
        data.relayedBytes = 0
        peerData.relayedBytes = 0

        let okMsg = "OK\n"
        discard send(fd.SocketHandle, okMsg[0].unsafeAddr, okMsg.len.cint, MSG_NOSIGNAL)
        discard send(peerFd.SocketHandle, okMsg[0].unsafeAddr, okMsg.len.cint, MSG_NOSIGNAL)
        server.selector.updateHandle(fd.SocketHandle, {Read})
        server.selector.updateHandle(peerFd.SocketHandle, {Read})
        echo "Paired clients for token: ", data.token
        return

    if server.waitingClients.len >= MaxWaitingClients:
      shouldBusyClose = true
    else:
      server.waitingClients[data.token] = fd
      data.state = WaitingForPeer
      let waitMsg = "WAIT\n"
      discard send(fd.SocketHandle, waitMsg[0].unsafeAddr, waitMsg.len.cint, MSG_NOSIGNAL)
      echo "Waiting for peer with token: ", data.token

  if shouldBusyClose:
    let busyMsg = "BUSY\n"
    discard send(fd.SocketHandle, busyMsg[0].unsafeAddr, busyMsg.len.cint, MSG_NOSIGNAL)
    server.closeClient(fd)

proc relayData(server: var RelayServer, fd: int, data: ClientData) =
  if data.sendBuffer.len > 0:
    let n = send(fd.SocketHandle, addr data.sendBuffer[0], data.sendBuffer.len.cint, MSG_NOSIGNAL)
    if n <= 0:
      server.closeClient(fd)
      return
    if n < data.sendBuffer.len:
      data.sendBuffer = data.sendBuffer[n ..^ 1]
      return
    data.sendBuffer = ""

  while true:
    var buf: array[BufferSize, char]
    let n = recv(fd.SocketHandle, addr buf[0], BufferSize.cint, 0)
    if n <= 0:
      if n == 0:
        server.closeClient(fd)
      return

    let now = nowMs()
    data.lastActivity = now
    data.relayedBytes += n.int64

    let peerData = server.selector.getData(data.peerFd)
    if peerData != nil:
      if data.relayedBytes + peerData.relayedBytes > MaxSessionBytes or now - data.relayingStartedAt > MaxSessionDurationMs:
        server.closeClient(data.peerFd)
        server.closeClient(fd)
        return

      if peerData.sendBuffer.len + n > MaxPendingBufferBytes:
        server.closeClient(data.peerFd)
        server.closeClient(fd)
        return

      peerData.sendBuffer.add(bytesToString(buf, n))
      peerData.lastActivity = now
      server.selector.updateHandle(data.peerFd.SocketHandle, {Read, Write})
    break

proc handleClient(server: var RelayServer, fd: int, listenFd: SocketHandle) =
  if fd.SocketHandle == listenFd:
    var clientAddr: SockAddr
    var clientAddrLen = sizeof(clientAddr).SockLen
    let clientFd = accept(listenFd, addr clientAddr, addr clientAddrLen)

    if clientFd.int >= 0:
      let clientIp = try:
        getAddrString(addr clientAddr)
      except CatchableError:
        ""

      if not allowEuGeoAccess(clientIp, server.geoPolicyEnabled):
        echo "Rejected non-EU relay client: ", clientIp
        close(clientFd)
        return

      var shouldReject = false
      withLock server.lock:
        shouldReject = server.clientFds.len >= MaxClients

      if shouldReject:
        close(clientFd)
        return

      setBlocking(clientFd, false)

      let clientData = ClientData(
        state: AwaitingToken,
        peerFd: 0,
        lastActivity: nowMs(),
        proofIssuedAt: 0,
        relayedBytes: 0,
        relayingStartedAt: 0
      )

      server.selector.registerHandle(clientFd, {Read}, clientData)
      withLock server.lock:
        server.clientFds.incl(clientFd.int)
      echo "Client connected: fd=", clientFd.int
    return

  let data = server.selector.getData(fd)
  if data == nil:
    return

  data.lastActivity = nowMs()

  case data.state
  of AwaitingToken:
    var buf: array[MaxTokenLen + 2, char]
    let n = recv(fd.SocketHandle, addr buf[0], (MaxTokenLen + 1).cint, 0)
    if n <= 0:
      server.closeClient(fd)
      return

    data.recvBuffer.add(bytesToString(buf, n))
    let line = extractLine(data.recvBuffer)
    if not line.found:
      if data.recvBuffer.len > MaxTokenLen:
        server.closeClient(fd)
      return

    if not isValidRelayToken(line.line):
      server.closeClient(fd)
      return

    data.token = line.line
    data.state = AwaitingProof
    data.proofNonce = generatePowNonce(fd)
    data.proofIssuedAt = nowMs()

    let challenge = "POW " & data.proofNonce & " " & $server.powDifficultyBits & "\n"
    discard send(fd.SocketHandle, challenge[0].unsafeAddr, challenge.len.cint, MSG_NOSIGNAL)

  of AwaitingProof:
    var buf: array[MaxProofLineLen + 2, char]
    let n = recv(fd.SocketHandle, addr buf[0], (MaxProofLineLen + 1).cint, 0)
    if n <= 0:
      server.closeClient(fd)
      return

    data.recvBuffer.add(bytesToString(buf, n))
    let line = extractLine(data.recvBuffer)
    if not line.found:
      if data.recvBuffer.len > MaxProofLineLen:
        server.closeClient(fd)
      return

    if nowMs() - data.proofIssuedAt > ProofTimeoutMs:
      server.closeClient(fd)
      return

    let parts = line.line.splitWhitespace()
    if parts.len != 2 or parts[0] != "POW" or not verifyPow(data.token, data.proofNonce, parts[1], server.powDifficultyBits):
      server.closeClient(fd)
      return

    pairOrQueueClient(server, fd, data)

  of WaitingForPeer:
    var buf: array[1024, char]
    let n = recv(fd.SocketHandle, addr buf[0], 1024.cint, 0)
    if n <= 0:
      server.closeClient(fd)

  of Relaying:
    relayData(server, fd, data)

proc checkIdleClients(server: var RelayServer, now: int64) =
  var toClose: seq[int] = @[]
  withLock server.lock:
    for fd in server.clientFds:
      let data = server.selector.getData(fd)
      if data == nil:
        continue

      case data.state
      of AwaitingProof:
        if now - data.proofIssuedAt > ProofTimeoutMs:
          toClose.add(fd)
      of WaitingForPeer:
        if now - data.lastActivity > WaitingTimeoutMs:
          toClose.add(fd)
      of Relaying:
        if now - data.lastActivity > IdleTimeoutMs or now - data.relayingStartedAt > MaxSessionDurationMs:
          toClose.add(fd)
      of AwaitingToken:
        if now - data.lastActivity > ProofTimeoutMs:
          toClose.add(fd)

  for fd in toClose:
    echo "Closing idle client: fd=", fd
    server.closeClient(fd)

proc run(port: int) =
  randomize()
  let powDifficultyBits = relayPowDifficultyBits()
  let relayGeoRangePath = getEnv("BUDDYDRIVE_RELAY_EU_RANGES_FILE", getEnv("BUDDYDRIVE_KV_EU_RANGES_FILE", "")).strip()
  let relayGeoStatus = configureEuGeoPolicy(getEnv("BUDDYDRIVE_RELAY_EU_ONLY", "") == "1", relayGeoRangePath, "relay")
  echo "BuddyDrive Relay starting on port ", port
  echo "Proof-of-work difficulty: ", powDifficultyBits, " bits"
  if relayGeoStatus.message.len > 0:
    echo relayGeoStatus.message
  echo ""

  var server = newRelayServer(powDifficultyBits, relayGeoStatus.active)

  let listenFd = createNativeSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
  if listenFd.int < 0:
    echo "Failed to create socket"
    quit(1)

  setSockOptInt(listenFd, SOL_SOCKET, SO_REUSEADDR, 1)
  setBlocking(listenFd, false)

  var addrInfo: Sockaddr_in
  addrInfo.sin_family = AF_INET.uint16
  addrInfo.sin_port = htons(port.uint16)
  addrInfo.sin_addr.s_addr = INADDR_ANY

  if bindAddr(listenFd, cast[ptr SockAddr](addr addrInfo), sizeof(addrInfo).SockLen) < 0:
    echo "Failed to bind to port ", port
    quit(1)

  if listen(listenFd, 128) < 0:
    echo "Failed to listen"
    quit(1)

  server.selector.registerHandle(listenFd, {Read}, nil)

  echo "Listening for connections..."
  echo "Waiting timeout: ", WaitingTimeoutMs div 1000, " seconds"
  echo "Idle timeout: ", IdleTimeoutMs div 1000, " seconds"
  echo ""

  var readyKeys: array[64, ReadyKey]
  var lastIdleCheck = nowMs()

  while true:
    let count = server.selector.selectInto(5000, readyKeys)
    let now = nowMs()

    if now - lastIdleCheck > 10000:
      checkIdleClients(server, now)
      lastIdleCheck = now

    for i in 0 ..< count:
      let key = readyKeys[i]
      let readyFd = key.fd.int
      if Read in key.events:
        if readyFd == listenFd.int:
          server.handleClient(listenFd.int, listenFd)
        else:
          server.handleClient(readyFd, listenFd)

      if Write in key.events:
        let data = server.selector.getData(readyFd)
        if data != nil and data.sendBuffer.len > 0:
          let n = send(readyFd.SocketHandle, addr data.sendBuffer[0], data.sendBuffer.len.cint, MSG_NOSIGNAL)
          if n <= 0:
            server.closeClient(readyFd)
          elif n < data.sendBuffer.len:
            data.sendBuffer = data.sendBuffer[n ..^ 1]
          else:
            data.sendBuffer = ""
            server.selector.updateHandle(readyFd.SocketHandle, {Read})

when isMainModule:
  var port = DefaultPort

  if paramCount() > 0:
    try:
      port = parseInt(paramStr(1))
    except:
      discard

  when defined(withKvStore):
    let kvConnStr = getEnv("TIDB_CONNECTION_STRING", "")
    if kvConnStr.len > 0:
      echo "Starting KV store with TiDB..."
      try:
        kvStoreRef = initKvStore(kvConnStr)
        echo "KV store initialized"

        if paramCount() > 1:
          try:
            kvApiPort = parseInt(paramStr(2))
          except:
            discard

        echo "KV API port: ", kvApiPort

        var kvThread: Thread[void]
        createThread(kvThread, kvApiThread)
        echo "KV API thread started"
      except Exception as e:
        echo "Failed to initialize KV store: ", e.msg
        echo "Running relay-only mode"
    else:
      echo "TIDB_CONNECTION_STRING not set, running relay-only mode"

  run(port)
