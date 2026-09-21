#!/bin/sh
set -eu

ADB=adb
CURL=curl
AAPT=aapt
APKSIGNER=apksigner
SHA256_TOOL=
SERIAL=
YES=no
COMMAND=
COMMAND_ARG=
OUTPUT=
CR=$(printf '\r')

usage() {
  printf '%s\n' 'usage: mantis-tool.sh [--adb PATH] [--curl PATH] [--aapt PATH] [--apksigner PATH] [--sha256 PATH] --serial SERIAL [--output DIR] [--yes] audit|plan|apply|install-wolf|restore BACKUP_DIRECTORY' >&2
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
    --yes)
      YES=yes
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      OUTPUT=$2
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

validate_manifests() {
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  python3 -B "$script_dir/../tests/verify-manifests.py" "$script_dir/../manifests"
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

restore_capability() {
  if read_shell cmd package help && help_proves_install_existing "$ACTUAL"; then
    RESTORE_CAPABILITY=cmd
  elif read_shell pm help && help_proves_install_existing "$ACTUAL"; then
    RESTORE_CAPABILITY=pm
  else
    RESTORE_CAPABILITY=none
  fi
}

help_proves_install_existing() {
  printf '%s\n' "$1" | awk '
    $1 == "install-existing" {
      usage = 1
      user = 0
      package = 0
      for (field = 2; field <= NF; field++) {
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
        } else if (token == "--full" || token == "--wait") {
        } else if (token == "PACKAGE" && field == NF) {
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
  for action in \
    android.settings.SETTINGS android.settings.WIFI_SETTINGS \
    android.settings.MANAGE_APPLICATIONS_SETTINGS android.settings.CONTROLLERS_SETTINGS \
    android.settings.DEVICE_INFO_SETTINGS android.settings.ACCESSIBILITY_SETTINGS \
    android.settings.DISPLAY_SETTINGS com.amazon.device.settings.action.DATE_TIME \
    com.amazon.device.settings.action.LANGUAGE
  do
    read_shell cmd package resolve-activity --brief -a "$action" || return 1
    printf '%s=%s\n' "$action" "$ACTUAL" >> "$audit_file"
  done
}

write_restore_script() {
  audit_file=$1
  capability=$2
  case "$capability" in
    cmd) restore_command='cmd package install-existing' ;;
    pm) restore_command='pm install-existing' ;;
    *) restore_command=false ;;
  esac
  cat > "$audit_file" <<EOF
#!/bin/sh
set -eu

ADB=\${ADB:-adb}
: "\${SERIAL:?set SERIAL to the target adb serial}"
backup_dir=\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)
removed_file=\$backup_dir/removed-successfully.txt

adb_shell() {
  "\$ADB" -s "\$SERIAL" shell "\$@"
}

expect_prop() {
  property=\$1
  expected=\$2
  actual=\$(adb_shell getprop "\$property")
  [ "\$actual" = "\$expected" ] || {
    printf 'restore target mismatch: %s expected=%s actual=%s\\n' "\$property" "\$expected" "\$actual" >&2
    exit 1
  }
}

expect_shell() {
  label=\$1
  expected=\$2
  shift 2
  actual=\$(adb_shell "\$@")
  [ "\$actual" = "\$expected" ] || {
    printf 'restore target mismatch: %s expected=%s actual=%s\\n' "\$label" "\$expected" "\$actual" >&2
    exit 1
  }
}

expect_prop ro.product.manufacturer Amazon
expect_prop ro.product.model AFTMM
expect_prop ro.product.device mantis
expect_prop ro.build.id NS6711
expect_prop ro.build.version.incremental 0011644900484
expect_prop ro.build.version.release 7.1.2
expect_prop ro.build.version.sdk 25
expect_prop ro.product.cpu.abi armeabi-v7a
expect_shell 'uname -m' armv7l uname -m
expect_shell getenforce Enforcing getenforce
expect_shell uid 2000 id -u

restore_package() {
  adb_shell $restore_command --user 0 "\$1"
}

[ -f "\$removed_file" ] || exit 0
awk '{ lines[NR] = \$0 } END { for (line = NR; line > 0; line--) print lines[line] }' "\$removed_file" |
while IFS= read -r package; do
  case "\$package" in
    ''|*[!A-Za-z0-9._]*)
      printf 'invalid recorded package: %s\\n' "\$package" >&2
      exit 1
      ;;
  esac
  restore_package "\$package"
done
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
    ! write_shell_capture "$work_dir/packages-active.txt" pm list packages ||
    ! write_shell_capture "$work_dir/packages-uninstalled.txt" pm list packages -u ||
    ! write_shell_capture "$work_dir/packages-disabled.txt" pm list packages -d ||
    ! cat "$script_dir/../manifests/preserve-core.txt" "$script_dir/../manifests/preserve-user-apps.txt" | LC_ALL=C sort -u > "$work_dir/protected-apps.txt" ||
    ! write_shell_capture "$work_dir/home-directory.txt" printenv HOME ||
    ! write_labeled_shell_capture "$work_dir/bluetooth.txt" bluetooth_on settings get global bluetooth_on ||
    ! write_shell_capture "$work_dir/tun0.txt" ip link show tun0 ||
    ! write_settings_route_resolvers "$work_dir/settings-route-resolvers.txt" ||
    ! write_shell_capture "$work_dir/home-resolver.txt" cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME ||
    ! write_restore_script "$work_dir/restore-user0.sh" "$RESTORE_CAPABILITY" ||
    ! : > "$work_dir/removed-successfully.txt" ||
    ! : > "$work_dir/operation-journal.txt" ||
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
  restore_capability
  printf 'RESTORE_CAPABILITY=%s\n' "$RESTORE_CAPABILITY"
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  publish_audit
  printf '%s\n' 'AUDIT=PASS'
}

require_restore_capability() {
  restore_capability
  [ "$RESTORE_CAPABILITY" != none ] || {
    printf '%s\n' 'no help-proven install-existing command is available' >&2
    exit 1
  }
}

restore_command() {
  case "$RESTORE_CAPABILITY" in
    cmd) printf '%s\n' 'cmd package install-existing' ;;
    pm) printf '%s\n' 'pm install-existing' ;;
    *) return 1 ;;
  esac
}

restore_package() {
  case "$RESTORE_CAPABILITY" in
    cmd) adb_shell cmd package install-existing --user 0 "$1" ;;
    pm) adb_shell pm install-existing --user 0 "$1" ;;
    *) return 1 ;;
  esac
}

package_list_contains() {
  package_list=$1
  package=$2
  printf '%s\n' "$package_list" | awk -v package="$package" '$0 == "package:" package { found = 1 } END { exit found ? 0 : 1 }'
}

active_package_list() {
  read_shell pm list packages || return 1
  ACTIVE_PACKAGES=$ACTUAL
}

require_active_packages() {
  active_packages=$1
  shift
  for required_package in "$@"; do
    package_list_contains "$active_packages" "$required_package" || {
      printf 'guard missing active package: %s\n' "$required_package" >&2
      return 1
    }
  done
}

require_preserved_active_packages() {
  active_packages=$1
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  for preserve_manifest in "$script_dir/../manifests/preserve-core.txt" "$script_dir/../manifests/preserve-user-apps.txt"; do
    while IFS= read -r required_package; do
      package_list_contains "$active_packages" "$required_package" || {
        printf 'guard missing active package: %s\n' "$required_package" >&2
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
  if ! GUARD_VALUE=$(adb_cmd get-state); then
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
}

require_settings_routes() {
  for settings_action in \
    android.settings.SETTINGS android.settings.WIFI_SETTINGS \
    android.settings.MANAGE_APPLICATIONS_SETTINGS android.settings.CONTROLLERS_SETTINGS \
    android.settings.DEVICE_INFO_SETTINGS android.settings.ACCESSIBILITY_SETTINGS \
    android.settings.DISPLAY_SETTINGS com.amazon.device.settings.action.DATE_TIME \
    com.amazon.device.settings.action.LANGUAGE
  do
    read_shell cmd package resolve-activity --brief -a "$settings_action" || return 1
    [ -n "$ACTUAL" ] || {
      printf 'guard has no Settings route resolver: %s\n' "$settings_action" >&2
      return 1
    }
  done
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
    [ -n "$NORMALIZED" ] && GUARD_TUN0_STATE="present:$NORMALIZED" || GUARD_TUN0_STATE=absent
  else
    GUARD_TUN0_STATE=absent
  fi
}

capture_guard_baseline() {
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
  [ "$GUARD_DEVELOPMENT_SETTINGS_ENABLED" = 1 ] || { printf 'guard development_settings_enabled expected=1 actual=%s\n' "$GUARD_DEVELOPMENT_SETTINGS_ENABLED" >&2; return 1; }
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
  [ "$GUARD_PERSIST_ADB_TCP_PORT" = 5555 ] || { printf 'guard persist.adb.tcp.port expected=5555 actual=%s\n' "$GUARD_PERSIST_ADB_TCP_PORT" >&2; return 1; }
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
  case "$SERIAL" in
    *:5555) ;;
    *) printf 'guard requires a TCP adb serial ending in :5555\n' >&2; return 1 ;;
  esac
  read_adb_transport || return 1
  [ "$GUARD_VALUE" = device ] || { printf 'guard TCP 5555 is not reachable: %s\n' "$GUARD_VALUE" >&2; return 1; }
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
  [ "$GUARD_VALUE" = 5555 ] || return 1
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
  read_adb_transport || return 1
  [ "$GUARD_VALUE" = device ] || { printf 'guard TCP 5555 is not reachable: %s\n' "$GUARD_VALUE" >&2; return 1; }
}

rollback_recorded_packages() {
  removed_file=$1
  rollback_file=$(mktemp "${TMPDIR:-/tmp}/mantis-rollback.XXXXXX") || return 1
  awk '{ lines[NR] = $0 } END { for (line = NR; line > 0; line--) print lines[line] }' "$removed_file" > "$rollback_file"
  rollback_ok=yes
  while IFS= read -r rollback_package; do
    [ -n "$rollback_package" ] || continue
    if ! restore_package "$rollback_package"; then
      printf 'rollback failed for %s\n' "$rollback_package" >&2
      rollback_ok=no
      break
    fi
    if ! remove_recorded_package "$removed_file" "$rollback_package"; then
      printf 'rollback ledger update failed for %s\n' "$rollback_package" >&2
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
    restore_package "$failed_package" || rollback_ok=no
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
  awk -v package="$recorded_candidate" '$0 == package { found = 1 } END { exit found ? 0 : 1 }' "$script_dir/../manifests/remove-user0.txt"
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

verify_backup_integrity() {
  backup_dir=$1
  [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ] || return 1
  for backup_file in device.txt removed-successfully.txt operation-journal.txt SHA256SUMS; do
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

validate_restore_journal() {
  backup_dir=$1
  removed_file=$backup_dir/removed-successfully.txt
  operation_file=$backup_dir/operation-journal.txt
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
}

reconcile_attempted_removals() {
  backup_dir=$1
  removed_file=$backup_dir/removed-successfully.txt
  operation_file=$backup_dir/operation-journal.txt
  reconciliation_file=$backup_dir/reconciliation-journal.txt
  active_package_list || return 1
  read_shell pm list packages -u || return 1
  all_packages=$ACTUAL
  : > "$reconciliation_file"
  while IFS=' ' read -r journal_state journal_package journal_extra; do
    [ "$journal_state" = attempt ] || continue
    [ -z "${journal_extra:-}" ] || return 1
    recorded_package_exists "$removed_file" "$journal_package" && continue
    if ! package_list_contains "$ACTIVE_PACKAGES" "$journal_package" && package_list_contains "$all_packages" "$journal_package"; then
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
  require_restore_capability
  plan_restore=$(restore_command)
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  while IFS= read -r package; do
    printf 'REMOVE=%s RESTORE=%s --user 0 %s\n' "$package" "$plan_restore" "$package"
  done < "$script_dir/../manifests/remove-user0.txt"
  printf '%s\n' 'PLAN=PASS'
}

apply() {
  require_target
  validate_manifests
  require_restore_capability
  require_wolf_ready || exit 1
  capture_guard_baseline || exit 1
  GUARD_BASELINE_TUN0_STATE=$GUARD_TUN0_STATE
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  publish_audit || exit 1
  backup_dir=$PUBLISHED_AUDIT_DIR
  removed_file=$backup_dir/removed-successfully.txt
  journal_file=$backup_dir/operation-journal.txt
  : > "$journal_file"
  refresh_backup_checksums "$backup_dir" || exit 1
  while IFS= read -r package; do
    active_package_list || { rollback_batch '' "$removed_file" "$journal_file"; exit 1; }
    if ! package_list_contains "$ACTIVE_PACKAGES" "$package"; then
      printf 'skip %s\n' "$package" >> "$journal_file"
      refresh_backup_checksums "$backup_dir" || exit 1
      continue
    fi
    printf 'attempt %s\n' "$package" >> "$journal_file"
    refresh_backup_checksums "$backup_dir" || exit 1
    if ! read_shell pm uninstall -k --user 0 "$package"; then
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch "$package" "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'removal failed for %s\n' "$package" >&2
      exit 1
    fi
    if [ "$ACTUAL" != Success ]; then
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch "$package" "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'removal failed for %s\n' "$package" >&2
      exit 1
    fi
    active_package_list || { printf 'failure %s\n' "$package" >> "$journal_file"; rollback_batch "$package" "$removed_file" "$journal_file" || true; refresh_backup_checksums "$backup_dir" || true; exit 1; }
    if package_list_contains "$ACTIVE_PACKAGES" "$package"; then
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch "$package" "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'removal verification failed for %s\n' "$package" >&2
      exit 1
    fi
    read_shell pm list packages -u || { printf 'failure %s\n' "$package" >> "$journal_file"; rollback_batch "$package" "$removed_file" "$journal_file" || true; refresh_backup_checksums "$backup_dir" || true; exit 1; }
    if ! package_list_contains "$ACTUAL" "$package"; then
      printf 'failure %s\n' "$package" >> "$journal_file"
      rollback_batch "$package" "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf 'removal verification failed for %s\n' "$package" >&2
      exit 1
    fi
    append_recorded_package "$removed_file" "$package" || { rollback_batch '' "$removed_file" "$journal_file" || true; exit 1; }
    printf 'success %s\n' "$package" >> "$journal_file"
    refresh_backup_checksums "$backup_dir" || { rollback_batch '' "$removed_file" "$journal_file" || true; exit 1; }
    if ! compact_guard; then
      printf 'guard-failure %s\n' "$package" >> "$journal_file"
      rollback_batch '' "$removed_file" "$journal_file" || true
      refresh_backup_checksums "$backup_dir" || true
      printf '%s\n' 'guard failure restored the current batch while ADB remained reachable' >&2
      exit 1
    fi
  done < "$script_dir/../manifests/remove-user0.txt"
  printf 'APPLY_OUTPUT=%s\n' "$backup_dir"
  printf '%s\n' 'APPLY=PASS'
}

restore_backup() {
  backup_dir=$COMMAND_ARG
  verify_backup_integrity "$backup_dir" || { printf '%s\n' 'backup integrity verification failed' >&2; exit 1; }
  require_target
  validate_manifests
  require_restore_capability
  validate_restore_journal "$backup_dir" || exit 1
  reconcile_attempted_removals "$backup_dir" || { printf '%s\n' 'backup reconciliation failed' >&2; exit 1; }
  removed_file=$backup_dir/removed-successfully.txt
  rollback_recorded_packages "$removed_file" || { printf '%s\n' 'restore failed before all packages were restored' >&2; exit 1; }
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
  *)
    usage
    exit 64
    ;;
esac
