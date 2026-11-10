#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-settings-main.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
export FAKE_UI_STATE=$test_dir/ui-state
export FAKE_ADB_LOG=$test_dir/adb.log

# Simulate a foreground but unpopulated MainSettingsActivity when launched
# without ACTION_MAIN. The optional Settings tile supplies ACTION_MAIN.
if FAKE_ROOT_REQUIRES_MAIN_ACTION=1 \
  "$root/scripts/mantis-tool.sh" --adb "$root/tests/fixtures/adb" \
    --serial test-host:5555 verify-settings > "$test_dir/out" 2> "$test_dir/err"; then
  :
else
  printf 'FAIL: Settings verification could not open the rendered root: %s\n' \
    "$(cat "$test_dir/err")" >&2
  exit 1
fi
grep -Fqx 'VERIFY_SETTINGS=PASS' "$test_dir/out" || {
  printf '%s\n' 'FAIL: Settings routes were not verified' >&2
  exit 1
}
grep -Fq 'shell am start -a android.intent.action.MAIN -f 0x04000000 -n com.amazon.tv.launcher/.ui.MainSettingsActivity' "$FAKE_ADB_LOG" || {
  printf '%s\n' 'FAIL: the stock Settings root did not receive ACTION_MAIN' >&2
  exit 1
}

printf '%s\n' 'SETTINGS_ROOT_MAIN_ACTION=PASS'
