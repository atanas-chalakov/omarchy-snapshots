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

    def test_classify_package(self):
        # Kernel & Boot
        self.assertEqual(core.classify_package("linux"), (True, "Kernel & Boot"))
        self.assertEqual(core.classify_package("linux-zen"), (True, "Kernel & Boot"))
        self.assertEqual(core.classify_package("limine"), (True, "Kernel & Boot"))
        self.assertEqual(core.classify_package("systemd"), (True, "Kernel & Boot"))

        # Graphics Driver
        self.assertEqual(core.classify_package("nvidia-utils"), (True, "Graphics Driver"))
        self.assertEqual(core.classify_package("mesa"), (True, "Graphics Driver"))
        self.assertEqual(core.classify_package("vulkan-radeon"), (True, "Graphics Driver"))

        # Display / Compositor
        self.assertEqual(core.classify_package("hyprland"), (True, "Display / Compositor"))
        self.assertEqual(core.classify_package("wayland"), (True, "Display / Compositor"))

        # Desktop Shell
        self.assertEqual(core.classify_package("omarchy"), (True, "Desktop Shell"))
        self.assertEqual(core.classify_package("quickshell"), (True, "Desktop Shell"))
        self.assertEqual(core.classify_package("waybar"), (True, "Desktop Shell"))

        # Non-critical packages
        self.assertEqual(core.classify_package("htop"), (False, None))
        self.assertEqual(core.classify_package("ripgrep"), (False, None))
        self.assertEqual(core.classify_package(""), (False, None))

    def test_parse_pacman_log_entries(self):
        import tempfile
        sample_log = (
            "[2026-10-07T16:30:10+0300] [PACMAN] Running 'pacman -Syu'\n"
            "[2026-10-07T16:30:15+0300] [ALPM] upgraded linux (6.11.2-arch1-1 -> 6.11.3-arch1-1)\n"
            "[2026-10-07T16:30:18+0300] [ALPM] installed waybar (0.11.0-1)\n"
            "[2026-10-07T16:30:20+0300] [ALPM] removed htop (3.3.0-1)\n"
            "[2026-10-07T16:30:22+0300] [ALPM] reinstalled mesa (24.2.3-1)\n"
        )
        with tempfile.NamedTemporaryFile("w+", encoding="utf-8", delete=False) as tf:
            tf.write(sample_log)
            tf_path = tf.name

        try:
            entries = core.parse_pacman_log(tf_path)
            self.assertEqual(len(entries), 4)

            # Check upgraded linux
            e0 = entries[0]
            self.assertEqual(e0["name"], "linux")
            self.assertEqual(e0["action"], "upgraded")
            self.assertEqual(e0["oldVersion"], "6.11.2-arch1-1")
            self.assertEqual(e0["newVersion"], "6.11.3-arch1-1")
            self.assertTrue(e0["isCritical"])
            self.assertEqual(e0["criticalCategory"], "Kernel & Boot")

            # Check installed waybar
            e1 = entries[1]
            self.assertEqual(e1["name"], "waybar")
            self.assertEqual(e1["action"], "installed")
            self.assertEqual(e1["newVersion"], "0.11.0-1")
            self.assertTrue(e1["isCritical"])
            self.assertEqual(e1["criticalCategory"], "Desktop Shell")

            # Check removed htop
            e2 = entries[2]
            self.assertEqual(e2["name"], "htop")
            self.assertEqual(e2["action"], "removed")
            self.assertFalse(e2["isCritical"])
            self.assertIsNone(e2["criticalCategory"])
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_correlate_packages_for_snapshots(self):
        t0 = 1760000000
        mock_snaps = [
            {"id": 1, "epoch": t0, "description": "Snap 1"},
            {"id": 2, "epoch": t0 + 3600, "description": "Snap 2"}
        ]
        mock_log = [
            {"epoch": t0 + 10, "name": "linux", "action": "upgraded", "version": "1 -> 2", "isCritical": True, "criticalCategory": "Kernel & Boot"},
            {"epoch": t0 + 20, "name": "htop", "action": "installed", "version": "1.0", "isCritical": False, "criticalCategory": None},
            {"epoch": t0 + 3605, "name": "hyprland", "action": "upgraded", "version": "0.44 -> 0.45", "isCritical": True, "criticalCategory": "Display / Compositor"}
        ]
        res = core.correlate_packages_for_snapshots(mock_snaps, mock_log)
        self.assertEqual(len(res), 2)

        s1 = res[0]
        self.assertEqual(s1["packageCount"], 2)
        self.assertTrue(s1["hasCriticalPackages"])
        self.assertIn("linux", s1["criticalPackages"])
        self.assertIn("1 upgraded, 1 installed", s1["packageSummary"])

        s2 = res[1]
        self.assertEqual(s2["packageCount"], 1)
        self.assertTrue(s2["hasCriticalPackages"])
        self.assertIn("hyprland", s2["criticalPackages"])
        self.assertIn("1 upgraded", s2["packageSummary"])

    def test_restore_file_mock(self):
        res = core.restore_file(19, "/etc/hypr/hyprland.conf", mock=True)
        self.assertTrue(res["ok"])
        self.assertEqual(res["snapshotId"], 19)
        self.assertEqual(res["filePath"], "/etc/hypr/hyprland.conf")
        self.assertIn(".bak.", res["backupPath"])
        self.assertIn("Successfully restored", res["message"])

    def test_restore_file_empty_path(self):
        res = core.restore_file(19, "", mock=True)
        self.assertFalse(res["ok"])
        self.assertIn("file_path is required", res["error"])

    def test_restore_file_live_nonexistent(self):
        res = core.restore_file(999999, "/nonexistent/test/file.conf", mock=False)
        self.assertFalse(res["ok"])
        self.assertIn("not found", res["error"].lower())

    def test_optimize_snapshots_mock_dry_run(self):
        res = core.optimize_snapshots(mock=True, execute=False)
        self.assertTrue(res["ok"])
        self.assertFalse(res["executed"])
        self.assertEqual(res["totalSnapshots"], 6)
        self.assertEqual(res["protectedCount"], 3)
        self.assertEqual(res["prunableCount"], 3)
        self.assertGreater(res["reclaimableBytes"], 0)
        self.assertIn("GiB", res["reclaimableHuman"])
        self.assertEqual(len(res["prunableSnapshots"]), 3)
        self.assertEqual(len(res["protectedSnapshots"]), 3)
        self.assertIn("Preserves 3 latest snapshots", res["retentionPolicy"])

    def test_optimize_snapshots_mock_execute(self):
        res = core.optimize_snapshots(mock=True, execute=True)
        self.assertTrue(res["ok"])
        self.assertTrue(res["executed"])
        self.assertEqual(res["prunedCount"], 3)
        self.assertEqual(res["prunedIds"], [16, 15, 14])
        self.assertIn("GiB", res["freedHuman"])
        self.assertIn("Successfully pruned 3 stale snapshots", res["message"])

    def test_optimize_snapshots_live_dry_run(self):
        res = core.optimize_snapshots(mock=False, execute=False)
        self.assertTrue(res["ok"])
        self.assertFalse(res["executed"])
        self.assertIn("totalSnapshots", res)
        self.assertIn("protectedCount", res)
        self.assertIn("prunableCount", res)

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
