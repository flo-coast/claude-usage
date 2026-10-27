# claude_usage.py: shared state for the Claude usage widget. One JSON file holds the latest value of every
# plan limit (session, weekly, weekly per model) with where it came from and when:
#   statusline  Claude Code's status line input (rate_limits), live on every reply, session + weekly only
#   api         api.anthropic.com/api/oauth/usage, the endpoint /usage reads, also has the per-model limits
# Writers take a lock and replace the file atomically, so the widget never reads half a file.
import fcntl, json, os, tempfile, time
from contextlib import contextmanager
from datetime import datetime

STATE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "claude-usage")
STATE = os.path.join(STATE_DIR, "state.json")
LOCK = os.path.join(STATE_DIR, "state.lock")
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
