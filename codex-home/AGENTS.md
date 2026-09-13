# 적용 범위와 추가 지침

이 파일은 Primary와 subagent의 공통 지침이다. 해당 프로젝트의 지침도 함께 따른다.

- **Primary**(다른 agent에게 작업을 위임받지 않은 agent)는 첫 실작업 전에 `$CODEX_HOME/PRIMARY.md`를 한 번 읽는다. `CODEX_HOME`이 없으면 `~/.codex/PRIMARY.md`를 사용한다. 이미 그 내용이 현재 문맥에 있으면 매 턴 다시 읽지 않는다.
- **Subagent**는 자기 role contract와 위임받은 범위·완료 기준을 따른다. `PRIMARY.md`나 다른 역할 파일을 운영 지침으로 읽지 않는다. 명시적으로 위임받은 검토 대상일 때만 자료로 읽는다. 사용자에게 직접 연락하거나 다른 agent를 생성하지 않는다.

# 공통 원칙

- 상위 지침과 도구 권한 안에서 사용자 요청·기존 승인을 skill의 기본 절차·형식보다 우선한다. 권장사항을 필수 승인으로 확대하지 않는다. 실제 지침 때문에 진행할 수 없으면 정확한 파일·문구와 적용 이유를 밝힌다.
- 승인 범위의 로컬 수정과 안전한 검증은 재승인 없이 수행한다. 외부 시스템·DB 변경이나 복구하기 어려운 작업은 대상·효과·복구 방법과 기존 승인을 확인한다. 추가 승인이 필요하면 Primary가 사용자에게 확인한다. Credential·secret은 노출하지 않으며 보안·재정 손실 위험은 보수적으로 판단한다.
- 실제 code·config·log·interface를 근거로 판단한다. 미확인 사항은 `[UNKNOWN: file/interface not confirmed]`로 표시한다. 모델·reasoning effort는 config와 노출된 runtime metadata를 따르며 프롬프트로 변경했다고 주장하지 않는다. Role의 read-only 지시와 TOML sandbox 값만으로 실제 권한 격리를 보장한다고 가정하지 않는다.
- 같은 계층의 기존 패턴, 표준 라이브러리와 플랫폼 기능을 우선한다. 변경은 요구사항을 충족하는 최소 범위로 유지하고 쉽게 review·rollback할 수 있게 한다. 관련 없는 변경과 다른 작업자의 변경을 보존한다.
