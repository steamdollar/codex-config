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
  ((${#targets[@]} == 15)) || fail "expected 15 manifest entries, found ${#targets[@]}"
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

compare_path_parameterized() {
  local source=$1 target=$2
  python3 - "$source" "$target" "$codex_home" "$clero_root" <<'PY'
import sys
from pathlib import Path

source_root, target_root = map(Path, sys.argv[1:3])
codex_home, clero_root = sys.argv[3:5]


def entries(root):
    result = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            raise SystemExit(1)
        relative = path.relative_to(root).as_posix()
        if path.is_file():
            result[relative] = ("file", path)
        elif path.is_dir():
            result[relative] = ("dir", path)
        else:
            raise SystemExit(1)
    return result


def normalized(path):
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data

    replacements = [
        ("${CODEX_HOME:-$HOME/.codex}", "<CODEX_HOME>"),
        ("$CODEX_HOME", "<CODEX_HOME>"),
        (codex_home, "<CODEX_HOME>"),
        ("$CLERO_TOKKO_ROOT", "<CLERO_ROOT>"),
        (clero_root, "<CLERO_ROOT>"),
    ]
    for original, replacement in replacements:
        if original:
            text = text.replace(original, replacement)
    return text.encode("utf-8")


source_entries = entries(source_root)
target_entries = entries(target_root)
if source_entries.keys() != target_entries.keys():
    raise SystemExit(1)
for relative, (source_kind, source_path) in source_entries.items():
    target_kind, target_path = target_entries[relative]
    if source_kind != target_kind:
        raise SystemExit(1)
    if source_kind == "file" and normalized(source_path) != normalized(target_path):
        raise SystemExit(1)
PY
}

preflight_install() {
  local i kind source rel target policy
  if [[ -n "$clero_root" ]]; then
    clero_root=$(realpath -e -- "$clero_root")
    [[ -d "$clero_root" ]] || fail "Clero root is not a directory: $clero_root"
  fi
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
        compare_path_parameterized "$source" "$target" || fail "unexpected path-sensitive content drift: $target"
        printf 'APPROVED PATH TRANSFORM %s\n' "$target"
      fi
    else
      printf 'NEW link %s -> %s\n' "$target" "$source"
    fi
  done

  if [[ -n "$clero_root" ]]; then
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
      rm -f -- "$target.codex-config.$$"
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
  : > "$active_backup/changed-targets.tsv"
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
    printf '%s\t%s\n' "$rel" "$had_original" >> "$active_backup/changed-targets.tsv"
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

declare -A restore_target_set=()
restore_incremental=false

load_restore_targets() {
  local rel had_original candidate found
  [[ -f "$restore_backup/changed-targets.tsv" ]] || return 0
  restore_incremental=true
  while IFS=$'\t' read -r rel had_original; do
    [[ -n "$rel" && "$rel" != /* && "$rel" != *".."* ]] || fail "invalid changed target in backup: $rel"
    [[ "$had_original" == 0 || "$had_original" == 1 ]] || fail "invalid changed target state in backup: $rel"
    [[ ! -v "restore_target_set[$rel]" ]] || fail "duplicate changed target in backup: $rel"
    found=false
    for candidate in "${targets[@]}"; do
      if [[ "$candidate" == "$rel" ]]; then
        restore_target_set["$rel"]=1
        found=true
        break
      fi
    done
    [[ "$found" == true ]] || fail "backup changed target is not in current manifest: $rel"
  done < "$restore_backup/changed-targets.tsv"
}

selected_for_uninstall() {
  local rel=$1
  [[ -z "$restore_backup" || "$restore_incremental" == false || -v "restore_target_set[$rel]" ]]
}

uninstall_preflight() {
  local i source rel target
  if [[ -n "$restore_backup" ]]; then
    restore_backup=$(realpath -e -- "$restore_backup")
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
  local i source rel target original clero_link recorded_clero
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
