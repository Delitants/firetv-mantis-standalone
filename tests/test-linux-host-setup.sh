#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mantis-linux-setup.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
bin=$test_dir/bin
mkdir "$bin" "$test_dir/cache" "$test_dir/ndk"
printf '%s\n' 'ID=debian' > "$test_dir/debian-release"
printf '%s\n' 'ID=ubuntu' > "$test_dir/ubuntu-release"
printf '%s\n' 'ID=linuxmint' 'ID_LIKE="ubuntu debian"' > "$test_dir/derivative-release"
printf '%s\n' 'ID=fedora' > "$test_dir/other-release"

cat > "$bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' x86_64
EOF
cat > "$bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat > "$bin/apt-get" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$APT_LOG"
case "$1" in
  install)
    for arg do
      if [ "$arg" = aapt ]; then
        printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/aapt"
        chmod +x "$FAKE_BIN/aapt"
      fi
    done
    ;;
esac
EOF
cat > "$bin/apt-cache" <<'EOF'
#!/bin/sh
[ "${FAKE_APT_CACHE_FAIL:-no}" = no ] || exit 1
exit 0
EOF
for tool in adb aapt apksigner java update-ca-certificates sha1sum sha256sum; do
  printf '#!/bin/sh\nexit 0\n' > "$bin/$tool"
done
chmod +x "$bin"/*

ndk=$test_dir/ndk
clang=$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi24-clang
mkdir -p "$(dirname "$clang")"
printf '%s\n' 'Pkg.Revision = 30.0.16248370' > "$ndk/source.properties"
printf '#!/bin/sh\nexit 0\n' > "$clang"
chmod +x "$clang"

run_setup() {
  case_name=$1
  release_file=$2
  ndk_dir=$3
  input=$4
  status=0
  : > "$test_dir/apt.log"
  printf '%b' "$input" | env PATH="$bin:$PATH" APT_LOG="$test_dir/apt.log" \
    FAKE_BIN="$bin" MANTIS_OS_RELEASE="$release_file" \
    MANTIS_NDK_DIR="$ndk_dir" XDG_CACHE_HOME="$test_dir/cache" \
    sh "$root/scripts/setup-linux-host.sh" > "$test_dir/$case_name.out" 2> "$test_dir/$case_name.err" || status=$?
  SETUP_STATUS=$status
  SETUP_OUTPUT=$(cat "$test_dir/$case_name.out" "$test_dir/$case_name.err")
}

run_setup ready "$test_dir/debian-release" "$ndk" 'n\n'
[ "$SETUP_STATUS" -eq 0 ] || { printf 'FAIL: ready Debian host failed: %s\n' "$SETUP_OUTPUT" >&2; exit 1; }
case "$SETUP_OUTPUT" in *ROOT_BUILD=SKIPPED*HOST_SETUP=PASS*) ;; *)
  printf 'FAIL: ready host did not report setup pass: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
[ ! -s "$test_dir/apt.log" ] || { printf '%s\n' 'FAIL: ready host invoked apt' >&2; exit 1; }

run_setup derivative "$test_dir/derivative-release" "$ndk" 'n\n'
[ "$SETUP_STATUS" -eq 0 ] || { printf 'FAIL: Ubuntu/Debian derivative failed: %s\n' "$SETUP_OUTPUT" >&2; exit 1; }

printf 'ID=debian\nEVIL=$(touch "%s")\n' "$test_dir/should-not-exist" > "$test_dir/untrusted-release"
run_setup untrusted-release "$test_dir/untrusted-release" "$ndk" 'n\n'
[ "$SETUP_STATUS" -eq 0 ] || { printf 'FAIL: release parser rejected valid ID: %s\n' "$SETUP_OUTPUT" >&2; exit 1; }
[ ! -e "$test_dir/should-not-exist" ] || { printf '%s\n' 'FAIL: OS release file was executed' >&2; exit 1; }

run_setup unsupported "$test_dir/other-release" "$ndk" ''
[ "$SETUP_STATUS" -ne 0 ] || { printf '%s\n' 'FAIL: unsupported distro passed' >&2; exit 1; }
case "$SETUP_OUTPUT" in *UNSUPPORTED_DISTRO*) ;; *)
  printf 'FAIL: unsupported distro lacks clear error: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
[ ! -s "$test_dir/apt.log" ] || { printf '%s\n' 'FAIL: unsupported distro invoked apt' >&2; exit 1; }

run_setup no-ndk "$test_dir/ubuntu-release" "$test_dir/missing-ndk" 'n\n'
[ "$SETUP_STATUS" -ne 0 ] || { printf '%s\n' 'FAIL: declined NDK download passed' >&2; exit 1; }
case "$SETUP_OUTPUT" in *SETUP_CANCELLED=ndk*) ;; *)
  printf 'FAIL: declined NDK lacks clear result: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
[ ! -s "$test_dir/apt.log" ] || { printf '%s\n' 'FAIL: NDK refusal invoked apt' >&2; exit 1; }

cat > "$bin/curl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then printf 'invalid archive' > "$2"; exit 0; fi
  shift
done
exit 1
EOF
chmod +x "$bin/curl"
run_setup bad-download "$test_dir/debian-release" "$test_dir/missing-ndk" 'y\n'
[ "$SETUP_STATUS" -ne 0 ] || { printf '%s\n' 'FAIL: invalid NDK download passed' >&2; exit 1; }
case "$SETUP_OUTPUT" in *'NDK download size mismatch'*) ;; *)
  printf 'FAIL: invalid NDK lacks integrity error: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
[ ! -e "$test_dir/cache/firetv-mantis-standalone/android-ndk-r30" ] || {
  printf '%s\n' 'FAIL: invalid NDK was installed' >&2; exit 1;
}
set -- "$test_dir/cache/firetv-mantis-standalone"/.ndk-stage.*
[ ! -e "$1" ] || { printf '%s\n' 'FAIL: invalid NDK staging was retained' >&2; exit 1; }
rm "$bin/curl"

printf '%s\n' 'Pkg.Revision = 29.0.0' > "$ndk/source.properties"
run_setup wrong-ndk "$test_dir/debian-release" "$ndk" 'n\n'
[ "$SETUP_STATUS" -ne 0 ] || { printf '%s\n' 'FAIL: wrong NDK revision passed' >&2; exit 1; }
case "$SETUP_OUTPUT" in *SETUP_CANCELLED=ndk*) ;; *)
  printf 'FAIL: wrong NDK did not request the pinned release: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
printf '%s\n' 'Pkg.Revision = 30.0.16248370' > "$ndk/source.properties"

rm "$bin/aapt"
run_setup no-apt "$test_dir/debian-release" "$ndk" 'n\n'
[ "$SETUP_STATUS" -ne 0 ] || { printf '%s\n' 'FAIL: declined apt install passed' >&2; exit 1; }
case "$SETUP_OUTPUT" in *SETUP_CANCELLED=apt*) ;; *)
  printf 'FAIL: declined apt install lacks clear result: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac
[ ! -s "$test_dir/apt.log" ] || { printf '%s\n' 'FAIL: apt ran after refusal' >&2; exit 1; }

status=0
printf 'y\nn\n' | env PATH="$bin:$PATH" APT_LOG="$test_dir/apt.log" \
  FAKE_BIN="$bin" FAKE_APT_CACHE_FAIL=yes MANTIS_OS_RELEASE="$test_dir/ubuntu-release" \
  MANTIS_NDK_DIR="$ndk" XDG_CACHE_HOME="$test_dir/cache" \
  sh "$root/scripts/setup-linux-host.sh" > "$test_dir/universe.out" 2> "$test_dir/universe.err" || status=$?
[ "$status" -ne 0 ] || { printf '%s\n' 'FAIL: declined Universe change passed' >&2; exit 1; }
grep -Fq 'SETUP_CANCELLED=universe' "$test_dir/universe.err" || {
  printf '%s\n' 'FAIL: declined Universe change lacks clear result' >&2; exit 1;
}
[ ! -e "$bin/aapt" ] || { printf '%s\n' 'FAIL: Universe refusal installed aapt' >&2; exit 1; }

cat > "$bin/add-apt-repository" <<'EOF'
#!/bin/sh
printf 'add-apt-repository %s\n' "$*" >> "$APT_LOG"
EOF
chmod +x "$bin/add-apt-repository"
status=0
printf 'y\ny\nn\n' | env PATH="$bin:$PATH" APT_LOG="$test_dir/apt.log" \
  FAKE_BIN="$bin" FAKE_APT_CACHE_FAIL=yes MANTIS_OS_RELEASE="$test_dir/ubuntu-release" \
  MANTIS_NDK_DIR="$ndk" XDG_CACHE_HOME="$test_dir/cache" \
  sh "$root/scripts/setup-linux-host.sh" > "$test_dir/universe-yes.out" 2> "$test_dir/universe-yes.err" || status=$?
[ "$status" -eq 0 ] || { printf 'FAIL: approved Universe change failed: %s\n' "$(cat "$test_dir/universe-yes.err")" >&2; exit 1; }
grep -Fq 'add-apt-repository -y universe' "$test_dir/apt.log" || {
  printf '%s\n' 'FAIL: approved Universe change did not enable repository' >&2; exit 1;
}
grep -Fq 'HOST_SETUP=PASS' "$test_dir/universe-yes.out" || {
  printf '%s\n' 'FAIL: approved Universe change did not complete setup' >&2; exit 1;
}
rm "$bin/aapt"

run_setup install-apt "$test_dir/debian-release" "$ndk" 'y\nn\n'
[ "$SETUP_STATUS" -eq 0 ] || { printf 'FAIL: approved apt install failed: %s\n' "$SETUP_OUTPUT" >&2; exit 1; }
grep -Fq 'update' "$test_dir/apt.log" || { printf '%s\n' 'FAIL: approved apt install skipped update' >&2; exit 1; }
grep -Fq 'install -y aapt' "$test_dir/apt.log" || { printf '%s\n' 'FAIL: approved apt install skipped aapt' >&2; exit 1; }
case "$SETUP_OUTPUT" in *ROOT_BUILD=SKIPPED*HOST_SETUP=PASS*) ;; *)
  printf 'FAIL: approved apt install did not finish: %s\n' "$SETUP_OUTPUT" >&2; exit 1 ;;
esac

printf '%s\n' 'LINUX_HOST_SETUP=PASS'
