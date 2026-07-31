# Sub-Agent Spawn Runtime

Read this file only immediately before the first actual spawn or model-worker fallback in a session. The delegation decision remains governed by `SUB_AGENTS.md`.

## Replaceable model bindings

| role | current binding | operating contract |
|---|---|---|
| **Primary** | `gpt-5.6-sol`, high | user-facing coordination and direct work by default |
| **Reader** | `gpt-5.6-luna`, medium, read-only | bounded bulk evidence and structured digests |
| **Executor** | `gpt-5.6-luna`, xhigh, workspace-write | one approved atomic implementation step |

The role contracts above remain stable when model bindings change. A role TOML file declares the binding; configuration proves intent, not actual runtime selection.

## Native delegation, attestation, and fallback

- Native typed delegation uses `agents.spawn_agent`, not the reduced `collaboration.spawn_agent` interface. Pass the exact `agent_type` (`reader` or `executor`) and use `fork_turns = "none"`; a task label alone does not select or attest a role.
- Verify the selected role/model from runtime-returned metadata or the saved child trace's `session_meta` and `turn_context`. If spawn metadata is absent, wait for the child to complete, locate its trace by `parent_thread_id` and canonical `agent_path`, and extract only those attestation records before reporting degradation. If neither source attests it, never claim that role/model.
- Treat `agent_nickname` as a runtime label, not configured identity. Report the attested role, model, and canonical task path; include the nickname only as an optional label.
- Treat `wait_agent` as synchronization, not a worker deadline. `Wait timed out` means only that the child did not finish within that wait call; it is non-terminal and must never be reported as agent failure.
- Distinguish terminal outcomes from waiting explicitly: `completed` is success subject to acceptance; an explicit runtime/tool `failed` or `error` outcome is failure; `interrupted` means cancellation, not an intrinsic worker failure; `running` remains active regardless of elapsed time.
- Never call `interrupt_agent` solely because elapsed time or repeated wait calls seem long. Interrupt only on the user's request, an explicit terminal runtime error, a pre-agreed deadline, or a concrete safety/resource condition that requires stopping; report which condition applied.
- Do not invent an implicit sub-agent deadline. When no deadline was agreed, keep waiting or do independent primary work and collect the completion later. Use longer blocking waits for high-reasoning agents, and send progress updates without claiming that a silent child is stuck.
- Prefer the native custom-agent selector. If `reader` selection or model attestation is unavailable, use the legacy-compatible `$CODEX_HOME/bin/luna-reader-worker --cwd "$PWD" "{bounded task}"`; it starts a separate read-only Codex process pinned to `gpt-5.6-luna` and fails unless its saved transcript attests that model. Report it as `[MODEL-WORKER: gpt-5.6-luna]`, not as a native sub-agent.
- If a native role is missing, a spawn fails, or selection/model attestation is unavailable, report `[DEGRADED: {role} selection or attestation unavailable]`. For `reader`, use the model-worker fallback when available; otherwise apply the primary-direct gate. For `executor`, apply the primary-direct gate unless another approved route materially changes scope, risk, or cost.
- Use `agy` only when `command -v agy` succeeds and the user explicitly approves cross-provider execution, for reader unavailability, a valuable provider-diverse check, a huge independent batch, or required browser/Google integration. Send only the minimum required artifacts, never secrets or the full conversation. Run `agy models`, select the lowest-sufficient Flash model, then `agy --sandbox --print` with the reader digest contract. Never use it as a routine co-default.
- Report `[DEGRADED: reader unavailable -> Antigravity/{actual model}]` or `[CROSS-CHECK: Antigravity/{actual model}]`; on failure, use the direct-fallback rule.
- Depth is 1: children never spawn. Only one executor writes to a repo at once; reader is read-only.
