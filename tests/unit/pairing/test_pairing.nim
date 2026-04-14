import std/unittest
import libp2p/stream/connection
import ../../../src/buddydrive/types
import ../../../src/buddydrive/p2p/pairing

suite "BuddyConnection state":
  test "newBuddyConnection starts in psNone":
    let bc = newBuddyConnection()
    check bc.state == psNone
    check bc.buddyId == ""
    check bc.buddyName == ""

  test "isConnected is false for psNone":
    let bc = newBuddyConnection()
    check not bc.isConnected()

  test "isConnected is false when conn is nil regardless of state":
    let bc = newBuddyConnection()
    bc.state = psReady
    check not bc.isConnected()

  test "isConnected is false for psError":
    let bc = newBuddyConnection()
    bc.state = psError
    check not bc.isConnected()

  test "isConnected is false for psHandshake":
    let bc = newBuddyConnection()
    bc.state = psHandshake
    check not bc.isConnected()

suite "verifyBuddy":
  test "returns true when buddy UUID matches config":
    let bc = newBuddyConnection()
    bc.buddyId = "buddy-1"
    var config = newAppConfig(newBuddyId("me", "myself"))
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    config.buddies = @[buddy]
    check bc.verifyBuddy(config)
    check bc.buddyName == "Alice"

  test "returns false when buddy UUID not in config":
    let bc = newBuddyConnection()
    bc.buddyId = "unknown-buddy"
    var config = newAppConfig(newBuddyId("me", "myself"))
    var buddy: BuddyInfo
    buddy.id = newBuddyId("buddy-1", "Alice")
    config.buddies = @[buddy]
    check not bc.verifyBuddy(config)

  test "returns false with empty buddies list":
    let bc = newBuddyConnection()
    bc.buddyId = "anyone"
    let config = newAppConfig(newBuddyId("me", "myself"))
    check not bc.verifyBuddy(config)

  test "matches against multiple buddies":
    let bc = newBuddyConnection()
    bc.buddyId = "buddy-2"
    var config = newAppConfig(newBuddyId("me", "myself"))
    var b1: BuddyInfo
    b1.id = newBuddyId("buddy-1", "Alice")
    var b2: BuddyInfo
    b2.id = newBuddyId("buddy-2", "Bob")
    config.buddies = @[b1, b2]
    check bc.verifyBuddy(config)
    check bc.buddyName == "Bob"
