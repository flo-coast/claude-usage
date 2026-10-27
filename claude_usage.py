# claude_usage.py: shared state for the Claude usage widget. One JSON file holds the latest value of every
# plan limit (session, weekly, weekly per model) with where it came from and when:
#   statusline  Claude Code's status line input (rate_limits), live on every reply, session + weekly only
#   api         api.anthropic.com/api/oauth/usage, the endpoint /usage reads, also has the per-model limits
# Writers take a lock and replace the file atomically, so the widget never reads half a file.
# Every change of a limit is also appended to history.jsonl (5 weeks kept) for the graphs in the popup.
import fcntl, json, os, tempfile, time
from contextlib import contextmanager
from datetime import datetime

STATE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "claude-usage")
STATE = os.path.join(STATE_DIR, "state.json")
LOCK = os.path.join(STATE_DIR, "state.lock")
HIST_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "claude-usage")
HISTORY = os.path.join(HIST_DIR, "history.jsonl")
HIST_EVERY = 10 * 60                                  # a point at least this often while values come in
HIST_KEEP = 35 * 86400
LABELS = {"session": "Session (5 h)", "weekly_all": "Week (all models)"}
ORDER = ["session", "weekly_all"]                     # per-model limits follow in API order


def empty():
    return dict(limits={}, statusline_at=0, api=dict(last_try=0, last_ok=0, backoff_until=0, error=None))


@contextmanager
def update():
    """with update() as st: ... -> st is written back when the block ends."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LOCK, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        st = load()
        yield st
        st["order"] = ORDER + [k for k in st["limits"] if k not in ORDER]
        record(st)
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".state-")
        with os.fdopen(fd, "w") as f:
            json.dump(st, f, indent=1)
        os.replace(tmp, STATE)


def load():
    try:
        st = json.load(open(STATE))
    except (OSError, ValueError):
        return empty()
    base = empty()
    base.update(st)
    return base


def record(st):
    """Append the limits that changed (or weren't noted for HIST_EVERY) to the history. Called under the lock."""
    now = time.time()
    last = st.setdefault("hist_last", {})
    lines = []
    for k, lim in st["limits"].items():
        prev = last.get(k)
        if lim["at"] < now - 60:                      # not written in this round
            continue
        if prev and prev["p"] == lim["percent"] and prev["r"] == lim["resets_at"] and now - prev["t"] < HIST_EVERY:
            continue
        last[k] = dict(t=round(now), p=lim["percent"], r=lim["resets_at"])
        lines.append(json.dumps(dict(k=k, **last[k]), separators=(",", ":")))
    if not lines:
        return
    os.makedirs(HIST_DIR, exist_ok=True)
    if now - st.get("hist_pruned", 0) > 86400:        # once a day drop what's older than HIST_KEEP
        st["hist_pruned"] = now
        keep = [l for l in history() if l["t"] > now - HIST_KEEP]
        fd, tmp = tempfile.mkstemp(dir=HIST_DIR, prefix=".history-")
        with os.fdopen(fd, "w") as f:
            f.writelines(json.dumps(l, separators=(",", ":")) + "\n" for l in keep)
        os.replace(tmp, HISTORY)
    with open(HISTORY, "a") as f:
        f.write("\n".join(lines) + "\n")


def history():
    try:
        f = open(HISTORY)
    except OSError:
        return []
    out = []
    with f:
        for line in f:
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def put(st, key, percent, resets_at, source, label=None):
    """Store one limit (the newest write wins; poll.py skips values the status line just set)."""
    now = time.time()
    st["limits"][key] = dict(label=label or LABELS.get(key, key), percent=float(percent),
                             resets_at=int(resets_at) if resets_at else None, source=source, at=now)


def iso_epoch(s):
    try:
        return datetime.fromisoformat(s).timestamp()
    except (TypeError, ValueError):
        return None


def effective(lim, now=None):
    """Percent as it is now: a window whose reset time has passed is back at 0."""
    now = now or time.time()
    if lim.get("resets_at") and lim["resets_at"] <= now:
        return 0.0
    return lim["percent"]
