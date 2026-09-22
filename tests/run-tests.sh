#!/bin/sh
set -eu

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mantis-tool-tests.XXXXXX")
ROOT="$TEST_TMP/repository"
cp -R "$SOURCE_ROOT" "$ROOT"
MANIFEST_REMOVE="$ROOT/manifests/remove-user0.txt"
MANIFEST_ROOT="$ROOT/manifests/disable-root-packages.txt"
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
unset FAKE_SERVICE_ADB_TCP_PORT FAKE_PERSIST_ADB_TCP_PORT FAKE_ADBD_PID FAKE_INIT_SVC_ADBD FAKE_ALWAYS_ON_VPN_APP
unset FAKE_ALWAYS_ON_VPN_LOCKDOWN FAKE_PACKAGE_STATE FAKE_DISABLE_MODE FAKE_DISABLE_FAIL_PACKAGE
unset FAKE_ADB_DRAIN_STDIN
unset FAKE_AFTER_DISABLE_ADB_ENABLED FAKE_DISABLE_RESULT FAKE_AFTER_DISABLE_PERSIST_ADB_TCP_PORT
unset FAKE_AFTER_DISABLE_ADB_ENABLED_AFTER_COUNT FAKE_ENABLE_FAIL_PACKAGE
unset FAKE_ENABLE_INTERRUPT_MARKER FAKE_ENABLE_ERROR_AFTER_STATE_PACKAGE FAKE_AFTER_ENABLE_BLUETOOTH_ON
unset FAKE_HOME_RESOLVER FAKE_HOME_RESOLVER_VERBOSE FAKE_AFTER_DISABLE_HOME_RESOLVER FAKE_INTERRUPT_MARKER FAKE_NETSTAT
unset FAKE_SETTINGS_ROUTES_VERBOSE FAKE_AFTER_DISABLE_SETTINGS_ROUTE_ACTION FAKE_AFTER_DISABLE_SETTINGS_ROUTE_VALUE
unset FAKE_AFTER_ENABLE_SETTINGS_ROUTE_ACTION FAKE_AFTER_ENABLE_SETTINGS_ROUTE_VALUE
unset FAKE_HUD_SETTINGS_TILE FAKE_HUD_POST_SELECT_FOCUS FAKE_ROOT_START_RESULT FAKE_ROOT_FOCUS
unset FAKE_ROOT_REQUIRES_CLEAR_TOP FAKE_ROOT_IGNORE_CLEAR_TOP
unset FAKE_STOCK_MENU_STATUS0_ACTION FAKE_STOCK_MENU_WRONG_ERROR_ACTION
unset FAKE_KEY176_NOOP FAKE_LONGPRESS3_NOOP
unset FAKE_CMD_PACKAGE_HELP FAKE_PM_HELP FAKE_PM_HELP_STATUS FAKE_PACKAGES_ACTIVE FAKE_PACKAGES_UNINSTALLED FAKE_PACKAGES_DISABLED
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

run_verify() {
  : > "$FAKE_ADB_LOG"
  if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial test-host:5555 --baseline "$VERIFY_BASELINE" verify >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
    STATUS=0
  else
    STATUS=$?
  fi
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

run_verify_settings() {
  : > "$FAKE_ADB_LOG"
  FAKE_UI_STATE="$TEST_TMP/ui-state"
  export FAKE_UI_STATE
  rm -f "$FAKE_UI_STATE"
  if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial test-host:5555 verify-settings >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
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
  rm -f "$FAKE_INTERRUPT_MARKER"
  if wait "$TOOL_PID"; then
    STATUS=0
  else
    STATUS=$?
  fi
  OUT=$(cat "$TEST_TMP/out")
  ERR=$(cat "$TEST_TMP/err")
  return "$STATUS"
}

run_wolf() {
  LAST_WOLF_CURL_LOG=$FAKE_WOLF_CURL_LOG
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
  unset LAST_WOLF_CURL_LOG
}

prepare_package_state() {
  unset FAKE_BLUETOOTH_ON FAKE_PERSIST_SYS_LOCALE FAKE_SYSTEM_LOCALES
  unset FAKE_ADB_DRAIN_STDIN
  unset FAKE_ADB_ENABLED FAKE_DEVELOPMENT_SETTINGS_ENABLED FAKE_INIT_SVC_ADBD FAKE_ADBD_PID
  unset FAKE_PERSIST_USB_CONFIG FAKE_SYS_USB_CONFIG FAKE_SERVICE_ADB_TCP_PORT FAKE_PERSIST_ADB_TCP_PORT
  unset FAKE_ADB_STATE FAKE_ALWAYS_ON_VPN_APP FAKE_ALWAYS_ON_VPN_LOCKDOWN FAKE_TUN0
  unset FAKE_SETTINGS_ROUTE_ACTION FAKE_SETTINGS_ROUTE_VALUE FAKE_UI_EMPTY_ACTION FAKE_UI_STATE
  unset FAKE_CURRENT_FOCUS FAKE_WOLF_FOCUS_DELAY FAKE_WOLF_FOCUS_DELAY_FILE FAKE_NETWORK_MODEL FAKE_NETWORK_SERIAL FAKE_SERIALNO
  unset FAKE_HUD_SETTINGS_TILE FAKE_HUD_POST_SELECT_FOCUS FAKE_ROOT_START_RESULT FAKE_ROOT_FOCUS
  unset FAKE_ROOT_REQUIRES_CLEAR_TOP FAKE_ROOT_IGNORE_CLEAR_TOP
  unset FAKE_STOCK_MENU_STATUS0_ACTION FAKE_STOCK_MENU_WRONG_ERROR_ACTION
  unset FAKE_KEY176_NOOP FAKE_LONGPRESS3_NOOP
  unset FAKE_WOLF_STATE FAKE_WOLF_INSTALLED_VERSION_CODE FAKE_WOLF_INSTALLED_VERSION_NAME
  unset FAKE_WOLF_DUMPSYS_INDENT
  FAKE_PACKAGE_STATE=$TEST_TMP/package-state
  export FAKE_PACKAGE_STATE
  : > "$FAKE_PACKAGE_STATE"
  rm -f "$FAKE_PACKAGE_STATE.enable-occurred"
  for preserve_manifest in "$ROOT/manifests/preserve-core.txt" "$ROOT/manifests/preserve-user-apps.txt"; do
    while IFS= read -r package; do
      printf 'active %s\n' "$package" >> "$FAKE_PACKAGE_STATE"
    done < "$preserve_manifest"
  done
  printf '%s\n' 'active com.amazon.android.marketplace' 'active com.amazon.bueller.music' >> "$FAKE_PACKAGE_STATE"
  unset FAKE_DISABLE_MODE FAKE_DISABLE_FAIL_PACKAGE FAKE_AFTER_DISABLE_ADB_ENABLED FAKE_DISABLE_RESULT
  unset FAKE_AFTER_DISABLE_PERSIST_ADB_TCP_PORT FAKE_AFTER_DISABLE_ADB_ENABLED_AFTER_COUNT FAKE_ENABLE_FAIL_PACKAGE
  unset FAKE_ENABLE_INTERRUPT_MARKER FAKE_ENABLE_ERROR_AFTER_STATE_PACKAGE FAKE_AFTER_ENABLE_BLUETOOTH_ON
  unset FAKE_REQUIRED_JOURNAL FAKE_REQUIRED_JOURNAL_RESULT
  unset FAKE_CMD_PACKAGE_HELP FAKE_PM_HELP FAKE_PM_HELP_STATUS
  unset FAKE_HOME_RESOLVER FAKE_HOME_RESOLVER_VERBOSE FAKE_AFTER_DISABLE_HOME_RESOLVER FAKE_INTERRUPT_MARKER FAKE_NETSTAT
  unset FAKE_SETTINGS_ROUTES_VERBOSE FAKE_AFTER_DISABLE_SETTINGS_ROUTE_ACTION FAKE_AFTER_DISABLE_SETTINGS_ROUTE_VALUE
  unset FAKE_AFTER_ENABLE_SETTINGS_ROUTE_ACTION FAKE_AFTER_ENABLE_SETTINGS_ROUTE_VALUE
}

[ "$(wc -l < "$MANIFEST_REMOVE" | tr -d ' ')" = 30 ] || fail 'remove-user0.txt must contain exactly 30 packages'
assert_contains "$(cat "$ROOT/manifests/preserve-core.txt")" 'com.amazon.ftvads.deeplinking'
assert_not_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.ftvads.deeplinking'
assert_contains "$(cat "$ROOT/manifests/preserve-core.txt")" 'com.amazon.tv.csapp'
assert_not_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.tv.csapp'
assert_not_contains "$(cat "$ROOT/manifests/preserve-core.txt")" 'com.amazon.venezia'
assert_not_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.venezia'
assert_contains "$(cat "$MANIFEST_ROOT")" 'com.amazon.venezia'
assert_contains "$(cat "$MANIFEST_ROOT")" 'com.imdb.livingroom.firetv'
assert_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.imdb.tv.android.app'
assert_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.ssm'
assert_contains "$(cat "$ROOT/manifests/preserve-core.txt")" 'com.amazon.vizzini.ftvcds'
assert_not_contains "$(cat "$MANIFEST_REMOVE")" 'com.amazon.vizzini.ftvcds'

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
  wolf_download=$(sed -n 's/^output=//p' "$LAST_WOLF_CURL_LOG")
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
VERIFY_BASELINE=$AUDIT_DIR
assert_file "$AUDIT_DIR/device.txt"
assert_file "$AUDIT_DIR/packages-enabled.txt"
assert_file "$AUDIT_DIR/packages-disabled.txt"
assert_file "$AUDIT_DIR/protected-apps.txt"
assert_file "$AUDIT_DIR/restore-user0.sh"
assert_file "$AUDIT_DIR/restore-journal.txt"
assert_file "$AUDIT_DIR/SHA256SUMS"
sh -n "$AUDIT_DIR/restore-user0.sh" || fail 'generated restore script is invalid shell'
verify_checksums "$AUDIT_DIR" || fail 'audit checksum verification failed'
assert_contains "$OUT" 'PACKAGE_OPERATION=pm disable-user --user 0'
assert_contains "$OUT" 'PACKAGE_RESTORE=pm enable --user 0'
assert_contains "$OUT" 'AUDIT=PASS'
assert_contains "$(cat "$AUDIT_DIR/device.txt")" 'persist.sys.locale=en-US'
assert_contains "$(cat "$AUDIT_DIR/device.txt")" 'system_locales=en-US'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.SETTINGS=com.amazon.tv.launcher/.ui.SettingsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.WIFI_SETTINGS=com.amazon.tv.settings.v2/.tv.network.NetworkActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.MANAGE_APPLICATIONS_SETTINGS=com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.CONTROLLERS_SETTINGS=com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.DEVICE_INFO_SETTINGS=com.amazon.tv.settings.v2/.tv.device.DeviceActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.ACCESSIBILITY_SETTINGS=com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.DISPLAY_SETTINGS=com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'com.amazon.device.settings.action.DATE_TIME=com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'com.amazon.device.settings.action.LANGUAGE=com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity'
assert_contains "$(cat "$AUDIT_DIR/settings-route-resolvers.txt")" 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS=com.amazon.tv.settings.v2/.tv.device.DeviceActivity'
assert_contains "$(cat "$AUDIT_DIR/home-resolver.txt")" 'com.amazon.tv.launcher/.HomeActivity'
assert_contains "$(cat "$AUDIT_DIR/bluetooth.txt")" 'bluetooth_on=1'
assert_contains "$(cat "$AUDIT_DIR/tun0.txt")" 'tun0:'
BASELINE_CONTENT=$(cat "$AUDIT_DIR/verification-baseline.txt")
assert_contains "$BASELINE_CONTENT" 'bluetooth_on=1'
assert_contains "$BASELINE_CONTENT" 'adb_enabled=1'
assert_contains "$BASELINE_CONTENT" 'development_settings_enabled=null'
assert_contains "$BASELINE_CONTENT" 'persist.sys.usb.config=mtp,adb'
assert_contains "$BASELINE_CONTENT" 'sys.usb.config=mtp,adb'
assert_contains "$BASELINE_CONTENT" 'service.adb.tcp.port=5555'
assert_contains "$BASELINE_CONTENT" 'init.svc.adbd=running'
assert_contains "$BASELINE_CONTENT" 'always_on_vpn_app=com.wireguard.android'
assert_contains "$BASELINE_CONTENT" 'tun0=present'

# Break caught: the real adb client may consume inherited stdin. Every ADB
# process must see /dev/null so route pipelines cannot be truncated.
DRAIN_STDIN_AUDIT_DIR="$TEST_TMP/audit-draining-adb"
FAKE_ADB_DRAIN_STDIN=yes run_tool --output "$DRAIN_STDIN_AUDIT_DIR" audit ||
  fail "audit allowed adb to drain its ten-route pipeline: $ERR"
[ "$(wc -l < "$DRAIN_STDIN_AUDIT_DIR/settings-route-resolvers.txt" | tr -d ' ')" = 10 ] ||
  fail 'audit did not capture all ten Settings routes with stdin-draining adb'
VERIFY_BASELINE=$DRAIN_STDIN_AUDIT_DIR
prepare_package_state
set_wolf_ready
FAKE_ADB_DRAIN_STDIN=yes run_verify ||
  fail "verify failed with stdin-draining adb: $ERR"
[ "$(awk '/shell cmd package resolve-activity --brief -a (android.settings|com.amazon.device.settings)/ { count++ } END { print count + 0 }' "$FAKE_ADB_LOG")" = 10 ] ||
  fail 'verify did not check all ten Settings routes with stdin-draining adb'
FAKE_ADB_DRAIN_STDIN=yes run_verify_settings ||
  fail "verify-settings failed with stdin-draining adb: $ERR"
[ "$(awk '/shell cmd package resolve-activity --brief -a (android.settings|com.amazon.device.settings)/ { count++ } END { print count + 0 }' "$FAKE_ADB_LOG")" = 10 ] ||
  fail 'verify-settings did not check all ten routes with stdin-draining adb'
unset FAKE_ADB_DRAIN_STDIN
VERIFY_BASELINE=$AUDIT_DIR

# Break caught: real Fire OS Settings resolvers emit strict metadata followed
# by the component. Audit must keep raw evidence separately while the guarded,
# checksummed route map contains exactly one parsed component per action.
VERBOSE_SETTINGS_AUDIT_DIR="$TEST_TMP/audit-settings-verbose"
FAKE_SETTINGS_ROUTES_VERBOSE=yes run_tool --output "$VERBOSE_SETTINGS_AUDIT_DIR" audit ||
  fail "verbose Settings audit failed: $ERR"
VERIFY_BASELINE=$VERBOSE_SETTINGS_AUDIT_DIR
prepare_package_state
set_wolf_ready
FAKE_SETTINGS_ROUTES_VERBOSE=yes run_verify ||
  fail "verify rejected production-shaped Settings resolvers: $ERR"
FAKE_SETTINGS_ROUTES_VERBOSE=yes run_verify_settings ||
  fail "verify-settings rejected production-shaped Settings resolvers: $ERR"
assert_file "$VERBOSE_SETTINGS_AUDIT_DIR/settings-route-resolvers.raw.txt"
assert_contains "$(cat "$VERBOSE_SETTINGS_AUDIT_DIR/settings-route-resolvers.raw.txt")" \
  'android.settings.SETTINGS|priority=100 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false'
assert_contains "$(cat "$VERBOSE_SETTINGS_AUDIT_DIR/settings-route-resolvers.raw.txt")" \
  'android.settings.WIFI_SETTINGS|com.amazon.tv.settings.v2/.tv.network.NetworkActivity'
assert_contains "$(cat "$VERBOSE_SETTINGS_AUDIT_DIR/settings-route-resolvers.txt")" \
  'android.settings.SETTINGS=com.amazon.tv.launcher/.ui.SettingsActivity'
assert_not_contains "$(cat "$VERBOSE_SETTINGS_AUDIT_DIR/settings-route-resolvers.txt")" 'priority='
verify_checksums "$VERBOSE_SETTINGS_AUDIT_DIR" || fail 'verbose Settings audit checksums failed'
VERIFY_BASELINE=$AUDIT_DIR

# Break caught: resolver metadata is a closed grammar and cannot carry a
# foreign action, prose, missing component, or multiple components.
bad_settings_index=0
for bad_settings_resolver in \
  'priority=100 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false' \
  'android.settings.SETTINGS=com.amazon.tv.launcher/.ui.SettingsActivity
com.amazon.tv.launcher/.ui.SettingsActivity' \
  'unparsed diagnostic prose
com.amazon.tv.launcher/.ui.SettingsActivity' \
  'com.amazon.tv.launcher/.ui.SettingsActivity
com.amazon.tv.launcher/.ui.SettingsActivity'
do
  bad_settings_index=$((bad_settings_index + 1))
  BAD_SETTINGS_AUDIT_DIR="$TEST_TMP/audit-settings-bad-$bad_settings_index"
  if FAKE_SETTINGS_ROUTE_ACTION=android.settings.SETTINGS \
    FAKE_SETTINGS_ROUTE_VALUE="$bad_settings_resolver" \
    run_tool --output "$BAD_SETTINGS_AUDIT_DIR" audit
  then
    fail 'audit accepted malformed or ambiguous Settings resolver output'
  fi
  assert_contains "$ERR" 'Settings resolver'
done
unset FAKE_SETTINGS_ROUTE_ACTION FAKE_SETTINGS_ROUTE_VALUE

# Break caught: the live resolver is verbose and names the stock vNext HOME.
# The exact parsed component, not a stale hard-code, is the checksummed guard.
VERBOSE_HOME_AUDIT_DIR="$TEST_TMP/audit-home-verbose"
FAKE_HOME_RESOLVER_VERBOSE=yes run_tool --output "$VERBOSE_HOME_AUDIT_DIR" audit ||
  fail "verbose HOME audit failed: $ERR"
VERIFY_BASELINE=$VERBOSE_HOME_AUDIT_DIR
prepare_package_state
set_wolf_ready
FAKE_HOME_RESOLVER_VERBOSE=yes run_verify ||
  fail "verify rejected the production-shaped HOME resolver: $ERR"
assert_contains "$(cat "$VERBOSE_HOME_AUDIT_DIR/home-resolver.txt")" 'priority=950 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true'
assert_contains "$(cat "$VERBOSE_HOME_AUDIT_DIR/home-resolver.txt")" 'com.amazon.tv.launcher/.ui.HomeActivity_vNext'
assert_contains "$(cat "$VERBOSE_HOME_AUDIT_DIR/verification-baseline.txt")" 'home_resolver_component=com.amazon.tv.launcher/.ui.HomeActivity_vNext'
verify_checksums "$VERBOSE_HOME_AUDIT_DIR" || fail 'verbose HOME audit checksums failed'
unset FAKE_HOME_RESOLVER_VERBOSE
if run_verify; then
  fail 'verify accepted a HOME component that drifted from its audit baseline'
fi
assert_contains "$ERR" 'guard HOME resolver expected=com.amazon.tv.launcher/.ui.HomeActivity_vNext actual=com.amazon.tv.launcher/.HomeActivity'
VERIFY_BASELINE=$AUDIT_DIR

FOREIGN_HOME_AUDIT_DIR="$TEST_TMP/audit-home-foreign"
if FAKE_HOME_RESOLVER=com.example.launcher/.Home run_tool --output "$FOREIGN_HOME_AUDIT_DIR" audit; then
  fail 'audit accepted a non-Amazon HOME resolver'
fi
assert_contains "$ERR" 'HOME resolver'
MISSING_HOME_AUDIT_DIR="$TEST_TMP/audit-home-missing"
if FAKE_HOME_RESOLVER='priority=950 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true' \
  run_tool --output "$MISSING_HOME_AUDIT_DIR" audit; then
  fail 'audit accepted HOME metadata without a component'
fi
assert_contains "$ERR" 'HOME resolver'
AMBIGUOUS_HOME_AUDIT_DIR="$TEST_TMP/audit-home-ambiguous"
if FAKE_HOME_RESOLVER='com.amazon.tv.launcher/.HomeActivity
com.amazon.tv.launcher/.ui.HomeActivity_vNext' \
  run_tool --output "$AMBIGUOUS_HOME_AUDIT_DIR" audit; then
  fail 'audit accepted ambiguous HOME components'
fi
assert_contains "$ERR" 'HOME resolver'
MALFORMED_HOME_AUDIT_DIR="$TEST_TMP/audit-home-malformed"
if FAKE_HOME_RESOLVER='unparsed diagnostic prose
com.amazon.tv.launcher/.ui.HomeActivity_vNext' \
  run_tool --output "$MALFORMED_HOME_AUDIT_DIR" audit; then
  fail 'audit accepted malformed HOME resolver output'
fi
assert_contains "$ERR" 'HOME resolver'
unset FAKE_HOME_RESOLVER

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

# Break caught: accepting only one half of the disable/enable capability pair.
PM_AUDIT_DIR="$TEST_TMP/audit-pm"
FAKE_PM_HELP='disable-user [--user USER_ID] PACKAGE_OR_COMPONENT
enable [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$PM_AUDIT_DIR" audit || fail "pm capability audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=pm disable-user --user 0'
assert_contains "$OUT" 'PACKAGE_RESTORE=pm enable --user 0'
PM_NONZERO_AUDIT_DIR="$TEST_TMP/audit-pm-nonzero"
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='pm enable [--user USER_ID] PACKAGE_OR_COMPONENT
pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$PM_NONZERO_AUDIT_DIR" audit || fail "nonzero pm capability audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=pm disable-user --user 0'
assert_contains "$OUT" 'PACKAGE_RESTORE=pm enable --user 0'
PM_NONZERO_OFFLINE_AUDIT_DIR="$TEST_TMP/audit-pm-nonzero-offline"
FAKE_ADB_STATE=offline \
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='pm enable [--user USER_ID] PACKAGE_OR_COMPONENT
pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$PM_NONZERO_OFFLINE_AUDIT_DIR" audit || fail "offline nonzero pm audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
PM_UNEXPECTED_STATUS_AUDIT_DIR="$TEST_TMP/audit-pm-unexpected-status"
FAKE_PM_HELP_STATUS=2 \
FAKE_PM_HELP='pm enable [--user USER_ID] PACKAGE_OR_COMPONENT
pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$PM_UNEXPECTED_STATUS_AUDIT_DIR" audit || fail "unexpected-status pm audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
prepare_package_state
set_wolf_ready
awk '
  $1 == "active" && ($2 == "com.amazon.android.marketplace" || $2 == "com.amazon.bueller.music") { print "disabled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
printf '%s\n' com.amazon.android.marketplace com.amazon.bueller.music > "$PM_AUDIT_DIR/disabled-successfully.txt"
refresh_checksums "$PM_AUDIT_DIR"
: > "$FAKE_ADB_LOG"
SERIAL=test-host:5555 ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err" ||
  fail "generated pm restore failed: $(cat "$TEST_TMP/restore-err")"
RESTORE_LOG=$(cat "$FAKE_ADB_LOG")
assert_contains "$RESTORE_LOG" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$RESTORE_LOG" 'shell pm enable --user 0 com.amazon.android.marketplace'
case "$RESTORE_LOG" in
  *com.example.removed*) fail 'restore used the package inventory instead of the successful-disable journal' ;;
esac
# Break caught: the generated recovery wrapper must be safely resumable after
# its shared controller has already emptied the restore ledger.
: > "$FAKE_ADB_LOG"
SERIAL=test-host:5555 ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err" ||
  fail "generated restore wrapper was not idempotent after completion: $(cat "$TEST_TMP/restore-err")"
assert_contains "$(cat "$TEST_TMP/restore-out")" 'RESTORE=PASS'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0'

# Break caught: recomputing checksums must not expand the generated script's
# embedded candidate-package boundary.
printf '%s\n' com.example.untrusted > "$PM_AUDIT_DIR/disabled-successfully.txt"
refresh_checksums "$PM_AUDIT_DIR"
: > "$FAKE_ADB_LOG"
if SERIAL=test-host:5555 ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err"; then
  fail 'generated restore accepted a non-manifest package'
fi
assert_contains "$(cat "$TEST_TMP/restore-err")" 'invalid recorded package'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0'
: > "$FAKE_ADB_LOG"
if FAKE_RELEASE=7.1.3 SERIAL=test-host:5555 ADB="$ROOT/tests/fixtures/adb" "$PM_AUDIT_DIR/restore-user0.sh" >"$TEST_TMP/restore-out" 2>"$TEST_TMP/restore-err"; then
  fail 'restore accepted a different Android release'
fi
assert_contains "$(cat "$TEST_TMP/restore-err")" 'release expected=7.1.2 actual=7.1.3'
case "$(cat "$FAKE_ADB_LOG")" in
  *'pm enable'*) fail 'restore attempted enable on a mismatched target' ;;
esac

# Break caught: planning a disable must expose the exact inverse without changing user 0.
PACKAGE_ORIGINAL_REMOVE="$TEST_TMP/remove-user0-package-operations.txt"
cp "$MANIFEST_REMOVE" "$PACKAGE_ORIGINAL_REMOVE"
printf '%s\n' com.amazon.android.marketplace com.amazon.bueller.music > "$MANIFEST_REMOVE"
prepare_package_state
set_wolf_ready
run_tool plan || fail "plan failed for valid package operations: $ERR"
assert_contains "$OUT" 'DISABLE=com.amazon.android.marketplace RESTORE=pm enable --user 0 com.amazon.android.marketplace'
assert_contains "$OUT" 'DISABLE=com.amazon.bueller.music RESTORE=pm enable --user 0 com.amazon.bueller.music'
assert_contains "$OUT" 'PACKAGE_OPERATION=pm disable-user --user 0'
assert_not_contains "$OUT" 'com.amazon.ftvads.deeplinking'
assert_not_contains "$OUT" 'com.amazon.tv.csapp'
assert_not_contains "$OUT" 'com.amazon.venezia'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0'

# Break caught: package manifests and restore ledgers are controller input, not
# adb input. A draining adb must not truncate apply, rollback, or restore loops.
PACKAGE_DRAIN_STDIN_DIR="$TEST_TMP/apply-draining-adb"
prepare_package_state
set_wolf_ready
FAKE_ADB_DRAIN_STDIN=yes \
  run_tool --output "$PACKAGE_DRAIN_STDIN_DIR" --yes apply ||
  fail "apply allowed adb to drain its package manifest: $ERR"
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm disable-user --user 0 com.amazon.android.marketplace'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm disable-user --user 0 com.amazon.bueller.music'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0 com.amazon.ftvads.deeplinking'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0 com.amazon.tv.csapp'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0 com.amazon.venezia'
[ "$(wc -l < "$PACKAGE_DRAIN_STDIN_DIR/disabled-successfully.txt" | tr -d ' ')" = 2 ] ||
  fail 'apply did not record both fixture packages with stdin-draining adb'
FAKE_ADB_DRAIN_STDIN=yes run_tool restore "$PACKAGE_DRAIN_STDIN_DIR" ||
  fail "restore allowed adb to drain its recovery ledger: $ERR"
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
[ ! -s "$PACKAGE_DRAIN_STDIN_DIR/disabled-successfully.txt" ] ||
  fail 'restore left a package in the ledger with stdin-draining adb'
unset FAKE_ADB_DRAIN_STDIN

PACKAGE_DRAIN_ROLLBACK_DIR="$TEST_TMP/rollback-draining-adb"
prepare_package_state
set_wolf_ready
FAKE_ADB_DRAIN_STDIN=yes \
FAKE_AFTER_DISABLE_ADB_ENABLED=0 \
FAKE_AFTER_DISABLE_ADB_ENABLED_AFTER_COUNT=2 \
  run_tool --output "$PACKAGE_DRAIN_ROLLBACK_DIR" --yes apply &&
  fail 'apply accepted the forced second-package guard failure'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
[ ! -s "$PACKAGE_DRAIN_ROLLBACK_DIR/disabled-successfully.txt" ] ||
  fail 'rollback left a package in the ledger with stdin-draining adb'
unset FAKE_ADB_DRAIN_STDIN

# Break caught: apply and fresh restore must carry the exact verbose HOME
# component through the checksummed baseline and compare it after every action.
PACKAGE_VERBOSE_HOME_DIR="$TEST_TMP/apply-home-verbose"
prepare_package_state
set_wolf_ready
FAKE_HOME_RESOLVER_VERBOSE=yes \
FAKE_SETTINGS_ROUTES_VERBOSE=yes \
  run_tool --output "$PACKAGE_VERBOSE_HOME_DIR" --yes apply ||
  fail "apply rejected production-shaped HOME/Settings resolvers: $ERR"
assert_contains "$(cat "$PACKAGE_VERBOSE_HOME_DIR/verification-baseline.txt")" 'home_resolver_component=com.amazon.tv.launcher/.ui.HomeActivity_vNext'
assert_contains "$(cat "$PACKAGE_VERBOSE_HOME_DIR/settings-route-resolvers.txt")" 'android.settings.WIFI_SETTINGS=com.amazon.tv.settings.v2/.tv.network.NetworkActivity'
FAKE_HOME_RESOLVER_VERBOSE=yes FAKE_SETTINGS_ROUTES_VERBOSE=yes \
  run_tool restore "$PACKAGE_VERBOSE_HOME_DIR" ||
  fail "restore rejected production-shaped HOME/Settings resolvers: $ERR"
assert_contains "$OUT" 'RESTORE=PASS'
unset FAKE_HOME_RESOLVER_VERBOSE FAKE_SETTINGS_ROUTES_VERBOSE

# Break caught: Fire OS returns status 1 for authoritative pm help usage. Exact
# disable/enable syntax still permits apply after a live transport check.
PACKAGE_NONZERO_HELP_DIR="$TEST_TMP/apply-nonzero-help"
prepare_package_state
set_wolf_ready
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='pm enable [--user USER_ID] PACKAGE_OR_COMPONENT
pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$PACKAGE_NONZERO_HELP_DIR" --yes apply ||
  fail "apply rejected exact nonzero pm usage: $ERR"
assert_contains "$OUT" 'APPLY=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'get-state'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm disable-user --user 0 com.amazon.android.marketplace'

# Break caught: a compact guard that omits any preserve manifest package can remove user apps after core recovery paths are already gone.
PACKAGE_TCOMM_GUARD_DIR="$TEST_TMP/apply-tcomm-guard"
prepare_package_state
awk '
  $1 == "active" && $2 == "com.amazon.tcomm" { print "disabled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
set_wolf_ready
if run_tool --output "$PACKAGE_TCOMM_GUARD_DIR" --yes apply; then
  fail 'apply accepted a missing mandatory preserve package'
fi
assert_contains "$ERR" 'guard missing enabled package: com.amazon.tcomm'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0'

# The exact-build packages retained by the ordinary shell-stage guard are
# operative inputs, not merely validator metadata. Venezia moves to the
# restorative root-only manifest instead.
for protected_platform_package in com.amazon.ftvads.deeplinking com.amazon.tv.csapp; do
  prepare_package_state
  awk -v package="$protected_platform_package" '
    $1 == "active" && $2 == package { print "disabled", $2; next }
    { print }
  ' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
  mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
  set_wolf_ready
  if run_tool --output "$TEST_TMP/apply-protected-platform-guard-${protected_platform_package##*.}" --yes apply; then
    fail "apply accepted disabled protected platform package: $protected_platform_package"
  fi
  assert_contains "$ERR" "guard missing enabled package: $protected_platform_package"
  assert_not_contains "$(cat "$FAKE_ADB_LOG")" "pm disable-user --user 0 $protected_platform_package"
done

# Break caught: any alternate HOME resolver can replace the stock recovery route.
PACKAGE_HOME_GUARD_DIR="$TEST_TMP/apply-home-guard"
prepare_package_state
set_wolf_ready
if FAKE_HOME_RESOLVER='com.example.launcher/.Home' run_tool --output "$PACKAGE_HOME_GUARD_DIR" --yes apply; then
  fail 'apply accepted a non-stock HOME resolver'
fi
assert_contains "$ERR" 'guard HOME resolver package expected=com.amazon.tv.launcher actual=com.example.launcher'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0'

# Break caught: a valid Amazon HOME component must remain byte-for-byte equal
# to the checksummed baseline after each package action.
PACKAGE_HOME_DRIFT_DIR="$TEST_TMP/apply-home-drift"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_HOME_RESOLVER=com.amazon.tv.launcher/.ui.HomeActivity_vNext \
  run_tool --output "$PACKAGE_HOME_DRIFT_DIR" --yes apply &&
  fail 'apply accepted HOME component drift after disable'
assert_contains "$ERR" 'guard HOME resolver expected=com.amazon.tv.launcher/.HomeActivity actual=com.amazon.tv.launcher/.ui.HomeActivity_vNext'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
verify_checksums "$PACKAGE_HOME_DRIFT_DIR" || fail 'HOME drift rollback left stale checksums'

# Break caught: Settings-route identity must be checked from the parsed audit
# baseline after every disable, and a mismatch must trigger inverse enable.
PACKAGE_SETTINGS_DRIFT_DIR="$TEST_TMP/apply-settings-drift"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_SETTINGS_ROUTE_ACTION=android.settings.WIFI_SETTINGS \
FAKE_AFTER_DISABLE_SETTINGS_ROUTE_VALUE=com.example.settings/.WifiActivity \
  run_tool --output "$PACKAGE_SETTINGS_DRIFT_DIR" --yes apply &&
  fail 'apply accepted Settings route drift after disable'
assert_contains "$ERR" 'Settings resolver changed from baseline expected=com.amazon.tv.settings.v2/.tv.network.NetworkActivity actual=com.example.settings/.WifiActivity action=android.settings.WIFI_SETTINGS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
verify_checksums "$PACKAGE_SETTINGS_DRIFT_DIR" || fail 'Settings drift rollback left stale checksums'

# Break caught: rollback cannot claim recovery when the Settings route remains
# changed after the inverse enable; the checksummed recovery ledger must stay.
PACKAGE_SETTINGS_ROLLBACK_DRIFT_DIR="$TEST_TMP/apply-settings-rollback-drift"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_SETTINGS_ROUTE_ACTION=android.settings.WIFI_SETTINGS \
FAKE_AFTER_DISABLE_SETTINGS_ROUTE_VALUE=com.example.settings/.DisabledWifiActivity \
FAKE_AFTER_ENABLE_SETTINGS_ROUTE_ACTION=android.settings.WIFI_SETTINGS \
FAKE_AFTER_ENABLE_SETTINGS_ROUTE_VALUE=com.example.settings/.EnabledWifiActivity \
  run_tool --output "$PACKAGE_SETTINGS_ROLLBACK_DRIFT_DIR" --yes apply &&
  fail 'apply accepted Settings drift through rollback'
assert_contains "$ERR" 'rollback incomplete'
assert_contains "$ERR" "$PACKAGE_SETTINGS_ROLLBACK_DRIFT_DIR"
assert_not_contains "$ERR" 'restored'
assert_contains "$(cat "$PACKAGE_SETTINGS_ROLLBACK_DRIFT_DIR/disabled-successfully.txt")" 'com.amazon.android.marketplace'
verify_checksums "$PACKAGE_SETTINGS_ROLLBACK_DRIFT_DIR" || fail 'Settings rollback drift left stale checksums'

# Break caught: accepting a successful command that leaves a package enabled.
PACKAGE_STILL_ACTIVE_DIR="$TEST_TMP/apply-still-active"
prepare_package_state
set_wolf_ready
FAKE_DISABLE_MODE=still-enabled run_tool --output "$PACKAGE_STILL_ACTIVE_DIR" --yes apply &&
  fail 'apply accepted a package that remained enabled'
assert_contains "$ERR" 'disable verification failed for com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_STILL_ACTIVE_DIR/operation-journal.txt")" 'attempt com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_STILL_ACTIVE_DIR/operation-journal.txt")" 'failure com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: an empty persistent TCP property is a valid captured baseline,
# but it must remain unchanged after every user-zero disable.
PACKAGE_EMPTY_PORT_DIR="$TEST_TMP/apply-empty-persist-port"
prepare_package_state
set_wolf_ready
FAKE_PERSIST_ADB_TCP_PORT= run_tool --output "$PACKAGE_EMPTY_PORT_DIR" --yes apply ||
  fail "apply rejected empty persistent TCP baseline: $ERR"
prepare_package_state
set_wolf_ready
PACKAGE_CHANGED_PORT_DIR="$TEST_TMP/apply-changed-persist-port"
if FAKE_PERSIST_ADB_TCP_PORT= FAKE_AFTER_DISABLE_PERSIST_ADB_TCP_PORT=5555 \
  run_tool --output "$PACKAGE_CHANGED_PORT_DIR" --yes apply; then
  fail 'apply accepted a changed persistent TCP port after disable'
fi
assert_contains "$ERR" 'guard changed persist_adb_tcp_port expected= actual=5555'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: a silent successful disable that has no state effect is rejected.
PACKAGE_NONLITERAL_DIR="$TEST_TMP/apply-nonliteral"
prepare_package_state
set_wolf_ready
FAKE_DISABLE_MODE=silent-no-effect run_tool --output "$PACKAGE_NONLITERAL_DIR" --yes apply &&
  fail 'apply accepted a silent disable with no state effect'
assert_contains "$ERR" 'disable verification failed for com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: a later disable error must restore the current batch in reverse order.
PACKAGE_ERROR_DIR="$TEST_TMP/apply-error"
prepare_package_state
set_wolf_ready
FAKE_DISABLE_FAIL_PACKAGE=com.amazon.bueller.music run_tool --output "$PACKAGE_ERROR_DIR" --yes apply &&
  fail 'apply accepted a failed disable'
assert_contains "$ERR" 'disable failed for com.amazon.bueller.music'
ERROR_LOG=$(cat "$FAKE_ADB_LOG")
assert_not_contains "$ERROR_LOG" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$ERROR_LOG" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: an already-disabled user-0 package must be skipped and omitted from rollback.
PACKAGE_ABSENT_DIR="$TEST_TMP/apply-absent"
prepare_package_state
awk '
  $1 == "active" && $2 == "com.amazon.android.marketplace" { print "disabled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
set_wolf_ready
run_tool --output "$PACKAGE_ABSENT_DIR" --yes apply || fail "apply failed for an already-disabled package: $ERR"
assert_contains "$(cat "$PACKAGE_ABSENT_DIR/operation-journal.txt")" 'skip com.amazon.android.marketplace'
assert_not_contains "$(cat "$PACKAGE_ABSENT_DIR/disabled-successfully.txt")" 'com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm disable-user --user 0 com.amazon.android.marketplace'

# Break caught: a disabled package must appear in the disabled package inventory.
PACKAGE_MISSING_U_DIR="$TEST_TMP/apply-missing-u"
prepare_package_state
set_wolf_ready
FAKE_DISABLE_MODE=missing-disabled run_tool --output "$PACKAGE_MISSING_U_DIR" --yes apply &&
  fail 'apply accepted a package missing from pm list packages -d'
assert_contains "$ERR" 'disable verification failed for com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: interruption recovery needs the attempt durable before adb, and each result before the next disable.
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

# Break caught: interruption after disable but before a success ledger entry must remain recoverable from its durable attempt.
PACKAGE_INTERRUPT_DIR="$TEST_TMP/apply-interrupted"
prepare_package_state
set_wolf_ready
FAKE_INTERRUPT_MARKER="$TEST_TMP/interrupt-after-disable" \
  run_tool_interrupted --output "$PACKAGE_INTERRUPT_DIR" --yes apply || true
assert_contains "$(cat "$PACKAGE_INTERRUPT_DIR/operation-journal.txt")" 'attempt com.amazon.android.marketplace'
assert_not_contains "$(cat "$PACKAGE_INTERRUPT_DIR/disabled-successfully.txt")" 'com.amazon.android.marketplace'
run_tool restore "$PACKAGE_INTERRUPT_DIR" || fail "restore did not reconcile an interrupted disable: $ERR"
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
assert_file "$PACKAGE_INTERRUPT_DIR/reconciliation-journal.txt"
assert_contains "$(cat "$PACKAGE_INTERRUPT_DIR/reconciliation-journal.txt")" 'reconciled com.amazon.android.marketplace'
verify_checksums "$PACKAGE_INTERRUPT_DIR" || fail 'interruption reconciliation left stale checksums'

# Break caught: interruption after pm enable changes state but before the
# successful-disable ledger is pruned must be resumable without a second enable.
PACKAGE_ENABLE_INTERRUPT_DIR="$TEST_TMP/restore-interrupted-enable"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_ENABLE_INTERRUPT_DIR" --yes apply || fail "apply failed for interrupted-enable test: $ERR"
ENABLE_INTERRUPT_MARKER="$TEST_TMP/interrupt-after-enable"
FAKE_INTERRUPT_MARKER="$ENABLE_INTERRUPT_MARKER" \
FAKE_ENABLE_INTERRUPT_MARKER="$ENABLE_INTERRUPT_MARKER" \
  run_tool_interrupted restore "$PACKAGE_ENABLE_INTERRUPT_DIR" || true
assert_contains "$(cat "$PACKAGE_ENABLE_INTERRUPT_DIR/restore-journal.txt")" 'attempt com.amazon.bueller.music'
assert_not_contains "$(cat "$PACKAGE_ENABLE_INTERRUPT_DIR/restore-journal.txt")" 'success com.amazon.bueller.music'
assert_contains "$(cat "$PACKAGE_ENABLE_INTERRUPT_DIR/disabled-successfully.txt")" 'com.amazon.bueller.music'
verify_checksums "$PACKAGE_ENABLE_INTERRUPT_DIR" || fail 'interrupted enable left stale backup checksums'
unset FAKE_INTERRUPT_MARKER FAKE_ENABLE_INTERRUPT_MARKER
run_tool restore "$PACKAGE_ENABLE_INTERRUPT_DIR" || fail "restore did not reconcile interrupted enable: $ERR"
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_ENABLE_INTERRUPT_DIR/restore-journal.txt")" 'reconciled-enabled com.amazon.bueller.music'
[ ! -s "$PACKAGE_ENABLE_INTERRUPT_DIR/disabled-successfully.txt" ] || fail 'interrupted-enable recovery did not empty the ledger'
verify_checksums "$PACKAGE_ENABLE_INTERRUPT_DIR" || fail 'interrupted-enable reconciliation left stale checksums'

# Break caught: pm enable can change state and still return nonzero. State and
# guards, not the command status alone, determine whether the inverse succeeded.
PACKAGE_ENABLE_NONZERO_DIR="$TEST_TMP/restore-enable-nonzero"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_ENABLE_NONZERO_DIR" --yes apply || fail "apply failed for nonzero-enable test: $ERR"
FAKE_ENABLE_ERROR_AFTER_STATE_PACKAGE=com.amazon.bueller.music \
  run_tool restore "$PACKAGE_ENABLE_NONZERO_DIR" || fail "restore rejected verified enable state after nonzero status: $ERR"
assert_contains "$(cat "$PACKAGE_ENABLE_NONZERO_DIR/restore-journal.txt")" 'success-after-error com.amazon.bueller.music'
[ ! -s "$PACKAGE_ENABLE_NONZERO_DIR/disabled-successfully.txt" ] || fail 'nonzero-enable recovery did not empty the ledger'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell cmd package resolve-activity --brief -a android.settings.WIFI_SETTINGS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'get-state'
awk '
  /pm enable --user 0/ {
    if (pending && !(packages && wolf && bluetooth && vpn && home && whisper && settings && usb_adb && network)) exit 1
    pending = 1
    packages = wolf = bluetooth = vpn = home = whisper = settings = usb_adb = network = 0
    next
  }
  pending && /pm list packages -e/ { packages = 1 }
  pending && /dumpsys package com.wolf.firelauncher/ { wolf = 1 }
  pending && /settings get global bluetooth_on/ { bluetooth = 1 }
  pending && /settings get secure always_on_vpn_app/ { vpn = 1 }
  pending && /resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME/ { home = 1 }
  pending && /netstat -ltn/ { whisper = 1 }
  pending && /resolve-activity --brief -a android.settings.WIFI_SETTINGS/ { settings = 1 }
  pending && /getprop sys.usb.config/ { usb_adb = 1 }
  pending && /get-state/ { network = 1 }
  END { exit !(pending && packages && wolf && bluetooth && vpn && home && whisper && settings && usb_adb && network) }
' "$FAKE_ADB_LOG" || fail 'restore did not run every guard category after each enable'

# Break caught: restore must reload the checksummed audit baseline and run the
# compact safety guard after each successful enable before pruning its ledger.
PACKAGE_RESTORE_GUARD_DIR="$TEST_TMP/restore-guard"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_RESTORE_GUARD_DIR" --yes apply || fail "apply failed for restore-guard test: $ERR"
if FAKE_AFTER_ENABLE_BLUETOOTH_ON=0 run_tool restore "$PACKAGE_RESTORE_GUARD_DIR"; then
  fail 'restore accepted Bluetooth drift after enable'
fi
assert_contains "$ERR" 'guard changed bluetooth_on expected=1 actual=0'
assert_contains "$(cat "$PACKAGE_RESTORE_GUARD_DIR/restore-journal.txt")" 'guard-failure com.amazon.bueller.music'
assert_contains "$(cat "$PACKAGE_RESTORE_GUARD_DIR/disabled-successfully.txt")" 'com.amazon.bueller.music'
awk '
  /pm enable --user 0 com.amazon.bueller.music/ { enabled = NR }
  /settings get global bluetooth_on/ { bluetooth = NR }
  END { exit !(enabled && bluetooth && enabled < bluetooth) }
' "$FAKE_ADB_LOG" || fail 'restore did not run Bluetooth guard after enable'
verify_checksums "$PACKAGE_RESTORE_GUARD_DIR" || fail 'restore guard failure left stale checksums'

# Break caught: fresh restore must load the checksummed parsed route baseline
# and retain its ledger when a route changes immediately after pm enable.
PACKAGE_RESTORE_SETTINGS_GUARD_DIR="$TEST_TMP/restore-settings-guard"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_RESTORE_SETTINGS_GUARD_DIR" --yes apply ||
  fail "apply failed for Settings restore-guard test: $ERR"
if FAKE_AFTER_ENABLE_SETTINGS_ROUTE_ACTION=android.settings.WIFI_SETTINGS \
  FAKE_AFTER_ENABLE_SETTINGS_ROUTE_VALUE=com.example.settings/.WifiActivity \
  run_tool restore "$PACKAGE_RESTORE_SETTINGS_GUARD_DIR"
then
  fail 'restore accepted Settings route drift after enable'
fi
assert_contains "$ERR" 'Settings resolver changed from baseline expected=com.amazon.tv.settings.v2/.tv.network.NetworkActivity actual=com.example.settings/.WifiActivity action=android.settings.WIFI_SETTINGS'
assert_contains "$(cat "$PACKAGE_RESTORE_SETTINGS_GUARD_DIR/restore-journal.txt")" 'guard-failure com.amazon.bueller.music'
assert_contains "$(cat "$PACKAGE_RESTORE_SETTINGS_GUARD_DIR/disabled-successfully.txt")" 'com.amazon.bueller.music'
verify_checksums "$PACKAGE_RESTORE_SETTINGS_GUARD_DIR" || fail 'Settings restore guard failure left stale checksums'

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
assert_contains "$RESTORE_LOG" 'shell pm enable --user 0 com.amazon.bueller.music'
assert_contains "$RESTORE_LOG" 'shell pm enable --user 0 com.amazon.android.marketplace'
awk '
  /pm enable --user 0 com.amazon.bueller.music/ { second = NR }
  /pm enable --user 0 com.amazon.android.marketplace/ { first = NR }
  END { exit !(second && first && second < first) }
' "$FAKE_ADB_LOG" || fail 'public restore did not use reverse order'

# Break caught: stale or tampered journals cannot be trusted for package installation.
PACKAGE_STALE_DIR="$TEST_TMP/apply-restore-stale"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_STALE_DIR" --yes apply || fail "apply failed for stale-journal test: $ERR"
printf '%s\n' com.example.untrusted > "$PACKAGE_STALE_DIR/disabled-successfully.txt"
if run_tool restore "$PACKAGE_STALE_DIR"; then
  fail 'restore accepted a journal whose SHA256SUMS did not match'
fi
assert_contains "$ERR" 'backup integrity verification failed'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm enable'

# Break caught: a checksummed backup from any other operation mode must not be
# interpreted as a disable/enable ledger, even if its checksums are recomputed.
PACKAGE_MODE_DIR="$TEST_TMP/apply-restore-mode"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_MODE_DIR" --yes apply || fail "apply failed for package-mode test: $ERR"
printf '%s\n' 'PACKAGE_OPERATION=unsupported' 'PACKAGE_RESTORE=unsupported' > "$PACKAGE_MODE_DIR/package-mode.txt"
refresh_checksums "$PACKAGE_MODE_DIR"
if run_tool restore "$PACKAGE_MODE_DIR"; then
  fail 'restore accepted a backup from a different package-operation mode'
fi
assert_contains "$ERR" 'backup package mode mismatch'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm enable'

# Break caught: public restore must not invoke enable for a ledger package that
# is no longer observed in the disabled inventory.
PACKAGE_PRECONDITION_DIR="$TEST_TMP/apply-restore-precondition"
prepare_package_state
set_wolf_ready
run_tool --output "$PACKAGE_PRECONDITION_DIR" --yes apply || fail "apply failed for restore-precondition test: $ERR"
awk '
  $1 == "disabled" && $2 == "com.amazon.android.marketplace" { print "active", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
if run_tool restore "$PACKAGE_PRECONDITION_DIR"; then
  fail 'public restore enabled a ledger package that was not disabled'
fi
assert_contains "$ERR" 'restore precondition failed for com.amazon.android.marketplace'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'

# Break caught: a wrong-device restore is refused before reconciliation or package installation.
if FAKE_RELEASE=7.1.3 run_tool restore "$PACKAGE_JOURNAL_DIR"; then
  fail 'public restore accepted the wrong device'
fi
assert_contains "$ERR" 'release expected=7.1.2 actual=7.1.3'
assert_not_contains "$(cat "$FAKE_ADB_LOG")" 'pm enable'
unset FAKE_RELEASE

# Break caught: losing ADB Debugging after a disable must trigger rollback while the transport remains live.
PACKAGE_ADB_GUARD_DIR="$TEST_TMP/apply-adb-guard"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_ADB_ENABLED=0 run_tool --output "$PACKAGE_ADB_GUARD_DIR" --yes apply &&
  fail 'apply accepted a changed adb_enabled setting'
assert_contains "$ERR" 'guard changed adb_enabled'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'get-state'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell pm enable --user 0 com.amazon.android.marketplace'
assert_contains "$(cat "$PACKAGE_ADB_GUARD_DIR/operation-journal.txt")" 'guard-failure com.amazon.android.marketplace'

# Break caught: apply must never claim the batch was restored when the inverse
# itself fails a compact guard. Keep the recovery ledger and publish its path.
PACKAGE_ROLLBACK_GUARD_DIR="$TEST_TMP/apply-rollback-guard"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_ADB_ENABLED=0 \
FAKE_AFTER_ENABLE_BLUETOOTH_ON=0 \
  run_tool --output "$PACKAGE_ROLLBACK_GUARD_DIR" --yes apply &&
  fail 'apply accepted a failed guard rollback'
assert_contains "$ERR" 'rollback incomplete'
assert_contains "$ERR" "$PACKAGE_ROLLBACK_GUARD_DIR"
assert_not_contains "$ERR" 'restored'
assert_not_contains "$ERR" 'reboot'
assert_contains "$(cat "$PACKAGE_ROLLBACK_GUARD_DIR/disabled-successfully.txt")" 'com.amazon.android.marketplace'
verify_checksums "$PACKAGE_ROLLBACK_GUARD_DIR" || fail 'failed guard rollback left stale checksums'

# Break caught: a partial rollback must remove each confirmed restore from the ledger and refresh the checksum before trying the next one.
PACKAGE_PARTIAL_ROLLBACK_DIR="$TEST_TMP/apply-partial-rollback"
prepare_package_state
set_wolf_ready
FAKE_AFTER_DISABLE_ADB_ENABLED=0 \
FAKE_AFTER_DISABLE_ADB_ENABLED_AFTER_COUNT=2 \
FAKE_ENABLE_FAIL_PACKAGE=com.amazon.android.marketplace \
  run_tool --output "$PACKAGE_PARTIAL_ROLLBACK_DIR" --yes apply && fail 'apply accepted a partial rollback'
PARTIAL_LEDGER=$(cat "$PACKAGE_PARTIAL_ROLLBACK_DIR/disabled-successfully.txt")
assert_contains "$PARTIAL_LEDGER" 'com.amazon.android.marketplace'
assert_not_contains "$PARTIAL_LEDGER" 'com.amazon.bueller.music'
verify_checksums "$PACKAGE_PARTIAL_ROLLBACK_DIR" || fail 'partial rollback left stale checksums'

clear_wolf_ready
unset FAKE_PACKAGE_STATE FAKE_REQUIRED_JOURNAL FAKE_REQUIRED_JOURNAL_RESULT
cp "$PACKAGE_ORIGINAL_REMOVE" "$MANIFEST_REMOVE"

# Break caught: treating prose or similarly named commands as disable/enable usage.
MISLEADING_AUDIT_DIR="$TEST_TMP/audit-misleading-help"
FAKE_PM_HELP='Use disable-user and enable --user only after a warning' \
  run_tool --output "$MISLEADING_AUDIT_DIR" audit || fail "misleading help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
INCOMPLETE_HELP_AUDIT_DIR="$TEST_TMP/audit-incomplete-help"
FAKE_PM_HELP='disable-user [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$INCOMPLETE_HELP_AUDIT_DIR" audit || fail "incomplete help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
NON_USAGE_HELP_AUDIT_DIR="$TEST_TMP/audit-non-usage-help"
FAKE_PM_HELP='disable-user --user USER_ID explanatory-text
enable --user USER_ID explanatory-text' \
  run_tool --output "$NON_USAGE_HELP_AUDIT_DIR" audit || fail "non-usage help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
TRAILING_PROSE_HELP_AUDIT_DIR="$TEST_TMP/audit-trailing-prose-help"
FAKE_PM_HELP='disable-user --user USER_ID PACKAGE_OR_COMPONENT explanatory-text
enable --user USER_ID PACKAGE_OR_COMPONENT explanatory-text' \
  run_tool --output "$TRAILING_PROSE_HELP_AUDIT_DIR" audit || fail "trailing prose help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
EMPTY_NONZERO_HELP_AUDIT_DIR="$TEST_TMP/audit-empty-nonzero-help"
FAKE_PM_HELP_STATUS=1 FAKE_PM_HELP= \
  run_tool --output "$EMPTY_NONZERO_HELP_AUDIT_DIR" audit || fail "empty nonzero help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
MALFORMED_NONZERO_HELP_AUDIT_DIR="$TEST_TMP/audit-malformed-nonzero-help"
FAKE_PM_HELP_STATUS=1 FAKE_PM_HELP='disable-user and enable are available' \
  run_tool --output "$MALFORMED_NONZERO_HELP_AUDIT_DIR" audit || fail "malformed nonzero help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
NONEXACT_NONZERO_HELP_AUDIT_DIR="$TEST_TMP/audit-nonexact-nonzero-help"
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT
pm enable [--user USER_ID] PACKAGE_OR_COMPONENT trailing-prose' \
  run_tool --output "$NONEXACT_NONZERO_HELP_AUDIT_DIR" audit || fail "nonexact nonzero help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
ARBITRARY_PREFIX_NONZERO_HELP_AUDIT_DIR="$TEST_TMP/audit-arbitrary-prefix-nonzero-help"
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='usage pm disable-user [--user USER_ID] PACKAGE_OR_COMPONENT
usage pm enable [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$ARBITRARY_PREFIX_NONZERO_HELP_AUDIT_DIR" audit || fail "arbitrary-prefix nonzero help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'
WRONG_PREFIX_NONZERO_HELP_AUDIT_DIR="$TEST_TMP/audit-wrong-prefix-nonzero-help"
FAKE_PM_HELP_STATUS=1 \
FAKE_PM_HELP='cmd disable-user [--user USER_ID] PACKAGE_OR_COMPONENT
cmd enable [--user USER_ID] PACKAGE_OR_COMPONENT' \
  run_tool --output "$WRONG_PREFIX_NONZERO_HELP_AUDIT_DIR" audit || fail "wrong-prefix nonzero help audit failed: $ERR"
assert_contains "$OUT" 'PACKAGE_OPERATION=unsupported'
assert_contains "$OUT" 'PACKAGE_RESTORE=unsupported'

# Break caught: attempting a user-0 disable without a help-proven disable/enable pair.
if FAKE_PM_HELP='no package state commands' run_tool --yes apply; then
  fail 'apply accepted no disable/enable capability'
fi
assert_contains "$ERR" 'no help-proven pm disable-user/enable commands are available'
case "$(cat "$FAKE_ADB_LOG")" in
  *'pm disable-user --user 0'*) fail 'apply attempted disable without restore capability' ;;
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

INVALID_MANIFEST_ORIGINAL="$TEST_TMP/remove-user0.txt"
cp "$MANIFEST_REMOVE" "$INVALID_MANIFEST_ORIGINAL"
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
cp "$INVALID_MANIFEST_ORIGINAL" "$MANIFEST_REMOVE"

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

# Break caught: verification must report a listener separately from observed
# end-to-end network remote behavior; an ADB probe cannot prove remote input.
prepare_package_state
set_wolf_ready
run_verify || fail "verify rejected the complete safe fixture: $ERR"
assert_contains "$OUT" 'VERIFY_GATE=PASS'
assert_contains "$OUT" 'SETTINGS_ROUTES=PASS'
assert_contains "$OUT" 'ADB_PERSISTENCE=PASS'
assert_contains "$OUT" 'TCP8009=PASS'
assert_contains "$OUT" 'NETWORK_REMOTE_OBSERVED=UNVERIFIED'

# Break caught: the selected USB transport is not evidence that the independent
# network ADB connection remains usable.
if "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial usb-primary \
  --network-serial network-check:5555 --baseline "$VERIFY_BASELINE" verify >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  STATUS=0
else STATUS=$?; fi
[ "$STATUS" -eq 0 ] || fail "USB primary with healthy network ADB failed: $(cat "$TEST_TMP/err")"
assert_contains "$(cat "$TEST_TMP/out")" 'NETWORK_ADB_SERIAL=network-check:5555'
if FAKE_NETWORK_ADB_STATE=offline "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial usb-primary \
  --network-serial network-check:5555 --baseline "$VERIFY_BASELINE" verify >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  fail 'verify accepted an offline independent network transport'
fi
assert_contains "$(cat "$TEST_TMP/err")" 'verify TCP 5555 is not reachable: offline'
if FAKE_NETWORK_MODEL=AFTKA "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial usb-primary \
  --network-serial network-check:5555 --baseline "$VERIFY_BASELINE" verify >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  fail 'verify accepted a wrong independent network target'
fi
assert_contains "$(cat "$TEST_TMP/err")" 'network target ro.product.model expected=AFTMM actual=AFTKA'
if FAKE_NETWORK_SERIAL=other-device "$ROOT/scripts/mantis-tool.sh" --adb "$ROOT/tests/fixtures/adb" --serial usb-primary \
  --network-serial network-check:5555 --baseline "$VERIFY_BASELINE" verify >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  fail 'verify accepted mismatched primary/network identity'
fi
assert_contains "$(cat "$TEST_TMP/err")" 'primary and network device identity mismatch'

# Break caught: every exact route must resolve and render, including the
# Developer Options screen that preserves ADB Debugging access.
run_verify_settings || fail "verify-settings rejected the complete safe fixture: $ERR"
assert_contains "$OUT" 'SETTINGS_ROUTES=PASS'
assert_contains "$OUT" 'DEVELOPER_OPTIONS=PASS'
assert_contains "$OUT" 'VERIFY_SETTINGS=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent 176'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -f 0x04000000 -n com.amazon.tv.launcher/.ui.MainSettingsActivity'

# Break caught: bringing an existing Settings task forward may resume its last
# Preferences subpage. The exact CLEAR_TOP flag must produce and focus the root.
prepare_package_state
set_wolf_ready
FAKE_ROOT_REQUIRES_CLEAR_TOP=1 \
  run_verify_settings || fail "verify-settings did not clear a resumed Settings task to root: $ERR"
assert_contains "$OUT" 'UI_SMOKE=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -f 0x04000000 -n com.amazon.tv.launcher/.ui.MainSettingsActivity'

# Status zero and Starting output are insufficient when the platform ignores
# CLEAR_TOP and keeps the resumed subpage focused.
prepare_package_state
set_wolf_ready
if FAKE_ROOT_REQUIRES_CLEAR_TOP=1 FAKE_ROOT_IGNORE_CLEAR_TOP=1 run_verify_settings; then
  fail 'verify-settings accepted an ignored CLEAR_TOP root launch'
fi
assert_contains "$ERR" 'Settings intermediate focus expected=com.amazon.tv.launcher/.ui.MainSettingsActivity'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'

# Break caught: keyevent 176 can return success without opening the HUD. The
# controller must silently observe that miss, fall back to long-press Home, and
# require exact HUD focus before inspecting the tile.
prepare_package_state
set_wolf_ready
FAKE_KEY176_NOOP=1 run_verify_settings || fail "verify-settings rejected the working long-press HUD fallback: $ERR"
assert_contains "$OUT" 'UI_SMOKE=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent --longpress 3'
assert_not_contains "$ERR" 'Settings intermediate focus expected='

# Neither a second no-op nor a wrong focused activity can satisfy HUD entry.
prepare_package_state
set_wolf_ready
if FAKE_KEY176_NOOP=1 FAKE_LONGPRESS3_NOOP=1 run_verify_settings; then
  fail 'verify-settings accepted two successful HUD-entry no-ops'
fi
assert_contains "$ERR" 'HUD entry failed after keyevent 176 and long-press Home'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent --longpress 3'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'
prepare_package_state
set_wolf_ready
if FAKE_CURRENT_FOCUS=com.example/.Wrong run_verify_settings; then
  fail 'verify-settings accepted wrong focus after both HUD-entry methods'
fi
assert_contains "$ERR" 'HUD entry failed after keyevent 176 and long-press Home'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent --longpress 3'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'

# Break caught: Fire OS may report a successful stock-menu action start while
# leaving Home focused. Status zero is safe only because the controller then
# opens and verifies the exact stock root before deterministic navigation.
prepare_package_state
set_wolf_ready
FAKE_STOCK_MENU_STATUS0_ACTION=android.settings.SETTINGS \
  run_verify_settings || fail "verify-settings rejected a status-zero stock-menu no-op: $ERR"
assert_contains "$OUT" 'UI_SMOKE=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -a android.settings.SETTINGS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -f 0x04000000 -n com.amazon.tv.launcher/.ui.MainSettingsActivity'

# A nonzero stock-menu launch remains acceptable only for the exact Amazon
# launcher permission denial, never an arbitrary start failure.
prepare_package_state
set_wolf_ready
if FAKE_STOCK_MENU_WRONG_ERROR_ACTION=android.settings.SETTINGS run_verify_settings; then
  fail 'verify-settings accepted a nonzero stock-menu launch with the wrong error'
fi
assert_contains "$ERR" 'Settings direct launch did not show stock-menu permission denial'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'

# Break caught: HUD selection proves the user-facing path even when Settings
# resumes a stock subpage; protected routes must still begin from direct root.
prepare_package_state
set_wolf_ready
FAKE_HUD_POST_SELECT_FOCUS=com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity \
  run_verify_settings || fail "verify-settings rejected a resumed stock HUD subpage: $ERR"
assert_contains "$OUT" 'UI_SMOKE=PASS'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell am start -f 0x04000000 -n com.amazon.tv.launcher/.ui.MainSettingsActivity'

# Break caught: Select must leave the HUD for a specifically known stock
# Settings destination; unchanged HUD or an unknown settings.v2 activity is
# not evidence that the Settings tile worked.
prepare_package_state
set_wolf_ready
if FAKE_HUD_POST_SELECT_FOCUS=com.amazon.tv.settings.v2/.hud.HudActivity run_verify_settings; then
  fail 'verify-settings accepted unchanged HUD focus after selecting Settings'
fi
assert_contains "$ERR" 'HUD Settings selection did not enter a known stock Settings destination'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'
prepare_package_state
set_wolf_ready
if FAKE_HUD_POST_SELECT_FOCUS=com.amazon.tv.settings.v2/.unknown.UnknownActivity run_verify_settings; then
  fail 'verify-settings accepted an unknown settings.v2 activity after selecting Settings'
fi
assert_contains "$ERR" 'HUD Settings selection did not enter a known stock Settings destination'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'

# Break caught: HUD evidence needs the exact usable Settings tile, not merely a
# HUD focus or a similarly named/disabled node.
prepare_package_state
set_wolf_ready
if FAKE_HUD_SETTINGS_TILE=missing run_verify_settings; then
  fail 'verify-settings accepted a HUD without the Settings tile'
fi
assert_contains "$ERR" 'HUD Settings tile is missing or unusable'
prepare_package_state
set_wolf_ready
if FAKE_HUD_SETTINGS_TILE=nonclickable run_verify_settings; then
  fail 'verify-settings accepted a nonclickable HUD Settings tile'
fi
assert_contains "$ERR" 'HUD Settings tile is missing or unusable'

# Break caught: selecting the HUD tile must remain inside an allowed stock
# Settings task, and deterministic protected navigation requires exact root.
prepare_package_state
set_wolf_ready
if FAKE_HUD_POST_SELECT_FOCUS=com.example/.Foreign run_verify_settings; then
  fail 'verify-settings accepted foreign focus after HUD Settings selection'
fi
assert_contains "$ERR" 'HUD Settings selection did not enter a known stock Settings destination'
prepare_package_state
set_wolf_ready
if FAKE_ROOT_START_RESULT=failure run_verify_settings; then
  fail 'verify-settings accepted failure to launch the stock Settings root'
fi
assert_contains "$ERR" 'stock Settings root launch failed'
prepare_package_state
set_wolf_ready
if FAKE_ROOT_FOCUS=com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity run_verify_settings; then
  fail 'verify-settings navigated a protected route without exact stock root focus'
fi
assert_contains "$ERR" 'Settings intermediate focus expected=com.amazon.tv.launcher/.ui.MainSettingsActivity'

# Break caught: a stale component elsewhere in dumpsys cannot satisfy either
# exact HUD-entry focus check, and final failure must clean up and return.
prepare_package_state
set_wolf_ready
if FAKE_CURRENT_FOCUS=com.example/.Wrong FAKE_UI_STATE="$TEST_TMP/ui-state" run_verify_settings; then
  fail 'verify-settings accepted a wrong current focus'
fi
assert_contains "$ERR" 'HUD entry failed after keyevent 176 and long-press Home'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell rm -f /sdcard/mantis-ui-smoke.xml'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent 3'
assert_not_contains "$OUT" 'UI_SMOKE=PASS'

# Break caught: a resolver mismatch is a Settings-smoke failure too, so the
# temporary XML and stock UI must be cleaned up before it returns.
prepare_package_state
set_wolf_ready
if FAKE_SETTINGS_ROUTE_ACTION=android.settings.SETTINGS \
  FAKE_SETTINGS_ROUTE_VALUE=com.example/.Wrong run_verify_settings; then
  fail 'verify-settings accepted an unexpected Settings resolver'
fi
assert_contains "$ERR" 'Settings resolver expected=com.amazon.tv.launcher/.ui.SettingsActivity'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell rm -f /sdcard/mantis-ui-smoke.xml'
assert_contains "$(cat "$FAKE_ADB_LOG")" 'shell input keyevent 3'

# Break caught: an incomplete preserve manifest is not enough if a required
# package is absent from the active user-zero package list.
awk '
  $1 == "active" && $2 == "com.amazon.tcomm" { print "disabled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
if run_verify; then
  fail 'verify accepted a missing mandatory preserve package'
fi
assert_contains "$ERR" 'guard missing enabled package: com.amazon.tcomm'

# Break caught: protected applications are mandatory even when their package
# name appears outside the generic preserve manifests.
prepare_package_state
set_wolf_ready
awk '
  $1 == "active" && $2 == "com.wireguard.android" { print "disabled", $2; next }
  { print }
' "$FAKE_PACKAGE_STATE" > "$FAKE_PACKAGE_STATE.next"
mv "$FAKE_PACKAGE_STATE.next" "$FAKE_PACKAGE_STATE"
if run_verify; then
  fail 'verify accepted an absent protected application'
fi
assert_contains "$ERR" 'guard missing enabled package: com.wireguard.android'

# Break caught: Bluetooth and the exact Wolf launcher identity are recovery
# gates, not merely install history.
prepare_package_state
set_wolf_ready
if FAKE_BLUETOOTH_ON=0 run_verify; then
  fail 'verify accepted Bluetooth disabled'
fi
assert_contains "$ERR" 'verify bluetooth_on expected=1 actual=0'
prepare_package_state
set_wolf_ready
if FAKE_CURRENT_FOCUS=com.example/.Wrong run_verify; then
  fail 'verify accepted a wrong Wolf current focus'
fi
assert_contains "$ERR" 'Wolf Launcher focus expected='
prepare_package_state
set_wolf_ready
WOLF_DELAY_FILE="$TEST_TMP/wolf-focus-delay"
rm -f "$WOLF_DELAY_FILE"
FAKE_WOLF_FOCUS_DELAY=1 FAKE_WOLF_FOCUS_DELAY_FILE="$WOLF_DELAY_FILE" run_verify ||
  fail "verify did not wait for delayed Wolf focus: $ERR"
prepare_package_state
clear_wolf_ready
if run_verify; then
  fail 'verify accepted installed Wolf 0.1.7-FireTV'
fi
assert_contains "$ERR" 'guard Wolf version code expected=11900120 actual=11723945'

# Break caught: resolver equality is a contract; a similarly named Settings
# activity is not a safe substitute.
prepare_package_state
set_wolf_ready
if FAKE_SETTINGS_ROUTE_ACTION=android.settings.WIFI_SETTINGS \
  FAKE_SETTINGS_ROUTE_VALUE=com.example.settings/.WifiActivity run_verify; then
  fail 'verify accepted an unexpected Wi-Fi Settings resolver'
fi
assert_contains "$ERR" 'Settings resolver changed from baseline expected=com.amazon.tv.settings.v2/.tv.network.NetworkActivity actual=com.example.settings/.WifiActivity action=android.settings.WIFI_SETTINGS'

# Break caught: a route can resolve while its UI no longer renders. This is
# particularly important for Developer Options and the permission-protected
# stock-menu paths.
prepare_package_state
set_wolf_ready
if FAKE_UI_EMPTY_ACTION=android.settings.APPLICATION_DEVELOPMENT_SETTINGS run_verify_settings; then
  fail 'verify-settings accepted an unrendered Developer Options screen'
fi
assert_contains "$ERR" 'Settings UI hierarchy was empty: android.settings.APPLICATION_DEVELOPMENT_SETTINGS'
prepare_package_state
set_wolf_ready
if FAKE_UI_EMPTY_ACTION=android.settings.ACCESSIBILITY_SETTINGS run_verify_settings; then
  fail 'verify-settings accepted an unrendered stock-menu Accessibility screen'
fi
assert_contains "$ERR" 'Settings UI hierarchy was empty: android.settings.ACCESSIBILITY_SETTINGS'

# Break caught: ADB persistence values are compared against the live Fire OS
# baseline. development_settings_enabled is legitimately null on this build.
prepare_package_state
set_wolf_ready
if FAKE_ADB_ENABLED=0 run_verify; then
  fail 'verify accepted changed adb_enabled'
fi
assert_contains "$ERR" 'verify adb_enabled expected=1 actual=0'
prepare_package_state
set_wolf_ready
if FAKE_DEVELOPMENT_SETTINGS_ENABLED=1 run_verify; then
  fail 'verify accepted a changed development_settings_enabled baseline'
fi
assert_contains "$ERR" 'verify development_settings_enabled expected=null actual=1'
prepare_package_state
set_wolf_ready
if FAKE_INIT_SVC_ADBD=stopped run_verify; then
  fail 'verify accepted a stopped adbd'
fi
assert_contains "$ERR" 'verify adbd is not running'
prepare_package_state
set_wolf_ready
if FAKE_PERSIST_USB_CONFIG=mtp run_verify; then
  fail 'verify accepted a persistent USB configuration without adb'
fi
assert_contains "$ERR" 'verify requires USB configuration containing adb: mtp'
prepare_package_state
set_wolf_ready
if FAKE_SYS_USB_CONFIG=mtp run_verify; then
  fail 'verify accepted a current USB configuration without adb'
fi
assert_contains "$ERR" 'verify requires USB configuration containing adb: mtp'
prepare_package_state
set_wolf_ready
if FAKE_SERVICE_ADB_TCP_PORT=5556 run_verify; then
  fail 'verify accepted a changed configured TCP ADB port'
fi
assert_contains "$ERR" 'verify service.adb.tcp.port expected=5555 actual=5556'
prepare_package_state
set_wolf_ready
if FAKE_ADB_STATE=offline run_verify; then
  fail 'verify accepted an unreachable TCP 5555 transport'
fi
assert_contains "$ERR" 'verify TCP 5555 is not reachable: offline'

# Break caught: locale, WireGuard continuity, and tun0 must not silently drift
# across a debloat operation.
prepare_package_state
set_wolf_ready
if FAKE_PERSIST_SYS_LOCALE=fr-FR run_verify; then
  fail 'verify accepted a changed locale'
fi
assert_contains "$ERR" 'verify locale expected=en-US actual=fr-FR'
prepare_package_state
set_wolf_ready
if FAKE_ALWAYS_ON_VPN_APP=none run_verify; then
  fail 'verify accepted changed WireGuard Always-on application'
fi
assert_contains "$ERR" 'verify always_on_vpn_app expected=com.wireguard.android actual=null'
prepare_package_state
set_wolf_ready
if FAKE_ALWAYS_ON_VPN_LOCKDOWN=0 run_verify; then
  fail 'verify accepted changed WireGuard lockdown'
fi
assert_contains "$ERR" 'verify always_on_vpn_lockdown expected=1 actual=0'
prepare_package_state
set_wolf_ready
if FAKE_TUN0=absent run_verify; then
  fail 'verify accepted changed tun0 presence'
fi
assert_contains "$ERR" 'verify tun0 expected=present actual=absent'

# Break caught: publication checks reject private connection material,
# executable images, and destructive system-partition commands in any tree.
SCAN_FIXTURE="$TEST_TMP/excluded-content"
mkdir "$SCAN_FIXTURE"
private_octet=10
printf '%s.%s.%s.%s\n' "$private_octet" 23 45 67 > "$SCAN_FIXTURE/private-address.txt"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted a private address'
fi
rm "$SCAN_FIXTURE/private-address.txt"
printf '%s\n' "-----BE"'GIN PRIVATE KEY-----' > "$SCAN_FIXTURE/key.txt"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted a PEM key header'
fi
rm "$SCAN_FIXTURE/key.txt"
printf '%s\n' 'Private'Key' = secret' > "$SCAN_FIXTURE/tunnel.conf"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted a WireGuard private key'
fi
rm "$SCAN_FIXTURE/tunnel.conf"
: > "$SCAN_FIXTURE/forbidden.apk"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted an APK'
fi
rm "$SCAN_FIXTURE/forbidden.apk"
: > "$SCAN_FIXTURE/forbidden.img"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted a partition image'
fi
rm "$SCAN_FIXTURE/forbidden.img"
printf '%s %s\n' 'rm -rf' '/sys''tem' > "$SCAN_FIXTURE/destructive.sh"
if sh "$ROOT/tests/scan-excluded-content.sh" "$SCAN_FIXTURE"; then
  fail 'excluded-content scan accepted a destructive system command'
fi
rm "$SCAN_FIXTURE/destructive.sh"

for documentation in README.md NOTICE.md SECURITY.md docs/MODEL-SAFETY.md \
  docs/PACKAGE-RATIONALE.md docs/RECOVERY.md docs/TEST-EVIDENCE.md; do
  assert_file "$ROOT/$documentation"
done

clear_wolf_ready
unset FAKE_PACKAGE_STATE FAKE_SETTINGS_ROUTE_ACTION FAKE_SETTINGS_ROUTE_VALUE FAKE_UI_EMPTY_ACTION

[ "$(wc -l < "$MANIFEST_REMOVE" | tr -d ' ')" = 30 ] || fail 'test run changed the exact 30-package candidate manifest'
cmp "$ORIGINAL_REMOVE" "$MANIFEST_REMOVE" >/dev/null || fail 'test run changed candidate manifest content'
python3 -B "$ROOT/tests/verify-manifests.py" "$ROOT/manifests"
python3 -B "$ROOT/tests/test-atomic-rename.py"
sh "$ROOT/tests/test-deploy-static.sh"
sh "$ROOT/tests/test-bundled-wolf.sh"

printf '%s\n' 'PASS: target gate tests'
