# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Core daemon and CLI built on libp2p: `init`, `add-folder`, `add-buddy` with
  pairing codes, `start`, and related subcommands, backed by TOML configuration.
- Buddy pairing protocol and encrypted file sync infrastructure, with
  deterministic initiator selection, UPnP attempts, and relay fallback when
  direct connections fail.
- Encrypted backup of synced files (filenames and content) on the buddy's
  machine, using deterministic path encryption for move detection and random
  content nonces.
- Content-hashed sync with streaming Blake2b hashing, move and delete
  detection, and re-sync of files that exist on the buddy but are missing
  locally (verified by hash).
- Recovery system: 12-word BIP39 recovery phrase with SHA-256 checksum
  (validated against the official BIP39 test vectors), Ed25519 master key
  derived from the mnemonic via Argon2i, and encrypted config sync to the
  relay and buddies. New CLI commands: `setup-recovery`, `recover`,
  `sync-config`, `export-recovery`.
- Crash-safe file receiving: incoming files are written to `.buddytmp` temp
  files, fsynced, then atomically renamed; leftover temp files are cleaned up
  on daemon startup.
- Folder policies: append-only mode that prevents remote overwrites of
  existing local files (including re-sync when the local hash differs from
  the remote, catching corrupt or partial files), and a per-folder encryption
  flag.
- Per-buddy sync scheduling; incoming connections are always accepted.
- Web-based admin GUI served from the daemon's control server, with
  LAN secret-path authentication and runtime config reload.
- GTK4 desktop GUI (Linux) for monitoring and configuration.
- Daemon control server with SQLite state and a REST API, including recovery
  and restore endpoints, plus a dedicated storage base path for incoming
  buddy data.
- Testament-based test suite with unit and integration tests covering crypto,
  pairing, discovery, sync, crash safety, and relay/KV integration.
- Relay server KV-store API with HMAC-authenticated discovery records,
  a `/relays/<region>` endpoint for per-region TCP relay addresses, packaged
  EU CIDR snapshots, and abuse hardening.

### Changed

- Peer discovery now uses the relay KV store instead of KadDHT: buddy
  addresses are published and looked up via pairing-code-derived,
  HMAC-authenticated records with a 6-hour TTL, and last-known addresses are
  cached in `state.db` for graceful degradation. The discovery interval moved
  from 15 seconds to 10 minutes.
- The relay server was moved to the separate
  [buddydrive-relay](https://github.com/gokr/buddydrive-relay) repository and
  removed from this one.
- `relayBaseUrl` was renamed to `apiBaseUrl` throughout the config, CLI, and
  API, with `https://api.buddydrive.org` as the default when unset.
- The relay TCP port changed from 19447 to 41722.
- Key derivation was upgraded from the Argon2i interactive tier (64 MB) to the
  moderate tier (256 MB) for stronger GPU/ASIC resistance.
- A single master key derived from the recovery phrase is now used for all
  folders, replacing per-folder keys.
- Documentation was consolidated under `docs/`, the website is deployed via
  GitHub Pages, and Debian packaging gained man pages, tmpfiles configuration,
  and a postinst script.
- Integration tests are now self-contained and fail loudly. Network-touching
  tests previously swallowed real failures as unittest skips — which Testament
  counts as passes — and the relay tests had been non-functional since the relay
  moved to its own repository. They now use an in-process TCP relay stand-in
  (`tests/support/test_relay.nim`), a KV API stub that verifies Ed25519 signatures
  for real (`tests/support/kv_stub.nim`), and per-process isolated data
  directories. New coverage includes bidirectional sync in one session,
  deletion propagation, append-only ignoring a remote delete, mismatched pairing
  codes, and the session-end exchange.

### Fixed

- Double-nonce bug in `encrypt`/`decrypt` that produced a corrupted
  nonce-prefixed ciphertext and broke decryption.
- Crash when mounting the pairing protocol handler on an already-started
  libp2p switch.
- GTK settings dialog not showing saved values, and header overflow on mobile.
- Daemon startup error handling, and a case where a file was moved even though
  `flushAndClose` had failed.
- DNS relay resolution: `/dns4/` and `/dns6/` multiaddresses are now resolved
  to IP addresses before dialing, as the raw TCP transport requires wire
  addresses.
- macOS build and runtime: `libsodium.dylib` loading and the missing
  `liblz4-dev` dependency.
- Sync no longer deletes files that exist on only one side. `computeOutboundDelta`
  treated a path the buddy holds but the local machine does not as a delete
  instruction and dropped it from the pull projection, so the file was destroyed
  on the buddy instead of being replicated — restoring onto an empty machine
  would have wiped the buddy's copy while reporting a successful sync. A remote
  path is now deleted only when the local index shows it was held before;
  `rebuildIndexFromDisk` no longer prunes rows for vanished files (pruning moved
  to `pruneIndexOfMissingFiles`, run after deletions are propagated), so a failed
  session errs toward a deleted file returning rather than a live file going away.
- Append-only folders now reject deletions as well as overwrites; previously
  `deleteLocalFile` was not covered by the policy.
- Sync sessions through the relay no longer fail at the end when one peer
  finishes first. The finishing peer closed the connection while the other was
  still waiting for a file ack and the final `sync-done`, and the relay tore down
  both halves, dropping buffered data so the slower peer saw a truncated stream.
  Sessions now end with an explicit `msgSessionEnd` exchange, ordered by the same
  UUID comparison that orders the delta phases; the message kind was appended so
  existing byte values are unchanged, and an older buddy only costs a timeout.
- Recovery no longer reports "Could not recover from relay" when the config
  service is merely unreachable. `fetchConfigFromRelay` now distinguishes found,
  missing, and unavailable, so `attemptRecovery` tells a user rebuilding a lost
  machine to retry later instead of implying no config is stored for their phrase.
