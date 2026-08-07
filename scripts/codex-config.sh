#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
manifest="$repo_root/manifest.tsv"
config_source="$repo_root/config.toml"
config_sync="$repo_root/scripts/sync-config.py"

usage() {
  printf '%s\n' \
    "Usage:" \
    "  $0 install   [--codex-home PATH] [--backup-dir PATH] [--allow-drift] [--activate-hooks] --dry-run|--apply" \
    "  $0 verify    [--codex-home PATH]" \
    "  $0 uninstall [--codex-home PATH] [--restore-backup PATH] --dry-run|--apply"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

canonical_path() {
  python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(os.path.expanduser(sys.argv[1])))
PY
}

filesystem_id() {
  python3 - "$1" <<'PY'
import os
import sys

print(os.stat(sys.argv[1]).st_dev)
PY
}

move_into_place() {
  local source=$1 target=$2
  [[ ! -e "$target" && ! -L "$target" ]] || fail "target appeared during install: $target"
  mv "$source" "$target"
}

command_name=${1:-}
[[ -n "$command_name" ]] || { usage; exit 2; }
shift

codex_home=${CODEX_HOME:-$HOME/.codex}
backup_dir=""
restore_backup=""
execution_mode="dry-run"
mode_explicit=false
allow_drift=false
activate_hooks=false

while (($#)); do
  case "$1" in
    --codex-home)
      (($# >= 2)) || fail "--codex-home requires a path"
      codex_home=$2
      shift 2
      ;;
    --backup-dir)
      (($# >= 2)) || fail "--backup-dir requires a path"
      backup_dir=$2
      shift 2
      ;;
    --restore-backup)
      (($# >= 2)) || fail "--restore-backup requires a path"
      restore_backup=$2
      shift 2
      ;;
    --dry-run)
      execution_mode="dry-run"
      mode_explicit=true
      shift
      ;;
    --apply)
      execution_mode="apply"
      mode_explicit=true
      shift
      ;;
    --allow-drift)
      allow_drift=true
      shift
      ;;
    --activate-hooks)
      activate_hooks=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -f "$manifest" ]] || fail "manifest missing: $manifest"
[[ -x "$config_sync" ]] || fail "config sync missing or not executable: $config_sync"
codex_home=$(canonical_path "$codex_home")
[[ "$codex_home" = /* && "$codex_home" != / ]] || fail "unsafe CODEX_HOME: $codex_home"

legacy_reader_rel="agents/luna-reader.toml"
legacy_reader_source="$repo_root/codex-home/$legacy_reader_rel"
legacy_reader_target="$codex_home/$legacy_reader_rel"
legacy_reader_cleanup_required=false
legacy_reader_moved=false

declare -a kinds=()
declare -a sources=()
declare -a targets=()

load_manifest() {
  local kind source target policy source_abs
  while IFS=$'\t' read -r kind source target policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    [[ "$kind" == file || "$kind" == dir ]] || fail "invalid manifest type: $kind"
    [[ ("$source" == codex-home/* || "$source" == config.toml) && "$source" != *".."* ]] || fail "unsafe source: $source"
    [[ "$target" != /* && "$target" != *".."* ]] || fail "unsafe live target: $target"
    case "$target" in
      skills/.system|skills/.system/*|plugins|plugins/*|auth.json|sessions|sessions/*|memories|memories/*|log|log/*|sqlite|sqlite/*)
        fail "denied live target: $target"
        ;;
    esac
    [[ "$policy" == exact ]] || fail "invalid migration policy: $policy"
    source_abs="$repo_root/$source"
    if [[ "$kind" == file ]]; then
      if [[ "$source" == config.toml && ! -e "$source_abs" && "$command_name" == install && "$execution_mode" == dry-run ]]; then
        kinds+=("$kind")
        sources+=("$source_abs")
        targets+=("$target")
        continue
      fi
      [[ -f "$source_abs" && ! -L "$source_abs" ]] || fail "source file missing: $source_abs"
    else
      [[ -d "$source_abs" && ! -L "$source_abs" ]] || fail "source directory missing: $source_abs"
    fi
    kinds+=("$kind")
    sources+=("$source_abs")
    targets+=("$target")
  done < "$manifest"
  ((${#targets[@]} > 0)) || fail "manifest contains no entries"
}

activate_git_hooks() {
  local existing
  existing=$(git -C "$repo_root" config --local --get core.hooksPath || true)
  if [[ -n "$existing" && "$existing" != .githooks ]]; then
    fail "refusing to replace existing core.hooksPath: $existing"
  fi
  if [[ "$execution_mode" == dry-run ]]; then
    [[ -n "$existing" ]] && printf '%s\n' 'NOOP: core.hooksPath already .githooks' || printf '%s\n' 'SET core.hooksPath=.githooks'
    return
  fi
  if [[ -z "$existing" ]]; then
    git -C "$repo_root" config --local core.hooksPath .githooks
    printf '%s\n' 'SET core.hooksPath=.githooks'
  else
    printf '%s\n' 'NOOP: core.hooksPath already .githooks'
  fi
}

preflight_git_hooks() {
  local existing
  existing=$(git -C "$repo_root" config --local --get core.hooksPath || true)
  [[ -z "$existing" || "$existing" == .githooks ]] || fail "refusing to replace existing core.hooksPath: $existing"
}

same_link() {
  local link_path=$1 expected=$2
  [[ -L "$link_path" && "$(readlink "$link_path")" == "$expected" ]]
}

preflight_legacy_reader_migration() {
  if same_link "$legacy_reader_target" "$legacy_reader_source"; then
    legacy_reader_cleanup_required=true
    printf 'REMOVE legacy managed link %s\n' "$legacy_reader_target"
  elif [[ -L "$legacy_reader_target" ]]; then
    printf 'KEEP foreign legacy symlink %s -> %s\n' "$legacy_reader_target" "$(readlink "$legacy_reader_target")"
  elif [[ -e "$legacy_reader_target" ]]; then
    printf 'KEEP foreign legacy target %s\n' "$legacy_reader_target"
  fi
}

compare_exact() {
  local kind=$1 source=$2 target=$3
  if [[ "$kind" == file ]]; then
    cmp -s -- "$source" "$target"
  else
    diff -qr -- "$source" "$target" >/dev/null
  fi
}

preflight_install() {
  local i kind source rel target
  preflight_legacy_reader_migration
  for i in "${!targets[@]}"; do
    kind=${kinds[$i]}
    source=${sources[$i]}
    rel=${targets[$i]}
    target="$codex_home/$rel"

    if same_link "$target" "$source"; then
      printf 'OK link %s -> %s\n' "$target" "$source"
      continue
    fi
    if [[ "$rel" == config.toml && ! -e "$source" ]]; then
      printf 'CONFIG source will be generated: %s\n' "$source"
      continue
    fi
    [[ ! -L "$target" ]] || fail "foreign symlink: $target -> $(readlink "$target")"
    if [[ -e "$target" ]]; then
      if [[ "$kind" == file ]]; then
        [[ -f "$target" ]] || fail "type mismatch, expected file: $target"
      else
        [[ -d "$target" ]] || fail "type mismatch, expected directory: $target"
      fi
      if compare_exact "$kind" "$source" "$target"; then
        printf 'PARITY %s\n' "$target"
      elif [[ "$allow_drift" == true ]]; then
        printf 'DRIFT %s (will be backed up and replaced)\n' "$target"
      else
        fail "unexpected content drift: $target"
      fi
    else
      printf 'NEW link %s -> %s\n' "$target" "$source"
    fi
  done
}

check_config() {
  local live_config="$codex_home/config.toml"
  [[ -f "$live_config" ]] || { printf 'CONFIG missing: %s\n' "$live_config"; return 1; }
  cmp -s -- "$config_source" "$live_config" && {
    printf '%s\n' 'CONFIG managed source matches'
    return 0
  }
  printf 'CONFIG differs from managed source: %s\n' "$config_source"
  return 1
}

check_config_syntax() {
  python3 - "$config_source" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
print("CONFIG managed source is valid TOML")
PY
}

verify_install() {
  local require_config_match=${1:-true}
  local i source target failures=0
  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    target="$codex_home/${targets[$i]}"
    if same_link "$target" "$source"; then
      printf 'VERIFIED %s -> %s\n' "$target" "$source"
    else
      printf 'INVALID %s\n' "$target" >&2
      failures=$((failures + 1))
    fi
  done
  if ! check_config_syntax || ! check_config; then
    if [[ "$require_config_match" == true ]]; then
      failures=$((failures + 1))
    else
      printf '%s\n' 'WARN: live config differs from the managed source; symlinks are installed and config was not changed' >&2
    fi
  fi
  ((failures == 0)) || fail "$failures verification checks failed"
}

declare -a changed_targets=()
declare -a changed_had_original=()
active_backup=""

rollback_install() {
  local status=${1:-$?}
  trap - ERR INT TERM
  if ((status != 0)) && [[ -n "$active_backup" ]]; then
    printf 'ROLLBACK after failure, backup=%s\n' "$active_backup" >&2
    local index rel target original
    for ((index=${#changed_targets[@]} - 1; index >= 0; index--)); do
      rel=${changed_targets[$index]}
      target="$codex_home/$rel"
      original="$active_backup/original/$rel"
      rm -f -- "$target.codex-config.$$"
      [[ ! -L "$target" ]] || rm -- "$target"
      if [[ ${changed_had_original[$index]} == 1 && -e "$original" ]]; then
        mkdir -p -- "$(dirname -- "$target")"
        mv -- "$original" "$target"
      fi
    done
    if [[ "$legacy_reader_moved" == true ]]; then
      local legacy_original="$active_backup/original/$legacy_reader_rel"
      if same_link "$legacy_reader_target" "$legacy_reader_source"; then
        rm -- "$legacy_reader_target"
      fi
      if [[ ! -e "$legacy_reader_target" && ! -L "$legacy_reader_target" && -L "$legacy_original" ]]; then
        mkdir -p -- "$(dirname -- "$legacy_reader_target")"
        mv -- "$legacy_original" "$legacy_reader_target"
      elif [[ -e "$legacy_reader_target" || -L "$legacy_reader_target" ]]; then
        printf 'ROLLBACK preserved foreign legacy target %s\n' "$legacy_reader_target" >&2
      fi
    fi
  fi
  exit "$status"
}

install_apply() {
  local timestamp i source rel target original tmp had_original
  local changes_required=false
  if [[ "$legacy_reader_cleanup_required" == true ]]; then
    changes_required=true
  fi
  for i in "${!targets[@]}"; do
    if ! same_link "$codex_home/${targets[$i]}" "${sources[$i]}"; then
      changes_required=true
      break
    fi
  done
  if [[ "$changes_required" == false ]]; then
    printf '%s\n' 'NOOP: all managed links already point to this repository'
    return
  fi

  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  if [[ -z "$backup_dir" ]]; then
    backup_dir="$codex_home/backups/portable-codex-config/$timestamp"
  fi
  active_backup=$(canonical_path "$backup_dir")
  backup_dir=$active_backup
  [[ ! -e "$active_backup" ]] || fail "backup already exists: $active_backup"
  mkdir -p -- "$active_backup/original"
  [[ "$(filesystem_id "$codex_home")" == "$(filesystem_id "$active_backup")" ]] || fail "backup must be on the same filesystem as CODEX_HOME"
  cp -a -- "$manifest" "$active_backup/manifest.tsv"
  printf '%s\n' "$repo_root" > "$active_backup/repository-path"
  : > "$active_backup/changed-targets.tsv"
  trap 'rollback_install $?' ERR
  trap 'rollback_install 130' INT
  trap 'rollback_install 143' TERM

  if [[ "$legacy_reader_cleanup_required" == true ]]; then
    same_link "$legacy_reader_target" "$legacy_reader_source" \
      || fail "legacy symlink changed during install: $legacy_reader_target"
    local legacy_original="$active_backup/original/$legacy_reader_rel"
    mkdir -p -- "$(dirname -- "$legacy_original")"
    mv -- "$legacy_reader_target" "$legacy_original"
    legacy_reader_moved=true
    printf 'REMOVED legacy managed link %s\n' "$legacy_reader_target"
  fi

  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    rel=${targets[$i]}
    target="$codex_home/$rel"
    if same_link "$target" "$source"; then
      continue
    fi
    original="$active_backup/original/$rel"
    had_original=0
    [[ ! -e "$target" ]] || had_original=1
    changed_targets+=("$rel")
    changed_had_original+=("$had_original")
    printf '%s\t%s\n' "$rel" "$had_original" >> "$active_backup/changed-targets.tsv"
    mkdir -p -- "$(dirname -- "$target")"
    if ((had_original)); then
      mkdir -p -- "$(dirname -- "$original")"
      mv -- "$target" "$original"
    fi
    tmp="$target.codex-config.$$"
    ln -s -- "$source" "$tmp"
    move_into_place "$tmp" "$target"
    printf 'LINKED %s -> %s\n' "$target" "$source"
  done
  trap - ERR INT TERM
  active_backup=""
  printf 'BACKUP %s\n' "$backup_dir"
}

declare -a restore_targets=()
restore_incremental=false

restore_target_contains() {
  local candidate rel=$1
  ((${#restore_targets[@]})) || return 1
  for candidate in "${restore_targets[@]}"; do
    [[ "$candidate" == "$rel" ]] && return 0
  done
  return 1
}

load_restore_targets() {
  local rel had_original candidate found
  [[ -f "$restore_backup/changed-targets.tsv" ]] || return 0
  restore_incremental=true
  while IFS=$'\t' read -r rel had_original; do
    [[ -n "$rel" && "$rel" != /* && "$rel" != *".."* ]] || fail "invalid changed target in backup: $rel"
    [[ "$had_original" == 0 || "$had_original" == 1 ]] || fail "invalid changed target state in backup: $rel"
    restore_target_contains "$rel" && fail "duplicate changed target in backup: $rel"
    found=false
    for candidate in "${targets[@]}"; do
      if [[ "$candidate" == "$rel" ]]; then
        restore_targets+=("$rel")
        found=true
        break
      fi
    done
    [[ "$found" == true ]] || fail "backup changed target is not in current manifest: $rel"
  done < "$restore_backup/changed-targets.tsv"
}

selected_for_uninstall() {
  local rel=$1
  [[ -z "$restore_backup" || "$restore_incremental" == false ]] && return 0
  restore_target_contains "$rel"
}

uninstall_preflight() {
  local i source rel target
  if [[ -n "$restore_backup" ]]; then
    restore_backup=$(canonical_path "$restore_backup")
    [[ -d "$restore_backup/original" && -f "$restore_backup/manifest.tsv" ]] || fail "invalid backup: $restore_backup"
    cmp -s -- "$manifest" "$restore_backup/manifest.tsv" || fail "backup manifest differs from current manifest"
    load_restore_targets
    printf 'RESTORE backup %s\n' "$restore_backup"
  fi
  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    rel=${targets[$i]}
    selected_for_uninstall "$rel" || continue
    target="$codex_home/$rel"
    if [[ -L "$target" ]]; then
      same_link "$target" "$source" || fail "refusing foreign symlink: $target"
      printf 'REMOVE managed link %s\n' "$target"
    elif [[ -e "$target" ]]; then
      fail "refusing non-symlink managed target: $target"
    else
      printf 'ABSENT %s\n' "$target"
    fi
  done
}

uninstall_apply() {
  local i source rel target original
  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    rel=${targets[$i]}
    selected_for_uninstall "$rel" || continue
    target="$codex_home/$rel"
    if same_link "$target" "$source"; then
      rm -- "$target"
      printf 'REMOVED %s\n' "$target"
    fi
    if [[ -n "$restore_backup" ]]; then
      original="$restore_backup/original/$rel"
      if [[ -e "$original" ]]; then
        mkdir -p -- "$(dirname -- "$target")"
        cp -a -- "$original" "$target"
        printf 'RESTORED %s\n' "$target"
      fi
    fi
  done
}

if [[ "$command_name" == install && "$activate_hooks" == true ]]; then
  preflight_git_hooks
fi

if [[ "$command_name" == install ]]; then
  sync_args=(--fallback-config "$codex_home/config.toml")
  [[ "$execution_mode" == apply ]] || sync_args=(--dry-run "${sync_args[@]}")
  "$config_sync" "${sync_args[@]}"
fi

load_manifest

case "$command_name" in
  install)
    [[ -z "$restore_backup" ]] || fail "--restore-backup is valid only for uninstall"
    preflight_install
    if [[ "$execution_mode" == apply ]]; then
      install_apply
      verify_install false
    else
      printf '%s\n' 'DRY-RUN: no changes made'
    fi
    [[ "$activate_hooks" == false ]] || activate_git_hooks
    ;;
  verify)
    [[ "$activate_hooks" == false ]] || fail "verify does not accept --activate-hooks"
    [[ "$mode_explicit" == false ]] || fail "verify does not accept --dry-run or --apply"
    [[ -z "$backup_dir" && -z "$restore_backup" && "$allow_drift" == false ]] || fail "verify accepts only --codex-home"
    verify_install true
    ;;
  uninstall)
    [[ "$activate_hooks" == false ]] || fail "uninstall does not accept --activate-hooks"
    [[ -z "$backup_dir" ]] || fail "uninstall does not accept --backup-dir"
    [[ "$allow_drift" == false ]] || fail "uninstall does not accept --allow-drift"
    uninstall_preflight
    if [[ "$execution_mode" == apply ]]; then
      uninstall_apply
    else
      printf '%s\n' 'DRY-RUN: no changes made'
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
