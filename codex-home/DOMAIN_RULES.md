# Domain Rules

금융/보안/블록체인/외부 API·system/infra/DB 상태 변경과 external dependency debugging에 적용한다.

- **Change Gate**: read-only discovery와 state-changing action을 분리하고, 상태 변경 전 explicit approval을 받는다.
- **Target**: write 전에 target environment, account, region, resource를 명시적으로 확인한다.
- **Recovery**: 적용 가능하면 dry-run, backup, rollback path를 먼저 확보한다.
- **Secrets**: prompt, command, log, artifact에서 credential과 secret을 redaction한다.
- **Safety**: 보안 또는 자금 손실 가능성이 있으면 Pessimistic Logic을 적용한다.
- **Error Handling**: 에러는 맥락(cause + call site)을 유지하도록 wrapping하여 반환한다.
- **Concurrency**: cancellation scope를 통한 task lifecycle 관리와 Thread-safety를 보장한다.
- **Idempotency**: 외부 API 호출이나 DB 상태 변경은 retry가 발생해도 안전하도록 설계한다.
- **Observability**: INFO는 주요 상태 변경, WARN은 복구 가능한 오류/재시도, ERROR는 개입이 필요한 실패로 구분하고 TraceID 등 추적 가능한 context를 포함한다.
- **Dependencies**: 서드파티 라이브러리는 최후의 수단으로 보고 Standard Library로 해결 가능한지 먼저 검토한다.
- **API Evolution**: Breaking Change를 지양하고, 필요하면 하위 호환성 또는 명시적 versioning을 둔다.
- **Documentation**: 복잡한 데이터 흐름이나 아키텍처는 필요한 경우에만 Mermaid 차트로 시각화한다.

## Debugging Spike Guard

외부 dependency/vendor/API/infra fix attempt가 두 번 실패한 시점부터:
- `DEBUG-LEDGER-{topic}.md`에 attempt별 hypothesis / change / result를 한 줄로 기록하고 session handoff에서 참조한다.
- 새 patch 전에 ledger를 읽고 `same-class symptom, Nth recurrence`를 명시한다.
- 3번째 same-class recurrence 또는 약 2시간 경과 시 patching을 멈추고 ledger 근거로 `keep patching vs switch alternative` 결정을 받는다. `continue`를 선택하면 다음 recurrence에 결정을 다시 제시한다.
