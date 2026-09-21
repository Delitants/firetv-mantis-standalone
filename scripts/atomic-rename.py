#!/usr/bin/env python3
"""Publish one private staging directory without following raced pathnames.

The shell populates the 0700 staging directory by pathname before this helper
runs. Code running as the same effective user can already read or modify that
controller-owned state and is outside this helper's threat boundary. The
publish operation still pins both trusted parents, validates the source entry
relative to its pinned parent immediately before the syscall, and never uses a
pathname for cleanup.
"""

import ctypes
import os
import stat
import sys

DARWIN_RENAME_EXCL = 0x00000004
LINUX_RENAME_NOREPLACE = 0x00000001


def strategy(platform_name):
    if platform_name.startswith("darwin"):
        return "darwin"
    if platform_name.startswith("linux"):
        return "linux"
    raise RuntimeError(f"unsupported platform for atomic no-replace rename: {platform_name}")


def path_parts(path):
    parent = os.path.dirname(path) or "."
    name = os.path.basename(path)
    if name in {"", ".", ".."}:
        raise RuntimeError(f"unsafe publication path: {path}")
    return parent, name


def open_trusted_parent(path):
    parent, name = path_parts(path)
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    flags |= getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(parent, flags)
    try:
        opened = os.fstat(descriptor)
        named = os.lstat(parent)
        if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
            raise RuntimeError(f"untrusted parent directory: {parent}")
        if not stat.S_ISDIR(opened.st_mode) or opened.st_uid != os.geteuid() or opened.st_mode & 0o022:
            raise RuntimeError(f"untrusted parent directory: {parent}")
        return descriptor, name
    except Exception:
        os.close(descriptor)
        raise


def source_identity_at(parent_descriptor, name):
    source_stat = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    if not stat.S_ISDIR(source_stat.st_mode):
        raise RuntimeError("staging path is not a directory")
    if source_stat.st_uid != os.geteuid() or source_stat.st_mode & 0o777 != 0o700:
        raise RuntimeError("staging directory is not controller-private")
    return source_stat.st_dev, source_stat.st_ino


def source_identity(source):
    parent_descriptor, name = open_trusted_parent(source)
    try:
        return source_identity_at(parent_descriptor, name)
    finally:
        os.close(parent_descriptor)


def darwin_renamer():
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameatx_np = libc.renameatx_np
    except AttributeError as error:
        raise RuntimeError("renameatx_np with RENAME_EXCL is unavailable") from error
    renameatx_np.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameatx_np.restype = ctypes.c_int

    def rename(source_parent, source_name, destination_parent, destination_name):
        return renameatx_np(
            source_parent,
            os.fsencode(source_name),
            destination_parent,
            os.fsencode(destination_name),
            DARWIN_RENAME_EXCL,
        )

    return rename


def linux_renamer():
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameat2 = libc.renameat2
    except AttributeError:
        syscall_numbers = {"x86_64": 316, "amd64": 316, "aarch64": 276, "arm64": 276, "armv7l": 382, "i386": 353}
        number = syscall_numbers.get(os.uname().machine.lower())
        if number is None:
            raise RuntimeError("renameat2 syscall number is unknown for this Linux architecture")
        syscall = libc.syscall

        def rename(source_parent, source_name, destination_parent, destination_name):
            return syscall(
                number,
                source_parent,
                os.fsencode(source_name),
                destination_parent,
                os.fsencode(destination_name),
                LINUX_RENAME_NOREPLACE,
            )

        return rename
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int

    def rename(source_parent, source_name, destination_parent, destination_name):
        return renameat2(
            source_parent,
            os.fsencode(source_name),
            destination_parent,
            os.fsencode(destination_name),
            LINUX_RENAME_NOREPLACE,
        )

    return rename


def load_renamer():
    selected = strategy(sys.platform)
    if selected == "darwin":
        return darwin_renamer()
    return linux_renamer()


def publish(source, destination, expected_device, expected_inode):
    rename = load_renamer()
    source_parent = -1
    destination_parent = -1
    try:
        source_parent, source_name = open_trusted_parent(source)
        destination_parent, destination_name = open_trusted_parent(destination)
        if source_identity_at(source_parent, source_name) != (expected_device, expected_inode):
            raise RuntimeError("staging directory changed after creation")
        result = rename(source_parent, source_name, destination_parent, destination_name)
        if result != 0:
            raise OSError(ctypes.get_errno(), "atomic no-replace rename failed")
    finally:
        if destination_parent >= 0:
            os.close(destination_parent)
        if source_parent >= 0:
            os.close(source_parent)


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
