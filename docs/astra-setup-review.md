# Astra Primary setup 재검토 — 2026-09-08

## 적용한 기본값과 판단 범위

Primary는 `gpt-6-astra / medium`, 단순하고 범위가 명확한 작업은 `low`로 시작한다.
사용자가 말한 `light`에 대응하는 설정값은 `low`다. 조사 시작 시 repository source는
이미 Astra high였고 CLI는 0.144.3이었다. 이번 변경은 high → medium과 운영 지침 정리다.

OpenAI의 API migration baseline은 기존 effort 유지다. 따라서 Sol high → Astra medium/low가
같은 품질을 낸다는 주장은 하지 않는다. 사용자가 요청한 속도·효율 방향의 시작값이며,
실제 작업으로 확인해야 한다. [Astra model guidance](https://developers.openai.com/api/docs/guides/latest-model)
및 [지원 effort](https://developers.openai.com/api/docs/models/gpt-6-astra).

이 검토는 versioned 설정·전역 지침·역할·managed skills·hooks·설치/검증 경계를 대상으로 한다.
과거 모든 대화의 효과를 측정한 회고는 아니다. 후속 승인으로 외부 사용자 skill 세 개도
원본 위치에서 정리했고, standalone E2E skill은 이 저장소 관리 대상으로 옮긴다. 공식 사실, 개인 운영 선택, 미검증 성능 가설을 구분한다.

## 전제별 결론

| 기존 또는 잠재적 전제 | 결론과 이번 처리 | 근거/위치 |
| --- | --- | --- |
| 높은 reasoning을 고정해야 안정적이다 | medium 기본, 명확한 작은 일은 low. 어려운 디버깅·설계의 실패가 보이면 상향을 검토한다. low/medium의 동등 품질은 미검증이다. | `config.shared.toml`; [난이도별 선택](https://learn.chatgpt.com/guides/best-practices) |
| Primary는 관리자이고 테스트는 항상 executor가 해야 한다 | 작은 변경은 구현·테스트·검수까지 Primary가 담당한다. 독립 실행의 이익이 있는 경우에만 위임한다. | `codex-home/AGENTS.md` 작업 선택·검증 |
| 로그 또는 여러 파일이면 항상 위임해야 한다 | 필터·집계로 충분하면 직접 처리한다. 분산된 대량 읽기는 reader로 격리하되 원인 판단은 Primary가 한다. | `codex-home/AGENTS.md` Context; [context pollution](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| 저렴한 하위 모델을 많이 쓰면 전체 비용도 낮다 | 작업별 spawn·중복 입력·대기·통합 비용까지 고려한다. 독립적으로 현재 실행 가능한 작업만 분리한다. | [subagent의 추가 token 소비](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| Astra로 바꾸면 알아서 더 위임한다 | 이익이 있는 조건에서 위임하라는 AGENTS 지시를 명시한다. depth-1과 역할 제한은 개인 운영 선택으로 유지한다. | `codex-home/AGENTS.md` 선택적 위임; [현재 Codex trigger](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| 작은 모델 high/xhigh가 항상 최적이다 | reader Luna high, executor Luna xhigh, researcher Terra medium, reviewer Sol high를 당장 함께 바꾸지 않는다. 최적이라는 증거는 없으며 Primary 전환 효과와 분리해 비교한다. | `codex-home/agents/*.toml` |
| 상위 모델이면 하위 reviewer가 무의미하다 | 독립된 context에서 위험을 보는 이점은 남는다. 모든 작업의 자동 단계로 쓰지 않고 중요한 경계에서 한 번 사용한다. reviewer 결과도 사실 근거로 판단한다. | `codex-home/AGENTS.md` 리뷰; 개인 운영 판단 |
| 규칙을 더 자세히 많이 쓰면 품질이 계속 오른다 | 전역 지침의 중복을 줄이고 목표·근거·제약·완료 기준을 중심으로 정리했다. 프로젝트 명령은 project 지침에 둔다. | [짧고 정확한 AGENTS](https://learn.chatgpt.com/guides/best-practices) |
| skill에 approval이라고 쓰였으면 항상 다시 물어야 한다 | 현재 요청과 누적 승인을 우선 적용한다. 실제 중대한 미승인 결정만 질문하고 승인 가능한 결과를 먼저 준비한다. | [Astra instruction sensitivity](https://developers.openai.com/api/docs/guides/latest-model); `codex-home/AGENTS.md` |
| 효율은 테스트 횟수를 무조건 한 번으로 묶는 것이다 | 개발 중 필요한 진단은 허용한다. 최종 검증을 묶고 통과 후 근거 없는 반복을 막는다. 저장소 필수 checks와 필요한 회귀 검증은 유지한다. | [testing calibration](https://developers.openai.com/api/docs/guides/latest-model) |
| context window가 크면 긴 raw output도 괜찮다 / 60%면 새 탭이 필요하다 | 필요한 근거만 읽고 hook은 참고 신호로 유지한다. 60%는 품질·가격 임계치가 아니다. 같은 목표는 이어가며 필요하면 compact, 새 목표는 새 session으로 진행한다. | `codex-home/hooks/context-budget.py`; [context 관리](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| AGY는 Codex quota를 안 쓰므로 공짜이고 항상 추가하면 좋다 | 호출 준비·검수 비용과 외부 서비스 제약은 남는다. 사용자가 AGY 또는 다른 모델 계열의 비교를 요청할 때만 사용하며 implicit invocation을 끈다. | `codex-home/skills/agy-worker/SKILL.md`; 개인 운영 판단 |
| full access + 지침 / read-only role이면 보안 격리가 충분하다 | 기존 명시적 개인 권한 선택은 유지하지만 행동 지침과 OS 격리를 구분한다. parent runtime override가 child 권한에 적용될 수 있다. | `README.md` Safety model; [권한 상속](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| TOML 또는 agent 자기보고가 실제 실행 모델을 증명한다 | 노출된 tool metadata와 설정 의도를 구분하는 규칙을 유지한다. 미확인 시 한계를 보고하며 확인용 spawn은 하지 않는다. | `codex-home/AGENTS.md` 선택적 위임 |
| API 신기능은 config에 키를 넣으면 Codex에서도 쓸 수 있다 | async tool calling·configuration_update·cache 설정을 임의 추가하지 않는다. 이미 동작하는 MultiAgentV2 namespace/binding도 이 전환 때문에 바꾸지 않는다. | API/Codex 지원 경계; CLI 및 현재 tool metadata |
| plugin·skill이 많으면 무조건 유리하다 | 작업별 skill을 필요할 때 사용한다. Ponytail plugin은 기본 비활성으로 바꾸고 기존 패턴 재사용 원칙은 전역에 남긴다. 명시적 CLI 세션 override로 vendor 기능을 다시 켤 수 있으며 cache는 편집하지 않는다. | `config.shared.toml`; 활성 Ponytail 지침과 사용자 우선순위 |
| 작은 diff가 곧 성공이고 tool 수가 적으면 효율적이다 | 완료 기준 충족·회귀·사용자 수정·시간·사용량을 함께 본다. 기존 workflow audit/efficiency retro를 재사용한다. | `codex-home/skills/agent-efficiency-retro/SKILL.md` |

공식 권고는 판단 근거이며 위 표의 모델 조합·depth·리뷰 횟수·hook threshold를
OpenAI가 검증한 최적 구성으로 해석하면 안 된다.

## 감사 도구 및 managed skill 확인

기존 8개 managed skill에 E2E를 추가한다. AGY는 명시적 호출용으로 전환하고,
완료 변경 설명 skill의 일반 "리뷰" trigger 및 이해 확인 gate를 줄인다. 역할 프롬프트는
전역 규칙의 복제와 과도한 결과 schema를 줄이고 역할별 판단·근거 경계는 보존한다.

외부 `config-audit`의 Claude용 linter, `session-retro`의 옛 transcript schema·모델 고정,
프로세스 정리 skill의 잘못된 script 경로와 Claude 전용 helper를 확인했다.
해당 helper는 제거하고 native ps·정확한 PID 재확인·승인된 signal 절차로 대체한다. 해당 세 skill은
`~/.agents/skills`의 원본이며 이 manifest 밖이다. config-audit는 대상 저장소의 현재
검증 명령을 따르게 하고, 더 이상 Claude용 검사의 실패를 Codex 설정 결함으로 취급하지 않는다.
E2E는 기존 승인 범위에서 계속 진행하되 수동 조작과 미승인 외부 write 경계를 보존한다.

## 사용 방법과 최소 비교

평소에는 새 session을 기본 medium으로 시작한다. CLI의 단순 작업은 다음처럼 실행한다.

```bash
codex -c 'model_reasoning_effort="low"'
```

Desktop/IDE에서는 client의 모델·reasoning 선택을 사용한다. 기존 session 선택값과 CLI override는
공유 default보다 우선할 수 있다. 프롬프트로 low라고 말하는 것만으로 runtime 설정이 바뀌지는 않는다.

요청은 다음 정도면 충분하다. 형식의 빈칸을 모두 채워야 작업을 시작할 수 있다는 뜻은 아니다.

> 목표: 어떤 동작을 바꿀지. 근거: 관련 파일·오류·문서. 제약: 보존할 동작과 허용 범위.
> 완료: 관찰할 결과와 필요한 테스트. 독립 작업의 분리가 유익하면 위임해도 된다.

새 benchmark framework는 만들지 않는다. 다음 몇 개의 비슷한 실제 작업에서 완료 시간,
사용자 재지시, 결함/재검증, 노출되는 사용량과 위임 대기를 기록한다. 가능하면 같은 출발점의
안전한 표적 작업에서 Sol high, Astra medium, Astra low를 비교하고, 한 번에 reasoning 또는
위임 방식 한 변수만 바꾼다. 서로 다른 작업의 토큰 수만으로 인과를 주장하지 않는다.
품질 저하가 보이면 해당 종류부터 medium/high로 올린다. 보안·금전·데이터 작업을 일부러
낮은 effort로 실행해 비교하지 않는다. 구독 usage allowance와 API 달러 가격은 동일 지표가 아니다.

현재 변경의 검증은 config parse·설치/동기화·기존 regression checks에 한정된다.
실제 Astra medium/low의 품질·비용 우위는 아직 측정하지 않았다.
