# AGENTS.md - BuddyDrive Development Guide

## Project Overview

BuddyDrive is a P2P encrypted folder sync tool written in Nim. It syncs folders with 1-2 buddies across the internet, bypassing NATs and firewalls. It includes a CLI daemon, a web GUI (embedded in the daemon), a GTK4 GUI, and a relay server.

## Build Commands

```bash
# Build CLI (default debug)
nimble build

# Build CLI (release)
nimble build -d:release
# or: nim c -d:release src/buddydrive.nim

# Build GTK4 GUI (debug)
nimble gui

# Build GTK4 GUI (release)
nimble gui_release

# Install GTK4 GUI with desktop integration
nimble install_gui

# Install icons
nimble icons

# Build relay server
nim c src/relay.nim
# With KV store support:
nim c -d:withKvStore src/relay.nim

# Run all tests
nimble test

# Run unit tests only
nimble testUnit

# Run integration tests only
nimble testIntegration

# Run a specific test suite
nimble testConfig
nimble testCrypto
nimble testRecovery
nimble testPolicy
nimble testScanner
nimble testIndex
nimble testMessages
nimble testConfigSync
nimble testControl
nimble testControlWeb
nimble testRawRelay
nimble testPairing
nimble testTransfer
nimble testCli
nimble testRelayServer

# Build Debian package
make deb
```

## Lint / Typecheck

There is no separate lint or typecheck command. The Nim compiler performs full type checking during build. Always run `nimble build` after making changes to verify correctness.

## Key Build Flags

- `--mm:arc` or `--mm:orc` — required by the `curly` HTTP library
- `--threads:on` — required by `curly`
- `-d:ssl` — enabled in config.nims
- `-d:gtk4` — enable GTK4 GUI build
- `-d:withKvStore` — enable TiDB KV store in relay
- `-d:chronicles_log_level=ERROR` — set in config.nims

## Architecture

### Source Layout

```
src/
├── buddydrive.nim              # CLI entry point, command dispatch
├── buddydrive_gui.nim          # GTK4 GUI entry point
├── web/                        # Web GUI assets (embedded via staticRead)
│   ├── index.html
│   ├── style.css
│   └── app.js
└── buddydrive/
    ├── types.nim               # Core types (AppConfig, BuddyId, FolderConfig, RecoveryConfig)
    ├── config.nim              # TOML config read/write (~/.buddydrive/config.toml)
    ├── crypto.nim              # libsodium encryption (XChaCha20-Poly1305)
    ├── recovery.nim            # BIP39 mnemonic, key derivation, config encrypt/decrypt
    ├── cli.nim                 # CLI subcommand handlers
    ├── daemon.nim              # Background sync daemon, discovery loop
    ├── control.nim             # REST API on localhost:17521, state.db management
    ├── control_web.nim         # Web GUI serving (staticRead + LAN secret auth)
    ├── logutils.nim            # Logging setup
    ├── nat.nim                 # NAT traversal (UPnP, CGNAT detection)
    ├── p2p/
    │   ├── node.nim            # libp2p node setup
    │   ├── discovery.nim       # KV-store relay discovery (publish/lookup via relay, HMAC auth)
    │   ├── protocol.nim        # BuddyDrive sync protocol
    │   ├── pairing.nim         # Buddy pairing handshake
    │   ├── messages.nim        # Protocol message types
    │   ├── rawrelay.nim        # Relay client for NAT fallback
    │   └── synchandler.nim     # Sync handler
    └── sync/
        ├── scanner.nim         # Polling file scanner, chunk I/O, .buddytmp atomic writes
        ├── index.nim           # SQLite file index
        ├── transfer.nim        # Chunked file transfer (64KB, LZ4 compression)
        ├── session.nim         # Sync sessions
        ├── policy.nim          # Sync policy (sync window, append-only, shouldSyncRemoteFile)
        └── config_sync.nim     # Config sync to relay/buddies, recovery logic
```

### Relay Server

```
relay/src/
├── relay.nim                  # Main relay server (mummy HTTP + TCP relay)
├── kvstore.nim                # TiDB Cloud MySQL KV store
├── kvstore_api.nim            # HTTP API: /kv/<pubkey>, /discovery/<key>
├── geoip_policy.nim           # EU-only KV access enforcement
└── geoip_ranges.nim          # CIDR range matching
```

### Other Directories

```
icons/                          # Application icons (48x48 through 512x512)
wordlists/                      # BIP39 English wordlist + name generation lists
  ├── bip39_english.txt
  ├── adjectives.txt
  └── nouns.txt
debian/                         # Debian packaging (control, rules, service, manpages)
website/                        # Static website content (docs, features, security, how-it-works)
tests/
  ├── testutils.nim            # Shared test helpers (withTestDir, strictIntegration, etc.)
  ├── unit/*/*.nim             # Unit tests
  └── integration/*.nim        # Integration tests
```

### Config & Data

- `~/.buddydrive/config.toml` — Static config (identity, folders, buddies, recovery)
- `~/.buddydrive/state.db` — Runtime state (SQLite): tables `runtime_status`, `buddy_state`, `folder_state`, `cached_buddy_addrs`
- `~/.buddydrive/index.db` — File metadata index (SQLite)
- `~/.buddydrive/port` — Control API port (written after daemon startup)
- `~/.buddydrive/buddydrive.log` — Log file

### GUI / Control API

- **Web GUI**: Served from the daemon via `control_web.nim` using `staticRead` to embed `src/web/` assets. No external files needed.
- **GTK4 GUI**: Direct GTK4 (not Owlkettle). Reads control API port from `~/.buddydrive/port`.
- **Control API**: REST server on `0.0.0.0:17521` (default). Localhost: no auth. LAN: secret path `/w/<secret>/` derived from buddy UUID.
- Dynamic daemon state lives in `state.db`; static configuration lives in `config.toml`
- GTK4 text entry widgets use `gtk_editable_get_text` (not `gtk_entry_get_text`)
- Cdecl callbacks cannot capture locals; use `userData` with allocated strings

### Constants

- Default P2P port: `41721` (defined in `types.nim`)
- Default control port: `17521` (defined in `control.nim`)
- Discovery interval: 10 minutes (`BuddyDiscoveryInterval` in `daemon.nim`)
- Discovery record TTL: 6h (server-side), re-published every 4h
- File chunk size: 64KB
- Transfer files use LZ4 compression when it reduces size

## Conventions

### Nim Style

- No comments in code unless explicitly requested
- Follow existing patterns in neighboring files
- Use `logutils` for logging (not raw `echo` except in CLI handlers)
- Use `parsetoml` for TOML parsing (not `toml-serialization`)
- Use `results` for error handling (`Result` type, not exceptions for expected failures)

### Async / GC Safety

- Chronos async procs enforce GC-safety — non-GC-safe calls (e.g., `parsetoml.parseFile`) must be wrapped with `{.cast(gcsafe).}:`
- Chronos async procs enforce exception tracking — calls that can raise `SodiumError` must be wrapped in `try/except`
- The control server runs synchronous HTTP in a dedicated thread
- SQLite access via `db_connector/db_sqlite` (bundled with Nim 2.2.8+)
- Chronos async requires `{.cast(gcsafe).}` for cross-thread calls

### Encryption

- libsodium via `libsodium/sodium` and `libsodium/sodium_sizes` imports
- `crypto_secretbox_easy` / `crypto_secretbox_open_easy` for config and file encryption
- `crypto_pwhash` for key derivation from passwords/mnemonics
- `crypto_generichash` for key derivation and content hashing (returns `seq[byte]`, not `string`)
- `crypto_generichash` signature: `crypto_generichash(data: string, hashlen: int, key: string = ""): seq[byte]`
- `crypto_pwhash` signature: `crypto_pwhash(passwd: string, salt: openArray[byte], outlen: Natural, alg, opslimit, memlimit): seq[byte]`
- `crypto_generichash` returns `seq[byte]` not `string`, so assignment to `array[32, byte]` requires explicit `byte()` casts
- **Streaming hash**: use `crypto_generichash_init/update/final` for large files — never read full file into memory
- **Deterministic path encryption**: derive nonce from `folderKey + "/path/" + plaintextPath` so same path always encrypts to same ciphertext (enables move detection)
- **Chunk encryption with random nonces**: each chunk gets a random nonce (24 bytes, prepended to ciphertext). Deterministic nonces are unsafe for content — same (file, offset) may have different plaintext across versions, causing nonce reuse.
- **Folder key from stable ID**: `folderKey = generichash(masterKey + "/folder/" + folderId)`. `folderId` is a UUID, not the folder name, so renaming doesn't orphan remote data.

## Current Sync Model

The new sync model is now **largely implemented**. See `docs/PLAN.md` for the full design and remaining work. Key implemented features:

- **Encrypted backup model**: files stored encrypted on buddy's machine (filenames + content). Buddy is storage, not co-author.
- **Per-buddy sync_time**: replaces global sync window. Controls when to initiate, not when to accept.
- **Always accept incoming**: sync time controls initiation only. Incoming connections from known buddies are always accepted.
- **Deterministic initiator**: CGNAT side initiates (dials the public side). If both public, lower UUID initiates.
- **Streaming blake2b hash**: `crypto_generichash_init/update/final` — 64KB chunks, never full file in memory.
- **Deterministic path encryption**: same path → same encrypted path. Enables move detection.
- **Random content nonces**: each chunk encrypted with random nonce (prepended). Same file encrypted twice produces different ciphertext — prevents nonce reuse.
- **Content-hash-based sync**: owner sends plaintext blake2b hash to storage buddy. Detects changes, moves, and deletes.
- **Owner-authoritative moves**: A tells B "rename X to Y". B does not infer moves from ciphertext identity.
- **Delete propagation**: `msgFileDelete` is sent and handled.
- **Hash verification on restore**: `verifyRestoredFile` re-scans and checks hash after write.
- **SQLite index is cache**: both sides maintain indexes for performance, but restore only needs the folder key + buddy's filesystem.
- **Restore flow**: recover config from relay → connect to buddy → list encrypted paths → decrypt paths → request missing files → verify hashes → rebuild index

### Remaining Work

- **Buddy-backed config fetch**: `syncConfigToBuddy()` and `fetchConfigFromBuddy()` are not implemented yet. Recovery works via relay path only.
- **Connection reuse**: check for existing transport connections before new dial — not yet implemented.
- **Connection upgrade**: replace relay with direct when possible — not yet implemented.
- **Long-lived CGNAT connections**: keepalive and prompt redial — not yet implemented.
- **`init --with-recovery`**: parsed as CLI flag but does nothing. Use `init` then `setup-recovery`.
- **Large folder listings**: file list exchange uses a single framed message (30MB max). Pagination or streaming deferred.

### HTTP Client (curly)

- `curly` requires `--mm:arc/orc` and `--threads:on`
- Timeout is passed per-request, not set on client
- `webby/httpheaders` for `emptyHttpHeaders()`
- PUT body: `body: openarray[char] = "".toOpenArray(0, -1)`

### File I/O / Crash Safety

- Files are written to `<path>.buddytmp` first, then `flushFile` + `closeFile` + `moveFile` to final path
- On daemon startup, `cleanupTempFiles` deletes leftover `.buddytmp` files
- Scanner ignores `.buddytmp` files during scans
- Config writes use atomic temp-file + rename (`config.nim`)
- Use `fmReadWriteExisting` (not `fmReadWrite`) for subsequent chunks to avoid truncation

### Config Hot-Reload

- The daemon polls `config.toml` mtime in the discovery loop and reloads on change
- `POST /config/reload` on the control API forces a reload

## Key Dependencies

- **libp2p** — P2P networking, direct transport
- **libsodium** — Encryption, key derivation
- **parsetoml** — TOML parsing (not GC-safe, needs `{.cast(gcsafe).}` in async)
- **chronos** — Async framework
- **curly** — HTTP client (relay KV API, config sync)
- **mummyx** (fork) — HTTP server (relay)
- **debby** (fork) — MySQL ORM for relay KV store
- **db_connector/db_sqlite** — SQLite (bundled with Nim 2.2.8+)
- **db_mysql** — MySQL for relay KV store (TiDB Cloud)
- **results** — Result type for error handling
- **stew** — Utility types used by libp2p
- **uuids** — UUID generation for buddy/folder IDs
- **nat_traversal** — NAT hole punching (UPnP)
- **lz4wrapper** (fork) — LZ4 compression for file chunks
- **nim-zlib** (pinned) — zlib for libp2p; pinned because libp2p declares underspecified version

## Recovery System

See `docs/PLAN.md` for full details. Key points:

- BIP39 12-word mnemonic as single recovery secret
- Master key stored plaintext in config.toml
- Config encrypted before syncing to relay/buddies
- Public key (Base58) used as relay KV store lookup key
- TiDB Cloud for relay KV store
- Default KV API URL: `https://buddydrive-tankfeud-ddaec82a.koyeb.app`
- Default TCP relay: `01.proxy.koyeb.app:19447`

## Testing

Tests use `std/unittest` and run via testament with `nimble test`:

- **Unit tests**: `tests/unit/*/*.nim` — 17 test files covering config, crypto, recovery, messages, policy, scanner, transfer crash safety, control, control_web, rawrelay, index, pairing, types, config_sync, discovery, session, geoip_ranges
- **Integration tests**: `tests/integration/*.nim` — 7 test files covering CLI flows, KV API, config sync e2e, relay fallback, relay file sync, relay server, pairing protocol

Integration tests are environment-dependent:
- Set `BUDDYDRIVE_STRICT_INTEGRATION=1` to fail hard when services unavailable
- Without it, tests skip gracefully

Test environment variables:
- `BUDDYDRIVE_STRICT_INTEGRATION=1` — fail on unavailable services
- `BUDDYDRIVE_KV_API_URL` — override KV API URL (default: `https://buddydrive-tankfeud-ddaec82a.koyeb.app`)
- `BUDDYDRIVE_LOCAL_KV_DSN` — local KV database connection string

Test utilities (`tests/testutils.nim`):
- `withTestDir(baseName)` — create/cleanup temp directory
- `withTestFile(baseName, content)` — create/cleanup temp file
- `runWithStrictFallback` — run block, skip on failure unless strict mode
- `strictIntegration()` — check env var
- `makeFileInfo()` — create test FileInfo

## Debian Packaging

- `make deb` builds the `.deb` package
- Debian dir contains: control, rules, service unit, postinst, manpages
- Systemd service runs as `buddydrive` user
- Build requires: `debhelper dpkg-dev help2man`
- `make install` supports `DESTDIR` for packaging

## Nim Quirks / Discoveries

- `reversed()` returns `seq[char]` not `string`, so base58 encoding needed manual reversal
- `fmReadWrite` truncates existing files; use `fmReadWriteExisting` for subsequent chunks
- Nim's `std/options` needed for `Option`/`some`/`none`
- `toml-serialization` is NOT used — use `parsetoml` only
