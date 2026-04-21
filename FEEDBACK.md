# PLAN.md Feedback

## Findings

1. High: `docs/PLAN.md:161-170` proposes deterministic chunk nonces from `folderKey + encryptedPath + offset`.
This is unsafe for content encryption. If the same file path and offset are reused across versions, you will reuse a nonce with different plaintext under the same key. With `crypto_secretbox_easy`, that is a real cryptographic break, not just a metadata leak. Path determinism may be acceptable for filenames, but chunk/content nonces need either randomness or a version/content-derived input that changes when plaintext changes.

2. High: `docs/PLAN.md:208-214` conflicts with `docs/PLAN.md:263-281`.
The plan wants `ciphertext_hash` to be the stable comparison key on the storage side, but it also makes ciphertext path-dependent via `docs/PLAN.md:163-167`. That means a move changes ciphertext, so `ciphertext_hash` cannot identify “same content at a new path”. If you instead force ciphertext stability with deterministic nonces, you hit finding 1. The clean fix is usually: owner sends a stable content identity for move detection, and storage may keep separate integrity metadata for what is actually stored.

3. High: `docs/PLAN.md:119-125` derives the folder key from `masterKey + folderName`.
That makes folder rename a key rotation. Renaming a folder would orphan remote data or require full re-encryption of the entire backup set. The folder key should come from a stable folder identifier, not the display name. A folder UUID or random per-folder key stored in config is safer.

4. High: the initiator rules are internally contradictory.
`docs/PLAN.md:292-297` says “if only one side has a public address: that side initiates”, but `docs/PLAN.md:348-355` correctly revises that to “the side without a public address initiates”. `docs/PLAN.md:324-329` still uses the older, wrong direction. This needs one consistent rule everywhere, because it is the core CGNAT fix.

5. Medium: `docs/PLAN.md:300-309` reduces dialability to `hasPublicAddress: bool`.
That is probably too weak. “Has a public address” is not the same as “is actually inbound-dialable”. Stale UPnP, bad `announce_addr`, firewalling, and mispublished addresses all break that assumption. I would use a richer reachability model or at least combine advertised addresses with recent direct-success history before deciding who waits and who relays.

6. Medium: `docs/PLAN.md:361-373` restore flow only checks whether a path exists locally.
That is too weak for real recovery. It misses corrupt local files, truncated files, stale versions, and partial restores. Restore logic should compare hashes or at least size plus hash, not just existence.

7. Medium: `docs/PLAN.md:250-257` and `docs/PLAN.md:449-450` assume whole-folder listings fit in single request/response flows.
For large folders, `list_paths` and file-list exchange can become a message-size and memory problem. The plan should mention pagination or streaming of path lists now, otherwise the protocol design will need reshaping later.

## Open Questions

1. Do you want move detection to be authoritative from the owner only?
That is the simplest secure model: A tells B “rename old encrypted path to new encrypted path”, and B does not try to infer moves from ciphertext identity.

2. Do you want the less-reachable side to be the normal long-lived connector?
That would align well with the CGNAT issue and reduce needless relay fallback more than purely scheduled one-shot dialing.

3. Do you want storage-side dedup at all?
If not, you can simplify a lot by dropping the need for stable ciphertext identity and treating B as opaque encrypted blob storage plus rename/delete executor.

## Overall

The direction is good, especially:
- treating sync transport as bidirectional over one connection
- always accepting incoming sync
- fixing the CGNAT initiation rule
- moving away from mtime/size-only comparison

The main thing I would change before implementation is the crypto/data-identity model:
- stable folder key from folder ID, not folder name
- deterministic path encryption only for paths
- non-deterministic or version-safe content encryption
- stable owner-supplied content identity for move detection, not ciphertext hash as the main sync identity
