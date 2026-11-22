import { execFile } from "node:child_process";

const ZCFG = `${process.env.XDG_CONFIG_HOME || `${process.env.HOME}/.config`}/zellij`;
const PIN = `${ZCFG}/scripts/pin-resume.sh`;
const TITLE = `${ZCFG}/scripts/set-tab-title.sh`;
const MAX_TITLE = 24;

// Restore each OpenCode pane into the root session currently open in its TUI.
export default {
  id: "zellij-resurrect.tui",
  setup(ctx) {
    if (!process.env.ZELLIJ_PANE_ID) return;

    let pinnedID = null;
    let pinnedTitle = null;

    const pin = (id) => {
      if (!id || id === pinnedID) return;
      pinnedID = id;
      execFile(
        "sh",
        [PIN, "opencode", "--session", id],
        { cwd: ctx.location?.directory || process.cwd() },
        (err) => { if (err) console.error("[zellij-resurrect]", err.message); }
      );
    };

    const activeRoot = () => {
      const id = ctx.ui?.router?.current?.()?.sessionID;
      if (!id) return null;
      const info = ctx.data.session.get(id);
      if (info?.parentID) return null;
      return { id, title: info?.title };
    };

    const sync = () => {
      const root = activeRoot();
      pin(root?.id);
      const title = (root?.title || '').replace(/[\r\n\t]/g, ' ').trim();
      const label = `OC  ${title ? (title.length > MAX_TITLE ? `${title.slice(0, MAX_TITLE - 1)}…` : title) : 'opencode'}`;
      if (label === pinnedTitle) return;
      pinnedTitle = label;
      execFile('sh', [TITLE, label], (err) => { if (err) console.error('[zellij-resurrect]', err.message); });
    };

    const unlisten = ctx.data.listen(sync);
    sync();

    return () => unlisten();
  },
};
