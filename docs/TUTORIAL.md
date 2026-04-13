# BuddyDrive Local Testing Tutorial

This tutorial shows how to smoke-test BuddyDrive on a single machine with two isolated instances.

## Key Concepts

- **Buddy ID** - a UUID that identifies a BuddyDrive instance
- **Buddy Name** - a human-readable name shared during handshake
- **Pairing Code** - a shared secret used both for pairing confirmation and relay fallback

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

BuddyDrive currently accepts a buddy ID and pairing code, then stores the buddy entry locally, so for testing you should add each side to the other. Use the same pairing code on both sides if you want relay fallback to work later.

```bash
HOME=/tmp/buddy1 ./bin/buddydrive add-buddy --id <BUDDY2_UUID> --code TEST-0001
HOME=/tmp/buddy2 ./bin/buddydrive add-buddy --id <BUDDY1_UUID> --code TEST-0001
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
Web GUI (localhost): http://127.0.0.1:17521/
Web GUI (LAN): http://<your-ip>:17521/w/<secret>/
BuddyDrive is running!
```

You can open the web GUI in a browser to manage folders, pair buddies, view logs, and change settings.

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
2. Relay fallback on both sides with matching pairing codes

### Using Relay Fallback

When adding a buddy, the pairing code is stored and used for relay connections:

```bash
# Both buddies add each other with matching codes
HOME=/tmp/buddy1 ./bin/buddydrive add-buddy --id <buddy2-id> --code ABCD-EFGH
HOME=/tmp/buddy2 ./bin/buddydrive add-buddy --id <buddy1-id> --code ABCD-EFGH

# Set relay region for both
HOME=/tmp/buddy1 ./bin/buddydrive config set relay-region local
HOME=/tmp/buddy2 ./bin/buddydrive config set relay-region local
```

The same pairing code connects both buddies through the relay.

For production, use the public relay list:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
```

## Restore

### Restore a Missing File From Your Buddy

Once both sides can sync, BuddyDrive restores missing local files as part of normal sync. In practice that means:

1. A file exists in Buddy B's folder
2. The same file is missing from Buddy A's folder
3. The next successful sync recreates the file on Buddy A

Append-only only protects existing local files from being overwritten. It does not block creating a file that is missing locally.

### Restore Config On A Replacement Machine

On the original machine, set up recovery once:

```bash
./bin/buddydrive setup-recovery
```

That command generates a 12-word recovery phrase, asks you to verify part of it, stores recovery metadata in `config.toml`, and syncs an encrypted copy of your config to the relay.

On a replacement machine:

```bash
./bin/buddydrive recover
./bin/buddydrive start
```

Enter the same 12-word phrase. If relay recovery succeeds, BuddyDrive writes the restored config locally. Starting the daemon then lets normal sync recreate the missing files in your configured folders.

Current limitation: `recover` first tries the relay and then prompts for buddy fallback details, but the buddy-backed config fetch path is not implemented yet.

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
