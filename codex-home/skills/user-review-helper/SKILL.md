---
name: user-review-helper
description: Guide review of code the agent just wrote. Use SESSION for an interactive walkthrough, QUICK for an ordered clickable reading path, or FULL for a standalone review briefing. Trigger on "리뷰 세션", "리뷰 순서/리스트", or review-guide export; not code review or PR feedback.
---

# User Review Helper (three modes)

Help the user review code the agent wrote. Apply two rules in every mode:

1. **Explain high-level behavior before low-level code.** Establish what changed, why, and which runtime pieces interact before showing code references.
2. **Order by data/runtime flow, never alphabetically or by git output order.**

- **SESSION** — staged high-level briefing → confirmation → link list → per-item Q&A.
- **QUICK** — compact chat-only reading path with one-line file summaries.
- **FULL** — standalone markdown briefing for large or multi-stage work.

## Select the mode

- SESSION: 리뷰 세션 / 같이 리뷰 / 설명해주고 나서 보자 / walk me through. The user will attend and ask questions; no export was requested.
- QUICK: 순서 / 리스트 / 뭐부터 / 정리해줘, with no mention of a document or session.
- FULL: export / 문서(md)로 / 브리핑 문서 / shareable / handoff. The deliverable is a file someone can read alone.
- Ambiguous between SESSION and QUICK: default to QUICK and offer a high-level-first SESSION.

## Shared rules

### Follow runtime execution order

| Change shape | Order |
|---|---|
| New backend endpoint | controller → component/usecase → accessor/I/O → domain types |
| New frontend feature with API call | accessor → presentational component → context/provider → hook → integration/page → call-site trigger |
| Backend-only usecase fix | component/usecase → accessor if I/O changed → domain types if changed |
| Pure frontend refactor | top-level page/component → nested/leaf component |
| Contract-first change | model/contract → backend boundary → component/accessor → frontend accessor/component |
| Cross-cutting chain | follow the real hop direction; within each hop use the rows above |

Split independent concerns into named sections or stages; never interleave them.

### Make every file clickable

- In Codex chat, use absolute links with optional line numbers: `[display.ts](/absolute/path/display.ts:42)`.
- In an exported repo markdown document, use paths relative to the document with standard line anchors when useful.
- Never make a bare path the primary file reference.

### Describe the change

Write what changed, not what the file generally does. Prefer “Adds the `errorUsageLimit` branch” over “Error handler.”

### Keep chat diagrams visible

Use a compact inline ASCII diagram in a plain code block. Show one interaction per line and optimize for quick comprehension, for example:

```text
Browser ─조회→ API ─등록 재시도→ AfterShip
```

For FULL markdown only, use Mermaid when the target preview is known to render it; otherwise use ASCII.

### Resolve scope from evidence

Start with `git status -s` and `git diff --stat`. For committed work, compare with the confirmed branch base or commit range. In multi-repo workspaces whose root is not a git repo, inspect only the relevant child repos. Honor any user-named scope.

### Skip review noise in SESSION and QUICK

Skip unless behaviorally important:

- Mechanical or redundant tests (`*.test.*`, `*.spec.*`, `__tests__/`)
- Pure re-exports
- i18n/locale files
- Mocks and snapshots
- Lockfiles, generated files, and dependency-only bumps
- Mechanical module wiring whose provider logic did not change

Include a behavior-defining contract or regression test when it is the clearest specification of changed behavior or part of the critical path. State the skipped categories and counts briefly. If no substantive files remain, say so without padding.

## SESSION mode

Run four phases. The confirmation gate is mandatory; do not collapse the phases into one message.

### Phase 1 — high-level briefing

Read the scoped diff first, but produce no code, file paths, or layer-based structure.

- Speak between planner and developer level: assume product and architecture familiarity, but no knowledge of this diff.
- Present 2–5 conceptual stages in runtime order, one behavioral move per stage.
- Name the runtime instances involved—browser/frontend, API server, DB, cache, worker, queue, or external API—and explain how their responsibilities and interactions changed.
- Keep independently acting or state-owning boundaries separate. For example,
  do not collapse frontend UI, browser storage, the Browser Notification API,
  and the OS into one `Browser` box when they make different decisions.
- Describe each changed interaction as `source → action/data → destination`. Also
  name an expected instance that is deliberately absent from a critical path
  when that boundary matters, such as a server that stores a preference but
  does not participate when the browser fires a notification.
- When more than two instances interact, add a small ASCII before/after or interaction diagram.
- Before sending, verify: (1) every state/decision owner appears, (2) every
  changed cross-instance interaction appears, and (3) important non-participation
  boundaries are explicit. Do not shorten the briefing until all three pass.
- End by asking the user to confirm the picture before entering files.

### Phase 2 — confirmation gate

Enter low-level review only after the user confirms Phase 1. If the user corrects the story, verify the correction against the code and repair the high-level picture first. If confirmation includes a question, answer it at the high level before continuing.

### Phase 3 — low-level entry

- List changed code as absolute clickable links, ordered by runtime flow.
- Group links under the Phase-1 stage names so both levels align.
- Give one line describing the change per file.
- Apply the shared noise filter and note what was skipped.

### Phase 4 — per-item Q&A

Let the user drive by opening items and asking questions.

- Re-read the referenced code and context before answering. Search actual precedents before comparing conventions.
- Lead with the conclusion, then explain the mechanism at the user’s level. Use an analogy from a stronger domain when useful, then map it back to the real mechanism.
- If the user spots a possible issue, verify and diagnose it. Modify code only when the user explicitly asks for the fix; once authorized, apply the smallest correct change, run the targeted test, report it, and return to the review position.
- Track covered items. When the user winds down, name uncovered items and at most a few follow-up observations.

## QUICK mode

Open with 2–3 plain-language lines describing what changed and why, before the table. Then provide one file per row, ordered by runtime/data flow, with a one-line summary no longer than about 80 characters. End with a ruthless 3–6-file critical path: the files whose mistakes would break behavior or contract.

Use this shape:

```markdown
<2–3 plain-language what/why lines>

## A. <Concern name>

| # | File | What changed |
|---|---|---|
| 1 | [file.ts](/absolute/path/file.ts:42) | One-line description |
| 2 | [other.ts](/absolute/path/other.ts:17) | Another change |

## Skipped (intentional)

- Tests: <count> files
- Re-exports / i18n / mocks / generated: <count> files

## Critical-path review

- **#N** — why this matters most
```

For one concern, omit the concern heading and use one table.

## FULL mode

Create one standalone markdown document with three layers in this order.

### 0. One-page summary

- State the single core change in one line.
- Show a before/after or data-flow diagram understandable in about ten seconds, including the runtime instances and changed interactions.
- Give one line per stage explaining what it did because of the core change.
- Make this section sufficient for a planner-level reader.

### Per stage — three fixed blocks

For each stage or independent concern:

1. **① 두괄식 요약** — lead with the conclusion and bold the verb; keep it to 3–6 lines.
2. **② 파일 읽는 순서** — numbered, clickable, and runtime-flow ordered. Include verify-only or unchanged context files, deletions marked clearly, and tests last.
3. **③ 대표 예시 1개** — trace the one critical-path artifact that exercises the most concepts using concrete input → transformations → output. End with the review traps or “읽을 때 핵심 N가지.”

Use two examples only if the stage has two irreducibly different shapes; never create a gallery of cases.

### Optional appendices

Add only when applicable:

- Review-fix or known-issues log
- Exact verification commands
- Recommended cross-stage review order, branch/commit status, and blockers

### Choose the representative example

- Select the artifact on the critical path that touches the most distinct concepts.
- Trace concrete values such as a request, JSON row, state, numbers, and final output.
- End with what the reviewer must not confuse.

### Choose the export location

1. If the work has a task/plan folder, write there and follow its numbering convention, such as `NN_review_session_<scope>.md`.
2. Otherwise use the repo’s established docs location or scratchpad and report the path.
3. If the destination is genuinely ambiguous and writing in one place would be costly to undo, ask once.

Use links relative to the exported document.

### FULL procedure

1. Resolve git scope and read relevant plan/handoff documents to recover existing stage names.
2. Read enough key files to produce accurate summaries and choose the representative example; apply the global delegation rules if the surface is large.
3. Write the one-page summary and fixed per-stage blocks, leading every section with its conclusion.
4. Trace one representative example per stage.
5. Export the document, report its path, and offer to expand a single stage or example.

Use this abbreviated shape:

```markdown
# NN — Review Session: <scope>

## 0. 한 장 요약

핵심 한 줄: <the one idea>.
<before → after instance/data-flow diagram>
- Stage A → <one line>
- Stage B → <one line>

## Stage A — <name>

### ① 두괄식 요약

**<verb>** …

### ② 파일 읽는 순서

1. [file](relative/path) — what changed / what to check
2. …

### ③ 대표 예시 — <artifact>

(a) 입력: <sample> → (b) 변환: <step> → (c) 출력: <value>

> 읽을 때 핵심 N가지: 1… 2… 3…
```

## Boundaries

- Do not use this skill to find bugs or perform a code review. Follow the workspace/global `REVIEW.md` workflow for that request.
- Do not use it to archive human PR comments. Use the dedicated PR-comment reporting/archive skill.
- Do not use it for a cold-start handoff prompt. Use `coldstart`.

## Anti-patterns

- Opening with file paths, diffs, or code before the plain-language story.
- Ordering by alphabet or `git status` rather than runtime/data flow.
- Printing bare paths instead of clickable links.
- SESSION: collapsing phases, structuring Phase 1 by layers/files, merging distinct runtime instances into a generic box, answering from memory, or editing without explicit fix authorization.
- QUICK: listing every test for completeness, writing long summaries, omitting the critical-path subset, or lecturing about familiar layers.
- FULL: dumping every case, burying the conclusion, using prose-only examples without concrete values, or failing to create the requested document.
- Turning a reading guide into a review verdict or bug hunt.
