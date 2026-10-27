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
    def test_home_primary_section_ignores_empty_secondary_header(self):
        class SavedHome(WOLF.Device):
            def __init__(self):
                super().__init__("unused", "unused")
                self.width, self.height = 1920, 1080

            def open_home(self):
                return ET.fromstring('''<hierarchy>
                    <node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/title"
                          text="Applications" bounds="[93,347][1827,396]"/>
                    <node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/title"
                          text="" bounds="[93,670][1827,719]"/>
                </hierarchy>''')

        self.assertEqual(SavedHome().applications_top(), 347)

    def test_public_launcher_has_no_locale_specific_labels(self):
        self.assertNotRegex((ROOT / "scripts/wolf-layout.py").read_text(), r"[\u0400-\u04ff]")
        self.assertFalse((ROOT / "settings-tile/res/values-uk/strings.xml").exists())

    def test_opens_launcher_settings_from_application_menu(self):
        class MenuDevice(WOLF.Device):
            def __init__(self, menu_count=9):
                super().__init__("fake-adb", "usb-primary")
                self.width, self.height = 1920, 1080
                self.screen = "home"
                self.menu_count = menu_count
                self.calls = []
                self.widgets_hidden = False

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
                elif args[:2] == ("input", "tap") and self.screen == "launcher-settings":
                    y = int(args[3])
                    self.screen = "sections" if y < 190 else "hidden-list" if 270 <= y <= 350 else "other-settings"
                elif args[:2] == ("input", "tap") and self.screen == "sections":
                    self.screen = "widget-dialog" if 270 <= int(args[3]) <= 350 else "other-settings"
                elif args[:2] == ("input", "tap") and self.screen == "widget-dialog":
                    self.widgets_hidden = 470 <= int(args[3]) <= 520
                elif args == ("input", "keyevent", "4"):
                    self.screen = "home"
                return ""

            def frame(self):
                return None

            def ui(self):
                if self.screen == "application-menu":
                    count = self.menu_count
                elif self.screen == "launcher-settings":
                    count = 4
                elif self.screen == "sections":
                    count = 3
                elif self.screen in ("widget-dialog", "hidden-list"):
                    count = 3
                elif self.screen == "other-settings":
                    count = 5
                else:
                    top = 215 if self.widgets_hidden else 347
                    return ET.fromstring(f'<hierarchy><node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/title" text="Any section name" bounds="[93,{top}][1827,{top+49}]"/></hierarchy>')
                offset = 470 if self.screen == "widget-dialog" else 130
                items = ''.join(f'<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/first_line" text="{("Widgets" if self.screen == "sections" and i == 2 else "Item " + str(i))}" bounds="[1348,{offset+77*i}][1891,{offset+49+77*i}]"/>' for i in range(count))
                checks = '<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/check_box" bounds="[1745,476][1781,512]"/>' if self.screen in ("widget-dialog", "hidden-list") else ''
                xml = '<hierarchy><node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/sidebar_header" bounds="[1308,0][1920,116]"/>' + items + checks + '</hierarchy>'
                return ET.fromstring(xml)

        device = MenuDevice()
        device.open_settings()
        self.assertEqual(device.screen, "launcher-settings")
        self.assertIn(("input", "keyevent", "82"), device.calls)
        self.assertNotIn(("am", "start", "-n", "com.wolf.firelauncher/.screens.launcher.SettingsActivity"), device.calls)
        self.assertEqual(device.applications_top(), 347)
        device.hide_empty_widgets()
        self.assertTrue(device.widgets_hidden)
        self.assertEqual(device.applications_top(), 215)
        device.open_hidden()
        self.assertEqual(device.screen, "hidden-list")

        device = MenuDevice(menu_count=8)
        with self.assertRaisesRegex(WOLF.LayoutError, "unexpected Wolf Application Menu"):
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
