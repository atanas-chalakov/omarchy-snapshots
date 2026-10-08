#!/usr/bin/env python3
"""
Unit tests for internal functions and logic in omarchy-snapshots-core.
Tests formatters, time calculations, status parsers, and mock handlers.
"""

import unittest
import os
import sys
import time

# Import omarchy-snapshots-core directly as a module
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_DIR = os.path.join(PROJECT_ROOT, "bin")
sys.path.insert(0, BIN_DIR)

from importlib.machinery import SourceFileLoader
core = SourceFileLoader("core", os.path.join(BIN_DIR, "omarchy-snapshots-core")).load_module()

class TestUnitEngine(unittest.TestCase):

    def test_format_bytes(self):
        self.assertEqual(core.format_bytes(0), "0.0 B")
        self.assertEqual(core.format_bytes(512), "512.0 B")
        self.assertEqual(core.format_bytes(1024), "1.0 KiB")
        self.assertEqual(core.format_bytes(1024 * 1024), "1.0 MiB")
        self.assertEqual(core.format_bytes(1024 * 1024 * 1024), "1.0 GiB")
        self.assertEqual(core.format_bytes(1024 * 1024 * 1024 * 1024), "1.0 TiB")
        self.assertEqual(core.format_bytes(None), "0 B")
        self.assertEqual(core.format_bytes(-100), "0 B")

    def test_format_relative_time(self):
        now = int(time.time())
        self.assertEqual(core.format_relative_time(now), "0s ago")
        self.assertEqual(core.format_relative_time(now - 30), "30s ago")
        self.assertEqual(core.format_relative_time(now - 59), "59s ago")
        self.assertEqual(core.format_relative_time(now - 60), "1m ago")
        self.assertEqual(core.format_relative_time(now - 120), "2m ago")
        self.assertEqual(core.format_relative_time(now - 3600), "1h ago")
        self.assertEqual(core.format_relative_time(now - 7200), "2h ago")
        self.assertEqual(core.format_relative_time(now - 86400), "1d ago")
        self.assertEqual(core.format_relative_time(now - 86400 * 3), "3d ago")
        self.assertEqual(core.format_relative_time(now - 86400 * 14), "2w ago")
        self.assertEqual(core.format_relative_time(0), "Unknown")
        self.assertEqual(core.format_relative_time(None), "Unknown")

    def test_get_mock_status_structure(self):
        st = core.get_mock_status()
        self.assertTrue(st["ok"])
        self.assertTrue(st["readable"])
        self.assertFalse(st["needsPermission"])
        self.assertEqual(st["health"]["status"], "healthy")
        self.assertTrue(st["health"]["limineSyncActive"])
        self.assertTrue(st["health"]["cleanupTimerActive"])
        self.assertGreater(st["storage"]["snapshotCount"], 0)
        self.assertGreater(st["storage"]["usedPercent"], 0)
        self.assertIn("GiB", st["storage"]["fsSizeHuman"])

        configs = st["configs"]
        self.assertEqual(len(configs), 1)
        root_cfg = configs[0]
        self.assertEqual(root_cfg["name"], "root")
        self.assertEqual(root_cfg["subvolume"], "/")
        self.assertTrue(root_cfg["readable"])

        snapshots = root_cfg["snapshots"]
        self.assertEqual(len(snapshots), 4)

        # Check sorting: newest (highest ID) first
        ids = [s["id"] for s in snapshots]
        self.assertEqual(ids, sorted(ids, reverse=True))

        for s in snapshots:
            self.assertIn("id", s)
            self.assertIn("type", s)
            self.assertIn("description", s)
            self.assertIn("date", s)
            self.assertIn("epoch", s)
            self.assertIn("relativeAge", s)
            self.assertIn("cleanup", s)
            self.assertIn("important", s)
            self.assertIn("bootable", s)

    def test_create_snapshot_mock(self):
        res1 = core.create_snapshot("Custom Test Checkpoint", mock=True)
        self.assertTrue(res1["ok"])
        self.assertIn("Custom Test Checkpoint", res1["message"])
        self.assertEqual(res1.get("snapshotId"), 20)

        res2 = core.create_snapshot("Pinned Test", important=True, mock=True)
        self.assertTrue(res2["ok"])
        self.assertIn("Pinned Test", res2["message"])

        # Test empty / whitespace description fallback
        res3 = core.create_snapshot("", mock=True)
        self.assertTrue(res3["ok"])
        self.assertIn("Manual checkpoint", res3["message"])

        res4 = core.create_snapshot("   ", mock=True)
        self.assertTrue(res4["ok"])
        self.assertIn("Manual checkpoint", res4["message"])

    def test_restore_snapshot_mock(self):
        res = core.restore_snapshot(19, mock=True)
        self.assertTrue(res["ok"])
        self.assertEqual(res["snapshotId"], 19)
        self.assertIn("System restore to snapshot #19", res["message"])

    def test_restore_snapshot_nonexistent_live(self):
        # In live mode, asking to restore a non-existent snapshot ID must fail cleanly
        res = core.restore_snapshot(999999, mock=False)
        self.assertFalse(res["ok"])
        self.assertIn("does not exist", res["error"])

    def test_delete_snapshot_mock(self):
        res = core.delete_snapshot(19, mock=True)
        self.assertTrue(res["ok"])
        self.assertIn("19", res["message"])

    def test_pin_unpin_snapshot_mock(self):
        pin_res = core.pin_snapshot(18, pin=True, mock=True)
        self.assertTrue(pin_res["ok"])
        self.assertIn("pinned", pin_res["message"])

        unpin_res = core.pin_snapshot(18, pin=False, mock=True)
        self.assertTrue(unpin_res["ok"])
        self.assertIn("unpinned", unpin_res["message"])

    def test_get_diff_mock(self):
        diff = core.get_diff(19, mock=True)
        self.assertTrue(diff["ok"])
        self.assertEqual(diff["snapshotId"], 19)
        self.assertEqual(diff["summary"]["added"], 3)
        self.assertEqual(diff["summary"]["modified"], 12)
        self.assertEqual(diff["summary"]["deleted"], 1)

        files = diff["files"]
        self.assertEqual(len(files), 5)
        for f in files:
            self.assertIn("path", f)
            self.assertIn(f["status"], ["added", "modified", "deleted"])

    def test_live_status_safe_read(self):
        # Querying live status on current system should not crash and should parse snapshots cleanly
        st = core.get_live_status()
        self.assertIn("ok", st)
        self.assertIn("health", st)
        self.assertIn("storage", st)
        self.assertIn("configs", st)
        self.assertTrue(st["health"]["limineSyncActive"])
        self.assertTrue(st["readable"])
        self.assertGreater(len(st["configs"]), 0)
        self.assertTrue(st["configs"][0]["readable"])
        self.assertGreater(len(st["configs"][0]["snapshots"]), 0)

if __name__ == "__main__":
    unittest.main()
