#!/usr/bin/env python3
"""
Unit test suite for omarchy-snapshots backend core.
Tests JSON schema compliance, status reporting, mock modes,
and snapshot action handlers.
"""

import unittest
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE_BIN = os.path.join(PROJECT_ROOT, "bin", "omarchy-snapshots-core")
CLI_BIN = os.path.join(PROJECT_ROOT, "bin", "omarchy-snapshots")

class TestSnapshotsCore(unittest.TestCase):

    def run_core(self, args):
        cmd = [CORE_BIN] + args
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0, f"Command failed: {res.stderr}")
        return json.loads(res.stdout)

    def test_mock_status_schema(self):
        data = self.run_core(["status", "--mock"])
        self.assertTrue(data.get("ok"))
        self.assertTrue(data.get("readable"))
        self.assertIn("health", data)
        self.assertIn("storage", data)
        self.assertIn("configs", data)

        health = data["health"]
        self.assertIn(health.get("status"), ["healthy", "warning", "error"])
        self.assertIn("label", health)
        self.assertIn("reason", health)
        self.assertIn("limineSyncActive", health)

        storage = data["storage"]
        self.assertGreater(storage.get("fsSize", 0), 0)
        self.assertIn("fsSizeHuman", storage)
        self.assertIn("fsAvailHuman", storage)

        configs = data["configs"]
        self.assertGreater(len(configs), 0)
        root_cfg = configs[0]
        self.assertEqual(root_cfg.get("name"), "root")
        snapshots = root_cfg.get("snapshots", [])
        self.assertGreater(len(snapshots), 0)

        s0 = snapshots[0]
        self.assertIn("id", s0)
        self.assertIn("relativeAge", s0)
        self.assertIn("description", s0)
        self.assertIn("cleanup", s0)

    def test_mock_diff(self):
        data = self.run_core(["diff", "--id", "19", "--mock"])
        self.assertTrue(data.get("ok"))
        self.assertEqual(data.get("snapshotId"), 19)
        self.assertIn("summary", data)
        self.assertIn("files", data)
        self.assertGreater(len(data["files"]), 0)

        first_file = data["files"][0]
        self.assertIn("path", first_file)
        self.assertIn(first_file.get("status"), ["added", "modified", "deleted"])

    def test_mock_create(self):
        data = self.run_core(["create", "--desc", "Test Checkpoint", "--mock"])
        self.assertTrue(data.get("ok"))
        self.assertIn("message", data)

    def test_mock_create_fallback_desc(self):
        data = self.run_core(["create", "--mock"])
        self.assertTrue(data.get("ok"))
        self.assertIn("Manual checkpoint", data.get("message", ""))
        self.assertEqual(data.get("snapshotId"), 20)

    def test_mock_restore(self):
        data = self.run_core(["restore", "--id", "19", "--mock"])
        self.assertTrue(data.get("ok"))
        self.assertEqual(data.get("snapshotId"), 19)
        self.assertIn("message", data)
        self.assertIn("19", data.get("message", ""))

    def test_restore_missing_id(self):
        cmd = [CORE_BIN, "restore", "--mock"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_mock_pin_unpin(self):
        pin_res = self.run_core(["pin", "--id", "18", "--mock"])
        self.assertTrue(pin_res.get("ok"))

        unpin_res = self.run_core(["unpin", "--id", "18", "--mock"])
        self.assertTrue(unpin_res.get("ok"))

    def test_mock_delete(self):
        del_res = self.run_core(["delete", "--id", "17", "--mock"])
        self.assertTrue(del_res.get("ok"))

    def test_mock_packages(self):
        pkg_res = self.run_core(["packages", "--id", "19", "--mock"])
        self.assertTrue(pkg_res.get("ok"))
        self.assertEqual(pkg_res.get("snapshotId"), 19)
        self.assertEqual(pkg_res.get("packageCount"), 6)
        self.assertTrue(pkg_res.get("hasCriticalPackages"))
        self.assertIn("linux", pkg_res.get("criticalPackages", []))
        self.assertEqual(len(pkg_res.get("packages", [])), 6)

    def test_mock_packages_missing_id(self):
        cmd = [CORE_BIN, "packages", "--mock"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_mock_restore_file(self):
        res = self.run_core(["restore-file", "--id", "19", "--path", "/etc/hypr/hyprland.conf", "--mock"])
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("snapshotId"), 19)
        self.assertEqual(res.get("filePath"), "/etc/hypr/hyprland.conf")
        self.assertIn(".bak.", res.get("backupPath", ""))

    def test_mock_restore_file_missing_id(self):
        cmd = [CORE_BIN, "restore-file", "--path", "/etc/hypr/hyprland.conf", "--mock"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_mock_restore_file_missing_path(self):
        cmd = [CORE_BIN, "restore-file", "--id", "19", "--mock"]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--path is required", (res.stdout + res.stderr))

    def test_mock_optimize_dry_run(self):
        res = self.run_core(["optimize", "--mock"])
        self.assertTrue(res.get("ok"))
        self.assertFalse(res.get("executed"))
        self.assertEqual(res.get("totalSnapshots"), 6)
        self.assertEqual(res.get("prunableCount"), 3)
        self.assertIn("reclaimableHuman", res)
        self.assertIn("retentionPolicy", res)

    def test_mock_optimize_execute(self):
        res = self.run_core(["optimize", "--execute", "--mock"])
        self.assertTrue(res.get("ok"))
        self.assertTrue(res.get("executed"))
        self.assertEqual(res.get("prunedCount"), 3)
        self.assertEqual(res.get("prunedIds"), [16, 15, 14])
        self.assertIn("freedHuman", res)

    def test_user_cli_list(self):
        res = subprocess.run([CLI_BIN, "list", "--mock"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("System Protected", res.stdout)
        self.assertIn("Pre-Update", res.stdout)

    def test_user_cli_diff(self):
        res = subprocess.run([CLI_BIN, "diff", "--id", "19", "--mock"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Diff for Snapshot #19", res.stdout)

    def test_manifest_validity(self):
        manifest_path = os.path.join(PROJECT_ROOT, "plugin.json")
        with open(manifest_path, "r") as f:
            manifest = json.load(f)
        self.assertEqual(manifest.get("id"), "ac.snapshots")
        self.assertEqual(manifest.get("category"), "System")
        self.assertIn("system", manifest.get("tags", []))
        self.assertIn("quickshell", manifest.get("tags", []))

if __name__ == "__main__":
    unittest.main()
