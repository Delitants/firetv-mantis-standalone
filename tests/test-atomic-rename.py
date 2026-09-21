#!/usr/bin/env python3
import ctypes
import ctypes.util
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "atomic-rename.py"
RACE_FIXTURE = ROOT / "tests" / "fixtures" / "atomic-race"


def make_directory(path):
    path.mkdir(mode=0o700)
    path.chmod(0o700)


def inspect(source):
    completed = subprocess.run(
        [sys.executable, "-B", str(HELPER), "inspect", str(source)],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip().split()


def inspect_result(source):
    return subprocess.run(
        [sys.executable, "-B", str(HELPER), "inspect", str(source)],
        check=False,
        capture_output=True,
        text=True,
    )


def publish(source, destination, device, inode):
    return subprocess.run(
        [
            sys.executable,
            "-B",
            str(HELPER),
            "publish",
            str(source),
            str(destination),
            str(device),
            str(inode),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def non_owner_uid():
    nobody = pwd.getpwnam("nobody").pw_uid
    if nobody == os.geteuid():
        raise RuntimeError("the ACL test requires a UID other than the effective UID")
    return nobody


def linux_acl_library():
    candidates = [ctypes.util.find_library("acl"), "libacl.so.1"]
    for candidate in candidates:
        if not candidate:
            continue
        try:
            return ctypes.CDLL(candidate, use_errno=True)
        except OSError:
            continue
    raise RuntimeError("libacl is unavailable for the Linux ACL regression test")


def add_non_owner_write_acl(path):
    if sys.platform == "darwin":
        subprocess.run(
            [
                "chmod",
                "+a",
                "everyone allow add_file,add_subdirectory,delete_child",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return
    if sys.platform.startswith("linux"):
        library = linux_acl_library()
        library.acl_from_text.argtypes = [ctypes.c_char_p]
        library.acl_from_text.restype = ctypes.c_void_p
        library.acl_set_fd.argtypes = [ctypes.c_int, ctypes.c_void_p]
        library.acl_set_fd.restype = ctypes.c_int
        library.acl_free.argtypes = [ctypes.c_void_p]
        library.acl_free.restype = ctypes.c_int
        acl_text = f"u::rwx,u:{non_owner_uid()}:rwx,g::---,m::rwx,o::---"
        acl = library.acl_from_text(acl_text.encode())
        if not acl:
            raise OSError(ctypes.get_errno(), "acl_from_text failed")
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if library.acl_set_fd(descriptor, acl) != 0:
                raise OSError(ctypes.get_errno(), "acl_set_fd failed")
        finally:
            os.close(descriptor)
            library.acl_free(acl)
        path.chmod(0o700)
        return
    raise RuntimeError(f"unsupported ACL test platform: {sys.platform}")


def publish_with_race(source, destination, race, record):
    device, inode = inspect(source)
    environment = os.environ.copy()
    environment.update(
        {
            "ATOMIC_RENAME_RACE": race,
            "ATOMIC_RENAME_SOURCE": str(source),
            "ATOMIC_RENAME_DESTINATION": str(destination),
            "ATOMIC_RENAME_RACE_RECORD": str(record),
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONPATH": str(RACE_FIXTURE),
        }
    )
    return subprocess.run(
        [
            sys.executable,
            "-B",
            str(HELPER),
            "publish",
            str(source),
            str(destination),
            device,
            inode,
        ],
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )


class AtomicRenameValidationTests(unittest.TestCase):
    def test_special_permission_bits_are_not_exact_private_mode(self):
        """Catches masking off sticky/set-id bits instead of requiring exact 0700."""
        with tempfile.TemporaryDirectory(prefix="mantis-special-mode-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            source = source_parent / "audit.tmp"
            make_directory(source_parent)
            make_directory(source)
            source.chmod(0o1700)

            completed = inspect_result(source)

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("staging directory is not controller-private", completed.stderr)

    def test_non_owner_write_acl_on_source_parent_is_rejected(self):
        """Catches trusting owner/mode bits when a different UID can replace entries."""
        with tempfile.TemporaryDirectory(prefix="mantis-parent-acl-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            source = source_parent / "audit.tmp"
            make_directory(source_parent)
            make_directory(source)
            add_non_owner_write_acl(source_parent)
            self.assertEqual(source_parent.stat().st_mode & 0o7777, 0o700)

            completed = inspect_result(source)

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("unsafe access ACL", completed.stderr)

    def test_non_owner_write_acl_on_staging_directory_is_rejected(self):
        """Catches publishing checksummed content that another UID can still modify."""
        with tempfile.TemporaryDirectory(prefix="mantis-stage-acl-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            source = source_parent / "audit.tmp"
            make_directory(source_parent)
            make_directory(source)
            add_non_owner_write_acl(source)
            self.assertEqual(source.stat().st_mode & 0o7777, 0o700)

            completed = inspect_result(source)

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("unsafe access ACL", completed.stderr)

    def test_non_owner_write_acl_on_destination_parent_is_rejected(self):
        """Catches trusting the destination parent without descriptor ACL checks."""
        with tempfile.TemporaryDirectory(prefix="mantis-destination-acl-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            destination_parent = root / "destination-parent"
            source = source_parent / "audit.tmp"
            destination = destination_parent / "audit"
            make_directory(source_parent)
            make_directory(destination_parent)
            make_directory(source)
            device, inode = inspect(source)
            add_non_owner_write_acl(destination_parent)
            self.assertEqual(destination_parent.stat().st_mode & 0o7777, 0o700)

            completed = publish(source, destination, device, inode)

            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("unsafe access ACL", completed.stderr)
            self.assertTrue(source.is_dir())
            self.assertFalse(destination.exists())


class AtomicRenameRaceTests(unittest.TestCase):
    def test_post_stat_replacement_documents_same_effective_uid_boundary(self):
        """Uses the real rename to pin the remaining same-effective-UID boundary."""
        with tempfile.TemporaryDirectory(prefix="mantis-post-stat-race-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            destination_parent = root / "destination-parent"
            attacker_target = root / "attacker-target"
            make_directory(source_parent)
            make_directory(destination_parent)
            make_directory(attacker_target)
            (attacker_target / "keep.txt").write_text(
                "same-euid attacker content\n", encoding="utf-8"
            )
            source = source_parent / "audit.tmp"
            destination = destination_parent / "audit"
            make_directory(source)
            (source / "device.txt").write_text("owned audit\n", encoding="utf-8")
            record = root / "race-record"

            device, inode = inspect(source)
            environment = os.environ.copy()
            environment.update(
                {
                    "ATOMIC_RENAME_RACE": "post-stat-source-replacement",
                    "ATOMIC_RENAME_SOURCE": str(source),
                    "ATOMIC_RENAME_DESTINATION": str(destination),
                    "ATOMIC_RENAME_ATTACKER_TARGET": str(attacker_target),
                    "ATOMIC_RENAME_RACE_RECORD": str(record),
                    "PYTHONDONTWRITEBYTECODE": "1",
                    "PYTHONPATH": str(RACE_FIXTURE),
                }
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(HELPER),
                    "publish",
                    str(source),
                    str(destination),
                    device,
                    inode,
                ],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertTrue(
                record.is_file(),
                "real helper did not expose a post-stat/pre-rename source boundary",
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(destination.is_symlink())
            self.assertEqual(destination.resolve(), attacker_target.resolve())
            self.assertEqual(
                (Path(f"{source}.original") / "device.txt").read_text(
                    encoding="utf-8"
                ),
                "owned audit\n",
            )

    def test_parent_path_replacement_uses_retained_directory_descriptors(self):
        """Catches closing parent FDs or passing AT_FDCWD to the rename syscall."""
        with tempfile.TemporaryDirectory(prefix="mantis-parent-race-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            destination_parent = root / "destination-parent"
            make_directory(source_parent)
            make_directory(destination_parent)
            source = source_parent / "audit.tmp"
            destination = destination_parent / "audit"
            make_directory(source)
            (source / "device.txt").write_text("owned audit\n", encoding="utf-8")
            record = root / "race-record"

            completed = publish_with_race(
                source, destination, "parent-path-replacement", record
            )

            self.assertTrue(
                record.is_file(),
                "real helper did not retain both parent FDs through final source validation",
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            displaced_destination = Path(f"{destination_parent}.opened") / "audit"
            self.assertEqual(
                (displaced_destination / "device.txt").read_text(encoding="utf-8"),
                "owned audit\n",
            )
            self.assertFalse(destination.exists())
            self.assertEqual(
                (destination_parent / "keep.txt").read_text(encoding="utf-8"),
                "replacement destination parent\n",
            )
            self.assertEqual(
                (source_parent / "keep.txt").read_text(encoding="utf-8"),
                "replacement source parent\n",
            )

    def test_late_source_replacement_is_rejected_by_final_relative_validation(self):
        """Catches validating the source before opening parents or only by full path."""
        with tempfile.TemporaryDirectory(prefix="mantis-source-race-") as temporary:
            root = Path(temporary)
            source_parent = root / "source-parent"
            destination_parent = root / "destination-parent"
            make_directory(source_parent)
            make_directory(destination_parent)
            source = source_parent / "audit.tmp"
            destination = destination_parent / "audit"
            make_directory(source)
            (source / "device.txt").write_text("owned audit\n", encoding="utf-8")
            record = root / "race-record"

            completed = publish_with_race(
                source, destination, "late-source-replacement", record
            )

            self.assertTrue(
                record.is_file(),
                "real helper did not perform final dirfd-relative source validation",
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("staging directory changed after creation", completed.stderr)
            self.assertFalse(destination.exists())
            self.assertEqual(
                (source / "keep.txt").read_text(encoding="utf-8"),
                "late source replacement\n",
            )
            self.assertEqual(
                (Path(f"{source}.original") / "device.txt").read_text(
                    encoding="utf-8"
                ),
                "owned audit\n",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
