# Portable Codex Config

Private source of truth for user-authored Codex guidance, custom agents,
rules, and custom skills. Live files under `$CODEX_HOME` are individual
symlinks; managed skills and runtime state stay local.

## Managed scope

- Root guidance: `AGENTS.md`, `SUB_AGENTS.md`, `REVIEW.md`, `DOMAIN_RULES.md`
- Lifecycle hook: `hooks.json`, `hooks/context-budget.py`
- Custom agents: `luna-reader.toml`, `terra-executor.toml`
- Custom rule: `default.rules`
- Six user-authored skills listed in `manifest.tsv`

`config.toml` is not managed as a symlink. `templates/config.portable.toml`
contains a secret-free portable reference; machine-local project trust and UI
state remain in the live config.

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
four root Markdown guidance files and also installs the lifecycle hook, custom
agent, rule, and skill links without replacing `.system` or runtime state.
Existing identical content is backed up before replacement; drift or foreign
symlinks stop setup.

For Clero machines, pass the local checkout through the environment:

```bash
CLERO_TOKKO_ROOT=/path/to/clero/tokko ./setup.sh
```

To preview an existing machine without changing it:

```bash
./setup.sh --dry-run
```

A missing or different live `config.toml` is reported but is never rewritten
by setup. Use `templates/config.portable.toml` as the manual merge reference.

## Install

The lower-level installer remains available for explicit backup paths,
verification, and rollback.

Preview first:

```bash
./scripts/codex-config.sh install \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --clero-root /path/to/clero/tokko \
  --dry-run
```

Apply only after reviewing the preview:

```bash
./scripts/codex-config.sh install \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --clero-root /path/to/clero/tokko \
  --apply
```

The install prints its timestamped backup path. Keep that path for rollback.

## Verify

```bash
./scripts/codex-config.sh verify \
  --codex-home "${CODEX_HOME:-$HOME/.codex}"
```

Restart Codex after installing or changing hooks or skills so discovery is refreshed.

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
incremental and legacy backup restoration, path-parameterized drift rejection,
and rollback after an injected link failure.

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
sessions, memories, logs, SQLite/state databases, generated caches, and live
`config.toml`. The installer refuses manifest paths outside the approved
Codex-home mapping and refuses foreign symlinks.
