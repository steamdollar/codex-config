# Primary Orchestration and Sub-Agents

The Primary alone faces the user and owns discovery, decisions, approvals, delegation, and acceptance. Role behavior lives in each agent TOML; this file only governs routing.

## Durable roles

| role | owns | excludes |
|---|---|---|
| **Primary** | communication, discovery, plans and approvals, delegation or direct execution, acceptance, final decisions | routine work already delegated |
| **Reader (`reader`)** | bounded bulk reads, extraction, classification, concise summaries | writes, plan decisions, final diagnosis |
| **Executor (`executor`)** | one approved atomic change, targeted tests, concise evidence | scope changes, user decisions, further delegation |
| **Advisor (`advisor`, user-explicit only)** | bounded high-judgment planning, diagnosis, or review | writes, final decisions, automatic selection |

## Routing

- Default to Primary-direct for small, sequential, tightly conversation-dependent, or already-resolved work. Delegate only when independent workload or context isolation clearly exceeds handoff and acceptance cost.
- Apply the gate once after scope is clear. Re-evaluate only when scope changes or a later step introduces independent work or a bulk read.
- Automatic routing applies to `reader` and `executor`. Use `advisor` only when the user explicitly requests it. Use `executor` only for one approved atomic change with clean ownership.
- Give agents bounded paths, contracts, acceptance criteria, and unknowns—not the full conversation or a full-repo reread request. Role-specific execution and return contracts come from their TOML files.

## Bulk-read override

Bulk is cumulative across an investigation phase. Delegate it to `reader` before the Primary consumes the raw input; do not evade this by splitting a sweep into small commands.

- **Primary-direct:** exact scope; at most three content-bearing files across two repos/layers; at most 160 lines or 12 KiB projected parent-visible output; likely resolved in one or two reads.
- **Moderate signal:** four to six files; three repos/layers; 161–400 lines or 12–32 KiB; or three unresolved Primary reads that imply more searching. Two moderate signals require `reader`.
- **Strong trigger:** seven or more files; four or more repos/layers; above 400 lines or 32 KiB; multi-stream logs; repo-wide inventory; or repetitive comparison. One strong trigger requires `reader`.
- Prefer projected output over counts when they conflict: four exact 20-line snippets may remain Primary-direct. Metadata-only orientation such as file names, `rg -l`, or concise status output does not count when below 80 lines.

Reader handoffs specify the question, bounded sources, selection criteria, exclusions, evidence format, and stop condition. The Primary owns final diagnosis and decisions. After the digest, spot-check at most two conclusion-bearing ranges and 80 total lines; delegate a bounded follow-up if more evidence is needed. Expand directly only for conflicting or safety-critical evidence and report the exception.

## Runtime and acceptance

- Read `SUB_AGENTS_RUNTIME.md` only immediately before the first spawn in a session; reuse it until it changes or relevant context is lost.
- Thin-check every result: status, changed-file or evidence summary, tests, deviations, and conclusion-bearing evidence. Deep-check API/contract, DB/migration, security/finance, cross-repo changes, failures, broad diffs, or unresolved unknowns without duplicating the delegated sweep.
- Report sub-agent details only when one is spawned, delegation degrades, or the user asks; include role/model, why, and material deviations.
