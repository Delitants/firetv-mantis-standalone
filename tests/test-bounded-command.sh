#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
status=0
output=$(python3 "$root/scripts/run-bounded.py" 0.2 sleep 5 2>&1) || status=$?
[ "$status" -eq 124 ] || {
  printf 'FAIL: timed-out command returned %s instead of 124\n' "$status" >&2
  exit 1
}
case "$output" in *COMMAND_TIMEOUT*) ;; *)
  printf 'FAIL: timed-out command has no diagnostic: %s\n' "$output" >&2
  exit 1
esac

slow_adb_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-bounded-adb.XXXXXX")
trap 'rm -rf "$slow_adb_dir"' EXIT HUP INT TERM
printf '#!/bin/sh\nsleep 5\n' > "$slow_adb_dir/adb"
chmod +x "$slow_adb_dir/adb"
status=0
output=$(python3 "$root/scripts/run-bounded.py" 0.2 "$slow_adb_dir/adb" -s usb-primary \
  shell pm disable-user --user 0 com.amazon.example 2>&1) || status=$?
[ "$status" -eq 124 ] || { printf 'FAIL: fake ADB timeout returned %s\n' "$status" >&2; exit 1; }
case "$output" in *'operation=adb.shell.pm.disable-user'*) ;; *)
  printf 'FAIL: ADB timeout did not identify the operation: %s\n' "$output" >&2
  exit 1
esac
case "$output" in *usb-primary*|*com.amazon.example*)
  printf 'FAIL: ADB timeout exposed device or package details: %s\n' "$output" >&2
  exit 1
  ;;
esac

output=$(python3 "$root/scripts/run-bounded.py" 2 sh -c 'printf bounded')
[ "$output" = bounded ] || {
  printf 'FAIL: bounded command did not forward output: %s\n' "$output" >&2
  exit 1
}

printf '%s\n' 'BOUNDED_COMMAND=PASS'
