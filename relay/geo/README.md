Place a generated `eu_cidrs.txt` file in this directory to enable packaged EU-only KV access.

Docker builds do not fetch this automatically anymore. Refresh it manually when you want to update the snapshot, then rebuild the image.

Expected format:
- one CIDR per line
- IPv4 and IPv6 supported
- blank lines and `#` comments ignored

Example:

```text
2.16.0.0/13
2001:67c::/32
```

The easiest free source is IPdeny's redistributable country zone files. To generate or refresh the packaged allowlist locally:

```bash
./tools/fetch_eu_cidrs.sh geo
```

This writes:
- `geo/eu_cidrs.txt`
- `geo/IPDENY-Copyrights.txt`

Recommended workflow:

```bash
./tools/fetch_eu_cidrs.sh geo
docker build -t buddydrive-relay .
```

Alternative: if you prefer CSV-based generation from MaxMind GeoLite2 Country CSV files, you can use:

```bash
nim r tools/build_eu_cidrs.nim -- \
  /path/to/GeoLite2-Country-Locations-en.csv \
  /path/to/GeoLite2-Country-Blocks-IPv4.csv \
  /path/to/GeoLite2-Country-Blocks-IPv6.csv \
  geo/eu_cidrs.txt
```
