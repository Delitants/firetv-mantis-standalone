#!/system/bin/sh
set -u

HERE=${0%/*}
JOURNAL=$HERE/root-actions.journal
CHECKSUM=$HERE/root-actions.journal.md5
: > "$JOURNAL" || exit 70

changed_forced=0
changed_ota=0
changed_override=0
changed_venezia=0
changed_imdb=0
changed_fallback=0
changed_primary=0

record() { printf '%s\n' "$*" >> "$JOURNAL"; }
enabled_packages() { pm list packages -e; }
disabled_packages() { pm list packages -d; }
package_enabled() { enabled_packages | grep -Fqx "package:$1"; }
package_disabled() { disabled_packages | grep -Fqx "package:$1"; }
component_disabled() {
  component=$1
  package=${component%%/*}
  class=${component#*/}
  case "$class" in .*) class=$package$class ;; esac
  dumpsys package "$package" | sed -n '/disabledComponents:/,/^[^ ]/p' | grep -Fqx "        $class"
}

rollback() {
  record 'rollback begin'
  [ "$changed_primary" = 0 ] || pm enable com.amazon.tv.launcher/.ui.HomeActivity_vNext >/dev/null 2>&1
  [ "$changed_fallback" = 0 ] || pm enable com.amazon.firehomestarter/.HomeStarterActivity >/dev/null 2>&1
  [ "$changed_imdb" = 0 ] || pm enable com.imdb.livingroom.firetv >/dev/null 2>&1
  [ "$changed_venezia" = 0 ] || pm enable com.amazon.venezia >/dev/null 2>&1
  [ "$changed_override" = 0 ] || pm enable com.amazon.device.software.ota.override >/dev/null 2>&1
  [ "$changed_ota" = 0 ] || pm enable com.amazon.device.software.ota >/dev/null 2>&1
  [ "$changed_forced" = 0 ] || pm enable com.amazon.tv.forcedotaupdater.v2 >/dev/null 2>&1
  record 'rollback end'
}

fail() {
  record "failure $*"
  rollback
  printf 'ROOT_ACTIONS=FAIL reason=%s\n' "$*"
  exit 1
}

expect_prop() {
  actual=$(getprop "$1") || fail "getprop-$1"
  [ "$actual" = "$2" ] || fail "identity-$1"
}

expect_prop ro.product.manufacturer Amazon
expect_prop ro.product.model AFTMM
expect_prop ro.product.device mantis
expect_prop ro.build.id NS6711
expect_prop ro.build.version.incremental 0011644900484
expect_prop ro.build.fingerprint 'Amazon/mantis/mantis:6.0/NS6711/5908N:user/amz-p,release-keys'
[ "$(uname -r)" = '4.4.120+' ] || fail kernel-release
[ "$(uname -m)" = armv7l ] || fail kernel-machine
[ "$(id -u)" = 0 ] || fail not-root
[ "$(getenforce)" = Enforcing ] || fail selinux-not-enforcing

for package in \
  ar.tvplayer.tv com.wireguard.android tv.sweet.tvplayer \
  com.wolf.firelauncher com.aurora.store \
  com.amazon.tv.launcher com.amazon.tv.settings.v2 \
  com.android.bluetooth com.amazon.tcomm \
  com.amazon.whisperjoin.middleware.np com.amazon.whisperlink.core.android
do
  package_enabled "$package" || fail "protected-package-$package"
done

disable_package() {
  package=$1
  flag=$2
  if package_disabled "$package"; then
    record "skip-package $package"
    return 0
  fi
  package_enabled "$package" || fail "package-state-$package"
  record "attempt-package $package"
  status=0
  pm disable "$package" >/dev/null 2>&1 || status=$?
  if package_disabled "$package"; then eval "$flag=1"; fi
  [ "$status" = 0 ] || fail "disable-package-$package"
  package_disabled "$package" || fail "verify-package-$package"
  eval "$flag=1"
  record "success-package $package"
}

disable_component() {
  component=$1
  flag=$2
  if component_disabled "$component"; then
    record "skip-component $component"
    return 0
  fi
  record "attempt-component $component"
  status=0
  output=$(pm disable "$component" 2>&1) || status=$?
  if component_disabled "$component"; then eval "$flag=1"; fi
  [ "$status" = 0 ] || fail "disable-component-$component"
  case "$output" in
    *'new state: disabled'*|*'new state: disabled-user'*|*'new state: disabled_until_used'*) ;;
    *) fail "verify-component-$component" ;;
  esac
  component_disabled "$component" || fail "verify-component-$component"
  record "success-component $component"
}

disable_package com.amazon.tv.forcedotaupdater.v2 changed_forced
disable_package com.amazon.device.software.ota changed_ota
disable_package com.amazon.device.software.ota.override changed_override
disable_package com.amazon.venezia changed_venezia
disable_package com.imdb.livingroom.firetv changed_imdb

disable_component com.amazon.firehomestarter/.HomeStarterActivity changed_fallback
disable_component com.amazon.tv.launcher/.ui.HomeActivity_vNext changed_primary

home=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
[ "$home" = 'com.wolf.firelauncher/.screens.launcher.LauncherActivity' ] || fail wolf-home-resolver

while IFS='|' read -r action expected; do
  actual=$(cmd package resolve-activity --brief -a "$action" 2>/dev/null | tail -n 1)
  [ "$actual" = "$expected" ] || fail "settings-route-$action"
done <<'EOF'
android.settings.SETTINGS|com.amazon.tv.launcher/.ui.SettingsActivity
android.settings.WIFI_SETTINGS|com.amazon.tv.settings.v2/.tv.network.NetworkActivity
android.settings.MANAGE_APPLICATIONS_SETTINGS|com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity
android.settings.CONTROLLERS_SETTINGS|com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity
android.settings.DEVICE_INFO_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity
android.settings.ACCESSIBILITY_SETTINGS|com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity
android.settings.DISPLAY_SETTINGS|com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity
com.amazon.device.settings.action.DATE_TIME|com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity
com.amazon.device.settings.action.LANGUAGE|com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity
android.settings.APPLICATION_DEVELOPMENT_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity
EOF

[ "$(settings get global adb_enabled)" = 1 ] || fail adb-disabled
[ "$(getprop init.svc.adbd)" = running ] || fail adbd-not-running
case ",$(getprop persist.sys.usb.config)," in *,adb,*) ;; *) fail usb-adb-missing ;; esac
[ "$(getprop service.adb.tcp.port)" = 5555 ] || fail network-adb-port
[ "$(settings get global bluetooth_on)" = 1 ] || fail bluetooth-disabled

am start -n com.wolf.firelauncher/.screens.launcher.LauncherActivity >/dev/null 2>&1 || fail wolf-launch
input keyevent 3 >/dev/null 2>&1 || fail home-key
record 'complete'
journal_md5=$(md5sum "$JOURNAL" 2>/dev/null | awk '{print $1}') || fail journal-checksum
[ -n "$journal_md5" ] || fail journal-checksum-empty
printf '%s  %s\n' "$journal_md5" 'root-actions.journal' > "$CHECKSUM" || fail journal-checksum-write
printf '%s\n' 'ROOT_ACTIONS=PASS'
exit 0
