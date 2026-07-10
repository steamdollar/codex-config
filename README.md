# Portable Codex Config

Private source of truth for user-authored Codex guidance, custom agents,
rules, and custom skills. Live files under `$CODEX_HOME` are individual
symlinks; managed skills and runtime state stay local.

## Managed scope

- Root guidance: `AGENTS.md`, `SUB_AGENTS.md`, `REVIEW.md`, `DOMAIN_RULES.md`
- Custom agents: `luna-reader.toml`, `terra-executor.toml`
- Custom rule: `default.rules`
- Six user-authored skills listed in `manifest.tsv`

`config.toml` is not managed as a symlink. `templates/config.portable.toml`
contains a secret-free portable reference; machine-local project trust and UI
state remain in the live config.

## Install

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

Restart Codex after installing or changing skills so discovery is refreshed.

## Uninstall or rollback

Preview restoration from an install backup:

```bash
./scripts/codex-config.sh uninstall \
  --codex-home "${CODEX_HOME:-$HOME/.codex}" \
  --restore-backup "$CODEX_HOME/backups/portable-codex-config/<timestamp>" \
  --dry-run
```

Replace `--dry-run` with `--apply` after reviewing the target list. Without
`--restore-backup`, uninstall removes only symlinks that point to this clone.

## Safety boundary

The manifest intentionally excludes `.system`, plugin cache, credentials,
sessions, memories, logs, SQLite/state databases, generated caches, and live
`config.toml`. The installer refuses manifest paths outside the approved
Codex-home mapping and refuses foreign symlinks.
