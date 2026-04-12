# BuddyDrive Control API

REST API served by the daemon on `127.0.0.1:17521` by default. The actual port is written to `~/.buddydrive/port` after startup.

## Authentication

None. The control server only binds to localhost.

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
  "addresses": ["/ip4/203.0.113.10/tcp/41721/p2p/16Uiu2HAm..."]
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

Show current saved configuration.

**Response:**

```json
{
  "buddy": {
    "name": "purple-banana",
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "folders": [],
  "buddies": []
}
```

### POST /config

Update selected config fields.

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
{"ok": true}
```

### POST /config/reload

Reload configuration from disk.

**Response:**

```json
{"ok": true}
```

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

## Notes

- The API is intentionally localhost-only and has no extra authentication layer.
- `POST /buddies/pair` requires a `code` field.
- Recovery-specific operations are handled by the CLI today, not the control API.
- There is no separate `GET /sync/:folder` endpoint in the current implementation; live status is exposed through `GET /folders` and `GET /buddies`.
