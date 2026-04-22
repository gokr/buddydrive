# BuddyDrive Development Plan

Project plan, architecture decisions, implementation history, and remaining work. For user-facing documentation see [MANUAL.md](MANUAL.md) and [TUTORIAL.md](TUTORIAL.md).

## Project Goal

Build BuddyDrive — a P2P encrypted folder sync tool in Nim that syncs folders with 1-2 buddies across the internet, bypassing NATs and firewalls. Also build BuddyDrive Relay — a TCP relay server and KV store for when direct P2P connections fail.

## Design Decisions

- **CLI-first, GUI later** — direct GTK4 (not Owlkettle) for the desktop GUI
- **libp2p** for P2P networking (direct transport, NAT traversal)
- **libsodium** for encryption (XSalsa20-Poly1305)
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
- **Encrypted backup model** — files stored fully opaque on buddy's machine (filenames + content). Buddy is storage, not co-author.
- **Deterministic path encryption, random content nonces** — paths need determinism for move detection; content must not reuse nonces across versions
- **Stable folder key from folder ID** — not folder name, so renaming a folder doesn't orphan remote data
- **Owner-authoritative move detection** — A tells B "rename X to Y"; B does not infer moves from ciphertext identity

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
- **Deterministic content nonces are unsafe** — reusing a nonce with different plaintext under the same key breaks XSalsa20-Poly1305. Content nonces must be random. Only path encryption can use deterministic nonces (same path always encrypts the same way, and path content doesn't change between versions).

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

## Current Sync Model

The new sync model (described below) is now **largely implemented**. The original v1 sync had fundamental issues that have been fixed:

1. ~~**No encryption at rest**~~ — **FIXED**: `FolderConfig.encrypted` is wired into the transfer path. Filenames are encrypted with deterministic nonces, content chunks with random nonces. `encryptedPath` is computed from the plaintext path via `encryptPath()`.

2. ~~**Broken hash function**~~ — **FIXED**: `scanner.nim` uses `hashFileStream()` — a streaming blake2b hash via `crypto_generichash_init/update/final` reading 64KB chunks. Never loads full file into memory.

3. ~~**No move detection**~~ — **FIXED**: `scanChanges` detects moved files (same content hash at a new path when the old path disappears). `msgMoveFile` is sent/received in the sync session.

4. ~~**No delete propagation**~~ — **FIXED**: `msgFileDelete` is sent in `sendDeltaPhase` and handled in `servePhase`. The `deleteLocalFile` proc removes the file on disk and its index entry.

5. ~~**Hash not used in comparison**~~ — **FIXED**: `shouldSyncRemoteFile` compares content hash, mtime, size, mode, and symlink target.

6. ~~**Global sync window**~~ — **FIXED**: Replaced by per-buddy `syncTime` field. `shouldAttemptBuddySync` checks per-buddy sync time with 15-minute tolerance. Empty sync time means "always."

7. ~~**Initiation problem**~~ — **FIXED**: `shouldInitiate()` implements deterministic initiator selection: the side without a public address initiates; if both same reachability, lower buddy UUID initiates.

8. ~~**Incoming rejected during closed window**~~ — **FIXED**: `handleIncomingConnection` accepts all incoming connections from known buddies regardless of sync time. Sync time controls initiation only.

### Remaining Limitations

- **Buddy-backed config fetch** — `syncConfigToBuddy()` and `fetchConfigFromBuddy()` are not implemented yet. Recovery currently only works via the relay path.
- **`init --with-recovery`** — Parsed as a CLI flag but does nothing. Use `init` then `setup-recovery` separately.
- **Long-lived CGNAT connections** — The CGNAT side does not yet maintain persistent/keepalive connections. It reconnects on each sync cycle.
- **Connection upgrade** — When a direct connection arrives and a relay connection already exists for that buddy, the relay connection is not yet automatically replaced.
- **Large folder listings** — File list exchange uses a single framed message (30MB max). Pagination or streaming is deferred.

---

## New Sync Model — Design (Implemented)

### Core Principle

BuddyDrive is primarily a **backup tool**: my files are stored encrypted on my buddy's machine. My buddy is lending me disk space, not co-authoring files. The buddy cannot read my filenames or content. A secondary "sharing" mode (encrypted=false) stores files plaintext for collaboration.

### Folder Key — Stable Identity

Each folder gets a 32-byte key derived from a **stable folder ID**, not the folder name:

```
folder_key = crypto_generichash(masterKey + "/folder/" + folderId, 32)
```

`folderId` is a UUID assigned on `add-folder` and stored in `FolderConfig.id` in config.toml. This is independent of `FolderConfig.name` (the display name), so renaming a folder does not orphan remote data or require re-encryption.

For folders without recovery enabled (no master key), a random key is generated on `add-folder` and stored in `FolderConfig.folderKey` in config.toml. Both approaches allow the owner to derive or retrieve the key later for restore.

```toml
[[folders]]
id = "f47ac10b-58cc-4372-a567-0e02b2c3d479"   # stable, never changes
name = "docs"                                   # display name, can change
path = "/home/user/Documents"
folder_key = "a1b2c3..."                        # random if no recovery, derived if recovery
encrypted = true
append_only = false
buddies = ["buddy-id-here"]
```

### Path Encryption — Deterministic

Every relative path (e.g., `photos/2024/vacation.jpg`) is encrypted to an opaque string before being sent to the buddy. The buddy stores files on disk using the encrypted path as the filename. The owner can reverse this because they have the folder key.

Deterministic nonce derivation ensures the same path always encrypts to the same ciphertext. This is safe because the plaintext (the path string) does not change between versions of the file at that path:

```
nonce = crypto_generichash(folderKey + "/path/" + plaintextPath, NonceSize)
encryptedPath = base64(crypto_secretbox_easy(folderKey, plaintextPath, nonce))
```

This makes path comparison possible: same plaintext path → same encrypted path. Moved file → new encrypted path. Move detection works because the owner can tell B "the content at encrypted_path_X is now at encrypted_path_Y."

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

This hashes files of any size (movies, databases) in 64KB chunks. The hash is of **plaintext content** and is used for:
- Local change detection (same path, different hash → modified)
- Move detection (same hash at new path → renamed)
- Sync identity sent to B (so B can recognize "same content, different encrypted_path" for moves)

### Chunk Encryption — Random Nonces

Each chunk is encrypted with the folder key using a **random nonce**. The nonce is prepended to the encrypted chunk before transmission:

```
nonce = randombytes(NonceSize)                # 24 bytes, random per chunk
encryptedChunk = nonce || crypto_secretbox_easy(folderKey, chunkData, nonce)
```

Random nonces are required because the same (file, offset) pair may contain different plaintext across versions. If a file at `/photos/vacation.jpg` is edited, the chunk at offset 0 now has different content. A deterministic nonce would reuse the same nonce with different plaintext under the same key — a catastrophic break for XSalsa20-Poly1305.

The overhead is 24 bytes (nonce) per 64KB chunk — negligible. B stores `nonce || ciphertext` as the on-disk blob. B does not need to understand the nonce; it's just opaque bytes.

For unencrypted (sharing) folders, no chunk encryption is applied.

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

The owner index stores `content_hash` (plaintext blake2b) for local change detection and move detection. It does not need a `ciphertext_hash` column — move detection uses the `content_hash` that the owner sends to B in the file list.

### Storage Index (B) — Local SQLite Cache

The storage buddy's index is also a cache. It tracks what encrypted blobs B has so it can answer "I already have this content" without re-scanning disk.

```sql
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  encrypted_path TEXT NOT NULL,   -- opaque path on disk
  content_hash BLOB NOT NULL,    -- as reported by owner (plaintext blake2b)
  size INTEGER NOT NULL,
  owner_buddy TEXT NOT NULL,     -- which buddy owns this
  UNIQUE(encrypted_path, owner_buddy)
);
CREATE INDEX idx_content_hash ON files(content_hash, owner_buddy);
```

B does not compute its own hash of the encrypted blob. Instead, B stores the `content_hash` as reported by A. This is the simplest model: A is the authority on content identity. B trusts A for the hash value. This avoids the problem of ciphertext being non-deterministic (random nonces), which would make any ciphertext-based hash useless for content comparison.

For data integrity verification, B can optionally compute a `storage_hash` of the encrypted blob on disk (hash of ciphertext + nonce) and compare it against what A originally sent. This detects bit rot or disk corruption, but is not needed for sync logic.

### Change Detection — Owner Scan

On each scan, the owner:

1. Walks the folder directory
2. For each file, computes `content_hash` (streaming blake2b) and `encrypted_path` (deterministic encryption)
3. Compares against index:
   - New path not in index → **added**
   - Same path, different `content_hash` → **modified**
   - Path in index but not on disk → **deleted**
   - Same `content_hash` at new path, old path gone → **moved** (just a rename, no re-transfer)

### Sync Protocol — Session Flow

**Initiator** (deterministically chosen, see below) connects to the other buddy. Both directions of sync happen over the single connection.

#### Step 1: Exchange File Lists

Both sides send their file lists for shared folders:

**Owner → Storage**: list of `(encrypted_path, content_hash, size)` per folder
**Storage → Owner**: list of `(encrypted_path, content_hash, size)` per folder

The owner sends encrypted paths and plaintext content hashes. B already knows the `content_hash` from the previous sync (stored in B's index). The content_hash lets B recognize "same content at a new encrypted path" for move detection.

For unencrypted (sharing) folders, `encrypted_path == path` and no encryption is applied.

#### Step 2: Compute Deltas

Each side compares its list against the other's:

**Owner side** (what A needs to tell B):
- B missing an `encrypted_path` that A has → upload to B
- Same `encrypted_path`, different `content_hash` → re-upload (modified file)
- A has `content_hash` at a new `encrypted_path`, B has same `content_hash` at the old `encrypted_path` → send MoveFile instruction to B (B renames on disk, no data transfer)
- B has `encrypted_path` that A no longer has → send DeleteFile instruction to B

**Storage side** (what B needs to send to A):
- A missing an `encrypted_path` that B has → A requests (restore scenario)
- Same `encrypted_path`, different `content_hash` → A requests (rare: file was modified on A's other buddy)

Move detection is **owner-authoritative**: A tells B to rename. B does not try to infer moves by matching content hashes on its own. This is the simplest and most secure model — A is the authority on what its files are named and where they live.

For the primary backup use case, the flow is typically one-directional: A pushes to B. But the protocol is symmetric — restore is just A requesting files from B.

#### Step 3: Transfer

- **Uploads**: owner encrypts each chunk on-the-fly with a random nonce before sending. B stores `nonce || ciphertext` directly to disk.
- **Downloads** (restore): B sends `nonce || ciphertext` chunks. A extracts the nonce, decrypts, writes plaintext.
- **Moves**: A sends a MoveFile message (old encrypted_path, new encrypted_path). B renames the file on disk and updates its index. No data transfer.
- **Deletes**: A sends a DeleteFile message. B removes the file on disk and its index entry.

#### Step 4: Update Indexes

Both sides update their SQLite indexes after successful transfer.

### Deterministic Initiator Selection

Both sides must agree on who initiates the connection. The rule:

```
1. If one side has a public address and the other doesn't:
   the side WITHOUT public address initiates
   (it dials the public side directly; the public side can't dial back)
2. If both have public addresses: lower buddy UUID initiates
3. If neither has public addresses: relay fallback, lower UUID initiates
```

The key insight for CGNAT: the side behind CGNAT *must* be the one to dial out, because the public side cannot reach it. This is the opposite of what you'd expect — the reachable side accepts, the unreachable side initiates.

Both sides can compute this from the discovery records. Each side knows its own reachability and can see the other's advertised addresses in the discovery record.

**Reachability signal in discovery**: each side publishes whether it considers itself publicly reachable. This is a hint, not a guarantee — stale UPnP or misconfigured `announce_addr` can make it wrong. When direct dial fails, the initiator falls back to relay and logs a diagnostic so the user can fix their configuration.

```json
{
  "peerId": "...",
  "addresses": ["..."],
  "relayRegion": "eu",
  "isPubliclyReachable": true,
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

- If A is behind CGNAT and B is public, A initiates at A's configured `sync_time` for B (A is the initiator per the CGNAT rule)
- B accepts the incoming connection even if it's outside B's own `sync_time`
- Both directions of sync happen over that one connection

The `sync_time` field can also be empty (default: sync whenever the daemon is running, like the current "always" behavior).

### Always Accept Incoming

Remove the sync window check from `handleIncomingConnection`. The sync time controls initiation only:

- `handleIncomingConnection`: accept all incoming from known buddies
- `connectToBuddies` loop: only dial at the scheduled `sync_time` for that buddy

If both buddies have `sync_time = "03:00"`, both try to connect at 03:00. The deterministic initiator rule picks one side to win; the other side's incoming handler accepts the winner's dial. The loser's outgoing attempt is skipped because `buddyConnections` already has an entry.

### Long-Lived Connections for CGNAT

The less-reachable side (CGNAT) should maintain a persistent or keepalive connection to the public side rather than reconnecting at each `sync_time`. This avoids repeated relay fallback when the CGNAT side can't be dialed. The connection stays open and sync happens over it whenever the sync_time triggers. If the connection drops, the CGNAT side redials promptly.

### CGNAT Connection Flow

Buddy A (CGNAT, no public address) and Buddy B (public):

1. Discovery: A publishes private addresses + `isPubliclyReachable: false`. B publishes public address + `isPubliclyReachable: true`.
2. Both sides compute initiator: A does not have a public address, so A initiates (it dials B directly).
3. A connects to B. B accepts the incoming connection.
4. Both directions of sync happen over the single connection.

If A's direct dial to B fails (misconfigured address on B's side), A falls back to relay and logs a diagnostic suggesting B verify its `announce_addr`.

### Restore Flow

On a replacement machine with only the 12-word phrase:

1. `buddydrive recover` → derive master key → fetch encrypted config from relay → write config.toml
2. Config gives: folder keys (derived from folder IDs + master key), buddy IDs, pairing codes
3. A connects to B (initiator rule applies)
4. A sends `list_paths` request for each folder
5. B responds with list of `(encrypted_path, content_hash, size)` for A's files
6. A decrypts each `encrypted_path` → plaintext path
7. For each path, A checks:
   - Does the file exist locally? If not → request from B
   - Does it exist but with a different `content_hash`? → request from B (corrupt or stale)
   - Same path, same hash → skip (already intact)
8. A decrypts received chunks on-the-fly, writes to plaintext path
9. A verifies each restored file's `content_hash` matches the hash from B's list
10. A rebuilds local index by scanning the restored files

No index blob needed. B's filesystem + A's folder key = complete restore.

### Unencrypted Sharing Mode

When `FolderConfig.encrypted = false`:
- `encrypted_path == path` (no encryption)
- Content is transferred plaintext
- B can browse and read the files
- Same sync protocol, just skip the encrypt/decrypt steps
- `content_hash` is still blake2b-256 of plaintext (same as encrypted mode)

This is a secondary use case for active collaboration. The primary use case is always encrypted backup.

### Known Limitations (v1)

- **Large folder listings**: the file list exchange uses a single framed message (10MB max). A folder with ~100K files at ~100 bytes per entry approaches this limit. Pagination or streaming of file lists is deferred to a future iteration.
- **Reachability signal**: `isPubliclyReachable` is a best-effort hint. Stale UPnP or bad `announce_addr` can make it wrong. The initiator falls back to relay on direct-dial failure and logs diagnostics.

---

## Implementation Plan

### Phase A: Crypto Foundation — COMPLETE

**Files**: `crypto.nim`, `types.nim`, `config.nim`

1. **Streaming content hash** — `hashFileStream(path: string): array[32, byte]` using `crypto_generichash_init/update/final` — DONE
2. **Deterministic path encryption** — `encryptPath(plainPath, folderKey): string` and `decryptPath(encPath, folderKey): string` using derived nonce — DONE
3. **Chunk encryption with random nonces** — `encryptChunk(data, folderKey): seq[byte]` (random nonce, prepended) and `decryptChunk(data, folderKey): seq[byte]` (extracts nonce from prefix) — DONE
4. **Folder key derivation** — `deriveFolderKey(masterKey, folderId): string` — DONE
5. **Add folder ID and folder key to config** — `FolderConfig` has `id: string` (UUID) and `folderKey: string` fields. `add-folder` generates both. — DONE
6. **Remove old `hashFile`** — deleted the broken `std/hashes`-based function from scanner.nim — DONE
7. **Remove old `encryptFilename`/`decryptFilename`** — replaced with the new deterministic `encryptPath`/`decryptPath` — DONE

### Phase B: Index Redesign — COMPLETE

**Files**: `index.nim`, `types.nim`

1. **New owner schema** — `files` table with `path`, `encrypted_path`, `hash` (content_hash), `size`, `mtime`, `synced`, `last_sync`, `mode`, `symlink_target`. Indexes on `content_hash` and `encrypted_path`. — DONE
2. **New storage schema** — `storage_files` table with `encrypted_path`, `content_hash`, `size`, `mode`, `symlink_target`, `owner_buddy`. Index on `content_hash + owner_buddy`. — DONE
3. **Index API** — `getFileByHash`, `addStorageFile`, `getStorageFile`, `listByOwner`, `getFileByEncryptedPath`, `updateStoragePath` — DONE
4. **Migration** — schema versioning with v1→v2→v3 upgrades — DONE

### Phase C: Scanner Rewrite — COMPLETE

**Files**: `scanner.nim`

1. **Use streaming hash** — `scanFile` calls `hashFileStream` — DONE
2. **Compute encrypted_path** — `scanFile` computes `encrypted_path` via `encryptPath` — DONE
3. **Move detection** — `scanChanges` checks for same `content_hash` at a new path when the old path disappears, marks as `fcMoved` — DONE

### Phase D: Sync Protocol Update — COMPLETE

**Files**: `messages.nim`, `protocol.nim`, `transfer.nim`, `session.nim`

1. **Update FileList message** — includes `content_hash` and `encryptedPath` in `FileEntry` — DONE
2. **Add ListPaths message** — `msgListPathsRequest`/`msgListPathsResponse` for restore — DONE
3. **Add MoveFile message** — A tells B to rename an encrypted_path — DONE
4. **Add DeleteFile message handling** — `msgFileDelete` is sent and handled — DONE
5. **Encrypt chunks on send** — `sendFileData` encrypts each chunk with random nonce — DONE
6. **Decrypt chunks on receive** — `receiveFileData` extracts nonce and decrypts — DONE
7. **Session flow** — `syncBuddyFolders` handles both push (backup) and pull (restore) with move/delete support — DONE
8. **Unencrypted shortcut** — when `folder.encrypted == false`, skip encrypt/decrypt steps — DONE
9. **Hash verification** — `verifyRestoredFile` re-scans and checks hash after write — DONE

### Phase E: Connection & Scheduling — PARTIALLY COMPLETE

**Files**: `daemon.nim`, `types.nim`, `config.nim`, `p2p/discovery.nim`

1. **Per-buddy sync_time** — `BuddyInfo.syncTime` field, config read/write, `shouldAttemptBuddySync` — DONE
2. **Discovery record extension** — `isPubliclyReachable: bool` and `syncTime: string` published in record — DONE
3. **Deterministic initiator** — `shouldInitiate()` implements the CGNAT-correct rule — DONE
4. **Remove incoming rejection** — `handleIncomingConnection` always accepts from known buddies — DONE
5. **Scheduled dialing** — `connectToBuddies` respects per-buddy sync_time with 15-minute tolerance — DONE
6. **Connection reuse** — checks for existing transport connections before new dial — NOT YET
7. **Connection upgrade** — replace relay with direct when possible — NOT YET
8. **Long-lived CGNAT connections** — keepalive and prompt redial — NOT YET

### Phase F: Restore — PARTIALLY COMPLETE

**Files**: `cli.nim`, `daemon.nim`, `p2p/protocol.nim`, `p2p/messages.nim`

1. **ListPaths protocol** — `msgListPathsRequest`/`msgListPathsResponse` — DONE
2. **Restore flow in daemon** — missing/hash-mismatched local files requested from buddy — DONE
3. **Hash verification on restore** — `verifyRestoredFile` computes hash and compares — DONE
4. **Index rebuild** — after restoring files, scan populates the owner index — DONE
5. **Buddy-backed config fetch** — `fetchConfigFromBuddy()` not implemented yet — NOT YET

### Phase G: Testing — COMPLETE

Existing test coverage:

1. **Unit tests** — streaming hash, deterministic path encryption/decryption, chunk encryption/decryption with random nonces, folder key derivation, move detection, initiator selection, session sync — DONE
2. **Integration test** — relay file sync: full file sync over relay — DONE
3. **Integration test** — recovery: setup-recovery and recover CLI flows — DONE
4. **Integration test** — pairing protocol — DONE
5. **Integration test** — CLI flows — DONE

Still to add:
6. **Integration test** — CGNAT simulation: one side with no public address, verify correct initiator selection and direct connection — NOT YET
7. **Integration test** — mixed encrypted/unencrypted: two folders, one encrypted one shared — NOT YET
8. **Unit test** — nonce reuse safety: encrypt the same file twice, verify ciphertexts differ — NOT YET
9. **Unit test** — path determinism: encrypt the same path twice, verify encrypted_paths are identical — NOT YET

### Implementation Order

A → B → C → D → E → F → G (Phases A-D and most of E-F are complete; remaining items are connection reuse, connection upgrade, long-lived CGNAT connections, buddy-backed config fetch, and some integration tests)

---

## Test Coverage

### Unit Tests (17 files)

`tests/unit/*/*.nim` — run via `nimble test` or `nimble testUnit`:

config, config_sync, control, control_web, crypto, discovery, geoip_ranges, index, messages, pairing, policy, rawrelay, recovery, scanner, session, transfer crash safety, types

### Integration Tests (7 files)

`tests/integration/*.nim` — run via `nimble test` or `nimble testIntegration`:

CLI flows, KV API, config sync e2e, relay fallback, relay file sync, relay server, pairing protocol

### Remaining Tests To Add

- Streaming hash vs full-file hash comparison
- Deterministic path encryption roundtrip
- Chunk encryption roundtrip (random nonces, different ciphertext each time)
- Folder key derivation from folder ID + master key
- Move detection in scanner
- Initiator selection (various reachability combinations)
- Full encrypted backup + restore
- Mixed encrypted/unencrypted folders
- Nonce reuse safety (same content → different ciphertext)
- Path determinism (same path → same encrypted path)

## Public Relay

- **TCP relay**: `01.proxy.koyeb.app:19447`
- **KV API**: `https://buddydrive-tankfeud-ddaec82a.koyeb.app`
- **Region**: Frankfurt (fra)

To deploy your own relay, see [relay/README.md](../relay/README.md).
