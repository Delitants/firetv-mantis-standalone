#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-grid-capture.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
capture_dir=$test_dir/private
mkdir "$capture_dir"

# Reject a bad destination before any ADB contact.
if "$root/scripts/mantis-tool.sh" --adb "$test_dir/nonexistent-adb" \
    --serial test-host:5555 --output relative verify-settings \
    > "$test_dir/invalid-out" 2> "$test_dir/invalid-err"; then
  printf '%s\n' 'FAIL: relative Settings capture directory was accepted' >&2
  exit 1
fi
grep -Fq 'existing absolute directory' "$test_dir/invalid-err" || {
  printf 'FAIL: invalid capture destination did not fail early: %s\n' \
    "$(cat "$test_dir/invalid-err")" >&2
  exit 1
}

export FAKE_UI_STATE=$test_dir/ui-state
export FAKE_ADB_LOG=$test_dir/adb.log
if FAKE_ROOT_GRID_NO_FOCUS=yes \
  "$root/scripts/mantis-tool.sh" --adb "$root/tests/fixtures/adb" \
    --serial test-host:5555 --output "$capture_dir" verify-settings \
    > "$test_dir/out" 2> "$test_dir/err"; then
  printf '%s\n' 'FAIL: an unfocused grid passed Settings verification' >&2
  exit 1
fi

capture_path=$(sed -n 's/^SETTINGS_GRID_CAPTURE=//p' "$test_dir/err" | tail -n 1)
case "$capture_path" in
  "$capture_dir"/settings-grid-failure.*/grid.xml) ;;
  *) printf 'FAIL: no private grid capture path: %s\n' "$(cat "$test_dir/err")" >&2; exit 1 ;;
esac
[ -f "$capture_path" ] || { printf '%s\n' 'FAIL: grid capture file is missing' >&2; exit 1; }
grep -Fq 'focused="false"' "$capture_path"
grep -Fq 'com.amazon.tv.launcher:id/title_text' "$capture_path"
grep -Fq 'text="Network"' "$capture_path"
if grep -Fq '<hierarchy' "$test_dir/err"; then
  printf '%s\n' 'FAIL: private grid XML leaked into the log' >&2
  exit 1
fi
python3 - "$capture_path" <<'PY'
import os
import stat
import sys

assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600
assert stat.S_IMODE(os.stat(os.path.dirname(sys.argv[1])).st_mode) == 0o700
PY

printf '%s\n' 'SETTINGS_GRID_CAPTURE=PASS'
