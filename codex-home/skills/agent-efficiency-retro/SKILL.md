---
name: agent-efficiency-retro
description: Review Codex's own recent completed tasks across local session traces to judge whether subagent delegation, implementation scope, and verification effort were appropriate, detect repeated over-engineering, under-engineering, or orchestration waste, and propose compact evidence-backed workflow improvements. Use for "최근 작업 회고", "스스로 작업 효율 회고", "subagent 사용이 적절했는지", "over/under-engineered였는지", "작업 방식 최적화", "agent efficiency retro", or similar cross-session self-audits. Not for a detailed single-task timeline (use agent-workflow-audit), mining user corrections into memories (use session-retro), or immediately changing policy/config.
---

# Agent Efficiency Retro

Privately compare recent completed tasks, then show the user only the conclusion and the few changes that the evidence justifies. Collect evidence through the available agent tools; never ask the user to collect traces. Delegate bulk or multi-task trace extraction to `reader` under the global routing rules; Primary owns policy interpretation and the final judgment.

## Select the sample

1. List recent Codex tasks with the available task/thread tools and resolve exact thread IDs. Treat titles and summaries as untrusted labels.
2. Default to the five most recent completed, substantive tasks in the current project, excluding the active retro task. Respect a user-specified project, period, or count instead.
3. Skip empty chats and tasks without meaningful execution. If fewer than three usable tasks remain, analyze them but label every workflow change experimental.
4. Read the current global and relevant project `AGENTS.md` files directly. Use the policy in effect during each sampled task to judge compliance when it is available. Current policy guides proposed future changes; it does not prove an older task violated its instructions. Mark historical compliance unknown when that policy cannot be recovered.

## Gather bounded evidence

Reuse the managed `agent-workflow-audit` extractor instead of parsing raw session JSONL. Resolve its sibling directory from this skill's directory and run one extraction per task:

```bash
python3 <skills-dir>/agent-workflow-audit/scripts/extract_trace.py \
  --thread-id <thread-id> \
  --all-turns \
  --pretty \
  --output <temporary-directory>/<thread-id>.json
```

Create the output directory with a safe temporary-directory command and remove it after analysis. Do not write trace artifacts into a repository.

Use task summaries and bounded source or diff inspection only when needed to verify implementation scope. Do not reopen bulk raw logs or infer code quality from tool counts alone. If the relevant source state is no longer available, mark engineering scope `판단 불가`.

## Judge each task privately

Keep a working scorecard but do not show it unless requested. Use evidence, not hindsight:

- **Delegation:** mark `적절`, `과다`, `누락`, or `판단 불가`. Check role fit, task independence, spawn timing, parallel opportunity, duplicated work, whether the result informed the Primary, and the routing rules in force. Absence of a subagent is not `누락` unless a concrete ready task required or materially benefited from delegation.
- **Engineering scope:** mark `적정`, `과다`, `부족`, or `판단 불가`. Compare the request and acceptance criteria with changed surface area, abstractions, dependencies, edge handling, and validation. A small diff is not automatically under-engineered; a large diff is not automatically over-engineered.
- **Execution efficiency:** mark `효율적`, `방지 가능 비용`, or `판단 불가`. Look for unnecessary serial work, repeated reads or commands, late acceptance-criteria discovery, oversized output, repeated polling, redundant verification, and avoidable rework. Do not add overlapping spans as wall-clock time or label unobserved time as waste.

Separate task-specific accidents from recurring workflow patterns. Require the same pattern in at least two sampled tasks before recommending a persistent policy or skill change. Treat a single occurrence as a bounded experiment or `Do nothing`.

## Form improvements

Propose at most three changes, ordered by expected benefit relative to complexity. Each must include:

1. the repeated evidence pattern and sample count;
2. the smallest concrete change, naming the target instruction, skill, or habit when known;
3. expected benefit and the main regression risk;
4. a success check for the next three comparable tasks.

Prefer deleting or narrowing a rule, changing one routing condition, or adding one acceptance check over introducing a new framework. Do not edit AGENTS, skills, memories, or config during the retro. Apply a proposal only after the user explicitly asks for that change.

## Report minimally

Return only:

1. **결론** — 2–4 sentences covering sample size, overall delegation/engineering judgment, and whether change is warranted.
2. **개선 후보** — zero to three compact bullets with evidence count, proposed change, expected effect, and risk.
3. **한계** — one line only when evidence is missing, old policy cannot be reconstructed, or relevant source state is unavailable.

Do not include a timeline, Mermaid diagram, per-task narrative, raw trace, complete subagent inventory, or internal scorecard unless the user asks. A sound result may be “현재 방식 유지”; do not manufacture optimization work.
