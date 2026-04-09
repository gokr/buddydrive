#!/bin/bash
# Test P2P peer discovery and connection

set -e

echo "=============================================================="
echo "Testing P2P Peer Discovery and Connection"
echo "=============================================================="
echo ""

# Setup
DIR1="/tmp/buddydrive_peer_test1"
DIR2="/tmp/buddydrive_peer_test2"
LOG1="$DIR1/node.log"
LOG2="$DIR2/node.log"

rm -rf "$DIR1" "$DIR2"
mkdir -p "$DIR1" "$DIR2"

# Initialize nodes
echo "Initializing Node 1..."
cd /home/gokr/tankfeud/buddydrive
HOME="$DIR1" ./bin/buddydrive init > /dev/null 2>&1
ID1=$(grep "^id = " "$DIR1/.buddydrive/config.toml" | cut -d'"' -f2)

echo "Initializing Node 2..."
HOME="$DIR2" ./bin/buddydrive init > /dev/null 2>&1
ID2=$(grep "^id = " "$DIR2/.buddydrive/config.toml" | cut -d'"' -f2)

echo ""
echo "Buddy IDs:"
echo "  Node 1: $ID1"
echo "  Node 2: $ID2"
echo ""

# Start both nodes in background
echo "Starting Node 1..."
HOME="$DIR1" timeout 15 ./bin/buddydrive start > "$LOG1" 2>&1 &
PID1=$!
echo "  PID: $PID1"

sleep 2

echo "Starting Node 2..."
HOME="$DIR2" timeout 13 ./bin/buddydrive start > "$LOG2" 2>&1 &
PID2=$!
echo "  PID: $PID2"

echo ""
echo "Nodes running. Waiting 5 seconds for DHT..."
sleep 5

echo ""
echo "=== Node 1 Log ==="
grep -E "Peer ID|Address|DHT|Announc" "$LOG1" | head -10

echo ""
echo "=== Node 2 Log ==="
grep -E "Peer ID|Address|DHT|Announc" "$LOG2" | head -10

echo ""
echo "Checking for DHT protocol..."
if grep -q "/ipfs/kad/1.0.0" "$LOG1"; then
  echo "✓ Node 1 has DHT protocol"
fi
if grep -q "/ipfs/kad/1.0.0" "$LOG2"; then
  echo "✓ Node 2 has DHT protocol"
fi

echo ""
echo "Waiting for nodes to finish..."
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true

echo ""
echo "Test complete!"
echo ""
echo "Full logs:"
echo "  Node 1: $LOG1"
echo "  Node 2: $LOG2"
