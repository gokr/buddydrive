import std/[algorithm, os, parsecsv, sets, strutils]

const EuCountryCodes = [
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"
]

proc loadEuGeonames(locationsCsv: string): HashSet[string] =
  var csv: CsvParser
  open(csv, locationsCsv)
  defer: close(csv)

  readHeaderRow(csv)
  let geonameIdx = csv.headers.find("geoname_id")
  let countryIdx = csv.headers.find("country_iso_code")
  if geonameIdx < 0 or countryIdx < 0:
    raise newException(IOError, "locations csv missing required headers")

  let euCodes = EuCountryCodes.toHashSet()
  while readRow(csv):
    let geonameId = csv.row[geonameIdx].strip()
    let countryCode = csv.row[countryIdx].strip().toUpperAscii()
    if geonameId.len > 0 and countryCode in euCodes:
      result.incl(geonameId)

proc appendEuNetworks(blocksCsv: string, euGeonames: HashSet[string], output: var seq[string]) =
  var csv: CsvParser
  open(csv, blocksCsv)
  defer: close(csv)

  readHeaderRow(csv)
  let networkIdx = csv.headers.find("network")
  let geonameIdx = csv.headers.find("geoname_id")
  let registeredIdx = csv.headers.find("registered_country_geoname_id")
  let representedIdx = csv.headers.find("represented_country_geoname_id")
  if networkIdx < 0:
    raise newException(IOError, "blocks csv missing network header")

  while readRow(csv):
    let network = csv.row[networkIdx].strip()
    if network.len == 0:
      continue

    let geonameId = if geonameIdx >= 0: csv.row[geonameIdx].strip() else: ""
    let registeredId = if registeredIdx >= 0: csv.row[registeredIdx].strip() else: ""
    let representedId = if representedIdx >= 0: csv.row[representedIdx].strip() else: ""

    if geonameId in euGeonames or registeredId in euGeonames or representedId in euGeonames:
      output.add(network)

when isMainModule:
  if paramCount() != 4:
    quit("usage: build_eu_cidrs <locations.csv> <blocks-ipv4.csv> <blocks-ipv6.csv> <output.txt>")

  let locationsCsv = paramStr(1)
  let blocksIpv4Csv = paramStr(2)
  let blocksIpv6Csv = paramStr(3)
  let outputPath = paramStr(4)

  let euGeonames = loadEuGeonames(locationsCsv)
  var networks: seq[string] = @[]
  appendEuNetworks(blocksIpv4Csv, euGeonames, networks)
  appendEuNetworks(blocksIpv6Csv, euGeonames, networks)
  networks.sort(system.cmp[string])

  createDir(outputPath.parentDir())
  writeFile(outputPath, networks.join("\n") & "\n")
