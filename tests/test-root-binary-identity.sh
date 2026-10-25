#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-root-binary-identity.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM

python3 - "$test_dir" <<'PY'
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
header = bytearray(52)
header[:6] = b"\x7fELF\x01\x01"
header[18:20] = (40).to_bytes(2, "little")
markers = {
    "exec-only": b"[ROOT] uid=0 exec-only SELinux=%s",
    "legacy": b"[ROOT] uid=0 daemon pid=%d socket=@%s",
    "mixed": b"[ROOT] uid=0 exec-only SELinux=%s [ROOT] uid=0 daemon pid=%d",
}
for name, marker in markers.items():
    (directory / name).write_bytes(header + marker)
(directory / "text-only").write_bytes(markers["exec-only"])
PY

python3 "$root/scripts/check-root-binary.py" "$test_dir/exec-only" || {
  printf '%s\n' 'FAIL: exec-only marker was rejected' >&2
  exit 1
}
for candidate in legacy mixed text-only; do
  if python3 "$root/scripts/check-root-binary.py" "$test_dir/$candidate" >"$test_dir/out" 2>"$test_dir/err"; then
    printf 'FAIL: unsafe %s binary marker was accepted\n' "$candidate" >&2
    exit 1
  fi
  grep -Fq 'ROOT_BINARY_REJECTED' "$test_dir/err" || {
    printf 'FAIL: unsafe %s binary gave no actionable error\n' "$candidate" >&2
    exit 1
  }
done

printf '%s\n' 'ROOT_BINARY_IDENTITY=PASS'
