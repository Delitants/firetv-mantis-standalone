#!/usr/bin/env python3
"""Print the title of the one focused, clickable stock Settings grid tile."""

import sys
import xml.etree.ElementTree as ET


def main() -> int:
    try:
        root = ET.fromstring(sys.stdin.read())
    except ET.ParseError as exc:
        print(f"Settings grid hierarchy is invalid: {exc}", file=sys.stderr)
        return 1

    titles = []
    for node in root.iter("node"):
        if node.get("focused") != "true" or node.get("clickable") != "true":
            continue
        labels = [
            child.get("text", "")
            for child in node.iter("node")
            if child.get("resource-id") == "com.amazon.tv.launcher:id/title_text"
        ]
        if len(labels) == 1 and labels[0]:
            titles.append(labels[0])
    if len(titles) != 1:
        print(f"Settings grid has {len(titles)} focused tiles", file=sys.stderr)
        return 1
    print(titles[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
