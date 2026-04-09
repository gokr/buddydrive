version = "0.1.0"
author = "Göran Krampe"
description = "P2P encrypted folder sync with buddies"
license = "MIT"
srcDir = "src"
binDir = "bin"
bin = @["buddydrive"]

requires "nim >= 2.2.8"
requires "libp2p >= 1.15"
requires "libsodium >= 0.7"
requires "parsetoml"
requires "results"
requires "uuids"
requires "db_connector"

task test, "Run tests":
  exec "nimble c -r tests/harness/test_peer_discovery.nim"

task build, "Build release":
  exec "nim c -d:release src/buddydrive.nim"
