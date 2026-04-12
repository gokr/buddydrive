# BuddyDrive Relay

A simple TCP relay server for BuddyDrive when direct connections are not possible.

## How It Works

1. Client connects and sends a token followed by `\n`
2. Server validates the token against the whitelist
3. If valid and no peer is waiting, the client waits
4. When a matching peer connects, both receive `OK`
5. All further bytes are relayed bidirectionally until one side disconnects

On the BuddyDrive side, the buddy `pairing_code` is reused as this relay token.

## Usage

```bash
# Set allowed tokens (comma-separated)
export BUDDYDRIVE_TOKENS="swift-eagle,brave-moose,calm-river"

# Run on default port 41722
./buddydrive-relay

# Or specify port
./buddydrive-relay 41722
```

## Docker

```bash
# Build
docker build -t buddydrive-relay .

# Run
docker run -d \
  -p 41722:41722 \
  -e BUDDYDRIVE_TOKENS="swift-eagle,brave-moose" \
  buddydrive-relay

# Or with docker-compose
docker-compose up -d
```

## Protocol

```text
Client -> Server: <token>\n
Server -> Client: WAIT\n
Server -> Client: OK\n
Server -> Client: (disconnect)   # invalid token
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
3. Deploy the relay with your allowed tokens
4. Optionally expose a small HTTP relay-list endpoint for your clients

## Koyeb Deployment

The relay can be deployed on Koyeb's free tier:

```bash
# Create app
koyeb apps create buddydrive

# Create secret for tokens
koyeb secrets create buddydrive-tokens --value 'token1,token2'

# Deploy from GitHub
koyeb services create relay \
  --app buddydrive \
  --git github.com/gokr/buddydrive \
  --git-branch master \
  --git-builder docker \
  --git-workdir relay \
  --ports 41722:tcp \
  --proxy-ports 41722:tcp \
  --env 'BUDDYDRIVE_TOKENS={{secret.buddydrive-tokens}}' \
  --regions fra
```

The relay will be available at the proxy host on the public port shown by Koyeb.
