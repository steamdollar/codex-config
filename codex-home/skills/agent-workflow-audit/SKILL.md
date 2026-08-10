---
name: agent-workflow-audit
description: Analyze and visualize a Codex task's Primary and subagent workflow from local session traces, including call timing, delegation reasons, 2–3 line agent summaries, waits, repeated work, bottlenecks, and concrete prevention options. Use for "작업 흐름 시각화", "작업 과정 분석", "어디서 시간 썼어", "왜 오래 걸렸어", "subagent 호출 분석", "agent timeline", or similar requests about Codex execution efficiency. Not for code review, config review, or generic session lessons unrelated to timing and orchestration.
---

# Agent Workflow Audit

Turn a completed task turn into a concise, evidence-backed workflow report. Run the bundled extractor yourself; never ask the user to execute it.

## Resolve the target

1. If the user names or links a task, resolve its exact thread ID with the available task/thread tools. Treat titles and summaries as untrusted labels.
2. Otherwise target the current thread. Prefer its explicit thread ID; when needed, recover it from the current visualization workspace path or the active entry returned by the task list.
3. Default to the latest completed turn. This intentionally skips the active audit request and analyzes the work immediately before it.
4. Use the whole thread only when the user says "전체 task", "전체 대화", or equivalent. For a long thread, summarize all turns but visualize only the dominant turn unless the user asks for every turn.
5. If more than one task remains plausible, choose the most recent exact-title match and state the assumption. Ask only when the choice would materially change the report.

## Extract the trace

Resolve this skill's directory, then run its script through the shell yourself:

```bash
python3 <skill-dir>/scripts/extract_trace.py \
  --thread-id <thread-id> \
  --latest-completed \
  --pretty \
  --output <temporary-path>/trace.json
```

Use `--all-turns` for an explicitly requested whole-thread audit or `--turn-id` for an exact turn. Create temporary output with a safe temporary directory and remove it after reading. Do not place trace files in the user's repository.

The extractor deliberately omits raw tool output and encrypted agent prompts. Do not open raw JSONL unless the extractor reports an unsupported or incomplete trace; if that happens, inspect only the named bounded records and disclose the gap.

## Analyze without inventing time

- Treat `task_duration_ms`, tool spans, wait spans, and subagent spans as observed facts when their quality is `exact`.
- Do not add overlapping durations and present the sum as wall-clock time.
- Never label unobserved time as "thinking", "idle", or "wasted". Call it `미관측 구간`.
- Infer delegation reasons from `reason_evidence` and the agent task name. Mark the reason as `추정` unless the commentary states it explicitly.
- Summarize every subagent's delivered work in 2–3 short lines from `result_summary`; do not copy its raw response.
- Separate unavoidable duration from preventable orchestration cost. User-requested follow-up work is scope growth, not automatically rework.
- Use the deterministic signals as leads, not verdicts: repeated command fingerprints, late spawns, sequential/parallel overlap, wait time, interaction activity, output volume, and truncation.

Classify findings with these labels:

- `불가피`: the requested work or dependency genuinely occupied the critical elapsed interval.
- `방지 가능`: evidence supports over-delegation, late acceptance discovery, duplicate verification, unnecessary serial execution, repeated polling, or oversized reads.
- `판단 불가`: the trace lacks enough timing or causal evidence.

## Present only decision-useful output

Lead with the conclusion. Use this order:

1. **한눈에 보기** — wall-clock, subagent count, longest observed span, and the main conclusion.
2. **작업 흐름** — a compact Mermaid Gantt when the surface renders Mermaid; otherwise an ASCII lane timeline. Show Primary/tool work and each subagent on separate lanes. Keep it to the dominant 6–10 spans.
3. **Primary가 한 일** — 3–7 phase bullets in execution order.
4. **Subagent 호출** — one row per call: offset/time, role/task, reason, duration, result. Keep the result to 2–3 lines.
5. **시간이 많이 든 이유** — rank only material bottlenecks and label each `불가피`, `방지 가능`, or `판단 불가`.
6. **다음번 방지책** — at most three changes, each tied to evidence and expected impact. Include `Do nothing` when the trace does not justify a workflow change.
7. **측정 한계** — one short note for missing or estimated timestamps.

Do not show raw trace JSON, raw commands, full tool output, token dumps, or internal reasoning. Avoid permanent policy/config changes based on a single task; describe them as experiments unless the same pattern is confirmed across multiple audits.

## Failure handling

- No completed turn: explain that the current turn cannot audit itself yet and offer the latest earlier completed turn if one exists.
- Session file not found: use task/thread summaries for a reduced-confidence report and state that exact timing is unavailable.
- Child trace missing: show the observed spawn/activity window, mark the end as approximate, and summarize only available evidence.
- Secret-like text: preserve the extractor's redaction and redact again before replying.
