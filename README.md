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
- **Context management** — bulk-output isolation, context-budget warnings, and a `coldstart` skill for compact session handoffs.
- **Verification discipline** — targeted checks, risk-gated review, and shared local/remote validation instead of repeated broad test runs.
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
gated by the repository guidance.

Credentials, sessions, memories, logs, machine-local project/hook trust state,
and generated runtime databases are not versioned. The installer also refuses
unsafe manifest targets and foreign symlinks. Broad permissions are a deliberate
personal trade-off, not a recommendation to run unreviewed agents with equivalent
access.

## Managed scope

- Root guidance: `AGENTS.md`
- Shared machine configuration: `config.shared.toml`; machine-local `config.toml`
- Lifecycle hooks: `hooks.json`, `hooks/context-budget.py`, `hooks/notify.py`, and the repository-local remote notifier
- Custom-agent role bindings: relative `config_file` entries for `reader.toml`, `executor.toml`, `researcher.toml`, `reviewer.toml`
- Custom rule: `default.rules`
- Seven user-authored skills listed in `manifest.tsv`

`config.shared.toml` contains portable settings such as the selected model,
plugins, and service defaults. `config.toml` is ignored, remains the manifest
symlink source, and is rebuilt from the shared file while preserving its parsed
`[projects]` and `[hooks.state]` subtrees. This lets Codex persist project and
hook trust decisions automatically. Other machine-local keys are overwritten
by synchronization; malformed trust state makes synchronization fail before
the local file is changed.

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
to Terra, and reviewer binds to Sol.
Runtime identity comes from each TOML `name`. The live `config.toml` symlink
uses one portable `agent-roles` directory symlink instead of individual
agent-file symlinks, which current Codex role loading rejects. `reviewer` is
automatically routed for explicit code, design, or instruction/policy/config
review. Role contracts live in `agents/*.toml` and are therefore stable when a
model binding changes. Restart or reload the local Codex client (desktop/CLI/IDE;
for example, reload the VS Code window) after changing this
configuration, then start a new session so
`agents.spawn_agent` exposes `reader`, `researcher`, `executor`, and `reviewer`
role selection. Explicit review analysis is defined by
`reviewer.toml` as a single-pass, risk-gated route with bounded evidence and no
recursive reviewer/executor loop.

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
60% of the model context window without blocking the turn.

Override the threshold for a launched Codex session when an absolute limit is
preferred:

```bash
CODEX_CONTEXT_BUDGET_HARD_TOKENS=200000 \
codex
```

One-shot markers are disposable runtime files outside the managed manifest.

## Completion notification

Local desktop completion notification is handled by `hooks/notify.py`. The
optional remote notifier keeps both its endpoint and bearer token outside the
repository. Configure them with environment variables:

```bash
export CODEX_REMOTE_NOTIFY_URL="https://example.internal/notify"
export CODEX_REMOTE_NOTIFY_TOKEN="..."
```

or with machine-local files under `$CODEX_HOME`:

```text
$CODEX_HOME/notify-url
$CODEX_HOME/notify-token
```

If either value is missing, remote notification is skipped without blocking the
Codex stop hook.

## Tests

Run the isolated installer integration tests against temporary Codex homes:

```bash
python3 tests/context-budget-hook-test.py
bash tests/codex-config-test.sh
```

The tests cover threshold and one-shot behavior, dry-run/apply/verify/uninstall,
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
