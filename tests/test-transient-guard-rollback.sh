#!/bin/sh
set -eu

source_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-transient-rollback.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
repo=$test_dir/repo
cp -R "$source_root" "$repo"
printf '%s\n' com.amazon.android.marketplace com.amazon.bueller.music > "$repo/manifests/remove-user0.txt"
state=$test_dir/package-state
: > "$state"
for manifest in preserve-core.txt preserve-user-apps.txt remove-user0.txt; do
  while IFS= read -r package; do printf 'active %s\n' "$package" >> "$state"; done < "$repo/manifests/$manifest"
done
fixture=$repo/tests/fixtures/adb
export FAKE_PACKAGE_STATE=$state FAKE_WOLF_INSTALLED_VERSION_CODE=11900120
export FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf

# The second disable causes a guard failure. The first inverse enable is
# verified but its guard fails once; all protected state then recovers.
FAKE_AFTER_DISABLE_ADB_ENABLED=0 \
FAKE_AFTER_DISABLE_ADB_ENABLED_AFTER_COUNT=2 \
FAKE_AFTER_ENABLE_BLUETOOTH_ON=0 \
FAKE_AFTER_ENABLE_BLUETOOTH_ON_ONCE=yes \
  "$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 --output "$test_dir/backup" --yes apply \
    > "$test_dir/out" 2> "$test_dir/err" && {
      printf '%s\n' 'FAIL: apply accepted the forced guard failure' >&2; exit 1;
    }

for package in com.amazon.android.marketplace com.amazon.bueller.music; do
  grep -Fqx "active $package" "$state" || {
    printf 'FAIL: rollback did not enable %s\n' "$package" >&2; exit 1;
  }
done
[ -e "$state.bluetooth-once" ] || { printf '%s\n' 'FAIL: transient guard was not exercised' >&2; exit 1; }
[ ! -s "$test_dir/backup/disabled-successfully.txt" ] || {
  printf 'FAIL: recovered guard left a rollback ledger: %s\n' "$(cat "$test_dir/backup/disabled-successfully.txt")" >&2
  exit 1
}
grep -Fq 'guard failure restored the current batch' "$test_dir/err" || {
  printf 'FAIL: rollback did not report verified recovery: %s\n' "$(cat "$test_dir/err")" >&2
  exit 1
}
! grep -Fq 'rollback failed for' "$test_dir/err" || {
  printf '%s\n' 'FAIL: verified package enables were mislabeled as failures' >&2
  exit 1
}
(cd "$test_dir/backup" && if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c SHA256SUMS >/dev/null
else
  shasum -a 256 -c SHA256SUMS >/dev/null
fi)

printf '%s\n' 'TRANSIENT_GUARD_ROLLBACK=PASS'
