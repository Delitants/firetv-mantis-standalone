#!/usr/bin/env python3
"""Offline checks for Wolf's guarded tile and section selection."""

import importlib.util
import pathlib
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wolf_layout", ROOT / "scripts/wolf-layout.py")
WOLF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WOLF)


class WolfLayoutTests(unittest.TestCase):
    def test_opens_launcher_settings_from_application_menu(self):
        class MenuDevice(WOLF.Device):
            def __init__(self, launcher_label):
                super().__init__("fake-adb", "usb-primary")
                self.width, self.height = 1920, 1080
                self.screen = "home"
                self.launcher_label = launcher_label
                self.calls = []

            def shell(self, *args):
                self.calls.append(args)
                if args == ("am", "start", "-n", WOLF.HOME):
                    self.screen = "home"
                elif args == ("am", "start", "-n", "com.wolf.firelauncher/.screens.launcher.SettingsActivity"):
                    self.screen = "other-settings"
                elif args == ("input", "keyevent", "82") and self.screen == "home":
                    self.screen = "application-menu"
                elif args[:2] == ("input", "tap") and self.screen == "application-menu":
                    self.screen = "launcher-settings" if 578 <= int(args[3]) <= 655 else "other-settings"
                elif args == ("input", "keyevent", "4"):
                    self.screen = "home"
                return ""

            def frame(self):
                return None

            def ui(self):
                if self.screen == "application-menu":
                    xml = f'<hierarchy><node package="com.wolf.firelauncher" text="Application Menu" bounds="[1338,0][1900,115]"/><node package="com.wolf.firelauncher" text="{self.launcher_label}" bounds="[1348,578][1750,655]"/><node package="com.wolf.firelauncher" text="Other Settings" bounds="[1348,730][1750,809]"/></hierarchy>'
                elif self.screen == "launcher-settings":
                    xml = '<hierarchy><node package="com.wolf.firelauncher" text="Sections" bounds="[1348,116][1750,193]"/><node package="com.wolf.firelauncher" text="Hidden Apps" bounds="[1348,270][1750,346]"/></hierarchy>'
                elif self.screen == "other-settings":
                    xml = '<hierarchy><node package="com.wolf.firelauncher" text="Other Settings" bounds="[1338,0][1900,115]"/></hierarchy>'
                else:
                    xml = '<hierarchy><node package="com.wolf.firelauncher" text="Applications" bounds="[93,215][1827,264]"/></hierarchy>'
                return ET.fromstring(xml)

        for label in ("Launcher Settings", "Інше"):
            with self.subTest(label=label):
                device = MenuDevice(label)
                device.open_settings()
                self.assertEqual(device.screen, "launcher-settings")
                self.assertIn(("input", "keyevent", "82"), device.calls)
                self.assertNotIn(("am", "start", "-n", "com.wolf.firelauncher/.screens.launcher.SettingsActivity"), device.calls)

        device = MenuDevice("Missing launcher entry")
        with self.assertRaisesRegex(WOLF.LayoutError, "did not expose Launcher Settings"):
            device.open_settings()
        self.assertEqual(device.screen, "application-menu")
        self.assertFalse(any(call[:2] == ("input", "tap") for call in device.calls))

    def test_raw_screencap_and_visibility_colors(self):
        pixels = bytes((0, 161, 29, 255, 255, 255, 255, 255, 18, 174, 245, 255))
        frame = WOLF.RawFrame(struct.pack("<III", 3, 1, 1) + pixels)
        self.assertEqual(frame.pixel(0, 0), (0, 161, 29))
        self.assertEqual(WOLF.marker_state((0, 161, 29)), "hidden")
        self.assertEqual(WOLF.marker_state((165, 222, 176)), "hidden")
        self.assertEqual(WOLF.marker_state((255, 255, 255)), "visible")
        self.assertTrue(WOLF.blue_download_icon((18, 174, 245)))
        self.assertFalse(WOLF.blue_download_icon((185, 243, 63)))
        with self.assertRaises(ValueError):
            WOLF.RawFrame(struct.pack("<III", 3, 1, 1) + pixels[:-1])

    def test_only_exact_wolf_text_rows_are_selected(self):
        root = ET.fromstring('<hierarchy><node text="Downloads" package="com.wolf.firelauncher" bounds="[1440,380][1760,460]"/><node text="Downloads" package="com.other" bounds="[1440,500][1760,580]"/><node text="Applications" package="com.wolf.firelauncher" bounds="[90,215][1830,264]"/></hierarchy>')
        self.assertEqual(len(WOLF.rows(root, ("Downloads",), 1920)), 1)
        self.assertEqual(WOLF.rows(root, ("Applications",), 1920), [])
        self.assertEqual(len(WOLF.rows(root, ("Applications",), 1920, right_only=False)), 1)
        self.assertEqual(WOLF.rows(root, ("Missing",), 1920), [])


if __name__ == "__main__":
    unittest.main()
