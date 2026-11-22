# Sourced from ~/.zshrc only inside a Zellij pane. Ports the old WezTerm/kitty
# behaviour: process-based tab titles, a running-command marker for the
# confirm-on-close binding, and cleanup of resurrect pins after a real exit.
[[ -n ${ZELLIJ:-} && -n ${ZELLIJ_PANE_ID:-} ]] || return 0

autoload -Uz add-zsh-hook

_ZJ_CFG=${XDG_CONFIG_HOME:-$HOME/.config}/zellij
_ZJ_SCRIPTS=$_ZJ_CFG/scripts
_ZJ_SESSION=${ZELLIJ_SESSION_NAME:-default}
_ZJ_STATE=${XDG_STATE_HOME:-$HOME/.local/state}/zellij/hooks/$_ZJ_SESSION
_ZJ_PINS=$_ZJ_CFG/pins/$_ZJ_SESSION

_zj_icon_for() {
  sh "$_ZJ_SCRIPTS/tab-icon.sh" "$1" 2>/dev/null
}
_ZJ_SHELL_LABEL=$(sh "$_ZJ_SCRIPTS/tab-icon.sh" shell 2>/dev/null)

# rename via the shared helper (single implementation of the tab-id lookup).
_zj_rename() {
  sh "$_ZJ_SCRIPTS/set-tab-title.sh" "$1" >/dev/null 2>&1
}

_zj_clean_name() {
  local base=${1:t}
  base=${base%.exe}
  local clean=$base
  if [[ $base =~ [0-9][0-9.]*$ ]]; then
    clean=${base%%-[0-9]*}
    [[ $clean == $base ]] && clean=${base%%[0-9]*}
  fi
  if [[ -z $clean ]]; then
    if [[ $base =~ ^[0-9]+\.[0-9] ]]; then clean=claude; else clean=$base; fi
  fi
  print -r -- ${clean:-shell}
}

_zj_preexec() {
  local cmdline=$1
  local -a words
  words=(${(z)cmdline})
  local cmd=''
  for w in $words; do
    case ${(Q)w} in
      *=*|sudo|time|command|env|nice|nohup|builtin) continue ;;
      *) cmd=${(Q)w}; break ;;
    esac
  done
  [[ -n $cmd ]] || return 0

  local name icon
  name=$(_zj_clean_name "$cmd")
  _zj_rename "$(_zj_icon_for "$name")"

  mkdir -p "$_ZJ_STATE" || return 0
  local busy=$_ZJ_STATE/${ZELLIJ_PANE_ID}.busy
  print -r -- "$$" > "$busy"

  # Restore whatever is running at shutdown. Runs in the background so the
  # command starts at once; if it already finished (precmd removed the busy
  # marker), drop the pin it just wrote. Agents re-pin with a resumable id.
  # Builtins (cd, export, exit…) can't be meaningfully restored; skip them.
  [[ $cmdline == *$'\n'* || $(whence -w -- $cmd) == *:\ (builtin|reserved) ]] && return 0
  {
    sh "$_ZJ_SCRIPTS/pin-resume.sh" zsh -ic "$cmdline"
    if [[ ! -f $busy ]]; then
      rm -f $_ZJ_PINS/${ZELLIJ_PANE_ID}.*(N)
      zellij action set-resurrect-command --pane-id "$ZELLIJ_PANE_ID" --clear
    fi
  } >/dev/null 2>&1 &!
}

# Back at the prompt means the foreground command really exited, so drop any
# pin it set (pin-resume.sh); the pane then restores as a plain shell.
_zj_precmd() {
  _zj_rename "$_ZJ_SHELL_LABEL"
  rm -f "$_ZJ_STATE/${ZELLIJ_PANE_ID}.busy"
  local -a pins=($_ZJ_PINS/${ZELLIJ_PANE_ID}.*(N))
  if (( $#pins )); then
    rm -f $pins
    zellij action set-resurrect-command --pane-id "$ZELLIJ_PANE_ID" --clear >/dev/null 2>&1 &!
  fi
}

add-zsh-hook preexec _zj_preexec
add-zsh-hook precmd _zj_precmd
