#!/usr/bin/env python3
"""Reject legacy GhostLock builds with a persistent root service."""

import pathlib
import struct
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-root-binary.py FILE", file=sys.stderr)
        return 64
    try:
        binary = pathlib.Path(sys.argv[1]).read_bytes()
    except OSError as error:
        print(f"ROOT_BINARY_REJECTED unreadable: {error}", file=sys.stderr)
        return 1
    expected = b"[ROOT] uid=0 exec-only SELinux="
    forbidden = (
        b"[ROOT] uid=0 daemon pid=",
        b"--enable-bind-shell",
        b"[su] bare-su mount failed",
    )
    is_arm_elf32 = (
        len(binary) >= 52
        and binary[:4] == b"\x7fELF"
        and binary[4:6] == b"\x01\x01"
        and struct.unpack_from("<H", binary, 18)[0] == 40
    )
    if not is_arm_elf32 or expected not in binary or any(marker in binary for marker in forbidden):
        print(
            "ROOT_BINARY_REJECTED expected ARM ELF32 patched exec-only GhostLock build; "
            "legacy daemon or bind-shell build is not allowed",
            file=sys.stderr,
        )
        return 1
    print("ROOT_BINARY_IDENTITY=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
