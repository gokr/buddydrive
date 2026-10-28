---
title: BuddyDrive
tagline: Backup your life, with a friend
---

## Hero Section

**Title:** BuddyDrive
**Subtitle:** Backup your life, with a friend.
**Description:** Peer-to-peer encrypted folder sync with relay-backed restore. Keep your documents, photos, and other important folders encrypted on a trusted buddy machine, then rebuild a lost machine with a 12-word recovery phrase and resync missing files.

**CTA Primary:** Get Started
**CTA Secondary:** Learn More

## Why BuddyDrive?

Your NAS can burn. Your external drive can fail. Ransomware can encrypt everything. And cloud backups cost money every month, storing your data on servers you do not control.

**BuddyDrive is different.** Pair with a friend, family member, or trusted colleague, keep an offsite copy on their machine, and use a recovery phrase to get your config back when a machine dies.

### Real Offsite Protection {icon=Offsite}

Fire, flood, theft, and dead disks are easier to survive when a buddy holds the other copy. Your backup lives somewhere you do not live.

### Recovery Phrase {icon=12W}

Set up a 12-word recovery phrase once. BuddyDrive derives a master key from it and syncs an encrypted copy of your config to the relay, so a replacement machine can rebuild itself.

### Encrypted Backup {icon=Lock}

Filenames and file contents are encrypted with XSalsa20-Poly1305 before they are stored with your buddy. Blob names are hashes of the encrypted paths, so even the directory listing says nothing.

### Owner Authoritative {icon=Owner}

Only the machine that owns a folder moves or deletes its files. A buddy stores sealed chunks it never opens, serves them back on request, and cannot push files into your folders.

### Restore Missing Files {icon=Sync}

After `recover`, a takeover session pulls back files your machine has no record of. Moves are detected by content hash, so a rename does not re-upload.

### Open Source {icon=OSS}

No accounts, no subscription, no black box between you and your data. Audit the code, or change it.

## How It Works

1. **Install BuddyDrive** on both machines
2. **Pair devices** using a simple code
3. **Select folders** to sync and optionally enable recovery
4. **Restore when needed** - recover config with 12 words, then let sync recreate missing files

## The Problem With Cloud Backups

| Cloud Backup | BuddyDrive |
|-------------|------------|
| $5-20/month forever | Free, forever |
| Data stored on company servers | Data stored with your buddy |
| Trust the provider | Trust someone you know |
| Account required | No account required |
| Recover through vendor | Recover with your own 12 words |

## Who Is This For?

- **Families** - offsite backup with people you already trust
- **Friends** - mutual backup without cloud costs
- **Small teams** - simple shared folder sync and restore
- **Privacy-conscious users** - local control over recovery secrets
- **Budget-conscious users** - free alternative to another subscription

## Get Started

BuddyDrive builds from source on Linux and macOS. Install it on two machines, pair them with one shared code, set up recovery, and start backing up.

[Download Now](/docs) or read the [full feature list](/features).
