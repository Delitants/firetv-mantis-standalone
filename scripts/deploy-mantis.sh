#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$HERE/.." && pwd)
ADB=adb
CURL=curl
AAPT=aapt
APKSIGNER=apksigner
SERIAL=
NETWORK_SERIAL=
ROOT_BINARY=
ROOT_PROFILE=$ROOT_DIR/exploit/profiles/mantis-NS6711-5908.conf
OUTPUT=
YES=no

usage() {
  printf '%s\n' 'usage: deploy-mantis.sh --serial USB_SERIAL --network-serial IP:5555 --root-binary FILE --output DIR --yes [--adb PATH] [--curl PATH] [--aapt PATH] [--apksigner PATH] [--root-profile FILE]' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --adb) ADB=$2; shift 2 ;;
    --curl) CURL=$2; shift 2 ;;
    --aapt) AAPT=$2; shift 2 ;;
    --apksigner) APKSIGNER=$2; shift 2 ;;
    --serial) SERIAL=$2; shift 2 ;;
    --network-serial) NETWORK_SERIAL=$2; shift 2 ;;
    --root-binary) ROOT_BINARY=$2; shift 2 ;;
    --root-profile) ROOT_PROFILE=$2; shift 2 ;;
    --output) OUTPUT=$2; shift 2 ;;
    --yes) YES=yes; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

[ "$YES" = yes ] || { printf '%s\n' '--yes is required' >&2; exit 64; }
[ -n "$SERIAL" ] && [ -n "$NETWORK_SERIAL" ] && [ -n "$OUTPUT" ] || { usage; exit 64; }
[ -f "$ROOT_BINARY" ] && [ ! -L "$ROOT_BINARY" ] || { printf '%s\n' 'root binary is missing or symlinked' >&2; exit 64; }
[ -f "$ROOT_PROFILE" ] && [ ! -L "$ROOT_PROFILE" ] || { printf '%s\n' 'root profile is missing or symlinked' >&2; exit 64; }
for tool in "$ADB" "$CURL" "$AAPT" "$APKSIGNER"; do
  command -v "$tool" >/dev/null 2>&1 || [ -x "$tool" ] || { printf 'required tool not found: %s\n' "$tool" >&2; exit 64; }
done

mkdir -p "$OUTPUT"
RUN_DIR=$OUTPUT/deployment-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$RUN_DIR" ] && [ ! -L "$RUN_DIR" ] || { printf 'output exists: %s\n' "$RUN_DIR" >&2; exit 1; }
mkdir "$RUN_DIR"
LOG=$RUN_DIR/deploy.log
exec 3>&1 4>&2
exec >"$LOG" 2>&1
trap 'status=$?; exec 1>&3 2>&4; if [ "$status" -eq 0 ]; then printf "DEPLOY_LOG=%s\n" "$LOG"; else printf "DEPLOY_FAILED status=%s log=%s\n" "$status" "$LOG" >&2; fi; exit "$status"' EXIT HUP INT TERM

adb_cmd() { "$ADB" -s "$SERIAL" "$@" < /dev/null; }
adb_shell() { adb_cmd shell "$@"; }
network_adb_cmd() { "$ADB" -s "$NETWORK_SERIAL" "$@" < /dev/null; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

expect_prop() {
  actual=$(adb_shell getprop "$1" | tr -d '\r') || fail "cannot read $1"
  [ "$actual" = "$2" ] || fail "target $1 expected=$2 actual=$actual"
}

target_gate() {
  [ "$(adb_cmd get-state | tr -d '\r')" = device ] || fail 'primary ADB transport is unavailable'
  [ "$(network_adb_cmd get-state | tr -d '\r')" = device ] || fail 'network ADB transport is unavailable'
  expect_prop ro.product.manufacturer Amazon
  expect_prop ro.product.model AFTMM
  expect_prop ro.product.device mantis
  expect_prop ro.build.id NS6711
  expect_prop ro.build.version.incremental 0011644900484
  expect_prop ro.build.fingerprint 'Amazon/mantis/mantis:6.0/NS6711/5908N:user/amz-p,release-keys'
  [ "$(adb_shell uname -r | tr -d '\r')" = '4.4.120+' ] || fail 'kernel release mismatch'
  [ "$(adb_shell uname -m | tr -d '\r')" = armv7l ] || fail 'kernel machine mismatch'
  [ "$(adb_shell id -u | tr -d '\r')" = 2000 ] || fail 'expected unprivileged ADB shell before root'
  [ "$(adb_shell getenforce | tr -d '\r')" = Enforcing ] || fail 'SELinux is not Enforcing'
  primary_identity=$(adb_shell getprop ro.serialno | tr -d '\r')
  network_identity=$(network_adb_cmd shell getprop ro.serialno | tr -d '\r')
  [ -n "$primary_identity" ] && [ "$primary_identity" = "$network_identity" ] || fail 'USB/network device identity mismatch'
  printf '%s\n' 'TARGET_GATE=PASS'
}

badging_value() {
  printf '%s\n' "$1" | sed -n "s/.*$2='\([^']*\)'.*/\1/p" | head -n 1
}

install_aurora() {
  url=https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-4.8.4.apk
  expected_size=9362660
  expected_hash=8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad
  expected_cert=4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f
  apk=$RUN_DIR/AuroraStore-4.8.4.apk
  "$CURL" --fail --location --output "$apk" "$url" || fail 'Aurora download failed'
  [ "$(wc -c < "$apk" | tr -d '[:space:]')" = "$expected_size" ] || fail 'Aurora size mismatch'
  [ "$(sha256_file "$apk")" = "$expected_hash" ] || fail 'Aurora SHA-256 mismatch'
  badging=$("$AAPT" dump badging "$apk") || fail 'Aurora aapt inspection failed'
  package_line=$(printf '%s\n' "$badging" | sed -n '/^package: /p' | head -n 1)
  activity_line=$(printf '%s\n' "$badging" | sed -n '/^launchable-activity: /p' | head -n 1)
  [ "$(badging_value "$package_line" name)" = com.aurora.store ] || fail 'Aurora package mismatch'
  [ "$(badging_value "$package_line" versionCode)" = 76 ] || fail 'Aurora versionCode mismatch'
  [ "$(badging_value "$package_line" versionName)" = 4.8.4 ] || fail 'Aurora versionName mismatch'
  activity=$(badging_value "$activity_line" name)
  case "$activity" in com.aurora.store.ComposeActivity|.ComposeActivity) ;; *) fail 'Aurora activity mismatch' ;; esac
  signatures=$("$APKSIGNER" verify --verbose --print-certs "$apk") || fail 'Aurora signature verification failed'
  case "$signatures" in *'Verified using v1 scheme (JAR signing): true'*) ;; *) fail 'Aurora v1 signature missing' ;; esac
  case "$signatures" in *'Verified using v2 scheme (APK Signature Scheme v2): true'*) ;; *) fail 'Aurora v2 signature missing' ;; esac
  cert=$(printf '%s\n' "$signatures" | sed -n 's/^Signer #[0-9][0-9]* certificate SHA-256 digest: //p' | tr -d ' :\r' | tr '[:upper:]' '[:lower:]')
  [ "$cert" = "$expected_cert" ] || fail 'Aurora signer mismatch'
  install_output=$(adb_cmd install -r "$apk") || fail 'Aurora installation failed'
  case "$install_output" in *Success*) ;; *) fail 'Aurora installation did not report Success' ;; esac
  package_dump=$(adb_shell dumpsys package com.aurora.store) || fail 'Aurora installed readback failed'
  case "$package_dump" in *'versionCode=76 '*|*'versionCode=76'*) ;; *) fail 'Aurora installed versionCode mismatch' ;; esac
  case "$package_dump" in *'versionName=4.8.4'*) ;; *) fail 'Aurora installed versionName mismatch' ;; esac
  printf '%s\n' 'AURORA_INSTALL=PASS'
}

package_enabled() { adb_shell pm list packages -e | tr -d '\r' | grep -Fqx "package:$1"; }
package_disabled() { adb_shell pm list packages -d | tr -d '\r' | grep -Fqx "package:$1"; }

settings_routes_qa() {
  while IFS='|' read -r action expected; do
    actual=$(adb_shell cmd package resolve-activity --brief -a "$action" | tr -d '\r' | tail -n 1)
    [ "$actual" = "$expected" ] || fail "Settings route $action expected=$expected actual=$actual"
  done <<'EOF'
android.settings.SETTINGS|com.amazon.tv.launcher/.ui.SettingsActivity
android.settings.WIFI_SETTINGS|com.amazon.tv.settings.v2/.tv.network.NetworkActivity
android.settings.MANAGE_APPLICATIONS_SETTINGS|com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity
android.settings.CONTROLLERS_SETTINGS|com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity
android.settings.DEVICE_INFO_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity
android.settings.ACCESSIBILITY_SETTINGS|com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity
android.settings.DISPLAY_SETTINGS|com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity
com.amazon.device.settings.action.DATE_TIME|com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity
com.amazon.device.settings.action.LANGUAGE|com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity
android.settings.APPLICATION_DEVELOPMENT_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity
EOF
}

qa() {
  phase=$1
  target_gate
  while IFS= read -r package; do package_disabled "$package" || fail "$phase debloat state $package"; done < "$ROOT_DIR/manifests/remove-user0.txt"
  while IFS= read -r package; do
    package_disabled "$package" || fail "$phase root-only disable state $package"
  done < "$ROOT_DIR/manifests/disable-root-packages.txt"
  while IFS= read -r package; do package_enabled "$package" || fail "$phase protected state $package"; done < "$ROOT_DIR/manifests/preserve-user-apps.txt"
  for package in com.amazon.tv.launcher com.amazon.tv.settings.v2 com.android.bluetooth com.amazon.tcomm com.amazon.whisperjoin.middleware.np com.amazon.whisperlink.core.android; do
    package_enabled "$package" || fail "$phase essential state $package"
  done
  home=$(adb_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r' | tail -n 1)
  [ "$home" = 'com.wolf.firelauncher/.screens.launcher.LauncherActivity' ] || fail "$phase Wolf resolver"
  settings_routes_qa
  "$HERE/mantis-tool.sh" --adb "$ADB" --serial "$SERIAL" verify-settings || fail "$phase Settings HUD/UI smoke"
  [ "$(adb_shell settings get global adb_enabled | tr -d '\r')" = 1 ] || fail "$phase ADB disabled"
  [ "$(adb_shell getprop init.svc.adbd | tr -d '\r')" = running ] || fail "$phase adbd state"
  case ",$(adb_shell getprop persist.sys.usb.config | tr -d '\r')," in *,adb,*) ;; *) fail "$phase USB ADB config" ;; esac
  [ "$(adb_shell getprop service.adb.tcp.port | tr -d '\r')" = 5555 ] || fail "$phase TCP ADB port"
  [ "$(network_adb_cmd get-state | tr -d '\r')" = device ] || fail "$phase network ADB"
  [ "$(adb_shell settings get global bluetooth_on | tr -d '\r')" = 1 ] || fail "$phase Bluetooth setting"
  adb_shell dumpsys bluetooth_manager | grep -Eq 'state: ON|enabled: true|State: ON' || fail "$phase Bluetooth adapter"
  [ "$(adb_shell settings get global wifi_on | tr -d '\r')" = 1 ] || fail "$phase Wi-Fi setting"
  adb_shell dumpsys wifi | grep -Eq 'Wi-Fi is enabled|mWifiEnabled=true|enabled: true' || fail "$phase Wi-Fi adapter"
  adb_shell dumpsys wifi | grep -Eq 'CONNECTED|COMPLETED' || fail "$phase Wi-Fi connection"
  for process in com.amazon.tcomm com.amazon.whisperjoin.middleware.np com.amazon.whisperlink.core.android; do
    adb_shell pidof "$process" | grep -Eq '[0-9]' || fail "$phase process $process"
  done
  adb_shell am start -n com.aurora.store/.ComposeActivity >/dev/null || fail "$phase Aurora launch"
  sleep 2
  adb_shell dumpsys window windows | grep -F 'mCurrentFocus' | grep -F 'com.aurora.store/.ComposeActivity' >/dev/null || fail "$phase Aurora focus"
  adb_shell input keyevent 3 >/dev/null || fail "$phase HOME key"
  sleep 2
  adb_shell dumpsys window windows | grep -F 'mCurrentFocus' | grep -F 'com.wolf.firelauncher/.screens.launcher.LauncherActivity' >/dev/null || fail "$phase Wolf focus"
  printf 'QA_%s=PASS\n' "$phase"
}

target_gate
[ "$(sha256_file "$ROOT_PROFILE")" = 1ac2127f32117bb5a9b8176b5a1b3aae04070fe5843737a875ac5b25999e0fdb ] || fail 'root profile SHA-256 mismatch'
TOOL=$HERE/mantis-tool.sh
"$TOOL" --adb "$ADB" --serial "$SERIAL" --network-serial "$NETWORK_SERIAL" --output "$RUN_DIR/preflight-audit" audit
"$TOOL" --adb "$ADB" --serial "$SERIAL" verify-settings
"$TOOL" --adb "$ADB" --curl "$CURL" --aapt "$AAPT" --apksigner "$APKSIGNER" --serial "$SERIAL" --yes install-wolf
install_aurora
"$TOOL" --adb "$ADB" --serial "$SERIAL" --network-serial "$NETWORK_SERIAL" --output "$RUN_DIR/debloat-backup" --yes apply

REMOTE=/data/local/tmp/mantis-deploy
adb_shell rm -rf "$REMOTE"
adb_shell mkdir -p "$REMOTE"
adb_cmd push "$ROOT_BINARY" "$REMOTE/ghostlock_root" >/dev/null
adb_cmd push "$ROOT_PROFILE" "$REMOTE/mantis.conf" >/dev/null
adb_cmd push "$HERE/device-root-actions.sh" "$REMOTE/device-root-actions.sh" >/dev/null
adb_shell chmod 700 "$REMOTE/ghostlock_root" "$REMOTE/mantis.conf" "$REMOTE/device-root-actions.sh"

for pair in "$ROOT_BINARY:ghostlock_root" "$ROOT_PROFILE:mantis.conf" "$HERE/device-root-actions.sh:device-root-actions.sh"; do
  local_file=${pair%%:*}; remote_file=${pair#*:}
  expected=$(sha256_file "$local_file")
  readback=$RUN_DIR/staged-readback-$remote_file
  adb_cmd pull "$REMOTE/$remote_file" "$readback" >/dev/null || fail "staged readback failed $remote_file"
  actual=$(sha256_file "$readback")
  [ "$actual" = "$expected" ] || fail "staged hash mismatch $remote_file"
  rm -f "$readback"
done

profile_check=$(adb_shell "$REMOTE/ghostlock_root" --profile "$REMOTE/mantis.conf" --check-profile 2>&1) || fail 'root profile check failed'
case "$profile_check" in
  *'target=mantis-NS6711-5908-0011644900484'*'verification=live-root-verified-exact-build'*) ;;
  *) fail 'root profile check returned unexpected identity' ;;
esac

adb_shell "cd $REMOTE && nohup ./ghostlock_root --profile ./mantis.conf --tries 1 --exec ./device-root-actions.sh >root.log 2>&1 </dev/null &"
root_result=
for attempt in $(awk 'BEGIN { for (i=1; i<=120; i++) print i }'); do
  if adb_shell grep -Fq 'ROOT_ACTIONS=PASS' "$REMOTE/root.log"; then root_result=pass; break; fi
  if adb_shell grep -Fq 'ROOT_ACTIONS=FAIL' "$REMOTE/root.log"; then root_result=fail; break; fi
  sleep 2
done
adb_cmd pull "$REMOTE/root.log" "$RUN_DIR/root.log" >/dev/null 2>&1 || true
adb_cmd pull "$REMOTE/root-actions.journal" "$RUN_DIR/root-actions.journal" >/dev/null 2>&1 || true
adb_cmd pull "$REMOTE/root-actions.journal.md5" "$RUN_DIR/root-actions.journal.md5" >/dev/null 2>&1 || true
[ "$root_result" = pass ] || { adb_cmd reboot >/dev/null 2>&1 || true; fail "root actions did not pass: ${root_result:-timeout}"; }
grep -Fq '[exec] ./device-root-actions.sh exited status=0' "$RUN_DIR/root.log" || fail 'root action exit status missing'
qa PRE_REBOOT

adb_cmd reboot >/dev/null
adb_cmd wait-for-device >/dev/null
for attempt in $(awk 'BEGIN { for (i=1; i<=120; i++) print i }'); do
  [ "$(adb_shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break
  sleep 2
done
"$ADB" connect "$NETWORK_SERIAL" >/dev/null 2>&1 || true
sleep 5
qa POST_REBOOT
[ "$(adb_shell id -u | tr -d '\r')" = 2000 ] || fail 'temporary root persisted unexpectedly'
[ "$(adb_shell getenforce | tr -d '\r')" = Enforcing ] || fail 'SELinux changed after reboot'

adb_shell screencap -p /sdcard/mantis-home-postboot.png
adb_cmd pull /sdcard/mantis-home-postboot.png "$RUN_DIR/mantis-home-postboot.png" >/dev/null
adb_shell rm -f /sdcard/mantis-home-postboot.png
printf '%s\n' 'DEPLOY=PASS'
printf 'SCREENSHOT=%s\n' "$RUN_DIR/mantis-home-postboot.png"
