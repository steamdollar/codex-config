#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import runpy
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "codex-home" / "hooks" / "context-budget.py"


def token_event(input_tokens: int, context_window: int, total_tokens: int = 9_999_999) -> dict:
    return {
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {"input_tokens": total_tokens},
                "last_token_usage": {"input_tokens": input_tokens},
                "model_context_window": context_window,
            },
        },
    }


def event_message(role: str) -> dict:
    return {
        "type": "response_item",
        "payload": {"type": "message", "role": role, "content": []},
    }


def event_marker(marker: str) -> dict:
    return {"type": "event_msg", "payload": {"type": marker}}


def tool_call(command: str, *, name: str = "exec") -> dict:
    return {
        "type": "response_item",
        "payload": {
            "type": "custom_tool_call",
            "status": "completed",
            "name": name,
            "call_id": command,
            "input": command,
        },
    }


def tool_output(output: object) -> dict:
    return {
        "type": "response_item",
        "payload": {
            "type": "custom_tool_call_output",
            "call_id": "call",
            "output": output,
        },
    }


class ContextBudgetHookTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.transcript = self.root / "session.jsonl"
        self.state = self.root / "state"

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_events(self, *events: object) -> None:
        lines = [event if isinstance(event, str) else json.dumps(event) for event in events]
        self.transcript.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def run_hook(
        self,
        session_id: str = "session-1",
        *,
        hook_input: dict | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        payload = (
            hook_input
            if hook_input is not None
            else {
                "hook_event_name": "UserPromptSubmit",
                "session_id": session_id,
                "transcript_path": str(self.transcript),
            }
        )
        process_env = os.environ.copy()
        process_env.pop("CODEX_CONTEXT_BUDGET_HARD_TOKENS", None)
        process_env["CODEX_CONTEXT_BUDGET_STATE_DIR"] = str(self.state)
        process_env.update(env or {})
        return subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            env=process_env,
            check=False,
        )

    def assert_silent(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def additional_context(self, result: subprocess.CompletedProcess[str]) -> str:
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(set(output), {"hookSpecificOutput"})
        hook_output = output["hookSpecificOutput"]
        self.assertEqual(
            set(hook_output),
            {"hookEventName", "additionalContext"},
        )
        self.assertEqual(hook_output["hookEventName"], "UserPromptSubmit")
        return hook_output["additionalContext"]

    def test_below_threshold_ignores_cumulative_total(self) -> None:
        self.write_events(token_event(599, 1000))
        self.assert_silent(self.run_hook())

    def test_threshold_warns_once(self) -> None:
        self.write_events(token_event(600, 1000))
        warning = self.run_hook()
        self.assertIn("[Context budget]", self.additional_context(warning))
        self.assert_silent(self.run_hook())

    def test_absolute_override_uses_exact_boundaries(self) -> None:
        override = {"CODEX_CONTEXT_BUDGET_HARD_TOKENS": "200"}
        self.write_events(token_event(199, 1000))
        self.assert_silent(self.run_hook("absolute-below", env=override))
        self.write_events(token_event(200, 1000))
        result = self.run_hook("absolute-threshold", env=override)
        self.assertIn("200 / 1,000", self.additional_context(result))

    def test_newest_valid_token_event_wins(self) -> None:
        self.write_events(
            token_event(900, 1000),
            "not-json",
            ["valid-json-non-object"],
            token_event(100, 1000),
        )
        self.assert_silent(self.run_hook())

    def test_non_object_after_valid_token_event_is_ignored(self) -> None:
        self.write_events(token_event(900, 1000), ["valid-json-non-object"])
        context = self.additional_context(self.run_hook("non-object-token-event"))
        self.assertIn("[Context budget]", context)

    def test_missing_or_malformed_input_fails_open(self) -> None:
        self.write_events(token_event(900, 1000))
        cases = [
            {},
            {"hook_event_name": "UserPromptSubmit", "session_id": "x", "transcript_path": None},
            {"hook_event_name": "Stop", "session_id": "x", "transcript_path": str(self.transcript)},
            {"hook_event_name": "PostToolUse", "session_id": "x", "transcript_path": str(self.transcript)},
        ]
        for index, hook_input in enumerate(cases):
            with self.subTest(index=index):
                self.assert_silent(self.run_hook(hook_input=hook_input))

    def test_missing_or_empty_transcript_fails_open(self) -> None:
        missing = self.root / "missing.jsonl"
        self.assert_silent(
            self.run_hook(
                hook_input={
                    "hook_event_name": "UserPromptSubmit",
                    "session_id": "missing-transcript",
                    "transcript_path": str(missing),
                }
            )
        )
        self.transcript.write_text("", encoding="utf-8")
        self.assert_silent(self.run_hook("empty-transcript"))

    def test_invalid_override_fails_open(self) -> None:
        self.write_events(token_event(900, 1000))
        self.assert_silent(
            self.run_hook(
                env={"CODEX_CONTEXT_BUDGET_HARD_TOKENS": "invalid"},
            )
        )

    def test_unsafe_existing_state_directory_fails_open_without_chmod(self) -> None:
        self.state.mkdir(mode=0o755)
        self.state.chmod(0o755)
        self.write_events(token_event(900, 1000))
        self.assert_silent(self.run_hook("unsafe-state"))
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)

    def test_clean_completed_turn_has_no_audit_warning(self) -> None:
        self.write_events(
            token_event(100, 1000),
            event_marker("task_started"),
            event_message("user"),
            tool_call("printf clean"),
            tool_output("ok"),
            event_marker("task_complete"),
        )
        self.assert_silent(self.run_hook("clean-turn"))

    def test_latest_completed_turn_isolated_from_active_newer_turn(self) -> None:
        self.write_events(
            event_marker("task_started"),
            event_message("user"),
            tool_call("completed command"),
            tool_call("completed command"),
            event_marker("task_complete"),
            event_marker("task_started"),
            event_message("user"),
            *(tool_call(f"active command {index}") for index in range(12)),
        )
        audit = self.additional_context(self.run_hook("active-newer-turn"))
        self.assertIn("exact duplicate command", audit)
        self.assertNotIn("tool calls=", audit)

    def test_latest_completed_turn_stops_reverse_scan_at_task_started(self) -> None:
        hook = runpy.run_path(str(HOOK), run_name="context_budget_hook_test")
        completed = event_marker("task_complete")
        user = event_message("user")
        started = event_marker("task_started")

        def guarded_reverse_lines(path: Path):
            yield json.dumps(completed).encode()
            yield json.dumps(user).encode()
            yield json.dumps(started).encode()
            raise AssertionError("reverse scan consumed older history")

        with patch.dict(
            hook["latest_completed_turn"].__globals__,
            {"reverse_lines": guarded_reverse_lines},
        ):
            turn = hook["latest_completed_turn"](self.transcript)
        self.assertEqual(turn, [started, user, completed])

    def test_modern_turn_keeps_mid_turn_user_messages(self) -> None:
        self.write_events(
            event_marker("task_started"),
            event_message("user"),
            tool_call("same command"),
            event_message("user"),
            tool_call("same command"),
            event_marker("task_complete"),
        )
        audit = self.additional_context(self.run_hook("mid-turn-user"))
        self.assertIn("[Turn audit diagnostic]", audit)
        self.assertIn("exact duplicate command", audit)

    def test_legacy_turn_without_task_started_uses_latest_user_boundary(self) -> None:
        self.write_events(
            event_message("user"),
            tool_call("legacy command"),
            tool_call("legacy command"),
            event_marker("task_complete"),
        )
        audit = self.additional_context(self.run_hook("legacy-turn"))
        self.assertIn("exact duplicate command", audit)

    def test_violating_completed_turn_reports_each_audit_trigger(self) -> None:
        events: list[dict] = [
            token_event(100, 1000),
            event_marker("task_started"),
            event_message("user"),
        ]
        events.extend(tool_call("cat same.txt") for _ in range(12))
        events.append(tool_output("x" * (12 * 1024 + 1)))
        events.append(tool_output("Warning: truncated output"))
        events.append(event_marker("task_complete"))
        self.write_events(*events)
        audit = self.additional_context(self.run_hook("violating-turn"))
        self.assertIn("[Turn audit diagnostic]", audit)
        self.assertIn("tool calls=12", audit)
        self.assertIn("total output=12,314 bytes", audit)
        self.assertIn("max output=12,289 bytes", audit)
        self.assertNotIn("without reader spawn", audit)
        self.assertIn("exact duplicate command", audit)
        self.assertIn("explicit truncation marker", audit)

    def test_malformed_completed_turn_fails_open(self) -> None:
        self.write_events(
            "not-json",
            event_marker("task_started"),
            event_message("user"),
            {"type": "response_item", "payload": {"type": "custom_tool_call"}},
            {"type": "response_item", "payload": {"type": "custom_tool_call_output", "output": {}}},
            event_marker("task_complete"),
        )
        self.assert_silent(self.run_hook("malformed-turn"))

    def test_audit_is_injected_alongside_context_warning(self) -> None:
        self.write_events(
            token_event(600, 1000),
            event_marker("task_started"),
            event_message("user"),
            tool_call("cat repeated.txt"),
            tool_call("cat repeated.txt"),
            event_marker("task_complete"),
        )
        context = self.additional_context(self.run_hook("context-and-audit"))
        self.assertIn("[Context budget]", context)
        self.assertIn("[Turn audit diagnostic]", context)


if __name__ == "__main__":
    unittest.main()
