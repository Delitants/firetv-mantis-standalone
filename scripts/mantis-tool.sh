#!/bin/sh
set -eu

ADB=adb
SERIAL=
YES=no
COMMAND=
OUTPUT=
CR=$(printf '\r')

usage() {
  printf '%s\n' 'usage: mantis-tool.sh [--adb PATH] --serial SERIAL [--output DIR] [--yes] audit|apply' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --adb)
      [ "$#" -ge 2 ] || { usage; exit 64; }
      ADB=$2
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

[ -n "$COMMAND" ] && [ "$#" -eq 0 ] || { usage; exit 64; }
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
    find . -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort |
    while IFS= read -r audit_file; do
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$audit_file"
      else
        shasum -a 256 "$audit_file"
      fi
    done > SHA256SUMS
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

publish_audit() {
  final_dir=$(audit_directory)
  [ ! -e "$final_dir" ] || { printf 'audit output already exists: %s\n' "$final_dir" >&2; return 1; }
  final_parent=$(dirname "$final_dir")
  [ -d "$final_parent" ] || { printf 'audit output parent does not exist: %s\n' "$final_parent" >&2; return 1; }
  work_dir=$(mktemp -d "$final_dir.tmp.XXXXXX") || return 1
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
    ! checksum_files "$work_dir"
  then
    rm -rf "$work_dir"
    return 1
  fi
  work_name=$(basename "$work_dir")
  if [ -e "$final_dir" ] || [ -L "$final_dir" ]; then
    rm -rf "$work_dir"
    printf 'audit output appeared during publication: %s\n' "$final_dir" >&2
    return 1
  fi
  if ! mv "$work_dir" "$final_dir"; then
    rm -rf "$work_dir"
    return 1
  fi
  if [ -d "$final_dir/$work_name" ]; then
    if [ ! -L "$final_dir" ]; then
      rm -rf "$final_dir/$work_name"
    fi
    printf 'audit output appeared during publication: %s\n' "$final_dir" >&2
    return 1
  fi
  [ -d "$final_dir" ] || {
    printf 'audit output publication failed: %s\n' "$final_dir" >&2
    return 1
  }
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

case "$COMMAND" in
  audit)
    audit
    ;;
  apply)
    [ "$YES" = yes ] || { printf '%s\n' '--yes is required for apply' >&2; exit 64; }
    require_target
    validate_manifests
    require_restore_capability
    printf '%s\n' 'No mutation is implemented.'
    ;;
  *)
    usage
    exit 64
    ;;
esac
