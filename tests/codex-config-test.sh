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

test_empty_install_verify_uninstall
test_backup_restore
test_incremental_restore_preserves_unchanged_links
test_rollback_after_link_failure
printf '%s\n' 'PASS: portable Codex config installer integration tests'
