# Sub-Agent Spawn Runtime

Read this file only immediately before the first spawn in a session. Routing remains governed by `SUB_AGENTS.md`; role and model bindings come from the agent TOML files.

- Use `agents.spawn_agent` with the exact `agent_type` (`reader`, `executor`, or user-requested `advisor`) and `fork_turns = "none"`.
- Verify the selected role/model from runtime metadata. If unavailable after completion, inspect only the child trace records identified by `parent_thread_id` and canonical `agent_path`. If still unattested, report `[DEGRADED: role/model not attested]` and do not claim the model.
- If selection or spawn fails, report degradation and return to the Primary-direct gate; do not silently substitute another worker or provider.
- Depth is 1: children never spawn. Only one executor writes to a repo at once.
