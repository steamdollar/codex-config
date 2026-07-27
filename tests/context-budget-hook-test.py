#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


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


class ContextBudgetHookTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.transcript = self.root / "session.jsonl"
        self.state = self.root / "state"

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_events(self, *events: dict | str) -> None:
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
        process_env.pop("CODEX_CONTEXT_BUDGET_SOFT_TOKENS", None)
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
        self.write_events(token_event(449, 1000))
        self.assert_silent(self.run_hook())

    def test_soft_then_hard_each_warn_once(self) -> None:
        self.write_events(token_event(450, 1000))
        soft = self.run_hook()
        self.assertIn("[Context budget soft]", self.additional_context(soft))
        self.assert_silent(self.run_hook())

        self.write_events(token_event(600, 1000))
        hard = self.run_hook()
        self.assertIn("[Context budget hard]", self.additional_context(hard))
        self.assert_silent(self.run_hook())

    def test_first_hard_crossing_consumes_soft(self) -> None:
        self.write_events(token_event(700, 1000))
        hard = self.run_hook("hard-first")
        self.assertIn("[Context budget hard]", self.additional_context(hard))

        self.write_events(token_event(500, 1000))
        self.assert_silent(self.run_hook("hard-first"))

    def test_absolute_override_uses_exact_boundaries(self) -> None:
        override = {
            "CODEX_CONTEXT_BUDGET_SOFT_TOKENS": "150",
            "CODEX_CONTEXT_BUDGET_HARD_TOKENS": "200",
        }
        self.write_events(token_event(149, 1000))
        self.assert_silent(self.run_hook("absolute-below", env=override))
        self.write_events(token_event(150, 1000))
        result = self.run_hook("absolute-soft", env=override)
        self.assertIn("150 / 1,000", self.additional_context(result))

    def test_newest_valid_token_event_wins(self) -> None:
        self.write_events(
            token_event(900, 1000),
            "not-json",
            token_event(100, 1000),
        )
        self.assert_silent(self.run_hook())

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

    def test_invalid_partial_override_fails_open(self) -> None:
        self.write_events(token_event(900, 1000))
        self.assert_silent(
            self.run_hook(
                env={"CODEX_CONTEXT_BUDGET_SOFT_TOKENS": "150"},
            )
        )

    def test_unsafe_existing_state_directory_fails_open_without_chmod(self) -> None:
        self.state.mkdir(mode=0o755)
        self.state.chmod(0o755)
        self.write_events(token_event(900, 1000))
        self.assert_silent(self.run_hook("unsafe-state"))
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o755)


if __name__ == "__main__":
    unittest.main()
