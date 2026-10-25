#!/system/bin/sh
set -eu

HERE=${0%/*}
JOURNAL=$HERE/root-actions.journal
CHECKSUM=$HERE/root-actions.journal.md5
[ -f "$JOURNAL" ] && [ ! -L "$JOURNAL" ]
[ -f "$CHECKSUM" ] && [ ! -L "$CHECKSUM" ]
checksum_line=$(cat "$CHECKSUM")
expected_md5=${checksum_line%% *}
[ "${#expected_md5}" = 32 ]
case "$expected_md5" in *[!0123456789abcdefABCDEF]*) exit 1 ;; esac
[ "$checksum_line" = "$expected_md5  root-actions.journal" ]
actual_md5_line=$(md5sum "$JOURNAL" 2>/dev/null)
actual_md5=${actual_md5_line%% *}
[ "$actual_md5" = "$expected_md5" ]

[ "$(getprop ro.product.device)" = mantis ]
[ "$(getprop ro.product.model)" = AFTMM ]
[ "$(getprop ro.build.version.incremental)" = 0011644900484 ]
[ "$(id -u)" = 0 ]

package_enabled() { pm list packages -e | grep -Fqx "package:$1"; }
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

restore_if_recorded() {
  record=$1
  target=$2
  if grep -Fqx "$record $target" "$JOURNAL"; then
    pm enable "$target" || exit 1
    case "$target" in
      */*) if component_disabled "$target"; then exit 1; fi ;;
      *) package_enabled "$target" || exit 1 ;;
    esac
    return 0
  else
    printf 'skip %s: not changed by recorded deployment\n' "$target"
  fi
}

restore_hidden_if_recorded() {
  record=$1
  target=$2
  if grep -Fqx "$record $target" "$JOURNAL"; then
    pm unhide --user 0 "$target" || exit 1
    if package_hidden "$target"; then exit 1; fi
    package_enabled "$target" || exit 1
  else
    printf 'skip %s: not hidden by recorded deployment\n' "$target"
  fi
}

restore_if_recorded success-component com.amazon.tv.launcher/.ui.HomeActivity_vNext
restore_hidden_if_recorded success-hidden-package com.amazon.firehomestarter
restore_if_recorded success-component com.amazon.firehomestarter/.HomeStarterActivity
restore_hidden_if_recorded success-hidden-package com.imdb.livingroom.firetv
restore_hidden_if_recorded success-hidden-package com.amazon.venezia
restore_hidden_if_recorded success-hidden-package com.amazon.device.software.ota.override
restore_hidden_if_recorded success-hidden-package com.amazon.device.software.ota
restore_hidden_if_recorded success-hidden-package com.amazon.tv.forcedotaupdater.v2
restore_if_recorded success-package com.imdb.livingroom.firetv
restore_if_recorded success-package com.amazon.venezia
restore_if_recorded success-package com.amazon.device.software.ota.override
restore_if_recorded success-package com.amazon.device.software.ota
restore_if_recorded success-package com.amazon.tv.forcedotaupdater.v2

printf '%s\n' 'ROOT_RESTORE=PASS'
