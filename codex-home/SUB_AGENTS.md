# Primary Orchestration and Sub-Agents

Goal: **The primary agent alone faces the user and owns decisions.** It executes directly or delegates approved work through the profitability gate. Roles describe responsibilities; model bindings are replaceable implementation choices. Share task plans and repo-local artifacts, not full conversations or duplicate rereads.

## Durable roles

| role | owns | excludes |
|---|---|---|
| **Primary** | communication, discovery, plans and approvals, delegation or direct execution, acceptance, final decisions | routine work already delegated |
| **Reader (`reader`)** | bounded bulk reads, extraction, classification, concise summaries | writes, plan decisions, final diagnosis |
| **Advisor (`advisor`)** | bounded high-judgment planning, diagnosis, review, and tradeoff analysis | writes, final decisions, user communication |
| **Executor (`executor`)** | one approved atomic change, targeted tests, concise evidence | scope changes, user decisions, further delegation |

## Workflow

1. The primary agent discovers and owns the decision. Delegate to `reader` when large input can become a small, explicit digest and the delegation gate is satisfied.
2. Non-trivial implementation or policy/behavior changes require a primary-owned plan and acceptance criteria. An explicit user request to implement or change something approves work within the stated scope; the `AGENTS.md` approval gate and literal-wording exemption still apply.
3. Apply the advisor escalation gate before committing to a high-judgment diagnosis, design, or review. The advisor recommends; the primary decides.
4. Apply the delegation gate to each atomic approved step, then execute directly or delegate to `executor`.
5. Delegated work returns its evidence schema. The primary thin-checks every result, deep-reviews only on a trigger, and renews user approval only when scope, risk, or cost materially changes.

## Delegation and advisor gates

- The primary applies these gates; the user does not need to request a sub-agent explicitly. Ask the user only when routing materially changes scope, risk, or cost.
- Context hygiene alone is insufficient. Delegate by default when at least two material benefits apply—bulky-output isolation, independent parallelism, workload leverage, or validation asymmetry—and the role-specific criteria below are met.
- Prefer primary-direct when work is small, sequential, context-heavy, or no larger than handoff plus acceptance cost.
- Use `reader` only when the input is large, output has a small schema, and spot-checking is cheap: bulk sweeps, long-log/comment classification, repetitive comparison, or extraction. Exclude small reads, ambiguous design, root-cause diagnosis, and final security/finance judgment.
- Escalate to `advisor` immediately for DB/schema/state-machine/API-contract changes, destructive or external-system actions, security/finance judgment, KPI/query semantics, architecture or source-of-truth decisions, and migrations or rollback design. Otherwise escalate when at least two apply: multiple repos or layers, multiple plausible root causes, a failed targeted attempt, cross-component E2E/contracts, or a materially ambiguous plan. Do not use it for a small decision already resolved by local evidence.
- Executor handoffs include objective, allowed scope/files, acceptance criteria, test, constraints, and unknowns. Executors return only `status / changed files / tests / deviations / unknowns`; store bulky logs as artifacts.
- Give agents only relevant paths, contracts, and artifacts; never the full conversation or a full-repo reread requirement.

## Replaceable model bindings

| role | current binding | operating contract |
|---|---|---|
| **Primary** | `gpt-5.6-sol`, medium | user-facing coordination and direct work by default |
| **Reader** | `gpt-5.6-luna`, low, read-only | bounded bulk evidence and structured digests |
| **Advisor** | `gpt-5.6-sol`, high, read-only | high-judgment recommendation before the primary decides |
| **Executor** | `gpt-5.6-terra`, medium, workspace-write | one approved atomic implementation step |

The role contracts above remain stable when model bindings change. A role TOML file declares the binding; configuration proves intent, not actual runtime selection.

## Native delegation, attestation, and fallback

- Native typed delegation uses `agents.spawn_agent`, not the reduced `collaboration.spawn_agent` interface. Pass the exact `agent_type` (`reader`, `advisor`, or `executor`) and use `fork_turns = "none"`; a task label alone does not select or attest a role.
- Verify the selected role/model from runtime-returned metadata or the saved child trace's `session_meta` and `turn_context`. If neither attests it, never claim that role/model.
- Treat `wait_agent` as synchronization, not a worker deadline. `Wait timed out` means only that the child did not finish within that wait call; it is non-terminal and must never be reported as agent failure.
- Distinguish terminal outcomes from waiting explicitly: `completed` is success subject to acceptance; an explicit runtime/tool `failed` or `error` outcome is failure; `interrupted` means cancellation, not an intrinsic worker failure; `running` remains active regardless of elapsed time.
- Never call `interrupt_agent` solely because elapsed time or repeated wait calls seem long. Interrupt only on the user's request, an explicit terminal runtime error, a pre-agreed deadline, or a concrete safety/resource condition that requires stopping; report which condition applied.
- Do not invent an implicit sub-agent deadline. When no deadline was agreed, keep waiting or do independent primary work and collect the completion later. Use longer blocking waits for high-reasoning agents, and send progress updates without claiming that a silent child is stuck.
- Prefer the native custom-agent selector. If `reader` selection or model attestation is unavailable, use the legacy-compatible `$CODEX_HOME/bin/luna-reader-worker --cwd "$PWD" "{bounded task}"`; it starts a separate read-only Codex process pinned to `gpt-5.6-luna` and fails unless its saved transcript attests that model. Report it as `[MODEL-WORKER: gpt-5.6-luna]`, not as a native sub-agent.
- If a native role is missing, a spawn fails, or selection/model attestation is unavailable, report `[DEGRADED: {role} selection or attestation unavailable]`. For `reader`, use the model-worker fallback when available; otherwise apply the primary-direct gate. For `advisor` or `executor`, apply the primary-direct gate unless another approved route materially changes scope, risk, or cost.
- Use `agy` only when `command -v agy` succeeds and the user explicitly approves cross-provider execution, for reader unavailability, a valuable provider-diverse check, a huge independent batch, or required browser/Google integration. Send only the minimum required artifacts, never secrets or the full conversation. Run `agy models`, select the lowest-sufficient Flash model, then `agy --sandbox --print` with the reader digest contract. Never use it as a routine co-default.
- Report `[DEGRADED: reader unavailable -> Antigravity/{actual model}]` or `[CROSS-CHECK: Antigravity/{actual model}]`; on failure, use the direct-fallback rule.
- Depth is 1: children never spawn. Only one executor writes to a repo at once; reader and advisor are read-only.

## Acceptance and report

- **Thin, always:** verify status, changed-file/diff summary, test command/result, and conclusion-changing evidence only.
- **Deep triggers:** API/contract, DB/migration, security/finance, cross-repo change, failed/flaky tests, plan deviation, broad diff, or unresolved unknowns. Do not reread or rerun without cause; mark unverifiable claims `[UNKNOWN: {file/interface} not confirmed]`.
- Judge profitability/context hygiene practically, not as exact counterfactual tokens: `profitability = profitable | marginal | not profitable`; `context hygiene = cleaner | neutral | worse`.
- Report sub-agent details only when one is spawned, delegation fails or degrades, or the user asks. When delegated: `spawned` (role + model + task) / `why` / `profitability` / `context hygiene` / `basis` / `deviations`.
