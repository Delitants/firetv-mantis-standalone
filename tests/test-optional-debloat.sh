#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-optional-debloat.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
state=$test_dir/package-state
fixture=$root/tests/fixtures/adb

[ -f "$root/manifests/remove-if-present-user0.txt" ] || {
  printf '%s\n' 'FAIL: optional package manifest is missing' >&2
  exit 1
}
grep -Fqx 'com.amazon.firebat' "$root/manifests/remove-user0.txt" || {
  printf '%s\n' 'FAIL: stock Prime Video package left the required debloat list' >&2
  exit 1
}
for package in com.amazon.alexashopping com.amazon.amazonvideo.livingroom com.amazon.shoptv.client com.amazon.shoptv.firetv.client; do
  grep -Fqx "$package" "$root/manifests/remove-if-present-user0.txt" || {
    printf 'FAIL: optional package is missing: %s\n' "$package" >&2
    exit 1
  }
done

make_state() {
  : > "$state"
  for manifest in preserve-core.txt preserve-user-apps.txt; do
    while IFS= read -r package; do printf 'active %s\n' "$package" >> "$state"; done < "$root/manifests/$manifest"
  done
  while IFS= read -r package; do printf 'disabled %s\n' "$package" >> "$state"; done < "$root/manifests/remove-user0.txt"
}

run_apply() {
  case_name=$1
  FAKE_PACKAGE_STATE="$state" FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 \
  FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
    "$root/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
      --network-serial network-check:5555 --output "$test_dir/$case_name" \
      --yes apply > "$test_dir/$case_name.out" 2> "$test_dir/$case_name.err" || {
        printf 'FAIL: optional apply %s failed: %s\n' "$case_name" "$(cat "$test_dir/$case_name.err")" >&2
        exit 1
      }
  grep -Fq 'APPLY=PASS' "$test_dir/$case_name.out" || { printf 'FAIL: %s did not pass\n' "$case_name" >&2; exit 1; }
}

make_state
run_apply absent
for package in com.amazon.alexashopping com.amazon.amazonvideo.livingroom com.amazon.shoptv.client com.amazon.shoptv.firetv.client; do
  grep -Fqx "skip-absent $package" "$test_dir/absent/operation-journal.txt" || {
    printf 'FAIL: absent optional package was not skipped: %s\n' "$package" >&2
    exit 1
  }
done
[ ! -s "$test_dir/absent/disabled-successfully.txt" ] || {
  printf '%s\n' 'FAIL: an absent optional package entered the restore ledger' >&2
  exit 1
}

make_state
printf '%s\n' 'active com.amazon.amazonvideo.livingroom' >> "$state"
run_apply present-prime
grep -Fqx 'disabled com.amazon.amazonvideo.livingroom' "$state" || {
  printf '%s\n' 'FAIL: installed Prime Video remained enabled' >&2
  exit 1
}
grep -Fqx 'com.amazon.amazonvideo.livingroom' "$test_dir/present-prime/disabled-successfully.txt" || {
  printf '%s\n' 'FAIL: disabled Prime Video was not journaled for restore' >&2
  exit 1
}

FAKE_PACKAGE_STATE="$state" FAKE_WOLF_INSTALLED_VERSION_CODE=11900120 \
FAKE_WOLF_INSTALLED_VERSION_NAME=0.1.9-Wolf \
  "$root/scripts/mantis-tool.sh" --adb "$fixture" --serial usb-primary \
    --network-serial network-check:5555 restore "$test_dir/present-prime" \
    > "$test_dir/restore.out" 2> "$test_dir/restore.err" || {
      printf 'FAIL: Prime Video restore failed: %s\n' "$(cat "$test_dir/restore.err")" >&2
      exit 1
    }
grep -Fq 'RESTORE=PASS' "$test_dir/restore.out" || { printf '%s\n' 'FAIL: Prime restore did not pass' >&2; exit 1; }
grep -Fqx 'active com.amazon.amazonvideo.livingroom' "$state" || {
  printf '%s\n' 'FAIL: Prime Video did not restore to enabled' >&2
  exit 1
}

printf '%s\n' 'OPTIONAL_DEBLOAT=PASS'
