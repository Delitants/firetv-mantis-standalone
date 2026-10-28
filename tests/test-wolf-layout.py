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
                self.apparent_top = None

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
                class Frame:
                    def __init__(self, rgb):
                        self.rgb = rgb
                    def pixel(self, x, y):
                        return self.rgb
                return Frame((255, 255, 255) if self.widgets_hidden else (0, 161, 29))

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
                    top = self.apparent_top if self.apparent_top is not None else 215 if self.widgets_hidden else 347
                    return ET.fromstring(f'<hierarchy><node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/title" text="Any section name" bounds="[93,{top}][1827,{top+49}]"/></hierarchy>')
                offset = 470 if self.screen == "widget-dialog" else 130
                items = ''.join(f'<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/first_line" text="{("Widgets" if self.screen == "sections" and i == 2 else "Show Section" if self.screen == "widget-dialog" and i == 0 else "Item " + str(i))}" bounds="[1348,{offset+77*i}][1891,{offset+49+77*i}]"/>' for i in range(count))
                checks = ('<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/check_box" bounds="[1745,476][1781,512]"/>'
                          '<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/check_box" bounds="[1745,553][1781,589]"/>') if self.screen == "widget-dialog" else ('<node package="com.wolf.firelauncher" resource-id="com.wolf.firelauncher:id/check_box" bounds="[1745,476][1781,512]"/>' if self.screen == "hidden-list" else '')
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

        device = MenuDevice()
        device.apparent_top = 215  # The photographed false positive: widgets still enabled.
        device.hide_empty_widgets()
        self.assertTrue(device.widgets_hidden)

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

    def test_existing_widget_dialog_is_dismissed_before_opening_settings(self):
        class DialogDevice(WOLF.Device):
            def __init__(self):
                super().__init__("fake-adb", "usb-primary")
                self.width, self.height = 1920, 1080
                self.depth = 4  # Dialog, Sections, Launcher Settings, Application Menu.
                self.calls = []

            def shell(self, *args):
                self.calls.append(args)
                if args == ("input", "keyevent", "4"):
                    self.depth -= 1
                return ""

            def frame(self):
                return None

            def ui(self):
                dialog = ('<node package="com.wolf.firelauncher" '
                          'resource-id="com.wolf.firelauncher:id/check_box" '
                          'bounds="[1745,476][1781,512]"/>') if self.depth == 4 else ''
                sidebar = ('<node package="com.wolf.firelauncher" '
                           'resource-id="com.wolf.firelauncher:id/sidebar_header" '
                           'bounds="[1308,0][1920,116]"/>') if 0 < self.depth < 4 else ''
                return ET.fromstring('<hierarchy><node package="com.wolf.firelauncher" '
                                     'resource-id="com.wolf.firelauncher:id/title" '
                                     'text="Applications" bounds="[93,347][1827,396]"/>'
                                     + dialog + sidebar + '</hierarchy>')

        device = DialogDevice()
        device.open_home()
        self.assertEqual(device.depth, 0)
        self.assertEqual(device.calls.count(("input", "keyevent", "4")), 4)

    def test_widget_checkbox_uses_visible_state_not_title_position(self):
        class CheckboxDevice(WOLF.Device):
            def __init__(self, rgb):
                super().__init__("fake-adb", "usb-primary")
                self.width, self.height = 1920, 1080
                self.rgb = rgb

            def frame(self):
                class Frame:
                    def __init__(self, rgb):
                        self.rgb = rgb
                    def pixel(self, x, y):
                        return self.rgb
                return Frame(self.rgb)

        box = (1745, 476, 1781, 512)
        self.assertEqual(CheckboxDevice((0, 161, 29)).widget_checkbox_state(box), "shown")
        self.assertEqual(CheckboxDevice((255, 255, 255)).widget_checkbox_state(box), "hidden")
        with self.assertRaisesRegex(WOLF.LayoutError, "unknown"):
            CheckboxDevice((40, 50, 60)).widget_checkbox_state(box)

    def test_ambiguous_downloads_never_toggles_a_tile(self):
        class AmbiguousDevice(WOLF.Device):
            def __init__(self):
                super().__init__("fake-adb", "usb-primary")
                self.toggled = []
            def open_hidden(self):
                pass
            def page_rows(self, *labels):
                return [("Downloads", (1, 1, 2, 2)), ("Downloads", (3, 3, 4, 4))]
            def icon_blue(self, box):
                return False
            def set_hidden(self, box, desired):
                self.toggled.append((box, desired))

        device = AmbiguousDevice()
        device.choose_downloads()
        device.verify_downloads()
        self.assertEqual(device.toggled, [])


if __name__ == "__main__":
    unittest.main()
