# Review Guide

Apply this guide only to explicit review or design-review requests. For ordinary implementation requests, `AGENTS.md` rules take precedence.

## Interaction Mode

Ask the user to choose an interaction mode first only for structural code changes or architecture redesigns:
- **BIG CHANGE**: Cover every relevant area in the selected review route, with at most four key issues per area.
- **SMALL CHANGE**: Ask one question at a time per section and keep the process concise.

Number issues and label options with letters.

## Review Routes

- **Code change**: Review architecture, code quality, tests, and performance where relevant.
- **Architecture or design**: Review boundaries, coupling, data flow, SPOFs, operational risk, and migration or rollback strategy.
- **Instruction, policy, or configuration**: Review precedence and scope, ambiguity or conflicts, runtime compatibility and enforceability, and context or maintenance cost.

## Issue Format

Report only the key issues found during the review or design discussion. By default, prioritize the top three issues by severity.

- **Issue**: State the concrete problem with the file name and line number.
- **Options**: Provide 2–3 realistic alternatives. Include "Do nothing" only when it is meaningful, and put a clearly recommended option first as Option A.
- **Metrics**: Include implementation effort, risk, impact on other code, and maintenance burden.
- **Recommendation**: Explain why Option A is recommended.
- **Decision**: Ask the user to choose or approve an option.
