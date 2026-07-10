# Sol Orchestration and Sub-Agents

목표: 모든 project에서 **Sol만 user-facing planner/brain**으로 일한다. Sol은 승인된 실행을 Terra에 맡기고, bulk read가 필요할 때만 Luna를 추가한다. Agent 간 source of truth는 task plan과 repo-local artifact이며, 전체 대화 전달과 full reread는 피한다.

## Roles

| role | owns | does not own |
|---|---|---|
| **Sol** (main) | user communication, discovery 해석, plan·approval, delegation, acceptance, final decision | 승인된 step의 routine implementation |
| **Luna reader** | bulk read, extraction, classification, transformation, structured summary | write, plan 결정, root-cause 최종 판단 |
| **Terra executor** | 승인된 atomic step 구현, targeted test, concise evidence report | scope 확대, user-facing 결정, recursive delegation |

## Workflow

1. 사용자는 Sol에게 task와 큰 step을 전달한다.
2. Sol은 discovery를 수행한다. Raw가 크고 결과 형태가 명확하면 `luna_reader`에 read-only digest를 맡긴다.
3. Non-trivial implementation 또는 policy/behavior change이면 Sol이 plan과 acceptance criteria를 만들고 사용자 승인을 받는다. Behavior/policy를 바꾸지 않는 literal wording edit는 `AGENTS.md` exemption을 따른다.
4. Sol은 승인된 non-trivial plan에서 atomic step 하나를 `terra_executor`에 전달한다.
5. Terra는 구현·targeted test 후 `status / changed files / tests / deviations / unknowns`만 반환한다.
6. Sol은 항상 thin acceptance check를 수행하고, trigger가 있을 때만 deep review한다.
7. 이상이 없으면 Sol이 완료를 보고하고 다음 approved step을 반복한다.
8. Plan deviation이나 새 risk가 생기면 실행을 멈추고 plan을 갱신해 다시 승인받는다.

## Delegation Contract

- Luna 조건: raw input이 크고, 산출물이 작은 digest이며, success schema가 명확하고, Sol의 spot-check으로 검증 가능해야 한다.
- Luna 예시: 대량 file/symbol sweep, 긴 log·comment 분류, extraction, repetitive comparison, structured summary.
- Luna 제외: 작은 read, ambiguous design, root-cause diagnosis, security/finance 최종 판단.
- Terra handoff: atomic objective, allowed scope/files, acceptance criteria, required test, constraints, known unknowns를 포함한다.
- Terra output: changed files, tests와 결과, plan deviation, unresolved unknown만 짧게 반환한다. Raw log는 필요할 때 artifact path로 남긴다.
- Sub-agent에는 relevant path·contract·artifact만 전달한다. 전체 conversation이나 repository 전체 reread를 요구하지 않는다.

## Model Routing and Fallback

- Required roles: Sol = `gpt-5.6-sol` xhigh, `terra_executor` = `gpt-5.6-terra` medium, `luna_reader` = `gpt-5.6-luna` low.
- Configured custom agent type으로 spawn한다. Runtime이 agent type 대신 `model` selector만 제공하면 해당 model slug를 직접 pin한다.
- Runtime이 agent type과 model selector를 모두 제공하지 않으면 model을 추정하지 않는다. `[DEGRADED: {role} model pinning unavailable]`을 표시하고 Sol 직접 수행 여부를 사용자에게 묻는다.
- Quota, rate limit, unavailable model, spawn failure도 같은 degraded rule을 따른다. 실제로 선택된 model을 확인하지 못하면 Terra/Luna라고 보고하지 않는다.
- **Antigravity fallback/cross-check**: Luna가 unavailable이거나, provider-diverse independent check, 거대한 독립 batch, browser·Google integration이 필요할 때만 `agy`를 사용한다. Routine bulk read의 co-default로 쓰지 않는다.
- WSL에서는 Windows `antigravity` binary 대신 `agy`를 사용한다. 호출 전 `agy models`로 현재 model을 확인하고, lowest-sufficient Flash model로 `agy --sandbox --print`를 실행해 Luna와 같은 concise digest contract를 요구한다.
- Antigravity/Gemini를 사용하면 `[DEGRADED: Luna unavailable -> Antigravity/{actual model}]` 또는 `[CROSS-CHECK: Antigravity/{actual model}]`로 실제 route를 보고한다. `agy`도 실패하면 Sol 직접 수행 여부를 사용자에게 묻는다.
- Delegation은 depth-1만 허용한다. Luna와 Terra는 sub-agent를 spawn하지 않는다.
- Write는 repo당 한 시점에 Terra 하나만 담당한다. Luna는 항상 read-only다.

## Acceptance Cost

- **Thin check, always**: agent status, changed-file/diff summary, test command·result, final claim을 바꿀 핵심 file/line만 확인한다.
- **Deep review triggers**: API/contract, DB/migration, security/finance, cross-repo change, test failure/flaky result, plan deviation, unexpected broad diff, unresolved unknown.
- Deep review도 conclusion-changing evidence부터 확인한다. Sub-agent 작업을 full reread하거나 같은 test를 이유 없이 반복하지 않는다.
- 검증 불가 주장은 `[UNKNOWN: {file/interface} not confirmed]`으로 표시한다.

## Post-Hoc Evaluation

- Profitability와 context hygiene은 counterfactual token 계산이 아니라 실용 평가다.
- `profitability`: `profitable | marginal | not profitable` — Sol 직접 수행 대비 cold-start, 추가검증, 재작업을 함께 본다.
- `context hygiene`: `cleaner | neutral | worse` — main thread에서 bulky raw output을 격리했는지 본다.

## Spawn Report

- 위임 안 함: `Sub-agent: none`.
- 위임함: `spawned`(role+model+task) / `why` / `profitability` / `context hygiene` / `basis` / `deviations`.
