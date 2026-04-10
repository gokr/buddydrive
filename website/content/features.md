---
title: Features
---

## Core Features

### End-to-End Encryption

BuddyDrive encrypts every file before transmission using modern cryptographic standards:

- **NaCl/libsodium** for authenticated encryption
- **X25519** key exchange for secure pairing
- **XSalsa20-Poly1305** for file encryption
- **Blake2b** for integrity verification

Your buddy stores encrypted blobs. They cannot read your files. Even with physical access to their machine, your data remains private.

### Peer-to-Peer Architecture

No central server. No cloud. No middleman.

```
Your Machine <--encrypted channel--> Buddy's Machine
```

BuddyDrive uses libp2p for peer discovery and transport. Current connectivity options include direct public TCP connections and relay fallback. Features:

- **DHT-based peer discovery** - find your buddy even behind home routers
- **Relay fallback** - available when both peers configure the same relay token
- **Multi-address support** - connects via IP, TCP, and more
- **Yamux multiplexing** - efficient multiple streams over one connection

### Automatic File Sync

Once paired and configured, BuddyDrive runs in the background:

- **File change detection** - notices new, modified, and deleted files
- **Incremental sync** - only transfers what changed
- **Chunked transfer** - handles large files efficiently
- **Resume support** - interrupted syncs continue where they left off

### Selective Folder Sync

Choose exactly what to share:

- Sync your Photos folder with your parents
- Sync Documents with your work partner
- Each buddy can have different folders
- Exclude sensitive files or subdirectories

### Real-Time Status

GTK4 desktop application shows:

- Connection status for each buddy
- Sync progress per folder
- File counts and bytes transferred
- Recent activity log

Command-line interface for headless servers.

## Security Features

### Secure Pairing

Pairing uses a short code that you share with your buddy out-of-band (in person, text, call):

1. Generate pairing code on your machine
2. Share code with your buddy
3. They enter the code on their machine
4. BuddyDrive stores the buddy relationship locally
5. Both sides can start the daemon and attempt sync

Each buddy relationship is configured independently.

### Encrypted At Rest

Files are encrypted before storage on your buddy's machine:

- Original filename hidden
- File contents encrypted
- Directory structure hidden
- Timestamps protected

Even with physical access to your buddy's hard drive, your data is unreadable.

### Forward Secrecy

Session keys are ephemeral. Past communications remain secure even if long-term keys are compromised.

### Integrity Verification

Every transferred file includes a cryptographic hash. Tampering is detected immediately.

## Sync Features

### Conflict Handling

When both you and your buddy edit the same file:

- **Last-write-wins** by default
- **Append-only mode** available per folder to avoid remote overwrites and deletions
- **No built-in version history yet**

### Bandwidth Control

- **Throttle sync speed** to avoid saturating your connection
- **Schedule syncs** for off-peak hours
- **Pause sync** when needed

### Large File Support

- Files split into 64KB chunks
- Resume-friendly chunked transfer flow
- LZ4 compression when it reduces payload size

## Platform Support

### Linux

Build from source today. GTK4 GUI with desktop integration on Linux.

### macOS

Build from source.

### Windows

Build from source.

### Headless

Run on servers, NAS boxes, or Raspberry Pi with command-line interface only.

## Technical Details

### Built With

- **Nim** - high-performance systems language
- **libp2p** - peer-to-peer networking
- **libsodium** - cryptography
- **GTK4** - native GUI
- **SQLite** - file tracking database

### Network Requirements

- Outbound internet access
- Direct mode needs a reachable public TCP address
- Relay mode needs a configured relay service and matching relay token
- IPv4 and IPv6 supported

### Storage

Synced files stored in encrypted form. Original files remain untouched on your machine.

Typical overhead: ~5% for encryption headers and metadata.

## Roadmap

Current version: 0.1.0

Upcoming features:

- **Mobile apps** - iOS and Android
- **Versioning** - keep multiple file versions
- **Selective download** - choose which files to fetch
- **Bandwidth scheduling** - sync only at night
- **Multiple buddies** - sync with more than one person
- **Compression** - reduce bandwidth for text files

## Limitations

Current limitations to be aware of:

- Background sync depends on peers connecting successfully
- One buddy per folder (multiple buddies planned)
- No mobile apps yet
- No file versioning yet

See [How It Works](/how-it-works) for technical architecture details.
