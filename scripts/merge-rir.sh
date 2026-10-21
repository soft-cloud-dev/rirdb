#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
out="${1:-dist}"
mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
urls=(
  "apnic|https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-extended-latest"
  "arin|https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest"
  "lacnic|https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest"
  "afrinic|https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-extended-latest"
  "ripencc|https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest"
)
for entry in "${urls[@]}"; do
  rir="${entry%%|*}"
  url="${entry#*|}"
  curl --fail --location --silent --show-error --retry 5 --retry-delay 3 --connect-timeout 20 --max-time 300 "$url" -o "$tmp/$rir"
  awk -F '|' -v rir="$rir" '
    $1 == rir && ($3 == "ipv4" || $3 == "ipv6" || $3 == "asn") && NF >= 7 { count++ }
    END { if (count < 100) exit 1 }
  ' "$tmp/$rir" || { echo "Invalid or incomplete dataset: $rir" >&2; exit 1; }
done
merged="$out/delegated-rir-extended.txt"
{
  printf '# registry|cc|type|start|value|date|status|opaque-id\n'
  for entry in "${urls[@]}"; do
    rir="${entry%%|*}"
    awk -F '|' -v rir="$rir" '$1 == rir && ($3 == "ipv4" || $3 == "ipv6" || $3 == "asn") && NF >= 7' "$tmp/$rir"
  done
} > "$merged"
gzip -n -9 -c "$merged" > "$merged.gz"
sha256sum "$merged" "$merged.gz" > "$out/SHA256SUMS"
awk -F '|' '$3 == "ipv4" {v4++} $3 == "ipv6" {v6++} $3 == "asn" {asn++} END {printf "ipv4=%d\nipv6=%d\nasn=%d\n",v4,v6,asn}' "$merged" > "$out/counts.txt"
