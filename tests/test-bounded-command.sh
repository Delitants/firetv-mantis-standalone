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

output=$(python3 "$root/scripts/run-bounded.py" 2 sh -c 'printf bounded')
[ "$output" = bounded ] || {
  printf 'FAIL: bounded command did not forward output: %s\n' "$output" >&2
  exit 1
}

printf '%s\n' 'BOUNDED_COMMAND=PASS'
