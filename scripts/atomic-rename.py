#!/usr/bin/env python3
import ctypes
import os
import sys

AT_FDCWD = -2
RENAME_EXCL = 0x00000004


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: atomic-rename.py SOURCE DESTINATION", file=sys.stderr)
        return 64

    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameatx_np = libc.renameatx_np
    except AttributeError:
        print("renameatx_np with RENAME_EXCL is unavailable", file=sys.stderr)
        return 1

    renameatx_np.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameatx_np.restype = ctypes.c_int
    result = renameatx_np(
        AT_FDCWD,
        os.fsencode(sys.argv[1]),
        AT_FDCWD,
        os.fsencode(sys.argv[2]),
        RENAME_EXCL,
    )
    if result == 0:
        return 0

    error_number = ctypes.get_errno()
    print(f"atomic rename failed: {os.strerror(error_number)}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
