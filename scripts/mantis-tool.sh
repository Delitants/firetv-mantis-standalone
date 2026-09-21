#!/bin/sh
set -eu

ADB=adb
CURL=curl
AAPT=aapt
APKSIGNER=apksigner
SHA256_TOOL=
SERIAL=
NETWORK_SERIAL=
YES=no
COMMAND=
COMMAND_ARG=
OUTPUT=
BASELINE=
CR=$(printf '\r')
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
MANIFEST_DIR=$SCRIPT_DIR/../manifests

usage() {
  printf '%s\n' 'usage: mantis-tool.sh [--adb PATH] [--curl PATH] [--aapt PATH] [--apksigner PATH] [--sha256 PATH] --serial SERIAL [--network-serial SERIAL:5555] [--baseline AUDIT_DIRECTORY] [--output DIR] [--yes] audit|plan|apply|install-wolf|restore BACKUP_DIRECTORY|verify|verify-settings' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --adb)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      ADB=$2
      shift 2
      ;;
    --curl)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      CURL=$2
      shift 2
      ;;
    --aapt)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      AAPT=$2
      shift 2
      ;;
    --apksigner)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      APKSIGNER=$2
      shift 2
      ;;
    --sha256)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      SHA256_TOOL=$2
      shift 2
      ;;
    --serial)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      SERIAL=$2
      shift 2
      ;;
    --network-serial)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      NETWORK_SERIAL=$2
      shift 2
      ;;
    --yes)
      YES=yes
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      OUTPUT=$2
      shift 2
      ;;
    --baseline)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      BASELINE=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 64
      ;;
    *)
      COMMAND=$1
      shift
      break
      ;;
  esac
done

[ -n "$COMMAND" ] || { usage; exit 64; }
if [ "$COMMAND" = restore ]; then
  [ "$#" -eq 1 ] || { usage; exit 64; }
  COMMAND_ARG=$1
else
  [ "$#" -eq 0 ] || { usage; exit 64; }
fi
[ -n "$SERIAL" ] || { printf '%s\n' '--serial is required for device commands' >&2; exit 64; }

adb_cmd() {
  "$ADB" -s "$SERIAL" "$@"
}

adb_shell() {
  adb_cmd shell "$@"
}
network_adb_cmd() { "$ADB" -s "${NETWORK_SERIAL:-$SERIAL}" "$@"; }
network_read_prop() { network_adb_cmd shell getprop "$1"; }
require_network_target() {
  for pair in 'ro.product.manufacturer:Amazon' 'ro.product.model:AFTMM' 'ro.product.device:mantis' 'ro.build.id:NS6711' 'ro.build.version.incremental:0011644900484'; do
    key=${pair%%:*}; expected=${pair#*:}; actual=$(network_read_prop "$key") || return 1
    [ "$actual" = "$expected" ] || { printf 'network target %s expected=%s actual=%s\n' "$key" "$expected" "$actual" >&2; return 1; }
  done
  primary_serial=$(adb_shell getprop ro.serialno) || return 1
  network_serial_value=$(network_adb_cmd shell getprop ro.serialno) || return 1
  [ -n "$primary_serial" ] && [ "$primary_serial" = "$network_serial_value" ] || { printf '%s\n' 'primary and network device identity mismatch' >&2; return 1; }
}

validate_manifests() {
  python3 -B "$SCRIPT_DIR/../tests/verify-manifests.py" "$MANIFEST_DIR"
}

strip_one_trailing_cr() {
  NORMALIZED=$1
  case "$NORMALIZED" in
    *"$CR") NORMALIZED=${NORMALIZED%"$CR"} ;;
  esac
}

read_shell() {
  if ! ACTUAL=$(adb_shell "$@"); then
    printf 'adb shell failed: %s\n' "$*" >&2
    return 1
  fi
  strip_one_trailing_cr "$ACTUAL"
  ACTUAL=$NORMALIZED
}

prop_label() {
  case "$1" in
    ro.product.manufacturer) printf '%s' manufacturer ;;
    ro.product.model) printf '%s' model ;;
    ro.product.device) printf '%s' device ;;
    ro.build.id) printf '%s' build_id ;;
    ro.build.version.incremental) printf '%s' incremental ;;
    ro.build.version.release) printf '%s' release ;;
    ro.build.version.sdk) printf '%s' sdk ;;
    ro.product.cpu.abi) printf '%s' abi ;;
  esac
}

expect_prop() {
  property=$1
  expected=$2
  if ! read_shell getprop "$property"; then
    return 1
  fi
  if [ "$ACTUAL" != "$expected" ]; then
    printf '%s expected=%s actual=%s\n' "$(prop_label "$property")" "$expected" "$ACTUAL" >&2
    return 1
  fi
}

expect_shell() {
  case "$1" in
    uname)
      shell_name="$1 $2"
      expected=$3
      if ! read_shell "$1" "$2"; then
        return 1
      fi
      ;;
    getenforce)
      shell_name=$1
      expected=$2
      if ! read_shell "$1"; then
        return 1
      fi
      ;;
  esac
  if [ "$ACTUAL" != "$expected" ]; then
    printf '%s expected=%s actual=%s\n' "$shell_name" "$expected" "$ACTUAL" >&2
    return 1
  fi
}

require_shell_uid() {
  expected=$1
  if ! read_shell id -u; then
    return 1
  fi
  if [ "$ACTUAL" != "$expected" ]; then
    printf 'uid expected=%s actual=%s\n' "$expected" "$ACTUAL" >&2
    return 1
  fi
}

target_matches() {
  target_ok=yes
  expect_prop ro.product.manufacturer Amazon || target_ok=no
  expect_prop ro.product.model AFTMM || target_ok=no
  expect_prop ro.product.device mantis || target_ok=no
  expect_prop ro.build.id NS6711 || target_ok=no
  expect_prop ro.build.version.incremental 0011644900484 || target_ok=no
  expect_prop ro.build.version.release 7.1.2 || target_ok=no
  expect_prop ro.build.version.sdk 25 || target_ok=no
  expect_prop ro.product.cpu.abi armeabi-v7a || target_ok=no
  expect_shell uname -m armv7l || target_ok=no
  expect_shell getenforce Enforcing || target_ok=no
  require_shell_uid 2000 || target_ok=no
  [ "$target_ok" = yes ]
}

require_target() {
  target_matches || { printf '%s\n' 'target gate rejected this device' >&2; exit 1; }
}

package_state_capability() {
  PACKAGE_STATE_CAPABILITY=none
  capture_package_help || return 0
  help_proves_pm_state_command "$PACKAGE_HELP_OUTPUT" disable-user || return 0
  help_proves_pm_state_command "$PACKAGE_HELP_OUTPUT" enable || return 0
  PACKAGE_STATE_CAPABILITY=pm-disable-enable
}

capture_package_help() {
  PACKAGE_HELP_STATUS=0
  PACKAGE_HELP_OUTPUT=$(adb_shell pm help 2>&1) || PACKAGE_HELP_STATUS=$?
  strip_one_trailing_cr "$PACKAGE_HELP_OUTPUT"
  PACKAGE_HELP_OUTPUT=$NORMALIZED
  [ -n "$PACKAGE_HELP_OUTPUT" ] || return 1
  [ "$PACKAGE_HELP_STATUS" -eq 0 ] && return 0
  [ "$PACKAGE_HELP_STATUS" -eq 1 ] || return 1
  if ! PACKAGE_HELP_TRANSPORT=$(adb_cmd get-state 2>/dev/null); then
    return 1
  fi
  strip_one_trailing_cr "$PACKAGE_HELP_TRANSPORT"
  [ "$NORMALIZED" = device ]
}

help_proves_pm_state_command() {
  printf '%s\n' "$1" | awk -v command="$2" '
    {
      command_field = 0
      if ($1 == command) command_field = 1
      else if ($1 == "pm" && $2 == command) command_field = 2
      if (!command_field) next
      usage = 1
      user = 0
      package = 0
      for (field = command_field + 1; field <= NF; field++) {
        token = $field
        gsub(/^\[/, "", token)
        gsub(/\]$/, "", token)
        if (token == "--user" && !user && field < NF) {
          field++
          user = $field
          gsub(/^\[/, "", user)
          gsub(/\]$/, "", user)
          if (user == "USER_ID") user = 1
          else usage = 0
        } else if ((token == "PACKAGE" || token == "PACKAGE_OR_COMPONENT") && field == NF) {
          package = 1
        } else {
          usage = 0
        }
      }
      if (usage && user && package) found = 1
    }
    END { exit found ? 0 : 1 }
  '
}

write_shell_capture() {
  audit_file=$1
  shift
  read_shell "$@" || return 1
  printf '%s\n' "$ACTUAL" > "$audit_file"
}

write_labeled_shell_capture() {
  audit_file=$1
  label=$2
  shift 2
  read_shell "$@" || return 1
  printf '%s=%s\n' "$label" "$ACTUAL" > "$audit_file"
}

write_device_snapshot() {
  audit_file=$1
  : > "$audit_file"
  for property in \
    ro.product.manufacturer ro.product.model ro.product.device ro.build.id \
    ro.build.version.incremental ro.build.version.release ro.build.version.sdk \
    ro.product.cpu.abi persist.sys.locale system_locales
  do
    read_shell getprop "$property" || return 1
    printf '%s=%s\n' "$property" "$ACTUAL" >> "$audit_file"
  done
  read_shell uname -m || return 1
  printf 'uname -m=%s\n' "$ACTUAL" >> "$audit_file"
  read_shell getenforce || return 1
  printf 'getenforce=%s\n' "$ACTUAL" >> "$audit_file"
  read_shell id -u || return 1
  printf 'uid=%s\n' "$ACTUAL" >> "$audit_file"
}

write_settings_route_resolvers() {
  audit_file=$1
  : > "$audit_file"
  settings_route_lines | while IFS='|' read -r action expected_component expected_focus route_kind; do
    read_shell cmd package resolve-activity --brief -a "$action" || return 1
    printf '%s=%s\n' "$action" "$ACTUAL" >> "$audit_file"
  done
}

write_verification_baseline() {
  audit_file=$1
  : > "$audit_file"
  for key in \
    persist.sys.locale system_locales persist.sys.usb.config sys.usb.config \
    service.adb.tcp.port persist.adb.tcp.port init.svc.adbd
  do
    read_shell getprop "$key" || return 1
    printf '%s=%s\n' "$key" "$ACTUAL" >> "$audit_file"
  done
  for key in bluetooth_on adb_enabled development_settings_enabled; do
    read_shell settings get global "$key" || return 1
    printf '%s=%s\n' "$key" "$ACTUAL" >> "$audit_file"
  done
  for key in always_on_vpn_app always_on_vpn_lockdown; do
    read_shell settings get secure "$key" || return 1
    printf '%s=%s\n' "$key" "$ACTUAL" >> "$audit_file"
  done
  if read_shell ip link show tun0; then
    printf 'tun0=present\n' >> "$audit_file"
  else
    printf 'tun0=absent\n' >> "$audit_file"
  fi
}

write_tun0_capture() {
  audit_file=$1
  if read_shell ip link show tun0; then printf '%s\n' "$ACTUAL" > "$audit_file"; else printf '%s\n' absent > "$audit_file"; fi
}

# action|resolved component|expected visible component|access path
settings_route_lines() {
  cat <<'EOF'
android.settings.SETTINGS|com.amazon.tv.launcher/.ui.SettingsActivity|com.amazon.tv.launcher/.ui.MainSettingsActivity|stock-menu
android.settings.WIFI_SETTINGS|com.amazon.tv.settings.v2/.tv.network.NetworkActivity|com.amazon.tv.settings.v2/.tv.network.NetworkActivity|shell
android.settings.MANAGE_APPLICATIONS_SETTINGS|com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity|com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity|shell
android.settings.CONTROLLERS_SETTINGS|com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity|com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity|shell
android.settings.DEVICE_INFO_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity|com.amazon.tv.settings.v2/.tv.device.DeviceActivity|shell
android.settings.ACCESSIBILITY_SETTINGS|com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity|com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity|stock-menu
android.settings.DISPLAY_SETTINGS|com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity|com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity|stock-menu
com.amazon.device.settings.action.DATE_TIME|com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity|com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity|stock-menu
com.amazon.device.settings.action.LANGUAGE|com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity|com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity|stock-menu
android.settings.APPLICATION_DEVELOPMENT_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity|com.amazon.tv.settings.v2/.tv.device.DeviceActivity|shell
EOF
}

write_restore_script() {
  audit_file=$1
  cat > "$audit_file" <<EOF
#!/bin/sh
set -eu

ADB=\${ADB:-adb}
: "\${SERIAL:?set SERIAL to the target adb serial}"
backup_dir=\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)
MANTIS_TOOL=\${MANTIS_TOOL:-$SCRIPT_DIR/mantis-tool.sh}
[ -x "\$MANTIS_TOOL" ] || {
  printf '%s\n' 'set MANTIS_TOOL to the reviewed executable mantis-tool.sh' >&2
  exit 1
}

if [ -n "\${NETWORK_SERIAL:-}" ]; then
  exec "\$MANTIS_TOOL" --adb "\$ADB" --serial "\$SERIAL" \
    --network-serial "\$NETWORK_SERIAL" restore "\$backup_dir"
fi
exec "\$MANTIS_TOOL" --adb "\$ADB" --serial "\$SERIAL" restore "\$backup_dir"
EOF
  chmod 700 "$audit_file"
}

checksum_files() {
  audit_dir=$1
  (
    cd "$audit_dir"
    checksum_tmp=SHA256SUMS.tmp.$$
    find . -type f ! -name 'SHA256SUMS*' -print | sed 's#^./##' | LC_ALL=C sort |
    while IFS= read -r audit_file; do
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$audit_file"
      else
        shasum -a 256 "$audit_file"
      fi
    done > "$checksum_tmp"
    mv -f "$checksum_tmp" SHA256SUMS
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c SHA256SUMS >/dev/null
    else
      shasum -a 256 -c SHA256SUMS >/dev/null
    fi
  )
}

audit_directory() {
  if [ -n "$OUTPUT" ]; then
    printf '%s' "$OUTPUT"
  else
    printf 'mantis-audit-%s' "$(date -u +%Y%m%dT%H%M%SZ)"
  fi
}

retain_staging() {
  printf 'audit staging retained for inspection: %s\n' "$1" >&2
}

publish_audit() {
  final_dir=$(audit_directory)
  [ ! -e "$final_dir" ] && [ ! -L "$final_dir" ] || { printf 'audit output already exists: %s\n' "$final_dir" >&2; return 1; }
  final_parent=$(dirname "$final_dir")
  [ -d "$final_parent" ] || { printf 'audit output parent does not exist: %s\n' "$final_parent" >&2; return 1; }
  work_dir=$(mktemp -d "$final_dir.tmp.XXXXXX") || return 1
  if ! stage_identity=$(python3 "$script_dir/atomic-rename.py" inspect "$work_dir"); then
    retain_staging "$work_dir"
    return 1
  fi
  stage_device=${stage_identity%% *}
  stage_inode=${stage_identity#* }
  case "$stage_device:$stage_inode" in
    *[!0-9:]*|*:*:*)
      retain_staging "$work_dir"
      return 1
      ;;
  esac
  if ! write_device_snapshot "$work_dir/device.txt" ||
    ! write_shell_capture "$work_dir/packages-enabled.txt" pm list packages -e ||
    ! write_shell_capture "$work_dir/packages-all.txt" pm list packages -u ||
    ! write_shell_capture "$work_dir/packages-disabled.txt" pm list packages -d ||
    ! cat "$MANIFEST_DIR/preserve-core.txt" "$MANIFEST_DIR/preserve-user-apps.txt" | LC_ALL=C sort -u > "$work_dir/protected-apps.txt" ||
    ! write_shell_capture "$work_dir/home-directory.txt" printenv HOME ||
    ! write_labeled_shell_capture "$work_dir/bluetooth.txt" bluetooth_on settings get global bluetooth_on ||
    ! write_tun0_capture "$work_dir/tun0.txt" ||
    ! write_verification_baseline "$work_dir/verification-baseline.txt" ||
    ! write_settings_route_resolvers "$work_dir/settings-route-resolvers.txt" ||
    ! write_shell_capture "$work_dir/home-resolver.txt" cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME ||
    ! printf 'PACKAGE_OPERATION=%s\nPACKAGE_RESTORE=%s\n' \
      "${PACKAGE_OPERATION:-unsupported}" "${PACKAGE_RESTORE:-unsupported}" > "$work_dir/package-mode.txt" ||
    ! write_restore_script "$work_dir/restore-user0.sh" "$PACKAGE_STATE_CAPABILITY" ||
    ! : > "$work_dir/disabled-successfully.txt" ||
    ! : > "$work_dir/operation-journal.txt" ||
    ! : > "$work_dir/restore-journal.txt" ||
    ! checksum_files "$work_dir"
  then
    retain_staging "$work_dir"
    return 1
  fi
  if ! python3 "$script_dir/atomic-rename.py" publish "$work_dir" "$final_dir" "$stage_device" "$stage_inode"; then
    retain_staging "$work_dir"
    printf 'audit output publication conflict: %s\n' "$final_dir" >&2
    return 1
  fi
  PUBLISHED_AUDIT_DIR=$final_dir
  printf 'AUDIT_OUTPUT=%s\n' "$final_dir"
}

audit() {
  if target_matches; then
    printf '%s\n' 'SUPPORTED_MUTATION_TARGET=YES'
  else
    printf '%s\n' 'SUPPORTED_MUTATION_TARGET=NO'
  fi
  printf '%s\n' 'ROOT=NOT_ACHIEVED'
  package_state_capability
  if [ "$PACKAGE_STATE_CAPABILITY" = pm-disable-enable ]; then
    PACKAGE_OPERATION='pm disable-user --user 0'
    PACKAGE_RESTORE='pm enable --user 0'
  else
    PACKAGE_OPERATION=unsupported
    PACKAGE_RESTORE=unsupported
  fi
  printf 'PACKAGE_OPERATION=%s\n' "$PACKAGE_OPERATION"
  printf 'PACKAGE_RESTORE=%s\n' "$PACKAGE_RESTORE"
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  publish_audit
  printf '%s\n' 'AUDIT=PASS'
}

require_package_state_capability() {
  package_state_capability
  [ "$PACKAGE_STATE_CAPABILITY" = pm-disable-enable ] || {
    printf '%s\n' 'no help-proven pm disable-user/enable commands are available' >&2
    exit 1
  }
  PACKAGE_OPERATION='pm disable-user --user 0'
  PACKAGE_RESTORE='pm enable --user 0'
}

restore_command() {
  [ "$PACKAGE_STATE_CAPABILITY" = pm-disable-enable ] || return 1
  printf '%s\n' 'pm enable'
}

restore_package() {
  [ "$PACKAGE_STATE_CAPABILITY" = pm-disable-enable ] || return 1
  RESTORE_ENABLE_STATUS=0
  adb_shell pm enable --user 0 "$1" || RESTORE_ENABLE_STATUS=$?
  capture_package_state "$1" || return 1
  package_list_contains "$PACKAGE_ENABLED" "$1" || {
    printf 'restore verification failed for %s: not enabled\n' "$1" >&2
    return 1
  }
  if package_list_contains "$PACKAGE_DISABLED" "$1"; then
    printf 'restore verification failed for %s: still disabled\n' "$1" >&2
    return 1
  fi
}

package_list_contains() {
  package_list=$1
  package=$2
  printf '%s\n' "$package_list" | awk -v package="$package" '$0 == "package:" package { found = 1 } END { exit found ? 0 : 1 }'
}

active_package_list() {
  read_shell pm list packages -e || return 1
  ACTIVE_PACKAGES=$ACTUAL
}

capture_package_state() {
  state_package=$1
  read_shell pm list packages -e || return 1
  PACKAGE_ENABLED=$ACTUAL
  read_shell pm list packages -d || return 1
  PACKAGE_DISABLED=$ACTUAL
}

require_active_packages() {
  active_packages=$1
  shift
  for required_package in "$@"; do
    package_list_contains "$active_packages" "$required_package" || {
      printf 'guard missing enabled package: %s\n' "$required_package" >&2
      return 1
    }
  done
}

require_preserved_active_packages() {
  active_packages=$1
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  for preserve_manifest in "$MANIFEST_DIR/preserve-core.txt" "$MANIFEST_DIR/preserve-user-apps.txt"; do
    while IFS= read -r required_package; do
      package_list_contains "$active_packages" "$required_package" || {
        printf 'guard missing enabled package: %s\n' "$required_package" >&2
        return 1
      }
    done < "$preserve_manifest"
  done
}

require_usb_adb() {
  usb_value=$1
  case ",$usb_value," in
    *,adb,*|*",adb,"*) ;;
    *) printf 'guard requires USB configuration containing adb: %s\n' "$usb_value" >&2; return 1 ;;
  esac
}

read_guard_value() {
  guard_label=$1
  shift
  read_shell "$@" || {
    printf 'guard could not read %s\n' "$guard_label" >&2
    return 1
  }
  GUARD_VALUE=$ACTUAL
}

read_adb_transport() {
  if ! GUARD_VALUE=$(network_adb_cmd get-state); then
    printf '%s\n' 'guard could not reach TCP adb transport' >&2
    return 1
  fi
  strip_one_trailing_cr "$GUARD_VALUE"
  GUARD_VALUE=$NORMALIZED
}

require_wolf_version() {
  read_shell dumpsys package "$WOLF_PACKAGE" || {
    printf '%s\n' 'guard could not inspect Wolf Launcher' >&2
    return 1
  }
  wolf_print_installed_identity "$ACTUAL"
  [ "$WOLF_INSTALLED_VERSION_CODE" = "$WOLF_VERSION_CODE" ] || {
    printf 'guard Wolf version code expected=%s actual=%s\n' "$WOLF_VERSION_CODE" "$WOLF_INSTALLED_VERSION_CODE" >&2
    return 1
  }
  [ "$WOLF_INSTALLED_VERSION_NAME" = "$WOLF_VERSION_NAME" ] || {
    printf 'guard Wolf version name expected=%s actual=%s\n' "$WOLF_VERSION_NAME" "$WOLF_INSTALLED_VERSION_NAME" >&2
    return 1
  }
}

require_wolf_ready() {
  require_wolf_version || return 1
  wolf_launch=$(adb_shell am start -n "$WOLF_COMPONENT") || {
    printf '%s\n' 'Wolf Launcher direct launch failed' >&2
    return 1
  }
  case "$wolf_launch" in
    *'Starting: Intent'*) ;;
    *) printf '%s\n' 'Wolf Launcher direct launch did not report a launch intent' >&2; return 1 ;;
  esac
  wolf_try=0
  while :; do
    read_shell dumpsys window windows || return 1
    wolf_focus=$(printf '%s\n' "$ACTUAL" | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^} ]*\).*/\1/p' | head -n 1)
    case "$wolf_focus" in "$WOLF_COMPONENT"|"$WOLF_PACKAGE/$WOLF_PACKAGE.${WOLF_ACTIVITY#*.}") break ;; esac
    wolf_try=$((wolf_try + 1)); [ "$wolf_try" -lt 3 ] || { printf 'Wolf Launcher focus expected=%s actual=%s\n' "$WOLF_COMPONENT" "$wolf_focus" >&2; return 1; }
    sleep 1
  done
}

require_settings_routes() {
  settings_route_lines | while IFS='|' read -r settings_action expected_component expected_focus route_kind; do
    read_shell cmd package resolve-activity --brief -a "$settings_action" || { settings_cleanup; exit 1; }
    [ "$ACTUAL" = "$expected_component" ] || {
      printf 'Settings resolver expected=%s actual=%s action=%s\n' "$expected_component" "$ACTUAL" "$settings_action" >&2
      exit 1
    }
  done
}

verify_active_packages() {
  active_package_list || return 1
  require_preserved_active_packages "$ACTIVE_PACKAGES" || return 1
  require_active_packages "$ACTIVE_PACKAGES" ar.tvplayer.tv com.wireguard.android tv.sweet.tvplayer || return 1
}

verify_value() {
  verify_label=$1
  verify_expected=$2
  shift 2
  read_guard_value "$verify_label" "$@" || return 1
  [ "$GUARD_VALUE" = "$verify_expected" ] || {
    printf 'verify %s expected=%s actual=%s\n' "$verify_label" "$verify_expected" "$GUARD_VALUE" >&2
    return 1
  }
}

verify_usb_adb() {
  verify_label=$1
  shift
  read_guard_value "$verify_label" "$@" || return 1
  require_usb_adb "$GUARD_VALUE" || {
    printf 'verify requires USB configuration containing adb: %s\n' "$GUARD_VALUE" >&2
    return 1
  }
}

verify_tcp_8009() {
  require_tcp_8009 || return 1
  printf '%s\n' 'TCP8009=PASS'
  # A listener is only transport evidence. It cannot establish that a person
  # or a non-ADB remote successfully moved the live Fire TV UI.
  printf '%s\n' 'NETWORK_REMOTE_OBSERVED=UNVERIFIED'
}

verify_adb_persistence() {
  case "$SERIAL" in
    *:5555) ;;
    *) [ -n "$NETWORK_SERIAL" ] || { printf '%s\n' 'USB primary requires --network-serial ending in :5555' >&2; return 1; } ;;
  esac
  case "${NETWORK_SERIAL:-$SERIAL}" in
    *:5555) ;;
    *) printf '%s\n' 'network serial must end in :5555' >&2; return 1 ;;
  esac
  require_network_target || return 1
  verify_value adb_enabled 1 settings get global adb_enabled || return 1
  # Fire OS on this target legitimately reports no value for this setting.
  verify_value development_settings_enabled null settings get global development_settings_enabled || return 1
  verify_value init.svc.adbd running getprop init.svc.adbd || {
    printf '%s\n' 'verify adbd is not running' >&2
    return 1
  }
  verify_usb_adb persist.sys.usb.config getprop persist.sys.usb.config || return 1
  verify_usb_adb sys.usb.config getprop sys.usb.config || return 1
  verify_value service.adb.tcp.port 5555 getprop service.adb.tcp.port || return 1
  baseline_file=$BASELINE/verification-baseline.txt
  baseline_persist_port=$(sed -n 's/^persist.adb.tcp.port=//p' "$baseline_file" | head -n 1)
  verify_value persist.adb.tcp.port "$baseline_persist_port" getprop persist.adb.tcp.port || return 1
  read_adb_transport || return 1
  [ "$GUARD_VALUE" = device ] || {
    printf 'verify TCP 5555 is not reachable: %s\n' "$GUARD_VALUE" >&2
    return 1
  }
  printf '%s\n' 'ADB_PERSISTENCE=PASS'
  printf 'NETWORK_ADB_SERIAL=%s\n' "${NETWORK_SERIAL:-$SERIAL}"
  # USB properties prove configuration only. Enumeration needs an independent
  # physical-host observation and is intentionally not inferred here.
  printf '%s\n' 'USB_PHYSICAL_ENUMERATION=UNVERIFIED'
}

verify_vpn_and_locale() {
  [ -n "$BASELINE" ] || { printf '%s\n' '--baseline is required for verify' >&2; return 1; }
  verify_backup_integrity "$BASELINE" || { printf '%s\n' 'baseline integrity verification failed' >&2; return 1; }
  baseline_file=$BASELINE/verification-baseline.txt
  [ -f "$baseline_file" ] || { printf '%s\n' 'baseline verification state is missing' >&2; return 1; }
  baseline_value() { sed -n "s/^$1=//p" "$baseline_file" | head -n 1; }
  verify_value locale "$(baseline_value persist.sys.locale)" getprop persist.sys.locale || return 1
  verify_value system_locales "$(baseline_value system_locales)" getprop system_locales || return 1
  verify_value always_on_vpn_app "$(baseline_value always_on_vpn_app)" settings get secure always_on_vpn_app || return 1
  verify_value always_on_vpn_lockdown "$(baseline_value always_on_vpn_lockdown)" settings get secure always_on_vpn_lockdown || return 1
  capture_tun0_state
  expected_tun=$(baseline_value tun0)
  actual_tun=absent; [ "$GUARD_TUN0_STATE" != absent ] && actual_tun=present
  [ "$actual_tun" = "$expected_tun" ] || {
    printf 'verify tun0 expected=%s actual=%s\n' "$expected_tun" "$actual_tun" >&2
    return 1
  }
}

verify() {
  require_target
  validate_manifests
  verify_active_packages || exit 1
  require_wolf_ready || exit 1
  read_guard_value bluetooth_on settings get global bluetooth_on || exit 1
  [ "$GUARD_VALUE" = 1 ] || {
    printf 'verify bluetooth_on expected=1 actual=%s\n' "$GUARD_VALUE" >&2
    exit 1
  }
  verify_vpn_and_locale || exit 1
  require_home_resolver || exit 1
  require_settings_routes || exit 1
  verify_adb_persistence || exit 1
  verify_tcp_8009 || exit 1
  printf '%s\n' 'SETTINGS_ROUTES=PASS'
  printf '%s\n' 'VERIFY_GATE=PASS'
}

start_settings_action() {
  settings_action=$1
  if SETTINGS_START_OUTPUT=$(adb_shell am start -a "$settings_action" 2>&1); then
    SETTINGS_START_STATUS=0
  else
    SETTINGS_START_STATUS=$?
  fi
}
settings_cleanup() {
  adb_shell rm -f /sdcard/mantis-ui-smoke.xml >/dev/null 2>&1 || true
  adb_shell input keyevent 4 >/dev/null 2>&1 || true
  adb_shell input keyevent 3 >/dev/null 2>&1 || true
}

assert_settings_ui() {
  settings_action=$1
  expected_focus=$2
  tries=0
  while :; do
    read_shell dumpsys window windows || { settings_cleanup; return 1; }
    focus=$(printf '%s\n' "$ACTUAL" | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^} ]*\).*/\1/p' | head -n 1)
    normalize_component() { case "$1" in */.*) p=${1%%/*}; printf '%s/%s.%s\n' "$p" "$p" "${1#*/.}" ;; *) printf '%s\n' "$1" ;; esac; }
    [ "$(normalize_component "$focus")" = "$(normalize_component "$expected_focus")" ] && break
    tries=$((tries + 1)); [ "$tries" -lt 3 ] || { printf 'Settings focus expected=%s actual=%s action=%s\n' "$expected_focus" "$focus" "$settings_action" >&2; settings_cleanup; return 1; }
    sleep 1
  done
  read_shell uiautomator dump /sdcard/mantis-ui-smoke.xml || { settings_cleanup; return 1; }
  read_shell cat /sdcard/mantis-ui-smoke.xml || { settings_cleanup; return 1; }
  case "$ACTUAL" in
    *'<hierarchy'*'<node '*'</hierarchy>'*) ;;
    *) printf 'Settings UI hierarchy was empty: %s\n' "$settings_action" >&2; settings_cleanup; return 1 ;;
  esac
  settings_cleanup
}

stock_menu_settings_navigation() {
  # The component resolver remains the identity check. These key events keep
  # protected routes within stock UI; no shell settings launch or setting write
  # is attempted. A changed layout fails the subsequent focused-UI assertion.
  settings_action=$1
  settings_key() { adb_shell input keyevent "$@" >/dev/null || return 1; sleep 1; }
  settings_focus() {
    expected=$1
    read_shell dumpsys window windows || return 1
    actual=$(printf '%s\n' "$ACTUAL" | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^} ]*\).*/\1/p' | head -n 1)
    normalize() { case "$1" in */.*) p=${1%%/*}; printf '%s/%s.%s\n' "$p" "$p" "${1#*/.}" ;; *) printf '%s\n' "$1" ;; esac; }
    [ "$(normalize "$actual")" = "$(normalize "$expected")" ] || { printf 'Settings intermediate focus expected=%s actual=%s\n' "$expected" "$actual" >&2; return 1; }
  }
  settings_key --longpress 3 || return 1
  settings_focus com.amazon.tv.launcher/.HudActivity || return 1
  for n in 1 2 3 4; do settings_key 22 || return 1; done
  settings_key 23 || return 1
  settings_focus com.amazon.tv.launcher/.ui.MainSettingsActivity || return 1
  case "$settings_action" in
    android.settings.SETTINGS) ;;
    android.settings.DISPLAY_SETTINGS) settings_key 20 || return 1; settings_key 23 || return 1 ;;
    android.settings.ACCESSIBILITY_SETTINGS) for n in 1 2; do settings_key 20 || return 1; done; for n in 1 2; do settings_key 22 || return 1; done; settings_key 23 || return 1 ;;
    com.amazon.device.settings.action.DATE_TIME|com.amazon.device.settings.action.LANGUAGE)
      settings_key 20 || return 1; for n in 1 2; do settings_key 22 || return 1; done; settings_key 23 || return 1
      settings_focus com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity || return 1
      if [ "$settings_action" = com.amazon.device.settings.action.LANGUAGE ]; then for n in 1 2 3 4 5 6 7; do settings_key 20 || return 1; done; settings_key 23 || return 1; fi
      ;;
  esac
}

verify_settings() {
  require_target
  settings_route_lines | while IFS='|' read -r settings_action expected_component expected_focus route_kind; do
    read_shell cmd package resolve-activity --brief -a "$settings_action" || { settings_cleanup; exit 1; }
    [ "$ACTUAL" = "$expected_component" ] || {
      printf 'Settings resolver expected=%s actual=%s action=%s\n' "$expected_component" "$ACTUAL" "$settings_action" >&2
      settings_cleanup; return 1
    }
    start_settings_action "$settings_action"
    case "$route_kind:$SETTINGS_START_STATUS" in
      shell:0) ;;
      stock-menu:0) stock_menu_settings_navigation "$settings_action" || { settings_cleanup; exit 1; } ;;
      stock-menu:*)
        case "$SETTINGS_START_OUTPUT" in
          *com.amazon.tv.permission.LAUNCHER_SETTINGS*) ;;
          *) printf 'Settings direct launch did not show stock-menu permission denial: %s\n' "$settings_action" >&2; settings_cleanup; exit 1 ;;
        esac
        stock_menu_settings_navigation "$settings_action" || { settings_cleanup; exit 1; }
        ;;
      *)
        printf 'Settings action could not be opened: %s\n' "$settings_action" >&2
        settings_cleanup; exit 1
        ;;
    esac
    assert_settings_ui "$settings_action" "$expected_focus" || { settings_cleanup; exit 1; }
  done
  printf '%s\n' 'SETTINGS_ROUTES=PASS'
  printf '%s\n' 'DEVELOPER_OPTIONS=PASS'
  printf '%s\n' 'UI_SMOKE=PASS'
  printf '%s\n' 'VERIFY_SETTINGS=PASS'
}

require_home_resolver() {
  read_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME || return 1
  [ "$ACTUAL" = com.amazon.tv.launcher/.HomeActivity ] || {
    printf 'guard HOME resolver expected=com.amazon.tv.launcher/.HomeActivity actual=%s\n' "$ACTUAL" >&2
    return 1
  }
}

require_tcp_8009() {
  read_shell netstat -ltn || return 1
  printf '%s\n' "$ACTUAL" | awk '/[:.]8009[[:space:]].*LISTEN/ { found = 1 } END { exit found ? 0 : 1 }' || {
    printf '%s\n' 'guard TCP 8009 is not listening' >&2
    return 1
  }
}

capture_tun0_state() {
  if tun0_output=$(adb_shell ip link show tun0); then
    strip_one_trailing_cr "$tun0_output"
    [ -n "$NORMALIZED" ] && GUARD_TUN0_STATE=present || GUARD_TUN0_STATE=absent
  else
    GUARD_TUN0_STATE=absent
  fi
}

capture_guard_baseline() {
  case "$SERIAL" in *:5555) ;; *) [ -n "$NETWORK_SERIAL" ] || { printf '%s\n' 'USB primary requires --network-serial ending in :5555' >&2; return 1; } ;; esac
  require_network_target || return 1
  active_package_list || return 1
  require_preserved_active_packages "$ACTIVE_PACKAGES" || return 1
  require_wolf_ready || return 1
  read_guard_value bluetooth_on settings get global bluetooth_on || return 1
  GUARD_BLUETOOTH_ON=$GUARD_VALUE
  [ "$GUARD_BLUETOOTH_ON" = 1 ] || { printf 'guard bluetooth_on expected=1 actual=%s\n' "$GUARD_BLUETOOTH_ON" >&2; return 1; }
  read_guard_value locale getprop persist.sys.locale || return 1
  GUARD_LOCALE=$GUARD_VALUE
  read_guard_value system_locales getprop system_locales || return 1
  GUARD_SYSTEM_LOCALES=$GUARD_VALUE
  read_guard_value adb_enabled settings get global adb_enabled || return 1
  GUARD_ADB_ENABLED=$GUARD_VALUE
  [ "$GUARD_ADB_ENABLED" = 1 ] || { printf 'guard adb_enabled expected=1 actual=%s\n' "$GUARD_ADB_ENABLED" >&2; return 1; }
  read_guard_value development_settings_enabled settings get global development_settings_enabled || return 1
  GUARD_DEVELOPMENT_SETTINGS_ENABLED=$GUARD_VALUE
  # Fire OS on the supported build returns null while the stock Developer
  # Options screen remains accessible. Capture the observed value and require
  # it to stay unchanged after every package operation.
  read_guard_value persist_sys_usb_config getprop persist.sys.usb.config || return 1
  GUARD_PERSIST_USB_CONFIG=$GUARD_VALUE
  require_usb_adb "$GUARD_PERSIST_USB_CONFIG" || return 1
  read_guard_value sys_usb_config getprop sys.usb.config || return 1
  GUARD_SYS_USB_CONFIG=$GUARD_VALUE
  require_usb_adb "$GUARD_SYS_USB_CONFIG" || return 1
  read_guard_value service_adb_tcp_port getprop service.adb.tcp.port || return 1
  GUARD_SERVICE_ADB_TCP_PORT=$GUARD_VALUE
  [ "$GUARD_SERVICE_ADB_TCP_PORT" = 5555 ] || { printf 'guard service.adb.tcp.port expected=5555 actual=%s\n' "$GUARD_SERVICE_ADB_TCP_PORT" >&2; return 1; }
  read_guard_value persist_adb_tcp_port getprop persist.adb.tcp.port || return 1
  GUARD_PERSIST_ADB_TCP_PORT=$GUARD_VALUE
  read_guard_value init_svc_adbd getprop init.svc.adbd || return 1
  GUARD_INIT_SVC_ADBD=$GUARD_VALUE
  [ "$GUARD_INIT_SVC_ADBD" = running ] || { printf 'guard init.svc.adbd expected=running actual=%s\n' "$GUARD_INIT_SVC_ADBD" >&2; return 1; }
  read_guard_value adbd pidof adbd || return 1
  GUARD_ADBD_PID=$GUARD_VALUE
  [ -n "$GUARD_ADBD_PID" ] || { printf '%s\n' 'guard adbd is not running' >&2; return 1; }
  read_guard_value always_on_vpn_app settings get secure always_on_vpn_app || return 1
  GUARD_ALWAYS_ON_VPN_APP=$GUARD_VALUE
  read_guard_value always_on_vpn_lockdown settings get secure always_on_vpn_lockdown || return 1
  GUARD_ALWAYS_ON_VPN_LOCKDOWN=$GUARD_VALUE
  capture_tun0_state
  require_home_resolver || return 1
  require_tcp_8009 || return 1
  require_settings_routes || return 1
  case "${NETWORK_SERIAL:-$SERIAL}" in
    *:5555) ;;
    *) printf 'guard requires a TCP adb serial ending in :5555\n' >&2; return 1 ;;
  esac
  read_adb_transport || return 1
  [ "$GUARD_VALUE" = device ] || { printf 'guard TCP 5555 is not reachable: %s\n' "$GUARD_VALUE" >&2; return 1; }
}

read_baseline_value() {
  baseline_file=$1
  baseline_key=$2
  if ! BASELINE_VALUE=$(awk -F= -v key="$baseline_key" '
    $1 == key { count++; sub(/^[^=]*=/, ""); value = $0 }
    END { if (count != 1) exit 1; printf "%s", value }
  ' "$baseline_file"); then
    printf 'baseline key is missing or duplicated: %s\n' "$baseline_key" >&2
    return 1
  fi
}

load_guard_baseline() {
  baseline_dir=$1
  baseline_file=$baseline_dir/verification-baseline.txt
  [ -f "$baseline_file" ] && [ ! -L "$baseline_file" ] || {
    printf '%s\n' 'baseline verification state is missing' >&2
    return 1
  }
  read_baseline_value "$baseline_file" bluetooth_on || return 1; GUARD_BLUETOOTH_ON=$BASELINE_VALUE
  read_baseline_value "$baseline_file" persist.sys.locale || return 1; GUARD_LOCALE=$BASELINE_VALUE
  read_baseline_value "$baseline_file" system_locales || return 1; GUARD_SYSTEM_LOCALES=$BASELINE_VALUE
  read_baseline_value "$baseline_file" adb_enabled || return 1; GUARD_ADB_ENABLED=$BASELINE_VALUE
  read_baseline_value "$baseline_file" development_settings_enabled || return 1; GUARD_DEVELOPMENT_SETTINGS_ENABLED=$BASELINE_VALUE
  read_baseline_value "$baseline_file" persist.sys.usb.config || return 1; GUARD_PERSIST_USB_CONFIG=$BASELINE_VALUE
  read_baseline_value "$baseline_file" sys.usb.config || return 1; GUARD_SYS_USB_CONFIG=$BASELINE_VALUE
  read_baseline_value "$baseline_file" service.adb.tcp.port || return 1; GUARD_SERVICE_ADB_TCP_PORT=$BASELINE_VALUE
  read_baseline_value "$baseline_file" persist.adb.tcp.port || return 1; GUARD_PERSIST_ADB_TCP_PORT=$BASELINE_VALUE
  read_baseline_value "$baseline_file" init.svc.adbd || return 1; GUARD_INIT_SVC_ADBD=$BASELINE_VALUE
  read_baseline_value "$baseline_file" always_on_vpn_app || return 1; GUARD_ALWAYS_ON_VPN_APP=$BASELINE_VALUE
  read_baseline_value "$baseline_file" always_on_vpn_lockdown || return 1; GUARD_ALWAYS_ON_VPN_LOCKDOWN=$BASELINE_VALUE
  read_baseline_value "$baseline_file" tun0 || return 1; GUARD_BASELINE_TUN0_STATE=$BASELINE_VALUE
  [ "$GUARD_BLUETOOTH_ON" = 1 ] || return 1
  [ "$GUARD_ADB_ENABLED" = 1 ] || return 1
  require_usb_adb "$GUARD_PERSIST_USB_CONFIG" || return 1
  require_usb_adb "$GUARD_SYS_USB_CONFIG" || return 1
  [ "$GUARD_SERVICE_ADB_TCP_PORT" = 5555 ] || return 1
  [ "$GUARD_INIT_SVC_ADBD" = running ] || return 1
  case "$GUARD_BASELINE_TUN0_STATE" in present|absent) ;; *) return 1 ;; esac
  read_guard_value adbd pidof adbd || return 1
  GUARD_ADBD_PID=$GUARD_VALUE
  [ -n "$GUARD_ADBD_PID" ] || return 1
  case "$SERIAL" in
    *:5555) ;;
    *) [ -n "$NETWORK_SERIAL" ] || { printf '%s\n' 'USB primary requires --network-serial ending in :5555' >&2; return 1; } ;;
  esac
  case "${NETWORK_SERIAL:-$SERIAL}" in
    *:5555) ;;
    *) printf '%s\n' 'network serial must end in :5555' >&2; return 1 ;;
  esac
  require_network_target || return 1
}

guard_unchanged_value() {
  guard_label=$1
  expected_value=$2
  shift 2
  read_guard_value "$guard_label" "$@" || return 1
  [ "$GUARD_VALUE" = "$expected_value" ] || {
    printf 'guard changed %s expected=%s actual=%s\n' "$guard_label" "$expected_value" "$GUARD_VALUE" >&2
    return 1
  }
}

compact_guard() {
  active_package_list || return 1
  require_preserved_active_packages "$ACTIVE_PACKAGES" || return 1
  require_wolf_version || return 1
  guard_unchanged_value bluetooth_on "$GUARD_BLUETOOTH_ON" settings get global bluetooth_on || return 1
  guard_unchanged_value locale "$GUARD_LOCALE" getprop persist.sys.locale || return 1
  guard_unchanged_value system_locales "$GUARD_SYSTEM_LOCALES" getprop system_locales || return 1
  guard_unchanged_value adb_enabled "$GUARD_ADB_ENABLED" settings get global adb_enabled || return 1
  guard_unchanged_value development_settings_enabled "$GUARD_DEVELOPMENT_SETTINGS_ENABLED" settings get global development_settings_enabled || return 1
  guard_unchanged_value persist_sys_usb_config "$GUARD_PERSIST_USB_CONFIG" getprop persist.sys.usb.config || return 1
  require_usb_adb "$GUARD_VALUE" || return 1
  guard_unchanged_value sys_usb_config "$GUARD_SYS_USB_CONFIG" getprop sys.usb.config || return 1
  require_usb_adb "$GUARD_VALUE" || return 1
  guard_unchanged_value service_adb_tcp_port "$GUARD_SERVICE_ADB_TCP_PORT" getprop service.adb.tcp.port || return 1
  [ "$GUARD_VALUE" = 5555 ] || return 1
  guard_unchanged_value persist_adb_tcp_port "$GUARD_PERSIST_ADB_TCP_PORT" getprop persist.adb.tcp.port || return 1
  guard_unchanged_value init_svc_adbd "$GUARD_INIT_SVC_ADBD" getprop init.svc.adbd || return 1
  guard_unchanged_value adbd "$GUARD_ADBD_PID" pidof adbd || return 1
  [ -n "$GUARD_VALUE" ] || { printf '%s\n' 'guard adbd is not running' >&2; return 1; }
  guard_unchanged_value always_on_vpn_app "$GUARD_ALWAYS_ON_VPN_APP" settings get secure always_on_vpn_app || return 1
  guard_unchanged_value always_on_vpn_lockdown "$GUARD_ALWAYS_ON_VPN_LOCKDOWN" settings get secure always_on_vpn_lockdown || return 1
  capture_tun0_state
  [ "$GUARD_TUN0_STATE" = "$GUARD_BASELINE_TUN0_STATE" ] || {
    printf 'guard changed tun0 presence expected=%s actual=%s\n' "$GUARD_BASELINE_TUN0_STATE" "$GUARD_TUN0_STATE" >&2
    return 1
  }
  require_home_resolver || return 1
  require_tcp_8009 || return 1
  require_settings_routes || return 1
  require_network_target || return 1
  read_adb_transport || return 1
  [ "$GUARD_VALUE" = device ] || { printf 'guard TCP 5555 is not reachable: %s\n' "$GUARD_VALUE" >&2; return 1; }
}

rollback_recorded_packages() {
  removed_file=$1
  backup_dir=$(dirname "$removed_file")
  restore_journal=$backup_dir/restore-journal.txt
  rollback_file=$(mktemp "${TMPDIR:-/tmp}/mantis-rollback.XXXXXX") || return 1
  awk '{ lines[NR] = $0 } END { for (line = NR; line > 0; line--) print lines[line] }' "$removed_file" > "$rollback_file"
  rollback_ok=yes
  while IFS= read -r rollback_package; do
    [ -n "$rollback_package" ] || continue
    recorded_package_exists "$removed_file" "$rollback_package" || continue
    if ! restore_recorded_package "$backup_dir" "$rollback_package"; then
      printf 'rollback failed for %s\n' "$rollback_package" >&2
      rollback_ok=no
      break
    fi
  done < "$rollback_file"
  rm -f "$rollback_file"
  [ "$rollback_ok" = yes ]
}

rollback_batch() {
  failed_package=$1
  removed_file=$2
  journal_file=$3
  rollback_ok=yes
  if [ -n "$failed_package" ]; then
    printf 'rollback %s\n' "$failed_package" >> "$journal_file"
    if recorded_package_exists "$removed_file" "$failed_package"; then
      restore_recorded_package "$(dirname "$removed_file")" "$failed_package" || rollback_ok=no
    fi
  fi
  rollback_recorded_packages "$removed_file" || rollback_ok=no
  [ "$rollback_ok" = yes ]
}

refresh_backup_checksums() {
  checksum_files "$1" || {
    printf 'could not refresh backup checksums: %s\n' "$1" >&2
    return 1
  }
}

validate_recorded_package() {
  recorded_candidate=$1
  case "$recorded_candidate" in
    ''|*[!A-Za-z0-9._]*) return 1 ;;
  esac
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  awk -v package="$recorded_candidate" '$0 == package { found = 1 } END { exit found ? 0 : 1 }' "$MANIFEST_DIR/remove-user0.txt"
}

recorded_package_exists() {
  removed_file=$1
  searched_package=$2
  awk -v package="$searched_package" '$0 == package { found = 1 } END { exit found ? 0 : 1 }' "$removed_file"
}

replace_recorded_ledger() {
  removed_file=$1
  replacement_file=$2
  [ -f "$replacement_file" ] || return 1
  mv -f "$replacement_file" "$removed_file" || return 1
  refresh_backup_checksums "$(dirname "$removed_file")"
}

append_recorded_package() {
  removed_file=$1
  ledger_package=$2
  recorded_package_exists "$removed_file" "$ledger_package" && return 0
  ledger_tmp="$removed_file.tmp.$$"
  { cat "$removed_file"; printf '%s\n' "$ledger_package"; } > "$ledger_tmp" || return 1
  replace_recorded_ledger "$removed_file" "$ledger_tmp"
}

remove_recorded_package() {
  removed_file=$1
  ledger_package=$2
  ledger_tmp="$removed_file.tmp.$$"
  awk -v package="$ledger_package" '$0 != package { print }' "$removed_file" > "$ledger_tmp" || return 1
  replace_recorded_ledger "$removed_file" "$ledger_tmp"
}

append_restore_record() {
  backup_dir=$1
  restore_state=$2
  restore_target=$3
  printf '%s %s\n' "$restore_state" "$restore_target" >> "$backup_dir/restore-journal.txt" || return 1
  refresh_backup_checksums "$backup_dir"
}

restore_recorded_package() {
  backup_dir=$1
  restore_target=$2
  removed_file=$backup_dir/disabled-successfully.txt
  capture_package_state "$restore_target" || return 1
  if package_list_contains "$PACKAGE_ENABLED" "$restore_target" ||
    ! package_list_contains "$PACKAGE_DISABLED" "$restore_target"
  then
    printf 'restore precondition failed for %s\n' "$restore_target" >&2
    return 1
  fi
  append_restore_record "$backup_dir" attempt "$restore_target" || return 1
  if restore_package "$restore_target"; then
    if [ "$RESTORE_ENABLE_STATUS" -eq 0 ]; then restore_result=success
    else restore_result=success-after-error
    fi
    append_restore_record "$backup_dir" "$restore_result" "$restore_target" || return 1
  else
    append_restore_record "$backup_dir" failure "$restore_target" || return 1
    return 1
  fi
  if ! compact_guard; then
    append_restore_record "$backup_dir" guard-failure "$restore_target" || true
    return 1
  fi
  remove_recorded_package "$removed_file" "$restore_target"
}

reconcile_attempted_enables() {
  backup_dir=$1
  removed_file=$backup_dir/disabled-successfully.txt
  restore_journal=$backup_dir/restore-journal.txt
  restore_snapshot=$(mktemp "${TMPDIR:-/tmp}/mantis-restore-journal.XXXXXX") || return 1
  cp "$restore_journal" "$restore_snapshot" || { rm -f "$restore_snapshot"; return 1; }
  reconcile_ok=yes
  while IFS=' ' read -r restore_state restore_target restore_extra; do
    [ "$restore_state" = attempt ] || continue
    [ -z "${restore_extra:-}" ] || { reconcile_ok=no; break; }
    recorded_package_exists "$removed_file" "$restore_target" || continue
    capture_package_state "$restore_target" || { reconcile_ok=no; break; }
    if package_list_contains "$PACKAGE_ENABLED" "$restore_target" &&
      ! package_list_contains "$PACKAGE_DISABLED" "$restore_target"
    then
      if ! compact_guard; then
        append_restore_record "$backup_dir" guard-failure "$restore_target" || true
        reconcile_ok=no
        break
      fi
      append_restore_record "$backup_dir" reconciled-enabled "$restore_target" || { reconcile_ok=no; break; }
      remove_recorded_package "$removed_file" "$restore_target" || { reconcile_ok=no; break; }
    elif package_list_contains "$PACKAGE_DISABLED" "$restore_target" &&
      ! package_list_contains "$PACKAGE_ENABLED" "$restore_target"
    then
      :
    else
      printf 'restore reconciliation found invalid state for %s\n' "$restore_target" >&2
      reconcile_ok=no
      break
    fi
  done < "$restore_snapshot"
  rm -f "$restore_snapshot"
  [ "$reconcile_ok" = yes ]
}

verify_backup_integrity() {
  backup_dir=$1
  [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ] || return 1
  for backup_file in device.txt disabled-successfully.txt operation-journal.txt restore-journal.txt package-mode.txt SHA256SUMS; do
    [ -f "$backup_dir/$backup_file" ] && [ ! -L "$backup_dir/$backup_file" ] || return 1
  done
  (
    cd "$backup_dir"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c SHA256SUMS >/dev/null
    else
      shasum -a 256 -c SHA256SUMS >/dev/null
    fi
  )
}

validate_backup_mode() {
  backup_dir=$1
  expected_mode='PACKAGE_OPERATION=pm disable-user --user 0
PACKAGE_RESTORE=pm enable --user 0'
  actual_mode=$(cat "$backup_dir/package-mode.txt") || return 1
  [ "$actual_mode" = "$expected_mode" ] || {
    printf '%s\n' 'backup package mode mismatch' >&2
    return 1
  }
}

validate_restore_journal() {
  backup_dir=$1
  removed_file=$backup_dir/disabled-successfully.txt
  operation_file=$backup_dir/operation-journal.txt
  restore_file=$backup_dir/restore-journal.txt
  while IFS= read -r package; do
    validate_recorded_package "$package" || {
      printf 'invalid recorded package: %s\n' "$package" >&2
      return 1
    }
  done < "$removed_file"
  while IFS=' ' read -r journal_state journal_package journal_extra; do
    [ -n "$journal_state" ] || continue
    [ -z "${journal_extra:-}" ] || { printf '%s\n' 'invalid operation journal record' >&2; return 1; }
    case "$journal_state" in
      attempt|success|failure|skip|rollback|guard-failure) ;;
      *) printf 'invalid operation journal state: %s\n' "$journal_state" >&2; return 1 ;;
    esac
    validate_recorded_package "$journal_package" || {
      printf 'invalid operation journal package: %s\n' "$journal_package" >&2
      return 1
    }
  done < "$operation_file"
  while IFS=' ' read -r journal_state journal_package journal_extra; do
    [ -n "$journal_state" ] || continue
    [ -z "${journal_extra:-}" ] || { printf '%s\n' 'invalid restore journal record' >&2; return 1; }
    case "$journal_state" in
      attempt|success|success-after-error|failure|guard-failure|reconciled-enabled) ;;
      *) printf 'invalid restore journal state: %s\n' "$journal_state" >&2; return 1 ;;
    esac
    validate_recorded_package "$journal_package" || {
      printf 'invalid restore journal package: %s\n' "$journal_package" >&2
      return 1
    }
  done < "$restore_file"
}

reconcile_attempted_disables() {
  backup_dir=$1
  removed_file=$backup_dir/disabled-successfully.txt
  operation_file=$backup_dir/operation-journal.txt
  reconciliation_file=$backup_dir/reconciliation-journal.txt
  active_package_list || return 1
  read_shell pm list packages -d || return 1
  disabled_packages=$ACTUAL
  : > "$reconciliation_file"
  while IFS=' ' read -r journal_state journal_package journal_extra; do
    [ "$journal_state" = attempt ] || continue
    [ -z "${journal_extra:-}" ] || return 1
    recorded_package_exists "$removed_file" "$journal_package" && continue
    if ! package_list_contains "$ACTIVE_PACKAGES" "$journal_package" && package_list_contains "$disabled_packages" "$journal_package"; then
      append_recorded_package "$removed_file" "$journal_package" || return 1
      printf 'reconciled %s\n' "$journal_package" >> "$reconciliation_file"
      refresh_backup_checksums "$backup_dir" || return 1
    fi
  done < "$operation_file"
  refresh_backup_checksums "$backup_dir"
}

plan() {
  require_target
  validate_manifests
  require_package_state_capability
  plan_restore=$(restore_command)
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  printf 'PACKAGE_OPERATION=%s\n' "$PACKAGE_OPERATION"
  printf 'PACKAGE_RESTORE=%s\n' "$PACKAGE_RESTORE"
  while IFS= read -r package; do
    printf 'DISABLE=%s RESTORE=%s --user 0 %s\n' "$package" "$plan_restore" "$package"
  done < "$MANIFEST_DIR/remove-user0.txt"
  printf '%s\n' 'PLAN=PASS'
}

apply() {
  require_target
  validate_manifests
  require_package_state_capability
  require_wolf_ready || exit 1
  capture_guard_baseline || exit 1
  GUARD_BASELINE_TUN0_STATE=$GUARD_TUN0_STATE
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  publish_audit || exit 1
  backup_dir=$PUBLISHED_AUDIT_DIR
  removed_file=$backup_dir/disabled-successfully.txt
  journal_file=$backup_dir/operation-journal.txt
  : > "$journal_file"
  refresh_backup_checksums "$backup_dir" || exit 1
  while IFS= read -r package; do
    capture_package_state "$package" || { rollback_batch '' "$removed_file" "$journal_file"; exit 1; }
    if ! package_list_contains "$PACKAGE_ENABLED" "$package"; then
      if package_list_contains "$PACKAGE_DISABLED" "$package"; then
        printf 'skip %s\n' "$package" >> "$journal_file"
        refresh_backup_checksums "$backup_dir" || exit 1
        continue
      fi
      rollback_batch '' "$removed_file" "$journal_file" || true
      printf 'candidate package is neither enabled nor disabled: %s\n' "$package" >&2
      exit 1
    fi
    if package_list_contains "$PACKAGE_DISABLED" "$package"; then
      rollback_batch '' "$removed_file" "$journal_file" || true
      printf 'candidate package has conflicting enabled/disabled state: %s\n' "$package" >&2
      exit 1
    fi
    printf 'attempt %s\n' "$package" >> "$journal_file"
    refresh_backup_checksums "$backup_dir" || exit 1
    disable_status=0
    read_shell pm disable-user --user 0 "$package" || disable_status=$?
    if ! capture_package_state "$package"; then
      apply_failed_package=$package
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch '' "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'could not verify disable state for %s\n' "$apply_failed_package" >&2
      exit 1
    fi
    disabled_now=no
    if ! package_list_contains "$PACKAGE_ENABLED" "$package" && package_list_contains "$PACKAGE_DISABLED" "$package"; then
      disabled_now=yes
      append_recorded_package "$removed_file" "$package" || { rollback_batch '' "$removed_file" "$journal_file" || true; exit 1; }
    fi
    if [ "$disable_status" -ne 0 ]; then
      apply_failed_package=$package
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch '' "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'disable failed for %s\n' "$apply_failed_package" >&2
      exit 1
    fi
    if [ "$disabled_now" != yes ]; then
      apply_failed_package=$package
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch '' "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'disable verification failed for %s\n' "$apply_failed_package" >&2
      exit 1
    fi
    printf 'success %s\n' "$package" >> "$journal_file"
    refresh_backup_checksums "$backup_dir" || { rollback_batch '' "$removed_file" "$journal_file" || true; exit 1; }
    apply_guard_package=$package
    if ! compact_guard; then
      printf 'guard-failure %s\n' "$apply_guard_package" >> "$journal_file"
      if rollback_batch '' "$removed_file" "$journal_file" &&
        [ ! -s "$removed_file" ] &&
        refresh_backup_checksums "$backup_dir"
      then
        printf '%s\n' 'guard failure restored the current batch while ADB remained reachable' >&2
      else
        refresh_backup_checksums "$backup_dir" || true
        printf 'guard failure rollback incomplete; recovery backup preserved at %s\n' "$backup_dir" >&2
      fi
      exit 1
    fi
  done < "$MANIFEST_DIR/remove-user0.txt"
  printf 'APPLY_OUTPUT=%s\n' "$backup_dir"
  printf '%s\n' 'APPLY=PASS'
}

restore_backup() {
  backup_dir=$COMMAND_ARG
  verify_backup_integrity "$backup_dir" || { printf '%s\n' 'backup integrity verification failed' >&2; exit 1; }
  validate_backup_mode "$backup_dir" || exit 1
  require_target
  validate_manifests
  require_package_state_capability
  validate_restore_journal "$backup_dir" || exit 1
  reconcile_attempted_disables "$backup_dir" || { printf '%s\n' 'backup reconciliation failed' >&2; exit 1; }
  load_guard_baseline "$backup_dir" || { printf '%s\n' 'could not load audit guard baseline' >&2; exit 1; }
  reconcile_attempted_enables "$backup_dir" || { printf '%s\n' 'restore reconciliation failed' >&2; exit 1; }
  removed_file=$backup_dir/disabled-successfully.txt
  rollback_recorded_packages "$removed_file" || { printf '%s\n' 'restore failed before all packages were restored' >&2; exit 1; }
  compact_guard || { printf '%s\n' 'final restore guard failed' >&2; exit 1; }
  printf '%s\n' 'RESTORE=PASS'
}

WOLF_URL=https://archive.org/download/wolf-launcher-0.1.9-wolf_202110/WolfLauncher_0.1.9-Wolf.apk
WOLF_SIZE=3272501
WOLF_APK_SHA256=d03ed56bb5564aa5b3e668831484917616510b02db4dde6a813d49a352054d05
WOLF_PACKAGE=com.wolf.firelauncher
WOLF_VERSION_CODE=11900120
WOLF_VERSION_NAME=0.1.9-Wolf
WOLF_MIN_SDK=21
WOLF_TARGET_SDK=29
WOLF_INSTALL_LOCATION=internalOnly
WOLF_ACTIVITY=.screens.launcher.LauncherActivity
WOLF_COMPONENT=$WOLF_PACKAGE/$WOLF_ACTIVITY
WOLF_CERT_SHA256=ea1270015ddbc06fd3b57b06b123c8c828ed5f76193611a18e8bd1fa7037819b

wolf_fail() {
  printf 'Wolf verification failed: %s\n' "$1" >&2
  exit 1
}

wolf_badging_value() {
  wolf_line=$1
  wolf_key=$2
  printf '%s\n' "$wolf_line" | sed -n "s/.*${wolf_key}='\\([^']*\\)'.*/\\1/p" | head -n 1
}

wolf_print_installed_identity() {
  wolf_package_dump=$1
  WOLF_INSTALLED_VERSION_CODE=$(printf '%s\n' "$wolf_package_dump" | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
  WOLF_INSTALLED_VERSION_NAME=$(printf '%s\n' "$wolf_package_dump" | sed -n 's/^[[:space:]]*versionName=\(.*\)$/\1/p' | head -n 1)
}

install_wolf() {
  require_target
  WOLF_TMP=$(mktemp -d "${TMPDIR:-/tmp}/wolf-launcher.XXXXXX") || {
    printf '%s\n' 'unable to create a temporary Wolf download directory' >&2
    exit 1
  }
  trap 'rm -rf "$WOLF_TMP"' EXIT HUP INT TERM
  wolf_apk=$WOLF_TMP/WolfLauncher_0.1.9-Wolf.apk

  "$CURL" --fail --location --output "$wolf_apk" "$WOLF_URL" || wolf_fail 'download failed'
  wolf_bytes=$(wc -c < "$wolf_apk" | tr -d '[:space:]')
  [ "$wolf_bytes" = "$WOLF_SIZE" ] || wolf_fail "byte count expected=$WOLF_SIZE actual=$wolf_bytes"
  if [ -n "$SHA256_TOOL" ]; then
    wolf_hash=$("$SHA256_TOOL" "$wolf_apk" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    wolf_hash=$(sha256sum "$wolf_apk" | awk '{print $1}')
  else
    wolf_hash=$(shasum -a 256 "$wolf_apk" | awk '{print $1}')
  fi
  [ "$wolf_hash" = "$WOLF_APK_SHA256" ] || wolf_fail 'APK SHA-256 does not match the pin'

  wolf_badging=$("$AAPT" dump badging "$wolf_apk") || wolf_fail 'aapt badging inspection failed'
  wolf_package_line=$(printf '%s\n' "$wolf_badging" | sed -n '/^package: /p' | head -n 1)
  wolf_package=$(wolf_badging_value "$wolf_package_line" name)
  wolf_version_code=$(wolf_badging_value "$wolf_package_line" versionCode)
  wolf_version_name=$(wolf_badging_value "$wolf_package_line" versionName)
  wolf_min_sdk=$(printf '%s\n' "$wolf_badging" | sed -n "s/^sdkVersion:'\\([^']*\\)'.*/\\1/p" | head -n 1)
  wolf_target_sdk=$(printf '%s\n' "$wolf_badging" | sed -n "s/^targetSdkVersion:'\\([^']*\\)'.*/\\1/p" | head -n 1)
  wolf_install_location=$(printf '%s\n' "$wolf_badging" | sed -n "s/^install-location:'\\([^']*\\)'.*/\\1/p" | head -n 1)
  wolf_activity_line=$(printf '%s\n' "$wolf_badging" | sed -n '/^launchable-activity: /p' | head -n 1)
  wolf_activity=$(wolf_badging_value "$wolf_activity_line" name)
  [ "$wolf_package" = "$WOLF_PACKAGE" ] || wolf_fail "package expected=$WOLF_PACKAGE actual=$wolf_package"
  [ "$wolf_version_code" = "$WOLF_VERSION_CODE" ] || wolf_fail "version code expected=$WOLF_VERSION_CODE actual=$wolf_version_code"
  [ "$wolf_version_name" = "$WOLF_VERSION_NAME" ] || wolf_fail "version name expected=$WOLF_VERSION_NAME actual=$wolf_version_name"
  [ "$wolf_min_sdk" = "$WOLF_MIN_SDK" ] || wolf_fail "minSdk expected=$WOLF_MIN_SDK actual=$wolf_min_sdk"
  [ "$wolf_target_sdk" = "$WOLF_TARGET_SDK" ] || wolf_fail "targetSdk expected=$WOLF_TARGET_SDK actual=$wolf_target_sdk"
  [ "$wolf_install_location" = "$WOLF_INSTALL_LOCATION" ] || wolf_fail "install location expected=$WOLF_INSTALL_LOCATION actual=$wolf_install_location"
  case "$wolf_activity" in
    "$WOLF_ACTIVITY"|"$WOLF_PACKAGE$WOLF_ACTIVITY") ;;
    *) wolf_fail "activity expected=$WOLF_ACTIVITY actual=$wolf_activity" ;;
  esac

  wolf_signatures=$("$APKSIGNER" verify --verbose --print-certs "$wolf_apk") || wolf_fail 'apksigner verification failed'
  case "$wolf_signatures" in
    *'Verified using v1 scheme (JAR signing): true'*) ;;
    *) wolf_fail 'v1 signature verification is missing' ;;
  esac
  case "$wolf_signatures" in
    *'Verified using v2 scheme (APK Signature Scheme v2): true'*) ;;
    *) wolf_fail 'v2 signature verification is missing' ;;
  esac
  wolf_cert=$(printf '%s\n' "$wolf_signatures" | sed -n 's/^Signer #[0-9][0-9]* certificate SHA-256 digest: //p' | tr -d ' :\r' | tr '[:upper:]' '[:lower:]')
  [ "$wolf_cert" = "$WOLF_CERT_SHA256" ] || wolf_fail 'signer certificate SHA-256 does not match the pin'
  printf '%s\n' 'WOLF_VERIFY=PASS'
  printf '%s\n' 'WOLF_CHECK_SCOPE=integrity and signer continuity only; publisher authenticity and malware safety are not established'

  if read_shell dumpsys package "$WOLF_PACKAGE"; then
    wolf_print_installed_identity "$ACTUAL"
    if [ -n "$WOLF_INSTALLED_VERSION_CODE" ] && [ -n "$WOLF_INSTALLED_VERSION_NAME" ]; then
      printf 'WOLF_PREVIOUS_VERSION_CODE=%s\n' "$WOLF_INSTALLED_VERSION_CODE"
      printf 'WOLF_PREVIOUS_VERSION_NAME=%s\n' "$WOLF_INSTALLED_VERSION_NAME"
    fi
  fi
  wolf_install=$(adb_cmd install -r "$wolf_apk") || wolf_fail 'adb install -r failed'
  case "$wolf_install" in
    *Success*) ;;
    *) wolf_fail 'adb install -r did not report Success' ;;
  esac
  read_shell dumpsys package "$WOLF_PACKAGE" || wolf_fail 'installed package readback failed'
  wolf_print_installed_identity "$ACTUAL"
  [ "$WOLF_INSTALLED_VERSION_CODE" = "$WOLF_VERSION_CODE" ] || wolf_fail "installed version code expected=$WOLF_VERSION_CODE actual=$WOLF_INSTALLED_VERSION_CODE"
  [ "$WOLF_INSTALLED_VERSION_NAME" = "$WOLF_VERSION_NAME" ] || wolf_fail "installed version name expected=$WOLF_VERSION_NAME actual=$WOLF_INSTALLED_VERSION_NAME"
  printf 'WOLF_INSTALLED_VERSION_CODE=%s\n' "$WOLF_INSTALLED_VERSION_CODE"
  printf 'WOLF_INSTALLED_VERSION_NAME=%s\n' "$WOLF_INSTALLED_VERSION_NAME"
  wolf_launch=$(adb_shell am start -n "$WOLF_COMPONENT") || wolf_fail 'direct launcher start failed'
  case "$wolf_launch" in
    *'Starting: Intent'*) ;;
    *) wolf_fail 'direct launcher start did not report a launch intent' ;;
  esac
  printf '%s\n' 'WOLF_DIRECT_LAUNCH=PASS'
  printf '%s\n' 'WOLF_INSTALL=PASS'
}

case "$COMMAND" in
  audit)
    audit
    ;;
  plan)
    plan
    ;;
  apply)
    [ "$YES" = yes ] || { printf '%s\n' '--yes is required for apply' >&2; exit 64; }
    apply
    ;;
  install-wolf)
    [ "$YES" = yes ] || { printf '%s\n' '--yes is required for install-wolf' >&2; exit 64; }
    install_wolf
    ;;
  restore)
    restore_backup
    ;;
  verify)
    verify
    ;;
  verify-settings)
    verify_settings
    ;;
  *)
    usage
    exit 64
    ;;
esac
