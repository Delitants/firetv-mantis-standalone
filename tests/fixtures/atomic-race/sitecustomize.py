import os


RACE = os.environ.get("ATOMIC_RENAME_RACE")
SOURCE = os.environ.get("ATOMIC_RENAME_SOURCE")
DESTINATION = os.environ.get("ATOMIC_RENAME_DESTINATION")
RECORD = os.environ.get("ATOMIC_RENAME_RACE_RECORD")

_real_open = os.open
_real_stat = os.stat
_opened_parents = set()
_triggered = False


def _absolute(path):
    return os.path.abspath(os.fsdecode(path))


def race_open(path, flags, mode=0o777, *, dir_fd=None):
    if dir_fd is None:
        descriptor = _real_open(path, flags, mode)
        candidate = _absolute(path)
        if SOURCE and candidate == os.path.dirname(SOURCE):
            _opened_parents.add("source")
        if DESTINATION and candidate == os.path.dirname(DESTINATION):
            _opened_parents.add("destination")
        return descriptor
    return _real_open(path, flags, mode, dir_fd=dir_fd)


def _write(path, value):
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(value)


def _replace_parent(path, label):
    displaced = f"{path}.opened"
    os.rename(path, displaced)
    os.mkdir(path, 0o700)
    _write(os.path.join(path, "keep.txt"), f"replacement {label} parent\n")


def _trigger_race():
    if RACE == "parent-path-replacement":
        _replace_parent(os.path.dirname(SOURCE), "source")
        _replace_parent(os.path.dirname(DESTINATION), "destination")
    elif RACE == "late-source-replacement":
        displaced = f"{SOURCE}.original"
        os.rename(SOURCE, displaced)
        os.mkdir(SOURCE, 0o700)
        _write(os.path.join(SOURCE, "keep.txt"), "late source replacement\n")
    else:
        raise RuntimeError(f"unknown atomic rename race: {RACE}")
    _write(RECORD, f"{RACE}\n")


def race_stat(path, *, dir_fd=None, follow_symlinks=True):
    global _triggered
    if (
        not _triggered
        and RACE
        and SOURCE
        and dir_fd is not None
        and os.fsdecode(path) == os.path.basename(SOURCE)
        and _opened_parents == {"source", "destination"}
    ):
        _triggered = True
        _trigger_race()
    return _real_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)


if RACE:
    if not SOURCE or not DESTINATION or not RECORD:
        raise RuntimeError("atomic rename race fixture is missing paths")
    os.open = race_open
    os.stat = race_stat
