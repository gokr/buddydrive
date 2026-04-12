import std/[os, strutils, selectors, tables, sets, locks, nativesockets, times]

when defined(withKvStore):
  import kvstore
  import kvstore_api

const DefaultPort = 41722
const MaxTokenLen = 64
const BufferSize = 64 * 1024
const IdleTimeoutMs = 300000 # 5 minutes

var Whitelist: HashSet[string]

proc loadWhitelist() =
  let whitelistEnv = getEnv("BUDDYDRIVE_TOKENS", "")
  if whitelistEnv.len == 0:
    echo "WARNING: BUDDYDRIVE_TOKENS environment variable not set"
    echo "No tokens will be accepted!"
    Whitelist = initHashSet[string]()
    return
  
  Whitelist = initHashSet[string]()
  for token in whitelistEnv.split(','):
    let t = token.strip()
    if t.len > 0:
      Whitelist.incl(t)
  
  echo "Loaded ", Whitelist.len, " token(s)"

type
  ConnectionState = enum
    AwaitingToken,
    WaitingForPeer,
    Relaying
  
  ClientData = ref object
    token: string
    state: ConnectionState
    peerFd: int
    sendBuffer: string
    recvBuffer: string
    lastActivity: int64

  RelayServer = object
    selector: Selector[ClientData]
    waitingClients: Table[string, int]
    clientFds: HashSet[int]
    lock: Lock

proc newRelayServer(): RelayServer =
  result.selector = newSelector[ClientData]()
  result.waitingClients = initTable[string, int]()
  result.clientFds = initHashSet[int]()
  initLock(result.lock)

proc bytesToString(buf: openArray[char], n: int): string =
  result = newString(n)
  if n > 0:
    copyMem(result[0].addr, unsafeAddr buf[0], n)

proc closeClient(server: var RelayServer, fd: int) =
  var data = server.selector.getData(fd)
  if data != nil and data.peerFd != 0:
    var peerData = server.selector.getData(data.peerFd)
    if peerData != nil:
      peerData.peerFd = 0
      peerData.state = AwaitingToken
    server.selector.updateHandle(data.peerFd.SocketHandle, {Read})
  
  withLock server.lock:
    if data != nil and data.token.len > 0:
      if server.waitingClients.getOrDefault(data.token) == fd:
        server.waitingClients.del(data.token)
    server.clientFds.excl(fd)
  
  server.selector.unregister(fd.SocketHandle)
  close(fd.SocketHandle)

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
    
    data.lastActivity = (epochTime() * 1000).int64
    
    let peerData = server.selector.getData(data.peerFd)
    if peerData != nil:
      peerData.sendBuffer.add(bytesToString(buf, n))
      peerData.lastActivity = data.lastActivity
      server.selector.updateHandle(data.peerFd.SocketHandle, {Read, Write})
    break

proc handleClient(server: var RelayServer, fd: int, listenFd: SocketHandle) =
  if fd.SocketHandle == listenFd:
    var clientAddr: SockAddr
    var clientAddrLen = sizeof(clientAddr).SockLen
    let clientFd = accept(listenFd, addr clientAddr, addr clientAddrLen)
    
    if clientFd.int >= 0:
      setBlocking(clientFd, false)
      
      var clientData = ClientData()
      clientData.state = AwaitingToken
      clientData.peerFd = 0
      clientData.lastActivity = (epochTime() * 1000).int64
      
      server.selector.registerHandle(clientFd, {Read}, clientData)
      withLock server.lock:
        server.clientFds.incl(clientFd.int)
      echo "Client connected: fd=", clientFd.int
    return

  var data = server.selector.getData(fd)
  if data == nil:
    return
  
  data.lastActivity = (epochTime() * 1000).int64
  
  case data.state
  of AwaitingToken:
    var buf: array[MaxTokenLen + 2, char]
    let n = recv(fd.SocketHandle, addr buf[0], (MaxTokenLen + 1).cint, 0)
    if n <= 0:
      server.closeClient(fd)
      return
    
    data.recvBuffer.add(bytesToString(buf, n))
    
    let newlinePos = data.recvBuffer.find('\n')
    if newlinePos < 0:
      if data.recvBuffer.len > MaxTokenLen:
        server.closeClient(fd)
      return
    
    data.token = data.recvBuffer[0 ..< newlinePos].strip()
    data.recvBuffer = data.recvBuffer[newlinePos + 1 ..^ 1]
    data.state = WaitingForPeer
    
    if data.token notin Whitelist:
      echo "Rejecting invalid token: ", data.token
      server.closeClient(fd)
      return
    
    withLock server.lock:
      if data.token in server.waitingClients:
        let peerFd = server.waitingClients[data.token]
        server.waitingClients.del(data.token)
        
        var peerData = server.selector.getData(peerFd)
        if peerData != nil and peerData.state == WaitingForPeer:
          data.peerFd = peerFd
          peerData.peerFd = fd
          data.state = Relaying
          peerData.state = Relaying
          
          let okMsg = "OK\n"
          discard send(fd.SocketHandle, okMsg[0].unsafeAddr, 3, MSG_NOSIGNAL)
          discard send(peerFd.SocketHandle, okMsg[0].unsafeAddr, 3, MSG_NOSIGNAL)
          
          server.selector.updateHandle(fd.SocketHandle, {Read})
          server.selector.updateHandle(peerFd.SocketHandle, {Read})
          
          echo "Paired clients for token: ", data.token
      else:
        server.waitingClients[data.token] = fd
        echo "Waiting for peer with token: ", data.token
        let waitMsg = "WAIT\n"
        discard send(fd.SocketHandle, waitMsg[0].unsafeAddr, 5, MSG_NOSIGNAL)
  
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
      if data != nil and data.state in {WaitingForPeer, Relaying}:
        if now - data.lastActivity > IdleTimeoutMs:
          toClose.add(fd)
  for fd in toClose:
    echo "Closing idle client: fd=", fd
    server.closeClient(fd)

proc run(port: int) =
  loadWhitelist()
  
  echo "BuddyDrive Relay starting on port ", port
  if Whitelist.len > 0:
    echo "Allowed tokens:"
    for token in Whitelist:
      echo "  ", token
  else:
    echo "No tokens configured - all connections will be rejected"
  echo ""
  
  var server = newRelayServer()
  
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
  echo "Set BUDDYDRIVE_TOKENS env var with comma-separated tokens."
  echo "Idle timeout: ", IdleTimeoutMs div 1000, " seconds"
  echo ""
  
  var readyKeys: array[64, ReadyKey]
  var lastIdleCheck = (epochTime() * 1000).int64
  
  while true:
    let count = server.selector.selectInto(5000, readyKeys)
    let now = (epochTime() * 1000).int64
    
    if now - lastIdleCheck > 10000:
      checkIdleClients(server, now)
      lastIdleCheck = now
    
    for i in 0 ..< count:
      let key = readyKeys[i]
      let fd = key.fd.int
      if Read in key.events:
        if key.fd.int == listenFd.int:
          server.handleClient(listenFd.int, listenFd)
        else:
          server.handleClient(fd, listenFd)
      
      if Write in key.events:
        var data = server.selector.getData(fd)
        if data != nil and data.sendBuffer.len > 0:
          let n = send(fd.SocketHandle, addr data.sendBuffer[0], data.sendBuffer.len.cint, MSG_NOSIGNAL)
          if n <= 0:
            server.closeClient(fd)
          elif n < data.sendBuffer.len:
            data.sendBuffer = data.sendBuffer[n ..^ 1]
          else:
            data.sendBuffer = ""
            server.selector.updateHandle(fd.SocketHandle, {Read})

when isMainModule:
  var port = DefaultPort
  var kvPort = 8080
  
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
        let kv = initKvStore(kvConnStr)
        echo "KV store initialized"
        
        if paramCount() > 1:
          try:
            kvPort = parseInt(paramStr(2))
          except:
            discard
        
        echo "KV API port: ", kvPort
      except Exception as e:
        echo "Failed to initialize KV store: ", e.msg
        echo "Running relay-only mode"
    else:
      echo "TIDB_CONNECTION_STRING not set, running relay-only mode"
  
  run(port)
