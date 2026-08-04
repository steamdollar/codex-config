# Primary Orchestration and Sub-Agents

The Primary alone faces the user and owns discovery, decisions, approvals, delegation, and acceptance. Role behavior lives in each agent TOML; this file only governs routing.

## Durable roles

| role | owns | excludes |
|---|---|---|
| **Primary** | communication, discovery, plans and approvals, delegation or direct execution, acceptance, final decisions | routine work already delegated |
| **Reader (`reader`)** | bounded bulk reads, extraction, classification, concise summaries | writes, plan decisions, final diagnosis |
| **Researcher (`researcher`)** | bounded external/public research, source filtering, evidence-backed synthesis | writes, final decisions, private mutations, child spawn |
| **Executor (`executor`)** | one approved atomic change, targeted tests, concise evidence | scope changes, user decisions, further delegation |
| **Advisor (`advisor`, user-explicit only)** | bounded high-judgment planning, diagnosis, or review | writes, final decisions, automatic selection |

## Routing

- Keep Primary-direct limited to trivial, tightly conversation-dependent, or exact sequential work within the direct-read and output limits. Delegate when independent workload or context isolation exceeds those limits.
- Require `researcher` for external research involving search or discovery, multi-source comparison, source reliability, recency or conflict filtering, or synthesis. One exact authoritative-page verification may remain Primary-direct.
- Require `executor` before the first source or behavior-affecting config mutation when scope is approved, non-trivial, independently executable, and cleanly owned.
- If routing is ambiguous, delegate to the narrowest matching role. Keep phase decisions sticky: bounded follow-up work reuses the same agent unless scope or risk changes.
- Apply the cached gate after scope classification and before each action boundary; re-evaluate only for a scope or risk change or a newly independent phase.
- Automatic routing applies to `reader`, `researcher`, and `executor`. Use `advisor` only when the user explicitly requests it. Use `executor` only for one approved atomic change with clean ownership.
- Give agents bounded paths, contracts, acceptance criteria, and unknowns—not the full conversation or a full-repo reread request. Role-specific execution and return contracts come from their TOML files.

## Bulk-read override

Bulk is cumulative across an investigation phase. Delegate it to `reader` before the Primary consumes the raw input; do not evade this by splitting a sweep into small commands.

- **Primary-direct:** exact scope; at most three content-bearing files across two repos/layers; at most 160 lines or 12 KiB projected parent-visible output; likely resolved in one or two reads.
- **Moderate signal:** four to six files; three repos/layers; 161–400 lines or 12–32 KiB; or three unresolved Primary reads that imply more searching. Two moderate signals require `reader`.
- **Strong trigger:** seven or more files; four or more repos/layers; above 400 lines or 32 KiB; multi-stream logs; repo-wide inventory; or repetitive comparison. One strong trigger requires `reader`.
- Prefer projected output over counts when they conflict: four exact 20-line snippets may remain Primary-direct. Metadata-only orientation such as file names, `rg -l`, or concise status output does not count when below 80 lines.

Reader handoffs specify the question, bounded sources, selection criteria, exclusions, evidence format, and stop condition. The Primary owns final diagnosis and decisions. After the digest, spot-check at most two conclusion-bearing ranges and 80 total lines; delegate a bounded follow-up if more evidence is needed. Expand directly only for conflicting or safety-critical evidence and report the exception.

## Runtime and acceptance

- Use `agents.spawn_agent` with the exact `agent_type` (`reader`, `researcher`, `executor`, or user-requested `advisor`) and `fork_turns = "none"`.
- The runtime `agent_type` allowlist is exactly `reader`, `researcher`, `executor`, and explicit-only `advisor`; attest the selected role and model for every spawn.
- Verify the selected role/model from runtime metadata. If unavailable after completion, inspect only the child trace records identified by `parent_thread_id` and canonical `agent_path`. If still unattested, report `[DEGRADED: role/model not attested]` and do not claim the model.
- If selection or spawn fails, report degradation and return to the Primary-direct gate; do not silently substitute another worker or provider.
- Depth is 1: children never spawn. Only one executor writes to a repo at once.
- Thin-check every result: status, changed-file or evidence summary, tests, deviations, and conclusion-bearing evidence. Deep-check API/contract, DB/migration, security/finance, cross-repo changes, failures, broad diffs, or unresolved unknowns without duplicating the delegated sweep.
- Report sub-agent details only when one is spawned, delegation degrades, or the user asks; include role/model, why, and material deviations.
