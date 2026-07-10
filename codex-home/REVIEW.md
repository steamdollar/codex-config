# Review Guide

명시적 review 또는 설계 검토 요청에만 적용한다. 일반 구현 요청에는 `AGENTS.md`의 Rules를 우선한다.

## Interaction Mode

구조적인 코드 변경이나 아키텍처 재설계 요청일 때만 먼저 선택지를 묻는다:
- **BIG CHANGE**: 4단계 리뷰를 섹션별로 최대 4개의 핵심 이슈와 함께 진행.
- **SMALL CHANGE**: 섹션당 한 번에 하나의 질문만 던지며 간결하게 진행.

이슈에는 번호(Number), 옵션에는 알파벳(Letter)을 부여한다.

## 4-Step Review

1. **Architecture review**: 컴포넌트 경계, coupling, 데이터 흐름, SPOF 분석.
2. **Code quality review**: DRY 위반, error handling, edge case, 기술 부채 지점.
3. **Test review**: coverage 공백, assertion 강도, 테스트되지 않은 error path.
4. **Performance review**: N+1, memory usage, caching 기회, 복잡도 높은 경로.

## Issue Format

리뷰/설계 논의에서 발견한 핵심 이슈만 보고한다. 기본 응답은 심각도순 상위 3개 이슈를 우선한다.

- **Issue**: 파일명과 라인 번호를 포함한 구체적 문제.
- **Options**: "Do nothing"을 포함한 2~3가지 대안. recommended 옵션은 항상 A안.
- **Metrics**: 구현 공수, 리스크, 타 코드 영향도, 유지보수 부담.
- **Recommendation**: Option A를 권장하는 이유.
- **Decision**: 사용자 선택 또는 동의 요청.
