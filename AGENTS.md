# codex-config 작업 지침

## 범위와 source of truth

- 이 파일은 이 저장소에서만 사용하는 작업 지침이다. 설치 artifact가 아니며 `manifest.tsv`에 추가하지 않는다.
- versioned repository source가 canonical이다. live `$CODEX_HOME` 파일을 직접 편집하지 말고 repository source를 수정한 뒤 installer로 반영한다.
- 전역 Primary 지침은 `codex-home/AGENTS.md`, custom role contract는 `codex-home/agents/*.toml`에 둔다.
- portable 설정은 `config.shared.toml`에서 수정한다. `config.toml`은 sync script가 machine-local `[projects]`와 `[hooks.state]`를 보존하며 생성한다.

## 변경과 설치

- managed source를 추가·이름 변경·제거하면 `manifest.tsv`, README, installer migration/retirement와 관련 test를 함께 갱신한다.
- installer는 repository가 소유한 정확한 symlink만 교체하거나 제거한다. foreign symlink와 regular file은 보존한다.
- live 설정을 반영할 때는 dry-run 결과를 확인한 뒤 apply하고 verify한다. source recovery는 Git을 사용하고 live 변경의 recovery는 installer backup과 rollback을 사용한다.
- 관련 없는 변경과 다른 작업자의 변경을 보존한다. 변경은 최소 범위이며 쉽게 review하고 rollback할 수 있어야 한다.

## 검증

- 모든 변경에서 `bash tests/codex-config-test.sh`와 `git diff --check`를 통과시킨다.
- shell script를 바꾸면 `bash -n`을, TOML을 바꾸면 Python `tomllib` parse를 추가로 실행한다.
- installer나 managed scope를 바꾸면 임시 `CODEX_HOME` integration 경로와 필요한 live verify까지 확인한다.

## Git delivery

- 새 branch를 만들거나 PR을 열지 않는다. 이 저장소의 변경은 `main`에서 작업하고 검증 후 commit하여 `origin/main`에 직접 push한다.
- push 전에 remote 변경을 확인하고 보존한다. conflict나 non-fast-forward를 덮어쓰지 않으며 force push하지 않는다.
