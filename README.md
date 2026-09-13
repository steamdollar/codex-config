# Portable Codex Config

A reproducible, opinionated Codex setup for agent-assisted software development.
This repository versions the workflow around the model—not just prompts: task
routing, custom agent roles, context management, verification, hooks, rollback,
and machine setup are kept inspectable and portable.

The goal is bounded autonomy rather than maximum autonomy. The primary agent
owns scope, decisions, and final acceptance; specialized agents receive narrow
read, research, review, or execution contracts and return evidence for review.

## What this repository demonstrates

- **Bounded multi-agent delegation** — explicit `reader`, `researcher`, `reviewer`, and `executor` roles with depth-1 delegation and constrained ownership.
- **AGY external-worker lane** — bounded ask, research, and review requests can use an optional Gemini-family second opinion without replacing native Codex roles.
- **Context management** — bulk-output isolation, context-budget warnings, and a `coldstart` skill for compact session handoffs.
- **Verification discipline** — targeted checks, explicitly requested independent review, and shared local/remote validation instead of repeated broad test runs.
- **Portable developer tooling** — one-command setup, machine-local trust preservation, drift detection, backup, verification, and rollback.
- **Workflow customization** — user-authored skills and completion hooks that turn recurring development habits into versioned tooling.

This is my working configuration, not a generic recommended default. The
interesting part is the set of trade-offs and guardrails; anyone reusing it
should review those choices for their own environment.

## Safety model

`config.shared.toml` deliberately uses broad local tool permissions
(`:danger-full-access` with `approval_policy = "never"`) to remove repetitive
approval friction during trusted local development. Safety is therefore enforced
at the workflow boundary rather than by asking for confirmation on every tool
call: destructive or external-state changes, DB/system writes, credential
handling, scope expansion, and other material-risk operations are explicitly
gated by the repository guidance. These are behavioral instructions, not an OS
sandbox. A child role's read-only declaration does not guarantee isolation when
parent runtime permission overrides are reapplied.

Credentials, sessions, memories, logs, machine-local project/hook trust state,
and generated runtime databases are not versioned. The installer also refuses
unsafe manifest targets and foreign symlinks. Broad permissions are a deliberate
personal trade-off, not a recommendation to run unreviewed agents with equivalent
access.

## Managed scope

- Shared agent guidance: `codex-home/AGENTS.md` → live `AGENTS.md`
- Primary-only guidance: `codex-home/PRIMARY.md` → live `PRIMARY.md`
- Shared machine configuration: `config.shared.toml`; machine-local `config.toml`
- Lifecycle hooks: `hooks.json`, `hooks/context-budget.py`, `hooks/notify.py`, `hooks/remote-notify.py`
- Custom-agent role bindings: relative `config_file` entries for `reader.toml`, `executor.toml`, `researcher.toml`, `reviewer.toml`
- Custom rule: `default.rules`
- User-authored skills listed in `manifest.tsv`

`config.shared.toml` contains portable settings such as the selected model,
plugins, and service defaults. `config.toml` is ignored, remains the manifest
symlink source, and is rebuilt from the shared file while preserving its parsed
`[projects]` and `[hooks.state]` subtrees. This lets Codex persist project and
hook trust decisions automatically. Other machine-local keys are overwritten
by synchronization; malformed trust state makes synchronization fail before
the local file is changed.

The primary default is GPT-5.6 Sol with `high` reasoning and the existing
service tier. The explicitly requested reviewer/architect workload uses
GPT-6 Astra with `xhigh`; reader, researcher, and executor keep their existing
workload-specific bindings. Primary can also use Astra with the same global
guidance; model selection does not require a second copy of the prompt.

Project trust is machine-local, for example:

```toml
[projects."/home/you/work/project"]
trust_level = "trusted"
```

Hook trust is also machine-local and is written by Codex after review through
`/hooks` in the Codex CLI TUI; the IDE chat does not expose this command. Do not
copy or hand-author `trusted_hash` values; synchronization only preserves values
already recorded by Codex for the exact hook definition.

Run `./scripts/sync-config.py` after changing the shared profile. Versioned
Git post-merge and post-checkout hooks do this automatically once `setup.sh`
has configured `core.hooksPath=.githooks`; setup refuses to replace a different
existing hook path.

The same versioned hook directory includes `pre-push`, which runs
`scripts/check-codex-config.sh` before every push. That shared runner is also
used by GitHub Actions, so local and remote checks cannot drift. A failed check
blocks the push; `git push --no-verify` is the explicit emergency bypass.

Native custom agents use Codex's `MultiAgentV2` interface under the custom
`agents` namespace. This exposes the `agent_type` selector that the reserved
`collaboration` namespace hides. The repository-managed custom roles are
`reader`, `researcher`, `executor`, and `reviewer`; other custom or unmanaged
files under `~/.codex/agents`, as well as Codex built-in roles, are outside this
repository's managed scope. Reader and executor bind to Luna, researcher binds
to Terra, and reviewer binds to Astra with `xhigh` reasoning.
Runtime identity comes from each TOML `name`. The live `config.toml` symlink
uses one portable `agent-roles` directory symlink instead of individual
agent-file symlinks, which current Codex role loading rejects. `reviewer` is
used only for explicitly requested independent code/design reviews and architect
questions. It is not automatically added after implementation; ordinary review
requests stay with Primary. Role contracts live in `agents/*.toml`.
Restart or reload the local Codex client (desktop/CLI/IDE;
for example, reload the VS Code window) after changing this
configuration, then start a new session so
`agents.spawn_agent` exposes `reader`, `researcher`, `executor`, and `reviewer`
role selection. Explicit review analysis is defined by
`reviewer.toml` as a single-pass, risk-gated route with bounded evidence and no
recursive reviewer/executor loop.

Global guidance preserves the user's scope and prior authorization, delegates
bounded evidence gathering and implementation, and stops verification once the
required checks pass. Skills supply task-specific defaults; they do not override
an explicit request for direct code links, a complete answer, or already authorized
work. Runtime tool metadata establishes exposed role/model bindings; TOML and a
model's self-report alone do not prove which model actually ran. Missing metadata
is reported as unconfirmed and does not cancel delegation. Bounded Primary fallback
applies only when agent creation fails or the assigned role is unavailable.

`agy-worker` is an explicit-only external-worker adapter for bounded `ask`,
`research`, and independent code/plan/design `review`; it does not replace the
native `researcher` or `reviewer` routes. Invoke it when requesting AGY or a separate
model-family comparison; it is not selected for routine reviews. The adapter expects `agy@agy-staff`
runtime version `0.5.1`, discovers its exact cache path from `codex plugin list`,
and passes the companion's stdio and exit status through. The vendor plugin is
kept disabled so its `$agy:*` skills are not implicit routing candidates; only
the installed companion is used. For a fresh install, run:

```bash
codex plugin marketplace add https://github.com/keli-wen/agy-staff.git
codex plugin add agy@agy-staff
./setup.sh
```

For an existing install, refresh only when needed, then restore the managed
disabled state:

```bash
codex plugin marketplace upgrade agy-staff
codex plugin add agy@agy-staff
./setup.sh
```

Restart or reload Codex after installing or upgrading the skill/plugin. The
companion lifecycle requires unsandboxed/full access or escalation; this
adapter has no sandbox workaround and never runs `setup --restricted`. AGY is
an external worker without native attestation, model metadata, agent UI, or
ThreadId; Primary still checks authoritative specs and synthesizes evidence.

## Optional Ponytail session

Ponytail is disabled by default to avoid imposing its output and test style on
ordinary coding tasks. The global guidance retains reuse of existing patterns,
standard libraries, and native platform features. Its installed plugin is preserved;
opt into the vendor skills for a CLI session with:

```bash
codex -c 'plugins."ponytail@ponytail".enabled=true'
```

The managed `e2e-test` skill continues through already authorized phases and pauses
only for required user interaction or new authorization. Its former standalone
installation is adopted through the installer's existing drift backup path; preview
and use `--allow-drift` only for that known directory when migrating.

## Prompt strategy and routing

`codex-home/AGENTS.md` contains only shared scope, authorization, evidence, and
change-safety rules, plus conditional pointers. Before its first substantive task,
Primary reads `$CODEX_HOME/PRIMARY.md` (or `~/.codex/PRIMARY.md` when `CODEX_HOME`
is unset). That file holds delegation, exploration budgets, verification, and
user communication rules for both Sol and Astra. It is not reread every turn
when its contents are already in context.

Subagents follow their own role instructions and assigned scope; they do not load
`PRIMARY.md` or other roles as operating instructions. A file explicitly assigned
as a review target can still be read as task material. This is an instruction to
read conditionally, not automatic file expansion or a tool-enforced access rule.
The split reduces shared instructions received by subagents; it does not promise
a smaller total Primary context. Start a new session to avoid retaining the old
expanded global instructions, and keep `fork_turns="none"` for delegated work.

The new file uses the installer's existing exact-file mapping, backup, and
rollback behavior; no file is retired. Role instructions are loaded for the
assigned task. The Astra reviewer keeps its evidence and
read-only boundaries without a fixed layer-by-layer inspection itinerary.
This follows the [official prompting guidance](https://learn.chatgpt.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra)
on removing excessive recipes while retaining clear decision and completion boundaries.

There is no custom model-detection hook or duplicate model-specific global prompt.
The [native profile mechanism](https://learn.chatgpt.com/docs/config-file/config-advanced)
supports configuration layers selected at CLI startup; automatic prompt replacement
when `/model` changes is not documented. Consider a small model-specific supplement
only after repeated failures on comparable tasks show that the common contract is
insufficient. `model_instructions_file` replaces Codex's built-in base instructions;
it is not an additive AGENTS.md supplement ([configuration reference](https://learn.chatgpt.com/docs/config-file/config-sample)).

Routing is decided before substantive tool work. Direct external exploration has
a backstop of one search batch and one source retrieval per research question;
additional exploration goes to researcher. Count source URLs inside batched calls,
and do not reset the budget by changing tools, turns, or the wording of the question.
Primary still reads required decision documents, stating that exception; checking
agent evidence does not authorize fresh exploration or full-page refetches.
Skill selection does not assign the work to Primary. These examples are semantic
review cases, not proof of runtime compliance:

| Request or change in scope | Expected route |
| --- | --- |
| Read one known config key or make a small local wording fix | Primary |
| Compare model guides, versions, and official config references | Researcher for public sources; Primary for local config and decisions |
| Explicitly delegate a single URL or user-provided document under user/project instructions | Researcher accepts the assigned investigation |
| A simple lookup needs another search or source retrieval | Hand existing evidence and remaining questions to researcher before that call |
| Extract evidence from multiple sessions or large logs | Reader extracts; Primary diagnoses |
| Write/update tests or run test/build commands | Follow the project's assigned owner, scope, and timing |
| Validate codex-config changes | Primary runs the required checks once after all changes are complete |
| Implement a separate change with a clear delegation benefit | Executor; Primary checks the combined result |
| “Review this” / explicitly request an independent review or architect | Primary / reviewer, respectively |

Verification routing belongs in project instructions; there is no global duration
threshold or trial run to choose an owner. Without project-specific rules, use the
ordinary work-routing criteria. Delegation specifies minimal checks or no execution,
and who owns final validation. When the project assigns final validation to Primary,
subagents leave those checks for one run after all changes are complete. Report
omitted checks and reasons; the assigned owner still completes required validation.

Exploratory output defaults to a combined 4,000-token budget per tool batch,
including nested calls. Narrow the source before limiting output. A second
truncation in the same task routes local extraction to reader and public research
to researcher; known bulk work is delegated immediately. Use completion events or
wait tools instead of repeated short status checks; polling-only tools use at least
30-second intervals unless user input or time-sensitive control requires otherwise.

These are prompt-level budgets, not enforced counters. The existing context hook
reports completed-turn diagnostics. Official [hook coverage](https://learn.chatgpt.com/docs/hooks)
excludes hosted web tools from PreToolUse/PostToolUse, and the
[tool output configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
does not establish that its history token limit applies to hosted web output.
The global output setting and tool permissions are therefore unchanged.

For the next three comparable research tasks, observe additional Primary search
or source retrieval beyond the budget, Primary exploratory truncations, and
repeated empty status polls; the target for each is zero. Record required-document
and unavailable-role exceptions separately. These observations have not yet been
collected. Binding and installation tests verify configuration and deployment;
exact prompt-string assertions do not establish runtime routing compliance.

## Quick setup on another machine

Clone the repository under the target Codex home and run the root setup
entrypoint:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}"
git clone https://github.com/steamdollar/codex-config.git \
  "${CODEX_HOME:-$HOME/.codex}/codex-config"
cd "${CODEX_HOME:-$HOME/.codex}/codex-config"
./setup.sh
```

`setup.sh` first generates the local `config.toml`, then applies the versioned
`manifest.tsv`: it creates symlinks for the root guidance and shared
configuration files and also installs the lifecycle
hook, rule, and skill links without replacing `.system`, unmanaged custom
agents, or runtime state. Custom agents are reached through the portable
`agent-roles` directory symlink and relative bindings in the linked
`config.toml`.
Existing identical content is backed up before replacement; drift or foreign
symlinks stop setup.

To preview an existing machine without changing it:

```bash
./setup.sh --dry-run
```

A missing or different managed target is reported before setup changes it.

## Install

The lower-level installer remains available for explicit backup paths,
verification, and rollback.

Preview first:

```bash
./scripts/codex-config.sh install \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --dry-run
```

Apply only after reviewing the preview:

```bash
./scripts/codex-config.sh install \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --apply
```

If a managed live file intentionally differs from the repository version, add
`--allow-drift` to explicitly back it up and replace it:

```bash
./scripts/codex-config.sh install \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --allow-drift \
  --apply
```

The install prints its timestamped backup path. Keep that path for rollback.

## Verify

```bash
./scripts/codex-config.sh verify \
  --codex-home "${CODEX_HOME:-$HOME/.codex}"
```

After installing or changing hooks, open `/hooks` in Codex and review and trust
the hook definition. Restart Codex after changing hooks or skills so discovery
is refreshed.

## Context-budget warning

The `UserPromptSubmit` hook reads the newest recorded
`last_token_usage.input_tokens` from the session transcript. It warns once at
60% of the model context window without blocking the turn. This is the last
recorded input size, not a prediction of the next turn's total context.
It also scans backward for the latest completed turn and reports call counts,
large output, duplicate commands, and truncation as diagnostic signals. These
signals do not establish waste or require stopping an authorized task.

Override the threshold for a launched Codex session when an absolute limit is
preferred:

```bash
CODEX_CONTEXT_BUDGET_HARD_TOKENS=200000 \
codex
```

One-shot markers are disposable runtime files outside the managed manifest.

## Completion notifications

`Stop` runs the local desktop notifier and the optional remote notifier directly
from managed paths under `hooks/`. The remote hook sends only when a token is
available in `CODEX_REMOTE_NOTIFY_TOKEN` or the unmanaged `$CODEX_HOME/notify-token`.
It sends hostname and project basename with a completion notice; no transcript
is included. `CODEX_REMOTE_NOTIFY_URL` overrides the existing private-network
default. That default uses HTTP and relies on the trusted network transport;
use HTTPS for endpoints outside that protected network. An empty URL disables
remote delivery. Tests mock delivery and never send live notifications.

The installer now manages `hooks/remote-notify.py` with the same exact ownership,
drift refusal, backup and rollback rules as other files. Changing its hook command
requires reviewing the new definition in `/hooks`; setup does not grant trust.
For backups made before a manifest change, use the matching repository revision
when rolling back; the installer rejects a mismatched backup manifest.

## Tests

Run the isolated installer integration tests against temporary Codex homes:

```bash
python3 tests/context-budget-hook-test.py
bash tests/codex-config-test.sh
```

The tests cover threshold and one-shot behavior, bounded transcript reads,
notification wiring, dry-run/apply/verify/uninstall,
incremental and legacy backup restoration, and rollback after an injected link
failure.

## Uninstall or rollback

Preview restoration from an install backup:

```bash
./scripts/codex-config.sh uninstall \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --restore-backup "$CODEX_HOME/backups/portable-codex-config/<timestamp>" \
  --dry-run
```

Replace `--dry-run` with `--apply` after reviewing the target list. New backups
restore only entries changed by that install; legacy backups retain full-manifest
restore behavior. Without `--restore-backup`, uninstall removes only symlinks
that point to this clone.

## Safety boundary

The manifest intentionally excludes `.system`, plugin cache, credentials,
sessions, memories, logs, SQLite/state databases, and generated caches. The
installer refuses manifest paths outside the approved Codex-home mapping and
refuses foreign symlinks.
