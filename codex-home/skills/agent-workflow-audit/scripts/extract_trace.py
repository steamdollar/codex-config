#!/usr/bin/env python3
"""Extract a privacy-bounded workflow trace from Codex session JSONL."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
SECRET_PATTERNS = (
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}"), "Bearer [REDACTED]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED_AWS_KEY]"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"), "[REDACTED_API_KEY]"),
    (
        re.compile(
            r"(?i)\b(password|passwd|token|secret|api[_-]?key)\b\s*[:=]\s*([^\s,;]{4,})"
        ),
        r"\1=[REDACTED]",
    ),
    (
        re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"),
        "[REDACTED_JWT]",
    ),
)


class TraceError(RuntimeError):
    """Raised for a user-actionable trace extraction failure."""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract Primary/tool/subagent timing from a Codex task trace."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--thread-id", help="Codex thread/task ID")
    source.add_argument("--session-file", type=Path, help="Exact rollout JSONL file")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument(
        "--latest-completed",
        action="store_true",
        help="Extract the most recent completed turn (default)",
    )
    selection.add_argument("--turn-id", help="Extract one exact turn ID")
    selection.add_argument(
        "--all-turns", action="store_true", help="Extract every completed turn"
    )
    parser.add_argument(
        "--sessions-root",
        type=Path,
        help="Override the Codex sessions directory",
    )
    parser.add_argument("--output", type=Path, help="Write JSON to this file")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON")
    parser.add_argument(
        "--max-text-chars",
        type=int,
        default=3000,
        help="Maximum characters retained for one summary/message",
    )
    return parser.parse_args(argv)


def codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".codex"


def iso_to_ms(value: Any) -> int | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def seconds_to_ms(value: Any) -> int | None:
    if isinstance(value, (int, float)):
        return int(value * 1000)
    return None


def redact_text(value: Any, limit: int) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    if len(text) > limit:
        return text[: max(0, limit - 16)].rstrip() + " …[truncated]"
    return text


def load_jsonl(path: Path) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    malformed = 0
    with path.open(encoding="utf-8") as handle:
        active_turn: str | None = None
        for line_number, raw in enumerate(handle, 1):
            try:
                record = json.loads(raw)
            except json.JSONDecodeError:
                malformed += 1
                continue
            if not isinstance(record, dict):
                malformed += 1
                continue
            payload = record.get("payload")
            if not isinstance(payload, dict):
                payload = {}
            payload_type = payload.get("type")
            explicit_turn = nested_turn_id(payload)
            if record.get("type") == "event_msg" and payload_type == "task_started":
                active_turn = str(payload.get("turn_id") or "") or None
            record["_line"] = line_number
            record["_order"] = len(records)
            record["_turn_id"] = explicit_turn or active_turn
            records.append(record)
            if record.get("type") == "event_msg" and payload_type == "task_complete":
                active_turn = None
    return records, malformed


def nested_turn_id(payload: dict[str, Any]) -> str | None:
    metadata = payload.get("internal_chat_message_metadata_passthrough")
    if isinstance(metadata, dict) and metadata.get("turn_id"):
        return str(metadata["turn_id"])
    if payload.get("type") in {"task_started", "task_complete"} and payload.get("turn_id"):
        return str(payload["turn_id"])
    return None


def infer_thread_id(path: Path, records: Iterable[dict[str, Any]]) -> str | None:
    match = re.search(r"-([0-9a-f-]{36})\.jsonl$", path.name, re.IGNORECASE)
    if match and UUID_RE.match(match.group(1)):
        return match.group(1)
    for record in records:
        if record.get("type") != "session_meta":
            continue
        payload = record.get("payload", {})
        for key in ("id", "thread_id", "session_id"):
            value = payload.get(key) if isinstance(payload, dict) else None
            if isinstance(value, str) and UUID_RE.match(value):
                return value
    return None


def locate_session(sessions_root: Path, thread_id: str) -> Path:
    if not UUID_RE.match(thread_id):
        raise TraceError(f"invalid thread ID: {thread_id}")
    candidates = sorted(sessions_root.rglob(f"*-{thread_id}.jsonl"))
    if not candidates:
        raise TraceError(f"session trace not found for thread {thread_id}")
    # The exact thread ID is part of the rollout filename, so avoid reading a
    # potentially large trace once for discovery and again for extraction.
    return max(candidates, key=lambda item: item.stat().st_mtime)


def collect_turns(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    starts: dict[str, dict[str, Any]] = {}
    completes: dict[str, dict[str, Any]] = {}
    for record in records:
        if record.get("type") != "event_msg":
            continue
        payload = record.get("payload", {})
        if not isinstance(payload, dict):
            continue
        turn_id = payload.get("turn_id")
        if not isinstance(turn_id, str):
            continue
        if payload.get("type") == "task_started":
            starts[turn_id] = payload
        elif payload.get("type") == "task_complete":
            completes[turn_id] = payload
    turns: list[dict[str, Any]] = []
    for turn_id, complete in completes.items():
        start = starts.get(turn_id, {})
        started_ms = seconds_to_ms(complete.get("started_at")) or seconds_to_ms(
            start.get("started_at")
        )
        completed_ms = seconds_to_ms(complete.get("completed_at"))
        duration_ms = complete.get("duration_ms")
        if not isinstance(duration_ms, int) and started_ms is not None and completed_ms is not None:
            duration_ms = max(0, completed_ms - started_ms)
        turns.append(
            {
                "turn_id": turn_id,
                "started_at_ms": started_ms,
                "completed_at_ms": completed_ms,
                "duration_ms": duration_ms,
                "time_to_first_token_ms": complete.get("time_to_first_token_ms"),
                "last_agent_message": complete.get("last_agent_message"),
            }
        )
    return sorted(turns, key=lambda item: item.get("completed_at_ms") or 0)


def select_turns(turns: list[dict[str, Any]], args: argparse.Namespace) -> list[dict[str, Any]]:
    if not turns:
        raise TraceError("no completed turns found")
    if args.turn_id:
        selected = [turn for turn in turns if turn["turn_id"] == args.turn_id]
        if not selected:
            raise TraceError(f"completed turn not found: {args.turn_id}")
        return selected
    if args.all_turns:
        return turns
    return [turns[-1]]


def event_time_ms(record: dict[str, Any], turn: dict[str, Any] | None = None) -> int | None:
    payload = record.get("payload", {})
    if not isinstance(payload, dict):
        payload = {}
    if payload.get("type") == "sub_agent_activity" and isinstance(
        payload.get("occurred_at_ms"), (int, float)
    ):
        candidate = int(payload["occurred_at_ms"])
    elif payload.get("type") == "task_started":
        candidate = seconds_to_ms(payload.get("started_at"))
    elif payload.get("type") == "task_complete":
        candidate = seconds_to_ms(payload.get("completed_at"))
    else:
        candidate = iso_to_ms(record.get("timestamp"))
    if candidate is None or turn is None:
        return candidate
    start = turn.get("started_at_ms")
    end = turn.get("completed_at_ms")
    if isinstance(start, int) and isinstance(end, int) and not (start - 1000 <= candidate <= end + 1000):
        return None
    return candidate


def content_text(payload: dict[str, Any]) -> str:
    content = payload.get("content")
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if isinstance(item, dict) and isinstance(item.get("text"), str):
            parts.append(item["text"])
    return "\n".join(parts)


def normalize_summary(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    result: list[str] = []
    for item in value:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict) and isinstance(item.get("text"), str):
            result.append(item["text"])
    return result


def output_payload_size(payload: dict[str, Any]) -> int:
    output = payload.get("output")
    return len(json.dumps(output, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def parse_json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str):
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def nested_tool_names(source: str) -> list[str]:
    names = re.findall(r"\btools\.([A-Za-z0-9_]+)\s*\(", source)
    return list(dict.fromkeys(names))


def extract_command(source: str) -> str | None:
    match = re.search(r"\bcmd\s*:\s*(\"(?:\\.|[^\"\\])*\")", source, re.DOTALL)
    if not match:
        return None
    try:
        value = json.loads(match.group(1))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, str) else None


def safe_command_labels(command: str | None) -> list[str]:
    if not command:
        return []
    labels: list[str] = []
    for line in command.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        segment = re.split(r"\s*(?:&&|\|\||;)\s*", stripped, maxsplit=1)[0]
        try:
            tokens = shlex.split(segment)
        except ValueError:
            continue
        if not tokens:
            continue
        executable = Path(tokens[0]).name
        label = executable
        if executable == "git" and len(tokens) > 1 and not tokens[1].startswith("-"):
            label = f"git {tokens[1]}"
        elif executable in {"bash", "zsh", "sh"} and len(tokens) > 1:
            label = f"{executable} {Path(tokens[1]).name}"
        elif executable.startswith("python") and len(tokens) > 1:
            if tokens[1] == "-m" and len(tokens) > 2:
                label = f"{executable} -m {tokens[2]}"
            elif not tokens[1].startswith("-"):
                label = f"{executable} {Path(tokens[1]).name}"
        elif executable in {"npm", "pnpm", "yarn"} and len(tokens) > 1:
            label = f"{executable} {tokens[1]}"
            if tokens[1] in {"run", "test"} and len(tokens) > 2 and not tokens[2].startswith("-"):
                label += f" {tokens[2]}"
        if label not in labels:
            labels.append(label)
        if len(labels) == 3:
            break
    return labels


def fingerprint(value: str) -> str:
    normalized = " ".join(value.split())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]


def interval_union_ms(intervals: Iterable[tuple[int | None, int | None]]) -> int:
    clean = sorted(
        (int(start), int(end))
        for start, end in intervals
        if isinstance(start, int) and isinstance(end, int) and end >= start
    )
    if not clean:
        return 0
    total = 0
    current_start, current_end = clean[0]
    for start, end in clean[1:]:
        if start <= current_end:
            current_end = max(current_end, end)
        else:
            total += current_end - current_start
            current_start, current_end = start, end
    return total + current_end - current_start


def max_concurrency(intervals: Iterable[tuple[int | None, int | None]]) -> int:
    points: list[tuple[int, int]] = []
    for start, end in intervals:
        if not isinstance(start, int) or not isinstance(end, int) or end < start:
            continue
        points.append((start, 1))
        points.append((end, -1))
    active = peak = 0
    for _, delta in sorted(points, key=lambda item: (item[0], item[1])):
        active += delta
        peak = max(peak, active)
    return peak


def child_trace_summary(
    sessions_root: Path, agent_thread_id: str | None, max_chars: int
) -> dict[str, Any]:
    if not agent_thread_id or not UUID_RE.match(agent_thread_id):
        return {"status": "missing", "time_quality": "unknown"}
    try:
        path = locate_session(sessions_root, agent_thread_id)
        records, malformed = load_jsonl(path)
    except (OSError, TraceError):
        return {"status": "missing", "time_quality": "unknown"}
    turns = collect_turns(records)
    completed = turns[-1] if turns else None
    if completed:
        return {
            "status": "completed",
            "time_quality": "exact",
            "started_at_ms": completed.get("started_at_ms"),
            "ended_at_ms": completed.get("completed_at_ms"),
            "duration_ms": completed.get("duration_ms"),
            "result_summary": redact_text(completed.get("last_agent_message") or "", max_chars),
            "malformed_records": malformed,
        }
    last_message = ""
    for record in records:
        payload = record.get("payload", {})
        if (
            record.get("type") == "response_item"
            and isinstance(payload, dict)
            and payload.get("type") == "message"
            and payload.get("role") == "assistant"
        ):
            last_message = content_text(payload)
    return {
        "status": "incomplete",
        "time_quality": "unknown",
        "result_summary": redact_text(last_message, max_chars),
        "malformed_records": malformed,
    }


def extract_turn(
    records: list[dict[str, Any]],
    turn: dict[str, Any],
    sessions_root: Path,
    max_chars: int,
) -> dict[str, Any]:
    turn_id = turn["turn_id"]
    scoped = [record for record in records if record.get("_turn_id") == turn_id]
    primary_messages: list[dict[str, Any]] = []
    user_messages: list[dict[str, Any]] = []
    reasoning: list[dict[str, Any]] = []
    calls: list[dict[str, Any]] = []
    outputs: dict[str, dict[str, Any]] = {}
    activity_by_event: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for record in scoped:
        payload = record.get("payload", {})
        if not isinstance(payload, dict):
            continue
        payload_type = payload.get("type")
        if record.get("type") == "response_item" and payload_type == "message":
            role = payload.get("role")
            text = content_text(payload)
            if role == "assistant" and text:
                message_time = event_time_ms(record, turn)
                primary_messages.append(
                    {
                        "order": record["_order"],
                        "at_ms": message_time,
                        "time_quality": "exact" if message_time is not None else "unknown",
                        "phase": payload.get("phase") or "unknown",
                        "text": redact_text(text, max_chars),
                    }
                )
            elif role == "user" and text and "<recommended_plugins>" not in text:
                user_messages.append(
                    {
                        "order": record["_order"],
                        "text": redact_text(text, max_chars),
                    }
                )
        elif record.get("type") == "event_msg" and payload_type == "user_message":
            text = payload.get("message")
            if isinstance(text, str) and text.strip():
                user_messages.append(
                    {"order": record["_order"], "text": redact_text(text, max_chars)}
                )
        elif record.get("type") == "response_item" and payload_type == "reasoning":
            summaries = normalize_summary(payload.get("summary"))
            if summaries:
                reasoning.append(
                    {
                        "order": record["_order"],
                        "at_ms": event_time_ms(record, turn),
                        "summaries": [redact_text(item, 300) for item in summaries],
                    }
                )
        elif record.get("type") == "response_item" and payload_type in {
            "custom_tool_call",
            "function_call",
        }:
            raw_input = payload.get("input") if payload_type == "custom_tool_call" else payload.get("arguments")
            source = raw_input if isinstance(raw_input, str) else json.dumps(raw_input, sort_keys=True)
            nested = nested_tool_names(source)
            command = extract_command(source)
            call_id = str(payload.get("call_id") or payload.get("id") or "")
            calls.append(
                {
                    "call_id": call_id,
                    "order": record["_order"],
                    "started_at_ms": event_time_ms(record, turn),
                    "namespace": payload.get("namespace"),
                    "name": payload.get("name") or "unknown",
                    "label": "+".join(nested) if nested else payload.get("name") or "unknown",
                    "command_labels": safe_command_labels(command),
                    "input_fingerprint": fingerprint(source),
                    "_arguments": parse_json_object(raw_input),
                }
            )
        elif record.get("type") == "response_item" and payload_type in {
            "custom_tool_call_output",
            "function_call_output",
        }:
            call_id = str(payload.get("call_id") or "")
            outputs[call_id] = {
                "at_ms": event_time_ms(record, turn),
                "size_bytes": output_payload_size(payload),
                "truncated": "truncat" in json.dumps(payload.get("output"), ensure_ascii=False).lower(),
                "status": parse_json_object(payload.get("output")),
            }
        elif record.get("type") == "event_msg" and payload_type == "sub_agent_activity":
            event_id = str(payload.get("event_id") or "")
            if event_id:
                activity_by_event[event_id].append(
                    {
                        "order": record["_order"],
                        "at_ms": event_time_ms(record, turn),
                        "kind": payload.get("kind"),
                        "agent_thread_id": payload.get("agent_thread_id"),
                        "agent_path": payload.get("agent_path"),
                    }
                )

    # De-duplicate user messages emitted in both response_item and event_msg forms.
    deduped_user: list[dict[str, Any]] = []
    seen_user: set[str] = set()
    for message in sorted(user_messages, key=lambda item: item["order"]):
        key = " ".join(message["text"].split())
        if key and key not in seen_user:
            seen_user.add(key)
            deduped_user.append(message)

    tools: list[dict[str, Any]] = []
    for call in calls:
        output = outputs.get(call["call_id"], {})
        ended_at = output.get("at_ms")
        started_at = call.get("started_at_ms")
        duration = (
            ended_at - started_at
            if isinstance(started_at, int) and isinstance(ended_at, int) and ended_at >= started_at
            else None
        )
        status = output.get("status") if isinstance(output.get("status"), dict) else {}
        tool = {key: value for key, value in call.items() if key not in {"_arguments"}}
        tool.update(
            {
                "ended_at_ms": ended_at,
                "duration_ms": duration,
                "time_quality": "exact" if duration is not None else "unknown",
                "output_size_bytes": output.get("size_bytes", 0),
                "output_truncated": bool(output.get("truncated")),
            }
        )
        if "timed_out" in status:
            tool["timed_out"] = bool(status["timed_out"])
        tools.append(tool)

    subagents: list[dict[str, Any]] = []
    for call in calls:
        if call.get("name") != "spawn_agent":
            continue
        activities = sorted(activity_by_event.get(call["call_id"], []), key=lambda item: item["order"])
        started_activity = next((item for item in activities if item.get("kind") == "started"), None)
        agent_thread_id = (
            started_activity.get("agent_thread_id") if started_activity else None
        )
        child = child_trace_summary(sessions_root, agent_thread_id, max_chars)
        started_at = (
            started_activity.get("at_ms") if started_activity else call.get("started_at_ms")
        )
        ended_at = child.get("ended_at_ms")
        time_quality = child.get("time_quality", "unknown")
        if not isinstance(ended_at, int) and activities:
            known_activity_times = [item["at_ms"] for item in activities if isinstance(item.get("at_ms"), int)]
            ended_at = max(known_activity_times) if known_activity_times else None
            time_quality = "activity-window" if ended_at is not None else "unknown"
        duration = (
            ended_at - started_at
            if isinstance(started_at, int) and isinstance(ended_at, int) and ended_at >= started_at
            else child.get("duration_ms")
        )
        reason_messages = [
            message
            for message in primary_messages
            if message["order"] < call["order"]
        ][-2:]
        arguments = call.get("_arguments", {})
        agent_path = started_activity.get("agent_path") if started_activity else None
        subagents.append(
            {
                "event_id": call["call_id"],
                "role": arguments.get("agent_type") or "unknown",
                "task_name": arguments.get("task_name")
                or (Path(agent_path).name if isinstance(agent_path, str) else "unknown"),
                "agent_path": agent_path,
                "agent_thread_id": agent_thread_id,
                "started_at_ms": started_at,
                "ended_at_ms": ended_at,
                "duration_ms": duration,
                "time_quality": time_quality,
                "status": child.get("status", "unknown"),
                "interaction_activity_count": sum(
                    1 for item in activities if item.get("kind") == "interacted"
                ),
                "reason_evidence": [message["text"] for message in reason_messages],
                "result_summary": child.get("result_summary", ""),
            }
        )

    tool_intervals = [
        (tool.get("started_at_ms"), tool.get("ended_at_ms")) for tool in tools
    ]
    wait_tools = [
        tool
        for tool in tools
        if tool.get("name") in {"wait_agent", "wait_threads", "wait"}
        or "wait" in str(tool.get("label", "")).lower()
    ]
    wait_intervals = [
        (tool.get("started_at_ms"), tool.get("ended_at_ms")) for tool in wait_tools
    ]
    subagent_intervals = [
        (agent.get("started_at_ms"), agent.get("ended_at_ms")) for agent in subagents
    ]
    observed_any = interval_union_ms(tool_intervals + subagent_intervals)
    turn_duration = turn.get("duration_ms") if isinstance(turn.get("duration_ms"), int) else None

    repeat_counter = Counter(
        tool["input_fingerprint"]
        for tool in tools
        if tool.get("name") not in {"spawn_agent", "list_agents", "wait_agent"}
    )
    repeated = []
    for fingerprint_value, count in repeat_counter.most_common():
        if count < 2:
            continue
        example = next(tool for tool in tools if tool["input_fingerprint"] == fingerprint_value)
        repeated.append(
            {
                "input_fingerprint": fingerprint_value,
                "count": count,
                "label": example.get("label"),
                "command_labels": example.get("command_labels", []),
            }
        )

    late_spawns = []
    if isinstance(turn.get("started_at_ms"), int) and isinstance(turn_duration, int) and turn_duration > 0:
        for agent in subagents:
            started_at = agent.get("started_at_ms")
            if isinstance(started_at, int):
                ratio = (started_at - turn["started_at_ms"]) / turn_duration
                if ratio >= 0.6:
                    late_spawns.append(
                        {"task_name": agent["task_name"], "turn_progress_ratio": round(ratio, 3)}
                    )

    longest_spans = []
    for tool in tools:
        if isinstance(tool.get("duration_ms"), int):
            longest_spans.append(
                {
                    "kind": "tool",
                    "name": tool.get("label"),
                    "duration_ms": tool["duration_ms"],
                }
            )
    for agent in subagents:
        if isinstance(agent.get("duration_ms"), int):
            longest_spans.append(
                {
                    "kind": "subagent",
                    "name": agent.get("task_name"),
                    "role": agent.get("role"),
                    "duration_ms": agent["duration_ms"],
                }
            )
    longest_spans.sort(key=lambda item: item["duration_ms"], reverse=True)

    unknown_tool_times = sum(1 for tool in tools if tool.get("time_quality") != "exact")
    unknown_agent_times = sum(1 for agent in subagents if agent.get("time_quality") != "exact")
    time_quality = "exact"
    if unknown_tool_times or unknown_agent_times:
        time_quality = "partial"

    result = {
        **{key: value for key, value in turn.items() if key != "last_agent_message"},
        "time_quality": time_quality,
        "requests": deduped_user,
        "primary_messages": sorted(primary_messages, key=lambda item: item["order"]),
        "reasoning_summaries": sorted(reasoning, key=lambda item: item["order"]),
        "tools": sorted(tools, key=lambda item: item["order"]),
        "subagents": sorted(
            subagents,
            key=lambda item: item.get("started_at_ms")
            if isinstance(item.get("started_at_ms"), int)
            else 2**63,
        ),
        "metrics": {
            "primary_message_count": len(primary_messages),
            "reasoning_summary_count": sum(len(item["summaries"]) for item in reasoning),
            "tool_call_count": len(tools),
            "subagent_count": len(subagents),
            "observed_tool_wall_ms": interval_union_ms(tool_intervals),
            "observed_wait_wall_ms": interval_union_ms(wait_intervals),
            "subagent_wall_coverage_ms": interval_union_ms(subagent_intervals),
            "subagent_elapsed_sum_ms": sum(
                agent["duration_ms"]
                for agent in subagents
                if isinstance(agent.get("duration_ms"), int)
            ),
            "max_subagent_concurrency": max_concurrency(subagent_intervals),
            "observed_any_activity_wall_ms": observed_any,
            "unobserved_wall_ms": max(0, turn_duration - observed_any)
            if isinstance(turn_duration, int)
            else None,
            "tool_output_bytes": sum(tool.get("output_size_bytes", 0) for tool in tools),
            "truncated_tool_outputs": sum(1 for tool in tools if tool.get("output_truncated")),
            "unknown_tool_timestamps": unknown_tool_times,
            "unknown_subagent_timestamps": unknown_agent_times,
        },
        "signals": {
            "longest_observed_spans": longest_spans[:10],
            "repeated_tool_inputs": repeated[:10],
            "late_subagent_spawns": late_spawns,
            "wait_call_count": len(wait_tools),
            "timed_out_wait_count": sum(1 for tool in wait_tools if tool.get("timed_out")),
            "subagent_interaction_activity_count": sum(
                agent.get("interaction_activity_count", 0) for agent in subagents
            ),
        },
    }
    return result


def build_trace(args: argparse.Namespace) -> dict[str, Any]:
    sessions_root = (args.sessions_root or codex_home() / "sessions").expanduser().resolve()
    if args.session_file:
        session_file = args.session_file.expanduser().resolve()
        if not session_file.is_file():
            raise TraceError(f"session file not found: {session_file}")
    else:
        session_file = locate_session(sessions_root, args.thread_id)
    records, malformed = load_jsonl(session_file)
    thread_id = args.thread_id or infer_thread_id(session_file, records)
    turns = select_turns(collect_turns(records), args)
    extracted = [
        extract_turn(records, turn, sessions_root, args.max_text_chars) for turn in turns
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "source": {
            "thread_id": thread_id,
            "session_file": str(session_file),
            "sessions_root": str(sessions_root),
            "selection": "all-turns"
            if args.all_turns
            else (f"turn:{args.turn_id}" if args.turn_id else "latest-completed"),
            "malformed_records": malformed,
            "privacy": "raw tool outputs and encrypted agent prompts omitted; summaries redacted",
        },
        "turns": extracted,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        trace = build_trace(args)
    except (OSError, TraceError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    rendered = json.dumps(
        trace,
        ensure_ascii=False,
        indent=2 if args.pretty else None,
        separators=None if args.pretty else (",", ":"),
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
