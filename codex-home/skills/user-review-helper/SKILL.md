---
name: user-review-helper
description: Explain a completed code change through its outcome, actor ownership, runtime instances, and relevant files, then export the complete walkthrough for VS Code Markdown Preview. Use for "완료된 변경 설명", "코드 워크스루", or "이 변경이 어떻게 동작해?". Not for finding bugs, evaluating correctness, or summarizing PR feedback.
---

# Completed change walkthrough

Explain the user's named change at their requested depth. Inspect its diff and the
necessary callers or dependencies before describing behavior. If scope is materially
ambiguous, resolve it before selecting unrelated changes.

- Start with the observable outcome and why the change was needed. Honor direct requests
  for code, links, a file list, or a complete document immediately.
- Trace one concrete request, event, or data item through the changed runtime instances.
  Identify who owns state and decisions and how data crosses the relevant boundaries.
- Make every flow step actor-first: name the acting instance before its action, then state
  the target and observable result. Keep actor names consistent across prose, tables, and
  diagrams so readers can immediately answer who did what.
- Describe participants as a system architect would. Distinguish a source construct such
  as a component, class, or handler from the runtime instance that executes it, such as a
  browser component instance, request-scoped handler invocation, server process, worker,
  session, or datastore. State its responsibility, owned state, lifetime, and process or
  network boundary when those facts affect the flow. Do not infer replica count, hosting,
  or deployment topology from code alone; mark unconfirmed architecture as unknown.
- Connect the flow to clickable source links in runtime order. Include tests or wiring
  when they explain behavior. Distinguish observed code from inference and unknowns.
- Assume engineering experience without assuming familiarity with this domain. Define
  unfamiliar terms in context. If the user is confused, revisit the earliest missing
  prerequisite with a concrete example rather than repeating the same explanation.
- When several actors participate, introduce them with a compact table covering runtime
  identity and responsibility before tracing the flow. In diagrams, use runtime actors as
  nodes and label edges with their actions or transferred data; do not substitute filenames
  or class names for actors. Skip visuals that merely repeat the prose.

Complete the requested explanation without comprehension gates. Pause between chunks
only when the user asks for an interactive, step-by-step session or when their answer
is necessary to proceed. Adapt to corrections without turning each concept into a quiz.

Every invocation must also export the complete walkthrough as a Markdown file optimized
for VS Code Markdown Preview. Put it in the task directory associated with the change,
normally the directory containing that task's `00_task.md`. Reuse an established,
task-owned walkthrough Markdown file when present; otherwise use the stable name
`walkthrough.md`. Honor a user-selected name only within that task directory. Do not
overwrite an unrelated file. If the task directory cannot be identified unambiguously,
resolve that location instead of falling back to the workspace root.

Keep the artifact portable with the task and make source navigation work from VS Code's
Markdown Preview. Identify repository files with repository-relative display paths and
relative Markdown link targets computed from the exported file's directory. Put line
numbers in `#L<number>` fragments where useful. Do not embed machine-specific workspace
paths, `file://` links, or `vscode://` deep links in the artifact. The in-tab answer may
use absolute link targets required by the client while preserving repository-relative
labels and the same destinations.

When a diagram materially helps, export it as a standalone SVG beside the Markdown and
reference it with a bounded HTML image element, for example:

```html
<a href="./runtime-flow.svg">
  <img src="./runtime-flow.svg" alt="Runtime flow" width="800">
</a>
```

Use runtime actors as SVG nodes and label edges with actions or transferred data. Keep
text legible at the embedded width, include an accessible title and description, and use
only inline SVG styling so the asset remains portable. Prefer a vertical layout when a
wide graph would be shrunk by Markdown Preview. Do not rely on Mermaid, external scripts,
remote assets, `<iframe>`, or document-level HTML/CSS. Create no SVG when a diagram would
not add material clarity. Produce standalone HTML only when the user explicitly requests
it in addition to the canonical Markdown walkthrough.

Compose the explanation once. The exported Markdown must preserve the in-tab content,
order, and links without omissions; only absolute-versus-relative local link targets and
the diagram representation may differ. Return the explanation in the tab with a clickable
link to the Markdown file, labeled with its repository-relative path. If Markdown or SVG
export fails, report the failure instead of claiming that it was created.

This skill explains completed work; it does not initiate a defect hunt, feedback archive,
handoff, or code change. Follow a new explicit request if the user changes that scope.
