#!/usr/bin/env python3
# statusline.py: Claude Code status line command. Saves rate_limits (session + weekly) from the status
# line input into the widget's state file and prints a short line:
#   Opus 5.5 · ctx 34% · 5h 7% · wk 20% · Fable 16%
# The per-model limits (Fable) come from poll.py, the status line input does not have them.
# Also keeps the context fill of every Claude Code session (st["contexts"][session_id]) for the widget.
import json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claude_usage as cu

try:
    data = json.load(sys.stdin)
except ValueError:
    data = {}

CONTEXT_KEEP = 6 * 3600                   # forget sessions idle this long

rl = data.get("rate_limits") or {}
ctx = (data.get("context_window") or {}).get("used_percentage")
model = (data.get("model") or {}).get("display_name")
with cu.update() as st:                   # without limits (first reply pending) it still notes that Claude Code is in use
    for src, key in (("five_hour", "session"), ("seven_day", "weekly_all")):
        w = rl.get(src)
        if w and w.get("used_percentage") is not None:
            cu.put(st, key, w["used_percentage"], w.get("resets_at"), "statusline")
    now = time.time()
    st["statusline_at"] = now
    contexts = {k: v for k, v in (st.get("contexts") or {}).items() if now - v.get("at", 0) < CONTEXT_KEEP}
    if ctx is not None and data.get("session_id"):
        ws = data.get("workspace") or {}
        cwd = ws.get("project_dir") or ws.get("current_dir") or data.get("cwd") or ""
        contexts[data["session_id"]] = dict(percent=float(ctx), model=model,
                                            project=os.path.basename(cwd.rstrip("/")) or "~", at=now)
    st["contexts"] = contexts

parts = []
if model:
    parts.append(model)
if ctx is not None:
    parts.append(f"ctx {ctx:.0f}%")
short = {"session": "5h", "weekly_all": "wk"}
now = time.time()
for key in st.get("order") or list(st["limits"]):
    lim = st["limits"].get(key)
    if lim:
        parts.append(f"{short.get(key, lim['label'].split('(')[-1].rstrip(')'))} {cu.effective(lim, now):.0f}%")
print(" · ".join(parts))
