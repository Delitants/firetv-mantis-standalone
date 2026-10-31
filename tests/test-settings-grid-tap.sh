#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
parser=$root/scripts/settings-grid-tap.py
grid='<hierarchy><node package="com.amazon.tv.launcher" class="android.widget.LinearLayout" enabled="true" focusable="true" focused="false" clickable="true" bounds="[104,208][445,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node><node package="com.amazon.tv.launcher" class="android.widget.LinearLayout" enabled="true" focusable="true" focused="false" clickable="true" bounds="[104,461][445,725]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Display &amp; Sounds" /></node></hierarchy>'

[ "$(printf '%s\n' "$grid" | python3 "$parser" Network)" = '274 330' ]
[ "$(printf '%s\n' "$grid" | python3 "$parser" 'Display & Sounds')" = '274 593' ]

for invalid in \
  '<hierarchy><node package="com.example" enabled="true" focusable="true" clickable="true" bounds="[104,208][445,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node></hierarchy>' \
  '<hierarchy><node package="com.amazon.tv.launcher" enabled="false" focusable="true" clickable="true" bounds="[104,208][445,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node></hierarchy>' \
  '<hierarchy><node package="com.amazon.tv.launcher" enabled="true" focusable="true" clickable="false" bounds="[104,208][445,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node></hierarchy>' \
  '<hierarchy><node package="com.amazon.tv.launcher" enabled="true" focusable="true" clickable="true" bounds="bad"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node></hierarchy>' \
  '<hierarchy></hierarchy>'
do
  if printf '%s\n' "$invalid" | python3 "$parser" Network >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: unsafe Settings tile was accepted' >&2
    exit 1
  fi
done

duplicate='<hierarchy><node package="com.amazon.tv.launcher" enabled="true" focusable="true" clickable="true" bounds="[104,208][445,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node><node package="com.amazon.tv.launcher" enabled="true" focusable="true" clickable="true" bounds="[453,208][786,453]"><node package="com.amazon.tv.launcher" enabled="true" resource-id="com.amazon.tv.launcher:id/title_text" text="Network" /></node></hierarchy>'
if printf '%s\n' "$duplicate" | python3 "$parser" Network >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: duplicate Settings tiles were accepted' >&2
  exit 1
fi

printf '%s\n' 'SETTINGS_GRID_TAP=PASS'
