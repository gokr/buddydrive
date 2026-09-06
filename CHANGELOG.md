# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

This entry summarizes the project's initial development period (2026-04-09 through
2026-04-26). No commits fall within the last 90 days; the window was extended back
to cover the most recent work.

### Added

- Buddy pairing protocol and encrypted file synchronization between paired
  devices, built on a libp2p node with CLI configuration management.
- GTK4 desktop application (`buddydrive-gui`) with folder, pairing, and buddy
  management dialogs.
- Web-based admin GUI served by the daemon's control server on
  `localhost:17521`, using the same REST API.
- Control server REST API (`/status`, `/buddies`, `/folders`, `/config`,
  `/logs`, pairing, and sync endpoints) backed by a SQLite `state.db` for
  runtime status, buddy connections, and folder sync state.
- Recovery system: a BIP39 12-word mnemonic as a single recovery secret, an
  asymmetric master key derived from it, and encrypted configuration synced to
  the relay and buddies. Includes `setup-recovery`, `recover`, `sync-config`,
  and `export-recovery` CLI commands, REST recovery endpoints, and recovery
  controls in the GTK GUI.
- Crash-safe file sync: received files are written to `.buddytmp` temp files,
  fsynced, then atomically renamed; leftover temp files are cleaned up on
  daemon startup.
- Relay fallback so synchronization continues when direct peer connections
  fail.
- Debian packaging with a systemd service unit, man pages, tmpfiles
  configuration, and a `postinst` script; `Makefile` targets for building and
  packaging.
- Testament-based test suite with unit and integration tests and per-category
  nimble tasks.
- Bandwidth throttling configuration.
- LAN access to the web GUI via a `/w/<secret>/` path prefix derived from the
  buddy UUID, replacing HTTP Basic Auth.
- Runtime config reload: the daemon checks `config.toml` for changes every
  15 seconds and logs sync window state transitions.
- A dedicated incoming storage base path for data received from buddies.
- Project website with a GitHub Pages deployment workflow.

### Changed

- Peer discovery now uses the relay's KV-store (`/discovery/<key>` endpoint
  with HMAC authentication and a 6-hour TTL, keyed on pairing codes) instead
  of Kademlia DHT. Last-known buddy addresses are cached in `state.db` for
  graceful degradation when the relay is unreachable.
- New sync model: streaming blake2b file hashing, deterministic path
  encryption, per-chunk encryption with random nonces, and per-folder keys
  derived from the master key and folder UUID rather than the folder name.
- Recovery mnemonics use standard BIP39 generation (128-bit entropy with a
  SHA-256 checksum), so validation catches single-word transcription errors.
  Key derivation was raised from the `interactive` to the `moderate` Argon2i
  tier (256 MB memory limit).
- Sync scheduling and configuration management exposed through the daemon API
  and GTK app, including daemon start/stop, per-buddy sync times, and richer
  config editing.
- The relay server was moved out of this repository into the separate
  [buddydrive-relay](https://github.com/gokr/buddydrive-relay) repository.
- `relayToken` was renamed to `pairingCode` and `relayBaseUrl` to `apiBaseUrl`
  across source, tests, and documentation; an empty `api_base_url` now falls
  back to `https://api.buddydrive.org`.
- The default relay TCP port changed from 19447 to 41722.
- A `GET /relays/<region>` endpoint serves TCP relay addresses per region.
- Folder keys are base64-encoded in the configuration for safe HTTP transport.
- Web GUI assets are served from disk at runtime instead of being embedded at
  compile time.

### Fixed

- Double-nonce bug in the encrypt/decrypt round trip.
- `flushAndClose` failures no longer leave a partially received file in place.
- DNS relay resolution: `/dns4/` and `/dns6/` multiaddresses are resolved to
  IP addresses before connecting, as the raw TCP transport requires wire
  addresses.
- Daemon startup error handling and a pairing protocol mount failure when the
  switch was already started.
- Settings dialog not showing saved values and header overflow on mobile.
- `libsodium.dylib` loading on macOS and build issues with pinned zlib and
  `results` dependency versions.

### Security

- Removed the leaked TiDB credential from `PLAN.md` and the
  `BUDDYDRIVE_TOKENS` whitelist from the relay.
- Hardened the relay and KV store against abuse, and packaged manual EU CIDR
  snapshots for relay builds.
