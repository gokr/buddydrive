#!/bin/bash
# Test harness for running two BuddyDrive instances locally

set -e

echo "=============================================================="
echo "Testing Two Local BuddyDrive Instances"
echo "=============================================================="
echo ""

# Setup test directories
DIR1="/tmp/buddydrive_test1"
DIR2="/tmp/buddydrive_test2"

rm -rf "$DIR1" "$DIR2"
mkdir -p "$DIR1" "$DIR2"

echo "Test setup complete"
echo "  Node 1 config: $DIR1/.buddydrive"
echo "  Node 2 config: $DIR2/.buddydrive"
echo ""

# Initialize both nodes
echo "Initializing Node 1..."
HOME="$DIR1" ./bin/buddydrive init 2>&1 | grep -E "Generated|Buddy ID"
ID1=$(grep "Buddy ID:" "$DIR1/.buddydrive/config.toml" 2>/dev/null | cut -d'"' -f2 || echo "")
echo ""

echo "Initializing Node 2..."
HOME="$DIR2" ./bin/buddydrive init 2>&1 | grep -E "Generated|Buddy ID"
ID2=$(grep "Buddy ID:" "$DIR2/.buddydrive/config.toml" 2>/dev/null | cut -d'"' -f2 || echo "")
echo ""

echo "Node identities:"
echo "  Node 1: $ID1"
echo "  Node 2: $ID2"
echo ""

# Add test folders
echo "Adding test folders..."
mkdir -p "$DIR1/sync_folder"
mkdir -p "$DIR2/sync_folder"
echo "Hello from node 1!" > "$DIR1/sync_folder/test.txt"

HOME="$DIR1" ./bin/buddydrive add-folder "$DIR1/sync_folder" --name test 2>&1 | grep -E "Folder added|Path"
HOME="$DIR2" ./bin/buddydrive add-folder "$DIR2/sync_folder" --name test 2>&1 | grep -E "Folder added|Path"
echo ""

# Pair buddies
echo "Pairing buddies..."
CODE1=$(HOME="$DIR1" ./bin/buddydrive add-buddy --generate-code 2>&1 | grep "Pairing Code:" | awk '{print $3}')
echo "Node 1 pairing code: $CODE1"

HOME="$DIR2" ./bin/buddydrive add-buddy --id "$ID1" --code "$CODE1" 2>&1 | grep -E "Buddy added"
echo ""

# Start both nodes in background
echo "Starting both nodes (running for 10 seconds)..."
HOME="$DIR1" timeout 10 ./bin/buddydrive start 2>&1 | sed 's/^/[Node1] /' &
PID1=$!

sleep 2

HOME="$DIR2" timeout 8 ./bin/buddydrive start 2>&1 | sed 's/^/[Node2] /' &
PID2=$!

echo ""
echo "Nodes running..."
echo "  PID 1: $PID1"
echo "  PID 2: $PID2"
echo ""

# Wait for both to finish
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true

echo ""
echo "Test complete!"
echo ""
echo "Cleanup:"
echo "  rm -rf $DIR1 $DIR2"
