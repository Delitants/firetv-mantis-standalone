#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mantis-tool-tests.XXXXXX")
MANIFEST_REMOVE="$ROOT/manifests/remove-user0.txt"
ORIGINAL_REMOVE=

restore_manifest() {
  if [ -n "$ORIGINAL_REMOVE" ]; then
    cp "$ORIGINAL_REMOVE" "$MANIFEST_REMOVE"
    ORIGINAL_REMOVE=
  fi
}

cleanup() {
  restore_manifest
  rm -rf "$TEST_TMP"
}

trap cleanup EXIT HUP INT TERM
export FAKE_ADB_LOG="$TEST_TMP/adb.log"
unset FAKE_MANUFACTURER FAKE_MODEL FAKE_DEVICE FAKE_BUILD_ID FAKE_INCREMENTAL
unset FAKE_RELEASE FAKE_SDK FAKE_ABI FAKE_UNAME FAKE_ENFORCE FAKE_UID
unset FAKE_PERSIST_SYS_LOCALE FAKE_SYSTEM_LOCALES FAKE_HOME FAKE_BLUETOOTH_ON FAKE_TUN0
unset FAKE_CMD_PACKAGE_HELP FAKE_PM_HELP FAKE_PACKAGES_ACTIVE FAKE_PACKAGES_UNINSTALLED FAKE_PACKAGES_DISABLED

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

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

verify_checksums() {
  checksum_dir=$1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$checksum_dir" && sha256sum -c SHA256SUMS >/dev/null)
  else
    (cd "$checksum_dir" && shasum -a 256 -c SHA256SUMS >/dev/null)
  fi
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

run_tool --output "$TEST_TMP/audit-initial" audit || true
[ "$STATUS" -eq 0 ] || fail "audit failed for exact target: $ERR"
assert_contains "$OUT" 'SUPPORTED_MUTATION_TARGET=YES'
assert_contains "$OUT" 'ROOT=NOT_ACHIEVED'
assert_contains "$(cat "$FAKE_ADB_LOG")" '-s test-serial shell getprop ro.product.model'

# Break caught: removing audit publication would leave no restorable baseline.
AUDIT_DIR="$TEST_TMP/audit"
run_tool --output "$AUDIT_DIR" audit || fail "audit publication failed: $ERR"
assert_file "$AUDIT_DIR/device.txt"
assert_file "$AUDIT_DIR/packages-active.txt"
assert_file "$AUDIT_DIR/packages-uninstalled.txt"
assert_file "$AUDIT_DIR/protected-apps.txt"
assert_file "$AUDIT_DIR/restore-user0.sh"
assert_file "$AUDIT_DIR/SHA256SUMS"
sh -n "$AUDIT_DIR/restore-user0.sh" || fail 'generated restore script is invalid shell'
verify_checksums "$AUDIT_DIR" || fail 'audit checksum verification failed'
assert_contains "$OUT" 'RESTORE_CAPABILITY=cmd'
assert_contains "$OUT" 'AUDIT=PASS'
assert_contains "$(cat "$AUDIT_DIR/device.txt")" 'persist.sys.locale=en-US'
assert_contains "$(cat "$AUDIT_DIR/device.txt")" 'system_locales=en-US'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.WIFI_SETTINGS=com.amazon.tv.settings/.wifi.WifiSettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.CONTROLLERS_SETTINGS=com.amazon.tv.settings/.controllers.ControllersActivity'
assert_contains "$(cat "$AUDIT_DIR/home-resolver.txt")" 'com.amazon.tv.launcher/.HomeActivity'
assert_contains "$(cat "$AUDIT_DIR/bluetooth.txt")" 'bluetooth_on=1'
assert_contains "$(cat "$AUDIT_DIR/tun0.txt")" 'tun0:'

# Break caught: preferring a cmd form that does not prove --user support.
PM_AUDIT_DIR="$TEST_TMP/audit-pm"
FAKE_CMD_PACKAGE_HELP='install-existing PACKAGE' FAKE_PM_HELP='install-existing --user USER_ID PACKAGE' \
  run_tool --output "$PM_AUDIT_DIR" audit || fail "pm fallback audit failed: $ERR"
assert_contains "$OUT" 'RESTORE_CAPABILITY=pm'
printf '%s\n' com.example.first com.example.second > "$PM_AUDIT_DIR/removed-successfully.txt"
: > "$FAKE_ADB_LOG"
SERIAL=test-serial ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err" ||
  fail "generated pm restore failed: $(cat "$TEST_TMP/restore-err")"
RESTORE_LOG=$(cat "$FAKE_ADB_LOG")
assert_contains "$RESTORE_LOG" 'shell pm install-existing --user 0 com.example.second'
assert_contains "$RESTORE_LOG" 'shell pm install-existing --user 0 com.example.first'
case "$RESTORE_LOG" in
  *com.example.removed*) fail 'restore used the package inventory instead of the removal journal' ;;
esac
: > "$FAKE_ADB_LOG"
if FAKE_RELEASE=7.1.3 SERIAL=test-serial ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err"; then
  fail 'restore accepted a different Android release'
fi
assert_contains "$(cat "$TEST_TMP/restore-err")" 'ro.build.version.release expected=7.1.2 actual=7.1.3'
case "$(cat "$FAKE_ADB_LOG")" in
  *install-existing*) fail 'restore attempted installation on a mismatched target' ;;
esac

# Break caught: attempting a user-0 removal without a help-proven rollback path.
if FAKE_CMD_PACKAGE_HELP='no install commands' FAKE_PM_HELP='no install commands' run_tool --yes apply; then
  fail 'apply accepted no restore capability'
fi
assert_contains "$ERR" 'no help-proven install-existing command is available'
case "$(cat "$FAKE_ADB_LOG")" in
  *'uninstall -k --user 0'*) fail 'apply attempted removal without restore capability' ;;
esac

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

FAKE_MODEL=$(printf 'AFTMM\r') run_tool --output "$TEST_TMP/audit-cr" audit
[ "$STATUS" -eq 0 ] || fail 'audit rejected a trailing CR'
assert_contains "$OUT" 'SUPPORTED_MUTATION_TARGET=YES'

ORIGINAL_REMOVE="$TEST_TMP/remove-user0.txt"
cp "$MANIFEST_REMOVE" "$ORIGINAL_REMOVE"
printf '%s\n' 'com.amazon.bueller.music ' > "$MANIFEST_REMOVE"

if FAKE_MODEL=AFTKA run_tool --yes apply; then
  fail 'accepted AFTKA with an invalid manifest'
fi
assert_contains "$ERR" 'model expected=AFTMM actual=AFTKA'
case "$ERR" in
  *'invalid package token'*) fail 'validated manifests before rejecting the target' ;;
esac
unset FAKE_MODEL

if run_tool --yes apply; then
  fail 'apply accepted an invalid manifest'
fi
assert_contains "$ERR" 'invalid package token'
case "$OUT" in
  *'No mutation is implemented.'*) fail 'apply reached its action after manifest rejection' ;;
esac
restore_manifest

python3 -B "$ROOT/tests/verify-manifests.py" "$ROOT/manifests"

printf '%s\n' 'PASS: target gate tests'
