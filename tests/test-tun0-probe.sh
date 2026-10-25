#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mantis-tun0-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM

FAKE_ADB_LOG="$TEST_DIR/adb.log" \
  "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" \
  --serial test-host:5555 --network-serial network-check:5555 \
  --output "$TEST_DIR/audit" audit > "$TEST_DIR/out" 2> "$TEST_DIR/err"

grep -q '^tun0=present$' "$TEST_DIR/audit/verification-baseline.txt"
grep -q 'tun0:' "$TEST_DIR/audit/tun0.txt"
grep -q 'shell cat /proc/net/dev' "$TEST_DIR/adb.log"
if grep -q 'shell ip link show tun0' "$TEST_DIR/adb.log"; then
  printf '%s\n' 'FAIL: tun0 probe still uses restricted ip command' >&2
  exit 1
fi

if FAKE_NETDEV_DENIED=yes FAKE_ADB_LOG="$TEST_DIR/denied-adb.log" \
  "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" \
  --serial test-host:5555 --network-serial network-check:5555 \
  --output "$TEST_DIR/denied-audit" audit > "$TEST_DIR/denied-out" 2> "$TEST_DIR/denied-err"
then
  printf '%s\n' 'FAIL: unreadable network devices were treated as tun0 absent' >&2
  exit 1
fi
grep -q 'adb shell failed: cat /proc/net/dev' "$TEST_DIR/denied-err"

printf '%s\n' 'TUN0_PROBE_TEST=PASS'
