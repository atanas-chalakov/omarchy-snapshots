#!/usr/bin/env python3
"""
Static QML, manifest, and asset validation tests for omarchy-snapshots.
Verifies file integrity, schema compliance, brace matching, and official validator pass.
"""

import unittest
import os
import sys
import json
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class TestQmlAndManifest(unittest.TestCase):

    def test_manifest_schema(self):
        path = os.path.join(PROJECT_ROOT, "manifest.json")
        self.assertTrue(os.path.isfile(path), "manifest.json must exist")
        with open(path, "r", encoding="utf-8") as f:
            m = json.load(f)

        self.assertEqual(m.get("schemaVersion"), 1)
        self.assertEqual(m.get("id"), "ac.snapshots")
        self.assertEqual(m.get("name"), "Snapshots & Recovery")
        self.assertEqual(m.get("author"), "Atanas Chalakov")
        self.assertIn("panel", m.get("kinds", []))
        self.assertIn("bar-widget", m.get("kinds", []))

        eps = m.get("entryPoints", {})
        self.assertEqual(eps.get("panel"), "SnapshotsHUD.qml")
        self.assertEqual(eps.get("barWidget"), "BarWidget.qml")

        bw = m.get("barWidget", {})
        self.assertEqual(bw.get("displayName"), "Snapshots & Recovery")
        self.assertEqual(bw.get("category"), "System")
        self.assertEqual(bw.get("defaultSection"), "right")

    def test_plugin_json_schema(self):
        path = os.path.join(PROJECT_ROOT, "plugin.json")
        self.assertTrue(os.path.isfile(path), "plugin.json must exist")
        with open(path, "r", encoding="utf-8") as f:
            p = json.load(f)

        self.assertEqual(p.get("id"), "ac.snapshots")
        self.assertEqual(p.get("name"), "Snapshots & Recovery")
        self.assertEqual(p.get("category"), "System")
        self.assertIn("quickshell", p.get("tags", []))
        self.assertIn("snapper", p.get("tags", []))
        self.assertIn("btrfs", p.get("tags", []))

    def test_no_symlinks_in_repository(self):
        for root, dirs, files in os.walk(PROJECT_ROOT):
            if ".git" in root:
                continue
            for item in dirs + files:
                full_path = os.path.join(root, item)
                self.assertFalse(os.path.islink(full_path), f"Symlinks are disallowed by Omarchy validator: {full_path}")

    def test_official_omarchy_validator(self):
        res = subprocess.run(["omarchy", "plugin", "validate", PROJECT_ROOT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0, f"Validator failed: {res.stderr or res.stdout}")

    def test_qml_file_sync(self):
        root_hud = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        qml_hud = os.path.join(PROJECT_ROOT, "qml", "SnapshotsHUD.qml")
        with open(root_hud, "r", encoding="utf-8") as f1, open(qml_hud, "r", encoding="utf-8") as f2:
            self.assertEqual(f1.read(), f2.read(), "SnapshotsHUD.qml in root and qml/ must be identical")

        root_bar = os.path.join(PROJECT_ROOT, "BarWidget.qml")
        qml_bar = os.path.join(PROJECT_ROOT, "qml", "BarWidget.qml")
        with open(root_bar, "r", encoding="utf-8") as f1, open(qml_bar, "r", encoding="utf-8") as f2:
            self.assertEqual(f1.read(), f2.read(), "BarWidget.qml in root and qml/ must be identical")

    def test_qml_syntax_braces_and_tokens(self):
        qml_files = [
            os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml"),
            os.path.join(PROJECT_ROOT, "BarWidget.qml")
        ]

        for qf in qml_files:
            with open(qf, "r", encoding="utf-8") as f:
                content = f.read()

            # Check matching braces
            self.assertEqual(content.count("{"), content.count("}"), f"Mismatched curly braces in {qf}")
            self.assertEqual(content.count("["), content.count("]"), f"Mismatched square brackets in {qf}")
            self.assertEqual(content.count("("), content.count(")"), f"Mismatched parentheses in {qf}")

            # Check no deprecated tokens
            self.assertNotIn("pickAlpha", content, f"Deprecated pickAlpha found in {qf}")

    def test_bar_widget_components(self):
        bar_path = os.path.join(PROJECT_ROOT, "BarWidget.qml")
        with open(bar_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("WidgetButton", content)
        self.assertIn("moduleName: \"ac.snapshots\"", content)
        self.assertIn("omarchy-shell shell toggle ac.snapshots", content)

    def test_hud_components(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("FloatingWindow", content)
        self.assertIn("StdioCollector", content)
        self.assertIn("waitForEnd: true", content)
        self.assertIn("onStreamFinished", content)
        self.assertIn("Keys.onEscapePressed", content)
        self.assertIn("showDiffModal", content)
        self.assertIn("showCreateModal", content)
        self.assertIn("showRestoreModal", content)

    def test_preview_image_valid(self):
        preview_path = os.path.join(PROJECT_ROOT, "preview.png")
        self.assertTrue(os.path.isfile(preview_path), "preview.png must exist in root")
        size = os.path.getsize(preview_path)
        self.assertGreater(size, 50 * 1024, "preview.png should be at least 50KB high-res screenshot")

        # Verify PNG magic bytes
        with open(preview_path, "rb") as f:
            header = f.read(8)
        self.assertEqual(header, b"\x89PNG\r\n\x1a\n", "preview.png must have valid PNG magic bytes")

if __name__ == "__main__":
    unittest.main()
