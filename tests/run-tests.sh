#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mantis-tool-tests.XXXXXX")
MANIFEST_REMOVE="$ROOT/manifests/remove-user0.txt"
ORIGINAL_REMOVE=
ORIGINAL_REMOVE="$TEST_TMP/remove-user0-original.txt"
cp "$MANIFEST_REMOVE" "$ORIGINAL_REMOVE"

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
REAL_PYTHON_BIN=$(command -v python3)
unset FAKE_MANUFACTURER FAKE_MODEL FAKE_DEVICE FAKE_BUILD_ID FAKE_INCREMENTAL
unset FAKE_RELEASE FAKE_SDK FAKE_ABI FAKE_UNAME FAKE_ENFORCE FAKE_UID
unset FAKE_PERSIST_SYS_LOCALE FAKE_SYSTEM_LOCALES FAKE_HOME FAKE_BLUETOOTH_ON FAKE_TUN0
unset FAKE_ADB_ENABLED FAKE_DEVELOPMENT_SETTINGS_ENABLED FAKE_PERSIST_USB_CONFIG FAKE_SYS_USB_CONFIG
unset FAKE_SERVICE_ADB_TCP_PORT FAKE_PERSIST_ADB_TCP_PORT FAKE_ADBD_PID FAKE_ALWAYS_ON_VPN_APP
unset FAKE_ALWAYS_ON_VPN_LOCKDOWN FAKE_PACKAGE_STATE FAKE_UNINSTALL_MODE FAKE_UNINSTALL_FAIL_PACKAGE
unset FAKE_AFTER_UNINSTALL_ADB_ENABLED FAKE_UNINSTALL_RESULT
unset FAKE_AFTER_UNINSTALL_ADB_ENABLED_AFTER_COUNT FAKE_INSTALL_EXISTING_FAIL_PACKAGE
unset FAKE_HOME_RESOLVER FAKE_INTERRUPT_MARKER FAKE_NETSTAT
unset FAKE_CMD_PACKAGE_HELP FAKE_PM_HELP FAKE_PACKAGES_ACTIVE FAKE_PACKAGES_UNINSTALLED FAKE_PACKAGES_DISABLED
unset FAKE_WOLF_CURL_EXPECTED_URL FAKE_WOLF_SIZE FAKE_WOLF_PACKAGE FAKE_WOLF_VERSION_CODE
unset FAKE_WOLF_VERSION_NAME FAKE_WOLF_MIN_SDK FAKE_WOLF_TARGET_SDK FAKE_WOLF_INSTALL_LOCATION
unset FAKE_WOLF_ACTIVITY FAKE_WOLF_V1 FAKE_WOLF_V2 FAKE_WOLF_SIGNER FAKE_WOLF_STATE
unset FAKE_WOLF_CURL_LOG FAKE_WOLF_DUMPSYS_INDENT

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

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "did not expect [$2] in [$1]" ;;
    *) ;;
  esac
}

verify_checksums() {
  checksum_dir=$1
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$checksum_dir" && sha256sum -c SHA256SUMS >/dev/null)
  else
    (cd "$checksum_dir" && shasum -a 256 -c SHA256SUMS >/dev/null)
  fi
}

refresh_checksums() {
  checksum_dir=$1
  (
    cd "$checksum_dir"
    find . -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort |
    while IFS= read -r checksum_file; do
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$checksum_file"
      else
        shasum -a 256 "$checksum_file"
      fi
    done > SHA256SUMS
  )
}

run_tool() {
  : > "$FAKE_ADB_LOG"
  if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial test-host:5555 "$@" >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
    STATUS=0
  else
    STATUS=$?
  fi
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

run_tool_interrupted() {
  : > "$FAKE_ADB_LOG"
  "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial test-host:5555 "$@" >"$TEST_TMP/out" 2>"$TEST_TMP/err" &
  TOOL_PID=$!
  wait_count=0
  while [ ! -e "$FAKE_INTERRUPT_MARKER" ] && [ "$wait_count" -lt 50 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
  done
  [ -e "$FAKE_INTERRUPT_MARKER" ] || fail 'fake ADB did not reach the interruption point'
  kill -TERM "$TOOL_PID"
  if wait "$TOOL_PID"; then
    STATUS=0
  else
    STATUS=$?
  fi
  rm -f "$FAKE_INTERRUPT_MARKER"
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

run_wolf() {
  export FAKE_WOLF_CURL_EXPECTED_URL FAKE_WOLF_SIZE FAKE_WOLF_HASH FAKE_WOLF_PACKAGE
  export FAKE_WOLF_VERSION_CODE FAKE_WOLF_VERSION_NAME FAKE_WOLF_MIN_SDK FAKE_WOLF_TARGET_SDK
  export FAKE_WOLF_INSTALL_LOCATION FAKE_WOLF_ACTIVITY FAKE_WOLF_V1 FAKE_WOLF_V2 FAKE_WOLF_SIGNER
  export FAKE_WOLF_STATE FAKE_WOLF_CURL_LOG FAKE_WOLF_DUMPSYS_INDENT
  : > "$FAKE_ADB_LOG"
  if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" \
    --curl "$ROOT/tests/fixtures/curl" --aapt "$ROOT/tests/fixtures/aapt" \
    --apksigner "$ROOT/tests/fixtures/apksigner" --sha256 "$ROOT/tests/fixtures/wolf-sha256" \
    --serial test-host:5555 --yes install-wolf >"$TEST_TMP/out" 2>"$TEST_TMP/err"
  then
    STATUS=0
  else
    STATUS=$?
  fi
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

reset_wolf_fixture() {
  unset FAKE_WOLF_CURL_EXPECTED_URL FAKE_WOLF_SIZE FAKE_WOLF_HASH FAKE_WOLF_PACKAGE
  unset FAKE_WOLF_VERSION_CODE FAKE_WOLF_VERSION_NAME FAKE_WOLF_MIN_SDK FAKE_WOLF_TARGET_SDK
  unset FAKE_WOLF_INSTALL_LOCATION FAKE_WOLF_ACTIVITY FAKE_WOLF_V1 FAKE_WOLF_V2 FAKE_WOLF_SIGNER
  unset FAKE_WOLF_STATE FAKE_WOLF_CURL_LOG FAKE_WOLF_DUMPSYS_INDENT
}

prepare_package_state() {
  FAKE_PACKAGE_STATE=$TEST_TMP/package-state
  export FAKE_PACKAGE_STATE
  : > "$FAKE_PACKAGE_STATE"
  for preserve_manifest in "$ROOT/manifests/preserve-core.txt" "$ROOT/manifests/preserve-user-apps.txt"; do
    while IFS= read -r package; do
      printf 'active %s\n' "$package" >> "$FAKE_PACKAGE_STATE"
    done < "$preserve_manifest"
  done
  printf '%s\n' 'active com.amazon.android.marketplace' 'active com.amazon.bueller.music' >> "$FAKE_PACKAGE_STATE"
  unset FAKE_UNINSTALL_MODE FAKE_UNINSTALL_FAIL_PACKAGE FAKE_AFTER_UNINSTALL_ADB_ENABLED FAKE_UNINSTALL_RESULT
  unset FAKE_AFTER_UNINSTALL_ADB_ENABLED_AFTER_COUNT FAKE_INSTALL_EXISTING_FAIL_PACKAGE
  unset FAKE_REQUIRED_JOURNAL FAKE_REQUIRED_JOURNAL_RESULT
  unset FAKE_CMD_PACKAGE_HELP FAKE_PM_HELP
  unset FAKE_HOME_RESOLVER FAKE_INTERRUPT_MARKER FAKE_NETSTAT
}

set_wolf_ready() {
  export FAKE_WOLF_INSTALLED_VERSION_CODE=11900120
  export FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf
}

clear_wolf_ready() {
  unset FAKE_WOLF_INSTALLED_VERSION_CODE FAKE_WOLF_INSTALLED_VERSION_NAME
}

assert_wolf_not_installed() {
  WOLF_ADB_LOG=$(cat "$FAKE_ADB_LOG")
  case "$WOLF_ADB_LOG" in
    *'install -r '*|*'uninstall '*|*'clear'*) fail "Wolf rejection modified a launcher: $WOLF_ADB_LOG" ;;
  esac
}

assert_wolf_download_removed() {
  wolf_download=$(sed -n 's/^output=//p' "$FAKE_WOLF_CURL_LOG")
  [ -n "$wolf_download" ] || fail 'Wolf curl fixture did not record an output path'
  [ ! -e "$wolf_download" ] || fail "Wolf temporary APK remained at $wolf_download"
}

# Break caught: reporting success without a pinned install, exact readback, and direct launch.
WOLF_POSITIVE_STATE="$TEST_TMP/wolf-positive-state"
printf '%s\n' '11723945 0.1.7-FireTV' > "$WOLF_POSITIVE_STATE"
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-positive.log" FAKE_WOLF_STATE="$WOLF_POSITIVE_STATE" run_wolf ||
  fail "Wolf positive fixture failed: $ERR"
assert_contains "$OUT" 'WOLF_VERIFY=PASS'
assert_contains "$OUT" 'WOLF_INSTALL=PASS'
assert_contains "$OUT" 'WOLF_INSTALLED_VERSION_CODE=11900120'
assert_contains "$OUT" 'WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf'
assert_contains "$OUT" 'WOLF_DIRECT_LAUNCH=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'install -r '
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell dumpsys package com.wolf.firelauncher'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -n com.wolf.firelauncher/.screens.launcher.LauncherActivity'
[ "$(cat "$WOLF_POSITIVE_STATE")" = '11900120 0.1.9-Wolf' ] || fail 'Wolf positive fixture did not update installed identity'
assert_wolf_download_removed

# Break caught: rejecting an installed Wolf version because dumpsys indents its fields.
WOLF_INDENTED_STATE="$TEST_TMP/wolf-indented-state"
printf '%s\n' '11723945 0.1.7-FireTV' > "$WOLF_INDENTED_STATE"
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-indented.log" FAKE_WOLF_STATE="$WOLF_INDENTED_STATE" \
FAKE_WOLF_DUMPSYS_INDENT=yes run_wolf || fail "Wolf indented dumpsys fixture failed: $ERR"
assert_contains "$OUT" 'WOLF_INSTALLED_VERSION_CODE=11900120'
assert_contains "$OUT" 'WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf'
assert_contains "$OUT" 'WOLF_DIRECT_LAUNCH=PASS'
assert_wolf_download_removed

run_tool --output "$TEST_TMP/audit-initial" audit || true
[ "$STATUS" -eq 0 ] || fail "audit failed for exact target: $ERR"
assert_contains "$OUT" 'SUPPORTED_MUTATION_TARGET=YES'
assert_contains "$OUT" 'ROOT=NOT_ACHIEVED'
assert_contains "$(cat "$FAKE_ADB_LOG")" '-s test-host:5555 shell getprop ro.product.model'

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
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.SETTINGS=com.amazon.tv.settings/.SettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.WIFI_SETTINGS=com.amazon.tv.settings/.wifi.WifiSettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.MANAGE_APPLICATIONS_SETTINGS=com.amazon.tv.settings/.applications.ManageApplicationsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.CONTROLLERS_SETTINGS=com.amazon.tv.settings/.controllers.ControllersActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.DEVICE_INFO_SETTINGS=com.amazon.tv.settings/.device.DeviceInfoSettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.ACCESSIBILITY_SETTINGS=com.amazon.tv.settings/.accessibility.AccessibilitySettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.DISPLAY_SETTINGS=com.amazon.tv.settings/.display.DisplaySettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'com.amazon.device.settings.action.DATE_TIME=com.amazon.tv.settings/.date.DateTimeSettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'com.amazon.device.settings.action.LANGUAGE=com.amazon.tv.settings/.locale.LocaleSettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/home-resolver.txt")" 'com.amazon.tv.launcher/.HomeActivity'
assert_contains "$(cat "$AUDIT_DIR/bluetooth.txt")" 'bluetooth_on=1'
assert_contains "$(cat "$AUDIT_DIR/tun0.txt")" 'tun0:'

# Break caught: bypassing the production atomic-rename helper on normal publication.
HELPER_AUDIT_DIR="$TEST_TMP/audit-helper"
HELPER_LOG="$TEST_TMP/atomic-rename.log"
if (
  PATH="$ROOT/tests/fixtures:$PATH"
  REAL_PYTHON="$REAL_PYTHON_BIN"
  RACE_OUTPUT_KIND=observe
  RACE_HELPER_LOG="$HELPER_LOG"
  export PATH REAL_PYTHON RACE_OUTPUT_KIND RACE_HELPER_LOG
  run_tool --output "$HELPER_AUDIT_DIR" audit
); then
  :
else
  fail "atomic helper audit failed: $(cat "$TEST_TMP/err")"
fi
assert_file "$HELPER_AUDIT_DIR/device.txt"
assert_contains "$(cat "$HELPER_LOG")" inspect
assert_contains "$(cat "$HELPER_LOG")" publish

# Break caught: placing a backup in a directory created at publish time.
RACE_AUDIT_DIR="$TEST_TMP/audit-race"
if (
  PATH="$ROOT/tests/fixtures:$PATH"
  REAL_PYTHON="$REAL_PYTHON_BIN"
  RACE_OUTPUT_KIND=directory
  RACE_OUTPUT_DIR="$RACE_AUDIT_DIR"
  RACE_HELPER_LOG="$TEST_TMP/atomic-directory.log"
  export PATH REAL_PYTHON RACE_OUTPUT_KIND RACE_OUTPUT_DIR RACE_HELPER_LOG
  run_tool --output "$RACE_AUDIT_DIR" audit
); then
  fail 'audit accepted an output directory that appeared during publication'
fi
OUT=$(cat "$TEST_TMP/out")
ERR=$(cat "$TEST_TMP/err")
assert_contains "$ERR" 'audit output publication conflict'
[ -d "$RACE_AUDIT_DIR" ] || fail 'race fixture did not create the destination directory'
assert_contains "$(cat "$RACE_AUDIT_DIR/keep.txt")" 'unrelated destination content'
[ ! -e "$RACE_AUDIT_DIR/device.txt" ] || fail 'audit published a backup into the raced destination'

# Break caught: following a symlink created at the exact output path.
RACE_SYMLINK_AUDIT_DIR="$TEST_TMP/audit-race-symlink"
RACE_LINK_TARGET="$TEST_TMP/audit-race-symlink-target"
mkdir "$RACE_LINK_TARGET"
printf '%s\n' 'unrelated symlink target content' > "$RACE_LINK_TARGET/keep.txt"
if (
  PATH="$ROOT/tests/fixtures:$PATH"
  REAL_PYTHON="$REAL_PYTHON_BIN"
  RACE_OUTPUT_KIND=symlink
  RACE_OUTPUT_DIR="$RACE_SYMLINK_AUDIT_DIR"
  RACE_LINK_TARGET="$RACE_LINK_TARGET"
  RACE_HELPER_LOG="$TEST_TMP/atomic-symlink.log"
  export PATH REAL_PYTHON RACE_OUTPUT_KIND RACE_OUTPUT_DIR RACE_LINK_TARGET RACE_HELPER_LOG
  run_tool --output "$RACE_SYMLINK_AUDIT_DIR" audit
); then
  fail 'audit accepted an output symlink that appeared during publication'
fi
OUT=$(cat "$TEST_TMP/out")
ERR=$(cat "$TEST_TMP/err")
assert_contains "$ERR" 'audit output publication conflict'
[ -L "$RACE_SYMLINK_AUDIT_DIR" ] || fail 'race fixture did not create the output symlink'
assert_contains "$(cat "$RACE_LINK_TARGET/keep.txt")" 'unrelated symlink target content'
[ ! -e "$RACE_LINK_TARGET/device.txt" ] || fail 'audit followed the raced output symlink'

# Break caught: publishing a staging path replaced after it was identified.
RACE_SOURCE_AUDIT_DIR="$TEST_TMP/audit-race-source"
RACE_SOURCE_RECORD="$TEST_TMP/replaced-source-path"
if (
  PATH="$ROOT/tests/fixtures:$PATH"
  REAL_PYTHON="$REAL_PYTHON_BIN"
  RACE_OUTPUT_KIND=source-replacement
  RACE_HELPER_LOG="$TEST_TMP/atomic-source.log"
  RACE_SOURCE_RECORD="$RACE_SOURCE_RECORD"
  export PATH REAL_PYTHON RACE_OUTPUT_KIND RACE_HELPER_LOG RACE_SOURCE_RECORD
  run_tool --output "$RACE_SOURCE_AUDIT_DIR" audit
); then
  fail 'audit accepted a replaced staging directory'
fi
OUT=$(cat "$TEST_TMP/out")
ERR=$(cat "$TEST_TMP/err")
assert_contains "$ERR" 'audit output publication conflict'
[ ! -e "$RACE_SOURCE_AUDIT_DIR/device.txt" ] || fail 'audit published replacement staging content'
REPLACED_SOURCE=$(cat "$RACE_SOURCE_RECORD")
assert_contains "$(cat "$REPLACED_SOURCE/keep.txt")" 'unrelated replacement content'

# Break caught: omitting the Linux no-replace implementation branch.
LINUX_STRATEGY=$(python3 "$ROOT/scripts/atomic-rename.py" strategy linux) || fail 'Linux atomic rename strategy is unavailable'
assert_contains "$LINUX_STRATEGY" 'linux: renameat2(RENAME_NOREPLACE)'

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

# Break caught: planning a removal must expose the exact inverse without changing user 0.
PACKAGE_ORIGINAL_REMOVE="$TEST_TMP/remove-user0-package-operations.txt"
cp "$MANIFEST_REMOVE" "$PACKAGE_ORIGINAL_REMOVE"
printf '%s\n' com.amazon.android.marketplace com.amazon.bueller.music > "$MANIFEST_REMOVE"
prepare_package_state
set_wolf_ready
run_tool plan || fail "plan failed for valid package operations: $ERR"
assert_contains "$OUT" 'REMOVE=com.amazon.android.marketplace RESTORE=cmd package install-existing --user 0 com.amazon.android.marketplace'
assert_contains "$OUT" 'REMOVE=com.amazon.bueller.music RESTORE=cmd package install-existing --user 0 com.amazon.bueller.music'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'uninstall -k --user 0'

# Break caught: a compact guard that omits any preserve manifest package can remove user apps after core recovery paths are already gone.
PACKAGE_TCOMM_GUARD_DIR="$TEST_TMP/apply-tcomm-guard"
prepare_package_state
awk '
  $1 == "active" && $2 == "com.amazon.tcomm" { print "uninstalled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
set_wolf_ready
if run_tool --output "$PACKAGE_TCOMM_GUARD_DIR" --yes apply; then
  fail 'apply accepted a missing mandatory preserve package'
fi
assert_contains "$ERR" 'guard missing active package: com.amazon.tcomm'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'uninstall -k --user 0'

# Break caught: any alternate HOME resolver can replace the stock recovery route.
PACKAGE_HOME_GUARD_DIR="$TEST_TMP/apply-home-guard"
prepare_package_state
set_wolf_ready
if FAKE_HOME_RESOLVER='com.example.launcher/.Home' run_tool --output "$PACKAGE_HOME_GUARD_DIR" --yes apply; then
  fail 'apply accepted a non-stock HOME resolver'
fi
assert_contains "$ERR" 'guard HOME resolver expected=com.amazon.tv.launcher/.HomeActivity actual=com.example.launcher/.Home'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'uninstall -k --user 0'

# Break caught: accepting a nonliteral uninstall response or a package that remains active.
PACKAGE_STILL_ACTIVE_DIR="$TEST_TMP/apply-still-active"
prepare_package_state
set_wolf_ready
FAKE_UNINSTALL_MODE=still-active run_tool --output "$PACKAGE_STILL_ACTIVE_DIR" --yes apply &&
  fail 'apply accepted Success while the package remained active'
assert_contains "$ERR" 'removal verification failed for com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_STILL_ACTIVE_DIR/operation-journal.txt")" 'attempt com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_STILL_ACTIVE_DIR/operation-journal.txt")" 'failure com.amazon.android.marketplace'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'

# Break caught: accepting a nonliteral Success response makes failed removals look safe.
PACKAGE_NONLITERAL_DIR="$TEST_TMP/apply-nonliteral"
prepare_package_state
set_wolf_ready
FAKE_UNINSTALL_RESULT='Success with trailing text' run_tool --output "$PACKAGE_NONLITERAL_DIR" --yes apply &&
  fail 'apply accepted a nonliteral uninstall response'
assert_contains "$ERR" 'removal failed for com.amazon.android.marketplace'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'

# Break caught: a later uninstall error must restore the current batch in reverse order.
PACKAGE_ERROR_DIR="$TEST_TMP/apply-error"
prepare_package_state
set_wolf_ready
FAKE_UNINSTALL_FAIL_PACKAGE=com.amazon.bueller.music run_tool --output "$PACKAGE_ERROR_DIR" --yes apply &&
  fail 'apply accepted a failed uninstall'
assert_contains "$ERR" 'removal failed for com.amazon.bueller.music'
ERROR_LOG=$(cat "$FAKE_ADB_LOG")
assert_contains "$ERROR_LOG" 'shell cmd package install-existing --user 0 com.amazon.bueller.music'
assert_contains "$ERROR_LOG" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'
awk '
  /install-existing --user 0 com.amazon.bueller.music/ { current = NR }
  /install-existing --user 0 com.amazon.android.marketplace/ { previous = NR }
  END { exit !(current && previous && current < previous) }
' "$FAKE_ADB_LOG" || fail 'rollback was not in reverse package order'

# Break caught: an already absent user-0 package must be skipped and omitted from rollback.
PACKAGE_ABSENT_DIR="$TEST_TMP/apply-absent"
prepare_package_state
awk '
  $1 == "active" && $2 == "com.amazon.android.marketplace" { print "uninstalled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
set_wolf_ready
run_tool --output "$PACKAGE_ABSENT_DIR" --yes apply || fail "apply failed for an absent package: $ERR"
assert_contains "$(cat "$PACKAGE_ABSENT_DIR/operation-journal.txt")" 'skip com.amazon.android.marketplace'
assert_not_contains "$(cat "$PACKAGE_ABSENT_DIR/removed-successfully.txt")" 'com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'uninstall -k --user 0 com.amazon.android.marketplace'

# Break caught: a package that vanishes from the all-users inventory has no safe rollback proof.
PACKAGE_MISSING_U_DIR="$TEST_TMP/apply-missing-u"
prepare_package_state
set_wolf_ready
FAKE_UNINSTALL_MODE=missing-uninstalled run_tool --output "$PACKAGE_MISSING_U_DIR" --yes apply &&
  fail 'apply accepted a package missing from pm list packages -u'
assert_contains "$ERR" 'removal verification failed for com.amazon.android.marketplace'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'

# Break caught: interruption recovery needs the attempt durable before adb, and each result before the next removal.
PACKAGE_JOURNAL_DIR="$TEST_TMP/apply-journal"
prepare_package_state
set_wolf_ready
FAKE_REQUIRED_JOURNAL="$PACKAGE_JOURNAL_DIR/operation-journal.txt" \
FAKE_REQUIRED_JOURNAL_RESULT='success com.amazon.android.marketplace' \
  run_tool --output "$PACKAGE_JOURNAL_DIR" --yes apply || fail "apply did not maintain a durable journal: $ERR"
JOURNAL=$(cat "$PACKAGE_JOURNAL_DIR/operation-journal.txt")
assert_contains "$JOURNAL" 'attempt com.amazon.android.marketplace'
assert_contains "$JOURNAL" 'success com.amazon.android.marketplace'
assert_contains "$JOURNAL" 'attempt com.amazon.bueller.music'
assert_contains "$JOURNAL" 'success com.amazon.bueller.music'
verify_checksums "$PACKAGE_JOURNAL_DIR" || fail 'apply did not retain checksummed journal and rollback state'

# Break caught: interruption after uninstall but before a success ledger entry must remain recoverable from its durable attempt.
PACKAGE_INTERRUPT_DIR="$TEST_TMP/apply-interrupted"
prepare_package_state
set_wolf_ready
FAKE_INTERRUPT_MARKER="$TEST_TMP/interrupt-after-uninstall" \
  run_tool_interrupted --output "$PACKAGE_INTERRUPT_DIR" --yes apply || true
assert_contains "$(cat "$PACKAGE_INTERRUPT_DIR/operation-journal.txt")" 'attempt com.amazon.android.marketplace'
assert_not_contains "$(cat "$PACKAGE_INTERRUPT_DIR/removed-successfully.txt")" 'com.amazon.android.marketplace'
run_tool restore "$PACKAGE_INTERRUPT_DIR" || fail "restore did not reconcile an interrupted uninstall: $ERR"
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'
assert_file "$PACKAGE_INTERRUPT_DIR/reconciliation-journal.txt"
assert_contains "$(cat "$PACKAGE_INTERRUPT_DIR/reconciliation-journal.txt")" 'reconciled com.amazon.android.marketplace'
verify_checksums "$PACKAGE_INTERRUPT_DIR" || fail 'interruption reconciliation left stale checksums'

# Break caught: restore must parse only trusted journal files rather than execute a supplied script, even if an attacker recomputes checksums.
PACKAGE_TRUST_DIR="$TEST_TMP/apply-restore-trust"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_TRUST_DIR" --yes apply || fail "apply failed for restore trust boundary: $ERR"
SCRIPT_MARKER="$TEST_TMP/untrusted-restore-script-ran"
printf 'touch %s\n' "$SCRIPT_MARKER" > "$PACKAGE_TRUST_DIR/restore-user0.sh"
chmod 700 "$PACKAGE_TRUST_DIR/restore-user0.sh"
refresh_checksums "$PACKAGE_TRUST_DIR"
run_tool restore "$PACKAGE_TRUST_DIR" || fail "controller restore rejected a checksummed backup: $ERR"
[ ! -e "$SCRIPT_MARKER" ] || fail 'public restore executed untrusted backup shell'
RESTORE_LOG=$(cat "$FAKE_ADB_LOG")
assert_contains "$RESTORE_LOG" 'shell cmd package install-existing --user 0 com.amazon.bueller.music'
assert_contains "$RESTORE_LOG" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'
awk '
  /install-existing --user 0 com.amazon.bueller.music/ { second = NR }
  /install-existing --user 0 com.amazon.android.marketplace/ { first = NR }
  END { exit !(second && first && second < first) }
' "$FAKE_ADB_LOG" || fail 'public restore did not use reverse order'

# Break caught: stale or tampered journals cannot be trusted for package installation.
PACKAGE_STALE_DIR="$TEST_TMP/apply-restore-stale"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_STALE_DIR" --yes apply || fail "apply failed for stale-journal test: $ERR"
printf '%s\n' com.example.untrusted > "$PACKAGE_STALE_DIR/removed-successfully.txt"
if run_tool restore "$PACKAGE_STALE_DIR"; then
  fail 'restore accepted a journal whose SHA256SUMS did not match'
fi
assert_contains "$ERR" 'backup integrity verification failed'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'install-existing'

# Break caught: a wrong-device restore is refused before reconciliation or package installation.
if FAKE_RELEASE=7.1.3 run_tool restore "$PACKAGE_JOURNAL_DIR"; then
  fail 'public restore accepted the wrong device'
fi
assert_contains "$ERR" 'release expected=7.1.2 actual=7.1.3'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'install-existing'
unset FAKE_RELEASE

# Break caught: losing ADB Debugging after an uninstall must trigger rollback while the transport remains live.
PACKAGE_ADB_GUARD_DIR="$TEST_TMP/apply-adb-guard"
prepare_package_state
set_wolf_ready
FAKE_AFTER_UNINSTALL_ADB_ENABLED=0 run_tool --output "$PACKAGE_ADB_GUARD_DIR" --yes apply &&
  fail 'apply accepted a changed adb_enabled setting'
assert_contains "$ERR" 'guard changed adb_enabled'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'get-state'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package install-existing --user 0 com.amazon.android.marketplace'

# Break caught: a partial rollback must remove each confirmed restore from the ledger and refresh the checksum before trying the next one.
PACKAGE_PARTIAL_ROLLBACK_DIR="$TEST_TMP/apply-partial-rollback"
prepare_package_state
set_wolf_ready
FAKE_AFTER_UNINSTALL_ADB_ENABLED=0 \
FAKE_AFTER_UNINSTALL_ADB_ENABLED_AFTER_COUNT=2 \
FAKE_INSTALL_EXISTING_FAIL_PACKAGE=com.amazon.android.marketplace \
  run_tool --output "$PACKAGE_PARTIAL_ROLLBACK_DIR" --yes apply && fail 'apply accepted a partial rollback'
PARTIAL_LEDGER=$(cat "$PACKAGE_PARTIAL_ROLLBACK_DIR/removed-successfully.txt")
assert_contains "$PARTIAL_LEDGER" 'com.amazon.android.marketplace'
assert_not_contains "$PARTIAL_LEDGER" 'com.amazon.bueller.music'
verify_checksums "$PACKAGE_PARTIAL_ROLLBACK_DIR" || fail 'partial rollback left stale checksums'

clear_wolf_ready
unset FAKE_PACKAGE_STATE FAKE_REQUIRED_JOURNAL FAKE_REQUIRED_JOURNAL_RESULT
cp "$PACKAGE_ORIGINAL_REMOVE" "$MANIFEST_REMOVE"

# Break caught: treating prose or similarly named commands as a rollback form.
MISLEADING_AUDIT_DIR="$TEST_TMP/audit-misleading-help"
FAKE_CMD_PACKAGE_HELP='Use install-existing --user only after a warning' \
  FAKE_PM_HELP='install-existing-extra --user USER_ID PACKAGE' \
  run_tool --output "$MISLEADING_AUDIT_DIR" audit || fail "misleading help audit failed: $ERR"
assert_contains "$OUT" 'RESTORE_CAPABILITY=none'
INCOMPLETE_HELP_AUDIT_DIR="$TEST_TMP/audit-incomplete-help"
FAKE_CMD_PACKAGE_HELP='install-existing --user' FAKE_PM_HELP='install-existing --user' \
  run_tool --output "$INCOMPLETE_HELP_AUDIT_DIR" audit || fail "incomplete help audit failed: $ERR"
assert_contains "$OUT" 'RESTORE_CAPABILITY=none'
NON_USAGE_HELP_AUDIT_DIR="$TEST_TMP/audit-non-usage-help"
FAKE_CMD_PACKAGE_HELP='install-existing --user USER_ID explanatory-text' \
  FAKE_PM_HELP='install-existing --user USER_ID explanatory-text' \
  run_tool --output "$NON_USAGE_HELP_AUDIT_DIR" audit || fail "non-usage help audit failed: $ERR"
assert_contains "$OUT" 'RESTORE_CAPABILITY=none'
TRAILING_PROSE_HELP_AUDIT_DIR="$TEST_TMP/audit-trailing-prose-help"
FAKE_CMD_PACKAGE_HELP='install-existing --user USER_ID PACKAGE explanatory-text' \
  FAKE_PM_HELP='install-existing --user USER_ID PACKAGE explanatory-text' \
  run_tool --output "$TRAILING_PROSE_HELP_AUDIT_DIR" audit || fail "trailing prose help audit failed: $ERR"
assert_contains "$OUT" 'RESTORE_CAPABILITY=none'

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

# Break caught: accepting a fetch from a different Wolf artifact URL.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-url.log" \
FAKE_WOLF_CURL_EXPECTED_URL='https://example.invalid/WolfLauncher.apk' \
  run_wolf && fail 'Wolf accepted a different download URL'
assert_wolf_not_installed

# Break caught: trusting an artifact whose byte length differs from the pin.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-size.log" FAKE_WOLF_SIZE=3272500 \
  run_wolf && fail 'Wolf accepted a different byte count'
assert_wolf_not_installed
assert_wolf_download_removed

# Break caught: trusting artifact bytes that do not match the pinned SHA-256.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-hash.log" FAKE_WOLF_HASH=00 \
  run_wolf && fail 'Wolf accepted a different APK hash'
assert_wolf_not_installed
assert_wolf_download_removed

# Break caught: installing an APK with a different package identity.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-package.log" FAKE_WOLF_PACKAGE=com.example.wolf \
  run_wolf && fail 'Wolf accepted a different package'
assert_wolf_not_installed
assert_wolf_download_removed

# Break caught: installing a different Wolf version code.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-version-code.log" FAKE_WOLF_VERSION_CODE=11900121 \
  run_wolf && fail 'Wolf accepted a different version code'
assert_wolf_not_installed

# Break caught: installing a different Wolf version name.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-version-name.log" FAKE_WOLF_VERSION_NAME=0.1.9-other \
  run_wolf && fail 'Wolf accepted a different version name'
assert_wolf_not_installed

# Break caught: accepting an APK incompatible with the API-25 target.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-min-sdk-low.log" FAKE_WOLF_MIN_SDK=20 \
  run_wolf && fail 'Wolf accepted a lower minSdk'
assert_wolf_not_installed
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-min-sdk-high.log" FAKE_WOLF_MIN_SDK=22 \
  run_wolf && fail 'Wolf accepted a higher minSdk'
assert_wolf_not_installed

# Break caught: accepting a different target SDK or install location.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-target-sdk.log" FAKE_WOLF_TARGET_SDK=28 \
  run_wolf && fail 'Wolf accepted a different targetSdk'
assert_wolf_not_installed
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-location.log" FAKE_WOLF_INSTALL_LOCATION=auto \
  run_wolf && fail 'Wolf accepted a different install location'
assert_wolf_not_installed

# Break caught: launching a package activity other than Wolf's launcher entry point.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-activity.log" FAKE_WOLF_ACTIVITY=.other.Activity \
  run_wolf && fail 'Wolf accepted a different launchable activity'
assert_wolf_not_installed

# Break caught: accepting an APK without either required signature scheme.
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-v1.log" FAKE_WOLF_V1=false \
  run_wolf && fail 'Wolf accepted a missing v1 signature'
assert_wolf_not_installed
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-v2.log" FAKE_WOLF_V2=false \
  run_wolf && fail 'Wolf accepted a missing v2 signature'
assert_wolf_not_installed

# Break caught: replacing a signed launcher when signer continuity is broken.
WOLF_SIGNER_STATE="$TEST_TMP/wolf-signer-state"
printf '%s\n' '11723945 0.1.7-FireTV' > "$WOLF_SIGNER_STATE"
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-signer.log" FAKE_WOLF_STATE="$WOLF_SIGNER_STATE" \
FAKE_WOLF_SIGNER=00 run_wolf && fail 'Wolf accepted a different signing certificate'
assert_wolf_not_installed
[ "$(cat "$WOLF_SIGNER_STATE")" = '11723945 0.1.7-FireTV' ] || fail 'signer mismatch replaced the existing launcher'

# Break caught: omitting -r or accepting an upgrade without exact final identity.
WOLF_UPGRADE_STATE="$TEST_TMP/wolf-upgrade-state"
printf '%s\n' '11723945 0.1.7-FireTV' > "$WOLF_UPGRADE_STATE"
reset_wolf_fixture
FAKE_WOLF_CURL_LOG="$TEST_TMP/wolf-curl-upgrade.log" FAKE_WOLF_STATE="$WOLF_UPGRADE_STATE" run_wolf ||
  fail "Wolf upgrade fixture failed: $ERR"
assert_contains "$OUT" 'WOLF_PREVIOUS_VERSION_CODE=11723945'
assert_contains "$OUT" 'WOLF_PREVIOUS_VERSION_NAME=0.1.7-FireTV'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'install -r '
[ "$(cat "$WOLF_UPGRADE_STATE")" = '11900120 0.1.9-Wolf' ] || fail 'Wolf upgrade did not finish at the pinned identity'
assert_wolf_download_removed

python3 -B "$ROOT/tests/verify-manifests.py" "$ROOT/manifests"
python3 -B "$ROOT/tests/test-atomic-rename.py"

printf '%s\n' 'PASS: target gate tests'
