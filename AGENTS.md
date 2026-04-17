# AGENTS.md - BuddyDrive Development Guide

## Project Overview

BuddyDrive is a P2P encrypted folder sync tool written in Nim. It syncs folders with 1-2 buddies across the internet, bypassing NATs and firewalls. It includes a CLI daemon, a GTK4 GUI, and a relay server.

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

# Build relay server
nim c src/relay.nim
# With KV store support:
nim c -d:withKvStore src/relay.nim

# Run tests
nimble test
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
└── buddydrive/
    ├── types.nim               # Core types (AppConfig, BuddyId, FolderConfig, RecoveryConfig)
    ├── config.nim              # TOML config read/write (~/.buddydrive/config.toml)
    ├── crypto.nim              # libsodium encryption (XChaCha20-Poly1305)
    ├── recovery.nim            # BIP39 mnemonic, key derivation, config encrypt/decrypt
    ├── cli.nim                 # CLI subcommand handlers
    ├── daemon.nim              # Background sync daemon
    ├── control.nim             # REST API on localhost:17521
    ├── logutils.nim            # Logging setup
    ├── nat.nim                 # NAT traversal
    ├── p2p/
    │   ├── node.nim            # libp2p node setup
    │   ├── discovery.nim       # KV-store relay discovery (publish/lookup via relay, HMAC auth)
    │   ├── protocol.nim        # BuddyDrive sync protocol
    │   ├── pairing.nim         # Buddy pairing handshake
    │   ├── messages.nim        # Protocol message types
    │   ├── rawrelay.nim        # Relay client for NAT fallback
    │   └── synchandler.nim      # Sync handler
    └── sync/
        ├── scanner.nim         # Polling file scanner
        ├── index.nim           # SQLite file index
        ├── transfer.nim        # Chunked file transfer
        ├── session.nim         # Sync sessions
        ├── policy.nim          # Sync policy
        └── config_sync.nim     # Config sync to relay/buddies, recovery logic
```

### Relay Server

```
relay/src/
├── relay.nim                  # Main relay server (mummy HTTP)
├── kvstore.nim                # TiDB Cloud MySQL KV store
├── kvstore_api.nim            # HTTP API: /kv/<pubkey>, /discovery/<key>
```

### Config & Data

- `~/.buddydrive/config.toml` — Static config (identity, folders, buddies, recovery)
- `~/.buddydrive/state.db` — Runtime state (SQLite)
- `~/.buddydrive/index.db` — File metadata index (SQLite)

### GUI / Control API

- Use direct GTK4, not Owlkettle
- The GUI should read the control API port from `~/.buddydrive/port`
- Dynamic daemon state lives in `state.db`; static configuration lives in `config.toml`
- GTK4 text entry widgets use `gtk_editable_get_text`

## Conventions

### Nim Style

- No comments in code unless explicitly requested
- Follow existing patterns in neighboring files
- Use `logutils` for logging (not raw `echo` except in CLI handlers)
- Use `parsetoml` for TOML parsing (not `toml-serialization`)

### Async / GC Safety

- Chronos async procs enforce GC-safety — non-GC-safe calls (e.g., `parsetoml.parseFile`) must be wrapped with `{.cast(gcsafe).}:`
- Chronos async procs enforce exception tracking — calls that can raise `SodiumError` must be wrapped in `try/except`
- The control server runs synchronous HTTP in a dedicated thread

### Encryption

- libsodium via `libsodium/sodium` and `libsodium/sodium_sizes` imports
- `crypto_secretbox_easy` / `crypto_secretbox_open_easy` for config encryption
- `crypto_pwhash` for key derivation from passwords/mnemonics
- `crypto_generichash` for key derivation (returns `seq[byte]`, not `string`)
- `crypto_generichash` signature: `crypto_generichash(data: string, hashlen: int, key: string = ""): seq[byte]`
- `crypto_pwhash` signature: `crypto_pwhash(passwd: string, salt: openArray[byte], outlen: Natural, alg, opslimit, memlimit): seq[byte]`

### HTTP Client (curly)

- `curly` requires `--mm:arc/orc` and `--threads:on`
- Timeout is passed per-request, not set on client
- `webby/httpheaders` for `emptyHttpHeaders()`
- PUT body: `body: openarray[char] = "".toOpenArray(0, -1)`

## Key Dependencies

- **libp2p** — P2P networking, direct transport
- **libsodium** — Encryption, key derivation
- **parsetoml** — TOML parsing (not GC-safe, needs `{.cast(gcsafe).}` in async)
- **chronos** — Async framework
- **curly** — HTTP client
- **mummy** — HTTP server (relay)
- **db_connector/db_sqlite** — SQLite (bundled with Nim 2.2.8+)
- **db_mysql** — MySQL for relay KV store (TiDB Cloud)

## Recovery System (in progress)

See `docs/PLAN.md` for full details. Key points:

- BIP39 12-word mnemonic as single recovery secret
- Master key stored plaintext in config.toml
- Config encrypted before syncing to relay/buddies
- Public key (Base58) used as relay KV store lookup key
- TiDB Cloud for relay KV store
- Relay URL: `https://01.proxy.koyeb.app`

## Testing

Tests use `std/unittest` and run via testament with `nimble test`:

- **Unit tests**: `tests/unit/*/*.nim` — 16 test files covering config, crypto, recovery, messages, policy, scanner, transfer crash safety, control, control_web, rawrelay, index, pairing, types, config_sync, discovery, geoip_ranges
- **Integration tests**: `tests/integration/*.nim` — 7 test files covering CLI flows, KV API, config sync e2e, relay fallback, relay file sync, relay server, pairing protocol

Integration tests are environment-dependent:
- Set `BUDDYDRIVE_STRICT_INTEGRATION=1` to fail hard when services unavailable
- Without it, tests skip gracefully
