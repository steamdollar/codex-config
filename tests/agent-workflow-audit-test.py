#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "codex-home/skills/agent-workflow-audit/scripts/extract_trace.py"
SPEC = importlib.util.spec_from_file_location("extract_trace", SCRIPT)
assert SPEC and SPEC.loader
extract_trace = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(extract_trace)


THREAD_ID = "11111111-1111-7111-8111-111111111111"
TURN_1 = "22222222-2222-7222-8222-222222222222"
TURN_2 = "33333333-3333-7333-8333-333333333333"
CHILD_ID = "44444444-4444-7444-8444-444444444444"


def record(timestamp: str, record_type: str, payload: dict) -> dict:
    return {"timestamp": timestamp, "type": record_type, "payload": payload}


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(item) + "\n" for item in records), encoding="utf-8")


class ExtractTraceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "sessions"
        root_file = self.root / "2026/08/10" / f"rollout-2026-08-10T00-00-00-{THREAD_ID}.jsonl"
        common_meta = {"internal_chat_message_metadata_passthrough": {"turn_id": TURN_2}}
        records = [
            record("2026-08-10T00:00:00Z", "event_msg", {"type": "task_started", "turn_id": TURN_1, "started_at": 1000}),
            record("2026-08-10T00:00:05Z", "event_msg", {"type": "user_message", "message": "first"}),
            record("2026-08-10T00:00:10Z", "event_msg", {"type": "task_complete", "turn_id": TURN_1, "started_at": 1000, "completed_at": 1010, "duration_ms": 10000}),
            record("2026-08-10T00:01:00Z", "event_msg", {"type": "task_started", "turn_id": TURN_2, "started_at": 2000}),
            record("1970-01-01T00:00:00Z", "event_msg", {"type": "user_message", "message": "audit this work"}),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {
                    "type": "message",
                    "role": "assistant",
                    "phase": "commentary",
                    "content": [{"type": "output_text", "text": "Large local read, so I will call reader."}],
                    **common_meta,
                },
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {
                    "type": "function_call",
                    "name": "spawn_agent",
                    "namespace": "agents",
                    "arguments": json.dumps({"agent_type": "reader", "task_name": "trace_reader", "message": "encrypted"}),
                    "call_id": "spawn-1",
                    **common_meta,
                },
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {"type": "function_call_output", "call_id": "spawn-1", "output": "{}", **common_meta},
            ),
            record(
                "1970-01-01T00:00:00Z",
                "event_msg",
                {
                    "type": "sub_agent_activity",
                    "event_id": "spawn-1",
                    "occurred_at_ms": 2001000,
                    "agent_thread_id": CHILD_ID,
                    "agent_path": "/root/trace_reader",
                    "kind": "started",
                },
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {
                    "type": "custom_tool_call",
                    "name": "exec",
                    "input": 'const r = await tools.exec_command({cmd: "bash tests/check.sh"}); text(r.output);',
                    "call_id": "tool-1",
                    **common_meta,
                },
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {"type": "custom_tool_call_output", "call_id": "tool-1", "output": "ok", **common_meta},
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {
                    "type": "custom_tool_call",
                    "name": "exec",
                    "input": 'const r = await tools.exec_command({cmd: "bash tests/check.sh"}); text(r.output);',
                    "call_id": "tool-2",
                    **common_meta,
                },
            ),
            record(
                "1970-01-01T00:00:00Z",
                "response_item",
                {"type": "custom_tool_call_output", "call_id": "tool-2", "output": "token=supersecretvalue", **common_meta},
            ),
            record(
                "1970-01-01T00:00:00Z",
                "event_msg",
                {
                    "type": "sub_agent_activity",
                    "event_id": "spawn-1",
                    "occurred_at_ms": 2006000,
                    "agent_thread_id": CHILD_ID,
                    "agent_path": "/root/trace_reader",
                    "kind": "interacted",
                },
            ),
            record("2026-08-10T00:02:00Z", "event_msg", {"type": "task_complete", "turn_id": TURN_2, "started_at": 2000, "completed_at": 2020, "duration_ms": 20000}),
        ]
        write_jsonl(root_file, records)

        child_file = self.root / "2026/08/10" / f"rollout-2026-08-10T00-01-01-{CHILD_ID}.jsonl"
        child_turn = "55555555-5555-7555-8555-555555555555"
        write_jsonl(
            child_file,
            [
                record("2026-08-10T00:01:01Z", "event_msg", {"type": "task_started", "turn_id": child_turn, "started_at": 2001}),
                record(
                    "2026-08-10T00:01:06Z",
                    "event_msg",
                    {
                        "type": "task_complete",
                        "turn_id": child_turn,
                        "started_at": 2001,
                        "completed_at": 2006,
                        "duration_ms": 5000,
                        "last_agent_message": "Read files and found token=supersecretvalue in a fixture.",
                    },
                ),
            ],
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def args(self, *extra: str):
        return extract_trace.parse_args(
            ["--thread-id", THREAD_ID, "--sessions-root", str(self.root), *extra]
        )

    def test_latest_completed_extracts_agent_and_signals(self) -> None:
        trace = extract_trace.build_trace(self.args("--latest-completed"))
        self.assertEqual([TURN_2], [turn["turn_id"] for turn in trace["turns"]])
        turn = trace["turns"][0]
        self.assertEqual(20000, turn["duration_ms"])
        self.assertEqual(1, turn["metrics"]["subagent_count"])
        self.assertEqual(5000, turn["subagents"][0]["duration_ms"])
        self.assertEqual("reader", turn["subagents"][0]["role"])
        self.assertEqual(1, turn["subagents"][0]["interaction_activity_count"])
        self.assertIn("[REDACTED]", turn["subagents"][0]["result_summary"])
        self.assertEqual(2, turn["signals"]["repeated_tool_inputs"][0]["count"])
        self.assertEqual(["bash check.sh"], turn["tools"][1]["command_labels"])
        self.assertEqual("partial", turn["time_quality"])

    def test_all_turns_keeps_completed_order(self) -> None:
        trace = extract_trace.build_trace(self.args("--all-turns"))
        self.assertEqual([TURN_1, TURN_2], [turn["turn_id"] for turn in trace["turns"]])

    def test_invalid_thread_id_is_rejected(self) -> None:
        with self.assertRaises(extract_trace.TraceError):
            extract_trace.locate_session(self.root, "not-an-id")


if __name__ == "__main__":
    unittest.main()
