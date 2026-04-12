---
title: How It Works
---

## Architecture

BuddyDrive uses peer-to-peer networking, relay fallback, and relay-backed config recovery.

```text
┌─────────────────┐                    ┌─────────────────┐
│  Your Machine   │                    │ Buddy's Machine │
│                 │                    │                 │
│  ┌───────────┐  │   direct/relay     │  ┌───────────┐  │
│  │ BuddyDrive│◄─┼───────────────────┼──►│ BuddyDrive│  │
│  └───────────┘  │                    │  └───────────┘  │
│       │         │                    │       │         │
│       ▼         │                    │       ▼         │
│  ┌───────────┐  │                    │  ┌───────────┐  │
│  │  Files    │  │                    │  │  Files    │  │
│  └───────────┘  │                    │  └───────────┘  │
└─────────────────┘                    └─────────────────┘
```

## Components

### Daemon

The daemon runs in the foreground today and contains:

- **libp2p node** - peer discovery and direct transport
- **Sync manager** - folder scan and sync orchestration
- **Control API** - localhost HTTP API for the GUI
- **SQLite state** - runtime status and file index tracking

### GUI

The GTK4 app shows:

- Buddy connection state
- Folder sync status
- Folder and buddy configuration
- Pairing and control actions

### CLI

The CLI handles:

- Initial setup
- Pairing
- Relay configuration
- Recovery setup and restore
- Manual inspection of config, folders, buddies, and logs

## Networking

### libp2p Stack

BuddyDrive uses libp2p for direct peer communication:

| Layer | Protocol | Purpose |
|-------|----------|---------|
| Transport | TCP | Direct connection |
| Security | Noise | Direct transport encryption |
| Muxer | Yamux | Multiplexing |
| Discovery | Kademlia DHT | Find peers |

### Peer Discovery

How two buddies find each other:

1. Each daemon publishes your buddy ID to the DHT with its current peer record
2. The daemon looks up configured buddies by buddy ID
3. It reads the advertised multiaddrs
4. It dials a public TCP address directly, or falls back to a relay when configured

### NAT Traversal

Current connectivity options:

- **Public TCP address** - direct connection when `announce_addr` points to a reachable public address
- **Relay fallback** - used when `relay_region` is set and both sides store the same buddy `pairing_code`
- **UPnP** - automatic port forwarding attempt when no explicit `announce_addr` is set

## File Sync

### Change Detection

The sync manager monitors configured folders:

1. Scan files in the folder
2. Capture path, size, mtime, and local hash state
3. Compare against the previous index
4. Queue added, modified, and deleted files

### Transfer Protocol

File transfer uses a simple chunked protocol:

```json
{
  "type": "file_request",
  "path": "photos/2024/vacation.jpg",
  "offset": 0,
  "length": 65536
}
```

Chunks are sent in 64KB blocks. LZ4 compression is used when it helps.

### Restore Behavior

Restore is just sync in the opposite direction:

1. One side advertises a file in its folder list
2. The other side sees the file is missing locally
3. The sync session requests the missing file
4. The file is recreated locally

If the destination folder is append-only and already has a file with that name, the local file is kept.

### SQLite State

BuddyDrive keeps runtime and file state in SQLite under `~/.buddydrive/`.

## Recovery Flow

### Setup Recovery

1. `buddydrive setup-recovery` generates a 12-word phrase
2. BuddyDrive derives a 32-byte master key from the phrase
3. Recovery metadata is stored in `[recovery]` in `config.toml`
4. The serialized config is encrypted with the master key and uploaded to the relay

### Recover On A New Machine

1. `buddydrive recover` asks for the 12-word phrase
2. BuddyDrive derives the same master key again
3. It fetches the encrypted config blob from the relay
4. The config is decrypted and saved locally
5. Starting the daemon lets normal sync restore missing files

## Control API

Local HTTP server (default port 17521) for GUI communication:

| Endpoint | Purpose |
|----------|---------|
| GET /status | Runtime status |
| GET /buddies | Buddy list with connection state |
| GET /folders | Folder list with sync status |
| GET /config | Current saved configuration |
| POST /folders | Add folder |
| DELETE /folders/:name | Remove folder |
| POST /buddies/pair | Pair buddy through the local API |
| POST /buddies/pairing-code | Generate pairing code |
| POST /sync/:folder | Trigger sync |
| POST /config | Update selected config fields |
| POST /config/reload | Reload config from disk |

## Limitations

### Current

- Sync is triggered when buddies connect
- One buddy per folder today
- Buddy-backed config fetch for `recover` is not implemented yet
- No delta sync for large files
- No selective download

### Planned

- Better background daemon management
- Multiple buddies per folder
- Delta sync
- More polished restore UX in the GUI

See [Features](/features) for user-facing capabilities or [Security](/security) for current security scope.
