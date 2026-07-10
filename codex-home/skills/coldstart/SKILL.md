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

**Preserve gates.** Encode the user's preferred sequence explicitly: Discovery report -> plan or step proposal -> user approval -> code. If a plan file already exists, tell the next agent to update or follow it instead of inventing a new one.

**One-line goal.** State success in one sentence. Keep background out of the prompt.

**Carry known decisions and gotchas.** Include only specific facts surfaced in the current work, with a file/section reference where possible. If a fact is not verified, mark it as `[UNKNOWN: ...]`.

## Use

Use this skill when the user asks for a prompt to continue a specific task in a new tab, fresh context window, or different coding agent session.

Do not use it for PR descriptions, ordinary summaries, or explaining how to continue inside the current session.

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

## Template

```markdown
# Cold start - <task name>

먼저 다음 문서만 읽고 컨텍스트를 잡는다:
1. `<absolute path>` - <why this is authoritative>
2. `<absolute path>` - <specific section/header if relevant>
3. `<absolute path>` - <only if it adds non-overlapping context>

목표 한 줄: <single sentence>

현재 상태:
- Branch: `<branch>` 또는 `[UNKNOWN: branch 미확인]`
- 진행 완료: <verified short bullets>
- 이어서 할 일: <verified next action>

진행 순서:
1. Discovery - 실제 code path와 contract를 확인하고, 확인한 파일/데이터 흐름/불확실한 점을 먼저 보고한다.
2. 계획 - 기존 plan이 있으면 그 문서를 업데이트/참조하고, 새 plan이 필요하면 `PLAN-<short-task>.md`를 작성한 뒤 승인받는다.
3. 구현 - 승인된 atomic step만 진행한다. repo layer 순서와 기존 convention을 우선한다.
4. 검증 - 변경 범위에 맞는 focused test/typecheck만 실행하고 결과를 보고한다.

이미 결정된 것 / 주의할 점:
- <decision or gotcha> - 근거: `<file or section>`
- <decision or gotcha> - 근거: `<file or section>`

추측하지 말고, 위 문서와 현재 코드/git evidence로 다시 확인해서 진행한다.
```

## Quality Checks

- The result is one copy-pasteable fenced `markdown` block.
- The goal is one sentence.
- Required-read references are absolute paths and exist.
- Required-read references are 4 or fewer.
- The prompt does not re-explain background already in the referenced docs.
- Discovery, planning/approval, implementation, and focused verification gates are explicit.
- Unknown or unverified state is marked with `[UNKNOWN: ...]`.

After the code block, add one short sentence telling the user to paste it into the new tab. No extra commentary.
