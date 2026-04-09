import std/os
import std/times
import std/strutils
import chronos

proc testTwoNodes() {.async.} =
  echo "=" & "=".repeat(60)
  echo "Testing Two Local BuddyDrive Instances"
  echo "=" & "=".repeat(60)
  echo ""
  
  let dir1 = "/tmp/buddydrive_test1"
  let dir2 = "/tmp/buddydrive_test2"
  
  # Clean up old test directories
  removeDir(dir1)
  removeDir(dir2)
  createDir(dir1)
  createDir(dir2)
  
  echo "Test setup complete"
  echo ""
  
  # Start two buddydrive processes
  echo "Starting Node 1 in background..."
  let p1 = startProcess(
    binary = "./bin/buddydrive",
    args = @["start"],
    workingDir = "/home/gokr/tankfeud/buddydrive",
    env = newStringTable({"HOME": dir1})
  )
  
  await sleepAsync(chronos.seconds(2))
  
  echo "Starting Node 2 in background..."
  let p2 = startProcess(
    binary = "./bin/buddydrive",
    args = @["start"],
    workingDir = "/home/gokr/tankfeud/buddydrive",
    env = newStringTable({"HOME": dir2})
  )
  
  echo ""
  echo "Both nodes starting..."
  echo "Waiting 5 seconds for DHT discovery..."
  
  await sleepAsync(chronos.seconds(5))
  
  echo ""
  echo "Stopping nodes..."
  p1.terminate()
  p2.terminate()
  
  echo "Test complete!"
  echo ""
  echo "Cleanup:"
  echo "  rm -rf ", dir1
  echo "  rm -rf ", dir2

when isMainModule:
  waitFor testTwoNodes()
