# BuddyDrive Local Testing Tutorial

This tutorial shows how to smoke-test BuddyDrive on a single machine with two isolated instances.

## Key Concepts

- **Buddy ID** - A UUID (e.g., `fcd6295c-a912-44d4-a27b-ad898795207d`) that identifies a BuddyDrive instance
- **Buddy Name** - A human-readable name like `purple-banana` generated from adjective-noun pairs
- **Peer ID** - A libp2p identifier (e.g., `16Uiu2HAm...`) used for P2P networking
- **Relay Token** - A shared secret that two buddies use to connect through a relay server

Important: a full end-to-end sync does not currently work over loopback or private-only addresses. BuddyDrive will only dial buddies when it discovers a public TCP address, or when relay fallback is configured. The steps below validate initialization, folder setup, pairing, and daemon startup on one machine. For a real file transfer test, use two machines with public reachability or configure relay fallback.

## Prerequisites

```bash
cd /home/gokr/tankfeud/buddydrive
nimble build
```

## Step 1: Create Two Isolated Test Homes

```bash
mkdir -p /tmp/buddy1/Documents
mkdir -p /tmp/buddy2/Documents

printf 'Hello from Buddy 1!\n' > /tmp/buddy1/Documents/test.txt
```

## Step 2: Initialize Both Instances

```bash
HOME=/tmp/buddy1 ./bin/buddydrive init
HOME=/tmp/buddy2 ./bin/buddydrive init
```

Each instance gets its own config under `/tmp/buddyX/.buddydrive/config.toml`.

## Step 3: Give the Second Instance a Different P2P Port

Both instances default to `listen_port = 41721`, so the second one must be changed before you start them together.

Open `/tmp/buddy2/.buddydrive/config.toml` and change:

```toml
listen_port = 41721
```

to:

```toml
listen_port = 41722
```

## Step 4: Add a Folder to Each Instance

```bash
HOME=/tmp/buddy1 ./bin/buddydrive add-folder /tmp/buddy1/Documents --name docs
HOME=/tmp/buddy2 ./bin/buddydrive add-folder /tmp/buddy2/Documents --name docs
```

## Step 5: Collect Both Buddy IDs

```bash
HOME=/tmp/buddy1 ./bin/buddydrive config
HOME=/tmp/buddy2 ./bin/buddydrive config
```

Copy the `ID:` value from each command.

## Step 6: Pair Both Sides

BuddyDrive currently accepts a buddy ID and pairing code, then stores the buddy entry locally, so for testing you should add each side to the other.

```bash
HOME=/tmp/buddy1 ./bin/buddydrive add-buddy --id <BUDDY2_UUID> --code TEST-0001
HOME=/tmp/buddy2 ./bin/buddydrive add-buddy --id <BUDDY1_UUID> --code TEST-0002
```

## Step 7: Verify the Saved Configuration

```bash
HOME=/tmp/buddy1 ./bin/buddydrive list-folders
HOME=/tmp/buddy1 ./bin/buddydrive list-buddies

HOME=/tmp/buddy2 ./bin/buddydrive list-folders
HOME=/tmp/buddy2 ./bin/buddydrive list-buddies
```

At this point you should see one folder and one buddy configured on each side.

## Step 8: Start Both Daemons

Use a different control API port for each process so both can run on the same machine.

**Terminal 1 (Buddy 1):**

```bash
HOME=/tmp/buddy1 ./bin/buddydrive start --port 17521
```

**Terminal 2 (Buddy 2):**

```bash
HOME=/tmp/buddy2 ./bin/buddydrive start --port 17522
```

Expected startup output includes lines like:

```text
Starting BuddyDrive daemon...
Starting daemon...
Node started with Peer ID: 16Uiu2HAm...
Listening on: /ip4/0.0.0.0/tcp/41721
DHT discovery started
Control server started on port 17521
BuddyDrive is running!
```

On a single machine you will usually also see a connectivity warning such as:

```text
Direct-only mode: no public TCP address is being advertised.
```

That warning is expected for this local smoke test.

## Step 9: What This Local Test Proves

This confirms that:

- separate BuddyDrive homes work
- config is written correctly
- folders and buddies are saved correctly
- the daemon starts and publishes to the DHT
- both instances can run concurrently with different P2P and control ports

It does not prove that file transfer works between the two instances on the same host.

## Step 10: Run a Real Sync Test

To test actual file transfer, use one of these setups:

1. Two real machines, each with a forwarded TCP port and a public `announce_addr` in `config.toml`
2. Relay fallback on both sides with a shared relay token

### Using the Public Koyeb Relay

A public relay is available at `01.proxy.koyeb.app:19447`. Configure both peers:

```bash
# On both machines - use the "local" region with custom relay
HOME=/tmp/buddy1 ./bin/buddydrive config set relay-region local
HOME=/tmp/buddy2 ./bin/buddydrive config set relay-region local

# Set matching relay tokens for each buddy
HOME=/tmp/buddy1 ./bin/buddydrive config set buddy-relay-token <buddy2-id> swift-eagle
HOME=/tmp/buddy2 ./bin/buddydrive config set buddy-relay-token <buddy1-id> swift-eagle
```

For production, use `relay-base-url` and `relay-region`:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
buddydrive config set buddy-relay-token <buddy-id> <shared-token>
```

## Cleanup

```bash
rm -rf /tmp/buddy1 /tmp/buddy2
```

## Troubleshooting

1. `Address already in use` on startup

Set different `listen_port` values in each config, and use different `--port` values when starting the daemons.

2. `buddydrive status` still shows buddies as offline

That is expected right now. The CLI status command reads configured state and sync window, but it does not yet report live daemon connectivity.

3. `buddydrive start --daemon` stays in the foreground

That is expected too. Background daemon mode is not fully implemented yet.

4. `buddydrive connect` does not help with local loopback testing

Correct. The command currently prints guidance, but manual direct dialing is not implemented.
