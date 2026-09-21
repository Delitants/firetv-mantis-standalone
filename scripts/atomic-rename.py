#!/usr/bin/env python3
import ctypes
import os
import stat
import sys

DARWIN_AT_FDCWD = -2
DARWIN_RENAME_EXCL = 0x00000004
LINUX_AT_FDCWD = -100
LINUX_RENAME_NOREPLACE = 0x00000001


def strategy(platform_name):
    if platform_name.startswith("darwin"):
        return "darwin"
    if platform_name.startswith("linux"):
        return "linux"
    raise RuntimeError(f"unsupported platform for atomic no-replace rename: {platform_name}")


def trusted_parent(path):
    parent = os.path.dirname(path) or "."
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(parent, flags)
    try:
        opened = os.fstat(descriptor)
        named = os.lstat(parent)
    finally:
        os.close(descriptor)
    if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
        raise RuntimeError(f"untrusted parent directory: {parent}")
    if not stat.S_ISDIR(opened.st_mode) or opened.st_uid != os.geteuid() or opened.st_mode & 0o022:
        raise RuntimeError(f"untrusted parent directory: {parent}")


def source_identity(source):
    trusted_parent(source)
    source_stat = os.lstat(source)
    if not stat.S_ISDIR(source_stat.st_mode) or stat.S_ISLNK(source_stat.st_mode):
        raise RuntimeError("staging path is not a directory")
    if source_stat.st_uid != os.geteuid() or source_stat.st_mode & 0o777 != 0o700:
        raise RuntimeError("staging directory is not controller-private")
    return source_stat.st_dev, source_stat.st_ino


def darwin_rename(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameatx_np = libc.renameatx_np
    except AttributeError as error:
        raise RuntimeError("renameatx_np with RENAME_EXCL is unavailable") from error
    renameatx_np.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameatx_np.restype = ctypes.c_int
    return renameatx_np(DARWIN_AT_FDCWD, os.fsencode(source), DARWIN_AT_FDCWD, os.fsencode(destination), DARWIN_RENAME_EXCL)


def linux_rename(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameat2 = libc.renameat2
    except AttributeError:
        syscall_numbers = {"x86_64": 316, "amd64": 316, "aarch64": 276, "arm64": 276, "armv7l": 382, "i386": 353}
        number = syscall_numbers.get(os.uname().machine.lower())
        if number is None:
            raise RuntimeError("renameat2 syscall number is unknown for this Linux architecture")
        return libc.syscall(number, LINUX_AT_FDCWD, os.fsencode(source), LINUX_AT_FDCWD, os.fsencode(destination), LINUX_RENAME_NOREPLACE)
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    return renameat2(LINUX_AT_FDCWD, os.fsencode(source), LINUX_AT_FDCWD, os.fsencode(destination), LINUX_RENAME_NOREPLACE)


def publish(source, destination, expected_device, expected_inode):
    trusted_parent(source)
    trusted_parent(destination)
    if source_identity(source) != (expected_device, expected_inode):
        raise RuntimeError("staging directory changed after creation")
    selected = strategy(sys.platform)
    if selected == "darwin":
        result = darwin_rename(source, destination)
    else:
        result = linux_rename(source, destination)
    if result != 0:
        raise OSError(ctypes.get_errno(), "atomic no-replace rename failed")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "inspect":
        device, inode = source_identity(sys.argv[2])
        print(f"{device} {inode}")
        return 0
    if len(sys.argv) == 6 and sys.argv[1] == "publish":
        publish(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "strategy":
        selected = strategy(sys.argv[2])
        if selected == "darwin":
            print("darwin: renameatx_np(RENAME_EXCL)")
        else:
            print("linux: renameat2(RENAME_NOREPLACE)")
        return 0
    print("usage: atomic-rename.py inspect SOURCE | publish SOURCE DESTINATION DEVICE INODE | strategy PLATFORM", file=sys.stderr)
    return 64


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AttributeError, OSError, RuntimeError, ValueError) as error:
        print(f"atomic rename failed: {error}", file=sys.stderr)
        raise SystemExit(1)
