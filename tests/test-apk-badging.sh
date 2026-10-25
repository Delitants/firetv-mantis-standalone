#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/scripts/apk-badging.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Real Ubuntu aapt package lines include later attributes ending in "name".
# The package field must not be replaced by compileSdkVersionCodename.
wolf="package: name='com.wolf.firelauncher' versionCode='11900120' versionName='0.1.9-Wolf' platformBuildVersionName='10' platformBuildVersionCode='29' compileSdkVersion='23' compileSdkVersionCodename='6.0-2438415'"
aurora="package: name='com.aurora.store' versionCode='76' versionName='4.8.4' platformBuildVersionName='17' platformBuildVersionCode='37' compileSdkVersion='37' compileSdkVersionCodename='17'"
without_package="package: versionCode='76' compileSdkVersionCodename='17'"

[ "$(apk_badging_value "$wolf" name)" = com.wolf.firelauncher ] || fail 'Wolf package name was read from a later attribute'
[ "$(apk_badging_value "$aurora" name)" = com.aurora.store ] || fail 'Aurora package name was read from a later attribute'
[ -z "$(apk_badging_value "$without_package" name)" ] || fail 'missing package name was accepted'
[ "$(apk_badging_value "$wolf" versionCode)" = 11900120 ] || fail 'Wolf version code changed'
[ "$(apk_badging_value "$wolf" versionName)" = 0.1.9-Wolf ] || fail 'Wolf version name changed'
[ "$(apk_badging_value "launchable-activity: name='com.wolf.firelauncher.screens.launcher.LauncherActivity' label='Wolf Launcher'" name)" = com.wolf.firelauncher.screens.launcher.LauncherActivity ] || fail 'launcher activity changed'

printf '%s\n' 'APK_BADGING=PASS'
