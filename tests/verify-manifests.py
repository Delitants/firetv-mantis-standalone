#!/usr/bin/env python3
"""Behavioral safety tests for Fire TV package manifests."""

import pathlib
import re
import sys
import tempfile


MANDATORY_CORE = (
    "amazon.fireos",
    "com.amazon.adep",
    "com.amazon.autopairservice",
    "com.amazon.connectivitycontroller",
    "com.amazon.connectivitydiag",
    "com.amazon.cpl",
    "com.amazon.device.bluetoothdfu",
    "com.amazon.device.bluetoothkeymaplib",
    "com.amazon.device.bluetoothpa",
    "com.amazon.device.settings",
    "com.amazon.device.settings.sdk.internal.library",
    "com.amazon.dialservice",
    "com.amazon.dp.logger",
    "com.amazon.fireinputdevices",
    "com.amazon.ftv.xpicker",
    "com.amazon.ftvads.deeplinking",
    "com.amazon.net.smartconnect",
    "com.amazon.ssdpservice",
    "com.amazon.tcomm",
    "com.amazon.tcomm.client",
    "com.amazon.tv.devicecontrol",
    "com.amazon.tv.devicecontrolsettings",
    "com.amazon.tv.ime",
    "com.amazon.tv.intentsupport",
    "com.amazon.tv.keypolicymanager",
    "com.amazon.tv.settings.core",
    "com.amazon.tv.settings.v2",
    "com.amazon.tv.launcher",
    "com.amazon.tv.routing",
    "com.amazon.uxcontrollerservice",
    "com.amazon.vizzini",
    "com.amazon.vizzini.ftvcds",
    "com.amazon.webview",
    "com.amazon.webview.chromium",
    "com.amazon.whasettings",
    "com.amazon.wifilocker",
    "com.amazon.whisperjoin.middleware.np",
    "com.amazon.whisperjoin.wss.wifiprovisioner",
    "com.amazon.whisperlink.core.android",
    "com.amazon.whisperplay.contracts",
    "com.amazon.whisperplay.service.install",
    "com.android.bluetooth",
    "com.android.bluetoothmidiservice",
    "com.android.packageinstaller",
    "com.android.providers.settings",
    "com.android.settings",
    "com.android.systemui",
)

MANDATORY_USER_APPS = (
    "ar.tvplayer.tv",
    "com.wireguard.android",
    "tv.sweet.tvplayer",
    "com.wolf.firelauncher",
)


class ValidationError(Exception):
    """A package manifest violates the conservative safety contract."""


PACKAGE_NAME = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$")
MANIFEST_NAMES = (
    "preserve-core.txt",
    "preserve-user-apps.txt",
    "remove-user0.txt",
)


def read_manifest(directory, name):
    path = directory / name
    if not path.is_file():
        raise ValidationError(f"missing manifest: {name}")
    packages = path.read_text(encoding="utf-8").splitlines()
    if not packages:
        raise ValidationError(f"empty manifest: {name}")
    for package in packages:
        if package != package.strip() or not PACKAGE_NAME.fullmatch(package):
            raise ValidationError(f"invalid package token in {name}: {package!r}")
    return packages


def validate_manifests(directory):
    directory = pathlib.Path(directory)
    manifests = {name: read_manifest(directory, name) for name in MANIFEST_NAMES}
    for name, packages in manifests.items():
        seen = set()
        for package in packages:
            if package in seen:
                raise ValidationError(f"duplicate package {package} in {name}")
            seen.add(package)

    core = set(manifests["preserve-core.txt"])
    user_apps = set(manifests["preserve-user-apps.txt"])
    removal = set(manifests["remove-user0.txt"])
    missing_core = set(MANDATORY_CORE) - core
    if missing_core:
        raise ValidationError(f"missing mandatory core package: {sorted(missing_core)[0]}")
    if user_apps != set(MANDATORY_USER_APPS):
        raise ValidationError("preserve-user-apps.txt must contain exactly the protected user apps")
    for package in removal:
        lowered = package.lower()
        if package in set(MANDATORY_USER_APPS) or package in set(MANDATORY_CORE):
            raise ValidationError(f"protected package removal: {package}")
        if package.startswith("com.android.bluetooth"):
            raise ValidationError(f"Bluetooth package is protected: {package}")
        if "whisper" in lowered:
            raise ValidationError(f"Whisper package is protected: {package}")
        if not package.startswith("com.amazon."):
            raise ValidationError(f"removal is not an Amazon package: {package}")
    overlap = (core | user_apps) & removal
    if overlap:
        raise ValidationError(f"preserve/removal overlap: {sorted(overlap)[0]}")

    return len(core) + len(user_apps), len(removal)


def write_manifest(directory, name, packages):
    (directory / name).write_text("\n".join(packages) + "\n", encoding="utf-8")


def positive_fixture(directory):
    write_manifest(directory, "preserve-core.txt", MANDATORY_CORE)
    write_manifest(directory, "preserve-user-apps.txt", MANDATORY_USER_APPS)
    write_manifest(directory, "remove-user0.txt", ("com.amazon.bueller.music",))


def assert_rejected(directory, description, expected_error):
    try:
        validate_manifests(directory)
    except ValidationError as error:
        if expected_error not in str(error):
            raise AssertionError(f"wrong rejection for {description}: {error}")
        return
    raise AssertionError(f"accepted unsafe manifest: {description}")


def run_self_test():
    with tempfile.TemporaryDirectory(prefix="mantis-manifest-tests-") as temporary:
        root = pathlib.Path(temporary)

        positive_fixture(root)
        assert validate_manifests(root) == (len(MANDATORY_CORE) + len(MANDATORY_USER_APPS), 1)

        write_manifest(root, "preserve-core.txt", MANDATORY_CORE[1:])
        assert_rejected(root, "missing mandatory core package", "missing mandatory core package")
        positive_fixture(root)

        write_manifest(root, "preserve-user-apps.txt", MANDATORY_USER_APPS[1:])
        assert_rejected(root, "missing mandatory user app", "must contain exactly")
        positive_fixture(root)

        write_manifest(root, "preserve-user-apps.txt", MANDATORY_USER_APPS + ("com.amazon.extra",))
        assert_rejected(root, "unexpected preserved user app", "must contain exactly")
        positive_fixture(root)

        write_manifest(root, "preserve-core.txt", MANDATORY_CORE + (MANDATORY_CORE[0],))
        assert_rejected(root, "duplicate package", "duplicate package")
        positive_fixture(root)

        write_manifest(root, "preserve-core.txt", MANDATORY_CORE + ("com.amazon.optional.safe",))
        write_manifest(root, "remove-user0.txt", ("com.amazon.bueller.music", "com.amazon.optional.safe"))
        assert_rejected(root, "preserve and removal overlap", "preserve/removal overlap")
        positive_fixture(root)

        for package in MANDATORY_USER_APPS:
            write_manifest(root, "remove-user0.txt", (package,))
            assert_rejected(root, f"protected user app {package}", "protected package removal")
        positive_fixture(root)

        for package in MANDATORY_CORE:
            write_manifest(root, "remove-user0.txt", (package,))
            assert_rejected(root, f"mandatory core package {package}", "protected package removal")
        positive_fixture(root)

        for package, description, expected_error in (
            ("com.android.bluetooth.widget", "Bluetooth family", "Bluetooth package is protected"),
            ("com.amazon.network.whisperhelper", "Whisper family", "Whisper package is protected"),
            ("com.example.unrelated", "non-Amazon removal", "not an Amazon package"),
            (" ", "blank token", "invalid package token"),
            ("com.amazon.bueller.music ", "blank-space token", "invalid package token"),
            ("com.amazon.bueller;music", "semicolon token", "invalid package token"),
            ("com.amazon.*", "wildcard token", "invalid package token"),
        ):
            write_manifest(root, "remove-user0.txt", (package,))
            assert_rejected(root, description, expected_error)
            positive_fixture(root)


def main(argv):
    if argv == ["--self-test"]:
        run_self_test()
        print("MANIFEST_TESTS=PASS")
        return 0
    if len(argv) != 1:
        print("usage: verify-manifests.py [--self-test|MANIFEST_DIRECTORY]", file=sys.stderr)
        return 64
    preserve, remove = validate_manifests(pathlib.Path(argv[0]))
    print(f"MANIFESTS=PASS preserve={preserve} remove={remove}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (AssertionError, ValidationError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
