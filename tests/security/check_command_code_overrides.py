#!/usr/bin/env python3
"""Shared predicate: prove the vendored command-code npm dependency tree
actually resolved the CVE-2026-54285 (GHSA-8988-4f7v-96qf) OpenTelemetry
override, not merely that modules/_pkgs/command-code.nix's postPatch claims
to apply it.

This is the exact same code path exercised by two callers, so the
verification logic itself cannot silently drift or be vacuous:

  1. modules/parts/command-code-security-checks.nix's real check, against
     the actual built package's node_modules tree.
  2. That same check module's negative fixtures under
     tests/security/command-code-overrides/{pass,reject-*}/, fabricated
     node_modules trees proving this predicate actually rejects a vulnerable
     version or a dropped override -- not just that it accepts the real
     build.

The override floor versions come from modules/_pkgs/command-code-lock/
opentelemetry-overrides.json, the single source of truth also read by
command-code.nix's postPatch and scripts/update-command-code.sh.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_version(version: str) -> tuple[int, ...]:
    """Parse a dotted numeric version, ignoring any -prerelease/+build tag."""
    core = version.split("-", 1)[0].split("+", 1)[0]
    parts = core.split(".")
    return tuple(int(part) for part in parts[:3])


def version_at_least(actual: str, floor: str) -> bool:
    return parse_version(actual) >= parse_version(floor)


def load_overrides(overrides_json: Path) -> list[dict[str, str]]:
    data = json.loads(overrides_json.read_text(encoding="utf-8"))
    return data["overrides"]


def verify(node_modules: Path, overrides: list[dict[str, str]]) -> list[str]:
    """Return human-readable failure reasons; an empty list means every
    override is satisfied in the given node_modules tree."""
    failures: list[str] = []
    for override in overrides:
        name = override["package"]
        floor = override["minVersion"]
        package_json = node_modules / name / "package.json"
        if not package_json.is_file():
            failures.append(f"{name}: missing from node_modules (override not applied)")
            continue
        try:
            resolved = json.loads(package_json.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            failures.append(f"{name}: unreadable package.json ({error})")
            continue
        actual = resolved.get("version")
        if not actual:
            failures.append(f"{name}: package.json has no version field")
            continue
        if not version_at_least(actual, floor):
            failures.append(
                f"{name}: resolved {actual}, expected >= {floor} "
                "(CVE-2026-54285 / GHSA-8988-4f7v-96qf fix)"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("node_modules", type=Path, help="node_modules root to verify")
    parser.add_argument(
        "overrides_json",
        type=Path,
        help="path to opentelemetry-overrides.json (the override registry)",
    )
    args = parser.parse_args()

    overrides = load_overrides(args.overrides_json)
    failures = verify(args.node_modules, overrides)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
