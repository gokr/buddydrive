import std/[httpclient, net, os, osproc, strutils, times]

proc repoRoot*(): string =
  currentSourcePath().parentDir().parentDir().parentDir()

proc freePort*(): int =
  let sock = newSocket()
  defer: sock.close()
  sock.bindAddr(Port(0))
  let (_, port) = sock.getLocalAddr()
  int(port)

proc ensureBuiltBinary*(cachedPath: var string, outputPrefix, buildCommandTemplate: string): string =
  if cachedPath.len == 0:
    let unique = $getTime().toUnix()
    cachedPath = getTempDir() / (outputPrefix & "_" & unique)
    let nimCachePath = getTempDir() / (outputPrefix & "_nimcache_" & unique)
    let command = buildCommandTemplate
      .replace("$OUT", quoteShell(cachedPath))
      .replace("$CACHE", quoteShell(nimCachePath))
    let build = execCmdEx(command, workingDir = repoRoot())
    doAssert build.exitCode == 0, build.output
  cachedPath

proc waitForTcpReady*(host: string, port: int, retries = 40, delayMs = 100) =
  for _ in 0 ..< retries:
    try:
      let sock = newSocket(buffered = true)
      defer: sock.close()
      sock.connect(host, Port(port))
      return
    except OSError:
      sleep(delayMs)
  doAssert false, "TCP service did not become ready"

proc waitForHttpReady*(url: string, retries = 50, delayMs = 100) =
  let client = newHttpClient()
  defer: client.close()
  for _ in 0 ..< retries:
    try:
      let resp = client.get(url)
      if resp.code == Http200:
        return
    except CatchableError:
      discard
    sleep(delayMs)
  doAssert false, "HTTP service did not become ready"

proc stopProcessCleanly*(process: Process) =
  if process == nil:
    return
  if peekExitCode(process) == -1:
    terminate(process)
    discard waitForExit(process, 5000)
  close(process)
