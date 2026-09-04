#!/usr/bin/env python3

import json
import os
import platform
import sys
import urllib.error
import urllib.request
from pathlib import Path


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))


def read_local_value(env_name: str, filename: str) -> str | None:
    value = os.environ.get(env_name, "").strip()
    if value:
        return value

    try:
        value = (codex_home() / filename).read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return value or None


def project_name(hook_input: object) -> str | None:
    if not isinstance(hook_input, dict):
        return None
    cwd = hook_input.get("cwd")
    if not isinstance(cwd, str) or not cwd.strip():
        return None
    name = Path(cwd).name.strip()
    return name or None


def main() -> int:
    try:
        hook_input = json.loads(sys.stdin.read())
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError):
        hook_input = {}

    token = read_local_value("CODEX_REMOTE_NOTIFY_TOKEN", "notify-token")
    url = read_local_value("CODEX_REMOTE_NOTIFY_URL", "notify-url")
    if not token or not url:
        return 0

    source = platform.node() or os.environ.get("HOSTNAME") or "unknown"
    project = project_name(hook_input)

    payload = {
        "source": source,
        "event": "codex.completed",
        "title": "Codex finished",
        "message": f"project: {project}" if project else "Task completed",
    }

    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            response.read(1)
    except (OSError, urllib.error.URLError, urllib.error.HTTPError, ValueError):
        # Notifications must never block or fail the Codex Stop hook.
        pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
