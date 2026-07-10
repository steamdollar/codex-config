---
name: clero-local-dev-triage
description: Use to start, verify, debug, or explain local development in the Clero tokko monorepo, including Website pnpm dev/build.sh issues, HTTPS certificate or NetworkError failures, Redis/tmux startup, MCP local run, and AWS SSO credential errors. Diagnose and control processes without editing source; hand off proven code changes to clero-stepwise-change after approval.
---

# Clero Local Dev Triage

## Purpose

Use this skill when the user asks to start, verify, debug, or explain local
Clero development behavior. The goal is to reproduce narrowly, identify the
root cause, and report Process, Health, and Workflow separately.

## Ground Rules

- Verify current repo files before relying on memory.
- Prefer targeted commands over full builds. Do not repeatedly run heavy
  `build.sh` or broad package builds.
- When running under WSL2, run one or two processes at a time to preserve host stability.
- If the user asks whether another component is healthy, answer yes/no with the
  evidence used.
- Do not edit source. If evidence proves a code change is needed, stop and hand
  off to `clero-stepwise-change` after approval.
- Treat `/ping` as server Health evidence only, never authenticated Workflow
  success.

## Workspace Resolution

Before using a repo-specific path:

1. Resolve Codex home as `${CODEX_HOME:-$HOME/.codex}`.
2. Resolve the Clero root from `CLERO_TOKKO_ROOT` when it is set; otherwise
   resolve `$CODEX_HOME/local/roots/clero-tokko` when that symlink exists.
3. If neither source resolves to a directory, report
   `[UNKNOWN: Clero repository root not configured]` and ask for the exact path.
4. Verify the expected subrepo or entrypoint under that root before running a
   command. Do not infer a checkout location from the current username.

## Triage Flow

1. Identify the concrete subrepo and service:
   `Clero-Website`, `Clero-MCP`, `Clero-CDK`, or `Clero-Model`.
2. Inspect the actual script or entrypoint before choosing a command:
   `package.json`, `build.sh`, Gradle task, tmux helper, or README.
3. Reproduce the smallest failing path.
4. Separate primary failure from secondary noise.
5. Check the adjacent dependency that commonly gets blamed:
   backend vs frontend, cert vs API down, Redis vs app boot, AWS SSO vs MCP code.
6. Report Process, Health, and Workflow separately with the root cause,
   evidence, and next narrow command.

## Known Clero Checks

Verify these in current files before using them as facts:

- Website dev certificates usually live at
  `Clero-Website/certificates/key.pem` and
  `Clero-Website/certificates/cert.pem`.
- Website API development mode has used HTTPS on `https://localhost:3001`.
- UI accessor defaults have used `https://localhost:3001`; browser
  `NetworkError when attempting to fetch resource` often means cert/protocol
  mismatch, not backend outage.
- Everyday frontend dev should prefer HTTPS without inspector when available,
  such as `pnpm --filter ui dev:https`; keep debug scripts separate.
- Redis local setup has used Docker container `redis-local` on port `6379`.
- Root `dev-tmux.sh`, when present, is the preferred one-command FE/BE/Redis
  launcher for the user's local workflow.
- `Clero-MCP` local run has used `AWS_REGION=us-west-2 ./gradlew run`. Resolve
  its AWS SSO profile as `${CLERO_AWS_PROFILE:-clero-dev-sso}` and verify it
  before use.
- MCP `/ping` proves server Health only; `/invocations` can still require a user
  token, so authenticated Workflow success needs separate evidence.
- `InvalidGrantException` or `Token is expired` during MCP boot usually points
  to expired AWS SSO credentials before code defects.
- `Clero-Website/build.sh` is a full validation pipeline and caller cwd can
  matter; inspect it before treating generic `pnpm build` as authoritative.

## Failure Signatures

Use this table as hypotheses, not proof:

| Symptom | First check | Likely next step |
| --- | --- | --- |
| `ENOENT key.pem` | Certificate files under `Clero-Website/certificates` | Recreate local certs with the repo's documented `mkcert` command |
| Browser `NetworkError` on login | `http://localhost:3001` vs `https://localhost:3001` | Confirm API HTTPS response and browser cert trust |
| MCP boot fails with `Token is expired` | AWS SSO profile/cache | Refresh `${CLERO_AWS_PROFILE:-clero-dev-sso}` credentials |
| Gradle `:run` keeps executing | Look for server started log and `/ping` | If `/ping` works, report Process running and Health healthy; keep Workflow unknown until an authenticated check |
| Focused UI/Jest command exits non-zero | Test pass count vs coverage threshold | Re-run with the narrow coverage setting or `--coverage=false` when appropriate |

## Report Format

For troubleshooting answers, use:

```md
## 결론
## Process
## Health
## Workflow
## 확인한 증거
## 실행한 명령
## 다음 조치
## 불확실한 점
```

Keep the conclusion first, tie every claim to a command output or file path,
and never use `/ping` alone to claim Workflow success.
