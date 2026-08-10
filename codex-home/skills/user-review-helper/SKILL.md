---
name: user-review-helper
description: Help the user understand code the agent just wrote before reading it. Explain the outcome for a planner, then the architecture, layering, runtime instances, and data/control flow for a developer; visualize when useful, confirm understanding, and only then walk through the code. Use for "리뷰 세션", "같이 리뷰", "리뷰 순서", or questions about what a completed change does. Do not use for bug-finding code review, PR feedback, or generic system documentation.
---

# Architecture-first review walkthrough

Use one progressive workflow, not separate quick, session, or document modes. Scale the depth to the change, but never skip the high-level understanding gate merely because the user asks for a file list.

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

### Visualize when it improves the model

Use the smallest useful visual when the explanation involves several interacting components, a changed sequence, or ownership across layers:

- a table for component-to-responsibility mappings,
- a flow or sequence diagram for runtime interactions,
- a before/after diagram for an ownership or topology change.

Prefer Mermaid where it renders reliably and compact ASCII otherwise. Keep instance boundaries explicit and label arrows with the action or data being transferred. Skip visualization for a genuinely simple change.

## 4. Confirm understanding

Stop after the planner and developer explanations. Ask the user to confirm the mental model or raise questions before entering files.

- Do not include code links in this first response.
- If the user corrects the explanation, verify the correction against the code and repair the model first.
- A direct request to proceed into the code counts as confirmation.

## 5. Walk through the code

After confirmation:

- map the earlier architecture and runtime stages to absolute clickable file links,
- order files by runtime/data flow, not alphabetically or by Git output,
- start with the smallest critical path that explains the behavior,
- describe what changed in each file and which earlier responsibility it implements,
- include tests or wiring only when they define behavior or clarify the critical path.

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
