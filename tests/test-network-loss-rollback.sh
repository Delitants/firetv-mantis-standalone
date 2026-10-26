#!/bin/sh
set -eu

source_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-network-rollback.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
repo=$test_dir/repo
cp -R "$source_root" "$repo"
printf '%s\n' com.amazon.android.marketplace com.amazon.bueller.music > "$repo/manifests/remove-user0.txt"
fixture=$repo/tests/fixtures/adb

verify_checksums() {
  (cd "$1" && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS >/dev/null
    else shasum -a 256 -c SHA256SUMS >/dev/null; fi)
}

prepare_state() {
  package_state=$1
  : > "$package_state"
  for manifest in preserve-core.txt preserve-user-apps.txt remove-user0.txt; do
    while IFS= read -r package; do printf 'active %s\n' "$package" >> "$package_state"; done < "$repo/manifests/$manifest"
  done
}

network_case=$test_dir/network-loss
mkdir "$network_case"
prepare_state "$network_case/package-state"
FAKE_PACKAGE_STATE="$network_case/package-state" \
FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
FAKE_NETWORK_DROP_AFTER_DISABLED_COUNT=2 \
  "$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 --output "$network_case/backup" --yes apply \
    > "$network_case/out" 2> "$network_case/err" && {
      printf '%s\n' 'FAIL: apply accepted a lost network ADB transport' >&2; exit 1;
    }
for package in com.amazon.android.marketplace com.amazon.bueller.music; do
  grep -Fqx "active $package" "$network_case/package-state" || {
    printf 'FAIL: USB rollback did not re-enable %s\n' "$package" >&2; exit 1;
  }
  grep -Fqx "$package" "$network_case/backup/disabled-successfully.txt" || {
    printf 'FAIL: incomplete full guard lost recovery ledger entry %s\n' "$package" >&2; exit 1;
  }
  grep -Fqx "attempt $package" "$network_case/backup/restore-journal.txt" || {
    printf 'FAIL: USB rollback did not journal %s\n' "$package" >&2; exit 1;
  }
done
! grep -Fq 'APPLY=PASS' "$network_case/out" || { printf '%s\n' 'FAIL: apply falsely reported success' >&2; exit 1; }
verify_checksums "$network_case/backup" || { printf '%s\n' 'FAIL: network-loss backup checksums failed' >&2; exit 1; }

# The transport becomes reachable again before the operator runs restore.
rm "$network_case/package-state.network-dropped"
FAKE_PACKAGE_STATE="$network_case/package-state" \
FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
  "$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 restore "$network_case/backup" \
    > "$network_case/restore-out" 2> "$network_case/restore-err" || {
      printf 'FAIL: recovery reconciliation failed: %s\n' "$(cat "$network_case/restore-err")" >&2; exit 1;
    }
grep -Fq 'RESTORE=PASS' "$network_case/restore-out" || { printf '%s\n' 'FAIL: recovery did not report pass' >&2; exit 1; }
[ ! -s "$network_case/backup/disabled-successfully.txt" ] || {
  printf '%s\n' 'FAIL: completed recovery left ledger entries' >&2; exit 1;
}
verify_checksums "$network_case/backup" || { printf '%s\n' 'FAIL: reconciled backup checksums failed' >&2; exit 1; }

usb_case=$test_dir/usb-loss
mkdir "$usb_case"
prepare_state "$usb_case/package-state"
FAKE_PACKAGE_STATE="$usb_case/package-state" \
FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
FAKE_USB_DROP_AFTER_DISABLED_COUNT=2 \
  "$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 --output "$usb_case/backup" --yes apply \
    > "$usb_case/out" 2> "$usb_case/err" && {
      printf '%s\n' 'FAIL: apply accepted lost USB ADB' >&2; exit 1;
    }
! grep -Fq 'APPLY=PASS' "$usb_case/out" || { printf '%s\n' 'FAIL: USB loss falsely passed apply' >&2; exit 1; }
grep -Fqx 'attempt com.amazon.bueller.music' "$usb_case/backup/operation-journal.txt" || {
  printf '%s\n' 'FAIL: USB loss dropped the attempted operation record' >&2; exit 1;
}
grep -Fqx 'com.amazon.android.marketplace' "$usb_case/backup/disabled-successfully.txt" || {
  printf '%s\n' 'FAIL: USB loss dropped the first verified disable from the recovery ledger' >&2; exit 1;
}
grep -Fqx 'disabled com.amazon.android.marketplace' "$usb_case/package-state" || {
  printf '%s\n' 'FAIL: USB loss fixture did not retain the first disabled package' >&2; exit 1;
}
verify_checksums "$usb_case/backup" || { printf '%s\n' 'FAIL: USB-loss backup checksums failed' >&2; exit 1; }

printf '%s\n' 'NETWORK_LOSS_ROLLBACK=PASS'
