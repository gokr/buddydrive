# BuddyDrive Control API

REST API served by the daemon on `0.0.0.0:17521` by default. The actual port is written to `~/.buddydrive/port` after startup.

## Authentication

- **Localhost** (`127.0.0.1`, `::1`): No authentication required.
- **LAN**: Requests from non-localhost addresses must use a secret path prefix `/w/<secret>/`. The secret is derived from the buddy UUID (first 8 chars, lowercase, no hyphens) and is printed at daemon startup. Requests without the correct prefix receive `403 Forbidden`.

## Web GUI

The control server also serves a built-in web GUI:

- **Localhost**: `http://127.0.0.1:<port>/`
- **LAN**: `http://<ip>:<port>/w/<secret>/`

The web GUI uses the same REST API below. Assets are embedded in the binary at compile time.

## Endpoints

### GET /status

Overall daemon status.

**Response:**

```json
{
  "buddy": {
    "name": "purple-banana",
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "running": true,
  "uptime": 3600,
  "peerId": "16Uiu2HAm...",
  "addresses": ["/ip4/203.0.113.10/tcp/41721/p2p/16Uiu2HAm..."],
  "syncEnabled": true,
  "syncWindow": "always"
}
```

### GET /buddies

List configured buddies plus any live status written by the daemon.

**Response:**

```json
{
  "buddies": [
    {
      "id": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
      "name": "cranky-wrench",
      "state": "connected",
      "latencyMs": 45,
      "lastSync": "2026-04-09T14:30:00Z"
    }
  ]
}
```

### POST /buddies/pairing-code

Generate a pairing code using the current local identity.

**Response:**

```json
{
  "buddyId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "buddyName": "purple-banana",
  "pairingCode": "X7K9-M2P4",
  "expiresAt": "2026-04-09T15:00:00Z"
}
```

### POST /buddies/pair

Add a buddy through the local API.

**Request:**

```json
{
  "buddyId": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
  "buddyName": "cranky-wrench",
  "code": "X7K9-M2P4"
}
```

**Response:**

```json
{
  "ok": true,
  "message": "Buddy paired successfully"
}
```

### DELETE /buddies/:id

Remove a buddy.

**Response:**

```json
{"ok": true}
```

### GET /folders

List configured folders plus any live sync status written by the daemon.

**Response:**

```json
{
  "folders": [
    {
      "name": "docs",
      "path": "/home/user/Documents",
      "encrypted": true,
      "buddies": ["b2c3d4e5-f6a7-8901-bcde-f23456789012"],
      "status": {
        "totalBytes": 2500000000,
        "syncedBytes": 2400000000,
        "fileCount": 1500,
        "syncedFiles": 1480,
        "status": "syncing"
      }
    }
  ]
}
```

### POST /folders

Add a folder.

**Request:**

```json
{
  "name": "docs",
  "path": "/home/user/Documents",
  "encrypted": true,
  "buddies": ["b2c3d4e5-f6a7-8901-bcde-f23456789012"]
}
```

**Response:**

```json
{"ok": true}
```

### DELETE /folders/:name

Remove a folder.

**Response:**

```json
{"ok": true}
```

### POST /sync/:folderName

Trigger sync for a folder name.

**Response:**

```json
{
  "ok": true,
  "message": "Sync started",
  "folder": "docs"
}
```

### GET /logs

Get recent log lines.

**Response:**

```json
{
  "logs": [
    {
      "raw": "2026-04-09T14:30:00Z INFO Connected to buddy: cranky-wrench"
    }
  ]
}
```

### GET /config

Show current saved configuration including network settings.

**Response:**

```json
{
  "buddy": {
    "name": "purple-banana",
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "network": {
    "listen_port": 41721,
    "announce_addr": "/ip4/203.0.113.10/tcp/41721",
    "relay_base_url": "https://buddydrive.net/relays",
    "relay_region": "eu",
    "sync_window_start": "",
    "sync_window_end": ""
  },
  "folders": [],
  "buddies": []
}
```

### POST /config

Update selected config fields. Returns `restartRequired` when changes need a daemon restart.

**Request:**

```json
{
  "buddy": {
    "name": "purple-banana"
  },
  "network": {
    "announce_addr": "/ip4/203.0.113.10/tcp/41721",
    "relay_base_url": "https://buddydrive.net/relays",
    "relay_region": "eu"
  }
}
```

**Response:**

```json
{
  "ok": true,
  "restartRequired": false
}
```

### POST /config/reload

Reload configuration from disk.

**Response:**

```json
{"ok": true}
```

## Recovery Endpoints

### POST /recovery/setup

Set up recovery with a BIP39 12-word mnemonic. Returns the mnemonic, public key, and master key.

**Response:**

```json
{
  "ok": true,
  "mnemonic": "notice expand butter soccer cart double burst fly wheel actual receive engage",
  "words": ["notice", "expand", "butter", "soccer", "cart", "double", "burst", "fly", "wheel", "actual", "receive", "engage"],
  "publicKey": "VmG8RusP5Xx",
  "masterKey": "a1b2c3d4..."
}
```

**Error codes:** `NO_CONFIG`, `ALREADY_SETUP`

### POST /recovery/verify-word

Verify a single word from the recovery phrase at a given index.

**Request:**

```json
{
  "index": 2,
  "word": "butter"
}
```

**Response:**

```json
{
  "ok": true,
  "correct": true
}
```

**Error codes:** `NO_CONFIG`, `NOT_SETUP`, `INVALID_INDEX`, `MISSING_WORD`

### POST /recovery/recover

Restore config from a 12-word mnemonic.

**Request:**

```json
{
  "mnemonic": "notice expand butter soccer cart double burst fly wheel actual receive engage"
}
```

**Response:**

```json
{
  "ok": true,
  "publicKey": "VmG8RusP5Xx",
  "masterKey": "a1b2c3d4..."
}
```

**Error codes:** `INVALID_MNEMONIC`, `NO_CONFIG`, `MISMATCH`

### GET /recovery

Show current recovery status.

**Response:**

```json
{
  "ok": true,
  "publicKey": "VmG8RusP5Xx",
  "masterKey": "a1b2c3d4...",
  "enabled": true
}
```

**Error codes:** `NO_CONFIG`, `NOT_SETUP`

### POST /recovery/export

Export recovery info (same as GET /recovery).

### POST /recovery/sync-config

Manually push encrypted config to the relay KV store.

**Response:**

```json
{
  "ok": true,
  "message": "Config synced to relay"
}
```

**Error codes:** `NO_CONFIG`, `NOT_SETUP`, `SYNC_FAILED`

## Error Responses

All errors follow this format:

```json
{
  "error": "Folder not found",
  "code": "FOLDER_NOT_FOUND"
}
```

Common error codes:

- `FOLDER_NOT_FOUND` - folder doesn't exist
- `BUDDY_NOT_FOUND` - buddy doesn't exist
- `INVALID_REQUEST` - bad or incomplete JSON body
- `NOT_FOUND` - endpoint not found
- `INTERNAL_ERROR` - server-side exception while handling the request
- `NO_CONFIG` - no config file found
- `ALREADY_SETUP` - recovery already enabled
- `NOT_SETUP` - recovery not set up
- `INVALID_MNEMONIC` - invalid 12-word mnemonic
- `MISMATCH` - mnemonic doesn't match stored master key
- `SYNC_FAILED` - config sync to relay failed

## Notes

- The API binds to `0.0.0.0` to allow LAN access via secret path authentication.
- `POST /buddies/pair` requires a `code` field.
- `POST /config` returns `restartRequired` when the daemon needs a restart for changes to take effect.
- There is no separate `GET /sync/:folder` endpoint; live status is exposed through `GET /folders` and `GET /buddies`.
- The daemon also reloads config from disk automatically when `config.toml` changes (polls mtime in the discovery loop).
