#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-geo}"
mkdir -p "$out_dir"

eu_codes=(at be bg hr cy cz dk ee fi fr de gr hu ie it lv lt lu mt nl pl pt ro sk si es se)

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

for code in "${eu_codes[@]}"; do
  curl -fsSL "https://www.ipdeny.com/ipblocks/data/aggregated/${code}-aggregated.zone" >> "$tmp_file"
  printf '\n' >> "$tmp_file"
  curl -fsSL "https://www.ipdeny.com/ipv6/ipaddresses/aggregated/${code}-aggregated.zone" >> "$tmp_file"
  printf '\n' >> "$tmp_file"
done

grep -v '^[[:space:]]*$' "$tmp_file" | sort -u > "$out_dir/eu_cidrs.txt"
curl -fsSL "https://www.ipdeny.com/ipblocks/data/countries/Copyrights.txt" -o "$out_dir/IPDENY-Copyrights.txt"
