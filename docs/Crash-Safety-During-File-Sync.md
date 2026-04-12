# Investigation: Crash Safety During File Sync

## Context

BuddyDrive syncs files between peers over libp2p using a chunked transfer protocol (64KB chunks, LZ4 compression). The question is: what happens if either peer crashes mid-sync, and can it recover cleanly afterward?

## Findings

### Current crash recovery: mostly safe, but with gaps

**What works well:**
- The `synced` flag in SQLite (`index.db`) is only set to `1` *after* the entire file is successfully received and written (`transfer.nim:226-227`). A crash mid-transfer leaves the file at `synced=0`, so the next sync session will re-transfer it.
- On reconnection (discovery loop retries every 15s, `daemon.nim:160-171`), the full sync handshake runs again: file lists are exchanged, `compareWithRemote()` detects what's missing/outdated by mtime+size, and needed files are re-requested.
- Config writes use atomic temp-file + rename (`config.nim`), so config won't corrupt on crash.

**Identified risks and gaps:**

### 1. Partially-written files left on disk (MEDIUM risk)
- `writeFileChunk()` (`scanner.nim:99-118`) writes directly to the final path -- no temp file, no atomic rename.
- If the receiver crashes after writing some chunks but before receiving all of them, a **truncated/corrupt file** remains at the target path.
- On restart, `compareWithRemote()` (`transfer.nim:237-250`) compares by **mtime and size** (`policy.nim:44-49`). The partially-written file may have a **different size** than the remote, so it would be re-synced. But:
  - If the OS updated mtime on the partial file to be *newer* than the remote's mtime, and the size happens to match (e.g., crash on last chunk of same-size update), `shouldSyncRemoteFile` would return `false` -- the corrupt file would **not** be re-synced.
  - The hash field exists in the schema but is **not used** in sync policy decisions (`policy.nim:44-49` only checks mtime and size).

### 2. No fsync after writes (LOW-MEDIUM risk)
- `writeFileChunk()` does not call `fsync`/`flushFile`. On power loss (not just process crash), data in OS write buffers may be lost, leaving a file that appears complete (correct size in directory entry) but contains zeroes or garbage in some regions.

### 3. SQLite index can become stale (LOW risk)
- `addFile` uses `INSERT OR REPLACE` (`index.nim:64-69`) with `tryExec` (no explicit transactions). If the process crashes between writing a file chunk and updating the index, the index may be missing the file or have stale metadata. However, since synced=0 files are just re-transferred, this is mostly benign.
- The index DB itself is opened without explicit WAL mode, so SQLite defaults to journal mode which is crash-safe for the DB itself.

### 4. Sender-side crash (LOW risk)
- If the sender crashes mid-transfer, the receiver's `receiveFileData()` (`transfer.nim:195-197`) will get `isNone` from `receiveMessage` and set `success = false`. The partially-written file stays on disk but is **not** marked as synced. On next sync, it will be re-requested.
- The partial file on disk is the same risk as point 1 above.

### 5. No transfer resumption (EFFICIENCY issue, not safety)
- Although `requestFile()` accepts an `offset` parameter (`transfer.nim:114`), there is no logic to actually resume from a saved offset. After crash, the entire file is re-transferred from byte 0.
- For large files over slow connections, this means repeated wasted bandwidth.

### 6. Append-only folders suppress re-sync (MEDIUM risk)
- If a folder is `appendOnly` and a file already exists locally (even partially/corrupt), `shouldSyncRemoteFile` returns `false` (`policy.nim:47-48`). A crash that leaves a partial file in an append-only folder would result in a permanently corrupt file that never gets re-synced.

## Summary

| Scenario | Safe? | Why |
|----------|-------|-----|
| Receiver crash, file not yet complete | Usually yes | synced=0, will re-transfer. But partial file left on disk. |
| Receiver crash, size happens to match remote | **No** | compareWithRemote may skip it if mtime is newer |
| Sender crash mid-transfer | Yes | Receiver sees connection drop, doesn't mark synced |
| Crash in append-only folder | **No** | Partial file won't be re-synced |
| Power loss (not process crash) | Risky | No fsync, data may be lost silently |
| SQLite index corruption | Very unlikely | SQLite journal mode protects DB integrity |

## Recommended Fixes (if desired)

1. **Write to temp file, then atomic rename** -- change `receiveFileData` to write chunks to `<path>.buddytmp`, then `moveFile()` to final path on success. Delete `.buddytmp` on startup cleanup.
2. **Use hash in sync comparison** -- after receiving a file, verify its hash matches the remote's hash. Also use hash (not just mtime+size) in `shouldSyncRemoteFile` to catch corrupt files.
3. **Add fsync** -- call `flushFile(f)` before close in `writeFileChunk`, or at least once after all chunks are written.
4. **Fix append-only gap** -- in append-only mode, if a local file exists but its hash doesn't match remote, allow re-sync (it was never fully synced).
5. **Startup cleanup** -- on daemon start, scan for and delete any `.buddytmp` files (leftovers from interrupted transfers).

## Key Files
- `src/buddydrive/sync/transfer.nim` -- transfer protocol, chunk send/receive
- `src/buddydrive/sync/scanner.nim` -- file I/O (writeFileChunk, readFileChunk, hashFile)
- `src/buddydrive/sync/session.nim` -- sync session orchestration
- `src/buddydrive/sync/index.nim` -- SQLite index (synced flag)
- `src/buddydrive/sync/policy.nim` -- sync decision logic (shouldSyncRemoteFile)
- `src/buddydrive/daemon.nim` -- daemon lifecycle, reconnection loop
