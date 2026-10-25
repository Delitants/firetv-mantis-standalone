#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mantis-hud-focus.XXXXXX")
trap 'rm -r "$TEST_TMP"' EXIT HUP INT TERM
export FAKE_ADB_LOG="$TEST_TMP/adb.log"
export FAKE_UI_STATE="$TEST_TMP/ui-state"
export FAKE_HUD_LOSS_MARKER="$TEST_TMP/lost-focus"
export FAKE_HUD_LOSE_FOCUS_ONCE=1

if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" \
  --serial test-host:5555 verify-settings > "$TEST_TMP/out" 2> "$TEST_TMP/err"; then
  :
else
  printf '%s\n' 'FAIL: HUD focus loss was not recovered' >&2
  tail -n 12 "$TEST_TMP/err" >&2
  exit 1
fi

[ -e "$FAKE_HUD_LOSS_MARKER" ] || { printf '%s\n' 'FAIL: fixture did not lose HUD focus' >&2; exit 1; }
grep -Fqx 'VERIFY_SETTINGS=PASS' "$TEST_TMP/out" || { printf '%s\n' 'FAIL: Settings verification did not pass' >&2; exit 1; }
printf '%s\n' 'HUD_FOCUS_RETRY=PASS'
