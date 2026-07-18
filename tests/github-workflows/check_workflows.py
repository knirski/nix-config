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


def has_trigger(value: object, trigger: str) -> bool:
    if isinstance(value, str):
        return value == trigger
    if isinstance(value, list):
        return trigger in value
    if isinstance(value, dict):
        return trigger in value
    return False


def permission_errors(value: object, scope: str, require_contents: bool, *, allow_write: bool = False) -> list[str]:
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
    if not allow_write and any(permission == "write" for permission in value.values()):
        errors.append(f"{scope} write permission is forbidden")
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
                # Pre-approved workflows that need write permissions for
                # legitimate purposes (e.g. automated PR reviews). Keep
                # this set minimal — review additions carefully.
                allow_write_job = path.name in {"pr-agent.yml"}
                errors.extend(
                    permission_errors(
                        job["permissions"], "job-level", False,
                        allow_write=allow_write_job,
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
