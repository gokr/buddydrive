import std/[unittest, net, os]
import ../../../relay/src/geoip_ranges
import ../../../relay/src/geoip_policy

suite "geoip range allowlist":
  test "matches ipv4 cidr ranges":
    var allowlist: GeoRangeAllowlist
    allowlist.addCidr("2.16.0.0/13")
    allowlist.sortAndCompact()

    check allowlist.contains(parseIpAddress("2.16.5.10"))
    check not allowlist.contains(parseIpAddress("8.8.8.8"))

  test "matches ipv6 cidr ranges":
    var allowlist: GeoRangeAllowlist
    allowlist.addCidr("2001:67c::/32")
    allowlist.sortAndCompact()

    check allowlist.contains(parseIpAddress("2001:67c:2e8:22::c100:68b"))
    check not allowlist.contains(parseIpAddress("2606:4700:4700::1111"))

  test "loads file and ignores comments":
    let path = getTempDir() / "buddydrive_geo_allowlist_test.txt"
    writeFile(path, "# comment\n\n2.16.0.0/13\n")
    defer:
      if fileExists(path):
        removeFile(path)

    let allowlist = loadGeoRangeAllowlist(path)
    check allowlist.contains(parseIpAddress("2.17.1.1"))
    check not allowlist.contains(parseIpAddress("1.1.1.1"))

  test "shared geo policy allows EU ranges":
    let path = getTempDir() / "buddydrive_geo_policy_test.txt"
    writeFile(path, "2.16.0.0/13\n2001:67c::/32\n")
    defer:
      if fileExists(path):
        removeFile(path)

    let status = configureEuGeoPolicy(true, path, "relay")
    check status.active
    check status.cidrCount == 2
    check allowEuGeoAccess("2.17.1.1", status.active)
    check allowEuGeoAccess("2001:67c:2e8:22::c100:68b", status.active)
    check allowEuGeoAccess("127.0.0.1", status.active)
    check not allowEuGeoAccess("8.8.8.8", status.active)
