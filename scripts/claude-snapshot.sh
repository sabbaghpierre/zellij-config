#!/bin/sh
# Claude Code SessionStart hook: restore this pane into the same Claude session.
export PATH="$HOME/.local/bin:$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0

json=$(cat)
vals=$(printf '%s\n' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("session_id","")); print(d.get("cwd",""))' 2>/dev/null) || exit 0
sid=$(printf '%s\n' "$vals" | sed -n 1p)
cwd=$(printf '%s\n' "$vals" | sed -n 2p)
[ -n "$sid" ] || exit 0

# Skip headless `claude -p` children: they inherit the pane env but are not its session.
flags=""
p=$PPID
i=0
while [ $i -lt 4 ] && [ -n "$p" ] && [ "$p" != "1" ]; do
  args=$(ps -o args= -p "$p" 2>/dev/null)
  case "$args" in
    *claude*)
      case "$args" in
        *" -p "*|*--print*) sid="" ;;
        *--dangerously-skip-permissions*) flags="--dangerously-skip-permissions" ;;
      esac
      break ;;
  esac
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
[ -n "$sid" ] || exit 0

[ -z "$cwd" ] || cd "$cwd" || exit 0
zcfg=${XDG_CONFIG_HOME:-$HOME/.config}/zellij
exec sh "$zcfg/scripts/pin-resume.sh" claude --resume "$sid" $flags
