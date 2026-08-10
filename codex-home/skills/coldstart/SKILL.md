---
name: coldstart
description: Create a paste-ready handoff prompt that continues the exact current task in a fresh Codex or agent tab without switching scope. Use when the user asks for a "cold start", "new tab", "handoff", or "인수인계" prompt. Do not use for summaries, PR descriptions, or choosing a new task.
---

# Coldstart

Create a compact prompt that lets a fresh session resume the user's intended task without selecting a nearby or queued task instead.

## Lock the task

Identify the target in this order:

1. Use the task explicitly named in the current handoff request.
2. Otherwise, use the latest user-confirmed active task only when it is unambiguous.
3. Use an in-progress plan step only when it matches that task.

Preserve the user's task wording when practical. Treat plans, specs, branches, recently modified files, and open files as evidence about the selected task, never as reasons to select a different task. If candidates conflict or the target is ambiguous, ask one concise question and do not draft the prompt.

## Build the handoff

1. State the exact task, scope boundary, and intended end state.
2. Derive 2-3 observable completion conditions and the immediate next action only from the latest confirmed conversation state. If they are not known, omit them or mark them unknown instead of designing new work.
3. Cite at most 2 verified absolute paths that directly control this task. For long files, cite the exact heading or symbol.
4. Include only verified progress and decisions or constraints that change the next session's work.
5. Preserve approvals, plan state, and risk gates only when they apply to the selected task.

Do not:

- advance to the next queued task;
- choose a task because its docs are newer or more complete;
- include unrelated plans or nearby work;
- invent goals, completion conditions, or next steps from nearby docs;
- add generic discovery, planning, or approval gates;
- list auto-loaded root `AGENTS.md` or global instructions unless requested;
- run broad builds or tests just to prepare the prompt;
- copy background that the next session can read from a cited source.

## Output

- Write in the user's language and wrap the entire prompt in one fenced `markdown` block.
- Use the exact task name as the first heading; do not prefix it with `Cold start`.
- Default to 12-18 lines and omit any section that adds no action-changing information.
- Mark unverified state with `[UNKNOWN: ...]`.
- After the block, add only one short sentence telling the user to paste it into the new tab.

```markdown
# <exact task name>

<work to resume, its intended end state, and the necessary scope boundary>

## Done when
- <observable completion condition>
- <verification or handoff condition>

## Start here
1. Read `<absolute path>` → `<heading/symbol>` for <why it controls this task>.
2. <immediate next action>

## Constraints
- <only verified, action-changing context>
```
