#!/usr/bin/env python3
"""Enforce security properties that actionlint intentionally does not cover."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


PINNED_ACTION = re.compile(r"^\s*-\s+uses:\s+[^\s@]+@[0-9a-f]{40}(?:\s+#\s+\S.*)?$")
ANY_ACTION = re.compile(r"^\s*-\s+uses:\s+(\S+)")


def validate(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    errors: list[str] = []

    if re.search(r"(?m)^\s*pull_request_target\s*:", text):
        errors.append("pull_request_target is forbidden")

    permission_match = re.search(r"(?m)^permissions:\s*\n((?:^[ \t]+.*\n?)*)", text)
    if permission_match is None:
        errors.append("top-level permissions block is required")
    else:
        permissions = permission_match.group(1)
        if not re.search(r"(?m)^\s+contents:\s+read\s*$", permissions):
            errors.append("top-level permissions must include contents: read")
        if re.search(r"(?m)^\s+[-\w]+:\s+write\s*$", permissions):
            errors.append("top-level write permission is forbidden")

    job_permission_blocks = re.finditer(
        r"(?m)^(?P<indent>[ \t]+)permissions:\s*\n(?P<body>(?:^(?P=indent)[ \t]+.*\n?)*)",
        text,
    )
    for block in job_permission_blocks:
        if re.search(r"(?m)^\s+[-\w]+:\s+write\s*$", block.group("body")):
            errors.append("job-level write permission is forbidden")

    for number, line in enumerate(lines, start=1):
        if ANY_ACTION.match(line) and not PINNED_ACTION.match(line):
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
