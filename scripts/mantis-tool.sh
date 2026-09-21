#!/bin/sh
set -eu

ADB=adb
SERIAL=
YES=no
COMMAND=
CR=$(printf '\r')

usage() {
  printf '%s\n' 'usage: mantis-tool.sh [--adb PATH] --serial SERIAL [--yes] audit|apply' >&2
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

audit() {
  if target_matches; then
    printf '%s\n' 'SUPPORTED_MUTATION_TARGET=YES'
  else
    printf '%s\n' 'SUPPORTED_MUTATION_TARGET=NO'
  fi
  printf '%s\n' 'ROOT=NOT_ACHIEVED'
}

case "$COMMAND" in
  audit)
    audit
    ;;
  apply)
    [ "$YES" = yes ] || { printf '%s\n' '--yes is required for apply' >&2; exit 64; }
    require_target
    printf '%s\n' 'No mutation is implemented.'
    ;;
  *)
    usage
    exit 64
    ;;
esac
