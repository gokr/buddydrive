# BuddyDrive Project Summary

## Goal

Build **BuddyDrive** - a P2P encrypted folder sync tool in Nim that allows syncing folders with 1-2 friends across the internet, bypassing NATs and firewalls using libp2p. Also build **BuddyDrive Relay** - a simple TCP relay server for when direct P2P connections fail (CGNAT, firewall issues).

## Instructions

- Build CLI-first, then add UI later (Owlkettle for GTK4)
- Use libp2p for P2P networking (direct transport, NAT traversal)
- Use libsodium for encryption (XChaCha20-Poly1305)
- Config at `~/.buddydrive/`, SQLite for file index
- Standard Nim logging
- User wants **direct-only connectivity** when possible — relay fallback is a secondary option. If direct connection fails, show a clear diagnostic message.
- User wants **automatic UPnP port forwarding** so users don't have to manually configure routers
- User wants **relay fallback** when direct connection fails
- User wants **sync windows** (time-based scheduling)
- User wants **append-only folders** (ransomware protection)
- User wants **LZ4 compression** for file chunks

## Discoveries

- **DHT discovery was unreliable (resolved)**: Provider/value records on public IPFS DHT didn't reliably return results — replaced with KV-store relay discovery
- **CGNAT is common**: ISP-level NAT prevents UPnP from getting public IPs (100.64.0.0/10 range)
- **Relay design**: Simple token-based pairing, bidirectional byte pipe after handshake. No whitelist — any token is accepted.
- **Koyeb TCP Proxy**: Not suitable for multi-instance relay due to lack of session affinity - use single-instance per relay or deterministic sharding
- **Region-based relay selection**: User chooses region (EU, US, Asia), both buddies hash token to pick same relay from canonical list
- **File write bug**: `fmReadWrite` truncates existing files; use `fmReadWriteExisting` for subsequent chunks

## Accomplished

### BuddyDrive Relay (complete)
- Simple TCP relay server — any token accepted, no whitelist
- Idle timeout (5 min), bidirectional byte forwarding
- KV store for encrypted config blobs (optional, `-d:withKvStore`, TiDB Cloud backend)
- Docker image: Ubuntu 24.04 builder + runtime (libmysqlclient21 for TiDB SSL)
- Verified working: two `nc` clients paired successfully through container

### BuddyDrive (mostly complete)
- CLI framework with all commands
- libp2p networking with TCP transport, Noise encryption, and relay KV-store discovery
- UPnP port mapping (graceful fallback on failure/CGNAT)
- Relay fallback with region-based relay selection
- Sync window (time-based scheduling)
- Append-only folder flag
- LZ4 chunk compression in file transfer
- Real file sync over relay working (test harness passes)
- Config commands for all new features

### Commits Created
- `870d006` "Add relay fallback and controlled sync behavior"
- `7c8cbed` "Add harness coverage for relay and sync flows"

## Relevant files / directories

```
buddydrive/
├── buddydrive.nimble          # Dependencies (lz4wrapper, curly, nat_traversal)
├── src/
│   ├── buddydrive.nim         # Main entry
│   └── buddydrive/
│       ├── cli.nim            # CLI with sync-window, folder-append-only commands
│       ├── config.nim          # TOML config with all new fields
│       ├── types.nim           # AppConfig with syncWindowStart/End, FolderConfig.appendOnly
│       ├── daemon.nim          # Sync window checks, runBuddySync after pairing
│       ├── nat.nim             # UPnP with CGNAT detection
│       ├── p2p/
│       │   ├── rawrelay.nim    # Relay connector, regional resolver, TTL cache
│       │   ├── messages.nim    # Protocol with msgSyncDone, LZ4 compression fields
│       │   └── ...
│       └── sync/
│           ├── policy.nim      # Sync window parsing, shouldSyncRemoteFile
│           ├── session.nim    # Bidirectional folder sync session
│           ├── scanner.nim    # Fixed writeFileChunk for multi-chunk files
│           ├── transfer.nim   # LZ4 compress/decompress in send/receive
│           └── index.nim      # Fixed SQLite query API
└── tests/harness/
    ├── test_sync_policy.nim    # Sync window and append-only tests
    ├── test_relay_fallback.nim # Relay pairing test
    └── test_relay_file_sync.nim # Full file sync over relay test

buddydrive-relay/
├── src/relay.nim              # TCP relay server + KV store thread
├── src/kvstore.nim            # TiDB MySQL KV store (debby ORM)
├── src/kvstore_api.nim        # Mummy HTTP server for KV API
├── Dockerfile                 # Ubuntu 24.04 builder + runtime
├── docker-compose.yml
└── README.md
```

## Next Steps

1. Push commits to GitHub (auth issue in tool session - user can push manually)
2. Deploy relay to public server (VPS with public IP)
3. Set up relay directory service (website endpoint returning regional relay lists)
4. Add bandwidth throttling config in transfer path
5. Real-world testing between two BuddyDrive instances over the internet
