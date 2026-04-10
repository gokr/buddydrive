---
## Goal

Add a working local control API to BuddyDrive so the GTK4 GUI can query daemon status, trigger syncs, manage folders/buddies, and show real-time feedback. The user wants:
1. GUI to actually add/remove folders and buddies through the API
2. A small pairing dialog instead of just showing the code in the status line
3. Control server to expose richer live state from the daemon safely

## Instructions

- Use direct GTK4 (not Owlkettle), as decided earlier in the conversation
- Control server must work with Chronos (daemon uses Chronos/libp2p) - final solution was a simple synchronous socket server in its own native thread
- All dynamic state stored in SQLite (`~/.buddydrive/state.db`)
- Static config remains in `config.toml`
- Use `{.cast(gcsafe).}` blocks when calling control functions from Chronos async procs
- Use `--threads:on` for building
- The GUI should read control port from `~/.buddydrive/port` instead of hardcoding
- Import `db_connector/db_sqlite` for SQLite access (bundled with Nim)

## Discoveries

- Jester uses asyncdispatch, which conflicts with Chronos (different async runtimes)
- Mummy requires `{.gcsafe, closure.}` handlers but Nim's GC-safety analyzer was problematic with global state
- Final working approach: simple synchronous `std/net` socket server in a native thread, reading from SQLite
- Nim's thread GC-safety checks propagate through call chains; `{.cast(gcsafe).}` is needed to suppress at thread boundaries
- Chronos async procs can only call GC-safe code, requiring casts around control server calls
- GTK4 uses `gtk_editable_get_text` instead of `gtk_entry_get_text` for text entry widgets
- Nim closures with `{.cdecl.}` calling convention cannot capture local variables; must use `userData` pointers with allocated memory
- Live status updates via daemon's `statusUpdateLoop` writing to SQLite every 2 seconds
- Chronos async procs that call `sleepAsync` must declare `raises: [CancelledError]`
- SQLite is better than JSON files for state: atomic updates, better concurrency, single source of truth
- `db_connector/db_sqlite` is bundled with Nim 2.2.8+, provides high-level SQLite API

## Accomplished

**Completed:**
- Created branch `gui-control-server` and worktree at `/home/gokr/tankfeud/buddydrive-gui-control`
- Implemented working control server in `src/buddydrive/control.nim`:
  - Simple synchronous HTTP server on localhost (default port 17521)
  - SQLite state.db with tables: `runtime_status`, `buddy_state`, `folder_state`
  - Endpoints: `/status`, `/buddies`, `/folders`, `/config`, `/logs`, `/buddies/pairing-code`, `/sync/:folder`, `/folders` (POST/DELETE), `/config/reload`, `/buddies/:uuid` (DELETE)
- Wired daemon startup to call `writeRuntimeStatus()`, `startControlServer()`, and `statusUpdateLoop()`
- Daemon writes buddy/folder live state to SQLite every 2 seconds via `statusUpdateLoop`
- Updated GUI with:
  - Clear and refresh lists properly (no row duplication)
  - Show daemon availability status
  - Show action feedback in-app (message label) instead of stdout
  - Read control port from `~/.buddydrive/port`
  - Add Folder dialog with name/path/encryption inputs
  - Pairing dialog showing code prominently with identity and expiration
  - Sync and Remove buttons on each folder row
  - Remove button on each buddy row
  - Proper memory allocation for button callbacks using `allocStr`/`freeStr`
- Both `nimble build` and `nimble gui_release` compile successfully
- Daemon creates `state.db` with SQLite tables for runtime status, buddy connections, folder sync progress
- Control server reads live state from SQLite and serves it via API

**Architecture:**
- `config.toml` - static configuration (identity, folders, buddies list)
- `state.db` - dynamic state:
  - `runtime_status` table: peerId, addresses, running, startedAt
  - `buddy_state` table: id, name, state (csConnected/csDisconnected), latencyMs, lastActivity
  - `folder_state` table: name, totalBytes, syncedBytes, fileCount, syncedFiles, status

**Known limitations:**
- Sync endpoints acknowledge but don't drive real sync engine
- Folder sync status values are still stubs (totalBytes, syncedBytes = 0) - need integration with FileIndex

## Relevant files / directories

**Worktree:** `/home/gokr/tankfeud/buddydrive-gui-control` (branch: `gui-control-server`)

**Core control server:**
- `src/buddydrive/control.nim` - synchronous localhost HTTP server, SQLite state management

**Daemon integration:**
- `src/buddydrive/daemon.nim` - calls `writeRuntimeStatus()`, `startControlServer()`, and `statusUpdateLoop()`

**GUI:**
- `src/buddydrive_gui.nim` - GTK4 GUI with dialogs, action buttons, message label

**Config:**
- `src/buddydrive/config.nim` - defines `getStatePath()` for `state.db`

**Build:**
- `buddydrive.nimble` - has `--threads:on` in build task

**Next work needed:**
1. Connect sync progress to real sync engine state (from FileIndex)
2. Add confirmation dialogs for destructive actions
3. Add refresh button for individual folders
4. Show folder sync history/errors
