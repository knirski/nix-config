#!/usr/bin/env python3
"""Enforce security properties that actionlint intentionally does not cover."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml


PINNED_ACTION = re.compile(
    r"^\s*-\s+uses:\s+['\"]?[^\s@'\"]+@[0-9a-f]{40}['\"]?(?:\s+#\s+\S.*)?$"
)
ANY_ACTION = re.compile(r"^\s*-\s+uses:\s+")

# Any workflow step/`with:` line that references a Cachix-shaped (or generic
# cache-auth) secret. Scoped narrowly to the one class of mistake this check
# closes -- see cache_token_errors() docstring for exactly what is and is not
# detected.
CACHE_TOKEN_SECRET = re.compile(
    r"secrets\.[A-Za-z0-9_]*(?:CACHIX|CACHE)[A-Za-z0-9_]*TOKEN[A-Za-z0-9_]*",
    re.IGNORECASE,
)
# Substrings that together mean "this only runs on a push to main". Both must
# appear (on the same line, or on an `if:` line within the same step) for a
# cache-token reference to be considered gated.
MAIN_PUSH_GATE_PARTS = ("event_name == 'push'", "refs/heads/main")
STEP_START = re.compile(r"^\s*-\s")

# Pre-approved per-workflow job-level write permissions. Each entry names the
# EXACT permission key/value pairs that specific workflow filename may
# declare at job level; any write permission not listed here is rejected the
# same as for every other workflow (an unlisted filename gets zero write
# tolerance). This replaces a blanket "this whole file may write anything"
# exemption -- keep entries minimal and review additions carefully.
JOB_WRITE_ALLOWLIST: dict[str, dict[str, str]] = {
    "pr-agent.yml": {"pull-requests": "write"},
}


def has_trigger(value: object, trigger: str) -> bool:
    if isinstance(value, str):
        return value == trigger
    if isinstance(value, list):
        return trigger in value
    if isinstance(value, dict):
        return trigger in value
    return False


def permission_errors(
    value: object,
    scope: str,
    require_contents: bool,
    *,
    allowed_writes: dict[str, str] | None = None,
) -> list[str]:
    errors: list[str] = []
    if isinstance(value, str):
        if value == "write-all":
            errors.append(f"{scope} write permission is forbidden")
        if require_contents and value != "read-all":
            errors.append(f"{scope} permissions must include contents: read")
        return errors
    if not isinstance(value, dict):
        return [f"{scope} permissions must be a mapping or read-all"]
    if require_contents and value.get("contents") != "read":
        errors.append(f"{scope} permissions must include contents: read")
    allowed = allowed_writes or {}
    for permission_key, permission_value in value.items():
        if permission_value == "write" and allowed.get(permission_key) != "write":
            errors.append(f"{scope} write permission is forbidden: {permission_key}")
    return errors


def cache_token_errors(lines: list[str], triggers_pull_request: bool) -> list[str]:
    """Flag a cache-auth-token secret reaching a pull_request-triggered
    workflow without a same-repo-push-to-main gate.

    Scope/limits: this is a narrow, purpose-built check for exactly one
    mistake class (the same secret string handed unconditionally to a
    composite action's `with:` input, e.g. `cachix-auth-token:
    '${{ secrets.CACHIX_AUTH_TOKEN }}'`, on a workflow that also runs on
    `pull_request`). It only fires when the workflow's `on:` includes
    `pull_request`. It looks for the literal
    `secrets.*CACHI(X|E)...TOKEN*` reference pattern and considers it
    gated if the same line, or an `if:` line within the same step, contains
    both `github.event_name == 'push'` and `refs/heads/main` substrings
    (covering both an inline ternary on the value itself and a step-level
    `if:` guard). It is NOT a general secrets-flow/taint analyzer: a
    differently named secret, indirection through an intermediate env var
    or job output, or a differently worded but equivalent gate expression
    will not be recognized.
    """
    if not triggers_pull_request:
        return []
    errors: list[str] = []
    step_starts = [i for i, line in enumerate(lines) if STEP_START.match(line)]
    for number, line in enumerate(lines, start=1):
        if not CACHE_TOKEN_SECRET.search(line):
            continue
        if all(part in line for part in MAIN_PUSH_GATE_PARTS):
            continue
        step_start = 0
        for start in step_starts:
            if start <= number - 1:
                step_start = start
            else:
                break
        context = lines[step_start:number]
        if any(
            "if:" in context_line and all(part in context_line for part in MAIN_PUSH_GATE_PARTS)
            for context_line in context
        ):
            continue
        errors.append(
            f"line {number}: cache-auth-token secret reaches a pull_request-triggered "
            "workflow without a push-to-main gate"
        )
    return errors


def validate(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
        # BaseLoader keeps YAML scalars as strings and, unlike SafeLoader's
        # YAML 1.1 rules, never turns the workflow key `on` into boolean true.
        data = yaml.load(text, Loader=yaml.BaseLoader)
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
        return [f"cannot parse workflow: {error}"]
    lines = text.splitlines()
    errors: list[str] = []

    if not isinstance(data, dict):
        return ["workflow root must be a mapping"]

    if has_trigger(data.get("on"), "pull_request_target"):
        errors.append("pull_request_target is forbidden")

    errors.extend(cache_token_errors(lines, has_trigger(data.get("on"), "pull_request")))

    if "permissions" not in data:
        errors.append("top-level permissions block is required")
    else:
        errors.extend(permission_errors(data["permissions"], "top-level", True))

    jobs = data.get("jobs", {})
    if not isinstance(jobs, dict):
        errors.append("jobs must be a mapping")
    else:
        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                errors.append(f"job {job_name!r} must be a mapping")
                continue
            if "permissions" in job:
                errors.extend(
                    permission_errors(
                        job["permissions"], "job-level", False,
                        allowed_writes=JOB_WRITE_ALLOWLIST.get(path.name),
                    )
                )

    for number, line in enumerate(lines, start=1):
        if ANY_ACTION.match(line) and not PINNED_ACTION.match(line):
            # Local composite actions use a path (./path/to/action) not a SHA.
            if line.strip().startswith("- uses: ./"):
                continue
            errors.append(f"line {number}: action must use a full commit SHA")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workflows", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for workflow in args.workflows:
        for error in validate(workflow):
            print(f"{workflow}: {error}", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
