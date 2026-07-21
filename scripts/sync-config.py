#!/usr/bin/env python3
"""Rebuild the machine-local Codex config from the versioned shared profile."""
from __future__ import annotations
import argparse
import fcntl
import json
import os
import sys
import tempfile
import tomllib
from pathlib import Path

def fail(message: str) -> None:
    raise ValueError(message)

def parse_toml(raw: bytes, label: Path) -> dict:
    try:
        value = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        fail(f"invalid TOML in {label}: {exc}")
    if not isinstance(value, dict):
        fail(f"unexpected TOML root in {label}")
    return value

def read_toml(path: Path) -> dict:
    try:
        return parse_toml(path.read_bytes(), path)
    except OSError as exc:
        fail(f"invalid TOML in {path}: {exc}")

def read_shared(path: Path) -> bytes:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        fail(f"invalid TOML in {path}: {exc}")
    shared = parse_toml(raw, path)
    if "projects" in shared:
        fail("config.shared.toml must not contain [projects]")
    hooks = shared.get("hooks")
    if isinstance(hooks, dict) and "state" in hooks:
        fail("config.shared.toml must not contain [hooks.state]")
    return raw

def validate_projects(value: object) -> dict[str, dict[str, str]]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        fail("unexpected [projects] schema: expected a table")
    projects = {}
    for path, settings in value.items():
        if not isinstance(path, str) or not isinstance(settings, dict):
            fail("unexpected [projects] schema: expected path tables")
        if set(settings) != {"trust_level"} or not isinstance(settings["trust_level"], str):
            fail("unexpected [projects] schema: expected only string trust_level")
        projects[path] = {"trust_level": settings["trust_level"]}
    return projects

def validate_hook_state(value: object) -> dict[str, dict[str, str]]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        fail("unexpected [hooks.state] schema: expected a table")
    hook_state = {}
    for hook_id, settings in value.items():
        if not isinstance(hook_id, str) or not isinstance(settings, dict):
            fail("unexpected [hooks.state] schema: expected hook tables")
        if set(settings) != {"trusted_hash"} or not isinstance(settings["trusted_hash"], str):
            fail("unexpected [hooks.state] schema: expected only string trusted_hash")
        hook_state[hook_id] = {"trusted_hash": settings["trusted_hash"]}
    return hook_state

def machine_local_state(config: dict) -> tuple[dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    hooks = config.get("hooks")
    if hooks is not None and not isinstance(hooks, dict):
        fail("unexpected [hooks] schema: expected a table")
    hook_state = None if hooks is None else hooks.get("state")
    return validate_projects(config.get("projects")), validate_hook_state(hook_state)

def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)

def render(
    shared: bytes,
    projects: dict[str, dict[str, str]],
    hook_state: dict[str, dict[str, str]],
) -> bytes:
    result = shared.rstrip(b"\n") + b"\n"
    if projects:
        result += b"\n"
        for path in sorted(projects):
            result += f"[projects.{quote(path)}]\ntrust_level = {quote(projects[path]['trust_level'])}\n".encode()
    if hook_state:
        result += b"\n"
        for hook_id in sorted(hook_state):
            result += f"[hooks.state.{quote(hook_id)}]\ntrusted_hash = {quote(hook_state[hook_id]['trusted_hash'])}\n".encode()
    return result

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--fallback-config", type=Path)
    args = parser.parse_args()
    root = args.repo_root.resolve()
    shared_path, local_path = root / "config.shared.toml", root / "config.toml"
    def machine_state_for_current_source() -> tuple[dict[str, dict[str, str]], dict[str, dict[str, str]]]:
        if local_path.exists():
            return machine_local_state(read_toml(local_path))
        if args.fallback_config is not None and args.fallback_config.exists():
            return machine_local_state(read_toml(args.fallback_config))
        return {}, {}

    shared_bytes = read_shared(shared_path)
    desired = render(shared_bytes, *machine_state_for_current_source())
    if args.dry_run:
        print("DRY-RUN: config.toml would be updated" if not local_path.exists() or local_path.read_bytes() != desired else "NOOP: config.toml is synchronized")
        return 0
    with (root / "config.toml.lock").open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        # Re-read and validate the precise shared bytes used for the write.
        shared_bytes = read_shared(shared_path)
        desired = render(shared_bytes, *machine_state_for_current_source())
        if local_path.exists() and local_path.read_bytes() == desired:
            print("NOOP: config.toml is synchronized")
            return 0
        fd, temporary_name = tempfile.mkstemp(prefix=".config.toml.", dir=root)
        try:
            with os.fdopen(fd, "wb") as temporary:
                temporary.write(desired)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.replace(temporary_name, local_path)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    print("SYNCHRONIZED config.toml")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
