#!/usr/bin/env python3
"""Zorua status-line relay for Claude Code.

Claude Code feeds the status-line command a JSON document on stdin. For claude.ai
Pro/Max accounts it contains `rate_limits.five_hour` / `seven_day` (documented:
https://code.claude.com/docs/en/statusline). This relay saves those windows to
`$CLAUDE_CONFIG_DIR/.zorua-usage.json` so `zorua usage` can show them, then runs the
original status-line command with the very same stdin and stdout.

    python3 zorua_statusline.py -- '<original status-line command>'

When the account had no status line, it prints a minimal one (model, context, 5h/7d).

It reads no credentials and talks to no network. Failures to write the cache
never affect the status line.
"""
import json
import os
import subprocess
import sys
import time


def save(data):
    try:
        rl = json.loads(data).get("rate_limits") or {}
        out = {}
        for k in ("five_hour", "seven_day"):
            w = rl.get(k)
            if isinstance(w, dict) and w.get("used_percentage") is not None:
                out[k] = {"used_percentage": w["used_percentage"], "resets_at": w.get("resets_at")}
        if not out:
            return
        out["updated_at"] = int(time.time())
        cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
        path = os.path.join(cfg, ".zorua-usage.json")
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, path)
    except Exception:
        pass


def default_line(data):
    """Minimal status line for accounts that had none: model, context, 5h / 7d."""
    try:
        d = json.loads(data)
    except Exception:
        return ""
    parts = []
    name = (d.get("model") or {}).get("display_name")
    if name:
        parts.append(str(name))
    ctx = (d.get("context_window") or {}).get("used_percentage")
    if ctx is not None:
        parts.append("ctx %d%%" % round(float(ctx)))
    rl = d.get("rate_limits") or {}
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        pct = (rl.get(key) or {}).get("used_percentage")
        if pct is not None:
            parts.append("%s %d%%" % (label, round(float(pct))))
    return " · ".join(parts)


def main():
    data = sys.stdin.buffer.read()
    save(data)
    argv = sys.argv[1:]
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv or not argv[0].strip():
        print(default_line(data))
        return 0
    return subprocess.run(argv[0], shell=True, input=data).returncode


if __name__ == "__main__":
    sys.exit(main())
