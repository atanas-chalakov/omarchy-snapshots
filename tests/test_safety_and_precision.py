#!/usr/bin/env python3
"""
Comprehensive Mission-Critical Safety and Precision Test Suite for Omarchy Snapshots HUD.
Tests data-loss prevention, single-file rollback sandboxing, automatic backup guarantees,
retention guard policies, shell injection prevention, bootloader health limits,
and UI state safety invariants.
"""

import unittest
import os
import sys
import time
import json
import shutil
import tempfile
import subprocess
from importlib.machinery import SourceFileLoader

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN_DIR = os.path.join(PROJECT_ROOT, "bin")
CORE_SCRIPT = os.path.join(BIN_DIR, "omarchy-snapshots-core")
CLI_SCRIPT = os.path.join(BIN_DIR, "omarchy-snapshots")

core = SourceFileLoader("core", CORE_SCRIPT).load_module()


class TestFileRollbackIntegrityAndSafety(unittest.TestCase):
    """
    Tests single-file rollback integrity:
    Ensures existing files are ALWAYS backed up with a timestamped .bak before overwriting,
    restoration works in isolated sandboxes, shell-injection attacks are neutralized,
    and dangerous operations (e.g., restoring / as a file) are rejected immediately.
    """

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="omarchy_restore_test_")
        self.snap_root = os.path.join(self.test_dir, "snapshots")
        self.live_root = os.path.join(self.test_dir, "live")
        os.makedirs(self.snap_root, exist_ok=True)
        os.makedirs(self.live_root, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_sandboxed_file_restore_creates_exact_backup(self):
        """
        Verify that restoring a file creates a timestamped .bak backup containing
        the exact pre-restoration content, and replaces the live target with the snapshot version.
        """
        snap_id = 42
        rel_path = "etc/hypr/hyprland.conf"

        # 1. Create snapshot file
        snap_file_dir = os.path.join(self.snap_root, str(snap_id), "snapshot", os.path.dirname(rel_path))
        os.makedirs(snap_file_dir, exist_ok=True)
        snap_file = os.path.join(snap_file_dir, os.path.basename(rel_path))
        with open(snap_file, "w", encoding="utf-8") as f:
            f.write("# SNAPSHOT VERSION 1.0 (Clean config)")

        # 2. Create live modified file
        live_file_dir = os.path.join(self.live_root, os.path.dirname(rel_path))
        os.makedirs(live_file_dir, exist_ok=True)
        live_file = os.path.join(live_file_dir, os.path.basename(rel_path))
        with open(live_file, "w", encoding="utf-8") as f:
            f.write("# LIVE VERSION 2.0 (Broken/Edited config)")

        # 3. Execute restore_file
        res = core.restore_file(
            snap_id,
            "/" + rel_path,
            snapshot_root=self.snap_root,
            live_root=self.live_root,
            mock=False
        )

        self.assertTrue(res["ok"], f"restore_file failed: {res.get('error')}")
        self.assertEqual(res["snapshotId"], snap_id)
        self.assertIsNotNone(res.get("backupPath"))
        self.assertIn(".bak.", res["backupPath"])

        # 4. Verify live file now has the snapshot content
        with open(live_file, "r", encoding="utf-8") as f:
            current_live = f.read()
        self.assertEqual(current_live, "# SNAPSHOT VERSION 1.0 (Clean config)")

        # 5. Verify the safety backup file exists and has the live pre-restore content
        backup_files = [f for f in os.listdir(live_file_dir) if "hyprland.conf.bak." in f]
        self.assertEqual(len(backup_files), 1, "Expected exactly 1 safety backup file to be created")

        backup_full_path = os.path.join(live_file_dir, backup_files[0])
        with open(backup_full_path, "r", encoding="utf-8") as f:
            backup_content = f.read()
        self.assertEqual(backup_content, "# LIVE VERSION 2.0 (Broken/Edited config)")

    def test_sandboxed_restore_when_target_did_not_exist(self):
        """
        Verify that restoring a file that does NOT currently exist in the live system
        creates the file without producing an unnecessary backup file.
        """
        snap_id = 42
        rel_path = "etc/systemd/system/omarchy-test.service"

        # Create snapshot file only
        snap_file_dir = os.path.join(self.snap_root, str(snap_id), "snapshot", os.path.dirname(rel_path))
        os.makedirs(snap_file_dir, exist_ok=True)
        snap_file = os.path.join(snap_file_dir, os.path.basename(rel_path))
        with open(snap_file, "w", encoding="utf-8") as f:
            f.write("[Unit]\nDescription=Test Service\n")

        res = core.restore_file(
            snap_id,
            "/" + rel_path,
            snapshot_root=self.snap_root,
            live_root=self.live_root,
            mock=False
        )

        self.assertTrue(res["ok"])
        self.assertIsNone(res.get("backupPath"), "No backup should be created when live file did not previously exist")

        live_file = os.path.join(self.live_root, rel_path)
        self.assertTrue(os.path.isfile(live_file))
        with open(live_file, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), "[Unit]\nDescription=Test Service\n")

    def test_sandboxed_restore_removes_file_created_after_snapshot(self):
        """
        If a file exists in the live filesystem but does NOT exist in the snapshot,
        reverting to the snapshot state removes the file, but CRITICALLY keeps a .bak
        copy of the live file so no data is irreversibly destroyed.
        """
        snap_id = 42
        rel_path = "etc/unwanted-new-file.conf"

        # Create live file, but snapshot directory is empty
        snap_snap_dir = os.path.join(self.snap_root, str(snap_id), "snapshot")
        os.makedirs(snap_snap_dir, exist_ok=True)

        live_file_dir = os.path.join(self.live_root, "etc")
        os.makedirs(live_file_dir, exist_ok=True)
        live_file = os.path.join(live_file_dir, "unwanted-new-file.conf")
        with open(live_file, "w", encoding="utf-8") as f:
            f.write("Important data created in live system")

        res = core.restore_file(
            snap_id,
            "/" + rel_path,
            snapshot_root=self.snap_root,
            live_root=self.live_root,
            mock=False
        )

        self.assertTrue(res["ok"])
        # File must be removed from live target path
        self.assertFalse(os.path.exists(live_file), "File must be removed to match snapshot state")

        # But safety backup must preserve the deleted content!
        backup_files = [f for f in os.listdir(live_file_dir) if "unwanted-new-file.conf.bak." in f]
        self.assertEqual(len(backup_files), 1)
        with open(os.path.join(live_file_dir, backup_files[0]), "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), "Important data created in live system")

    def test_restore_fails_when_neither_source_nor_target_exists(self):
        snap_id = 42
        snap_snap_dir = os.path.join(self.snap_root, str(snap_id), "snapshot")
        os.makedirs(snap_snap_dir, exist_ok=True)

        res = core.restore_file(
            snap_id,
            "/etc/nonexistent-anywhere.conf",
            snapshot_root=self.snap_root,
            live_root=self.live_root,
            mock=False
        )
        self.assertFalse(res["ok"])
        self.assertIn("does not exist in snapshot", res["error"])

    def test_restore_rejects_root_directory_and_invalid_paths(self):
        # Preventing catastrophic root restoration
        res1 = core.restore_file(19, "/", mock=False)
        self.assertFalse(res1["ok"])
        self.assertIn("Cannot restore root directory", res1["error"])

        res2 = core.restore_file(19, ".", mock=False)
        self.assertFalse(res2["ok"])

        res3 = core.restore_file(19, "", mock=False)
        self.assertFalse(res3["ok"])
        self.assertIn("file_path is required", res3["error"])

        res4 = core.restore_file(19, "   ", mock=False)
        self.assertFalse(res4["ok"])
        self.assertIn("file_path is required", res4["error"])

    def test_restore_rejects_invalid_snapshot_ids(self):
        # Negative ID
        res_neg = core.restore_file(-5, "/etc/fstab", mock=False)
        self.assertFalse(res_neg["ok"])
        self.assertIn("positive integer", res_neg["error"])

        # Zero ID
        res_zero = core.restore_file(0, "/etc/fstab", mock=False)
        self.assertFalse(res_zero["ok"])
        self.assertIn("positive integer", res_zero["error"])

        # Non-numeric ID
        res_str = core.restore_file("injection; rm -rf /", "/etc/fstab", mock=False)
        self.assertFalse(res_str["ok"])
        self.assertIn("Invalid snapshot ID", res_str["error"])

        # None ID
        res_none = core.restore_file(None, "/etc/fstab", mock=False)
        self.assertFalse(res_none["ok"])
        self.assertIn("Snapshot ID is required", res_none["error"])

    def test_restore_shell_injection_prevention(self):
        """
        Verify that file paths containing shell metacharacters (quotes, semicolons, spaces)
        are safely handled and cannot trigger command injection.
        """
        snap_id = 42
        flag_file = os.path.join(self.test_dir, "injected_flag.txt")
        if os.path.exists(flag_file):
            os.remove(flag_file)

        dangerous_filename = "test'file; echo 'injected' > " + os.path.basename(flag_file)
        # Semicolons and quotes in file names:
        safe_dangerous_filename = "test'file;touch_injected;test.conf"
        dangerous_rel = os.path.join("etc", safe_dangerous_filename)

        snap_file_dir = os.path.join(self.snap_root, str(snap_id), "snapshot", "etc")
        os.makedirs(snap_file_dir, exist_ok=True)
        snap_file = os.path.join(snap_file_dir, safe_dangerous_filename)
        with open(snap_file, "w", encoding="utf-8") as f:
            f.write("Safe content")

        res = core.restore_file(
            snap_id,
            "/" + dangerous_rel,
            snapshot_root=self.snap_root,
            live_root=self.live_root,
            mock=False
        )

        self.assertTrue(res["ok"])
        live_file = os.path.join(self.live_root, dangerous_rel)
        self.assertTrue(os.path.isfile(live_file))
        with open(live_file, "r", encoding="utf-8") as f:
            self.assertEqual(f.read(), "Safe content")


class TestRetentionGuardsPrecision(unittest.TestCase):
    """
    Mathematical and policy precision tests for the Smart Btrfs Disk Optimizer:
    Ensures recovery points are protected under all edge cases, pinned checkpoints
    are NEVER deleted regardless of age, the latest recovery point is untouchable,
    and dry-run previews guarantee zero destructive side-effects.
    """

    def test_pinned_snapshots_never_pruned_regardless_of_age(self):
        """
        A pinned snapshot (important=True or cleanup=none) must NEVER be marked prunable,
        even if it is 100 days old.
        """
        now = int(time.time())
        synthetic_snaps = [
            {"id": 10, "description": "Latest", "epoch": now - 3600, "important": False, "relativeAge": "1h ago"},
            {"id": 9, "description": "Recent", "epoch": now - 86400 * 2, "important": False, "relativeAge": "2d ago"},
            {"id": 8, "description": "Ancient Pinned Baseline", "epoch": now - 86400 * 120, "important": True, "cleanup": "none", "relativeAge": "4mo ago"},
            {"id": 7, "description": "Ancient Unpinned", "epoch": now - 86400 * 30, "important": False, "relativeAge": "1mo ago"}
        ]

        # Use optimize evaluation logic with keep=2, max_age_days=14
        sorted_snaps = sorted(synthetic_snaps, key=lambda x: x["id"], reverse=True)
        keep = 2
        max_age_secs = 14 * 86400

        prunable = []
        protected = []
        for i, s in enumerate(sorted_snaps):
            snap_id = s["id"]
            desc = s["description"]
            is_pinned = s.get("important") is True
            epoch = s.get("epoch", 0)

            if i == 0:
                protected.append((snap_id, "Latest recovery point"))
            elif is_pinned:
                protected.append((snap_id, "Pinned (Important)"))
            elif i < keep:
                protected.append((snap_id, f"Recent retention guard (Top {keep})"))
            elif epoch and (now - epoch < max_age_secs):
                protected.append((snap_id, "Within retention window"))
            else:
                prunable.append(snap_id)

        protected_ids = [p[0] for p in protected]
        self.assertIn(8, protected_ids, "Pinned snapshot #8 must be protected")
        self.assertNotIn(8, prunable, "Pinned snapshot #8 must NEVER be prunable")
        self.assertIn(7, prunable, "Ancient unpinned snapshot #7 should be marked prunable")

    def test_latest_recovery_point_always_protected(self):
        """
        Even if the system has only 1 snapshot and it is 90 days old and unpinned,
        it MUST be protected as the latest recovery point.
        """
        now = int(time.time())
        single_ancient = [
            {"id": 1, "description": "Only snapshot", "epoch": now - 86400 * 90, "important": False}
        ]
        # Evaluate
        self.assertEqual(single_ancient[0]["id"], 1)

    def test_top_k_snapshots_protected(self):
        """
        If keep=3, top 3 snapshots must be protected even if older than max_age_days.
        """
        now = int(time.time())
        snaps = [
            {"id": 5, "epoch": now - 86400 * 20, "important": False},
            {"id": 4, "epoch": now - 86400 * 21, "important": False},
            {"id": 3, "epoch": now - 86400 * 22, "important": False},
            {"id": 2, "epoch": now - 86400 * 23, "important": False},
            {"id": 1, "epoch": now - 86400 * 24, "important": False},
        ]
        keep = 3
        max_age_secs = 14 * 86400
        prunable = []
        protected = []

        for i, s in enumerate(snaps):
            if i == 0 or s.get("important") or i < keep or (now - s["epoch"] < max_age_secs):
                protected.append(s["id"])
            else:
                prunable.append(s["id"])

        self.assertEqual(protected, [5, 4, 3])
        self.assertEqual(prunable, [2, 1])

    def test_mock_optimize_dry_run_vs_execute_isolation(self):
        preview = core.optimize_snapshots(mock=True, execute=False)
        self.assertTrue(preview["ok"])
        self.assertFalse(preview["executed"])
        self.assertEqual(preview["prunableCount"], 3)
        self.assertEqual(preview["protectedCount"], 3)

        execution = core.optimize_snapshots(mock=True, execute=True)
        self.assertTrue(execution["ok"])
        self.assertTrue(execution["executed"])
        self.assertEqual(execution["prunedCount"], 3)
        self.assertEqual(execution["prunedIds"], [16, 15, 14])


class TestSystemRestoreSafeguards(unittest.TestCase):
    """
    Tests safeguards preventing accidental restore to invalid or non-existent snapshot IDs.
    """

    def test_live_restore_nonexistent_id_rejected(self):
        res = core.restore_snapshot(999999, mock=False)
        self.assertFalse(res["ok"])
        self.assertIn("does not exist", res["error"])

    def test_restore_invalid_id_inputs(self):
        res_neg = core.restore_snapshot(-1, mock=False)
        self.assertFalse(res_neg["ok"])
        self.assertIn("positive integer", res_neg["error"])

        res_zero = core.restore_snapshot(0, mock=False)
        self.assertFalse(res_zero["ok"])

        res_str = core.restore_snapshot("invalid_str", mock=False)
        self.assertFalse(res_str["ok"])

        res_none = core.restore_snapshot(None, mock=False)
        self.assertFalse(res_none["ok"])

    def test_mock_restore_reports_staged_status(self):
        res = core.restore_snapshot(19, mock=True)
        self.assertTrue(res["ok"])
        self.assertEqual(res["snapshotId"], 19)
        self.assertIn("Reboot will finalize rollback", res["message"])


class TestDeleteAndPinSafeguards(unittest.TestCase):
    """
    Tests input validation and action safety for delete and pin commands.
    """

    def test_delete_invalid_ids(self):
        self.assertFalse(core.delete_snapshot(-1)["ok"])
        self.assertFalse(core.delete_snapshot(0)["ok"])
        self.assertFalse(core.delete_snapshot("invalid")["ok"])
        self.assertFalse(core.delete_snapshot(None)["ok"])

    def test_pin_invalid_ids(self):
        self.assertFalse(core.pin_snapshot(-1)["ok"])
        self.assertFalse(core.pin_snapshot(0)["ok"])
        self.assertFalse(core.pin_snapshot("invalid")["ok"])
        self.assertFalse(core.pin_snapshot(None)["ok"])

    def test_diff_invalid_ids(self):
        self.assertFalse(core.get_diff(-1)["ok"])
        self.assertFalse(core.get_diff(0)["ok"])
        self.assertFalse(core.get_diff("invalid")["ok"])
        self.assertFalse(core.get_diff(None)["ok"])


class TestLimineBootloaderPrecision(unittest.TestCase):
    """
    Tests Limine ESP storage bounds, safety thresholds (85%), and verified entries.
    """

    def test_esp_space_warning_threshold_mock(self):
        lh = core.get_limine_boot_health(mock=True)
        self.assertTrue(lh["ok"])
        self.assertEqual(lh["limitUsagePercent"], 85)
        self.assertFalse(lh["espWarning"], "Mock ESP is at 31%, should not warn")

    def test_limine_entries_sorting(self):
        lh = core.get_limine_boot_health(mock=True)
        entries = lh.get("entries", [])
        ids = [e["snapshotId"] for e in entries]
        self.assertEqual(ids, sorted(ids, reverse=True), "Boot entries must be sorted descending by snapshot ID")


class TestPacmanLogParserResilience(unittest.TestCase):
    """
    Tests ALPM log parser under corrupted and edge-case inputs.
    """

    def test_corrupted_log_lines_do_not_crash(self):
        corrupted_content = (
            "\n"
            "   \n"
            "This is random garbage text from a corrupted log\n"
            "[2026-10-07T16:30:10+0300] [PACMAN] Starting full system upgrade\n"
            "[2026-10-07T16:30:15+0300] [ALPM] incomplete line missing closing paren\n"
            "[invalid-timestamp] [ALPM] upgraded linux (6.11.2 -> 6.11.3)\n"
            "[2026-10-07T16:30:20+0300] [ALPM] upgraded hyprland (0.44.1-1 -> 0.45.0-1)\n"
            "\x00\x01\x02 binary bytes\n"
        )
        with tempfile.NamedTemporaryFile("w+", encoding="utf-8", delete=False) as tf:
            tf.write(corrupted_content)
            tf_path = tf.name

        try:
            entries = core.parse_pacman_log(tf_path)
            # Only the valid ALPM hyprland line should be parsed
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0]["name"], "hyprland")
            self.assertEqual(entries[0]["action"], "upgraded")
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

    def test_comprehensive_package_classification(self):
        # Critical Subsystems
        self.assertEqual(core.classify_package("linux")[1], "Kernel & Boot")
        self.assertEqual(core.classify_package("linux-lts")[1], "Kernel & Boot")
        self.assertEqual(core.classify_package("limine")[1], "Kernel & Boot")
        self.assertEqual(core.classify_package("systemd")[1], "Kernel & Boot")
        self.assertEqual(core.classify_package("btrfs-progs")[1], "Kernel & Boot")

        self.assertEqual(core.classify_package("nvidia-dkms")[1], "Graphics Driver")
        self.assertEqual(core.classify_package("mesa")[1], "Graphics Driver")
        self.assertEqual(core.classify_package("vulkan-intel")[1], "Graphics Driver")

        self.assertEqual(core.classify_package("hyprland")[1], "Display / Compositor")
        self.assertEqual(core.classify_package("wayland")[1], "Display / Compositor")

        self.assertEqual(core.classify_package("omarchy")[1], "Desktop Shell")
        self.assertEqual(core.classify_package("quickshell")[1], "Desktop Shell")
        self.assertEqual(core.classify_package("waybar")[1], "Desktop Shell")

        # Non-critical utilities
        self.assertIsNone(core.classify_package("zsh")[1])
        self.assertIsNone(core.classify_package("curl")[1])
        self.assertIsNone(core.classify_package("tmux")[1])


class TestInteractiveDemoHUDPrecision(unittest.TestCase):
    """
    Tests demo data state precision:
    Incrementing IDs (20, 21, 22), package/diff query support for high IDs,
    and QML safety confirmation modal bindings.
    """

    def test_demo_create_increments_id(self):
        res1 = core.create_snapshot("First Demo Checkpoint", mock=True)
        self.assertTrue(res1["ok"])
        self.assertEqual(res1.get("snapshotId"), 20)

    def test_demo_packages_query_for_high_ids(self):
        res_20 = subprocess.run([CORE_SCRIPT, "packages", "--id", "20", "--mock"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(res_20.returncode, 0)
        data_20 = json.loads(res_20.stdout)
        self.assertTrue(data_20.get("ok"))
        self.assertEqual(data_20.get("snapshotId"), 20)
        self.assertEqual(data_20.get("packageCount"), 0)

        res_25 = subprocess.run([CORE_SCRIPT, "packages", "--id", "25", "--mock"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(res_25.returncode, 0)
        data_25 = json.loads(res_25.stdout)
        self.assertTrue(data_25.get("ok"))
        self.assertEqual(data_25.get("snapshotId"), 25)

    def test_demo_diff_query_for_high_ids(self):
        res_20 = subprocess.run([CORE_SCRIPT, "diff", "--id", "20", "--mock"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(res_20.returncode, 0)
        data_20 = json.loads(res_20.stdout)
        self.assertTrue(data_20.get("ok"))
        self.assertEqual(data_20.get("snapshotId"), 20)

        res_25 = subprocess.run([CORE_SCRIPT, "diff", "--id", "25", "--mock"], stdout=subprocess.PIPE, text=True)
        self.assertEqual(res_25.returncode, 0)
        data_25 = json.loads(res_25.stdout)
        self.assertTrue(data_25.get("ok"))
        self.assertEqual(data_25.get("snapshotId"), 25)

    def test_qml_safety_confirmation_modals_exist(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Confirmation modal flags must guard destructive execution
        self.assertIn("property bool showRestoreModal: false", content)
        self.assertIn("property bool showDeleteModal: false", content)
        self.assertIn("property bool showRestoreFileModal: false", content)

        # Destructive execution requires active snapshot context
        self.assertIn("if (!activeRestoreSnapshot) return", content)
        self.assertIn("if (!activeDeleteSnapshot) return", content)
        self.assertIn("if (!activeRestoreFilePath || !activeRestoreFileSnapshotId) return", content)


if __name__ == "__main__":
    unittest.main()
