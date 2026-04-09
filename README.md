# BuddyDrive

P2P encrypted folder sync for you and your buddies.

BuddyDrive lets you sync folders with 1-2 friends across the internet, bypassing NATs and firewalls. No cloud. No middleman. Just peer-to-peer encrypted sync.

## Features

- **P2P Networking** - libp2p with DHT discovery, NAT traversal (hole punching), and relay fallback
- **End-to-End Encryption** - libsodium (XChaCha20-Poly1305) for both file contents and filenames
- **Simple CLI** - Easy to use command-line interface
- **Cross-Platform** - Works on Linux, macOS, and Windows

## Installation

### Prerequisites

- Nim 2.0.16 or later
- libsodium

### Build from Source

```bash
git clone https://github.com/gokr/buddydrive.git
cd buddydrive
nimble build
```

## Quick Start

```bash
# Initialize your BuddyDrive identity
buddydrive init

# Add a folder to sync
buddydrive add-folder ~/Documents --name docs --encrypted

# Pair with a buddy
buddydrive add-buddy --generate-code
# Share the generated code with your buddy

# On your buddy's machine
buddydrive add-buddy --id <your-id> --code <pairing-code>

# Start syncing
buddydrive start
```

## Usage

### CLI Commands

| Command | Description |
|---------|-------------|
| `buddydrive init` | Generate identity, create config |
| `buddydrive config` | Show current config |
| `buddydrive add-folder <path>` | Add folder to sync |
| `buddydrive remove-folder <name>` | Remove folder |
| `buddydrive list-folders` | List configured folders |
| `buddydrive add-buddy` | Add/pair with a buddy |
| `buddydrive remove-buddy <id>` | Remove buddy |
| `buddydrive list-buddies` | List paired buddies |
| `buddydrive start` | Start sync daemon |
| `buddydrive stop` | Stop daemon |
| `buddydrive status` | Show sync status |
| `buddydrive logs` | Show recent logs |

### Example Session

```bash
$ buddydrive init
Generated buddy name: purple-banana
Buddy ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Config created at: ~/.buddydrive/config.toml

$ buddydrive add-folder ~/Documents --name docs --encrypted
Folder added: docs
  Path: /home/user/Documents
  Encrypted: yes

$ buddydrive start
Starting BuddyDrive daemon...
Connected to DHT
Connected to buddy: cranky-wrench
Watching 1 folder...

$ buddydrive status
Buddy: purple-banana
Status: Online
Folders:
  docs  /home/user/Documents  [synced]  2.3 GB
```

## How It Works

### Peer Discovery

1. App generates UUID + Ed25519 keypair
2. Connects to libp2p DHT using public bootstrap nodes
3. Announces presence on DHT
4. Discovers buddies via DHT lookup
5. Connects directly or via NAT traversal (hole punching/relay)

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

[[folders]]
name = "docs"
path = "/home/user/Documents"
encrypted = true
buddies = ["buddy-id-here"]

[[buddies]]
id = "buddy-id-here"
name = "cranky-wrench"
```

## Roadmap

- [ ] Delta sync (rolling hash)
- [ ] GUI (Owlkettle)
- [ ] System tray integration
- [ ] Auto-start on boot
- [ ] Package for distros (deb, rpm, brew)
- [ ] Multiple buddies per folder
- [ ] Selective sync (ignore patterns)
- [ ] Bandwidth limiting
- [ ] Version history

## Contributing

Contributions welcome! Please feel free to submit pull requests.

## License

MIT
