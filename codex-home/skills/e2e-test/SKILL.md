---
name: e2e-test
description: Phase-based full-stack end-to-end verification across UI, backend/API, agent or MCP, and data layers, especially for Clero-style local stacks. Use when the user asks for "E2E 테스트", "e2e test", "full stack 테스트", "프론트랑 백 같이 띄워서 테스트", "이번 작업 검증", or similar and wants real multi-process verification of completed work, not unit tests or a one-shot smoke check.
---

# E2E Test

Use this skill to run a finished implementation through an end-to-end path with explicit phases, evidence, and cleanup. Adapt the phases to the repository after reading local docs, scripts, env files, and existing plans; do not assume service names or ports without checking the codebase first.

## Operating Principles

- Exercise the real UI for full-stack scope. Use Playwright or an app-native browser automation harness when available and safe; otherwise hand browser interaction to the user. Do not replace a UI flow with curl, MCP JSON-RPC, or direct database checks and call it E2E.
- Keep phase boundaries explicit. Report meaningful phase results and continue within the approved scope. Pause only for required manual interaction or a material action not covered by existing authorization; a long-running process or phase boundary alone does not require another approval.
- Let Codex handle introspection and automation: repo discovery, env inspection, command execution, log tailing, read-only cloud queries, curl smoke checks, and artifact updates. Let the user handle MFA/SSO, credentials, account choices, and manual browser checks unless automation is already configured.
- Reuse the task's existing verification artifact. For a multi-phase run without one, record evidence in `PLAN-e2e-<task>.md`; a separate file is unnecessary when the requested report already preserves the results.
- Prefer temporary env overrides over editing tracked `.env` files. If a file must change, record the original state, keep the diff minimal, and restore it in the final phase.
- Treat cloud, blockchain, payment, production, shared-data, and database writes as approval-gated. A repository-specific E2E policy may explicitly pre-authorize task-isolated ephemeral fixtures written through its controlled dev/test runner; that exception does not extend to production, shared prefixes, persisted business entities, or cleanup. Use read-only commands by default outside that narrow exception.
- Stop and mark unknowns instead of inventing interfaces. If a required implementation or command cannot be found, write `[UNKNOWN: <file/interface>에 대한 구현체가 확인되지 않음]`.

## Inputs To Collect

Resolve these from the request and repository first; ask only for missing information that changes the test scope or requires user action:

1. Target feature: what was implemented and what user-visible behavior must be verified.
2. Reference docs: existing `PLAN-*.md`, `SUMMARY.md`, `z_archived/*`, PR notes, or issue links.
3. Scope: full stack, UI-only, API+agent, API-only, data-only, or another explicit boundary.
4. Environment: local by default; dev/staging/prod only with explicit confirmation.
5. Automation availability: Playwright/browser harness available, or user-driven browser flow.

## Standard Full-Stack Local Phases

Adjust these phases to the repo. Skip irrelevant layers only after documenting why.

### Phase 0 - Environment Readiness

Codex actions:
- Inspect project docs, package scripts, build files, and env files for the exact local startup path.
- Identify local vs remote endpoints. For Clero-style stacks, common gotchas include `MCP_SERVER_URL` in api and `API_HOST` in MCP; full-stack local E2E should dispatch to local services.
- Start required local dependencies and app processes in observable sessions. Capture command, port, log path, PID/session id, and env overrides.
- Wait for readiness endpoints or UI root responses before declaring the phase complete.
- If SSO/MFA is required, ask the user to run the login step and then continue with read-only verification.

Hand-off: all required services are running, endpoints are known, and temporary changes are listed.

### Phase 1 - Data Layer Direct Check

Verify data state independently of application code.

- Use read-only database, object storage, index, or chain queries appropriate to the feature.
- Confirm table/index/schema assumptions against source code or docs before querying.
- Check representative rows, blob/object references, schema versions, legacy coexistence, fallback rows, and edge cases relevant to the feature.
- Record exact commands or query shapes without leaking secrets.

Hand-off: data layer is ready or the blocking data issue is documented.

### Phase 2 - API Smoke

Bypass UI and agent layers.

- Discover auth flow from repo tests or local docs before inventing a token path.
- Hit local API endpoints with curl or the repo's preferred client.
- Cover happy path, fallback path, validation failure, permission failure, and legacy alias behavior when applicable.
- Watch logs while calling the API and confirm requests reached the intended local service, not dev/staging.
- Respect throttling and avoid load-style tests unless explicitly requested.

Hand-off: API contract and logs match the expected behavior.

### Phase 3 - Agent Or MCP Scenario Through UI

Use this only when the product path includes an agent, MCP server, orchestration layer, or tool-calling flow.

User or browser automation actions:
- Run one scenario at a time in the real UI chat or agent surface.
- Cover explicit arguments, inferred arguments, ambiguous prompts, fallback prompts, and regressions relevant to the feature.

Codex actions:
- Tail the agent/MCP/orchestrator logs after each scenario.
- Confirm routing decision, selected tool/sub-agent, tool arguments, dispatch target URL, response shape, and result quality.
- If calls hit remote endpoints when local was expected, stop and fix environment wiring before continuing.

Hand-off: agent routing and tool dispatch are verified with log evidence.

### Phase 4 - Product UI Scenario

Exercise the actual user workflow that consumes the feature.

- Prefer Playwright screenshots/traces when a test harness is present and safe to run.
- If manual, give the user a short scenario list and ask for observed results one step at a time.
- Inspect API logs, browser console output, network responses, screenshots, or persisted state when failures appear.
- Record UI-specific issues even if they are outside the original implementation scope.

Hand-off: visible product behavior is verified or issues are documented.

### Phase 5 - Wrap-Up And Cleanup

- Update the chosen verification artifact with results and findings.
- Stop background processes created for the test.
- Remove temporary files such as tokens, test logs, truststores, and scratch artifacts unless the user wants to keep them.
- Restore env overrides and report any remaining dirty files.
- Report verified behavior, failed or untested boundaries, and any remaining cleanup, with the commands or evidence needed to assess the result.

## Phase results

Report the result, supporting evidence, and relevant next action briefly. Continue through
authorized phases without a separate go-ahead; preserve the external-write boundaries above.

## Findings Format

Number findings sequentially across phases: `Issue 1`, `Issue 2`, ...

For each finding, capture:
- Issue: what broke and where; include `file:line` links when applicable.
- Impact: who is affected and when.
- The smallest corrective action; include alternatives only when a real trade-off needs a decision.

## Not For

- Unit tests, integration tests, lint, or typecheck-only verification.
- Code-review nit validation.
- New feature implementation.
- One-shot "is the server up?" checks.
- Load tests, production tests, or destructive external-system checks without explicit approval.

## Prior Tab Or Archive Reuse

If the user references a previous tab or "이전처럼", search for `PLAN-*.md`, `SUMMARY.md`, and `z_archived/*` first. Reuse prior phase structure and known findings when applicable, but revalidate commands and env wiring against the current repo.
