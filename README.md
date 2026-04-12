# BuddyDrive

P2P folder sync and relay-backed restore for you and your buddies.

BuddyDrive lets you sync folders with 1-2 friends across the internet, bypassing NATs and firewalls. It also supports a 12-word recovery phrase, a per-installation master key, and relay-backed config restore so you can rebuild a lost machine and resync missing files.

## Features

- **P2P Networking** - libp2p with DHT discovery, direct public TCP dialing, UPnP attempts, and relay fallback
- **Recovery And Restore** - 12-word recovery phrase, stored master key, encrypted config sync to relay, and config restore on a new machine
- **Restore Missing Files** - normal sync recreates files that exist on your buddy but are missing locally
- **Folder Policies** - append-only mode prevents remote overwrites of existing local files
- **Simple CLI** - easy to use command-line interface
- **GTK4 GUI** - native desktop application for monitoring and configuration
- **Cross-Platform** - works on Linux, macOS, and Windows

## Installation

### Prerequisites

- **Nim** 2.2.8 or later
- **libsodium** 1.0.18 or later
- **SQLite3** development headers
- **GTK4** development libraries (for GUI)
- **pkg-config** (for GUI build)
- **g++** (C++ compiler, required by libp2p's lsquic dependency)

### Linux (Debian/Ubuntu)

```bash
# Install Nim (using choosenim for version management)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
source ~/.nimble/bin/nim

# Install system dependencies (CLI)
sudo apt update
sudo apt install -y build-essential g++ git libsodium-dev libsqlite3-dev

# Install GTK4 dependencies (for GUI)
sudo apt install -y pkg-config libgtk-4-dev

# Clone and build
git clone https://github.com/gokr/buddydrive.git
cd buddydrive
nimble build        # Build CLI
nimble gui_release  # Build GUI
```

### macOS

```bash
# Install Homebrew if needed: https://brew.sh

# Install Nim via Homebrew
brew install nim

# Or use choosenim for version management
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
source ~/.nimble/bin/nim

# Install system dependencies
brew install libsodium sqlite3 gtk4 pkg-config

# Clone and build
git clone https://github.com/gokr/buddydrive.git
cd buddydrive
nimble build        # Build CLI
nimble gui_release  # Build GUI
```

### Installing the GUI

After building, install with desktop integration:

```bash
nimble install_gui
```

This installs:

- `buddydrive-gui` binary to `~/.local/bin/`
- Desktop entry to `~/.local/share/applications/`
- Icons to `~/.local/share/icons/`

After installation, BuddyDrive will appear in your applications menu.

## Quick Start

See [TUTORIAL.md](TUTORIAL.md) for a detailed local testing guide.

```bash
# Initialize your BuddyDrive identity
buddydrive init

# Optional but recommended: set up recovery
buddydrive setup-recovery

# Add a folder to sync
buddydrive add-folder ~/Documents --name docs

# Pair with a buddy
buddydrive add-buddy --generate-code
# Share the generated code with your buddy

# On your buddy's machine
buddydrive add-buddy --id <your-id> --code <pairing-code>

# Start the daemon
buddydrive start
```

## Concepts

### Buddy Identity

When you run `buddydrive init`, your instance gets:

- **Buddy ID** - a UUID that uniquely identifies your BuddyDrive instance
- **Buddy Name** - a human-readable name displayed in outputs and shared during handshake

### Pairing

To sync folders with someone, both sides add each other:

1. Generate a pairing code with `buddydrive add-buddy --generate-code`
2. Share your Buddy ID and pairing code with your buddy
3. Your buddy runs `buddydrive add-buddy --id <your-id> --code <pairing-code>`
4. Repeat in reverse on the other side

The pairing code serves two purposes:

- Confirms you are pairing with the right person
- Acts as the shared secret for relay fallback

### Recovery And Restore

BuddyDrive can store enough encrypted config in the relay to rebuild a machine later:

1. Run `buddydrive setup-recovery`
2. Write down the generated 12-word recovery phrase
3. BuddyDrive derives a master key, saves recovery metadata in `config.toml`, and syncs an encrypted config blob to the relay
4. On a replacement machine, run `buddydrive recover`, enter the same 12 words, then start the daemon to resync folders

Restore happens in two layers:

- **Config restore** - `buddydrive recover` fetches your encrypted config from the relay and writes `~/.buddydrive/config.toml`
- **File restore** - once the daemon is running again, normal sync recreates missing local files from your buddy

Append-only folders still protect existing local files from being overwritten by the remote copy.

### Connectivity Notes

- BuddyDrive connects peers when it discovers a public TCP address for the buddy, or when relay fallback is configured.
- For direct connections, forward the configured `listen_port` on your router and set `[network].announce_addr` in `~/.buddydrive/config.toml` to a public multiaddr such as `/ip4/<public-ip>/tcp/41721`.
- For relay fallback, configure relay region. The stored pairing code is reused as the relay shared secret:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
```

A public config-recovery relay is available at `https://01.proxy.koyeb.app`. See [relay/README.md](relay/README.md) for relay details and self-hosting notes.

## Usage

### CLI Commands

| Command | Description |
|---------|-------------|
| `buddydrive init` | Generate identity and create config |
| `buddydrive config` | Show current config |
| `buddydrive config set <key> ...` | Update runtime configuration |
| `buddydrive add-folder <path>` | Add folder to sync |
| `buddydrive remove-folder <name>` | Remove folder |
| `buddydrive list-folders` | List configured folders |
| `buddydrive add-buddy` | Add or pair with a buddy |
| `buddydrive remove-buddy <id>` | Remove buddy |
| `buddydrive list-buddies` | List paired buddies |
| `buddydrive connect <address>` | Manual connect placeholder |
| `buddydrive start [--port <control-port>]` | Start sync daemon in the foreground |
| `buddydrive stop` | Stop command placeholder |
| `buddydrive status` | Show configured folders, buddies, and sync window |
| `buddydrive logs` | Show recent logs |
| `buddydrive setup-recovery` | Generate and verify a 12-word recovery phrase, then sync encrypted config to the relay |
| `buddydrive recover` | Restore config from a 12-word recovery phrase and then resync folders |
| `buddydrive sync-config` | Manually push encrypted config to the relay and configured buddies |
| `buddydrive export-recovery` | Show stored recovery public key and master key metadata |

### Example Session

```bash
$ buddydrive init
Initializing BuddyDrive...

Generated buddy name: purple-banana
Buddy ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Config created at: ~/.buddydrive/config.toml

$ buddydrive add-folder ~/Documents --name docs
Folder added: docs
  Path: /home/user/Documents
  Encrypted: true
  Append-only: false

$ buddydrive add-buddy --generate-code
Generating pairing code...

Share this with your buddy:
  Your Buddy ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Your Name: purple-banana
  Pairing Code: X7K9-M2P4

$ buddydrive start
Starting BuddyDrive daemon...
Starting daemon...
...
BuddyDrive is running!

$ buddydrive status
Buddy: purple-banana (a1b2c3d4...)
Peer ID: (run 'buddydrive start' to connect)
Sync window: always

Folders:
  docs
    Path: /home/user/Documents
    Encrypted: true
    Append-only: false
```

## Current CLI Limitations

- `buddydrive start --daemon` currently prints a note and continues in the foreground.
- `buddydrive start --port <control-port>` is supported even though it is not shown in `help`; it changes the local control API port.
- `buddydrive stop` is not implemented yet; use your process manager or `Ctrl+C` for foreground runs.
- `buddydrive status` does not yet query the running daemon for live connection state.
- `buddydrive connect` does not perform a manual direct dial yet.
- `buddydrive recover` currently restores configuration from the relay path; the buddy fallback prompt is present, but that fetch path is not implemented yet.
- `buddydrive export-recovery` does not reveal the original 12-word phrase because the phrase is not stored locally.

## How It Works

### Peer Discovery

1. `buddydrive init` creates a local buddy identity and config file
2. `buddydrive start` creates the libp2p node for the running session
3. The daemon announces your buddy ID on the DHT
4. The daemon looks up configured buddies via DHT
5. It connects directly when a public TCP address is available, or via relay fallback when configured

### Recovery And Transport Security

- Direct libp2p connections use Noise transport encryption
- Recovery setup derives a 32-byte master key from the 12-word phrase
- Config sync encrypts the serialized config blob with the master key before uploading it to the relay
- Normal sync restores missing files by comparing remote file lists with the local folder state

### Sync Protocol

1. Scans folder for changes (polling-based)
2. Exchanges file lists with buddy
3. Requests missing files
4. Transfers chunks (64KB)
5. Both sides update SQLite index

## Configuration

Config file location: `~/.buddydrive/config.toml`

```toml
[buddy]
name = "purple-banana"
id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

[recovery]
enabled = true
public_key = "6J8h2qFvExampleRecoveryKey"
master_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

[network]
listen_port = 41721
announce_addr = "/ip4/203.0.113.10/tcp/41721"
relay_base_url = "https://buddydrive.net/relays"
relay_region = "eu"
sync_window_start = ""
sync_window_end = ""
bandwidth_limit_kbps = 0

[[folders]]
name = "docs"
path = "/home/user/Documents"
encrypted = true
append_only = false
buddies = ["buddy-id-here"]

[[buddies]]
id = "buddy-id-here"
name = "cranky-wrench"
pairing_code = "ABCD-EFGH"
added_at = "2026-04-10T12:00:00Z"
```

## Roadmap

- [ ] Delta sync (rolling hash)
- [x] GTK4 desktop app
- [x] Bandwidth limiting
- [ ] System tray integration
- [ ] Auto-start on boot
- [ ] Package for distros (deb, rpm, brew)
- [ ] Multiple buddies per folder
- [ ] Selective sync (ignore patterns)
- [ ] Version history

## Contributing

Contributions welcome. Please feel free to submit pull requests.

## License

MIT

## Debian/Ubuntu Package

### Build the Package

```bash
# Install build dependencies
sudo apt install -y build-essential g++ git libsodium-dev libsqlite3-dev debhelper dpkg-dev help2man

# Build the package
make deb

# The .deb file will be in the parent directory
sudo dpkg -i ../buddydrive_*.deb
```

### Using systemd

```bash
# Check if service is enabled/running
systemctl status buddydrive

# Enable to start on boot
sudo systemctl enable buddydrive

# Start/stop the service
sudo systemctl start buddydrive
sudo systemctl stop buddydrive

# View logs
journalctl -u buddydrive -f
```
