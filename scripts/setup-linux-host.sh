#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
NDK_REVISION=30.0.16248370
NDK_URL=https://dl.google.com/android/repository/android-ndk-r30-linux.zip
NDK_BYTES=738633529
NDK_SHA1=5107f898313790e449e87eee2183d9a20602dee9
BASE_COMMIT=2e73c256ff0205de6d08ea0996d15f4700e23fdc
PATCH=$ROOT/exploit/patches/0001-feat-add-exact-Mantis-exec-only-root-port.patch
PROFILE=profiles/mantis-NS6711-5908.conf
CLANG_REL=toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi24-clang

fail() { printf '%s\n' "$*" >&2; exit 1; }
confirm() {
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer || return 1
  case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}
run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; return; fi
  command -v sudo >/dev/null 2>&1 || fail 'sudo is required to install APT packages'
  sudo "$@"
}
valid_ndk() {
  [ -d "$1" ] && [ ! -L "$1" ] &&
    [ -x "$1/$CLANG_REL" ] &&
    [ -f "$1/source.properties" ] &&
    grep -Eq '^Pkg\.Revision[[:space:]]*=[[:space:]]*30[.]0[.]16248370[[:space:]]*$' "$1/source.properties"
}

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  printf '%s\n' 'usage: scripts/setup-linux-host.sh' \
    'Installs missing Ubuntu/Debian host tools and Android NDK r30 with Y/N prompts, then optionally builds GhostLock. It never runs deployment.'
  exit 0
fi
[ "$#" -eq 0 ] || fail 'usage: scripts/setup-linux-host.sh'
os_release=${MANTIS_OS_RELEASE:-/etc/os-release}
[ -f "$os_release" ] || fail "UNSUPPORTED_DISTRO missing $os_release"
ID=
ID_LIKE=
while IFS='=' read -r release_key release_value; do
  case "$release_key" in
    ID|ID_LIKE)
      case "$release_value" in
        \"*\") release_value=${release_value#\"}; release_value=${release_value%\"} ;;
      esac
      if [ "$release_key" = ID ]; then ID=$release_value
      else ID_LIKE=$release_value; fi
      ;;
  esac
done < "$os_release"
case " ${ID:-} ${ID_LIKE:-} " in
  *' ubuntu '*|*' debian '*) ;;
  *) fail "UNSUPPORTED_DISTRO ${ID:-unknown}; use Ubuntu, Debian, or an APT-based derivative" ;;
esac
[ "$(uname -m)" = x86_64 ] || fail 'UNSUPPORTED_ARCH NDK r30 Linux ZIP requires x86_64'
command -v apt-get >/dev/null 2>&1 || fail 'APT is required on this host'

missing_packages=
add_if_missing() {
  if ! command -v "$1" >/dev/null 2>&1; then
    case " $missing_packages " in
      *" $2 "*) ;;
      *) missing_packages="$missing_packages $2" ;;
    esac
  fi
}
check_host_tools() {
  missing_packages=
  add_if_missing git git
  add_if_missing curl curl
  add_if_missing unzip unzip
  add_if_missing make make
  add_if_missing python3 python3
  add_if_missing adb adb
  add_if_missing aapt aapt
  add_if_missing apksigner apksigner
  add_if_missing java default-jre-headless
  if [ ! -x /usr/sbin/update-ca-certificates ]; then
    add_if_missing update-ca-certificates ca-certificates
  fi
  add_if_missing sha1sum coreutils
  add_if_missing sha256sum coreutils
  add_if_missing realpath coreutils
  add_if_missing cmp diffutils
  add_if_missing awk mawk
  add_if_missing grep grep
}
check_host_tools
if [ -n "$missing_packages" ]; then
  confirm "Install missing APT packages:$missing_packages?" || fail 'SETUP_CANCELLED=apt'
  run_privileged apt-get update
  case " ${ID:-} ${ID_LIKE:-} " in
    *' ubuntu '*)
      if ! apt-cache show aapt >/dev/null 2>&1 || ! apt-cache show apksigner >/dev/null 2>&1; then
        confirm 'Enable the official Ubuntu universe repository for Android tools?' || fail 'SETUP_CANCELLED=universe'
        if ! command -v add-apt-repository >/dev/null 2>&1; then
          run_privileged apt-get install -y software-properties-common
        fi
        run_privileged add-apt-repository -y universe
        run_privileged apt-get update
      fi
      ;;
  esac
  # Package names above are fixed literals, never user-supplied input.
  run_privileged apt-get install -y $missing_packages
  check_host_tools
  [ -z "$missing_packages" ] || fail "HOST_TOOLS_MISSING:$missing_packages"
fi
printf '%s\n' 'HOST_TOOLS=PASS'

ndk_dir=
if [ -n "${MANTIS_NDK_DIR:-}" ]; then
  if valid_ndk "$MANTIS_NDK_DIR"; then
    ndk_dir=$(CDPATH= cd -- "$MANTIS_NDK_DIR" && pwd -P)
  fi
else
  for candidate in "$ROOT/../android-ndk-r30" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/firetv-mantis-standalone/android-ndk-r30" \
    "${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/$NDK_REVISION"; do
    if valid_ndk "$candidate"; then
      ndk_dir=$(CDPATH= cd -- "$candidate" && pwd -P)
      break
    fi
  done
fi

if [ -z "$ndk_dir" ]; then
  confirm 'Download and install Google Android NDK r30 (739 MB ZIP, several GB extracted)?' || fail 'SETUP_CANCELLED=ndk'
  cache_root=${XDG_CACHE_HOME:-$HOME/.cache}/firetv-mantis-standalone
  umask 077
  mkdir -p "$cache_root"
  [ ! -L "$cache_root" ] || fail 'NDK cache directory must not be a symlink'
  [ ! -e "$cache_root/android-ndk-r30" ] || fail "NDK cache destination already exists: $cache_root/android-ndk-r30"
  stage=$(mktemp -d "$cache_root/.ndk-stage.XXXXXX") || fail 'could not create NDK staging directory'
  trap 'rm -rf "$stage"' EXIT HUP INT TERM
  archive=$stage/android-ndk-r30-linux.zip
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 1800 \
    --output "$archive" "$NDK_URL"
  bytes=$(wc -c < "$archive" | tr -d '[:space:]')
  [ "$bytes" = "$NDK_BYTES" ] || fail "NDK download size mismatch: $bytes"
  digest=$(sha1sum "$archive" | awk '{print $1}')
  [ "$digest" = "$NDK_SHA1" ] || fail 'NDK download checksum mismatch'
  unzip -q "$archive" -d "$stage"
  valid_ndk "$stage/android-ndk-r30" || fail 'downloaded NDK compiler or revision is invalid'
  mv "$stage/android-ndk-r30" "$cache_root/android-ndk-r30"
  ndk_dir=$cache_root/android-ndk-r30
  rm -rf "$stage"
  trap - EXIT HUP INT TERM
fi
printf 'NDK_PATH=%s\n' "$ndk_dir"

if ! confirm 'Fetch/apply the pinned GhostLock source and build the root tool?'; then
  printf '%s\n' 'ROOT_BUILD=SKIPPED' 'HOST_SETUP=PASS'
  exit 0
fi

ghostlock_dir=${MANTIS_GHOSTLOCK_DIR:-$ROOT/../GhostLock}
if [ ! -e "$ghostlock_dir" ]; then
  git clone --branch 4.4 https://github.com/R0rt1z2/GhostLock.git "$ghostlock_dir"
  git -C "$ghostlock_dir" checkout --detach "$BASE_COMMIT"
fi
[ -d "$ghostlock_dir" ] && [ ! -L "$ghostlock_dir" ] || fail "GhostLock path is invalid: $ghostlock_dir"
ghostlock_dir=$(CDPATH= cd -- "$ghostlock_dir" && pwd -P)
[ "$(git -C "$ghostlock_dir" rev-parse --show-toplevel 2>/dev/null)" = "$ghostlock_dir" ] ||
  fail 'GhostLock directory is not its own Git checkout'
[ -z "$(git -C "$ghostlock_dir" status --porcelain)" ] || fail 'GhostLock checkout has uncommitted changes; inspect it first'
head_commit=$(git -C "$ghostlock_dir" rev-parse HEAD)
if [ "$head_commit" = "$BASE_COMMIT" ]; then
  git -C "$ghostlock_dir" -c user.name='Mantis Local Build' \
    -c user.email='mantis-build@example.invalid' am "$PATCH"
else
  parent_commit=$(git -C "$ghostlock_dir" rev-parse HEAD^ 2>/dev/null || true)
  [ "$parent_commit" = "$BASE_COMMIT" ] &&
    [ "$(git -C "$ghostlock_dir" log -1 --format=%s)" = 'feat: add exact Mantis exec-only root port' ] ||
    fail 'GhostLock is not at the pinned base or its Mantis patch commit'
fi
cmp -s "$ROOT/exploit/profiles/mantis-NS6711-5908.conf" "$ghostlock_dir/$PROFILE" ||
  fail 'GhostLock Mantis profile differs from the pinned profile'
(
  cd "$ghostlock_dir"
  cat <<'EOF' | sha256sum -c - >/dev/null
6de598877792f9b6f25d66e6ecf9be030e86cb64231bd125e4bd91eb36ed1488  VERSION
178942ef517d3b0bb8392bc38a58d2e4c9b67a6ea6d5c605e19f5b9afd642a52  Makefile
163832e9f57528ba045a2465737c6a438e175b1a69feadab63fe056bb655dd1b  src/gl_root.c
978addde4fcf6627b12dc7e13c927c1c5a6b64f3f4a1dfdf2790d311bcc38b34  src/gl_profile.c
3a33e2e0b00f271cf0ec8902998fd660ae42f10b93daa74a5511bf35c9f99dd8  src/gl_profile.h
c3173a2179e97b75b9668c5f4708d427e0711189025cc769e3bc4f809ea1123c  src/gl_profiles_embedded.h
35ca8ec7a63ff91f26a48d003738cc2a74db5066b3e0a80ba5f48bad20b5f4d5  src/gl_reclaim.h
1ac2127f32117bb5a9b8176b5a1b3aae04070fe5843737a875ac5b25999e0fdb  profiles/mantis-NS6711-5908.conf
EOF
) || fail 'GhostLock source differs from the pinned Mantis patch'
clang=$ndk_dir/$CLANG_REL
make -C "$ghostlock_dir" NDK="$ndk_dir" CC="$clang" API=24
python3 "$ROOT/scripts/check-root-binary.py" "$ghostlock_dir/build/ghostlock_root"
printf 'ROOT_BINARY=%s\n' "$ghostlock_dir/build/ghostlock_root"
printf '%s\n' 'ROOT_BUILD=PASS' 'HOST_SETUP=PASS'
