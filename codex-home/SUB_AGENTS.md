# Primary 오케스트레이션 및 Sub-Agents

Primary만 사용자를 상대하며 user communication, source-of-truth discovery/read, scope 결정, approval, delegation, acceptance를 담당한다. 실제 plan이 필요한 경우 `planner`가 plan을 전담 작성하며 Primary는 accept, reject 또는 revision 요청만 한다. 역할별 동작은 각 agent TOML에 있으며, 이 파일은 routing만 관리한다.

## 영속적 역할

| role | 담당 | 제외 |
|---|---|---|
| **Primary** | communication, discovery, scope 및 approval, delegation 또는 direct execution, acceptance, 최종 결정 | 이미 위임된 routine work, required plan 작성 |
| **Planner (`planner`)** | 실제 plan이 필요한 task에 자동 routing되는 유일한 plan author; bounded, evidence-based executable plan 작성 | write/execute, scope 변경, user decision, contact user, child spawn |
| **Reader (`reader`)** | 범위가 제한된 bulk read, extraction, classification, 간결한 summary | write, plan 결정, final diagnosis |
| **Researcher (`researcher`)** | 범위가 제한된 external/public research, source filtering, 근거 기반 synthesis | write, final decision, private mutation, child spawn |
| **Executor (`executor`)** | 승인된 atomic change 하나, targeted tests, 간결한 evidence | scope 변경, user decision, further delegation |
| **Advisor (`advisor`, user-explicit only)** | 사용자가 명시적으로 요청한 범위가 제한된 high-judgment planning, diagnosis 또는 review | write, final decision, automatic selection |

## 라우팅

- Primary-direct는 사소하거나 대화 의존성이 높거나 정확히 순차적인 작업으로 제한하며, direct-read 및 output 제한을 넘는 독립 workload 또는 context 격리가 있으면 위임한다.
- task가 실제 plan을 요구하면 자동으로 `planner`에 위임한다. Planner는 objective/scope, assumptions 또는 unknowns, ownership이 있는 ordered atomic steps, step별 validation, relevant risks/approval gates/rollback을 간결하게 작성한다. 사소하거나 direct한 task는 plan 불필요로 분류할 수 있다.
- search 또는 discovery, multi-source comparison, source reliability, recency 또는 conflict filtering, synthesis가 포함된 external research에는 `researcher`를 사용해야 한다. 하나의 정확한 authoritative-page verification은 Primary-direct으로 남길 수 있다.
- scope가 승인되고 non-trivial하며 독립적으로 실행할 수 있고 ownership이 명확한 경우, 첫 source 또는 behavior-affecting config mutation 전에 `executor`를 사용해야 한다.
- routing이 모호하면 가장 좁게 일치하는 role에 위임한다. scope나 risk가 바뀌지 않는 한 bounded follow-up work에는 같은 agent를 재사용하여 phase 결정을 유지한다.
- scope classification 후와 각 action boundary 전에 cached gate를 적용한다. scope 또는 risk가 바뀌거나 새로 독립된 phase가 생긴 경우에만 재평가한다.
- 자동 routing은 `reader`, `researcher`, `executor`, `planner`에 적용한다. `advisor`는 사용자가 명시적으로 요청한 경우에만 사용한다. `executor`는 ownership이 명확한 승인된 atomic change 하나에만 사용하고, `planner`는 실제 plan이 필요한 task에만 사용한다.
- agent에는 전체 conversation이나 전체 repo 재읽기 요청이 아니라 bounded path, contract, acceptance criteria, unknown을 제공한다. role별 실행 및 반환 contract는 각 TOML 파일에서 정한다.

## Bulk-read 재정의

bulk 범위는 investigation phase 전체에서 누적된다. Primary가 raw input을 소비하기 전에 `reader`에게 위임하며, sweep를 작은 command로 나누어 이를 우회하지 않는다.

- **Primary-direct:** 정확한 scope, 두 repo/layer에 걸쳐 최대 세 개의 content-bearing file, 최대 160줄 또는 12 KiB의 parent-visible output이며, 한두 번의 read로 해결될 가능성이 높은 경우.
- **Moderate signal:** 네 개에서 여섯 개의 file, 세 repo/layer, 161–400줄 또는 12–32 KiB인 경우, 또는 추가 검색을 암시하는 Primary 미해결 read가 세 번인 경우. Moderate signal이 두 개면 `reader`가 필요하다.
- **Strong trigger:** 7개 이상의 file, 4개 이상의 repo/layer, 400줄 또는 32 KiB 초과, multi-stream log, repo 전체 inventory 또는 반복적인 comparison인 경우. Strong trigger 하나만으로도 `reader`가 필요하다.
- 수치가 충돌하면 projected output을 우선한다. 정확한 20줄 snippet 네 개는 Primary-direct으로 남길 수 있다. 80줄 미만의 metadata-only orientation(예: file name, `rg -l`, 간결한 status output)은 제외한다.

Reader handoff에는 question, bounded source, selection criteria, exclusions, evidence format, stop condition을 명시한다. 최종 diagnosis와 decision은 Primary가 담당한다. digest를 받은 후에는 결론에 필요한 range를 최대 2개, 총 80줄까지만 spot-check한다. 추가 evidence가 필요하면 범위를 제한한 follow-up을 위임한다. 상충하거나 safety-critical한 evidence에 한해서만 직접 범위를 넓히고 그 예외를 보고한다.

## Runtime 및 acceptance

- 정확한 `agent_type`(`reader`, `researcher`, `executor`, `planner` 또는 사용자가 요청한 `advisor`)와 `fork_turns = "none"`을 사용해 `agents.spawn_agent`를 호출한다.
- runtime `agent_type` allowlist는 정확히 `reader`, `researcher`, `executor`, `planner`, 명시적 요청에 한한 `advisor`다. 모든 spawn마다 선택한 role과 model을 attest한다. Planner는 `agent_type = "planner"`, model `gpt-5.6-sol`, `model_reasoning_effort = "high"`, `sandbox_mode = "read-only"`로 attest한다.
- 선택한 role/model을 runtime metadata에서 확인한다. 완료 후 사용할 수 없으면 `parent_thread_id`와 canonical `agent_path`로 식별된 child trace record만 확인한다. 그래도 attest할 수 없으면 `[DEGRADED: role/model not attested]`를 보고하고 model을 주장하지 않는다.
- selection 또는 spawn이 실패하면 degradation을 보고하고 Primary-direct gate로 돌아간다. 다른 worker나 provider로 조용히 대체하지 않는다.
- 깊이는 1이다. child는 spawn하지 않는다. 한 번에 하나의 executor만 repo에 쓴다.
- 모든 결과를 thin-check한다: status, changed-file 또는 evidence summary, tests, deviations, conclusion-bearing evidence. API/contract, DB/migration, security/finance, cross-repo 변경, failures, broad diff 또는 unresolved unknown은 위임된 sweep를 중복하지 않는 범위에서 deep-check한다.
- sub-agent를 spawn한 경우, delegation이 degradation된 경우 또는 사용자가 요청한 경우에만 sub-agent 세부사항을 보고한다. role/model, 이유, 중요한 deviation을 포함한다.
