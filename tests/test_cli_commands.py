#!/usr/bin/env python3
"""
CLI and Subprocess test suite for omarchy-snapshots and omarchy-snapshots-core.
Tests CLI argument parsing, flags, formatting, exit codes, and error reporting.
"""

import unittest
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI_BIN = os.path.join(PROJECT_ROOT, "bin", "omarchy-snapshots")
CORE_BIN = os.path.join(PROJECT_ROOT, "bin", "omarchy-snapshots-core")

class TestCliCommands(unittest.TestCase):

    def run_cmd(self, binary, args):
        cmd = [binary] + args
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_cli_help(self):
        res = self.run_cmd(CLI_BIN, ["--help"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Omarchy Snapshots CLI", res.stdout)
        self.assertIn("list", res.stdout)
        self.assertIn("create", res.stdout)
        self.assertIn("restore", res.stdout)
        self.assertIn("delete", res.stdout)

    def test_core_help(self):
        res = self.run_cmd(CORE_BIN, ["--help"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Omarchy Snapshots Backend Core", res.stdout)

    def test_cli_list_mock_output(self):
        res = self.run_cmd(CLI_BIN, ["list", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("System Protected", res.stdout)
        self.assertIn("Limine Boot Sync: Active", res.stdout)
        self.assertIn("Subvolume:", res.stdout)
        self.assertIn("/ (root)", res.stdout)
        self.assertIn("Pre-Update (omarchy 4.0.2)", res.stdout)
        self.assertIn("[📌]", res.stdout)

    def test_cli_json_mock_valid(self):
        res = self.run_cmd(CLI_BIN, ["json", "--mock"])
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout)
        self.assertTrue(data.get("ok"))
        self.assertIn("health", data)
        self.assertIn("storage", data)

    def test_cli_diff_mock(self):
        res = self.run_cmd(CLI_BIN, ["diff", "--id", "19", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Diff for Snapshot #19", res.stdout)
        self.assertIn("Added: +3", res.stdout)
        self.assertIn("Modified: ~12", res.stdout)
        self.assertIn("Deleted: -1", res.stdout)

    def test_cli_create_mock(self):
        res = self.run_cmd(CLI_BIN, ["create", "--desc", "Test Checkpoint Alpha", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Test Checkpoint Alpha", res.stdout)

    def test_cli_create_mock_default_desc(self):
        res = self.run_cmd(CLI_BIN, ["create", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Manual checkpoint", res.stdout)

    def test_cli_create_important_mock(self):
        res = self.run_cmd(CLI_BIN, ["create", "--desc", "Pinned Checkpoint Beta", "--important", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("Pinned Checkpoint Beta", res.stdout)

    def test_cli_restore_mock(self):
        res = self.run_cmd(CLI_BIN, ["restore", "--id", "19", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("restore", res.stdout.lower())
        self.assertIn("19", res.stdout)

    def test_cli_pin_unpin_mock(self):
        res_pin = self.run_cmd(CLI_BIN, ["pin", "--id", "18", "--mock"])
        self.assertEqual(res_pin.returncode, 0)
        self.assertIn("pinned", res_pin.stdout.lower())

        res_unpin = self.run_cmd(CLI_BIN, ["unpin", "--id", "18", "--mock"])
        self.assertEqual(res_unpin.returncode, 0)
        self.assertIn("unpinned", res_unpin.stdout.lower())

    def test_cli_delete_mock(self):
        res = self.run_cmd(CLI_BIN, ["delete", "--id", "17", "--mock"])
        self.assertEqual(res.returncode, 0)
        self.assertIn("deleted", res.stdout.lower())

    # Error handling test cases
    def test_missing_id_diff(self):
        res = self.run_cmd(CLI_BIN, ["diff", "--mock"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_missing_id_restore(self):
        res = self.run_cmd(CLI_BIN, ["restore", "--mock"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_missing_id_delete(self):
        res = self.run_cmd(CLI_BIN, ["delete", "--mock"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_missing_id_pin(self):
        res = self.run_cmd(CLI_BIN, ["pin", "--mock"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_missing_id_unpin(self):
        res = self.run_cmd(CLI_BIN, ["unpin", "--mock"])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("--id is required", (res.stdout + res.stderr))

    def test_invalid_command(self):
        res = self.run_cmd(CLI_BIN, ["nonexistent_action"])
        self.assertNotEqual(res.returncode, 0)

if __name__ == "__main__":
    unittest.main()
