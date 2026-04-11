import std/os
import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/p2p/rawrelay
import ../../src/buddydrive/p2p/pairing

proc strictIntegration(): bool =
  getEnv("BUDDYDRIVE_STRICT_INTEGRATION", "") == "1"

proc makeConfig(
    selfId: string,
    selfName: string,
    otherId: string,
    otherName: string,
    pairingCode: string,
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  result.relayRegion = "local"

  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  buddy.pairingCode = pairingCode
  result.buddies = @[buddy]

proc connectAndPair(config: AppConfig): Future[string] {.async.} =
  var relayListCache = initRelayListCache()
  let relayConn = await connectViaRegionalRelay(
    relayListCache,
    config.relayBaseUrl,
    config.relayRegion,
    config.buddies[0].pairingCode
  )
  let conn = relayConn.conn

  let bc = newBuddyConnection()
  bc.conn = conn

  let success = await bc.performHandshake(config)
  doAssert success
  let remoteName = bc.buddyName
  await bc.close()
  remoteName

proc main() {.async.} =
  let cfg1 = makeConfig(
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "swift-eagle"
  )
  let cfg2 = makeConfig(
    "22222222-2222-2222-2222-222222222222",
    "buddy-two",
    "11111111-1111-1111-1111-111111111111",
    "buddy-one",
    "swift-eagle"
  )

  let remote1 = try:
    let f1 = connectAndPair(cfg1)
    let f2 = connectAndPair(cfg2)
    let r1 = await f1
    let r2 = await f2
    doAssert r1 == "buddy-two"
    doAssert r2 == "buddy-one"
    r1
  except CatchableError as e:
    if strictIntegration():
      raise
    echo "relay fallback unavailable; skipping in non-strict mode: ", e.msg
    return

  doAssert remote1 == "buddy-two"
  echo "relay fallback pairing ok"

waitFor main()
