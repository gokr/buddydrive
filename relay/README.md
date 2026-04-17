# BuddyDrive Relay

A TCP relay server and KV store for BuddyDrive. The relay enables NAT traversal when direct connections are not possible. The KV store (optional, requires TiDB Cloud) stores encrypted config blobs for recovery.

## How It Works

### TCP Relay

1. Client connects and sends a token (the pairing code) followed by `\n`
2. Server replies with `POW <nonce> <difficulty>`
3. Client sends `POW <counter>` for a valid proof-of-work solution
4. If no peer with the same token is waiting, the client waits
5. When a matching peer connects, both receive `OK`
6. All further bytes are relayed bidirectionally until one side disconnects

On the BuddyDrive side, the buddy `pairing_code` is reused as this relay token. Any token is accepted — there is no whitelist.

### KV Store (optional)

When built with `-d:withKvStore`, the relay also runs an HTTP API for storing encrypted config blobs and buddy discovery records. BuddyDrive uses the KV store for recovery (encrypted config uploaded with public key as lookup key) and the discovery endpoint for peer discovery (address records published with keys derived from pairing codes).

**KV API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/kv/<pubkey>` | Fetch encrypted config |
| PUT | `/kv/<pubkey>` | Store encrypted config (signed) |
| DELETE | `/kv/<pubkey>` | Delete config (signed tombstone) |
| GET | `/health` | Health check |

**Discovery API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/discovery/<key>` | Fetch buddy address record |
| PUT | `/discovery/<key>` | Store/update address record (requires X-HMAC header) |
| DELETE | `/discovery/<key>` | Delete address record (requires X-HMAC header) |

Discovery records have a 6h TTL and are HMAC-authenticated. The key is a Base58-encoded hash derived from the pairing code.

## Usage

```bash
# Run TCP relay only (default port 41722)
./buddydrive-relay

# Specify port
./buddydrive-relay 41722

# With KV store (requires TIDB_CONNECTION_STRING)
export TIDB_CONNECTION_STRING="mysql://user:pass@host:4000/buddydrive"
./buddydrive-relay 41722 8080

# Optional: restrict KV API to EU IP ranges packaged in the container
export BUDDYDRIVE_KV_EU_ONLY=1
export BUDDYDRIVE_KV_EU_RANGES_FILE=/app/geo/eu_cidrs.txt

# Optional: restrict TCP relay clients to EU IP ranges too
export BUDDYDRIVE_RELAY_EU_ONLY=1
export BUDDYDRIVE_RELAY_EU_RANGES_FILE=/app/geo/eu_cidrs.txt
```

## Docker

```bash
# Build
docker build -t buddydrive-relay .

# Run (TCP relay only)
docker run -d -p 41722:41722 buddydrive-relay

# Run with KV store
docker run -d \
  -p 41722:41722 \
  -p 8080:8080 \
  -e TIDB_CONNECTION_STRING="mysql://user:pass@host:4000/buddydrive" \
  buddydrive-relay
```

## Protocol

```text
Client -> Server: <token>\n
Server -> Client: POW <nonce> <difficulty>\n
Client -> Server: POW <counter>\n
Server -> Client: WAIT\n
Server -> Client: OK\n
```

After `OK`, all data is relayed bidirectionally.

## Configuring BuddyDrive Clients

Both buddies need the same pairing code stored for their relationship.

For local testing, BuddyDrive has a built-in `local` relay mapping:

```bash
buddydrive config set relay-region local
buddydrive config set buddy-pairing-code <buddy-id> <pairing-code>
```

For hosted relay discovery, BuddyDrive expects an HTTP relay list service. Configure:

```bash
buddydrive config set relay-base-url https://example.com/relays
buddydrive config set relay-region eu
buddydrive config set buddy-pairing-code <buddy-id> <pairing-code>
```

BuddyDrive fetches `<relay-base-url>/<relay-region>` and expects JSON like:

```json
{
  "relays": [
    "/dns4/relay.example.com/tcp/41722"
  ],
  "ttl_seconds": 3600
}
```

## VPS Deployment

1. Get a VPS with a public IP
2. Install Docker
3. Deploy the relay
4. Optionally enable the KV store with a TiDB Cloud connection string

## Koyeb Deployment

The relay can be deployed on Koyeb's free tier with both TCP relay and KV store:

```bash
# Create app
koyeb apps create buddydrive

# Create secret for TiDB connection
koyeb secrets create tidb-connection-string --value 'mysql://user:pass@host:4000/buddydrive'

# Deploy from GitHub
koyeb services create relay \
  --app buddydrive \
  --git github.com/gokr/buddydrive \
  --git-branch master \
  --git-builder docker \
  --git-workdir relay \
  --ports 41722:tcp \
  --proxy-ports 41722:tcp \
  --env 'TIDB_CONNECTION_STRING={{secret.tidb-connection-string}}' \
  --regions fra
```

The TCP relay is available at the proxy host/port. The KV API is available via the service's HTTP route.

## EU-only KV Access

If you want KV API access or TCP relay access limited to EU IP ranges, place a generated `geo/eu_cidrs.txt` in the relay directory before building the Docker image.

For local generation outside Docker, run:

```bash
./tools/fetch_eu_cidrs.sh geo
```

This is intentionally manual so Docker builds do not depend on network access and do not refresh the geo snapshot on every build.

Free sources do exist. The current packaged path uses IPdeny's redistributable country zone files. The CSV converter in `tools/build_eu_cidrs.nim` is still available if you prefer a CSV source such as MaxMind GeoLite2 Country CSV.
