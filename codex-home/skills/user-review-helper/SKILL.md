---
name: user-review-helper
description: Produce an ordered, link-rich list of nontrivial files the user should review after Codex or another agent changed code. Use when the user asks for a "review order", "리뷰 순서", "리뷰할 파일 정리", "리뷰할 거 정리", "뭐부터 리뷰하지", "리뷰 리스트", "nontrivial files", "변경된 파일 중 중요한 것만", or similar. This is a curated reading path, not a code review.
---

# User Review Helper

Produce the reading path for the user's manual review: nontrivial changed files, ordered by runtime/data flow, with one-line summaries and clickable links.

This is not a code review and not a PR summary. It answers: "Which files should I open, in what order, to review the agent's work efficiently?"

## Principles

**Skip noise.** Exclude these unless the user explicitly asks:
- Pure re-exports: `index.ts` that only adds exports
- i18n/locale files: `messages/*.json`, `*.locales.*`
- Mocks and snapshots: `__mocks__/`, `.snap`
- Lockfiles and generated artifacts
- Mechanical module wiring, such as NestJS `*.module.ts` files that only add imports/providers

**Keep behavior-defining tests.** Include a nontrivial contract/regression test
when it is the clearest specification of changed behavior or belongs on the
critical path. Exclude mechanical or redundant `*.test.*`, `*.spec.*`, and
`__tests__/` files by default.

If no nontrivial files remain, say that directly and list the skipped categories.

**Order by execution path.** Do not sort alphabetically or by `git status` order.

| Change shape | Preferred order |
|---|---|
| New BE endpoint | controller -> component/usecase -> accessor/I/O -> domain types |
| BE usecase fix | component/usecase -> accessor/I/O if changed -> domain types |
| New FE feature with API call | ui-accessor -> reusable component -> context/provider -> hook -> route/page -> call-site trigger |
| Pure FE refactor | top-level page/component -> nested/leaf component |
| Cross-repo or cross-hop flow | follow real hop direction, then order files within each hop |
| Contract-first change | model/contract -> backend boundary -> component/accessor -> frontend accessor/component |

**Summaries describe the diff.** One line per file, 80 characters or less where practical. Say what changed, not what the file generally does.

**Use clickable file links.** In Codex final answers, prefer absolute markdown links:
`[display.ts](/absolute/path/display.ts:42)`.
If the repo-relative link is more useful for a requested artifact, use `[path/to/file.ts](path/to/file.ts)`.
Never dump bare paths as the primary list.

**Recommend a critical path.** End with 3-6 files that are the minimum review set. Choose files whose mistakes would break runtime behavior or contract, including a behavior-defining test when it is essential evidence.

## Procedure

1. Identify the change set.
   - Start with `git status -s` and `git diff --stat`.
   - If the scope is committed work, compare against the right base with `git diff --stat <base>...HEAD` or `git show --stat`.
   - If ambiguous, ask one concise question about the base/scope.

2. Filter skipped categories.
   - Apply the behavior-defining test exception, then count skipped mechanical
     tests and generated/noise files so the omission is explicit.

3. Read the relevant diffs.
   - Use focused `git diff -- <file>` or `git show -- <file>`.
   - Classify each nontrivial file by runtime role.

4. Order by runtime/data flow.
   - Split unrelated concerns into separate sections.
   - Keep the list short enough to be useful.

5. Produce the output.

## Output Format

Use `## Review Order` for one concern. For multiple unrelated concerns, repeat the
review section with headings such as `## A. <Concern>` and `## B. <Concern>`.

```markdown
## Review Order

| # | File | What changed |
|---|---|---|
| 1 | [file.ts](/abs/path/file.ts:42) | One-line diff summary |
| 2 | [other.ts](/abs/path/other.ts:17) | One-line diff summary |

## Skipped

- Mechanical/redundant tests: <count>
- Re-exports/i18n/mocks/generated/module wiring: <count>

## Critical Path

- #1 - <why this matters>
- #2 - <why this matters>
```

## Anti-Patterns

- Listing every file "for completeness".
- Including mechanical/redundant tests, or excluding a behavior-defining test needed on the critical path.
- Alphabetical order.
- Describing layer responsibility instead of the diff.
- Long summaries that become a PR description.
- Omitting the critical-path subset.
