# BuddyDrive

P2P encrypted folder sync for you and your buddies.

BuddyDrive lets you sync folders with 1-2 friends across the internet, bypassing NATs and firewalls. No cloud. No middleman. Just peer-to-peer encrypted sync.

## Features

- **P2P Networking** - libp2p with DHT discovery, NAT traversal (hole punching), and relay fallback
- **End-to-End Encryption** - libsodium (XChaCha20-Poly1305) for both file contents and filenames
- **Simple CLI** - Easy to use command-line interface
- **GTK4 GUI** - Native desktop application for monitoring and configuration
- **Cross-Platform** - Works on Linux, macOS, and Windows

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

- **Buddy ID** - A UUID (e.g., `fcd6295c-a912-44d4-a27b-ad898795207d`) that uniquely identifies your BuddyDrive instance. Share this with buddies so they can pair with you.
- **Buddy Name** - A human-readable name (e.g., `purple-banana`) that's displayed in outputs and shared during handshake. You can customize it.

### Pairing

To sync folders with someone, both sides add each other:

1. **Generate a pairing code** with `buddydrive add-buddy --generate-code`
2. **Share your Buddy ID and pairing code** with your buddy
3. Your buddy runs `buddydrive add-buddy --id <your-id> --code <pairing-code>`
4. Both sides repeat in reverse

The pairing code serves two purposes:
- Confirms you're pairing with the right person
- Used as the shared secret for relay connections (both buddies use the same code)

### Security

Pairing uses a shared secret model:
- Both buddies must have the same pairing code stored
- The code is used during relay handshake
- Connections are encrypted via libp2p Noise protocol

**Important**: Only pair with people you trust. An attacker who knows your Buddy ID and pairing code can connect as your buddy.

## Connectivity Notes

- BuddyDrive connects peers when it discovers a public TCP address for the buddy, or when relay fallback is configured.
- For direct connections, forward the configured `listen_port` on your router and set `[network].announce_addr` in `~/.buddydrive/config.toml` to a public multiaddr such as `/ip4/<public-ip>/tcp/41721`.
- For relay fallback, configure relay region. The pairing code is used as the relay shared secret:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
```

A public relay is available on Koyeb at `01.proxy.koyeb.app:19447` (tokens: `swift-eagle`, `brave-moose`). See [relay/README.md](relay/README.md) for self-hosting.

See [TUTORIAL.md](TUTORIAL.md) for local testing workflow.

## Usage

### CLI Commands

| Command | Description |
|---------|-------------|
| `buddydrive init` | Generate identity, create config |
| `buddydrive config` | Show current config |
| `buddydrive config set <key> ...` | Update runtime configuration |
| `buddydrive add-folder <path>` | Add folder to sync |
| `buddydrive remove-folder <name>` | Remove folder |
| `buddydrive list-folders` | List configured folders |
| `buddydrive add-buddy` | Add/pair with a buddy |
| `buddydrive remove-buddy <id>` | Remove buddy |
| `buddydrive list-buddies` | List paired buddies |
| `buddydrive connect <address>` | Manual connect placeholder |
| `buddydrive start [--port <control-port>]` | Start sync daemon in the foreground |
| `buddydrive stop` | Stop command placeholder |
| `buddydrive status` | Show configured folders, buddies, and sync window |
| `buddydrive logs` | Show recent logs |

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

## How It Works

### Peer Discovery

1. `buddydrive init` creates a local buddy identity and config file
2. `buddydrive start` creates the libp2p node for the running session
3. The daemon announces your buddy ID on the DHT
4. The daemon looks up configured buddies via DHT
5. It connects directly when a public TCP address is available, or via relay fallback when configured

### Encryption

- Per-folder encryption keys derived using Argon2id
- File contents encrypted with XChaCha20-Poly1305
- Filenames also encrypted (base64 encoded)
- Nonces stored alongside encrypted data

### Sync Protocol

1. Scans folder for changes (polling-based)
2. Exchanges file lists with buddy
3. Requests missing files
4. Transfers encrypted chunks (64KB)
5. Both sides update SQLite index

## Configuration

Config file location: `~/.buddydrive/config.toml`

```toml
[buddy]
name = "purple-banana"
id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

[network]
listen_port = 41721
announce_addr = "/ip4/203.0.113.10/tcp/41721"
relay_base_url = "https://buddydrive.net/relays"
relay_region = "eu"
sync_window_start = ""
sync_window_end = ""

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

Contributions welcome! Please feel free to submit pull requests.

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
