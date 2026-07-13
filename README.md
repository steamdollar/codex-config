# Portable Codex Config

Private source of truth for user-authored Codex guidance, custom agents,
rules, and custom skills. Live files under `$CODEX_HOME` are individual
symlinks; managed skills and runtime state stay local.

## Managed scope

- Root guidance: `AGENTS.md`, `SUB_AGENTS.md`, `REVIEW.md`, `DOMAIN_RULES.md`
- Machine configuration: `config.toml`
- Lifecycle hook: `hooks.json`, `hooks/context-budget.py`
- Custom-agent role bindings: `advisor.toml`, `luna-reader.toml`, `terra-executor.toml`
- Attested reader fallback (legacy filename): `bin/luna-reader-worker`
- Custom rule: `default.rules`
- Four user-authored skills listed in `manifest.tsv`

`config.toml` is managed as a symlink to the repository's machine profile. It
contains the selected model, plugins, and local project trust entries. Review
absolute project paths before using this profile on another machine.

Native custom agents use Codex's `MultiAgentV2` interface under the custom
`agents` namespace. This exposes the `agent_type` selector that the reserved
`collaboration` namespace hides. Runtime roles are `reader`, `advisor`, and
`executor`; their TOML files bind them to Luna, Sol, and Terra respectively.
The physical filenames `luna-reader.toml` and `terra-executor.toml` remain for
managed-symlink compatibility; runtime identity comes from each TOML `name`.
Role contracts are therefore stable when a model binding changes. Reload the
VS Code window after changing this configuration; new sessions should expose
`agents.spawn_agent` with `reader`, `advisor`, and `executor` role selection.

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

`setup.sh` applies the versioned `manifest.tsv`: it creates symlinks for the
root guidance and machine configuration files and also installs the lifecycle
hook, custom agent, rule, and skill links without replacing `.system` or
runtime state.
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

## Reader fallback

If the native `reader` selector is unavailable or cannot attest the selected
model, the legacy-named `bin/luna-reader-worker` starts a separate read-only
Codex process pinned to `gpt-5.6-luna`, then checks the saved session
transcript before returning the result. This preserves the current reader
binding but does not appear as a native sub-agent thread in the IDE UI.

```bash
"${CODEX_HOME:-$HOME/.codex}/bin/luna-reader-worker" \
  --cwd "$PWD" \
  "Read the supplied logs and return a five-line categorized summary."
```

## Context-budget warning

The `Stop` hook reads the newest recorded `last_token_usage.input_tokens` from
the session transcript. It warns once at 45% and once at 60% of the model
context window without blocking the turn.

Override both thresholds for a launched Codex session when absolute limits are
preferred:

```bash
CODEX_CONTEXT_BUDGET_SOFT_TOKENS=150000 \
CODEX_CONTEXT_BUDGET_HARD_TOKENS=200000 \
codex
```

One-shot markers are disposable runtime files outside the managed manifest.

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
