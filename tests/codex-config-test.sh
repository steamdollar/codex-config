#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
installer="$repo_root/scripts/codex-config.sh"
manifest="$repo_root/manifest.tsv"
tmp_root=$(mktemp -d)
trap 'rm -rf -- "$tmp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_role_configuration() {
  python3 - "$repo_root" <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
with (root / "config.toml").open("rb") as f:
    config = tomllib.load(f)

expected_config = {
    "model": "gpt-5.6-terra",
    "model_reasoning_effort": "medium",
}
for key, value in expected_config.items():
    if config.get(key) != value:
        raise SystemExit(f"config.toml {key}: expected {value!r}, got {config.get(key)!r}")

expected_roles = {
    "luna-reader.toml": {
        "name": "reader",
        "model": "gpt-5.6-luna",
        "model_reasoning_effort": "low",
        "sandbox_mode": "read-only",
    },
    "terra-executor.toml": {
        "name": "executor",
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "workspace-write",
    },
    "advisor.toml": {
        "name": "advisor",
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
    },
}

seen_names = set()
for filename, expected in expected_roles.items():
    with (root / "codex-home" / "agents" / filename).open("rb") as f:
        role = tomllib.load(f)
    for key, value in expected.items():
        if role.get(key) != value:
            raise SystemExit(f"{filename} {key}: expected {value!r}, got {role.get(key)!r}")
    if role["name"] in seen_names:
        raise SystemExit(f"duplicate runtime role name: {role['name']}")
    seen_names.add(role["name"])

manifest = (root / "manifest.tsv").read_text()
if "codex-home/agents/advisor.toml\tagents/advisor.toml\texact" not in manifest:
    raise SystemExit("manifest does not install advisor.toml")

sub_agents = (root / "codex-home" / "SUB_AGENTS.md").read_text()
for selector in ("`reader`", "`advisor`", "`executor`"):
    if selector not in sub_agents:
        raise SystemExit(f"SUB_AGENTS.md missing native selector {selector}")
if 'fork_turns = "none"' not in sub_agents:
    raise SystemExit("SUB_AGENTS.md missing depth-isolated native delegation contract")
PY
}

new_home() {
  local home=$1
  mkdir -p -- "$home"
}

assert_managed_links_absent() {
  local home=$1 kind source rel policy
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    [[ ! -e "$home/$rel" && ! -L "$home/$rel" ]] || fail "managed target remains: $home/$rel"
  done < "$manifest"
}

assert_regular_parity() {
  local home=$1 kind source rel policy
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    [[ ! -L "$home/$rel" ]] || fail "expected restored regular target: $home/$rel"
    if [[ "$kind" == file ]]; then
      cmp -s -- "$repo_root/$source" "$home/$rel" || fail "restored file differs: $rel"
    else
      diff -qr -- "$repo_root/$source" "$home/$rel" >/dev/null || fail "restored directory differs: $rel"
    fi
  done < "$manifest"
}

test_empty_install_verify_uninstall() {
  local home="$tmp_root/empty-home" backup="$tmp_root/empty-backup"
  new_home "$home"

  "$installer" install --codex-home "$home" --dry-run >/dev/null
  assert_managed_links_absent "$home"

  "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  "$installer" verify --codex-home "$home" >/dev/null

  "$installer" uninstall --codex-home "$home" --dry-run >/dev/null
  [[ -L "$home/AGENTS.md" ]] || fail "dry-run removed a managed link"

  "$installer" uninstall --codex-home "$home" --apply >/dev/null
  assert_managed_links_absent "$home"
}

test_backup_restore() {
  local home="$tmp_root/restore-home" backup="$tmp_root/restore-backup"
  local kind source rel policy
  new_home "$home"

  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$home/$rel")"
    cp -a -- "$repo_root/$source" "$home/$rel"
  done < "$manifest"

  "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  rm -- "$backup/changed-targets.tsv"
  "$installer" uninstall --codex-home "$home" --restore-backup "$backup" --apply >/dev/null
  assert_regular_parity "$home"
}

test_incremental_restore_preserves_unchanged_links() {
  local home="$tmp_root/incremental-home" backup="$tmp_root/incremental-backup"
  local kind source rel policy
  new_home "$home"

  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    case "$rel" in
      hooks.json|hooks/context-budget.py)
        continue
        ;;
    esac
    mkdir -p -- "$(dirname -- "$home/$rel")"
    ln -s -- "$repo_root/$source" "$home/$rel"
  done < "$manifest"

  "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  [[ "$(wc -l < "$backup/changed-targets.tsv")" -eq 2 ]] || fail "incremental backup did not record exactly two changed targets"
  "$installer" uninstall --codex-home "$home" --restore-backup "$backup" --apply >/dev/null

  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    case "$rel" in
      hooks.json|hooks/context-budget.py)
        [[ ! -e "$home/$rel" && ! -L "$home/$rel" ]] || fail "incremental hook target remains: $rel"
        ;;
      *)
        [[ -L "$home/$rel" && "$(readlink -- "$home/$rel")" == "$repo_root/$source" ]] || fail "unchanged managed link was removed: $rel"
        ;;
    esac
  done < "$manifest"
}

test_rollback_after_link_failure() {
  local home="$tmp_root/rollback-home" backup="$tmp_root/rollback-backup"
  local fake_bin="$tmp_root/fake-bin" real_mv
  local kind source rel policy
  new_home "$home"
  home=$(cd -- "$home" && pwd -P)
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$home/$rel")"
    cp -a -- "$repo_root/$source" "$home/$rel"
  done < "$manifest"
  mkdir -p -- "$fake_bin"
  real_mv=$(command -v mv)
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'target=""; for arg do target=$arg; done\n'
    printf 'source=""; for arg do [[ "$arg" == *.codex-config.* ]] && source=$arg; done\n'
    printf 'if [[ "$target" == %q && -n "$source" ]]; then exit 97; fi\n' "$home/REVIEW.md"
    printf 'exec %q "$@"\n' "$real_mv"
  } > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >"$tmp_root/rollback.out" 2>"$tmp_root/rollback.err"; then
    fail "injected link failure unexpectedly succeeded"
  fi
  grep -q 'ROLLBACK after failure' "$tmp_root/rollback.err" || fail "rollback was not reported"
  assert_regular_parity "$home"
  [[ -z "$(find "$home" -name '*.codex-config.*' -print -quit)" ]] || fail "temporary link remained after rollback"
}

test_role_configuration

test_shared_config_has_no_machine_project_paths() {
  ! rg -q '^\[projects\.' "$repo_root/config.toml" || fail "shared config contains machine-local project trust"
}

test_shared_config_has_no_machine_project_paths
test_empty_install_verify_uninstall
test_backup_restore
test_incremental_restore_preserves_unchanged_links
test_rollback_after_link_failure
printf '%s\n' 'PASS: portable Codex config installer integration tests'
