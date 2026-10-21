#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

previous="${1:?previous merged file required}"
current="${2:?current merged file required}"
out="${3:-dist}"
previous_label="${4:-previous}"
current_label="${5:-current}"

mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

grep -v '^#' "$previous" | sort -u > "$tmp/previous"
grep -v '^#' "$current" | sort -u > "$tmp/current"

changes="$out/changes.txt"

{
  printf '# previous=%s\n' "$previous_label"
  printf '# current=%s\n' "$current_label"
  printf '# format=operation|registry|cc|type|start|value|date|status|opaque-id\n'
  comm -23 "$tmp/previous" "$tmp/current" | sed 's/^/-|/'
  comm -13 "$tmp/previous" "$tmp/current" | sed 's/^/+|/'
} > "$changes"

gzip -n -9 -c "$changes" > "$changes.gz"

awk -F '|' '
  $1 == "+" { added++; added_type[$4]++ }
  $1 == "-" { removed++; removed_type[$4]++ }
  END {
    printf "added=%d\n", added
    printf "removed=%d\n", removed
    printf "added_ipv4=%d\n", added_type["ipv4"]
    printf "removed_ipv4=%d\n", removed_type["ipv4"]
    printf "added_ipv6=%d\n", added_type["ipv6"]
    printf "removed_ipv6=%d\n", removed_type["ipv6"]
    printf "added_asn=%d\n", added_type["asn"]
    printf "removed_asn=%d\n", removed_type["asn"]
  }
' "$changes" > "$out/changes-counts.txt"
