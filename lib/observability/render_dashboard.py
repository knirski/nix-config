#!/usr/bin/env python3
"""Render a downloaded Grafana dashboard without Nix evaluation-time I/O."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def replace_strings(value: Any, replacements: list[tuple[str, str]]) -> Any:
    if isinstance(value, str):
        for source, destination in replacements:
            value = value.replace(source, destination)
        return value
    if isinstance(value, list):
        return [replace_strings(item, replacements) for item in value]
    if isinstance(value, dict):
        return {
            key: replace_strings(item, replacements) for key, item in value.items()
        }
    return value


def render(dashboard: dict[str, Any], specification: dict[str, Any]) -> dict[str, Any]:
    configured = specification["replacements"]
    replacements = [
        (f"${{{item['key']}}}", item["value"]) for item in configured
    ]
    replacements.extend(
        (f'"${item["key"]}"', f'"{item["value"]}"') for item in configured
    )
    replacements.append(("$__rate_interval", "4m"))

    rendered = replace_strings(dashboard, replacements)
    template_names = {item["key"] for item in configured}
    templating = rendered.get("templating")
    if isinstance(templating, dict):
        template_list = templating.get("list")
        if isinstance(template_list, list):
            templating["list"] = [
                item
                for item in template_list
                if not isinstance(item, dict) or item.get("name") not in template_names
            ]
    rendered["tags"] = specification["tags"]
    rendered.update(specification["extraAttrs"])
    return rendered


def main() -> None:
    dashboard_path, specification_path, output_path = map(Path, sys.argv[1:])
    dashboard = json.loads(dashboard_path.read_text(encoding="utf-8"))
    specification = json.loads(specification_path.read_text(encoding="utf-8"))
    rendered = render(dashboard, specification)
    output_path.write_text(
        json.dumps(rendered, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
