#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
DEPLOY=$ROOT/scripts/deploy-mantis.sh
CONTROLLER=$ROOT/scripts/mantis-tool.sh
ROOT_ACTIONS=$ROOT/scripts/device-root-actions.sh
ROOT_RESTORE=$ROOT/scripts/device-root-restore.sh
PROFILE=$ROOT/exploit/profiles/mantis-NS6711-5908.conf
PATCH=$ROOT/exploit/patches/0001-feat-add-exact-Mantis-exec-only-root-port.patch
ROOT_PACKAGES=$ROOT/manifests/disable-root-packages.txt

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq "$2" "$1" || fail "$1 missing $2"; }
absent() { ! grep -Fq "$2" "$1" || fail "$1 contains forbidden $2"; }

sh -n "$DEPLOY"
sh -n "$ROOT_ACTIONS"
sh -n "$ROOT_RESTORE"
[ -x "$DEPLOY" ] && [ -x "$ROOT_ACTIONS" ] && [ -x "$ROOT_RESTORE" ] || fail 'deployment scripts are not executable'

profile_hash=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$PROFILE"; else shasum -a 256 "$PROFILE"; fi | awk '{print $1}')
[ "$profile_hash" = 1ac2127f32117bb5a9b8176b5a1b3aae04070fe5843737a875ac5b25999e0fdb ] || fail 'profile hash drift'

for identity in \
  'match.ro.product.device=mantis' \
  'match.ro.product.model=AFTMM' \
  'match.ro.build.version.incremental=0011644900484' \
  'match.uname.release=4.4.120+' \
  'match.uname.machine=armv7l'
do contains "$PROFILE" "$identity"; done

for package in \
  com.amazon.tv.forcedotaupdater.v2 \
  com.amazon.device.software.ota \
  com.amazon.device.software.ota.override \
  com.amazon.firehomestarter \
  com.amazon.venezia \
  com.imdb.livingroom.firetv
do
  contains "$ROOT_PACKAGES" "$package"
  contains "$ROOT_ACTIONS" "hide_package $package"
  contains "$ROOT_RESTORE" "restore_hidden_if_recorded success-hidden-package $package"
done
contains "$ROOT_ACTIONS" 'pm unhide --user 0 "$package"'
absent "$ROOT/manifests/preserve-core.txt" 'com.amazon.venezia'
contains "$ROOT/manifests/remove-user0.txt" 'com.amazon.imdb.tv.android.app'
contains "$ROOT/manifests/remove-user0.txt" 'com.amazon.ssm'
contains "$ROOT/manifests/preserve-core.txt" 'com.amazon.vizzini.ftvcds'
absent "$ROOT/manifests/remove-user0.txt" 'com.amazon.vizzini.ftvcds'
contains "$DEPLOY" 'manifests/disable-root-packages.txt'
contains "$DEPLOY" 'package_hidden "$package"'
contains "$ROOT_ACTIONS" 'hide_package com.amazon.firehomestarter'
contains "$ROOT_ACTIONS" 'disable_component com.amazon.tv.launcher/.ui.HomeActivity_vNext'
contains "$ROOT_RESTORE" 'restore_hidden_if_recorded success-hidden-package com.amazon.firehomestarter'
contains "$ROOT_RESTORE" 'restore_if_recorded success-component com.amazon.firehomestarter/.HomeStarterActivity'
contains "$ROOT_RESTORE" 'restore_if_recorded success-component com.amazon.tv.launcher/.ui.HomeActivity_vNext'
contains "$ROOT_ACTIONS" 'com.amazon.tv.launcher/.ui.SettingsActivity'
contains "$ROOT_ACTIONS" 'com.amazon.tv.settings.v2/.tv.network.NetworkActivity'
for protected in ar.tvplayer.tv com.wireguard.android tv.sweet.tvplayer com.wolf.firelauncher com.aurora.store; do
  contains "$ROOT_ACTIONS" "$protected"
done
contains "$ROOT_ACTIONS" 'PRESERVED_USER_APPS='
contains "$ROOT_ACTIONS" 'if package_enabled "$package"; then'
contains "$ROOT_ACTIONS" 'for package in $PRESERVED_USER_APPS; do'

absent "$ROOT_ACTIONS" 'pm clear'
absent "$ROOT_ACTIONS" 'pm uninstall'
absent "$ROOT_ACTIONS" 'setenforce'
absent "$ROOT_ACTIONS" 'mount '
absent "$ROOT_ACTIONS" 'sha256sum'
absent "$ROOT_ACTIONS" '<<'
absent "$ROOT_ACTIONS" 'awk'
contains "$ROOT_ACTIONS" 'for route in'
contains "$ROOT_ACTIONS" 'action=${route%%\|*}'
contains "$ROOT_ACTIONS" 'expected=${route#*\|}'
contains "$ROOT_ACTIONS" 'changed=${entry%%\|*}'
contains "$ROOT_ACTIONS" 'package=${entry#*\|}'
contains "$ROOT_ACTIONS" "printf '[journal] %s"
absent "$ROOT_RESTORE" 'sha256sum'
absent "$ROOT_RESTORE" 'awk'
contains "$ROOT_RESTORE" 'package_enabled "$target"'
contains "$ROOT_RESTORE" 'component_disabled "$target"'
absent "$DEPLOY" 'adb_shell sha256sum'
contains "$DEPLOY" 'adb_cmd pull "$REMOTE/$remote_file" "$readback"'
contains "$DEPLOY" 'adb_shell chmod 755 "$REMOTE"'
contains "$DEPLOY" 'adb_shell chmod 755 "$REMOTE/device-root-actions.sh"'
contains "$DEPLOY" 'check-root-binary.py'
contains "$DEPLOY" 'root-actions.journal.md5"'
absent "$DEPLOY" 'adb_shell chmod 666'
contains "$DEPLOY" "sed -n 's/^\\[journal\\] //p'"
contains "$DEPLOY" 'root-actions.journal.md5'
contains "$DEPLOY" "'[exec] ./device-root-actions.sh exited status='"
contains "$DEPLOY" 'ROOT_LAUNCH_ADB_STATUS='
contains "$DEPLOY" 'run-bounded.py" 20 "$ADB" -s "$SERIAL" shell'
contains "$DEPLOY" 'ROOT_WAIT remaining='
contains "$DEPLOY" 'MANTIS_PROGRESS_FD=3'
contains "$DEPLOY" 'fops marker absent from every reclaim socket; holding reclaim'
contains "$DEPLOY" "fail 'boot did not complete within 300 seconds'"
absent "$ROOT_ACTIONS" 'root-actions.journal.md5'
contains "$ROOT_RESTORE" 'md5sum "$JOURNAL"'
contains "$ROOT_RESTORE" 'root-actions.journal.md5'
profile_line=$(grep -n '^profile_check=' "$DEPLOY" | head -n 1 | cut -d: -f1)
wolf_line=$(grep -n '^announce_phase WOLF_INSTALL$' "$DEPLOY" | head -n 1 | cut -d: -f1)
debloat_line=$(grep -n '^announce_phase DEBLOAT_APPLY$' "$DEPLOY" | head -n 1 | cut -d: -f1)
[ -n "$profile_line" ] && [ "$profile_line" -lt "$wolf_line" ] && [ "$profile_line" -lt "$debloat_line" ] || fail 'root profile validation must precede all mutations'
absent "$DEPLOY" 'uk-UA'

contains "$DEPLOY" 'install-wolf'
contains "$DEPLOY" 'run-bounded.py'
contains "$CONTROLLER" 'run-bounded.py'
contains "$CONTROLLER" 'WolfLauncher_0.1.9-Wolf.apk'
contains "$DEPLOY" 'AuroraStore-4.8.4.apk'
contains "$DEPLOY" '8a1ed9aa09631290da91cb793e0517b0f20dc70239ac94ae6682cd94f91a4bad'
contains "$DEPLOY" '4c626157ad02bda3401a7263555f68a79663fc3e13a4d4369a12570941aa280f'
contains "$DEPLOY" "qa POST_REBOOT"
contains "$DEPLOY" 'adb_shell am start -a android.intent.action.MAIN -c android.intent.category.HOME'
contains "$DEPLOY" "printf 'QA_%s=PASS"
contains "$DEPLOY" 'screencap -p'

contains "$PATCH" 'Subject: [PATCH] feat: add exact Mantis exec-only root port'
contains "$PATCH" 'README-MANTIS.md'
contains "$PATCH" 'profiles/mantis-NS6711-5908.conf'
contains "$PATCH" 'no persistent root service is exposed'

printf '%s\n' 'DEPLOY_STATIC=PASS'
