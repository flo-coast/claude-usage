#!/bin/sh
# uninstall.sh: removes the widget, the timer, the status line entry (if it's ours) and the installed scripts.
set -e
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/claude-usage"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

systemctl --user disable --now claude-usage-poll.timer 2>/dev/null || true
rm -f "$UNITS/claude-usage-poll.service" "$UNITS/claude-usage-poll.timer"
systemctl --user daemon-reload
kpackagetool6 -t Plasma/Applet -r org.flocoast.claudeusage 2>/dev/null || true

python3 -I - <<'PY'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
try:
    cfg = json.load(open(path))
except (OSError, ValueError):
    raise SystemExit
if "claude-usage/statusline.py" in (cfg.get("statusLine") or {}).get("command", ""):
    del cfg["statusLine"]
    json.dump(cfg, open(path, "w"), indent=2)
    print("status line removed from", path)
PY

rm -rf "$DEST" "${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage"
echo "Done. Remove the widget from your panel if it's still there."
