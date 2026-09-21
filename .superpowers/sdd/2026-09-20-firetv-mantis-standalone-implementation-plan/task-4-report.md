# Task 4 — Wolf Integrity Verification and Installation

## Scope

Implemented `install-wolf` as an offline-testable, target-gated workflow. It
downloads only the pinned Wolf 0.1.9-Wolf URL into a `mktemp -d` directory,
requires the pinned length, APK SHA-256, package metadata, activity, v1/v2
verification, and signer certificate before calling `adb install -r`.
It then reads back the exact installed version and direct-starts
`com.wolf.firelauncher/.screens.launcher.LauncherActivity`. The temporary APK
is removed by the exit trap. No APK is committed.

The workflow reports `WOLF_VERIFY=PASS`, `WOLF_INSTALL=PASS`, and direct launch
evidence. It also explicitly states the boundary: these checks prove artifact
integrity and signer continuity only; they do not establish publisher
authenticity or malware safety.

## RED evidence

1. `sh tests/run-tests.sh` exited `1` before implementation with:
   `FAIL: Wolf positive fixture failed: usage: mantis-tool.sh ... audit|apply`.
   The failure was the missing `install-wolf` behavior.
2. The fixture was then changed to the normal fully-qualified `aapt` activity
   form. The focused installer test exited `1` with:
   `Wolf verification failed: activity expected=.screens.launcher.LauncherActivity actual=com.wolf.firelauncher.screens.launcher.LauncherActivity`.
   This caught the representation mismatch before adding the equivalence check.

## GREEN evidence

- Focused fixture command (offline; fixture `curl`, `aapt`, `apksigner`, hash,
  and `adb`) completed `0` and printed `WOLF_VERIFY=PASS` and
  `WOLF_INSTALL=PASS`. It also asserted the state transition
  `11723945 0.1.7-FireTV` → `11900120 0.1.9-Wolf` and that the temporary APK
  path recorded by curl no longer existed.
- `sh tests/run-tests.sh` is green in the shared verification run. The suite
  covers wrong URL, size, hash, package, both version fields, both minSdk
  directions, targetSdk, install location, activity, v1/v2, signer mismatch,
  successful install/readback/direct launch, and the 0.1.7 upgrade fixture.
  Every rejection asserts no `adb install`, uninstall, or clear invocation.

## Files

- `scripts/mantis-tool.sh`
- `tests/run-tests.sh`
- `tests/fixtures/adb`
- `tests/fixtures/curl`, `aapt`, `apksigner`, `sha256sum`, and `shasum`

## Self-review

- Pins match the supplied URL, size, SHA-256, metadata, signer, and component.
- Installation follows all integrity/identity checks; signer mismatch leaves
  the fixture's pre-existing 0.1.7 launcher state unchanged.
- The normal fully-qualified `aapt` activity spelling is accepted only when it
  denotes the pinned component; unrelated activities remain rejected.
- No target, manifest, audit, rollback, protected-app, or APK repository state
  was changed.

## Remaining concern

This is fixture-only verification by design. The real archived APK, real tools,
and a live `mantis/AFTMM` target were intentionally not contacted in this task;
publisher authenticity and malware safety remain outside these pins.
