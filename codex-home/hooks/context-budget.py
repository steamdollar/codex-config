#!/usr/bin/env python3
"""Inject one-shot Codex context-budget guidance before a user turn."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator


HARD_PERCENT = 60
CHUNK_SIZE = 64 * 1024
AUDIT_OUTPUT_LIMIT = 12 * 1024

TOOL_CALL_TYPES = {"custom_tool_call", "function_call", "tool_call"}
TOOL_OUTPUT_TYPES = {
    "custom_tool_call_output",
    "function_call_output",
    "tool_result",
}
COMPLETION_TYPES = {
    "task_complete",
    "turn_complete",
    "turn_completed",
    "response_completed",
    "agent_turn_complete",
}
TRUNCATION_TEXT = re.compile(
    r"(?:warning:\s*)?truncated(?:\s+output)?|"
    r"output\s+(?:was\s+)?truncated|original\s+token\s+count|"
    r"\[truncated\]",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class TurnAudit:
    tool_calls: int
    total_output_bytes: int
    max_output_bytes: int
    duplicate_command: bool
    explicit_truncation: bool


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


def transcript_events(path: Path) -> list[dict]:
    events: list[dict] = []
    with path.open("rb") as transcript:
        for raw_line in transcript:
            try:
                event = json.loads(raw_line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(event, dict):
                events.append(event)
    return events


def event_payload(event: dict) -> dict | None:
    payload = event.get("payload")
    return payload if isinstance(payload, dict) else None


def payload_type(event: dict) -> str | None:
    payload = event_payload(event)
    event_type = payload.get("type") if payload is not None else None
    return event_type if isinstance(event_type, str) else None


def is_user_event(event: dict) -> bool:
    payload = event_payload(event)
    if payload is None:
        return False
    if event.get("type") == "event_msg" and payload.get("type") == "user_message":
        return True
    return payload.get("type") == "message" and payload.get("role") == "user"


def is_turn_start(event: dict) -> bool:
    return event.get("type") == "event_msg" and payload_type(event) == "task_started"


def is_turn_complete(event: dict) -> bool:
    return event.get("type") == "event_msg" and payload_type(event) in COMPLETION_TYPES


def latest_completed_turn(path: Path) -> list[dict] | None:
    try:
        events = transcript_events(path)
    except OSError:
        return None
    completed_indexes = [
        index for index, event in enumerate(events) if is_turn_complete(event)
    ]
    if not completed_indexes:
        return None
    complete_index = completed_indexes[-1]
    start_indexes = [
        index for index, event in enumerate(events[:complete_index]) if is_turn_start(event)
    ]
    if start_indexes:
        start_index = start_indexes[-1]
    else:
        user_indexes = [
            index for index, event in enumerate(events[:complete_index]) if is_user_event(event)
        ]
        if not user_indexes:
            return None
        start_index = user_indexes[-1]
    turn = events[start_index : complete_index + 1]
    return turn if any(is_user_event(event) for event in turn) else None


def output_text_bytes(value: object) -> int:
    if isinstance(value, str):
        return len(value.encode("utf-8"))
    if not isinstance(value, list):
        return 0
    total = 0
    for item in value:
        if isinstance(item, str):
            total += len(item.encode("utf-8"))
        elif isinstance(item, dict) and isinstance(item.get("text"), str):
            total += len(item["text"].encode("utf-8"))
    return total


def has_truncation_marker(value: object) -> bool:
    if isinstance(value, str):
        return bool(TRUNCATION_TEXT.search(value))
    if isinstance(value, list):
        return any(has_truncation_marker(item) for item in value)
    if isinstance(value, dict):
        for key, nested in value.items():
            if (
                isinstance(key, str)
                and key.lower() in {"truncated", "is_truncated", "output_truncated"}
                and nested is True
            ):
                return True
            if has_truncation_marker(nested):
                return True
    return False


def tool_command(payload: dict) -> str | None:
    command = payload.get("input")
    if isinstance(command, str):
        return command
    command = payload.get("command")
    return command if isinstance(command, str) else None


def turn_audit(path: Path) -> TurnAudit | None:
    turn = latest_completed_turn(path)
    if turn is None:
        return None
    commands: list[str] = []
    total_output_bytes = 0
    max_output_bytes = 0
    explicit_truncation = False
    tool_calls = 0
    for event in turn:
        payload = event_payload(event)
        event_type = payload_type(event)
        if payload is None:
            continue
        if event_type in TOOL_CALL_TYPES:
            tool_calls += 1
            command = tool_command(payload)
            if command is not None:
                commands.append(command)
        elif event_type in TOOL_OUTPUT_TYPES:
            output = payload.get("output")
            output_bytes = output_text_bytes(output)
            total_output_bytes += output_bytes
            max_output_bytes = max(max_output_bytes, output_bytes)
            explicit_truncation = explicit_truncation or has_truncation_marker(payload)
    return TurnAudit(
        tool_calls=tool_calls,
        total_output_bytes=total_output_bytes,
        max_output_bytes=max_output_bytes,
        duplicate_command=len(commands) != len(set(commands)),
        explicit_truncation=explicit_truncation,
    )


def audit_message(audit: TurnAudit) -> str | None:
    violations: list[str] = []
    if audit.tool_calls >= 12:
        violations.append(f"tool calls={audit.tool_calls}")
    if audit.total_output_bytes > AUDIT_OUTPUT_LIMIT:
        violations.append(f"total output={audit.total_output_bytes:,} bytes")
    if audit.max_output_bytes > AUDIT_OUTPUT_LIMIT:
        violations.append(f"max output={audit.max_output_bytes:,} bytes")
    if audit.duplicate_command:
        violations.append("exact duplicate command")
    if audit.explicit_truncation:
        violations.append("explicit truncation marker")
    return f"[Turn audit] {'; '.join(violations)}." if violations else None


def threshold(context_window: int) -> int | None:
    hard_override = os.environ.get("CODEX_CONTEXT_BUDGET_HARD_TOKENS")
    if hard_override is not None:
        try:
            hard = int(hard_override)
        except ValueError:
            return None
    else:
        hard = (context_window * HARD_PERCENT + 99) // 100
    if hard <= 0:
        return None
    return hard


def state_root() -> Path:
    override = os.environ.get("CODEX_CONTEXT_BUDGET_STATE_DIR")
    if override:
        return Path(override)
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        return Path(runtime_dir) / "codex-context-budget"
    uid = getattr(os, "getuid", lambda: "user")()
    return Path(tempfile.gettempdir()) / f"codex-context-budget-{uid}"


def claim_warning(session_id: str) -> bool:
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
    marker = root / f"{session_key}.hard"
    try:
        descriptor = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    except OSError:
        return False
    else:
        os.close(descriptor)

    return True


def warning_message(input_tokens: int, context_window: int) -> str:
    percentage = input_tokens / context_window * 100
    action = (
        "In your next response, explicitly recommend starting a new tab at the "
        "next clean boundary and offer a PLAN/ADR/task handoff. Do not interrupt an "
        "unsafe or incomplete atomic action."
    )
    return (
        f"[Context budget] {input_tokens:,} / {context_window:,} input tokens "
        f"({percentage:.1f}%). This turn is not blocked. {action}"
    )


def main() -> int:
    try:
        hook_input = json.load(sys.stdin)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return 0
    if (
        not isinstance(hook_input, dict)
        or hook_input.get("hook_event_name") != "UserPromptSubmit"
    ):
        return 0

    session_id = hook_input.get("session_id")
    transcript_path = hook_input.get("transcript_path")
    if not isinstance(session_id, str) or not session_id:
        return 0
    if not isinstance(transcript_path, str) or not transcript_path:
        return 0

    transcript = Path(transcript_path)
    messages: list[str] = []
    usage = latest_usage(transcript)
    if usage is not None:
        input_tokens, context_window = usage
        configured_threshold = threshold(context_window)
        if configured_threshold is not None and input_tokens >= configured_threshold:
            if claim_warning(session_id):
                messages.append(warning_message(input_tokens, context_window))

    audit = turn_audit(transcript)
    if audit is not None:
        audit_warning = audit_message(audit)
        if audit_warning is not None:
            messages.append(audit_warning)
    if not messages:
        return 0

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "\n".join(messages),
        },
    }
    print(json.dumps(output, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
