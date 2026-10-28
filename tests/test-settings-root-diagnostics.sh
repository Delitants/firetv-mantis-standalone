#!/bin/sh
set -eu

source_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-settings-root.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
fixture=$source_root/tests/fixtures/adb
export FAKE_UI_STATE=$test_dir/ui-state

FAKE_ROOT_GRID_NO_FOCUS=yes \
  "$source_root/scripts/mantis-tool.sh" --adb "$fixture" --serial test-host:5555 \
    verify-settings > "$test_dir/out" 2> "$test_dir/err" && {
      printf '%s\n' 'FAIL: Settings accepted a root grid with no focused tile' >&2; exit 1;
    }
grep -Fq 'Settings grid has 0 focused tiles' "$test_dir/err" || {
  printf 'FAIL: Settings hid the grid parser failure: %s\n' "$(cat "$test_dir/err")" >&2
  exit 1
}
! grep -Fq 'VERIFY_SETTINGS=PASS' "$test_dir/out" || {
  printf '%s\n' 'FAIL: Settings falsely reported pass' >&2; exit 1;
}
printf '%s\n' 'SETTINGS_ROOT_DIAGNOSTICS=PASS'
