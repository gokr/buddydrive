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
│   ├── buddydrive.nim              # Main entry point
│   ├── buddydrive_gui.nim          # GTK4 GUI entry point
│   └── buddydrive/
│       ├── cli.nim                  # CLI parsing
│       ├── config.nim              # Config read/write
│       ├── crypto.nim              # Encryption (libsodium)
│       ├── types.nim               # Shared types
│       ├── logutils.nim            # Logging setup
│       ├── recovery.nim            # BIP39 mnemonic, key derivation, config encrypt/decrypt
│       ├── control.nim             # REST API control server
│       ├── control_web.nim         # Web GUI serving
│       ├── daemon.nim              # Background sync daemon
│       ├── nat.nim                 # NAT traversal (UPnP)
│       ├── sync/
│       │   ├── scanner.nim         # Polling file scanner
│       │   ├── index.nim           # SQLite file index
│       │   ├── transfer.nim        # File transfer
│       │   ├── session.nim         # Sync sessions
│       │   ├── policy.nim          # Sync policy
│       │   └── config_sync.nim     # Config sync to relay/buddies, recovery logic
│       ├── p2p/
│       │   ├── node.nim            # libp2p node
│       │   ├── discovery.nim       # DHT provider records discovery
│       │   ├── protocol.nim       # BuddyDrive protocol
│       │   ├── pairing.nim        # Buddy pairing handshake
│       │   ├── messages.nim        # Protocol messages
│       │   ├── rawrelay.nim        # Relay client for NAT fallback
│       │   ├── synchandler.nim    # Sync handler
│       └── syncmanager.nim        # Sync manager
├── tests/
│   ├── testutils.nim              # Shared test utilities
│   ├── unit/                      # Unit tests (testament)
│   │   ├── config/               # Config tests
│   │   ├── config_sync/          # Config sync tests
│   │   ├── control/              # Control API tests
│   │   ├── control_web/          # Web control tests
│   │   ├── crypto/               # Crypto tests
│   │   ├── index/                # File index tests
│   │   ├── messages/             # Protocol message tests
│   │   ├── pairing/              # Pairing state tests
│   │   ├── policy/               # Sync policy tests
│   │   ├── rawrelay/             # Relay helper tests
│   │   ├── recovery/             # Recovery tests
│   │   ├── scanner/              # Scanner + crash safety tests
│   │   └── types/                # Core type tests
│   └── integration/              # Integration tests (testament)
│       ├── test_cli_flows.nim
│       ├── test_config_sync_e2e.nim
│       ├── test_kv_api.nim
│       ├── test_pairing.nim
│       ├── test_peer_discovery.nim        # Local DHT server
│       ├── test_peer_discovery_public.nim # Public DHT
│       ├── test_relay_fallback.nim
│       ├── test_relay_file_sync.nim
│       └── test_relay_server.nim
├── wordlists/
│   ├── adjectives.txt
│   ├── nouns.txt
│   └── bip39_english.txt
├── relay/
│   └── src/
│       ├── relay.nim              # TCP relay server
│       ├── kvstore.nim           # TiDB MySQL KV store
│       └── kvstore_api.nim       # KV HTTP API
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
   - DHT provider records (addProvider/getProviders)
   - Periodic re-announcement (provider records expire after ~30 min)

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
11. **Unencrypted folder option** — Allow setting a folder to not be encrypted (encryption remains the default)
12. Can we simplify the info to be sent to buddy with only one item, like buddy nickname/token
13. Improve crash-resilience, see file `Crash-Safety-During-File-Sync.md`
    - [DONE] Atomic writes: temp file (`.buddytmp`) + best-effort fsync + rename
    - [DONE] Startup cleanup of leftover `.buddytmp` files
    - [DONE] Ignore `.buddytmp` files during scans
    - [SKIPPED] Transfer resumption from saved offset for large files
14. GUI/control port follow-up
    - [TODO] Make the GTK GUI read the actual control API port from `~/.buddydrive/port`
    - [TODO] Remove the hardcoded `127.0.0.1:17521` assumption from the GUI
---

## Recovery System

### Goal

Add a recovery system to BuddyDrive that allows users to recover their configuration and files if their machine is lost/destroyed, using a BIP39 12-word mnemonic as the single recovery secret.

### Design Decisions

- **Pairing code** reused as relay token (auto-generated XXXX-XXXX) — serves dual purpose: pairing confirmation + relay shared secret (`relayToken` renamed to `pairingCode`)
- **BIP39 12-word mnemonic** — the single recovery secret; user must write it down and verify by typing back 3 random words during setup
- **Asymmetric master key** (public + private) generated from mnemonic — stored in plaintext in config.toml (if attacker has machine access, they already have all files)
- **Single master key for all folders** — no per-folder keys; buddies never decrypt files, they only store encrypted blobs
- **Config is encrypted** with master key before syncing to relay and to all connected buddies for recovery
- **Relay KV store** stores the encrypted config file with the **public key** (Base58) as the lookup key — optional for the user but **default is true**
- **Recovery only needs the 12 words** — no need to remember a buddy ID + pairing code. The mnemonic regenerates the asymmetric key, fetches the encrypted config from relay, decrypts it, and sync restores all folders
- **Buddy fallback**: if relay unavailable, recover from a buddy (need buddy ID + pairing code) — secondary path only
- **No selective restore** — sync automatically recreates missing local files
- **Recovery is opt-in** by default
- **GTK GUI** should have a nice recovery dialog with word grid and verification
- **Web GUI** serves recovery controls from the daemon's control server (browser-based, any device)
- **Config sync** happens during sync window (nightly) if config changed, and also via manual `buddydrive sync-config`
- **First config sync** should happen immediately after setup
- **No signing** needed for relay config uploads
- **No test recovery** during setup (redundant if verification step passes)

### TiDB Connection

```
Set via `TIDB_CONNECTION_STRING` environment variable (stored in Koyeb secrets)
```

Default KV API URL: `https://buddydrive-tankfeud-ddaec82a.koyeb.app`
Default TCP relay: `01.proxy.koyeb.app:19447`

### Recovery CLI Commands

```bash
buddydrive setup-recovery    # Generate mnemonic, verify, encrypt config, sync to relay
buddydrive recover           # Enter mnemonic, fetch encrypted config from relay, decrypt, restore
buddydrive sync-config       # Manually push encrypted config to relay
buddydrive export-recovery   # Export recovery info (mnemonic, public key)
```

### Recovery Files

| File | Purpose |
|------|---------|
| `src/buddydrive/recovery.nim` | BIP39 mnemonic, key derivation, config encryption |
| `src/buddydrive/sync/config_sync.nim` | Config sync to relay/buddies, recovery logic |
| `relay/src/kvstore.nim` | TiDB MySQL interface for config KV store |
| `relay/src/kvstore_api.nim` | HTTP API for KV store (GET/PUT/DELETE /kv/<pubkey>) |
| `wordlists/bip39_english.txt` | BIP39 English wordlist (2048 words) |

### Build/Lib Discoveries

- `curly` HTTP library requires `--mm:arc or --mm:orc` and `--threads:on`
- `curly` timeout is passed as a parameter to get/put/post/delete, not set on the client object
- `curly` delete signature: `delete(curl: Curly, url: string, headers: sink HttpHeaders = emptyHttpHeaders(), timeout = 60): Response`
- `curly` put signature: `put(curl: Curly, url: string, headers: sink HttpHeaders = emptyHttpHeaders(), body: openarray[char] = "".toOpenArray(0, -1), timeout = 60): Response`
- `libsodium`'s `crypto_pwhash` signature: `crypto_pwhash(passwd: string, salt: openArray[byte], outlen: Natural, alg = phaDefault, opslimit = ..., memlimit = ...): seq[byte]`
- `libsodium`'s `crypto_generichash` signature: `crypto_generichash(data: string, hashlen: int = ..., key: string = ""): seq[byte]` — NOT `crypto_generichash_blake2b`
- `crypto_generichash` returns `seq[byte]` not `string`, so assignment to `array[32, byte]` requires explicit `byte()` casts
- Nim's `reversed()` returns `seq[char]` not `string`, so base58 encoding needed manual reversal
- Chronos async procs have strict exception tracking — calls to functions that can raise `SodiumError` must be wrapped in try/except
- Chronos async procs also enforce GC-safety — `deserializeConfigFromSync` calls `loadConfig` which calls `parseFile` which is not GC-safe, causing build failure
- `webby/httpheaders` needed for `emptyHttpHeaders()` used by curly
- `std/options` needed for `Option`/`some`/`none`

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
  - Session-based sync coordination ✓

- Phase 5: Encryption - COMPLETE ✓
  - libsodium secretbox for content ✓
  - Password-based key derivation ✓
  - Encrypted filename support ✓

- Phase 6: Debian packaging - COMPLETE ✓
  - debian/ directory with control, rules ✓
  - systemd service unit file ✓
  - Makefile for build/package ✓

### Recovery System Progress

- Phase 1: BIP39 wordlist + `RecoveryConfig` type + `recovery` field on `AppConfig` — COMPLETE
- Phase 2: `recovery.nim` (mnemonic gen, validation, key derivation, config encrypt/decrypt, base58) — COMPLETE
- Phase 3: `config_sync.nim` (relay sync, buddy sync, recovery logic) — COMPLETE
- Phase 4: Relay KV store (`kvstore.nim` + `kvstore_api.nim` using Mummy) — COMPLETE
- Phase 5: `config.nim` loads/saves `[recovery]` section — COMPLETE
- Phase 6: CLI commands (`setup-recovery`, `recover`, `sync-config`, `export-recovery`) — COMPLETE
- Phase 7: `daemon.nim` loads master key on startup — COMPLETE
- Phase 8: REST API recovery endpoints — COMPLETE
- Phase 9: Tests — COMPLETE
- Phase 10: Web GUI merged from `simple-web-gui` branch — COMPLETE

### Remaining Work

- GTK GUI: BIP39 recovery dialog with word grid and verification of random words
- End-to-end test of full recovery flow against Koyeb relay
- Add recovery controls to web GUI

### Test Coverage

**Existing tests:**
- `test_sync_policy.nim` — sync window, append-only policy (PASSING)
- `test_recovery.nim` — BIP39 mnemonic gen, validation, key derivation determinism, hex round-trip, setup/verify, recover-from-mnemonic, encrypt/decrypt round-trip, wrong key rejection, full recovery flow, word helpers (PASSING)
- `test_kv_api.nim` — KV API PUT/GET/DELETE, overwrite, missing key 404, /health (compiles, needs Koyeb KV API)
- `test_config_sync_e2e.nim` — sync to relay + recover, attemptRecovery flow, wrong mnemonic, idempotent sync (compiles, needs Koyeb KV API)
- `test_relay_file_sync.nim` — forward sync A→B, reverse sync B→A (restores missing files), append-only folder (compiles, needs relay)
- `test_relay_fallback.nim` — relay pairing (compiles, needs relay)
- `test_peer_discovery.nim` — DHT discovery (needs port availability)

**Tests still to add:**
- REST API recovery endpoint tests (POST /recovery/setup, /recovery/verify-word, /recovery/recover, GET /recovery, POST /recovery/sync-config)
- CLI integration test: run `buddydrive setup-recovery` and `buddydrive recover` as subprocesses
- Buddy-to-buddy config sync test (once `syncConfigToBuddy` is implemented)
- Relay with `-d:withKvStore` local integration test (start relay + KV API, test against it)
- Test that `buddydrive init --with-recovery` generates mnemonic and verifies
- Clean up unused imports in `recovery.nim`
- Update `daemon.nim` to derive folder keys from master key on startup
- Test full recovery flow end-to-end
- Test end-to-end sync between two machines with real connectivity
- Improve DHT discovery reliability with bootstrap nodes
- Add UPnP auto-configuration for easier setup
- Implement proper background daemon mode (currently stays in foreground)
- Add live connection status to `buddydrive status` command

---

## Architecture Notes

### Control Server / State Management

The BuddyDrive daemon includes a control server running on `0.0.0.0:17521` by default that provides a REST API for monitoring and configuration. Both the web GUI and GTK4 GUI communicate with the daemon via this API.

**Web GUI:**
- Served from the control server at `http://127.0.0.1:<port>/` (localhost) and `http://<ip>:<port>/w/<secret>/` (LAN)
- LAN access requires a secret path derived from the buddy UUID
- Assets are embedded in the binary at compile time via `staticRead`
- Provides folder management, buddy pairing, settings, and log viewing

**State Storage:**
- `~/.buddydrive/config.toml` - Static configuration (identity, folders, buddies)
- `~/.buddydrive/state.db` - Runtime state (SQLite):
  - `runtime_status` - peer ID, addresses, daemon running status
  - `buddy_state` - connection state per buddy
  - `folder_state` - sync progress per folder
- `~/.buddydrive/index.db` - File metadata index (per-folder SQLite)

**Key Endpoints:**
- `GET /status` - Daemon status and identity
- `GET /buddies` - Buddy list with connection state
- `GET /folders` - Folder list with sync status
- `POST /folders` - Add folder
- `DELETE /folders/:name` - Remove folder
- `POST /buddies/pair` - Pair with buddy (requires buddy ID and code)
- `POST /buddies/pairing-code` - Generate pairing code
- `POST /config` - Update configuration
- `POST /sync/:folder` - Trigger folder sync

### GUI Configuration Dialogs

The GTK4 GUI provides comprehensive configuration:

1. **Add Folder Dialog** - Name, path, encryption toggle
2. **Pair Buddy Dialog** - Buddy ID, name (optional), pairing code
3. **Settings Dialog:**
   - Identity: Your buddy name
   - Network: Listen port, announce address
   - Relay: Base URL, region for fallback
   - Sync Window: Optional time restrictions (HH:MM format)

### Build Notes

- Uses `--threads:on` for multi-threading
- Control server uses `std/net` synchronous HTTP server in dedicated thread
- SQLite access via `db_connector/db_sqlite` (bundled with Nim 2.2.8+)
- Chronos async requires `{.cast(gcsafe).}` for cross-thread calls
- GTK4 GUI uses `gtk_editable_get_text` not `gtk_entry_get_text`
- Cdecl callbacks cannot capture locals; use `userData` with allocated strings

### Testing

Integration tests for DHT discovery and relay fallback are environment-dependent:
- Set `BUDDYDRIVE_STRICT_INTEGRATION=1` to make tests fail hard when services unavailable
- Without this flag, tests skip gracefully when environment doesn't support them

### Public Relay

A public relay is deployed on Koyeb for testing and production use:

- **TCP relay**: `01.proxy.koyeb.app:19447` (for NAT traversal)
- **KV API**: `https://buddydrive-tankfeud-ddaec82a.koyeb.app` (for encrypted config storage)
- **Region**: Frankfurt (fra)
- **Source**: `relay/` directory in repository

To deploy your own relay, see `../relay/README.md`.
