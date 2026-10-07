#!/usr/bin/env bash
# capture-gallery.sh — Automated screenshot capture of Omarchy Snapshots HUD
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/assets/screenshots"
PLUGIN_ID="ac.snapshots"

mkdir -p "$ASSETS_DIR"

if ! command -v grim >/dev/null 2>&1; then
  echo "Error: grim is required to capture screenshots." >&2
  exit 1
fi

get_geometry() {
  hyprctl clients -j | jq -r '.[] | select(.title=="Snapshots & Recovery") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -n1
}

capture_view() {
  local name="$1"
  local payload="$2"
  local target_file="$ASSETS_DIR/${name}.png"

  echo "Capturing view: $name..."
  omarchy-shell shell summon "$PLUGIN_ID" "$payload" >/dev/null 2>&1 || true
  sleep 0.8

  local geom
  geom=$(get_geometry)
  if [[ -n "$geom" && "$geom" != "null" ]]; then
    grim -g "$geom" "$target_file"
    echo "✓ Saved $target_file ($geom)"
  else
    echo "Warning: could not detect Snapshots & Recovery window geometry" >&2
  fi
}

echo "============================================================"
echo " Capturing Omarchy Snapshots Screenshot Gallery"
echo "============================================================"

capture_view "overview" '{"mock":true}'
capture_view "diff-inspector" '{"mock":true,"action":"diff","id":19}'
capture_view "create-modal" '{"mock":true,"action":"create","desc":"Before Kernel 6.11 Update"}'
capture_view "restore-modal" '{"mock":true,"action":"restore","id":19}'

# Copy primary overview to root preview.png for marketplace
if [[ -f "$ASSETS_DIR/overview.png" ]]; then
  cp "$ASSETS_DIR/overview.png" "$PROJECT_ROOT/preview.png"
  echo "✓ Copied overview.png to root preview.png"
fi

# Hide panel after capturing
omarchy-shell -q shell hide "$PLUGIN_ID" >/dev/null 2>&1 || true

echo "============================================================"
echo " Gallery capture complete! Saved to assets/screenshots/"
echo "============================================================"
