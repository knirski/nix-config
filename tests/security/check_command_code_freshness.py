#!/usr/bin/env python3
"""Fail if the vendored command-code npm dependency tree has gone longer
than its documented staleness window without a human review.

This intentionally does NOT live in `nix flake check`. A staleness check is
inherently a function of wall-clock time, and a `checks.*` derivation is
cached by its (time-independent) inputs -- once built and substituted from
Cachix, it would never re-run just because time passed, silently freezing
"pass" forever and defeating the whole point. `builtins.currentTime` would
avoid that particular caching trap but requires `--impure`, which would
break ordinary offline `nix flake check` outright. So this is a plain,
offline script (no network, no --impure) invoked as its own CI step in
ci.yml's `static` job -- which reads the true wall clock fresh on every run
-- and is also runnable locally via `just lint`.

The reviewed date is locally recorded in
modules/_pkgs/command-code-lock/last-reviewed.json by whoever last ran
`just update-command-code` (or manually re-confirmed the current pin and
its overrides are still appropriate); this script never contacts the npm
registry.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path


def days_since(recorded: datetime.date, today: datetime.date) -> int:
    return (today - recorded).days


def check(record_path: Path, today: datetime.date) -> list[str]:
    data = json.loads(record_path.read_text(encoding="utf-8"))
    recorded = datetime.date.fromisoformat(data["date"])
    stale_after = int(data["staleAfterDays"])
    elapsed = days_since(recorded, today)
    if elapsed < 0:
        return [
            f"{record_path}: recorded date {data['date']} is in the future "
            f"relative to {today.isoformat()}"
        ]
    if elapsed > stale_after:
        return [
            f"{record_path}: command-code (version {data.get('version', '?')}) "
            f"was last reviewed {elapsed} days ago on {data['date']}, "
            f"exceeding the {stale_after}-day staleness window. Run "
            "`just update-command-code <version>` (even a no-op re-run "
            "against the current version) to review the vendored npm tree "
            "and OpenTelemetry override, then update this file's `date`."
        ]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "record",
        type=Path,
        help="path to command-code-lock/last-reviewed.json",
    )
    parser.add_argument(
        "--today",
        type=datetime.date.fromisoformat,
        default=None,
        help="override 'today' as YYYY-MM-DD (for testing only)",
    )
    args = parser.parse_args()
    today = args.today or datetime.datetime.now(datetime.timezone.utc).date()

    failures = check(args.record, today)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
