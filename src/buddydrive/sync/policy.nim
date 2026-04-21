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

proc syncTimeDescription*(buddy: BuddyInfo): string =
  if buddy.syncTime.len > 0:
    buddy.syncTime
  else:
    "always"

proc hasSyncWindow*(config: AppConfig): bool =
  config.syncWindowStart.len > 0 and config.syncWindowEnd.len > 0

proc syncWindowDescription*(config: AppConfig): string =
  if hasSyncWindow(config):
    config.syncWindowStart & "-" & config.syncWindowEnd
  else:
    "always"

proc isWithinSyncWindow*(config: AppConfig, currentTime: DateTime = now()): bool =
  if not hasSyncWindow(config):
    return true

  let startMinute = parseClockMinutes(config.syncWindowStart)
  let endMinute = parseClockMinutes(config.syncWindowEnd)
  if startMinute < 0 or endMinute < 0:
    return true

  let currentMinute = currentTime.hour * 60 + currentTime.minute
  if startMinute == endMinute:
    return true
  if startMinute < endMinute:
    currentMinute >= startMinute and currentMinute < endMinute
  else:
    currentMinute >= startMinute or currentMinute < endMinute

proc shouldInitiateBuddySync*(buddy: BuddyInfo, currentTime: DateTime = now(), toleranceMinutes = 15): bool =
  if buddy.syncTime.len == 0:
    return true

  let scheduledMinute = parseClockMinutes(buddy.syncTime)
  if scheduledMinute < 0:
    return true

  let currentMinute = currentTime.hour * 60 + currentTime.minute
  var diff = abs(currentMinute - scheduledMinute)
  diff = min(diff, 24 * 60 - diff)
  diff <= toleranceMinutes

proc shouldSyncRemoteFile*(folder: FolderConfig, remote: FileInfo, localFound: bool, local: FileInfo = default(FileInfo)): bool =
  if not localFound:
    return true
  if folder.appendOnly:
    return false
  remote.mtime > local.mtime or remote.size != local.size
