#!/bin/sh
set -eu

root=${1:-.}
[ -d "$root" ] || { printf 'scan root is not a directory: %s\n' "$root" >&2; exit 64; }

failed=no
scan_list=$(mktemp "${TMPDIR:-/tmp}/firetv-excluded-content.XXXXXX")
trap 'rm -f "$scan_list"' EXIT HUP INT TERM
reject() {
  printf 'excluded content: %s: %s\n' "$1" "$2" >&2
  failed=yes
}

find "$root" -type f ! -path '*/.git/*' -print > "$scan_list"
while IFS= read -r file; do
  case "$file" in
    *.apk|*.apks|*.img|*.bin|*.mbn|*.zip) reject "$file" 'binary artifact or partition image' ;;
  esac
  if [ "${file##*.}" = patch ]; then
    sed '/^-/d' "$file" | grep -I -E -q '(^|[^0-9])((10|127)\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)' && reject "$file" 'private or loopback IPv4 address'
  else
    grep -I -E -q '(^|[^0-9])((10|127)\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)' "$file" && reject "$file" 'private or loopback IPv4 address'
  fi
  grep -I -E -q -- '-----BEGIN( [A-Z0-9]+)? PRIVATE KEY-----' "$file" && reject "$file" 'PEM private key header'
  grep -I -E -q 'PrivateKey[[:space:]]*=' "$file" && reject "$file" 'WireGuard private key'
  grep -I -E -q 'rm[[:space:]]+-[A-Za-z]*r[A-Za-z]*f[A-Za-z]*[[:space:]]+/system([[:space:]/]|$)' "$file" && reject "$file" 'destructive system-partition command'
done < "$scan_list"

[ "$failed" = no ]
