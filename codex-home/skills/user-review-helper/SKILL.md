---
name: user-review-helper
description: Explain a completed code change through its outcome, runtime flow, and relevant files. Use for "완료된 변경 설명", "코드 워크스루", or "이 변경이 어떻게 동작해?". Not for finding bugs, evaluating correctness, or summarizing PR feedback.
---

# Completed change walkthrough

Explain the user's named change at their requested depth. Inspect its diff and the
necessary callers or dependencies before describing behavior. If scope is materially
ambiguous, resolve it before selecting unrelated changes.

- Start with the observable outcome and why the change was needed. Honor direct requests
  for code, links, a file list, or a complete document immediately.
- Trace one concrete request, event, or data item through the changed runtime instances.
  Identify who owns state and decisions and how data crosses the relevant boundaries.
- Connect the flow to clickable source links in runtime order. Include tests or wiring
  when they explain behavior. Distinguish observed code from inference and unknowns.
- Assume engineering experience without assuming familiarity with this domain. Define
  unfamiliar terms in context. If the user is confused, revisit the earliest missing
  prerequisite with a concrete example rather than repeating the same explanation.
- Use a small diagram or table when ownership or interactions need it. Skip visuals
  that merely repeat the prose.

Complete the requested explanation without comprehension gates. Pause between chunks
only when the user asks for an interactive, step-by-step session or when their answer
is necessary to proceed. Adapt to corrections without turning each concept into a quiz.

Export a document only when requested, using the chosen destination and relative links.
This skill explains completed work; it does not initiate a defect hunt, feedback archive,
handoff, or code change. Follow a new explicit request if the user changes that scope.
