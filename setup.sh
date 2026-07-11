#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
installer="$repo_root/scripts/codex-config.sh"

args=(
  install
  --codex-home "${CODEX_HOME:-$HOME/.codex}"
  --apply
)

# Explicit CLI arguments come last so callers can override defaults, including
# using --dry-run before applying changes on an existing machine.
exec "$installer" "${args[@]}" "$@"
