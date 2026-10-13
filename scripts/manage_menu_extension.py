#!/usr/bin/env python3
"""
manage_menu_extension.py: Helper script to install, update, and remove
Snapshots & Recovery entries in ~/.config/omarchy/extensions/omarchy-menu.jsonc.
"""

import sys
import os
import re
import json
import subprocess

DEFAULT_EXTENSION_PATH = os.path.expanduser("~/.config/omarchy/extensions/omarchy-menu.jsonc")

MENU_SNAPSHOTS_ENTRY = {
    "icon": "󰆼",
    "label": "Snapshots & Recovery",
    "description": "Btrfs & Snapper system recovery points, diffs, and boot health",
    "aliases": ["snapshots", "snapper", "backup", "restore"],
    "action": "omarchy-snapshots gui"
}

def strip_jsonc(raw_text):
    """Strips full-line comments and trailing commas per Omarchy MenuModel.js specification."""
    no_comments = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw_text, flags=re.MULTILINE)
    no_trailing_commas = re.sub(r",(\s*[}\]])", r"\1", no_comments)
    return no_trailing_commas

def read_menu_dict(filepath):
    if not os.path.exists(filepath):
        return {}
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    stripped = strip_jsonc(content).strip()
    if not stripped:
        return {}
    try:
        return json.loads(stripped)
    except Exception as e:
        print(f"Warning: Could not parse {filepath}: {e}", file=sys.stderr)
        return {}

def write_menu_dict(filepath, data):
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    header = "{\n  // Extend the Quickshell Omarchy menu with JSONC.\n"
    body_entries = []
    for k, v in data.items():
        formatted_entry = f'  "{k}": ' + json.dumps(v, ensure_ascii=False, indent=4).replace("\n", "\n  ")
        body_entries.append(formatted_entry)
    content = header + ",\n".join(body_entries) + "\n}\n"
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(content)

def reload_omarchy_menu():
    """Triggers hot-reload of Omarchy menu if shell is active."""
    try:
        subprocess.run(["omarchy", "menu", "refresh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        pass

def install_extension(filepath=DEFAULT_EXTENSION_PATH):
    data = read_menu_dict(filepath)
    data["system.snapshots"] = MENU_SNAPSHOTS_ENTRY
    if "setup.snapshots" in data:
        data["setup.snapshots"]["icon"] = "󰆼"
        data["setup.snapshots"]["action"] = "omarchy-snapshots gui"
    write_menu_dict(filepath, data)
    reload_omarchy_menu()
    print(f"✓ Installed Snapshots & Recovery into {filepath}")
    return 0

def uninstall_extension(filepath=DEFAULT_EXTENSION_PATH):
    if not os.path.exists(filepath):
        return 0
    data = read_menu_dict(filepath)
    changed = False
    if "system.snapshots" in data:
        del data["system.snapshots"]
        changed = True
    if "setup.snapshots" in data and ("omarchy-snapshots" in data["setup.snapshots"].get("action", "") or "ac.snapshots" in data["setup.snapshots"].get("action", "")):
        del data["setup.snapshots"]
        changed = True
    if changed:
        write_menu_dict(filepath, data)
        reload_omarchy_menu()
        print(f"✓ Removed Snapshots & Recovery from {filepath}")
    else:
        print(f"Snapshots & Recovery was not found in {filepath}")
    return 0

def status_extension(filepath=DEFAULT_EXTENSION_PATH):
    if not os.path.exists(filepath):
        print(f"Extension file not found at {filepath}")
        return 1
    data = read_menu_dict(filepath)
    has_sys = "system.snapshots" in data
    has_setup = "setup.snapshots" in data
    if has_sys or has_setup:
        print(f"Active in {filepath}:")
        if has_sys:
            print("  - system.snapshots ->", data["system.snapshots"].get("action"))
        if has_setup:
            print("  - setup.snapshots  ->", data["setup.snapshots"].get("action"))
        return 0
    else:
        print(f"Not active in {filepath}")
        return 1

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    target = DEFAULT_EXTENSION_PATH
    if "--target" in sys.argv:
        idx = sys.argv.index("--target")
        if idx + 1 < len(sys.argv):
            target = sys.argv[idx + 1]

    if action == "install":
        sys.exit(install_extension(target))
    elif action == "uninstall":
        sys.exit(uninstall_extension(target))
    elif action == "status":
        sys.exit(status_extension(target))
    elif action == "validate":
        d = read_menu_dict(target)
        if d:
            print("Valid JSONC with", len(d), "entries")
            sys.exit(0)
        else:
            print("Empty or invalid")
            sys.exit(1)
    else:
        print(f"Unknown action: {action}. Usage: manage_menu_extension.py [install|uninstall|status|validate] [--target PATH]")
        sys.exit(1)

if __name__ == "__main__":
    main()
