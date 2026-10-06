import std/unittest
import std/times
import ../../../src/buddydrive/types
import ../../../src/buddydrive/sync/policy

suite "parseClockMinutes":
  test "valid HH:MM":
    check parseClockMinutes("01:30") == 90
    check parseClockMinutes("00:00") == 0
    check parseClockMinutes("23:59") == 23 * 60 + 59
    check parseClockMinutes("12:00") == 720

  test "invalid format returns -1":
    check parseClockMinutes("invalid") == -1
    check parseClockMinutes("25:00") == -1
    check parseClockMinutes("12:60") == -1
    check parseClockMinutes("") == -1

suite "syncTimeDescription":
  test "always when sync time empty":
    check syncTimeDescription("") == "always"

  test "shows time when set":
    check syncTimeDescription("03:00") == "03:00"

suite "isWithinSyncTime":
  test "always within when sync time empty":
    check isWithinSyncTime("")

  test "within 15 minute window around target":
    check isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 2, 45, 0, 0, local()))
    check isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 3, 15, 0, 0, local()))
    check not isWithinSyncTime("03:00", dateTime(2026, mApr, 10, 3, 16, 0, 0, local()))

  test "window wraps midnight":
    check isWithinSyncTime("00:05", dateTime(2026, mApr, 10, 23, 55, 0, 0, local()))
    check isWithinSyncTime("23:55", dateTime(2026, mApr, 11, 0, 5, 0, 0, local()))

  test "invalid sync time falls through to true":
    check isWithinSyncTime("bad")

suite "shouldAttemptBuddySync":
  test "empty sync time means always":
    var buddy: BuddyInfo
    check shouldAttemptBuddySync(buddy)

  test "buddy sync time uses scheduled window":
    var buddy: BuddyInfo
    buddy.syncTime = "03:00"
    check shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 3, 5, 0, 0, local()))
    check not shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 4, 0, 0, 0, local()))

suite "shouldAttemptBuddySync timing":
  test "always when sync time is empty":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = ""
    check shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 12, 0, 0, 0, local()))

  test "within tolerance around scheduled time":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = "03:00"
    check shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 2, 50, 0, 0, local()))
    check shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 3, 10, 0, 0, local()))
    check not shouldAttemptBuddySync(buddy, dateTime(2026, mApr, 10, 3, 30, 0, 0, local()))

  test "invalid sync time falls through to always":
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    buddy.syncTime = "bad"
    check shouldAttemptBuddySync(buddy)
