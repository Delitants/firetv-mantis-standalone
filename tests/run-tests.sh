#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mantis-tool-tests.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
export FAKE_ADB_LOG="$TEST_TMP/adb.log"
unset FAKE_MANUFACTURER FAKE_MODEL FAKE_DEVICE FAKE_BUILD_ID FAKE_INCREMENTAL
unset FAKE_RELEASE FAKE_SDK FAKE_ABI FAKE_UNAME FAKE_ENFORCE FAKE_UID

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
}

run_tool() {
  : > "$FAKE_ADB_LOG"
  if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial test-serial "$@" >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
    STATUS=0
  else
    STATUS=$?
  fi
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

run_tool audit || true
[ "$STATUS" -eq 0 ] || fail "audit failed for exact target: $ERR"
assert_contains "$OUT" 'SUPPORTED_MUTATION_TARGET=YES'
assert_contains "$OUT" 'ROOT=NOT_ACHIEVED'
assert_contains "$(cat "$FAKE_ADB_LOG")" '-s test-serial shell getprop ro.product.model'

if FAKE_MODEL=AFTKA run_tool --yes apply; then
  fail 'accepted AFTKA'
fi
assert_contains "$ERR" 'model expected=AFTMM actual=AFTKA'
unset FAKE_MODEL

if FAKE_INCREMENTAL=0011644900485 run_tool --yes apply; then
  fail 'accepted different build'
fi
assert_contains "$ERR" 'incremental expected=0011644900484 actual=0011644900485'
unset FAKE_INCREMENTAL

FAKE_MODEL=$(printf 'AFTMM\r') run_tool audit
[ "$STATUS" -eq 0 ] || fail 'audit rejected a trailing CR'
assert_contains "$OUT" 'SUPPORTED_MUTATION_TARGET=YES'

printf '%s\n' 'PASS: target gate tests'
