#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-core-preflight.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

python3 - "$test_dir/root-binary" <<'PY'
import pathlib
import sys

header = bytearray(52)
header[:6] = b"\x7fELF\x01\x01"
header[18:20] = (40).to_bytes(2, "little")
pathlib.Path(sys.argv[1]).write_bytes(header + b"[ROOT] uid=0 exec-only SELinux=%s")
PY

run_case() {
  case_name=$1
  omit_package=$2
  case_dir=$test_dir/$case_name
  mkdir "$case_dir"
  package_state=$case_dir/package-state
  : > "$package_state"
  while IFS= read -r package; do
    [ "$package" = "$omit_package" ] || printf 'active %s\n' "$package" >> "$package_state"
  done < "$root/manifests/preserve-core.txt"
  : > "$case_dir/adb.log"
  FAKE_PACKAGE_STATE="$package_state" FAKE_ADB_LOG="$case_dir/adb.log" \
    "$root/scripts/deploy-mantis.sh" \
      --adb "$root/tests/fixtures/adb" --curl true --aapt true --apksigner true \
      --serial usb-primary --network-serial network-check:5555 \
      --root-binary "$test_dir/root-binary" --output "$case_dir" --yes \
      > "$case_dir/stdout" 2> "$case_dir/stderr" || true
  set -- "$case_dir"/deployment-*/deploy.log
  [ "$#" -eq 1 ] && [ -f "$1" ] || { printf 'FAIL: missing deploy log for %s\n' "$case_name" >&2; exit 1; }
  deploy_log=$1
}

run_case missing-logger com.amazon.dp.logger
grep -Fq 'PREFLIGHT_CORE_MISSING=com.amazon.dp.logger' "$deploy_log" || {
  printf '%s\n' 'FAIL: missing dp.logger was not identified before app installation' >&2
  exit 1
}
if grep -Eq 'PHASE=(SETTINGS_PREFLIGHT|ROOT_STAGING|WOLF_INSTALL|AURORA_INSTALL)' "$deploy_log"; then
  printf '%s\n' 'FAIL: missing core package was detected after additional deployment phases' >&2
  exit 1
fi
if grep -Eq ' install | pm disable-user | pm enable ' "$test_dir/missing-logger/adb.log"; then
  printf '%s\n' 'FAIL: missing core package caused a package mutation' >&2
  exit 1
fi

run_case missing-screensaver com.amazon.ftv.screensaver
grep -Fq 'PREFLIGHT_CORE_MISSING=com.amazon.ftv.screensaver' "$deploy_log" || {
  printf '%s\n' 'FAIL: missing screensaver was not identified before app installation' >&2
  exit 1
}
if grep -Eq 'PHASE=(ROOT_STAGING|WOLF_INSTALL|AURORA_INSTALL|DEBLOAT_APPLY)' "$deploy_log"; then
  printf '%s\n' 'FAIL: missing screensaver passed the deployment preflight' >&2
  exit 1
fi

run_case complete-baseline none
grep -Fq 'PREFLIGHT_CORE=PASS' "$deploy_log" || {
  printf '%s\n' 'FAIL: complete core baseline did not pass its preflight' >&2
  exit 1
}
grep -Fq 'PHASE=SETTINGS_PREFLIGHT' "$deploy_log" || {
  printf '%s\n' 'FAIL: complete core baseline did not advance to settings preflight' >&2
  exit 1
}

printf '%s\n' 'CORE_PREFLIGHT=PASS'
