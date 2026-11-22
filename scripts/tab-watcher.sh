#!/bin/sh
# Background watcher: names tabs that still show a default "Tab #N" label — or
# a label this watcher previously set — from the command running in them.
# Covers panes with no zsh hook (direct `zellij run`, app TUIs) without fighting
# the hook, resurrect wrappers, the OpenCode plugin, or manual renames.
# Started by the launcher; exits on its own if the session disappears.
set -u
export PATH="$HOME/.local/bin:$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
script_dir=$(cd "$(dirname "$0")" && pwd)
session=${ZELLIJ_WORK_SESSION:-work}
interval=${ZELLIJ_WATCHER_INTERVAL:-2}
state="${XDG_STATE_HOME:-$HOME/.local/state}/zellij/tab-watcher/$session"
lockdir="$state/lock.d"
mkdir -p "$state"
rm -f "$state/lock"  # old non-atomic lock, no longer used

# Atomic lock: mkdir succeeds for exactly one watcher. Recover from a stale
# lock left by a crash by checking the recorded PID.
if ! mkdir "$lockdir" 2>/dev/null; then
  pid=$(cat "$lockdir/pid" 2>/dev/null || true)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0  # already running for this session
  fi
  rm -rf "$lockdir"
  mkdir "$lockdir" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$lockdir/pid"
trap 'rm -rf "$lockdir"' EXIT INT TERM

fails=0
started=0
while :; do
  data=$(zellij -s "$session" action list-panes -t -j 2>/dev/null) || {
    # Before the first success the session may still be starting; don't give up.
    if [ "$started" -eq 1 ]; then
      fails=$((fails + 1)); [ "$fails" -ge 5 ] && exit 0
    fi
    sleep "$interval"; continue;
  }
  started=1
  fails=0
  printf '%s\n' "$data" | python3 -c '
import json, sys, subprocess
try:
    panes = json.load(sys.stdin)
except Exception:
    sys.exit()

STATE = sys.argv[3]
# {tab_id: label} for tabs this watcher named.
ours = {}
try:
    for line in open(STATE).read().splitlines():
        tid, _, label = line.partition("\t")
        ours[int(tid)] = label
except Exception:
    pass

def label_for(p):
    cmd = ""
    running = (p.get("command_state") or {}).get("running") or {}
    c = running.get("command") or {}
    if isinstance(c, dict):
        cmd = c.get("text") or ""
    if not cmd:
        cmd = p.get("terminal_command") or ""
    cmd = cmd.strip()
    if not cmd:
        return None
    first = cmd.split()[0]
    if first == "env":
        first = cmd.split()[1] if len(cmd.split()) > 1 else first
    try:
        return subprocess.check_output(
            ["sh", sys.argv[1], first],
            stderr=subprocess.DEVNULL, text=True
        ).strip() or None
    except Exception:
        return None

seen = {}
names = {}
for p in panes:
    if p.get("is_plugin"):
        continue
    tid = p.get("tab_id")
    if tid is None:
        continue
    name = (p.get("tab_name") or "").strip()
    names[tid] = name
    # Touch only default names or labels we set ourselves. Never override the
    # shell hook, wrapper, OpenCode plugin, or the user.
    if not (name.startswith("Tab #") or ours.get(tid) == name):
        continue
    label = label_for(p)
    if not label:
        continue
    cur = seen.get(tid)
    if cur is None or p.get("is_focused"):
        seen[tid] = label

for tid, label in seen.items():
    if label == names[tid]:
        continue
    try:
        subprocess.run(
            ["zellij", "-s", sys.argv[2], "action", "rename-tab-by-id",
             str(tid), label],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    except Exception:
        pass

# Keep only tabs that still exist so the state file cannot grow forever.
new = {t: l for t, l in ours.items() if t in names}
new.update(seen)
if new != ours:
    with open(STATE, "w") as f:
        f.write("".join("%d\t%s\n" % kv for kv in sorted(new.items())))
' "$script_dir/tab-icon.sh" "$session" "$state/ours"
  sleep "$interval"
done
