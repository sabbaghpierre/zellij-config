#!/bin/sh
# Install the Zellij config from this repo on macOS or Linux (incl. Void).
# Idempotent: safe to re-run. Backs up anything it replaces.
# Errors out early with a clear message if a requirement is missing.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.sh"
os=$(uname -s)
zcfg="${XDG_CONFIG_HOME:-$HOME/.config}/zellij"
ocfg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
backup() { # backup <path> — only for real files/dirs, never symlinks
  [ -e "$1" ] || return 0
  if [ -L "$1" ]; then
    target=$(readlink "$1")
    case "$target" in "$here"/*|"$here") return 0 ;; esac
    mv "$1" "$1.backup-$(date +%Y%m%d%H%M%S)"
    echo "moved symlink $1 -> $1.backup-*"
    return 0
  fi
  mv "$1" "$1.backup-$(date +%Y%m%d%H%M%S)"
  echo "backed up $1 -> $1.backup-*"
}
link() { # link <source> <dest>
  if [ "$(readlink "$2" 2>/dev/null || true)" = "$1" ]; then return 0; fi
  backup "$2"
  mkdir -p "$(dirname "$2")"
  ln -sfn "$1" "$2"
  echo "linked $2 -> $1"
}
need() { command -v "$1" >/dev/null 2>&1 || fail "missing '$1'"; }
fail() { echo "error: $*" >&2; exit 1; }
note() { echo "note: $*"; }

echo "== checking requirements =="
echo "reference zellij: $ZELLIJ_TESTED (min $ZELLIJ_MIN)"
need zellij
need python3
need sh
command -v node >/dev/null 2>&1 || note "node not found: OpenCode session-title plugin won't run"
command -v zsh  >/dev/null 2>&1 || note "zsh not found: smart tab titles and TUI pins need zsh"
command -v claude   >/dev/null 2>&1 || note "claude CLI not found (agent restore will fall back to shell)"
command -v opencode >/dev/null 2>&1 || note "opencode CLI not found"

ver=$(zellij --version 2>/dev/null | awk '{print $2}')
major=$(printf '%s\n' "${ver:-0}" | cut -d. -f1)
minor=$(printf '%s\n' "${ver:-0}" | cut -d. -f2)
min_major=$(printf '%s\n' "$ZELLIJ_MIN" | cut -d. -f1)
min_minor=$(printf '%s\n' "$ZELLIJ_MIN" | cut -d. -f2)
case $major$minor in
  ''|*[!0-9]*) note "could not parse zellij version '${ver:-unknown}'" ;;
  *)
    if [ "$major" -lt "$min_major" ] || \
       { [ "$major" -eq "$min_major" ] && [ "$minor" -lt "$min_minor" ]; }; then
      fail "zellij ${ver:-unknown} is too old; need >= $ZELLIJ_MIN"
    fi
    ;;
esac

fontslug=$(printf '%s' "$FONT_NAME" | tr -d ' ')
if command -v fc-list >/dev/null 2>&1; then
  fc-list 2>/dev/null | grep -qi "$FONT_NAME" || note "$FONT_NAME not found; tab icons may be boxes"
elif [ "$os" = Darwin ]; then
  ls /Library/Fonts/"$fontslug"* "/Library/Fonts/$FONT_NAME"* \
     "$HOME/Library/Fonts/"$fontslug"*" "$HOME/Library/Fonts/$FONT_NAME"* >/dev/null 2>&1 || \
    note "$FONT_NAME not found; tab icons may be boxes"
fi

if ! zellij setup --check >/dev/null 2>&1; then
  note "existing zellij config did not pass 'setup --check' (will check after install)"
fi

echo "== config =="
mkdir -p "$zcfg"
link "$here/config.kdl" "$zcfg/config.kdl"
for s in "$here"/scripts/*; do
  [ -f "$s" ] || continue
  case $(basename "$s") in icons.tsv) ;; *) chmod +x "$s" ;; esac
  link "$s" "$zcfg/scripts/$(basename "$s")"
done
# Drop links to scripts that were removed from the repo.
for l in "$zcfg"/scripts/*; do
  if [ -L "$l" ] && [ ! -e "$l" ]; then rm -f "$l"; echo "removed stale $l"; fi
done
chmod +x "$here/launcher/zellij-work"

echo "== OpenCode plugin =="
if [ -d "$ocfg" ]; then
  plugin="$ocfg/plugins/zellij-resurrect"
  mkdir -p "$plugin"
  link "$here/opencode-plugin/tui.js" "$plugin/tui.js"
  if [ -f "$ocfg/cli.json" ]; then
    cp "$ocfg/cli.json" "$ocfg/cli.json.backup-$(date +%Y%m%d%H%M%S)"
    python3 - "$ocfg/cli.json" "file://$plugin" <<'PY'
import json, sys
path, uri = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
plugins = data.setdefault("plugins", [])
if not any(p.rstrip("/").endswith("zellij-resurrect") for p in plugins):
    plugins.append(uri)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    echo "registered plugin in $ocfg/cli.json"
  else
    note "$ocfg/cli.json missing; add \"plugins\": [\"file://$plugin\"] manually"
  fi
else
  note "$ocfg missing; OpenCode plugin not installed"
fi

echo "== Claude hooks =="
if [ -f "$HOME/.claude/settings.json" ]; then
  cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup-$(date +%Y%m%d%H%M%S)"
  python3 - "$HOME/.claude/settings.json" "$zcfg/scripts/claude-snapshot.sh" <<'PY'
import json, sys
path, script = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
hooks = data.setdefault("hooks", {})
start = hooks.setdefault("SessionStart", [])
cmd = 'bash "%s"' % script
entry = {"hooks": [{"type": "command", "command": cmd}]}
def has(hay):
    for group in hay:
        for h in group.get("hooks", []):
            if "claude-snapshot.sh" in h.get("command", ""):
                return True
    return False
if not has(start):
    start.append(entry)
# Note: no SessionEnd hook. Clearing the pin on exit also fires on Zellij
# quit, which would delete the pin we need for resurrection. pin-resume.sh
# and the zsh precmd hook drop the pin after a real agent exit instead.
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  echo "installed SessionStart hook in ~/.claude/settings.json"
else
  note "~/.claude/settings.json missing; add the SessionStart hook manually"
fi

echo "== shell hook =="
if command -v zsh >/dev/null 2>&1; then
  zshrc=$HOME/.zshrc
  line="[ -n \"\${ZELLIJ:-}\" ] && [ -f \"$zcfg/scripts/zellij-hooks.zsh\" ] && source \"$zcfg/scripts/zellij-hooks.zsh\""
  touch "$zshrc"
  if ! grep -Fq 'zellij-hooks.zsh' "$zshrc"; then
    cp "$zshrc" "$zshrc.backup-$(date +%Y%m%d%H%M%S)"
    printf '\n# Zellij pane hooks (smart titles, close confirmation, TUI pins)\n%s\n' "$line" >> "$zshrc"
    echo "added zellij hook source to $zshrc"
  fi
fi

echo "== launcher =="
if [ "$os" = Darwin ]; then
  # Retire the old "Zellij Work.app" so there aren't two dock icons.
  oldapp="$HOME/Applications/Zellij Work.app"
  [ -e "$oldapp" ] && backup "$oldapp"
  app="$HOME/Applications/Zellij.app"
  backup "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$here/launcher/Info.plist" "$app/Contents/"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$HOME/.local/bin/zellij-work" > "$app/Contents/MacOS/zellij-work"
  [ -f "$here/launcher/zellij.icns" ] && cp "$here/launcher/zellij.icns" "$app/Contents/Resources/"
  chmod +x "$app/Contents/MacOS/zellij-work"
  echo "installed $app"
fi
mkdir -p "$HOME/.local/bin"
link "$here/launcher/zellij-work" "$HOME/.local/bin/zellij-work"
if [ -d "$HOME/.local/share/applications" ] || [ "$os" != Darwin ]; then
  mkdir -p "$HOME/.local/share/applications"
  # Match the package launcher ID and drop older entries so there is one icon.
  rm -f "$HOME/.local/share/applications/zellij-work.desktop" \
        "$HOME/.local/share/applications/zellij.desktop"
  desktop="$HOME/.local/share/applications/dev.zellij.Zellij.desktop"
  sed "s|__LAUNCHER__|$HOME/.local/bin/zellij-work|" "$here/launcher/zellij.desktop" > "$desktop"
  chmod 644 "$desktop"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  echo "installed $desktop"
fi

echo "== validating =="
for s in "$here"/scripts/*.sh; do sh -n "$s" || fail "syntax error in $s"; done
echo "sh scripts OK"
if command -v zsh >/dev/null 2>&1; then zsh -n "$here/scripts/zellij-hooks.zsh" >/dev/null && echo "zsh hook OK"; fi
if command -v node >/dev/null 2>&1; then node --check "$here/opencode-plugin/tui.js" >/dev/null && echo "node plugin OK"; fi
for j in "$ocfg/cli.json" "$HOME/.claude/settings.json"; do
  [ -f "$j" ] || continue
  if python3 -m json.tool "$j" >/dev/null 2>&1; then echo "$j OK"; else fail "$j invalid"; fi
done
if ZELLIJ_CONFIG_FILE="$zcfg/config.kdl" zellij setup --check >/dev/null 2>&1; then echo "config.kdl OK"; else fail "config validation failed"; fi

echo
echo "done. Launch with: $HOME/.local/bin/zellij-work"
echo "session name: work (override with ZELLIJ_WORK_SESSION)"
echo "tip: press Ctrl g to lock/unlock Zellij when inside nvim so Alt keys reach it"
