#!/usr/bin/env python3
"""Run one host command with a hard wall-clock limit and inherited output."""

import math
import os
import subprocess
import sys


def operation_label(command) -> str:
    """Identify an ADB timeout without echoing serials or command arguments."""
    if os.path.basename(command[0]) != "adb":
        return ""
    args = command[1:]
    if len(args) >= 2 and args[0] == "-s":
        args = args[2:]
    if not args:
        return " operation=adb"
    if args[0] == "shell":
        shell_args = args[1:]
        if len(shell_args) >= 2 and shell_args[0] == "pm":
            action = shell_args[1]
            if action in {"disable-user", "enable", "list", "path"}:
                return f" operation=adb.shell.pm.{action}"
        if len(shell_args) >= 2 and shell_args[:2] == ["settings", "get"]:
            return " operation=adb.shell.settings.get"
        if shell_args[:1] == ["getprop"]:
            return " operation=adb.shell.getprop"
        if len(shell_args) >= 2 and shell_args[0] == "dumpsys" and shell_args[1] in {
            "package", "window", "bluetooth_manager", "wifi"
        }:
            return f" operation=adb.shell.dumpsys.{shell_args[1]}"
        if shell_args[:3] == ["cmd", "package", "resolve-activity"]:
            return " operation=adb.shell.cmd.package.resolve-activity"
        if shell_args[:2] == ["uiautomator", "dump"]:
            return " operation=adb.shell.uiautomator.dump"
        if shell_args and shell_args[0] in {"cat", "netstat", "pidof"}:
            return f" operation=adb.shell.{shell_args[0]}"
    action = args[0]
    if action in {"shell", "install", "push", "pull", "get-state", "devices", "connect", "wait-for-device"}:
        return f" operation=adb.{action}"
    return " operation=adb.other"


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: run-bounded.py SECONDS COMMAND [ARG ...]", file=sys.stderr)
        return 64
    try:
        seconds = float(sys.argv[1])
    except ValueError:
        return 64
    if not math.isfinite(seconds) or seconds <= 0:
        return 64
    command = sys.argv[2:]
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, timeout=seconds)
    except subprocess.TimeoutExpired:
        print(
            f"COMMAND_TIMEOUT seconds={seconds:g} executable={os.path.basename(command[0])}"
            f"{operation_label(command)}",
            file=sys.stderr,
        )
        return 124
    except FileNotFoundError:
        print(f"COMMAND_NOT_FOUND executable={command[0]}", file=sys.stderr)
        return 127
    except OSError as error:
        print(f"COMMAND_ERROR executable={command[0]} error={error}", file=sys.stderr)
        return 126
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == "__main__":
    sys.exit(main())
