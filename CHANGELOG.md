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
- Integration tests for pairing, relay fallback, and file sync are now
  self-contained: an in-process TCP relay stand-in (`tests/support/test_relay.nim`),
  a KV API stub that verifies Ed25519 signatures for real
  (`tests/support/kv_stub.nim`), and isolated per-process config and index
  directories. New coverage includes bidirectional sync in a single session,
  deletion propagation, append-only folders ignoring a remote delete, and
  mismatched pairing codes failing to meet on the relay. Previously the relay
  tests had been dead since the relay server moved to its own repository.
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
- Append-only folders now also reject remote deletions, not just overwrites.
- Network-touching integration tests no longer convert real failures into
  unittest skips, which testament had counted as passes.
- Key derivation was upgraded from the Argon2i interactive tier (64 MB) to the
  moderate tier (256 MB) for stronger GPU/ASIC resistance.
- A single master key derived from the recovery phrase is now used for all
  folders, replacing per-folder keys.
- Documentation was consolidated under `docs/`, the website is deployed via
  GitHub Pages, and Debian packaging gained man pages, tmpfiles configuration,
  and a postinst script.

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
- Data loss during sync: a file that existed on only one side was deleted on
  the buddy instead of being replicated, because the outbound delta treated
  any remote path the local machine lacked as a deletion and removed it from
  the pull projection. A remote path is now deleted only when the local index
  shows it was held before; anything never seen locally stays in the
  projection and gets pulled. Index rows for missing files are pruned only
  after deletions have propagated, so a failed session at worst resurrects a
  deleted file rather than losing a live one. Restoring onto an empty machine
  now fetches the buddy's files instead of wiping them.
- Sync sessions over the relay failing at the end even though all files had
  arrived: the peer that finished first closed the connection while the other
  was still awaiting file acknowledgements and the final sync-done, and the
  relay tore down both halves and dropped buffered data. Sessions now end
  with an explicit `msgSessionEnd` exchange whose speaking order is derived
  from the same UUID comparison that orders the delta phases; peers running
  an older version only cost a timeout instead of a failed session.
- `recover` printed "Could not recover from relay" both when no config was
  stored for the recovery phrase and when the config service was unreachable.
  It now distinguishes the two: "no config is stored for this recovery
  phrase" versus "the service could not be reached, your config may still be
  stored, try again later" (`fetchConfigFromRelayChecked` reports found,
  missing, or unavailable).
