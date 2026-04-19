# BuddyDrive Development Plan

Project plan, architecture decisions, implementation history, and remaining work. For user-facing documentation see [MANUAL.md](MANUAL.md) and [TUTORIAL.md](TUTORIAL.md).

## Project Goal

Build BuddyDrive — a P2P encrypted folder sync tool in Nim that syncs folders with 1-2 buddies across the internet, bypassing NATs and firewalls. Also build BuddyDrive Relay — a TCP relay server and KV store for when direct P2P connections fail.

## Design Decisions

- **CLI-first, GUI later** — direct GTK4 (not Owlkettle) for the desktop GUI
- **libp2p** for P2P networking (direct transport, NAT traversal)
- **libsodium** for encryption (XChaCha20-Poly1305)
- **KV-store relay discovery** — replaced DHT-based discovery (DHT was unreliable)
- **Pairing code reused as relay token** — auto-generated XXXX-XXXX format
- **BIP39 12-word mnemonic** — the single recovery secret
- **Asymmetric master key** from mnemonic — stored in plaintext in config.toml
- **Config encrypted** with master key before syncing to relay and buddies
- **Relay KV store** uses public key (Base58) as lookup key
- **Recovery only needs the 12 words** — no need to remember a buddy ID + pairing code
- **Direct-only connectivity preferred** — relay fallback is secondary
- **Automatic UPnP** — users should not have to manually configure routers
- **LZ4 compression** — for file chunks when it reduces size
- **Region-based relay selection** — user chooses region, both buddies hash token to pick same relay

## Key Discoveries

- **CGNAT is common** — ISP-level NAT prevents UPnP from getting public IPs (100.64.0.0/10 range)
- **Koyeb TCP Proxy** — not suitable for multi-instance relay due to lack of session affinity
- **`fmReadWrite` truncates** — use `fmReadWriteExisting` for subsequent chunks
- **`reversed()` returns `seq[char]`** — base58 encoding needed manual reversal
- **`crypto_generichash` returns `seq[byte]`** — not `string`, requires explicit `byte()` casts
- **Chronos async enforces GC-safety** — `parsetoml.parseFile` must be wrapped with `{.cast(gcsafe).}:`
- **Chronos async enforces exception tracking** — calls that can raise `SodiumError` must be wrapped in `try/except`
- **`curly` requires `--mm:arc/orc` and `--threads:on`** — timeout is per-request, not on client
- **Nim's `std/hashes.hash` is 64-bit non-cryptographic** — not suitable for cross-machine comparison; replaced with crypto_generichash streaming

## Implementation History

### Phase 1: Core Infrastructure — COMPLETE

- Project structure, nimble package, config.nims
- CLI framework with subcommands
- TOML config read/write with atomic writes
- Name generation, UUID generation, pairing code generation

### Phase 2: libp2p Networking — COMPLETE

- libp2p node creation with TCP transport, Noise security, Yamux multiplexer
- KV-store relay discovery with HMAC authentication (replaced DHT)
- Direct peer connection tested

### Phase 3: Buddy Pairing — COMPLETE

- Pairing handshake implemented
- Buddy verification against config
- BuddyConnection tracking in daemon

### Phase 4: File Sync (v1 — to be replaced) — COMPLETE

- File scanner with change detection (polling-based)
- SQLite file index
- Chunk-based file transfer (64KB)
- Session-based sync coordination
- LZ4 compression

### Phase 5: Encryption — COMPLETE

- libsodium secretbox for content
- Password-based key derivation
- Encrypted filename support (exists in crypto.nim but not wired)

### Phase 6: Debian Packaging — COMPLETE

### Phase 7: Relay Server — COMPLETE

### Phase 8: Recovery System — COMPLETE

### Phase 9: Crash Safety — PARTIALLY COMPLETE

- [DONE] Atomic writes: temp file (`.buddytmp`) + flushFile + closeFile + moveFile
- [DONE] Startup cleanup of leftover `.buddytmp` files
- [DONE] flushAndClose with test-only failure mode

### Phase 10: Discovery Migration — COMPLETE

---

## Current Sync Model — Problems

The existing sync implementation has fundamental issues that require a full replacement:

1. **No encryption at rest** — `FolderConfig.encrypted` is stored but not wired into the transfer path. `encryptedPath` is always set to `path`. Files are stored plaintext on the buddy's machine.

2. **Broken hash function** — `scanner.nim:hashFile` uses Nim's `std/hashes.hash` (64-bit, non-cryptographic, reads entire file into memory). Not suitable for cross-machine comparison.

3. **No move detection** — A renamed file appears as delete + add, causing a full re-upload.

4. **No delete propagation** — `msgFileDelete` exists in the protocol but is never sent or handled.

5. **Hash not used in comparison** — `shouldSyncRemoteFile` only compares mtime and size. A corrupt file with the same size/mtime won't be re-synced.

6. **Global sync window** — `syncWindowStart/End` applies to all buddies equally. No per-buddy scheduling.

7. **Initiation problem** — Both sides try to connect independently. When one side is behind CGNAT, the public side fails to dial and falls back to relay unnecessarily, even though the CGNAT side can dial out directly.

8. **Incoming connections rejected during closed window** — `handleIncomingConnection` rejects sync when the local window is closed, even though the remote side wants to push.

---

## New Sync Model — Design

### Core Principle

BuddyDrive is primarily a **backup tool**: my files are stored encrypted on my buddy's machine. My buddy is lending me disk space, not co-authoring files. The buddy cannot read my filenames or content. A secondary "sharing" mode (encrypted=false) stores files plaintext for collaboration.

### Folder Key Derivation

Each folder gets a 32-byte key derived deterministically from the master key + folder name:

```
folder_key = crypto_generichash(masterKey + "/folder/" + folderName, 32)
```

For folders without recovery enabled (no master key), a random key is generated on `add-folder` and stored in config.toml. Both approaches allow the owner to derive the key later for restore.

### Path Encryption

Every relative path (e.g., `photos/2024/vacation.jpg`) is encrypted to an opaque string before being sent to the buddy. The buddy stores files on disk using the encrypted path as the filename. The owner can reverse this because they have the folder key.

The existing `encryptFilename`/`decryptFilename` in `crypto.nim` does this but has a problem: each call generates a random nonce, so the same filename encrypts differently each time. This makes move detection impossible — you can't tell that a path changed.

**Deterministic path encryption**: derive the nonce from the path itself so the same path always encrypts to the same ciphertext:

```
nonce = crypto_generichash(folderKey + "/path/" + plaintextPath, NonceSize)
encryptedPath = base64(crypto_secretbox_easy(folderKey, plaintextPath, nonce))
```

This makes path comparison possible: same plaintext path → same encrypted path. Moved file → new encrypted path. The storage side can detect a rename by matching content hashes across encrypted paths.

### Content Hash — Streaming

Replace `hashFile` with a streaming blake2b hash that never loads the full file into memory:

```nim
proc hashFileStream(path: string): array[32, byte] =
  let state = crypto_generichash_init(key = "", hashlen = 32)
  let f = open(path, fmRead)
  var buf = newSeq[byte](64 * 1024)
  while true:
    let n = f.readBytes(buf, 0, buf.len)
    if n == 0: break
    crypto_generichash_update(state, buf[0 ..< n])
  f.close()
  crypto_generichash_final(state, 32)
```

This hashes files of any size (movies, databases) in 64KB chunks.

### Chunk Encryption

During transfer, each chunk is encrypted with the folder key. The nonce is derived deterministically from the encrypted path + chunk offset:

```
nonce = crypto_generichash(folderKey + "/chunk/" + encryptedPath + "/" + offset, NonceSize)
encryptedChunk = crypto_secretbox_easy(folderKey, chunkData, nonce)
```

Deterministic nonces mean both sides can encrypt/decrypt without exchanging nonces per chunk. The nonce is unique per (file, offset) pair.

### Owner Index (A) — Local SQLite Cache

The owner's index is a **performance optimization**, not a source of truth. After a full restore it gets rebuilt by scanning local files.

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL,              -- plaintext relative path
  encrypted_path TEXT NOT NULL,    -- encrypted + base64 relative path
  content_hash BLOB NOT NULL,     -- blake2b-256 of plaintext
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  synced INTEGER DEFAULT 0,
  last_sync INTEGER DEFAULT 0,
  UNIQUE(path)
);
CREATE INDEX idx_content_hash ON files(content_hash);
CREATE INDEX idx_encrypted_path ON files(encrypted_path);
```

### Storage Index (B) — Local SQLite Cache

The storage buddy's index is also a cache. It tracks what encrypted blobs B has so it can answer "I already have this content" without re-scanning disk.

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  encrypted_path TEXT NOT NULL,   -- opaque path on disk
  content_hash BLOB NOT NULL,     -- same hash as owner (of plaintext, or of ciphertext — see below)
  size INTEGER NOT NULL,
  owner_buddy TEXT NOT NULL,      -- which buddy owns this
  UNIQUE(encrypted_path, owner_buddy)
);
CREATE INDEX idx_content_hash ON files(content_hash, owner_buddy);
```

**Content hash on B's side**: B cannot compute the plaintext hash because B doesn't have the key. Two options:

1. **A sends the hash** — A includes content_hash in the file list. B trusts A. Simple but B can't verify.
2. **B hashes ciphertext** — B computes hash of the encrypted blob on disk. A sends the ciphertext hash. B can verify independently.

Option 2 is better: B computes `hash(encrypted_blob_on_disk)`. A computes the same hash before sending. This lets B verify data integrity without knowing the content. The owner's index stores both `content_hash` (plaintext, for change detection) and `ciphertext_hash` (for sync comparison with B).

Updated owner schema:

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL,
  encrypted_path TEXT NOT NULL,
  content_hash BLOB NOT NULL,      -- blake2b-256 of plaintext (for local change detection)
  ciphertext_hash BLOB NOT NULL,   -- blake2b-256 of encrypted blob (for sync with B)
  size INTEGER NOT NULL,
  mtime INTEGER NOT NULL,
  synced INTEGER DEFAULT 0,
  last_sync INTEGER DEFAULT 0,
  UNIQUE(path)
);
```

### Change Detection — Owner Scan

On each scan, the owner:

1. Walks the folder directory
2. For each file, computes `content_hash` (streaming blake2b) and `encrypted_path` (deterministic encryption)
3. Compares against index:
   - New path not in index → **added**
   - Same path, different `content_hash` → **modified**
   - Path in index but not on disk → **deleted**
   - Same `content_hash` at new path, old path gone → **moved** (just a rename, no re-transfer)

For modified files, also compute the new `ciphertext_hash` after encrypting.

### Sync Protocol — Session Flow

**Initiator** (deterministically chosen, see below) connects to the other buddy. Both directions of sync happen over the single connection.

#### Step 1: Exchange File Lists

Both sides send their file lists for shared folders. The format differs by role:

**Owner → Storage**: list of `(encrypted_path, ciphertext_hash, size)` per folder
**Storage → Owner**: list of `(encrypted_path, ciphertext_hash, size)` per folder

The owner sends encrypted paths and ciphertext hashes — the storage side never sees plaintext paths or content hashes.

For unencrypted (sharing) folders, `encrypted_path == path` and no encryption is applied.

#### Step 2: Compute Deltas

Each side compares its list against the other's:

**Owner side** (what A needs to send to B):
- B missing an `encrypted_path` that A has → upload
- Same `encrypted_path`, different `ciphertext_hash` → re-upload (modified)
- B has `encrypted_path` that A no longer has → B deletes it
- B has `ciphertext_hash` at old `encrypted_path`, A has same hash at new path → move (B renames on disk)

**Storage side** (what B needs to send to A):
- A missing an `encrypted_path` that B has → A requests (restore scenario)
- Same `encrypted_path`, different `ciphertext_hash` → A requests (file was modified on A's other buddy? edge case)

For the primary backup use case, the flow is typically one-directional: A pushes to B. But the protocol is symmetric — restore is just A requesting files from B.

#### Step 3: Transfer

- **Uploads**: owner encrypts chunks on-the-fly during send. B stores the encrypted chunks directly to disk.
- **Downloads** (restore): B sends encrypted chunks. A decrypts on-the-fly during write.
- **Moves**: B renames the file on disk. No data transfer.
- **Deletes**: B removes the file on disk.

#### Step 4: Update Indexes

Both sides update their SQLite indexes after successful transfer.

### Deterministic Initiator Selection

Both sides must agree on who initiates the connection. The rule:

```
1. If only one side has a public address: that side initiates
2. If both have public addresses: lower buddy UUID initiates
3. If neither has public addresses: relay fallback, lower UUID initiates
```

Both sides can compute this from the discovery records they see for each other. The discovery record already includes the peer's advertised addresses. A side knows its own reachability (did UPnP succeed? is announce_addr set?).

**Discovery record extension**: add a `has_public_address: bool` field so each side can determine the other's reachability without examining the actual address list (which they may not have if the relay is down).

```json
{
  "peerId": "...",
  "addresses": ["..."],
  "relayRegion": "eu",
  "hasPublicAddress": true,
  "syncTime": "03:00"
}
```

### Per-Buddy Sync Time

Replace the global `sync_window_start/end` with a per-buddy `sync_time` field. This is the time of day when the initiator should attempt to connect:

```toml
[[buddies]]
id = "abc-123"
name = "cranky-wrench"
pairing_code = "ABCD-EFGH"
sync_time = "03:00"    # connect at 03:00 daily
added_at = "2026-04-10T12:00:00Z"
```

The initiator connects at the scheduled `sync_time`. The other side **always accepts incoming syncs** — the sync time only controls when to *initiate*, not when to *accept*. This means:

- If A is behind CGNAT and B is public, B initiates at B's configured `sync_time` for A
- A accepts the incoming connection even if it's outside A's own `sync_time`
- Both directions of sync happen over that one connection

The `sync_time` field can also be empty (default: sync whenever the daemon is running, like the current "always" behavior).

### Always Accept Incoming

Remove the sync window check from `handleIncomingConnection`. The sync time controls initiation only:

- `handleIncomingConnection`: accept all incoming from known buddies
- `connectToBuddies` loop: only dial at the scheduled `sync_time` for that buddy

If both buddies have `sync_time = "03:00"`, both try to connect at 03:00. One wins (deterministic initiator rule), the other's incoming connection handler accepts the winner's dial. The loser's outgoing attempt is skipped because `buddyConnections` already has an entry.

### CGNAT Connection Flow

Buddy A (CGNAT, no public address) and Buddy B (public):

1. Discovery: A publishes private addresses + `hasPublicAddress: false`. B publishes public address + `hasPublicAddress: true`.
2. Both sides compute initiator: B has public address, B is the initiator. But wait — B can't dial A.
3. **Exception**: when only one side has a public address, the *other* side initiates (the CGNAT side dials out, because only the CGNAT side can reach the public side). Revised rule:

```
1. If one side has public address and the other doesn't: the side WITHOUT public address initiates
   (it dials the public side directly; the public side can't dial back)
2. If both have public addresses: lower buddy UUID initiates
3. If neither has public addresses: relay fallback, lower UUID initiates
```

This ensures the CGNAT side always initiates the direct connection. The public side accepts. Sync flows both directions over that connection.

### Restore Flow

On a replacement machine with only the 12-word phrase:

1. `buddydrive recover` → derive master key → fetch encrypted config from relay → write config.toml
2. Config gives: folder keys, buddy IDs, pairing codes
3. A connects to B (initiator rule applies)
4. A sends `list_paths` request for each folder
5. B responds with list of `(encrypted_path, size)` for A's files
6. A decrypts each `encrypted_path` → plaintext path
7. A checks local filesystem: for each path that doesn't exist locally, request the file from B
8. A decrypts received chunks on-the-fly, writes to plaintext path
9. A rebuilds local index by scanning the restored files

No index blob needed. B's filesystem + A's folder key = complete restore.

### Unencrypted Sharing Mode

When `FolderConfig.encrypted = false`:
- `encrypted_path == path` (no encryption)
- Content is transferred plaintext
- B can browse and read the files
- Same sync protocol, just skip the encrypt/decrypt steps
- `content_hash` and `ciphertext_hash` are the same (hash of plaintext)

This is a secondary use case for active collaboration. The primary use case is always encrypted backup.

---

## Implementation Plan

### Phase A: Crypto Foundation

**Files**: `crypto.nim`, `types.nim`, `config.nim`

1. **Streaming content hash** — add `hashFileStream(path: string): array[32, byte]` using `crypto_generichash_init/update/final`
2. **Ciphertext hash** — add `hashBytes(data: openArray[byte]): array[32, byte]` using `crypto_generichash`
3. **Deterministic path encryption** — add `encryptPathDeterministic(plainPath, folderKey): string` and `decryptPathDeterministic(encPath, folderKey): string` using derived nonce
4. **Chunk encryption** — add `encryptChunk(data, folderKey, encPath, offset): seq[byte]` and `decryptChunk(data, folderKey, encPath, offset): seq[byte]` using derived nonce
5. **Folder key derivation** — add `deriveFolderKey(masterKey, folderName): string`
6. **Add folder key to config** — `FolderConfig` gets a `folderKey` field. If recovery is enabled, derive from master key. Otherwise, generate random on `add-folder` and store in config.toml.
7. **Remove old `hashFile`** — delete the broken `std/hashes`-based function from scanner.nim

### Phase B: Index Redesign

**Files**: `index.nim`, `types.nim`

1. **New owner schema** — add `ciphertext_hash` column, add `idx_content_hash` and `idx_encrypted_path` indexes
2. **New storage schema** — new table with `encrypted_path`, `ciphertext_hash`, `size`, `owner_buddy`
3. **Index API** — add methods: `getFileByHash`, `addStorageFile`, `getStorageFile`, `listByOwner`
4. **Migration** — handle existing index.db gracefully (version column or schema check)

### Phase C: Scanner Rewrite

**Files**: `scanner.nim`

1. **Use streaming hash** — `scanFile` calls `hashFileStream` instead of `hashFile`
2. **Compute encrypted_path** — `scanFile` also computes `encrypted_path` via `encryptPathDeterministic`
3. **Compute ciphertext_hash** — after encrypting, hash the ciphertext (or compute during transfer)
4. **Move detection** — `scanChanges` checks for same `content_hash` at a new path when the old path disappears

### Phase D: Sync Protocol Update

**Files**: `messages.nim`, `protocol.nim`, `transfer.nim`, `session.nim`

1. **Update FileList message** — include `ciphertext_hash` in `FileEntry`
2. **Add ListPaths message** — new request/response pair for restore (B lists its encrypted_paths for a folder)
3. **Add MoveFile message** — tell B to rename an encrypted_path (includes old and new path, plus content_hash for verification)
4. **Add DeleteFile message handling** — wire up the existing `msgFileDelete` to actually delete on B's side
5. **Encrypt chunks on send** — `sendFileData` encrypts each chunk before sending
6. **Decrypt chunks on receive** — `receiveFileData` decrypts each chunk after receiving
7. **Session flow** — rewrite `syncBuddyFolders` to handle both push (backup) and pull (restore) with move/delete support
8. **Unencrypted shortcut** — when `folder.encrypted == false`, skip encrypt/decrypt steps

### Phase E: Connection & Scheduling

**Files**: `daemon.nim`, `types.nim`, `config.nim`, `p2p/discovery.nim`

1. **Per-buddy sync_time** — add `syncTime: string` to `BuddyInfo`, update config read/write, remove global `syncWindowStart/End`
2. **Discovery record extension** — add `hasPublicAddress: bool` and `syncTime: string` to published record
3. **Deterministic initiator** — add `shouldInitiate(myConfig, buddyRecord): bool` proc
4. **Remove incoming rejection** — remove sync window check from `handleIncomingConnection`
5. **Scheduled dialing** — `connectToBuddies` only dials a buddy when within that buddy's `sync_time` window (e.g., ±15 minutes of the configured time, or always if syncTime is empty)
6. **Connection reuse** — before dialing, check `daemon.node.switch` for existing transport connections to the buddy's peer ID; open a stream on existing connection instead of new dial
7. **Connection upgrade** — when an incoming direct connection arrives and a relay connection already exists for that buddy, replace relay with direct

### Phase F: Restore

**Files**: `cli.nim`, `daemon.nim`, `p2p/protocol.nim`, `p2p/messages.nim`

1. **ListPaths protocol** — A requests B to list all encrypted_paths for a folder; B responds with list
2. **Restore flow in CLI** — after `buddydrive recover` restores config, `buddydrive start` detects missing local files and requests them from B
3. **Index rebuild** — after restoring files, scan them to populate the owner index

### Phase G: Testing

1. **Unit tests** — streaming hash, deterministic path encryption/decryption, chunk encryption/decryption, folder key derivation, move detection, initiator selection
2. **Integration test** — full encrypted backup: A adds folder, syncs to B, verify B has encrypted files
3. **Integration test** — restore: delete A's files, restart A, restore from B, verify files match
4. **Integration test** — move detection: rename file on A, sync, verify B renames without re-upload
5. **Integration test** — CGNAT simulation: one side with no public address, verify correct initiator selection and direct connection
6. **Integration test** — mixed encrypted/unencrypted: two folders, one encrypted one shared, verify correct behavior for each

### Implementation Order

A → B → C → D → E → F → G

Each phase builds on the previous. Phase A (crypto) has no dependencies and can start immediately. Phase E (connection changes) is mostly independent of B/C/D and could be done in parallel.

---

## Test Coverage

### Unit Tests (16 files)

`tests/unit/*/*.nim` — run via `nimble test` or `nimble testUnit`:

config, config_sync, control, control_web, crypto, discovery, geoip_ranges, index, messages, pairing, policy, rawrelay, recovery, scanner, transfer crash safety, types

### Integration Tests (7 files)

`tests/integration/*.nim` — run via `nimble test` or `nimble testIntegration`:

CLI flows, KV API, config sync e2e, relay fallback, relay file sync, relay server, pairing protocol

### Tests To Add (Phase G)

- Streaming hash vs full-file hash comparison
- Deterministic path encryption roundtrip
- Chunk encryption roundtrip
- Folder key derivation from master key
- Move detection in scanner
- Initiator selection (various reachability combinations)
- Full encrypted backup + restore
- Mixed encrypted/unencrypted folders

## Public Relay

- **TCP relay**: `01.proxy.koyeb.app:19447`
- **KV API**: `https://buddydrive-tankfeud-ddaec82a.koyeb.app`
- **Region**: Frankfurt (fra)

To deploy your own relay, see [relay/README.md](../relay/README.md).
