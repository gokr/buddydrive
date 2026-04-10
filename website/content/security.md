---
title: Security
---

## Your Security Matters

BuddyDrive is designed around a simple principle: **your data should only be readable by you.**

This page explains exactly how we protect your files.

## Encryption Overview

BuddyDrive uses industry-standard cryptography:

| Component | Algorithm | Purpose |
|-----------|-----------|---------|
| Key Exchange | X25519 | Secure pairing |
| File Encryption | XSalsa20-Poly1305 | Encrypt file contents |
| Integrity | Blake2b | Detect tampering |
| Authentication | Poly1305 | Verify file authenticity |

All cryptography provided by **libsodium**, the same library used by Signal, WireGuard, and many security-focused applications.

## How Encryption Works

### Pairing

When you pair with a buddy:

1. Your machine generates a **keypair** (public + private key)
2. A **6-character code** is derived from your public key
3. You share this code with your buddy (in person, text, etc.)
4. Your buddy's machine generates their own keypair
5. Both machines exchange public keys securely
6. A **shared secret** is derived using X25519
7. This secret encrypts all future communication

The pairing code is only used once. After pairing, all communication uses cryptographic keys.

### File Encryption

Before a file leaves your machine:

1. Generate a random **symmetric key** for this file
2. Encrypt the file contents with XSalsa20-Poly1305
3. Encrypt the symmetric key with the shared secret
4. Calculate Blake2b hash for integrity
5. Send encrypted blob to your buddy

Your buddy receives:

- Encrypted file contents (unreadable)
- Encrypted file key (can't decrypt without their private key)
- Cryptographic hash (for integrity)

They cannot read your file. They can only store it.

### At Rest

Files stored on your buddy's machine:

- Encrypted contents
- Randomized filenames (not your original filename)
- No directory structure visible
- Timestamps obscured

Even with physical access to your buddy's storage, your files are protected.

## What Your Buddy Can See

Your buddy can see:

- That you have synced X files
- Total storage used
- When sync activity occurred

Your buddy **cannot** see:

- Your filenames
- Your folder structure
- Your file contents
- Any metadata

## Threat Model

### What We Protect Against

**Network interception**: All traffic is encrypted. An attacker on your WiFi or ISP cannot read your files.

**Physical access to buddy's machine**: Your buddy cannot read your files even with their own hardware.

**Compromised buddy device**: If your buddy's machine is hacked, your files remain encrypted.

**Replay attacks**: Each message has unique authentication. Old messages cannot be replayed.

### What We Don't Protect Against

**Your machine compromised**: If malware reads your files before encryption, BuddyDrive cannot help. Use standard security practices.

**Social engineering**: If you pair with an attacker, they can store your encrypted files. Only pair with people you trust.

**Denial of service**: An attacker could prevent sync but cannot read your data.

**Key logger**: If an attacker captures your pairing code and acts quickly, they could impersonate your buddy.

## Secure Pairing Guidelines

Only pair with people you trust:

1. **Share codes verbally** or in person when possible
2. **Verify identity** through a second channel
3. **Use unique codes** - each pairing gets its own code
4. **Check fingerprints** - both machines show buddy ID

## Audit and Transparency

BuddyDrive is 100% open source:

- All cryptography code is public
- No hidden backdoors
- No proprietary components
- Community-reviewed

You can verify exactly how your data is protected.

### Key Dependencies

| Library | Trust Level |
|---------|-------------|
| libsodium | Widely audited, used by Signal |
| libp2p | Developed by Protocol Labs |
| GTK4 | Official GNOME toolkit |

## Privacy

BuddyDrive collects **no data**:

- No telemetry
- No analytics
- No crash reports (unless you opt-in)
- No registration
- No accounts

We don't even have a server to collect data on.

## Responsible Disclosure

Found a security issue? Email: security@buddydrive.org

We will:

1. Acknowledge within 48 hours
2. Investigate and fix
3. Credit you (if desired)
4. Never sue for good-faith research

## Security Checklist

Before using BuddyDrive in production:

- [ ] Pair only with trusted buddies
- [ ] Verify buddy ID after pairing
- [ ] Keep your system updated
- [ ] Use strong local passwords
- [ ] Consider full-disk encryption on your machine
- [ ] Regularly check sync activity

## Compare to Alternatives

| Feature | BuddyDrive | Cloud Storage | NAS |
|---------|-----------|---------------|-----|
| End-to-end encrypted | Yes | Usually no | No |
| Zero knowledge | Yes | Varies | No |
| Offsite backup | Yes | Yes | No |
| Free | Yes | No | Yes (hardware) |
| No third party | Yes | No | Yes |
| Works behind NAT | Yes | Yes | Maybe |

---

**Bottom line**: Your files are encrypted before they leave your machine, during transfer, and at rest on your buddy's machine. Only you can decrypt them.
