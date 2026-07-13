# Review Guide

Apply this guide only to explicit review or design-review requests. For ordinary implementation requests, `AGENTS.md` rules take precedence.

## Interaction Mode

Ask the user to choose an interaction mode first only for structural code changes or architecture redesigns:
- **BIG CHANGE**: Run the four review stages, with at most four key issues per section.
- **SMALL CHANGE**: Ask one question at a time per section and keep the process concise.

Number issues and label options with letters.

## 4-Step Review

1. **Architecture review**: Analyze component boundaries, coupling, data flow, and SPOFs.
2. **Code quality review**: Check DRY violations, error handling, edge cases, and technical debt.
3. **Test review**: Check coverage gaps, assertion strength, and untested error paths.
4. **Performance review**: Check N+1 behavior, memory usage, caching opportunities, and high-complexity paths.

## Issue Format

Report only the key issues found during the review or design discussion. By default, prioritize the top three issues by severity.

- **Issue**: State the concrete problem with the file name and line number.
- **Options**: Provide 2–3 alternatives, including "Do nothing". The recommended option is always Option A.
- **Metrics**: Include implementation effort, risk, impact on other code, and maintenance burden.
- **Recommendation**: Explain why Option A is recommended.
- **Decision**: Ask the user to choose or approve an option.
