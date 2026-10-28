#!/bin/sh
set -eu

source_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-rerun.XXXXXX")
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
export FAKE_ADB_LOG=$test_dir/adb.log

FAKE_DISABLE_ERROR_AFTER_STATE_PACKAGE=com.amazon.android.marketplace \
  "$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 --output "$test_dir/first-backup" --yes apply \
    > "$test_dir/first.out" 2> "$test_dir/first.err" || {
      printf 'FAIL: verified state transition was rejected: %s\n' "$(cat "$test_dir/first.err")" >&2
      exit 1
    }
grep -Fq 'APPLY=PASS' "$test_dir/first.out"
grep -Fqx 'success com.amazon.android.marketplace' "$test_dir/first-backup/operation-journal.txt"
grep -Fqx 'disabled com.amazon.android.marketplace' "$state"
! grep -Fq 'shell pm enable --user 0 com.amazon.android.marketplace' "$FAKE_ADB_LOG"

# The first run's backup is gone. The fresh run must only converge from the
# observed package state and must never invent an original enabled baseline.
rm -rf "$test_dir/first-backup"
: > "$FAKE_ADB_LOG"
"$repo/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
  --network-serial network-check:5555 --output "$test_dir/second-backup" --yes apply \
  > "$test_dir/second.out" 2> "$test_dir/second.err" || {
    printf 'FAIL: rerun rejected observed partial state: %s\n' "$(cat "$test_dir/second.err")" >&2
    exit 1
  }
grep -Fq 'APPLY=PASS' "$test_dir/second.out"
grep -Fqx 'skip com.amazon.android.marketplace' "$test_dir/second-backup/operation-journal.txt"
! grep -Fq 'shell pm disable-user --user 0' "$FAKE_ADB_LOG"
! grep -Fq 'shell pm enable --user 0' "$FAKE_ADB_LOG"
(cd "$test_dir/second-backup" && if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c SHA256SUMS >/dev/null
else
  shasum -a 256 -c SHA256SUMS >/dev/null
fi)

printf '%s\n' 'RERUN_NO_BACKUP=PASS'
