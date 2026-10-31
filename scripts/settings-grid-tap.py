#!/usr/bin/env python3
"""Locate one enabled, clickable stock Settings tile by its visible title."""

import re
import sys
import xml.etree.ElementTree as ET

PACKAGE = "com.amazon.tv.launcher"
TITLE_ID = PACKAGE + ":id/title_text"
TITLES = {"Network", "Display & Sounds", "Accessibility", "Preferences"}
BOUNDS = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in TITLES:
        print("expected one supported stock Settings tile title", file=sys.stderr)
        return 2
    title = sys.argv[1]
    try:
        root = ET.fromstring(sys.stdin.buffer.read())
    except ET.ParseError as exc:
        print(f"Settings grid hierarchy is invalid: {exc}", file=sys.stderr)
        return 1

    centers = []
    for node in root.iter("node"):
        if any(
            node.get(key) != expected
            for key, expected in (
                ("package", PACKAGE),
                ("enabled", "true"),
                ("focusable", "true"),
                ("clickable", "true"),
            )
        ):
            continue
        labels = [child for child in node.iter("node") if child.get("resource-id") == TITLE_ID]
        if len(labels) != 1 or any(
            labels[0].get(key) != expected
            for key, expected in (("package", PACKAGE), ("enabled", "true"), ("text", title))
        ):
            continue
        match = BOUNDS.fullmatch(node.get("bounds", ""))
        if match is None:
            continue
        left, top, right, bottom = map(int, match.groups())
        if not (0 <= left < right <= 4096 and 0 <= top < bottom <= 2160):
            continue
        centers.append(((left + right) // 2, (top + bottom) // 2))

    if len(centers) != 1:
        print(f"Settings grid tile {title} has {len(centers)} usable matches", file=sys.stderr)
        return 1
    print(*centers[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
