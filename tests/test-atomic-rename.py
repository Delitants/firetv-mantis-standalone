#!/usr/bin/env python3
import os
from pathlib import Path
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


class AtomicRenameRaceTests(unittest.TestCase):
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
