---
name: user-review-helper
description: Explain a completed code change through its outcome, runtime flow, and relevant files at the user's requested depth. Use for "리뷰 세션", "같이 리뷰", "리뷰 순서", or questions about what a completed change does. Do not use for bug-finding code review, PR feedback, or generic system documentation.
---

# Architecture-first review walkthrough

Use the progressive workflow below for an interactive review session. Honor an explicit request for a file list, code links, a direct code walkthrough, or a complete document in that response; add only the context needed to understand it. A teaching preference must not block the requested output.

## 1. Establish the real scope

- Treat the user-named change, task, commit, or file set as authoritative.
- Inspect the relevant diff and key surrounding code before explaining it. Start with `git status -s` and `git diff --stat`; for committed work, use the confirmed base or commit range.
- In multi-repo workspaces, inspect only the relevant child repositories.
- If the scope cannot be identified without choosing between materially different changes, ask one concise question.

## 2. Explain it like a planner

Start without code, file paths, or a layer-by-layer inventory. Explain:

- the problem or need,
- the observable behavior before and after,
- the single core change that makes the rest follow,
- any important non-goal or unchanged behavior.

Keep this proportional to the work. The user should understand what was accomplished before learning how it was built.

## 3. Build the developer mental model

Then explain only the architecture affected by this change:

- the participating layers or boundaries and their responsibilities,
- each independently acting runtime instance, such as browser UI, browser API or storage, server, database, cache, worker, queue, or external service,
- which component owns each important state or decision,
- the data and control flow as `source → action/data → destination`,
- changed interactions, responsibility transfers, and important instances deliberately absent from a path.

Use before/after framing when topology, ownership, or responsibility changed. Ground every claim in the inspected code; distinguish verified behavior from inference and name unresolved unknowns.

### Default teaching level

- Assume the user can read production code but may be new to the affected infrastructure, product domain, framework, or runtime. Do not infer domain familiarity from general engineering experience.
- Start with runtime instances and one plain-language responsibility or relationship at a time. Define a new term before using it to explain another new term.
- Prefer one concrete request, event, or data item traced end to end over a survey of abstractions. Split a broad instance such as an API server into smaller request flows when needed.
- Introduce implementation mechanisms only after the user understands the need they serve. For example, establish "the server needs a configuration ID and permission" before SSM, IAM, ARN, or task-role details.
- Use the user's named files as entry points, not an inspection boundary. Read enough surrounding code to explain the real runtime path.

### Visualize when it improves the model

Use the smallest useful visual when the explanation involves several interacting components, a changed sequence, or ownership across layers:

- a table for component-to-responsibility mappings,
- a flow or sequence diagram for runtime interactions,
- a before/after diagram for an ownership or topology change.

Prefer Mermaid where it renders reliably and compact ASCII otherwise. Keep instance boundaries explicit and label arrows with the action or data being transferred. Skip visualization for a genuinely simple change.

### Reset on comprehension failure

Treat explicit confusion such as "모르겠다", "하나도 이해가 안 된다", or an equivalent strong signal as evidence that the starting assumptions are wrong, not that the current explanation merely needs more detail.

1. Stop the walkthrough immediately; do not continue to the next file or concept.
2. State briefly which assumption or explanation level was mismatched without blaming the user.
3. Discard assumed familiarity and locate the earliest missing prerequisite.
4. Restart from the smallest useful relationship in plain language, with one concrete example or tightly mapped analogy and minimal jargon.
5. Ask for a comprehension check before restoring implementation terminology or continuing.
6. Preserve the newly successful abstraction level for the rest of the session. Use later questions and confirmations as calibration signals rather than interruptions.

## 4. Confirm understanding

For an interactive session without a requested direct output, pause after the planner and developer explanations and invite questions before entering files. If the user already requested code or a complete walkthrough, continue without another confirmation.

- In the default interactive introduction, defer code links until they help the user connect the model to the code; include them immediately when requested.
- If the user corrects the explanation, verify the correction against the code and repair the model first.
- If the user reports confusion, use the full comprehension reset above instead of paraphrasing the same explanation.
- A direct request to proceed into the code counts as confirmation.

## 5. Walk through the code

After confirmation, or when the user explicitly requests the code walkthrough:

- map the earlier architecture and runtime stages to absolute clickable file links,
- order files by runtime/data flow, not alphabetically or by Git output,
- start with the smallest critical path that explains the behavior,
- walk through one concrete request or data flow per chunk; split a runtime instance into sub-chunks when it owns several distinct flows,
- describe what changed in each file and which earlier responsibility it implements,
- include tests or wiring only when they define behavior or clarify the critical path.

End each substantial chunk with a one-sentence restatement in plain language and a clear next boundary. Do not advance past a newly introduced domain concept until the user's response indicates the model is holding.

Let the user choose where to go deeper. Re-read the selected code and relevant context before answering. If the user identifies a possible defect, diagnose it only when requested; modify code only after an explicit fix request and then return to the walkthrough position.

## Optional export

When the user explicitly requests a Markdown document, export the same planner → architecture → confirmation-ready → code-path material. This is an output option, not a separate workflow. Use links relative to the document and write to the user-named location or the established task/docs location; ask once only if the destination is materially ambiguous.

## Boundaries

- Do not perform a code review, hunt for defects, or issue a correctness verdict.
- Do not archive or analyze human PR feedback; use the PR-comment reporting workflow.
- Do not create a cold-start handoff.
- Do not substitute generic architecture lectures for the actual changed boundaries.
- Do not lead with diffs, files, or implementation details.
- Do not change code unless the user explicitly asks for a fix.
