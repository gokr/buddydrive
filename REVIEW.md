# Review

Reviewed against `PLAN.md` and the current working tree on 2026-04-09.

## Findings

### High

1. `src/buddydrive/p2p/protocol.nim:37-42,56-62` uses `Option[ProtocolMessage]`, `none(...)`, and `some(...)` without importing `std/options`.
This is a compile blocker for the protocol layer.

2. `src/buddydrive/cli.nim:407` and `src/buddydrive/daemon.nim:42` call `daemon.node.listenAddrs()`, but `BuddyNode` only exposes `getAddrs()` in `src/buddydrive/p2p/node.nim:82-85`.
This is another compile blocker in the main startup path.

3. `src/buddydrive/cli.nim:447` uses `mapIt(...)` without importing `std/sequtils`.
That makes the `status` command fail to compile.

4. `src/buddydrive/p2p/messages.nim:141` casts untrusted network data directly with `MessageKind(data[0])`.
An invalid first byte can raise a range defect instead of returning a clean protocol error.

5. `src/buddydrive/p2p/messages.nim:156-161,172-178,189-195,202-208,243-248` reads variable-length fields without checking that `pos + length <= data.len` before copying bytes.
Malformed or truncated packets can read past the end of the buffer and crash the process instead of being rejected.

6. `src/buddydrive/config.nim:75-103` writes TOML by string concatenation without escaping quotes, backslashes, or newlines.
This will break config persistence for valid user input like folder names containing `"`, and especially Windows paths despite `README.md:12` claiming cross-platform support.

### Medium

7. `src/buddydrive/cli.nim:503-513` does not generate a UUID despite the CLI, README, and plan all presenting the identifier as a UUID.
It produces four 8-hex chunks instead of the standard UUID layout, and it uses `randomize()` / `rand()` rather than a stronger ID generator.

8. `src/buddydrive/cli.nim:328` tells the other side to run `add-buddy --id` with `cfg.buddy.uuid.shortId()` instead of the full ID.
That conflicts with the rest of the code and docs, which expect full buddy IDs for lookup and removal.

9. `src/buddydrive/p2p/node.nim:58-64` builds the switch with `.withAddresses(@[])`.
Even if the rest of the stack compiled, the node is not configured with listening addresses, which makes the advertised peer-to-peer flow in `PLAN.md` unlikely to work.

10. `src/buddydrive/p2p/discovery.nim:35-54` is effectively a stub.
`start()` only flips a boolean, `announce()` does nothing, and `findBuddy()` always returns `@[]`. The daemon logs successful DHT publication in `src/buddydrive/daemon.nim:50-57`, but discovery is not implemented yet.

11. `src/buddydrive/cli.nim:341-345` presents buddy pairing as a command but only prints a placeholder message and never persists a buddy with `config.addBuddy(...)`.
That makes the CLI surface look more complete than the implementation actually is.

12. `src/buddydrive/logutils.nim:7-21` only writes to a file if a path is explicitly passed, but `src/buddydrive.nim:5` calls `setupLogging()` with no path and `src/buddydrive/cli.nim:464-472` offers a `logs` command that expects a log file.
In the normal startup path, `buddydrive logs` will often report no log file even after running commands.

### Low

13. `PLAN.md:28-32` expects `logging.nim`, but the codebase currently uses `src/buddydrive/logutils.nim`.
This is not a functional bug, but it is a plan/code mismatch that makes the repo harder to navigate.

14. `src/buddydrive/config.nim:105-106` uses a temp file plus `moveFile(...)`, which is a good start, but the write path is not clearly atomic across filesystems and does not clean up the temp file on failure.
That is more of a robustness concern than an immediate bug.

## Test And Verification Gaps

1. `buddydrive.nimble:15-17` defines a `test` task for `tests/test_crypto.nim` and `tests/test_config.nim`, but there is currently no `tests/` tree in the repository.

2. `PLAN.md:43-47` calls out `test_crypto.nim`, `test_config.nim`, and `tests/harness/test_local_sync.nim`, but none of those files are present.

3. I attempted `nimble test` and `nimble build` for verification. Both currently fail before local compilation due a dependency metadata parse error in the installed `lsquic` package under `~/.nimble/pkgs2/.../nimblemeta.json`.
That means the project is not currently verified end-to-end in this environment, independent of the source-level issues above.

## Overall Assessment

The repository has a good project outline and a reasonable CLI/config skeleton, but it is still much closer to an early scaffold than to the MVP described in `PLAN.md`.

The biggest immediate issues are:

1. Build-breaking compile defects in the active CLI/protocol code paths.
2. Unsafe message decoding on untrusted peer input.
3. Missing tests despite the nimble contract and plan.
4. Several CLI commands and daemon/discovery paths that present themselves as working features while still being placeholders.
