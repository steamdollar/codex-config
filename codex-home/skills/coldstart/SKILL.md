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

Use the latest verified session state. Prefer directly observed repo/tool state over explicit user decisions, verified progress reports, plans, and inference, in that order.

1. State the exact task, scope boundary, and intended end state.
2. Derive 2-3 observable completion conditions and the immediate next action only from verified state. If they are not known, omit them or mark them unknown instead of designing new work.
3. Preserve current implementation/investigation state when work has already started: what is complete, in progress, or not yet started when that distinction changes the next action.
4. Preserve verification separately from implementation state: what was run, what passed or failed, and material checks that were not run. Never turn untested state into implied success.
5. Preserve task-relevant working-tree or commit state when already known and necessary to avoid losing or overwriting work. Do not inspect Git solely to populate the handoff unless that state is needed for safe continuation.
6. Prefer 1-3 verified repository-relative paths that directly control the task. Use absolute paths for files outside the repository or when location ambiguity matters. For long files, cite the exact heading or symbol.
7. Include only verified decisions, constraints, approvals, plan state, or risk gates that change the next session's work.
8. Include a rejected approach only when retrying it is a realistic risk and the reason for rejection is still valid.

Do not:

- advance to the next queued task;
- choose a task because its docs are newer or more complete;
- include unrelated plans or nearby work;
- invent goals, completion conditions, progress, verification, or next steps from nearby docs;
- add generic discovery, planning, or approval gates;
- list auto-loaded root `AGENTS.md` or global instructions unless requested;
- run broad builds or tests just to prepare the prompt;
- copy background that the next session can read from a cited source;
- dump full git status, logs, architecture, tech stack, or debugging history when a smaller action-changing statement is enough.

## Output

- Write in the user's language and wrap the entire prompt in one fenced `markdown` block.
- Use the exact task name as the first heading; do not prefix it with `Cold start`.
- Default to 12-22 lines and omit any section that adds no action-changing information.
- Mark unverified state with `[UNKNOWN: ...]`.
- After the block, add only one short sentence telling the user to paste it into the new tab.

```markdown
# <exact task name>

<work to resume, its intended end state, and the necessary scope boundary>

## Current state
- <verified completed/in-progress state>
- <task-relevant working-tree or commit state, if material>

## Done when
- <observable completion condition>
- <verification or handoff condition>

## Start here
1. Read `<repo-relative path>` → `<heading/symbol>` for <why it controls this task>.
2. <immediate next action>

## Verification
- <last verified test/build/runtime state>
- [UNKNOWN: <material verification gap>]

## Constraints
- <only verified, action-changing context or still-valid rejected approach>
```
