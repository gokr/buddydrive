---
title: Getting Started
---

## Quick Start

### Prerequisites

- Linux, macOS, or Windows
- Internet connection
- A friend with BuddyDrive installed

### Install

**Linux:**

```bash
# Build from source
git clone https://github.com/gokr/buddydrive
cd buddydrive
nimble build
```

**macOS:**

```bash
# Build from source
git clone https://github.com/gokr/buddydrive
cd buddydrive
nimble build
```

**Windows:**

```powershell
# Build from source
git clone https://github.com/gokr/buddydrive
cd buddydrive
nimble build
```

### Initialize

First time setup creates your local BuddyDrive identity:

```bash
buddydrive init
```

This creates:

- **Buddy ID** - A UUID that uniquely identifies your instance (e.g., `fcd6295c-a912-44d4-a27b-ad898795207d`)
- **Buddy Name** - A human-readable name (e.g., `purple-banana`)
- Configuration file at `~/.buddydrive/config.toml`

### Pair With a Buddy

**On your machine:**

```bash
buddydrive add-buddy --generate-code
```

Output looks like:

```
Generating pairing code...

Share this with your buddy:
  Your Buddy ID: fcd6295c-a912-44d4-a27b-ad898795207d
  Your Name: purple-banana
  Pairing Code: ABCD-EFGH
```

**On your buddy's machine:**

```bash
buddydrive add-buddy --id <your-buddy-id> --code ABCD-EFGH
```

If successful:

```
Pairing with buddy: fcd6295c...
Pairing code: ABCD-EFGH

Buddy added: fcd6295c...
Pairing code stored for relay fallback.
```

The pairing code is used for both pairing confirmation and relay connections.

### Add a Folder

Configure a folder to sync:

```bash
buddydrive add-folder ~/Documents --name docs
```

Options:

- `--name` - Friendly name for the folder (required)
- `--no-encrypt` - Disable encryption
- `--append-only` - Only accept new incoming files for that folder
- `--buddy <id>` - Restrict the folder to a specific buddy

### Start the Daemon

```bash
buddydrive start
```

Optional:

- `--port <control-port>` - Change the local control API port
- `--daemon` - Accepted, but currently continues in the foreground

### Connectivity Notes

BuddyDrive connects peers in one of two ways:

1. Direct connection with a public TCP address
2. Relay fallback using the pairing code

For direct connections, forward the configured `listen_port` on your router and set `[network].announce_addr` in `~/.buddydrive/config.toml` to a public multiaddr such as:

```toml
announce_addr = "/ip4/203.0.113.10/tcp/41721"
```

For relay fallback, configure relay region. The pairing code stored when adding a buddy is used as the relay shared secret:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
```

**About the Pairing Code:**

- Serves as both pairing confirmation and relay shared secret
- Both buddies must use the **same code** for their relationship
- The relay uses codes to pair connections - it connects two clients using matching codes
- A public relay is available on Koyeb at `01.proxy.koyeb.app:19447` with codes `swift-eagle` and `brave-moose`

### Check Status

```bash
buddydrive status
```

Output looks like:

```
Buddy: purple-banana (fcd6295c...)
Sync window: always

Folders:
  docs
    Path: /home/you/Documents
    Encrypted: true
    Append-only: false
```

### Current CLI Limitations

- `buddydrive start --daemon` is not fully implemented yet
- `buddydrive stop` is a placeholder command today
- `buddydrive status` shows configured state, not live daemon connectivity
- `buddydrive connect` does not perform a manual direct dial yet

## GUI

### Launch

```bash
buddydrive-gui
```

Or from your desktop menu: BuddyDrive

### Features

- **Status panel** - daemon running, identity, uptime
- **Folders list** - configured folders and sync status
- **Buddies list** - paired buddies and their stored configuration
- **Add folder dialog** - select path, name, encryption, and append-only mode
- **Pair dialog** - generate or enter pairing details

### Controls

- **Refresh** - reload status from the local control API
- **Sync All** - trigger sync actions from the GUI
- **Remove** - remove folder or buddy entries

## CLI Reference

### Commands

```
buddydrive init                        Initialize BuddyDrive
buddydrive config                      Show configuration
buddydrive config set <key> ...        Update configuration values
buddydrive add-folder <path>           Add folder to sync
  --name <name>                        Folder name (required)
  --no-encrypt                         Don't encrypt files
  --append-only                        Only sync new files
  --buddy <id>                         Restrict folder to buddy
buddydrive remove-folder <name>        Remove folder
buddydrive list-folders                List configured folders
buddydrive add-buddy                   Pair with a buddy
  --generate-code                      Generate pairing code
  --id <buddy-id>                      Buddy ID to pair with
  --code <code>                        Pairing code from buddy
buddydrive remove-buddy <id>           Remove buddy
buddydrive list-buddies                List paired buddies
buddydrive connect <address>           Manual connect placeholder
buddydrive start                       Start sync daemon
  --port <control-port>                Override control API port
  --daemon                             Accepted but stays foreground
buddydrive stop                        Stop placeholder command
buddydrive status                      Show configured status
buddydrive logs                        Show recent logs
buddydrive help                        Show help
```

### Examples

```bash
# Pair with a buddy
buddydrive add-buddy --generate-code
buddydrive add-buddy --id abc123 --code XYZ-789

# Add folders
buddydrive add-folder ~/Photos --name photos
buddydrive add-folder ~/Documents --name docs --append-only

# Configure relay fallback
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
buddydrive config set buddy-relay-token abc123 swift-eagle

# Check what's configured
buddydrive list-folders
buddydrive list-buddies
buddydrive config

# Start and inspect logs
buddydrive start --port 17521
buddydrive status
buddydrive logs
```

## Configuration

Config stored at `~/.buddydrive/config.toml`:

```toml
[buddy]
name = "Alice"
id = "fcd6295c-a912-44d4-a27b-ad898795207d"
public_key = ""

[network]
listen_port = 41721
announce_addr = "/ip4/203.0.113.10/tcp/41721"
relay_base_url = "https://buddydrive.net/relays"
relay_region = "eu"
sync_window_start = ""
sync_window_end = ""

[[folders]]
name = "docs"
path = "/home/alice/Documents"
encrypted = true
append_only = false
buddies = ["bob-uuid"]

[[buddies]]
id = "bob-uuid"
name = "Bob"
public_key = ""
relay_token = "swift-eagle"
added_at = "2026-04-10T12:00:00Z"
```

Edit with care. Better to use CLI commands.

## Files

| Location | Purpose |
|----------|---------|
| `~/.buddydrive/config.toml` | Configuration |
| `~/.buddydrive/state.db` | Runtime state |
| `~/.buddydrive/index.db` | File index |
| `~/.buddydrive/buddydrive.log` | Logs |
| `~/.buddydrive/port` | Control API port |

## Troubleshooting

### Daemon won't start

```bash
# Check logs
cat ~/.buddydrive/buddydrive.log

# Check config
buddydrive config
```

### Can't connect to buddy

1. Both peers need internet access
2. Both peers need `buddydrive start` running
3. Check stored buddies with `buddydrive list-buddies`
4. For direct mode, verify port forwarding and `announce_addr`
5. For relay mode, verify `relay-region`, `relay-base-url`, and matching relay tokens

### Files not syncing

1. Check daemon logs with `buddydrive logs`
2. Check folder configuration with `buddydrive list-folders`
3. Remember `buddydrive status` does not show live connection state yet
4. Single-machine loopback tests are limited unless you use relay fallback

### Reset everything

```bash
# Stop foreground daemon with Ctrl+C if running

# Backup config if needed
cp ~/.buddydrive/config.toml ~/buddydrive-backup.toml

# Remove all state
rm -rf ~/.buddydrive

# Start fresh
buddydrive init
```

## Next Steps

- Read [Features](/features) for capabilities
- Read [Security](/security) for encryption details
- Read [How It Works](/how-it-works) for architecture

## Getting Help

- GitHub Issues: bug reports, feature requests
- Documentation: this site
- Community: discussions, questions
