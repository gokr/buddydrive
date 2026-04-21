import std/[strutils, times]
import ../types

proc parseClockMinutes*(value: string): int =
  let parts = value.strip().split(":")
  if parts.len != 2:
    return -1

  try:
    let hour = parseInt(parts[0])
    let minute = parseInt(parts[1])
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
      return -1
    hour * 60 + minute
  except ValueError:
    -1

proc syncTimeDescription*(syncTime: string): string =
  if syncTime.len > 0:
    syncTime
  else:
    "always"

proc isWithinSyncTime*(syncTime: string, currentTime: DateTime = now(), toleranceMinutes = 15): bool =
  if syncTime.len == 0:
    return true

  let targetMinute = parseClockMinutes(syncTime)
  if targetMinute < 0:
    return true

  let currentMinute = currentTime.hour * 60 + currentTime.minute
  let diff = abs(currentMinute - targetMinute)
  let wrappedDiff = min(diff, (24 * 60) - diff)
  wrappedDiff <= toleranceMinutes

proc shouldAttemptBuddySync*(buddy: BuddyInfo, currentTime: DateTime = now(), toleranceMinutes = 15): bool =
  isWithinSyncTime(buddy.syncTime, currentTime, toleranceMinutes)

proc shouldInitiateBuddySync*(buddy: BuddyInfo, currentTime: DateTime = now(), toleranceMinutes = 15): bool =
  shouldAttemptBuddySync(buddy, currentTime, toleranceMinutes)

proc shouldSyncRemoteFile*(folder: FolderConfig, remote: FileInfo, localFound: bool, local: FileInfo = default(FileInfo)): bool =
  if not localFound:
    return true
  if folder.appendOnly:
    return false
  if remote.mtime != local.mtime or remote.size != local.size:
    return true
  if remote.hash != local.hash:
    return true
  if remote.mode != local.mode or remote.symlinkTarget != local.symlinkTarget:
    return true
  false
