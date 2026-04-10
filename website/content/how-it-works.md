---
title: How It Works
---

## Architecture

BuddyDrive uses peer-to-peer networking with modern cryptographic protocols.

```
┌─────────────────┐                    ┌─────────────────┐
│  Your Machine   │                    │  Buddy's Machine │
│                 │                    │                  │
│  ┌───────────┐  │   libp2p/Noise    │  ┌───────────┐   │
│  │ BuddyDrive│◄─┼──────────────────┼──►│ BuddyDrive│   │
│  └───────────┘  │   encrypted       │  └───────────┘   │
│       │         │                   │       │          │
│       ▼         │                   │       ▼          │
│  ┌───────────┐  │                   │  ┌───────────┐   │
│  │  Files    │  │                   │  │ Encrypted │   │
│  │ (plain)   │  │                   │  │  Storage  │   │
│  └───────────┘  │                   │  └───────────┘   │
└─────────────────┘                    └─────────────────┘
```

## Components

### Daemon (Background Service)

The BuddyDrive daemon runs in the background:

- **libp2p node** - handles peer-to-peer networking
- **Sync manager** - detects file changes and coordinates sync
- **Control API** - local HTTP server for GUI communication
- **SQLite database** - tracks file state and sync progress

### GUI (Desktop Application)

GTK4 application for Linux, macOS, Windows:

- Shows buddy connection status
- Displays folder sync progress
- Manages folder configuration
- Handles pairing workflow

### CLI (Command Line)

For headless operation:

- Same daemon, no GUI
- Run on servers, NAS, Raspberry Pi
- Script-friendly output

## Networking

### libp2p Stack

BuddyDrive uses libp2p for all networking:

| Layer | Protocol | Purpose |
|-------|----------|---------|
| Transport | TCP | Connection |
| Security | Noise | Encryption |
| Muxer | Yamux | Multiplexing |
| Discovery | Kademlia DHT | Find peers |

### Peer Discovery

How two buddies find each other:

1. **Buddy ID Announce** - Each daemon publishes your buddy ID to the DHT with its current peer record
2. **Buddy Lookup** - Query the DHT for a configured buddy ID
3. **Address Resolution** - Read the peer ID and advertised multi-addresses
4. **Connection Attempt** - Dial a public TCP address directly, or fall back to relay when configured

### NAT Traversal

Current connectivity options:

- **Public TCP address** - direct connection when a forwarded port and public `announce_addr` are available
- **Relay fallback** - used when `relay_region` and a shared buddy `relay_token` are configured
- **UPnP** - automatic port forwarding attempt when no explicit `announce_addr` is set

## File Sync

### Change Detection

The sync manager monitors configured folders:

1. **Scan** - enumerate files, calculate hashes
2. **Compare** - check against last-known state
3. **Detect** - identify added, modified, deleted files
4. **Queue** - add changes to sync queue

### Transfer Protocol

File transfer uses a simple chunked protocol:

```
REQUEST:
{
  "type": "file_request",
  "path": "photos/2024/vacation.jpg",
  "offset": 0,
  "length": 65536
}

RESPONSE:
{
  "type": "file_chunk",
  "data": "<base64-encoded-chunk>",
  "hash": "<blake2b-hash>"
}
```

### SQLite State

Each folder tracked in SQLite:

```sql
CREATE TABLE files (
  path TEXT PRIMARY KEY,
  size INTEGER,
  mtime INTEGER,
  hash BLOB,
  synced INTEGER,
  last_sync INTEGER
);
```

## Control API

Local HTTP server (default port 17521) for GUI communication:

| Endpoint | Purpose |
|----------|---------|
| GET /status | Runtime status |
| GET /buddies | Buddy list with connection state |
| GET /folders | Folder list with sync status |
| POST /folders | Add folder |
| DELETE /folders/:name | Remove folder |
| POST /sync/:folder | Trigger sync |
| POST /buddies/pairing-code | Generate pairing code |

API reads from SQLite, avoiding thread safety issues.

## Cryptography

### Key Hierarchy

```
Master Key (per installation)
    │
    ├── Identity Key Pair (X25519)
    │       Used for: authentication, key exchange
    │
    └── Per-Buddy Shared Secret
            Derived via: X25519 key exchange
            Used for: session encryption
```

### File Encryption

Each file encrypted with unique key:

1. **Generate random key** (32 bytes)
2. **Encrypt file** with XSalsa20-Poly1305
3. **Encrypt key** with buddy's shared secret
4. **Store together** as encrypted blob

### Message Authentication

Every message authenticated:

- Poly1305 MAC for file chunks
- Blake2b hash for integrity
- Sequence numbers prevent replay

## Data Flow

### Syncing a New File

```
1. User adds file to ~/SyncedFolder/photo.jpg

2. Daemon detects change:
   - Scanner finds new file
   - Calculates Blake2b hash
   - Adds to SQLite index

3. Sync triggered:
   - Request sent to buddy
   - Buddy accepts, creates storage slot

4. Transfer:
   - File encrypted locally
   - Sent in 64KB chunks
   - Buddy stores encrypted

5. Complete:
   - Mark synced in SQLite
   - GUI shows progress
```

### Requesting a File

```
1. User clicks "Sync" on folder

2. Daemon sends file manifest:
   - List of files with hashes
   - Buddy compares to stored blobs

3. Buddy sends encrypted files

4. Local decryption:
   - Decrypt with shared secret
   - Verify hash
   - Write to disk
```

## Performance

### Memory

- ~50MB baseline
- Additional ~10MB per active sync

### CPU

- Encryption: ~100MB/s on modern CPU
- Hashing: ~200MB/s
- Sync overhead: minimal when idle

### Network

- Chunked transfer for large files
- LZ4 compression when it helps for a transferred chunk
- Bandwidth throttling (planned)

### Disk

- Encrypted files: ~5% larger than originals
- SQLite index: ~1KB per file

## Limitations

### Current

- Sync triggered when buddies connect
- One buddy per folder
- No delta sync for large files
- No selective download

### Planned

- Better background daemon management
- Multiple buddies per folder
- Delta sync (rsync-style)
- Compression for text files
- Mobile apps

---

See [Features](/features) for user-facing capabilities or [Security](/security) for cryptographic details.
