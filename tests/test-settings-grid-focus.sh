#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PARSER=$ROOT/scripts/settings-grid-focus.py

focused_network='<hierarchy><node focused="true" clickable="true"><node text="Network" resource-id="com.amazon.tv.launcher:id/title_text" /></node></hierarchy>'
focused_equipment='<hierarchy><node focused="true" clickable="true"><node text="Equipment&#10;Control" resource-id="com.amazon.tv.launcher:id/title_text" /></node></hierarchy>'

[ "$(printf '%s\n' "$focused_network" | python3 "$PARSER")" = Network ]
[ "$(printf '%s\n' "$focused_equipment" | python3 "$PARSER")" = "Equipment
Control" ]
if printf '%s\n' '<hierarchy><node text="Network" /></hierarchy>' | python3 "$PARSER" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: parser accepted a grid without a focused tile' >&2
  exit 1
fi

grep -Fq 'expect_stock_grid_tile "Display & Sounds"' "$ROOT/scripts/mantis-tool.sh"
grep -Fq '[ "$grid_title" = Network ]' "$ROOT/scripts/mantis-tool.sh"

printf '%s\n' 'SETTINGS_GRID_FOCUS=PASS'
