---
title: Security
---

## Your Security Matters

BuddyDrive is designed around a simple principle: you should understand exactly what is protected today, and what still depends on trusting your buddy.

## What Exists Today

BuddyDrive currently has two security layers that are important to understand:

| Component | Algorithm | Purpose |
|-----------|-----------|---------|
| Direct peer transport | libp2p Noise | Encrypt direct libp2p connections |
| Recovery config backup | libsodium `crypto_secretbox` | Encrypt config synced to relay |
| Pairing code | Shared secret | Match buddies, derive discovery keys, HMAC-authenticate relay records, and relay fallback sessions |
| Recovery phrase | 12-word mnemonic | Re-derive recovery metadata on a new machine |

## Recovery Phrase And Master Key

When you run `buddydrive setup-recovery`:

1. BuddyDrive generates a 12-word recovery phrase
2. It derives a master key from that phrase
3. It stores recovery metadata in `config.toml`
4. It encrypts your serialized config before syncing it to the relay

When you later run `buddydrive recover`, BuddyDrive uses the same 12 words to derive the same recovery material, fetches the encrypted config from the relay, decrypts it locally, and writes the restored config.

## Pairing And Direct Connections

The pairing code is a shared secret between buddies:

- You share it out-of-band with someone you trust
- Both sides store it for that buddy relationship
- Relay fallback uses it to match the two peers
- Direct libp2p connections use Noise transport encryption once connected

## Current Scope And Limits

This is the part that matters most when comparing the docs to the current codebase:

- Direct libp2p transport is encrypted by Noise
- Recovery config blobs synced to the relay are encrypted with the recovery master key
- Restore works by recovering config first and then letting normal sync recreate missing files
- Append-only protects existing local files from remote overwrite

Current limitation: application-level encryption for synced folder contents is not wired into the active sync path yet. Pair only with buddies you trust to hold your files.

## What Your Buddy Can See Today

Your buddy can see:

- The folders and files you sync with them
- File contents they receive through normal sync
- Total storage use and sync timing

Your buddy cannot see:

- The encrypted recovery config stored in the relay without your recovery phrase
- Your other buddies' configuration unless you share it with them

## Threat Model

### What We Protect Against

**Network interception on direct libp2p connections**: Noise protects direct peer transport.

**Relay compromise for config backup**: the relay stores an encrypted config blob; without the recovery phrase-derived master key it should not be readable.

**Lost machine**: recovery lets you rebuild config on a replacement device and then resync missing files.

### What We Do Not Protect Against

**Untrusted buddies**: if you pair with someone you do not trust, they can receive your synced files.

**Your machine compromised**: malware on your machine can read files before or during sync.

**Denial of service**: an attacker can still prevent peers from connecting.

## Secure Pairing Guidelines

Only pair with people you trust:

1. Share codes verbally or in person when possible
2. Verify identity through a second channel
3. Use unique codes for each buddy relationship
4. Check buddy IDs on both machines

## Security Checklist

- [ ] Pair only with trusted buddies
- [ ] Verify buddy ID after pairing
- [ ] Write down the 12-word recovery phrase and store it offline
- [ ] Keep your system updated
- [ ] Use strong local passwords
- [ ] Consider full-disk encryption on your machine
- [ ] Regularly check sync activity

## Bottom Line

BuddyDrive already protects direct libp2p transport and encrypts relay-backed recovery config with your master key. Recovery and restore are now part of the product, but synced folder contents should still be treated as visible to the buddy who stores them in the current implementation.
