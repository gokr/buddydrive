# BuddyDrive Relay — Development Notes

## Goal

Build **BuddyDrive Relay** — a TCP relay server and optional HTTP API for BuddyDrive. The relay enables NAT traversal when direct P2P connections fail. The API stores encrypted config blobs for recovery and buddy discovery records.

## Status: Complete

The relay server is fully functional and deployed.

## Architecture

### TCP Relay

- Token-based pairing: two clients with the same token are connected bidirectionally
- Proof-of-work challenge (configurable difficulty, default 16 bits) to prevent abuse
- Any token is accepted — no whitelist
- Limits: MaxClients=256, MaxWaitingClients=128, IdleTimeout=5min, WaitingTimeout=60s, MaxSessionBytes=64MB, MaxSessionDuration=30min
- GeoIP policy: optional EU-only access via `BUDDYDRIVE_RELAY_EU_ONLY`

### HTTP API (optional, `-d:withKvStore`)

- TiDB Cloud MySQL backend via `debby` ORM
- Encrypted config blobs: GET/PUT/DELETE at `/kv/<pubkey>` with signed mutations (Ed25519)
- Discovery records: GET/PUT/DELETE at `/discovery/<key>` with HMAC authentication
- Rate limiting: token bucket per IP and per key
- GeoIP policy: optional EU-only API access via `BUDDYDRIVE_KV_EU_ONLY`
- Health check: GET `/health`

## Deployment

- **Public relay**: `relay-eu.buddydrive.org:19447` (TCP), `https://api.buddydrive.org` (API)
- **Region**: Frankfurt (fra)
- Docker and Koyeb deployment supported
- VPS deployment with Docker also supported

## Key Dependencies

- **mummyx** (fork) — HTTP server for the API
- **debby** (fork) — MySQL ORM for TiDB Cloud
- **db_mysql** — MySQL driver

## See Also

- [relay/README.md](README.md) for usage, Docker, and deployment details
- [relay/geo/README.md](geo/README.md) for EU-only access configuration
