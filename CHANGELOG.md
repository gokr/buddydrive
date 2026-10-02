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
- Append-only folders now also refuse remote deletions, not only remote
  overwrites, so existing local files cannot be removed by the buddy.
- The integration test suite is self-contained and fails loudly: removed the
  failure-swallowing wrappers and `|| true`, added an in-process TCP relay
  stand-in and a signature-verifying KV API stub, and isolated each test run
  in a fresh config and index directory.

### Fixed

- Sync no longer deletes files that exist on only one side. A remote path is
  deleted only when the local index shows it was held before; paths never seen
  locally are pulled instead. This previously destroyed one-sided files and
  could wipe a buddy's copy when restoring onto an empty machine.
- Sync sessions now end with an explicit session-end exchange in a fixed
  order, so a peer cannot hang up while the buddy still has data in flight
  through a relay. Relayed syncs that transferred everything could previously
  report a truncated, failed session.
- Recovery now distinguishes "no config is stored for this recovery phrase"
  from "the config service could not be reached", instead of reporting an
  unreachable service as a missing backup.
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
