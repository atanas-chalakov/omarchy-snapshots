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
        self.assertIn("tooltipText", content)

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
        self.assertIn("showDeleteModal", content)

    def test_package_correlator_ui(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Diff modal tabs
        self.assertIn("property string diffTab", content)
        self.assertIn("tabPkgsRow", content)
        self.assertIn("Package Updates", content)
        self.assertIn("File Changes", content)

        # Snapshot card package badges
        self.assertIn("pkgChipLayout", content)
        self.assertIn("hasCriticalPackages", content)
        self.assertIn("packageSummary", content)
        self.assertIn("criticalCategory", content)

    def test_restore_file_ui(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Restore file properties and functions
        self.assertIn("property bool showRestoreFileModal", content)
        self.assertIn("property string activeRestoreFilePath", content)
        self.assertIn("function confirmRestoreFile(", content)
        self.assertIn("function executeRestoreFile()", content)
        self.assertIn("restoreFileProcess", content)

        # Restore file button chip in file list
        self.assertIn("fileRestoreBtn", content)
        self.assertIn("confirmRestoreFile", content)

        # Restore file modal dialog
        self.assertIn("restoreFileModalCard", content)
        self.assertIn("Roll Back File from Snapshot", content)
        self.assertIn("Safety Guarantee: Automatic Backup", content)

    def test_optimizer_ui_components(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Optimizer properties and methods
        self.assertIn("property bool showOptimizeModal", content)
        self.assertIn("property var activeOptimizeData", content)
        self.assertIn("function openOptimizeModal()", content)
        self.assertIn("function executeOptimize()", content)
        self.assertIn("estimateOptimizeProcess", content)
        self.assertIn("executeOptimizeProcess", content)

        # Header button and shortcut
        self.assertIn("optimizeDiskBtn", content)
        self.assertIn("Qt.Key_O", content)
        self.assertIn("hintOptimizePill", content)

        # Optimizer modal dialog
        self.assertIn("optimizeModalCard", content)
        self.assertIn("Smart Btrfs Disk Optimizer", content)
        self.assertIn("Safe Retention Guard Active", content)

    def test_keyboard_navigation_support(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Selection state properties
        self.assertIn("property int selectedIndex", content)
        self.assertIn("readonly property var selectedSnapshot", content)
        self.assertIn("function selectNext()", content)
        self.assertIn("function selectPrev()", content)
        self.assertIn("function cycleFilter(", content)

        # Main key navigation bindings
        self.assertIn("Keys.onPressed", content)
        self.assertIn("Qt.Key_J", content)
        self.assertIn("Qt.Key_K", content)
        self.assertIn("Qt.Key_Down", content)
        self.assertIn("Qt.Key_Up", content)
        self.assertIn("Qt.Key_Home", content)
        self.assertIn("Qt.Key_End", content)

        # Snapshot actions shortcuts
        self.assertIn("Qt.Key_C", content)
        self.assertIn("Qt.Key_D", content)
        self.assertIn("Qt.Key_B", content)
        self.assertIn("Qt.Key_P", content)
        self.assertIn("Qt.Key_R", content)
        self.assertIn("Qt.Key_X", content)
        self.assertIn("Qt.Key_F", content)
        self.assertIn("Qt.Key_G", content)
        self.assertIn("Qt.Key_Escape", content)
        self.assertIn("Qt.Key_Q", content)

        # Search field and modal key handlers
        self.assertIn("createDescInput", content)
        self.assertIn("restoreModalCard", content)
        self.assertIn("deleteModalCard", content)
        self.assertIn("focus: root.showCreateModal", content)

        # Standard Omarchy key catcher & focus scope integration
        self.assertIn("PanelKeyCatcher", content)
        self.assertIn("FocusScope", content)
        self.assertIn("Keys.priority: Keys.BeforeItem", content)
        self.assertIn("Keys.forwardTo: [navKeyHandler]", content)
        self.assertIn("onMoveRequested", content)
        self.assertIn("onActivateRequested", content)
        self.assertIn("onCloseRequested", content)
        self.assertIn("onDeleteRequested", content)
        self.assertIn("onTextKey", content)
        self.assertIn("keyCatcher.forceActiveFocus()", content)

        # Window focus automation
        self.assertIn("windowFocusProcess", content)
        self.assertIn("hl.dsp.focus", content)

        # Visual shortcut key badges next to buttons & inputs
        self.assertIn("keyRefTxt", content)
        self.assertIn("keyNewTxt", content)
        self.assertIn("keyEscTxt", content)
        self.assertIn("chipKeyText", content)
        self.assertIn("searchKeyBadge", content)
        self.assertIn("diffKeyTxt", content)
        self.assertIn("browseKeyTxt", content)
        self.assertIn("pinKeyTxt", content)
        self.assertIn("resKeyTxt", content)
        self.assertIn("delKeyTxt", content)

        # Interactive footer hint bar pills
        self.assertIn("Keyboard Shortcuts Footer Hint Bar", content)
        self.assertIn("h1Mouse", content)
        self.assertIn("h2Mouse", content)
        self.assertIn("h3Mouse", content)
        self.assertIn("h6Mouse", content)
        self.assertIn("h10Mouse", content)

    def test_preview_image_valid(self):
        preview_path = os.path.join(PROJECT_ROOT, "preview.png")
        self.assertTrue(os.path.isfile(preview_path), "preview.png must exist in root")
        size = os.path.getsize(preview_path)
        self.assertGreater(size, 50 * 1024, "preview.png should be at least 50KB high-res screenshot")

        # Verify PNG magic bytes
        with open(preview_path, "rb") as f:
            header = f.read(8)
        self.assertEqual(header, b"\x89PNG\r\n\x1a\n", "preview.png must have valid PNG magic bytes")

    def test_installer_scripts(self):
        inst = os.path.join(PROJECT_ROOT, "install.sh")
        uninst = os.path.join(PROJECT_ROOT, "uninstall.sh")
        self.assertTrue(os.path.isfile(inst) and os.access(inst, os.X_OK), "install.sh must exist and be executable")
        self.assertTrue(os.path.isfile(uninst) and os.access(uninst, os.X_OK), "uninstall.sh must exist and be executable")

    def test_desktop_entry(self):
        desktop_path = os.path.join(PROJECT_ROOT, "omarchy-snapshots.desktop")
        self.assertTrue(os.path.isfile(desktop_path), "omarchy-snapshots.desktop must exist")
        with open(desktop_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("Type=Application", content)
        self.assertIn("Exec=omarchy-snapshots gui", content)
        self.assertIn("Actions=Create;Diff;Mock;", content)

    def test_arch_packaging(self):
        pkgbuild = os.path.join(PROJECT_ROOT, "packaging", "PKGBUILD")
        srcinfo = os.path.join(PROJECT_ROOT, "packaging", ".SRCINFO")
        install_hook = os.path.join(PROJECT_ROOT, "packaging", "omarchy-snapshots.install")
        self.assertTrue(os.path.isfile(pkgbuild), "packaging/PKGBUILD must exist")
        self.assertTrue(os.path.isfile(srcinfo), "packaging/.SRCINFO must exist")
        self.assertTrue(os.path.isfile(install_hook), "packaging/omarchy-snapshots.install must exist")
        with open(pkgbuild, "r", encoding="utf-8") as f:
            self.assertIn("pkgname=omarchy-snapshots", f.read())
        with open(srcinfo, "r", encoding="utf-8") as f:
            self.assertIn("pkgname = omarchy-snapshots", f.read())

    def test_demo_data_interactive_state(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("property var mockSnapshotsList: null", content)
        self.assertIn("onUseMockDataChanged", content)
        self.assertIn("mockSnapshotsList = [newSnap].concat(mockSnapshotsList)", content)
        self.assertIn("root.mockSnapshotsList.slice()", content)

    def test_destructive_actions_safety_guards(self):
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Full system restore safety guards
        self.assertIn("function confirmRestore(snapshot)", content)
        self.assertIn("function executeRestore()", content)
        self.assertIn("property bool showRestoreModal: false", content)
        self.assertIn("if (!activeRestoreSnapshot) return", content)

        # Snapshot delete safety guards
        self.assertIn("function confirmDelete(snapshot)", content)
        self.assertIn("function executeDelete()", content)
        self.assertIn("property bool showDeleteModal: false", content)
        self.assertIn("if (!activeDeleteSnapshot) return", content)

        # File restore safety guards
        self.assertIn("function confirmRestoreFile(", content)
        self.assertIn("function executeRestoreFile()", content)
        self.assertIn("property bool showRestoreFileModal: false", content)
        self.assertIn("if (!activeRestoreFilePath || !activeRestoreFileSnapshotId) return", content)

    def test_qml_text_format_security(self):
        """
        Verify that all dynamic Text elements declare explicit textFormat (Text.PlainText).
        Enforces the official Omarchy security standard to prevent unauthenticated outbound
        HTTP GET requests via RichText <img src="..."> promotion and markup parsing issues.
        """
        scan_script = "/home/ac/Work/omarchy/test/shell.d/qml-text-format-scan.py"
        if not os.path.isfile(scan_script):
            self.skipTest("Omarchy qml-text-format-scan.py not found")

        import tempfile
        with tempfile.TemporaryDirectory() as td:
            shell_dir = os.path.join(td, "shell")
            os.makedirs(shell_dir, exist_ok=True)
            for qf in ["SnapshotsHUD.qml", "BarWidget.qml"]:
                src = os.path.join(PROJECT_ROOT, qf)
                if os.path.isfile(src):
                    os.symlink(src, os.path.join(shell_dir, qf))

            res = subprocess.run([sys.executable, scan_script, td], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            violations = [line for line in res.stdout.splitlines() if line.strip()]
            self.assertEqual(len(violations), 0, f"Found QML Text elements without explicit textFormat:\n" + "\n".join(violations))

    def test_qmllint_layout_positioning(self):
        """
        Verify that qmllint reports 0 undefined layout positioning warnings
        (no anchors on items managed by ColumnLayout/RowLayout).
        """
        qmllint_bin = "/usr/lib/qt6/bin/qmllint"
        if not os.path.isfile(qmllint_bin) or not os.access(qmllint_bin, os.X_OK):
            self.skipTest("Qt6 qmllint binary not found")

        import tempfile
        with tempfile.TemporaryDirectory() as td:
            qs_dir = os.path.join(td, "qs")
            os.makedirs(qs_dir, exist_ok=True)
            os.symlink("/home/ac/Work/omarchy/shell/Ui", os.path.join(qs_dir, "Ui"))
            os.symlink("/home/ac/Work/omarchy/shell/Commons", os.path.join(qs_dir, "Commons"))

            hud_qml = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
            res = subprocess.run([qmllint_bin, "-I", td, hud_qml], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            layout_warnings = [l for l in res.stderr.splitlines() if "Quick.layout-positioning" in l]
            self.assertEqual(len(layout_warnings), 0, f"qmllint found layout positioning warnings:\n" + "\n".join(layout_warnings))

    def test_process_lifecycle_cleanup(self):
        """
        Verify that running subprocesses are terminated when dialogs are closed,
        the HUD is hidden, or the component is destroyed.
        """
        hud_path = os.path.join(PROJECT_ROOT, "SnapshotsHUD.qml")
        with open(hud_path, "r", encoding="utf-8") as f:
            content = f.read()

        self.assertIn("Component.onDestruction", content)
        self.assertIn("if (diffProcess.running) diffProcess.running = false", content)
        self.assertIn("if (estimateOptimizeProcess.running) estimateOptimizeProcess.running = false", content)
        self.assertIn("if (bootHealthProcess.running) bootHealthProcess.running = false", content)

    def test_omarchy_menu_extension_schema_and_merge(self):
        """
        Verify packaging/omarchy-menu-extension.jsonc and manage_menu_extension.py
        conform to the official Omarchy Menu specification and handle JSONC merging.
        """
        import tempfile
        ext_path = os.path.join(PROJECT_ROOT, "packaging", "omarchy-menu-extension.jsonc")
        self.assertTrue(os.path.isfile(ext_path), "packaging/omarchy-menu-extension.jsonc must exist")

        with open(ext_path, "r", encoding="utf-8") as f:
            raw = f.read()

        # Parse with Omarchy stripJsonc rules
        stripped = re_strip = subprocess.check_output([
            sys.executable, "-c",
            "import sys, os; sys.path.insert(0, os.path.join('" + PROJECT_ROOT + "', 'scripts')); "
            "from manage_menu_extension import strip_jsonc; import json; "
            "d = json.loads(strip_jsonc(open('" + ext_path + "').read())); "
            "print(json.dumps(d))"
        ]).decode("utf-8")
        data = json.loads(stripped)

        self.assertIn("system.snapshots", data)
        entry = data["system.snapshots"]
        self.assertEqual(entry.get("icon"), "󰆼")
        self.assertEqual(entry.get("label"), "Snapshots & Recovery")
        self.assertEqual(entry.get("action"), "omarchy-snapshots gui")
        self.assertIn("snapshots", entry.get("aliases", []))
        self.assertIn("snapper", entry.get("aliases", []))

        # Test manage_menu_extension.py install & uninstall on isolated temp file
        manage_script = os.path.join(PROJECT_ROOT, "scripts", "manage_menu_extension.py")
        with tempfile.NamedTemporaryFile("w+", suffix=".jsonc") as tf:
            tf.write("{\n  // User config\n  \"setup.test\": {\"label\": \"TestApp\"}\n}\n")
            tf.flush()

            # Install
            res = subprocess.run([sys.executable, manage_script, "install", "--target", tf.name], capture_output=True, text=True)
            self.assertEqual(res.returncode, 0)

            # Validate installed content
            res_val = subprocess.run([sys.executable, manage_script, "validate", "--target", tf.name], capture_output=True, text=True)
            self.assertEqual(res_val.returncode, 0)

            with open(tf.name, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn('"system.snapshots"', content)
            self.assertIn('"setup.test"', content)

            # Uninstall
            res_un = subprocess.run([sys.executable, manage_script, "uninstall", "--target", tf.name], capture_output=True, text=True)
            self.assertEqual(res_un.returncode, 0)
            with open(tf.name, "r", encoding="utf-8") as f:
                content_after = f.read()
            self.assertNotIn('"system.snapshots"', content_after)
            self.assertIn('"setup.test"', content_after)

    def test_alpm_pacman_hook_specification(self):
        """
        Verify packaging/00-omarchy-snapshots-pre.hook adheres to ALPM-HOOKS(5).
        """
        hook_path = os.path.join(PROJECT_ROOT, "packaging", "00-omarchy-snapshots-pre.hook")
        self.assertTrue(os.path.isfile(hook_path), "00-omarchy-snapshots-pre.hook must exist")

        with open(hook_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip() and not l.startswith("#")]

        self.assertIn("[Trigger]", lines)
        self.assertIn("Operation = Upgrade", lines)
        self.assertIn("Operation = Install", lines)
        self.assertIn("Operation = Remove", lines)
        self.assertIn("Type = Package", lines)
        self.assertIn("Target = *", lines)

        self.assertIn("[Action]", lines)
        self.assertIn("When = PreTransaction", lines)
        self.assertIn("Exec = /usr/share/libalpm/scripts/omarchy-snapshots-pre-hook", lines)
        self.assertIn("NeedsTargets", lines)
        self.assertIn("AbortOnFail", lines)

    def test_omarchy_snapshots_pre_hook_script(self):
        """
        Verify scripts/omarchy-snapshots-pre-hook is valid executable bash,
        safely handles Omarchy update bypass, explicit bypass, and stdin targets.
        """
        script_path = os.path.join(PROJECT_ROOT, "scripts", "omarchy-snapshots-pre-hook")
        self.assertTrue(os.path.isfile(script_path), "scripts/omarchy-snapshots-pre-hook must exist")
        self.assertTrue(os.access(script_path, os.X_OK), "scripts/omarchy-snapshots-pre-hook must be executable")

        # 1. Test OMARCHY_UPDATE_PACMAN bypass
        env_update = os.environ.copy()
        env_update["OMARCHY_UPDATE_PACMAN"] = "1"
        res = subprocess.run([script_path], env=env_update, input="", text=True, capture_output=True)
        self.assertEqual(res.returncode, 0, "Must exit 0 when OMARCHY_UPDATE_PACMAN is set")

        # 2. Test OMARCHY_SNAPSHOT_DISABLE bypass
        env_disable = os.environ.copy()
        env_disable["OMARCHY_SNAPSHOT_DISABLE"] = "1"
        res = subprocess.run([script_path], env=env_disable, input="", text=True, capture_output=True)
        self.assertEqual(res.returncode, 0, "Must exit 0 when OMARCHY_SNAPSHOT_DISABLE is set")

        # 3. Test installer & uninstaller scripts exist and are executable
        install_script = os.path.join(PROJECT_ROOT, "scripts", "install-pacman-hook.sh")
        uninstall_script = os.path.join(PROJECT_ROOT, "scripts", "uninstall-pacman-hook.sh")
        self.assertTrue(os.path.isfile(install_script), "install-pacman-hook.sh must exist")
        self.assertTrue(os.path.isfile(uninstall_script), "uninstall-pacman-hook.sh must exist")
        self.assertTrue(os.access(install_script, os.X_OK))
        self.assertTrue(os.access(uninstall_script, os.X_OK))

    def test_cli_hook_and_menu_commands(self):
        """
        Verify omarchy-snapshots CLI supports 'hook' and 'menu' commands without error.
        """
        cli_bin = os.path.join(PROJECT_ROOT, "bin", "omarchy-snapshots")
        # Run menu status
        res_menu = subprocess.run([cli_bin, "menu"], capture_output=True, text=True)
        self.assertEqual(res_menu.returncode, 0)
        self.assertIn("Active in", res_menu.stdout)

        # Run hook command (exits 0 if active, 1 with instruction if inactive)
        res_hook = subprocess.run([cli_bin, "hook"], capture_output=True, text=True)
        self.assertIn(res_hook.returncode, [0, 1])
        output = res_hook.stdout + res_hook.stderr
        self.assertTrue("Pacman Pre-Transaction" in output or "install-pacman-hook" in output)

if __name__ == "__main__":
    unittest.main()
