#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-grid-tap-fallback.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
export FAKE_UI_STATE=$test_dir/ui-state
export FAKE_ADB_LOG=$test_dir/adb.log

FAKE_ROOT_GRID_NO_FOCUS=yes FAKE_ROOT_GRID_TAP_FALLBACK=yes \
  "$root/scripts/mantis-tool.sh" --adb "$root/tests/fixtures/adb" \
    --serial test-host:5555 verify-settings > "$test_dir/out" 2> "$test_dir/err" || {
      printf 'FAIL: Settings did not use verified visible tiles: %s\n' "$(cat "$test_dir/err")" >&2
      exit 1
    }
grep -Fqx 'VERIFY_SETTINGS=PASS' "$test_dir/out" || {
  printf '%s\n' 'FAIL: Settings verification did not pass through tile fallback' >&2
  exit 1
}
for tap in '150 250' '350 350' '350 250'; do
  grep -Fq "shell input tap $tap" "$FAKE_ADB_LOG" || {
    printf 'FAIL: expected Settings tile was not tapped: %s\n' "$tap" >&2
    exit 1
  }
done
grep -Fq 'Settings grid navigation=verified-tap' "$test_dir/err" || {
  printf '%s\n' 'FAIL: tile fallback was not reported' >&2
  exit 1
}
printf '%s\n' 'SETTINGS_ROOT_TAP_FALLBACK=PASS'
