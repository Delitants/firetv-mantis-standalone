#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-output-path.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

cat > "$test_dir/adb-stub" <<'EOF'
#!/bin/sh
printf 'called\n' >> "$FAKE_ADB_CALLS"
exit 1
EOF
chmod +x "$test_dir/adb-stub"

run_deploy() {
  case_name=$1
  output_dir=$2
  : > "$test_dir/adb-calls"
  status=0
  (
    cd "$test_dir"
    FAKE_ADB_CALLS="$test_dir/adb-calls" "$root/scripts/deploy-mantis.sh" \
      --adb "$test_dir/adb-stub" --curl true --aapt true --apksigner true \
      --serial test-usb --network-serial test-network:5555 \
      --root-binary "$root/tests/fixtures/aapt" \
      --output "$output_dir" --yes
  ) > "$test_dir/$case_name.out" 2> "$test_dir/$case_name.err" || status=$?
  [ "$status" -ne 0 ] || { printf 'FAIL: %s unexpectedly passed\n' "$case_name" >&2; exit 1; }
}

assert_rejected_before_side_effects() {
  case_name=$1
  output_dir=$2
  expected_message=$3
  grep -Fq "$expected_message" "$test_dir/$case_name.err" || {
    printf 'FAIL: %s lacks output-path warning: %s\n' "$case_name" "$(cat "$test_dir/$case_name.err")" >&2
    exit 1
  }
  [ ! -s "$test_dir/adb-calls" ] || { printf 'FAIL: %s reached ADB\n' "$case_name" >&2; exit 1; }
  set -- "$output_dir"/deployment-*
  [ ! -e "$1" ] || { printf 'FAIL: %s created a deployment log\n' "$case_name" >&2; exit 1; }
}

mkdir -p "$test_dir/path/to/private-backup"
run_deploy placeholder "$test_dir/path/to/private-backup"
assert_rejected_before_side_effects placeholder "$test_dir/path/to/private-backup" 'example --output path'

run_deploy missing "$test_dir/misspelled-backup"
assert_rejected_before_side_effects missing "$test_dir/misspelled-backup" 'create it first'
[ ! -e "$test_dir/misspelled-backup" ] || { printf '%s\n' 'FAIL: missing output was created' >&2; exit 1; }

run_deploy relative relative-backup
assert_rejected_before_side_effects relative "$test_dir/relative-backup" 'absolute directory'
[ ! -e "$test_dir/relative-backup" ] || { printf '%s\n' 'FAIL: relative output was created' >&2; exit 1; }

mkdir "$test_dir/real-backup"
run_deploy valid "$test_dir/real-backup"
[ -s "$test_dir/adb-calls" ] || { printf '%s\n' 'FAIL: valid output did not reach the target gate' >&2; exit 1; }
set -- "$test_dir/real-backup"/deployment-*/deploy.log
[ "$#" -eq 1 ] && [ -f "$1" ] || { printf '%s\n' 'FAIL: valid output has no deploy log' >&2; exit 1; }

printf '%s\n' 'DEPLOY_OUTPUT_PATH=PASS'
