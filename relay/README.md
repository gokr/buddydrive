# BuddyDrive Relay

A simple TCP relay server for BuddyDrive P2P sync when direct connections aren't possible.

## How It Works

1. Client connects and sends a token (newline-terminated)
2. Server validates token against whitelist
3. If valid and no peer waiting, client waits
4. When matching peer connects, both receive "OK" and bidirectional relay begins
5. Either side disconnects → relay ends

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

```
Client -> Server: <token>\n
Server -> Client: OK\n           (when paired)
Server -> Client: WAIT\n         (waiting for peer)
Server -> Client: (disconnect)   (invalid token)

After OK, all data is relayed bidirectionally.
```

## VPS Deployment

1. Get a VPS with public IP (Hetzner, DigitalOcean, Vultr ~$4-6/mo)
2. Install Docker
3. Deploy with your tokens
4. Configure BuddyDrive clients to use relay:

```bash
buddydrive config set relay.addr "/ip4/<vps-ip>/tcp/41722"
buddydrive config set relay.token "swift-eagle"
```
