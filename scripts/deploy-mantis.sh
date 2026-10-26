#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$HERE/.." && pwd)
. "$HERE/apk-badging.sh"
. "$HERE/adb-transport.sh"
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
case "$OUTPUT" in
  */path/to/private-backup|*/path/to/private-backup/*)
    printf 'example --output path is not a backup location: %s\n' "$OUTPUT" >&2
    exit 64
    ;;
  /*) ;;
  *) printf 'specify an existing absolute directory for --output: %s\n' "$OUTPUT" >&2; exit 64 ;;
esac
[ "$OUTPUT" != / ] || { printf '%s\n' '--output must not be the filesystem root' >&2; exit 64; }
[ -d "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || {
  printf 'the --output directory is missing or is a symlink; create it first: %s\n' "$OUTPUT" >&2
  exit 64
}
[ -w "$OUTPUT" ] || { printf 'the --output directory is not writable: %s\n' "$OUTPUT" >&2; exit 64; }
[ -f "$ROOT_BINARY" ] && [ ! -L "$ROOT_BINARY" ] || { printf '%s\n' 'root binary is missing or symlinked' >&2; exit 64; }
[ -f "$ROOT_PROFILE" ] && [ ! -L "$ROOT_PROFILE" ] || { printf '%s\n' 'root profile is missing or symlinked' >&2; exit 64; }
for tool in "$ADB" "$CURL" "$AAPT" "$APKSIGNER"; do
  command -v "$tool" >/dev/null 2>&1 || [ -x "$tool" ] || { printf 'required tool not found: %s\n' "$tool" >&2; exit 64; }
done

RUN_DIR=$OUTPUT/deployment-$(date -u +%Y%m%dT%H%M%SZ)
[ ! -e "$RUN_DIR" ] && [ ! -L "$RUN_DIR" ] || { printf 'output exists: %s\n' "$RUN_DIR" >&2; exit 1; }
mkdir "$RUN_DIR"
LOG=$RUN_DIR/deploy.log
exec 3>&1 4>&2
exec >"$LOG" 2>&1
DEPLOY_COMPLETE=no
trap 'status=$?; exec 1>&3 2>&4; if [ "$status" -eq 0 ] && [ "$DEPLOY_COMPLETE" = yes ]; then printf "DEPLOY_LOG=%s\n" "$LOG"; else [ "$status" -ne 0 ] || status=1; printf "DEPLOY_FAILED status=%s log=%s\n" "$status" "$LOG" >&2; fi; exit "$status"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'DEPLOY_LOG=%s\n' "$LOG" >&3

announce_phase() {
  printf 'PHASE=%s\n' "$1"
  printf 'PHASE=%s\n' "$1" >&3
}

adb_cmd() {
  adb_timeout=180
  [ "${1:-}" = wait-for-device ] && adb_timeout=300
  python3 "$HERE/run-bounded.py" "$adb_timeout" "$ADB" -s "$SERIAL" "$@" < /dev/null
}
adb_shell() { adb_cmd shell "$@"; }
network_adb_cmd() { python3 "$HERE/run-bounded.py" 180 "$ADB" -s "$NETWORK_SERIAL" "$@" < /dev/null; }
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
  require_usb_primary "$ADB" "$SERIAL" "$NETWORK_SERIAL" || fail 'USB primary transport is required'
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

preflight_core_packages() {
  audit_dir=$1
  if ! (
    cd "$audit_dir"
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS >/dev/null
    else shasum -a 256 -c SHA256SUMS >/dev/null; fi
  ); then
    fail 'preflight audit checksum verification failed'
  fi
  enabled_packages=$audit_dir/packages-enabled.txt
  while IFS= read -r required_package; do
    if ! grep -Fqx "package:$required_package" "$enabled_packages"; then
      printf 'PREFLIGHT_CORE_MISSING=%s\n' "$required_package"
      fail 'restore the missing protected package before deployment'
    fi
  done < "$ROOT_DIR/manifests/preserve-core.txt"
  printf '%s\n' 'PREFLIGHT_CORE=PASS'
}

install_aurora() {
  url=https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-4.8.4.apk
  expected_size=9362660
  expected_hash=8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad
  expected_cert=4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f
  apk=$RUN_DIR/AuroraStore-4.8.4.apk
  "$CURL" --fail --location --silent --show-error --connect-timeout 15 --max-time 180 --output "$apk" "$url" || fail 'Aurora download failed'
  [ "$(wc -c < "$apk" | tr -d '[:space:]')" = "$expected_size" ] || fail 'Aurora size mismatch'
  [ "$(sha256_file "$apk")" = "$expected_hash" ] || fail 'Aurora SHA-256 mismatch'
  badging=$("$AAPT" dump badging "$apk") || fail 'Aurora aapt inspection failed'
  package_line=$(printf '%s\n' "$badging" | sed -n '/^package: /p' | head -n 1)
  activity_line=$(printf '%s\n' "$badging" | sed -n '/^launchable-activity: /p' | head -n 1)
  [ "$(apk_badging_value "$package_line" name)" = com.aurora.store ] || fail 'Aurora package mismatch'
  [ "$(apk_badging_value "$package_line" versionCode)" = 76 ] || fail 'Aurora versionCode mismatch'
  [ "$(apk_badging_value "$package_line" versionName)" = 4.8.4 ] || fail 'Aurora versionName mismatch'
  activity=$(apk_badging_value "$activity_line" name)
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
package_hidden() {
  adb_shell dumpsys package "$1" | tr -d '\r' | grep -F 'User 0:' | grep -Fq 'installed=true hidden=true'
}

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
    if package_enabled "$package"; then fail "$phase optional debloat state $package"; fi
  done < "$ROOT_DIR/manifests/remove-if-present-user0.txt"
  while IFS= read -r package; do
    package_hidden "$package" || fail "$phase root-only hidden state $package"
  done < "$ROOT_DIR/manifests/disable-root-packages.txt"
  baseline_packages=$RUN_DIR/debloat-backup/packages-enabled.txt
  [ -f "$baseline_packages" ] && [ ! -L "$baseline_packages" ] || fail "$phase missing protected-app baseline"
  while IFS= read -r package; do
    if grep -Fqx "package:$package" "$baseline_packages"; then
      package_enabled "$package" || fail "$phase protected state $package"
    fi
  done < "$ROOT_DIR/manifests/preserve-user-apps.txt"
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
  aurora_focus=$(adb_shell dumpsys window windows | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^} ]*\).*/\1/p' | head -n 1)
  case "$aurora_focus" in
    com.aurora.store/.ComposeActivity|com.aurora.store/com.aurora.store.ComposeActivity) ;;
    *) fail "$phase Aurora focus actual=$aurora_focus" ;;
  esac
  adb_shell am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null || fail "$phase HOME intent"
  sleep 2
  home_focus=$(adb_shell dumpsys window windows | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^} ]*\).*/\1/p' | head -n 1)
  case "$home_focus" in
    com.wolf.firelauncher/.screens.launcher.LauncherActivity|com.wolf.firelauncher/com.wolf.firelauncher.screens.launcher.LauncherActivity) ;;
    *) fail "$phase Wolf focus actual=$home_focus" ;;
  esac
  python3 "$HERE/wolf-layout.py" --adb "$ADB" --serial "$SERIAL" --verify || fail "$phase Wolf layout"
  printf 'QA_%s=PASS\n' "$phase"
}

announce_phase TARGET_GATE
target_gate
announce_phase ROOT_BINARY_CHECK
python3 "$HERE/check-root-binary.py" "$ROOT_BINARY" || fail 'root binary identity mismatch'
[ "$(sha256_file "$ROOT_PROFILE")" = 1ac2127f32117bb5a9b8176b5a1b3aae04070fe5843737a875ac5b25999e0fdb ] || fail 'root profile SHA-256 mismatch'
TOOL=$HERE/mantis-tool.sh
announce_phase PREFLIGHT_AUDIT
"$TOOL" --adb "$ADB" --serial "$SERIAL" --network-serial "$NETWORK_SERIAL" --output "$RUN_DIR/preflight-audit" audit
preflight_core_packages "$RUN_DIR/preflight-audit"
announce_phase SETTINGS_PREFLIGHT
"$TOOL" --adb "$ADB" --serial "$SERIAL" verify-settings
announce_phase ROOT_STAGING
REMOTE=/data/local/tmp/mantis-deploy-$(date -u +%Y%m%dT%H%M%SZ)
adb_shell mkdir "$REMOTE"
adb_shell chmod 755 "$REMOTE"
adb_cmd push "$ROOT_BINARY" "$REMOTE/ghostlock_root" >/dev/null
adb_cmd push "$ROOT_PROFILE" "$REMOTE/mantis.conf" >/dev/null
adb_cmd push "$HERE/device-root-actions.sh" "$REMOTE/device-root-actions.sh" >/dev/null
adb_shell chmod 700 "$REMOTE/ghostlock_root" "$REMOTE/mantis.conf"
adb_shell chmod 755 "$REMOTE/device-root-actions.sh"

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

announce_phase WOLF_INSTALL
"$TOOL" --adb "$ADB" --curl "$CURL" --aapt "$AAPT" --apksigner "$APKSIGNER" --serial "$SERIAL" --yes install-wolf
announce_phase WOLF_LAYOUT
python3 "$HERE/wolf-layout.py" --adb "$ADB" --serial "$SERIAL" || fail 'Wolf layout setup failed before debloat'
announce_phase AURORA_INSTALL
install_aurora
announce_phase DEBLOAT_APPLY
MANTIS_PROGRESS_FD=3 "$TOOL" --adb "$ADB" --serial "$SERIAL" --network-serial "$NETWORK_SERIAL" --output "$RUN_DIR/debloat-backup" --yes apply

announce_phase ROOT_ACTIONS
root_launch_status=0
python3 "$HERE/run-bounded.py" 20 "$ADB" -s "$SERIAL" shell \
  "cd $REMOTE && nohup ./ghostlock_root --profile ./mantis.conf --tries 1 --exec ./device-root-actions.sh >root.log 2>&1 </dev/null &" \
  < /dev/null || root_launch_status=$?
printf 'ROOT_LAUNCH_ADB_STATUS=%s\n' "$root_launch_status"
case "$root_launch_status" in 0|124) ;; *) fail "root launcher ADB failed with status $root_launch_status" ;; esac
root_result=
root_deadline=$(( $(date +%s) + 300 ))
root_next_progress=0
while [ "$(date +%s)" -lt "$root_deadline" ]; do
  root_now=$(date +%s)
  if [ "$root_now" -ge "$root_next_progress" ]; then
    printf 'ROOT_WAIT remaining=%ss\n' "$(( root_deadline - root_now ))"
    printf 'ROOT_WAIT remaining=%ss\n' "$(( root_deadline - root_now ))" >&3
    root_next_progress=$(( root_now + 20 ))
  fi
  if root_snapshot=$(python3 "$HERE/run-bounded.py" 15 "$ADB" -s "$SERIAL" shell cat "$REMOTE/root.log" 2>/dev/null); then
    case "$root_snapshot" in
      *'fops marker absent from every reclaim socket; holding reclaim'*) root_result=fail; break ;;
      *'ROOT_ACTIONS=FAIL'*) root_result=fail; break ;;
      *'[exec] ./device-root-actions.sh exited status=0'*)
        case "$root_snapshot" in *'ROOT_ACTIONS=PASS'*) root_result=pass ;; *) root_result=fail ;; esac
        break ;;
      *'[exec] ./device-root-actions.sh exited status='*) root_result=fail; break ;;
    esac
  fi
  sleep 2
done
adb_cmd pull "$REMOTE/root.log" "$RUN_DIR/root.log" >/dev/null 2>&1 || true
if [ -f "$RUN_DIR/root.log" ]; then
  sed -n 's/^\[journal\] //p' "$RUN_DIR/root.log" > "$RUN_DIR/root-actions.journal"
  if [ -s "$RUN_DIR/root-actions.journal" ]; then
    if command -v md5sum >/dev/null 2>&1; then
      journal_md5=$(md5sum "$RUN_DIR/root-actions.journal" | awk '{print $1}')
    else
      journal_md5=$(md5 -q "$RUN_DIR/root-actions.journal")
    fi
    printf '%s  %s\n' "$journal_md5" root-actions.journal > "$RUN_DIR/root-actions.journal.md5"
  fi
fi
[ "$root_result" = pass ] || fail "root actions did not pass: ${root_result:-timeout}; inspect ROOT_ROLLBACK before reboot"
grep -Fq '[exec] ./device-root-actions.sh exited status=0' "$RUN_DIR/root.log" || fail 'root action exit status missing'
[ -s "$RUN_DIR/root-actions.journal" ] || fail 'root action journal missing or empty'
[ "$(tail -n 1 "$RUN_DIR/root-actions.journal")" = complete ] || fail 'root action journal incomplete'
announce_phase QA_PRE_REBOOT
qa PRE_REBOOT

announce_phase REBOOT
adb_cmd reboot >/dev/null
adb_cmd wait-for-device >/dev/null
boot_complete=no
boot_deadline=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$boot_deadline" ]; do
  boot_value=$(python3 "$HERE/run-bounded.py" 10 "$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') || boot_value=
  if [ "$boot_value" = 1 ]; then boot_complete=yes; break; fi
  sleep 2
done
[ "$boot_complete" = yes ] || fail 'boot did not complete within 300 seconds'
python3 "$HERE/run-bounded.py" 60 "$ADB" connect "$NETWORK_SERIAL" >/dev/null 2>&1 || true
sleep 5
announce_phase QA_POST_REBOOT
qa POST_REBOOT
[ "$(adb_shell id -u | tr -d '\r')" = 2000 ] || fail 'temporary root persisted unexpectedly'
[ "$(adb_shell getenforce | tr -d '\r')" = Enforcing ] || fail 'SELinux changed after reboot'

announce_phase SCREENSHOT
adb_shell screencap -p /sdcard/mantis-home-postboot.png
adb_cmd pull /sdcard/mantis-home-postboot.png "$RUN_DIR/mantis-home-postboot.png" >/dev/null
adb_shell rm -f /sdcard/mantis-home-postboot.png
printf '%s\n' 'DEPLOY=PASS'
printf 'SCREENSHOT=%s\n' "$RUN_DIR/mantis-home-postboot.png"
DEPLOY_COMPLETE=yes
