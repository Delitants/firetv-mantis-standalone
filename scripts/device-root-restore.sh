#!/system/bin/sh
set -eu

HERE=${0%/*}
JOURNAL=$HERE/root-actions.journal
CHECKSUM=$HERE/root-actions.journal.md5
[ -f "$JOURNAL" ] && [ ! -L "$JOURNAL" ]
[ -f "$CHECKSUM" ] && [ ! -L "$CHECKSUM" ]
expected_md5=$(awk '
  NR == 1 && NF == 2 && length($1) == 32 && $1 !~ /[^0-9a-fA-F]/ && $2 == "root-actions.journal" {
    value = $1
    next
  }
  { exit 1 }
  END {
    if (NR != 1 || value == "") exit 1
    print value
  }
' "$CHECKSUM")
actual_md5=$(md5sum "$JOURNAL" 2>/dev/null | awk '{print $1}')
[ "$actual_md5" = "$expected_md5" ]

[ "$(getprop ro.product.device)" = mantis ]
[ "$(getprop ro.product.model)" = AFTMM ]
[ "$(getprop ro.build.version.incremental)" = 0011644900484 ]
[ "$(id -u)" = 0 ]

restore_if_recorded() {
  record=$1
  target=$2
  if grep -Fqx "$record $target" "$JOURNAL"; then
    pm enable "$target"
  else
    printf 'skip %s: not changed by recorded deployment\n' "$target"
  fi
}

restore_if_recorded success-component com.amazon.tv.launcher/.ui.HomeActivity_vNext
restore_if_recorded success-component com.amazon.firehomestarter/.HomeStarterActivity
restore_if_recorded success-package com.imdb.livingroom.firetv
restore_if_recorded success-package com.amazon.venezia
restore_if_recorded success-package com.amazon.device.software.ota.override
restore_if_recorded success-package com.amazon.device.software.ota
restore_if_recorded success-package com.amazon.tv.forcedotaupdater.v2

printf '%s\n' 'ROOT_RESTORE=PASS'
