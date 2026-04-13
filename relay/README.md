# BuddyDrive Relay

A TCP relay server and KV store for BuddyDrive. The relay enables NAT traversal when direct connections are not possible. The KV store (optional, requires TiDB Cloud) stores encrypted config blobs for recovery.

## How It Works

### TCP Relay

1. Client connects and sends a token (the pairing code) followed by `\n`
2. If no peer with the same token is waiting, the client waits
3. When a matching peer connects, both receive `OK`
4. All further bytes are relayed bidirectionally until one side disconnects

On the BuddyDrive side, the buddy `pairing_code` is reused as this relay token. Any token is accepted — there is no whitelist.

### KV Store (optional)

When built with `-d:withKvStore`, the relay also runs an HTTP API for storing encrypted config blobs. BuddyDrive uses this for recovery: the encrypted config is uploaded with the public key (Base58) as the lookup key.

**KV API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/kv/<pubkey>` | Fetch encrypted config |
| PUT | `/kv/<pubkey>` | Store encrypted config |
| DELETE | `/kv/<pubkey>` | Delete config |
| GET | `/health` | Health check |
| GET | `/stats` | Config count |

## Usage

```bash
# Run TCP relay only (default port 41722)
./buddydrive-relay

# Specify port
./buddydrive-relay 41722

# With KV store (requires TIDB_CONNECTION_STRING)
export TIDB_CONNECTION_STRING="mysql://user:pass@host:4000/buddydrive"
./buddydrive-relay 41722 8080
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
