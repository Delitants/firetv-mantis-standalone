#!/system/bin/sh
set -u

changed_forced=0
changed_ota=0
changed_override=0
changed_venezia=0
changed_imdb=0
changed_starter=0
changed_primary=0

record() {
  printf '[journal] %s\n' "$*" >&2 && return 0
  rollback
  printf '%s\n' 'ROOT_ACTIONS=FAIL reason=journal-write'
  exit 74
}
enabled_packages() { pm list packages -e; }
disabled_packages() { pm list packages -d; }
package_enabled() { enabled_packages | grep -Fqx "package:$1"; }
package_disabled() { disabled_packages | grep -Fqx "package:$1"; }
package_hidden() {
  dumpsys package "$1" | grep -F 'User 0:' | grep -Fq 'installed=true hidden=true'
}
component_disabled() {
  component=$1
  package=${component%%/*}
  class=${component#*/}
  case "$class" in .*) class=$package$class ;; esac
  dumpsys package "$package" | sed -n '/disabledComponents:/,/^[^ ]/p' | grep -Fqx "        $class"
}

rollback() {
  rollback_failed=0
  printf '%s\n' '[journal] rollback begin' >&2 || :
  if [ "$changed_primary" != 0 ]; then
    pm enable com.amazon.tv.launcher/.ui.HomeActivity_vNext >/dev/null 2>&1 || rollback_failed=1
    component_disabled com.amazon.tv.launcher/.ui.HomeActivity_vNext && rollback_failed=1
  fi
  if [ "$changed_starter" != 0 ]; then
    pm unhide --user 0 com.amazon.firehomestarter >/dev/null 2>&1 || rollback_failed=1
    package_hidden com.amazon.firehomestarter && rollback_failed=1
    package_enabled com.amazon.firehomestarter || rollback_failed=1
  fi
  for entry in \
    "$changed_imdb|com.imdb.livingroom.firetv" \
    "$changed_venezia|com.amazon.venezia" \
    "$changed_override|com.amazon.device.software.ota.override" \
    "$changed_ota|com.amazon.device.software.ota" \
    "$changed_forced|com.amazon.tv.forcedotaupdater.v2"
  do
    changed=${entry%%\|*}
    package=${entry#*\|}
    if [ "$changed" != 0 ]; then
      pm unhide --user 0 "$package" >/dev/null 2>&1 || rollback_failed=1
      package_hidden "$package" && rollback_failed=1
      package_enabled "$package" || rollback_failed=1
    fi
  done
  if [ "$rollback_failed" = 0 ]; then
    printf '%s\n' '[journal] rollback complete' >&2 || :
    printf '%s\n' 'ROOT_ROLLBACK=PASS'
  else
    printf '%s\n' '[journal] rollback incomplete' >&2 || :
    printf '%s\n' 'ROOT_ROLLBACK=FAIL'
  fi
}

fail() {
  printf '[journal] failure %s\n' "$*" >&2 || :
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

PRESERVED_USER_APPS=
for package in ar.tvplayer.tv com.wireguard.android tv.sweet.tvplayer; do
  if package_enabled "$package"; then
    PRESERVED_USER_APPS="$PRESERVED_USER_APPS $package"
  fi
done

require_protected_packages() {
  for package in $PRESERVED_USER_APPS; do
    package_enabled "$package" || fail "protected-package-$package"
  done
  for package in \
    com.wolf.firelauncher com.aurora.store \
    com.amazon.tv.launcher com.amazon.tv.settings.v2 \
    com.android.bluetooth com.amazon.tcomm \
    com.amazon.whisperjoin.middleware.np com.amazon.whisperlink.core.android
  do
    package_enabled "$package" || fail "protected-package-$package"
  done
}

require_protected_packages

hide_package() {
  package=$1
  flag=$2
  if package_hidden "$package"; then
    record "skip-hidden-package $package"
    return 0
  fi
  package_enabled "$package" || fail "package-state-$package"
  record "attempt-hidden-package $package"
  status=0
  pm hide --user 0 "$package" >/dev/null 2>&1 || status=$?
  if package_hidden "$package"; then eval "$flag=1"; fi
  [ "$status" = 0 ] || fail "hide-package-$package"
  package_hidden "$package" || fail "verify-hidden-package-$package"
  eval "$flag=1"
  record "success-hidden-package $package"
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

hide_package com.amazon.tv.forcedotaupdater.v2 changed_forced
hide_package com.amazon.device.software.ota changed_ota
hide_package com.amazon.device.software.ota.override changed_override
hide_package com.amazon.venezia changed_venezia
hide_package com.imdb.livingroom.firetv changed_imdb

hide_package com.amazon.firehomestarter changed_starter
disable_component com.amazon.tv.launcher/.ui.HomeActivity_vNext changed_primary
require_protected_packages

home=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1)
[ "$home" = 'com.wolf.firelauncher/.screens.launcher.LauncherActivity' ] || fail wolf-home-resolver

for route in \
  'android.settings.SETTINGS|com.amazon.tv.launcher/.ui.SettingsActivity' \
  'android.settings.WIFI_SETTINGS|com.amazon.tv.settings.v2/.tv.network.NetworkActivity' \
  'android.settings.MANAGE_APPLICATIONS_SETTINGS|com.amazon.tv.settings.v2/.tv.applications.ApplicationsActivity' \
  'android.settings.CONTROLLERS_SETTINGS|com.amazon.tv.settings.v2/.tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity' \
  'android.settings.DEVICE_INFO_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity' \
  'android.settings.ACCESSIBILITY_SETTINGS|com.amazon.tv.settings.v2/.tv.accessibility.AccessibilityActivity' \
  'android.settings.DISPLAY_SETTINGS|com.amazon.tv.settings.v2/.tv.display_sounds.DisplayAndSoundsActivity' \
  'com.amazon.device.settings.action.DATE_TIME|com.amazon.tv.settings.v2/.tv.preferences.PreferencesActivity' \
  'com.amazon.device.settings.action.LANGUAGE|com.amazon.tv.settings.v2/.tv.preferences.LanguageSelectActivity' \
  'android.settings.APPLICATION_DEVELOPMENT_SETTINGS|com.amazon.tv.settings.v2/.tv.device.DeviceActivity'
do
  action=${route%%\|*}
  expected=${route#*\|}
  actual=$(cmd package resolve-activity --brief -a "$action" 2>/dev/null | tail -n 1)
  [ "$actual" = "$expected" ] || fail "settings-route-$action"
done

[ "$(settings get global adb_enabled)" = 1 ] || fail adb-disabled
[ "$(getprop init.svc.adbd)" = running ] || fail adbd-not-running
case ",$(getprop persist.sys.usb.config)," in *,adb,*) ;; *) fail usb-adb-missing ;; esac
[ "$(getprop service.adb.tcp.port)" = 5555 ] || fail network-adb-port
[ "$(settings get global bluetooth_on)" = 1 ] || fail bluetooth-disabled

am start -n com.wolf.firelauncher/.screens.launcher.LauncherActivity >/dev/null 2>&1 || fail wolf-launch
am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1 || fail home-intent
record 'complete'
printf '%s\n' 'ROOT_ACTIONS=PASS'
exit 0
