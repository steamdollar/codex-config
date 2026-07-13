---
name: coldstart
description: Generate a cold-start handoff prompt that the user can paste into a fresh Codex or coding-agent tab to continue a specific task. Use when the user asks for a "cold start prompt", "new tab prompt", "handoff prompt", "context reset prompt", "다른 탭에서 이어서 할 prompt", "새 세션으로 넘길 prompt", "인수인계 prompt", or similar. Prefer references to existing PLAN, ADR, spec, task, and decision docs over re-explaining context inline.
---

# Coldstart

Produce a prompt the user can paste into a brand-new Codex/coding-agent session so the next agent can continue a specific task without losing decisions, constraints, and review workflow.

## Principles

**Cite, don't re-explain.** The prompt should point to authoritative docs and sections. Do not copy background/context prose that the next session can re-read from files.

**Avoid auto-loaded and redundant files.** Do not list root `AGENTS.md` or global agent instructions as required reads unless the user explicitly asks. The active agent already receives them. Do list task-specific `PLAN-*`, ADR, spec, contract, or note files that are not always loaded.

**Point to sections.** For long docs, cite the exact heading and tell the next agent to grep/jump there instead of reading the whole file.

**Preserve applicable gates.** Carry forward gates from the user's request, repository instructions, and existing plan. Do not introduce plan or approval requirements for work that does not require them. If a plan already exists, follow or update it instead of inventing a new one.

**One-line goal.** State success in one sentence. Keep background out of the prompt.

**Carry known decisions and gotchas.** Include only specific facts surfaced in the current work, with a file/section reference where possible. If a fact is not verified, mark it as `[UNKNOWN: ...]`.

## Procedure

1. Identify the exact task and scope from the user's message.
   - If ambiguous, ask one concise clarifying question.
   - Do not invent the task from nearby open files.

2. Locate relevant docs with narrow searches from the project root.
   - Prioritize task-specific `PLAN-*` files, master implementation plans, ADR/decision notes, specs, contract files, and issue notes.
   - Include at most 4 required-read references.
   - Prefer absolute paths so the next session can open them directly.
   - Verify referenced paths exist.

3. Check current state only as needed.
   - Use `git status -s`, `git branch --show-current`, `git log --oneline -n 5`, or narrow `rg` searches when the prompt needs branch/progress facts.
   - Do not run broad builds or tests just to write a cold-start prompt.

4. Compose the prompt in the user's language.
   - Korean user -> Korean prompt.
   - Wrap the whole prompt in one fenced `markdown` block.
   - Keep the goal to one sentence and required-read references to 4 or fewer verified absolute paths.
   - Mark unverified state with `[UNKNOWN: ...]`.
   - After the block, add only one short sentence telling the user to paste it into the new tab.

## Template

```markdown
# Cold start - <task name>

Read only the following documents first to establish context:
1. `<absolute path>` - <why this is authoritative>
2. `<absolute path>` - <specific section/header if relevant>
3. `<absolute path>` - <only if it adds non-overlapping context>

One-line goal: <single sentence>

Current state:
- Branch: `<branch>` or `[UNKNOWN: branch not confirmed]`
- Completed: <verified short bullets>
- Next action: <verified next action>

Execution order:
1. Discovery - Verify the real code path and contract, then report the verified files, data flow, and uncertainties first.
2. Planning/approval - Follow the existing plan and repository guidance. Handle any required plan or approval before changing code.
3. Implementation - Perform only approved atomic steps. Prefer the repository's layer order and existing conventions.
4. Verification - Run only focused tests/typechecks appropriate to the change and report the results.

Existing decisions / gotchas:
- <decision or gotcha> - basis: `<file or section>`
- <decision or gotcha> - basis: `<file or section>`

Do not guess. Reconfirm the task using the documents above and current code/git evidence before proceeding.
```
