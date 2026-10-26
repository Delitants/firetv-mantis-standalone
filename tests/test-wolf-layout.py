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
