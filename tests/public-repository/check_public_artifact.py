#!/usr/bin/env python3
"""Validate an explicitly public SVG against the repository disclosure policy."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ALLOWED_TEXT = {
    "Backup target",
    "Critical roles",
    "DHCP",
    "DNS",
    "DNS + DHCP appliance",
    "Encrypted backups",
    "Encrypted DNS",
    "Home LAN",
    "Internet",
    "Isolated guest services",
    "Public architecture overview",
    "Remote access",
    "Role and trust flow overview",
    "Router",
    "Upstream DNS",
    "VPN",
    "VPN administration",
    "Workstation",
}

PROHIBITED_PATTERNS = {
    "IPv4 address": re.compile(r"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])"),
    "IPv6 address": re.compile(
        r"(?i)(?<![0-9a-f:])(?:"
        r"(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4}|"
        r"(?:[0-9a-f]{1,4}:){1,7}:|"
        r"(?:[0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}|"
        r"(?:[0-9a-f]{1,4}:){1,5}(?::[0-9a-f]{1,4}){1,2}|"
        r"(?:[0-9a-f]{1,4}:){1,4}(?::[0-9a-f]{1,4}){1,3}|"
        r"(?:[0-9a-f]{1,4}:){1,3}(?::[0-9a-f]{1,4}){1,4}|"
        r"(?:[0-9a-f]{1,4}:){1,2}(?::[0-9a-f]{1,4}){1,5}|"
        r"[0-9a-f]{1,4}:(?:(?::[0-9a-f]{1,4}){1,6})|"
        r":(?:(?::[0-9a-f]{1,4}){1,7}|:)"
        r")(?![0-9a-f:])"
    ),
    "MAC address": re.compile(r"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f])"),
    "disk or device path": re.compile(r"(?i)(?:/dev/|\b(?:ata|nvme)-[a-z0-9._-]+|\bUUID=)"),
    "network interface": re.compile(
        r"(?i)\b(?:enp\w+|eno\w+|ens\w+|eth\d+|wlan\w+|wl[a-z0-9]+|"
        r"tailscale\d+|virbr\d+|veth\w+|wg\d+|tun\d+|tap\d+|br\d+|"
        r"bond\d+|docker\d+|en\d+)\b"
    ),
    "username or home path": re.compile(r"(?i)(?:\bkrzysiek\b|/home/[a-z0-9._-]+)"),
    "rescue addressing": re.compile(r"(?i)(?:\bdirect[- ]link\b|\brescue\b|192\.168\.254\.)"),
    "known LAN device label": re.compile(
        r"(?i)\b(?:soyo|zbook|czworaczki|drukarka|twins|orbi(?:-satellite)?(?:-[12])?)\b"
    ),
}

ALLOWED_ELEMENTS = {"defs", "desc", "g", "marker", "path", "rect", "svg", "text", "title", "tspan"}
ALLOWED_ATTRIBUTES = {
    "aria-labelledby",
    "d",
    "fill",
    "font-family",
    "font-size",
    "font-weight",
    "height",
    "id",
    "marker-end",
    "markerHeight",
    "markerWidth",
    "orient",
    "refX",
    "refY",
    "role",
    "rx",
    "stroke",
    "stroke-dasharray",
    "stroke-width",
    "text-anchor",
    "viewBox",
    "width",
    "x",
    "y",
}
MAX_BYTES = 4 * 1024
MAX_WIDTH = 1600
MAX_HEIGHT = 900
URL_RE = re.compile(r"(?i)(?:https?://|data:|javascript:|//[^/])")
NUMBER_RE = re.compile(r"-?(?:\d+(?:\.\d+)?|\.\d+)")
PATH_RE = re.compile(r"[MmLlHhVvZz0-9.,\- ]+")


def approved_attribute_value(name: str, value: str) -> bool:
    """Restrict attributes to the small vocabulary needed by our renderer."""
    exact = {
        "aria-labelledby": {"overview-title overview-description"},
        "font-family": {"sans-serif"},
        "id": {"arrow", "overview-description", "overview-title"},
        "marker-end": {"url(#arrow)"},
        "orient": {"auto-start-reverse"},
        "role": {"img"},
        "text-anchor": {"middle"},
    }
    if name in exact:
        return value in exact[name]
    if name in {"fill", "stroke"}:
        return value == "none" or re.fullmatch(r"#[0-9a-fA-F]{6}", value) is not None
    if name == "d":
        return PATH_RE.fullmatch(value) is not None
    if name == "viewBox":
        return len(value.split()) == 4 and all(NUMBER_RE.fullmatch(part) for part in value.split())
    if name == "stroke-dasharray":
        return all(NUMBER_RE.fullmatch(part) for part in value.split())
    return NUMBER_RE.fullmatch(value) is not None


def local_name(name: str) -> str:
    return name.rsplit("}", 1)[-1]


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        size = path.stat().st_size
        if size > MAX_BYTES:
            return [f"exceeds {MAX_BYTES}-byte size limit: {size} bytes"]
        serialized_text = path.read_text(encoding="utf-8")
        root = ET.fromstring(serialized_text)
    except (ET.ParseError, OSError, UnicodeDecodeError) as error:
        return [f"cannot parse SVG: {error}"]

    if local_name(root.tag) != "svg":
        errors.append("root element is not svg")

    try:
        width = float(root.attrib["width"])
        height = float(root.attrib["height"])
        view_box = [float(value) for value in root.attrib["viewBox"].split()]
        if len(view_box) != 4:
            raise ValueError("viewBox must contain four numbers")
        if width > MAX_WIDTH or height > MAX_HEIGHT or view_box[2] > MAX_WIDTH or view_box[3] > MAX_HEIGHT:
            errors.append(f"dimensions exceed {MAX_WIDTH}x{MAX_HEIGHT}")
    except (KeyError, ValueError) as error:
        errors.append(f"invalid or missing dimensions: {error}")

    for label, pattern in PROHIBITED_PATTERNS.items():
        if match := pattern.search(serialized_text):
            errors.append(f"contains prohibited {label}: {match.group(0)!r}")

    visible_text: set[str] = set()
    for element in root.iter():
        tag = local_name(element.tag)
        if tag not in ALLOWED_ELEMENTS:
            errors.append(f"contains unapproved <{tag}> element")

        for raw_name, value in element.attrib.items():
            name = local_name(raw_name)
            if name not in ALLOWED_ATTRIBUTES:
                errors.append(f"contains unapproved attribute {name!r}")
            elif not approved_attribute_value(name, value):
                errors.append(f"contains unapproved value for attribute {name!r}")
            if name.lower().startswith("on"):
                errors.append(f"contains event-handler attribute {name!r}")
            if name in {"href", "src"} and value and not value.startswith("#"):
                errors.append(f"contains external resource reference {value!r}")
            if URL_RE.search(value) or re.search(r"(?i)url\((?!\s*#)", value):
                errors.append(f"contains external or active URL in {name!r}")

        # SVG accessibility metadata is visible to assistive technology and
        # search indexers, so it follows the same vocabulary as drawn labels.
        if element.text and (normalized := " ".join(element.text.split())):
            if tag in {"desc", "text", "title", "tspan"}:
                visible_text.add(normalized)
            else:
                errors.append(f"contains text in non-text element <{tag}>")
        if element.tail and (normalized_tail := " ".join(element.tail.split())):
            if tag == "tspan":
                visible_text.add(normalized_tail)
            else:
                errors.append(f"contains text outside a text element after <{tag}>")

    unexpected = sorted(visible_text - ALLOWED_TEXT)
    if unexpected:
        errors.append("contains text outside the public vocabulary: " + ", ".join(repr(x) for x in unexpected))

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("svg", type=Path)
    args = parser.parse_args()
    errors = validate(args.svg)
    if errors:
        print(f"{args.svg}: public artifact rejected", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
