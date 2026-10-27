#!/usr/bin/env python3
# history.py: prints what the widget's popup draws, per limit the points of the current window and a
# forecast from the average pace since the window started:
#   {"weekly_all": {"start": .., "end": .., "since": .., "points": [[t, percent], ..], "at_reset": 82, "runs_out": null}}
# Every window starts at 0, so the first point is (start, 0) and since is the first real history point.
# at_reset is where the limit lands at this pace, runs_out the time it hits 100 % (only if before the reset).
import json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claude_usage as cu

WINDOW = {"session": 5 * 3600}                       # everything else is weekly
MAX_POINTS = 150
MIN_ELAPSED = 0.1                                    # no forecast in the first 10 % of a window


def series(key, lim, hist, now):
    end = lim.get("resets_at")
    if not end or end <= now:
        return None
    start = end - WINDOW.get(key, 7 * 86400)
    pts = [(h["t"], h["p"]) for h in hist if h["k"] == key and start <= h["t"] <= now]
    pts.append((min(now, lim["at"]), lim["percent"]))
    bucket = (end - start) / MAX_POINTS                # keep the highest value per bucket
    thin = {}
    for t, p in sorted(pts):
        b = int((t - start) // bucket)
        if b not in thin or p >= thin[b][1]:
            thin[b] = (t, p)
    since = min(thin.values())[0]                    # before that the graph only knows it started at 0
    out = dict(start=start, end=end, since=round(since), points=[[round(start), 0]] + [[round(t), p] for t, p in thin.values()],
               at_reset=None, runs_out=None)
    elapsed = now - start
    if elapsed >= MIN_ELAPSED * (end - start) and lim["percent"] > 0:
        rate = lim["percent"] / elapsed
        out["at_reset"] = round(lim["percent"] + rate * (end - now))
        if out["at_reset"] >= 100:
            out["runs_out"] = round(now + (100 - lim["percent"]) / rate)
    return out


def main():
    now = time.time()
    st, hist = cu.load(), cu.history()
    res = {}
    for key, lim in st["limits"].items():
        s = series(key, lim, hist, now)
        if s:
            res[key] = s
    print(json.dumps(res))


if __name__ == "__main__":
    main()
