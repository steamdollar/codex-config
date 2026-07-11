#!/usr/bin/env python3
"""Emit one-shot, non-blocking Codex context-budget warnings."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Iterator


SOFT_PERCENT = 45
HARD_PERCENT = 60
CHUNK_SIZE = 64 * 1024


def reverse_lines(path: Path) -> Iterator[bytes]:
    with path.open("rb") as transcript:
        transcript.seek(0, os.SEEK_END)
        position = transcript.tell()
        remainder = b""
        while position > 0:
            size = min(CHUNK_SIZE, position)
            position -= size
            transcript.seek(position)
            block = transcript.read(size) + remainder
            lines = block.split(b"\n")
            remainder = lines[0]
            for line in reversed(lines[1:]):
                if line:
                    yield line
        if remainder:
            yield remainder


def latest_usage(path: Path) -> tuple[int, int] | None:
    try:
        for raw_line in reverse_lines(path):
            try:
                event = json.loads(raw_line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if event.get("type") != "event_msg":
                continue
            payload = event.get("payload")
            if not isinstance(payload, dict) or payload.get("type") != "token_count":
                continue
            info = payload.get("info")
            if not isinstance(info, dict):
                continue
            last_usage = info.get("last_token_usage")
            if not isinstance(last_usage, dict):
                continue
            input_tokens = last_usage.get("input_tokens")
            context_window = info.get("model_context_window")
            if (
                isinstance(input_tokens, int)
                and not isinstance(input_tokens, bool)
                and input_tokens >= 0
                and isinstance(context_window, int)
                and not isinstance(context_window, bool)
                and context_window > 0
            ):
                return input_tokens, context_window
    except OSError:
        return None
    return None


def thresholds(context_window: int) -> tuple[int, int] | None:
    soft_override = os.environ.get("CODEX_CONTEXT_BUDGET_SOFT_TOKENS")
    hard_override = os.environ.get("CODEX_CONTEXT_BUDGET_HARD_TOKENS")
    if soft_override is not None or hard_override is not None:
        if soft_override is None or hard_override is None:
            return None
        try:
            soft = int(soft_override)
            hard = int(hard_override)
        except ValueError:
            return None
    else:
        soft = (context_window * SOFT_PERCENT + 99) // 100
        hard = (context_window * HARD_PERCENT + 99) // 100
    if not 0 < soft < hard:
        return None
    return soft, hard


def state_root() -> Path:
    override = os.environ.get("CODEX_CONTEXT_BUDGET_STATE_DIR")
    if override:
        return Path(override)
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        return Path(runtime_dir) / "codex-context-budget"
    uid = getattr(os, "getuid", lambda: "user")()
    return Path(tempfile.gettempdir()) / f"codex-context-budget-{uid}"


def claim_warning(session_id: str, level: str, consume_soft: bool = False) -> bool:
    root = state_root()
    try:
        root.mkdir(mode=0o700, parents=True, exist_ok=False)
    except FileExistsError:
        pass
    except OSError:
        return False
    try:
        root_stat = root.lstat()
    except OSError:
        return False
    if not stat.S_ISDIR(root_stat.st_mode) or stat.S_IMODE(root_stat.st_mode) != 0o700:
        return False
    getuid = getattr(os, "getuid", None)
    if getuid is not None and root_stat.st_uid != getuid():
        return False

    session_key = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    if level == "soft" and (root / f"{session_key}.hard").exists():
        return False
    marker = root / f"{session_key}.{level}"
    try:
        descriptor = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    except OSError:
        return False
    else:
        os.close(descriptor)

    if consume_soft:
        soft_marker = root / f"{session_key}.soft"
        try:
            descriptor = os.open(
                soft_marker,
                os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                0o600,
            )
        except (FileExistsError, OSError):
            pass
        else:
            os.close(descriptor)
    return True


def warning_message(level: str, input_tokens: int, context_window: int) -> str:
    percentage = input_tokens / context_window * 100
    action = (
        "Finish the current atomic step and prepare a PLAN/ADR/task handoff."
        if level == "soft"
        else "Start a new tab at the next clean boundary using a PLAN/ADR/task handoff."
    )
    return (
        f"[Context budget {level}] {input_tokens:,} / {context_window:,} input tokens "
        f"({percentage:.1f}%). This turn is not blocked. {action}"
    )


def main() -> int:
    try:
        hook_input = json.load(sys.stdin)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return 0
    if not isinstance(hook_input, dict) or hook_input.get("hook_event_name") != "Stop":
        return 0

    session_id = hook_input.get("session_id")
    transcript_path = hook_input.get("transcript_path")
    if not isinstance(session_id, str) or not session_id:
        return 0
    if not isinstance(transcript_path, str) or not transcript_path:
        return 0

    usage = latest_usage(Path(transcript_path))
    if usage is None:
        return 0
    input_tokens, context_window = usage
    configured_thresholds = thresholds(context_window)
    if configured_thresholds is None:
        return 0
    soft, hard = configured_thresholds

    if input_tokens >= hard:
        level = "hard"
        if not claim_warning(session_id, level, consume_soft=True):
            return 0
    elif input_tokens >= soft:
        level = "soft"
        if not claim_warning(session_id, level):
            return 0
    else:
        return 0

    output = {
        "continue": True,
        "systemMessage": warning_message(level, input_tokens, context_window),
    }
    print(json.dumps(output, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
