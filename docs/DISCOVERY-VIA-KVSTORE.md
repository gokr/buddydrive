# Discovery via KV-store

Replace DHT-based buddy discovery with a simpler KV-store-based approach. The DHT is slow, unreliable, and complex. BuddyDrive already operates a relay with a KV-store for recovery — extending it for discovery eliminates the DHT dependency and gives faster, more reliable lookups.

---

## Current State

- `discovery.nim` uses `addProvider`/`getProviders` on the libp2p Kademlia DHT
- DHT lookups can take minutes, require bootstrap nodes, and fail on restrictive networks
- Provider records expire after ~30 min, requiring frequent re-announcement
- The relay KV-store already exists at `/kv/<pubkey>` for encrypted config recovery
- UPnP remains useful for obtaining a public address, independent of discovery

## New Design

### Record Structure

Published to `/discovery/<derived-key>`:

```json
{
  "peerId": "16Uiu2HA...",
  "addresses": ["/ip4/1.2.3.4/tcp/41721", "/ip4/10.0.0.1/tcp/41721"],
  "relayRegion": "eu"
}
```

- **peerId** — libp2p Peer ID for direct dial
- **addresses** — all advertised multiaddresses (public + private; consumer decides which to use)
- **relayRegion** — optional; if present, the buddy can also be reached via relay fallback in this region
- **timestamp** — set by the server on PUT, not by the client
- **TTL** — set by the server (6h), not by the client

### Key Derivation

The lookup key is derived from the pairing code so that only paired buddies can find each other:

```
derived_key = base58(blake2b-256(pairing_code + "/discovery"))
auth_key    = blake2b-256(pairing_code + "/auth")
```

- `derived_key` — the KV-store path component (`/discovery/<derived_key>`)
- `auth_key` — used as the HMAC key for PUT/DELETE authentication

Each pairing code produces a unique key. Alice publishes under two keys if she has two buddies (one per pairing code). Bob looks up the key derived from his pairing code with Alice.

### Publishing Flow

1. On daemon startup, for each configured buddy:
   - Derive `discovery_key` from `buddy.pairingCode`
   - Build the address record (peer ID, advertised addresses, relay region if set)
   - PUT to `/discovery/<discovery_key>` with HMAC
   - Cache addresses in `state.db`
2. Re-publish every 4h (well within 6h TTL)
3. On graceful shutdown, optionally DELETE the record (best-effort; TTL handles crashes)
4. If KV-store is temporarily unavailable, retry on next cycle; cached addresses in `state.db` allow connections anyway

### Lookup Flow

1. On sync window start (or daemon start if no window configured), for each buddy not yet connected:
   - Derive `discovery_key` from `buddy.pairingCode`
   - GET `/discovery/<discovery_key>`
   - If found, extract peer ID + addresses and attempt direct connection
   - If address record includes `relayRegion`, fall back to relay if direct connection fails
2. If not found, poll every 10 minutes until the sync window closes or buddy is found
3. On successful connection, stop polling that buddy
4. If connection drops, re-lookup on next discovery cycle

### Graceful Degradation

- Cache the last-known buddy addresses in `state.db` (table: `cached_buddy_addrs`)
- On startup, try cached addresses immediately before waiting for a KV-store lookup
- This handles temporary KV-store outages and speeds up reconnection after restarts

---

## Security

### Current KV-store Problem

The `/kv/` API is unauthenticated — anyone can read, write, or delete any key. For recovery this is acceptable because the config blob is encrypted. For discovery it is not:

- **Spoofing** — attacker publishes a fake address under a buddy's key, intercepts the connection
- **Deletion** — attacker deletes your record, making you undiscoverable
- **Enumeration** — if keys are predictable (e.g., buddy UUIDs), anyone can scan them

### Solution: HMAC Authentication

The pairing code is a shared secret between two buddies. Derive an HMAC key from it:

```
PUT /discovery/<derived_key>
    Header: X-HMAC: <hex(hmac_sha256(auth_key, record_bytes))>

DELETE /discovery/<derived_key>
    Header: X-HMAC: <hex(hmac_sha256(auth_key, ""))>
```

The server:
1. On PUT: looks up `hash(pairing_code + "/auth")` stored during the first PUT for that key, verifies HMAC matches. If no stored auth hash exists, stores it and accepts the PUT.
2. On DELETE: verifies HMAC against stored auth hash.
3. On GET: no authentication needed — the derived key is unguessable without the pairing code.

**Key rotation**: if a pairing code changes (re-pairing), the derived key changes, and the new PUT stores a new auth hash. The old record becomes orphaned and expires via TTL.

**Server never sees raw pairing codes** — it only stores `hash(pairing_code + "/auth")` for HMAC validation.

### Privacy

- Discovery keys are hashes of pairing codes — unguessable without knowing the code
- Addresses are not publicly enumerable (unlike DHT where anyone can query a namespace)
- GET is open but requires knowing the derived key, which only paired buddies have

---

## API Changes

### New Endpoint: `/discovery/<key>`

```
GET  /discovery/<key>                        — returns record JSON, or 404
PUT  /discovery/<key>  X-HMAC: <hex>          — create/update record, server sets timestamp
DELETE /discovery/<key>  X-HMAC: <hex>        — delete record
```

### Existing Endpoint: `/kv/<pubkey>` (unchanged)

```
GET  /kv/<pubkey>    — encrypted config blob for recovery
PUT  /kv/<pubkey>    — encrypted config blob for recovery
DELETE /kv/<pubkey>  — encrypted config blob for recovery
```

Recovery keys are Base58-encoded public keys. Discovery keys are Base58-encoded hashes. The path prefix (`/kv/` vs `/discovery/`) makes them unambiguous.

### Server-side TTL

- Discovery records: TTL = 6h (configurable on server side)
- KV-store records: no TTL (recovery config should persist)
- Server sets `timestamp` field on every PUT to current server time
- Expired records are cleaned up lazily on read or via a periodic sweep

---

## Implementation Plan

### Phase 1: Relay server changes

Files: `relay/src/relay.nim`, `relay/src/kvstore.nim`, `relay/src/kvstore_api.nim`

1. Add `/discovery/` route handler (GET/PUT/DELETE)
2. Add `discovery_store` table in KV-store (key, record_json, auth_hash, timestamp)
3. HMAC validation on PUT/DELETE:
   - On first PUT for a key: store the `X-HMAC` header value as `auth_hash`, accept the record
   - On subsequent PUT/DELETE: verify `X-HMAC` matches stored `auth_hash`; reject with 401 if mismatch
4. Server sets `timestamp` on every PUT
5. TTL enforcement: records older than 6h return 404 on GET; periodic cleanup
6. Add `/discovery/` without key → 400, unknown path → 404

### Phase 2: Client-side discovery

Files: `src/buddydrive/p2p/discovery.nim`, `src/buddydrive/p2p/node.nim`, `src/buddydrive/daemon.nim`

1. Rewrite `discovery.nim`:
   - Remove DHT imports and `addProvider`/`getProviders` calls
   - Add `publishBuddy(buddyId, pairingCode, peerId, addresses, relayRegion)` — derives key, builds record, PUTs with HMAC
   - Add `findBuddy(buddyId, pairingCode)` — derives key, GETs record, returns (peerId, addresses, relayRegion)
   - Add `unpublishBuddy(buddyId, pairingCode)` — derives key, DELETEs with HMAC
   - Keep `publishBuddyLoop` — re-publish every 4h instead of 30min
2. Simplify `node.nim`:
   - Remove `dhtClient`/`bootstrapPeers` params from `start()`
   - Remove `bootstrapDht` proc
   - Remove KadDHT mount from switch
   - Keep peer ID, addresses, switch — still needed for direct connections
3. Update `daemon.nim`:
   - On startup: publish address records for each buddy, then lookup buddies
   - Discovery loop: poll every 10 min for unconnected buddies during sync window
   - On shutdown: best-effort unpublish
   - Use `state.db` cache for last-known addresses

### Phase 3: Daemon integration

Files: `src/buddydrive/daemon.nim`, `src/buddydrive/control.nim`

1. Add `cached_buddy_addrs` table to `state.db` (buddy_uuid, peer_id, addresses_json, last_seen, relay_region)
2. On buddy lookup: check cache first, then KV-store, update cache on success
3. On startup: try cached addresses immediately for faster reconnection
4. Control API: add discovery status to `GET /status` response

### Phase 4: Remove DHT

Files: `src/buddydrive/p2p/discovery.nim`, `src/buddydrive/p2p/node.nim`, `buddydrive.nimble`

1. Remove all KadDHT imports and DHT-related code from `node.nim` and `discovery.nim`
2. Remove `bootstrapDht`, `dhtClient`, `bootstrapPeers`, `updatePeers`
3. Remove DHT-related test infrastructure (local DHT server in tests)
4. Update `buddydrive.nimble` if any DHT-only dependencies can be dropped
5. Update AGENTS.md, docs/PLAN.md, README.md

### Phase 5: Tests

Files: `tests/unit/`, `tests/integration/`

1. Unit test: key derivation (pairing code → discovery key + auth key)
2. Unit test: HMAC generation and validation
3. Unit test: record serialization/deserialization
4. Integration test: publish + lookup against relay `/discovery/` endpoint
5. Integration test: TTL expiry (set short TTL, wait, verify 404)
6. Integration test: HMAC rejection (PUT with wrong HMAC → 401)
7. Update `test_peer_discovery.nim` (remove local DHT server test, test against relay)
8. Update `test_peer_discovery_public.nim` (remove entirely or repurpose)

---

## Migration Notes

- Existing `config.toml` files still work — `pairingCode` is already stored per buddy
- No config format changes needed
- The `relayBaseUrl` config field already points at the relay; discovery just uses a different path on the same host
- BuddyDrive instances on old versions will continue using DHT until upgraded; they won't interfere with KV-store discovery
