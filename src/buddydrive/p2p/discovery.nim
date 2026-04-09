import std/times
import results
import chronos
import libp2p
import libp2p/builders
import libp2p/switch
import libp2p/peerid
import libp2p/peerinfo
import libp2p/multiaddress
import node
import ../types

export results

type
  DiscoveryError* = object of CatchableError
  
  DiscoveryService* = ref object
    node*: BuddyNode
    started*: bool

const 
  BuddyDriveNamespace* = "/buddydrive"
  DefaultBootstrapNodes* = @[
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPF2Tf2xDjjBQGXBpZz4wJi0nWpc8QjwMgd",
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9PChmtgd5AX2dtzjZsmj6U3XL1YXG"
  ]

proc newDiscovery*(node: BuddyNode): DiscoveryService =
  result = DiscoveryService()
  result.node = node
  result.started = false

proc start*(discovery: DiscoveryService) {.async.} =
  if discovery.started:
    return
  
  discovery.started = true

proc stop*(discovery: DiscoveryService) {.async.} =
  discovery.started = false

proc announce*(discovery: DiscoveryService, buddyId: string) {.async.} =
  if not discovery.started:
    raise newException(DiscoveryError, "Discovery not started")
  
  discard

proc findBuddy*(discovery: DiscoveryService, buddyId: string): Future[seq[peerinfo.PeerInfo]] {.async.} =
  result = @[]

proc publishBuddy*(discovery: DiscoveryService, buddyId: string) {.async.} =
  await discovery.announce(buddyId)
