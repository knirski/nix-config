#!/usr/bin/env python3
"""Deterministic repository-local Markdown and discoverability checks."""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
import unicodedata
from collections import defaultdict, deque
from pathlib import Path
from urllib.parse import unquote

ALLOWED_STATUSES = {"canonical", "active", "completed", "superseded", "historical"}
NAVIGATION_ROOTS = {"README.md", "docs/README.md", "AGENTS.md"}
PRIMARY_INDEX = "docs/README.md"
MANAGED_HOST_DOCS = {"hosts/soyo/DEPLOY.md", "hosts/zbook/INSTALL.md", "hosts/zbook/DEPLOY.md", "hosts/macbook/INSTALL.md"}
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)|!\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")


def github_heading_text(markdown: str) -> str:
    markdown = re.sub(r"!\[([^]]*)\]\([^)]*\)", r"\1", markdown)
    markdown = re.sub(r"\[([^]]+)\]\([^)]*\)", r"\1", markdown)
    return markdown.replace("`", "")


def github_slug(value: str) -> str:
    value = github_heading_text(value).strip().lower()
    # github-slugger removes punctuation, preserves Unicode letters/numbers and
    # hyphens, then replaces each ASCII space (including repeated spaces).
    value = "".join(
        char
        for char in value
        if char in {" ", "-"} or unicodedata.category(char)[0] in {"L", "M", "N"}
    )
    return value.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    result: set[str] = set()
    counts: defaultdict[str, int] = defaultdict(int)
    fenced = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        match = None if fenced else HEADING_RE.match(line)
        if not match:
            continue
        base = github_slug(match.group(2))
        occurrence = counts[base]
        counts[base] += 1
        result.add(base if occurrence == 0 else f"{base}-{occurrence}")
    return result


def links(path: Path) -> list[str]:
    return [
        match.group(1) or match.group(2)
        for match in LINK_RE.finditer(path.read_text(encoding="utf-8"))
    ]


def managed_documents(repo: Path) -> set[str]:
    docs = {str(path.relative_to(repo)) for path in (repo / "docs").rglob("*.md")}
    return docs | {path for path in MANAGED_HOST_DOCS if (repo / path).exists()}


def check_repository(repo: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = repo / "docs/status.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))["documents"]
    managed = managed_documents(repo)

    if set(manifest) != managed:
        for path in sorted(managed - set(manifest)):
            errors.append(f"status manifest missing document: {path}")
        for path in sorted(set(manifest) - managed):
            errors.append(f"status manifest references missing document: {path}")
    for path, metadata in manifest.items():
        if metadata.get("status") not in ALLOWED_STATUSES:
            errors.append(
                f"invalid lifecycle status for {path}: {metadata.get('status')!r}"
            )
        replacement = metadata.get("replacement")
        if replacement and not (repo / replacement).exists():
            errors.append(f"missing replacement for {path}: {replacement}")

    graph: defaultdict[str, set[str]] = defaultdict(set)
    primary_links: set[str] = set()
    scanned = managed | NAVIGATION_ROOTS
    anchor_cache: dict[Path, set[str]] = {}
    for relative in sorted(scanned):
        source = repo / relative
        if not source.exists():
            errors.append(f"missing navigation root: {relative}")
            continue
        for raw_target in links(source):
            target = raw_target.strip().strip("<>")
            if target.startswith(("http://", "https://", "mailto:", "app://")):
                continue
            if target.startswith("/"):
                errors.append(
                    f"{relative}: absolute local link is not portable: {target}"
                )
                continue
            file_part, separator, fragment = target.partition("#")
            decoded_file = unquote(file_part)
            destination = source if not decoded_file else source.parent / decoded_file
            destination = destination.resolve()
            try:
                destination_relative = str(destination.relative_to(repo.resolve()))
            except ValueError:
                errors.append(f"{relative}: link escapes repository: {target}")
                continue
            if not destination.exists():
                errors.append(f"{relative}: missing link target: {target}")
                continue
            graph[relative].add(destination_relative)
            if relative == PRIMARY_INDEX:
                primary_links.add(destination_relative)
            if separator and fragment and destination.suffix.lower() == ".md":
                expected = unquote(fragment).lower()
                available = anchor_cache.setdefault(destination, anchors(destination))
                if expected not in available:
                    errors.append(
                        f"{relative}: missing anchor #{fragment} in {destination_relative}"
                    )

    reachable = set(NAVIGATION_ROOTS)
    queue = deque(NAVIGATION_ROOTS)
    while queue:
        for destination in graph[queue.popleft()]:
            if destination not in reachable:
                reachable.add(destination)
                queue.append(destination)
    for path in sorted(managed - reachable):
        errors.append(f"orphaned managed document: {path}")
    for path, metadata in manifest.items():
        if (
            path != PRIMARY_INDEX
            and metadata.get("status") in {"active", "canonical"}
            and path not in primary_links
        ):
            errors.append(f"active document lacks primary docs index link: {path}")
    return errors


def self_test(repo: Path) -> None:
    fixture = repo / "tests/docs/fixtures/github-slugs.md.fixture"
    expected = {
        "hello-world",
        "zażółć-gęślą",
        "inline-code--punctuation",
        "repeat",
        "repeat-1",
    }
    assert anchors(fixture) == expected, (anchors(fixture), expected)

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        (root / "docs").mkdir()
        (root / "README.md").write_text("[Docs](docs/README.md)\n", encoding="utf-8")
        (root / "AGENTS.md").write_text("# Rules\n", encoding="utf-8")
        (root / "docs/README.md").write_text("# Docs\n", encoding="utf-8")
        broken = (repo / "tests/docs/fixtures/broken-link.md.fixture").read_text(
            encoding="utf-8"
        )
        (root / "docs/broken.md").write_text(broken, encoding="utf-8")
        anchor_target = repo / "tests/docs/fixtures/anchor-target.md.fixture"
        broken_anchor = repo / "tests/docs/fixtures/broken-anchor.md.fixture"
        (root / "docs/anchor-target.md").write_text(
            anchor_target.read_text(encoding="utf-8"), encoding="utf-8"
        )
        (root / "docs/broken-anchor.md").write_text(
            broken_anchor.read_text(encoding="utf-8"), encoding="utf-8"
        )
        manifest = {
            "schemaVersion": 1,
            "documents": {
                "docs/README.md": {"status": "canonical"},
                "docs/broken.md": {"status": "active"},
                "docs/anchor-target.md": {"status": "historical"},
                "docs/broken-anchor.md": {"status": "historical"},
            },
        }
        (root / "docs/status.json").write_text(json.dumps(manifest), encoding="utf-8")
        failures = check_repository(root)
        assert any("missing link target" in failure for failure in failures), failures
        assert any("missing anchor" in failure for failure in failures), failures
        assert any("lacks primary" in failure for failure in failures), failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    if args.self_test:
        self_test(repo)
    errors = check_repository(repo)
    if errors:
        print("Documentation correctness failures:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(
        "Documentation links, anchors, lifecycle status, and discoverability are valid."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
