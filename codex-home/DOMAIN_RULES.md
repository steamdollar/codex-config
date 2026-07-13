# Domain Rules

Apply these rules to finance, security, blockchain, external API/system, infrastructure, database state changes, and external-dependency debugging.

- **Change Gate**: Follow the `AGENTS.md` approval rule. Before an external-system or database state change, report the exact target, action, and recovery path, then obtain fresh confirmation.
- **Target**: Before writing, explicitly verify the target environment, account, region, and resource.
- **Recovery**: When applicable, secure a dry-run, backup, and rollback path first.
- **Secrets**: Redact credentials and secrets from prompts, commands, logs, and artifacts.
- **Safety**: Apply pessimistic logic when security or financial loss is possible.
- **Error Handling**: Return errors with context preserved, including the cause and call site.
- **Concurrency**: Preserve task lifecycle management through cancellation scopes and ensure thread safety.
- **Idempotency**: Design external API calls and database state changes to remain safe across retries.
- **Observability**: Use INFO for major state changes, WARN for recoverable errors/retries, and ERROR for issues requiring intervention; include traceable context such as a TraceID.
- **Dependencies**: Treat third-party libraries as a last resort and first check whether the Standard Library is sufficient.
- **API Evolution**: Avoid breaking changes; when necessary, provide backward compatibility or explicit versioning.
- **Documentation**: Use Mermaid diagrams for complex data flows or architectures only when they materially help.

## Debugging Spike Guard

After two failed attempts to fix an external dependency, vendor, API, or infrastructure issue:
- Record each attempt's hypothesis, change, and result concisely in the current session and carry the summary into a handoff when needed; do not create a repository file by default.
- Create or update `DEBUG-LEDGER-{topic}.md` only when persistence across sessions is materially useful and the user approves the repository path and write.
- Review the recorded attempts before a new patch and state `same-class symptom, Nth recurrence`.
- Stop patching after the third same-class recurrence or approximately two hours. Based on the recorded attempts, ask for a `keep patching vs switch alternative` decision. If `continue` is chosen, present the decision again at the next recurrence.
