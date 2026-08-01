---
name: coldstart
description: Create a handoff prompt for continuing work in a fresh Codex or agent tab, grounded in existing PLAN, ADR, spec, task, and decision docs. Use for "cold start", "new tab", or "인수인계 prompt" requests.
---

# Coldstart

Produce a compact prompt the user can paste into a new Codex/coding-agent session. Make the intended outcome and completion criteria obvious before adding context.

## Principles

**Lead with the goal.** State the concrete deliverable, scope boundary, and intended outcome. Never use a vague goal such as "continue the task."

**Define done.** Add 2-4 observable completion conditions, including the relevant verification or handoff state.

**Include only action-changing context.** Omit generic workflow, background prose, and facts the next agent can discover cheaply. Keep a decision, constraint, or current-state fact only when it changes what the next agent should do.

**Cite instead of copying.** Point to authoritative files and exact headings or symbols. Do not summarize material the next session can read directly.

**Avoid auto-loaded files.** Do not list root `AGENTS.md` or global instructions unless the user explicitly asks. Include only task-specific plans, ADRs, specs, contracts, or decision notes that are not loaded automatically.

**Preserve real gates.** Carry forward approvals, plan state, and risk gates that actually apply. Do not add generic approval or planning steps.

## Procedure

1. Determine the goal from the user's latest direction and the active plan/spec.
   - Express it as an end state, not an activity.
   - Resolve conflicting historical wording in favor of the user's latest direction.
   - Ask one concise question only when the outcome cannot be determined safely.

2. Derive 2-4 completion conditions.
   - Cover the requested artifact or behavior, scope boundary, and relevant verification.
   - Do not turn generic repository rules into completion conditions.

3. Locate only the sources needed to act.
   - Prefer the active task plan plus the most authoritative spec, ADR, or code symbol.
   - Include at most 3 verified absolute paths.
   - For long files, cite the exact heading or symbol.

4. Check current state only as needed.
   - Use `git status -s`, `git branch --show-current`, `git log --oneline -n 5`, or narrow `rg` searches when the prompt needs branch/progress facts.
   - Do not run broad builds or tests just to write a cold-start prompt.

5. Compose the prompt in the user's language.
   - Korean user -> Korean prompt.
   - Wrap the whole prompt in one fenced `markdown` block.
   - Keep it short enough to scan before opening files; default to about 20 lines.
   - Put `Goal` and `Done when` before references or current state.
   - Mark unverified state with `[UNKNOWN: ...]`.
   - After the block, add only one short sentence telling the user to paste it into the new tab.

## Template

```markdown
# Cold start - <task name>

## Goal
<deliverable, scope, and intended end state in one concrete sentence>

## Done when
- <observable completion condition>
- <relevant test, review, or handoff condition>

## Start here
1. Read `<absolute path>` → `<heading/symbol>` for <why it controls the work>.
2. <one concrete next action>

## Current state
- Done: <only verified progress that prevents repeated work>
- Next: <immediate next step>

## Decisions / constraints
- <only an action-changing decision, gate, or gotcha> — `<source>`
```
