# Review Guide

Apply this guide to explicit review or design-review requests and to internal
acceptance reviews routed by `SUB_AGENTS.md`. For ordinary implementation
requests, `AGENTS.md` rules take precedence.

## Interaction Mode

Ask the user to choose an interaction mode first only for structural code changes or architecture redesigns:
- **BIG CHANGE**: Cover every relevant area in the selected review route, with at most four key issues per area.
- **SMALL CHANGE**: Ask one question at a time per section and keep the process concise.

Number issues and label options with letters.

## Internal Acceptance Review

When the primary spawns a read-only advisor to review completed implementation,
the primary—not the user—is the review client. Do not ask the user to choose an
interaction mode or decide findings.

- Use the primary's bounded review packet: objective and acceptance criteria,
  behavior/data-flow summary, diff base and changed files, tests and results,
  risk focus and invariants, and excluded or unrelated dirty files.
- Verify the actual diff and referenced tests. Stay within the packet scope and
  do not write files.
- Return blocking and non-blocking findings ordered by severity with `file:line`,
  test gaps, and residual risks. Return `LGTM` when there are no blocking
  findings.
- The primary adjudicates findings, performs final acceptance, and involves the
  user only when scope, risk, cost, or an unresolved trade-off materially
  changes.

## Review Routes

- **Code change**: Review architecture, code quality, tests, and performance where relevant.
- **Architecture or design**: Review boundaries, coupling, data flow, SPOFs, operational risk, and migration or rollback strategy.
- **Instruction, policy, or configuration**: Review precedence and scope, ambiguity or conflicts, runtime compatibility and enforceability, and context or maintenance cost.

## Issue Format

For user-facing review, report only the key issues found during the review or design discussion. By default, prioritize the top three issues by severity.

- **Issue**: State the concrete problem with the file name and line number.
- **Options**: Provide 2–3 realistic alternatives. Include "Do nothing" only when it is meaningful, and put a clearly recommended option first as Option A.
- **Metrics**: Include implementation effort, risk, impact on other code, and maintenance burden.
- **Recommendation**: Explain why Option A is recommended.
- **Decision**: Ask the user to choose or approve an option.
