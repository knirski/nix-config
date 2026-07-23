#!/usr/bin/env python3
"""Prove the KVM-classified check set cannot silently drift between ci.yml's
"Strict KVM behavior tests" job, the justfile's `test-resilience` recipe, and
the canonical list in lib/testing/kvm-checks.nix.

The canonical list is passed in via --expect by the Nix check that invokes
this script (modules/parts/kvm-gate-drift-check.nix), so this script never
hardcodes the check names itself -- it only proves the two textual surfaces
(ci.yml, justfile) actually agree with whatever Nix considers canonical.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

CHECK_REF = re.compile(r"checks\.x86_64-linux\.([A-Za-z0-9_-]+)")

KVM_JOB_NAME = "Strict KVM behavior tests"
JUSTFILE_RECIPE = "test-resilience"


def names_from_ci(ci_yml_path: Path) -> set[str]:
    workflow = yaml.safe_load(ci_yml_path.read_text(encoding="utf-8"))
    jobs = workflow.get("jobs", {}) if workflow else {}

    for job in jobs.values():
        if job.get("name") == KVM_JOB_NAME:
            run_text = "\n".join(
                step["run"] for step in job.get("steps", []) if "run" in step
            )
            return set(CHECK_REF.findall(run_text))

    raise SystemExit(
        f"check_kvm_gate: no job named {KVM_JOB_NAME!r} found in {ci_yml_path}"
    )


def names_from_justfile(justfile_path: Path) -> set[str]:
    lines = justfile_path.read_text(encoding="utf-8").splitlines(keepends=True)
    recipe_header = re.compile(rf"^{re.escape(JUSTFILE_RECIPE)}(\s+\S+)*\s*:")

    recipe_lines: list[str] = []
    in_recipe = False
    for line in lines:
        if recipe_header.match(line):
            in_recipe = True
            recipe_lines.append(line)
            continue
        if in_recipe:
            # `just` recipe bodies are indented; an unindented, non-blank
            # line ends the recipe.
            if line.strip() == "" or line[:1] in (" ", "\t"):
                recipe_lines.append(line)
                continue
            break

    if not recipe_lines:
        raise SystemExit(
            f"check_kvm_gate: no `{JUSTFILE_RECIPE}` recipe found in {justfile_path}"
        )

    return set(CHECK_REF.findall("".join(recipe_lines)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ci-yml", required=True, type=Path)
    parser.add_argument("--justfile", required=True, type=Path)
    parser.add_argument(
        "--expect",
        required=True,
        help="comma-separated canonical KVM check names (from lib/testing/kvm-checks.nix)",
    )
    args = parser.parse_args()

    expected = set(filter(None, args.expect.split(",")))
    ci_names = names_from_ci(args.ci_yml)
    just_names = names_from_justfile(args.justfile)

    problems = []
    if not expected:
        problems.append("--expect supplied an empty canonical KVM check list")
    if ci_names != expected:
        problems.append(
            f"ci.yml {KVM_JOB_NAME!r} job builds {sorted(ci_names)}, "
            f"expected {sorted(expected)}"
        )
    if just_names != expected:
        problems.append(
            f"justfile `{JUSTFILE_RECIPE}` recipe builds {sorted(just_names)}, "
            f"expected {sorted(expected)}"
        )

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
