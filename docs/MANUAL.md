# BuddyDrive Manual

Complete reference for BuddyDrive CLI, GUI, configuration, and internals.

## Installation

### Prerequisites

- **Nim** 2.2.8 or later
- **libsodium** 1.0.18 or later
- **SQLite3** development headers
- **GTK4** development libraries (for native GUI, Linux only)
- **pkg-config** (for GUI build)
- **g++** (C++ compiler, required by libp2p's lsquic dependency)

### Linux (Debian/Ubuntu)

```bash
# Install Nim (using choosenim for version management)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
source ~/.nimble/bin/nim

# Install system dependencies (CLI)
sudo apt update
sudo apt install -y build-essential g++ git libsodium-dev libsqlite3-dev liblz4-dev

# Install GTK4 dependencies (for native GUI)
sudo apt install -y pkg-config libgtk-4-dev

# Clone and build
git clone https://github.com/gokr/buddydrive.git
cd buddydrive
nimble build        # Build CLI
nimble gui_release  # Build GTK4 GUI
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
nimble gui_release  # Build GTK4 GUI
```

### Installing the GTK4 GUI

After building, install with desktop integration:

```bash
nimble install_gui
```

This installs:

- `buddydrive-gui` binary to `~/.local/bin/`
- Desktop entry to `~/.local/share/applications/`
- Icons to `~/.local/share/icons/`

After installation, BuddyDrive will appear in your applications menu.

### Debian/Ubuntu Package

```bash
# Install build dependencies
sudo apt install -y build-essential g++ git libsodium-dev libsqlite3-dev liblz4-dev debhelper dpkg-dev help2man

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

## CLI Reference

### Commands

| Command | Description |
|---------|-------------|
| `buddydrive init` | Generate identity and create config |
| `buddydrive init --with-recovery` | Generate identity and set up recovery in one step |
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

### add-folder Options

| Flag | Description |
|------|-------------|
| `--name <name>` | Friendly name for the folder |
| `--no-encrypt` | Disable the folder's encryption flag in config |
| `--append-only` | Only accept new incoming files for that folder |
| `--buddy <id>` | Restrict the folder to a specific buddy |

### add-buddy Options

| Flag | Description |
|------|-------------|
| `--generate-code` | Generate a pairing code using the current local identity |
| `--id <buddy-id>` | Buddy ID to pair with |
| `--code <code>` | Pairing code from the buddy |

### start Options

| Flag | Description |
|------|-------------|
| `--port <control-port>` | Override control API port (default 17521) |
| `--daemon` | Accepted, but currently continues in the foreground |

### Current CLI Limitations

- `buddydrive start --daemon` currently prints a note and continues in the foreground
- `buddydrive stop` is not implemented yet; use your process manager or `Ctrl+C`
- `buddydrive status` does not yet query the running daemon for live connection state
- `buddydrive connect` does not perform a manual direct dial yet
- `buddydrive recover` currently restores configuration from the relay path; the buddy fallback prompt is present, but that fetch path is not implemented yet
- `buddydrive export-recovery` does not reveal the original 12-word phrase because the phrase is not stored locally

## Concepts

### Buddy Identity

When you run `buddydrive init`, your instance gets:

- **Buddy ID** — a UUID that uniquely identifies your BuddyDrive instance
- **Buddy Name** — a human-readable name (adjective-noun format like "purple-banana") displayed in outputs and shared during handshake

### Pairing

To sync folders with someone, both sides add each other:

1. Generate a pairing code with `buddydrive add-buddy --generate-code`
2. Share your Buddy ID and pairing code with your buddy
3. Your buddy runs `buddydrive add-buddy --id <your-id> --code <pairing-code>`
4. Repeat in reverse on the other side

The pairing code serves two purposes:

- Confirms you are pairing with the right person
- Acts as the shared secret for relay fallback

### Recovery and Restore

BuddyDrive can store enough encrypted config in the relay to rebuild a machine later:

1. Run `buddydrive setup-recovery`
2. Write down the generated 12-word recovery phrase
3. BuddyDrive derives a master key, saves recovery metadata in `config.toml`, and syncs an encrypted config blob to the relay
4. On a replacement machine, run `buddydrive recover`, enter the same 12 words, then start the daemon to resync folders

Restore happens in two layers:

- **Config restore** — `buddydrive recover` fetches your encrypted config from the relay and writes `~/.buddydrive/config.toml`
- **File restore** — once the daemon is running again, normal sync recreates missing local files from your buddy

Append-only folders still protect existing local files from being overwritten by the remote copy.

### Folder Policies

- **Encrypted** — folder encryption flag (default true). Note: application-level encryption for synced folder contents is not wired into the active sync path yet
- **Append-only** — prevents remote overwrites of existing local files. Missing files are still created
- **Buddy-specific** — restrict a folder to sync with a specific buddy

### Sync Window

Time-based scheduling restricts sync to a window. Configure with:

```bash
buddydrive config set sync-window-start 22:00
buddydrive config set sync-window-end 06:00
```

When both fields are empty (default), sync runs at all times.

## How It Works

### Peer Discovery

1. `buddydrive init` creates a local buddy identity and config file
2. `buddydrive start` creates the libp2p node for the running session
3. The daemon publishes your address to the relay at `/discovery/<derived-key>`, where the key is derived from the pairing code
4. The daemon looks up configured buddies using the same derived key via the relay KV-store (every 10 minutes)
5. It connects directly when a public TCP address is available, or via relay fallback when configured
6. Cached addresses in `state.db` are used for graceful degradation when the relay is unavailable

### Recovery and Transport Security

- Direct libp2p connections use Noise transport encryption
- Recovery setup derives a 32-byte master key from the 12-word phrase
- Config sync encrypts the serialized config blob with the master key before uploading it to the relay KV store
- Normal sync restores missing files by comparing remote file lists with the local folder state

### Sync Protocol

1. Scans folder for changes (polling-based)
2. Exchanges file lists with buddy
3. Requests missing files
4. Transfers chunks (64KB, LZ4 compressed when beneficial)
5. Both sides update SQLite index
6. File writes use atomic `.buddytmp` + `flushFile` + `moveFile` for crash safety

### NAT Traversal

- **Public TCP address** — direct connection when `announce_addr` points to a reachable public address
- **UPnP** — automatic port forwarding attempt when no explicit `announce_addr` is set
- **Relay fallback** — used when `relay_region` is set and both sides store the same buddy `pairing_code`

### Connectivity

For direct connections, forward the configured `listen_port` on your router and set `[network].announce_addr` in `~/.buddydrive/config.toml` to a public multiaddr such as `/ip4/<public-ip>/tcp/41721`.

For relay fallback, configure relay region. The stored pairing code is reused as the relay shared secret:

```bash
buddydrive config set relay-base-url https://buddydrive.net/relays
buddydrive config set relay-region eu
```

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

### Data Files

| Location | Purpose |
|----------|---------|
| `~/.buddydrive/config.toml` | Static configuration (identity, folders, buddies, recovery) |
| `~/.buddydrive/state.db` | Runtime state (SQLite): `runtime_status`, `buddy_state`, `folder_state`, `cached_buddy_addrs` |
| `~/.buddydrive/index.db` | File metadata index (SQLite) |
| `~/.buddydrive/port` | Control API port (written after daemon startup) |
| `~/.buddydrive/buddydrive.log` | Log file |

## Web GUI

The daemon serves a browser-based UI on the control port. It uses the same REST API as the CLI:

- **Localhost access**: `http://127.0.0.1:<port>/` — no authentication needed
- **LAN access**: `http://<ip>:<port>/w/<secret>/` — secret path derived from buddy UUID (first 8 chars, lowercase, no hyphens)
- Assets are embedded in the binary at compile time via `staticRead` — no external files needed
- The web GUI provides folder management, buddy pairing, settings, and log viewing

## Control API

REST API served by the daemon on `0.0.0.0:17521` by default. The actual port is written to `~/.buddydrive/port` after startup.

### Authentication

- **Localhost** (`127.0.0.1`, `::1`): No authentication required.
- **LAN**: Requests from non-localhost addresses must use a secret path prefix `/w/<secret>/`. Requests without the correct prefix receive `403 Forbidden`.

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/status` | Daemon status and identity |
| GET | `/buddies` | Buddy list with connection state |
| POST | `/buddies/pairing-code` | Generate pairing code |
| POST | `/buddies/pair` | Pair with a buddy (requires buddy ID and code) |
| DELETE | `/buddies/:id` | Remove a buddy |
| GET | `/folders` | Folder list with sync status |
| POST | `/folders` | Add folder |
| DELETE | `/folders/:name` | Remove folder |
| POST | `/sync/:folderName` | Trigger folder sync |
| GET | `/config` | Current saved configuration |
| POST | `/config` | Update selected config fields (returns `restartRequired` when needed) |
| POST | `/config/reload` | Reload configuration from disk |

### Recovery Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/recovery/setup` | Set up recovery with BIP39 mnemonic |
| POST | `/recovery/verify-word` | Verify a single word from the recovery phrase |
| POST | `/recovery/recover` | Restore config from 12-word mnemonic |
| GET | `/recovery` | Show current recovery status |
| POST | `/recovery/export` | Export recovery info |
| POST | `/recovery/sync-config` | Manually push encrypted config to relay KV store |

### Error Responses

All errors follow this format:

```json
{
  "error": "Description",
  "code": "ERROR_CODE"
}
```

Common error codes: `FOLDER_NOT_FOUND`, `BUDDY_NOT_FOUND`, `INVALID_REQUEST`, `NOT_FOUND`, `INTERNAL_ERROR`, `NO_CONFIG`, `ALREADY_SETUP`, `NOT_SETUP`, `INVALID_MNEMONIC`, `MISMATCH`, `SYNC_FAILED`

### Notes

- `POST /config` returns `restartRequired` when the daemon needs a restart for changes to take effect
- The daemon also reloads config from disk automatically when `config.toml` changes (polls mtime in the discovery loop)

## Security

### Current Security Layers

| Component | Algorithm | Purpose |
|-----------|-----------|---------|
| Direct peer transport | libp2p Noise | Encrypt direct libp2p connections |
| Recovery config backup | libsodium `crypto_secretbox` | Encrypt config synced to relay |
| Pairing code | Shared secret | Match buddies, derive discovery keys, HMAC-authenticate relay records, relay fallback |
| Recovery phrase | 12-word mnemonic | Re-derive recovery metadata on a new machine |

### Threat Model

**Protected against:**

- Network interception on direct libp2p connections (Noise transport)
- Relay compromise for config backup (encrypted with recovery master key)
- Lost machine (recovery rebuilds config, sync restores files)

**Not protected against:**

- Untrusted buddies (paired buddies can receive your synced files)
- Machine compromise (malware can read files before or during sync)
- Denial of service (attacker can prevent peer connections)

### Current Scope Limit

Application-level encryption for synced folder contents is not wired into the active sync path yet. Pair only with buddies you trust to hold your files.

## Relay Server

The relay enables NAT traversal and encrypted config storage. See [relay/README.md](../relay/README.md) for full details.

### Public Relay

- **TCP relay**: `01.proxy.koyeb.app:19447` (for NAT traversal)
- **KV API**: `https://buddydrive-tankfeud-ddaec82a.koyeb.app` (for encrypted config storage)
- **Region**: Frankfurt (fra)

### Self-Hosted Relay

```bash
# TCP relay only (default port 41722)
./buddydrive-relay

# With KV store (requires TIDB_CONNECTION_STRING)
export TIDB_CONNECTION_STRING="mysql://user:pass@host:4000/buddydrive"
./buddydrive-relay 41722 8080
```

Docker and Koyeb deployment options are documented in [relay/README.md](../relay/README.md).

## Troubleshooting

### Daemon won't start

```bash
buddydrive logs
buddydrive config
```

### Can't connect to buddy

1. Both peers need internet access
2. Both peers need `buddydrive start` running
3. Check stored buddies with `buddydrive list-buddies`
4. For direct mode, verify port forwarding and `announce_addr`
5. For relay mode, verify `relay-region`, `relay-base-url`, and matching pairing codes

### Files not syncing

1. Check daemon logs with `buddydrive logs`
2. Check folder configuration with `buddydrive list-folders`
3. `buddydrive status` does not show live connection state yet
4. Missing files are restored through normal sync after connectivity returns

### Address already in use

Set different `listen_port` values in each instance's config, and use different `--port` values when starting the daemons.

### `buddydrive status` shows buddies as offline

Expected. The CLI status command reads configured state and sync window, but does not yet report live daemon connectivity.

## Roadmap

- [ ] Delta sync (rolling hash)
- [x] GTK4 desktop app
- [x] Web GUI (browser-based, served from daemon)
- [x] Bandwidth limiting
- [ ] System tray integration
- [ ] Auto-start on boot
- [ ] Package for distros (deb, rpm, brew)
- [ ] Multiple buddies per folder
- [ ] Selective sync (ignore patterns)
- [ ] Version history
