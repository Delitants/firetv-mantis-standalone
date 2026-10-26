#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-screen-restore.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
state=$test_dir/package-state
backup=$test_dir/backup
fixture=$root/tests/fixtures/adb
refresh_checksums() {
  (
    cd "$backup"
    find . -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort |
      while IFS= read -r path; do
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$path"
        else shasum -a 256 "$path"; fi
      done > SHA256SUMS
  )
}
: > "$state"
for manifest in preserve-core.txt preserve-user-apps.txt; do
  while IFS= read -r package; do printf 'active %s\n' "$package" >> "$state"; done < "$root/manifests/$manifest"
done
printf '%s\n' 'active com.amazon.android.marketplace' >> "$state"

FAKE_PACKAGE_STATE="$state" FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 \
FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
  "$root/scripts/mantis-tool.sh" --adb "$fixture" --serial test-host:5555 \
    --output "$backup" audit > "$test_dir/audit-out" 2> "$test_dir/audit-err" || {
      printf 'FAIL: audit fixture failed: %s\n' "$(cat "$test_dir/audit-err")" >&2; exit 1;
    }

# An older deployment's protected list did not contain the screensaver.
awk '$0 != "com.amazon.ftv.screensaver"' "$backup/protected-apps.txt" > "$backup/protected-apps.next"
mv "$backup/protected-apps.next" "$backup/protected-apps.txt"
printf '%s\n' com.amazon.ftv.screensaver com.amazon.android.marketplace > "$backup/disabled-successfully.txt"
printf '%s\n' \
  'attempt com.amazon.ftv.screensaver' 'success com.amazon.ftv.screensaver' \
  'attempt com.amazon.android.marketplace' 'success com.amazon.android.marketplace' \
  > "$backup/operation-journal.txt"
awk '$2 == "com.amazon.ftv.screensaver" || $2 == "com.amazon.android.marketplace" { print "disabled", $2; next } { print }' \
  "$state" > "$state.next"
mv "$state.next" "$state"
refresh_checksums

FAKE_PACKAGE_STATE="$state" FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 \
FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
  "$root/scripts/mantis-tool.sh" --adb "$fixture" --serial test-host:5555 \
    restore "$backup" > "$test_dir/restore-out" 2> "$test_dir/restore-err" || {
      printf 'FAIL: legacy restore failed: %s\n' "$(cat "$test_dir/restore-err")" >&2; exit 1;
    }
grep -Fq 'RESTORE=PASS' "$test_dir/restore-out" || { printf '%s\n' 'FAIL: restore had no pass marker' >&2; exit 1; }
grep -Fqx 'active com.amazon.ftv.screensaver' "$state" || { printf '%s\n' 'FAIL: screensaver stayed disabled' >&2; exit 1; }
grep -Fqx 'active com.amazon.android.marketplace' "$state" || { printf '%s\n' 'FAIL: other candidate stayed disabled' >&2; exit 1; }
[ ! -s "$backup/disabled-successfully.txt" ] || { printf '%s\n' 'FAIL: restore ledger was not cleared' >&2; exit 1; }

# If the screensaver was disabled before the old backup, restoring other apps
# must preserve that historical state rather than fail the new core guard.
awk '$0 != "package:com.amazon.ftv.screensaver"' "$backup/packages-enabled.txt" > "$backup/packages-enabled.next"
mv "$backup/packages-enabled.next" "$backup/packages-enabled.txt"
printf '%s\n' com.amazon.android.marketplace > "$backup/disabled-successfully.txt"
printf '%s\n' 'skip com.amazon.ftv.screensaver' \
  'attempt com.amazon.android.marketplace' 'success com.amazon.android.marketplace' \
  > "$backup/operation-journal.txt"
: > "$backup/restore-journal.txt"
awk '$2 == "com.amazon.ftv.screensaver" || $2 == "com.amazon.android.marketplace" { print "disabled", $2; next } { print }' \
  "$state" > "$state.next"
mv "$state.next" "$state"
refresh_checksums
FAKE_PACKAGE_STATE="$state" FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 \
FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
  "$root/scripts/mantis-tool.sh" --adb "$fixture" --serial test-host:5555 \
    restore "$backup" > "$test_dir/pre-disabled-out" 2> "$test_dir/pre-disabled-err" || {
      printf 'FAIL: legacy pre-disabled restore failed: %s\n' "$(cat "$test_dir/pre-disabled-err")" >&2; exit 1;
    }
grep -Fq 'RESTORE=PASS' "$test_dir/pre-disabled-out" || { printf '%s\n' 'FAIL: pre-disabled restore had no pass marker' >&2; exit 1; }
grep -Fqx 'disabled com.amazon.ftv.screensaver' "$state" || { printf '%s\n' 'FAIL: pre-disabled screensaver state was changed' >&2; exit 1; }
grep -Fqx 'active com.amazon.android.marketplace' "$state" || { printf '%s\n' 'FAIL: other legacy candidate stayed disabled' >&2; exit 1; }

printf '%s\n' 'LEGACY_SCREENSAVER_RESTORE=PASS'
