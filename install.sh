#!/bin/sh
# install.sh: copies the scripts to ~/.local/share/claude-usage, sets up the Claude Code status line,
# starts the poll timer and installs the Plasma widget. Run it again to update.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/claude-usage"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$DEST" "$UNITS"
install -m 644 "$SRC/claude_usage.py" "$DEST/"
install -m 755 "$SRC/poll.py" "$SRC/statusline.py" "$DEST/"
for u in claude-usage-poll.service claude-usage-poll.timer; do
    rm -f "$UNITS/$u"                                  # may be an old symlink into the source folder
    sed "s|@DEST@|$DEST|" "$SRC/systemd/$u" > "$UNITS/$u"
done
systemctl --user daemon-reload
systemctl --user enable --now claude-usage-poll.timer

# Status line: set it when there is none or it's ours already, never replace someone else's
python3 -I - "$DEST/statusline.py" <<'PY'
import json, os, shutil, sys
path = os.path.expanduser("~/.claude/settings.json")
cmd = "/usr/bin/python3 -I " + sys.argv[1]
try:
    cfg = json.load(open(path))
except FileNotFoundError:
    cfg = {}
old = (cfg.get("statusLine") or {}).get("command", "")
if old == cmd:
    print("status line already set")
elif old and "claude-usage/statusline.py" not in old:
    print("You already have a status line, left it alone. To use this one set statusLine.command in")
    print(f"{path} to\n  {cmd}")
else:
    if os.path.exists(path):
        shutil.copy2(path, path + ".before-claude-usage")
    cfg["statusLine"] = {"type": "command", "command": cmd}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(cfg, open(path, "w"), indent=2)
    print("status line set in", path)
PY

if command -v kpackagetool6 >/dev/null; then
    kpackagetool6 -t Plasma/Applet -u "$SRC/plasmoid" 2>/dev/null || kpackagetool6 -t Plasma/Applet -i "$SRC/plasmoid"
    echo "Widget installed. Right-click your panel, Add Widgets, search for Claude Usage."
else
    echo "kpackagetool6 not found, skipped the Plasma widget. The status line works without it."
fi
