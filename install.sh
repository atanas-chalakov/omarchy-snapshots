#!/usr/bin/env bash
# install.sh — Setup and install Omarchy Snapshots HUD
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ac.snapshots"

echo "============================================================"
echo " Installing Omarchy Snapshots & Recovery HUD ($PLUGIN_ID)"
echo "============================================================"

# 1. Ensure required local directories exist
mkdir -p "$HOME/.config/omarchy/plugins"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$HOME/.local/share/icons/hicolor/48x48/apps"
mkdir -p "$HOME/.local/share/icons/hicolor/64x64/apps"
mkdir -p "$HOME/.local/share/icons/hicolor/128x128/apps"
mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"

# 2. Link plugin into Omarchy plugins directory
PLUGIN_TARGET="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
if [[ -L "$PLUGIN_TARGET" || -d "$PLUGIN_TARGET" ]]; then
  if [[ "$(readlink -f "$PLUGIN_TARGET" 2>/dev/null || true)" == "$SCRIPT_DIR" ]]; then
    echo "✓ Plugin symlink already points to $SCRIPT_DIR"
  else
    echo "Updating plugin symlink at $PLUGIN_TARGET..."
    rm -rf "$PLUGIN_TARGET"
    ln -s "$SCRIPT_DIR" "$PLUGIN_TARGET"
  fi
else
  echo "Linking plugin into $PLUGIN_TARGET..."
  ln -s "$SCRIPT_DIR" "$PLUGIN_TARGET"
fi

# 3. Install CLI launchers
echo "Installing CLI launchers to ~/.local/bin/..."
ln -sf "$SCRIPT_DIR/bin/omarchy-snapshots" "$HOME/.local/bin/omarchy-snapshots"
ln -sf "$SCRIPT_DIR/bin/omarchy-snapshots-core" "$HOME/.local/bin/omarchy-snapshots-core"
chmod +x "$SCRIPT_DIR/bin/omarchy-snapshots" "$SCRIPT_DIR/bin/omarchy-snapshots-core"

# 4. Install Desktop Application entry
echo "Installing desktop entry to ~/.local/share/applications/omarchy-snapshots.desktop..."
sed "s|Exec=omarchy-snapshots|Exec=$HOME/.local/bin/omarchy-snapshots|g" \
  "$SCRIPT_DIR/omarchy-snapshots.desktop" > "$HOME/.local/share/applications/omarchy-snapshots.desktop"

# 5. Install App Icons
if [[ -f "$SCRIPT_DIR/assets/icons/omarchy-snapshots.svg" ]]; then
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/omarchy-snapshots.svg"
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots-48.png" "$HOME/.local/share/icons/hicolor/48x48/apps/omarchy-snapshots.png" 2>/dev/null || true
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots-64.png" "$HOME/.local/share/icons/hicolor/64x64/apps/omarchy-snapshots.png" 2>/dev/null || true
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots-128.png" "$HOME/.local/share/icons/hicolor/128x128/apps/omarchy-snapshots.png" 2>/dev/null || true
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots-256.png" "$HOME/.local/share/icons/hicolor/256x256/apps/omarchy-snapshots.png" 2>/dev/null || true
  cp "$SCRIPT_DIR/assets/icons/omarchy-snapshots-512.png" "$HOME/.local/share/icons/hicolor/512x512/apps/omarchy-snapshots.png" 2>/dev/null || true
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  fi
fi

# Update desktop database if available
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# 6. Validate plugin manifest
if command -v omarchy >/dev/null 2>&1; then
  echo "Validating plugin manifest..."
  omarchy plugin validate "$SCRIPT_DIR" || echo "Note: Manifest validation warning"

  # 7. Enable in Omarchy shell
  echo "Enabling plugin in Omarchy shell..."
  omarchy plugin enable "$PLUGIN_ID" --section right 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo " ✓ Installation complete!"
echo "============================================================"
echo "You can now open the Snapshots HUD using:"
echo "  • Status Bar: Click the Snapshots companion icon (󰆼)"
echo "  • Terminal:   omarchy-snapshots (or omarchy-snapshots gui)"
echo "  • App Menu:   Search for 'Snapshots & Recovery' in Rofi / Walker"
echo ""
echo "To bind to a key in Hyprland (~/.config/hypr/bindings.conf):"
echo "  bind = \$mainMod, S, exec, omarchy-snapshots gui"
echo "============================================================"
