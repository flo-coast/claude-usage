#!/usr/bin/env python3
# poll.py [--force]: fetches the plan limits from api.anthropic.com/api/oauth/usage (the endpoint Claude
# Code's /usage reads) for the per-model limits (Fable) the status line does not have.
# Gentle on purpose, run by a 5-min user timer but only calls the API when
#   - Claude Code was in use in the last 30 min (status line ran or a claude process is running),
#   - the last successful call is >= 15 min old,
#   - no backoff is pending (429/5xx/network -> 15 min doubling up to 4 h, honours Retry-After).
# --force (widget's refresh button) skips the first two checks, never the backoff, and still waits a minute.
# The OAuth token is read from ~/.claude/.credentials.json and only sent to api.anthropic.com. It is never
# renewed here (renewing would rotate the refresh token and could log Claude Code out): when it has
# expired the old values just stay until Claude Code renews it itself.
import json, os, subprocess, sys, time, urllib.error, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import claude_usage as cu

URL = "https://api.anthropic.com/api/oauth/usage"
CREDS = os.path.expanduser("~/.claude/.credentials.json")
MIN_GAP = 15 * 60
FORCE_GAP = 60
ACTIVE_WINDOW = 30 * 60
BACKOFF_MIN, BACKOFF_MAX = 15 * 60, 4 * 3600


def claude_running():
    return subprocess.run(["pgrep", "-x", "claude"], capture_output=True).returncode == 0


def token():
    try:
        o = json.load(open(CREDS))["claudeAiOauth"]
    except (OSError, ValueError, KeyError):
        return None, "no_credentials"
    if o.get("expiresAt", 0) / 1000 < time.time() + 60:
        return None, "token_expired"
    return o.get("accessToken"), None


def fail(st, why, wait=None):
    api = st["api"]
    prev = api.get("backoff_s") or 0
    api["backoff_s"] = wait or min(BACKOFF_MAX, max(BACKOFF_MIN, prev * 2))
    api["backoff_until"] = time.time() + api["backoff_s"]
    api["error"] = why


def main():
    force = "--force" in sys.argv
    now = time.time()
    st = cu.load()
    api = st["api"]
    if now < api.get("backoff_until", 0):
        print(f"backoff until {time.strftime('%H:%M', time.localtime(api['backoff_until']))} ({api.get('error')})")
        return
    if now - api.get("last_try", 0) < FORCE_GAP:
        print("asked less than a minute ago")
        return
    if not force:
        if now - api.get("last_ok", 0) < MIN_GAP:
            print("fresh enough")
            return
        if now - st.get("statusline_at", 0) > ACTIVE_WINDOW and not claude_running():
            print("Claude Code not in use")
            return
    tok, why = token()
    with cu.update() as st:
        st["api"]["last_try"] = now
        if not tok:
            st["api"]["error"] = why                 # no backoff: Claude Code renews the token on its own
            print(why)
            return
        req = urllib.request.Request(URL, headers={"Authorization": "Bearer " + tok,
                                                   "anthropic-beta": "oauth-2025-04-20",
                                                   "User-Agent": "claude-usage-widget/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.load(r)
        except urllib.error.HTTPError as e:
            ra = e.headers.get("Retry-After", "")
            fail(st, f"http_{e.code}", int(ra) if ra.isdigit() else None)
            if e.code == 401:                        # token rejected: wait for Claude Code to renew it
                st["api"]["error"] = "token_rejected"
            print(st["api"]["error"])
            return
        except (OSError, ValueError) as e:
            fail(st, "network" if isinstance(e, OSError) else "parse")
            print(st["api"]["error"], e)
            return
        n = 0
        for lim in data.get("limits") or []:
            kind, pct = lim.get("kind"), lim.get("percent")
            if pct is None:
                continue
            label = None
            if kind == "weekly_scoped":
                model = (((lim.get("scope") or {}).get("model") or {}).get("display_name") or "model").strip()
                kind, label = f"weekly:{model}", f"Week ({model})"
            elif kind not in cu.LABELS:
                label = kind.replace("_", " ").capitalize()
            old = st["limits"].get(kind)
            if old and old["source"] == "statusline" and old["at"] > now - 120:
                continue                             # the status line just delivered a fresher value
            cu.put(st, kind, pct, cu.iso_epoch(lim.get("resets_at")), "api", label)
            n += 1
        st["api"].update(last_ok=now, error=None, backoff_s=0, backoff_until=0)
        print(f"ok, {n} limits")


if __name__ == "__main__":
    main()
