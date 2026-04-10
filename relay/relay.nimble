version = "0.1.0"
author = "Göran Krampe"
description = "Simple TCP relay for BuddyDrive P2P sync"
license = "MIT"
srcDir = "src"
binDir = "bin"
bin = @["relay"]

requires "nim >= 2.2.0"

task build, "Build release binary":
  exec "nim c -d:release src/relay.nim"
