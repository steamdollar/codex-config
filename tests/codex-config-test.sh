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
if (root / "codex-home" / "REVIEW.md").exists():
    raise SystemExit("retired REVIEW.md source still exists")
if (root / "codex-home" / "agents" / "planner.toml").exists():
    raise SystemExit("retired planner source still exists")
if (root / "codex-home" / "agents" / "advisor.toml").exists():
    raise SystemExit("retired advisor source still exists")
terra_source = root / "codex-home" / "agents" / "terra-executor.toml"
if terra_source.exists() or terra_source.is_symlink():
    raise SystemExit("retired terra-executor source still exists")
with (root / "config.shared.toml").open("rb") as f:
    config = tomllib.load(f)

expected_config = {
    "model": "gpt-5.6-sol",
    "model_reasoning_effort": "high",
    "default_permissions": ":danger-full-access",
    "approval_policy": "never",
}
for key, value in expected_config.items():
    if config.get(key) != value:
        raise SystemExit(f"config.shared.toml {key}: expected {value!r}, got {config.get(key)!r}")

expected_roles = {
    "reader.toml": {
        "name": "reader",
        "model": "gpt-5.6-luna",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
    },
    "executor.toml": {
        "name": "executor",
        "model": "gpt-5.6-luna",
        "model_reasoning_effort": "xhigh",
        "sandbox_mode": "workspace-write",
    },
    "researcher.toml": {
        "name": "researcher",
        "model": "gpt-5.6-terra",
        "model_reasoning_effort": "medium",
        "sandbox_mode": "read-only",
    },
    "reviewer.toml": {
        "name": "reviewer",
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
    },
}

seen_names = set()
for filename, expected in expected_roles.items():
    with (root / "codex-home" / "agents" / filename).open("rb") as f:
        role = tomllib.load(f)
    if not str(role.get("description", "")).strip():
        raise SystemExit(f"{filename} description must be nonempty")
    if not str(role.get("developer_instructions", "")).strip():
        raise SystemExit(f"{filename} developer_instructions must be nonempty")
    for key, value in expected.items():
        if role.get(key) != value:
            raise SystemExit(f"{filename} {key}: expected {value!r}, got {role.get(key)!r}")
    if role["name"] in seen_names:
        raise SystemExit(f"duplicate runtime role name: {role['name']}")
    seen_names.add(role["name"])

manifest = (root / "manifest.tsv").read_text()
if "codex-home/REVIEW.md" in manifest or "\tREVIEW.md\t" in manifest:
    raise SystemExit("retired REVIEW.md is still managed")
if "codex-home/agents/advisor.toml\tagents/advisor.toml\texact" in manifest:
    raise SystemExit("retired advisor.toml is still managed")
if "terra-executor" in manifest:
    raise SystemExit("retired terra-executor.toml is still managed")
if "codex-home/agents/executor.toml\tagents/executor.toml\texact" not in manifest:
    raise SystemExit("manifest does not install executor.toml")
if "codex-home/agents/researcher.toml\tagents/researcher.toml\texact" not in manifest:
    raise SystemExit("manifest does not install researcher.toml")
if "codex-home/agents/reader.toml\tagents/reader.toml\texact" not in manifest:
    raise SystemExit("manifest does not install reader.toml")
if "codex-home/agents/reviewer.toml\tagents/reviewer.toml\texact" not in manifest:
    raise SystemExit("manifest does not install reviewer.toml")
if "codex-home/skills/agent-workflow-audit\tskills/agent-workflow-audit\texact" not in manifest:
    raise SystemExit("manifest does not install agent-workflow-audit")
if "codex-home/skills/agent-efficiency-retro\tskills/agent-efficiency-retro\texact" not in manifest:
    raise SystemExit("manifest does not install agent-efficiency-retro")
if "luna-reader" in manifest or "luna-reader" in (root / "README.md").read_text():
    raise SystemExit("deprecated luna-reader agent reference is still managed or documented")

agents = (root / "codex-home" / "AGENTS.md").read_text()
readme = (root / "README.md").read_text()
if "advisor.toml" in readme or "`advisor`" in readme:
    raise SystemExit("retired advisor role is still documented")
if "REVIEW.md" in agents or "REVIEW.md" in readme:
    raise SystemExit("retired REVIEW.md is still referenced by guidance")
if (root / "codex-home" / "SUB_AGENTS.md").exists():
    raise SystemExit("retired SUB_AGENTS.md source still exists")
if "SUB_AGENTS.md" in manifest or "SUB_AGENTS.md" in readme:
    raise SystemExit("retired SUB_AGENTS.md is still managed or documented")
if "terra-executor" in readme or "terra-executor" in agents:
    raise SystemExit("retired terra-executor is still documented")
if "Root guidance: `AGENTS.md`" not in readme:
    raise SystemExit("README does not identify AGENTS.md as the only root guidance")
if "Role contracts live in `agents/*.toml`" not in readme:
    raise SystemExit("README does not identify agent TOMLs as role contracts")
if "The repository-managed custom roles are" not in readme:
    raise SystemExit("README does not identify repository-managed custom roles")
if "Runtime roles are" in readme:
    raise SystemExit("README overstates repository roles as the only runtime roles")
if "Restart or reload the local Codex client (desktop/CLI/IDE" not in readme:
    raise SystemExit("README does not describe client reload and new-session behavior")
if "scope/dependency/risk가 단순하고 직접적인 작업은 별도 plan 없이 진행할 수 있다." not in agents:
    raise SystemExit("AGENTS.md does not define the no-plan simple-task default")
for contract in (
    "`reviewer`를 한 번 호출한다",
    "넓은 범위의 동작에 영향을 주는 변경만 자동으로 검토한다",
    "문서나 작고 제한적인 변경은 검토하지 않는다",
    "수정이 간단하며 되돌리기 쉬우면 Primary가 직접 수정한다",
    "먼저 사용자에게 묻는다",
    "수정 후 `reviewer`를 다시 호출하지 않는다",
    "Primary가 제한된 범위에서 직접 검토한다",
    "다른 agent로 대신하지 않는다",
):
    if contract not in agents:
        raise SystemExit(f"AGENTS.md orchestration contract missing: {contract}")
if "role 또는 model을 검증할 수 없으면" in agents:
    raise SystemExit("AGENTS.md retains generic attestation fallback duplicate")
for contract in (
    "scope·dependency·risk가 단순하고 대화 의존성이 높거나 문구·단일 문서·작은 설정만 바꾸는 bounded 작업은 Primary가 직접 수행한다.",
    "Primary는 작고 직접적인 읽기·실행과 알려진 단일 소스 확인을 직접 수행한다.",
    "`executor`는 여러 파일의 구현, 독립된 targeted test, 병렬화처럼 위임이 context·risk·wall-clock time 측면에서 실질적인 이점을 줄 때만 호출하며 모든 write의 필수 관문으로 사용하지 않는다.",
    "`reviewer`를 제외한 role의 spawn 또는 attestation이 불가하면 `[DEGRADED: role/model not attested]`를 보고하고 bounded Primary fallback을 사용하며 다른 role로 조용히 대체하지 않는다.",
    "전역 자동 라우팅은 위 표에 정의된",
    "`reader`·`researcher`·`reviewer`·`executor`만 사용하며",
    "Codex built-in·unmanaged custom·project-specific role은",
    "사용자가 명시적으로 요청하거나 적용되는 project/skill 지침이 명시적으로 요청할 때만 사용한다.",
    "위임이 이미 정당화된 작업 중 서로 독립적이고, 예상 wall-clock 절감이 setup·handoff·통합 비용보다 큰 currently-ready 작업만 runtime concurrency 한도 내에서 병렬 실행한다.",
    "Primary가 disjoint ownership을 명시하고 shared mutable target/state가 겹치지 않으면 write 작업도 병렬 실행할 수 있다. 같은 파일뿐 아니라 생성물·lockfile/manifest·migration/fixture·build output·외부 상태 같은 간접 shared state 충돌도 확인한다.",
    "결과가 다음 작업의 input·scope·판단을 좌우하거나 shared mutable state가 겹치면 작업 dependency graph 순서로 직렬화한다. 예상치 못한 overlap은 덮어쓰거나 되돌리지 말고 affected task를 재조정하며, material decision일 때만 사용자에게 묻는다.",
    "병렬 write가 끝나면 Primary가 combined diff와 필요한 integration coverage를 확인한다. Sub-agent가 성공한 동일 verification은 결과가 stale하거나 잘못됐다는 구체적 근거 없이 Primary가 재실행하지 않는다.",
    "scope와 risk가 유지되는 bounded follow-up에는 동일한 non-review agent를 재사용한다.",
):
    if contract not in agents:
        raise SystemExit(f"AGENTS.md thin orchestration contract missing: {contract}")
if "repository에 write하는 `executor`는 동시에 하나만 둔다" in agents:
    raise SystemExit("AGENTS.md retains executor-only write serialization")
PY

  python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
contracts = {
    "reader.toml": (
        "Primary agent가 위임한 범위가 제한된 로컬 읽기 작업만 맡는다.",
        "파일을 편집하거나 사용자에게 연락하거나",
        "status: complete, partial, or needs_scope",
    ),
    "researcher.toml": (
        "범위가 제한된 외부 또는 공개 조사만 맡는다.",
        "파일을 편집하거나 외부 시스템을 변경하거나",
        "status: complete, partial, or needs_scope",
    ),
    "executor.toml": (
        "승인된 원자적 구현 단계 정확히 하나만 맡는다.",
        "test code·fixture의 최소 변경은 Primary가 명시적으로 제외하지",
        "기존 coverage가 없거나 부족하면",
        "최소한의 targeted test를 작성·수정한다",
        "가장 좁은 final validation batch를 한 번만 실행한다",
        "Targeted test가 compile과 동작 경계를 함께 확인하면",
        "사용자에게 연락하거나 user-facing/final 결정을 내리거나 scope를 넓히거나",
        "`status`는 변경과 관련 검증이",
    ),
}
for filename, phrases in contracts.items():
    text = (root / "codex-home" / "agents" / filename).read_text()
    for phrase in phrases:
        if phrase not in text:
            raise SystemExit(f"{filename} contract missing: {phrase}")

executor = (root / "codex-home" / "agents" / "executor.toml").read_text()
for phrase in (
    "예상치 못한 overlap 또는 shared mutable state 충돌",
    "덮어쓰거나 되돌리지 않는다",
    "`status = partial`과 deviation",
    "material decision이 아닌 한",
    "실패 판단에 필요한 최소 failure lines",
):
    if phrase not in executor:
        raise SystemExit(f"executor overlap/output contract missing: {phrase}")
if "최대 120" in executor or "at most 120" in executor:
    raise SystemExit("executor retains an arbitrary failure-line cap")
PY

  python3 - "$repo_root/codex-home/agents/reviewer.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    reviewer = tomllib.load(f)
instructions = reviewer["developer_instructions"]
for phrase in (
    "범위가 제한된 변경 diff, 범위가 제한된 검토 대상",
    "인수 기준이 누락된 경우",
    "기존 아키텍처와 설계 패턴에 맞는지",
    "구현 패턴 적합성은 검토의 일부다",
    "coverage label이 `targeted`인지 `comprehensive`인지",
    "`needs_scope`",
    "`status` = `complete`, `partial`, 또는 `needs_scope`",
    "`outcome` = `findings` 또는 `no_findings`",
    "`proven issue` 또는 `credible risk`",
    "unknown은 결함이 아닌 잔여 위험이다",
    "`path:line`",
    "`remediation gate`인",
    "`auto-fix eligible` 또는 `user decision required`",
    "두 번째 또는 재귀적인 reviewer/executor 루프를",
):
    if phrase not in instructions:
        raise SystemExit(f"reviewer contract missing: {phrase}")
for retired in (
    "clarification required",
    "at most 3 findings",
    "exclusive return schema",
):
    if retired in instructions:
        raise SystemExit(f"reviewer contract retains retired behavior: {retired}")
if reviewer["model"] != "gpt-5.6-sol" or reviewer["model_reasoning_effort"] != "high" or reviewer["sandbox_mode"] != "read-only":
    raise SystemExit("reviewer runtime binding changed")
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

test_legacy_reader_migration() {
  local home="$tmp_root/legacy-reader-home" backup="$tmp_root/legacy-reader-backup"
  local old_target="$home/agents/luna-reader.toml"
  local old_source="$repo_root/codex-home/agents/luna-reader.toml"
  local new_target="$home/agents/reader.toml"
  new_home "$home"
  mkdir -p -- "$(dirname -- "$old_target")"
  ln -s -- "$old_source" "$old_target"

  "$installer" install --codex-home "$home" --backup-dir "$backup" --dry-run >/dev/null
  [[ -L "$old_target" ]] || fail "legacy link was removed during dry-run"
  "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  [[ ! -e "$old_target" && ! -L "$old_target" ]] || fail "legacy managed link remains after migration"
  [[ -L "$new_target" && "$(readlink "$new_target")" == "$repo_root/codex-home/agents/reader.toml" ]] || fail "reader link was not installed"

  local foreign_home="$tmp_root/foreign-legacy-reader-home"
  local foreign_target="$foreign_home/agents/luna-reader.toml"
  local foreign_source="$tmp_root/foreign-reader.toml"
  new_home "$foreign_home"
  mkdir -p -- "$(dirname -- "$foreign_target")"
  printf '%s\n' 'foreign' > "$foreign_source"
  ln -s -- "$foreign_source" "$foreign_target"
  "$installer" install --codex-home "$foreign_home" --apply >/dev/null
  [[ -L "$foreign_target" && "$(readlink "$foreign_target")" == "$foreign_source" ]] || fail "foreign legacy link was removed"
}

test_retired_review_migration() {
  local dry_home="$tmp_root/retired-review-dry-home"
  local dry_target="$dry_home/REVIEW.md"
  local owned_home="$tmp_root/retired-review-owned-home"
  local owned_target="$owned_home/REVIEW.md"
  local foreign_link_home="$tmp_root/retired-review-foreign-link-home"
  local foreign_link="$foreign_link_home/REVIEW.md"
  local foreign_source="$tmp_root/foreign-review.md"
  local regular_home="$tmp_root/retired-review-regular-home"
  local regular_target="$regular_home/REVIEW.md"
  local kind source rel policy

  new_home "$dry_home"
  ln -s -- "$repo_root/codex-home/REVIEW.md" "$dry_target"
  "$installer" install --codex-home "$dry_home" --dry-run >/dev/null
  [[ -L "$dry_target" && "$(readlink "$dry_target")" == "$repo_root/codex-home/REVIEW.md" ]] || fail "dry-run retired link was mutated"

  new_home "$owned_home"
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$owned_home/$rel")"
    ln -s -- "$repo_root/$source" "$owned_home/$rel"
  done < "$manifest"
  ln -s -- "$repo_root/codex-home/REVIEW.md" "$owned_target"
  "$installer" install --codex-home "$owned_home" --apply >/dev/null
  [[ ! -e "$owned_target" && ! -L "$owned_target" ]] || fail "owned retired link remains after apply"
  [[ ! -e "$owned_home/backups" && ! -L "$owned_home/backups" ]] || fail "retirement-only run created a backup directory"

  new_home "$foreign_link_home"
  printf '%s\n' foreign > "$foreign_source"
  ln -s -- "$foreign_source" "$foreign_link"
  "$installer" install --codex-home "$foreign_link_home" --apply >/dev/null
  [[ -L "$foreign_link" && "$(readlink "$foreign_link")" == "$foreign_source" ]] || fail "foreign retired symlink was removed"

  new_home "$regular_home"
  printf '%s\n' foreign > "$regular_target"
  "$installer" install --codex-home "$regular_home" --apply >/dev/null
  [[ -f "$regular_target" && ! -L "$regular_target" ]] || fail "regular retired target was removed"
  cmp -s "$regular_target" "$foreign_source" || fail "regular retired target changed"
}

test_retired_sub_agents_migration() {
  local dry_home="$tmp_root/retired-sub-agents-dry-home"
  local dry_target="$dry_home/SUB_AGENTS.md"
  local owned_home="$tmp_root/retired-sub-agents-owned-home"
  local owned_target="$owned_home/SUB_AGENTS.md"
  local foreign_link_home="$tmp_root/retired-sub-agents-foreign-link-home"
  local foreign_link="$foreign_link_home/SUB_AGENTS.md"
  local foreign_source="$tmp_root/foreign-sub-agents.md"
  local regular_home="$tmp_root/retired-sub-agents-regular-home"
  local regular_target="$regular_home/SUB_AGENTS.md"
  local kind source rel policy

  new_home "$dry_home"
  ln -s -- "$repo_root/codex-home/SUB_AGENTS.md" "$dry_target"
  "$installer" install --codex-home "$dry_home" --dry-run >/dev/null
  [[ -L "$dry_target" && "$(readlink "$dry_target")" == "$repo_root/codex-home/SUB_AGENTS.md" ]] || fail "dry-run retired SUB_AGENTS.md link was mutated"

  new_home "$owned_home"
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$owned_home/$rel")"
    ln -s -- "$repo_root/$source" "$owned_home/$rel"
  done < "$manifest"
  ln -s -- "$repo_root/codex-home/SUB_AGENTS.md" "$owned_target"
  "$installer" install --codex-home "$owned_home" --apply >/dev/null
  [[ ! -e "$owned_target" && ! -L "$owned_target" ]] || fail "owned retired SUB_AGENTS.md link remains after apply"
  [[ ! -e "$owned_home/backups" && ! -L "$owned_home/backups" ]] || fail "SUB_AGENTS.md retirement-only run created a backup directory"

  new_home "$foreign_link_home"
  printf '%s\n' foreign > "$foreign_source"
  ln -s -- "$foreign_source" "$foreign_link"
  "$installer" install --codex-home "$foreign_link_home" --apply >/dev/null
  [[ -L "$foreign_link" && "$(readlink "$foreign_link")" == "$foreign_source" ]] || fail "foreign retired SUB_AGENTS.md symlink was removed"

  new_home "$regular_home"
  printf '%s\n' foreign > "$regular_target"
  "$installer" install --codex-home "$regular_home" --apply >/dev/null
  [[ -f "$regular_target" && ! -L "$regular_target" ]] || fail "regular retired SUB_AGENTS.md target was removed"
  cmp -s "$regular_target" "$foreign_source" || fail "regular retired SUB_AGENTS.md target changed"
}

test_retired_planner_migration() {
  local dry_home="$tmp_root/retired-planner-dry-home"
  local dry_target="$dry_home/agents/planner.toml"
  local owned_home="$tmp_root/retired-planner-owned-home"
  local owned_target="$owned_home/agents/planner.toml"
  local foreign_link_home="$tmp_root/retired-planner-foreign-link-home"
  local foreign_link="$foreign_link_home/agents/planner.toml"
  local foreign_source="$tmp_root/foreign-planner.toml"
  local regular_home="$tmp_root/retired-planner-regular-home"
  local regular_target="$regular_home/agents/planner.toml"
  local kind source rel policy

  new_home "$dry_home"
  mkdir -p -- "$(dirname -- "$dry_target")"
  ln -s -- "$repo_root/codex-home/agents/planner.toml" "$dry_target"
  "$installer" install --codex-home "$dry_home" --dry-run >/dev/null
  [[ -L "$dry_target" && "$(readlink "$dry_target")" == "$repo_root/codex-home/agents/planner.toml" ]] || fail "dry-run retired planner link was mutated"

  new_home "$owned_home"
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$owned_home/$rel")"
    ln -s -- "$repo_root/$source" "$owned_home/$rel"
  done < "$manifest"
  mkdir -p -- "$(dirname -- "$owned_target")"
  ln -s -- "$repo_root/codex-home/agents/planner.toml" "$owned_target"
  "$installer" install --codex-home "$owned_home" --apply >/dev/null
  [[ ! -e "$owned_target" && ! -L "$owned_target" ]] || fail "owned retired planner link remains after apply"
  [[ ! -e "$owned_home/backups" && ! -L "$owned_home/backups" ]] || fail "planner retirement-only run created a backup directory"

  new_home "$foreign_link_home"
  printf '%s\n' foreign > "$foreign_source"
  mkdir -p -- "$(dirname -- "$foreign_link")"
  ln -s -- "$foreign_source" "$foreign_link"
  "$installer" install --codex-home "$foreign_link_home" --apply >/dev/null
  [[ -L "$foreign_link" && "$(readlink "$foreign_link")" == "$foreign_source" ]] || fail "foreign retired planner symlink was removed"

  new_home "$regular_home"
  mkdir -p -- "$(dirname -- "$regular_target")"
  printf '%s\n' foreign > "$regular_target"
  "$installer" install --codex-home "$regular_home" --apply >/dev/null
  [[ -f "$regular_target" && ! -L "$regular_target" ]] || fail "regular retired planner target was removed"
  cmp -s "$regular_target" "$foreign_source" || fail "regular retired planner target changed"
}

test_retired_advisor_migration() {
  local dry_home="$tmp_root/retired-advisor-dry-home"
  local dry_target="$dry_home/agents/advisor.toml"
  local owned_home="$tmp_root/retired-advisor-owned-home"
  local owned_target="$owned_home/agents/advisor.toml"
  local foreign_link_home="$tmp_root/retired-advisor-foreign-link-home"
  local foreign_link="$foreign_link_home/agents/advisor.toml"
  local foreign_source="$tmp_root/foreign-advisor.toml"
  local regular_home="$tmp_root/retired-advisor-regular-home"
  local regular_target="$regular_home/agents/advisor.toml"
  local kind source rel policy

  new_home "$dry_home"
  mkdir -p -- "$(dirname -- "$dry_target")"
  ln -s -- "$repo_root/codex-home/agents/advisor.toml" "$dry_target"
  "$installer" install --codex-home "$dry_home" --dry-run >/dev/null
  [[ -L "$dry_target" && "$(readlink "$dry_target")" == "$repo_root/codex-home/agents/advisor.toml" ]] || fail "dry-run retired advisor link was mutated"

  new_home "$owned_home"
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$owned_home/$rel")"
    ln -s -- "$repo_root/$source" "$owned_home/$rel"
  done < "$manifest"
  mkdir -p -- "$(dirname -- "$owned_target")"
  ln -s -- "$repo_root/codex-home/agents/advisor.toml" "$owned_target"
  "$installer" install --codex-home "$owned_home" --apply >/dev/null
  [[ ! -e "$owned_target" && ! -L "$owned_target" ]] || fail "owned retired advisor link remains after apply"
  [[ ! -e "$owned_home/backups" && ! -L "$owned_home/backups" ]] || fail "advisor retirement-only run created a backup directory"

  new_home "$foreign_link_home"
  printf '%s\n' foreign > "$foreign_source"
  mkdir -p -- "$(dirname -- "$foreign_link")"
  ln -s -- "$foreign_source" "$foreign_link"
  "$installer" install --codex-home "$foreign_link_home" --apply >/dev/null
  [[ -L "$foreign_link" && "$(readlink "$foreign_link")" == "$foreign_source" ]] || fail "foreign retired advisor symlink was removed"

  new_home "$regular_home"
  mkdir -p -- "$(dirname -- "$regular_target")"
  printf '%s\n' foreign > "$regular_target"
  "$installer" install --codex-home "$regular_home" --apply >/dev/null
  [[ -f "$regular_target" && ! -L "$regular_target" ]] || fail "regular retired advisor target was removed"
  cmp -s "$regular_target" "$foreign_source" || fail "regular retired advisor target changed"
}

test_retired_terra_executor_migration() {
  local dry_home="$tmp_root/retired-terra-executor-dry-home"
  local dry_target="$dry_home/agents/terra-executor.toml"
  local owned_home="$tmp_root/retired-terra-executor-owned-home"
  local owned_target="$owned_home/agents/terra-executor.toml"
  local foreign_link_home="$tmp_root/retired-terra-executor-foreign-link-home"
  local foreign_link="$foreign_link_home/agents/terra-executor.toml"
  local foreign_source="$tmp_root/foreign-terra-executor.toml"
  local regular_home="$tmp_root/retired-terra-executor-regular-home"
  local regular_target="$regular_home/agents/terra-executor.toml"
  local kind source rel policy

  new_home "$dry_home"
  mkdir -p -- "$(dirname -- "$dry_target")"
  ln -s -- "$repo_root/codex-home/agents/terra-executor.toml" "$dry_target"
  "$installer" install --codex-home "$dry_home" --dry-run >/dev/null
  [[ -L "$dry_target" && "$(readlink "$dry_target")" == "$repo_root/codex-home/agents/terra-executor.toml" ]] || fail "dry-run retired terra-executor link was mutated"

  new_home "$owned_home"
  while IFS=$'\t' read -r kind source rel policy; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    mkdir -p -- "$(dirname -- "$owned_home/$rel")"
    ln -s -- "$repo_root/$source" "$owned_home/$rel"
  done < "$manifest"
  mkdir -p -- "$(dirname -- "$owned_target")"
  ln -s -- "$repo_root/codex-home/agents/terra-executor.toml" "$owned_target"
  "$installer" install --codex-home "$owned_home" --apply >/dev/null
  [[ ! -e "$owned_target" && ! -L "$owned_target" ]] || fail "owned retired terra-executor link remains after apply"
  [[ ! -e "$owned_home/backups" && ! -L "$owned_home/backups" ]] || fail "terra-executor retirement-only run created a backup directory"

  new_home "$foreign_link_home"
  printf '%s\n' foreign > "$foreign_source"
  mkdir -p -- "$(dirname -- "$foreign_link")"
  ln -s -- "$foreign_source" "$foreign_link"
  "$installer" install --codex-home "$foreign_link_home" --apply >/dev/null
  [[ -L "$foreign_link" && "$(readlink "$foreign_link")" == "$foreign_source" ]] || fail "foreign retired terra-executor symlink was removed"

  new_home "$regular_home"
  mkdir -p -- "$(dirname -- "$regular_target")"
  printf '%s\n' foreign > "$regular_target"
  "$installer" install --codex-home "$regular_home" --apply >/dev/null
  [[ -f "$regular_target" && ! -L "$regular_target" ]] || fail "regular retired terra-executor target was removed"
  cmp -s "$regular_target" "$foreign_source" || fail "regular retired terra-executor target changed"
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
        [[ -L "$home/$rel" && "$(readlink "$home/$rel")" == "$repo_root/$source" ]] || fail "unchanged managed link was removed: $rel"
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
  mkdir -p -- "$home/agents"
  ln -s -- "$repo_root/codex-home/agents/luna-reader.toml" "$home/agents/luna-reader.toml"
  ln -s -- "$repo_root/codex-home/REVIEW.md" "$home/REVIEW.md"
  ln -s -- "$repo_root/codex-home/SUB_AGENTS.md" "$home/SUB_AGENTS.md"
  ln -s -- "$repo_root/codex-home/agents/planner.toml" "$home/agents/planner.toml"
  ln -s -- "$repo_root/codex-home/agents/advisor.toml" "$home/agents/advisor.toml"
  ln -s -- "$repo_root/codex-home/agents/terra-executor.toml" "$home/agents/terra-executor.toml"
  real_mv=$(command -v mv)
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'target=""; for arg do target=$arg; done\n'
    printf 'source=""; for arg do [[ "$arg" == *.codex-config.* ]] && source=$arg; done\n'
    printf 'if [[ "$target" == %q && -n "$source" ]]; then exit 97; fi\n' "$home/agents/reader.toml"
    printf 'exec %q "$@"\n' "$real_mv"
  } > "$fake_bin/mv"
  chmod +x "$fake_bin/mv"

  if PATH="$fake_bin:$PATH" "$installer" install --codex-home "$home" --backup-dir "$backup" --apply >"$tmp_root/rollback.out" 2>"$tmp_root/rollback.err"; then
    fail "injected link failure unexpectedly succeeded"
  fi
  grep -q 'ROLLBACK after failure' "$tmp_root/rollback.err" || fail "rollback was not reported"
  assert_regular_parity "$home"
  [[ -L "$home/agents/luna-reader.toml" && "$(readlink "$home/agents/luna-reader.toml")" == "$repo_root/codex-home/agents/luna-reader.toml" ]] || fail "legacy link was not restored after rollback"
  [[ -L "$home/REVIEW.md" && "$(readlink "$home/REVIEW.md")" == "$repo_root/codex-home/REVIEW.md" ]] || fail "retired REVIEW link was not restored after rollback"
  [[ -L "$home/SUB_AGENTS.md" && "$(readlink "$home/SUB_AGENTS.md")" == "$repo_root/codex-home/SUB_AGENTS.md" ]] || fail "retired SUB_AGENTS.md link was not restored after rollback"
  [[ -L "$home/agents/planner.toml" && "$(readlink "$home/agents/planner.toml")" == "$repo_root/codex-home/agents/planner.toml" ]] || fail "retired planner link was not restored after rollback"
  [[ -L "$home/agents/advisor.toml" && "$(readlink "$home/agents/advisor.toml")" == "$repo_root/codex-home/agents/advisor.toml" ]] || fail "retired advisor link was not restored after rollback"
  [[ -L "$home/agents/terra-executor.toml" && "$(readlink "$home/agents/terra-executor.toml")" == "$repo_root/codex-home/agents/terra-executor.toml" ]] || fail "retired terra-executor link was not restored after rollback"
  [[ -z "$(find "$home" -name '*.codex-config.*' -print -quit)" ]] || fail "temporary link remained after rollback"
}

test_role_configuration

test_shared_config_has_no_machine_project_paths() {
  ! rg -q '^\[projects\.' "$repo_root/config.shared.toml" || fail "shared config contains machine-local project trust"
  ! rg -q '^\[hooks\.state' "$repo_root/config.shared.toml" || fail "shared config contains machine-local hook trust"
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
  printf '\n[hooks.state."/tmp/hooks.json:stop:0:0"]\ntrusted_hash = "sha256:test-hook-hash"\nenabled = true\n' >> "$work/config.toml"
  "$work/scripts/sync-config.py" >/dev/null
  python3 - "$work/config.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
projects = config["projects"]
assert projects["/tmp/한글\\path"]["trust_level"] == "trusted"
assert config["hooks"]["state"]["/tmp/hooks.json:stop:0:0"]["trusted_hash"] == "sha256:test-hook-hash"
assert config["hooks"]["state"]["/tmp/hooks.json:stop:0:0"]["enabled"] is True
PY
  cp "$work/config.toml" "$work/preserved-machine-state"
  "$work/scripts/sync-config.py" >/dev/null
  cmp -s "$work/config.toml" "$work/preserved-machine-state" || fail "machine-local state sync is not idempotent"
  printf '\n[projects."/bad"]\nextra = "no"\n' >> "$work/config.toml"
  cp "$work/config.toml" "$work/invalid-local"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "invalid project schema accepted"; fi
  cmp -s "$work/config.toml" "$work/invalid-local" || fail "invalid local config was partially modified"
  cp "$work/generated" "$work/config.toml"
  printf '\n[hooks.state."/bad/hooks.json:stop:0:0"]\nextra = "no"\n' >> "$work/config.toml"
  cp "$work/config.toml" "$work/invalid-hook-state"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "invalid hook state schema accepted"; fi
  cmp -s "$work/config.toml" "$work/invalid-hook-state" || fail "invalid hook state partially modified local config"
  cp "$work/generated" "$work/config.toml"
  printf '\n[hooks.state."/bad/hooks.json:stop:0:0"]\ntrusted_hash = "sha256:bad-enabled"\nenabled = "yes"\n' >> "$work/config.toml"
  cp "$work/config.toml" "$work/invalid-hook-enabled"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "invalid hook enabled type accepted"; fi
  cmp -s "$work/config.toml" "$work/invalid-hook-enabled" || fail "invalid hook enabled type partially modified local config"
  cp "$work/generated" "$work/config.toml"
  cp "$work/config.toml" "$work/before-shared-error"
  printf 'not = [\n' > "$work/config.shared.toml"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "malformed shared config accepted"; fi
  cmp -s "$work/config.toml" "$work/before-shared-error" || fail "malformed shared config partially modified local config"
  printf '\n[projects."/bad"]\nextra = "no"\n' > "$work/config.shared.toml"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "shared projects accepted"; fi
  cmp -s "$work/config.toml" "$work/before-shared-error" || fail "shared projects partially modified local config"
  cp "$repo_root/config.shared.toml" "$work/config.shared.toml"
  printf '\n[hooks.state."/shared/hooks.json:stop:0:0"]\ntrusted_hash = "sha256:shared"\n' >> "$work/config.shared.toml"
  if "$work/scripts/sync-config.py" >/dev/null 2>&1; then fail "shared hook state accepted"; fi
  cmp -s "$work/config.toml" "$work/before-shared-error" || fail "shared hook state partially modified local config"
}

test_fresh_config_fallback() {
  local work="$tmp_root/fallback-repo" home="$tmp_root/fallback-home" backup="$tmp_root/fallback-backup"
  local canonical_work
  cp -a -- "$repo_root" "$work"
  canonical_work=$(cd -- "$work" && pwd -P)
  rm -f -- "$work/config.toml"
  mkdir -p -- "$home"
  cp "$work/config.shared.toml" "$home/config.toml"
  printf '\n[projects."/tmp/기존\\\\path"]\ntrust_level = "trusted"\n' >> "$home/config.toml"
  printf '\n[hooks.state."/fallback/hooks.json:stop:0:0"]\ntrusted_hash = "sha256:fallback-hook-hash"\n' >> "$home/config.toml"
  "$work/scripts/codex-config.sh" install --codex-home "$home" --backup-dir "$backup" --apply >/dev/null
  [[ -L "$home/config.toml" && "$(readlink "$home/config.toml")" == "$canonical_work/config.toml" ]] || fail "fresh install did not link generated config"
  python3 - "$work/config.toml" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert config["projects"]["/tmp/기존\\path"]["trust_level"] == "trusted"
assert config["hooks"]["state"]["/fallback/hooks.json:stop:0:0"]["trusted_hash"] == "sha256:fallback-hook-hash"
PY

  local invalid_work="$tmp_root/fallback-invalid"
  cp -a -- "$repo_root" "$invalid_work"
  rm -f -- "$invalid_work/config.toml"
  printf '[projects."/bad"]\nextra = "no"\n' > "$tmp_root/invalid-fallback.toml"
  if "$invalid_work/scripts/sync-config.py" --fallback-config "$tmp_root/invalid-fallback.toml" >/dev/null 2>&1; then fail "invalid fallback schema accepted"; fi
  [[ ! -e "$invalid_work/config.toml" ]] || fail "invalid fallback partially wrote local config"
  printf '[hooks.state."/bad/hooks.json:stop:0:0"]\nextra = "no"\n' > "$tmp_root/invalid-hook-fallback.toml"
  if "$invalid_work/scripts/sync-config.py" --fallback-config "$tmp_root/invalid-hook-fallback.toml" >/dev/null 2>&1; then fail "invalid hook fallback schema accepted"; fi
  [[ ! -e "$invalid_work/config.toml" ]] || fail "invalid hook fallback partially wrote local config"
}

test_hook_activation() {
  local work="$tmp_root/hook-repo" foreign="$tmp_root/foreign-hook-repo"
  cp -a -- "$repo_root" "$work"
  [[ -x "$work/.githooks/post-merge" && -x "$work/.githooks/post-checkout" && -x "$work/.githooks/pre-push" ]] || fail "versioned hooks are not executable"
  grep -Fq 'scripts/check-codex-config.sh' "$work/.githooks/pre-push" || fail "pre-push hook does not delegate to shared checks"
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
test_legacy_reader_migration
test_retired_review_migration
test_retired_sub_agents_migration
test_retired_planner_migration
test_retired_advisor_migration
test_retired_terra_executor_migration
test_backup_restore
test_incremental_restore_preserves_unchanged_links
test_rollback_after_link_failure
printf '%s\n' 'PASS: portable Codex config installer integration tests'
