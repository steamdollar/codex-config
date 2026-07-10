---
name: clero-stepwise-change
description: Use for Clero tokko monorepo work when a task needs source-aware discovery, non-trivial planning, or pattern-aligned source changes across Clero-Model, Clero-Website, Clero-MCP, or Clero-CDK, including approved code-change handoffs from clero-local-dev-triage.
---

# Clero Stepwise Change

## Purpose

Use this skill for Clero work where correctness depends on existing contracts,
layer boundaries, generated artifacts, or the user's preferred incremental
review style.

Do not use it for a one-line factual answer that does not touch repo context.

## First Checks

1. Resolve Codex home as `${CODEX_HOME:-$HOME/.codex}`. Resolve the Clero root
   from `CLERO_TOKKO_ROOT`, or from `$CODEX_HOME/local/roots/clero-tokko` when
   that symlink exists. If neither resolves to a directory, report
   `[UNKNOWN: Clero repository root not configured]` and ask for the exact path.
2. Read `$CLERO_TOKKO_ROOT/AGENTS.md` if available after resolution.
3. If `$CODEX_HOME/memories/MEMORY.md` exists, check it for the domain keyword
   before deep repo exploration:
   `rg -n "<keyword>|<operation>|<route>|<enum>" "$CODEX_HOME/memories/MEMORY.md"`.
4. Remember that the resolved Clero root itself may not be a git repo.
   Run `git status` only inside concrete subrepos such as `Clero-Model`,
   `Clero-Website`, `Clero-MCP`, or `Clero-CDK`.
5. Use narrow `rg` searches by operation, route, DTO, enum, UI label, or domain
   term. Avoid broad scans of the monorepo.

## Discovery Order

When the edit location is unclear, inspect in this order and stop once the
relevant path is proven:

1. User-visible text, route, API path, domain keyword.
2. Smithy operation/model in `Clero-Model`.
3. Backend `api` controller or route in `Clero-Website`.
4. Backend `api-component` use case.
5. Backend `api-accessor` I/O implementation.
6. Frontend `ui-accessor` API client or mapper.
7. Frontend `ui-components` reusable component.
8. Frontend `ui` page or route.

Report discovery using this compact structure:

```md
## 기능 이해
## 검색 키워드
## 확인한 파일
## 요청/데이터 흐름 추정
## 수정 가능성이 높은 파일
## 읽기만 하면 되는 파일
## 불확실한 점
## 다음 step
```

Use `[UNKNOWN: file/interface not confirmed]` for unverified claims.

## Planning Rule

For non-trivial changes, create a plan before implementation:

- Path: repo root `PLAN-{short-task-name}.md`.
- Language: Korean.
- Do not implement immediately after creating the plan unless the user approves.
- Keep scope atomic. Default work order is `Clero-Model` -> Website backend ->
  Website frontend. Handle one area per turn unless there is a clear reason.

Plan structure:

```md
# 작업 계획

## 1. 목표
## 2. 영향 범위
## 3. 단계별 작업
## 4. 수정 예정 파일
## 5. 생성/빌드/테스트 명령
## 6. 확인 필요 사항
```

## Pattern Before Edit

Before adding code:

1. Search for similar implementations in the same layer.
2. Prefer existing naming, dependency injection, mapper, accessor, error
   handling, test helper, and export patterns.
3. Do not create new top-level folders or cross-layer helper dumps.
4. If an exception is necessary, explain the tradeoff and ask before editing.

Known Clero examples to verify in current code before relying on them:

- Smithy changes in `Clero-Model` usually require `./gradlew build`.
- Website packages may consume `apps/api-domain/dist`; rebuild the producer
  package after enum/domain changes.
- S3 reads generally follow handler -> component -> accessor, not direct
  handler-side SDK calls.
- Focused Jest can pass tests but still exit non-zero because global coverage
  thresholds run; validate target behavior and use file-scoped coverage when
  needed.

## Review Output

Route explicit review-order requests to `user-review-helper`; do not duplicate
its file-ordering rules here.

## Completion

Finish Clero tasks with:

```md
## 완료 내용
## 변경 파일
## 실행한 명령
## 테스트 결과
## 남은 작업 또는 확인 필요 사항
```

If tests or builds were skipped, state why and provide the narrow command the
user can run.
