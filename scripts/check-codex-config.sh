#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo_root"

for command_name in python3 rg; do
  command -v "$command_name" >/dev/null || {
    printf 'ERROR: required command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

for script in \
  setup.sh \
  scripts/codex-config.sh \
  scripts/check-codex-config.sh \
  tests/codex-config-test.sh \
  .githooks/post-checkout \
  .githooks/post-merge \
  .githooks/pre-push
do
  bash -n "$script"
done

python3 -m json.tool codex-home/hooks.json >/dev/null
python3 tests/context-budget-hook-test.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/agent-workflow-audit-test.py
bash tests/codex-config-test.sh
git --no-pager diff --check
