
# BuddyDrive Local Testing Tutorial

This tutorial shows how to test BuddyDrive on a single machine with two instances syncing a folder.

## Prerequisites

```bash
# Build the project
cd /home/gokr/tankfeud/buddydrive
nimble build
```

## Step 1: Create Two Test Directories

```bash
# Create test directories for each instance
mkdir -p /tmp/buddy1/sync-folder
mkdir -p /tmp/buddy2/sync-folder

# Create a test file in buddy1's folder
echo "Hello from Buddy 1!" > /tmp/buddy1/sync-folder/test.txt
```

## Step 2: Initialize Both Instances

```bash
# Initialize Buddy 1
HOME=/tmp/buddy1 ./bin/buddydrive init

# Initialize Buddy 2
HOME=/tmp/buddy2 ./bin/buddydrive init
```

## Step 3: Add Folders to Each Instance

```bash
# Add sync folder to Buddy 1
HOME=/tmp/buddy1 ./bin/buddydrive add-folder /tmp/buddy1/sync-folder --name mydocs

# Add sync folder to Buddy 2
HOME=/tmp/buddy2 ./bin/buddydrive add-folder /tmp/buddy2/sync-folder --name mydocs
```

## Step 4: Pair the Buddies

```bash
# Get Buddy 1's ID
HOME=/tmp/buddy1 ./bin/buddydrive config
# Note the "Buddy ID" line, e.g., "Buddy ID: abc123..."

# Get Buddy 2's ID
HOME=/tmp/buddy2 ./bin/buddydrive config
# Note the "Buddy ID" line, e.g., "Buddy ID: def456..."
```

Now add each other as buddies:

```bash
# Buddy 1 adds Buddy 2 (use the actual UUID from above)
HOME=/tmp/buddy1 ./bin/buddydrive add-buddy --id <BUDDY2_UUID> --code TEST

# Buddy 2 adds Buddy 1 (use the actual UUID from above)
HOME=/tmp/buddy2 ./bin/buddydrive add-buddy --id <BUDDY1_UUID> --code TEST
```

## Step 5: Start Both Daemons

Open two terminal windows:

**Terminal 1 (Buddy 1):**
```bash
HOME=/tmp/buddy1 ./bin/buddydrive start
```

**Terminal 2 (Buddy 2):**
```bash
HOME=/tmp/buddy2 ./bin/buddydrive start
```

You should see output like:
```
Starting daemon...
Node started with Peer ID: 16Uiu2HAm...
Listening on: /ip4/127.0.0.1/tcp/XXXXX
DHT discovery started
Announced buddy ID on DHT: <your-uuid>
```

## Step 6: Verify Sync

```bash
# Check that test.txt from Buddy 1 synced to Buddy 2
ls -la /tmp/buddy2/sync-folder/

# Create a file in Buddy 2's folder
echo "Hello from Buddy 2!" > /tmp/buddy2/sync-folder/reply.txt

# Wait a few seconds, then check Buddy 1's folder
ls -la /tmp/buddy1/sync-folder/
```

## Step 7: Check Status

```bash
# Check Buddy 1's status
HOME=/tmp/buddy1 ./bin/buddydrive status

# Check Buddy 2's status
HOME=/tmp/buddy2 ./bin/buddydrive status
```

## Cleanup

```bash
# Stop daemons with Ctrl+C in each terminal
# Then remove test directories
rm -rf /tmp/buddy1 /tmp/buddy2
```

## Troubleshooting

1. **Port conflicts**: If both instances try to use the same port, the second one will fail. Each instance picks a random port automatically.

2. **DHT discovery**: For local testing, DHT discovery won't work without bootstrap nodes. The instances connect directly when they know each other's addresses.

3. **Firewall**: For production use across the internet, ensure the TCP port is accessible.

## What's Happening Under the Hood

1. **libp2p** creates a P2P node with a unique Peer ID
2. **DHT** announces the buddy ID so others can find you
3. **Pairing** verifies both sides have each other in their buddy list
4. **Sync** compares file lists and transfers needed files in chunks
5. **Encryption** (when enabled) encrypts file contents and filenames

## Next Steps

- Try syncing different file types
- Test with larger files
- Enable encryption with `--no-encrypt` flag removed
- Run over the internet with a friend
