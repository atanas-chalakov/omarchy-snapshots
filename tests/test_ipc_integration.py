#!/usr/bin/env python3
"""
IPC and Hyprland integration tests for omarchy-snapshots.
Verifies live interaction with the running Omarchy shell, window creation,
summoning, toggling, and hiding.
"""

import unittest
import subprocess
import json
import time

class TestIpcIntegration(unittest.TestCase):

    def run_cmd(self, cmd_list):
        return subprocess.run(cmd_list, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def is_window_open(self):
        res = self.run_cmd(["hyprctl", "clients", "-j"])
        if res.returncode != 0:
            return False
        try:
            clients = json.loads(res.stdout)
            for c in clients:
                if c.get("title") == "Snapshots & Recovery":
                    return True
        except Exception:
            return False
        return False

    def test_shell_plugin_registered(self):
        res = self.run_cmd(["omarchy-shell", "shell", "listPlugins"])
        self.assertEqual(res.returncode, 0, "omarchy-shell must be reachable")
        self.assertIn("ac.snapshots", res.stdout, "ac.snapshots must be in discovered plugins list")

    def test_summon_and_hide_lifecycle(self):
        # 1. Summon with mock payload
        res_summon = self.run_cmd(["omarchy-shell", "shell", "summon", "ac.snapshots", '{"mock":true}'])
        self.assertEqual(res_summon.returncode, 0)
        self.assertEqual(res_summon.stdout.strip(), "ok")

        # Give compositor 0.6s to create window surface
        time.sleep(0.6)
        self.assertTrue(self.is_window_open(), "Window 'Snapshots & Recovery' must appear in Hyprland clients")

        # 2. Hide window
        res_hide = self.run_cmd(["omarchy-shell", "shell", "hide", "ac.snapshots"])
        self.assertEqual(res_hide.returncode, 0)

        # Give compositor 0.6s to tear down surface
        time.sleep(0.6)
        self.assertFalse(self.is_window_open(), "Window 'Snapshots & Recovery' must be hidden after hide command")

    def test_toggle_lifecycle(self):
        # Ensure hidden first
        self.run_cmd(["omarchy-shell", "-q", "shell", "hide", "ac.snapshots"])
        time.sleep(0.4)

        # Toggle ON
        res_toggle_on = self.run_cmd(["omarchy-shell", "shell", "toggle", "ac.snapshots", '{"mock":true}'])
        self.assertEqual(res_toggle_on.returncode, 0)
        time.sleep(0.6)
        self.assertTrue(self.is_window_open(), "Window must open after toggle ON")

        # Toggle OFF
        res_toggle_off = self.run_cmd(["omarchy-shell", "shell", "toggle", "ac.snapshots"])
        self.assertEqual(res_toggle_off.returncode, 0)
        time.sleep(0.6)
        self.assertFalse(self.is_window_open(), "Window must close after toggle OFF")

    @classmethod
    def tearDownClass(cls):
        # Always ensure HUD is hidden when tests conclude
        subprocess.run(["omarchy-shell", "-q", "shell", "hide", "ac.snapshots"])

if __name__ == "__main__":
    unittest.main()
