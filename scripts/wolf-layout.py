#!/usr/bin/env python3
"""Configure the pinned Wolf 0.1.9 Home layout through its visible UI.

No Wolf database or APK is modified. Every tap is based on a fresh Wolf UI
snapshot, and toggle states are read back from the on-screen indicators.
"""

import argparse
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

WOLF_PACKAGE = "com.wolf.firelauncher"
HOME = WOLF_PACKAGE + "/.screens.launcher.LauncherActivity"
BOUNDS = re.compile(r"^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$")
SIDEBAR_HEADER = WOLF_PACKAGE + ":id/sidebar_header"
SIDEBAR_ITEM = WOLF_PACKAGE + ":id/first_line"
SIDEBAR_CHECKBOX = WOLF_PACKAGE + ":id/check_box"
SECTION_TITLE = WOLF_PACKAGE + ":id/title"


class LayoutError(Exception):
    pass


class RawFrame:
    def __init__(self, data):
        if len(data) < 12:
            raise ValueError("short raw screencap")
        self.width, self.height, self.format = struct.unpack_from("<III", data)
        if not 640 <= self.width <= 4096 or not 360 <= self.height <= 2160:
            # Tests use a tiny synthetic frame.
            if not 1 <= self.width <= 4 or self.height != 1:
                raise ValueError("unexpected raw screencap dimensions")
        if self.format not in (1, 2, 3, 4):
            raise ValueError("unexpected raw screencap format")
        self.bytes_per_pixel = 3 if self.format == 3 else 4
        size = self.width * self.height * self.bytes_per_pixel
        if len(data) == 12 + size:
            offset = 12
        elif len(data) == 16 + size:
            offset = 16  # newer screencap includes a color-space word
        else:
            raise ValueError("raw screencap byte count mismatch")
        self.data = data[offset:]

    def pixel(self, x, y):
        if not 0 <= x < self.width or not 0 <= y < self.height:
            raise ValueError("sample outside screenshot")
        start = (y * self.width + x) * self.bytes_per_pixel
        return tuple(self.data[start : start + 3])


def marker_state(rgb):
    red, green, blue = rgb
    if green > red + 25 and green > blue + 20 and green > 120:
        return "hidden"
    if min(rgb) > 190 and max(rgb) - min(rgb) < 30:
        return "visible"
    raise LayoutError(f"Wolf tile marker has unknown color {rgb}")


def blue_download_icon(rgb):
    red, green, blue = rgb
    return blue > green + 35 and green > red + 40


def rows(root, labels, width, right_only=True):
    found = []
    for node in root.iter("node"):
        if node.get("package") != WOLF_PACKAGE or node.get("text") not in labels:
            continue
        match = BOUNDS.fullmatch(node.get("bounds", ""))
        if not match:
            continue
        box = tuple(map(int, match.groups()))
        if (not right_only or box[0] >= width * 0.64) and box[2] > box[0] and box[3] > box[1]:
            found.append((node.get("text"), box))
    return found


def resource_rows(root, resource_id, width, right_only=True):
    found = []
    for node in root.iter("node"):
        if node.get("package") != WOLF_PACKAGE or node.get("resource-id") != resource_id:
            continue
        match = BOUNDS.fullmatch(node.get("bounds", ""))
        if not match:
            continue
        box = tuple(map(int, match.groups()))
        if (not right_only or box[0] >= width * 0.64) and box[2] > box[0] and box[3] > box[1]:
            found.append((node.get("text", ""), box))
    return sorted(found, key=lambda row: (row[1][1], row[1][0]))


def sidebar_open(root, width):
    return bool(resource_rows(root, SIDEBAR_HEADER, width))


def sidebar_items(root, width):
    return resource_rows(root, SIDEBAR_ITEM, width)


def checkbox_items(root, width):
    return resource_rows(root, SIDEBAR_CHECKBOX, width)


class Device:
    def __init__(self, adb, serial):
        self.adb = adb
        self.serial = serial
        self.width = None
        self.height = None
        self.deadline = time.monotonic() + 300

    def command(self, *args, timeout=30):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise LayoutError("Wolf UI operation exceeded 300 seconds")
        result = subprocess.run(
            [self.adb, "-s", self.serial, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=min(timeout, remaining),
            check=False,
        )
        if result.returncode:
            raise LayoutError(
                f"ADB {args[0]} failed: {result.stderr.decode('utf-8', 'replace').strip()}"
            )
        return result.stdout

    def shell(self, *args):
        return self.command("shell", *args).decode("utf-8", "replace").strip()

    def frame(self):
        frame = RawFrame(self.command("exec-out", "screencap", timeout=35))
        self.width, self.height = frame.width, frame.height
        return frame

    def ui(self):
        for attempt in range(3):
            self.shell("uiautomator", "dump", "/data/local/tmp/mantis-wolf-layout.xml")
            xml = self.shell("cat", "/data/local/tmp/mantis-wolf-layout.xml")
            try:
                root = ET.fromstring(xml)
            except ET.ParseError:
                if attempt == 2:
                    raise LayoutError("Wolf UI hierarchy is unavailable")
                time.sleep(1)
                continue
            if root.find(".//node[@package='com.wolf.firelauncher']") is not None:
                return root
            if attempt == 2:
                raise LayoutError("foreground UI is not Wolf Launcher")
            time.sleep(1)
        raise LayoutError("Wolf UI hierarchy is unavailable")

    def tap(self, box):
        x = (box[0] + box[2]) // 2
        y = (box[1] + box[3]) // 2
        self.shell("input", "tap", str(x), str(y))
        time.sleep(0.35)

    def click_label(self, *labels):
        root = self.ui()
        candidates = rows(root, labels, self.width)
        if len(candidates) != 1:
            raise LayoutError(f"expected one Wolf row {labels}, found {len(candidates)}")
        self.tap(candidates[0][1])

    def open_home(self):
        self.shell("am", "start", "-n", HOME)
        time.sleep(0.8)
        self.frame()
        for _ in range(4):
            root = self.ui()
            if not sidebar_open(root, self.width):
                return root
            self.shell("input", "keyevent", "4")
            time.sleep(0.3)
        raise LayoutError("Wolf Settings sidebar remained open over Home")

    def open_settings(self):
        self.open_home()
        self.shell("input", "keyevent", "82")
        time.sleep(0.4)
        self.frame()
        root = self.ui()
        if not sidebar_open(root, self.width):
            raise LayoutError("Wolf Application Menu did not open")
        items = sidebar_items(root, self.width)
        if len(items) == 9 and not checkbox_items(root, self.width):
            # Pinned Wolf 0.1.9: Launcher Settings precedes Android and Other Settings.
            self.tap(items[-3][1])
        elif len(items) != 4 or checkbox_items(root, self.width):
            raise LayoutError("unexpected Wolf Application Menu layout")
        for _ in range(3):
            root = self.ui()
            if sidebar_open(root, self.width) and len(sidebar_items(root, self.width)) == 4 and not checkbox_items(root, self.width):
                return
            time.sleep(0.4)
        raise LayoutError("Wolf Launcher Settings menu did not open")

    def open_hidden(self):
        self.open_settings()
        self.tap(sidebar_items(self.ui(), self.width)[2][1])
        self.frame()
        root = self.ui()
        if not sidebar_open(root, self.width) or not checkbox_items(root, self.width):
            raise LayoutError("Wolf Hidden Tiles did not open")
        # Restore the alphabetical list to its start before each target.
        for _ in range(5):
            self.shell("input", "swipe", str(self.width * 4 // 5), str(self.height // 3),
                       str(self.width * 4 // 5), str(self.height * 4 // 5), "180")
        time.sleep(0.3)

    def page_rows(self, *labels):
        return rows(self.ui(), labels, self.width)

    def marker(self, box):
        frame = self.frame()
        x = frame.width - max(25, frame.width * 47 // 1920)
        y = (box[1] + box[3]) // 2 - max(7, frame.height * 13 // 1080)
        return marker_state(frame.pixel(x, y))

    def icon_blue(self, box):
        frame = self.frame()
        x = box[0] - max(25, frame.width * 56 // 1920)
        y = (box[1] + box[3]) // 2 - max(16, frame.height * 30 // 1080)
        return blue_download_icon(frame.pixel(x, y))

    def set_hidden(self, box, desired):
        if self.marker(box) == desired:
            return
        self.tap(box)
        if self.marker(box) != desired:
            raise LayoutError("Wolf tile visibility did not change as requested")

    def scan_pages(self, labels):
        seen = set()
        for _ in range(10):
            root = self.ui()
            page = rows(root, labels, self.width)
            signature = tuple((n.get("text"), n.get("bounds")) for n in root.iter("node")
                              if n.get("package") == WOLF_PACKAGE and n.get("text")
                              and BOUNDS.fullmatch(n.get("bounds", ""))
                              and int(BOUNDS.fullmatch(n.get("bounds"))[1]) >= self.width * 0.64)
            if signature in seen:
                break
            seen.add(signature)
            yield page
            self.shell("input", "swipe", str(self.width * 4 // 5), str(self.height * 4 // 5),
                       str(self.width * 4 // 5), str(self.height // 3), "250")
            time.sleep(0.35)

    def hide_named(self, *labels):
        self.open_hidden()
        found = 0
        for page in self.scan_pages(labels):
            found = max(found, len(page))
            for _, box in page:
                self.set_hidden(box, "hidden")
        print(f"WOLF_HIDDEN_{labels[0].upper().replace(' ', '_')}={found}")
        return found

    def verify_named_hidden(self, *labels, required=False):
        self.open_hidden()
        found = 0
        for page in self.scan_pages(labels):
            found = max(found, len(page))
            for _, box in page:
                if self.marker(box) != "hidden":
                    raise LayoutError(f"visible Wolf tile remained: {labels[0]}")
        if required and not found:
            raise LayoutError(f"Wolf tile missing from visibility list: {labels[0]}")

    def choose_downloads(self):
        self.open_hidden()
        found = [(box, self.icon_blue(box)) for _, box in self.page_rows("Downloads")]
        if len(found) < 2:
            print(f"WOLF_DOWNLOAD_TILES={len(found)} skipped=no-duplicate")
            return
        if len(found) != 2 or sum(is_blue for _, is_blue in found) != 1:
            raise LayoutError("Downloads duplicates cannot be identified by icon")
        blue_box = next(box for box, is_blue in found if is_blue)
        other_box = next(box for box, is_blue in found if not is_blue)
        self.set_hidden(other_box, "visible")
        self.set_hidden(blue_box, "hidden")
        print("WOLF_DOWNLOAD_TILES=2 retained=non-blue")

    def verify_downloads(self):
        self.open_hidden()
        found = [(box, self.icon_blue(box)) for _, box in self.page_rows("Downloads")]
        if len(found) < 2:
            return
        if len(found) != 2 or sum(is_blue for _, is_blue in found) != 1:
            raise LayoutError("Downloads duplicates cannot be identified by icon")
        for box, is_blue in found:
            desired = "hidden" if is_blue else "visible"
            if self.marker(box) != desired:
                raise LayoutError("Downloads tile visibility did not persist")

    def applications_top(self):
        root = self.open_home()
        candidates = [row for row in resource_rows(root, SECTION_TITLE, self.width, right_only=False)
                      if row[1][0] < self.width * 0.2 and row[1][2] - row[1][0] > self.width * 0.7]
        if len(candidates) != 1:
            raise LayoutError("Wolf primary section title is not uniquely visible")
        return candidates[0][1][1]

    def hide_empty_widgets(self):
        top = self.applications_top()
        if top <= self.height * 0.26:
            print("WOLF_WIDGET_GAP=PASS already-closed")
            return
        self.open_settings()
        self.tap(sidebar_items(self.ui(), self.width)[0][1])
        section_items = sidebar_items(self.ui(), self.width)
        if len(section_items) != 3:
            raise LayoutError("Wolf Sections menu layout changed")
        widgets = [row for row in section_items if row[0] == "Widgets"]
        if len(widgets) != 1:
            raise LayoutError("Wolf Widgets section was not identifiable")
        self.tap(widgets[0][1])
        options = sidebar_items(self.ui(), self.width)
        checks = checkbox_items(self.ui(), self.width)
        if len(options) < 3 or not checks or not (options[0][1][1] <= checks[0][1][1] <= options[0][1][3]):
            raise LayoutError("Wolf Widgets visibility control was not identifiable")
        self.tap(options[0][1])
        # Wolf applies section changes when the dialog closes with Back.
        self.shell("input", "keyevent", "4")
        time.sleep(0.3)
        if self.applications_top() > self.height * 0.26:
            raise LayoutError("Widgets section remained visible after toggle")
        print("WOLF_WIDGET_GAP=PASS hidden-empty-section")


def main():
    parser = argparse.ArgumentParser(description="Guarded Wolf tile and layout setup")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True)
    parser.add_argument("--verify", action="store_true", help="check saved layout without toggling")
    args = parser.parse_args()
    device = Device(args.adb, args.serial)
    if device.shell("getprop", "ro.product.device") != "mantis" or device.shell(
        "getprop", "ro.build.version.incremental"
    ) != "0011644900484":
        raise LayoutError("Wolf layout target mismatch")
    if args.verify:
        print("WOLF_LAYOUT_STEP=VERIFY", flush=True)
        if device.applications_top() > device.height * 0.26:
            raise LayoutError("empty Widgets section reopened")
        device.verify_downloads()
        device.verify_named_hidden("What Should I Watch")
        device.verify_named_hidden("Wolf Launcher", required=True)
        device.verify_named_hidden("FireTV Player", "Prime Video")
    else:
        print("WOLF_LAYOUT_STEP=WIDGETS", flush=True)
        device.hide_empty_widgets()
        print("WOLF_LAYOUT_STEP=DOWNLOADS", flush=True)
        device.choose_downloads()
        print("WOLF_LAYOUT_STEP=HIDDEN_TILES", flush=True)
        device.hide_named("What Should I Watch")
        if device.hide_named("Wolf Launcher") != 1:
            raise LayoutError("Wolf Launcher tile was not found")
        device.hide_named("FireTV Player", "Prime Video")
    device.open_home()
    print("WOLF_LAYOUT=PASS")


if __name__ == "__main__":
    try:
        main()
    except (LayoutError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"WOLF_LAYOUT=FAIL {error}", file=sys.stderr)
        sys.exit(1)
