version = "0.1.0"
author = "Göran Krampe"
description = "Simple TCP relay for BuddyDrive P2P sync with KV config store"
license = "MIT"
srcDir = "src"
binDir = "bin"
bin = @["relay"]

requires "nim >= 2.2.0"
requires "db_connector"
requires "mummy"

task build, "Build release binary":
  exec "nim c -d:release src/relay.nim"
