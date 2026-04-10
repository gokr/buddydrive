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
# Download the latest release
curl -LO https://github.com/your-repo/buddydrive/releases/latest/buddydrive-linux-x64.tar.gz
tar xzf buddydrive-linux-x64.tar.gz
sudo mv buddydrive /usr/local/bin/

# Or build from source
git clone https://github.com/your-repo/buddydrive
cd buddydrive
nimble build
```

**macOS:**

```bash
# Download DMG or build from source
# Requires Xcode command line tools
```

**Windows:**

```powershell
# Download ZIP or build from source
# Requires Visual Studio Build Tools
```

### Initialize

First time setup creates your identity:

```bash
buddydrive init
```

This generates:
- Your unique buddy ID
- Cryptographic key pair
- Configuration file at `~/.buddydrive/config.toml`

### Pair With a Buddy

**On your machine:**

```bash
buddydrive add-buddy --generate-code
```

Output:
```
Your pairing code: ABCD-EFGH
Share this code with your buddy. Code expires in 5 minutes.

Your buddy ID: fcd6295c-a912-44d4-a27b-ad898795207d
```

**On your buddy's machine:**

```bash
buddydrive add-buddy --id <your-buddy-id> --code ABCD-EFGH
```

If successful:
```
Paired with: <your-name> (fcd6295c...)
```

### Add a Folder

Configure a folder to sync:

```bash
buddydrive add-folder ~/Documents --name docs
```

Options:
- `--name` - Friendly name for the folder (required)
- `--no-encrypt` - Disable encryption (not recommended)
- `--buddy <id>` - Share with specific buddy

### Start Syncing

Start the daemon:

```bash
buddydrive start
```

For background operation:

```bash
buddydrive start --daemon
```

### Check Status

```bash
buddydrive status
```

Output:
```
BuddyDrive Status
Running: true
Uptime: 2h 15m
Peer ID: 16Uiu2HAk...

Folders:
  docs
    Path: /home/you/Documents
    Files: 234
    Status: synced

Buddies:
  Alice (fcd6295c...)
    Status: connected
    Last sync: 5 minutes ago
```

### Stop the Daemon

```bash
buddydrive stop
```

## GUI

### Launch

```bash
buddydrive-gui
```

Or from your desktop menu: BuddyDrive

### Features

- **Status panel** - daemon running, identity, uptime
- **Folders list** - all configured folders with sync status
- **Buddies list** - paired buddies with connection state
- **Add folder dialog** - select path, name, encryption
- **Pair dialog** - generate or enter pairing codes

### Controls

- **Refresh** - update status from daemon
- **Sync All** - sync all folders
- **Sync** (per folder) - sync individual folder
- **Remove** - remove folder or buddy

## CLI Reference

### Commands

```
buddydrive init                        Initialize BuddyDrive
buddydrive config                      Show configuration
buddydrive add-folder <path>           Add folder to sync
  --name <name>                        Folder name (required)
  --no-encrypt                          Don't encrypt files
  --buddy <id>                         Share with buddy
buddydrive remove-folder <name>        Remove folder
buddydrive list-folders                List configured folders
buddydrive add-buddy                   Pair with buddy
  --generate-code                      Generate pairing code
  --id <buddy-id>                      Buddy ID to pair with
  --code <code>                        Pairing code from buddy
buddydrive remove-buddy <id>          Remove buddy
buddydrive list-buddies                List paired buddies
buddydrive connect <address>           Connect manually
buddydrive start                       Start sync daemon
  --daemon                             Run in background
buddydrive stop                        Stop sync daemon
buddydrive status                      Show sync status
buddydrive logs                        Show recent logs
buddydrive help                        Show help
```

### Examples

```bash
# Pair with a buddy
buddydrive add-buddy --generate-code
# (share code with buddy)
buddydrive add-buddy --id abc123 --code XYZ-789

# Add multiple folders
buddydrive add-folder ~/Photos --name photos
buddydrive add-folder ~/Documents --name docs
buddydrive add-folder ~/Projects --name projects

# Check what's configured
buddydrive list-folders
buddydrive list-buddies

# Start and monitor
buddydrive start --daemon
buddydrive status
buddydrive logs

# Stop
buddydrive stop
```

## Configuration

Config stored at `~/.buddydrive/config.toml`:

```toml
[buddy]
name = "Alice"
uuid = "fcd6295c-a912-44d4-a27b-ad898795207d"

[[folders]]
name = "docs"
path = "/home/alice/Documents"
encrypted = true
buddies = ["bob-uuid"]

[[buddies]]
id = { uuid = "bob-uuid", name = "Bob" }
publicKey = "abc123..."
addedAt = 2024-01-15T10:30:00Z
```

Edit with care. Better to use CLI commands.

## Files

| Location | Purpose |
|----------|---------|
| `~/.buddydrive/config.toml` | Configuration |
| `~/.buddydrive/state.db` | Runtime state (SQLite) |
| `~/.buddydrive/buddydrive.log` | Logs |
| `~/.buddydrive/port` | Control API port |

## Troubleshooting

### Daemon won't start

```bash
# Check if already running
ps aux | grep buddydrive

# Check logs
cat ~/.buddydrive/buddydrive.log

# Check config
buddydrive config
```

### Can't connect to buddy

1. Both need internet access
2. Both need buddydrive running
3. Check pairing status: `buddydrive list-buddies`
4. Try regenerating pairing codes

### Files not syncing

1. Check daemon running: `buddydrive status`
2. Check folder configured: `buddydrive list-folders`
3. Check buddy connected in GUI or status output
4. Manually trigger: GUI "Sync" button or API call

### Pairing code expired

Codes expire after 5 minutes. Generate a new one:

```bash
buddydrive add-buddy --generate-code
```

### Reset everything

```bash
# Stop daemon
buddydrive stop

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
