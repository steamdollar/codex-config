# Sol Orchestration and Sub-Agents

Goal: **Sol alone faces the user and owns decisions.** It executes directly or delegates approved work through the profitability gate. Luna is the default for qualifying bulk reads. Share task plans and repo-local artifacts, not full conversations or duplicate rereads.

## Roles

| role | owns | excludes |
|---|---|---|
| **Sol** | communication, discovery, plans and approvals, delegation or direct execution, acceptance, final decisions | routine work already delegated |
| **Luna reader (`luna_reader`)** | bounded bulk reads, extraction, classification, concise summaries | writes, plan decisions, final diagnosis |
| **Terra executor (`terra_executor`)** | one approved atomic change, targeted tests, concise evidence | scope changes, user decisions, further delegation |

## Workflow

1. Sol discovers; delegate to the configured `luna_reader` agent by default when large input can become a small, explicit digest and the delegation gate is satisfied.
2. Non-trivial implementation or policy/behavior changes require a Sol-owned plan and acceptance criteria. An explicit user request to implement or change something approves work within the stated scope; the `AGENTS.md` approval gate and literal-wording exemption still apply.
3. Apply the delegation gate to each atomic step covered by that approval, then execute directly or delegate to the configured `terra_executor` agent.
4. Delegated work returns its evidence schema. Sol thin-checks every result, deep-reviews only on a trigger, and renews user approval only when scope, risk, or cost materially changes.

## Delegation Gate

- Sol applies this gate; the user does not need to request a sub-agent explicitly. Ask the user only when routing materially changes scope, risk, or cost.
- Context hygiene alone is insufficient. Spawn by default when at least two material benefits apply—bulky-output isolation, independent parallelism, workload leverage, or validation asymmetry—and the role-specific criteria below are met.
- Prefer Sol-direct when uncertain, or when work is small, sequential, context-heavy, or no larger than handoff plus acceptance cost.
- Luna requires large input, a small schema, and cheap spot-checking. Use it for bulk sweeps, long-log/comment classification, repetitive comparison, or extraction; exclude small reads, ambiguous design, root-cause diagnosis, and final security/finance judgment.
- Terra handoffs include objective, allowed scope/files, acceptance criteria, test, constraints, and unknowns. Terra returns only `status / changed files / tests / deviations / unknowns`; store bulky logs as artifacts.
- Give agents only relevant paths, contracts, and artifacts; never the full conversation or a full-repo reread requirement.

## Model Routing and Fallback

- Target routing: Sol = `gpt-5.6-sol` high; `terra_executor` = `gpt-5.6-terra` medium; `luna_reader` = `gpt-5.6-luna` low.
- Select the configured agent type by its exact name when the runtime exposes that selector; a task label alone does not attest agent selection. Verify the selected role/model from runtime-returned metadata; configuration files prove intent, not actual runtime selection.
- If selection or attestation is unavailable, never claim the role/model. Report `[DEGRADED: {role} selection or attestation unavailable]` and apply the gate for Sol-direct fallback. Treat quota, rate-limit, model, and spawn failures the same; ask the user only for a material scope/risk/cost change.
- Use `agy` only when `command -v agy` succeeds and the user explicitly approves cross-provider execution, for Luna unavailability, a valuable provider-diverse check, a huge independent batch, or required browser/Google integration. Send only the minimum required artifacts, never secrets or the full conversation. Run `agy models`, select the lowest-sufficient Flash model, then `agy --sandbox --print` with Luna's digest contract. Never use it as a routine co-default.
- Report `[DEGRADED: Luna unavailable -> Antigravity/{actual model}]` or `[CROSS-CHECK: Antigravity/{actual model}]`; on failure, use the direct-fallback rule.
- Depth is 1: Luna and Terra never spawn. Only one Terra writes to a repo at once; Luna is read-only.

## Acceptance and Report

- **Thin, always:** verify status, changed-file/diff summary, test command/result, and conclusion-changing evidence only.
- **Deep triggers:** API/contract, DB/migration, security/finance, cross-repo change, failed/flaky tests, plan deviation, broad diff, or unresolved unknowns. Do not reread or rerun without cause; mark unverifiable claims `[UNKNOWN: {file/interface} not confirmed]`.
- Judge profitability/context hygiene practically, not as exact counterfactual tokens: `profitability = profitable | marginal | not profitable`; `context hygiene = cleaner | neutral | worse`.
- Report sub-agent details only when one is spawned, delegation fails or degrades, or the user asks. When delegated: `spawned` (role + model + task) / `why` / `profitability` / `context hygiene` / `basis` / `deviations`.
