# BuddyDrive - P2P Encrypted Folder Sync

## Overview

A CLI-based P2P encrypted folder sync tool in Nim that allows syncing folders with 1-2 buddies across the internet, bypassing NATs and firewalls.

## Key Features

- **P2P Networking**: libp2p with DHT discovery, NAT traversal (hole punching), relay fallback
- **Encryption**: libsodium (XChaCha20-Poly1305) for file contents AND filenames
- **Sync**: Full file sync with polling-based scanning (MVP), delta sync later
- **Discovery**: Public libp2p DHT bootstrap nodes
- **Config**: `~/.buddydrive/` directory
- **Index**: SQLite for file metadata tracking
- **CLI**: Subcommand-based interface

---

## Project Structure

```
buddydrive/
├── buddydrive.nimble
├── config.nims
├── src/
│   ├── buddydrive.nim           # Main entry point
│   └── buddydrive/
│       ├── cli.nim              # CLI parsing
│       ├── config.nim           # Config read/write
│       ├── crypto.nim           # Encryption (libsodium)
│       ├── types.nim            # Shared types
│       ├── logutils.nim         # Logging setup
│       ├── sync/
│       │   ├── scanner.nim      # Polling file scanner
│       │   ├── index.nim        # SQLite file index
│       │   └── transfer.nim     # File transfer
│       ├── p2p/
│       │   ├── node.nim         # libp2p node
│       │   ├── discovery.nim    # DHT/rendezvous
│       │   ├── protocol.nim     # BuddyDrive protocol
│       │   └── messages.nim     # Protocol messages
│       └── daemon.nim           # Background service
├── tests/
│   ├── test_crypto.nim
│   ├── test_config.nim
│   └── harness/
│       └── test_local_sync.nim
├── wordlists/
│   ├── adjectives.txt
│   └── nouns.txt
└── README.md
```

---

## CLI Commands

```bash
buddydrive init                          # Generate identity, create config
buddydrive config                        # Show current config
buddydrive add-folder <path> [options]   # Add folder to sync
buddydrive remove-folder <name>          # Remove folder
buddydrive list-folders                  # List configured folders
buddydrive add-buddy [options]           # Add/pair with a buddy
buddydrive remove-buddy <id>             # Remove buddy
buddydrive list-buddies                   # List paired buddies
buddydrive start [options]               # Start sync daemon
buddydrive stop                          # Stop daemon
buddydrive status                        # Show sync status
buddydrive logs                          # Show recent logs
```

### Examples

```bash
# Initialize
$ buddydrive init
Generated buddy name: purple-banana
Buddy ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Config created at: ~/.buddydrive/config.toml

# Add a folder
$ buddydrive add-folder ~/Documents --name docs --encrypted
Folder added: docs
  Path: /home/user/Documents
  Encrypted: yes

# Pair with a buddy
$ buddydrive add-buddy --generate-code
Share this with your buddy:
  Buddy ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Pairing Code: X7K9-M2P4

$ buddydrive add-buddy --id b2c3d4e5-f6a7-8901-bcde-f23456789012 --code X7K9-M2P4
Enter password: ****
Buddy paired: cranky-wrench

# Start syncing
$ buddydrive start
Starting BuddyDrive daemon...
Connected to DHT
Connected to buddy: cranky-wrench
Watching 1 folder...

# Check status
$ buddydrive status
Buddy: purple-banana
Status: Online
Folders:
  docs  /home/user/Documents  [synced]  2.3 GB
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Days 1-2)

1. **Project Setup**
   - Create nimble package
   - Set up config.nims
   - Create directory structure

2. **Types (`src/buddydrive/types.nim`)**
   - Core type definitions
   - BuddyId, PeerInfo, FolderConfig, AppConfig, FileInfo, FileChange

3. **Logging (`src/buddydrive/logging.nim`)**
   - Standard Nim logging wrapper
   - File and console output

4. **Config (`src/buddydrive/config.nim`)**
   - TOML config at `~/.buddydrive/config.toml`
   - Atomic writes
   - loadConfig, saveConfig, initConfig

5. **CLI (`src/buddydrive/cli.nim`)**
   - Subcommand parsing
   - Handle init, config commands

6. **Wordlists**
   - Adjectives and nouns for name generation

**Deliverable**: `buddydrive init` and `buddydrive config` commands work

---

### Phase 2: libp2p Networking (Days 3-5)

1. **Node Setup (`src/buddydrive/p2p/node.nim`)**
   - TCP + WebSocket transports
   - Noise secure channel
   - Yamux multiplexer
   - DHT with bootstrap nodes

2. **NAT Traversal**
   - AutoNAT (detect NAT type)
   - DCUTR (hole punching)
   - Relay client (fallback)

3. **Discovery (`src/buddydrive/p2p/discovery.nim`)**
   - DHT publish/lookup
   - Rendezvous protocol

**Deliverable**: Two instances can discover each other via DHT

---

### Phase 3: Buddy Pairing (Days 6-7)

1. **Pairing Protocol**
   - Generate pairing code (short-lived token)
   - Publish to DHT under rendezvous point
   - Exchange public keys

2. **Key Derivation**
   - Argon2id for password → encryption key
   - Per-buddy shared secrets

3. **Authentication**
   - Challenge-response with password

**Deliverable**: Buddies can pair using ID + code + password

---

### Phase 4: File Sync Protocol (Days 8-11)

1. **File Index (`src/buddydrive/sync/index.nim`)**
   - SQLite database
   - Track file metadata (path, size, mtime, hash)
   - Sync log

2. **Scanner (`src/buddydrive/sync/scanner.nim`)**
   - Polling-based (every 5s)
   - Detect added, modified, deleted files
   - Compute hashes for changed files

3. **Encryption (`src/buddydrive/crypto.nim`)**
   - XChaCha20-Poly1305 for file content
   - Encrypted filenames (base64 encoded)
   - Per-folder encryption keys

4. **Protocol Messages (`src/buddydrive/p2p/messages.nim`)**
   - MsgFileList, MsgFileRequest, MsgFileData, MsgFileAck, MsgFileDelete

5. **Sync Protocol (`src/buddydrive/p2p/protocol.nim`)**
   - Exchange file lists
   - Request missing files
   - Transfer encrypted chunks

6. **Transfer (`src/buddydrive/sync/transfer.nim`)**
   - Chunked transfer (64KB)
   - Resume support

**Deliverable**: Files sync between two buddies

---

### Phase 5: Status & Monitoring (Days 12-13)

1. **Status Command**
   - Show buddy connection status
   - Show folder sync progress
   - Show recent activity

2. **Daemon Mode**
   - Fork to background
   - PID file
   - Signal handling (SIGTERM, SIGHUP)

3. **Logging**
   - Activity log
   - Error tracking

**Deliverable**: Can monitor sync progress, daemon runs in background

---

### Phase 6: Testing & Polish (Days 14-15)

1. **Test Harness**
   - Local sync test (two instances)
   - NAT traversal simulation
   - Conflict scenarios

2. **Unit Tests**
   - Crypto tests
   - Config tests
   - Protocol tests

3. **Documentation**
   - README with usage
   - Build instructions

**Deliverable**: Stable, tested CLI sync tool

---

## Technical Details

### Peer Discovery Flow

```
1. App generates: UUID + Ed25519 keypair
2. Name derived: adjective-noun (e.g., "purple-banana")
3. Connect to libp2p DHT (public bootstrap nodes)
4. Announce presence: DHT[buddydrive/{uuid}] = {peer_addrs}
5. Search for buddy: DHT[buddydrive/{buddy-uuid}]
6. Connect via:
   a. Direct (if public IP)
   b. Hole punch (DCUTR)
   c. Relay (fallback)
```

### Pairing Protocol

```
Alice generates: pairing_code = random_6_chars()
Alice publishes: DHT[buddydrive/{id}/pairing/{code}] = {public_key}

Bob: add-buddy --id <alice-id> --code <code>
Bob looks up: DHT[buddydrive/{id}/pairing/{code}]
Bob gets: Alice's public key
Bob connects to Alice
Alice validates code
Both exchange encryption keys (derived from shared password)
Both store buddy info
```

### Sync Protocol

```
1. Alice scans folder, detects changes
2. Alice sends MsgFileList(files, hashes) to Bob
3. Bob compares with his index
4. Bob requests missing files: MsgFileRequest(path)
5. Alice sends encrypted chunks: MsgFileData(offset, data)
6. Bob decrypts, writes, sends MsgFileAck
7. Both update index
```

### Encryption Model

```nim
# Per-folder encryption key (derived from password + salt)
folderKey = argon2id(password, salt, iterations=3, memory=64KB)

# Encrypt file content
encryptedData = xChaCha20Poly1305(data, folderKey, random_nonce)

# Encrypt filename
encryptedName = base64(xChaCha20Poly1305(originalPath, folderKey, nonce))

# File on disk: <nonce><encrypted_content><auth_tag>
# Filename: base64(nonce || encrypt(originalName))
```

### File Index Schema

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  folder_name TEXT NOT NULL,
  path TEXT NOT NULL,
  encrypted_path TEXT,
  size INTEGER,
  mtime INTEGER,
  hash BLOB,
  last_sync INTEGER,
  UNIQUE(folder_name, path)
);

CREATE TABLE sync_log (
  id INTEGER PRIMARY KEY,
  timestamp INTEGER,
  folder_name TEXT,
  file_path TEXT,
  action TEXT,  -- 'upload', 'download', 'delete'
  buddy_id TEXT,
  bytes_transferred INTEGER
);

CREATE TABLE buddies (
  id TEXT PRIMARY KEY,
  name TEXT,
  public_key BLOB,
  added_at INTEGER
);
```

---

## Config File Format

```toml
# ~/.buddydrive/config.toml

[buddy]
name = "purple-banana"
id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
public_key = "..."  # base64

[[folders]]
name = "docs"
path = "/home/user/Documents"
encrypted = true
buddies = ["b2c3d4e5-f6a7-8901-bcde-f23456789012"]

[[buddies]]
id = "b2c3d4e5-f6a7-8901-bcde-f23456789012"
name = "cranky-wrench"
public_key = "..."
added_at = 2026-04-09T10:30:00Z
```

---

## Dependencies

```nimble
version = "0.1.0"
requires "nim >= 2.0.16"
requires "libp2p >= 1.15"
requires "libsodium >= 0.7"
requires "parsetoml"
requires "toml-serialization"
requires "result"
requires "sqlite3"
```

---

## Conflict Resolution

1. Compare modification times
2. Later timestamp wins
3. Losing version saved as: `file.conflict.YYYYMMDD-HHMMSS`
4. User notified in logs

---

## Error Handling

- Network errors: Auto-reconnect with exponential backoff
- File access errors: Log and skip, retry later
- Sync errors: Store in error log, manual review

---

## Debian Packaging

BuddyDrive will be distributed as a `.deb` package for easy installation on Debian/Ubuntu systems.

### Package Structure

```
buddydrive_0.1.0_amd64.deb
├── DEBIAN/
│   ├── control          # Package metadata
│   ├── preinst          # Pre-install script
│   ├── postinst         # Post-install script
│   ├── prerm            # Pre-remove script
│   └── postrm           # Post-remove script
├── usr/
│   └── bin/
│       └── buddydrive   # Main executable
├── etc/
│   └── systemd/
│       └── system/
│           └── buddydrive.service  # Systemd service
└── usr/
    └── share/
        └── doc/
            └── buddydrive/
                ├── README.md
                └── LICENSE
```

### Systemd Service

```ini
# /etc/systemd/system/buddydrive.service
[Unit]
Description=BuddyDrive P2P Sync Service
After=network.target

[Service]
Type=simple
User=buddydrive
Group=buddydrive
ExecStart=/usr/bin/buddydrive start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Post-Install Actions

1. Create `buddydrive` user/group
2. Enable systemd service
3. Create config directory at `/var/lib/buddydrive/`

### Build Command

```bash
# Build the .deb package
dpkg-deb --build buddydrive_0.1.0_amd64
```

### Installation

```bash
sudo dpkg -i buddydrive_0.1.0_amd64.deb
sudo systemctl enable buddydrive
sudo systemctl start buddydrive
```

---

## Future Enhancements (Post-MVP)

1. Delta sync (rolling hash)
2. Owlkettle GUI
3. System tray integration
4. Auto-start on boot
5. Package managers (deb, rpm, brew, chocolatey)
6. Multiple buddies per folder
7. Selective sync (ignore patterns)
8. Bandwidth limiting
9. Version history

---

## Development Log

### 2026-04-09
- Project initialized
- Phase 1 completed:
  - Project structure created
  - CLI framework with subcommands working
  - Config file (TOML) read/write
  - Name generation (adjective-noun)
  - UUID generation
  - Pairing code generation
  - Commands: init, config, add-folder, remove-folder, list-folders, add-buddy, list-buddies, start, stop, status
- Dependencies: libp2p, libsodium, parsetoml, results

### Next Steps
- Phase 2: libp2p networking - COMPLETE ✓
  - libp2p node creation working ✓
  - Node starts and binds to addresses ✓
  - MultiAddress display working ✓
  - Kademlia DHT integration ✓
  - DHT announce/findProvider API ✓
  - Test harness for two local instances ✓
  - Direct peer connection tested ✓

- Phase 3: Buddy pairing protocol - COMPLETE ✓
  - Pairing handshake implemented ✓
  - Buddy verification against config ✓
  - BuddyConnection tracking in daemon ✓

- Phase 4: File sync - COMPLETE ✓
  - File scanner with change detection ✓
  - SQLite file index ✓
  - Chunk-based file transfer ✓
  - SyncManager coordination ✓

- Phase 5: Encryption - COMPLETE ✓
  - libsodium secretbox for content ✓
  - Password-based key derivation ✓
  - Encrypted filename support ✓

- Phase 6: Debian packaging - COMPLETE ✓
  - debian/ directory with control, rules ✓
  - systemd service unit file ✓
  - Makefile for build/package ✓

### Remaining Work
- Test end-to-end sync between two local instances
- Test actual DHT discovery with bootstrap nodes
- Add relay fallback for NAT traversal
- Phase 3: Buddy pairing protocol
- Phase 4: File sync with encryption
