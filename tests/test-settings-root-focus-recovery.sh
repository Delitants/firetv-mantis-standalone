#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-grid-recovery.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
export FAKE_UI_STATE=$test_dir/ui-state
export FAKE_ADB_LOG=$test_dir/adb.log

# A stock grid that has not focused a tile yet, or retains another tile,
# must be moved to Network before deterministic Settings navigation starts.
for initial in unfocused equipment; do
  rm -f "$FAKE_UI_STATE" "$FAKE_ADB_LOG"
  marker=$test_dir/moved-$initial
  if FAKE_ROOT_GRID_BEFORE_MOVE=$initial FAKE_ROOT_GRID_MOVE_MARKER=$marker \
    "$root/scripts/mantis-tool.sh" --adb "$root/tests/fixtures/adb" \
      --serial test-host:5555 verify-settings > "$test_dir/out" 2> "$test_dir/err"; then
    :
  else
    printf 'FAIL: Settings did not recover from %s grid focus: %s\n' \
      "$initial" "$(cat "$test_dir/err")" >&2
    exit 1
  fi
  [ -e "$marker" ] || { printf 'FAIL: no D-pad focus recovery for %s\n' "$initial" >&2; exit 1; }
  grep -Fqx 'VERIFY_SETTINGS=PASS' "$test_dir/out" || {
    printf 'FAIL: Settings verification did not pass after %s focus recovery\n' "$initial" >&2
    exit 1
  }
done

printf '%s\n' 'SETTINGS_ROOT_FOCUS_RECOVERY=PASS'
