# BuddyDrive Control API

REST API served by the daemon on `127.0.0.1:17521` (configurable).

## Authentication

None required - only accessible from localhost. The port is written to `~/.buddydrive/port` after startup.

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
  "peerId": "QmXxxx...",
  "addresses": ["/ip4/192.168.1.100/tcp/4001/p2p/QmXxxx..."]
}
```

### GET /buddies

List all configured buddies.

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

### POST /buddies

Add a new buddy.

**Request:**
```json
{
  "name": "cranky-wrench",
  "id": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
  "pairingCode": "X7K9-M2P4"
}
```

**Response:**
```json
{
  "ok": true,
  "buddy": {
    "id": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
    "name": "cranky-wrench"
  }
}
```

### DELETE /buddies/:id

Remove a buddy.

**Response:**
```json
{"ok": true}
```

### POST /buddies/pairing-code

Generate a new pairing code.

**Response:**
```json
{
  "buddyId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "buddyName": "purple-banana",
  "pairingCode": "X7K9-M2P4",
  "expiresAt": "2026-04-09T15:00:00Z"
}
```

### GET /folders

List all configured folders.

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
{
  "ok": true,
  "folder": {
    "name": "docs",
    "path": "/home/user/Documents"
  }
}
```

### DELETE /folders/:name

Remove a folder.

**Response:**
```json
{"ok": true}
```

### POST /sync/:folderName

Trigger manual sync for a folder.

**Response:**
```json
{
  "ok": true,
  "syncId": "sync-123",
  "message": "Sync started"
}
```

### GET /sync/:folderName

Get sync status for a folder.

**Response:**
```json
{
  "folder": "docs",
  "status": "syncing",
  "progress": 85,
  "filesTotal": 1500,
  "filesSynced": 1275,
  "bytesTotal": 2500000000,
  "bytesSynced": 2125000000,
  "currentFile": "project/report.pdf",
  "startedAt": "2026-04-09T14:30:00Z",
  "errors": []
}
```

### GET /sync/:folderName/cancel

Cancel ongoing sync.

**Response:**
```json
{"ok": true}
```

### GET /logs

Get recent log entries.

**Query params:**
- `count` - Number of lines (default: 100, max: 1000)
- `level` - Filter by level: debug, info, warn, error

**Response:**
```json
{
  "logs": [
    {
      "timestamp": "2026-04-09T14:30:00Z",
      "level": "info",
      "message": "Connected to buddy: cranky-wrench"
    }
  ]
}
```

### POST /config/reload

Reload configuration from disk.

**Response:**
```json
{"ok": true}
```

### GET /config

Show current configuration.

**Response:**
```json
{
  "buddy": {
    "name": "purple-banana",
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "folders": [...],
  "buddies": [...]
}
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
- `CONFIG_NOT_FOUND` - No config file
- `FOLDER_NOT_FOUND` - Folder doesn't exist
- `BUDDY_NOT_FOUND` - Buddy doesn't exist
- `SYNC_IN_PROGRESS` - Sync already running
- `INVALID_REQUEST` - Bad JSON body
- `PAIRING_FAILED` - Pairing rejected
