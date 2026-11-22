#!/bin/sh
# Name the tab containing this pane. Resurrect wrappers launch their command
# directly (no shell), so the zsh title hook never runs for those panes.
export PATH="$HOME/.local/bin:$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
name=$1
pane=${ZELLIJ_PANE_ID#terminal_}
[ -n "$pane" ] || exit 0
tab_id=$(zellij action list-panes -t -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit()
for p in data:
    if not p.get("is_plugin") and str(p.get("id")) == sys.argv[1]:
        print(p.get("tab_id") or "")
        break
' "$pane")
[ -n "$tab_id" ] || exit 0
exec zellij action rename-tab --tab-id "$tab_id" "$name"
