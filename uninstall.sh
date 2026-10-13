#!/usr/bin/env bash
# uninstall.sh — Remove Omarchy Snapshots HUD
set -euo pipefail

PLUGIN_ID="ac.snapshots"

echo "Uninstalling Omarchy Snapshots HUD ($PLUGIN_ID)..."

# 1. Disable in Omarchy shell
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
fi

# 2. Remove files
rm -f "$HOME/.local/bin/omarchy-snapshots"
rm -f "$HOME/.local/bin/omarchy-snapshots-core"
rm -f "$HOME/.local/share/applications/omarchy-snapshots.desktop"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/omarchy-snapshots.svg"
rm -f "$HOME/.local/share/icons/hicolor/48x48/apps/omarchy-snapshots.png"
rm -f "$HOME/.local/share/icons/hicolor/64x64/apps/omarchy-snapshots.png"
rm -f "$HOME/.local/share/icons/hicolor/128x128/apps/omarchy-snapshots.png"
rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/omarchy-snapshots.png"
rm -f "$HOME/.local/share/icons/hicolor/512x512/apps/omarchy-snapshots.png"
rm -f "$HOME/.config/omarchy/plugins/$PLUGIN_ID"

# 3. Clean up Omarchy Menu extension
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/scripts/manage_menu_extension.py" ]]; then
  python3 "$SCRIPT_DIR/scripts/manage_menu_extension.py" uninstall 2>/dev/null || true
fi

# 4. Remove local Pacman hook if installed and writable
if [[ -w /etc/pacman.d/hooks/00-omarchy-snapshots-pre.hook ]]; then
  rm -f /etc/pacman.d/hooks/00-omarchy-snapshots-pre.hook
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

echo "✓ Omarchy Snapshots HUD successfully removed."
