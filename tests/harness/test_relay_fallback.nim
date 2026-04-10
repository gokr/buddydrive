import chronos
import ../../src/buddydrive/types
import ../../src/buddydrive/p2p/rawrelay
import ../../src/buddydrive/p2p/pairing

proc makeConfig(
    selfId: string,
    selfName: string,
    otherId: string,
    otherName: string,
    relayToken: string,
): AppConfig =
  result = newAppConfig(newBuddyId(selfId, selfName))
  result.relayRegion = "local"

  var buddy: BuddyInfo
  buddy.id = newBuddyId(otherId, otherName)
  buddy.relayToken = relayToken
  result.buddies = @[buddy]

proc connectAndPair(config: AppConfig): Future[string] {.async.} =
  var relayListCache = initRelayListCache()
  let relayConn = await connectViaRegionalRelay(
    relayListCache,
    config.relayBaseUrl,
    config.relayRegion,
    config.buddies[0].relayToken
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

  let f1 = connectAndPair(cfg1)
  let f2 = connectAndPair(cfg2)

  let remote1 = await f1
  let remote2 = await f2

  doAssert remote1 == "buddy-two"
  doAssert remote2 == "buddy-one"
  echo "relay fallback pairing ok"

waitFor main()
