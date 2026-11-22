#!/bin/sh
# Restore this pane with a specific command after a Zellij restart. Only for
# apps whose state lives in an id that the command line doesn't show (agent
# sessions). Zellij already restores any other command, its args and cwd.
#   pin-resume.sh <cmd> [args...]   called from the app's own startup hook
#   pin-resume.sh --run <pinfile>   what Zellij runs on restore
# The pin is dropped when the command really exits (here, or by the zsh precmd
# hook), so a pane you quit comes back as a plain shell.
export PATH="$HOME/.local/bin:$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
zcfg=${XDG_CONFIG_HOME:-$HOME/.config}/zellij
scripts=$zcfg/scripts
session=${ZELLIJ_SESSION_NAME:-default}
pins=$zcfg/pins/$session

if [ "${1:-}" = --run ]; then
  pinfile=$2
  set --
  if [ -f "$pinfile" ]; then
    while IFS= read -r arg; do set -- "$@" "$arg"; done < "$pinfile"
    rm -f "$pinfile"  # the app pins itself again on startup
  fi
  if [ "$#" -gt 0 ]; then
    name=$1
    [ "${2:-}" = -ic ] && name=${3%% *}  # shell-wrapped command line
    sh "$scripts/set-tab-title.sh" "$(sh "$scripts/tab-icon.sh" "$name")"
    busy=${XDG_STATE_HOME:-$HOME/.local/state}/zellij/hooks/$session/${ZELLIJ_PANE_ID:-none}.busy
    mkdir -p "${busy%/*}" && printf '%s\n' "$$" > "$busy"
    "$@"
    rm -f "$busy" "$pins/${ZELLIJ_PANE_ID:-none}".*
    zellij action set-resurrect-command --pane-id "$ZELLIJ_PANE_ID" --clear >/dev/null 2>&1
  fi
  exec "$SHELL" -l
fi

[ "$#" -gt 0 ] && [ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0
mkdir -p "$pins" || exit 0
rm -f "$pins/$ZELLIJ_PANE_ID".*
pinfile=$(mktemp "$pins/$ZELLIJ_PANE_ID.XXXXXX") || exit 0
printf '%s\n' "$@" > "$pinfile"
exec zellij action set-resurrect-command --pane-id "$ZELLIJ_PANE_ID" --cwd "$PWD" -- \
  "$scripts/pin-resume.sh" --run "$pinfile"
