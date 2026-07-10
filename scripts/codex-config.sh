#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
manifest="$repo_root/manifest.tsv"
template="$repo_root/templates/config.portable.toml"

usage() {
  printf '%s\n' \
    "Usage:" \
    "  $0 install   [--codex-home PATH] [--clero-root PATH] [--backup-dir PATH] --dry-run|--apply" \
    "  $0 verify    [--codex-home PATH]" \
    "  $0 uninstall [--codex-home PATH] [--restore-backup PATH] --dry-run|--apply"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command_name=${1:-}
[[ -n "$command_name" ]] || { usage; exit 2; }
shift

codex_home=${CODEX_HOME:-$HOME/.codex}
clero_root=""
backup_dir=""
restore_backup=""
execution_mode="dry-run"
mode_explicit=false

while (($#)); do
  case "$1" in
    --codex-home)
      (($# >= 2)) || fail "--codex-home requires a path"
      codex_home=$2
      shift 2
      ;;
    --clero-root)
      (($# >= 2)) || fail "--clero-root requires a path"
      clero_root=$2
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
codex_home=$(realpath -m -- "$codex_home")
[[ "$codex_home" = /* && "$codex_home" != / ]] || fail "unsafe CODEX_HOME: $codex_home"

declare -a kinds=()
declare -a sources=()
declare -a targets=()
declare -a policies=()

load_manifest() {
  local kind source target policy source_abs
  while IFS=$'\t' read -r kind source target policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    [[ "$kind" == file || "$kind" == dir ]] || fail "invalid manifest type: $kind"
    [[ "$source" == codex-home/* && "$source" != *".."* ]] || fail "unsafe source: $source"
    [[ "$target" != /* && "$target" != *".."* ]] || fail "unsafe live target: $target"
    case "$target" in
      skills/.system|skills/.system/*|plugins|plugins/*|auth.json|sessions|sessions/*|memories|memories/*|log|log/*|sqlite|sqlite/*)
        fail "denied live target: $target"
        ;;
    esac
    [[ "$policy" == exact || "$policy" == path-parameterized ]] || fail "invalid migration policy: $policy"
    source_abs="$repo_root/$source"
    if [[ "$kind" == file ]]; then
      [[ -f "$source_abs" && ! -L "$source_abs" ]] || fail "source file missing: $source_abs"
    else
      [[ -d "$source_abs" && ! -L "$source_abs" ]] || fail "source directory missing: $source_abs"
    fi
    kinds+=("$kind")
    sources+=("$source_abs")
    targets+=("$target")
    policies+=("$policy")
  done < "$manifest"
  ((${#targets[@]} == 13)) || fail "expected 13 manifest entries, found ${#targets[@]}"
}

same_link() {
  local link_path=$1 expected=$2
  [[ -L "$link_path" && "$(readlink -- "$link_path")" == "$expected" ]]
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
  local i kind source rel target policy
  for i in "${!targets[@]}"; do
    kind=${kinds[$i]}
    source=${sources[$i]}
    rel=${targets[$i]}
    policy=${policies[$i]}
    target="$codex_home/$rel"

    if same_link "$target" "$source"; then
      printf 'OK link %s -> %s\n' "$target" "$source"
      continue
    fi
    [[ ! -L "$target" ]] || fail "foreign symlink: $target -> $(readlink -- "$target")"
    if [[ -e "$target" ]]; then
      if [[ "$kind" == file ]]; then
        [[ -f "$target" ]] || fail "type mismatch, expected file: $target"
      else
        [[ -d "$target" ]] || fail "type mismatch, expected directory: $target"
      fi
      if [[ "$policy" == exact ]]; then
        compare_exact "$kind" "$source" "$target" || fail "unexpected content drift: $target"
        printf 'PARITY %s\n' "$target"
      else
        [[ -f "$source/agents/openai.yaml" && -f "$target/agents/openai.yaml" ]] || fail "path-sensitive skill shape mismatch: $target"
        cmp -s -- "$source/agents/openai.yaml" "$target/agents/openai.yaml" || fail "unexpected non-path skill drift: $target/agents/openai.yaml"
        printf 'APPROVED PATH TRANSFORM %s\n' "$target"
      fi
    else
      printf 'NEW link %s -> %s\n' "$target" "$source"
    fi
  done

  if [[ -n "$clero_root" ]]; then
    clero_root=$(realpath -e -- "$clero_root")
    [[ -d "$clero_root" ]] || fail "Clero root is not a directory: $clero_root"
    local clero_link="$codex_home/local/roots/clero-tokko"
    if [[ -L "$clero_link" ]]; then
      [[ "$(readlink -- "$clero_link")" == "$clero_root" ]] || fail "foreign Clero root link: $clero_link"
    elif [[ -e "$clero_link" ]]; then
      fail "Clero root target already exists and is not a symlink: $clero_link"
    fi
    printf 'CLERO root %s -> %s\n' "$clero_link" "$clero_root"
  fi
}

check_config() {
  local live_config="$codex_home/config.toml"
  [[ -f "$live_config" ]] || { printf 'CONFIG missing: %s\n' "$live_config"; return 1; }
  python3 - "$template" "$live_config" <<'PY'
import sys
import tomllib

template_path, live_path = sys.argv[1:]
with open(template_path, "rb") as f:
    template = tomllib.load(f)
with open(live_path, "rb") as f:
    live = tomllib.load(f)

def leaves(value, prefix=()):
    for key, child in value.items():
        path = prefix + (key,)
        if isinstance(child, dict):
            yield from leaves(child, path)
        else:
            yield path, child

different = []
for path, expected in leaves(template):
    current = live
    for key in path:
        if not isinstance(current, dict) or key not in current:
            different.append(("missing", path, expected, None))
            break
        current = current[key]
    else:
        if current != expected:
            different.append(("different", path, expected, current))

if different:
    for status, path, expected, current in different:
        print(f"CONFIG {status}: {'.'.join(path)} expected={expected!r} current={current!r}")
    raise SystemExit(1)
print("CONFIG portable keys match")
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
  if ! check_config; then
    if [[ "$require_config_match" == true ]]; then
      failures=$((failures + 1))
    else
      printf '%s\n' 'WARN: live config differs from the portable template; symlinks are installed and config was not changed' >&2
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
      [[ ! -L "$target" ]] || rm -- "$target"
      if [[ ${changed_had_original[$index]} == 1 && -e "$original" ]]; then
        mkdir -p -- "$(dirname -- "$target")"
        mv -- "$original" "$target"
      fi
    done
  fi
  exit "$status"
}

install_apply() {
  local timestamp i source rel target original tmp had_original clero_link
  local changes_required=false
  for i in "${!targets[@]}"; do
    if ! same_link "$codex_home/${targets[$i]}" "${sources[$i]}"; then
      changes_required=true
      break
    fi
  done
  if [[ -n "$clero_root" ]] && ! same_link "$codex_home/local/roots/clero-tokko" "$clero_root"; then
    changes_required=true
  fi
  if [[ "$changes_required" == false ]]; then
    printf '%s\n' 'NOOP: all managed links already point to this repository'
    return
  fi

  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  if [[ -z "$backup_dir" ]]; then
    backup_dir="$codex_home/backups/portable-codex-config/$timestamp"
  fi
  active_backup=$(realpath -m -- "$backup_dir")
  backup_dir=$active_backup
  [[ ! -e "$active_backup" ]] || fail "backup already exists: $active_backup"
  mkdir -p -- "$active_backup/original"
  [[ "$(stat -c %d -- "$codex_home")" == "$(stat -c %d -- "$active_backup")" ]] || fail "backup must be on the same filesystem as CODEX_HOME"
  cp -a -- "$manifest" "$active_backup/manifest.tsv"
  printf '%s\n' "$repo_root" > "$active_backup/repository-path"
  trap 'rollback_install $?' ERR
  trap 'rollback_install 130' INT
  trap 'rollback_install 143' TERM

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
    mkdir -p -- "$(dirname -- "$target")"
    if ((had_original)); then
      mkdir -p -- "$(dirname -- "$original")"
      mv -- "$target" "$original"
    fi
    tmp="$target.codex-config.$$"
    ln -s -- "$source" "$tmp"
    mv -T -- "$tmp" "$target"
    printf 'LINKED %s -> %s\n' "$target" "$source"
  done

  if [[ -n "$clero_root" ]]; then
    clero_link="$codex_home/local/roots/clero-tokko"
    if [[ ! -L "$clero_link" ]]; then
      mkdir -p -- "$(dirname -- "$clero_link")"
      changed_targets+=("local/roots/clero-tokko")
      changed_had_original+=("0")
      ln -s -- "$clero_root" "$clero_link"
      printf '%s\n' "$clero_root" > "$active_backup/clero-root-created"
    fi
    printf 'LINKED %s -> %s\n' "$clero_link" "$clero_root"
  fi

  trap - ERR INT TERM
  active_backup=""
  printf 'BACKUP %s\n' "$backup_dir"
}

uninstall_preflight() {
  local i source target
  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    target="$codex_home/${targets[$i]}"
    if [[ -L "$target" ]]; then
      same_link "$target" "$source" || fail "refusing foreign symlink: $target"
      printf 'REMOVE managed link %s\n' "$target"
    elif [[ -e "$target" ]]; then
      fail "refusing non-symlink managed target: $target"
    else
      printf 'ABSENT %s\n' "$target"
    fi
  done
  if [[ -n "$restore_backup" ]]; then
    restore_backup=$(realpath -e -- "$restore_backup")
    [[ -d "$restore_backup/original" && -f "$restore_backup/manifest.tsv" ]] || fail "invalid backup: $restore_backup"
    cmp -s -- "$manifest" "$restore_backup/manifest.tsv" || fail "backup manifest differs from current manifest"
    printf 'RESTORE backup %s\n' "$restore_backup"
  fi
}

uninstall_apply() {
  local i source rel target original clero_link recorded_clero
  for i in "${!targets[@]}"; do
    source=${sources[$i]}
    rel=${targets[$i]}
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

  if [[ -n "$restore_backup" && -f "$restore_backup/clero-root-created" ]]; then
    recorded_clero=$(<"$restore_backup/clero-root-created")
    clero_link="$codex_home/local/roots/clero-tokko"
    if [[ -L "$clero_link" && "$(readlink -- "$clero_link")" == "$recorded_clero" ]]; then
      rm -- "$clero_link"
      printf 'REMOVED %s\n' "$clero_link"
    fi
  fi
}

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
    ;;
  verify)
    [[ "$mode_explicit" == false ]] || fail "verify does not accept --dry-run or --apply"
    [[ -z "$clero_root" && -z "$backup_dir" && -z "$restore_backup" ]] || fail "verify accepts only --codex-home"
    verify_install true
    ;;
  uninstall)
    [[ -z "$clero_root" && -z "$backup_dir" ]] || fail "uninstall does not accept --clero-root or --backup-dir"
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
