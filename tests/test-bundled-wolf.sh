#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
apk="$root/assets/WolfLauncher_0.1.9-Wolf.apk"
expected_hash=d03ed56bb5564aa5b3e668831484917616510b02db4dde6a813d49a352054d05

[ -f "$apk" ] || { printf 'missing bundled Wolf Launcher: %s\n' "$apk" >&2; exit 1; }
[ "$(wc -c < "$apk" | tr -d '[:space:]')" = 3272501 ] || { printf '%s\n' 'bundled Wolf Launcher size mismatch' >&2; exit 1; }
[ "$(shasum -a 256 "$apk" | awk '{print $1}')" = "$expected_hash" ] || { printf '%s\n' 'bundled Wolf Launcher hash mismatch' >&2; exit 1; }

fixture=$(mktemp -d "${TMPDIR:-/tmp}/wolf-publication-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
mkdir "$fixture/assets"
cp "$apk" "$fixture/assets/WolfLauncher_0.1.9-Wolf.apk"
sh "$root/tests/scan-excluded-content.sh" "$fixture"
printf x >> "$fixture/assets/WolfLauncher_0.1.9-Wolf.apk"
if sh "$root/tests/scan-excluded-content.sh" "$fixture"; then
  printf '%s\n' 'excluded-content scan accepted a modified Wolf Launcher APK' >&2
  exit 1
fi

printf '%s\n' 'PASS: bundled Wolf Launcher publication gate'
