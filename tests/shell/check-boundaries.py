#!/usr/bin/env python3
"""Keep repository-authored shell at a checked construction boundary."""

from __future__ import annotations

import sys
from pathlib import Path


EXPECTED_SOURCES = {
    "scripts/healthcheck.sh",
    "scripts/recover-secrets.sh",
    "scripts/set-tailscale-keys.sh",
    "tests/backup/restic-integration.sh",
}
EXPECTED_TEST_HARNESSES = {
    "tests/scripts/fixtures/fake-dig.bash",
    "tests/scripts/fixtures/fake-nix.bash",
    "tests/scripts/fixtures/fake-rage.bash",
    "tests/scripts/fixtures/fake-ssh.bash",
    "tests/scripts/healthcheck.bats",
    "tests/scripts/recover-secrets.bats",
    "tests/scripts/set-tailscale-keys.bats",
    "tests/scripts/test-helper.bash",
    "tests/shell/shared-env.bats",
}


def main(root: Path) -> int:
    errors: list[str] = []
    sources = {
        path.relative_to(root).as_posix()
        for base in (root / "scripts", root / "tests")
        if base.exists()
        for path in base.rglob("*.sh")
    }
    if sources != EXPECTED_SOURCES:
        missing = sorted(EXPECTED_SOURCES - sources)
        unchecked = sorted(sources - EXPECTED_SOURCES)
        if missing:
            errors.append(f"inventory names missing shell sources: {missing}")
        if unchecked:
            errors.append(f"new shell sources need classification: {unchecked}")

    harnesses = {
        path.relative_to(root).as_posix()
        for suffix in ("*.bash", "*.bats")
        for path in (root / "tests").rglob(suffix)
    }
    if harnesses != EXPECTED_TEST_HARNESSES:
        missing = sorted(EXPECTED_TEST_HARNESSES - harnesses)
        unchecked = sorted(harnesses - EXPECTED_TEST_HARNESSES)
        if missing:
            errors.append(f"inventory names missing structured test sources: {missing}")
        if unchecked:
            errors.append(
                f"new structured test sources need classification: {unchecked}"
            )

    ignored_components = {".cache", ".devenv", ".direnv", ".git"}
    for path in root.rglob("*.nix"):
        if ignored_components.intersection(path.relative_to(root).parts):
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            errors.append(f"{path.relative_to(root)}: cannot inspect Nix source: {error}")
            continue
        if "pkgs.writeShellScript" in source:
            errors.append(
                f"{path.relative_to(root)}: use checked writeShellApplication "
                "with explicit runtimeInputs"
            )

    for error in errors:
        print(error, file=sys.stderr)
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
