# Primary Orchestration and Sub-Agents

Goal: **The primary agent alone faces the user and owns decisions.** It executes directly or delegates approved work through the profitability gate. Roles describe responsibilities; model bindings are replaceable implementation choices. Share task plans and repo-local artifacts, not full conversations or duplicate rereads.

The advisor role is disabled. The primary performs planning, diagnosis, review, and acceptance directly.

## Durable roles

| role | owns | excludes |
|---|---|---|
| **Primary** | communication, discovery, plans and approvals, delegation or direct execution, acceptance, final decisions | routine work already delegated |
| **Reader (`reader`)** | bounded bulk reads, extraction, classification, concise summaries | writes, plan decisions, final diagnosis |
| **Executor (`executor`)** | one approved atomic change, targeted tests, concise evidence | scope changes, user decisions, further delegation |

## Workflow

1. The primary agent discovers and owns the decision. If the task could plausibly meet the benefit gate, apply one delegation checkpoint after scope is clear.
2. Non-trivial implementation or policy/behavior changes require a primary-owned plan and acceptance criteria. An explicit user request to implement or change something approves work within the stated scope; the `AGENTS.md` approval gate and literal-wording exemption still apply.
3. Keep the initial direct-or-delegate route through approved atomic steps. Re-evaluate only when scope changes or a later step introduces newly independent or bulky work.
4. Delegated work returns its evidence schema. The primary thin-checks every result, deep-reviews only on a trigger, and renews user approval only when scope, risk, or cost materially changes.

## Delegation gate

- The primary applies this gate; the user does not need to request a sub-agent explicitly. Ask the user only when routing materially changes scope, risk, or cost.
- Default to primary-direct for small, sequential, context-heavy, or already-resolved work; these cases need no checkpoint or bookkeeping.
- For a task with plausible delegation benefit, evaluate the gate once after scope is clear. Do not reopen this file merely because a new turn or plan step begins; re-read only under the `AGENTS.md` session-policy conditions.
- Task category alone—including contract, DB, security, finance, migration, or external-system work—never forces a spawn. Delegate when one strong benefit or two moderate benefits apply and the role-specific criteria below are met.
- **Strong benefits:** clean independent parallelism or large or repetitive input that can become a small bounded digest.
- **Moderate benefits:** workload leverage greater than handoff plus acceptance cost; context isolation; or validation asymmetry. Context hygiene alone remains insufficient.
- Prefer primary-direct when the threshold is not met, or when work is small, sequential, context-heavy, already resolved by evidence, or no larger than handoff plus acceptance cost.
- Use `reader` only when the input is large, output has a small schema, and spot-checking is cheap: bulk sweeps, long-log/comment classification, repetitive comparison, or extraction. Exclude small reads, ambiguous design, root-cause diagnosis, and final security/finance judgment.
- Use `executor` only for an approved atomic implementation with clean ownership when the independent workload benefit exceeds handoff and acceptance cost; otherwise execute directly.
- Executor handoffs include objective, allowed scope/files, acceptance criteria, test, constraints, and unknowns. Executors return only `status / changed files / tests / deviations / unknowns`; store bulky logs as artifacts.
- Give agents only relevant paths, contracts, and artifacts; never the full conversation or a full-repo reread requirement.

## Spawn runtime

- Do not read spawn mechanics while deciding whether to delegate. Immediately before the first actual spawn or model-worker fallback in a session, read and apply `SUB_AGENTS_RUNTIME.md`; reuse it from context thereafter and re-read only after file change or relevant context loss.

## Acceptance and report

- **Thin, always:** verify status, changed-file/diff summary, test command/result, and conclusion-changing evidence only.
- **Deep triggers:** API/contract, DB/migration, security/finance, cross-repo change, failed/flaky tests, plan deviation, broad diff, or unresolved unknowns. Do not reread or rerun without cause; mark unverifiable claims `[UNKNOWN: {file/interface} not confirmed]`.
- Judge profitability/context hygiene practically, not as exact counterfactual tokens: `profitability = profitable | marginal | not profitable`; `context hygiene = cleaner | neutral | worse`.
- Report sub-agent details only when one is spawned, delegation fails or degrades, or the user asks. When delegated: `spawned` (role + model + task) / `why` / `profitability` / `context hygiene` / `basis` / `deviations`.
