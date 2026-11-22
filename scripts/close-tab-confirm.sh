#!/bin/sh
# Bound to Super w: ask before closing when a command is still running in the
# tab the key was pressed in. Run supplies ZELLIJ_PANE_ID for that pane.
export PATH="$HOME/.local/bin:$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
session=${ZELLIJ_SESSION_NAME:-default}
pane=${ZELLIJ_PANE_ID:-${ZELLIJ_ORIGIN_PANE_ID:-}}
pane=${pane#terminal_}
state="${XDG_STATE_HOME:-$HOME/.local/state}/zellij/hooks/$session"

# Resolve the origin tab and its pane ids from Zellij's own state so only that
# tab's markers count, and so the prompt closes the same tab even after a switch.
info=$(zellij action list-panes -t -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit()
origin = sys.argv[1]
tid = None
for p in data:
    if not p.get("is_plugin") and str(p.get("id")) == origin:
        tid = p.get("tab_id")
        break
if tid is None:
    sys.exit()
print(tid)
for p in data:
    if p.get("tab_id") == tid and not p.get("is_plugin"):
        print(p.get("id"))
' "$pane" 2>/dev/null)

tab_id=$(printf '%s\n' "$info" | sed -n 1p)
busy=0
if [ -n "$tab_id" ]; then
  for p in $(printf '%s\n' "$info" | tail -n +2); do
    f="$state/$p.busy"
    [ -f "$f" ] || continue
    pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then busy=1; else rm -f "$f"; fi
  done
else
  # Cannot identify the origin tab: fail closed, never close a guess.
  echo 'close-tab: could not resolve origin tab; nothing closed' >&2
  exit 0
fi

if [ "$busy" -eq 1 ]; then
  zellij prompt confirm "A command is still running. Close this tab?" \
    --yes "Close tab" --no "Cancel" --title "Confirm close" --at-center || exit 0
fi
if [ -n "$tab_id" ]; then
  exec zellij action close-tab --tab-id "$tab_id"
fi
exec zellij action close-tab
