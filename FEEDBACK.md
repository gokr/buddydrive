# PLAN.md Feedback

## Findings — All Resolved

All findings below have been addressed in the current implementation:

1. ~~High: deterministic chunk nonces from `folderKey + encryptedPath + offset` are unsafe~~ — **Fixed**: chunk encryption now uses random nonces. Deterministic nonces are only used for path encryption (where the plaintext — the path string — never changes across versions).

2. ~~High: `ciphertext_hash` conflicts with path-dependent ciphertext~~ — **Fixed**: the owner sends a stable plaintext `content_hash` (blake2b-256) for move detection. Storage-side `ciphertext_hash` is not used for sync identity; B stores `content_hash` as reported by A.

3. ~~High: folder key derived from `masterKey + folderName` makes rename a key rotation~~ — **Fixed**: folder key is now derived from `masterKey + "/folder/" + folderId` where `folderId` is a UUID. Renaming a folder does not orphan remote data.

4. ~~High: initiator rules are internally contradictory~~ — **Fixed**: the consistent rule is now "the side WITHOUT a public address initiates; if both same reachability, lower buddy UUID initiates." Implemented in `shouldInitiate()` in `discovery.nim`.

5. ~~Medium: `hasPublicAddress: bool` is too weak~~ — **Partially addressed**: the code uses `isPubliclyReachable` as a best-effort hint. When direct dial fails, the initiator falls back to relay and logs diagnostics. A richer reachability model is deferred.

6. ~~Medium: restore flow only checks whether a path exists~~ — **Fixed**: `shouldSyncRemoteFile` now compares content hash, mtime, size, mode, and symlink target. `verifyRestoredFile` re-scans and checks hash after write.

7. ~~Medium: whole-folder listings in single request/response~~ — **Known limitation**: file list exchange uses a single framed message (30MB max). Pagination or streaming is deferred.

## Open Questions — Resolved

1. ~~Do you want move detection to be authoritative from the owner only?~~ — **Yes**: implemented as owner-authoritative moves. A sends `msgMoveFile`, B does not infer moves from ciphertext identity.

2. ~~Do you want the less-reachable side to be the normal long-lived connector?~~ — **Desired but not yet implemented**: the CGNAT side should maintain persistent/keepalive connections. Currently reconnects on each sync cycle.

3. ~~Do you want storage-side dedup at all?~~ — **Simplified**: B stores `content_hash` as reported by A for move detection. B does not independently hash ciphertext. Storage-side dedup is not implemented.
