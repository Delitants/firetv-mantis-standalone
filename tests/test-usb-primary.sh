#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-usb-primary.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
fixture=$root/tests/fixtures/adb

run_deploy() {
  case_name=$1
  usb_serial=$2
  network_serial=$3
  mkdir "$test_dir/$case_name"
  : > "$test_dir/$case_name/adb.log"
  FAKE_ADB_LOG="$test_dir/$case_name/adb.log" \
    "$root/scripts/deploy-mantis.sh" \
      --adb "$fixture" --curl true --aapt true --apksigner true \
      --serial "$usb_serial" --network-serial "$network_serial" \
      --root-binary "$root/tests/fixtures/aapt" \
      --output "$test_dir/$case_name" --yes \
      > "$test_dir/$case_name/stdout" 2> "$test_dir/$case_name/stderr" || true
  set -- "$test_dir/$case_name"/deployment-*/deploy.log
  [ "$#" -eq 1 ] && [ -f "$1" ] || { printf 'FAIL: no deploy log for %s\n' "$case_name" >&2; exit 1; }
  deploy_log=$1
}

assert_early_usb_rejection() {
  case_name=$1
  grep -Fq 'USB_PRIMARY_REJECTED' "$deploy_log" || {
    printf 'FAIL: %s did not reject its non-USB primary before root checks\n' "$case_name" >&2
    exit 1
  }
  if grep -Fq 'PHASE=ROOT_BINARY_CHECK' "$deploy_log"; then
    printf 'FAIL: %s reached root check after unsafe transport\n' "$case_name" >&2
    exit 1
  fi
  if grep -Eq ' install | pm disable-user ' "$test_dir/$case_name/adb.log"; then
    printf 'FAIL: %s mutated apps after unsafe transport\n' "$case_name" >&2
    exit 1
  fi
}

run_deploy same-serial network-check:5555 network-check:5555
assert_early_usb_rejection same-serial

run_deploy network-primary test-host:5555 network-check:5555
assert_early_usb_rejection network-primary

FAKE_ADB_USB_STATE=unauthorized run_deploy unauthorized usb-primary network-check:5555
assert_early_usb_rejection unauthorized

FAKE_ADB_USB_PRESENT=no run_deploy missing-usb usb-primary network-check:5555
assert_early_usb_rejection missing-usb

unset FAKE_ADB_USB_STATE FAKE_ADB_USB_PRESENT
run_deploy valid-usb usb-primary network-check:5555
grep -Fq 'TARGET_GATE=PASS' "$deploy_log" || {
  printf '%s\n' 'FAIL: valid USB primary was rejected' >&2
  exit 1
}
grep -Fq 'PHASE=ROOT_BINARY_CHECK' "$deploy_log" || {
  printf '%s\n' 'FAIL: valid USB primary did not reach root binary check' >&2
  exit 1
}

: > "$test_dir/direct-apply-adb.log"
FAKE_ADB_LOG="$test_dir/direct-apply-adb.log" \
  "$root/scripts/mantis-tool.sh" --adb "$fixture" \
    --serial test-host:5555 --network-serial network-check:5555 \
    --output "$test_dir/direct-apply" --yes apply \
    > "$test_dir/direct-apply-out" 2> "$test_dir/direct-apply-err" || true
grep -Fq 'USB_PRIMARY_REJECTED' "$test_dir/direct-apply-err" || {
  printf '%s\n' 'FAIL: direct apply did not reject wireless primary' >&2
  exit 1
}
if grep -Fq 'pm disable-user' "$test_dir/direct-apply-adb.log"; then
  printf '%s\n' 'FAIL: direct apply mutated packages after unsafe transport' >&2
  exit 1
fi

printf '%s\n' 'USB_PRIMARY=PASS'
