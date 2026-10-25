#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-deploy-progress.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

mkdir "$test_dir/output"
if "$root/scripts/deploy-mantis.sh" \
  --adb false --curl true --aapt true --apksigner true \
  --serial test-usb --network-serial test-network:5555 \
  --root-binary "$root/tests/fixtures/aapt" --output "$test_dir/output" --yes \
  >"$test_dir/stdout" 2>"$test_dir/stderr"
then
  printf '%s\n' 'FAIL: unreachable target unexpectedly passed' >&2
  exit 1
fi

grep -Fq 'PHASE=TARGET_GATE' "$test_dir/stdout" || {
  printf '%s\n' 'FAIL: deployment gave no progress before the first ADB call' >&2
  exit 1
}
grep -Fq 'DEPLOY_LOG=' "$test_dir/stdout" || {
  printf '%s\n' 'FAIL: deployment did not disclose its live log path' >&2
  exit 1
}
set -- "$test_dir"/output/deployment-*/deploy.log
[ "$#" -eq 1 ] && [ -f "$1" ] && grep -Fq 'PHASE=TARGET_GATE' "$1" || {
  printf '%s\n' 'FAIL: deployment log has no initial phase' >&2
  exit 1
}

mkdir "$test_dir/signal-output"
FAKE_ADB_DELAY=3 "$root/scripts/deploy-mantis.sh" \
  --adb "$root/tests/fixtures/adb" --curl true --aapt true --apksigner true \
  --serial test-usb --network-serial test-network:5555 \
  --root-binary "$root/tests/fixtures/aapt" --output "$test_dir/signal-output" --yes \
  >"$test_dir/signal-stdout" 2>"$test_dir/signal-stderr" &
deploy_pid=$!
sleep 1
kill -TERM "$deploy_pid"
status=0
wait "$deploy_pid" || status=$?
[ "$status" -ne 0 ] && grep -Fq 'DEPLOY_FAILED' "$test_dir/signal-stderr" || {
  printf 'FAIL: interrupted deployment reported success (status=%s)\n' "$status" >&2
  exit 1
}

printf '%s\n' 'DEPLOY_PROGRESS=PASS'
