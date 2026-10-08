#!/usr/bin/env python3
"""CodeX Switch status-line relay for Claude Code.

Claude Code feeds the status-line command a JSON document on stdin. For claude.ai
Pro/Max accounts it contains `rate_limits.five_hour` / `seven_day` (documented:
https://code.claude.com/docs/en/statusline). This relay saves those windows to
`$CLAUDE_CONFIG_DIR/.cx-usage.json` so `cx usage` can show them, then runs the
original status-line command with the very same stdin and stdout.

    python3 cx_statusline.py -- '<original status-line command>'

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
        path = os.path.join(cfg, ".cx-usage.json")
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, path)
    except Exception:
        pass


def main():
    data = sys.stdin.buffer.read()
    save(data)
    argv = sys.argv[1:]
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv or not argv[0].strip():
        return 0
    return subprocess.run(argv[0], shell=True, input=data).returncode


if __name__ == "__main__":
    sys.exit(main())
