---
name: agy-worker
description: Route fast, bounded AGY external-worker second opinions when an independent Gemini model-family view can improve an ask, bounded research, or independent code/plan/design review without consuming the Primary's Codex quota or context. Use only after the Primary confirms the authoritative spec directly; do not use AGY as the sole reviewer for security, data, migration, financial, or other high-risk decisions, and do not route implementation or generic staffer work automatically.
---

# AGY Worker

Use the installed `agy@agy-staff` plugin as a thin external-worker adapter. The
runtime companion expected by this skill is version `0.5.1`; the adapter
resolves that version from `codex plugin list` and passes arguments through:

```bash
node "${CODEX_HOME:-$HOME/.codex}/skills/agy-worker/scripts/agy-worker.mjs" <agy-command> [args...]
```

Choose only these automatic routes:

- `ask` → AGY `ask` for a fast, independent second opinion.
- bounded research → AGY `research` for context-light evidence gathering.
- independent code, plan, or design review → AGY `review`.

The native `researcher` and `reviewer` routes remain available and are not
replaced. `implement` is allowed only when the user explicitly asks for AGY
implementation; generic staffer work is never an automatic route. Do not use
vendor `$agy:*` skills as orchestration primitives. The vendor plugin is kept
disabled in Codex so those skills are not implicit candidates; the adapter uses
its installed companion directly.

The companion's full lifecycle (`start`, `wait`, `status`, `result`, and
`cancel`) needs unsandboxed/full access or an escalated permission. Never use a
sandbox workaround, `writable_roots`, or `setup --restricted`; without the
required authority report degraded/failure explicitly. For background jobs,
run the exact wait command printed by `start` once in the background per job;
if it exits `2`, rerun that same wait command. Every started job must be
reported. External-worker failures are not silently rerouted.

Keep prompts bounded and exclude credentials, secrets, and unnecessary file
contents. The Primary must inspect the authoritative spec directly, spot-check
decision-critical evidence, and synthesize AGY's `ask`, `research`, or `review`
output; never pass collected output verbatim to the final user and never repeat
an entire investigation without a concrete gap. This worker has no native attestation,
model metadata, agent UI, or ThreadId. High-risk security, data,
migration, and financial decisions require a native or Primary review in
addition to any AGY opinion. After an explicit AGY implementation, keep the
normal Primary diff and verification contract.
