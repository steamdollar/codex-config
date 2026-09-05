# Portable Codex Config

Private source of truth for user-authored Codex guidance, custom agents,
rules, and custom skills. Managed live entries under `$CODEX_HOME` are
symlinks; managed skills and runtime state stay local.

## Managed scope

- Root guidance: `AGENTS.md`
- Shared machine configuration: `config.shared.toml`; machine-local `config.toml`
- Lifecycle hooks: `hooks.json`, `hooks/context-budget.py`, `hooks/notify.py`, `hooks/remote-notify.py`
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

The primary default is GPT-6 Astra with `high` reasoning and the existing
service tier. Subagents retain the cheaper workload-specific bindings below;
this is not an all-Astra configuration. Astra consumes more of the shared
usage allowance than Sol, with actual usage depending on the task and context.
See [official model guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra)
and [usage limits](https://learn.chatgpt.com/docs/pricing).

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
routed for reviews spanning multiple boundaries or benefiting from independent
analysis; small document/config reviews stay with Primary. Role contracts live in `agents/*.toml` and are therefore stable when a
model binding changes. Restart or reload the local Codex client (desktop/CLI/IDE;
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
model's self-report alone do not prove which model actually ran.

## Quick setup on another machine

Clone the private repository under the target Codex home and run the root
setup entrypoint:

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
