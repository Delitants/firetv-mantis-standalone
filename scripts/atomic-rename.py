#!/usr/bin/env python3
"""Publish one private staging directory without following raced pathnames.

The shell populates the 0700 staging directory by pathname before this helper
runs. Mutation rights granted to a different UID through access ACLs are
rejected on retained descriptors. Code running as the same effective user can
already read or modify controller-owned state and remains outside this helper's
threat boundary, including the final validation-to-rename interval. Publication
pins both trusted parents and never uses a pathname for cleanup.
"""

import ctypes
import ctypes.util
import errno
import os
import stat
import sys

DARWIN_RENAME_EXCL = 0x00000004
LINUX_RENAME_NOREPLACE = 0x00000001

DARWIN_ACL_TYPE_EXTENDED = 0x00000100
DARWIN_ACL_FIRST_ENTRY = 0
DARWIN_ACL_NEXT_ENTRY = -1
DARWIN_ACL_EXTENDED_ALLOW = 1
DARWIN_ACL_EXTENDED_DENY = 2
DARWIN_ACL_DANGEROUS_PERMISSIONS = (
    (1 << 2)  # write data / add file
    | (1 << 4)  # delete
    | (1 << 5)  # append data / add subdirectory
    | (1 << 6)  # delete child
    | (1 << 8)  # write attributes
    | (1 << 10)  # write extended attributes
    | (1 << 12)  # write ACL/security metadata
    | (1 << 13)  # change owner
)
DARWIN_ID_TYPE_UID = 0

LINUX_ACL_FIRST_ENTRY = 0
LINUX_ACL_NEXT_ENTRY = 1
LINUX_ACL_USER_OBJ = 0x01
LINUX_ACL_USER = 0x02
LINUX_ACL_GROUP_OBJ = 0x04
LINUX_ACL_GROUP = 0x08
LINUX_ACL_MASK = 0x10
LINUX_ACL_OTHER = 0x20
LINUX_ACL_WRITE = 0x02


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


def acl_error(operation):
    error_number = ctypes.get_errno()
    if error_number:
        return OSError(error_number, operation)
    return RuntimeError(f"{operation}: ACL safety cannot be determined")


def configure_common_acl_api(library):
    library.acl_get_entry.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)]
    library.acl_get_entry.restype = ctypes.c_int
    library.acl_get_tag_type.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
    library.acl_get_tag_type.restype = ctypes.c_int
    library.acl_get_qualifier.argtypes = [ctypes.c_void_p]
    library.acl_get_qualifier.restype = ctypes.c_void_p
    library.acl_free.argtypes = [ctypes.c_void_p]
    library.acl_free.restype = ctypes.c_int


def darwin_assert_safe_access_acl(descriptor, owner_uid):
    library = ctypes.CDLL(None, use_errno=True)
    required = (
        "acl_get_fd_np",
        "acl_get_entry",
        "acl_get_tag_type",
        "acl_get_permset_mask_np",
        "acl_get_qualifier",
        "acl_free",
        "mbr_uuid_to_id",
    )
    if any(not hasattr(library, name) for name in required):
        raise RuntimeError("Darwin ACL inspection is unavailable")
    configure_common_acl_api(library)
    library.acl_get_fd_np.argtypes = [ctypes.c_int, ctypes.c_int]
    library.acl_get_fd_np.restype = ctypes.c_void_p
    library.acl_get_permset_mask_np.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)]
    library.acl_get_permset_mask_np.restype = ctypes.c_int
    library.mbr_uuid_to_id.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_int),
    ]
    library.mbr_uuid_to_id.restype = ctypes.c_int

    ctypes.set_errno(0)
    acl = library.acl_get_fd_np(descriptor, DARWIN_ACL_TYPE_EXTENDED)
    if not acl:
        if ctypes.get_errno() == errno.ENOENT:
            return
        raise acl_error("acl_get_fd_np failed")
    try:
        entry = ctypes.c_void_p()
        entry_id = DARWIN_ACL_FIRST_ENTRY
        while True:
            ctypes.set_errno(0)
            result = library.acl_get_entry(acl, entry_id, ctypes.byref(entry))
            if result != 0:
                if entry_id == DARWIN_ACL_NEXT_ENTRY and ctypes.get_errno() == errno.EINVAL:
                    break
                raise acl_error("acl_get_entry failed")
            tag = ctypes.c_int()
            ctypes.set_errno(0)
            if library.acl_get_tag_type(entry, ctypes.byref(tag)) != 0:
                raise acl_error("acl_get_tag_type failed")
            if tag.value == DARWIN_ACL_EXTENDED_ALLOW:
                permissions = ctypes.c_uint64()
                ctypes.set_errno(0)
                if library.acl_get_permset_mask_np(entry, ctypes.byref(permissions)) != 0:
                    raise acl_error("acl_get_permset_mask_np failed")
                if permissions.value & DARWIN_ACL_DANGEROUS_PERMISSIONS:
                    ctypes.set_errno(0)
                    qualifier = library.acl_get_qualifier(entry)
                    if not qualifier:
                        raise acl_error("acl_get_qualifier failed")
                    try:
                        principal_id = ctypes.c_uint32()
                        principal_type = ctypes.c_int()
                        result = library.mbr_uuid_to_id(
                            qualifier,
                            ctypes.byref(principal_id),
                            ctypes.byref(principal_type),
                        )
                        if result != 0:
                            raise RuntimeError(
                                "Darwin ACL principal cannot be resolved safely"
                            )
                        if (
                            principal_type.value != DARWIN_ID_TYPE_UID
                            or principal_id.value != owner_uid
                        ):
                            raise RuntimeError(
                                "unsafe access ACL grants non-owner write authority"
                            )
                    finally:
                        library.acl_free(qualifier)
            elif tag.value != DARWIN_ACL_EXTENDED_DENY:
                raise RuntimeError("Darwin ACL contains an unknown entry type")
            entry_id = DARWIN_ACL_NEXT_ENTRY
    finally:
        library.acl_free(acl)


def linux_acl_library():
    candidates = [ctypes.util.find_library("acl"), "libacl.so.1"]
    for candidate in candidates:
        if not candidate:
            continue
        try:
            return ctypes.CDLL(candidate, use_errno=True)
        except OSError:
            continue
    raise RuntimeError("Linux POSIX ACL inspection is unavailable")


def linux_assert_safe_access_acl(descriptor, owner_uid):
    library = linux_acl_library()
    required = (
        "acl_get_fd",
        "acl_get_entry",
        "acl_get_tag_type",
        "acl_get_permset",
        "acl_get_perm",
        "acl_get_qualifier",
        "acl_free",
    )
    if any(not hasattr(library, name) for name in required):
        raise RuntimeError("Linux POSIX ACL inspection is unavailable")
    configure_common_acl_api(library)
    library.acl_get_fd.argtypes = [ctypes.c_int]
    library.acl_get_fd.restype = ctypes.c_void_p
    library.acl_get_permset.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    library.acl_get_permset.restype = ctypes.c_int
    library.acl_get_perm.argtypes = [ctypes.c_void_p, ctypes.c_int]
    library.acl_get_perm.restype = ctypes.c_int

    ctypes.set_errno(0)
    acl = library.acl_get_fd(descriptor)
    if not acl:
        raise acl_error("acl_get_fd failed")
    try:
        entry = ctypes.c_void_p()
        entry_id = LINUX_ACL_FIRST_ENTRY
        while True:
            ctypes.set_errno(0)
            result = library.acl_get_entry(acl, entry_id, ctypes.byref(entry))
            if result == 0:
                break
            if result < 0:
                raise acl_error("acl_get_entry failed")
            tag = ctypes.c_int()
            ctypes.set_errno(0)
            if library.acl_get_tag_type(entry, ctypes.byref(tag)) != 0:
                raise acl_error("acl_get_tag_type failed")
            if tag.value not in {
                LINUX_ACL_USER_OBJ,
                LINUX_ACL_USER,
                LINUX_ACL_GROUP_OBJ,
                LINUX_ACL_GROUP,
                LINUX_ACL_MASK,
                LINUX_ACL_OTHER,
            }:
                raise RuntimeError("Linux ACL contains an unknown entry type")
            permission_set = ctypes.c_void_p()
            ctypes.set_errno(0)
            if library.acl_get_permset(entry, ctypes.byref(permission_set)) != 0:
                raise acl_error("acl_get_permset failed")
            ctypes.set_errno(0)
            writable = library.acl_get_perm(permission_set, LINUX_ACL_WRITE)
            if writable < 0:
                raise acl_error("acl_get_perm failed")
            if writable and tag.value == LINUX_ACL_USER:
                ctypes.set_errno(0)
                qualifier = library.acl_get_qualifier(entry)
                if not qualifier:
                    raise acl_error("acl_get_qualifier failed")
                try:
                    principal_id = ctypes.cast(
                        qualifier, ctypes.POINTER(ctypes.c_uint32)
                    ).contents.value
                finally:
                    library.acl_free(qualifier)
                if principal_id != owner_uid:
                    raise RuntimeError(
                        "unsafe access ACL grants non-owner write authority"
                    )
            elif writable and tag.value in {
                LINUX_ACL_GROUP_OBJ,
                LINUX_ACL_GROUP,
                LINUX_ACL_OTHER,
            }:
                raise RuntimeError(
                    "unsafe access ACL grants non-owner write authority"
                )
            entry_id = LINUX_ACL_NEXT_ENTRY
    finally:
        library.acl_free(acl)


def assert_safe_access_acl(descriptor, owner_uid):
    selected = strategy(sys.platform)
    if selected == "darwin":
        darwin_assert_safe_access_acl(descriptor, owner_uid)
    else:
        linux_assert_safe_access_acl(descriptor, owner_uid)


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
        assert_safe_access_acl(descriptor, opened.st_uid)
        return descriptor, name
    except Exception:
        os.close(descriptor)
        raise


def source_identity_at(parent_descriptor, name):
    source_stat = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    if not stat.S_ISDIR(source_stat.st_mode):
        raise RuntimeError("staging path is not a directory")
    if source_stat.st_uid != os.geteuid() or stat.S_IMODE(source_stat.st_mode) != 0o700:
        raise RuntimeError("staging directory is not controller-private")
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    flags |= getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(name, flags, dir_fd=parent_descriptor)
    try:
        opened = os.fstat(descriptor)
        if (opened.st_dev, opened.st_ino) != (source_stat.st_dev, source_stat.st_ino):
            raise RuntimeError("staging directory changed during validation")
        if (
            not stat.S_ISDIR(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or stat.S_IMODE(opened.st_mode) != 0o700
        ):
            raise RuntimeError("staging directory is not controller-private")
        assert_safe_access_acl(descriptor, opened.st_uid)
    finally:
        os.close(descriptor)
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
