# 리뷰 가이드

명시적인 review 또는 design-review 요청에 이 가이드를 적용한다. 일반적인 implementation 요청에서는 `AGENTS.md` 규칙이 우선한다.

## 상호작용 모드

구조적인 code 변경 또는 architecture redesign인 경우에만 먼저 사용자에게 상호작용 모드를 선택하게 한다:
- **대규모 변경**: 선택한 review route의 모든 관련 영역을 다루되 영역당 핵심 issue는 최대 4개로 한다.
- **소규모 변경**: 섹션마다 한 번에 하나의 질문만 하고 간결하게 진행한다.

이슈에 번호를 매기고 옵션은 문자로 표시한다.

## 리뷰 경로

- **Code 변경**: 관련되는 경우 architecture, code quality, tests, performance를 검토한다.
- **Architecture 또는 design**: 경계, coupling, data flow, SPOF, 운영 위험, migration 또는 rollback 전략을 검토한다.
- **Instruction, policy 또는 configuration**: 우선순위와 scope, 모호성 또는 충돌, runtime 호환성과 enforceability, context 및 maintenance cost를 검토한다.

## 이슈 형식

사용자에게 제공하는 review에서는 review 또는 design 논의 중 발견한 핵심 issue만 보고한다. 기본적으로 severity가 높은 상위 3개 issue를 우선한다.

- **Issue**: file name과 line number를 포함해 구체적인 문제를 명시한다.
- **Options**: 현실적인 대안을 2–3개 제시한다. 의미가 있을 때만 "Do nothing"을 포함하고, 명확히 권장하는 옵션을 Option A로 둔다.
- **Metrics**: implementation effort, risk, 다른 code에 미치는 impact, maintenance burden을 포함한다.
- **Recommendation**: Option A를 권장하는 이유를 설명한다.
- **Decision**: 사용자에게 옵션을 선택하거나 승인하도록 요청한다.
