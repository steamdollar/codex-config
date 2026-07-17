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
with (root / "config.shared.toml").open("rb") as f:
    config = tomllib.load(f)

expected_config = {
    "model": "gpt-5.6-sol",
    "model_reasoning_effort": "high",
}
for key, value in expected_config.items():
    if config.get(key) != value:
        raise SystemExit(f"config.shared.toml {key}: expected {value!r}, got {config.get(key)!r}")

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
for wait_contract in (
    "`Wait timed out` means only that the child did not finish within that wait call",
    "must never be reported as agent failure",
    "Never call `interrupt_agent` solely because elapsed time or repeated wait calls seem long",
    "Do not invent an implicit sub-agent deadline",
):
    if wait_contract not in sub_agents:
        raise SystemExit(f"SUB_AGENTS.md missing wait/interrupt contract: {wait_contract}")
for attestation_contract in (
    "wait for the child to complete, locate its trace by `parent_thread_id` and canonical `agent_path`",
    "extract only those attestation records before reporting degradation",
    "Treat `agent_nickname` as a runtime label, not configured identity",
    "Report the attested role, model, and canonical task path",
):
    if attestation_contract not in sub_agents:
        raise SystemExit(f"SUB_AGENTS.md missing attestation contract: {attestation_contract}")
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
  ! rg -q '^\[projects\.' "$repo_root/config.shared.toml" || fail "shared config contains machine-local project trust"
}

test_config_sync() {
  local work="$tmp_root/sync-repo"
  cp -a -- "$repo_root" "$work"
  rm -f -- "$work/config.toml"
  "$work/scripts/sync-config.py" --dry-run >/dev/null
  [[ ! -e "$work/config.toml" ]] || fail "sync dry-run wrote config"
  "$work/scripts/sync-config.py" >/dev/null
  [[ -f "$work/config.toml" ]] || fail "sync did not generate config"
  cp "$work/config.toml" "$work/generated"
  "$work/scripts/sync-config.py" >/dev/null
  cmp -s "$work/config.toml" "$work/generated" || fail "sync is not idempotent"
  printf '\n[projects."/tmp/한글\\\\path"]\ntrust_level = "trusted"\n' >> "$work/config.toml"
  "$work/scripts/sync-config.py" >/dev/null
  python3 - "$work/config.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as f:
    projects = tomllib.load(f)["projects"]
assert projects["/tmp/한글\\path"]["trust_level"] == "trusted"
PY
  printf '\n[projects."/bad"]\nextra = "no"\n' >> "$work/config.toml"
  cp "$work/config.toml" "$work/invalid-local"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "invalid project schema accepted"; fi
  cmp -s "$work/config.toml" "$work/invalid-local" || fail "invalid local config was partially modified"
  cp "$work/generated" "$work/config.toml"
  cp "$work/config.toml" "$work/before-shared-error"
  printf 'not = [\n' > "$work/config.shared.toml"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "malformed shared config accepted"; fi
  cmp -s "$work/config.toml" "$work/before-shared-error" || fail "malformed shared config partially modified local config"
  printf '\n[projects."/bad"]\nextra = "no"\n' > "$work/config.shared.toml"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "shared projects accepted"; fi
  cmp -s "$work/config.toml" "$work/before-shared-error" || fail "shared projects partially modified local config"
}

test_fresh_config_fallback() {
  local work="$tmp_root/fallback-repo" home="$tmp_root/fallback-home" backup="$tmp_root/fallback-backup"
  cp -a -- "$repo_root" "$work"
  rm -f -- "$work/config.toml"
  mkdir -p -- "$home"
  cp "$work/config.shared.toml" "$home/config.toml"
  printf '\n[projects."/tmp/기존\\\\path"]\ntrust_level = "trusted"\n' >> "$home/config.toml"
  "$work/scripts/codex-config.sh" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  [[ -L "$home/config.toml" && "$(readlink -- "$home/config.toml")" == "$work/config.toml" ]] || fail "fresh install did not link generated config"
  python3 - "$work/config.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert config["projects"]["/tmp/기존\\path"]["trust_level"] == "trusted"
PY

  local invalid_work="$tmp_root/fallback-invalid"
  cp -a -- "$repo_root" "$invalid_work"
  rm -f -- "$invalid_work/config.toml"
  printf '[projects."/bad"]\nextra = "no"\n' > "$tmp_root/invalid-fallback.toml"
  if "$invalid_work/scripts/sync-config.py" --fallback-config "$tmp_root/invalid-fallback.toml" >/dev/null 2>&1; then fail "invalid fallback schema accepted"; fi
  [[ ! -e "$invalid_work/config.toml" ]] || fail "invalid fallback partially wrote local config"
}

test_hook_activation() {
  local work="$tmp_root/hook-repo" foreign="$tmp_root/foreign-hook-repo"
  cp -a -- "$repo_root" "$work"
  [[ -x "$work/.githooks/post-merge" && -x "$work/.githooks/post-checkout" ]] || fail "versioned sync hooks are not executable"
  "$work/setup.sh" --codex-home "$tmp_root/hook-home" --apply >/dev/null
  [[ "$(git -C "$work" config --local --get core.hooksPath)" == .githooks ]] || fail "setup did not activate versioned hooks"
  cp -a -- "$repo_root" "$foreign"
  git -C "$foreign" config core.hooksPath .foreign-hooks
  if "$foreign/setup.sh" --codex-home "$tmp_root/foreign-hook-home" --dry-run >/dev/null 2>&1; then fail "foreign hooksPath accepted"; fi
}

test_shared_config_has_no_machine_project_paths
test_config_sync
test_fresh_config_fallback
test_hook_activation
test_empty_install_verify_uninstall
test_backup_restore
test_incremental_restore_preserves_unchanged_links
test_rollback_after_link_failure
printf '%s\n' 'PASS: portable Codex config installer integration tests'
